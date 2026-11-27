module GeneralizabilityTests
using Test, BayesianMGMFRM, Distributions, LinearAlgebra, ForwardDiff
import LogDensityProblems as L
const G=BayesianMGMFRM.Generalizability
rows=[(p,r,t) for p in 1:6 for r in 1:3 for t in 1:2]
data=(;person=first.(rows),rater=getindex.(rows,2),task=last.(rows),
    content=[.2p+.1r+sin(p+r+t) for (p,r,t) in rows],
    organization=[.1p+.2t+cos(p+r+t) for (p,r,t) in rows])
prior=(;mean=Normal(0,2),sd=truncated(Normal(),0,Inf),correlation=LKJ(2,2))
@testset "Scalar Bayesian model retains Gaussian density and explicit priors" begin
    scalar_prior=(;mean=prior.mean,sd=prior.sd,correlation=nothing)
    t=G.model(data;scores=(:content,),person=:person,facets=(rater=:rater,task=:task),prior=scalar_prior)
    q=G.initial(t)+.1sin.(1:t.dimension)
    @test first(L.logdensity_and_gradient(t,q))≈L.logdensity(t,q)
    @test last(L.logdensity_and_gradient(t,q))≈ForwardDiff.gradient(z->L.logdensity(t,z),q) atol=1e-8
    @test G.restore_target(t.record).record==t.record
    @test_throws ArgumentError BayesianMGMFRM.fit(t;method=:reml)
end
@testset "Multivariate Gaussian covariance components" begin
    for facets in ((rater=:rater,),(rater=:rater,task=:task)), nested in (false,true)
        nested && length(facets)==1 && continue
        tab=length(facets)==1 ? (; (k=>v[1:2:end] for (k,v) in pairs(data))...) : data
        nesting=nested ? (rater=:task,) : (;)
        t=G.model(tab;scores=(:content,:organization),person=:person,facets,nesting,prior)
        @test t.allocation.passed
        @test G.restore_target(t.record).record==t.record
        @test_throws ArgumentError BayesianMGMFRM.fit(t;method=:mmle,chains=4,warmup=10,ndraws=10,seed=1)
        for extreme in (-1000.,1000.)
            q=G.initial(t);q[first(first(t.components).covariance)]=extreme
            @test L.logdensity(t,q)==-Inf
            @test first(L.logdensity_and_gradient(t,q))==-Inf
        end
        for amp in (0.,.25)
            q=G.initial(t)+amp.*sin.(1:t.dimension)
            lp,g=L.logdensity_and_gradient(t,q)
            @test lp≈L.logdensity(t,q) atol=1e-10
            @test g≈ForwardDiff.gradient(x->L.logdensity(t,x),q) atol=1e-8
            v=G.unpack(t,q);F=last(v.factors)
            ref=[logpdf(MvNormal(v.mean[n,:],F*F'),t.scores[n,:]) for n in axes(t.scores,1)]
            @test G.pointwise(t,q)≈ref atol=1e-12
            for b in t.components
                x=q[b.covariance];F=G.factor(t,x);sd=sqrt.(diag(F*F'));R=F*F'./(sd*sd')
                _,_,jac=G.A._cholesky_cpc(x,3:3,2)
                refprior=sum(logpdf(prior.sd,s)+log(s) for s in sd)+logpdf(prior.correlation,R)+jac
                @test G.covariance_prior(t,x)≈refprior atol=1e-12
            end
        end
    end
end
@testset "Crossed and nested D studies use their declared replication units" begin
    for nested in (false,true)
        t=G.model(data;scores=(:content,:organization),person=:person,
            facets=(rater=:rater,task=:task),nesting=nested ? (rater=:task,) : (;),prior)
        matrices=[[(.2k+.03sin(s+k))*[1. .2;.2 1.5] for k in eachindex(t.components)] for s in 1:64]
        r=G.Report((;schema=G.REPORT_SCHEMA,scores=t.record.scores,facets=[:rater,:task],
            components=[(;b.name,b.factors) for b in t.components],
            covariance_draws=[reduce(vcat,vec.(v)) for v in matrices],chains=4,
            chain_ids=repeat(1:4;inner=16),iterations=repeat(1:16,4),
            qualification=(qualified=false,),source_sample_hash="deterministic-algebra-fixture"))
        w=[.6,.4];ds=reliability(r;counts=(rater=3,task=2),weights=w)
        expected=map(matrices) do vs
            v=Dict(b.name=>M for (b,M) in zip(t.components,vs))
            if nested
                relative=v["person:task"]/2+v["residual"]/6
                absolute=relative+v["task"]/2+v["task:rater"]/6
            else
                relative=v["person:rater"]/3+v["person:task"]/2+v["residual"]/6
                absolute=relative+v["rater"]/3+v["task"]/2+v["rater:task"]/6
            end
            u=dot(w,v["person"]*w)
            (u/(u+dot(w,relative*w)),u/(u+dot(w,absolute*w)),sqrt(dot(w,absolute*w)))
        end
        @test first(ds.rows).G.mean≈sum(first,expected)/64
        @test first(ds.rows).Phi.mean≈sum(x->x[2],expected)/64
        @test first(ds.rows).absolute_sem.mean≈sum(last,expected)/64
        @test !ds.qualification.qualified
        @test_throws ArgumentError reliability(r;counts=(rater=3,),weights=w)
    end
end
end
