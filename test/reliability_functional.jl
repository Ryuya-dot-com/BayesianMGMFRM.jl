using Test, BayesianMGMFRM, Statistics

@testset "Reliability estimand and predictive-tail precision" begin
    B=BayesianMGMFRM; A=B.AdditiveFacets
    x=[0. 1.;1. 2.;2. 3.;3. 4.]
    for target in (:absolute,:centered)
        c=B._posterior_reliability_components(x,[1.,1.],target)
        for y in (x[[2,3,4,1],:], x.+17, -3x)
            d=B._posterior_reliability_components(y,[1.,1.],target)
            @test c.reliability ≈ d.reliability
        end
        y=target===:centered ? x.-mean(x;dims=2) : x
        means=vec(mean(y;dims=1))
        within=mean(mean((y[:,i].-means[i]).^2) for i in 1:2)
        between=var(means;corrected=false)
        @test c.reliability ≈ between/(between+within)
        @test c.within ≈ within
    end
    # Enumerated posterior mixture: B=W=.5, exactly the conjugate EAP ratio.
    noise=sqrt(.5).*[-1. -1.;-1. 1.;1. -1.;1. 1.]
    c=B._posterior_reliability_components(noise.+[-sqrt(.5) sqrt(.5)],[1.,1.],:absolute)
    @test c.between ≈ .5
    @test c.within ≈ .5
    @test c.reliability ≈ .5
    @test !isapprox(c.reliability,1/(1+c.within))
    obs=zeros(80);rep=sin.(collect(1.:80))
    p=A._diagnostic_tail_mcse(obs,rep,4)
    @test p.status===:available && isfinite(p.value)
    expected=B._classification_mean(rep.>=obs,4).mcse
    @test p.value==expected.value
    @test A._diagnostic_tail_mcse(obs,ones(80),4).status===:degenerate_draws
    @test ismissing(A._diagnostic_tail_mcse(obs,ones(80),4).value)
    @test A._diagnostic_tail_mcse(obs,rep,4;complete_chains=false).status===:subsampled_chain_mcse_unavailable
    @test A._diagnostic_tail_mcse(obs,[NaN;rep[2:end]],4).status===:incomplete_draws_mcse_unavailable
end
