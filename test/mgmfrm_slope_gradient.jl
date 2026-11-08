module MGMFRMSlopeGradientChecks
using Test, BayesianMGMFRM, LinearAlgebra
const B=BayesianMGMFRM
const E=B.Experimental
const FD=B.ForwardDiff

@testset "Analytic D1 score retains constraints, priors and slope policies" begin
    for R in (1,3), K in (2,3,25), policy in (:fixed_one,:estimated_positive)
        cells=[(p,i,r) for p in 1:4 for i in 1:3 for r in 1:R]
        d=FacetData((;person=first.(cells),item=getindex.(cells,2),rater=last.(cells),
            score=[mod(p+i+r,K) for (p,i,r) in cells]);
            person=:person,item=:item,rater=:rater,score=:score,category_levels=0:K-1)
        s=mfrm_spec(d;family=:mgmfrm,dimensions=1,thresholds=:partial_credit,q_matrix=trues(3,1))
        m=E.slope_restriction(s;item_slopes=policy,rater_consistency=:fixed_one)
        prior=E.NormalizedMGMFRMPrior(prior_model=:exchangeable,
            person_sd=.6,rater_sd=.4,item_sd=.7,step_sd=.3,
            log_discrimination_sd=.35,log_consistency_sd=.45)
        profiles=policy===:fixed_one ? (false,true) : (false,)
        for profiled in profiles
            p=profiled ? E.MeanProfilePrior(m,prior;
                item_means=Dict(i=>.1i for i in d.item_levels),
                step_means=Dict(i=>.02i.*((1:K-1).-K/2) for i in d.item_levels),
                category_levels=d.category_levels,units=:raw) : prior
            t=B._normalized_mgmfrm_target(m,p);x0=initial_params(t);n=length(x0)
            f=x->B.LogDensityProblems.logdensity(t,x)
            for x in (x0,x0.+.3sin.(1:n),x0.+2cos.(1:n))
                before=copy(x)
                value,g=B.LogDensityProblems.logdensity_and_gradient(t,x)
                @test x==before
                @test value≈f(x) atol=1e-8 rtol=1e-12
                @test g≈FD.gradient(f,x) atol=1e-7 rtol=1e-8
                v=sin.(1:n);v/=norm(v);h=1e-5
                @test dot(g,v)≈(f(x+h*v)-f(x-h*v))/(2h) atol=1e-5 rtol=1e-6
                @test all(isfinite,g)
            end
            @test_throws ArgumentError B.LogDensityProblems.logdensity_and_gradient(t,x0[1:end-1])
            bad=copy(x0);bad[1]=NaN
            @test_throws ArgumentError B.LogDensityProblems.logdensity_and_gradient(t,bad)
            bad[1]=Inf
            @test_throws ArgumentError B.LogDensityProblems.logdensity_and_gradient(t,bad)
            if K==3 && R==3
                jac=FD.jacobian(x->last(B.LogDensityProblems.logdensity_and_gradient(t,x)),x0)
                @test jac≈FD.hessian(f,x0) atol=1e-7 rtol=1e-8
                @test jac≈jac' atol=1e-8
            end
            if policy===:estimated_positive
                bad=copy(x0);bad[first(t.blueprint.blocks[:log_item_dimension_discrimination])]=1000
                @test_throws ArgumentError B.LogDensityProblems.logdensity_and_gradient(t,bad)
            end
        end
    end
end
end
