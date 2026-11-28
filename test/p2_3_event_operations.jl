module EventOperationTests
using Test, BayesianMGMFRM, Distributions, Statistics
using BayesianMGMFRM.GlassBox
import BayesianMGMFRM: fit
const B=BayesianMGMFRM;const A=B.AdditiveFacets
rows=[(p,r,c) for p in 1:6 for r in 1:3 for c in 1:3]
table=(;person=first.(rows),rater=getindex.(rows,2),item=last.(rows),
    event=["p$(p)-r$(r)" for (p,r,c) in rows],score=[mod(p+r+c,4) for (p,r,c) in rows])
ordinary=mfrm_spec(table;person=:person,score=:score,facets=(rater=:rater,item=:item),
    assessment=:event,steps=:item,category_levels=0:3,prior=:default)
shared=mfrm_spec(table;person=:person,score=:score,facets=(rater=:rater,item=:item,event=:event),
    assessment=:event,steps=:item,category_levels=0:3,population=(person=truncated(Normal(),0,Inf),event=truncated(Normal(0,.5),0,Inf)),
    prior_sd=(facets=(rater=1.,item=1.),step=1.),intercept=Normal(0,2.5))
@testset "Event deletion preserves the declared model" begin
    d=B._explanatory_profile_design(ordinary,:assessment,nothing)
    ds=B._explanatory_profile_design(shared,:assessment,:event)
    @test B._event_comparison_binding(ordinary,:assessment,d.profiles)==B._event_comparison_binding(shared,:assessment,ds.profiles)
    for id in (first(d.profiles).performance,last(d.profiles).performance)
        target=B._explanatory_training_target(ordinary,d,id)
        keep=findall(!isequal(id),table.event)
        @test target.dimension==ordinary.dimension
        @test A.names(target,:raw)==A.names(ordinary,:raw)
        @test A.record(A.restore(A.record(target)))==A.record(target)
        for amp in (0.,.2,.8)
            q=amp.*sin.(1:ordinary.dimension)
            @test logprior(target,q)==logprior(ordinary,q)
            @test pointwise_loglikelihood(target,q)≈pointwise_loglikelihood(ordinary,q)[keep] atol=1e-12
        end
    end
    @test_throws ArgumentError B._explanatory_profile_design(ordinary,:assessment,:event)
    @test_throws ArgumentError B._explanatory_training_target(ordinary,d,"unknown")
end
@testset "Standard and shared event order agrees for unsorted IDs" begin
    tab=map(reverse,table)
    kw=(;person=:person,score=:score,assessment=:event,steps=:item,category_levels=0:3)
    a=mfrm_spec(tab;kw...,facets=(rater=:rater,item=:item),prior=:default)
    b=mfrm_spec(tab;kw...,facets=(rater=:rater,item=:item,event=:event),
        population=(person=truncated(Normal(),0,Inf),event=truncated(Normal(0,.5),0,Inf)),
        prior_sd=(facets=(rater=1.,item=1.),step=1.),intercept=Normal(0,2.5))
    ad=B._explanatory_profile_design(a,:assessment,nothing)
    bd=B._explanatory_profile_design(b,:assessment,:event)
    @test B._event_comparison_binding(a,:assessment,ad.profiles)==B._event_comparison_binding(b,:assessment,bd.profiles)
end
@testset "Diagnostic probabilities preserve the ordinal likelihood" begin
    for t in (ordinary,shared),amp in (0.,.3)
        q=amp.*sin.(1:t.dimension)
        weights=A._diagnostic_logweights(t,q);scores=A._diagnostic_scores(t)
        probabilities=B.predictive_probabilities(t,q);buffer=zeros(4)
        for n in eachindex(t.person)
            mu,v=A._diagnostic_moments!(buffer,weights,n,scores[n])
            @test buffer≈probabilities[n,:] atol=1e-13
            @test mu≈sum(buffer.*scores[n])
            @test v≈sum(buffer.*(scores[n].-mu).^2)
        end
    end
end
@testset "Public event comparisons and shared diagnostics" begin
    # Short actual chains exercise operations; their warnings remain in reports.
    fo=fit(ordinary;chains=4,warmup=50,ndraws=40,seed=617,progress=false)
    fs=fit(shared;chains=4,warmup=50,ndraws=40,seed=618,progress=false)
    po=pointwise_loglikelihood(fo;unit=:assessment)
    @test size(po.log_density)==(160,18)
    @test po.integration===:joint_conditional_event_profile
    @test vec(sum(po.log_density;dims=2))≈[sum(pointwise_loglikelihood(ordinary,q)) for q in eachrow(fo.record.run.draws)]
    co=criteria(fo;unit=:assessment)
    cs=criteria(fs;unit=:assessment,integrate=:event)
    comparison=compare_models(:shared=>cs,:ordinary=>co;criterion=:psis_loo)
    @test comparison.difference≈cs.elpd-co.elpd
    @test comparison.unit===:assessment
    @test all(r->r.method===:conditional_psis,co.rows)
    plan=B.loo_refit_plan(fo,first(table.event);unit=:assessment)
    fr=fit(plan.target;chains=4,warmup=50,ndraws=40,seed=619,progress=false)
    ref=criteria(fo;unit=:assessment,refits=[first(table.event)=>fr],independent_refit_rng=true)
    @test ref.rows[1].method===:direct_refit
    q3=diagnostics(fs;kind=:residual_correlation,by=:item,unit=:event,max_draws=40)
    @test q3.n_pairs==3 && q3.n_units==18
    @test q3.residual_target===:remaining_dependence_given_fitted_effects
    stats=diagnostics(fs;kind=:fit_statistics,by=:rater)
    @test length(stats.rows)==3
    @test all(r->isfinite(r.infit_mnsq_mean) && isfinite(r.plugin_infit_mnsq),stats.rows)
    rel=reliability(fs)
    @test 0<=rel.reliability<=1
    @test ismissing(rel.population_marginal_reliability)
    @test rel.population_target===:not_evaluated
    mktempdir() do dir
        path=joinpath(dir,"comparison.json")
        receipt=save_report(path,comparison;return_receipt=true)
        restored=load_report(path;expected_sha256=receipt.sha256)
        @test restored.difference==comparison.difference
    end
end
end
