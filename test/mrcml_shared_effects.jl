module MRCMLSharedEffectsTests
using Test, BayesianMGMFRM, Distributions, ForwardDiff
using BayesianMGMFRM.GlassBox
const B=BayesianMGMFRM;const A=B.AdditiveFacets
rows=[(p,r,c) for p in 1:8 for r in 1:3 for c in 1:3]
data=(;person=first.(rows),rater=getindex.(rows,2),item=last.(rows),
    event=["$p-$r" for (p,r,c) in rows],score=[mod(p+r+c,4) for (p,r,c) in rows])
opts=(;person=:person,score=:score,facets=(rater=:rater,item=:item,event=:event),
    assessment=:event,steps=:item,category_levels=0:3,
    random_effects=(event=truncated(Normal(0,.5),0,Inf),))
@testset "Shared effects compose with groups, DFF and anchors" begin
    roster=(;person=1:8,group=repeat(["A","B"];inner=4))
    pop=(;roster,person=:person,group=:group,reference="A",
        coefficient_prior=Normal(0,1),sd_prior=truncated(Normal(),0,Inf))
    for grouped in (false,true), anchored in (false,true)
        kw=anchored ? (;fixed_calibration=(facets=(item=Dict(1=>.4),),)) : (;)
        t=grouped ? mfrm_spec(data;opts...,kw...,population=pop,
            prior_sd=(facets=(rater=1.,item=1.),step=1.),interactions=((:rater,:group)=>.5,)) :
            mfrm_spec(data;opts...,kw...,prior=:default)
        @test t isa A.MRCMLTarget
        @test validate_design(t).passed
        @test A.record(A.restore(A.record(t)))==A.record(t)
        b=only(filter(b->b.name===:event,t.prior_blocks))
        @test length(b.raw_range)==24 && b.iso_factor==1
        @test !t.prior_symmetry.prior_asymmetry_detected
        d=B._explanatory_profile_design(t,:assessment,:event)
        tr=B._explanatory_training_target(t,d,first(data.event))
        @test validate_design(tr).passed
        @test A.record(A.restore(A.record(tr)))==A.record(tr)
        for amplitude in (0.,.3)
            q=amplitude.*sin.(1:t.dimension)
            lp,g=logdensity_and_gradient(t,q)
            @test lp≈logposterior(t,q)
            @test g≈ForwardDiff.gradient(x->logposterior(t,x),q) atol=1e-9
            @test logprior(t,q)==logprior(tr,q)
            @test pointwise_loglikelihood(tr,q)≈pointwise_loglikelihood(t,q)[4:end] atol=1e-12
            quad=B._explanatory_quadrature((241,481),1e-7,1e-5)
            integral=B._explanatory_integrals(t,d,(;draws=reshape(q,1,:)),quad;profiles=[1])
            @test integral.coarse≈integral.fine atol=1e-10
            # Integration must erase the event's posterior random-effect value.
            changed=copy(q);changed[first(b.raw_range)]+=2
            other=B._explanatory_integrals(t,d,(;draws=reshape(changed,1,:)),quad;profiles=[1])
            @test integral.fine≈other.fine atol=1e-12
        end
    end
    bad=merge(data,(;event=data.person))
    @test !validate_design(mfrm_spec(bad;opts...,prior=:default)).passed
    @test_throws ArgumentError mfrm_spec(data;opts...,prior=:none)
end
@testset "Fixed calibration preserves a freely estimated group origin" begin
    pop=(;roster=(person=1:8,group=repeat(["A","B"];inner=4)),
        person=:person,group=:group,reference="A",
        coefficient_prior=Normal(.2,1.3),sd_prior=truncated(Normal(),0,Inf))
    anchors=Dict(1=>.4,2=>.7,3=>-.2)
    target(shift;population=pop)=mfrm_spec(data;opts...,population,
        prior_sd=(facets=(rater=1.,item=0.),step=1.),
        fixed_calibration=(facets=(item=Dict(k=>v+shift for (k,v) in anchors),),))
    t=target(0.);moved=target(1.7);d=t.spec_record.population
    @test first(d.mean_terms).name=="intercept"
    @test !hasproperty(target(0.;population=merge(pop,(;intercept=false))).spec_record.population,:has_intercept)
    q=.3sin.(1:t.dimension);qm=copy(q);qm[first(d.beta)]+=1.7/d.coefficient_prior.sd
    @test pointwise_loglikelihood(t,q)≈pointwise_loglikelihood(moved,qm) atol=1e-12
    c=coordinates(t,q);cm=coordinates(moved,qm)
    @test cm.person≈c.person.+1.7 atol=1e-12
    @test cm.population.coefficients[2:end]≈c.population.coefficients[2:end] atol=1e-12
end
end
