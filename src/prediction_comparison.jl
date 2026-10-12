function _comparison_prediction_binding(p)
    order = sortperm(p.observation_ids)
    expected = _cache_hash((; dataset_id=p.dataset_id, category_levels=p.category_levels,
        observations=collect(zip(p.observation_ids[order], p.observations[order]))))
    p.training_binding == p.observation_binding == expected ||
        throw(ArgumentError("prediction observation/training binding does not match its contents"))
    return nothing
end

function _prediction_difference_se(delta, observations, unit)
    unit === :none && return (; value=missing, n_units=0, status=:not_requested)
    labels = unit === :observation ? collect(eachindex(delta)) : getproperty.(observations, :person)
    groups = unique(labels)
    totals = [sum(delta[findall(==(g), labels)]) for g in groups]
    G = length(groups)
    G >= 2 || return (; value=missing, n_units=G, status=:insufficient_units)
    return (; value=sqrt(G * var(totals)), n_units=G, status=:approximate)
end

"""
    BayesianMGMFRM.compare_predictions(models::Pair...;
        comparison_axis, criterion=:waic, baseline=nothing, se_unit=:none,
        dataset_id=nothing, observation_ids=nothing, ...)

Compare two or more supported fits, or two or more `prediction_observations`
bundles, on the same original rating outcomes. For fits, supply `dataset_id`
and unique observation IDs: a vector shared by all fits, or a dictionary from
model labels to vectors in each fit's row order. For bundles omit both keywords.
All original draws/chains are used; different fit draw counts are permitted.

Declare `comparison_axis=:model` (same D/Q), `:dimensions` (D and Q may differ),
or `:q_matrix` (same D). Family, priors, scales and correlation metadata are
retained; an axis label alone does not isolate a causal effect of that choice.
Allowed criteria are `:waic`, `:raw_loo`, and `:hill_smoothed_loo`; the last is
the package's non-reference-validated Hill smoother, not validated PSIS.

Rows retain input order. ELPD differences are model minus the declared baseline
(first model by default), not an automatically selected winner. `se_unit=:none`
leaves difference SE missing; `:observation` assumes exchangeable rating units;
`:person` sums differences within person before computing the approximate SE.
The latter is one-way clustering under an exchangeable-person assumption, not
a correction for arbitrary crossed rater/item dependence. These SEs are neither
MCMC MCSE nor repeated-data simulation uncertainty. One unit gives missing SE.

Warnings, problem observation IDs and model identities remain in each row.
This is an existing-level rating-omission approximation, not refitted K-fold,
new-person/rater prediction, scientific acceptance or automatic model selection.
"""
function compare_predictions(models::Pair...; comparison_axis::Symbol,
        criterion::Symbol=:waic, baseline=nothing, se_unit::Symbol=:none,
        dataset_id=nothing, observation_ids=nothing,
        pareto_k_threshold::Real=.7, tail_fraction::Real=.2, min_tail_draws::Int=5)
    length(models) >= 2 || throw(ArgumentError("provide at least two named models"))
    labels = string.(first.(models))
    all(x->!isempty(strip(x)), labels) && length(unique(labels)) == length(labels) ||
        throw(ArgumentError("model labels must be nonempty and unique"))
    comparison_axis in (:model, :dimensions, :q_matrix) ||
        throw(ArgumentError("declare comparison_axis=:model, :dimensions, or :q_matrix"))
    se_unit in (:none, :observation, :person) ||
        throw(ArgumentError("se_unit must be :none, :observation, or :person"))
    criterion in (:waic, :raw_loo, :hill_smoothed_loo) ||
        throw(ArgumentError("choose :waic, :raw_loo, or :hill_smoothed_loo"))
    base_label = baseline === nothing ? first(labels) : string(baseline)
    base = findfirst(==(base_label), labels)
    base === nothing && throw(ArgumentError("baseline must name a supplied model"))
    values = last.(models)
    predictions = if all(x->x isa PredictionObservationAdapter.SupportedFit, values)
        dataset_id isa AbstractString || throw(ArgumentError("fit comparison needs a dataset_id"))
        ids = if observation_ids isa AbstractVector
            fill(observation_ids, length(models))
        elseif observation_ids isa AbstractDict
            mapping = Dict(string(k)=>v for (k,v) in observation_ids)
            length(mapping) == length(observation_ids) && Set(keys(mapping)) == Set(labels) ||
                throw(ArgumentError("observation ID dictionary must match the model labels"))
            [mapping[label] for label in labels]
        else
            throw(ArgumentError("provide observation_ids as a vector or model-label dictionary"))
        end
        [prediction_observations(fit; dataset_id, observation_ids=id, include_probabilities=false)
            for (fit,id) in zip(values,ids)]
    elseif all(x->x isa NamedTuple, values)
        dataset_id === nothing && observation_ids === nothing ||
            throw(ArgumentError("prediction bundles already contain their data/observation IDs"))
        collect(values)
    else
        throw(ArgumentError("supply only supported fits or only prediction bundles"))
    end
    reference = predictions[base]
    orders = [observation_alignment(reference,p) for p in predictions]
    for p in predictions
        _comparison_prediction_binding(p)
        comparison_axis === :dimensions || p.model.dimensions == reference.model.dimensions ||
            throw(ArgumentError("different dimensions require comparison_axis=:dimensions"))
        comparison_axis in (:dimensions,:q_matrix) || isequal(p.model.q_matrix,reference.model.q_matrix) ||
            throw(ArgumentError("different Q requires :dimensions or :q_matrix"))
    end
    evaluations = [prediction_criteria(p; criteria=(criterion,), pareto_k_threshold,
        tail_fraction, min_tail_draws) for p in predictions]
    pointwise = [collect(getproperty(getproperty(e.scores,criterion).pointwise,
        criterion === :waic ? :elpd_waic : :elpd_loo)[order]) for (e,order) in zip(evaluations,orders)]
    all(x->all(isfinite,x), pointwise) || throw(ArgumentError("criterion produced nonfinite ELPD"))
    rows = map(eachindex(predictions)) do i
        e, p = evaluations[i], predictions[i]
        delta = pointwise[i] .- pointwise[base]
        se = _prediction_difference_se(delta,reference.observations,se_unit)
        criterion_warning = getproperty(e.criterion_warnings,criterion)
        (; model=labels[i], baseline=base_label, elpd=sum(pointwise[i]),
            elpd_difference=sum(delta), se_elpd_difference=se.value,
            se_status=se.status, n_uncertainty_units=se.n_units,
            sampling_warning=e.sampling_warning, criterion_warning,
            problem_observation_ids=copy(getproperty(e.problem_observation_ids,criterion)),
            status=e.sampling_warning || criterion_warning !== :ok ? :warning : :descriptive,
            model_contract=deepcopy(p.model), source_sample_hash=p.source_sample_hash,
            source_hash_status=p.source_hash_status, n_retained_draws=p.n_retained_draws,
            pointwise_elpd=pointwise[i], pointwise_difference=delta)
    end
    return (; schema="bayesianmgmfrm.prediction_comparison.v1", criterion, comparison_axis,
        baseline=base_label, dataset_id=reference.dataset_id,
        observation_ids=copy(reference.observation_ids),
        observation_binding=reference.observation_binding, training_binding=reference.training_binding,
        category_levels=copy(reference.category_levels), weighting=reference.weighting,
        prediction_target=reference.prediction_target, conditioning=reference.conditioning,
        criterion_target=:single_rating_omission_fixed_specification,
        rows, se_unit, uncertainty=(; standard_error=se_unit === :none ? :not_requested : :approximate_exchangeable_unit,
            crossed_cluster_adjustment=:not_computed, mcmc_mcse=:not_computed,
            replication_uncertainty=:not_computed, relative_efficiency=:not_used),
        reference_psis_validation=:not_established,
        model_selection=:not_performed, scientific_acceptance=:not_established)
end
