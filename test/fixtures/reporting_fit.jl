# Deterministic reporting inputs, never posterior or backend-validation evidence.
function reporting_fit(family; backend = :advancedhmc, warmup = 3, recorded = true,
        thresholds = :partial_credit, data = nothing, ndraws = 4, chains = 1,
        rhat_threshold = 1.01, ess_threshold = 400, spec_kwargs...)
    data === nothing && (data = FacetData((; person = [1, 1, 1, 2, 2, 2], item = [1, 1, 2, 1, 2, 2],
        rater = [1, 2, 1, 1, 2, 1], score = [0, 1, 2, 1, 0, 2]);
        person = :person, item = :item, rater = :rater, score = :score))
    spec = mfrm_spec(data; family, thresholds,
        discrimination = family === :gmfrm ? :rater : :none,
        dimensions = family === :mgmfrm ? 2 : 1,
        q_matrix = family === :mgmfrm ? Bool[1 0; 0 1] : nothing, spec_kwargs...)
    design = getdesign(spec; preview = family !== :mfrm)
    target = family === :mfrm ? MFRMLogDensity(design) : family === :gmfrm ?
        B._gmfrm_promotion_candidate_logdensity(design) : B._mgmfrm_guarded_local_fit_logdensity(design)
    initial = initial_params(target)
    total_draws = ndraws * chains
    chain_ids = repeat(collect(1:chains); inner = ndraws)
    iterations = repeat(collect(1:ndraws), chains)
    draws = [initial[p] + 0.01 * sin(d + p) for d in 1:total_draws, p in eachindex(initial)]
    density = family === :mfrm ? x -> logposterior(design, x) : x -> B._source_fixture_logposterior(target, x)
    logdensities = density.(eachrow(draws))
    controls = (; ndraws, chains, warmup, step_size = 0.1, max_depth = 2, init_jitter = 0.0)
    warmup_stats = recorded ? NamedTuple[(; chain, iteration = i,
        divergent = i == 1, tree_depth = i == 3 ? 2 : 1, nonfinite_logdensity = i == 2)
        for chain in 1:chains for i in 1:warmup] : nothing
    stats = NamedTuple[B._advancedhmc_stat_row((; log_density = logdensities[d],
        step_size = 0.1, acceptance_rate = 0.75, hamiltonian_energy = Float64(d)), chain_ids[d], iterations[d]) for d in 1:total_draws]
    if family === :mfrm
        return MFRMFit(design, MFRMPrior(), draws, logdensities, 0.75, chain_ids,
            iterations, fill(0.75, chains), backend, :nuts, warmup, 0.1, stats,
            B._with_warmup_diagnostics(controls, warmup_stats, backend))
    end
    run = (; checked = B._check_diagnostic_thresholds(rhat_threshold, ess_threshold), nparams = length(initial), initial,
        initial_logdensity = density(initial), total_draws, draws, logdensities,
        chain_ids, iterations, chain_acceptance = fill(0.75, chains),
        sampler_stats = stats, controls, backend, sampler = :nuts, warmup_stats,
        sampler_rows = B._generalized_candidate_sampler_rows(logdensities, iterations,
            fill(0.75, chains), stats, controls, backend), split_chains_requested = true, actual_split = chains >= 2 && ndraws >= 4)
    surface = family === :gmfrm ? B._gmfrm_promotion_candidate_diagnostic_surface(target, run) :
        B._mgmfrm_guarded_local_fit_diagnostic_surface(target, run)
    return family === :gmfrm ? B._gmfrm_fit_from_sampler_diagnostics(design, target.prior, surface) :
        B._mgmfrm_fit_from_sampler_diagnostics(design, target.prior, surface)
end
