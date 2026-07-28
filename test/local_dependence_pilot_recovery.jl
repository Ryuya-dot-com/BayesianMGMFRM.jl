using JSON3
using SHA
using Test

const RECOVERY_REPOSITORY_ROOT = normpath(joinpath(@__DIR__, ".."))
include(joinpath(RECOVERY_REPOSITORY_ROOT, "scripts",
    "local_dependence_pilot_recovery.jl"))
using .LocalDependencePilotRecovery
const Recovery = LocalDependencePilotRecovery
const RecoveryArchive = Recovery.LocalDependencePilotAttemptArchive

recovery_hex(character) = repeat(String(character), 64)

function recovery_plan()
    return (;
        plan_id = recovery_hex("1"),
        protocol_plan_id = recovery_hex("2"),
        protocol_file_sha256 = recovery_hex("3"),
        protocol_content_hash = recovery_hex("4"),
        ordered_job_rows_sha256 = recovery_hex("5"),
        pilot_contract_sha256 = recovery_hex("6"),
    )
end

function recovery_execution_context_tests()
    @testset "local-dependence recovery execution-context binding" begin
        pilot_context = Recovery.LD1B_PILOT_EXECUTION_CONTEXT
        smoke_context = Recovery.LD1B_BOUNDED_SMOKE_EXECUTION_CONTEXT
    @test Recovery.ld1b_execution_context(:pilot) == (;
        execution_scope = :pilot,
        root_namespace = :local_dependence_pilot,
        official_pilot_denominator_eligible = true,
    )
    @test Recovery.ld1b_execution_context(:bounded_smoke) == (;
        execution_scope = :bounded_smoke,
        root_namespace = :local_dependence_pilot_bounded_smoke_v1,
        official_pilot_denominator_eligible = false,
    )
    @test_throws Exception Recovery.ld1b_execution_context(:unknown)
    @test all(endswith(schema, ".v2") for schema in (
        Recovery.LD1B_ATTEMPT_OWNER_SCHEMA,
        Recovery.LD1B_ATTEMPT_RESERVATION_SCHEMA,
        Recovery.LD1B_CANONICAL_ATTEMPT_OWNER_SCHEMA,
        Recovery.LD1B_CHILD_LAUNCH_SCHEMA,
        Recovery.LD1B_CHILD_EXIT_SCHEMA,
        Recovery.LD1B_INTERRUPTION_REVIEW_SCHEMA,
        Recovery.LD1B_PRECOMMIT_INTERRUPTION_REVIEW_SCHEMA,
    ))

    owner_args = (;
        plan_identity = recovery_plan(),
        execution_source_identity = recovery_execution(),
        job_identity = recovery_job(),
        attempt_number = 1,
        attempt_role = :primary,
        controller_host = "host",
        controller_run_id = "run",
        controller_pid = 9001,
        recorded_at_utc = "2026-07-28T00:00:00Z",
    )
    pilot_owner = Recovery.ld1b_attempt_owner_precommit(; owner_args...)
    @test pilot_owner.execution_context == pilot_context
    @test pilot_owner.execution_context_sha256 ==
        RecoveryArchive.ld1b_archive_canonical_sha256(pilot_context)
    @test pilot_owner.attempt.role === :primary
    @test pilot_owner.attempt.counts_toward_primary

    invalid_smoke_context = (;
        execution_scope = :bounded_smoke,
        root_namespace = :local_dependence_pilot_bounded_smoke,
        official_pilot_denominator_eligible = false,
    )
    @test_throws Exception Recovery.ld1b_attempt_owner_precommit(;
        merge(owner_args, (;
            attempt_role = :verification,
            execution_context = invalid_smoke_context,
        ))...)
    @test_throws Exception Recovery.ld1b_attempt_owner_precommit(;
        merge(owner_args, (;
            attempt_role = :primary,
            execution_context = smoke_context,
        ))...)
    @test_throws Exception Recovery.ld1b_attempt_owner_precommit(;
        merge(owner_args, (;
            attempt_number = 2,
            attempt_role = :verification,
            execution_context = smoke_context,
        ))...)
    @test_throws Exception Recovery.ld1b_attempt_owner_precommit(;
        merge(owner_args, (;
            attempt_number = 2,
            attempt_role = :remediation,
            execution_context = smoke_context,
        ))...)
    @test_throws Exception Recovery.ld1b_attempt_owner_precommit(;
        merge(owner_args, (; attempt_role = :verification))...)

        @testset "bounded-smoke reservation through launched review" begin
        mktempdir() do root
            fixture = recovery_smoke_fixture(root)
            @test_throws Exception Recovery.
                ld1b_validate_attempt_reservation_file(
                    fixture.reservation_path; execution_root = root,
                    plan_identity = fixture.identity.plan_identity,
                    execution_source_identity =
                        fixture.identity.execution_source_identity,
                    job_identity = fixture.identity.job_identity,
                    attempt_number = 1,
                    attempt_role = :verification,
                    expected_reservation_id = fixture.reservation_id,
                    expected_execution_root_relative_attempt_path =
                        fixture.attempt_relative,
                )
            reservation = Recovery.ld1b_validate_attempt_reservation_file(
                fixture.reservation_path; execution_root = root,
                fixture.identity...,
                expected_reservation_id = fixture.reservation_id,
                expected_execution_root_relative_attempt_path =
                    fixture.attempt_relative,
            )
            owner = Recovery.ld1b_validate_canonical_attempt_owner_file(
                fixture.attempt_dir;
                reservation_path = fixture.reservation_path,
                execution_root = root, fixture.identity...,
                expected_reservation_id = fixture.reservation_id,
            )
            launch = Recovery.ld1b_validate_child_launch_file(
                fixture.attempt_dir;
                reservation_path = fixture.reservation_path,
                execution_root = root, fixture.identity...,
                expected_reservation_id = fixture.reservation_id,
            )
            exit = Recovery.ld1b_validate_child_exit_file(
                fixture.attempt_dir;
                reservation_path = fixture.reservation_path,
                execution_root = root, fixture.identity...,
                expected_reservation_id = fixture.reservation_id,
            )
            review = Recovery.ld1b_publish_interruption_review(
                fixture.attempt_dir; fixture.identity...,
                mode = :validated_exit_receipt,
                retirement_reason_code = :interrupted_without_result,
                result_semantic_assessment = :result_absent,
                review_host = "smoke-review-host",
                reviewer = "smoke-reviewer",
                reviewed_at_utc = "2026-07-28T00:05:00Z",
                controller_confirmed_stopped = true,
                child_confirmed_stopped = true,
                staging_dir = joinpath(root, ".review-staging"),
                boundary = root,
                reservation_path = fixture.reservation_path,
                execution_root = root,
                expected_reservation_id = fixture.reservation_id,
            )
            @test review.published
            validated_review = Recovery.ld1b_validate_interruption_review_file(
                fixture.attempt_dir; fixture.identity...,
                reservation_path = fixture.reservation_path,
                execution_root = root,
                expected_reservation_id = fixture.reservation_id,
            )
            @test validated_review.valid

            context_sha = RecoveryArchive.ld1b_archive_canonical_sha256(
                smoke_context)
            for artifact in (
                    reservation.artifact,
                    owner.artifact,
                    launch.artifact,
                    exit.artifact,
                    validated_review.artifact,
                )
                native = Recovery._native(artifact)
                @test native["execution_context"] ==
                    Recovery._native(smoke_context)
                @test native["execution_context_sha256"] == context_sha
                @test native["attempt"]["number"] == 1
                @test native["attempt"]["role"] == "verification"
                @test !native["attempt"]["counts_toward_primary"]
            end

            tampered_context = Recovery._native(merge(smoke_context, (;
                official_pilot_denominator_eligible = true,
            )))
            tampered_reservation = recovery_rehash(
                fixture.reservation.artifact;
                execution_context = tampered_context,
                execution_context_sha256 =
                    RecoveryArchive.ld1b_archive_canonical_sha256(
                        tampered_context),
            )
            @test_throws Exception Recovery.ld1b_validate_attempt_reservation(
                tampered_reservation; fixture.identity...,
                expected_reservation_id = fixture.reservation_id,
                expected_execution_root_relative_reservation_path =
                    fixture.reservation_relative,
                expected_execution_root_relative_attempt_path =
                    fixture.attempt_relative,
            )
        end
    end

        @testset "bounded-smoke precommit review remains science-zero" begin
        mktempdir() do root
            fixture = recovery_smoke_fixture(root; publish_owner = false)
            published = Recovery.ld1b_publish_precommit_interruption_review(
                fixture.attempt_dir;
                reservation_path = fixture.reservation_path,
                execution_root = root, fixture.identity...,
                expected_reservation_id = fixture.reservation_id,
                reason_code = :interrupted_after_reservation_before_owner,
                review_host = "smoke-review-host",
                reviewer = "smoke-reviewer",
                reviewed_at_utc = "2026-07-28T00:05:00Z",
                controller_confirmed_stopped = true,
                child_launch_receipt_confirmed_absent = true,
                child_process_confirmed_stopped = true,
                staging_dir = joinpath(root, ".review-staging"),
            )
            @test published.published
            @test published.scientific_contribution == 0
            validated = Recovery.
                ld1b_validate_precommit_interruption_review_file(
                    fixture.attempt_dir;
                    reservation_path = fixture.reservation_path,
                    execution_root = root, fixture.identity...,
                    expected_reservation_id = fixture.reservation_id,
                )
            native = Recovery._native(validated.artifact)
            @test native["execution_context"] ==
                Recovery._native(smoke_context)
            @test native["attempt"]["role"] == "verification"
            @test !native["attempt"]["counts_toward_primary"]
            @test native["attempt_state"]["scientific_contribution"] == 0
        end
        end
    end
end

function recovery_execution()
    return (;
        batch_runner_source_sha256 = recovery_hex("a"),
        local_json_source_sha256 = bytes2hex(open(sha256,
            joinpath(RECOVERY_REPOSITORY_ROOT, "scripts", "local_json.jl"))),
        job_runner_source_sha256 = recovery_hex("b"),
        attempt_archive_source_sha256 =
            RecoveryArchive.ld1b_attempt_archive_source_sha256(),
        local_dependence_pilot_recovery_source_sha256 =
            Recovery.ld1b_recovery_source_sha256(),
        local_dependence_pilot_calibration_semantics_source_sha256 =
            recovery_hex("c"),
    )
end

function recovery_job()
    return (;
        job_id = "ld1b1_pilot__rep01__s05__null_support_at_minimum",
        row_index = 5,
        scenario_index = 5,
        scenario_id = :null_support_at_minimum,
        replication = 1,
        expected_action = :fit_and_score_diagnostic,
        seed = 410_005,
        fit_seed = 510_005,
        draw_selection_seed = 610_005,
        posterior_predictive_seed = 710_005,
    )
end

function recovery_write_json(path, value)
    mkpath(dirname(path))
    open(path, "w") do io
        RecoveryArchive.write_json(io, value)
        println(io)
    end
    return path
end

function recovery_file_sha(path)
    return bytes2hex(open(sha256, path))
end

function recovery_fixture(root; attempt_number = 1,
        attempt_role = :primary, with_exit = true)
    attempt_dir = joinpath(root, "attempt_$(lpad(attempt_number, 3, '0'))")
    mkpath(attempt_dir)
    plan = recovery_plan()
    execution = recovery_execution()
    job = recovery_job()
    identity = (; plan_identity = plan,
        execution_source_identity = execution, job_identity = job,
        attempt_number, attempt_role)
    owner = Recovery.ld1b_attempt_owner_precommit(; identity...,
        controller_host = "test-host", controller_run_id = "run-001",
        controller_pid = 1201, recorded_at_utc = "2026-07-27T00:00:00Z")
    owner_path = recovery_write_json(joinpath(attempt_dir,
        Recovery.LD1B_ATTEMPT_OWNER_FILENAME), owner)
    owner_sha = recovery_file_sha(owner_path)
    launch = Recovery.ld1b_child_launch_receipt(; identity...,
        owner_artifact = owner, owner_receipt_sha256 = owner_sha,
        child_pid = 1202, recorded_at_utc = "2026-07-27T00:00:01Z")
    launch_path = recovery_write_json(joinpath(attempt_dir,
        Recovery.LD1B_CHILD_LAUNCH_FILENAME), launch)
    launch_sha = recovery_file_sha(launch_path)
    exit = nothing
    exit_path = nothing
    exit_sha = nothing
    if with_exit
        exit = Recovery.ld1b_child_exit_receipt(; identity...,
            owner_artifact = owner, owner_receipt_sha256 = owner_sha,
            launch_artifact = launch, launch_receipt_sha256 = launch_sha,
            exit_code = 137,
            recorded_at_utc = "2026-07-27T00:00:02Z")
        exit_path = recovery_write_json(joinpath(attempt_dir,
            Recovery.LD1B_CHILD_EXIT_FILENAME), exit)
        exit_sha = recovery_file_sha(exit_path)
    end
    return (; root, attempt_dir, identity, owner, owner_path, owner_sha,
        launch, launch_path, launch_sha, exit, exit_path, exit_sha)
end

function recovery_rehash(value; replacements...)
    native = Recovery._native(value)
    delete!(native, "content_hash")
    for (key, replacement) in pairs((; replacements...))
        native[String(key)] = replacement
    end
    return RecoveryArchive.ld1b_archive_with_content_hash(native)
end

function recovery_smoke_fixture(root; publish_owner::Bool = true,
        with_exit::Bool = publish_owner)
    with_exit && !publish_owner && error("an exit receipt requires an owner")
    job = recovery_job()
    execution_context = Recovery.LD1B_BOUNDED_SMOKE_EXECUTION_CONTEXT
    identity = (;
        plan_identity = recovery_plan(),
        execution_source_identity = recovery_execution(),
        job_identity = job,
        attempt_number = 1,
        attempt_role = :verification,
        execution_context,
    )
    attempt_relative = joinpath("jobs", job.job_id, "attempt_001")
    attempt_dir = joinpath(root, attempt_relative)
    reservation_relative = joinpath(
        "attempt_reservations", job.job_id, "attempt_001",
        Recovery.LD1B_ATTEMPT_RESERVATION_FILENAME,
    )
    reservation_path = joinpath(root, reservation_relative)
    reservation_id = "bounded-smoke-reservation-001"
    mkpath(dirname(reservation_path))
    reservation = Recovery.ld1b_publish_attempt_reservation(
        reservation_path; execution_root = root, identity..., reservation_id,
        execution_root_relative_attempt_path = attempt_relative,
        controller_host = "smoke-controller-host",
        controller_run_id = "smoke-controller-run-001",
        controller_pid = 9101,
        recorded_at_utc = "2026-07-28T00:00:00Z",
        staging_dir = joinpath(root, ".reservation-staging"),
    )
    mkpath(dirname(attempt_dir))
    mkdir(attempt_dir)
    if !publish_owner
        return (; root, identity, attempt_relative, attempt_dir,
            reservation_relative, reservation_path, reservation_id,
            reservation, owner = nothing, launch = nothing,
            launch_path = nothing, launch_sha = nothing,
            exit = nothing, exit_path = nothing, exit_sha = nothing)
    end

    owner = Recovery.ld1b_publish_canonical_attempt_owner(
        attempt_dir; reservation_path, execution_root = root, identity...,
        expected_reservation_id = reservation_id,
        recorded_at_utc = "2026-07-28T00:00:01Z",
        staging_dir = joinpath(root, ".receipt-staging"),
    )
    lineage = (;
        reservation_artifact = reservation.artifact,
        reservation_receipt_sha256 = reservation.file_sha256,
        expected_reservation_id = reservation_id,
        expected_execution_root_relative_reservation_path =
            reservation_relative,
        expected_execution_root_relative_attempt_path = attempt_relative,
    )
    launch = Recovery.ld1b_child_launch_receipt(;
        identity..., owner_artifact = owner.artifact,
        owner_receipt_sha256 = owner.owner_file_sha256,
        child_pid = 9102,
        recorded_at_utc = "2026-07-28T00:00:02Z",
        lineage...,
    )
    launch_path = recovery_write_json(joinpath(
        attempt_dir, Recovery.LD1B_CHILD_LAUNCH_FILENAME), launch)
    launch_sha = recovery_file_sha(launch_path)
    exit = nothing
    exit_path = nothing
    exit_sha = nothing
    if with_exit
        exit = Recovery.ld1b_child_exit_receipt(;
            identity..., owner_artifact = owner.artifact,
            owner_receipt_sha256 = owner.owner_file_sha256,
            launch_artifact = launch, launch_receipt_sha256 = launch_sha,
            exit_code = 0,
            recorded_at_utc = "2026-07-28T00:00:03Z",
            lineage...,
        )
        exit_path = recovery_write_json(joinpath(
            attempt_dir, Recovery.LD1B_CHILD_EXIT_FILENAME), exit)
        exit_sha = recovery_file_sha(exit_path)
    end
    return (; root, identity, attempt_relative, attempt_dir,
        reservation_relative, reservation_path, reservation_id,
        reservation, owner, launch, launch_path, launch_sha,
        exit, exit_path, exit_sha)
end

@testset "local-dependence pilot stopped-process recovery artifacts" begin
    @testset "validated exit-receipt lineage and snapshots" begin
        mktempdir() do root
            fixture = recovery_fixture(root)
            inventory = Recovery.ld1b_inventory_before_interruption_review(
                fixture.attempt_dir)
            @test Set(row.path for row in inventory.rows if row.kind === :file) ==
                Set((Recovery.LD1B_ATTEMPT_OWNER_FILENAME,
                    Recovery.LD1B_CHILD_LAUNCH_FILENAME,
                    Recovery.LD1B_CHILD_EXIT_FILENAME))
            review = Recovery.ld1b_stopped_process_interruption_review(;
                fixture.identity...,
                owner_artifact = fixture.owner,
                owner_receipt_sha256 = fixture.owner_sha,
                launch_artifact = fixture.launch,
                launch_receipt_sha256 = fixture.launch_sha,
                exit_artifact = fixture.exit,
                exit_receipt_sha256 = fixture.exit_sha,
                inventory_before_review = inventory,
                mode = :validated_exit_receipt,
                retirement_reason_code = :interrupted_without_result,
                observed_attempt_state = (;
                    result_present = false,
                    result_file_sha256 = nothing,
                    result_semantic_assessment = :result_absent,
                ),
                review_host = "review-host", reviewer = "reviewer-01",
                reviewed_at_utc = "2026-07-27T00:05:00Z",
                controller_confirmed_stopped = true,
                child_confirmed_stopped = true)
            @test review.schema == Recovery.LD1B_INTERRUPTION_REVIEW_SCHEMA
            @test RecoveryArchive.ld1b_verify_archive_content_hash(review) ==
                review.content_hash.value
            recovery_write_json(joinpath(fixture.attempt_dir,
                Recovery.LD1B_INTERRUPTION_REVIEW_FILENAME), review)
            validated = Recovery.ld1b_validate_interruption_review_file(
                fixture.attempt_dir; fixture.identity...)
            @test validated.valid
            @test validated.mode === :validated_exit_receipt
            @test validated.file_sha256 == recovery_file_sha(joinpath(
                fixture.attempt_dir,
                Recovery.LD1B_INTERRUPTION_REVIEW_FILENAME))
            @test validated.canonical_sha256 == review.content_hash.value
            @test Recovery.ld1b_validate_attempt_owner_file(
                fixture.attempt_dir; fixture.identity...).state ===
                :owner_precommitted
            @test Recovery.ld1b_validate_child_launch_file(
                fixture.attempt_dir; fixture.identity...).state ===
                :child_launched
            @test Recovery.ld1b_validate_child_exit_file(
                fixture.attempt_dir; fixture.identity...).state ===
                :child_exit_observed
        end
    end

    @testset "external process-identity review is distinct" begin
        mktempdir() do root
            fixture = recovery_fixture(root; attempt_number = 2,
                attempt_role = :remediation, with_exit = false)
            inventory = Recovery.ld1b_inventory_before_interruption_review(
                fixture.attempt_dir)
            external = (;
                evidence_source = "independent process-table review",
                controller_process_identity = "controller start-token absent",
                child_process_identity = "child start-token absent",
                observed_at_utc = "2026-07-27T00:04:00Z",
            )
            review = Recovery.ld1b_stopped_process_interruption_review(;
                fixture.identity...,
                owner_artifact = fixture.owner,
                owner_receipt_sha256 = fixture.owner_sha,
                launch_artifact = fixture.launch,
                launch_receipt_sha256 = fixture.launch_sha,
                inventory_before_review = inventory,
                mode = :external_process_identity_review,
                retirement_reason_code = :interrupted_without_result,
                observed_attempt_state = (;
                    result_present = false,
                    result_file_sha256 = nothing,
                    result_semantic_assessment = :result_absent,
                ),
                review_host = "review-host", reviewer = "reviewer-02",
                reviewed_at_utc = "2026-07-27T00:05:00Z",
                controller_confirmed_stopped = true,
                child_confirmed_stopped = true,
                external_process_identity_review = external)
            recovery_write_json(joinpath(fixture.attempt_dir,
                Recovery.LD1B_INTERRUPTION_REVIEW_FILENAME), review)
            validated = Recovery.ld1b_validate_interruption_review_file(
                fixture.attempt_dir; fixture.identity...)
            @test validated.mode === :external_process_identity_review
            @test validated.exit_file_sha256 === nothing

            @test_throws Exception Recovery.
                ld1b_stopped_process_interruption_review(;
                    fixture.identity...,
                    owner_artifact = fixture.owner,
                    owner_receipt_sha256 = fixture.owner_sha,
                    launch_artifact = fixture.launch,
                    launch_receipt_sha256 = fixture.launch_sha,
                    inventory_before_review = inventory,
                    mode = :external_process_identity_review,
                    retirement_reason_code = :interrupted_without_result,
                    observed_attempt_state = (;
                        result_present = false,
                        result_file_sha256 = nothing,
                        result_semantic_assessment = :result_absent,
                    ),
                    review_host = "review-host", reviewer = "reviewer",
                    reviewed_at_utc = "time",
                    controller_confirmed_stopped = false,
                    child_confirmed_stopped = true,
                    external_process_identity_review = external)
        end
    end

    @testset "CREATE_NEW review publication" begin
        mktempdir() do root
            fixture = recovery_fixture(root)
            result = Recovery.ld1b_publish_interruption_review(
                fixture.attempt_dir; fixture.identity...,
                mode = :validated_exit_receipt,
                retirement_reason_code = :interrupted_without_result,
                result_semantic_assessment = :result_absent,
                review_host = "review-host", reviewer = "reviewer-03",
                reviewed_at_utc = "2026-07-27T00:05:00Z",
                controller_confirmed_stopped = true,
                child_confirmed_stopped = true,
                staging_dir = joinpath(root, ".staging"), boundary = root)
            @test result.published
            @test result.review_mode === :validated_exit_receipt
            @test_throws Exception Recovery.ld1b_publish_interruption_review(
                fixture.attempt_dir; fixture.identity...,
                mode = :validated_exit_receipt,
                retirement_reason_code = :interrupted_without_result,
                result_semantic_assessment = :result_absent,
                review_host = "review-host", reviewer = "reviewer-03",
                reviewed_at_utc = "2026-07-27T00:05:00Z",
                controller_confirmed_stopped = true,
                child_confirmed_stopped = true,
                staging_dir = joinpath(root, ".staging"), boundary = root)
        end
    end

    @testset "observed result bytes and retirement reason are coupled" begin
        mktempdir() do root
            fixture = recovery_fixture(root)
            result_path = recovery_write_json(joinpath(
                fixture.attempt_dir, "job_result.json"),
                (schema = "test.unsealed_result.v1", completed = true))
            result_sha = recovery_file_sha(result_path)
            inventory = Recovery.ld1b_inventory_before_interruption_review(
                fixture.attempt_dir)
            state = (;
                result_present = true,
                result_file_sha256 = result_sha,
                result_semantic_assessment =
                    :semantically_valid_unsealed_result,
            )
            review = Recovery.ld1b_stopped_process_interruption_review(;
                fixture.identity...,
                owner_artifact = fixture.owner,
                owner_receipt_sha256 = fixture.owner_sha,
                launch_artifact = fixture.launch,
                launch_receipt_sha256 = fixture.launch_sha,
                exit_artifact = fixture.exit,
                exit_receipt_sha256 = fixture.exit_sha,
                inventory_before_review = inventory,
                mode = :validated_exit_receipt,
                retirement_reason_code =
                    :interrupted_with_semantically_valid_unsealed_result,
                observed_attempt_state = state,
                review_host = "review-host", reviewer = "reviewer",
                reviewed_at_utc = "2026-07-27T00:05:00Z",
                controller_confirmed_stopped = true,
                child_confirmed_stopped = true)
            recovery_write_json(joinpath(fixture.attempt_dir,
                Recovery.LD1B_INTERRUPTION_REVIEW_FILENAME), review)
            validated = Recovery.ld1b_validate_interruption_review_file(
                fixture.attempt_dir; fixture.identity...)
            @test validated.retirement_reason_code ===
                :interrupted_with_semantically_valid_unsealed_result
            @test validated.observed_attempt_state["result_file_sha256"] ==
                result_sha

            mismatched_state = merge(state, (;
                result_semantic_assessment = :invalid_unsealed_result))
            @test_throws Exception Recovery.
                ld1b_stopped_process_interruption_review(;
                    fixture.identity...,
                    owner_artifact = fixture.owner,
                    owner_receipt_sha256 = fixture.owner_sha,
                    launch_artifact = fixture.launch,
                    launch_receipt_sha256 = fixture.launch_sha,
                    exit_artifact = fixture.exit,
                    exit_receipt_sha256 = fixture.exit_sha,
                    inventory_before_review = inventory,
                    mode = :validated_exit_receipt,
                    retirement_reason_code =
                        :interrupted_with_semantically_valid_unsealed_result,
                    observed_attempt_state = mismatched_state,
                    review_host = "review-host", reviewer = "reviewer",
                    reviewed_at_utc = "2026-07-27T00:05:00Z",
                    controller_confirmed_stopped = true,
                    child_confirmed_stopped = true)

            write(result_path, "mutated")
            @test_throws Exception Recovery.
                ld1b_validate_interruption_review_file(
                    fixture.attempt_dir; fixture.identity...)
        end
    end

    @testset "exact schemas, identities, and receipt lineage fail closed" begin
        mktempdir() do root
            fixture = recovery_fixture(root)
            inventory = Recovery.ld1b_inventory_before_interruption_review(
                fixture.attempt_dir)
            args = (;
                fixture.identity...,
                owner_artifact = fixture.owner,
                owner_receipt_sha256 = fixture.owner_sha,
                launch_artifact = fixture.launch,
                launch_receipt_sha256 = fixture.launch_sha,
                exit_artifact = fixture.exit,
                exit_receipt_sha256 = fixture.exit_sha,
                inventory_before_review = inventory,
                mode = :validated_exit_receipt,
                retirement_reason_code = :interrupted_without_result,
                observed_attempt_state = (;
                    result_present = false,
                    result_file_sha256 = nothing,
                    result_semantic_assessment = :result_absent,
                ),
                review_host = "review-host", reviewer = "reviewer",
                reviewed_at_utc = "2026-07-27T00:05:00Z",
                controller_confirmed_stopped = true,
                child_confirmed_stopped = true,
            )
            review = Recovery.ld1b_stopped_process_interruption_review(; args...)
            @test_throws Exception Recovery.
                ld1b_validate_stopped_process_interruption_review(
                    merge(review, (; unknown = true));
                    fixture.identity...,
                    owner_artifact = fixture.owner,
                    owner_receipt_sha256 = fixture.owner_sha,
                    launch_artifact = fixture.launch,
                    launch_receipt_sha256 = fixture.launch_sha,
                    exit_artifact = fixture.exit,
                    exit_receipt_sha256 = fixture.exit_sha)
            @test_throws Exception Recovery.
                ld1b_validate_stopped_process_interruption_review(
                    merge(review, (; scope = :tampered));
                    fixture.identity...,
                    owner_artifact = fixture.owner,
                    owner_receipt_sha256 = fixture.owner_sha,
                    launch_artifact = fixture.launch,
                    launch_receipt_sha256 = fixture.launch_sha,
                    exit_artifact = fixture.exit,
                    exit_receipt_sha256 = fixture.exit_sha)
            @test_throws Exception Recovery.
                ld1b_validate_stopped_process_interruption_review(review;
                    fixture.identity...,
                    owner_artifact = fixture.owner,
                    owner_receipt_sha256 = recovery_hex("d"),
                    launch_artifact = fixture.launch,
                    launch_receipt_sha256 = fixture.launch_sha,
                    exit_artifact = fixture.exit,
                    exit_receipt_sha256 = fixture.exit_sha)
            @test_throws Exception Recovery.ld1b_attempt_owner_precommit(;
                fixture.identity..., controller_host = "host",
                controller_run_id = "run", controller_pid = 0,
                recorded_at_utc = "time")
            @test_throws Exception Recovery.ld1b_attempt_owner_precommit(;
                fixture.identity..., controller_host = "",
                controller_run_id = "run", controller_pid = 1,
                recorded_at_utc = "time")
            @test_throws Exception Recovery.ld1b_attempt_owner_precommit(;
                fixture.identity..., attempt_number = 2,
                attempt_role = :primary, controller_host = "host",
                controller_run_id = "run", controller_pid = 1,
                recorded_at_utc = "time")
            colliding_plan = Dict{Any,Any}(pairs(recovery_plan()))
            colliding_plan["plan_id"] = recovery_hex("1")
            @test_throws Exception Recovery.ld1b_attempt_owner_precommit(;
                plan_identity = colliding_plan,
                execution_source_identity = fixture.identity.
                    execution_source_identity,
                job_identity = fixture.identity.job_identity,
                attempt_number = 1, attempt_role = :primary,
                controller_host = "host", controller_run_id = "run",
                controller_pid = 1, recorded_at_utc = "time")
        end
    end

    @testset "snapshot links, duplicate keys, and inventory mutation fail" begin
        mktempdir() do root
            fixture = recovery_fixture(root)
            hardlink(fixture.owner_path, joinpath(root, "owner-link.json"))
            @test_throws Exception Recovery.ld1b_validate_attempt_owner_file(
                fixture.attempt_dir; fixture.identity...)
        end
        mktempdir() do root
            fixture = recovery_fixture(root)
            outside = joinpath(root, "outside.json")
            mv(fixture.owner_path, outside)
            symlink(outside, fixture.owner_path)
            @test_throws Exception Recovery.ld1b_validate_attempt_owner_file(
                fixture.attempt_dir; fixture.identity...)
        end
        mktempdir() do root
            fixture = recovery_fixture(root)
            write(fixture.owner_path,
                "{\"schema\":\"x\",\"schema\":\"y\"}\n")
            @test_throws Exception Recovery.ld1b_validate_attempt_owner_file(
                fixture.attempt_dir; fixture.identity...)
        end
        mktempdir() do root
            fixture = recovery_fixture(root)
            Recovery.ld1b_publish_interruption_review(fixture.attempt_dir;
                fixture.identity..., mode = :validated_exit_receipt,
                retirement_reason_code = :interrupted_without_result,
                result_semantic_assessment = :result_absent,
                review_host = "review-host", reviewer = "reviewer",
                reviewed_at_utc = "2026-07-27T00:05:00Z",
                controller_confirmed_stopped = true,
                child_confirmed_stopped = true,
                staging_dir = joinpath(root, ".staging"), boundary = root)
            write(joinpath(fixture.attempt_dir, "late-member.txt"), "late")
            @test_throws Exception Recovery.
                ld1b_validate_interruption_review_file(
                    fixture.attempt_dir; fixture.identity...)
        end
    end
end

recovery_execution_context_tests()
