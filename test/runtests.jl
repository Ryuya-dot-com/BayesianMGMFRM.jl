using Test
using ForwardDiff
using JSON3
using ReverseDiff

using BayesianMGMFRM:
    FaithfulFastData,
    faithful_fast_logposterior,
    faithful_fast_logposterior_and_gradient,
    faithful_fast_num_params

function central_difference(logp, x, i; eps = 1e-5)
    xp = copy(x)
    xm = copy(x)
    xp[i] += eps
    xm[i] -= eps
    return (logp(xp) - logp(xm)) / (2eps)
end

@testset "faithful scalar analytic gradient" begin
    fd = FaithfulFastData(
        X = [1, 2, 3, 4, 5, 2, 4, 1, 3, 5, 2, 4],
        examinee = [1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 1, 3],
        rater = [1, 2, 3, 4, 1, 3, 2, 4, 1, 2, 4, 3],
        J = 5,
        R = 4,
        K = 5,
        N = 12,
    )
    x = [0.07 * sin(i) + 0.03 * cos(2i) for i in 1:faithful_fast_num_params(fd)]
    logp = z -> faithful_fast_logposterior(z, fd)

    lp, g_analytic = faithful_fast_logposterior_and_gradient(x, fd)
    @test lp ≈ logp(x) atol = 1e-10 rtol = 1e-10

    g_reverse = ReverseDiff.gradient(logp, x)
    @test maximum(abs.(g_analytic .- g_reverse)) < 1e-8

    g_forward = ForwardDiff.gradient(logp, x)
    @test maximum(abs.(g_analytic .- g_forward)) < 1e-8

    coords = unique(round.(Int, range(1, length(x), length = min(length(x), 12))))
    for i in coords
        @test g_analytic[i] ≈ central_difference(logp, x, i) atol = 1e-4 rtol = 1e-4
    end

    stan_fixture = get(ENV, "MFRM_STAN_LOGDENSITY_FIXTURE", "")
    if isempty(stan_fixture)
        @test_skip "Stan log-density fixture not configured; set MFRM_STAN_LOGDENSITY_FIXTURE"
    else
        fixture = JSON3.read(read(stan_fixture, String))
        x_stan = Vector{Float64}(fixture[:x])
        lp_stan = Float64(fixture[:stan_log_density])
        tol = haskey(fixture, :tolerance) ? Float64(fixture[:tolerance]) : 1e-6
        lp_julia, g_julia = faithful_fast_logposterior_and_gradient(x_stan, fd)
        @test lp_julia ≈ lp_stan atol = tol rtol = tol
        if haskey(fixture, :stan_gradient)
            g_stan = Vector{Float64}(fixture[:stan_gradient])
            @test maximum(abs.(g_julia .- g_stan)) < max(tol, 1e-6)
        end
    end
end
