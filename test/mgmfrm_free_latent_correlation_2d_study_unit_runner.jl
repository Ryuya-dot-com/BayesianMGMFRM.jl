using Test
using BayesianMGMFRM
using JSON3

module FreeCorrelationStudyUnitRunnerForTest

include(joinpath(
    @__DIR__,
    "..",
    "scripts",
    "run_mgmfrm_free_latent_correlation_2d_study_unit.jl",
))

end


function _freecorr_runner_rehash!(runner, value)
    haskey(value, "content_hash") && delete!(value, "content_hash")
    value["content_hash"] = runner.freecorr_json_native(
        runner.freecorr_content_hash_record(
            value;
            covers = :artifact_without_content_hash,
        ),
    )
    return value
end

function _freecorr_runner_options(
        runner,
        root,
        unit_id;
        mode = "status",
        artifact = nothing)
    args = [
        "--mode", mode,
        "--unit-id", unit_id,
        "--attempt-root", root,
        "--allow-test-root",
    ]
    artifact === nothing || append!(args, ["--artifact", artifact])
    return withenv(runner.FREECORR_TEST_ROOT_ENV => "1") do
        runner.freecorr_parse_args(args)
    end
end

function _freecorr_simple_artifact(runner, label)
    return runner.freecorr_with_content_hash((;
        schema = "bayesianmgmfrm.test.preexecution_artifact.v1",
        label,
        scientific_execution_receipt = false,
    ))
end

function _freecorr_generic_validator(runner, value)
    runner.freecorr_verify_content_hash(value; label = "test artifact")
    return true
end

function _freecorr_test_symlink(target, link; dir_target::Bool)
    try
        symlink(target, link; dir_target)
    catch error
        if Sys.iswindows() && error isa Base.IOError &&
                error.code in (Base.UV_EPERM, Base.UV_EACCES)
            return (;
                available = false,
                reason = :windows_symlink_privilege,
                code = error.code,
            )
        end
        rethrow()
    end
    islink(link) || error("symlink probe did not create a link")
    return (; available = true, reason = :available, code = nothing)
end


@testset "free-correlation v2 pre-execution single-unit archive runner" begin
    runner = FreeCorrelationStudyUnitRunnerForTest
    plan = BayesianMGMFRM.Experimental.
        free_latent_correlation_2d_study_plan()
    unit = first(plan.units)

    @testset "frozen scope and CLI" begin
        @test plan.version == 2
        @test endswith(plan.schema, ".v2")
        @test endswith(plan.plan_id, "_v2")
        @test unit.phase === :feasibility

        help = runner.freecorr_parse_args(["--help"])
        @test help.help
        usage = runner.freecorr_runner_usage()
        @test occursin("blocked before archive reservation", usage)
        @test occursin("resource-probe", usage)
        @test occursin("first feasibility unit and three", usage)
        @test occursin("never interprets or creates scientific attempt state", usage)
        @test !occursin(r"(?m)^\s+--all(?:\s|$)", usage)
        @test runner.freecorr_parse_mode("resource-probe") === :resource_probe
        @test runner.freecorr_parse_mode("resource_probe") === :resource_probe
        @test runner.FREECORR_RESOURCE_PROBE_REPETITIONS == 3
        @test runner.FREECORR_RESOURCE_PROBE_FILENAME ==
            "initial_gradient_probe_attempt_001.json"
        @test runner.FREECORR_RESOURCE_PROBE_RESERVATION_FILENAME ==
            "initial_gradient_probe_attempt_001.reservation.json"
        @test runner.FREECORR_RESOURCE_PROBE_FAILURE_FILENAME ==
            "initial_gradient_probe_attempt_001.failure.json"

        duplicate_cases = (
            ["--mode", "status", "--mode", "validate",
                "--unit-id", unit.unit_id],
            ["--unit-id", unit.unit_id, "--unit-id", unit.unit_id],
            ["--mode", "validate", "--unit-id", unit.unit_id,
                "--artifact", "a", "--artifact", "b"],
            ["--unit-id", unit.unit_id,
                "--attempt-root", "a", "--attempt-root", "b"],
            ["--mode", "execute-primary", "--unit-id", unit.unit_id,
                "--confirm-scientific-mcmc", "--confirm-scientific-mcmc"],
            ["--unit-id", unit.unit_id,
                "--allow-test-root", "--allow-test-root"],
        )
        withenv(runner.FREECORR_TEST_ROOT_ENV => "1") do
            for args in duplicate_cases
                @test_throws ErrorException runner.freecorr_parse_args(args)
            end
        end
        for forbidden in (
                ["--all"], ["--attempt", "2"], ["--seed", "1"],
                ["--force"], ["--resume"])
            @test_throws ErrorException runner.freecorr_parse_args(vcat(
                ["--unit-id", unit.unit_id],
                forbidden,
            ))
        end
        @test_throws ErrorException runner.freecorr_parse_args([
            "--unit-id", unit.unit_id,
            "--confirm-scientific-mcmc",
        ])
        mktempdir() do root
            @test_throws ErrorException runner.freecorr_parse_args([
                "--unit-id", unit.unit_id,
                "--attempt-root", root,
                "--allow-test-root",
            ])
            withenv(runner.FREECORR_TEST_ROOT_ENV => "1") do
                @test_throws ErrorException runner.freecorr_parse_args([
                    "--unit-id", unit.unit_id,
                    "--attempt-root", root,
                ])
            end
        end

        source_text = read(joinpath(
            @__DIR__,
            "..",
            "scripts",
            "run_mgmfrm_free_latent_correlation_2d_study_unit.jl",
        ), String)
        @test !occursin("using Serialization", source_text)
        @test !occursin("execute_mcmc = true", source_text)
        @test !occursin("freecorr_started_artifact", source_text)
        @test !occursin("freecorr_generation_artifact", source_text)
        @test !occursin("freecorr_terminal_artifact", source_text)
        @test !occursin("freecorr_validate_started", source_text)
        @test !occursin("freecorr_decode", source_text)
        @test !occursin("run_unit", source_text)
        @test !occursin("mv(", source_text)
        @test occursin("hardlink(temporary_path, target)", source_text)
        if Sys.iswindows()
            @test runner.freecorr_windows_attribute_result_occupied(
                UInt32(0),
                UInt32(0),
                "present",
            )
            @test !runner.freecorr_windows_attribute_result_occupied(
                typemax(UInt32),
                UInt32(2),
                "missing-leaf",
            )
            @test !runner.freecorr_windows_attribute_result_occupied(
                typemax(UInt32),
                UInt32(3),
                "missing-parent",
            )
            @test_throws ErrorException runner.freecorr_windows_attribute_result_occupied(
                typemax(UInt32),
                UInt32(5),
                "access-denied",
            )
        end
        runtests_text = read(joinpath(@__DIR__, "runtests.jl"), String)
        @test count(
            line -> occursin(
                "\"mgmfrm_free_latent_correlation_2d_study_unit_runner.jl\"",
                line,
            ),
            split(runtests_text, '\n'),
        ) == 1 &&
            occursin(
                "free-correlation runner workspace-project subprocess",
                runtests_text,
            ) &&
            occursin("--project=\$(dirname(@__DIR__))", runtests_text) &&
            occursin(
                "\"JULIA_LOAD_PATH\" => join(",
                runtests_text,
            ) &&
            occursin("Sys.iswindows() ? ';' : ':'", runtests_text)
    end

    @testset "strict JSON and canonical content hashes" begin
        for value in (NaN, Inf, -Inf)
            @test_throws ErrorException runner.freecorr_json_native(value)
            @test_throws ErrorException runner.freecorr_canonical_sha256(value)
            @test_throws ErrorException runner.freecorr_encode_json_bytes(value)
        end
        collision = Dict{Any,Any}(:same => 1, "same" => 2)
        @test_throws ErrorException runner.freecorr_json_native(collision)

        artifact = _freecorr_simple_artifact(runner, "canonical-v1")
        @test artifact.content_hash.canonical_format ===
            :freecorr_local_json_sorted_compact_v1
        @test runner.freecorr_verify_content_hash(
            artifact;
            label = "canonical test artifact",
        ) == artifact.content_hash.value

        mktempdir() do root
            duplicate = joinpath(root, "duplicate.json")
            write(duplicate, "{\"key\":1,\"key\":2}")
            @test_throws ErrorException runner.freecorr_read_json_once(
                duplicate,
                "duplicate-key test",
            )
            escaped_duplicate = joinpath(root, "escaped_duplicate.json")
            write(escaped_duplicate, "{\"key\":1,\"\\u006bey\":2}")
            @test_throws ErrorException runner.freecorr_read_json_once(
                escaped_duplicate,
                "escaped duplicate-key test",
            )
        end
    end

    @testset "execution-gate truth table" begin
        @test runner.freecorr_gate_status(true, true, true) ===
            :preexecution_dry_run_core_authorized_runner_blocked
        @test runner.freecorr_gate_status(true, false, false) ===
            :preexecution_dry_run_protocol_authorized_operational_blocked
        @test runner.freecorr_gate_status(false, true, false) ===
            :preexecution_dry_run_protocol_blocked_operational_authorized
        @test runner.freecorr_gate_status(false, false, false) ===
            :preexecution_dry_run_protocol_and_operational_blocked
        for gates in ((true, true, false), (true, false, true),
                (false, true, true), (false, false, true))
            @test_throws ErrorException runner.freecorr_gate_status(gates...)
        end
        preflight = runner.freecorr_preflight(plan, unit)
        @test preflight.protocol_execution_authorized
        @test !preflight.operational_execution_authorized
        @test !preflight.execution_authorized
        @test preflight.execution_authorized === (
            preflight.protocol_execution_authorized &&
            preflight.operational_execution_authorized
        )
    end

    @testset "diagnostic source and environment snapshots" begin
        source_receipt = runner.freecorr_source_receipt(plan)
        source_validation = runner.freecorr_validate_source_receipt(
            source_receipt,
            plan;
            require_current = true,
        )
        @test source_validation.current_matches
        @test source_receipt.scope ===
            :current_diagnostic_snapshot_not_loaded_code_attestation
        @test !source_receipt.scientific_execution_receipt
        @test !source_receipt.loaded_code_attested
        @test source_receipt.source_bytes_read_once_per_file
        @test Tuple(row.path for row in source_receipt.core_sources) ==
            plan.unit_result_contract.source_paths
        @test "src/mgmfrm_free_correlation_resource_probe.jl" in
            plan.unit_result_contract.source_paths

        environment_receipt = runner.freecorr_environment_receipt(plan)
        environment_validation = runner.freecorr_validate_environment_receipt(
            environment_receipt,
            plan;
            require_current = true,
        )
        @test environment_validation.current_matches
        @test environment_receipt.scope ===
            :current_diagnostic_snapshot_not_scientific_execution_receipt
        @test !environment_receipt.scientific_execution_receipt
        @test environment_receipt.environment_bytes_read_once_per_file
        expected_manifest = isfile(joinpath(
            @__DIR__,
            "..",
            "Manifest-v$(VERSION.major).$(VERSION.minor).toml",
        )) ? "Manifest-v$(VERSION.major).$(VERSION.minor).toml" :
            "Manifest.toml"
        @test environment_receipt.environment_files.manifest.path ==
            expected_manifest
        @test environment_receipt.environment_files.project.path ==
            "Project.toml"
        header_version = VersionNumber(
            environment_receipt.manifest_header.julia_version,
        )
        @test (header_version.major, header_version.minor) ==
            (VERSION.major, VERSION.minor)
        @test environment_receipt.manifest_header.manifest_format == "2.0"
        @test environment_receipt.manifest_header.
            project_resolve_hash_verified
        @test environment_receipt.manifest_header.
            manifest_patch_matches_runtime === (header_version == VERSION)
        if VERSION == v"1.12.6"
            @test expected_manifest == "Manifest.toml"
            @test header_version == v"1.12.5"
            @test !environment_receipt.manifest_header.
                manifest_patch_matches_runtime
        elseif VERSION == v"1.12.5" || VERSION == v"1.10.8"
            @test environment_receipt.manifest_header.
                manifest_patch_matches_runtime
        end
        @test environment_receipt.workspace_filesystem.permitted
        if Sys.iswindows() && occursin(
                "Dropbox",
                runner.FREECORR_RUNNER_ROOT,
            )
            @test environment_receipt.workspace_filesystem.reparse_present
            @test environment_receipt.workspace_filesystem.classification ===
                :windows_cloud_files_family
        end
        if environment_receipt.workspace_filesystem.reparse_present
            @test environment_receipt.workspace_filesystem.classification ===
                :windows_cloud_files_family
            @test occursin(
                r"^0x[0-9a-f]{8}$",
                environment_receipt.workspace_filesystem.reparse_tag,
            )
        end

        environment_native = runner.freecorr_json_native(environment_receipt)
        environment_native["runtime"]["blas_threads"] += 1
        _freecorr_runner_rehash!(runner, environment_native)
        @test_throws ErrorException runner.freecorr_validate_environment_receipt(
            environment_native,
            plan;
            require_current = false,
        )
    end

    @testset "dry-run publication and current-receipt validation" begin
        mktempdir() do root
            options = _freecorr_runner_options(
                runner,
                root,
                unit.unit_id;
                mode = "dry-run",
            )
            result = runner.freecorr_write_dry_run(options, plan, unit)
            @test isfile(result.path)
            @test result.publication === :hardlink_create_new
            @test result.published
            @test result.artifact.status ===
                :preexecution_dry_run_protocol_authorized_operational_blocked
            @test result.artifact.scope === :preexecution_diagnostic_only
            @test !result.artifact.scientific_execution_receipt
            @test !result.artifact.loaded_code_attestation
            @test result.artifact.self_consistency_only
            @test !result.artifact.authenticity_attested
            @test !result.artifact.external_anchor_present
            @test !result.artifact.timestamp_attested
            @test result.artifact.execution_gates.
                protocol_execution_authorized
            @test !result.artifact.execution_gates.
                operational_execution_authorized
            @test !result.artifact.execution_gates.execution_authorized
            @test !result.artifact.execution_gates.
                archive_runner_execution_authorized
            @test all(value === false for value in values(
                result.artifact.activity,
            ))
            @test !ispath(runner.freecorr_unit_root(root, plan, unit))
            @test !ispath(runner.freecorr_attempt_dir(root, plan, unit))
            @test runner.freecorr_validate_utc_timestamp(
                result.artifact.created_at_utc,
            ) == result.artifact.created_at_utc
            @test_throws ErrorException runner.freecorr_validate_utc_timestamp(
                "2026-02-30T00:00:00.000Z",
            )

            snapshot = runner.freecorr_read_json_once(
                result.path,
                "published dry-run test artifact",
            )
            @test snapshot.nbytes == filesize(result.path)
            @test length(snapshot.bytes) == snapshot.nbytes
            validation = runner.freecorr_validate_dry_run_artifact(
                snapshot.parsed,
                plan,
                unit;
                require_current = true,
            )
            @test validation.validated
            @test validation.source.current_matches
            @test validation.environment.current_matches

            valid_options = merge(options, (;
                mode = :validate,
                artifact = result.path,
            ))
            validation_artifact = runner.freecorr_validate_artifact_path(
                valid_options,
                plan,
                unit,
            )
            @test validation_artifact.status ===
                :dry_run_artifact_self_consistency_verified_current_snapshot
            @test validation_artifact.artifact_bytes_read_once
            @test validation_artifact.self_consistency_only
            @test !validation_artifact.authenticity_attested
            @test !validation_artifact.external_anchor_present
            @test !validation_artifact.timestamp_attested
            output = IOBuffer()
            errors = IOBuffer()
            code = withenv(runner.FREECORR_TEST_ROOT_ENV => "1") do
                runner.freecorr_runner_main([
                    "--mode", "validate",
                    "--unit-id", unit.unit_id,
                    "--attempt-root", root,
                    "--allow-test-root",
                    "--artifact", result.path,
                ]; output_io = output, error_io = errors)
            end
            @test code == 0
            @test isempty(String(take!(errors)))
            @test JSON3.read(String(take!(output))).status ==
                "dry_run_artifact_self_consistency_verified_current_snapshot"

            content_tampered = runner.freecorr_json_native(snapshot.parsed)
            content_tampered["activity"]["mcmc_executed"] = true
            @test_throws ErrorException runner.freecorr_validate_dry_run_artifact(
                content_tampered,
                plan,
                unit;
                require_current = false,
            )
            _freecorr_runner_rehash!(runner, content_tampered)
            @test_throws ErrorException runner.freecorr_validate_dry_run_artifact(
                content_tampered,
                plan,
                unit;
                require_current = false,
            )

            receipt_tampered = runner.freecorr_json_native(snapshot.parsed)
            source = receipt_tampered["source_snapshot"]
            source["core_sources"][1]["sha256"] = repeat("0", 64)
            source["aggregate_sha256"] = runner.freecorr_canonical_sha256((;
                plan_id = source["plan_id"],
                plan_fingerprint = source["plan_fingerprint"],
                core_sources = source["core_sources"],
                harness_sources = source["harness_sources"],
            ))
            _freecorr_runner_rehash!(runner, source)
            _freecorr_runner_rehash!(runner, receipt_tampered)
            @test runner.freecorr_validate_dry_run_artifact(
                receipt_tampered,
                plan,
                unit;
                require_current = false,
            ).validated
            @test_throws ErrorException runner.freecorr_validate_dry_run_artifact(
                receipt_tampered,
                plan,
                unit;
                require_current = true,
            )

            tampered_path = joinpath(dirname(result.path), "tampered.json")
            write(
                tampered_path,
                runner.freecorr_encode_json_bytes(content_tampered),
            )
            output = IOBuffer()
            errors = IOBuffer()
            code = withenv(runner.FREECORR_TEST_ROOT_ENV => "1") do
                runner.freecorr_runner_main([
                    "--mode", "validate",
                    "--unit-id", unit.unit_id,
                    "--attempt-root", root,
                    "--allow-test-root",
                    "--artifact", tampered_path,
                ]; output_io = output, error_io = errors)
            end
            @test code == 4
            @test isempty(String(take!(output)))
            @test occursin("scientific activity", String(take!(errors)))

            staging = runner.freecorr_staging_dir(root, plan)
            mkpath(staging)
            write(joinpath(staging, "orphan.tmp"), "ignored staging orphan")
            status_options = merge(options, (; mode = :status))
            status = runner.freecorr_status_artifact(
                status_options,
                plan,
                unit,
            )
            @test status.status === :archive_state_valid
            @test status.state.state === :absent
            @test status.resource_probe_state.state === :absent
            @test status.resource_probe_artifacts_inspected_by_status
            @test !status.staging_orphans_are_status_inputs
        end
    end

    @testset "fixed MCMC-free resource-probe receipt" begin
        contract = runner.freecorr_resource_probe_contract()
        @test contract.unit_selection === :first_frozen_feasibility_unit
        @test contract.repetitions == 3
        @test contract.resource_probe_attempt == 1
        @test contract.reservation_required_before_measurement
        @test contract.reservation_permanently_consumes_attempt
        @test contract.interrupted_reservation_requires_operator_review
        @test contract.pre_reservation_runtime_initialization ===
            :one_by_one_blas_gemm
        @test contract.runtime_initialization_result_checked
        @test !contract.runtime_initialization_mcmc
        @test contract.reservation_binds_source_aggregate
        @test contract.reservation_binds_stable_environment_identity
        @test contract.terminal_cross_binding_required
        @test contract.scientific_attempt_tree_separate
        @test !contract.scientific_attempt_creation_supported
        @test !contract.execute_primary_available
        @test !contract.mcmc_allowed
        @test !contract.recovery_evidence_allowed
        @test contract.threshold_failure_receipt_persisted
        @test contract.threshold_failure_exit_code == 5
        @test !contract.retry_supported
        @test !contract.overwrite_allowed
        @test contract.serialized_package_provenance_digests_recomputed
        @test contract.serialized_package_artifact_hash_recomputed
        @test !contract.power_loss_durability_attested
        @test runner.freecorr_resource_probe_exit_code(true) == 0
        @test runner.freecorr_resource_probe_exit_code(false) == 5
        initialization = runner.freecorr_initialize_resource_probe_runtime()
        @test initialization.result_checked
        @test !initialization.mcmc_executed

        mktempdir() do root
            options = _freecorr_runner_options(
                runner,
                root,
                unit.unit_id;
                mode = "resource-probe",
            )
            boundary = runner.freecorr_prepare_archive_root(
                root;
                test_root_override = true,
                create = true,
            )
            reservation = runner.freecorr_resource_probe_reservation(
                plan,
                unit,
            )
            reservation_path =
                runner.freecorr_resource_probe_reservation_path(
                    root,
                    plan,
                    unit,
                )
            runner.freecorr_atomic_publish_json(
                reservation_path,
                reservation,
                runner.freecorr_staging_dir(root, plan),
                boundary;
                semantic_validator = value ->
                    runner.freecorr_validate_resource_probe_reservation(
                        value,
                        plan,
                        unit,
                    ),
                artifact_label = "test resource-probe reservation",
            )
            partial = runner.freecorr_resource_probe_archive_status(
                options,
                plan,
            )
            @test partial.state === :partial
            @test !partial.archive_integrity_passed
            @test partial.disposition ===
                :resource_probe_reserved_incomplete
            @test partial.attempt_consumed
            @test !partial.initial_gradient_probe_thresholds_passed

            retry_measurements = Ref(0)
            @test_throws ErrorException runner.freecorr_write_resource_probe(
                options,
                plan,
                unit;
                measure_probe = (args...) -> begin
                    retry_measurements[] += 1
                    error("must not run")
                end,
            )
            @test retry_measurements[] == 0

            status = runner.freecorr_status_artifact(
                merge(options, (; mode = :status)),
                plan,
                unit,
            )
            @test status.status === :archive_state_invalid
            @test status.resource_probe_state.state === :partial

            output = IOBuffer()
            errors = IOBuffer()
            code = withenv(runner.FREECORR_TEST_ROOT_ENV => "1") do
                runner.freecorr_runner_main([
                    "--mode", "validate",
                    "--unit-id", unit.unit_id,
                    "--attempt-root", root,
                    "--allow-test-root",
                ]; output_io = output, error_io = errors)
            end
            @test code == 4
            @test isempty(String(take!(errors)))
            @test JSON3.read(String(take!(output))).status ==
                "archive_state_invalid"
        end

        mktempdir() do root
            options = _freecorr_runner_options(
                runner,
                root,
                unit.unit_id;
                mode = "resource-probe",
            )
            measurement_started = Channel{Nothing}(1)
            release_measurement = Channel{Nothing}(1)
            measurement_calls = Ref(0)
            winner = @async runner.freecorr_write_resource_probe(
                options,
                plan,
                unit;
                measure_probe = (args...) -> begin
                    measurement_calls[] += 1
                    put!(measurement_started, nothing)
                    take!(release_measurement)
                    error("injected measurement failure")
                end,
            )
            take!(measurement_started)

            losing_measurements = Ref(0)
            @test_throws ErrorException runner.freecorr_write_resource_probe(
                options,
                plan,
                unit;
                measure_probe = (args...) -> begin
                    losing_measurements[] += 1
                    error("loser must not measure")
                end,
            )
            @test losing_measurements[] == 0
            put!(release_measurement, nothing)
            winner_error = try
                fetch(winner)
                nothing
            catch error
                error
            end
            @test winner_error isa TaskFailedException
            @test measurement_calls[] == 1

            reservation_path =
                runner.freecorr_resource_probe_reservation_path(
                    root,
                    plan,
                    unit,
                )
            failure_path = runner.freecorr_resource_probe_failure_path(
                root,
                plan,
                unit,
            )
            @test isfile(reservation_path)
            @test isfile(failure_path)
            @test !ispath(runner.freecorr_resource_probe_path(
                root,
                plan,
                unit,
            ))
            terminal = runner.freecorr_resource_probe_archive_status(
                options,
                plan,
            )
            @test terminal.state === :valid
            @test terminal.outcome === :operational_failure
            @test terminal.archive_integrity_passed
            @test terminal.attempt_consumed
            @test !terminal.initial_gradient_probe_thresholds_passed

            post_failure_measurements = Ref(0)
            @test_throws ErrorException runner.freecorr_write_resource_probe(
                options,
                plan,
                unit;
                measure_probe = (args...) -> begin
                    post_failure_measurements[] += 1
                    error("retry must not measure")
                end,
            )
            @test post_failure_measurements[] == 0
            @test !ispath(runner.freecorr_unit_root(root, plan, unit))
        end

        mktempdir() do root
            wrong_unit = plan.units[2]
            wrong_output = IOBuffer()
            wrong_errors = IOBuffer()
            wrong_code = withenv(
                    runner.FREECORR_TEST_ROOT_ENV => "1") do
                runner.freecorr_runner_main([
                    "--mode", "resource-probe",
                    "--unit-id", wrong_unit.unit_id,
                    "--attempt-root", root,
                    "--allow-test-root",
                ]; output_io = wrong_output, error_io = wrong_errors)
            end
            @test wrong_code == 4
            @test isempty(String(take!(wrong_output)))
            @test occursin(
                "fixed to the first feasibility unit",
                String(take!(wrong_errors)),
            )
            @test isempty(readdir(root))

            output = IOBuffer()
            errors = IOBuffer()
            code = withenv(runner.FREECORR_TEST_ROOT_ENV => "1") do
                runner.freecorr_runner_main([
                    "--mode", "resource-probe",
                    "--unit-id", unit.unit_id,
                    "--attempt-root", root,
                    "--allow-test-root",
                ]; output_io = output, error_io = errors)
            end
            @test code in (0, 5)
            @test isempty(String(take!(errors)))
            summary = JSON3.read(String(take!(output)))
            @test summary.resource_probe_receipt_persisted
            @test !summary.scientific_execution_receipt
            @test !summary.scientific_attempt_created
            @test !summary.mcmc_executed
            @test !summary.recovery_evidence_available
            @test summary.package_provenance_digests_recomputed_after_json
            @test summary.package_artifact_sha256_recomputed_after_json
            @test summary.initial_gradient_probe_thresholds_passed ===
                summary.profile_thresholds_passed
            @test !summary.operational_execution_authorized
            @test summary.self_consistency_only
            @test !summary.authenticity_attested
            @test !summary.external_anchor_present
            @test !summary.timestamp_attested

            expected_path = runner.freecorr_resource_probe_path(
                root,
                plan,
                unit,
            )
            reservation_path =
                runner.freecorr_resource_probe_reservation_path(
                    root,
                    plan,
                    unit,
                )
            @test normpath(String(summary.path)) == normpath(expected_path)
            @test normpath(String(summary.reservation_path)) ==
                normpath(reservation_path)
            @test isfile(expected_path)
            @test isfile(reservation_path)
            @test basename(expected_path) ==
                "initial_gradient_probe_attempt_001.json"
            @test occursin(
                runner.FREECORR_RESOURCE_PROBE_DIRECTORY,
                expected_path,
            )
            @test !runner.freecorr_path_within(
                expected_path,
                runner.freecorr_unit_root(root, plan, unit),
            )
            @test !ispath(runner.freecorr_unit_root(root, plan, unit))
            @test !ispath(runner.freecorr_attempt_dir(root, plan, unit))

            snapshot = runner.freecorr_read_json_once(
                expected_path,
                "resource-probe test receipt",
            )
            reservation_snapshot = runner.freecorr_read_json_once(
                reservation_path,
                "resource-probe test reservation",
            )
            reservation_validation =
                runner.freecorr_validate_resource_probe_reservation(
                    reservation_snapshot.parsed,
                    plan,
                    unit,
                )
            receipt = runner.freecorr_json_native(snapshot.parsed)
            validation = runner.freecorr_validate_resource_probe_receipt(
                receipt,
                plan,
                unit;
                require_current = true,
            )
            @test validation.validated
            @test validation.source.current_matches
            @test validation.environment.current_matches
            @test validation.package_provenance_digests_recomputed
            @test validation.package_artifact_sha256_recomputed
            @test validation.reservation_file_sha256 ==
                reservation_snapshot.file_sha256
            @test validation.reservation_content_sha256 ==
                reservation_validation.content_sha256
            @test validation.source.aggregate_sha256 ==
                reservation_validation.source_aggregate_sha256
            @test validation.environment.stable_identity_sha256 ==
                reservation_validation.stable_environment_identity_sha256
            @test !validation.scientific_execution_receipt
            @test !validation.mcmc_executed
            @test !validation.recovery_evidence_available
            @test validation.profile_thresholds_passed ===
                summary.profile_thresholds_passed
            @test code == (validation.profile_thresholds_passed ? 0 : 5)
            @test receipt["resource_probe_contract"]["repetitions"] == 3
            @test receipt["resource_probe_contract"][
                "reservation_required_before_measurement"
            ]
            @test receipt["resource_probe_artifact"]["repetitions"] == 3
            @test receipt["resource_probe_artifact"]["execute_measurement"]
            @test length(receipt["resource_probe_artifact"]["measurement"][
                "gradient_profile"
            ]["timed_rows"]) == 3
            @test !receipt["operational_execution_authorized"]
            @test !receipt["scientific_execution_authorized"]
            @test !receipt["scientific_attempt_created"]
            @test !receipt["mcmc_executed"]
            @test !receipt["recovery_evidence_available"]
            @test !receipt["short_nuts_resource_profile_completed"]
            @test !receipt["atomic_scientific_runner_ready"]
            @test receipt["activity"]["resource_probe_attempt"] == 1
            @test receipt["activity"]["fixture_generated"]
            @test receipt["activity"]["gradient_executed"]
            @test !receipt["activity"]["model_fit_run"]
            @test !receipt["activity"]["mcmc_executed"]
            @test !receipt["activity"]["scientific_state_written"]
            @test !receipt["activity"]["recovery_evidence_available"]

            archive_status = runner.freecorr_status_artifact(
                _freecorr_runner_options(
                    runner,
                    root,
                    unit.unit_id;
                    mode = "status",
                ),
                plan,
                unit,
            )
            @test archive_status.status === :archive_state_valid
            @test archive_status.resource_probe_state.state === :valid
            @test archive_status.resource_probe_state.outcome ===
                (validation.profile_thresholds_passed ?
                    :threshold_pass : :threshold_fail)
            @test archive_status.resource_probe_state.attempt_consumed
            @test archive_status.initial_gradient_probe_thresholds_passed ===
                validation.profile_thresholds_passed
            @test !archive_status.operational_execution_authorized

            validation_options = _freecorr_runner_options(
                runner,
                root,
                unit.unit_id;
                mode = "validate",
                artifact = expected_path,
            )
            validation_artifact = runner.freecorr_validate_artifact_path(
                validation_options,
                plan,
                unit,
            )
            @test validation_artifact.status ===
                :resource_probe_receipt_package_native_reconstruction_validated_current_snapshot
            @test validation_artifact.profile_thresholds_passed ===
                validation.profile_thresholds_passed
            @test validation_artifact.package_provenance_digests_recomputed
            @test validation_artifact.package_artifact_sha256_recomputed
            @test !validation_artifact.scientific_execution_receipt
            @test !validation_artifact.mcmc_started_by_this_invocation
            @test !validation_artifact.recovery_evidence_available

            winner_bytes = read(expected_path)
            retry_output = IOBuffer()
            retry_errors = IOBuffer()
            retry_code = withenv(
                    runner.FREECORR_TEST_ROOT_ENV => "1") do
                runner.freecorr_runner_main([
                    "--mode", "resource-probe",
                    "--unit-id", unit.unit_id,
                    "--attempt-root", root,
                    "--allow-test-root",
                ]; output_io = retry_output, error_io = retry_errors)
            end
            @test retry_code == 4
            @test isempty(String(take!(retry_output)))
            @test occursin(
                "immutable resource-probe attempt 001",
                String(take!(retry_errors)),
            )
            @test read(expected_path) == winner_bytes
            @test !ispath(runner.freecorr_unit_root(root, plan, unit))
            @test !ispath(runner.freecorr_attempt_dir(root, plan, unit))

            validate_output = IOBuffer()
            validate_errors = IOBuffer()
            validate_code = withenv(
                    runner.FREECORR_TEST_ROOT_ENV => "1") do
                runner.freecorr_runner_main([
                    "--mode", "validate",
                    "--unit-id", unit.unit_id,
                    "--attempt-root", root,
                    "--allow-test-root",
                    "--artifact", expected_path,
                ]; output_io = validate_output, error_io = validate_errors)
            end
            @test validate_code == 0
            @test isempty(String(take!(validate_errors)))
            @test JSON3.read(String(take!(validate_output))).status ==
                "resource_probe_receipt_package_native_reconstruction_validated_current_snapshot"

            restored = runner.freecorr_validate_resource_probe_payload(
                receipt["resource_probe_artifact"],
                plan,
                unit,
            ).package_native_artifact
            forced_profile = merge(
                restored.measurement.gradient_profile,
                (;
                    free_memory_bytes_before = UInt64(0),
                    free_memory_bytes_after = UInt64(0),
                    minimum_free_memory_bytes_observed = UInt64(0),
                ),
            )
            forced_runtime = merge(
                restored.runtime,
                (;
                    free_memory_bytes_before = UInt64(0),
                    free_memory_bytes_after = UInt64(0),
                    minimum_free_memory_bytes_observed = UInt64(0),
                ),
            )
            forced_provenance = getfield(
                BayesianMGMFRM,
                :_free_correlation_resource_probe_provenance,
            )(forced_runtime)
            forced_measurement = merge(
                restored.measurement,
                (; gradient_profile = forced_profile),
            )
            forced_failure_probe = getfield(
                BayesianMGMFRM,
                :_free_correlation_resource_probe_artifact,
            )(
                plan,
                unit,
                runner.FREECORR_RESOURCE_PROBE_REPETITIONS;
                runtime = forced_runtime,
                provenance = forced_provenance,
                measurement = forced_measurement,
            )
            getfield(
                BayesianMGMFRM,
                :_validate_free_correlation_study_resource_probe,
            )(forced_failure_probe, plan, unit.unit_id)
            @test !forced_failure_probe.profile_thresholds_passed
            @test !forced_failure_probe.checks.free_memory_passed

            mktempdir() do deterministic_root
                deterministic_output = IOBuffer()
                deterministic_errors = IOBuffer()
                deterministic_code = withenv(
                        runner.FREECORR_TEST_ROOT_ENV => "1") do
                    runner.freecorr_runner_main([
                        "--mode", "resource-probe",
                        "--unit-id", unit.unit_id,
                        "--attempt-root", deterministic_root,
                        "--allow-test-root",
                    ];
                        output_io = deterministic_output,
                        error_io = deterministic_errors,
                        measure_probe = (args...) -> forced_failure_probe,
                    )
                end
                @test deterministic_code == 5
                @test isempty(String(take!(deterministic_errors)))
                deterministic_summary = JSON3.read(
                    String(take!(deterministic_output)),
                )
                @test deterministic_summary.resource_probe_receipt_persisted
                @test !deterministic_summary.profile_thresholds_passed
                @test !deterministic_summary.
                    initial_gradient_probe_thresholds_passed
                @test !deterministic_summary.operational_execution_authorized
                @test isfile(runner.freecorr_resource_probe_reservation_path(
                    deterministic_root,
                    plan,
                    unit,
                ))
                @test isfile(runner.freecorr_resource_probe_path(
                    deterministic_root,
                    plan,
                    unit,
                ))
                deterministic_status = runner.
                    freecorr_resource_probe_archive_status(
                        _freecorr_runner_options(
                            runner,
                            deterministic_root,
                            unit.unit_id,
                        ),
                        plan,
                    )
                @test deterministic_status.state === :valid
                @test deterministic_status.outcome === :threshold_fail
                @test !deterministic_status.
                    initial_gradient_probe_thresholds_passed
            end

            provenance_tampered = deepcopy(receipt)
            provenance_sources = provenance_tampered[
                "resource_probe_artifact"
            ]["provenance"]["sources"]
            provenance_sources[1]["sha256"] = repeat("0", 64)
            provenance_tampered["resource_probe_json_sha256"] =
                runner.freecorr_canonical_sha256(
                    provenance_tampered["resource_probe_artifact"],
                )
            _freecorr_runner_rehash!(runner, provenance_tampered)
            provenance_error = try
                runner.freecorr_validate_resource_probe_receipt(
                    provenance_tampered,
                    plan,
                    unit;
                    require_current = false,
                )
                nothing
            catch error
                error
            end
            @test provenance_error isa Exception
            @test occursin(
                "provenance digests were modified",
                sprint(showerror, provenance_error),
            )

            artifact_hash_tampered = deepcopy(receipt)
            embedded_hash = artifact_hash_tampered[
                "resource_probe_artifact"
            ]["artifact_sha256"]
            artifact_hash_tampered[
                "resource_probe_artifact"
            ]["artifact_sha256"] = string(
                first(embedded_hash) == '0' ? '1' : '0',
                embedded_hash[2:end],
            )
            artifact_hash_tampered["resource_probe_artifact_sha256"] =
                artifact_hash_tampered[
                    "resource_probe_artifact"
                ]["artifact_sha256"]
            artifact_hash_tampered["resource_probe_json_sha256"] =
                runner.freecorr_canonical_sha256(
                    artifact_hash_tampered["resource_probe_artifact"],
                )
            _freecorr_runner_rehash!(runner, artifact_hash_tampered)
            @test_throws ErrorException runner.
                freecorr_validate_resource_probe_receipt(
                    artifact_hash_tampered,
                    plan,
                    unit;
                    require_current = false,
                )

            tampered = deepcopy(receipt)
            checks = tampered["resource_probe_artifact"]["checks"]
            checks["free_memory_passed"] = !checks["free_memory_passed"]
            tampered["resource_probe_json_sha256"] =
                runner.freecorr_canonical_sha256(
                    tampered["resource_probe_artifact"],
                )
            _freecorr_runner_rehash!(runner, tampered)
            @test_throws ErrorException runner.
                freecorr_validate_resource_probe_receipt(
                    tampered,
                    plan,
                    unit;
                    require_current = false,
                )
            write(
                expected_path,
                runner.freecorr_encode_json_bytes(tampered),
            )
            tamper_output = IOBuffer()
            tamper_errors = IOBuffer()
            tamper_code = withenv(
                    runner.FREECORR_TEST_ROOT_ENV => "1") do
                runner.freecorr_runner_main([
                    "--mode", "validate",
                    "--unit-id", unit.unit_id,
                    "--attempt-root", root,
                    "--allow-test-root",
                    "--artifact", expected_path,
                ]; output_io = tamper_output, error_io = tamper_errors)
            end
            @test tamper_code == 4
            @test isempty(String(take!(tamper_output)))
            @test occursin(
                "complete valid reservation/terminal tree",
                String(take!(tamper_errors)),
            )

            status_output = IOBuffer()
            status_errors = IOBuffer()
            status_code = withenv(
                    runner.FREECORR_TEST_ROOT_ENV => "1") do
                runner.freecorr_runner_main([
                    "--mode", "status",
                    "--unit-id", unit.unit_id,
                    "--attempt-root", root,
                    "--allow-test-root",
                ]; output_io = status_output, error_io = status_errors)
            end
            @test status_code == 0
            @test isempty(String(take!(status_errors)))
            tampered_status = JSON3.read(String(take!(status_output)))
            @test tampered_status.status == "archive_state_invalid"
            @test tampered_status.resource_probe_state.state == "invalid"

            archive_validate_output = IOBuffer()
            archive_validate_errors = IOBuffer()
            archive_validate_code = withenv(
                    runner.FREECORR_TEST_ROOT_ENV => "1") do
                runner.freecorr_runner_main([
                    "--mode", "validate",
                    "--unit-id", unit.unit_id,
                    "--attempt-root", root,
                    "--allow-test-root",
                ];
                    output_io = archive_validate_output,
                    error_io = archive_validate_errors,
                )
            end
            @test archive_validate_code == 4
            @test isempty(String(take!(archive_validate_errors)))
            @test JSON3.read(
                String(take!(archive_validate_output)),
            ).status == "archive_state_invalid"
            @test !ispath(runner.freecorr_unit_root(root, plan, unit))
            @test !ispath(runner.freecorr_attempt_dir(root, plan, unit))
        end
    end

    @testset "hardlink CREATE_NEW publication is fail-closed" begin
        mktempdir() do root
            boundary = normpath(tempdir())
            staging = joinpath(root, "staging")
            artifact = _freecorr_simple_artifact(runner, "atomic")
            publish = target -> runner.freecorr_atomic_publish_json(
                target,
                artifact,
                staging,
                boundary;
                semantic_validator = value ->
                    _freecorr_generic_validator(runner, value),
            )

            target = joinpath(root, "targets", "winner.json")
            first_result = publish(target)
            winner_bytes = read(target)
            @test first_result.publication === :hardlink_create_new
            @test_throws ErrorException publish(target)
            @test read(target) == winner_bytes

            file_target = joinpath(root, "targets", "existing-file.json")
            write(file_target, "sentinel")
            @test_throws ErrorException publish(file_target)
            @test read(file_target, String) == "sentinel"

            directory_target = joinpath(root, "targets", "existing-directory")
            mkpath(directory_target)
            @test_throws ErrorException publish(directory_target)
            @test isdir(directory_target)

            link_target = joinpath(root, "targets", "dangling-link.json")
            link_capability = _freecorr_test_symlink(
                joinpath(root, "missing-target.json"),
                link_target;
                dir_target = false,
            )
            if link_capability.available
                @test islink(link_target)
                @test_throws ErrorException publish(link_target)
                @test islink(link_target)
            else
                @test !link_capability.available
                @test Sys.iswindows()
                @test link_capability.reason === :windows_symlink_privilege
                @test link_capability.code in (Base.UV_EPERM, Base.UV_EACCES)
            end

            real_parent = joinpath(root, "real-parent")
            mkpath(real_parent)
            linked_parent = joinpath(root, "linked-parent")
            parent_link_capability = _freecorr_test_symlink(
                real_parent,
                linked_parent;
                dir_target = true,
            )
            if parent_link_capability.available
                @test_throws ErrorException publish(joinpath(
                    linked_parent,
                    "through-link.json",
                ))
            else
                @test !parent_link_capability.available
                @test Sys.iswindows()
                @test parent_link_capability.reason ===
                    :windows_symlink_privilege
                @test parent_link_capability.code in
                    (Base.UV_EPERM, Base.UV_EACCES)
            end

            concurrent_target = joinpath(root, "targets", "concurrent.json")
            tasks = [Threads.@spawn begin
                try
                    publish(concurrent_target)
                    :published
                catch
                    :blocked
                end
            end for _ in 1:2]
            outcomes = fetch.(tasks)
            @test count(==(:published), outcomes) == 1
            @test count(==(:blocked), outcomes) == 1
            @test isfile(concurrent_target)

            postfailure_target = joinpath(
                root,
                "targets",
                "postvalidation-failure.json",
            )
            validator_calls = Ref(0)
            postfailure_validator = value -> begin
                _freecorr_generic_validator(runner, value)
                validator_calls[] += 1
                validator_calls[] == 2 && error(
                    "intentional post-publication validation failure",
                )
                true
            end
            @test_throws ErrorException runner.freecorr_atomic_publish_json(
                postfailure_target,
                artifact,
                staging,
                boundary;
                semantic_validator = postfailure_validator,
            )
            @test validator_calls[] == 2
            @test isfile(postfailure_target)
            @test runner.freecorr_archive_contract().
                postpublish_validation_failure_target_disposition ===
                :left_in_place_for_forensic_review
            @test runner.freecorr_archive_contract().
                remaining_toctou_risk ===
                :path_and_leaf_races_without_handle_relative_io

            long_parent = joinpath(
                root,
                repeat("long-a", 16),
                repeat("long-b", 16),
                repeat("long-c", 16),
            )
            long_target = joinpath(long_parent, "long-path-target.json")
            if Sys.iswindows()
                @test length(abspath(long_target)) > 260
            end
            long_result = publish(long_target)
            @test long_result.publication === :hardlink_create_new
            @test isfile(long_target)
        end
    end

    @testset "scientific attempt material is never interpreted" begin
        mktempdir() do root
            options = _freecorr_runner_options(
                runner,
                root,
                unit.unit_id,
            )
            absent = runner.freecorr_attempt_status(options, plan, unit)
            @test absent.state === :absent
            @test absent.archive_integrity_passed
            clean_status = runner.freecorr_status_artifact(
                options,
                plan,
                unit,
            )
            @test clean_status.self_consistency_only
            @test !clean_status.authenticity_attested
            @test !clean_status.external_anchor_present
            @test !clean_status.timestamp_attested
            @test clean_status.workspace_filesystem.inspection_passed
            @test clean_status.workspace_filesystem.permitted

            mkpath(runner.freecorr_unit_root(root, plan, unit))
            unsupported = runner.freecorr_attempt_status(options, plan, unit)
            @test unsupported.state ===
                runner.FREECORR_UNSUPPORTED_SCIENTIFIC_STATE
            @test unsupported.disposition ===
                :unsupported_scientific_attempt_for_preexecution_runner_v1
            @test !unsupported.archive_integrity_passed
            @test unsupported.details.unit_path_present
            @test !unsupported.details.child_paths_inspected
            @test !unsupported.details.contents_interpreted

            output = IOBuffer()
            errors = IOBuffer()
            status_code = withenv(runner.FREECORR_TEST_ROOT_ENV => "1") do
                runner.freecorr_runner_main([
                    "--mode", "status",
                    "--unit-id", unit.unit_id,
                    "--attempt-root", root,
                    "--allow-test-root",
                ]; output_io = output, error_io = errors)
            end
            @test status_code == 0
            @test JSON3.read(String(take!(output))).status ==
                "archive_state_invalid"
            @test isempty(String(take!(errors)))

            output = IOBuffer()
            errors = IOBuffer()
            validate_code = withenv(runner.FREECORR_TEST_ROOT_ENV => "1") do
                runner.freecorr_runner_main([
                    "--mode", "validate",
                    "--unit-id", unit.unit_id,
                    "--attempt-root", root,
                    "--allow-test-root",
                ]; output_io = output, error_io = errors)
            end
            @test validate_code == 4
            @test JSON3.read(String(take!(output))).state.disposition ==
                "unsupported_scientific_attempt_for_preexecution_runner_v1"
            @test isempty(String(take!(errors)))
        end

        mktempdir() do root
            options = _freecorr_runner_options(
                runner,
                root,
                unit.unit_id,
            )
            attempt = runner.freecorr_attempt_dir(root, plan, unit)
            mkpath(attempt)
            write(joinpath(attempt, "started.json"),
                "this is deliberately not JSON and must not be read")
            unsupported = runner.freecorr_attempt_status(options, plan, unit)
            @test unsupported.state ===
                :unsupported_scientific_attempt_for_preexecution_runner_v1
            @test !unsupported.details.child_paths_inspected
            @test !unsupported.details.contents_interpreted
        end

        mktempdir() do root
            options = _freecorr_runner_options(
                runner,
                root,
                unit.unit_id,
            )
            unit_path = runner.freecorr_unit_root(root, plan, unit)
            mkpath(dirname(unit_path))
            write(unit_path, "occupied by a regular file")
            unsupported = runner.freecorr_attempt_status(options, plan, unit)
            @test unsupported.state ===
                :unsupported_scientific_attempt_for_preexecution_runner_v1
            @test !unsupported.details.contents_interpreted
        end

        mktempdir() do root
            options = _freecorr_runner_options(
                runner,
                root,
                unit.unit_id,
            )
            write(joinpath(root, plan.plan_id),
                "regular file where a parent directory is required")
            security_invalid = runner.freecorr_attempt_status(
                options,
                plan,
                unit,
            )
            @test security_invalid.state === :archive_security_invalid
            @test !security_invalid.archive_integrity_passed
            @test security_invalid.disposition ===
                :scientific_parent_chain_security_validation_failed
        end

        mktempdir() do root
            options = _freecorr_runner_options(
                runner,
                root,
                unit.unit_id,
            )
            real_parent = joinpath(root, "real-plan-parent")
            mkpath(real_parent)
            linked_plan = joinpath(root, plan.plan_id)
            link_capability = _freecorr_test_symlink(
                real_parent,
                linked_plan;
                dir_target = true,
            )
            if link_capability.available
                security_invalid = runner.freecorr_attempt_status(
                    options,
                    plan,
                    unit,
                )
                @test security_invalid.state === :archive_security_invalid
                @test security_invalid.disposition ===
                    :scientific_parent_chain_security_validation_failed
            else
                @test !link_capability.available
                @test Sys.iswindows()
                @test link_capability.reason === :windows_symlink_privilege
                @test link_capability.code in (Base.UV_EPERM, Base.UV_EACCES)
            end
        end

        mktempdir() do root
            options = _freecorr_runner_options(
                runner,
                root,
                unit.unit_id,
            )
            unit_path = runner.freecorr_unit_root(root, plan, unit)
            mkpath(dirname(unit_path))
            final_link_capability = _freecorr_test_symlink(
                joinpath(root, "missing-unit-target"),
                unit_path;
                dir_target = true,
            )
            if final_link_capability.available
                security_invalid = runner.freecorr_attempt_status(
                    options,
                    plan,
                    unit,
                )
                @test security_invalid.state === :archive_security_invalid
                @test security_invalid.disposition ===
                    :scientific_unit_root_link_forbidden
                @test !security_invalid.details.child_paths_inspected
                @test !security_invalid.details.contents_interpreted
            else
                @test !final_link_capability.available
                @test Sys.iswindows()
                @test final_link_capability.reason ===
                    :windows_symlink_privilege
                @test final_link_capability.code in
                    (Base.UV_EPERM, Base.UV_EACCES)
            end
        end
    end

    @testset "execute-primary always blocks without writes" begin
        mktempdir() do root
            for confirmation in (false, true)
                output = IOBuffer()
                errors = IOBuffer()
                args = [
                    "--mode", "execute-primary",
                    "--unit-id", unit.unit_id,
                    "--attempt-root", root,
                    "--allow-test-root",
                ]
                confirmation && push!(args, "--confirm-scientific-mcmc")
                code = withenv(runner.FREECORR_TEST_ROOT_ENV => "1") do
                    runner.freecorr_runner_main(
                        args;
                        output_io = output,
                        error_io = errors,
                    )
                end
                @test code == 3
                @test isempty(String(take!(errors)))
                blocked = JSON3.read(String(take!(output)))
                @test blocked.confirmation_present === confirmation
                @test blocked.status ==
                    "scientific_execution_blocked_pending_resource_profile"
                @test blocked.protocol_execution_authorized
                @test !blocked.operational_execution_authorized
                @test !blocked.execution_authorized
                @test !blocked.archive_runner_execution_authorized
                @test !blocked.attempt_reserved
                @test !blocked.archive_tree_modified
                @test !blocked.fixture_generated
                @test !blocked.response_data_generated
                @test !blocked.model_fit_run
                @test !blocked.mcmc_executed
                @test isempty(readdir(root))
                @test !ispath(runner.freecorr_execution_root(root, plan))
            end
        end
    end
end
