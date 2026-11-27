module ExplanatoryPowerTests
using Test, BayesianMGMFRM, Distributions, Statistics
using BayesianMGMFRM.GlassBox
const B=BayesianMGMFRM;const A=B.AdditiveFacets

function fixture(mixed)
    rows=[(p,r,c) for p in 1:4 for r in 1:4 for c in ("a","b")]
    d=Dict(:person=>[p for (p,r,c) in rows],:judge=>[r for (p,r,c) in rows],
        :rubric=>[c for (p,r,c) in rows],:rate=>[p/3 for (p,r,c) in rows],
        :experience=>[r/3 for (p,r,c) in rows],:product=>[p*r/9 for (p,r,c) in rows],
        :score=>[mod(p+r,mixed && c=="a" ? 2 : 4) for (p,r,c) in rows])
    t=mfrm_spec(d;person=:person,score=:score,facets=(assessor=:judge,criterion=:rubric),steps=:criterion,
        category_levels=mixed ? Dict("a"=>0:1,"b"=>0:3) : 0:3,
        population=(assessor=LogNormal(-.4,.7),),prior_sd=(person=.7,facets=(criterion=.4,),step=.45),
        predictors=(person=(rate=Normal(.1,.6),),assessor=(experience=Normal(-.1,.6),),
            response=(product=(by=:criterion,prior=Normal(0,.5)),)),intercept=Normal(0,.8))
    t,d
end

@testset "Scientific factor measures and exact powered alternatives" begin
    for mixed in (false,true)
        t,d=fixture(mixed);defs=B._explanatory_power_definitions(t)
        @test sort(reduce(vcat,[f.raw for f in defs]))==collect(1:t.dimension)
        for q in (zeros(t.dimension),[.7sin(j) for j in 1:t.dimension],collect(range(-2,2;length=t.dimension)))
            joint=0.;volume=0.
            for f in defs
                z=q[f.raw];dim=length(z)
                expected=if f.family===:lognormal
                    sigma=exp(f.logmean+f.logsd*only(z));volume+=log(f.logsd*sigma)
                    logpdf(LogNormal(f.logmean,f.logsd),sigma)
                elseif dim==0
                    0.
                else
                    sd=f.hyper==0 ? f.sd : exp(f.logmean+f.logsd*q[f.hyper])
                    volume+=dim*log(sd)
                    sum(logpdf.(Normal(0,sd),sd*z))
                end
                actual=B._explanatory_factor_value(f,q);joint+=expected
                @test actual≈expected atol=1e-12
                @test f.selectable==(f.role!==:conditional_residual)
            end
            @test joint+volume≈logprior(t,q) atol=1e-11
            @test volume≈coordinates(t,q).log_volume atol=1e-12
        end
        # Rotating a zero-sum orthonormal basis changes no Gaussian block density.
        f=first(filter(f->f.role===:step_prior && f.free_dimension>1,defs))
        q=zeros(t.dimension);q[f.raw]=[.3,-.7];old=B._explanatory_factor_value(f,q)
        q[f.raw]=[-.7,-.3];@test B._explanatory_factor_value(f,q)≈old atol=1e-14
        # Rescaling a predictor and transporting its prior changes only a density constant.
        term=first(t.terms);f=only(filter(f->f.id==A._term_name(term),defs))
        deltas=[B._explanatory_factor_value(merge(f,(;sd=f.sd/10)),q)-B._explanatory_factor_value(f,q)
            for q in (zeros(t.dimension),fill(.2,t.dimension))]
        @test deltas≈fill(log(10),2) atol=1e-14
    end
    for alpha in (.25,.9,1.,1.1,4.)
        mu=-.4;s=.7;alt=LogNormal(mu+(1-alpha)*s*s/alpha,s/sqrt(alpha))
        differences=[logpdf(alt,x)-alpha*logpdf(LogNormal(mu,s),x) for x in (.1,.4,1.,3.)]
        @test maximum(differences)-minimum(differences)<1e-12
        wrong=LogNormal(mu,s/sqrt(alpha))
        wrongdiff=[logpdf(wrong,x)-alpha*logpdf(LogNormal(mu,s),x) for x in (.1,3.)]
        @test alpha==1 || abs(wrongdiff[1]-wrongdiff[2])>.01
        nd=[logpdf(Normal(.3,.6/sqrt(alpha)),x)-alpha*logpdf(Normal(.3,.6),x) for x in (-1.,0.,2.)]
        @test maximum(nd)-minimum(nd)<1e-12
    end
    # Deterministic integration of a conjugate normal posterior, not MCMC/SBC.
    xs=quantile.(Normal(1.,sqrt(.5)),((1:20000).-0.5)./20000)
    lp=logpdf.(Normal(0,1),xs)
    for alpha in (.9,1.,1.1)
        weights=exp.((alpha-1).*lp);weights./=sum(weights)
        @test sum(weights.*xs)≈2/(alpha+1) atol=5e-5
    end
    empirical=B._explanatory_power_weights(fill(2.,80),.9,2,.7,false)
    @test !empirical.reliable && !empirical.identity
    identity=B._explanatory_power_weights(fill(0.,80),.9,2,.7,true)
    @test identity.identity && identity.reliable
    @test_throws ArgumentError B._explanatory_power_weights([floatmax(Float64),-1.],4.,1,.7,false)
end
end
