module CorrelatedGradientTests
using Test, BayesianMGMFRM, LinearAlgebra
import LogDensityProblems as L
const B=BayesianMGMFRM
const E=B.Experimental

# Deterministic artificial ratings; not generated research data or posterior draws.
function specification(K=3; P=4, R=3, I=4, sparse=false)
    cells=[(p,i,r) for p in 1:P for i in 1:I for r in 1:R
        if !sparse || R==1 || mod(p+i+r,3)!=0]
    data=FacetData((;person=first.(cells),item=getindex.(cells,2),rater=last.(cells),
        score=[mod(p+2i+r,K) for (p,i,r) in cells]);
        person=:person,item=:item,rater=:rater,score=:score,category_levels=0:(K-1))
    q=falses(I,2)
    for i in 1:I;q[i,isodd(i) ? 1 : 2]=true;end
    return mfrm_spec(data;family=:mgmfrm,dimensions=2,q_matrix=q,
        dimension_labels=["First","Second"])
end
prior()=E.GeneralizedPrior(person_sd=.7,rater_sd=.4,item_sd=.6,
    log_discrimination_sd=.3,log_consistency_sd=.2,step_sd=.5)
target(spec=specification();eta=2)=B._mgmfrm_correlated_2d_target(E.correlated(spec;lkj_eta=eta),prior())

function finite_checks()
    @testset "correlated 2D analytic scores" begin
        for K in (2,3,4,9), R in (1,3), sparse in (false,true)
            t=target(specification(K;R,sparse));n=L.dimension(t)
            @test L.capabilities(typeof(t))==L.LogDensityOrder{1}()
            for z in (-8.,-2.,-.4,0.,.7,2.,8.)
                x=[.2sin(i) for i in 1:n];x[end]=z
                value,g=L.logdensity_and_gradient(t,x)
                reference=B.ForwardDiff.gradient(q->L.logdensity(t,q),x)
                @test value==L.logdensity(t,x)
                @test all(isfinite,g)
                @test all(isapprox.(g,reference;atol=1e-8,rtol=1e-9))
            end
        end
        t=target();n=L.dimension(t);persons=t.base.blueprint.blocks[:person]
        for z in (-1000.,-20.,20.,1000.), level in (0.,.7)
            x=initial_params(t);x[end]=z
            x[first(persons):2:last(persons)].=level
            x[(first(persons)+1):2:last(persons)].=sign(z)*level
            value,g=L.logdensity_and_gradient(t,x)
            reference=B.ForwardDiff.gradient(q->L.logdensity(t,q),x)
            @test isfinite(value) && value==L.logdensity(t,x)
            @test all(isfinite,g)
            @test all(isapprox.(g,reference;atol=1e-8,rtol=1e-9))
        end
        for z in (-372.,372.)
            x=initial_params(t);x[first(persons)]=nextfloat(0.);x[end]=z
            value,g=L.logdensity_and_gradient(t,x)
            reference=B.ForwardDiff.gradient(q->L.logdensity(t,q),x)
            @test value==L.logdensity(t,x)
            @test all(isfinite,g)
            @test all(isapprox.(g,reference;atol=1e-8,rtol=1e-9))
        end
        for bad in (zeros(n-1),zeros(n+1),fill(NaN,n),fill(Inf,n))
            @test_throws ArgumentError L.logdensity_and_gradient(t,bad)
        end
        spec=E.correlated(specification())
        @test E.surface_contract(spec).gradient_selection.selected===:analytic
        @test E.surface_contract(spec;ad_backend=:ForwardDiff).gradient_selection.selected===:ForwardDiff
        @test E.surface_contract(spec).gradient_selection.reason===:validated_correlated_2d_analytic_score
        @test_throws ArgumentError E.fit(spec;prior=prior(),backend=:cmdstan,ad_backend=:analytic)
        @test_throws ArgumentError B._logdensity_gradient_target(t,initial_params(t),:unsupported)
    end
end
end
