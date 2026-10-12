using BayesianMGMFRM, Serialization, Test, TOML, SHA
include("../examples/saved_prediction_workflow.jl")
input,output=ARGS
config=TOML.parsefile(joinpath(input,"inputs.toml"))
paths=[name=>joinpath(input,file) for (name,file) in zip(config["names"],config["files"])]
before=[sha256(read(path)) for (_,path) in paths]
expected=deserialize(joinpath(input,"expected.jls"))
actual=saved_prediction_workflow(paths...;directory=output,
    dataset_id=config["dataset_id"],observation_ids=config["observation_ids"],comparison_axis=:model)
checks=@testset "Fresh-session public saved prediction workflow" begin
    @test isequal(actual.comparison,expected.comparison)
    @test [r.model for r in actual.models]==[r.model for r in expected.models]
    for (a,b) in zip(actual.models,expected.models)
        @test isequal(a.diagnostics,b.diagnostics)
        @test isequal(a.parameter_mcse,b.parameter_mcse)
        @test a.report["waic"]==b.report["waic"]
        @test a.report["loo"]==b.report["loo"]
        @test a.report["diagnostics"]==b.report["diagnostics"]
    end
    @test before==[sha256(read(path)) for (_,path) in paths]
end
open(joinpath(output,"replay.toml"),"w") do io
    counts=Test.get_test_counts(checks)
    TOML.print(io,Dict("status"=>"passed","assertions"=>counts.passes+counts.cumulative_passes,
        "julia_version"=>string(VERSION),"pid"=>getpid(),"new_posterior_fits"=>0))
end
