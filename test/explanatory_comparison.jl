module ExplanatoryComparisonTests
using Test, BayesianMGMFRM, Distributions, Statistics
using BayesianMGMFRM.GlassBox
const B=BayesianMGMFRM;const A=B.AdditiveFacets
function fixture(;mixed=false,population_residual=true,one_per_person=false,performance_coefficients=false)
    rows=[(p,o,r,c) for p in 1:4 for o in 1:2 for r in 1:3 for c in 1:2]
    one_per_person && filter!(x->x[1]!=1 || x[2]==1,rows)
    data=Dict(:speaker=>[p for (p,o,r,c) in rows],:talk=>[2p+o for (p,o,r,c) in rows],
        :judge=>[r for (p,o,r,c) in rows],:rubric=>[c for (p,o,r,c) in rows],
        :rate=>[p/3+(-1.)^o/2 for (p,o,r,c) in rows],
        :score=>[mod(p+o+r,mixed && c==1 ? 2 : 4) for (p,o,r,c) in rows])
    t=mfrm_spec(data;person=:speaker,score=:score,performance=:talk,
        facets=(session_noise=:talk,listener=:judge,rubric_owner=:rubric),steps=:rubric_owner,
        category_levels=mixed ? Dict(1=>0:1,2=>0:3) : 0:3,
        population=population_residual ? (session_noise=.35,listener=.4) : (listener=.4,),
        prior_sd=population_residual ? (person=.7,facets=(rubric_owner=.2,),step=.4) :
            (person=.7,facets=(session_noise=.35,rubric_owner=.2),step=.4),
        predictors=(person=(mean_rate=Normal(0,.5),),response=(rate_change=performance_coefficients ? (by=:session_noise,prior=Normal(0,.5)) : Normal(0,.5),)),
        decompose=(rate=(between=:mean_rate,within=:rate_change),),intercept=Normal(0,.8))
    t
end

@testset "Assessment-unit shared effects and zero-effect reference" begin
    rows=[(p,r,c) for p in 1:4 for r in 1:3 for c in 1:3]
    d=(;person=first.(rows),rater=getindex.(rows,2),item=last.(rows),
        event=[3p+r for (p,r,c) in rows],score=[mod(p+r+c,4) for (p,r,c) in rows])
    for mixed in (false,true), sd_prior in (0.,truncated(Normal(),0,Inf),truncated(LocationScale(0,.7,TDist(4)),0,Inf))
        t=mfrm_spec(d;person=:person,score=:score,facets=(rater=:rater,item=:item,event=:event),
            assessment=:event,steps=:item,category_levels=mixed ? Dict(i=>0:(i==1 ? 4 : 3) for i in 1:3) : 0:3,
            population=(person=truncated(Normal(),0,Inf),event=sd_prior),
            prior_sd=(facets=(rater=1.,item=1.),step=1.),intercept=Normal(0,2.5))
        @test validate_design(t).identified
        design=B._explanatory_profile_design(t,:assessment,:event)
        @test length(design.groups)==12 && all(length(g)==3 for g in design.groups)
        @test design.integration===:one_iid_assessment_residual_joint_profile
        train=B._explanatory_training_target(t,design,first(design.profiles).performance)
        q=.1sin.(1:train.dimension);full=B._explanatory_transport(train,t,q)
        keep=setdiff(eachindex(t.person),design.groups[1])
        @test pointwise_loglikelihood(train,q)≈pointwise_loglikelihood(t,full)[keep] atol=1e-12
        @test A.record(train).schema=="bayesianmgmfrm.explanatory_facet_design.v4"
        # A joint probability must reduce to the conditional product when SD is zero.
        quad=first(B._explanatory_quadrature((31,61),1e-7,1e-5))
        eta=[-.2,.5];tau=[[-.3,.1,.2],[-.3,.1,.2]];ys=[2,4]
        ref=sum(begin w=[0.;cumsum(eta[i].-tau[i])];w[ys[i]]-log(sum(exp,w)) end for i in 1:2)
        @test B._explanatory_integral(eta,tau,ys,quad,0.)≈ref atol=1e-12
    end
end

@testset "Joint integration, support, identity and normalized refit prior" begin
    quads=B._explanatory_quadrature((61,121),1e-7,1e-5)
    # Independent uniform-z quadrature using Distributions and direct PCM masses.
    z=range(-9.,9.;length=20001);dz=step(z)
    for mixed in (false,true)
        t=fixture(;mixed);d=B._explanatory_profile_design(t,:performance,:session_noise)
        @test length(d.profiles)==8
        @test_throws ArgumentError B._explanatory_profile_design(t,nothing,:session_noise)
        @test_throws ArgumentError B._explanatory_profile_design(t,:performance,:listener)
        @test_throws ArgumentError B._explanatory_training_target(t,d,"unknown")
        training=B._explanatory_training_target(t,d,first(d.profiles).performance)
        keep=setdiff(eachindex(t.person),d.groups[1])
        @test training.table[:mean_rate]==t.table[:mean_rate][keep]
        @test training.table[:rate_change]==t.table[:rate_change][keep]
        @test t.dimension==training.dimension+1
        for amplitude in (0.,.3)
            q=amplitude.*sin.(1:training.dimension)
            full=B._explanatory_transport(training,t,q)
            @test pointwise_loglikelihood(training,q)≈pointwise_loglikelihood(t,full)[keep] atol=1e-12
            @test logprior(t,full)≈logprior(training,q)-log(2pi)/2 atol=1e-12
        end
        eta=[-.7,.8];tau=mixed ? [[0.],[-.4,.1,.3]] : [[-.4,.1,.3],[.3,-.1,-.2]]
        ys=mixed ? [2,3] : [1,3];sd=.7
        probability(x)=prod(begin
            logits=[0.;cumsum(eta[n].-sd*x.-tau[n])]
            exp(logits[ys[n]])/sum(exp,logits)
        end for n in 1:2)
        reference=log(sum(pdf(Normal(),x)*probability(x) for x in z)*dz)
        for quad in quads
            @test B._explanatory_integral(eta,tau,ys,quad,sd)≈reference atol=2e-12
        end
    end
    @test exp(B._explanatory_integral([0.],[[0.]],[2],quads[2],.7))≈.5 atol=1e-14
    @test exp(B._explanatory_integral([0.,0.],[[0.],[0.]],[2,2],quads[2],.7))>.25
    t=fixture(;population_residual=false)
    @test_throws ArgumentError B._explanatory_profile_design(t,:performance,:session_noise)
    @test_throws ArgumentError B._explanatory_profile_design(fixture(;one_per_person=true),:performance,:session_noise)
    @test_throws ArgumentError B._explanatory_profile_design(fixture(;performance_coefficients=true),:performance,:session_noise)
    @test_throws ArgumentError B._explanatory_quadrature((61,61),1e-7,1e-5)
    @test_throws ArgumentError B._explanatory_quadrature((true,121),1e-7,1e-5)
    @test_throws ArgumentError B._explanatory_quadrature((61,121),NaN,1e-5)
    # Grouped deletion SE for a mean equals the independent batch-mean SE.
    values=sin.(1:40);leave=[mean(values[setdiff(1:40,[j])]) for j in 1:40]
    @test sqrt(39/40*sum(abs2,leave.-mean(leave)))≈std(values)/sqrt(40)
end
end
