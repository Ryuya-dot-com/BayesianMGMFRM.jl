# Reuse native model-coordinate reconstruction, never predictive unit conversion.
function _recovery_native(fit::_ModelComparisonFit)
    checked = PredictionObservationAdapter._context(fit, nothing, nothing, Random.default_rng())
    return (; coordinates=_posterior_plot_coordinates(fit, :model), spec=checked.spec,
        total_draws=checked.total_draws, chain_ids=checked.chain_ids, iterations=checked.iterations,
        quality=checked.quality, prior=_prior_cache_record(fit.prior),
        checked.source_sample_hash, checked.source_hash_status)
end

function _recovery_native(fit::_RecordedMGMFRMFit)
    context = _mgmfrm_correlated_2d_report_context(fit)
    record, run = context.checked.record, context.checked.record.run
    return (; coordinates=_mgmfrm_correlated_2d_report_coordinates(context; scale=:model),
        spec=record.spec, run.total_draws, run.chain_ids, run.iterations,
        quality=context.diagnostics.summary, prior=record.prior,
        source_sample_hash=record.content_hash, source_hash_status=:validated)
end

function _recovery_native(fit::_FixedQMFRMFit)
    checked = _fixed_q_report_samples((; fit.record))
    spec = _fixed_q_result_spec(checked)
    spec.family === :mfrm || throw(ArgumentError(
        "common recovery requires canonical fixed-MFRM records; legacy v1 is unsupported"))
    location = _fixed_q_location_diagnostics(checked)
    run = checked.record.run
    return (; coordinates=checked.model_coordinates, spec, run.total_draws, run.chain_ids, run.iterations,
        quality=merge(checked.diagnostics.summary, (; location.location_status, location.location_summary)),
        prior=checked.record.prior, source_sample_hash=checked.record.content_hash, source_hash_status=:validated)
end

function _recovery_context(fit)
    context = _recovery_native(fit)
    S, chains, iterations = context.total_draws, context.chain_ids, context.iterations
    S >= 1 && length(chains) == length(iterations) == S ||
        throw(ArgumentError("recovery requires all original retained draws and chain metadata"))
    labels = sort(unique(chains))
    labels == collect(1:length(labels)) && S % length(labels) == 0 ||
        throw(ArgumentError("recovery requires equal complete chains numbered from one"))
    n = div(S, length(labels))
    chains == repeat(labels; inner=n) && iterations == repeat(1:n; outer=length(labels)) ||
        throw(ArgumentError("recovery chains must be complete and in original order"))
    names = getproperty.(context.coordinates, :parameter)
    !isempty(names) && length(unique(names)) == length(names) ||
        throw(ArgumentError("recovery quantity names must be nonempty and unique"))
    all(r -> length(r.values) == S && all(isfinite, r.values), context.coordinates) ||
        throw(ArgumentError("nonfinite or misaligned model-coordinate draws"))
    all(r -> !r.fixed || allequal(r.values), context.coordinates) ||
        throw(ArgumentError("a declared fixed recovery quantity varies across draws"))
    return context
end

function _recovery_quantity(row, spec)
    dimensionless = row.block in (:item_discrimination, :rater_discrimination, :item_dimension_discrimination, :rater_consistency)
    space = get(row, :parameter_space, dimensionless ? :dimensionless :
        spec.family === :mfrm ? :unit_logit : :model_coordinate)
    return (; row.parameter, row.block, row.dimension,
        dimension_label=row.dimension === nothing ? nothing : spec.dimension_labels[row.dimension],
        row.fixed, derived=get(row, :derived, missing), parameter_space=space)
end

function _recovery_model_contract(fit, context)
    spec = context.spec
    return (; family=spec.family, dimensions=spec.dimensions,
        dimension_labels=copy(spec.dimension_labels), q_matrix=deepcopy(spec.q_matrix),
        item_levels=copy(spec.data.item_levels), thresholds=spec.thresholds,
        category_contract=_model_family_category_contract(spec), prior=deepcopy(context.prior),
        fitted_target=_prediction_fitted_target(fit))
end

"""
    BayesianMGMFRM.recovery_quantities(fit)

List supported named model-coordinate quantities of a saved fit, including
dimension labels, units, structural constants and native derived quantities.
All eight supported fit types use their existing report/plot reconstruction;
canonical fixed-MFRM records are required. No plotting dependency is needed.
Use these exact names as keys for `recovery_evaluation`. This is an inventory,
not raw sampler coordinates or a mapping between different latent models.
"""
function recovery_quantities(fit::PredictionObservationAdapter.SupportedFit)
    context = _recovery_context(fit)
    return (; schema="bayesianmgmfrm.recovery_quantities.v1",
        rows=[_recovery_quantity(row, context.spec) for row in context.coordinates],
        model_contract=_recovery_model_contract(fit, context),
        n_retained_draws=context.total_draws, sampling_quality=deepcopy(context.quality),
        context.source_sample_hash, context.source_hash_status,
        scientific_acceptance=:not_established)
end

"""
    BayesianMGMFRM.recovery_evaluation(fit, truth::AbstractDict;
        dataset_id, observation_ids, interval=0.95)

Evaluate named simulation truths for one dataset, using all retained draws and
chains. Keys are exact names from `recovery_quantities`; nonempty subsets are
allowed. Truths must already use the fitted model's scale, labels and identifying
constraints. No truth centering, latent alignment or across-model mapping is
inferred. This function cannot establish that the supplied values generated data.

Reuses native bias/interval recovery arithmetic and MCMC MCSE. Sampling warnings
are retained. Estimated quantities have central-interval coverage; structural
constants have `covered=missing`, `coverage_applicable=false` and a separate
fixed-value/truth agreement flag. Their point intervals are not calibration
evidence. Interval-endpoint MCSE is neither a coverage-decision error bound nor
simulation replication uncertainty, and no precision threshold is applied.

Returns a source-bound, content-hashed record with per-quantity rows and explicit
single-dataset scope. This neither fits/generates data nor pools replications,
performs joint-prior SBC, compares models, or establishes design adequacy.
Existing vector-truth `parameter_recovery` methods are unchanged.
"""
function recovery_evaluation(fit::PredictionObservationAdapter.SupportedFit, truth::AbstractDict;
        dataset_id::AbstractString, observation_ids, interval::Real=0.95)
    lower, upper = _interval_probabilities(interval)
    isempty(strip(dataset_id)) && throw(ArgumentError("dataset_id must be nonempty"))
    !isempty(truth) && all(k -> k isa AbstractString && !isempty(strip(k)), keys(truth)) ||
        throw(ArgumentError("truth must map nonempty exact quantity names to finite real values"))
    all(v -> v isa Real && !(v isa Bool) && isfinite(Float64(v)), values(truth)) ||
        throw(ArgumentError("truth values must be finite real numbers, not Bool"))
    context = _recovery_context(fit)
    ids = PredictionObservationAdapter._ids(observation_ids, context.spec.data.n, "observation_ids")
    names = getproperty.(context.coordinates, :parameter)
    all(k -> k in names, keys(truth)) || throw(ArgumentError("unknown recovery quantity name"))
    coordinates = [r for r in context.coordinates if haskey(truth, r.parameter)]
    all(r -> r.block !== :latent_correlation || -1 <= Float64(truth[r.parameter]) <= 1, coordinates) ||
        throw(ArgumentError("correlation truths must lie in [-1, 1]"))
    n_chains = length(unique(context.chain_ids))
    rows = map(enumerate(coordinates)) do (index, coordinate)
        descriptor = _recovery_quantity(coordinate, context.spec)
        values = reshape(Float64.(coordinate.values), :, 1)
        row = only(_parameter_recovery_rows([coordinate.parameter], Dict(coordinate.block=>1:1),
            values, [Float64(truth[coordinate.parameter])]; interval, metadata=(;)))
        mcse = only(_posterior_mcse_rows(values, [coordinate.parameter], n_chains;
            probabilities=(lower, 0.5, upper), parameter_space=descriptor.parameter_space,
            structurally_fixed_parameters=coordinate.fixed ? Set([coordinate.parameter]) : Set{String}()))
        fixed_match = coordinate.fixed ? first(coordinate.values) == row.true_value : missing
        merge(row, descriptor, (; parameter_index=index, mcse,
            covered=coordinate.fixed ? missing : row.covered,
            coverage_applicable=!coordinate.fixed, fixed_value_matches_truth=fixed_match,
            flag=coordinate.fixed ? (fixed_match ? :fixed_value_matches_truth : :fixed_truth_mismatch) : row.flag))
    end
    sampling_warning = _prediction_sampling_warning(context.quality)
    mcse_warning = any(r -> !r.fixed && r.mcse.mcse_status !== :available, rows)
    fixed_truth_mismatch = any(r -> r.fixed_value_matches_truth === false, rows)
    result = (; schema="bayesianmgmfrm.recovery_evaluation.v1", dataset_id=String(dataset_id),
        observation_ids=ids, source_binding=_prediction_source_binding(context.spec.data, ids, String(dataset_id)),
        model_contract=_recovery_model_contract(fit, context),
        interval_probability=Float64(interval), rows,
        n_retained_draws=context.total_draws, chain_ids=copy(context.chain_ids), iterations=copy(context.iterations),
        evaluated_draws_hash=_cache_hash([(; r.parameter, values=collect(r.values)) for r in coordinates]),
        sampling_quality=deepcopy(context.quality), sampling_warning, mcse_warning, fixed_truth_mismatch,
        status=sampling_warning || mcse_warning || fixed_truth_mismatch ? :warning : :descriptive,
        context.source_sample_hash, context.source_hash_status,
        evaluation_unit=:single_dataset, n_evaluated_datasets=1, independent_replications=:not_verified,
        generating_truth_verification=:not_established, calibration_verified=false,
        uncertainty=(; within_fit_mcmc=:native_mcse, replication_uncertainty=:not_computed,
            coverage_decision_error_bound=:not_computed, precision_threshold=:not_applied),
        sbc=:not_performed, scientific_acceptance=:not_established)
    return _prediction_seal(result)
end
