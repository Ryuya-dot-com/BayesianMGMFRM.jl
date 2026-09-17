module MFRMCorrelated2DResultChecks
using Test, BayesianMGMFRM, Random, Statistics
const B = BayesianMGMFRM
include("fixtures/correlated_fixed_q_result.jl")

@testset "correlated fixed-Q results (synthetic, no sampling)" begin
    for categories in (2, 4), backend in (:advancedhmc, :cmdstan)
        cells = [(p, i, r) for p in 1:2 for i in 1:4 for r in 1:2]
        data = FacetData((; person = first.(cells), item = getindex.(cells, 2),
            rater = last.(cells), score = [mod(sum(cell), categories) for cell in cells]);
            person = :person, item = :item, rater = :rater, score = :score,
            category_levels = 0:(categories - 1))
        spec = mfrm_spec(data; family = :mfrm, dimensions = 2, thresholds = :partial_credit,
            q_matrix = Bool[1 0; 1 0; 0 1; 0 1], dimension_labels = ["First", "Second"])
        target = B._MFRMFixedQCorrelated2DLogDensity(spec; prior = MFRMPrior(), lkj_eta = 3)
        initial = initial_params(target)
        draws = [initial[p] + 0.35 * sin(d + p) + 0.2 for d in 1:8, p in eachindex(initial)]
        logdensities = [B.LogDensityProblems.logdensity(target, row) for row in eachrow(draws)]
        chain_ids, iterations = repeat(1:2; inner = 4), repeat(1:4; outer = 2)
        controls = (; ndraws = 4, chains = 2, warmup = 0, step_size = 0.1,
            target_accept = 0.8, max_depth = 2, max_energy_error = 1000.0,
            init_jitter = 0.0, metric = :diagonal)
        controls = merge(controls, backend === :advancedhmc ?
            (; ad_backend = :ForwardDiff, gradient_backend = :ad) :
            (; ad_backend = :stan_reverse_mode, gradient_backend = :stan_autodiff,
                execution = :cmdstan_cli, thinning = 1))
        stats = NamedTuple[B._advancedhmc_stat_row((; log_density = logdensities[d],
            step_size = 0.1, acceptance_rate = 0.75, hamiltonian_energy = Float64(d)),
            chain_ids[d], iterations[d]) for d in 1:8]
        backend === :cmdstan && (stats = NamedTuple[merge(stat, (; stan_lp = stat.log_density)) for stat in stats])
        chain_acceptance = fill(0.75, 2)
        run = (; checked = B._check_diagnostic_thresholds(1.01, 400), nparams = length(initial), initial,
            initial_logdensity = B.LogDensityProblems.logdensity(target, initial), total_draws = 8,
            draws, logdensities, chain_ids, iterations, chain_acceptance, sampler_stats = stats, controls,
            sampler_rows = B._generalized_candidate_sampler_rows(logdensities, iterations,
                chain_acceptance, stats, controls, backend), backend, sampler = :nuts,
            split_chains_requested = true, actual_split = true)
        record = (; schema = "bayesianmgmfrm.correlated_fixed_q_mfrm_samples.v1", base_spec = spec,
            prior = B._mfrm_correlated_2d_prior_record(target),
            target_identity = B._mfrm_correlated_2d_identity(target), run)
        record = merge(record, (; content_hash = B._mgmfrm_normalized_sample_hash(record)))
        result = B._restore_mfrm_correlated_2d_samples(record; expected_identity = record.target_identity)
        mktempdir(directory -> check_correlated_fixed_q_result(result, directory))
    end
end
end
