"""Opt-in extraction for existing fitted rows; no sampling or model ranking.

Load with include, then use .PredictionObservationAdapter. Kept outside package
includes while the prediction pilot's package sources are frozen.
"""
module PredictionObservationAdapter
using BayesianMGMFRM, Random
const B = BayesianMGMFRM
export prediction_observations, observation_alignment

const SupportedFit = Union{B.MFRMFit,B.GMFRMFit,B.MGMFRMFit,B._RecordedMGMFRMFit}

function _context(fit::B._ModelComparisonFit, ndraws, draw_indices, rng)
    design = fit.design
    B._require_canonical_design(design, "prediction_observations")
    indices = B._posterior_draw_indices(fit, ndraws, draw_indices, rng)
    direct = fit isa B.MFRMFit ? fit.draws[indices, :] : fit.direct_draws[indices, :]
    if fit isa B.MFRMFit
        B._check_fit_supported_mfrm(design, "prediction_observations")
        foreach(row -> B._check_parameter_vector(design, row), eachrow(direct))
        quality = B.diagnostics(fit).summary
    elseif fit isa B.GMFRMFit
        B._gmfrm_direct_draws_for_prediction(design, direct, "prediction_observations")
        quality = fit.diagnostic_surface.summary
    else
        B._mgmfrm_direct_draws_for_prediction(design, direct, "prediction_observations")
        quality = fit.diagnostic_surface.summary
    end
    metadata = B.fit_metadata(fit)
    return (; design, direct, indices, chain_ids=fit.chain_ids[indices],
        iterations=fit.iterations[indices], metadata, quality,
        source_sample_hash=nothing, source_hash_status=:not_available_for_legacy_fit,
        latent_correlation=fit isa B.MGMFRMFit ? :identity_fixed : :not_applicable,
        target_contract=B.fit_ready_parameter_layout(design))
end

function _context(fit::B._RecordedMGMFRMFit, ndraws, draw_indices, rng)
    bundle = B._mgmfrm_correlated_2d_prediction_bundle(fit, ndraws, draw_indices, rng)
    checked, target, indices = bundle.checked, bundle.target, bundle.indices
    run = checked.record.run
    metadata = B._mgmfrm_correlated_2d_prediction_metadata(target)
    contract = fit isa B._NormalizedMGMFRMFit ? checked.prior_metadata : checked.target_contract
    return (; design=target.base.design, bundle.direct, indices,
        chain_ids=run.chain_ids[indices], iterations=run.iterations[indices],
        metadata=merge(metadata, (; backend=run.backend, sampler_controls=run.controls)),
        quality=(; flag=checked.diagnostics.flag, settings=run.checked),
        source_sample_hash=checked.record.content_hash, source_hash_status=:validated,
        metadata.latent_correlation, target_contract=contract)
end

function _ids(values, n, label)
    values isa AbstractVector && length(values) == n ||
        throw(ArgumentError("$label must be a vector with one ID per fitted observation"))
    all(x -> x isa AbstractString && !isempty(strip(x)), values) ||
        throw(ArgumentError("$label must contain nonempty strings"))
    ids = String.(values)
    length(unique(ids)) == n || throw(ArgumentError("$label must be unique"))
    return ids
end

function _observations(data)
    roles = sort!(collect(keys(data.optional)); by=string)
    return [(; person=data.person_levels[data.person[n]],
        rater=data.rater_levels[data.rater[n]], item=data.item_levels[data.item[n]],
        score=data.score[n], optional=Tuple(role => data.optional_levels[role][data.optional[role][n]]
                                           for role in roles)) for n in 1:data.n]
end

"""
    prediction_observations(fit; dataset_id, observation_ids,
        ndraws=nothing, draw_indices=nothing, rng=Random.default_rng(),
        include_probabilities=true)

Extract conditional predictions for ALL original fitted rows of the five
supported fit types. Supply persistent observation IDs in that fit's row order;
row numbers and response-group IDs are not automatically promoted to outcome IDs.
`dataset_id` names the shared source dataset. IDs and native labels/scores are
bound together, including optional metadata, in a row-order-independent hash.

Returns draws × observations pointwise log likelihood, optional draws ×
observations × categories probabilities, selected chain/iteration IDs, model
scale/constraints/prior metadata and diagnostics. Selection preserves duplicates.
Probabilities and likelihood share one stable logit evaluation. Setting
`include_probabilities=false` avoids allocating the category array. No prior or
Jacobian enters the likelihood. Diagnostic warnings are retained, not filtered.

This does not accept new rows, folds, weights, new facet levels, or a replacement
prediction target. The result is training-row, existing-level conditional
prediction. It is not a fitted-CV result or a scientific acceptance decision.
"""
function prediction_observations(fit::SupportedFit; dataset_id::AbstractString,
        observation_ids, ndraws::Union{Nothing,Int}=nothing, draw_indices=nothing,
        rng::AbstractRNG=Random.default_rng(), include_probabilities::Bool=true)
    isempty(strip(dataset_id)) && throw(ArgumentError("dataset_id must be nonempty"))
    # Check identity arguments before restoring potentially large saved draws.
    data = fit isa B._ModelComparisonFit ? fit.design.spec.data : fit.record.spec.data
    ids = _ids(observation_ids, data.n, "observation_ids")
    context = _context(fit, ndraws, draw_indices, rng)
    design, direct = context.design, context.direct
    data = design.spec.data
    S, N, K = size(direct, 1), data.n, length(data.category_levels)
    S > 0 || throw(ArgumentError("at least one retained draw is required"))
    probabilities = include_probabilities ? Array{Float64}(undef, S, N, K) : nothing
    pointwise = Matrix{Float64}(undef, S, N)
    eta = Vector{Float64}(undef, K)
    family = design.spec.family
    loadings = family === :mgmfrm ? B._mgmfrm_source_loading_index_matrix(design) : nothing
    for s in 1:S, n in 1:N
        params = view(direct, s, :)
        if family === :mfrm
            B._linear_predictors!(eta, design, params, n)
        elseif family === :gmfrm
            B._gmfrm_source_linear_predictors!(eta, design, params, n)
        else
            B._mgmfrm_source_linear_predictors!(eta, design, params, n, loadings)
        end
        all(isfinite, eta) || throw(ArgumentError("nonfinite category logits at draw $s, row $n"))
        eta .-= maximum(eta)
        z = B._logsumexp(eta)
        pointwise[s, n] = eta[data.category[n]]-z
        if include_probabilities
            for k in 1:K
                probabilities[s, n, k] = exp(eta[k]-z)
            end
        end
    end
    all(isfinite, pointwise) || throw(ArgumentError("nonfinite pointwise log likelihood"))
    observations = deepcopy(_observations(data))
    category_contract = B.model_family_contract(design.spec).category
    order = sortperm(ids)
    binding = B._cache_hash((; dataset_id=String(dataset_id),
        category_levels=data.category_levels, observations=collect(zip(ids[order], observations[order]))))
    return (; schema="bayesianmgmfrm.prediction_observations.prototype.v1",
        dataset_id=String(dataset_id), observation_ids=ids, observations,
        source_row_indices=collect(1:N), category_levels=copy(data.category_levels),
        observation_binding=binding, training_binding=binding,
        prediction_target=:training_rows_existing_levels,
        conditioning=:joint_posterior_existing_levels, weighting=:equal_observation,
        probabilities, pointwise_loglikelihood=pointwise,
        draw_indices=context.indices, chain_ids=copy(context.chain_ids),
        iterations=copy(context.iterations), sampling_quality=deepcopy(context.quality),
        model=(; family, dimensions=design.spec.dimensions,
            dimension_labels=copy(design.spec.dimension_labels),
            q_matrix=deepcopy(design.spec.q_matrix), thresholds=design.spec.thresholds,
            likelihood_scale=category_contract.implementation_scale_constant, category_contract,
            context.latent_correlation, target_contract=deepcopy(context.target_contract),
            native_metadata=deepcopy(context.metadata)),
        context.source_sample_hash, context.source_hash_status,
        scientific_acceptance=:not_established)
end

"""
    observation_alignment(reference, candidate)

Return candidate column indices in reference outcome order after checking source
dataset, outcomes, categories and conditional training target. Different latent
models may align; this is not permission to compare their parameter values, an
automatic comparison-axis choice, or a WAIC/LOO ranking function. Arrays are not
copied. Draws from different fits need not have the same counts or RNG streams.
"""
function observation_alignment(reference, candidate)
    for bundle in (reference, candidate)
        bundle.schema == "bayesianmgmfrm.prediction_observations.prototype.v1" ||
            throw(ArgumentError("unsupported prediction observation schema"))
        ids = _ids(bundle.observation_ids, length(bundle.observations), "observation_ids")
        size(bundle.pointwise_loglikelihood, 2) == length(ids) ||
            throw(ArgumentError("likelihood columns do not match observation IDs"))
    end
    for field in (:dataset_id, :category_levels, :prediction_target, :conditioning,
                  :weighting, :training_binding, :observation_binding)
        isequal(getproperty(reference, field), getproperty(candidate, field)) ||
            throw(ArgumentError("incompatible $field"))
    end
    lookup = Dict(id => i for (i, id) in enumerate(candidate.observation_ids))
    Set(reference.observation_ids) == Set(candidate.observation_ids) ||
        throw(ArgumentError("observation IDs differ"))
    order = [lookup[id] for id in reference.observation_ids]
    isequal(reference.observations, candidate.observations[order]) ||
        throw(ArgumentError("aligned native labels, metadata or scores differ"))
    return order
end
end
