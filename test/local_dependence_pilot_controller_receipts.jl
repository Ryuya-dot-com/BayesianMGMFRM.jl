using Test

const LD1B1_CONTROLLER_TEST_ROOT = normpath(joinpath(@__DIR__, ".."))
include(joinpath(
    LD1B1_CONTROLLER_TEST_ROOT,
    "scripts",
    "run_local_dependence_calibration_pilot_batch.jl",
))

ld1b1_controller_test_hex(character) = repeat(String(character), 64)

function ld1b1_controller_test_identity()
    execution_source_identity = (;
        batch_runner_source_sha256 = ld1b1_file_sha256(joinpath(
            LD1B1_CONTROLLER_TEST_ROOT,
            "scripts",
            "run_local_dependence_calibration_pilot_batch.jl",
        )),
        local_json_source_sha256 = ld1b1_file_sha256(joinpath(
            LD1B1_CONTROLLER_TEST_ROOT, "scripts", "local_json.jl")),
        job_runner_source_sha256 = ld1b1_controller_test_hex("b"),
        attempt_archive_source_sha256 =
            LD1B1AttemptArchive.ld1b_attempt_archive_source_sha256(),
        local_dependence_pilot_recovery_source_sha256 =
            LD1B1Recovery.ld1b_recovery_source_sha256(),
        local_dependence_pilot_calibration_semantics_source_sha256 =
            ld1b1_file_sha256(joinpath(
                LD1B1_CONTROLLER_TEST_ROOT,
                "scripts",
                "local_dependence_pilot_calibration_semantics.jl",
            )),
    )
    return (;
        plan_id = ld1b1_controller_test_hex("1"),
        protocol_plan_id = ld1b1_controller_test_hex("2"),
        protocol_file_sha256 = ld1b1_controller_test_hex("3"),
        protocol_content_hash = ld1b1_controller_test_hex("4"),
        ordered_job_rows_sha256 = ld1b1_controller_test_hex("5"),
        pilot_contract_sha256 = ld1b1_controller_test_hex("6"),
        execution_source_identity,
    )
end

function ld1b1_controller_test_job()
    return (;
        job_id = "ld1b1_controller_fake_job",
        row_index = 1,
        scenario_index = 1,
        scenario_id = :controller_fake_scenario,
        replication = 1,
        expected_action = :fit_and_score_diagnostic,
        seed = 101,
        fit_seed = 102,
        draw_selection_seed = 103,
        posterior_predictive_seed = 104,
    )
end

function ld1b1_controller_test_prepare(root; run_id = "test_run")
    identity = ld1b1_controller_test_identity()
    job = ld1b1_controller_test_job()
    setup = ld1b1_publish_attempt_reservation_create_new(
        root, identity, job, 1, run_id)
    @test isfile(setup.lineage.reservation_path)
    @test !ispath(setup.lineage.attempt_dir)
    mkpath(dirname(setup.lineage.attempt_dir))
    mkdir(setup.lineage.attempt_dir)
    owner = ld1b1_publish_canonical_owner_create_new(
        setup.lineage, root)
    return (; root, identity, job, setup, owner)
end

function ld1b1_controller_test_child(exit_code::Int)
    return String[
        Base.julia_cmd().exec[1],
        "--startup-file=no",
        "-O0",
        "-e",
        "sleep(0.2); exit($exit_code)",
    ]
end

function ld1b1_controller_test_run(fixture, exit_code::Int)
    return ld1b1_run_command_with_controller_receipts(
        ld1b1_controller_test_child(exit_code),
        joinpath(fixture.root, "fake_child.log"),
        fixture.setup.lineage,
        fixture.owner.owner,
        fixture.root,
    )
end

function ld1b1_controller_test_write_json(path, value)
    mkpath(dirname(path))
    open(path, "w") do io
        write_json(io, value)
        println(io)
    end
    return path
end

function ld1b1_controller_test_fit_signature_artifact(signature)
    return Dict{String,Any}(
        "manifest" => Dict{String,Any}(
            "data" => Dict("data_signature" => signature),
            "validation" => Dict("data_signature" => signature),
            "fit" => Dict{String,Any}(
                "data_signature" => signature,
                "design_identity" =>
                    Dict("data_signature" => signature),
            ),
            "rating_design" => Dict{String,Any}(
                "data_signature" => signature,
                "anchor_linking" =>
                    Dict("data_signature" => signature),
            ),
        ),
        "reproducibility" => Dict("data_signature" => signature),
        "archive_manifest" => Dict{String,Any}(
            "manifest" => Dict("data_signature" => signature),
            "reproducibility" => Dict("data_signature" => signature),
        ),
    )
end

function ld1b1_controller_test_fit_export_source(artifact)
    native_hash = Dict(
        "algorithm" => "sha256",
        "value" => ld1b1_controller_test_hex("a"),
        "scope" => "artifact_without_hash_metadata",
        "canonicalization" => "cache_stable_string",
        "n_canonical_bytes" => 1,
    )
    artifact["schema"] = "bayesianmgmfrm.fit_artifact.v1"
    artifact["object"] = "fit_artifact"
    artifact["created_at"] = "2026-07-27T00:00:00"
    artifact["evidence_artifact_schema_policy"] = Dict{String,Any}()
    get!(artifact, "diagnostics", Dict{String,Any}())
    artifact["posterior_summary"] = Any[]
    artifact["environment"] = nothing
    artifact["draws"] = Any[]
    artifact["log_posterior"] = Any[]
    artifact["sampler_stats"] = Any[]
    artifact["content_hash"] = deepcopy(native_hash)
    json_hash = ld1b1_json_content_hash_record(
        artifact; scope = :fit_artifact_json_payload)
    export_value = Dict(
        "schema" =>
            "bayesianmgmfrm.local_dependence_pilot_fit_artifact_export.v1",
        "object" => "fit_artifact_export",
        "serialization" => Dict(
            "format" => "json",
            "projection" => "ld1b1_json_native_v1",
            "symbol_values" => "string",
            "missing_values" => "json_null",
            "nonfinite_numbers" => "rejected",
        ),
        "artifact_content_hash" => native_hash,
        "json_content_hash" => ld1b1_json_native(json_hash),
        "artifact" => artifact,
    )
    return (;
        bytes = collect(codeunits(JSON3.write(export_value))),
        payload = (;
            fit_artifact_json_content_hash = json_hash.value,
            data_signature = artifact["reproducibility"]["data_signature"],
        ),
    )
end

function ld1b1_controller_test_fit_source_error(artifact)
    source = ld1b1_controller_test_fit_export_source(artifact)
    return try
        ld1b1_validate_source_member_json(
            source.bytes,
            :fit_result,
            nothing,
            source.payload,
            :completed,
        )
        nothing
    catch error
        error
    end
end

@testset "LD1b1 canonical decimal data signatures fail closed" begin
    signature = "18446744073709551615"
    @test ld1b1_data_signature(signature, "signature") == signature
    @test ld1b1_data_signature(
        typemax(UInt64), "native signature";
        allow_native_uint64 = true) == signature
    @test_throws Exception ld1b1_data_signature(
        typemax(UInt64), "unprojected signature")
    @test_throws Exception ld1b1_data_signature(
        42, "signed native signature"; allow_native_uint64 = true)
    @test_throws Exception ld1b1_data_signature("01", "signature")
    @test_throws Exception ld1b1_data_signature(
        "18446744073709551616", "signature")

    parsed_small_number = JSON3.read("{\"data_signature\":42}")[
        :data_signature]
    parsed_large_number = JSON3.read(
        "{\"data_signature\":18446744073709551615}")[
            :data_signature]
    @test parsed_large_number isa Number
    @test !(parsed_large_number isa AbstractString)
    @test_throws Exception ld1b1_data_signature(
        parsed_small_number, "JSON number")
    @test_throws Exception ld1b1_data_signature(
        parsed_large_number, "large JSON number")

    artifact = ld1b1_controller_test_fit_signature_artifact(signature)
    validated = ld1b1_validate_canonical_fit_artifact_data_signatures(
        artifact, signature)
    @test validated.data_signature == signature
    @test validated.n_paths == 9

    invalid_string = deepcopy(artifact)
    invalid_string["manifest"]["fit"]["data_signature"] = "01"
    @test_throws Exception ld1b1_validate_canonical_fit_artifact_data_signatures(
        invalid_string, signature)
    invalid_string_source_error =
        ld1b1_controller_test_fit_source_error(deepcopy(invalid_string))
    @test invalid_string_source_error isa Exception
    @test occursin("not a canonical decimal data signature",
        sprint(showerror, invalid_string_source_error))

    invalid_number = deepcopy(artifact)
    invalid_number["manifest"]["fit"]["data_signature"] =
        parsed_large_number
    @test_throws Exception ld1b1_validate_canonical_fit_artifact_data_signatures(
        invalid_number, signature)
    invalid_number_source_error =
        ld1b1_controller_test_fit_source_error(deepcopy(invalid_number))
    @test invalid_number_source_error isa Exception
    @test occursin("not a canonical decimal string data signature",
        sprint(showerror, invalid_number_source_error))

    mismatch = deepcopy(artifact)
    mismatch["archive_manifest"]["manifest"]["data_signature"] = "42"
    @test_throws Exception ld1b1_validate_canonical_fit_artifact_data_signatures(
        mismatch, signature)

    missing_path = deepcopy(artifact)
    delete!(missing_path["manifest"]["data"], "data_signature")
    @test_throws Exception ld1b1_validate_canonical_fit_artifact_data_signatures(
        missing_path, signature)

    additional_path = deepcopy(artifact)
    additional_path["diagnostics"] = Dict("data_signature" => signature)
    @test_throws Exception ld1b1_validate_canonical_fit_artifact_data_signatures(
        additional_path, signature)

    moved_path = deepcopy(artifact)
    delete!(moved_path["manifest"]["fit"]["design_identity"],
        "data_signature")
    moved_path["manifest"]["design_identity"] =
        Dict("data_signature" => signature)
    @test_throws Exception ld1b1_validate_canonical_fit_artifact_data_signatures(
        moved_path, signature)

    source_tamper = ld1b1_controller_test_fit_signature_artifact(signature)
    source_tamper["diagnostics"] = Dict("data_signature" => signature)
    source_error = ld1b1_controller_test_fit_source_error(source_tamper)
    @test source_error isa Exception
    @test occursin("data-signature path set is noncanonical",
        sprint(showerror, source_error))
end

@testset "LD1b1 controller readiness and command authorization" begin
    readiness = ld1b1_execution_readiness(;
        protocol_execution_authorized = true,
        job_runner_path = LD1B1_DEFAULT_JOB_RUNNER,
        attempt_root = LD1B1_DEFAULT_ATTEMPT_ROOT,
        canonical_executor_source_pin_validated = false,
        bounded_canonical_smoke_passed = true,
        completed_attempt_archive_seal_supported = true,
        interrupted_attempt_recovery_review_passed = true,
    )
    @test readiness.canonical_executor_materialized ==
        (isfile(LD1B1_DEFAULT_JOB_RUNNER) &&
            !islink(LD1B1_DEFAULT_JOB_RUNNER))
    @test !readiness.final_worker_source_pinned_and_identities_regenerated
    @test !readiness.canonical_executor_source_pinned
    @test !readiness.operational_execution_authorized
    @test :final_worker_source_pinned_and_identities_regenerated in
        readiness.blockers

    pinned = ld1b1_execution_readiness(;
        protocol_execution_authorized = true,
        job_runner_path = LD1B1_DEFAULT_JOB_RUNNER,
        attempt_root = LD1B1_DEFAULT_ATTEMPT_ROOT,
        canonical_executor_source_pin_validated = true,
        bounded_canonical_smoke_passed = false,
        completed_attempt_archive_seal_supported = true,
        interrupted_attempt_recovery_review_passed = false,
    )
    @test pinned.canonical_executor_materialized
    @test pinned.final_worker_source_pinned_and_identities_regenerated
    @test pinned.canonical_executor_source_pinned
    @test !pinned.operational_execution_authorized
    @test Set(pinned.blockers) == Set((
        :bounded_canonical_smoke_passed,
        :interrupted_attempt_recovery_review_passed,
    ))

    identity = ld1b1_controller_test_identity()
    job = ld1b1_controller_test_job()
    mktempdir() do root
        options = (;
            attempt = 1,
            runner = LD1B1_DEFAULT_JOB_RUNNER,
            protocol = LD1B1_DEFAULT_PROTOCOL,
            mode = :dry_run,
            retry_of = nothing,
            retry_reason = nothing,
        )
        status_command = ld1b1_job_command(
            job, identity, root, options;
            controller_readiness_authorized = false)
        @test !status_command.controller_readiness_authorized
        @test "status" in status_command.args
        @test !("--controller-readiness-authorized" in status_command.args)
        @test "--reservation-receipt" in status_command.args

        execute_command = ld1b1_job_command(
            job, identity, root, options;
            controller_readiness_authorized = true)
        @test execute_command.controller_readiness_authorized
        @test "execute" in execute_command.args
        @test "--controller-readiness-authorized" in execute_command.args
    end
end

@testset "LD1b1 controller CREATE_NEW receipt order" begin
    mktempdir() do root
        fixture = ld1b1_controller_test_prepare(root)
        result = ld1b1_controller_test_run(fixture, 0)
        @test result.ok
        @test result.subprocess_started
        @test result.exit_code == 0
        @test result.receipt_order ==
            (:reservation, :attempt_directory, :owner, :launch, :exit)
        receipts = ld1b1_validate_canonical_terminal_admission_receipts(
            fixture.setup.lineage.attempt_dir,
            fixture.identity,
            fixture.job,
            1,
        )
        @test receipts.exit_code == 0
        @test receipts.owner.state === :canonical_owner_precommitted
        @test receipts.launch.owner.file_sha256 ==
            receipts.owner.file_sha256
        @test receipts.exit.launch.file_sha256 ==
            receipts.launch.file_sha256
        @test !ispath(ld1b1_seal_path(
            root, fixture.job.job_id, 1))
        @test_throws Exception ld1b1_publish_canonical_owner_create_new(
            fixture.setup.lineage, root)
        @test_throws Exception ld1b1_publish_attempt_reservation_create_new(
            root, fixture.identity, fixture.job, 1, "test_run")
    end
end

@testset "LD1b1 nonzero child exit cannot enter terminal admission" begin
    mktempdir() do root
        fixture = ld1b1_controller_test_prepare(root)
        result = ld1b1_controller_test_run(fixture, 7)
        @test !result.ok
        @test result.subprocess_started
        @test result.exit_code == 7
        receipts = ld1b1_validate_canonical_controller_receipts(
            fixture.setup.lineage.attempt_dir,
            fixture.identity,
            fixture.job,
            1,
        )
        @test receipts.exit_code == 7
        @test_throws ErrorException ld1b1_validate_canonical_terminal_admission_receipts(
            fixture.setup.lineage.attempt_dir,
            fixture.identity,
            fixture.job,
            1,
        )
    end
end

@testset "LD1b1 missing and tampered receipts fail closed" begin
    mktempdir() do root
        fixture = ld1b1_controller_test_prepare(root)
        result = ld1b1_controller_test_run(fixture, 0)
        @test result.ok
        exit_path = joinpath(
            fixture.setup.lineage.attempt_dir,
            LD1B1Recovery.LD1B_CHILD_EXIT_FILENAME,
        )
        mv(exit_path, joinpath(root, "removed_exit.json"))
        @test_throws Exception ld1b1_validate_canonical_controller_receipts(
            fixture.setup.lineage.attempt_dir,
            fixture.identity,
            fixture.job,
            1,
        )
    end

    mktempdir() do root
        fixture = ld1b1_controller_test_prepare(root)
        result = ld1b1_controller_test_run(fixture, 0)
        @test result.ok
        launch_path = joinpath(
            fixture.setup.lineage.attempt_dir,
            LD1B1Recovery.LD1B_CHILD_LAUNCH_FILENAME,
        )
        open(launch_path, "a") do io
            println(io)
        end
        @test_throws Exception ld1b1_validate_canonical_controller_receipts(
            fixture.setup.lineage.attempt_dir,
            fixture.identity,
            fixture.job,
            1,
        )
    end
end

@testset "LD1b1 reservation-only scan is partial and contributes zero" begin
    identity = ld1b1_controller_test_identity()
    job = ld1b1_controller_test_job()
    mktempdir() do root
        setup = ld1b1_publish_attempt_reservation_create_new(
            root, identity, job, 1, "reservation_only")
        @test !ispath(setup.lineage.attempt_dir)
        scan = ld1b1_scan_attempts(
            [job], identity, root;
            calibration_semantic_context = (; synthetic = true),
        )
        @test scan.attempt_reservation_scan_active
        @test length(scan.attempt_reservation_rows) == 1
        @test only(scan.job_state_rows).state === :partial
        @test scan.summary.n_primary_attempts_observed == 0
        @test scan.summary.n_partial_primary_attempts == 1
        @test !scan.summary.pilot_execution_completed
        attempt = only(only(scan.job_state_rows).attempt_result_rows)
        @test attempt.archive_state === :reserved_precommit_partial
        @test attempt.scientific_contribution == 0
    end
end

@testset "LD1b1 reservation ledger participates in the state digest" begin
    identity = ld1b1_controller_test_identity()
    job = ld1b1_controller_test_job()
    mktempdir() do root
        setup = ld1b1_publish_attempt_reservation_create_new(
            root, identity, job, 1, "digest_binding")
        mkpath(dirname(setup.lineage.attempt_dir))
        mkdir(setup.lineage.attempt_dir)
        before = ld1b1_scan_attempts(
            [job], identity, root;
            calibration_semantic_context = (; synthetic = true),
        )
        open(setup.lineage.reservation_path, "a") do io
            println(io)
        end
        after = ld1b1_scan_attempts(
            [job], identity, root;
            calibration_semantic_context = (; synthetic = true),
        )
        @test before.attempt_reservation_state_digest !=
            after.attempt_reservation_state_digest
        @test before.state_digest != after.state_digest
        @test only(before.attempt_reservation_rows).
            reservation_file_sha256 !=
            only(after.attempt_reservation_rows).reservation_file_sha256
    end
end

@testset "LD1b1 reservation-only precommit retirement remains science-zero" begin
    identity = ld1b1_controller_test_identity()
    job = ld1b1_controller_test_job()
    mktempdir() do root
        setup = ld1b1_publish_attempt_reservation_create_new(
            root, identity, job, 1, "precommit_retirement")
        mkpath(dirname(setup.lineage.attempt_dir))
        mkdir(setup.lineage.attempt_dir)
        inventory = LD1B1Recovery.
            ld1b_inventory_before_precommit_interruption_review(
                setup.lineage.attempt_dir)
        review = LD1B1Recovery.ld1b_precommit_interruption_review(;
            setup.lineage.identity_args...,
            setup.lineage.lineage_args...,
            inventory_before_review = inventory,
            reason_code = :interrupted_after_reservation_before_owner,
            review_host = "independent-review-host",
            reviewer = "independent-reviewer",
            reviewed_at_utc = "2026-07-27T00:05:00Z",
            controller_confirmed_stopped = true,
            child_launch_receipt_confirmed_absent = true,
            child_process_confirmed_stopped = true,
        )
        external_path = ld1b1_controller_test_write_json(
            joinpath(root, "external_precommit_review.json"), review)
        rm(setup.lineage.attempt_dir)
        @test !ispath(setup.lineage.attempt_dir)

        rows = ld1b1_retire_interrupted_selected(
            (; selected = (job,)),
            (; identity, calibration_semantic_context = (; synthetic = true)),
            root,
            (;
                attempt = 1,
                stopped_process_review = external_path,
                retirement_reason =
                    :interrupted_after_reservation_before_owner,
            ),
        )
        row = only(rows)
        @test row.action_status === :retired_interruption_verified
        @test row.review_mode === :precommit_process_stop_review
        @test !row.model_fit_run
        @test !row.mcmc_run

        retired = ld1b1_validate_retired_attempt(
            root, identity, job, 1)
        @test retired.review_kind === :precommit_interruption
        @test retired.retirement_reason_code ===
            :interrupted_after_reservation_before_owner
        @test !retired.retirement_counts_toward_primary

        scan = ld1b1_scan_attempts(
            [job], identity, root;
            calibration_semantic_context = (; synthetic = true),
        )
        state = only(scan.job_state_rows)
        @test state.state === :primary_retired_interrupted
        @test scan.summary.n_primary_attempts_observed == 0
        @test scan.summary.n_retired_primary_attempts == 1
        @test scan.summary.n_partial_attempts == 0
        @test !scan.summary.pilot_execution_completed

        repeated = only(ld1b1_retire_interrupted_selected(
            (; selected = (job,)),
            (; identity, calibration_semantic_context = (; synthetic = true)),
            root,
            (;
                attempt = 1,
                stopped_process_review = external_path,
                retirement_reason =
                    :interrupted_after_reservation_before_owner,
            ),
        ))
        @test repeated.review_publication === :reused_existing
        @test repeated.retirement_publication === :reused_existing
    end
end

@testset "LD1b1 canonical launched interruption retires with reservation lineage" begin
    mktempdir() do root
        fixture = ld1b1_controller_test_prepare(
            root; run_id = "launched_retirement")
        child = ld1b1_controller_test_run(fixture, 0)
        @test child.ok
        receipts = ld1b1_validate_canonical_controller_receipts(
            fixture.setup.lineage.attempt_dir,
            fixture.identity,
            fixture.job,
            1,
        )
        inventory = LD1B1Recovery.
            ld1b_inventory_before_interruption_review(
                fixture.setup.lineage.attempt_dir)
        review = LD1B1Recovery.
            ld1b_stopped_process_interruption_review(;
                fixture.setup.lineage.identity_args...,
                fixture.setup.lineage.lineage_args...,
                owner_artifact = receipts.owner.artifact,
                owner_receipt_sha256 = receipts.owner.file_sha256,
                launch_artifact = receipts.launch.artifact,
                launch_receipt_sha256 = receipts.launch.file_sha256,
                exit_artifact = receipts.exit.artifact,
                exit_receipt_sha256 = receipts.exit.file_sha256,
                inventory_before_review = inventory,
                mode = :validated_exit_receipt,
                review_host = "independent-review-host",
                reviewer = "independent-reviewer",
                reviewed_at_utc = "2026-07-27T00:10:00Z",
                retirement_reason_code = :interrupted_without_result,
                observed_attempt_state = (;
                    result_present = false,
                    result_file_sha256 = nothing,
                    result_semantic_assessment = :result_absent,
                ),
                controller_confirmed_stopped = true,
                child_confirmed_stopped = true,
            )
        external_path = ld1b1_controller_test_write_json(
            joinpath(root, "external_launched_review.json"), review)
        retired_row = only(ld1b1_retire_interrupted_selected(
            (; selected = (fixture.job,)),
            (;
                identity = fixture.identity,
                calibration_semantic_context = (; synthetic = true),
            ),
            root,
            (;
                attempt = 1,
                stopped_process_review = external_path,
                retirement_reason = :interrupted_without_result,
            ),
        ))
        @test retired_row.action_status === :retired_interruption_verified
        @test retired_row.review_mode === :validated_exit_receipt
        @test !retired_row.model_fit_run
        @test !retired_row.mcmc_run

        retired = ld1b1_validate_retired_attempt(
            root, fixture.identity, fixture.job, 1)
        @test retired.review_kind === :launched_interruption
        @test retired.retirement_reason_code === :interrupted_without_result
        @test !retired.retirement_counts_toward_primary

        scan = ld1b1_scan_attempts(
            [fixture.job], fixture.identity, root;
            calibration_semantic_context = (; synthetic = true),
        )
        @test only(scan.job_state_rows).state ===
            :primary_retired_interrupted
        @test scan.summary.n_primary_attempts_observed == 0
        @test scan.summary.n_retired_primary_attempts == 1
    end
end
