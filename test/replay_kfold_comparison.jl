# Run after CommonPredictionKfoldChecks.checks(directory), in a fresh Julia process.
using BayesianMGMFRM, Test, Serialization
include("../examples/saved_kfold_comparison.jl")
directory=only(ARGS)
entries=deserialize(joinpath(directory,"replay-inputs.jls"))
expected=deserialize(joinpath(directory,"replay-expected.jls"))
@testset "Fresh-process public K-fold workflow" begin
    @test length(entries)==length(expected)==11
    for (entry, comparison) in zip(entries,expected)
        replay=saved_kfold_comparison("first"=>entry,"same"=>entry;comparison_axis=:model)
        @test isequal(replay,comparison)
        @test replay.scientific_acceptance===:not_established
        @test replay.model_selection===:not_performed
    end
    multi=saved_kfold_comparison("MFRM"=>entries[1],"GMFRM"=>entries[2],"MGMFRM"=>entries[3];
        comparison_axis=:dimensions,baseline="MFRM")
    @test [r.elpd for r in multi.rows]==[e.rows[1].elpd for e in expected[1:3]]
    @test multi.rows[3].elpd_difference ≈ expected[3].rows[1].elpd-expected[1].rows[1].elpd
end
