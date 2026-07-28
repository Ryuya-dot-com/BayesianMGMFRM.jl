using SHA
using Test

const PRECOMMIT_REPOSITORY_ROOT = normpath(joinpath(@__DIR__, ".."))
include(joinpath(PRECOMMIT_REPOSITORY_ROOT, "scripts",
    "local_dependence_pilot_recovery.jl"))
using .LocalDependencePilotRecovery
const PrecommitRecovery = LocalDependencePilotRecovery
const PrecommitArchive =
    LocalDependencePilotRecovery.LocalDependencePilotAttemptArchive

precommit_hex(character) = repeat(String(character), 64)

function precommit_identity()
    plan = (;
        plan_id = precommit_hex("1"),
        protocol_plan_id = precommit_hex("2"),
        protocol_file_sha256 = precommit_hex("3"),
        protocol_content_hash = precommit_hex("4"),
        ordered_job_rows_sha256 = precommit_hex("5"),
        pilot_contract_sha256 = precommit_hex("6"),
    )
    execution = (;
        batch_runner_source_sha256 = precommit_hex("a"),
        local_json_source_sha256 = bytes2hex(open(sha256,
            joinpath(PRECOMMIT_REPOSITORY_ROOT, "scripts", "local_json.jl"))),
        job_runner_source_sha256 = precommit_hex("b"),
        attempt_archive_source_sha256 =
            PrecommitArchive.ld1b_attempt_archive_source_sha256(),
        local_dependence_pilot_recovery_source_sha256 =
            PrecommitRecovery.ld1b_recovery_source_sha256(),
        local_dependence_pilot_calibration_semantics_source_sha256 =
            precommit_hex("c"),
    )
    job = (;
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
    return (;
        plan_identity = plan,
        execution_source_identity = execution,
        job_identity = job,
        attempt_number = 1,
        attempt_role = :primary,
    )
end

function precommit_write_json(path, value)
    mkpath(dirname(path))
    open(path, "w") do io
        PrecommitArchive.write_json(io, value)
        println(io)
    end
    return path
end

precommit_file_sha(path) = bytes2hex(open(sha256, path))

function precommit_rehash(edit!::Function, value)
    native = PrecommitRecovery._native(value)
    delete!(native, "content_hash")
    edit!(native)
    return PrecommitArchive.ld1b_archive_with_content_hash(native)
end

function precommit_fixture(root; publish_owner = false,
        reservation_id = "reservation-001")
    identity = precommit_identity()
    attempt_relative = joinpath("jobs", identity.job_identity.job_id,
        "attempt_001")
    attempt_dir = joinpath(root, attempt_relative)
    reservation_path = joinpath(root, "reservations",
        identity.job_identity.job_id, "attempt_001",
        PrecommitRecovery.LD1B_ATTEMPT_RESERVATION_FILENAME)
    mkpath(dirname(reservation_path))
    reservation = PrecommitRecovery.ld1b_publish_attempt_reservation(
        reservation_path; execution_root = root, identity..., reservation_id,
        execution_root_relative_attempt_path = attempt_relative,
        controller_host = "controller-host",
        controller_run_id = "controller-run-001", controller_pid = 8101,
        recorded_at_utc = "2026-07-27T01:00:00Z",
        staging_dir = joinpath(root, ".staging"))
    mkpath(attempt_dir)
    owner = if publish_owner
        PrecommitRecovery.ld1b_publish_canonical_attempt_owner(attempt_dir;
            reservation_path, execution_root = root, identity...,
            expected_reservation_id = reservation_id,
            recorded_at_utc = "2026-07-27T01:00:01Z",
            staging_dir = joinpath(root, ".staging"))
    else
        nothing
    end
    return (; root, identity, attempt_relative, attempt_dir,
        reservation_id, reservation_path, reservation, owner)
end

function precommit_review_args(fixture; owner_present = false)
    return (;
        reservation_path = fixture.reservation_path,
        execution_root = fixture.root,
        fixture.identity...,
        expected_reservation_id = fixture.reservation_id,
        reason_code = owner_present ?
            :interrupted_after_owner_before_launch_receipt :
            :interrupted_after_reservation_before_owner,
        review_host = "review-host",
        reviewer = "reviewer-001",
        reviewed_at_utc = "2026-07-27T01:05:00Z",
        controller_confirmed_stopped = true,
        child_launch_receipt_confirmed_absent = true,
        child_process_confirmed_stopped = true,
        staging_dir = joinpath(fixture.root, ".staging"),
    )
end

function precommit_launched_fixture(root; with_exit::Bool)
    fixture = precommit_fixture(root; publish_owner = true)
    reservation = PrecommitRecovery.ld1b_validate_attempt_reservation_file(
        fixture.reservation_path; execution_root = root,
        fixture.identity...,
        expected_reservation_id = fixture.reservation_id,
        expected_execution_root_relative_attempt_path =
            fixture.attempt_relative)
    owner = PrecommitRecovery.ld1b_validate_canonical_attempt_owner_file(
        fixture.attempt_dir; reservation_path = fixture.reservation_path,
        execution_root = root, fixture.identity...,
        expected_reservation_id = fixture.reservation_id)
    lineage = (;
        reservation_artifact = reservation.artifact,
        reservation_receipt_sha256 = reservation.file_sha256,
        expected_reservation_id = fixture.reservation_id,
        expected_execution_root_relative_reservation_path =
            reservation.execution_root_relative_reservation_path,
        expected_execution_root_relative_attempt_path =
            fixture.attempt_relative,
    )
    launch_artifact = PrecommitRecovery.ld1b_child_launch_receipt(;
        fixture.identity..., owner_artifact = owner.artifact,
        owner_receipt_sha256 = owner.file_sha256, child_pid = 8302,
        recorded_at_utc = "2026-07-27T02:00:01Z", lineage...)
    launch_path = precommit_write_json(joinpath(fixture.attempt_dir,
        PrecommitRecovery.LD1B_CHILD_LAUNCH_FILENAME), launch_artifact)
    launch_sha256 = precommit_file_sha(launch_path)
    exit_artifact = nothing
    exit_sha256 = nothing
    if with_exit
        exit_artifact = PrecommitRecovery.ld1b_child_exit_receipt(;
            fixture.identity..., owner_artifact = owner.artifact,
            owner_receipt_sha256 = owner.file_sha256, launch_artifact,
            launch_receipt_sha256 = launch_sha256, exit_code = 137,
            recorded_at_utc = "2026-07-27T02:00:02Z", lineage...)
        exit_path = precommit_write_json(joinpath(fixture.attempt_dir,
            PrecommitRecovery.LD1B_CHILD_EXIT_FILENAME), exit_artifact)
        exit_sha256 = precommit_file_sha(exit_path)
    end
    return (; fixture..., reservation, canonical_owner = owner,
        launch_artifact, launch_sha256, exit_artifact, exit_sha256, lineage)
end

@testset "local-dependence precommit reservation and recovery" begin
    @testset "immutable reservation and canonical owner lineage" begin
        mktempdir() do root
            fixture = precommit_fixture(root; publish_owner = true)
            @test fixture.reservation.published
            @test fixture.reservation.publication ===
                :same_volume_hardlink_create_new
            @test !fixture.reservation.overwrite_allowed
            reservation = PrecommitRecovery.
                ld1b_validate_attempt_reservation_file(
                    fixture.reservation_path; execution_root = root,
                    fixture.identity...,
                    expected_reservation_id = fixture.reservation_id,
                    expected_execution_root_relative_attempt_path =
                        fixture.attempt_relative)
            @test reservation.state === :attempt_reserved
            @test reservation.execution_root_relative_attempt_path ==
                fixture.attempt_relative
            @test reservation.artifact["publication_contract"][
                "exclusive_create_new"]
            @test !reservation.artifact["publication_contract"][
                "overwrite_allowed"]
            @test reservation.artifact["publication_contract"][
                "immutable_after_publication"]

            owner = PrecommitRecovery.
                ld1b_validate_canonical_attempt_owner_file(
                    fixture.attempt_dir;
                    reservation_path = fixture.reservation_path,
                    execution_root = root, fixture.identity...,
                    expected_reservation_id = fixture.reservation_id)
            @test owner.state === :canonical_owner_precommitted
            @test owner.artifact["schema"] ==
                PrecommitRecovery.LD1B_CANONICAL_ATTEMPT_OWNER_SCHEMA
            @test owner.artifact["reservation_receipt"]["file_sha256"] ==
                fixture.reservation.file_sha256
            @test owner.artifact["owner"]["controller_run_id"] ==
                "controller-run-001"

            launch_artifact = PrecommitRecovery.ld1b_child_launch_receipt(;
                fixture.identity..., owner_artifact = owner.artifact,
                owner_receipt_sha256 = owner.file_sha256,
                child_pid = 8102,
                recorded_at_utc = "2026-07-27T01:00:02Z",
                reservation_artifact = reservation.artifact,
                reservation_receipt_sha256 = reservation.file_sha256,
                expected_reservation_id = fixture.reservation_id,
                expected_execution_root_relative_reservation_path =
                    reservation.execution_root_relative_reservation_path,
                expected_execution_root_relative_attempt_path =
                    fixture.attempt_relative)
            launch_path = precommit_write_json(joinpath(fixture.attempt_dir,
                PrecommitRecovery.LD1B_CHILD_LAUNCH_FILENAME),
                launch_artifact)
            launch = PrecommitRecovery.ld1b_validate_child_launch_file(
                fixture.attempt_dir;
                reservation_path = fixture.reservation_path,
                execution_root = root, fixture.identity...,
                expected_reservation_id = fixture.reservation_id)
            @test launch.state === :child_launched
            @test launch.artifact["schema"] ==
                PrecommitRecovery.LD1B_CHILD_LAUNCH_SCHEMA
            exit_artifact = PrecommitRecovery.ld1b_child_exit_receipt(;
                fixture.identity..., owner_artifact = owner.artifact,
                owner_receipt_sha256 = owner.file_sha256,
                launch_artifact, launch_receipt_sha256 =
                    precommit_file_sha(launch_path), exit_code = 0,
                recorded_at_utc = "2026-07-27T01:00:03Z",
                reservation_artifact = reservation.artifact,
                reservation_receipt_sha256 = reservation.file_sha256,
                expected_reservation_id = fixture.reservation_id,
                expected_execution_root_relative_reservation_path =
                    reservation.execution_root_relative_reservation_path,
                expected_execution_root_relative_attempt_path =
                    fixture.attempt_relative)
            precommit_write_json(joinpath(fixture.attempt_dir,
                PrecommitRecovery.LD1B_CHILD_EXIT_FILENAME), exit_artifact)
            exit = PrecommitRecovery.ld1b_validate_child_exit_file(
                fixture.attempt_dir;
                reservation_path = fixture.reservation_path,
                execution_root = root, fixture.identity...,
                expected_reservation_id = fixture.reservation_id)
            @test exit.state === :child_exit_observed
            @test exit.artifact["schema"] ==
                PrecommitRecovery.LD1B_CHILD_EXIT_SCHEMA

            legacy = PrecommitRecovery.ld1b_attempt_owner_precommit(;
                fixture.identity..., controller_host = "legacy-host",
                controller_run_id = "legacy-run", controller_pid = 1,
                recorded_at_utc = "2026-07-27T00:00:00Z")
            @test PrecommitRecovery.ld1b_validate_attempt_owner_precommit(
                legacy; fixture.identity...).valid
            @test legacy.schema == PrecommitRecovery.LD1B_ATTEMPT_OWNER_SCHEMA
        end
    end

    @testset "reservation exactness, wrong paths, and nonoverwrite" begin
        mktempdir() do root
            fixture = precommit_fixture(root)
            original_sha = precommit_file_sha(fixture.reservation_path)
            @test_throws Exception PrecommitRecovery.
                ld1b_publish_attempt_reservation(fixture.reservation_path;
                    execution_root = root, fixture.identity...,
                    reservation_id = fixture.reservation_id,
                    execution_root_relative_attempt_path =
                        fixture.attempt_relative,
                    controller_host = "controller-host",
                    controller_run_id = "controller-run-001",
                    controller_pid = 8101,
                    recorded_at_utc = "2026-07-27T01:00:00Z",
                    staging_dir = joinpath(root, ".staging"))
            @test precommit_file_sha(fixture.reservation_path) == original_sha

            @test_throws Exception PrecommitRecovery.
                ld1b_validate_attempt_reservation_file(
                    fixture.reservation_path; execution_root = root,
                    fixture.identity...,
                    expected_reservation_id = "wrong-reservation",
                    expected_execution_root_relative_attempt_path =
                        fixture.attempt_relative)
            @test_throws Exception PrecommitRecovery.
                ld1b_validate_attempt_reservation_file(
                    fixture.reservation_path; execution_root = root,
                    fixture.identity...,
                    expected_reservation_id = fixture.reservation_id,
                    expected_execution_root_relative_attempt_path =
                        joinpath("jobs", "wrong", "attempt_001"))

            wrong_path = joinpath(root, "reservations", "wrong",
                PrecommitRecovery.LD1B_ATTEMPT_RESERVATION_FILENAME)
            precommit_write_json(wrong_path, fixture.reservation.artifact)
            @test_throws Exception PrecommitRecovery.
                ld1b_validate_attempt_reservation_file(wrong_path;
                    execution_root = root, fixture.identity...,
                    expected_reservation_id = fixture.reservation_id,
                    expected_execution_root_relative_attempt_path =
                        fixture.attempt_relative)

            extra = precommit_rehash(fixture.reservation.artifact) do native
                native["extra"] = true
            end
            @test_throws Exception PrecommitRecovery.
                ld1b_validate_attempt_reservation(extra;
                    fixture.identity...,
                    expected_reservation_id = fixture.reservation_id,
                    expected_execution_root_relative_reservation_path =
                        fixture.reservation.
                            execution_root_relative_reservation_path,
                    expected_execution_root_relative_attempt_path =
                        fixture.attempt_relative)
            missing = precommit_rehash(fixture.reservation.artifact) do native
                delete!(native["reservation"], "controller_pid")
            end
            @test_throws Exception PrecommitRecovery.
                ld1b_validate_attempt_reservation(missing;
                    fixture.identity...,
                    expected_reservation_id = fixture.reservation_id,
                    expected_execution_root_relative_reservation_path =
                        fixture.reservation.
                            execution_root_relative_reservation_path,
                    expected_execution_root_relative_attempt_path =
                        fixture.attempt_relative)
            tampered = PrecommitRecovery._native(fixture.reservation.artifact)
            tampered["reservation"]["controller_pid"] = 9999
            @test_throws Exception PrecommitRecovery.
                ld1b_validate_attempt_reservation(tampered;
                    fixture.identity...)
        end
    end

    @testset "reservation publication race has one winner" begin
        mktempdir() do root
            identity = precommit_identity()
            attempt_relative = joinpath("jobs", identity.job_identity.job_id,
                "attempt_001")
            reservation_path = joinpath(root, "reservations", "race",
                PrecommitRecovery.LD1B_ATTEMPT_RESERVATION_FILENAME)
            mkpath(dirname(reservation_path))
            outcomes = Channel{Tuple{String,Bool}}(2)
            @sync for reservation_id in ("race-a", "race-b")
                @async begin
                    succeeded = try
                        PrecommitRecovery.ld1b_publish_attempt_reservation(
                            reservation_path; execution_root = root,
                            identity..., reservation_id,
                            execution_root_relative_attempt_path =
                                attempt_relative,
                            controller_host = "race-host",
                            controller_run_id = reservation_id,
                            controller_pid = reservation_id == "race-a" ?
                                8201 : 8202,
                            recorded_at_utc = "2026-07-27T01:00:00Z",
                            staging_dir = joinpath(root, ".staging"))
                        true
                    catch
                        false
                    end
                    put!(outcomes, (reservation_id, succeeded))
                end
            end
            results = [take!(outcomes) for _ in 1:2]
            @test count(last, results) == 1
            winner = only(first(result) for result in results if last(result))
            validated = PrecommitRecovery.
                ld1b_validate_attempt_reservation_file(reservation_path;
                    execution_root = root, identity...,
                    expected_reservation_id = winner,
                    expected_execution_root_relative_attempt_path =
                        attempt_relative)
            @test validated.reservation_id == winner
        end
    end

    @testset "reservation-only recovery is exact and contributes zero" begin
        mktempdir() do root
            fixture = precommit_fixture(root)
            args = precommit_review_args(fixture)
            published = PrecommitRecovery.
                ld1b_publish_precommit_interruption_review(
                    fixture.attempt_dir; args...)
            @test published.published
            @test published.reason_code ===
                :interrupted_after_reservation_before_owner
            @test !published.owner_present
            @test published.scientific_contribution == 0
            validated = PrecommitRecovery.
                ld1b_validate_precommit_interruption_review_file(
                    fixture.attempt_dir;
                    reservation_path = fixture.reservation_path,
                    execution_root = root, fixture.identity...,
                    expected_reservation_id = fixture.reservation_id)
            @test validated.scientific_contribution == 0
            @test !validated.artifact["attempt_state"][
                "child_launch_receipt_present"]
            @test !validated.artifact["attempt_state"][
                "science_execution_authorized"]
            @test !validated.artifact["attempt_state"][
                "job_result_present"]

            original_sha = validated.file_sha256
            @test_throws Exception PrecommitRecovery.
                ld1b_publish_precommit_interruption_review(
                    fixture.attempt_dir; args...)
            @test precommit_file_sha(joinpath(fixture.attempt_dir,
                PrecommitRecovery.
                    LD1B_PRECOMMIT_INTERRUPTION_REVIEW_FILENAME)) ==
                original_sha

            write(joinpath(fixture.attempt_dir, "late-extra.txt"), "late")
            @test_throws Exception PrecommitRecovery.
                ld1b_validate_precommit_interruption_review_file(
                    fixture.attempt_dir;
                    reservation_path = fixture.reservation_path,
                    execution_root = root, fixture.identity...,
                    expected_reservation_id = fixture.reservation_id)
        end
    end

    @testset "owner-before-launch recovery and negative states" begin
        mktempdir() do root
            fixture = precommit_fixture(root; publish_owner = true)
            args = precommit_review_args(fixture; owner_present = true)
            published = PrecommitRecovery.
                ld1b_publish_precommit_interruption_review(
                    fixture.attempt_dir; args...)
            @test published.reason_code ===
                :interrupted_after_owner_before_launch_receipt
            @test published.owner_present
            @test published.scientific_contribution == 0
            validated = PrecommitRecovery.
                ld1b_validate_precommit_interruption_review_file(
                    fixture.attempt_dir;
                    reservation_path = fixture.reservation_path,
                    execution_root = root, fixture.identity...,
                    expected_reservation_id = fixture.reservation_id)
            @test validated.owner_file_sha256 == fixture.owner.file_sha256

            scientific_tamper = precommit_rehash(validated.artifact) do native
                native["attempt_state"]["scientific_contribution"] = 1
            end
            reservation = PrecommitRecovery.
                ld1b_validate_attempt_reservation_file(
                    fixture.reservation_path; execution_root = root,
                    fixture.identity...,
                    expected_reservation_id = fixture.reservation_id,
                    expected_execution_root_relative_attempt_path =
                        fixture.attempt_relative)
            inventory = PrecommitRecovery.
                ld1b_inventory_before_precommit_interruption_review(
                    fixture.attempt_dir)
            @test_throws Exception PrecommitRecovery.
                ld1b_validate_precommit_interruption_review(
                    scientific_tamper; fixture.identity...,
                    reservation_artifact = reservation.artifact,
                    reservation_receipt_sha256 = reservation.file_sha256,
                    expected_reservation_id = fixture.reservation_id,
                    expected_execution_root_relative_reservation_path =
                        reservation.execution_root_relative_reservation_path,
                    expected_execution_root_relative_attempt_path =
                        fixture.attempt_relative,
                    owner_artifact = fixture.owner.artifact,
                    owner_receipt_sha256 = fixture.owner.file_sha256,
                    expected_inventory_before_review = inventory)

            missing_owner_path = joinpath(fixture.attempt_dir,
                PrecommitRecovery.LD1B_ATTEMPT_OWNER_FILENAME)
            rm(missing_owner_path)
            @test_throws Exception PrecommitRecovery.
                ld1b_validate_precommit_interruption_review_file(
                    fixture.attempt_dir;
                    reservation_path = fixture.reservation_path,
                    execution_root = root, fixture.identity...,
                    expected_reservation_id = fixture.reservation_id)
        end

        mktempdir() do root
            fixture = precommit_fixture(root)
            precommit_write_json(joinpath(fixture.attempt_dir,
                PrecommitRecovery.LD1B_CHILD_LAUNCH_FILENAME),
                (; unexpected = "launch"))
            @test_throws Exception PrecommitRecovery.
                ld1b_publish_precommit_interruption_review(
                    fixture.attempt_dir;
                    precommit_review_args(fixture)...)
        end

        mktempdir() do root
            fixture = precommit_fixture(root)
            bad_args = merge(precommit_review_args(fixture), (;
                reason_code =
                    :interrupted_after_owner_before_launch_receipt))
            @test_throws Exception PrecommitRecovery.
                ld1b_publish_precommit_interruption_review(
                    fixture.attempt_dir; bad_args...)
            bad_stopped = merge(precommit_review_args(fixture), (;
                controller_confirmed_stopped = false))
            @test_throws Exception PrecommitRecovery.
                ld1b_publish_precommit_interruption_review(
                    fixture.attempt_dir; bad_stopped...)
            bad_child = merge(precommit_review_args(fixture), (;
                child_launch_receipt_confirmed_absent = false))
            @test_throws Exception PrecommitRecovery.
                ld1b_publish_precommit_interruption_review(
                    fixture.attempt_dir; bad_child...)
            bad_child_process = merge(precommit_review_args(fixture), (;
                child_process_confirmed_stopped = false))
            @test_throws Exception PrecommitRecovery.
                ld1b_publish_precommit_interruption_review(
                    fixture.attempt_dir; bad_child_process...)
        end
    end

    @testset "canonical launched stopped-process reviews" begin
        for with_exit in (false, true)
            mktempdir() do root
                fixture = precommit_launched_fixture(root; with_exit)
                mode = with_exit ? :validated_exit_receipt :
                    :external_process_identity_review
                external = with_exit ? nothing : (;
                    evidence_source = "independent process-table review",
                    controller_process_identity = "controller token absent",
                    child_process_identity = "child token absent",
                    observed_at_utc = "2026-07-27T02:04:00Z",
                )
                published = PrecommitRecovery.ld1b_publish_interruption_review(
                    fixture.attempt_dir; fixture.identity..., mode,
                    review_host = "review-host", reviewer = "reviewer-002",
                    reviewed_at_utc = "2026-07-27T02:05:00Z",
                    retirement_reason_code = :interrupted_without_result,
                    result_semantic_assessment = :result_absent,
                    controller_confirmed_stopped = true,
                    child_confirmed_stopped = true,
                    external_process_identity_review = external,
                    staging_dir = joinpath(root, ".staging"), boundary = root,
                    reservation_path = fixture.reservation_path,
                    execution_root = root,
                    expected_reservation_id = fixture.reservation_id)
                @test published.review_mode === mode
                validated = PrecommitRecovery.
                    ld1b_validate_interruption_review_file(
                        fixture.attempt_dir;
                        reservation_path = fixture.reservation_path,
                        execution_root = root, fixture.identity...,
                        expected_reservation_id = fixture.reservation_id)
                @test validated.valid
                @test validated.mode === mode
                @test (validated.exit_file_sha256 !== nothing) == with_exit
                @test validated.owner_file_sha256 ==
                    fixture.canonical_owner.file_sha256

                if with_exit
                    tampered = precommit_rehash(validated.artifact) do native
                        native["receipt_lineage"]["owner"]["file_sha256"] =
                            precommit_hex("d")
                    end
                    inventory = PrecommitRecovery.
                        ld1b_inventory_before_interruption_review(
                            fixture.attempt_dir)
                    @test_throws Exception PrecommitRecovery.
                        ld1b_validate_stopped_process_interruption_review(
                            tampered; fixture.identity...,
                            owner_artifact =
                                fixture.canonical_owner.artifact,
                            owner_receipt_sha256 =
                                fixture.canonical_owner.file_sha256,
                            launch_artifact = fixture.launch_artifact,
                            launch_receipt_sha256 = fixture.launch_sha256,
                            exit_artifact = fixture.exit_artifact,
                            exit_receipt_sha256 = fixture.exit_sha256,
                            expected_inventory_before_review = inventory,
                            fixture.lineage...)
                    @test_throws Exception PrecommitRecovery.
                        ld1b_validate_interruption_review_file(
                            fixture.attempt_dir;
                            reservation_path = fixture.reservation_path,
                            execution_root = root, fixture.identity...,
                            expected_reservation_id = "wrong-reservation")
                end
            end
        end
    end

    @testset "retirement-safe validation and explicit idempotent reuse" begin
        mktempdir() do root
            fixture = precommit_fixture(root)
            args = precommit_review_args(fixture)
            published = PrecommitRecovery.
                ld1b_publish_precommit_interruption_review(
                    fixture.attempt_dir; args...)
            before = PrecommitRecovery.
                ld1b_inventory_before_precommit_interruption_review(
                    fixture.attempt_dir)
            embedded_rows_sha256 = published.artifact[
                "inventory_before_review"]["rows_sha256"]
            retirement = PrecommitArchive.
                ld1b_publish_attempt_retirement_marker(
                    fixture.attempt_dir; fixture.identity...,
                    retirement_reason_code = published.reason_code,
                    review_record_sha256 = published.review_file_sha256,
                    process_confirmed_stopped = true,
                    staging_dir = joinpath(root, ".staging"), boundary = root)
            @test retirement.publication.published
            after = PrecommitRecovery.
                ld1b_inventory_before_precommit_interruption_review(
                    fixture.attempt_dir)
            @test after.rows_sha256 == before.rows_sha256
            @test after.rows_sha256 == embedded_rows_sha256
            validated = PrecommitRecovery.
                ld1b_validate_precommit_interruption_review_file(
                    fixture.attempt_dir;
                    reservation_path = fixture.reservation_path,
                    execution_root = root, fixture.identity...,
                    expected_reservation_id = fixture.reservation_id)
            @test validated.valid
            @test validated.scientific_contribution == 0

            reused = PrecommitRecovery.
                ld1b_reuse_existing_precommit_interruption_review(
                    fixture.attempt_dir;
                    reservation_path = fixture.reservation_path,
                    execution_root = root, fixture.identity...,
                    expected_reservation_id = fixture.reservation_id,
                    reason_code =
                        :interrupted_after_reservation_before_owner,
                    review_host = "review-host", reviewer = "reviewer-001",
                    reviewed_at_utc = "2026-07-27T01:05:00Z",
                    controller_confirmed_stopped = true,
                    child_launch_receipt_confirmed_absent = true,
                    child_process_confirmed_stopped = true)
            @test reused.reused
            @test !reused.published
            @test !reused.overwrite_allowed
            @test reused.file_sha256 == published.review_file_sha256
            @test_throws Exception PrecommitRecovery.
                ld1b_reuse_existing_precommit_interruption_review(
                    fixture.attempt_dir;
                    reservation_path = fixture.reservation_path,
                    execution_root = root, fixture.identity...,
                    expected_reservation_id = fixture.reservation_id,
                    reason_code =
                        :interrupted_after_reservation_before_owner,
                    review_host = "review-host", reviewer = "reviewer-001",
                    reviewed_at_utc = "different-time",
                    controller_confirmed_stopped = true,
                    child_launch_receipt_confirmed_absent = true,
                    child_process_confirmed_stopped = true)
        end
    end
end
