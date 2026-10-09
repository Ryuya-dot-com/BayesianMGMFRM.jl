using Test, LinearAlgebra, Statistics
include(joinpath(@__DIR__,"..","scripts/mgmfrm_core_location_conditional.jl"))
const C=MGMFRMCoreLocationConditional

@testset "Exact normal location conditional" begin
    theta=[1. -2.; 3. 2.]
    A=[1. 0.; 0. 2.; 1. 1.]
    b=[.5,-.2,.3]
    result=C.location_conditional(theta,A,b;person_sd=1.,item_sd=1.)
    @test result.observed_mean == [2.,0.]
    @test result.offsets ≈ [-1.5,-.2,-1.7]
    @test result.precision == [4. 1.; 1. 7.]
    @test result.covariance ≈ [7. -1.; -1. 4.]/27
    @test result.conditional_mean ≈ [20.3,5.2]/27
    @test dot(result.standardized_residual,result.standardized_residual) ≈
        dot(result.observed_mean-result.conditional_mean,
            result.precision*(result.observed_mean-result.conditional_mean))
    for (person_sd,item_sd) in ((1.,1.),(1.3,.7)), shift in ([.3,-.4],[-.8,.2])
        original=C.location_conditional(theta,A,b;person_sd,item_sd)
        moved=C.location_conditional(theta .+ permutedims(shift),A,b+A*shift;person_sd,item_sd)
        @test moved.offsets ≈ original.offsets
        @test moved.conditional_mean ≈ original.conditional_mean
        @test moved.covariance ≈ original.covariance
        actual=-.5*(sum(abs2,theta .+ permutedims(shift))-sum(abs2,theta))/person_sd^2 -
            .5*(sum(abs2,b+A*shift)-sum(abs2,b))/item_sd^2
        analytic=-.5*(sum(abs2,moved.standardized_residual)-sum(abs2,original.standardized_residual))
        @test actual ≈ analytic atol=1e-12
    end
    pure=C.location_conditional(theta,A[1:2,:],b[1:2];person_sd=1.,item_sd=1.)
    @test pure.covariance ≈ [1/3 0; 0 1/6]
    # With zero loadings only the independent person prior anchors the mean.
    unanchored=C.location_conditional(theta,zeros(3,2),b;person_sd=1.3,item_sd=.7)
    @test unanchored.conditional_mean == zeros(2)
    @test unanchored.covariance ≈ Matrix{Float64}(I,2,2)*(1.3^2/2)
    single=C.location_conditional(reshape([2.],1,1),reshape([3.],1,1),[1.];person_sd=2.,item_sd=.5)
    @test single.covariance[1,1] ≈ 1/(1/4+9/.25)
    for args in ((theta,A,[1.]),(zeros(0,2),A,b),(fill(NaN,2,2),A,b))
        @test_throws ArgumentError C.location_conditional(args...;person_sd=1.,item_sd=1.)
    end
    for sd in (0.,-1.,Inf,NaN,true)
        @test_throws ArgumentError C.location_conditional(theta,A,b;person_sd=sd,item_sd=1.)
        @test_throws ArgumentError C.location_conditional(theta,A,b;person_sd=1.,item_sd=sd)
    end
end
