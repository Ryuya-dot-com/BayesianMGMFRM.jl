# Deterministic saved formats, not posterior or backend-comparison evidence.
function prediction_fixed_fixture(kind; K=4, backend=:advancedhmc, D=2, mixed=false)
    cells = [(p,i,r) for p in 1:3 for i in 1:2D for r in 1:2]
    data = FacetData((; person=first.(cells), item=getindex.(cells,2), rater=last.(cells),
        score=[mod(sum(c),K) for c in cells]); person=:person, item=:item, rater=:rater,
        score=:score, category_levels=0:(K-1))
    q = Bool[d == cld(i,2) for i in 1:2D, d in 1:D]
    mixed && (q[2,2]=true)
    spec = mfrm_spec(data; family=kind === :legacy ? :mgmfrm : :mfrm,
        dimensions=D, q_matrix=q, thresholds=:partial_credit)
    correlated = kind in (:correlated, :exchangeable_correlated)
    model = correlated ? B.Experimental.correlated(spec; lkj_eta=3) : spec
    exchangeable = kind in (:exchangeable, :exchangeable_correlated)
    target = exchangeable ? B._MFRMExchangeableRatersLogDensity(model;
        scales=(; person_sd=.7, rater_kernel_sd=.4, item_sd=.6, step_sd=.5)) :
        correlated ? B._MFRMFixedQCorrelated2DLogDensity(spec; prior=MFRMPrior(), lkj_eta=3) :
        B._MFRMFixedQReferenceLogDensity(spec; prior=MFRMPrior())
    initial = initial_params(target)
    draws = [.15sin(s+p)+.2 for s in 1:40, p in eachindex(initial)]
    logdensities = [B.LogDensityProblems.logdensity(target, row) for row in eachrow(draws)]
    chain_ids, iterations = repeat(1:2; inner=20), repeat(1:20; outer=2)
    controls = (; ndraws=20, chains=2, warmup=0, step_size=.1, target_accept=.8,
        max_depth=2, max_energy_error=1000., init_jitter=0., metric=:diagonal)
    controls = merge(controls, backend === :advancedhmc ? (; ad_backend=:ForwardDiff, gradient_backend=:ad) :
        (; ad_backend=:stan_reverse_mode, gradient_backend=:stan_autodiff, execution=:cmdstan_cli, thinning=1))
    stats = NamedTuple[B._advancedhmc_stat_row((; log_density=logdensities[s], step_size=.1,
        acceptance_rate=.75, hamiltonian_energy=Float64(s)), chain_ids[s], iterations[s]) for s in 1:40]
    backend === :cmdstan && (stats=NamedTuple[merge(s,(;stan_lp=s.log_density)) for s in stats])
    acceptance=fill(.75,2)
    run = (; checked=B._check_diagnostic_thresholds(1.01,400), nparams=length(initial), initial,
        initial_logdensity=B.LogDensityProblems.logdensity(target,initial), total_draws=40, draws,
        logdensities, chain_ids, iterations, chain_acceptance=acceptance, sampler_stats=stats, controls,
        sampler_rows=B._generalized_candidate_sampler_rows(logdensities,iterations,acceptance,stats,controls,backend),
        backend, sampler=:nuts, split_chains_requested=true, actual_split=true, warmup_stats=NamedTuple[])
    record = if exchangeable
        (; schema="bayesianmgmfrm.exchangeable_rater_mfrm_samples.v1", spec=model,
            prior=B._mfrm_exchangeable_rater_record(target), target_identity=B._mfrm_exchangeable_rater_identity(target), run)
    elseif correlated
        (; schema="bayesianmgmfrm.correlated_fixed_q_mfrm_samples.v1", base_spec=spec,
            prior=B._mfrm_correlated_2d_prior_record(target), target_identity=B._mfrm_correlated_2d_identity(target), run)
    else
        (; schema=kind === :legacy ? "bayesianmgmfrm.fixed_q_mfrm_samples.v1" : "bayesianmgmfrm.fixed_q_mfrm_samples.v2",
            spec, prior=B._mfrm_fixed_q_prior_record(target), target_identity=B._mfrm_fixed_q_identity(target), run)
    end
    record = merge(record,(;content_hash=B._mgmfrm_normalized_sample_hash(record)))
    fit_type = exchangeable ? B._ExchangeableMFRMFit : correlated ? B._CorrelatedMFRMFit : B.MultidimensionalMFRMFit
    fit = fit_type(record; expected_identity=record.target_identity)
    reference = exchangeable ? B._mfrm_exchangeable_rater_reference(target) : correlated ? target.base : target
    return (; fit, reference)
end
