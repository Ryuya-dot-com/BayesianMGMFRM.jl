module MGMFRMPriorMeasureChecks

using Test, BayesianMGMFRM, ForwardDiff, LinearAlgebra, Statistics
import JSON3
const B = BayesianMGMFRM
include("test_groups.jl")

# The existing normal helper intentionally accepts fixed Float64 scales.
scale_difference(f, x) = (f(x + 1e-5) - f(x - 1e-5)) / 2e-5

# Normalized reference in the package's LAST-reconstructed free chart.
# distinguished=0 is centered/exchangeable; 1:n retains that source rater's ID.
# These are test-only densities, not new GeneralizedPrior options.
function zero_sum_logdensity(v, tau, distinguished = 0)
    m = length(v)
    n = m + 1
    lp = log(n) / 2 - m * (log(tau) + log(2pi) / 2) -
        (sum(abs2, v) + sum(v)^2) / (2tau^2)
    distinguished == 0 && return lp
    full = vcat(v, -sum(v))
    return lp - full[distinguished] - tau^2 * m / (2n)
end

@testset "Normalized source/exchangeable priors in common coordinates (no fitting)" begin
    for n in (2, 3, 5), tau in (0.5, 1.0, 2.0)
        m = n - 1
        C = vcat(Matrix{Float64}(I, m, m), -ones(1, m))
        A = C' * C
        covariance = tau^2 * (Matrix{Float64}(I, m, m) - ones(m, m) / n)
        projection = Matrix{Float64}(I, n, n) - ones(n, n) / n
        @test C * covariance * C' ≈ tau^2 * projection atol = 1e-12
        @test logdet(A) ≈ log(n) atol = 1e-12
        # First-reconstructed source chart u=(full[2],...,full[n]).
        T = C[2:end, :]
        @test abs(det(T)) ≈ 1 atol = 1e-12
        @test vcat(-ones(1, m), Matrix{Float64}(I, m, m)) * T ≈ C
        for distinguished in (0, 1, n)
            full_mean = distinguished == 0 ? zeros(n) :
                tau^2 .* (fill(1 / n, n) - Matrix{Float64}(I, n, n)[:, distinguished])
            mu = full_mean[1:m]
            reference(v) = -(dot(v - mu, covariance \ (v - mu)) +
                m * log(2pi) + logdet(covariance)) / 2
            h = distinguished == 0 ? zeros(m) : -C[distinguished, :]
            for v in (zeros(m), [0.3sin(i) + 0.2 for i in 1:m], mu)
                lp = zero_sum_logdensity(v, tau, distinguished)
                @test lp ≈ reference(v) atol = 1e-12
                @test ForwardDiff.gradient(x -> zero_sum_logdensity(x, tau, distinguished), v) ≈
                    -(A * v) / tau^2 + h atol = 1e-12
                @test ForwardDiff.hessian(x -> zero_sum_logdensity(x, tau, distinguished), v) ≈
                    -inv(covariance) atol = 1e-12
                tau_gradient = -m / tau + dot(v, A * v) / tau^3 -
                    (distinguished == 0 ? 0.0 : tau * m / n)
                @test ForwardDiff.derivative(s -> zero_sum_logdensity(v, s, distinguished), tau) ≈
                    tau_gradient atol = 1e-12
                @test C * v ≈ B._sum_to_zero_from_raw(v, n)
                if distinguished == 1
                    u = T * v
                    # In the source chart the linear tilt is +sum(u); in the
                    # package chart, with the SAME distinguished rater, it is -v[1].
                    @test zero_sum_logdensity(u, tau, n) ≈ lp atol = 1e-12
                    @test T' * ForwardDiff.gradient(x -> zero_sum_logdensity(x, tau, n), u) ≈
                        ForwardDiff.gradient(x -> zero_sum_logdensity(x, tau, 1), v) atol = 1e-12
                    @test lp - zero_sum_logdensity(v, tau) ≈
                        -v[1] - tau^2 * m / (2n) atol = 1e-12
                end
            end
            @test norm(ForwardDiff.gradient(x -> zero_sum_logdensity(x, tau, distinguished), mu)) < 1e-12
            @test C * mu ≈ full_mean atol = 1e-12
        end
        v = [0.3sin(i) + 0.2 for i in 1:m]
        full = C * v
        normal_kernel(s) = sum(B._normal_logpdf(x, s) for x in full)
        log_Z0(s) = -log(s) - log(2pi * n) / 2
        @test normal_kernel(tau) - log_Z0(tau) ≈ zero_sum_logdensity(v, tau) atol = 1e-12
        @test scale_difference(s -> normal_kernel(s) - zero_sum_logdensity(v, s), tau) ≈
            -1 / tau atol = 1e-8 rtol = 1e-8
        # Source positive-coordinate product, changed to free log coordinates.
        source_kernel(s) = sum(B._normal_logpdf(log(a), s) - log(a)
            for a in exp.(full)) + sum(v)
        log_Zsource(s) = log_Z0(s) + s^2 * m / (2n)
        @test source_kernel(tau) - log_Zsource(tau) ≈ zero_sum_logdensity(v, tau, n) atol = 1e-12
        @test scale_difference(s -> source_kernel(s) - zero_sum_logdensity(v, s, n), tau) ≈
            -1 / tau + tau * m / n atol = 1e-8 rtol = 1e-8
        # Relabeling is invariant only if the distinguished source rater moves too.
        reversed = reverse(full)[1:m]
        @test zero_sum_logdensity(reversed, tau) ≈ zero_sum_logdensity(v, tau) atol = 1e-12
        @test zero_sum_logdensity(reversed, tau, n) ≈ zero_sum_logdensity(v, tau, 1) atol = 1e-12
        @test zero_sum_logdensity(reversed, tau, 1) - zero_sum_logdensity(v, tau, 1) ≈
            full[1] - full[n] atol = 1e-12
        # Kernel SD tau versus common constrained marginal SD s.
        s = tau * sqrt((n - 1) / n)
        @test s * sqrt(n / (n - 1)) ≈ tau
        @test diag(C * covariance * C') ≈ fill(s^2, n)
        @test covariance[1, 1] + (C * covariance * C')[n, n] -
            2 * (C * covariance * C')[1, n] ≈ 2tau^2
    end
end

@testset "Numerical prior normalization and scale score (no fitting)" begin
    # Stdlib Gauss-Legendre quadrature on [-12tau,12tau] per free coordinate;
    # independently integrates the density and its fixed-coordinate scale score.
    order = 96
    rule = eigen(SymTridiagonal(zeros(order), [k / sqrt(4k^2 - 1) for k in 1:(order - 1)]))
    nodes, weights = 12 .* rule.values, 24 .* rule.vectors[1, :].^2
    for n in (2, 3), tau in (0.5, 1.0, 2.0), distinguished in (0, 1)
        m = n - 1
        mass, score = 0.0, 0.0
        for indices in Iterators.product(ntuple(_ -> eachindex(nodes), m)...)
            v = [tau * nodes[i] for i in indices]
            weight = tau^m * prod(weights[i] for i in indices)
            density = exp(zero_sum_logdensity(v, tau, distinguished))
            mass += weight * density
            score += weight * density * ForwardDiff.derivative(s ->
                zero_sum_logdensity(v, s, distinguished), tau)
        end
        @test mass ≈ 1 atol = 1e-9 rtol = 0
        @test abs(score) < 1e-9
    end
end

@testset "Prior choices recover their declared joint Gaussian moments (no fitting)" begin
    scales = (; person_sd = 1.2, rater_sd = .7, item_sd = .9,
        log_discrimination_sd = .4, log_consistency_sd = .5, step_sd = .6)
    for R in (2, 3, 5), K in (2, 4)
        cells = [(p, i, r) for p in 1:2 for i in 1:2 for r in 1:R]
        data = FacetData((; person = first.(cells), item = getindex.(cells, 2),
            rater = ["R$r" for (_, _, r) in cells], score = mod.(eachindex(cells), K));
            person = :person, item = :item, rater = :rater, score = :score,
            category_levels = 0:(K - 1))
        spec = mfrm_spec(data; family = :mgmfrm, dimensions = 2,
            thresholds = :partial_credit, q_matrix = Bool[1 0; 0 1])
        base = B._mgmfrm_guarded_local_fit_logdensity(spec;
            prior = B._SourceFixturePrior(; scales...))
        bp = base.blueprint
        sd = zeros(bp.n_parameters)
        for (block, scale) in zip((:person, :rater_free, :item,
                :log_item_dimension_discrimination, :log_rater_consistency_free, :item_steps),
                values(scales))
            sd[bp.blocks[block]] .= scale
        end
        C = vcat(Matrix{Float64}(I, R - 1, R - 1), -ones(1, R - 1))
        projection = Matrix{Float64}(I, R, R) - ones(R, R) / R
        for (model, distinguished) in ((:raw, 0), (:exchangeable, 0), (:source, 1), (:source, R))
            target = model === :raw ? base : B._MGMFRMNormalizedPriorLogDensity(spec;
                prior_model = model, scales,
                source_rater = distinguished == 0 ? nothing : data.rater_levels[distinguished])
            lp = model === :raw ? x -> B._source_fixture_logprior(base, x) : x -> B.logprior(target, x)
            covariance = Matrix(Diagonal(sd.^2))
            mu = zeros(length(sd))
            if model !== :raw
                for (block, tau) in ((:rater_free, scales.rater_sd),
                        (:log_rater_consistency_free, scales.log_consistency_sd))
                    indices = bp.blocks[block]
                    covariance[indices, indices] = tau^2 .* (
                        Matrix{Float64}(I, R - 1, R - 1) - ones(R - 1, R - 1) / R)
                end
                H = K - 1
                for i in 1:2
                    indices = bp.blocks[:item_steps][((i - 1) * (H - 1) + 1):(i * (H - 1))]
                    covariance[indices, indices] = scales.step_sd^2 .* (
                        Matrix{Float64}(I, H - 1, H - 1) - ones(H - 1, H - 1) / H)
                end
                if model === :source
                    full_mean = -scales.log_consistency_sd^2 .* projection[:, distinguished]
                    mu[bp.blocks[:log_rater_consistency_free]] = full_mean[1:(R - 1)]
                end
            end
            origin = zeros(length(sd))
            observed_covariance = inv(-ForwardDiff.hessian(lp, origin))
            observed_mean = observed_covariance * ForwardDiff.gradient(lp, origin)
            @test observed_covariance ≈ covariance atol = 1e-12
            @test observed_mean ≈ mu atol = 1e-12
            for x in (origin, mu .+ [.13sin(j) for j in eachindex(mu)])
                expected = -(dot(x - mu, covariance \ (x - mu)) +
                    length(x) * log(2pi) + logdet(covariance)) / 2
                @test lp(x) ≈ expected atol = 1e-11
            end
            for (block, tau) in ((:rater_free, scales.rater_sd),
                    (:log_rater_consistency_free, scales.log_consistency_sd))
                indices = bp.blocks[block]
                full_covariance = C * observed_covariance[indices, indices] * C'
                expected = tau^2 .* (model === :raw ? C * C' : projection)
                @test full_covariance ≈ expected atol = 1e-12
                if block === :log_rater_consistency_free
                    full_mean = C * observed_mean[indices]
                    variance = full_covariance[1, 1] + full_covariance[R, R] -
                        2full_covariance[1, R]
                    @test variance ≈ (model === :raw ? R + 2 : 2) * tau^2
                    if model === :source
                        q = distinguished
                        j = q == 1 ? R : 1
                        @test full_mean[q] - full_mean[j] ≈ -tau^2
                        @test exp(full_mean[q] - full_mean[j] + variance / 2) ≈ 1
                        @test exp(full_mean[q] + full_covariance[q, q] / 2) ≈
                            exp(-tau^2 * (R - 1) / (2R))
                    else
                        @test full_mean ≈ zeros(R) atol = 1e-12
                    end
                end
            end
            if K == 2 && model !== :raw
                # Regression: no step-size-zero range, and an unused SD cannot
                # change the zero-dimensional step block's density or gradient.
                changed = B._MGMFRMNormalizedPriorLogDensity(spec; prior_model = model,
                    scales = merge(scales, (; step_sd = 3 * scales.step_sd)),
                    source_rater = distinguished == 0 ? nothing : data.rater_levels[distinguished])
                x = [.13sin(j) for j in eachindex(sd)]
                @test B.logprior(changed, x) == lp(x)
                @test ForwardDiff.gradient(z -> B.logprior(changed, z), x) ≈
                    ForwardDiff.gradient(lp, x)
            end
        end
    end
end

@testset "Matching average variance is distinct from matching every contrast" begin
    for R in (2, 3, 5), sigma in (.5, 1., 2.)
        C = vcat(Matrix{Float64}(I, R - 1, R - 1), -ones(1, R - 1))
        raw = sigma^2 .* C * C'
        exchangeable = 2sigma^2 .* (Matrix{Float64}(I, R, R) - ones(R, R) / R)
        contrast_variances(S) = [S[i, i] + S[j, j] - 2S[i, j] for i in 1:R for j in (i + 1):R]
        @test mean(diag(raw)) ≈ mean(diag(exchangeable))
        @test mean(contrast_variances(raw)) ≈ mean(contrast_variances(exchangeable)) ≈ 4sigma^2
        @test isapprox(raw, exchangeable) == (R == 2)
    end
end

@testset "Score reflection separates response symmetry from raw-step prior symmetry" begin
    # Y' = K-1-Y: theta,b,severity change sign and steps become -reverse(steps).
    # This checks a category relabelling, not the fixed-label equivalence theorem.
    for K in (2, 3, 4, 6)
        cells = [(p, i, r) for p in 1:2 for i in 1:2 for r in 1:3]
        data = FacetData((; person=first.(cells), item=getindex.(cells, 2),
            rater=last.(cells), score=mod.(eachindex(cells), K));
            person=:person, item=:item, rater=:rater, score=:score,
            category_levels=0:(K-1))
        spec = mfrm_spec(data; family=:mgmfrm, dimensions=2,
            thresholds=:partial_credit, q_matrix=Bool[1 0; 0 1])
        scales = (; person_sd=1., rater_sd=1., item_sd=1.,
            log_discrimination_sd=.5, log_consistency_sd=.5, step_sd=1.)
        base = B._mgmfrm_guarded_local_fit_logdensity(spec;
            prior=B._SourceFixturePrior(; scales...))
        bp = base.blueprint
        raw = [.23sin(j) for j in 1:bp.n_parameters]
        raw[bp.blocks[:item_steps]] .= 0
        m = K-2
        m > 0 && (raw[bp.blocks[:item_steps][1:m]] .= 1)
        reflected = copy(raw)
        for block in (:person, :item, :rater_free)
            reflected[bp.blocks[block]] .*= -1
        end
        if m > 0
            for i in 1:2
                indices = bp.blocks[:item_steps][((i-1)*m+1):(i*m)]
                full = vcat(raw[indices], -sum(raw[indices]))
                reflected[indices] = -reverse(full)[1:m]
            end
        end
        probability(x) = B._mgmfrm_predictive_probabilities_direct(base.design,
            permutedims(B._mgmfrm_source_constrained_params_from_unconstrained(
                base.design, x, bp)))[1, :, :]
        @test probability(reflected) ≈ reverse(probability(raw); dims=2) atol=1e-12
        difference = B._source_fixture_logprior(base, reflected)-B._source_fixture_logprior(base, raw)
        @test difference ≈ (m > 0 ? -(m^2-1)/2 : 0.) atol=1e-12
        for model in (:exchangeable, :source)
            target = B._MGMFRMNormalizedPriorLogDensity(spec; prior_model=model, scales,
                source_rater=model === :source ? 1 : nothing)
            @test B.logprior(target, reflected) ≈ B.logprior(target, raw) atol=1e-12
        end
    end
end

if test_flag("BAYESIANMGMFRM_CMDSTAN_TESTS")
    @testset "Stan positive-coordinate source/exchangeable prior reference (no fitting)" begin
        check = cmdstan_backend_check(; require_ready = true, include_paths = true)
        @info "Prior reference comparison" julia=VERSION cmdstan=check.cmdstan_version
        mktempdir() do directory
            stem = joinpath(directory, "mgmfrm_prior_measure")
            cp(joinpath(@__DIR__, "stan", "mgmfrm_prior_measure.stan"), stem * ".stan")
            make = B._cmdstan_configured_program("MAKE", ("make", "gmake"))
            B._cmdstan_run(Cmd(`$make -f makefile $stem`; dir = check.cmdstan_root), :model_compile)
            executable = B._cmdstan_executable_path(stem)
            max_density_error, max_gradient_error = 0.0, 0.0
            for (R, K) in ((2, 4), (3, 3), (5, 6)), tau in (0.5, 1.0, 2.0), exchangeable in (0, 1)
                m = R - 1
                C = vcat(Matrix{Float64}(I, m, m), -ones(1, m))
                T = C[2:end, :]
                P = 2m + K - 2
                # Compare in the existing package chart; Stan uses FIRST-rater reconstruction.
                map_to_stan(x) = vcat(T * x[1:m], T * x[(m + 1):2m], x[(2m + 1):end])
                density(x) = zero_sum_logdensity(x[1:m], tau) +
                    zero_sum_logdensity(x[(m + 1):2m], 0.8tau, exchangeable == 1 ? 0 : 1) +
                    zero_sum_logdensity(x[(2m + 1):end], 1.3tau)
                points = [zeros(P), [0.2sin(i) + 0.1 for i in 1:P]]
                data_path, points_path, output_path = [joinpath(directory, name)
                    for name in ("data.json", "points.json", "density.csv")]
                write(data_path, JSON3.write((; R, K, exchangeable,
                    severity_sd = tau, consistency_sd = 0.8tau, step_sd = 1.3tau)))
                write(points_path, JSON3.write((; params_r = map_to_stan.(points))))
                jac = ForwardDiff.jacobian(map_to_stan, points[1])
                for jacobian in (0, 1)
                    B._cmdstan_run(`$executable log_prob unconstrained_params=$points_path jacobian=$jacobian data file=$data_path output file=$output_path sig_figs=18 refresh=0`, :density_check)
                    csv = B._cmdstan_read_csv(output_path, length(points))
                    @test csv.header == ["lp__"; ["g_severity_free.$i" for i in 1:m];
                        ["g_consistency_free.$i" for i in 1:m]; ["g_step_free.$i" for i in 1:(K - 2)]]
                    for (row, x) in enumerate(points)
                        # Without Stan's automatic positive-parameter Jacobian,
                        # remove the same +sum(log(alpha_free)) from the expected target.
                        expected(v) = density(v) - (1 - jacobian) * sum(map_to_stan(v)[(m + 1):2m])
                        expected_lp = expected(x)
                        expected_gradient = ForwardDiff.gradient(expected, x)
                        gradient = jac' * csv.values[row, 2:end]
                        @test csv.values[row, 1] ≈ expected_lp atol = 1e-10 rtol = 1e-10
                        @test all(isapprox.(gradient, expected_gradient; atol = 1e-9, rtol = 1e-10))
                        max_density_error = max(max_density_error, abs(csv.values[row, 1] - expected_lp))
                        max_gradient_error = max(max_gradient_error, maximum(abs.(gradient - expected_gradient)))
                    end
                end
            end
            @info "Prior reference errors" max_density_error max_gradient_error
        end
    end
end

end # module
