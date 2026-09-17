# Canonical fixed-coefficient specification; stable fitting remains separate.
function _check_mfrm_fixed_q_options(family, dimensions, thresholds, discrimination, bias, anchors)
    _is_mfrm_fixed_q(family, dimensions) || return nothing
    thresholds === :partial_credit && discrimination === :none && isempty(bias) && isempty(anchors) ||
        throw(ArgumentError("multidimensional MFRM requires partial-credit thresholds, fixed Q coefficients, no bias terms and no anchors"))
    return nothing
end

function _mfrm_fixed_q_constraints()
    return NamedTuple[(; block, constraint, transform, status = :specified_only, note)
        for (block, constraint, transform, note) in (
            (:person, :prior_anchored, :identity, "One ability per person and named dimension; locations anchored by zero-centered priors"),
            (:rater_free, :sum_to_zero, :sum_to_zero_last, "Free severities for all but the last rater; last severity is their negative sum"),
            (:item, :prior_anchored, :identity, "One difficulty per item; locations anchored by zero-centered priors"),
            (:item_steps, :first_step_zero_sum_to_zero, :sum_to_zero_last, "First step zero; last nonbaseline step is the negative sum of the free steps; both are zero for binary responses"),
            (:q_matrix, :fixed_mask, :fixed_coefficients, "Active Q coefficients fixed at one and inactive coefficients at zero"),
            (:rater_consistency, :fixed_one, :constant, "All rater consistency coefficients fixed at one"),
            (:latent_correlation, :identity_fixed, :constant, "Ability prior covariance is person_sd^2 times the identity; no estimated population correlation"))]
end

function _mfrm_fixed_q_prior_rows()
    return NamedTuple[(; block, prior = :normal, parameters = (; location = 0.0, scale),
        density_space = :unit_logit_free, jacobian_policy = :none_declared_free_coordinate_density,
        status = :specified_only) for (block, scale) in
        ((:person, :person_sd), (:rater_free, :rater_sd), (:item, :item_sd), (:item_steps, :step_sd))]
end

function _mfrm_fixed_q_reference_spec(spec::FacetSpec)
    _is_mfrm_fixed_q(spec) || throw(ArgumentError("expected a multidimensional MFRM specification"))
    return mfrm_spec(spec.data; family = :mgmfrm, dimensions = spec.dimensions,
        thresholds = spec.thresholds, q_matrix = spec.q_matrix,
        dimension_labels = spec.dimension_labels, validation_report = spec.validation)
end

function _mfrm_fixed_q_blueprint(base::NamedTuple)
    names, indices = String[], Int[]
    blocks = Dict{Symbol,UnitRange{Int}}()
    for block in (:person, :rater_free, :item, :item_steps)
        source = base.blocks[block]
        _push_named_block!(names, blocks, block, base.parameter_names[source])
        append!(indices, source)
    end
    return (; parameter_names = names, blocks, n_parameters = length(names), base_indices = indices)
end

function _mfrm_fixed_q_design(spec::FacetSpec)
    reference = getdesign(_mfrm_fixed_q_reference_spec(spec); preview = true)
    blueprint = _mfrm_fixed_q_blueprint(_mgmfrm_fit_ready_candidate_blueprint(reference))
    return FacetDesign(spec, blueprint.parameter_names, blueprint.blocks,
        Dict(:person => :prior_anchored, :rater_free => :sum_to_zero,
            :item => :prior_anchored, :item_steps => :first_step_zero_sum_to_zero))
end

_mfrm_fixed_q_spec_metadata() = (;
    model = :mfrm_fixed_q, model_label = "Multidimensional MFRM (fixed coefficients)",
    scale_convention = :unit_logit, parameter_space = :unit_logit_free,
    location = :prior_anchored, latent_correlation = :identity_fixed,
    loading_policy = :fixed_q_coefficients, rater_consistency = :fixed_one,
    prior_policy = :independent_normal_free_unit_logit,
    jacobian_policy = :none_declared_free_coordinate_density)

function _mfrm_fixed_q_parameter_layout(design::FacetDesign)
    return merge(_specified_only_preview_parameter_layout(design),
        _mfrm_fixed_q_spec_metadata(), (; density_space = :unit_logit_free,
            likelihood = :multidimensional_partial_credit, parameterization = :fixed_q_free_coordinates))
end

function _reject_mfrm_fixed_q_fit(spec::FacetSpec, caller::AbstractString)
    _is_mfrm_fixed_q(spec) && throw(ArgumentError(
        "$caller does not support multidimensional MFRM. " *
        "Use BayesianMGMFRM.Experimental.fit(spec), then save_fit_cache/load_fit_cache; automatic request caching is unavailable."))
    return nothing
end

# Private fixed-coefficient sampling; canonical records stay separate from fit caches.
_mfrm_fixed_q_prior_record(target::_MFRMFixedQReferenceLogDensity) = (;
    schema = :fixed_q_mfrm_prior_v1,
    scale_convention = :unit_logit,
    parameter_measure = :free_last_reconstructed_rater_and_item_steps,
    location = :prior_anchored,
    scales = Base.structdiff(_prior_cache_record(target.prior), (; prior_contract = nothing)),
)

_mfrm_fixed_q_identity(target::_MFRMFixedQReferenceLogDensity) = _cache_hash((;
    design = design_identity(target.design).value,
    prior = _mfrm_fixed_q_prior_record(target),
))

_mfrm_fixed_q_pointwise(target::_MFRMFixedQReferenceLogDensity, params::AbstractVector) =
    _mgmfrm_source_pointwise_loglikelihood_from_unconstrained(target.base.design,
        _mfrm_fixed_q_reference_raw(target, params))

_cmdstan_generalized_family(::_MFRMFixedQReferenceLogDensity) = :mfrm_fixed_q
_cmdstan_generalized_data(target::_MFRMFixedQReferenceLogDensity) =
    merge(_cmdstan_mgmfrm_data(target.base), (; reference_sd =
        [_source_fixture_prior_sd(target, i) for i in 1:LogDensityProblems.dimension(target)]))

function _cmdstan_generalized_chain_result(path::AbstractString,
        target::_MFRMFixedQReferenceLogDensity, chain::Int, ndraws::Int; warmup::Int = 0)
    evaluate = function(params)
        pointwise = _mfrm_fixed_q_pointwise(target, params)
        return (; pointwise, logposterior = sum(pointwise) + logprior(target, params))
    end
    parsed = _cmdstan_raw_chain_result(path, LogDensityProblems.dimension(target),
        target.base.design.spec.data.n, chain, ndraws, evaluate; warmup)
    all(isapprox(stat.stan_lp, lp; atol = 1e-8, rtol = 1e-8)
        for (stat, lp) in zip(parsed.stats, parsed.logps)) || throw(CmdStanError(
            :output_parse, :log_posterior_mismatch,
            "CmdStan and Julia fixed-Q MFRM log posteriors disagree"))
    return parsed
end

function _mfrm_fixed_q_model_coordinates(target::_MFRMFixedQReferenceLogDensity,
        draws::AbstractMatrix{<:Real})
    size(draws, 1) > 0 && size(draws, 2) == LogDensityProblems.dimension(target) &&
        all(isfinite, draws) || throw(ArgumentError("invalid fixed-Q MFRM draw matrix"))
    design = target.base.design
    spec, data = design.spec, design.spec.data
    direct = Matrix{Float64}(undef, size(draws, 1), length(design.parameter_names))
    raw = zeros(target.base.blueprint.n_parameters)
    for i in axes(draws, 1)
        # Reuse only the constraint algebra, in unit logits. No likelihood rescaling.
        raw[target.blueprint.base_indices] .= view(draws, i, :)
        direct[i, :] .= _mgmfrm_source_constrained_params_from_unconstrained(design, raw)
    end
    dimensions = Dict(:person => repeat(collect(1:spec.dimensions), length(data.person_levels)),
        :item_dimension_discrimination => [d for i in axes(spec.q_matrix, 1)
            for d in axes(spec.q_matrix, 2) if spec.q_matrix[i, d]])
    rows = NamedTuple[]
    for block in (:person, :rater, :item, :item_dimension_discrimination, :rater_consistency)
        for (offset, index) in enumerate(design.blocks[block])
            push!(rows, (; parameter = design.parameter_names[index], values = view(direct, :, index),
                block, dimension = haskey(dimensions, block) ? dimensions[block][offset] : nothing,
                fixed = block in (:item_dimension_discrimination, :rater_consistency),
                derived = block === :rater && offset == length(data.rater_levels)))
        end
    end
    for (i, item) in enumerate(data.item_levels), m in 1:length(data.category_levels)
        push!(rows, (; parameter = "item_step[item=$item,m=$m]",
            values = [_source_step_value(design, params, :item_steps, i, m) for params in eachrow(direct)],
            block = :item_steps, dimension = nothing, fixed = m == 1 || length(data.category_levels) == 2,
            derived = m == length(data.category_levels)))
    end
    return rows
end

function _mfrm_fixed_q_samples(target, record::NamedTuple;
        model::Symbol = :mfrm_fixed_q, parameter_space::Symbol = :unit_logit,
        model_parameter_space::Symbol = :unit_logit_with_fixed_coefficients)
    run = record.run
    _check_generalized_sample_run(target, run)
    if run.backend === :cmdstan
        all(hasproperty(stat, :stan_lp) && isapprox(stat.stan_lp, lp; atol = 1e-8, rtol = 1e-8)
            for (stat, lp) in zip(run.sampler_stats, run.logdensities)) ||
            throw(ArgumentError("fixed-Q MFRM retained Stan log posterior mismatch"))
    end
    names = target.blueprint.parameter_names
    # Location draws already use unit logits; reconstruct only the declared constraints.
    parameter_rows = _candidate_mcmc_diagnostic_rows(run.draws, names, run.controls.chains;
        parameter_space, split_chains = run.split_chains_requested,
        rhat_threshold = run.checked.rhat_threshold, ess_threshold = run.checked.ess_threshold)
    summary = _posterior_summary_rows(run.draws, names; lower = 0.025, upper = 0.975,
        intervals = (), reference = 0.0, rope = nothing, rope_probability_threshold = 0.95)
    coordinates = _mfrm_fixed_q_model_coordinates(target, run.draws)
    model_names = [row.parameter for row in coordinates]
    model_draws = hcat([row.values for row in coordinates]...)
    model_rows = _candidate_mcmc_diagnostic_rows(model_draws, model_names, run.controls.chains;
        parameter_space = model_parameter_space,
        structurally_fixed_parameters = Set(row.parameter for row in coordinates if row.fixed),
        split_chains = run.split_chains_requested,
        rhat_threshold = run.checked.rhat_threshold, ess_threshold = run.checked.ess_threshold)
    model_summary = _posterior_summary_rows(model_draws, model_names; lower = 0.025, upper = 0.975,
        intervals = (), reference = 0.0, rope = nothing, rope_probability_threshold = 0.95)
    metrics = _mcmc_metric_summary(model_rows, run.checked.rhat_threshold, run.checked.ess_threshold)
    flag = _generalized_candidate_summary_flag(count(row -> row.flag !== :ok, run.sampler_rows),
        sum(row.n_nonfinite_logdensity for row in run.sampler_rows), 0, 0, metrics, metrics)
    return (; record, public_fit = false, parameter_names = copy(names),
        parameter_space, posterior_summary = summary,
        model, model_coordinates = coordinates,
        model_posterior_summary = [merge(row, (; coordinate.block, coordinate.dimension,
                coordinate.fixed, coordinate.derived))
            for (row, coordinate) in zip(model_summary, coordinates)],
        diagnostics = (; parameter_rows, model_parameter_rows = model_rows,
            sampler_rows = run.sampler_rows, summary = (; metrics..., flag)),
        warmup_diagnostics = _warmup_diagnostic_rows(
            get(run, :warmup_stats, nothing), run.controls, run.backend))
end

function _mfrm_fixed_q_sample(target::_MFRMFixedQReferenceLogDensity,
        initial::AbstractVector = initial_params(target);
        backend::Symbol = :advancedhmc, record_warmup::Bool = true, kwargs...)
    runner = backend === :advancedhmc ? _run_generalized_candidate_advancedhmc :
        backend === :cmdstan ? _cmdstan_generalized_candidate_run :
        throw(ArgumentError("fixed-Q MFRM sampling supports :advancedhmc or :cmdstan"))
    # The validated design and prior are authoritative; rebuild mutable numerical views.
    _require_canonical_design(target.design, "fixed-Q MFRM sampling")
    target = _MFRMFixedQReferenceLogDensity(target.design.spec; prior = target.prior)
    run = runner(target, initial; record_warmup, kwargs...)
    record = (; schema = _is_mfrm_fixed_q(target.design.spec) ?
            "bayesianmgmfrm.fixed_q_mfrm_samples.v2" : "bayesianmgmfrm.fixed_q_mfrm_samples.v1",
        spec = deepcopy(target.design.spec), prior = _mfrm_fixed_q_prior_record(target),
        target_identity = _mfrm_fixed_q_identity(target), run)
    record = merge(record, (; content_hash = _mgmfrm_normalized_sample_hash(record)))
    return _mfrm_fixed_q_samples(target, record)
end

function _restore_mfrm_fixed_q_samples(record; expected_identity::AbstractString)
    record isa NamedTuple && keys(record) ==
        (:schema, :spec, :prior, :target_identity, :run, :content_hash) &&
        record.spec isa FacetSpec && record.prior isa NamedTuple && record.run isa NamedTuple &&
        record.target_identity == expected_identity ||
        throw(ArgumentError("fixed-Q MFRM sample contract or target mismatch"))
    (record.schema == "bayesianmgmfrm.fixed_q_mfrm_samples.v1" && record.spec.family === :mgmfrm ||
        record.schema == "bayesianmgmfrm.fixed_q_mfrm_samples.v2" && _is_mfrm_fixed_q(record.spec)) ||
        throw(ArgumentError("fixed-Q MFRM sample schema and model specification mismatch"))
    record.content_hash == _mgmfrm_normalized_sample_hash(record) ||
        throw(ArgumentError("fixed-Q MFRM sample content hash mismatch"))
    hasproperty(record.prior, :scales) && record.prior.scales isa NamedTuple &&
        Set(keys(record.prior.scales)) == Set(fieldnames(MFRMPrior)) &&
        all(x -> x isa Real, values(record.prior.scales)) ||
        throw(ArgumentError("invalid fixed-Q MFRM prior scales"))
    target = _MFRMFixedQReferenceLogDensity(record.spec; prior = MFRMPrior(; record.prior.scales...))
    isequal(record.prior, _mfrm_fixed_q_prior_record(target)) &&
        _mfrm_fixed_q_identity(target) == expected_identity ||
        throw(ArgumentError("fixed-Q MFRM prior, measure or design mismatch"))
    return _mfrm_fixed_q_samples(target, record)
end

# Trusted same-environment Serialization. Rebuild names, summaries and diagnostics.
function _save_mfrm_fixed_q_samples(path::AbstractString, result::NamedTuple;
        overwrite::Bool = false)
    record = result.record
    _restore_mfrm_fixed_q_samples(record; expected_identity = record.target_identity)
    return _save_serialized_record(path, record; overwrite)
end

function _load_mfrm_fixed_q_samples(path::AbstractString; expected_identity::AbstractString)
    return _restore_mfrm_fixed_q_samples(open(deserialize, path); expected_identity)
end

# Root type identity is preserved for persistence; fitting uses Experimental.fit.
struct MultidimensionalMFRMFit
    record::NamedTuple

    function MultidimensionalMFRMFit(record::NamedTuple; expected_identity::AbstractString)
        snapshot = deepcopy(record)
        _restore_mfrm_fixed_q_samples(snapshot; expected_identity)
        return new(snapshot)
    end
end

# Preserve the defining type identity of saved correlated results.
"""
    BayesianMGMFRM.Experimental.CorrelatedMFRMFit

Correlated two-dimensional MFRM result. Use `diagnostics` to assess sampling,
`direct_posterior_summary` for rho and ability intervals, and
`save_fit_cache`/`load_fit_cache` to save and reopen the fit.
"""
struct _CorrelatedMFRMFit
    record::NamedTuple

    function _CorrelatedMFRMFit(record::NamedTuple; expected_identity::AbstractString)
        snapshot = deepcopy(record)
        _restore_mfrm_correlated_2d_samples(snapshot; expected_identity)
        return new(snapshot)
    end
end

const _FixedQMFRMFit = Union{MultidimensionalMFRMFit,_CorrelatedMFRMFit}

_fixed_q_fit_model(::MultidimensionalMFRMFit) = :mfrm_fixed_q
_fixed_q_fit_model(::_CorrelatedMFRMFit) = :mfrm_fixed_q_correlated_2d
_fixed_q_default_view(::MultidimensionalMFRMFit) = :full
_fixed_q_default_view(::_CorrelatedMFRMFit) = :public
_fixed_q_artifact_label(fit::_FixedQMFRMFit) = Symbol(_fixed_q_fit_model(fit), :_fit_artifact)
_fixed_q_artifact_schemas(::MultidimensionalMFRMFit) = (
    "bayesianmgmfrm.mfrm_fixed_q_fit_artifact.v1", "bayesianmgmfrm.mfrm_fixed_q_fit_artifact.v2")
_fixed_q_artifact_schemas(::_CorrelatedMFRMFit) = ("bayesianmgmfrm.mfrm_fixed_q_correlated_2d_fit_artifact.v1",)
_fixed_q_model_manifest(fit::MultidimensionalMFRMFit; view::Symbol = :full) =
    model_manifest(getdesign(fit.record.spec; preview = true); view)

_mfrm_fixed_q_fit(result::NamedTuple) = MultidimensionalMFRMFit(result.record;
    expected_identity = result.record.target_identity)

function _mfrm_fixed_q_fit(spec::FacetSpec; prior::MFRMPrior = MFRMPrior(),
        backend::Symbol = :advancedhmc, init = nothing, kwargs...)
    _is_mfrm_fixed_q(spec) || throw(ArgumentError("multidimensional MFRM fitting requires family = :mfrm and dimensions >= 2"))
    target = _MFRMFixedQReferenceLogDensity(spec; prior)
    initial = _fit_initial_params(target.design, init)
    return _mfrm_fixed_q_fit(_mfrm_fixed_q_sample(target, initial; backend, kwargs...))
end

_mfrm_fixed_q_samples(fit::MultidimensionalMFRMFit) =
    _restore_mfrm_fixed_q_samples(fit.record; expected_identity = fit.record.target_identity)

_save_mfrm_fixed_q_samples(path::AbstractString, fit::MultidimensionalMFRMFit; kwargs...) =
    _save_mfrm_fixed_q_samples(path, (; record = fit.record); kwargs...)

_fixed_q_result_spec(checked) = checked.model === :mfrm_fixed_q_correlated_2d ?
    checked.record.base_spec : checked.record.spec

function _fixed_q_report_samples(result::NamedTuple)
    record = result.record
    if _nt_get(record, :schema, nothing) == "bayesianmgmfrm.correlated_fixed_q_mfrm_samples.v1"
        return _restore_mfrm_correlated_2d_samples(record; expected_identity = record.target_identity)
    end
    return _restore_mfrm_fixed_q_samples(record; expected_identity = record.target_identity)
end

function _mfrm_fixed_q_metadata(checked)
    record, run = checked.record, checked.record.run
    data = _fixed_q_result_spec(checked).data
    return (; model = checked.model, model_label = checked.model === :mfrm_fixed_q_correlated_2d ?
            "Correlated fixed-coefficient multidimensional MFRM" : "Fixed-coefficient multidimensional MFRM",
        backend = run.backend, backend_label = run.backend === :advancedhmc ? "Julia (AdvancedHMC)" : "CmdStan",
        sampler = run.sampler, scale_convention = :unit_logit,
        target_identity = record.target_identity, source_sample_schema = record.schema,
        source_sample_content_hash = record.content_hash, prior = deepcopy(record.prior),
        sampler_controls = deepcopy(run.controls), diagnostic_settings =
            (; run.checked..., split_chains = run.split_chains_requested),
        n_retained = size(run.draws, 1), n_observations = data.n,
        person_levels = copy(data.person_levels), item_levels = copy(data.item_levels),
        rater_levels = copy(data.rater_levels), category_levels = copy(data.category_levels))
end

function fit_metadata(fit::MultidimensionalMFRMFit; view::Symbol = :full)
    view === :full || throw(ArgumentError("multidimensional MFRM result metadata currently supports view = :full only"))
    metadata = _mfrm_fixed_q_legacy_fit_metadata(fit)
    return _is_mfrm_fixed_q(fit.record.spec) ? merge(metadata, (;
        estimation_status = :experimental, public_fit = true, experimental_public = true,
        fitting_available = true)) : metadata
end

# Frozen v1 persistence metadata; existing cache artifacts must rebuild exactly.
function _mfrm_fixed_q_legacy_fit_metadata(fit::MultidimensionalMFRMFit)
    checked = _mfrm_fixed_q_samples(fit)
    spec, run = checked.record.spec, checked.record.run
    return deepcopy(merge(_mfrm_fixed_q_metadata(checked), (;
        family = :mfrm, model_label = "Multidimensional MFRM (fixed coefficients)",
        estimation_status = :private_reference, public_fit = false, experimental_public = false,
        dimensions = spec.dimensions, dimension_labels = copy(spec.dimension_labels),
        thresholds = spec.thresholds, q_matrix = _q_matrix_manifest(spec.q_matrix),
        item_structure = _model_family_item_structure(spec),
        parameter_space = :unit_logit_free, location = :prior_anchored,
        latent_correlation = :identity_fixed,
        loading_policy = :fixed_q_coefficients, rater_consistency = :fixed_one,
        identification = (; person = :prior_anchored, item = :prior_anchored,
            rater = :sum_to_zero, item_steps = :first_zero_remaining_sum_to_zero),
        n_parameters = length(checked.parameter_names), n_model_parameters = length(checked.model_coordinates),
        parameter_names = copy(checked.parameter_names), n_draws = size(run.draws, 1),
        n_chains = run.controls.chains, draws_per_chain = run.controls.ndraws)))
end

function Base.show(io::IO, fit::MultidimensionalMFRMFit)
    metadata = fit_metadata(fit)
    print(io, metadata.model_label, " (", metadata.dimensions, " dimensions, ",
        metadata.n_draws, " retained draws, ", metadata.backend_label,
        "; unit logits; ", metadata.experimental_public ? "experimental)" : "private result)")
end

function posterior_summary(fit::MultidimensionalMFRMFit;
        lower::Real = 0.025, upper::Real = 0.975, intervals = (0.66, 0.9, 0.95),
        reference::Real = 0.0, rope = nothing, rope_probability_threshold::Real = 0.95)
    checked = _mfrm_fixed_q_samples(fit)
    return _posterior_summary_rows(checked.record.run.draws, checked.parameter_names;
        lower, upper, intervals, reference, rope, rope_probability_threshold)
end

function direct_posterior_summary(fit::MultidimensionalMFRMFit;
        lower::Real = 0.025, upper::Real = 0.975, intervals = (0.66, 0.9, 0.95),
        reference::Real = 0.0, rope = nothing, rope_probability_threshold::Real = 0.95)
    checked = _mfrm_fixed_q_samples(fit)
    coordinates = checked.model_coordinates
    rows = _posterior_summary_rows(hcat([row.values for row in coordinates]...),
        getproperty.(coordinates, :parameter); lower, upper, intervals, reference, rope, rope_probability_threshold)
    labels = checked.record.spec.dimension_labels
    return [merge(row, (; coordinate.block, coordinate.dimension, coordinate.fixed, coordinate.derived,
        dimension_label = coordinate.dimension === nothing ? missing : labels[coordinate.dimension]))
        for (row, coordinate) in zip(rows, coordinates)]
end

function diagnostics(fit::MultidimensionalMFRMFit; view::Symbol = :full,
        split_chains::Bool = fit.record.run.split_chains_requested,
        rhat_threshold::Real = fit.record.run.checked.rhat_threshold,
        ess_threshold::Real = fit.record.run.checked.ess_threshold)
    view === :full || throw(ArgumentError("multidimensional MFRM result diagnostics currently supports view = :full only"))
    checked = _mfrm_fixed_q_samples(fit)
    run = checked.record.run
    thresholds = _check_diagnostic_thresholds(rhat_threshold, ess_threshold)
    split_chains == run.split_chains_requested && thresholds == run.checked ||
        throw(ArgumentError("diagnostics must use the stored split_chains, rhat_threshold and ess_threshold settings"))
    return deepcopy(merge(checked.diagnostics, (; model = :mfrm_fixed_q, backend = run.backend,
        diagnostic_settings = (; run.checked..., split_chains = run.split_chains_requested),
        warmup_rows = checked.warmup_diagnostics)))
end

function _mfrm_fixed_q_artifact_payload(fit::_FixedQMFRMFit;
        include_draws::Bool, include_log_posterior::Bool, include_sampler_stats::Bool,
        include_environment::Bool, include_packages::Bool, legacy::Bool = false,
        split_chains::Bool = fit.record.run.split_chains_requested,
        rhat_threshold::Real = fit.record.run.checked.rhat_threshold,
        ess_threshold::Real = fit.record.run.checked.ess_threshold)
    checked = _mfrm_fixed_q_samples(fit)
    record, run = checked.record, checked.record.run
    spec = _fixed_q_result_spec(checked)
    legacy && !(fit isa MultidimensionalMFRMFit) && throw(ArgumentError("legacy artifacts apply only to independent multidimensional MFRM"))
    _is_mfrm_fixed_q(spec) || throw(ArgumentError(
        "fit artifacts and fit caches require canonical multidimensional MFRM samples; use the private loader for legacy samples"))
    diagnostic = diagnostics(fit; split_chains, rhat_threshold, ess_threshold)
    metadata = legacy ? _mfrm_fixed_q_legacy_fit_metadata(fit) : fit_metadata(fit)
    rng = get(run.controls, :rng, (; algorithm = missing, seed = missing, replayable = false))
    manifest = merge(_fixed_q_model_manifest(fit),
        (; object = :fit, fit = metadata, diagnostics = diagnostic.summary))
    if legacy
        equation = merge(manifest.spec.equation, (;
            implementation_gaps = [:experimental_fit_cache_report_workflow],
            experimental_fit_available = false, experimental_fit_entrypoint = nothing))
        manifest = merge(manifest, (; spec = merge(manifest.spec, (; equation))))
    end
    policy = (; draws = _artifact_inclusion_flag(include_draws),
        log_posterior = _artifact_inclusion_flag(include_log_posterior),
        sampler_stats = _artifact_inclusion_flag(include_sampler_stats),
        environment = _artifact_inclusion_flag(include_environment),
        package_status = _artifact_inclusion_flag(include_environment && include_packages))
    return (; schema = legacy ? "bayesianmgmfrm.mfrm_fixed_q_fit_artifact.v1" :
            last(_fixed_q_artifact_schemas(fit)),
        object = :fit_artifact, family = :mfrm, model = _fixed_q_fit_model(fit),
        status = legacy ? :private_reference : :experimental, manifest, diagnostics = diagnostic,
        posterior_summary = posterior_summary(fit),
        direct_posterior_summary = direct_posterior_summary(fit),
        reproducibility = (; data_signature = spec.validation.data_signature,
            target_identity = record.target_identity, source_sample_schema = record.schema,
            source_sample_content_hash = record.content_hash, prior = deepcopy(record.prior),
            sampler_controls = deepcopy(run.controls), rng = deepcopy(rng),
            replayable_rng = _nt_get(rng, :replayable, false) === true,
            diagnostic_policy = metadata.diagnostic_settings, artifact_policy = policy),
        draws = include_draws ? copy(run.draws) : nothing,
        log_posterior = include_log_posterior ? copy(run.logdensities) : nothing,
        sampler_stats = include_sampler_stats ? deepcopy(run.sampler_stats) : nothing,
        warmup_stats = include_sampler_stats ? deepcopy(get(run, :warmup_stats, nothing)) : nothing)
end

function fit_artifact(fit::_FixedQMFRMFit; view::Symbol = :full,
        include_draws::Bool = false, include_log_posterior::Bool = include_draws,
        include_sampler_stats::Bool = false, include_environment::Bool = true,
        include_packages::Bool = false, include_environment_paths::Bool = false,
        kwargs...)
    view in (:full, :public) || throw(ArgumentError("view must be :full or :public"))
    payload = _mfrm_fixed_q_artifact_payload(fit; include_draws, include_log_posterior,
        include_sampler_stats, include_environment, include_packages, kwargs...)
    environment = include_environment ? evidence_metadata(;
        include_packages, include_paths = include_environment_paths) : nothing
    artifact = _with_archive_metadata(merge(payload, (; created_at = string(now()), environment));
        label = _fixed_q_artifact_label(fit))
    return view === :full ? artifact : _public_fit_artifact_projection(artifact, fit)
end

function _public_fit_artifact_projection(artifact, fit::_FixedQMFRMFit)
    metadata = merge(fit_metadata(fit), (; estimation_status = :experimental,
        fitting_available = true))
    manifest = merge(_fixed_q_model_manifest(fit; view = :public),
        (; object = :fit, fit = _public_fit_report_project_value(metadata)))
    source = merge(_artifact_hash_payload(artifact), (; reproducibility =
        merge(artifact.reproducibility, (; prior = metadata.prior))))
    payload = merge(_public_fit_report_project_value(source), (;
        schema = "bayesianmgmfrm.fit_artifact_public.v1", object = :fit_artifact,
        family = :mfrm, model = _fixed_q_fit_model(fit), status = :experimental, stability = :experimental,
        model_manifest = manifest,
        source_artifact = (; schema = artifact.schema, hash = artifact.content_hash.value)))
    return merge(payload, (; content_hash = _artifact_content_hash_record(payload)))
end

_fit_warmup_diagnostics(fit::_FixedQMFRMFit) =
    _mfrm_fixed_q_samples(fit).warmup_diagnostics

function fit_archive_manifest(fit::_FixedQMFRMFit;
        label = nothing, source_path = nothing, artifact = nothing, kwargs...)
    value = artifact === nothing ? fit_artifact(fit; kwargs...) : artifact
    return fit_archive_manifest(value; label, source_path)
end

function save_fit_cache(path::AbstractString, fit::_FixedQMFRMFit;
        artifact_split_chains::Bool = fit.record.run.split_chains_requested,
        artifact_rhat_threshold::Real = fit.record.run.checked.rhat_threshold,
        artifact_ess_threshold::Real = fit.record.run.checked.ess_threshold, kwargs...)
    snapshot = typeof(fit)(fit.record; expected_identity = fit.record.target_identity)
    return _save_fit_cache(path, snapshot; artifact_split_chains,
        artifact_rhat_threshold, artifact_ess_threshold, kwargs...)
end

function _fit_cache_record(fit::_FixedQMFRMFit;
        cache_key, artifact, source_path = nothing)
    artifact isa NamedTuple || throw(ArgumentError("multidimensional MFRM cache artifact must be a NamedTuple"))
    archive_manifest = fit_archive_manifest(artifact; label = :fit_cache_artifact, source_path)
    record = (; schema = "bayesianmgmfrm.fit_cache.v2", object = :fit_cache,
        model = _fixed_q_fit_model(fit), created_at = string(now()),
        serialization = (; format = :julia_serialization, julia_version = string(VERSION),
            portability = :same_julia_major_minor_recommended),
        cache_key = cache_key === nothing ? missing : String(cache_key),
        target_identity = fit.record.target_identity, source_sample_schema = fit.record.schema,
        source_sample_content_hash = fit.record.content_hash,
        artifact_content_hash = archive_manifest.content_hash, archive_manifest, fit, artifact)
    context = source_path === nothing ? "multidimensional MFRM fit cache" : String(source_path)
    _check_fit_cache_record(record, context)
    return _verify_fit_cache_record(record, context)
end

Base.@nospecializeinfer function _check_mfrm_fixed_q_cache_record(@nospecialize(record::NamedTuple), path)
    keys(record) == (:schema, :object, :model, :created_at, :serialization, :cache_key,
        :target_identity, :source_sample_schema, :source_sample_content_hash,
        :artifact_content_hash, :archive_manifest, :fit, :artifact) &&
        record.object === :fit_cache && record.fit isa _FixedQMFRMFit &&
        record.model === _fixed_q_fit_model(record.fit) && record.artifact isa NamedTuple &&
        record.created_at isa AbstractString &&
        (ismissing(record.cache_key) || record.cache_key isa AbstractString) ||
        throw(ArgumentError("invalid multidimensional MFRM fit-cache contract at $path"))
    checked = _mfrm_fixed_q_samples(record.fit)
    sample = checked.record
    _is_mfrm_fixed_q(_fixed_q_result_spec(checked)) && isequal(record.target_identity, sample.target_identity) &&
        isequal(record.source_sample_schema, sample.schema) &&
        isequal(record.source_sample_content_hash, sample.content_hash) ||
        throw(ArgumentError("multidimensional MFRM cache source/target mismatch at $path"))
    serialization = record.serialization
    serialization isa NamedTuple && keys(serialization) == (:format, :julia_version, :portability) &&
        serialization.format === :julia_serialization && serialization.julia_version isa AbstractString &&
        serialization.portability === :same_julia_major_minor_recommended ||
        throw(ArgumentError("invalid multidimensional MFRM serialization metadata at $path"))
    artifact = record.artifact
    _nt_get(artifact, :schema, nothing) in _fixed_q_artifact_schemas(record.fit) ||
        throw(ArgumentError("unsupported multidimensional MFRM artifact schema at $path"))
    reproducibility = _nt_get(artifact, :reproducibility, nothing)
    policy = reproducibility isa NamedTuple ? _nt_get(reproducibility, :artifact_policy, nothing) : nothing
    policy isa NamedTuple && keys(policy) == (:draws, :log_posterior, :sampler_stats, :environment, :package_status) &&
        all(flag -> flag isa Symbol && flag in (:included, :omitted), values(policy)) &&
        _nt_get(artifact, :created_at, nothing) isa AbstractString && hasproperty(artifact, :environment) ||
        throw(ArgumentError("invalid multidimensional MFRM artifact policy at $path"))
    (policy.environment === :included ? artifact.environment isa AbstractDict : artifact.environment === nothing) ||
        throw(ArgumentError("multidimensional MFRM artifact environment policy mismatch at $path"))
    expected = _mfrm_fixed_q_artifact_payload(record.fit;
        legacy = artifact.schema == "bayesianmgmfrm.mfrm_fixed_q_fit_artifact.v1",
        include_draws = policy.draws === :included, include_log_posterior = policy.log_posterior === :included,
        include_sampler_stats = policy.sampler_stats === :included, include_environment = policy.environment === :included,
        include_packages = policy.package_status === :included)
    actual = Base.structdiff(artifact, (; created_at = nothing, environment = nothing,
        content_hash = nothing, archive_manifest = nothing))
    isequal(actual, expected) || throw(ArgumentError("multidimensional MFRM artifact does not match the saved fit at $path"))
    for (archive, label) in ((record.archive_manifest, :fit_cache_artifact),
            (_nt_get(artifact, :archive_manifest, nothing), _fixed_q_artifact_label(record.fit)))
        archive isa NamedTuple && _nt_get(archive, :created_at, nothing) isa AbstractString &&
            hasproperty(archive, :source_path) && (ismissing(archive.source_path) || archive.source_path isa AbstractString) ||
            throw(ArgumentError("invalid multidimensional MFRM archive manifest at $path"))
        excluded = (; created_at = nothing, source_path = nothing)
        isequal(Base.structdiff(archive, excluded),
            Base.structdiff(fit_archive_manifest(artifact; label), excluded)) ||
            throw(ArgumentError("multidimensional MFRM archive does not match its artifact at $path"))
    end
    return record
end

function _mfrm_fixed_q_plot_data(result::NamedTuple; interval::Real = 0.95, kwargs...)
    _interval_probabilities(Float64(interval))
    # Rebuild from the checked canonical record; never trust mutable derived views.
    checked = _fixed_q_report_samples(result)
    labels = _fixed_q_result_spec(checked).dimension_labels
    selected = _select_posterior_coordinates(checked.model_coordinates, labels; kwargs...)
    selected.scale === :model || throw(ArgumentError("fixed-Q MFRM interval plots use scale = :model"))
    constraints = Dict(:person => "locations anchored by priors", :item => "locations anchored by priors",
        :rater => "sum to zero", :item_steps => "first step zero sum to zero",
        :item_dimension_discrimination => "active Q loadings fixed at 1",
        :rater_consistency => "fixed at 1")
    checked.model === :mfrm_fixed_q_correlated_2d &&
        (constraints[:latent_correlation] = "population correlation; estimated")
    data = _posterior_interval_data(selected; interval, constraints,
        diagnostic = replace(_plot_diagnostic_note(checked.diagnostics.summary),
            "inspect diagnostics(fit)" => "inspect parameter and sampler diagnostics"))
    rows = [merge(row, (; coordinate.derived)) for (row, coordinate) in zip(data.rows, selected.rows)]
    checked.model === :mfrm_fixed_q_correlated_2d &&
        (rows = [merge(row, (; coordinate.parameter_space)) for (row, coordinate) in zip(rows, selected.rows)])
    return merge(data, (; rows, model = checked.model, dimension_labels = copy(labels),
        backend = checked.record.run.backend, target_identity = checked.record.target_identity,
        fixed_note = "Diamonds: fixed coefficients or zero baseline steps. Inactive Q loadings are zero and omitted."))
end

function _plot_mfrm_fixed_q(result::NamedTuple; size = nothing, kwargs...)
    extension = Base.get_extension(@__MODULE__, :BayesianMGMFRMCairoMakieExt)
    extension === nothing && throw(ArgumentError("fixed-Q MFRM plotting requires `using CairoMakie`"))
    data = _mfrm_fixed_q_plot_data(result; kwargs...)
    return _render_mfrm_fixed_q(extension, :posterior, data; size)
end

function _mfrm_fixed_q_diagnostic_plot_data(result::NamedTuple;
        max_parameters::Int = 12, bins = 20, kwargs...)
    bins isa Integer && !(bins isa Bool) && bins > 0 || throw(ArgumentError("bins must be a positive integer"))
    checked = _fixed_q_report_samples(result)
    labels = _fixed_q_result_spec(checked).dimension_labels
    selected = _select_posterior_coordinates(checked.model_coordinates, labels; max_parameters, kwargs...)
    selected.scale === :model || throw(ArgumentError("fixed-Q MFRM diagnostic plots use scale = :model"))
    run = checked.record.run
    data = _trace_rank_plot_data(selected, checked.diagnostics.model_parameter_rows,
        checked.diagnostics, run; bins, nchains = run.controls.chains, per_chain = run.controls.ndraws,
        fixed_status = "Fixed coefficient or baseline step; diagnostics not applicable")
    if checked.model === :mfrm_fixed_q_correlated_2d
        rows = [merge(row, (; coordinate.parameter_space)) for (row, coordinate) in zip(data.rows, selected.rows)]
        data = merge(data, (; rows))
    end
    return merge(data, (; model = checked.model, dimension_labels = copy(labels),
        backend = run.backend, target_identity = checked.record.target_identity,
        diagnostic = replace(data.diagnostic,
            "inspect diagnostics(fit)" => "inspect parameter and sampler diagnostics")))
end

function _plot_mfrm_fixed_q_diagnostics(result::NamedTuple; size = nothing, kwargs...)
    extension = Base.get_extension(@__MODULE__, :BayesianMGMFRMCairoMakieExt)
    extension === nothing && throw(ArgumentError("fixed-Q MFRM plotting requires `using CairoMakie`"))
    data = _mfrm_fixed_q_diagnostic_plot_data(result; kwargs...)
    return _render_mfrm_fixed_q(extension, :diagnostics, data; size)
end

function _mfrm_fixed_q_predictive_draws(target::_MFRMFixedQReferenceLogDensity,
        draws::AbstractMatrix{<:Real})
    size(draws, 1) > 0 || throw(ArgumentError("fixed-Q MFRM prediction requires retained draws"))
    design = target.base.design
    direct = Matrix{Float64}(undef, size(draws, 1), length(design.parameter_names))
    for i in axes(draws, 1)
        # The existing likelihood's 1.7 multiplier cancels this reference mapping.
        # Stored draws and reported coordinates remain in unit logits.
        direct[i, :] .= _mgmfrm_source_constrained_params_from_unconstrained(design,
            _mfrm_fixed_q_reference_raw(target, view(draws, i, :)))
    end
    return direct
end

function _mfrm_fixed_q_predictive_check(result::NamedTuple;
        ndraws::Union{Nothing,Int} = nothing, draw_indices = nothing, seed::Integer = 1)
    checked = _fixed_q_report_samples(result)
    record, run = checked.record, checked.record.run
    rng, rng_control = _fit_rng(Random.default_rng(), seed)
    indices = _posterior_draw_indices(run, ndraws, draw_indices, rng)
    spec = _fixed_q_result_spec(checked)
    correlated = checked.model === :mfrm_fixed_q_correlated_2d
    prior = correlated ? record.prior.base : record.prior
    target = _MFRMFixedQReferenceLogDensity(spec; prior = MFRMPrior(; prior.scales...))
    # Conditional rating probabilities depend on retained abilities, not rho separately.
    columns = 1:LogDensityProblems.dimension(target)
    direct = _mfrm_fixed_q_predictive_draws(target, view(run.draws, indices, columns))
    replicated = _replicate_scores_mgmfrm_direct(target.base.design, direct, rng)
    check = _posterior_predictive_check(spec, replicated, indices)
    return merge(check, (; model = checked.model, backend = run.backend,
        target_identity = record.target_identity, n_retained = size(run.draws, 1),
        chain_ids = run.chain_ids[indices], iterations = run.iterations[indices],
        rng = rng_control, diagnostics = checked.diagnostics,
        diagnostic = replace(_plot_diagnostic_note(checked.diagnostics.summary),
            "inspect diagnostics(fit)" => "inspect parameter and sampler diagnostics")))
end

function _mfrm_fixed_q_predictive_plot_data(result::NamedTuple; interval::Real = 0.9,
        ndraws::Union{Nothing,Int} = nothing, draw_indices = nothing, seed::Integer = 1)
    _interval_probabilities(interval)
    check = _mfrm_fixed_q_predictive_check(result; ndraws, draw_indices, seed)
    data = _category_predictive_plot_data(check; interval, ndraws, draw_indices,
        n_retained = check.n_retained, rng = check.rng, diagnostic = check.diagnostic)
    return merge(data, (; check.model, check.backend, check.target_identity,
        check.chain_ids, check.iterations))
end

function _plot_mfrm_fixed_q_predictive(result::NamedTuple; size = nothing, kwargs...)
    extension = Base.get_extension(@__MODULE__, :BayesianMGMFRMCairoMakieExt)
    extension === nothing && throw(ArgumentError("fixed-Q MFRM plotting requires `using CairoMakie`"))
    data = _mfrm_fixed_q_predictive_plot_data(result; kwargs...)
    return _render_mfrm_fixed_q(extension, :predictive, data; size)
end

function _canonical_mfrm_fixed_q_samples(fit::MultidimensionalMFRMFit)
    checked = _mfrm_fixed_q_samples(fit)
    _is_mfrm_fixed_q(checked.record.spec) || throw(ArgumentError(
        "saved-result reporting and plotting require canonical multidimensional MFRM samples; legacy samples use the private entry points"))
    return checked
end

plot_posterior(fit::MultidimensionalMFRMFit; kwargs...) =
    _plot_mfrm_fixed_q(_canonical_mfrm_fixed_q_samples(fit); kwargs...)
plot_diagnostics(fit::MultidimensionalMFRMFit; kwargs...) =
    _plot_mfrm_fixed_q_diagnostics(_canonical_mfrm_fixed_q_samples(fit); kwargs...)
plot_predictive(fit::MultidimensionalMFRMFit; kwargs...) =
    _plot_mfrm_fixed_q_predictive(_canonical_mfrm_fixed_q_samples(fit); kwargs...)

function _render_mfrm_fixed_q(extension, kind, data; size = nothing)
    backend = data.backend === :advancedhmc ? "Julia (AdvancedHMC)" : "CmdStan"
    correlated = data.model === :mfrm_fixed_q_correlated_2d
    model = correlated ? "Experimental correlated MFRM (fixed coefficients)" :
        "Experimental fixed-coefficient multidimensional MFRM"
    scale_note = correlated ? "locations: unit logits | rho: correlation" : "unit logits"
    units = Dict(:item_dimension_discrimination => "Loading (dimensionless)",
        :rater_consistency => "Consistency (dimensionless)", :latent_correlation => "Population correlation (rho)")
    kind === :posterior && return extension._render_posterior(data;
        title = "$model\n$backend | $scale_note",
        dimension_labels = data.dimension_labels, xlabel = units, size)
    kind === :diagnostics && return extension._render_diagnostics(data;
        title = "$model chain diagnostics\n$backend | $scale_note", ylabel = units, size)
    return extension._render_predictive(data;
        title = "$model\n$backend | unit-logit posterior predictive check\nCategory proportions", size)
end

# Private sample-report assembler; canonical fit reporting reuses its numerical sections.
function _mfrm_fixed_q_report(result::NamedTuple; posterior_interval::Real = 0.95,
        predictive_interval::Real = 0.9, include_posterior_predictive::Bool = true,
        ndraws::Union{Nothing,Int} = nothing, draw_indices = nothing, seed::Integer = 1,
        on_section_error::Symbol = :capture, require_complete::Bool = false)
    checked = _fixed_q_report_samples(result)
    record, run = checked.record, checked.record.run
    spec = _fixed_q_result_spec(checked)
    data = spec.data
    correlated = checked.model === :mfrm_fixed_q_correlated_2d
    lower, upper = _interval_probabilities(posterior_interval)
    _interval_probabilities(predictive_interval)
    policy = _fit_report_on_section_error(on_section_error)
    seed isa Bool && throw(ArgumentError("report seed must be an integer, not Bool"))
    _, rng_control = _fit_rng(Random.default_rng(), seed)
    !include_posterior_predictive && (ndraws !== nothing || draw_indices !== nothing) &&
        throw(ArgumentError("draw selection requires include_posterior_predictive = true"))
    summarize(draws, names) = _posterior_summary_rows(draws, names; lower, upper,
        intervals = (), reference = 0.0, rope = nothing, rope_probability_threshold = 0.95)
    posterior = _fit_report_section(policy) do
        rows = summarize(run.draws, checked.parameter_names)
        correlated && (rows = [merge(row, (; parameter_space = space))
            for (row, space) in zip(rows, checked.parameter_spaces)])
        (; rows, n_rows = length(rows), parameter_space = correlated ? :unit_logit_and_fisher_z : :unit_logit_free,
            interpretation = correlated ? "Sampled locations/steps use unit logits; the correlation coordinate uses Fisher z. All retained draws; central $(100 * posterior_interval)% credible intervals." : "Sampled free coordinates in unit logits; all retained draws. Central $(100 * posterior_interval)% credible intervals.")
    end
    direct_posterior = _fit_report_section(policy) do
        coordinates = checked.model_coordinates
        summaries = summarize(hcat([row.values for row in coordinates]...), getproperty.(coordinates, :parameter))
        rows = [merge(row, (; coordinate.block, coordinate.dimension, coordinate.fixed, coordinate.derived,
            dimension_label = coordinate.dimension === nothing ? missing : spec.dimension_labels[coordinate.dimension]))
            for (row, coordinate) in zip(summaries, coordinates)]
        correlated && (rows = [merge(row, (; coordinate.parameter_space)) for (row, coordinate) in zip(rows, coordinates)])
        (; rows, n_rows = length(rows), parameter_space = correlated ? :unit_logit_with_fixed_coefficients_and_correlation : :unit_logit_with_fixed_coefficients,
            interpretation = correlated ? "Locations and steps use unit logits; fixed coefficients are dimensionless. Population rho is transformed draw by draw from Fisher z and has its own intervals and diagnostics. Central $(100 * posterior_interval)% credible intervals use all retained draws. Fixed point intervals are constants, not estimated certainty; derived intervals use reconstructed draws." : "Reconstructed model coordinates: locations and steps in unit logits; loadings and consistency dimensionless. Central $(100 * posterior_interval)% credible intervals use all retained draws. Fixed point intervals are declared constants, not estimated certainty. Derived last-rater and last-step intervals use their reconstructed draws.")
    end
    posterior_predictive = include_posterior_predictive ? _fit_report_section(policy) do
        check = _mfrm_fixed_q_predictive_check(checked; ndraws, draw_indices, seed)
        rows = predictive_check_summary(check; interval = predictive_interval, include_grouped = true)
        selection = draw_indices !== nothing ? "Explicit ordered draw indices" :
            ndraws === nothing ? "All retained draws in stored order" : "Draw indices sampled with replacement"
        n_replicates, n_unique_draws = length(check.draw_indices), length(unique(check.draw_indices))
        (; rows, n_rows = length(rows), check.draw_indices, check.chain_ids, check.iterations, check.rng,
            selection, n_replicates, n_unique_draws, n_retained = size(run.draws, 1), n_observations = data.n,
            interpretation = "Conditional on the existing rating rows, persons, items and raters. $(n_replicates) replicated datasets of $(data.n) ratings; $(n_unique_draws) distinct draws from $(size(run.draws, 1)) retained; seed $(rng_control.seed). $selection. Central $(100 * predictive_interval)% pointwise predictive intervals summarize replicated statistics, not parameter uncertainty. Same-data agreement does not establish convergence or performance for new facets.")
    end : _fit_report_not_requested()
    warning_rows = checked.diagnostics.summary.flag === :ok ? NamedTuple[] :
        [(; code = :mcmc_warning, severity = :warning,
            message = replace(_plot_diagnostic_note(checked.diagnostics.summary),
                "inspect diagnostics(fit)" => "inspect parameter and sampler diagnostics"),
            action = :inspect_parameter_and_sampler_diagnostics)]
    prior_scales = correlated ? record.prior.base.scales : record.prior.scales
    prior_rows = [_fit_report_prior_policy_row(; family = checked.model, block,
        parameter_space = :unit_logit_free, prior_family = :normal, location = 0.0,
        scale_parameter, scale = getproperty(prior_scales, scale_parameter), active = true,
        direct_scale_prior = true, jacobian_policy = :none_declared_free_coordinate_density,
        status = :active, note = "Independent zero-mean normal prior on the free unit-logit coordinates in this block.")
        for (block, scale_parameter) in ((:person, :person_sd), (:rater_free, :rater_sd),
            (:item, :item_sd), (:item_steps, :step_sd))]
    if correlated
        prior_rows = _mfrm_correlated_prior_rows(prior_rows, record.prior.correlation.lkj_eta)
    end
    fixed_rows = [(; row.parameter, row.block, row.dimension,
        fixed = true, value = first(row.values)) for row in checked.model_coordinates if row.fixed]
    q_rows = [(; item = data.item_levels[i], dimension = d, dimension_label = spec.dimension_labels[d],
        loading = Int(spec.q_matrix[i, d]), fixed = true) for i in axes(spec.q_matrix, 1) for d in axes(spec.q_matrix, 2)]
    unsupported = (; (name => _fit_report_unsupported("$label is not connected to fixed-coefficient MFRM saved results.")
        for (name, label) in ((:rating_design, "Rating-design audit"),
            (:category_functioning, "Category-functioning analysis"), (:rater_homogeneity, "Rater-homogeneity analysis"),
            (:mcmc_budget_guidance, "MCMC-budget guidance"), (:prior_predictive, "Prior predictive analysis"),
            (:calibration, "Calibration analysis"), (:waic, "WAIC"), (:loo, "LOO"),
            (:dff, "DFF analysis"), (:artifact, "Public fit artifacts")))...)
    report = merge((; schema = "bayesianmgmfrm.fit_report.v1", object = :fit_report,
        created_at = string(now()), family = checked.model, thresholds = spec.thresholds,
        dimensions = spec.dimensions, dimension_labels = copy(spec.dimension_labels),
        estimation_status = :private_reference,
        interpretation = (correlated ? "Population rho has a separate correlation scale. " : "") * "Report completeness means no captured section errors; it does not certify MCMC quality or support for every analysis. Unsupported sections state their reasons. This report describes a fixed-coefficient model in unit logits and is not a fit cache or restart checkpoint.",
        metadata = correlated ? _mfrm_correlated_2d_metadata(checked) : _mfrm_fixed_q_metadata(checked),
        report_policy = (; posterior_interval = Float64(posterior_interval),
            predictive_interval = Float64(predictive_interval), include_posterior_predictive,
            ndraws, draw_indices = draw_indices === nothing ? nothing : collect(draw_indices),
            resolved_draw_indices = get(posterior_predictive, :draw_indices, nothing),
            rng = rng_control, on_section_error = policy, require_complete),
        diagnostics = merge(checked.diagnostics, (; status = :computed, warning_rows,
            interpretation = "Free and reconstructed parameter diagnostics use all retained draws and the stored thresholds. Fixed coordinates have no convergence gate; derived coordinates have their own diagnostics. Whole-model warnings remain even when prediction uses a subset.")),
        warmup = (; status = :computed, rows = checked.warmup_diagnostics,
            n_rows = length(checked.warmup_diagnostics), interpretation = _FIT_REPORT_WARMUP_INTERPRETATION),
        fixed_coordinates = (; status = :computed, rows = fixed_rows, n_rows = length(fixed_rows),
            interpretation = "Active Q loadings and rater consistency are fixed at one; baseline item steps at zero. Inactive Q loadings are zero and listed in the Q table."),
        q_matrix = (; status = :computed, rows = q_rows, n_rows = length(q_rows), q_matrix = copy(spec.q_matrix),
            dimension_labels = copy(spec.dimension_labels),
            interpretation = correlated ? "Stored between-item Q entries are fixed coefficients. The two ability dimensions have an estimated population correlation rho; this is distinct from dependence among posterior draws." : "Stored confirmatory Q entries are fixed coefficients. Latent-population correlation is fixed to identity; posterior dependence is not an estimated population correlation."),
        prior_policy = (; status = :computed, rows = prior_rows, n_rows = length(prior_rows),
            interpretation = correlated ? "Locations are prior-anchored. Each directly parameterized ability pair has a bivariate normal prior with covariance person_sd^2 * [1 rho; rho 1]. Other free coordinates retain independent normal priors; sum-constrained reconstructions are dependent. LKJ(eta) is declared on rho; rho = tanh(z) contributes log(1-rho^2) exactly once. The ability covariance determinant is part of the normal density, not another transformation Jacobian." : "Locations are prior-anchored. Normal priors are declared on free unit-logit coordinates. The last rater and last item steps are negative sums and have induced dependent priors; each baseline step is zero. Loadings and consistency have no sampled prior. Deterministic reconstruction adds no Jacobian to this declared free-coordinate density."),
        pooling_policy = (; status = :computed, rows = [correlated && row.block === :latent_correlation ?
            (; row.block, scale = missing, scale_estimated = false, shape_parameter = :eta,
                shape = row.shape, shape_estimated = false, correlation_estimated = true) :
            (; row.block, scale = row.scale, scale_estimated = false) for row in prior_rows], n_rows = length(prior_rows),
            interpretation = correlated ? "Marginal ability and other normal-prior scales and LKJ eta are fixed inputs. Population rho is estimated. Ability coordinates are jointly normal within each person; other free blocks retain independent priors and sum-constrained reconstructions are dependent." : "Prior scales are fixed inputs, not learned hyperparameters. Free coordinates have independent priors; sum-constrained reconstructions are dependent."),
        posterior, direct_posterior, posterior_predictive), unsupported)
    if correlated
        # Keep rho visible even when the human report previews only a few rows.
        rho_name = last(checked.model_coordinates).parameter
        report = merge(report, (; diagnostics = merge(report.diagnostics, (;
            correlation_rows = filter(row -> row.parameter == rho_name, checked.diagnostics.model_parameter_rows)))))
        if direct_posterior.status === :computed
            report = merge(report, (; direct_posterior = merge(direct_posterior, (;
                correlation_rows = filter(row -> row.parameter == rho_name, direct_posterior.rows)))))
        end
    end
    health = fit_report_health(report)
    report = merge(report, (; report_status = health.status, report_health = health))
    require_complete && _require_complete_fit_report(report, :_mfrm_fixed_q_report)
    return report
end

"""
    fit_report(fit::MultidimensionalMFRMFit; view = :full,
        posterior_lower = 0.025, posterior_upper = 0.975, seed = 1, ...)

Report a saved fixed-coefficient multidimensional MFRM result, including its
rating-design audit and reproducibility artifact summary. Use
`include_full_artifact = true` to embed the full artifact, or `view = :public`
for reader-facing output. This experimental result uses unit logits, fixed Q
coefficients and independent abilities unless `Experimental.correlated(spec)`
was selected. Correlated results default to `view = :public` and include rho
intervals and diagnostics. Estimate it with
`BayesianMGMFRM.Experimental.fit`. Unsupported analyses are labelled in the report.

Posterior bounds must be central and strictly inside `(0, 1)`. Prediction uses
the existing rating rows and a local `seed`; posterior summaries and diagnostics
always use all retained draws. Diagnostic settings must match the saved fit.

Set `include_prior_predictive = true` to simulate from the saved model/prior,
with `prior_predictive_ndraws = 100` and `prior_interval = 0.95` by default.
This adds parameter and rating summaries, correlation intervals when applicable,
and prior-implication diagnostics. Prior and posterior predictions use separate
local RNGs initialized from `seed`; neither updates nor refits the saved result.
`prior_interval` controls parameter prior intervals; `predictive_interval`
controls rating prediction intervals for both prior and posterior checks.
"""
function fit_report(fit::_FixedQMFRMFit; view::Symbol = _fixed_q_default_view(fit),
        posterior_lower::Real = 0.025, posterior_upper::Real = 0.975,
        predictive_interval::Real = 0.9, include_posterior_predictive::Bool = true,
        include_prior_predictive::Bool = false, prior_predictive_ndraws::Int = 100,
        prior_interval::Real = 0.95,
        ndraws::Union{Nothing,Int} = nothing, draw_indices = nothing, seed::Integer = 1,
        include_artifact::Bool = true, include_full_artifact::Bool = false,
        artifact_include_draws::Bool = false,
        artifact_include_log_posterior::Bool = artifact_include_draws,
        artifact_include_sampler_stats::Bool = false,
        artifact_include_environment::Bool = false, artifact_include_packages::Bool = false,
        split_chains::Bool = fit.record.run.split_chains_requested,
        rhat_threshold::Real = fit.record.run.checked.rhat_threshold,
        ess_threshold::Real = fit.record.run.checked.ess_threshold,
        on_section_error::Symbol = :capture, require_complete::Bool = false)
    view in (:full, :public) || throw(ArgumentError("view must be :full or :public"))
    _interval_probabilities(prior_interval)
    lower, upper = _check_posterior_summary_bounds(posterior_lower, posterior_upper)
    interval = upper - lower
    0 < interval < 1 && isapprox(lower + upper, 1; atol = 8eps(Float64), rtol = 0) ||
        throw(ArgumentError("multidimensional MFRM reports require central posterior_lower/posterior_upper bounds strictly inside (0, 1)"))
    !include_artifact && (include_full_artifact || artifact_include_draws ||
        artifact_include_log_posterior || artifact_include_sampler_stats ||
        artifact_include_environment || artifact_include_packages) &&
        throw(ArgumentError("artifact options require include_artifact = true"))
    checked = _canonical_mfrm_fixed_q_samples(fit)
    diagnostics(fit; split_chains, rhat_threshold, ess_threshold)
    policy = _fit_report_on_section_error(on_section_error)
    base = _mfrm_fixed_q_report(checked; posterior_interval = interval, predictive_interval,
        include_posterior_predictive, ndraws, draw_indices, seed, on_section_error)
    prior_predictive = _fixed_q_prior_report(checked; ndraws = prior_predictive_ndraws,
        seed, interval = prior_interval, predictive_interval, include_prior_predictive,
        on_section_error = policy)
    manifest = _fixed_q_model_manifest(fit)
    rating_design = _fit_report_section(policy) do
        audit = manifest.rating_design
        rows = collect(audit.rows)
        (; schema = audit.schema, rows, n_rows = length(rows), summary = audit.summary, audit)
    end
    artifact = include_artifact ? _fit_report_section(policy) do
        value = fit_artifact(fit; include_draws = artifact_include_draws,
            include_log_posterior = artifact_include_log_posterior,
            include_sampler_stats = artifact_include_sampler_stats,
            include_environment = artifact_include_environment,
            include_packages = artifact_include_packages,
            split_chains, rhat_threshold, ess_threshold)
        (; schema = value.schema, content_hash = value.content_hash,
            archive_manifest = value.archive_manifest,
            artifact = include_full_artifact ? value : nothing)
    end : _fit_report_not_requested()
    report = merge(base, (; family = :mfrm, model = _fixed_q_fit_model(fit),
        estimation_status = :experimental,
        metadata = merge(fit_metadata(fit), (; estimation_status = :experimental,
            fitting_available = true,
            interpretation = checked.model === :mfrm_fixed_q_correlated_2d ?
                "Experimental correlated MFRM: locations and steps in unit logits; population rho on its correlation scale." :
                "Experimental fixed-coefficient multidimensional MFRM reporting in unit logits.")),
        manifest, rating_design, artifact, prior_predictive,
        report_policy = merge(base.report_policy, (; posterior_lower = lower, posterior_upper = upper,
            include_prior_predictive, prior_predictive_ndraws, prior_interval = Float64(prior_interval),
            include_artifact, include_full_artifact, require_complete))))
    health = _derive_fit_report_health(report)
    report = merge(report, (; report_status = health.status, report_health = health))
    require_complete && _require_complete_fit_report(report, :fit_report)
    return view === :full ? report : fit_report_public(report)
end

fit_report_public(fit::_FixedQMFRMFit; kwargs...) =
    fit_report_public(fit_report(fit; kwargs...))

# Private sample bundles and canonical saved fits share figure preparation and staging.
function _save_mfrm_fixed_q_report_bundle(directory::AbstractString, result::NamedTuple;
        figures = (posterior = (;), diagnostics = (;), predictive = (;)),
        seed::Integer = 1, overwrite::Bool = false, label = nothing,
        title::AbstractString = "Fixed-coefficient multidimensional MFRM report",
        max_rows::Integer = 6, include_empty::Bool = false,
        require_complete::Bool = false, kwargs...)
    if figures === nothing
        report = _mfrm_fixed_q_report(result; seed, require_complete, kwargs...)
        return save_fit_report_bundle(directory, report;
            overwrite, label, title, max_rows, include_empty, require_complete)
    end
    _fit_report_figure_options(figures)
    haskey(figures, :wright) && throw(ArgumentError("fixed-coefficient MFRM bundles support posterior, diagnostics and predictive figures"))
    extension = _check_fit_report_figure_destination(directory, figures; overwrite, max_rows)
    checked = _fixed_q_report_samples(result)
    report = _mfrm_fixed_q_report(checked; seed, require_complete, kwargs...)
    return _write_mfrm_fixed_q_report_figures(directory, checked, report, figures, extension;
        seed, overwrite, label, title, max_rows, include_empty, require_complete)
end

function save_fit_report_bundle(directory::AbstractString, fit::_FixedQMFRMFit;
        figures = nothing, seed::Integer = 1, view::Symbol = _fixed_q_default_view(fit),
        overwrite::Bool = false, label = nothing,
        title::AbstractString = fit isa _CorrelatedMFRMFit ?
            "Correlated multidimensional MFRM report" : "Multidimensional MFRM report",
        max_rows::Integer = 6,
        include_empty::Bool = false, require_complete::Bool = false, kwargs...)
    view in (:full, :public) || throw(ArgumentError("view must be :full or :public"))
    if figures === nothing
        report = fit_report(fit; view, seed, require_complete, kwargs...)
        return _save_fit_report_bundle(directory, report;
            overwrite, label, title, max_rows, include_empty, require_complete)
    end
    _fit_report_figure_options(figures)
    haskey(figures, :wright) && throw(ArgumentError("multidimensional MFRM bundles do not support Wright maps"))
    any(kind -> haskey(figures, kind), (:prior, :prior_predictive)) &&
        !get(kwargs, :include_prior_predictive, false) &&
        throw(ArgumentError("prior figures require include_prior_predictive = true"))
    extension = _check_fit_report_figure_destination(directory, figures; overwrite, max_rows)
    checked = _canonical_mfrm_fixed_q_samples(fit)
    report = fit_report(fit; view = :full, seed, require_complete, kwargs...)
    exported_report = view === :public ? fit_report_public(report) : report
    return _write_mfrm_fixed_q_report_figures(directory, checked, report, figures, extension;
        exported_report, seed, overwrite, label, title, max_rows, include_empty, require_complete)
end

function _write_mfrm_fixed_q_report_figures(directory, checked, report, figures, extension;
        exported_report = report, seed, overwrite, label, title, max_rows,
        include_empty, require_complete)
    identity = (; report.family, report.dimension_labels, report.metadata.backend,
        report.metadata.scale_convention, report.metadata.target_identity,
        report.metadata.source_sample_schema, report.metadata.source_sample_content_hash)
    return _write_fit_report_figures(directory, exported_report, figures;
            identity, seed, overwrite, label, title, max_rows, include_empty, require_complete) do kind, numerical, size
        if kind in (:prior, :prior_predictive)
            data = _report_prior_plot_data(report.prior_predictive, kind; numerical...)
            figure = kind === :prior ? _render_fixed_q_prior(extension, data; size) :
                _render_prior_predictive(extension, data; size)
            return (; data, figure)
        end
        data = if kind === :posterior
            _mfrm_fixed_q_plot_data(checked; numerical..., interval = report.report_policy.posterior_interval)
        elseif kind === :diagnostics
            _mfrm_fixed_q_diagnostic_plot_data(checked; numerical...)
        else
            section = report.posterior_predictive
            section.status === :computed || throw(ArgumentError("predictive figure requires a computed posterior_predictive report section"))
            rows = predictive_check_plot_data(filter(row -> row.statistic === :category_proportion, section.rows))
            (; rows, interval = report.report_policy.predictive_interval,
                section.draw_indices, section.chain_ids, section.iterations, section.rng,
                section.n_replicates, section.n_observations, section.n_retained,
                section.n_unique_draws, section.selection, model = checked.model,
                report.metadata.backend, report.metadata.target_identity,
                diagnostic = replace(_plot_diagnostic_note(report.diagnostics.summary),
                    "inspect diagnostics(fit)" => "inspect parameter and sampler diagnostics"))
        end
        (; data, figure = _render_mfrm_fixed_q(extension, kind, data; size))
    end
end
