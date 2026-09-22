isdefined(@__MODULE__, :MGMFRMCorrelated2DFixtures) || include("mgmfrm_correlated_2d_fixtures.jl")
module MGMFRMCorrelated2DPredictiveChecks
using Test, BayesianMGMFRM, Random, Statistics, Serialization
using ..MGMFRMCorrelated2DFixtures: target, synthetic_record, rehash
const B = BayesianMGMFRM
const E = B.Experimental

prior(t) = E.GeneralizedPrior(; B._source_fixture_prior_values(t.prior.source_prior)...)
model(t) = E.correlated(t.base.design.spec; lkj_eta = t.prior.lkj_eta)
asfit(r) = E.CorrelatedMGMFRMFit(r; expected_identity = r.target_identity)
serialized(x) = (io = IOBuffer(); serialize(io, x); take!(io))

# Independent pure-Q adjacent-category calculation, including all raw transforms.
# No production probability, loading-index or step-reconstruction helper is used.
function reference_probabilities(t, raw; multiplier = 1.7)
    spec = t.base.design.spec; data = spec.data; blocks = t.base.blueprint.blocks
    K = length(data.category_levels)
    rfree = raw[blocks[:rater_free]]; severity = [rfree; -sum(rfree)]
    gfree = raw[blocks[:log_rater_consistency_free]]; gamma = exp.([gfree; -sum(gfree)])
    loadings = exp.(raw[blocks[:log_item_dimension_discrimination]])
    steps = reshape(raw[blocks[:item_steps]], K - 2, length(data.item_levels))
    probs = zeros(data.n, K)
    for n in 1:data.n
        p, i, r = data.person[n], data.item[n], data.rater[n]
        d = only(findall(spec.q_matrix[i, :]))
        theta = raw[blocks[:person][2(p - 1) + d]]
        eta = loadings[i] * theta - raw[blocks[:item][i]] - severity[r]
        step = [0; steps[:, i]; -sum(steps[:, i])]
        logits = [0; cumsum(multiplier * gamma[r] .* (eta .- step[2:end]))]
        probs[n, :] = exp.(logits .- maximum(logits))
        probs[n, :] ./= sum(probs[n, :])
    end
    return probs
end

function check_probabilities(t, raw, probabilities)
    @test size(probabilities) == (size(raw, 1), t.base.design.spec.data.n,
        length(t.base.design.spec.data.category_levels))
    @test all(isfinite, probabilities) && all(0 .<= probabilities .<= 1)
    @test all(isapprox.(sum(probabilities; dims = 3), 1; atol = 1e-14))
    for d in axes(raw, 1)
        @test probabilities[d, :, :] ≈ reference_probabilities(t, raw[d, :]) atol = 1e-13
        pointwise = B._mgmfrm_free_latent_correlation_2d_pointwise_loglikelihood(t, raw[d, :])
        data = t.base.design.spec.data
        @test pointwise ≈ [log(probabilities[d, n, data.category[n]]) for n in 1:data.n] atol = 1e-12
    end
end

@testset "correlated MGMFRM joint prior and existing-row simulation" begin
    for K in (2, 4), raters in (1, 3)
        t = target(; K, raters); spec = model(t); p = prior(t)
        check = E.prior_predictive_check(spec; prior = p, ndraws = 31, rng = MersenneTwister(83))
        @test isequal(check, E.prior_predictive_check(spec; prior = p, ndraws = 31, rng = MersenneTwister(83)))
        @test check.replicated_scores == E.prior_predict(spec; prior = p, ndraws = 31, rng = MersenneTwister(83))
        @test size(check.replicated_scores) == (31, t.base.design.spec.data.n)
        @test all(in(t.base.design.spec.data.category_levels), check.replicated_scores)
        @test check.prediction_conditioning === :joint_prior && check.prediction_target === :existing_rating_rows
        @test !check.new_facet_levels && check.likelihood_scale == 1.7
        @test check.prior.scales == B._source_fixture_prior_values(t.prior.source_prior)
        @test check.prior.lkj_eta == t.prior.lkj_eta && check.prior.correlation_prior_measure === :d_rho
        @test check.target_identity == B._mgmfrm_correlated_2d_identity(t)
        @test check.raw_parameter_names == t.blueprint.parameter_names
        @test check.direct_parameter_names == B._mgmfrm_correlated_2d_sample_blueprint(t).constrained_parameter_names
        @test check.direct_parameter_draws[:, end] == tanh.(check.raw_parameter_draws[:, end])
        @test !hasproperty(check, :draw_indices)
        @test !isempty(predictive_check_summary(check; include_grouped = true))
        direct = check.direct_parameter_draws[:, 1:end-1]
        probabilities = B._mgmfrm_predictive_probabilities_direct(t.base.design, direct)
        check_probabilities(t, check.raw_parameter_draws, probabilities)
        # Observed scores do not update the simulated prior, even with unused categories.
        data = t.base.design.spec.data
        changed_scores = fill(first(data.category_levels), data.n)
        changed_scores[end] = last(data.category_levels)
        changed_data = B._facet_data_with_scores(data, changed_scores)
        changed = E.correlated(mfrm_spec(changed_data; family = :mgmfrm, dimensions = 2,
            q_matrix = spec.base_spec.q_matrix, dimension_labels = spec.base_spec.dimension_labels); lkj_eta = spec.lkj_eta)
        updated = E.prior_predictive_check(changed; prior = p, ndraws = 31, rng = MersenneTwister(83))
        @test updated.parameter_draws == check.parameter_draws
        @test updated.replicated_scores == check.replicated_scores
        @test updated.observed.mean_score == mean(changed_scores)
        @test updated.target_identity != check.target_identity
        @test size(E.prior_predict(spec; prior = p, ndraws = 1)) == (1, data.n)
        contract = E.surface_contract(spec)
        @test contract.prior.prior_predict_available && contract.prior.prior_predictive_check_available
        @test contract.predictive_checks_available && contract.predictive_probabilities_available
        @test contract.posterior_predict_available && !contract.new_facet_levels
        @test contract.reports_available && !contract.automatic_cache_enabled
    end
end

@testset "normalized joint prior generation matches the fitting density" begin
    for eta in (1, 2, 5, 10_000)
        t = target(; eta); p = prior(t)
        draws = B._mgmfrm_correlated_2d_prior_draws(t, 20_000, MersenneTwister(172 + eta))
        rho = tanh.(draws[:, end]); x = draws[:, 1] ./ p.person_sd; y = draws[:, 2] ./ p.person_sd
        residual = (y .- rho .* x) ./ sqrt.(1 .- rho.^2)
        @test all(-1 .< rho .< 1)
        @test abs(mean(rho)) < 0.025
        @test isapprox(mean(rho.^2), 1 / (2eta + 1); rtol = 0.04)
        @test abs(mean(x)) < 0.04 && abs(mean(y)) < 0.04
        @test abs(var(x) - 1) < 0.04 && abs(var(y) - 1) < 0.04
        @test abs(mean(residual)) < 0.04 && abs(var(residual) - 1) < 0.04
        @test abs(cor(x, residual)) < 0.04
        @test abs(mean(x .* y .* rho) - 1 / (2eta + 1)) < 0.025
        for j in 7:(size(draws, 2) - 1)
            sd = B._source_fixture_prior_sd(t.base, j)
            @test abs(mean(draws[:, j]) / sd) < 0.04
            @test abs(var(draws[:, j]) / sd^2 - 1) < 0.04
        end
        for d in 1:4
            row = draws[d, :]; r = rho[d]
            lp = B.Turing.logpdf(B.Turing.Beta(eta, eta), (r + 1) / 2) - log(2) + log1p(-r * r)
            for j in 1:2:6
                lp += B.Turing.logpdf(B.Turing.MvNormal(zeros(2), p.person_sd^2 .* [1 r; r 1]), row[j:j+1])
            end
            for j in 7:(length(row) - 1)
                lp += B.Turing.logpdf(B.Turing.Normal(0, B._source_fixture_prior_sd(t.base, j)), row[j])
            end
            likelihood = B._mgmfrm_free_latent_correlation_2d_loglikelihood(t, row)
            @test B.LogDensityProblems.logdensity(t, row) ≈ likelihood + lp atol = 1e-9
        end
    end
end

@testset "correlated posterior prediction, selection and cache replay" begin
    for K in (2, 4), backend in (:advancedhmc, :cmdstan)
        t = target(; K, raters = K == 2 ? 1 : 3)
        record = synthetic_record(t; backend); fit = asfit(record); snapshot = serialized(fit.record)
        indices = [40, 1, 13, 1]
        probs = predictive_probabilities(fit; draw_indices = indices)
        check_probabilities(t, record.run.draws[indices, :], probs)
        @test probs[2, :, :] == probs[4, :, :]
        @test size(predictive_probabilities(fit), 1) == 40
        @test predictive_probabilities(fit; ndraws = 7, rng = MersenneTwister(23)) ==
            predictive_probabilities(fit; draw_indices = rand(MersenneTwister(23), 1:40, 7))
        check = posterior_predictive_check(fit; draw_indices = indices, rng = MersenneTwister(37))
        @test check.replicated_scores == posterior_predict(fit; draw_indices = indices, rng = MersenneTwister(37))
        @test check.draw_indices == indices && check.draw_indices !== indices
        @test check.prior == fit_metadata(fit).prior
        @test check.target_identity == record.target_identity && check.source_sample_content_hash == record.content_hash
        @test check.sampling_quality === diagnostics(fit).summary.flag
        @test check.prediction_conditioning === :joint_posterior_existing_levels
        @test check.backend === backend && !check.new_facet_levels
        @test all(in(record.spec.data.category_levels), check.replicated_scores)
        @test !isempty(predictive_check_summary(check; include_grouped = true))
        random_check = posterior_predictive_check(fit; ndraws = 80, rng = MersenneTwister(37))
        @test length(random_check.draw_indices) == 80 && length(unique(random_check.draw_indices)) < 80
        @test random_check.replicated_scores == posterior_predict(fit; ndraws = 80, rng = MersenneTwister(37))
        # Changing only population rho cannot change conditional response probabilities.
        draws = copy(record.run.draws); draws[:, end] .= 0.8
        lp = [B.LogDensityProblems.logdensity(t, row) for row in eachrow(draws)]
        stats = [merge(s, (; log_density = l), backend === :cmdstan ? (; stan_lp = l) : (;))
            for (s, l) in zip(record.run.sampler_stats, lp)]
        run = merge(record.run, (; draws, logdensities = lp, sampler_stats = stats))
        run = merge(run, (; sampler_rows = B._generalized_candidate_sampler_rows(lp, run.iterations,
            run.chain_acceptance, stats, run.controls, backend)))
        changed = asfit(rehash(merge(record, (; run))))
        @test predictive_probabilities(changed; draw_indices = indices) == probs
        @test !(reference_probabilities(t, draws[1, :]; multiplier = 1.0) ≈ probs[2, :, :])
        for op in (predictive_probabilities, posterior_predict, posterior_predictive_check)
            for kwargs in ((; ndraws = 0), (; draw_indices = Int[]), (; draw_indices = [0]),
                    (; draw_indices = [41]), (; ndraws = 1, draw_indices = [1]))
                @test_throws ArgumentError op(fit; kwargs...)
            end
            bad = deepcopy(fit); bad.record.run.draws[1, end] += 0.2
            @test_throws ArgumentError op(bad)
        end
        mktempdir() do dir
            path = joinpath(dir, "fit.jls"); save_fit_cache(path, fit)
            bytes = read(path); loaded = load_fit_cache(path)
            @test predictive_probabilities(loaded; draw_indices = indices) == probs
            @test isequal(posterior_predictive_check(loaded; draw_indices = indices, rng = MersenneTwister(37)), check)
            @test read(path) == bytes
        end
        @test serialized(fit.record) == snapshot
    end
end

@testset "prediction rejects invalid inputs without advancing caller RNG" begin
    t = target(); m = model(t); p = prior(t); fit = asfit(synthetic_record(t))
    for op in (E.prior_predict, E.prior_predictive_check)
        for invalid in (nothing, MFRMPrior(), t.prior.source_prior, E.ExchangeablePrior(; rater_kernel_sd = 0.4))
            rng = MersenneTwister(1)
            @test_throws ArgumentError op(m; prior = invalid, rng)
            @test rand(rng) == rand(MersenneTwister(1))
        end
        @test_throws ArgumentError op(m; prior = p, ndraws = 0)
        @test_throws ArgumentError op(m; prior = p, experimental = true)
        changed = deepcopy(m); changed.base_spec.q_matrix[1, 2] = true
        @test_throws ArgumentError op(changed; prior = p)
    end
    for kwargs in ((; min_category_probability = -1), (; prior_warning_probability = NaN),
            (; wide_facet_range_fraction = -1))
        rng = MersenneTwister(1)
        @test_throws ArgumentError E.prior_predictive_check(m; prior = p, rng, kwargs...)
        @test rand(rng) == rand(MersenneTwister(1))
    end
    Random.seed!(921); expected = rand(); Random.seed!(921)
    E.prior_predictive_check(m; prior = p, ndraws = 3, rng = MersenneTwister(7))
    posterior_predictive_check(fit; ndraws = 3, rng = MersenneTwister(7))
    @test rand() == expected
end
end
