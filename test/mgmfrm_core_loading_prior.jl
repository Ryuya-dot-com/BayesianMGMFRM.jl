using Test, Statistics, Random
include(joinpath(@__DIR__,"../scripts/mgmfrm_core_prior_review.jl"))
const R=MGMFRMCorePriorReview
const E,P,B=R.E,R.P,R.B
observed=(;candidate_id="independent_2d_raw_primary_01",category_levels=collect(1:4),
    observations=[(;person,item="I$i",rater="R$r",score=mod1(p+i+r,4))
        for (p,person) in enumerate(P.PERSONS) for i in 1:5 for r in 1:5])
spec=P.specification(observed)
prior=B.GeneralizedPrior(;person_sd=1.,rater_sd=1.,item_sd=1.,
    log_discrimination_sd=1.,log_consistency_sd=.5,step_sd=1.)
@testset "Explicit loading-only prior and unchanged prediction contract" begin
    ref=R.review(spec,:implementation_reference;ndraws=16,prior_seed=9370101,response_seed=9370102)
    same=R.review(spec,P.prior();label=:reference_explicit,ndraws=16,prior_seed=9370101,response_seed=9370102)
    alt=R.review(spec,prior;label=:loading_sd_1,ndraws=16,prior_seed=9370101,response_seed=9370102,batch_size=7)
    @test same.values==ref.values && same.raw_draws==ref.raw_draws
    @test same.replicated_scores==ref.replicated_scores
    @test alt.raw_draws[:,110:114] == 2ref.raw_draws[:,110:114]
    other=[1:109;115:128]
    @test alt.raw_draws[:,other]==ref.raw_draws[:,other]
    @test alt.summary.scales.log_discrimination_sd==1.
    @test alt.summary.scales.log_consistency_sd==ref.summary.scales.log_consistency_sd==.5
    @test !alt.summary.observed_scores_used && !alt.summary.prior_selected
    @test alt.summary.regime==:loading_sd_1 && all(isfinite,alt.values)
    paired=R.paired_summary(ref,alt)
    @test first(paired).mean≈mean(alt.values[:,1,1]-ref.values[:,1,1])
    t0=P.target(spec)
    t1=B._mgmfrm_guarded_local_fit_logdensity(spec;prior=B._source_fixture_prior(prior))
    for raw in eachrow(ref.raw_draws)
        x=collect(raw);delta=5log(.5)+1.5sum(abs2,x[110:114])
        @test B._source_fixture_loglikelihood(t1,x)==B._source_fixture_loglikelihood(t0,x)
        @test B._source_fixture_logprior(t1,x)-B._source_fixture_logprior(t0,x)≈delta atol=1e-10
        @test B.LogDensityProblems.logdensity(t1,x)-B.LogDensityProblems.logdensity(t0,x)≈delta atol=1e-10
    end
    @test_throws ArgumentError R.review(spec,prior;ndraws=1,prior_seed=1,response_seed=2)
    @test_throws ArgumentError R.review(spec,prior;ndraws=16,prior_seed=1,response_seed=1)
    @test_throws ArgumentError R.review(spec,prior;ndraws=16,prior_seed=-1,response_seed=2)
end
