# Qualified common K-fold preparation and saved-fit scoring. No sampler is invoked.
_prediction_base_spec(model::_SlopeRestrictedSpec) = model.base_spec
_prediction_training_model(model::_SlopeRestrictedSpec, spec) = _SlopeRestrictedSpec(spec; item_slopes=model.item_slopes, rater_consistency=:fixed_one)
_prediction_base_spec(model::FacetSpec) = model
_prediction_base_spec(model::Union{CorrelatedMFRMSpec,_CorrelatedMGMFRMSpec}) = model.base_spec
_prediction_training_model(model::FacetSpec, spec) = spec
_prediction_training_model(model::CorrelatedMFRMSpec, spec) = CorrelatedMFRMSpec(spec; lkj_eta=model.lkj_eta)
_prediction_training_model(model::_CorrelatedMGMFRMSpec, spec) = _CorrelatedMGMFRMSpec(spec; lkj_eta=model.lkj_eta)

_prediction_legacy_target(design, prior) = _cache_hash((;
    design=design_identity(design).value, prior=_prior_cache_record(prior)))

function _prediction_refit_target(model::FacetSpec, prior::MFRMPrior)
    model.family === :mfrm || throw(ArgumentError("MFRMPrior requires an MFRM model"))
    if model.dimensions == 1
        target = MFRMLogDensity(getdesign(model); prior)
        return (; kind=:mfrm, identity=_prediction_legacy_target(target.design, prior))
    end
    target = _MFRMFixedQReferenceLogDensity(model; prior)
    return (; kind=:fixed_mfrm, identity=_mfrm_fixed_q_identity(target))
end
function _prediction_refit_target(model::FacetSpec, prior::GeneralizedPrior)
    raw_prior = _source_fixture_prior(prior)
    target = model.family === :gmfrm ? _gmfrm_promotion_candidate_logdensity(model; prior=raw_prior) :
        model.family === :mgmfrm ? _mgmfrm_guarded_local_fit_logdensity(model; prior=raw_prior) :
        throw(ArgumentError("GeneralizedPrior requires GMFRM or MGMFRM"))
    return (; kind=model.family, identity=_prediction_legacy_target(target.design, raw_prior))
end
function _prediction_refit_target(model::Union{FacetSpec,_SlopeRestrictedSpec}, prior::_SlopePrior)
    target = _normalized_mgmfrm_target(model, prior)
    return (; kind=:normalized_mgmfrm, identity=_mgmfrm_normalized_prior_identity(target))
end
function _prediction_refit_target(model::_CorrelatedMGMFRMSpec, prior::GeneralizedPrior)
    target = _mgmfrm_free_latent_correlation_2d_logdensity(model.base_spec;
        prior=_source_fixture_prior(prior), lkj_eta=model.lkj_eta)
    return (; kind=:correlated_mgmfrm, identity=_mgmfrm_correlated_2d_identity(target))
end
function _prediction_refit_target(model::CorrelatedMFRMSpec, prior::MFRMPrior)
    target = _MFRMFixedQCorrelated2DLogDensity(model.base_spec; prior, lkj_eta=model.lkj_eta)
    return (; kind=:correlated_mfrm, identity=_mfrm_correlated_2d_identity(target))
end
function _prediction_refit_target(model::Union{FacetSpec,CorrelatedMFRMSpec}, prior::_ExchangeablePrior)
    target = _fixed_q_prior_target(model, prior)
    return (; kind=:exchangeable_mfrm, identity=_mfrm_exchangeable_rater_identity(target))
end
_prediction_refit_target(model, prior) = throw(ArgumentError("unsupported refit model/prior combination"))

function _prediction_fitted_target(fit::_ModelComparisonFit)
    kind = fit isa MFRMFit ? :mfrm : fit isa GMFRMFit ? :gmfrm : :mgmfrm
    return (; kind, identity=_prediction_legacy_target(fit.design, fit.prior))
end
function _prediction_fitted_target(fit::Union{_RecordedMGMFRMFit,_FixedQMFRMFit})
    kind = fit isa _NormalizedMGMFRMFit ? :normalized_mgmfrm :
        fit isa _CorrelatedMGMFRMFit ? :correlated_mgmfrm :
        fit isa _ExchangeableMFRMFit ? :exchangeable_mfrm :
        fit isa _CorrelatedMFRMFit ? :correlated_mfrm : :fixed_mfrm
    return (; kind, identity=fit.record.target_identity)
end

function _prediction_source_binding(data, ids, dataset_id)
    order = sortperm(ids)
    observations = PredictionObservationAdapter._observations(data)
    return _cache_hash((; dataset_id, category_levels=data.category_levels,
        observations=collect(zip(ids[order], observations[order]))))
end

function _prediction_fold_payload(request)
    spec = request.source_spec
    source_identity = design_identity(spec; preview=true).value
    ids = PredictionObservationAdapter._ids(request.observation_ids, spec.data.n, "observation_ids")
    isempty(strip(request.dataset_id)) && throw(ArgumentError("dataset_id must be nonempty"))
    training_target = _prediction_refit_target(request.model, request.prior)
    source_binding = _prediction_source_binding(spec.data, ids, request.dataset_id)
    return (; request.schema, request.dataset_id, source_identity, source_binding, observation_ids=ids,
        request.split_binding, request.fold, request.training_observations,
        request.heldout_observations, training_target)
end

"""
    prediction_refit_plan(model, plan; prior, dataset_id, observation_ids)

Prepare all K-fold training requests without sampling. `model` is a `FacetSpec`,
supported `Experimental.correlated(spec)` model or `Experimental.slope_restriction`
model; `prior` is explicit. The slope restriction retains its fixed/estimated
coefficient policies and requires its admitted normalized prior.
The existing K-fold partition and known-level checks run before any request is
returned. Model, Q, dimension names, prior and supported covariance are retained.
Persistent unique rating IDs are supplied in the source specification's row order.

Each `folds` entry exposes `model` and `prior` for `fit` (scalar MFRM) or
`Experimental.fit` (other supported models), and is bound to the full source,
split, training target and heldout order. Use `prediction_fold_observations`
to score its independently fitted training result. No full-data fit, posterior
initialization, backend choice or sampler control is inferred. Specify priors
before examining heldout outcomes; this API cannot detect prior/model tuning.

Only existing person/rater/item/category levels are supported. Optional grouping
metadata do not become fitted effects. This is not an automatic refit executor,
LOO repair, or a new-level marginal prediction API. Use `prediction_kfold` and
`compare_kfold_predictions` to aggregate and compare the saved heldout results.
"""
function prediction_refit_plan(model, plan; prior, dataset_id::AbstractString, observation_ids)
    source_spec = deepcopy(_prediction_base_spec(model))
    ids = PredictionObservationAdapter._ids(observation_ids, source_spec.data.n, "observation_ids")
    isempty(strip(dataset_id)) && throw(ArgumentError("dataset_id must be nonempty"))
    _prediction_refit_target(model, prior)
    audit = _check_kfold_refit_plan_for_execution(source_spec.data, plan)
    source_binding = _prediction_source_binding(source_spec.data, ids, String(dataset_id))
    split_binding = _cache_hash((; source_binding, group_by=plan.group_by,
        folds=sort([(; row.fold, training_ids=sort(ids[row.training_observations]),
            heldout_ids=sort(ids[row.heldout_observations])) for row in plan.fold_rows];
            by=row -> _cache_stable_string(row.fold))))
    folds = map(plan.fold_rows) do row
        training = _loo_refit_training_data(source_spec.data, row.training_observations)
        spec = _refit_training_spec(source_spec, training)
        request = (; schema="bayesianmgmfrm.prediction_refit_fold.v1", dataset_id=String(dataset_id),
            source_spec, observation_ids=copy(ids), split_binding, fold=deepcopy(row.fold),
            training_observations=copy(row.training_observations),
            heldout_observations=copy(row.heldout_observations),
            model=_prediction_training_model(model, spec), prior=deepcopy(prior))
        merge(request, (; binding=_cache_hash(_prediction_fold_payload(request))))
    end
    prepared = (; schema="bayesianmgmfrm.prediction_refit_plan.v2", dataset_id=String(dataset_id),
        source_binding, split_binding, group_by=plan.group_by, folds, plan_diagnostics=audit,
        prediction_target=:heldout_rows_existing_levels, scientific_acceptance=:not_established)
    return merge(prepared, (; content_hash=_cache_hash(_prediction_plan_payload(prepared))))
end

"""
    prediction_fold_observations(training_fit, request; include_probabilities=true)

Score one prepared K-fold request using all original retained training-fit draws
and chains. Reject changed requests and fits for different training observations,
model, prior or covariance. Saved records undergo their native integrity checks.
Heldout native labels are mapped to the actual training parameter order; the
existing likelihood kernel is shared with `prediction_observations`.

Returns heldout draws × rows log likelihood, optional category probabilities,
persistent IDs, source/split/target bindings and unfiltered sampling diagnostics.
Correlated draws already contain the joint ability transform; it is not applied
again. Heldout results have a distinct schema and cannot be passed to training-row
WAIC/LOO. No convergence qualification, fit execution receipt, or predictive
comparison is inferred from a matching target. Legacy fixed-MFRM v1 records are
not migrated into canonical refit targets.
"""
function prediction_fold_observations(training_fit::PredictionObservationAdapter.SupportedFit,
        request; include_probabilities::Bool=true)
    request.schema == "bayesianmgmfrm.prediction_refit_fold.v1" ||
        throw(ArgumentError("unsupported prediction refit request"))
    payload = _prediction_fold_payload(request)
    _cache_hash(payload) == request.binding || throw(ArgumentError("prediction refit request has changed"))
    # Validate saved draws before relying on their target identity.
    context = PredictionObservationAdapter._context(training_fit, nothing, nothing, Random.default_rng())
    _prediction_fitted_target(training_fit) == payload.training_target ||
        throw(ArgumentError("fit does not match the requested training data/model/prior target"))
    score_design = _loo_refit_score_design(request.source_spec.data, context.design,
        request.heldout_observations)
    probabilities, pointwise = PredictionObservationAdapter._prediction_arrays(
        score_design, context.direct, include_probabilities)
    result = (; schema="bayesianmgmfrm.prediction_fold_observations.v2",
        request.dataset_id, request.split_binding, request.binding, request.fold,
        source_identity=payload.source_identity, source_binding=payload.source_binding,
        training_target=payload.training_target,
        observation_ids=copy(request.observation_ids[request.heldout_observations]),
        training_observation_ids=copy(request.observation_ids[request.training_observations]),
        observations=deepcopy(PredictionObservationAdapter._observations(score_design.spec.data)),
        source_row_indices=copy(request.heldout_observations),
        category_levels=copy(score_design.spec.data.category_levels),
        prediction_target=:heldout_rows_existing_levels, conditioning=:joint_training_posterior_existing_levels,
        weighting=:equal_observation, probabilities, pointwise_loglikelihood=pointwise,
        draw_indices=context.indices, n_retained_draws=context.total_draws,
        chain_ids=copy(context.chain_ids), iterations=copy(context.iterations),
        sampling_quality=deepcopy(context.quality), native_metadata=deepcopy(context.metadata),
        target_contract=deepcopy(context.target_contract),
        context.source_sample_hash, context.source_hash_status,
        scientific_acceptance=:not_established)
    return _prediction_seal(result)
end

_prediction_seal(record::NamedTuple) = merge(record, (; content_hash=_cache_hash(record)))
function _prediction_check_seal(record, schema)
    get(record, :schema, nothing) == schema && hasproperty(record, :content_hash) ||
        throw(ArgumentError("unsupported prediction record; reprepare/rescore using the current API"))
    _cache_hash(Base.structdiff(record, (; content_hash=nothing))) == record.content_hash ||
        throw(ArgumentError("prediction record contents have changed"))
    return nothing
end
function _prediction_plan_payload(prepared)
    return (; prepared.schema, prepared.dataset_id, prepared.source_binding,
        prepared.split_binding, prepared.group_by, fold_bindings=[r.binding for r in prepared.folds],
        prepared.plan_diagnostics, prepared.prediction_target, prepared.scientific_acceptance)
end
