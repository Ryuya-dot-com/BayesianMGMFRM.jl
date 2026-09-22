# Private complete fixed-Q targets and sample records; no public fit/cache dispatch.
struct _MGMFRMNormalizedPriorLogDensity
    base::_MGMFRMGuardedLocalFitLogDensity
    prior_model::Symbol
    source_rater_index::Int

    function _MGMFRMNormalizedPriorLogDensity(spec::FacetSpec;
            prior_model::Symbol, scales::NamedTuple, source_rater = nothing)
        prior_model in (:source, :exchangeable) || throw(ArgumentError(
            "prior_model must be :source or :exchangeable"))
        Set(keys(scales)) == Set(fieldnames(_SourceFixturePrior)) || throw(ArgumentError(
            "all six prior scales must be explicitly specified"))
        # Reuse validated scalar storage, not the legacy prior's joint distribution.
        prior = _SourceFixturePrior(; scales...)
        base = _mgmfrm_guarded_local_fit_logdensity(spec; prior)
        index = 0
        if prior_model === :source
            source_rater === nothing && throw(ArgumentError(
                "the source prior requires an explicit source_rater ID"))
            found = findfirst(isequal(source_rater), base.design.spec.data.rater_levels)
            found === nothing && throw(ArgumentError("source_rater ID is absent from the data"))
            index = found
            R = length(base.design.spec.data.rater_levels)
            isfinite(((R - 1) / (2R) * prior.log_consistency_sd) * prior.log_consistency_sd) ||
                throw(ArgumentError("source consistency scale gives a non-finite normalizer"))
        else
            source_rater === nothing || throw(ArgumentError(
                "the exchangeable prior has no distinguished source_rater"))
        end
        return new(base, prior_model, index)
    end
end

function _mgmfrm_normalized_prior_record(target::_MGMFRMNormalizedPriorLogDensity)
    return (;
        schema = Symbol("bayesianmgmfrm.normalized_fixed_q_prior.v1"),
        prior_model = target.prior_model,
        scale_convention = :kernel_sd_for_centered_blocks,
        parameter_measure = :last_reconstructed_free_coordinates,
        source_rater = target.source_rater_index == 0 ? nothing :
            deepcopy(target.base.design.spec.data.rater_levels[target.source_rater_index]),
        scales = _source_fixture_prior_values(target.base.prior),
    )
end

function _mgmfrm_normalized_prior_identity(target::_MGMFRMNormalizedPriorLogDensity)
    return _cache_hash((;
        design = design_identity(target.base.design).value,
        prior = _mgmfrm_normalized_prior_record(target),
    ))
end

# In-memory record verification; this does not read or reuse any fit cache.
function _MGMFRMNormalizedPriorLogDensity(spec::FacetSpec, record::NamedTuple;
        expected_identity::AbstractString)
    Set(keys(record)) == Set((:schema, :prior_model, :scale_convention,
        :parameter_measure, :source_rater, :scales)) || throw(ArgumentError(
            "unrecognized normalized-prior record fields"))
    record.schema === Symbol("bayesianmgmfrm.normalized_fixed_q_prior.v1") &&
        record.scale_convention === :kernel_sd_for_centered_blocks &&
        record.parameter_measure === :last_reconstructed_free_coordinates ||
        throw(ArgumentError("unrecognized normalized-prior record contract"))
    record.prior_model isa Symbol && record.scales isa NamedTuple ||
        throw(ArgumentError("invalid normalized-prior record values"))
    target = _MGMFRMNormalizedPriorLogDensity(spec;
        prior_model = record.prior_model, scales = record.scales,
        source_rater = record.source_rater)
    _mgmfrm_normalized_prior_identity(target) == expected_identity ||
        throw(ArgumentError("normalized-prior target identity mismatch"))
    return target
end

# Normalized full-vector zero-sum normal minus independent free-coordinate normals.
_zero_sum_prior_correction(v, sd::Float64) =
    log(length(v) + 1) / 2 - (sum(v) / sd)^2 / 2

function logprior(target::_MGMFRMNormalizedPriorLogDensity, raw::AbstractVector)
    base = target.base
    lp = _source_fixture_logprior(base, raw) # Also validates length and finite coordinates.
    blocks, prior = base.blueprint.blocks, base.prior
    lp += _zero_sum_prior_correction(view(raw, blocks[:rater_free]), prior.rater_sd)
    consistency = view(raw, blocks[:log_rater_consistency_free])
    lp += _zero_sum_prior_correction(consistency, prior.log_consistency_sd)
    nsteps = length(base.design.spec.data.category_levels) - 2
    steps = blocks[:item_steps]
    for start in first(steps):nsteps:last(steps)
        lp += _zero_sum_prior_correction(view(raw, start:(start + nsteps - 1)), prior.step_sd)
    end
    if target.prior_model === :source
        R = length(consistency) + 1
        ell = target.source_rater_index == R ? -sum(consistency) : consistency[target.source_rater_index]
        lp -= ell + ((R - 1) / (2R) * prior.log_consistency_sd) * prior.log_consistency_sd
    end
    return lp
end

LogDensityProblems.dimension(target::_MGMFRMNormalizedPriorLogDensity) =
    LogDensityProblems.dimension(target.base)
LogDensityProblems.capabilities(::Type{_MGMFRMNormalizedPriorLogDensity}) =
    LogDensityProblems.LogDensityOrder{0}()
LogDensityProblems.logdensity(target::_MGMFRMNormalizedPriorLogDensity, raw) =
    _source_fixture_loglikelihood(target.base, raw) + logprior(target, raw)
initial_params(target::_MGMFRMNormalizedPriorLogDensity) = initial_params(target.base)

function _cmdstan_mgmfrm_data(target::_MGMFRMNormalizedPriorLogDensity)
    return merge(_cmdstan_mgmfrm_data(target.base), (;
        prior_model = target.prior_model === :source ? 1 : 2,
        source_rater = target.source_rater_index,
    ))
end

_check_source_fixture_raw_vector(target::_MGMFRMNormalizedPriorLogDensity, raw::AbstractVector) =
    _check_source_fixture_raw_vector(target.base, raw)
_cmdstan_generalized_family(::_MGMFRMNormalizedPriorLogDensity) = :mgmfrm
_cmdstan_generalized_data(target::_MGMFRMNormalizedPriorLogDensity) =
    _cmdstan_mgmfrm_data(target)
function _cmdstan_generalized_chain_result(path::AbstractString,
        target::_MGMFRMNormalizedPriorLogDensity, chain::Int, ndraws::Int; warmup::Int = 0)
    parsed = _cmdstan_mgmfrm_chain_result(path, target.base, chain, ndraws;
        density_target = target, warmup)
    # Stan's beta ~ normal statement drops these constants; explicit centered
    # corrections remain in lp__. Check the prior branch as well as log_lik.
    constant = _source_fixture_logprior(target.base, zeros(LogDensityProblems.dimension(target)))
    all(isapprox(stat.stan_lp + constant, lp; atol = 1e-8, rtol = 1e-8)
        for (stat, lp) in zip(parsed.stats, parsed.logps)) || throw(CmdStanError(
            :output_parse, :log_posterior_mismatch,
            "CmdStan and Julia normalized-prior log posteriors disagree"))
    return parsed
end

function _check_generalized_sample_run(target, run::NamedTuple)
    legacy_keys = (:checked, :nparams, :initial, :initial_logdensity, :total_draws,
        :draws, :logdensities, :chain_ids, :iterations, :chain_acceptance,
        :sampler_stats, :controls, :sampler_rows, :backend, :sampler,
        :split_chains_requested, :actual_split)
    keys(run) in (legacy_keys, (legacy_keys..., :warmup_stats)) ||
        throw(ArgumentError("unrecognized generalized sample fields"))
    run.backend in (:advancedhmc, :cmdstan) && run.sampler === :nuts ||
        throw(ArgumentError("unrecognized generalized sampler"))
    controls = run.controls
    _check_fit_controls(controls.ndraws, controls.warmup, controls.chains, controls.step_size)
    _check_nuts_controls(controls.target_accept, controls.max_depth,
        controls.max_energy_error, controls.init_jitter)
    if run.backend === :advancedhmc
        controls.gradient_backend === _gradient_backend_kind(controls.ad_backend) ||
            throw(ArgumentError("generalized Julia gradient backend mismatch"))
        _advancedhmc_metric(controls.metric, LogDensityProblems.dimension(target))
    else
        controls.ad_backend === :stan_reverse_mode && controls.gradient_backend === :stan_autodiff &&
            controls.execution === :cmdstan_cli && controls.thinning == 1 &&
            controls.max_energy_error == 1000.0 ||
            throw(ArgumentError("generalized CmdStan controls mismatch"))
        _cmdstan_metric(controls.metric)
    end
    _check_diagnostic_thresholds(run.checked.rhat_threshold, run.checked.ess_threshold)
    n, p = Base.checked_mul(controls.chains, controls.ndraws), LogDensityProblems.dimension(target)
    run.nparams == p && run.total_draws == n &&
        run.draws isa Matrix{Float64} && size(run.draws) == (n, p) &&
        run.logdensities isa Vector{Float64} && length(run.logdensities) == n &&
        all(isfinite, run.draws) && all(isfinite, run.logdensities) ||
        throw(ArgumentError("invalid generalized sample dimensions or values"))
    run.chain_ids == repeat(1:controls.chains; inner = controls.ndraws) &&
        run.iterations == repeat(1:controls.ndraws; outer = controls.chains) &&
        length(run.sampler_stats) == n &&
        length(run.chain_acceptance) == controls.chains &&
        all(x -> isfinite(x) && 0 <= x <= 1, run.chain_acceptance) &&
        run.split_chains_requested isa Bool &&
        run.actual_split === (run.split_chains_requested && controls.chains >= 2 && controls.ndraws >= 4) ||
        throw(ArgumentError("invalid generalized chain layout"))
    _check_source_fixture_raw_vector(target, run.initial)
    isfinite(run.initial_logdensity) &&
        isapprox(LogDensityProblems.logdensity(target, run.initial), run.initial_logdensity;
        atol = 1e-8, rtol = 1e-10) ||
        throw(ArgumentError("generalized initial density mismatch"))
    for row in 1:n
        chain = run.chain_ids[row]
        _with_sampler_context(run.backend, chain, :output_validation) do
            stat = run.sampler_stats[row]
            stat.chain == chain && stat.iteration == run.iterations[row] &&
                stat.is_adapt === false && 0 <= stat.acceptance_rate <= 1 &&
                stat.log_density == run.logdensities[row] ||
                throw(ArgumentError("invalid retained sampler-stat row $row"))
            lp = LogDensityProblems.logdensity(target, view(run.draws, row, :))
            isfinite(lp) && isapprox(lp, run.logdensities[row]; atol = 1e-8, rtol = 1e-10) ||
                throw(ArgumentError("generalized retained density mismatch at row $row"))
        end
    end
    for chain in 1:controls.chains
        stats = run.sampler_stats[((chain - 1) * controls.ndraws + 1):(chain * controls.ndraws)]
        isequal(run.chain_acceptance[chain], _stat_mean(stats, :acceptance_rate)) ||
            throw(ArgumentError("generalized chain acceptance mismatch"))
    end
    rows = _generalized_candidate_sampler_rows(run.logdensities, run.iterations,
        run.chain_acceptance, run.sampler_stats, controls, run.backend)
    isequal(rows, run.sampler_rows) ||
        throw(ArgumentError("generalized sampler summary mismatch"))
    return nothing
end

# Hash only canonical records. The separately verified target identity covers the
# spec/data; generic display of a FacetSpec is not a content hash.
_mgmfrm_normalized_sample_hash(record::NamedTuple) = _cache_hash((;
    record.schema, record.prior, record.target_identity, record.run))

function _mgmfrm_normalized_prior_samples(target, record::NamedTuple)
    _check_generalized_sample_run(target, record.run)
    # Parameter transforms and MCMC metrics do not depend on the prior's density.
    tables = _generalized_candidate_diagnostic_tables(target.base, record.run)
    tables.n_nonfinite_direct_loglikelihood == 0 && tables.n_failed_direct_constraints == 0 &&
        all(isfinite, tables.direct_values.direct_draws) ||
        throw(ArgumentError("normalized-prior direct draw validation failed"))
    return (;
        record,
        public_fit = false,
        raw_parameter_names = copy(target.base.blueprint.parameter_names),
        direct_parameter_names = copy(target.base.blueprint.constrained_parameter_names),
        diagnostics = tables,
        warmup_diagnostics = _warmup_diagnostic_rows(
            get(record.run, :warmup_stats, nothing), record.run.controls, record.run.backend),
    )
end

function _mgmfrm_normalized_prior_sample(target::_MGMFRMNormalizedPriorLogDensity,
        raw_initial::AbstractVector = initial_params(target);
        backend::Symbol = :advancedhmc, record_warmup::Bool = true, kwargs...)
    runner = backend === :advancedhmc ? _run_generalized_candidate_advancedhmc :
        backend === :cmdstan ? _cmdstan_generalized_candidate_run :
        throw(ArgumentError("normalized-prior sampling supports :advancedhmc or :cmdstan"))
    # As in fixed-coefficient sampling, rebuild from the authoritative design/prior.
    identity = _mgmfrm_normalized_prior_identity(target)
    target = _MGMFRMNormalizedPriorLogDensity(target.base.design.spec,
        _mgmfrm_normalized_prior_record(target); expected_identity = identity)
    run = runner(target, raw_initial; record_warmup, kwargs...)
    record = (;
        schema = record_warmup ? "bayesianmgmfrm.normalized_fixed_q_samples.v2" :
            "bayesianmgmfrm.normalized_fixed_q_samples.v1",
        spec = deepcopy(target.base.design.spec),
        prior = _mgmfrm_normalized_prior_record(target),
        target_identity = _mgmfrm_normalized_prior_identity(target),
        run,
    )
    record = merge(record, (; content_hash = _mgmfrm_normalized_sample_hash(record)))
    return _mgmfrm_normalized_prior_samples(target, record)
end

function _restore_mgmfrm_normalized_prior_samples(record; expected_identity::AbstractString)
    record isa NamedTuple && keys(record) ==
        (:schema, :spec, :prior, :target_identity, :run, :content_hash) ||
        throw(ArgumentError("unrecognized normalized-prior sample record"))
    record.schema in ("bayesianmgmfrm.normalized_fixed_q_samples.v1",
        "bayesianmgmfrm.normalized_fixed_q_samples.v2") &&
        record.spec isa FacetSpec && record.prior isa NamedTuple &&
        record.run isa NamedTuple && record.target_identity == expected_identity ||
        throw(ArgumentError("normalized-prior sample contract or target mismatch"))
    (record.schema == "bayesianmgmfrm.normalized_fixed_q_samples.v2") ==
        hasproperty(record.run, :warmup_stats) ||
        throw(ArgumentError("normalized-prior warmup schema mismatch"))
    hasproperty(record.run, :warmup_stats) && record.run.warmup_stats === nothing &&
        throw(ArgumentError("version 2 requires recorded warmup statistics"))
    record.content_hash == _mgmfrm_normalized_sample_hash(record) ||
        throw(ArgumentError("normalized-prior sample content hash mismatch"))
    target = _MGMFRMNormalizedPriorLogDensity(record.spec, record.prior; expected_identity)
    return _mgmfrm_normalized_prior_samples(target, record)
end

# Trusted same-environment Serialization only, deliberately separate from fit caches.
# Derived diagnostics are rebuilt from retained samples instead of serializing two truths.
function _save_mgmfrm_normalized_prior_samples(path::AbstractString, result::NamedTuple;
        overwrite::Bool = false)
    record = result.record
    _restore_mgmfrm_normalized_prior_samples(record; expected_identity = record.target_identity)
    return _save_serialized_record(path, record; overwrite)
end

function _load_mgmfrm_normalized_prior_samples(path::AbstractString;
        expected_identity::AbstractString)
    record = open(deserialize, path)
    return _restore_mgmfrm_normalized_prior_samples(record; expected_identity)
end
