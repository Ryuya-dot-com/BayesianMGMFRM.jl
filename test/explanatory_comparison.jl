module ExplanatoryComparisonTests
using Test, BayesianMGMFRM, Distributions, Statistics
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
