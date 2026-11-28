using JSON3
using SHA
using Test

# Run with --project pointing to the producer checkout. Read the PR fixtures
# relative to this test file and the original sources relative to that project.
producer = dirname(Base.active_project())
candidate = dirname(@__DIR__)
fixture(root, name) = joinpath(root, "test", "fixtures", name * ".json")
digest(path) = bytes2hex(open(sha256, path))

@testset "archived local-dependence and design studies" begin
    for name in ("local_dependence_pilot_protocol_preflight",
            "local_dependence_calibration_scorer_preflight",
            "existing_api_design_robustness_stress_grid")
        @test digest(fixture(candidate, name)) == digest(fixture(producer, name))
    end
    mktempdir() do scratch
        for name in ("local_dependence_pilot_batch_execution_harness",
                "existing_api_design_robustness_plan")
            output = joinpath(scratch, name * ".json")
            script = joinpath(producer, "scripts", "generate_" * name * ".jl")
            run(`$(Base.julia_cmd()) --startup-file=no --project=$producer $script --output $output`)
            @test digest(output) == digest(fixture(candidate, name))
        end
    end
    grid = JSON3.read(read(fixture(candidate, "existing_api_design_robustness_stress_grid"), String))
    runtime = grid.runtime_provenance
    @test runtime.project_toml_sha256 == digest(joinpath(producer, "Project.toml"))
    @test runtime.manifest_toml_sha256 == digest(joinpath(producer, runtime.manifest_file))
    for file in runtime.source_files
        @test file.sha256 == digest(joinpath(producer, file.path))
    end
    include(joinpath(producer, "scripts", "local_json.jl"))
    include(joinpath(producer, "test", "local_dependence_calibration_artifact.jl"))
end
