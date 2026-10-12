# Run after CommonRecoveryEvaluationChecks.checks(directory), in a fresh process.
using BayesianMGMFRM, Test, Serialization
include("../examples/saved_recovery_evaluation.jl")
directory=only(ARGS)
@testset "Fresh-process named recovery evaluation" begin
    @test all(isfile(joinpath(directory,"case-$i.jls")) for i in 1:11)
    for i in 1:11
        input=deserialize(joinpath(directory,"case-$i.jls"))
        replay=saved_recovery_evaluation(input.path,input.truth;
            input.dataset_id,input.observation_ids,input.interval)
        @test isequal(replay,input.expected)
        prediction=BayesianMGMFRM.prediction_observations(load_fit_cache(input.path);
            input.dataset_id,input.observation_ids,include_probabilities=false)
        @test replay.source_binding==prediction.observation_binding
    end
end
