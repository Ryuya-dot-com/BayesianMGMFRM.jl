using JSON3
using SHA
using Test

const LD1B1_BOUNDED_SMOKE_TEST_ROOT = normpath(joinpath(@__DIR__, ".."))

module LD1B1BoundedCanonicalSmokeRunnerForTest

include(joinpath(@__DIR__, "..", "scripts",
    "run_local_dependence_calibration_pilot_batch.jl"))

end

const LD1B1BoundedSmokeRunner =
    LD1B1BoundedCanonicalSmokeRunnerForTest

function ld1b1_bounded_smoke_test_checked()
    runner = LD1B1BoundedSmokeRunner
    protocol_path = runner.LD1B1_DEFAULT_PROTOCOL
    protocol = JSON3.read(read(protocol_path, String))
    runner.ld1b1_validate_frozen_pilot_contract(protocol)
    protocol_content_hash = runner.ld1b1_verify_content_hash(
        protocol; label = "bounded-smoke test protocol")
    protocol_file_sha256 = runner.ld1b1_file_sha256(protocol_path)
    preflight = protocol[:pilot_preflight]
    jobs = collect(preflight[:job_rows])
    job_ids = runner.ld1b1_job_id.(jobs)
    ordered_job_rows_sha256 = runner.ld1b1_canonical_sha256(
        runner.ld1b1_json_native(preflight[:job_rows]))
    pilot_contract_sha256 = runner.ld1b1_canonical_sha256(
        runner.ld1b1_json_native(protocol[:pilot_contract]))
    source_identity = runner.ld1b1_source_identity(protocol)
    canonical_executor_source_pin_id = runner.ld1b1_require_sha256(
        protocol[:canonical_executor_source_pin][:pin_id][:value],
        "bounded-smoke test canonical executor source-pin id",
    )
    protocol_plan_material = (;
        protocol_file_sha256,
        protocol_content_hash,
        ordered_job_rows_sha256,
        pilot_contract_sha256,
        canonical_executor_source_pin_id,
        project_toml_sha256 = source_identity.project_toml_sha256,
        manifest_toml = source_identity.manifest_toml,
        manifest_toml_sha256 = source_identity.manifest_toml_sha256,
        source_rows = source_identity.source_rows,
    )
    protocol_plan_id = runner.ld1b1_canonical_sha256(protocol_plan_material)
    execution_source_identity = (;
        batch_runner_source_sha256 = runner.ld1b1_file_sha256(joinpath(
            LD1B1_BOUNDED_SMOKE_TEST_ROOT,
            "scripts",
            "run_local_dependence_calibration_pilot_batch.jl",
        )),
        local_json_source_sha256 = runner.ld1b1_file_sha256(joinpath(
            LD1B1_BOUNDED_SMOKE_TEST_ROOT,
            "scripts",
            "local_json.jl",
        )),
        job_runner_source_sha256 = runner.ld1b1_file_sha256(
            runner.LD1B1_DEFAULT_JOB_RUNNER),
        attempt_archive_source_sha256 = runner.LD1B1AttemptArchive.
            ld1b_attempt_archive_source_sha256(),
        local_dependence_pilot_recovery_source_sha256 =
            runner.LD1B1Recovery.ld1b_recovery_source_sha256(),
        local_dependence_pilot_calibration_semantics_source_sha256 =
            runner.ld1b1_file_sha256(joinpath(
                LD1B1_BOUNDED_SMOKE_TEST_ROOT,
                "scripts",
                "local_dependence_pilot_calibration_semantics.jl",
            )),
    )
    plan_id = runner.ld1b1_canonical_sha256((;
        protocol_plan_id,
        execution_source_identity,
    ))
    identity = merge(protocol_plan_material, (;
        protocol_plan_id,
        execution_source_identity,
        plan_id,
    ))
    calibration_semantic_context = runner.LD1B1CalibrationSemantics.
        ld1b1_load_calibration_semantic_context(protocol_path)
    return (;
        protocol,
        preflight,
        jobs,
        job_ids,
        identity,
        calibration_semantic_context,
    )
end

function ld1b1_bounded_smoke_test_error(f)
    try
        f()
        return nothing
    catch err
        return err
    end
end

function ld1b1_bounded_smoke_test_write(path::AbstractString, artifact)
    return LD1B1BoundedSmokeRunner.ld1b1_atomic_write_artifact(
        path, artifact; overwrite = false)
end

function ld1b1_bounded_smoke_test_rehash(artifact; replacements...)
    runner = LD1B1BoundedSmokeRunner
    names = Tuple(name for name in propertynames(artifact)
        if name !== :content_hash)
    material = NamedTuple{names}(Tuple(
        getproperty(artifact, name) for name in names))
    return runner.ld1b1_with_content_hash(
        merge(material, (; replacements...)))
end

function ld1b1_bounded_smoke_test_failure_evidence(
        identity, job, execution_context)
    runner = LD1B1BoundedSmokeRunner
    member_sha256 = repeat("d", 64)
    payload = (;
        failure_content_sha256 = member_sha256,
        failure_stage = :generation,
        error_class = "BoundedSmokeTestGenerationFailure",
        failure_recorded = true,
    )
    member = (;
        role = :generation_failure_record,
        path = "members/generation_failure.json",
        media_type = :application_json,
        bytes = 2,
        sha256 = member_sha256,
    )
    return runner.ld1b1_evidence_envelope(
        identity,
        job,
        1,
        :generation_failed,
        :generation_failure_record,
        payload;
        member,
        dependencies = (),
        runner_source_sha256 =
            identity.execution_source_identity.job_runner_source_sha256,
        execution_context,
    )
end

function ld1b1_bounded_smoke_test_validate_evidence(
        path::AbstractString, identity, job, execution_context)
    runner = LD1B1BoundedSmokeRunner
    return runner.ld1b1_validate_evidence_file(
        path,
        identity,
        job,
        1,
        :generation_failed,
        :generation_failure_record,
        dirname(path),
        filesize(path),
        runner.ld1b1_file_sha256(path);
        execution_context,
    )
end

function ld1b1_bounded_smoke_test_prepare_child(
        root::AbstractString, smoke_identity, job, run_id::AbstractString)
    runner = LD1B1BoundedSmokeRunner
    smoke_context = runner.ld1b1_execution_context(:bounded_smoke)
    smoke_root = joinpath(root, "local_dependence_pilot_bounded_smoke_v1")
    execution_root = runner.ld1b1_bounded_smoke_execution_root(
        smoke_root, smoke_identity.plan_id)
    setup = runner.ld1b1_publish_attempt_reservation_create_new(
        execution_root,
        smoke_identity,
        job,
        1,
        run_id;
        execution_context = smoke_context,
    )
    mkpath(dirname(setup.lineage.attempt_dir))
    mkdir(setup.lineage.attempt_dir)
    owner = runner.ld1b1_publish_canonical_owner_create_new(
        setup.lineage, execution_root)
    return (; execution_root, setup, owner)
end

function ld1b1_bounded_smoke_test_child(code::AbstractString, args...)
    return String[
        Base.julia_cmd().exec[1],
        "--startup-file=no",
        "--history-file=no",
        "-O0",
        "-e",
        String(code),
        String.(args)...,
    ]
end

@testset "LD1b1 bounded canonical smoke" begin
    runner = LD1B1BoundedSmokeRunner
    checked = ld1b1_bounded_smoke_test_checked()
    specs = runner.ld1b1_job_specs(checked)
    job = runner.ld1b1_bounded_smoke_job(specs)
    derived = runner.ld1b1_bounded_smoke_identity(checked.identity, job)
    pilot_context = runner.ld1b1_execution_context(:pilot)
    smoke_context = runner.ld1b1_execution_context(:bounded_smoke)

    @testset "exact row 5, contract, and derived plan" begin
        @test length(specs) == runner.LD1B1_EXPECTED_JOBS
        @test job.row_index == 5
        @test job.job_id ==
            "ld1b1_pilot__rep01__s05__null_support_at_minimum"
        @test job.scenario_index == 5
        @test job.scenario_id === :null_support_at_minimum
        @test job.matched_set_id === :pair_support_boundary
        @test job.replication == 1
        @test job.seed == 30_260_720
        @test job.fit_seed == 200_128_656_464_948_117
        @test job.draw_selection_seed == 1_112_135_171_630_182_159
        @test job.posterior_predictive_seed ==
            5_104_868_204_648_614_505
        @test job.expected_action === :fit_and_score_diagnostic
        @test job.expected_structural_eligibility
        @test job.resources == (;
            n_ratings = 240,
            n_probability_cells = 960,
            n_truth_cells = 6_376,
        )

        contract = derived.contract
        @test Set(propertynames(contract)) == Set((
            :schema,
            :scope,
            :execution_context,
            :canonical_parent_plan_id,
            :canonical_executor_source_pin_id,
            :job,
            :sampler_contract,
            :quality_contract,
            :bounds,
            :restrictions,
        ))
        @test contract.schema ==
            "bayesianmgmfrm.local_dependence_pilot_bounded_smoke_contract.v1"
        @test contract.scope === :verification_only_nonpilot
        @test contract.execution_context == smoke_context
        @test contract.canonical_parent_plan_id == checked.identity.plan_id
        @test contract.canonical_executor_source_pin_id == checked.identity.
            canonical_executor_source_pin_id
        @test contract.job == merge(
            runner.ld1b1_result_job_identity(job), (; resources = job.resources))
        @test contract.sampler_contract == job.sampler_contract
        @test contract.quality_contract == job.quality_contract
        @test contract.bounds == (;
            max_jobs = 1,
            timeout_seconds = runner.LD1B1_BOUNDED_SMOKE_TIMEOUT_SECONDS,
            termination_grace_seconds =
                runner.LD1B1_BOUNDED_SMOKE_TERMINATION_GRACE_SECONDS,
            max_rss_bytes = runner.LD1B1_BOUNDED_SMOKE_MAX_RSS_BYTES,
            max_archive_bytes =
                runner.LD1B1_BOUNDED_SMOKE_MAX_ARCHIVE_BYTES,
            maximum_child_processes = 1,
        )
        @test contract.restrictions == (;
            attempt = 1,
            attempt_role = :verification,
            retries_allowed = false,
            resume_allowed = false,
            sampler_overrides_allowed = false,
            seed_overrides_allowed = false,
            canonical_pilot_root_writes_allowed = false,
            official_pilot_denominator_eligible = false,
            scientific_contribution = 0,
        )
        expected_smoke_plan_id = runner.ld1b1_canonical_sha256((;
            domain = :ld1b1_bounded_canonical_smoke_plan_v1,
            parent_plan_identity =
                runner.ld1b1_result_plan_identity(checked.identity),
            execution_source_identity =
                checked.identity.execution_source_identity,
            contract,
        ))
        @test derived.smoke_plan_id == expected_smoke_plan_id
        @test derived.identity.plan_id == expected_smoke_plan_id
        @test derived.identity.parent_plan_id == checked.identity.plan_id
        @test derived.identity.bounded_smoke_contract == contract
        @test derived.identity.plan_id != checked.identity.plan_id
        @test runner.ld1b1_attempt_identity(1, smoke_context) == (;
            number = 1,
            role = :verification,
            counts_toward_primary = false,
        )
        @test_throws Exception runner.ld1b1_bounded_smoke_contract(
            checked.identity, merge(job, (; row_index = 6)))
    end

    @testset "authorization is create-new, exact, and tamper evident" begin
        mktempdir() do smoke_root
            authorization = runner.ld1b1_bounded_smoke_authorization(
                checked.identity, derived.identity, job, smoke_root)
            path = runner.ld1b1_bounded_smoke_authorization_path(
                smoke_root, derived.smoke_plan_id)
            ld1b1_bounded_smoke_test_write(path, authorization)
            validated = runner.ld1b1_validate_bounded_smoke_authorization(
                path,
                checked.identity,
                derived.identity,
                job,
                smoke_root,
            )
            @test validated.valid
            @test validated.content_hash == authorization.content_hash.value
            @test validated.artifact[:execution_context][
                :root_namespace] == "local_dependence_pilot_bounded_smoke_v1"
            @test !validated.artifact[:evidence_boundary][
                :bounded_smoke_passed]
            @test_throws Exception ld1b1_bounded_smoke_test_write(
                path, authorization)
        end

        mktempdir() do smoke_root
            authorization = runner.ld1b1_bounded_smoke_authorization(
                checked.identity, derived.identity, job, smoke_root)
            tampered = ld1b1_bounded_smoke_test_rehash(
                authorization;
                path_contract = merge(authorization.path_contract, (;
                    root_namespace = :local_dependence_pilot,
                )),
            )
            path = runner.ld1b1_bounded_smoke_authorization_path(
                smoke_root, derived.smoke_plan_id)
            ld1b1_bounded_smoke_test_write(path, tampered)
            @test_throws Exception runner.
                ld1b1_validate_bounded_smoke_authorization(
                    path,
                    checked.identity,
                    derived.identity,
                    job,
                    smoke_root,
                )
        end
    end

    @testset "pilot and smoke result/evidence contexts cannot cross" begin
        smoke_result = runner.ld1b1_result_envelope(
            derived.identity,
            job,
            1,
            :generation_failed;
            file_manifest = (),
            runner_source_sha256 = derived.identity.
                execution_source_identity.job_runner_source_sha256,
            execution_context = smoke_context,
        )
        pilot_result = runner.ld1b1_result_envelope(
            checked.identity,
            job,
            1,
            :generation_failed;
            file_manifest = (),
            runner_source_sha256 = checked.identity.
                execution_source_identity.job_runner_source_sha256,
            execution_context = pilot_context,
        )
        @test smoke_result.scope === :ld1b1_bounded_smoke_job_result
        @test smoke_result.attempt.role === :verification
        @test smoke_result.attempt.counts_toward_primary === false
        @test pilot_result.scope === :ld1b1_pilot_job_result
        @test pilot_result.attempt.role === :primary
        @test pilot_result.attempt.counts_toward_primary === true

        mktempdir() do root
            path = runner.ld1b1_result_path(
                joinpath(root, "smoke_execution"), job.job_id, 1)
            ld1b1_bounded_smoke_test_write(path, smoke_result)
            err = ld1b1_bounded_smoke_test_error() do
                runner.ld1b1_validate_result(
                    path,
                    derived.identity,
                    job,
                    1;
                    calibration_semantic_context =
                        checked.calibration_semantic_context,
                    execution_context = pilot_context,
                )
            end
            @test err isa Exception
            @test occursin("execution context", lowercase(sprint(showerror, err)))
        end

        mktempdir() do root
            path = runner.ld1b1_result_path(
                joinpath(root, "pilot_execution"), job.job_id, 1)
            ld1b1_bounded_smoke_test_write(path, pilot_result)
            err = ld1b1_bounded_smoke_test_error() do
                runner.ld1b1_validate_result(
                    path,
                    checked.identity,
                    job,
                    1;
                    calibration_semantic_context =
                        checked.calibration_semantic_context,
                    execution_context = smoke_context,
                )
            end
            @test err isa Exception
            @test occursin("execution context", lowercase(sprint(showerror, err)))
        end

        smoke_evidence = ld1b1_bounded_smoke_test_failure_evidence(
            derived.identity, job, smoke_context)
        pilot_evidence = ld1b1_bounded_smoke_test_failure_evidence(
            checked.identity, job, pilot_context)
        @test smoke_evidence.scope === :ld1b1_bounded_smoke_job_evidence
        @test smoke_evidence.attempt.role === :verification
        @test smoke_evidence.attempt.counts_toward_primary === false
        @test pilot_evidence.scope === :ld1b1_pilot_job_evidence
        @test pilot_evidence.attempt.role === :primary
        @test pilot_evidence.attempt.counts_toward_primary === true

        mktempdir() do root
            smoke_path = joinpath(root, "smoke", "generation_failure.json")
            ld1b1_bounded_smoke_test_write(smoke_path, smoke_evidence)
            @test ld1b1_bounded_smoke_test_validate_evidence(
                smoke_path,
                derived.identity,
                job,
                smoke_context,
            ).content_hash == smoke_evidence.content_hash.value
            err = ld1b1_bounded_smoke_test_error() do
                ld1b1_bounded_smoke_test_validate_evidence(
                    smoke_path,
                    derived.identity,
                    job,
                    pilot_context,
                )
            end
            @test err isa Exception
            @test occursin("execution context", lowercase(sprint(showerror, err)))

            pilot_path = joinpath(root, "pilot", "generation_failure.json")
            ld1b1_bounded_smoke_test_write(pilot_path, pilot_evidence)
            @test ld1b1_bounded_smoke_test_validate_evidence(
                pilot_path,
                checked.identity,
                job,
                pilot_context,
            ).content_hash == pilot_evidence.content_hash.value
            err = ld1b1_bounded_smoke_test_error() do
                ld1b1_bounded_smoke_test_validate_evidence(
                    pilot_path,
                    checked.identity,
                    job,
                    smoke_context,
                )
            end
            @test err isa Exception
            @test occursin("execution context", lowercase(sprint(showerror, err)))
        end
    end

    @testset "normal readiness remains blocked without a smoke receipt" begin
        readiness = runner.ld1b1_execution_readiness(;
            protocol_execution_authorized = true,
            job_runner_path = runner.LD1B1_DEFAULT_JOB_RUNNER,
            attempt_root = runner.LD1B1_DEFAULT_ATTEMPT_ROOT,
            canonical_executor_source_pin_validated = true,
            bounded_canonical_smoke_passed = false,
            completed_attempt_archive_seal_supported = true,
            interrupted_attempt_recovery_review_passed = true,
        )
        @test readiness.canonical_executor_source_pinned
        @test readiness.canonical_execution_root_bound
        @test !readiness.bounded_canonical_smoke_passed
        @test !readiness.operational_execution_authorized
        @test readiness.blockers == (:bounded_canonical_smoke_passed,)
    end

    @testset "bounded child fails closed on time, archive, and RSS" begin
        mktempdir() do root
            fixture = ld1b1_bounded_smoke_test_prepare_child(
                root, derived.identity, job, "bounded_timeout")
            watch = joinpath(root, "timeout_watch")
            mkpath(watch)
            result = runner.ld1b1_run_command_with_controller_receipts(
                ld1b1_bounded_smoke_test_child("sleep(3)"),
                joinpath(root, "logs", "timeout.log"),
                fixture.setup.lineage,
                fixture.owner.owner,
                fixture.execution_root;
                timeout_seconds = 0.2,
                termination_grace_seconds = 0.2,
                max_rss_bytes = 1 << 40,
                max_archive_bytes = 1 << 30,
                monitored_archive_root = watch,
                poll_seconds = 0.02,
                rss_observer = _ -> 0,
            )
            @test !result.ok
            @test result.subprocess_started
            @test result.timed_out
            @test result.resource_limit_code === :wall_time_cap_exceeded
            @test result.launch_publication !== nothing
            @test result.exit_publication !== nothing
        end

        mktempdir() do root
            fixture = ld1b1_bounded_smoke_test_prepare_child(
                root, derived.identity, job, "bounded_archive")
            watch = joinpath(root, "archive_watch")
            mkpath(watch)
            payload_path = joinpath(watch, "oversized.bin")
            code = "open(ARGS[1], \"w\") do io; " *
                "write(io, fill(UInt8(0x61), 4096)); end; sleep(3)"
            result = runner.ld1b1_run_command_with_controller_receipts(
                ld1b1_bounded_smoke_test_child(code, payload_path),
                joinpath(root, "logs", "archive.log"),
                fixture.setup.lineage,
                fixture.owner.owner,
                fixture.execution_root;
                timeout_seconds = 5.0,
                termination_grace_seconds = 0.2,
                max_rss_bytes = 1 << 40,
                max_archive_bytes = 1_024,
                monitored_archive_root = watch,
                poll_seconds = 0.02,
                rss_observer = _ -> 0,
            )
            @test !result.ok
            @test result.resource_limit_exceeded
            @test result.resource_limit_code === :archive_cap_exceeded
            @test result.peak_archive_bytes > 1_024
            @test result.exit_publication !== nothing
        end

        mktempdir() do root
            fixture = ld1b1_bounded_smoke_test_prepare_child(
                root, derived.identity, job, "bounded_rss")
            watch = joinpath(root, "rss_watch")
            mkpath(watch)
            result = runner.ld1b1_run_command_with_controller_receipts(
                ld1b1_bounded_smoke_test_child("sleep(3)"),
                joinpath(root, "logs", "rss.log"),
                fixture.setup.lineage,
                fixture.owner.owner,
                fixture.execution_root;
                timeout_seconds = 5.0,
                termination_grace_seconds = 0.2,
                max_rss_bytes = 1,
                max_archive_bytes = 1 << 30,
                monitored_archive_root = watch,
                poll_seconds = 0.02,
                rss_observer = _ -> 2,
            )
            @test !result.ok
            @test result.resource_limit_exceeded
            @test result.resource_limit_code === :rss_cap_exceeded
            @test result.peak_rss_bytes > 1
            @test result.exit_publication !== nothing
        end
    end
end
