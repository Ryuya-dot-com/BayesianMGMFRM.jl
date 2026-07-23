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
        @test occursin("never interprets or creates scientific attempt state", usage)
        @test !occursin(r"(?m)^\s+--all(?:\s|$)", usage)

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
                "\"JULIA_LOAD_PATH\" => \"@:@stdlib\"",
                runtests_text,
            )
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
            @test !status.staging_orphans_are_status_inputs
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
                repeat("long-a", 12),
                repeat("long-b", 12),
                repeat("long-c", 12),
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
