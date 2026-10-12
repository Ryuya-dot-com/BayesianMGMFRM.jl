module MGMFRMCoreNUTSStationarityChecks
using Test, LinearAlgebra, Random
include("../scripts/mgmfrm_core_nuts_stationarity.jl")
const N = MGMFRMCoreNUTSStationarity

@testset "Independent one-transition NUTS probe mechanics (not calibration)" begin
    m, K = [.3,-.2], [2. .4;.4 1.3]
    section = (;center=m, precision=K, logdensity=q -> -dot(q-m,K*(q-m))/2+123.0)
    args = (;replicas=12,input_seed=6101,transition_seed=7101,step_size=.11,inverse_mass=[.6,1.7])
    a = N.probe(section;args...)
    b = N.probe(section;args...)
    @test a == b
    R = cholesky(Symmetric(K)).U
    @test a.zin ≈ (R*(a.qin .- m')')'
    @test a.zout ≈ (R*(a.qout .- m')')'
    rng = MersenneTwister(6101)
    @test a.zin == reduce(vcat,[randn(rng,2)' for _ in 1:12])
    short = N.probe(section;merge(args,(;replicas=1))...)
    @test short.zin[1,:] == a.zin[1,:]
    @test short.zout[1,:] == a.zout[1,:]
    other = N.probe(section;merge(args,(;transition_seed=7102))...)
    @test other.zin == a.zin
    @test other.zout != a.zout
    embedded = N.probe(section;args...,embedded=true)
    @test embedded.zout ≈ a.zout atol=2e-10
    @test getproperty.(embedded.stats,:n_steps) == getproperty.(a.stats,:n_steps)
    @test all(s -> !s.numerical_error && 0 < s.tree_depth <= 10 && s.n_steps > 0, a.stats)
    @test sum(abs2,a.zout-a.zin) > 0
    @test m == [.3,-.2] && K == [2. .4;.4 1.3]
    for bad in ((;replicas=0),(;replicas=true),(;input_seed=-1),(;input_seed=7101),
            (;step_size=0.),(;step_size=NaN),(;step_size=true),(;max_depth=0),
            (;max_depth=1.5),(;max_energy_error=Inf),(;inverse_mass=[1.,0.]),
            (;inverse_mass=[1.]))
        @test_throws ArgumentError N.probe(section;merge(args,bad)...)
    end
    @test_throws ArgumentError N.probe(merge(section,(;precision=[1. 1.;0. 1.]));args...)
    @test_throws PosDefException N.probe(merge(section,(;precision=[1. 0.;0. -1.]));args...)
end
end
