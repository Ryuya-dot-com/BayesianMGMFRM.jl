using BayesianMGMFRM
using JSON3
using SHA
using Test

module CurrentPilotContractGuardForTest
include(joinpath(@__DIR__, "..", "scripts", "run_local_dependence_calibration_pilot_batch.jl"))
end

function check_pilot_diagnostic_dependency(archived_protocol)
    guard = CurrentPilotContractGuardForTest
    contract = BayesianMGMFRM.local_dependence_calibration_pilot_contract()
    live = JSON3.read(JSON3.write(contract))
    recorded = archived_protocol.pilot_contract
    expected = recorded.quality_requirements.diagnostic_contract_details.dependency.version
    actual = live.quality_requirements.diagnostic_contract_details.dependency.version
    @testset "the frozen pilot binds its diagnostic dependency" begin
        @test guard.ld1b1_validate_frozen_pilot_contract(archived_protocol)
        if actual == expected
            @test guard.ld1b1_validate_frozen_pilot_contract((; pilot_contract=live))
        else
            @test_throws "differs from the frozen canonical contract" guard.ld1b1_validate_frozen_pilot_contract((; pilot_contract=live))
            # Account for the version in this comparison only. The executor still
            # receives and validates the complete, unmodified protocol.
            comparison = guard.ld1b1_json_native(recorded)
            comparison["quality_requirements"]["diagnostic_contract_details"]["dependency"]["version"] = actual
            @test comparison == guard.ld1b1_json_native(live)
        end
    end
    return expected
end

function check_current_pilot_harness(; executor_tests = false)
    root = dirname(@__DIR__)
    fixture_dir = joinpath("test", "fixtures")
    harness = joinpath(fixture_dir, "local_dependence_pilot_batch_execution_harness.json")
    protocol = joinpath(fixture_dir, "local_dependence_pilot_protocol_preflight.json")
    archived = JSON3.read(read(joinpath(root, harness), String))

    diagnostic_version = check_pilot_diagnostic_dependency(JSON3.read(read(joinpath(root, protocol), String)))

    # The executor checks resolve paths relative to their source files and verify
    # exact file identities. Generate both current inputs at their canonical paths
    # in an isolated checkout. Downstream archives keep the original bytes.
    mktempdir() do scratch
        for name in ("src", "ext", "scripts", "test", "Project.toml")
            cp(joinpath(root, name), joinpath(scratch, name))
        end
        for name in readdir(root)
            occursin(r"^Manifest(?:-v\d+\.\d+)?\.toml$", name) || continue
            cp(joinpath(root, name), joinpath(scratch, name))
        end
        # The pilot's recorded dependency is part of its SHA. Resolve it only in
        # the scratch project; generators and executor checks load the same source.
        setup = """
            using Pkg
            Pkg.instantiate()
            name = "MCMCDiagnosticTools"
            version = VersionNumber(only(ARGS))
            uuid = Pkg.project().dependencies[name]
            if Pkg.dependencies()[uuid].version != version
                Pkg.pin(Pkg.PackageSpec(; name, version))
            end
            """
        julia = `$(Base.julia_cmd()) --startup-file=no --project=$scratch`
        run(`$julia -e $setup $diagnostic_version`)
        for generator in ("generate_local_dependence_calibration_scorer_preflight.jl",
                "generate_local_dependence_pilot_protocol_preflight.jl",
                "generate_local_dependence_pilot_batch_execution_harness.jl")
            script = joinpath(scratch, "scripts", generator)
            run(`$julia $script`)
        end

        current = JSON3.read(read(joinpath(scratch, harness), String))
        @testset "current pilot dry run reproduces the archived job plan" begin
            @test current.protocol_artifact.file_sha256 == bytes2hex(open(sha256, joinpath(scratch, protocol)))
            @test current.plan_identity.pilot_contract_sha256 == archived.plan_identity.pilot_contract_sha256
            @test current.plan_identity.ordered_job_rows_sha256 == archived.plan_identity.ordered_job_rows_sha256
            @test [r.job_id for r in current.command_rows] == [r.job_id for r in archived.command_rows]
            @test current.summary.n_fit_jobs == 540
            @test current.summary.n_pre_fit_rejection_jobs == 120
            @test current.summary.passed && current.summary.job_runner_subprocesses_started == 0
            @test !current.summary.model_fit_run && !current.summary.mcmc_run
        end
        if executor_tests
            checks = joinpath(scratch, "test", basename(@__FILE__))
            run(`$julia $checks --executor-fixtures`)
        end
    end
end

function check_pilot_executor_fixtures()
    include(joinpath(@__DIR__, "..", "scripts", "local_json.jl"))
    for file in ("local_dependence_calibration_artifact.jl",
            "local_dependence_pilot_protocol_artifact.jl",
            "local_dependence_pilot_calibration_semantics.jl",
            "local_dependence_pilot_attempt_archive.jl",
            "local_dependence_pilot_bounded_canonical_smoke.jl",
            "local_dependence_pilot_recovery.jl",
            "local_dependence_pilot_precommit_recovery.jl",
            "local_dependence_pilot_batch_execution_harness.jl",
            "local_dependence_pilot_controller_receipts.jl",
            "local_dependence_pilot_job_worker.jl")
        Base.include(@__MODULE__, joinpath(@__DIR__, file))
    end
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    if isempty(ARGS)
        check_current_pilot_harness()
    elseif ARGS == ["--executor-fixtures"]
        check_pilot_executor_fixtures()
    else
        error("unrecognized pilot test arguments: $ARGS")
    end
end
