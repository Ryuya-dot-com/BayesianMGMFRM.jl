module JointRatingGradientTests
using Test, BayesianMGMFRM, LinearAlgebra
import LogDensityProblems as L
const B=BayesianMGMFRM
const S=B.Experimental.JointRatings.S
const FD=B.ForwardDiff
include("joint_ratings_fixture.jl")
function finite_checks()
    tests=@testset "JointRatings exact gradient and numerical tails" begin
        for (K,shared,predictors) in ((2,true,false),(3,true,true),(4,false,true),(9,false,false))
            t=static_fixture(;K,shared,predictors,sparse=true,repeated=true)
            qs=static_points(t)
            for z in (-1000.,-100.,-23.35152179432271,20.454138487056348,100.,1000.)
                q=copy(qs[2]);q[t.blocks.correlation].=[z,-z];push!(qs,q)
            end
            for q in qs
                lp,g=L.logdensity_and_gradient(t,q)
                expected=FD.gradient(x->L.logdensity(t,x),q)
                @test lp==L.logdensity(t,q)
                @test all(isfinite,g)
                @test g≈expected atol=2e-9 rtol=2e-10
            end
            @test_throws ArgumentError L.logdensity_and_gradient(t,zeros(1))
            for value in (NaN,Inf,-Inf)
                q=S.initial(t);q[1]=value
                lp,g=L.logdensity_and_gradient(t,q)
                @test lp==-Inf && all(isnan,g)
            end
            q=S.initial(t);q[t.blocks.log_response_sd].=1000.
            @test L.logdensity(t,q)==L.logdensity_and_gradient(t,q)[1]==-Inf
            q=S.initial(t);q .+= 0.1 .* sin.(eachindex(q))
            analytic=B._logdensity_gradient_target(t,q,:analytic)
            reference=B._logdensity_gradient_target(t,q,:ForwardDiff)
            @test L.logdensity_and_gradient(analytic.target,q)[2]≈L.logdensity_and_gradient(reference.target,q)[2]
        end
    end
    return tests.n_passed
end
end
