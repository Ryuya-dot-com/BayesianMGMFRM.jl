# Canonical fixed-Q targets and sample records, shared by private and public consumers.
struct _NormalizedMGMFRMPrior
    prior_model::Symbol
    scales::NamedTuple
    source_rater::Any
    function _NormalizedMGMFRMPrior(; prior_model::Symbol, person_sd, rater_sd,
            item_sd, log_discrimination_sd, log_consistency_sd, step_sd,
            source_rater = nothing)
        prior_model in (:exchangeable, :source) || throw(ArgumentError(
            "prior_model must be :exchangeable or :source"))
        (prior_model === :source) == (source_rater !== nothing) || throw(ArgumentError(
            "source_rater is required only for the source prior"))
        scales = (; person_sd, rater_sd, item_sd, log_discrimination_sd, log_consistency_sd, step_sd)
        all(x -> x isa Real && !(x isa Bool), values(scales)) ||
            throw(ArgumentError("prior scales must be finite positive real numbers, not Bool"))
        checked = _source_fixture_prior_values(_SourceFixturePrior(; scales...))
        return new(prior_model, checked, deepcopy(source_rater))
    end
end

struct _NormalizedMGMFRMFit
    record::NamedTuple
    function _NormalizedMGMFRMFit(record::NamedTuple; expected_identity::AbstractString)
        snapshot = deepcopy(record)
        _restore_mgmfrm_normalized_prior_samples(snapshot; expected_identity)
        return new(snapshot)
    end
end

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

# Reuse the location map, but evaluate the full normalized target (not its raw-prior base).
struct _MGMFRMNormalizedLocationLogDensity
    raw::_MGMFRMNormalizedPriorLogDensity
    map::_MGMFRMLocationLogDensity
end
_MGMFRMNormalizedLocationLogDensity(raw::_MGMFRMNormalizedPriorLogDensity) =
    _MGMFRMNormalizedLocationLogDensity(raw, _MGMFRMLocationLogDensity(raw.base))
_mgmfrm_location_to_raw(t::_MGMFRMNormalizedLocationLogDensity, q) =
    _mgmfrm_location_to_raw(t.map, q)
_mgmfrm_location_from_raw(t::_MGMFRMNormalizedLocationLogDensity, x) =
    _mgmfrm_location_from_raw(t.map, x)
LogDensityProblems.dimension(t::_MGMFRMNormalizedLocationLogDensity) =
    LogDensityProblems.dimension(t.raw)
LogDensityProblems.capabilities(::Type{_MGMFRMNormalizedLocationLogDensity}) =
    LogDensityProblems.LogDensityOrder{0}()
initial_params(t::_MGMFRMNormalizedLocationLogDensity) =
    _mgmfrm_location_from_raw(t, initial_params(t.raw))
_check_source_fixture_raw_vector(t::_MGMFRMNormalizedLocationLogDensity, x::AbstractVector) =
    _check_source_fixture_raw_vector(t.raw, x)
LogDensityProblems.logdensity(t::_MGMFRMNormalizedLocationLogDensity, q) =
    LogDensityProblems.logdensity(t.raw, _mgmfrm_location_to_raw(t, q))

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

# Derived explanation, never a second persisted mathematical target. Both prior
# prediction and restored samples use the existing canonical record above.
function _mgmfrm_normalized_log_consistency_mean(target::_MGMFRMNormalizedPriorLogDensity)
    R = length(target.base.design.spec.data.rater_levels)
    means = zeros(R)
    if target.prior_model === :source && R > 1
        tau = target.base.prior.log_consistency_sd
        means .= (tau/R)*tau
        means[target.source_rater_index] = -(((R-1)/R)*tau)*tau
    end
    return means
end

function _mgmfrm_normalized_prior_metadata(target::_MGMFRMNormalizedPriorLogDensity)
    prior = _mgmfrm_normalized_prior_record(target)
    spec = target.base.design.spec
    R, H = length(spec.data.rater_levels), length(spec.data.category_levels)-1
    scales = prior.scales
    centered(n, sd) = (; distribution=:normalized_zero_sum_normal,
        length=n, free_dimension=n-1, kernel_sd=sd,
        marginal_sd=sd*sqrt((n-1)/n),
        contrast_sd=n > 1 ? sqrt(2.0)*sd : missing,
        scale_active=n > 1, constraint=:sum_zero)
    log_means = _mgmfrm_normalized_log_consistency_mean(target)
    label = prior.prior_model === :source ?
        "MGMFRM normalized source prior; distinguished rater $(repr(prior.source_rater))" :
        "MGMFRM normalized exchangeable prior"
    return (;
        schema="bayesianmgmfrm.normalized_mgmfrm_prior_metadata.v1",
        target_identity=_mgmfrm_normalized_prior_identity(target), prior,
        prior_label=label * "; zero-sum block scales are kernel SDs",
        model_family=:mgmfrm, loading_policy=:estimated_positive_fixed_q,
        latent_correlation=:identity_fixed, likelihood_scale=1.7,
        dimension_labels=deepcopy(spec.dimension_labels), q_matrix=copy(spec.q_matrix),
        rater_levels=deepcopy(spec.data.rater_levels), item_levels=deepcopy(spec.data.item_levels),
        category_levels=copy(spec.data.category_levels),
        blocks=(;
            person=(; distribution=:independent_normal, mean=0.0, sd=scales.person_sd),
            item=(; distribution=:independent_normal, mean=0.0, sd=scales.item_sd),
            log_loading=(; distribution=:independent_normal, mean=0.0, sd=scales.log_discrimination_sd),
            severity=merge(centered(R, scales.rater_sd), (; mean=zeros(R))),
            log_consistency=merge(centered(R, scales.log_consistency_sd),
                (; distribution=prior.prior_model === :source ? :tilted_zero_sum_normal : :normalized_zero_sum_normal,
                    mean=log_means)),
            item_steps=merge(centered(H, scales.step_sd),
                (; mean=zeros(H), independent_item_blocks=true, baseline_step=0.0))),
        public_fit=false, scientific_acceptance=:not_established,
    )
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
    # Binary responses have one fixed zero step and no free step density.
    if nsteps > 0
        for start in first(steps):nsteps:last(steps)
            lp += _zero_sum_prior_correction(view(raw, start:(start + nsteps - 1)), prior.step_sd)
        end
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

function _guarded_generalized_prior_draws(target::_MGMFRMNormalizedPriorLogDensity,
        ndraws::Int, rng::AbstractRNG)
    draws = _guarded_generalized_prior_draws(target.base, ndraws, rng)
    blocks = target.base.blueprint.blocks
    R = length(blocks[:rater_free])+1
    H = length(target.base.design.spec.data.category_levels)-1
    selected = [blocks[:rater_free], blocks[:log_rater_consistency_free]]
    if H > 1
        steps = blocks[:item_steps]
        append!(selected, [start:(start+H-2) for start in first(steps):(H-1):last(steps)])
    end
    # In the last-reconstructed chart, the free Gaussian covariance is
    # tau^2 * (I - 11'/n). Match the existing fixed-coefficient sampler's
    # Cholesky construction; no density weighting or MCMC is involved.
    for block in selected
        m = length(block)
        isempty(block) && continue
        factor = cholesky(Symmetric(Matrix{Float64}(I, m, m)-ones(m, m)/(m+1))).L
        for row in eachrow(draws)
            row[block] .= factor * row[block]
        end
    end
    means = _mgmfrm_normalized_log_consistency_mean(target)
    draws[:, blocks[:log_rater_consistency_free]] .+= permutedims(means[1:(R-1)])
    all(isfinite, draws) || throw(ArgumentError("normalized MGMFRM prior generated nonfinite coordinates"))
    return draws
end

# Private, prior-only counterpart to the existing normalized sampling route.
# It does not make the fixed-coefficient ExchangeablePrior accept MGMFRM.
function _mgmfrm_normalized_prior_predictive_check(target::_MGMFRMNormalizedPriorLogDensity;
        ndraws::Int = 1000, rng::AbstractRNG = Random.default_rng(),
        min_category_probability::Real = 0.01, prior_warning_probability::Real = 0.95,
        wide_facet_range_fraction::Real = 0.8)
    _check_prior_implication_controls(; min_category_probability,
        prior_warning_probability, wide_facet_range_fraction)
    identity = _mgmfrm_normalized_prior_identity(target)
    target = _MGMFRMNormalizedPriorLogDensity(target.base.design.spec,
        _mgmfrm_normalized_prior_record(target); expected_identity=identity)
    metadata = _mgmfrm_normalized_prior_metadata(target)
    raw = _guarded_generalized_prior_draws(target, ndraws, rng)
    bundle = _generalized_prior_bundle_from_draws(target.base, raw; prior_record=metadata.prior)
    check = _generalized_prior_check_from_bundle(bundle;
        prior_record=metadata.prior, rng, min_category_probability,
        prior_warning_probability, wide_facet_range_fraction)
    return merge(check, (;
        schema="bayesianmgmfrm.normalized_mgmfrm_prior_predictive_check.v1",
        target_identity=identity, prior_metadata=metadata, prior_label=metadata.prior_label,
        public_fit=false))
end

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
        prior_metadata = _mgmfrm_normalized_prior_metadata(target),
        raw_parameter_names = copy(target.base.blueprint.parameter_names),
        direct_parameter_names = copy(target.base.blueprint.constrained_parameter_names),
        diagnostics = tables,
        warmup_diagnostics = _warmup_diagnostic_rows(
            get(record.run, :warmup_stats, nothing), record.run.controls, record.run.backend),
    )
end

function _mgmfrm_normalized_prior_sample(target::_MGMFRMNormalizedPriorLogDensity,
        raw_initial::AbstractVector = initial_params(target);
        backend::Symbol = :advancedhmc, record_warmup::Bool = true,
        sampling_coordinates::Symbol = :raw, kwargs...)
    _check_mgmfrm_sampling_coordinates(target.base.design.spec, sampling_coordinates, backend, true)
    runner = backend === :advancedhmc ? _run_generalized_candidate_advancedhmc :
        backend === :cmdstan ? _cmdstan_generalized_candidate_run :
        throw(ArgumentError("normalized-prior sampling supports :advancedhmc or :cmdstan"))
    # As in fixed-coefficient sampling, rebuild from the authoritative design/prior.
    identity = _mgmfrm_normalized_prior_identity(target)
    target = _MGMFRMNormalizedPriorLogDensity(target.base.design.spec,
        _mgmfrm_normalized_prior_record(target); expected_identity = identity)
    run = if sampling_coordinates === :raw
        runner(target, raw_initial; record_warmup, kwargs...)
    else
        location = _MGMFRMNormalizedLocationLogDensity(target)
        sampled = runner(location, raw_initial;
            _initial_transform=x -> _mgmfrm_location_from_raw(location, x), record_warmup, kwargs...)
        # Unit absolute Jacobian: log densities and energy telemetry stay valid.
        merge(sampled, (; initial=Float64.(collect(raw_initial)),
            draws=reduce(vcat, [permutedims(_mgmfrm_location_to_raw(location, q))
                for q in eachrow(sampled.draws)]),
            controls=merge(sampled.controls, (; sampling_coordinates,
                stored_coordinates=:raw_unconstrained,
                initialization_coordinates=:raw_unconstrained, coordinate_logabsdet=0.0))))
    end
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
