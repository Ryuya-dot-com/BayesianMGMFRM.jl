using JSON3
using SHA
using Test

function check_current_pilot_harness(; executor_tests = false)
    root = dirname(@__DIR__)
    fixture_dir = joinpath("test", "fixtures")
    harness = joinpath(fixture_dir, "local_dependence_pilot_batch_execution_harness.json")
    protocol = joinpath(fixture_dir, "local_dependence_pilot_protocol_preflight.json")
    archived = JSON3.read(read(joinpath(root, harness), String))

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
        project = dirname(Base.active_project())
        for generator in ("generate_local_dependence_calibration_scorer_preflight.jl",
                "generate_local_dependence_pilot_protocol_preflight.jl",
                "generate_local_dependence_pilot_batch_execution_harness.jl")
            script = joinpath(scratch, "scripts", generator)
            run(`$(Base.julia_cmd()) --startup-file=no --project=$project $script`)
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
                Base.include(@__MODULE__, joinpath(scratch, "test", file))
            end
        end
    end
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && check_current_pilot_harness()
