using Test, Random, Statistics
include(joinpath(@__DIR__,"..","scripts","mgmfrm_core_prior_review.jl"))
const R=MGMFRMCorePriorReview
const E=R.E
const P=R.P
const B=R.B
observed=P.readjson("results/workflows/20260921-core-generator-01/fixed/observed.json")
spec=P.specification(observed)
gs=R.groups(spec.data)
findgroup(scope,id)=only(findall(g -> g.scope===scope && g.id==id,gs))

@testset "Declared priors, typed draw law, paired streams and score independence" begin
    results=[R.review(spec,c;ndraws=12,prior_seed=9240301,response_seed=9240302,batch_size=5) for c in R.REGIMES]
    for (i,c) in pairs(R.REGIMES)
        prior=B._mgmfrm_stress_prior(c)
        rng=MersenneTwister(9240301)
        bundle=B._guarded_generalized_prior_draw_bundle(spec,"test";prior,ndraws=12,rng)
        @test results[i].raw_draws==bundle.raw_draws
        @test results[i].raw_parameter_names==bundle.raw_parameter_names
        @test results[i].replicated_scores==B._guarded_generalized_replicate_scores(bundle,MersenneTwister(9240302),"test")
        @test results[i].summary.scales==only(filter(r -> r.regime===c,B._mgmfrm_validation_prior_regimes())).scales
        target=B._guarded_generalized_prior_target(bundle.design,prior)
        sds=[B._source_fixture_prior_sd(target,j) for j in 1:128]
        native_normals=results[i].raw_draws./permutedims(sds)
        base_sds=[ones(109);fill(.5,9);ones(10)]
        @test native_normals≈results[1].raw_draws./permutedims(base_sds) atol=1e-14
        @test results[i].raw_draws[:,1:100]==results[1].raw_draws[:,1:100]
        @test !results[i].summary.observed_scores_used && !results[i].summary.prior_selected
    end
    rng=MersenneTwister(9240301)
    public=B.Experimental.prior_predict(spec;prior=B._mgmfrm_stress_prior(:implementation_reference),ndraws=12,rng)
    rng2=MersenneTwister(9240301)
    bundle=B._guarded_generalized_prior_draw_bundle(spec,"test";prior=P.prior(),ndraws=12,rng=rng2)
    @test public==B._guarded_generalized_replicate_scores(bundle,rng2,"test")
    altered=deepcopy(spec.data.score)
    data=B.FacetData((;person=[spec.data.person_levels[n] for n in spec.data.person],
        item=[spec.data.item_levels[n] for n in spec.data.item],rater=[spec.data.rater_levels[n] for n in spec.data.rater],
        score=5 .- altered);person=:person,item=:item,rater=:rater,score=:score,category_levels=1:4)
    changed=B.mfrm_spec(data;family=:mgmfrm,dimensions=2,thresholds=:partial_credit,discrimination=:none,q_matrix=P.Q)
    replay=R.review(changed,:implementation_reference;ndraws=12,prior_seed=9240301,response_seed=9240302,batch_size=7)
    @test replay.raw_draws==results[1].raw_draws && replay.replicated_scores==results[1].replicated_scores
    @test replay.values≈results[1].values atol=1e-13
    paired=R.paired_summary(results[1],results[2])
    @test paired[1].mean≈mean(results[2].values[:,1,1]-results[1].values[:,1,1])
    @test paired[1].iid_mean_mcse≈std(results[2].values[:,1,1]-results[1].values[:,1,1])/sqrt(12)
    @test_throws ArgumentError R.paired_summary(results[1],merge(results[2],(;summary=merge(results[2].summary,(;prior_seed=2)))))
    @test_throws ArgumentError R.review(spec,:unknown;ndraws=12,prior_seed=1,response_seed=2)
    @test_throws ArgumentError R.review(spec,:implementation_reference;ndraws=12,prior_seed=1,response_seed=1)
    @test_throws ArgumentError R.review(spec,:implementation_reference;ndraws=1,prior_seed=1,response_seed=2)
end

@testset "Group identities, exact probability fixtures and missing-category events" begin
    @test length(gs)==118
    @test all(g -> isapprox(sum(g.weights),1.),gs)
    @test gs[findgroup(:person_dimension,"P2/D1")].n_observations==10
    @test all(n -> spec.data.person_levels[spec.data.person[n]]=="P2",gs[findgroup(:person_dimension,"P2/D1")].indices)
    logs=fill(-log(4),4,1250,4)
    scores=repeat(permutedims(spec.data.score),4)
    scores[1,:].=1
    scores[2,:].=2
    scores[3,:]=repeat([1,2,3,4],313)[1:1250]
    values=fill(NaN,4,118,12)
    R.fill_metrics!(values,1:4,logs,scores,gs)
    @test all(v -> isapprox(v,.25),values[:,:,1:4])
    @test all(v -> isapprox(v,.5),values[:,:,5])
    @test all(iszero,values[:,:,6])
    @test all(v -> isapprox(v,1.),values[:,:,7])
    @test all(v -> isapprox(v,2.5),values[:,:,8])
    @test values[1,1,9]≈1. && values[2,1,9]==0.
    @test values[1,1,10:12]==[1.,1.,1.] && values[3,1,10:12]==zeros(3)
    # D1 accounts for 40% of rows but 50% of the declared overall weight.
    for n in 1:1250
        if P.Q[spec.data.item[n],1]
            logs[:,n,:].=permutedims(log.([.97,.01,.01,.01]))
        end
    end
    R.fill_metrics!(values,1:4,logs,scores,gs)
    @test values[1,1,5]≈(.98+.5)/2 atol=1e-12
    @test values[1,1,6]≈.5 atol=1e-12
    @test values[1,findgroup(:dimension,"D2"),5]≈.5
    @test values[1,findgroup(:rater_dimension,"R5/D1"),6]≈1.
    @test_throws ArgumentError R.fill_metrics!(values,1:4,fill(NaN,4,1250,4),scores,gs)
    zero=R.summarize(zeros(2048);binary=true)
    @test zero.mean==zero.iid_mean_mcse==0.
    @test zero.binomial_interval95[2]≈-expm1(log(.025)/2048) rtol=1e-10
    @test zero.binomial_interval95[2]>0.
    @test_throws ArgumentError R.summarize([0.,NaN])
    @test_throws ArgumentError R.summarize([0.,.5];binary=true)
end

P.writejson(only(ARGS),(;tests_passed=true,new_sampler_runs=0,scientific_acceptance=false,
    scope="Known-answer arithmetic, typed-prior correspondence, common random numbers and grouping"))
