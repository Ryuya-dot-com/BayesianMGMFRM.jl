module MatchedDimensionPlanChecks
using BayesianMGMFRM, Test
include("../examples/matched_dimension_refit_plans.jl")
const E=BayesianMGMFRM.Experimental

@testset "Matched dimension plans preserve the comparison and refuse changed loading roles" begin
    cells=[(p,i,r) for p in 1:4 for i in 1:4 for r in 1:3 for occasion in 1:2]
    data=FacetData((;person=first.(cells),item=getindex.(cells,2),rater=last.(cells),
        score=[mod(p+i+r,3) for (p,i,r) in cells]);
        person=:person,item=:item,rater=:rater,score=:score,category_levels=0:2)
    split=kfold_plan(data;k=2)
    prior=E.NormalizedMGMFRMPrior(prior_model=:exchangeable,
        person_sd=1.,rater_sd=.5,item_sd=1.,log_discrimination_sd=.3,
        log_consistency_sd=.3,step_sd=.7)
    q=Bool[1 0;1 0;0 1;0 1]
    options=(;dimension_labels=["A","B"],prior,dataset_id="plan fixture",
        observation_ids=["rating-$n" for n in 1:data.n])
    plans=matched_dimension_refit_plans(data,split;q_matrix=q,options...)
    one,many=last.(plans)
    @test one.split_binding==many.split_binding
    @test one.source_binding==many.source_binding
    @test q==Bool[1 0;1 0;0 1;0 1]
    for (a,b) in zip(one.folds,many.folds)
        @test a.training_observations==b.training_observations
        @test a.heldout_observations==b.heldout_observations
        @test a.model.dimensions==1 && b.model.dimensions==2
        @test a.model.dimension_labels==["General"] && b.model.dimension_labels==["A","B"]
        @test sum(a.model.q_matrix)==sum(b.model.q_matrix)==4
        @test a.prior.scales==b.prior.scales==prior.scales
        @test a.binding!=b.binding
    end
    @test_throws ArgumentError matched_dimension_refit_plans(data,split;
        q_matrix=trues(4,1),options...)
    @test_throws ArgumentError matched_dimension_refit_plans(data,split;
        q_matrix=Bool[1 1;1 0;0 1;0 1],options...)
    @test_throws ArgumentError matched_dimension_refit_plans(data,split;
        q_matrix=q,options...,prior=E.GeneralizedPrior(;prior.scales...))
end
end
