# Common heldout scores are additive rating scores, including when splits use groups.
function _prediction_checked_plan(prepared)
    get(prepared, :schema, nothing) == "bayesianmgmfrm.prediction_refit_plan.v2" ||
        throw(ArgumentError("reprepare the K-fold plan with the current API"))
    _cache_hash(_prediction_plan_payload(prepared)) == prepared.content_hash ||
        throw(ArgumentError("prepared K-fold roster has changed"))
    for request in prepared.folds
        payload = _prediction_fold_payload(request)
        _cache_hash(payload) == request.binding || throw(ArgumentError("fold request has changed"))
        payload.source_binding == prepared.source_binding &&
            request.split_binding == prepared.split_binding ||
            throw(ArgumentError("fold request does not belong to this source/split"))
    end
    return first(prepared.folds)
end

function _prediction_kfold_model(request)
    spec, prior = request.source_spec, request.prior
    # Canonical fields, not abbreviated show(::FacetSpec), bind model/prior contents.
    return (; family=spec.family, dimensions=spec.dimensions,
        dimension_labels=copy(spec.dimension_labels), q_matrix=deepcopy(spec.q_matrix),
        item_levels=copy(spec.data.item_levels), thresholds=spec.thresholds,
        category_contract=_model_family_category_contract(spec),
        prior=(; type=string(typeof(prior)), values=NamedTuple{fieldnames(typeof(prior))}(
            Tuple(getfield(prior, name) for name in fieldnames(typeof(prior))))),
        covariance=request.model isa FacetSpec ? :independent : :correlated,
        lkj_eta=request.model isa FacetSpec ? nothing : request.model.lkj_eta,
        source_target=_prediction_refit_target(_prediction_training_model(request.model, spec), prior))
end

function _prediction_checked_fold(score, request)
    _prediction_check_seal(score, "bayesianmgmfrm.prediction_fold_observations.v2")
    payload = _prediction_fold_payload(request)
    for key in (:dataset_id, :split_binding, :fold, :source_identity, :source_binding, :training_target)
        isequal(getproperty(score, key), getproperty(payload, key)) ||
            throw(ArgumentError("fold score has a different $key"))
    end
    score.binding == request.binding &&
        score.observation_ids == request.observation_ids[request.heldout_observations] &&
        score.training_observation_ids == request.observation_ids[request.training_observations] &&
        score.source_row_indices == request.heldout_observations &&
        isequal(score.observations, PredictionObservationAdapter._observations(request.source_spec.data)[request.heldout_observations]) &&
        score.category_levels == request.source_spec.data.category_levels ||
        throw(ArgumentError("fold score outcomes/order do not match the request"))
    score.prediction_target === :heldout_rows_existing_levels &&
        score.conditioning === :joint_training_posterior_existing_levels &&
        score.weighting === :equal_observation || throw(ArgumentError("unsupported heldout target"))
    S = score.n_retained_draws
    matrix = score.pointwise_loglikelihood
    S >= 1 && size(matrix) == (S, length(score.observation_ids)) &&
        score.draw_indices == collect(1:S) &&
        length(score.chain_ids) == length(score.iterations) == S ||
        throw(ArgumentError("fold scoring requires all original retained draws"))
    labels = sort(unique(score.chain_ids))
    labels == collect(1:length(labels)) && S % length(labels) == 0 ||
        throw(ArgumentError("invalid fold chain layout"))
    n = div(S, length(labels))
    score.chain_ids == repeat(labels; inner=n) && score.iterations == repeat(1:n; outer=length(labels)) ||
        throw(ArgumentError("fold chains must be complete and in original order"))
    all(x -> isfinite(x) && x <= 0, matrix) ||
        throw(ArgumentError("heldout category log probabilities must be finite and nonpositive"))
    return matrix
end

_prediction_sampling_warning(quality) = get(quality, :flag, :unknown) !== :ok ||
    (get(quality, :location_summary, nothing) !== nothing && quality.location_summary.flag !== :ok)

"""
    BayesianMGMFRM.prediction_kfold(prepared, scores; failures=Pair[],
        mcse=:none, independent_fold_rng=false)

Aggregate `prediction_fold_observations` results against the original complete
`prediction_refit_plan`. Results may arrive in any fold order. Explicit failures
are fold ID => nonempty reason pairs; absent results remain `:missing`. Duplicate,
foreign or edited records are rejected. All retained draws/chains are used.

Each rating's score is log(mean(exp(loglikelihood))) over its training posterior.
Scores are additive over ratings, even for grouped splits; this is not a joint
group predictive density. Any missing/failed fold leaves the full ELPD missing.
Diagnostic warnings retain all scores and mark the result as a warning. No folds
are discarded. Data-sampling SE and repeated-data uncertainty are not computed.
This descriptive result neither qualifies convergence nor selects a model.

Set `mcse=:delta` to add `folds[i].mcmc_error` and total `mcmc_error` for the
finite-MCMC error conditional on these data and this split. For each fold,
linearize sum(log(mean(exp(loglikelihood)))) using joint draws across all
heldout ratings, then reuse the autocorrelation-aware mean MCSE. Require at
least two chains and ten draws per chain; these are computational minima,
not sufficient-precision criteria. Degenerate first-order influence is missing,
not zero error. Warnings, draw concentration and curvature-review requirements
remain explicit; the estimate does not account for finite-MCMC bias.

Total MCSE requires the caller's `independent_fold_rng=true` declaration that
fold fits used independent random streams. It is unrelated to independence of
the overlapping training datasets. Detectable reused sample hashes are rejected;
the declaration is not verified from seeds or hashes. Without it, fold MCSEs
remain available but total MCSE is missing. Default `mcse=:none` preserves the
previous result structure. No posterior interval, precision gate or ranking is
created.
"""
function prediction_kfold(prepared, scores; failures=Pair[],
        mcse::Symbol=:none, independent_fold_rng::Bool=false)
    mcse in (:none,:delta) || throw(ArgumentError("mcse must be :none or :delta"))
    independent_fold_rng && mcse === :none && throw(ArgumentError(
        "independent_fold_rng requires mcse=:delta"))
    reference = _prediction_checked_plan(prepared)
    requests = prepared.folds
    expected = [r.fold for r in requests]
    byfold, reasons = Dict{Any,Any}(), Dict{Any,String}()
    for score in scores
        score.fold in expected && !haskey(byfold, score.fold) ||
            throw(ArgumentError("unknown or duplicate scored fold"))
        byfold[score.fold] = score
    end
    for pair in failures
        pair isa Pair || throw(ArgumentError("failures must contain fold => reason pairs"))
        id, reason = first(pair), last(pair)
        id in expected && !haskey(reasons, id) && !haskey(byfold, id) ||
            throw(ArgumentError("unknown, duplicate or also-scored failed fold"))
        reason isa AbstractString && !isempty(strip(reason)) ||
            throw(ArgumentError("failure reasons must be nonempty strings"))
        reasons[id] = String(reason)
    end
    pointwise = Vector{Union{Missing,Float64}}(missing, length(reference.observation_ids))
    rows = map(requests) do request
        ids = reference.observation_ids[request.heldout_observations]
        if !haskey(byfold, request.fold)
            row = (; fold=request.fold, status=haskey(reasons, request.fold) ? :failed : :missing,
                observation_ids=copy(ids), elpd=missing, n_retained_draws=missing,
                sampling_quality=nothing, sampling_warning=missing,
                failure_reason=get(reasons, request.fold, nothing), score_content_hash=nothing,
                source_sample_hash=nothing, source_hash_status=:not_available,
                training_target=_prediction_refit_target(request.model, request.prior))
            return mcse === :none ? row : merge(row,(; mcmc_error=(;
                value=missing, per_rating=missing, status=:not_scored, method=:mcmc_delta_influence)))
        end
        score = byfold[request.fold]
        matrix = _prediction_checked_fold(score, request)
        elpd = [_logmeanexp(view(matrix, :, i)) for i in axes(matrix, 2)]
        all(isfinite, elpd) || throw(ArgumentError("nonfinite heldout score"))
        pointwise[request.heldout_observations] = elpd
        warning = _prediction_sampling_warning(score.sampling_quality)
        row = (; fold=request.fold, status=warning ? :diagnostic_warning : :computed,
            observation_ids=copy(ids), elpd=sum(elpd), score.n_retained_draws,
            sampling_quality=deepcopy(score.sampling_quality), sampling_warning=warning,
            failure_reason=nothing, score_content_hash=score.content_hash,
            score.source_sample_hash, score.source_hash_status, score.training_target)
        return mcse === :none ? row : merge(row,(;mcmc_error=
            _prediction_log_score_mcse(matrix,elpd,length(unique(score.chain_ids)))))
    end
    complete = all(!ismissing, pointwise)
    warning = any(r -> r.sampling_warning === true, rows)
    result = (; schema="bayesianmgmfrm.prediction_kfold.v1", prepared.dataset_id,
        prepared.source_binding, prepared.split_binding, prepared.group_by,
        plan_content_hash=prepared.content_hash, observation_ids=copy(reference.observation_ids),
        observations=deepcopy(PredictionObservationAdapter._observations(reference.source_spec.data)),
        category_levels=copy(reference.source_spec.data.category_levels),
        model_contract=_prediction_kfold_model(reference),
        prediction_target=:heldout_rows_existing_levels, conditioning=:joint_training_posterior_existing_levels,
        weighting=:equal_observation, score_unit=:rating, n_expected_folds=length(requests),
        n_scored_folds=length(byfold), complete, sampling_warning=warning,
        diagnostics_ok=complete && !warning, status=!complete ? :incomplete : warning ? :warning : :descriptive,
        elpd=complete ? sum(pointwise) : missing, kfoldic=complete ? -2sum(pointwise) : missing,
        pointwise_elpd=pointwise, folds=rows, se_elpd=missing,
        uncertainty=(; standard_error=:not_computed, mcmc_mcse=:not_computed, replication_uncertainty=:not_computed),
        scientific_acceptance=:not_established)
    if mcse === :delta
        error = _prediction_kfold_mcse(rows,complete,independent_fold_rng,length(pointwise))
        mcse_warning = ismissing(error.value)
        result = merge(result,(;mcmc_error=error, mcse_warning,
            status=!complete ? :incomplete : warning || mcse_warning ? :warning : :descriptive,
            uncertainty=merge(result.uncertainty,(;mcmc_mcse=:first_order_delta))))
    end
    return _prediction_seal(result)
end

"""
    BayesianMGMFRM.compare_kfold_predictions(models::Pair...; comparison_axis, baseline=nothing,
        independent_model_rng=false)

Compare named `prediction_kfold` results on the identical source and K-fold split.
Declare `:model` (same D/Q), `:dimensions` (D/Q may differ), or `:q_matrix` (same D).
Input order is retained; differences are model minus baseline (first by default).
IDs align the individual rating scores. If any model is incomplete, all contrasts
remain missing. Diagnostic warnings remain visible and never remove a fold/model.
No automatic ranking, winner, weights or data-sampling SE is produced.
Fold dependence is not approximated by treating folds as independent replications.

When any input requests `prediction_kfold(...; mcse=:delta)`, rows retain its
`mcmc_error` and add `difference_mcmc_error`. Difference MCSE requires available
total MCSE for both models and `independent_model_rng=true`, declaring independent
MCMC random streams between model fits. Known sample reuse is rejected; the
caller remains responsible for the independence assumption. Within-model fold
independence must also have been declared during aggregation. No MCMC row pairing
or independence of rating outcomes is inferred. The baseline minus itself has
exactly zero computational error when the comparison is complete; other missing
MCSEs remain missing. All-data/fold sampling uncertainty and finite-MCMC bias
remain separate and unestimated.
"""
function compare_kfold_predictions(models::Pair...; comparison_axis::Symbol, baseline=nothing,
        independent_model_rng::Bool=false)
    length(models) >= 2 || throw(ArgumentError("provide at least two named models"))
    labels = string.(first.(models))
    all(x -> !isempty(strip(x)), labels) && length(unique(labels)) == length(labels) ||
        throw(ArgumentError("model labels must be nonempty and unique"))
    comparison_axis in (:model, :dimensions, :q_matrix) ||
        throw(ArgumentError("declare comparison_axis=:model, :dimensions, or :q_matrix"))
    base_label = baseline === nothing ? first(labels) : string(baseline)
    base = findfirst(==(base_label), labels)
    base === nothing && throw(ArgumentError("baseline must name a supplied model"))
    results = last.(models)
    for result in results
        _prediction_check_seal(result, "bayesianmgmfrm.prediction_kfold.v1")
    end
    reference = results[base]
    orders = map(results) do result
        for key in (:dataset_id, :source_binding, :split_binding, :group_by, :category_levels,
                :prediction_target, :conditioning, :weighting, :score_unit, :n_expected_folds)
            isequal(getproperty(result, key), getproperty(reference, key)) ||
                throw(ArgumentError("K-fold comparison requires the same $key"))
        end
        Set(result.observation_ids) == Set(reference.observation_ids) ||
            throw(ArgumentError("K-fold comparison requires identical rating IDs"))
        index = Dict(id => i for (i, id) in enumerate(result.observation_ids))
        order = [index[id] for id in reference.observation_ids]
        isequal(result.observations[order], reference.observations) ||
            throw(ArgumentError("K-fold comparison requires identical rating outcomes"))
        model, refmodel = result.model_contract, reference.model_contract
        comparison_axis === :dimensions || model.dimensions == refmodel.dimensions ||
            throw(ArgumentError("different dimensions require comparison_axis=:dimensions"))
        if comparison_axis === :model
            item_order = [findfirst(==(item), model.item_levels) for item in refmodel.item_levels]
            q = model.q_matrix === nothing ? nothing : model.q_matrix[item_order, :]
            isequal(q, refmodel.q_matrix) || throw(ArgumentError("different Q requires :dimensions or :q_matrix"))
        end
        order
    end
    with_mcse = any(r -> hasproperty(r,:mcmc_error), results)
    independent_model_rng && !with_mcse && throw(ArgumentError(
        "independent_model_rng requires an input with requested MCSE"))
    independent_model_rng && _prediction_check_independent_samples(
        [result.folds for result in results])
    complete = all(r -> r.complete, results)
    warning = any(r -> r.sampling_warning, results)
    aligned = [r.pointwise_elpd[order] for (r, order) in zip(results, orders)]
    rows = map(eachindex(results)) do i
        result = results[i]
        delta = complete ? aligned[i] .- aligned[base] : fill(missing, length(reference.observation_ids))
        row = (; model=labels[i], baseline=base_label, result.elpd, result.complete, result.status,
            result.sampling_warning, result.diagnostics_ok, result.n_scored_folds,
            elpd_difference=complete ? sum(delta) : missing, pointwise_difference=delta,
            pointwise_elpd=copy(aligned[i]), model_contract=deepcopy(result.model_contract),
            folds=deepcopy(result.folds), source_content_hash=result.content_hash,
            se_elpd_difference=missing)
        return !with_mcse ? row : merge(row,(;mcmc_error=get(result,:mcmc_error,nothing),
            difference_mcmc_error=_prediction_comparison_mcse(result,reference,
                complete,i==base,independent_model_rng,length(reference.observation_ids))))
    end
    comparison = (; schema="bayesianmgmfrm.kfold_prediction_comparison.v1", criterion=:kfold,
        comparison_axis, baseline=base_label, reference.dataset_id, reference.source_binding,
        reference.split_binding, reference.group_by, observation_ids=copy(reference.observation_ids),
        category_levels=copy(reference.category_levels), reference.prediction_target,
        reference.conditioning, reference.weighting, reference.score_unit, rows, complete,
        status=!complete ? :incomplete : warning ? :warning : :descriptive,
        diagnostics_ok=complete && !warning, uncertainty=with_mcse ?
            merge(reference.uncertainty,(;mcmc_mcse=:first_order_delta)) : reference.uncertainty,
        model_selection=:not_performed, scientific_acceptance=:not_established)
    if with_mcse
        mcse_warning = any(r -> ismissing(r.difference_mcmc_error.value), rows)
        comparison = merge(comparison,(;mcse_warning,
            status=!complete ? :incomplete : warning || mcse_warning ? :warning : :descriptive))
    end
    return comparison
end
