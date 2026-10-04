# Public experimental adapters over the existing normalized target and v1/v2 records.
function _normalized_mgmfrm_target(spec, prior::_NormalizedMGMFRMPrior)
    spec isa FacetSpec && spec.family === :mgmfrm || throw(ArgumentError(
        "NormalizedMGMFRMPrior requires an independent fixed-Q MGMFRM specification"))
    return _MGMFRMNormalizedPriorLogDensity(spec; prior_model=prior.prior_model,
        scales=prior.scales, source_rater=prior.source_rater)
end

function _normalized_mgmfrm_fit(spec, prior::_NormalizedMGMFRMPrior;
        backend::Symbol=:advancedhmc, init=nothing, sampling_coordinates::Symbol=:raw, kwargs...)
    target = _normalized_mgmfrm_target(spec, prior)
    _check_mgmfrm_sampling_coordinates(spec, sampling_coordinates, backend, true)
    backend === :cmdstan && length(spec.data.category_levels) < 3 &&
        throw(ArgumentError("normalized MGMFRM CmdStan fitting requires at least three categories"))
    init === nothing || init isa AbstractVector{<:Real} ||
        throw(ArgumentError("init must be a real raw-coordinate vector or nothing"))
    initial = init === nothing ? initial_params(target) : Float64.(collect(init))
    _check_source_fixture_raw_vector(target, initial)
    result = _mgmfrm_normalized_prior_sample(target, initial; backend, sampling_coordinates, kwargs...)
    return _NormalizedMGMFRMFit(result.record; expected_identity=result.record.target_identity)
end

_normalized_mgmfrm_model(target) = Symbol("mgmfrm_normalized_", target.prior_model)
_normalized_mgmfrm_target(fit::_NormalizedMGMFRMFit) =
    _MGMFRMNormalizedPriorLogDensity(fit.record.spec, fit.record.prior;
        expected_identity=fit.record.target_identity)

function _normalized_mgmfrm_prior_check(target::_MGMFRMNormalizedPriorLogDensity; kwargs...)
    check = _mgmfrm_normalized_prior_predictive_check(target; kwargs...)
    return merge(check, (; model=_normalized_mgmfrm_model(target), public_fit=true,
        prediction_target=:existing_rating_rows,
        prior_metadata=merge(check.prior_metadata, (; public_fit=true))))
end
_normalized_mgmfrm_prior_check(spec, prior::_NormalizedMGMFRMPrior; kwargs...) =
    _normalized_mgmfrm_prior_check(_normalized_mgmfrm_target(spec, prior); kwargs...)

function _recorded_mgmfrm_samples(fit::_NormalizedMGMFRMFit)
    checked = _restore_mgmfrm_normalized_prior_samples(fit.record;
        expected_identity=fit.record.target_identity)
    target = _normalized_mgmfrm_target(fit)
    return merge(checked, (; model=_normalized_mgmfrm_model(target), public_fit=true,
        prior_metadata=merge(checked.prior_metadata, (; public_fit=true)),
        raw_parameter_spaces=fill(:raw_unconstrained, length(checked.raw_parameter_names)),
        direct_parameter_spaces=fill(:direct_constrained, length(checked.direct_parameter_names)),
        structurally_fixed_parameters=_structurally_fixed_constrained_parameter_names(target.base.blueprint)))
end

_recorded_mgmfrm_schemas(::_NormalizedMGMFRMFit) = (;
    cache="bayesianmgmfrm.normalized_mgmfrm_fit_cache.v1",
    artifact="bayesianmgmfrm.normalized_mgmfrm_fit_artifact.v1",
    label=:normalized_mgmfrm_fit_artifact)

function fit_metadata(fit::_NormalizedMGMFRMFit; view::Symbol=:full)
    view in (:full, :public) || throw(ArgumentError("view must be :full or :public"))
    checked = _recorded_mgmfrm_samples(fit)
    record, run = checked.record, checked.record.run
    spec, data = record.spec, record.spec.data
    prior_metadata = checked.prior_metadata
    metadata = (; family=:mgmfrm, model=checked.model,
        model_label="Normalized-prior MGMFRM (estimated loadings and consistency)",
        status=:experimental, estimation_status=:experimental,
        public_fit=true, experimental_public=true, fitting_available=true,
        dimensions=spec.dimensions, dimension_labels=copy(spec.dimension_labels),
        q_matrix=_q_matrix_manifest(spec.q_matrix), item_structure=_model_family_item_structure(spec),
        thresholds=spec.thresholds, likelihood_scale=1.7,
        loading_policy=:estimated_positive_fixed_q, rater_consistency=:positive_product_one,
        location=:prior_anchored, latent_correlation=:identity_fixed,
        parameter_space=:raw_unconstrained_coordinates,
        raw_parameter_names=copy(checked.raw_parameter_names),
        direct_parameter_names=copy(checked.direct_parameter_names),
        prior=record.prior, prior_metadata, prior_label=prior_metadata.prior_label,
        target_identity=record.target_identity, target_contract=prior_metadata,
        n_observations=data.n, n_persons=length(data.person_levels),
        n_items=length(data.item_levels), n_raters=length(data.rater_levels),
        n_categories=length(data.category_levels), category_levels=copy(data.category_levels),
        n_parameters=run.nparams, n_direct_parameters=length(checked.direct_parameter_names),
        n_draws=run.total_draws, n_chains=run.controls.chains,
        draws_per_chain=run.controls.ndraws, warmup=run.controls.warmup,
        backend=run.backend, sampler=run.sampler, sampler_controls=deepcopy(run.controls),
        diagnostic_settings=(; run.checked..., split_chains=run.split_chains_requested),
        data_signature=spec.validation.data_signature, scientific_acceptance=:not_established)
    return view === :full ? metadata : _public_reader_payload(metadata;
        schema="bayesianmgmfrm.fit_metadata_public.v1", family=:mgmfrm, stability=:experimental)
end

function Base.show(io::IO, fit::_NormalizedMGMFRMFit)
    print(io, "NormalizedMGMFRMFit (", fit.record.prior.prior_model, "; ",
        fit.record.run.total_draws, " retained draws; ", fit.record.run.backend, "; experimental)")
end

function _mgmfrm_correlated_2d_prediction_bundle(fit::_NormalizedMGMFRMFit, ndraws, draw_indices, rng)
    checked = _recorded_mgmfrm_samples(fit)
    indices = _posterior_draw_indices(checked.record.run, ndraws, draw_indices, rng)
    target = _normalized_mgmfrm_target(fit)
    direct = checked.diagnostics.direct_values.direct_draws[indices, :]
    return (; checked, target, direct, indices)
end

function _mgmfrm_correlated_2d_prediction_metadata(target::_MGMFRMNormalizedPriorLogDensity)
    metadata = _mgmfrm_normalized_prior_metadata(target)
    return (; model_family=:mgmfrm, model=_normalized_mgmfrm_model(target),
        stability=:experimental, scientific_acceptance=:not_established,
        prediction_target=:existing_rating_rows, new_facet_levels=false,
        metadata.dimension_labels, metadata.q_matrix, metadata.likelihood_scale,
        metadata.latent_correlation, metadata.target_identity, metadata.prior,
        prior_metadata=merge(metadata, (; public_fit=true)), metadata.prior_label)
end

function _mgmfrm_correlated_2d_report_context(fit::_NormalizedMGMFRMFit)
    checked = _recorded_mgmfrm_samples(fit)
    target = _normalized_mgmfrm_target(fit)
    return (; fit, checked, target, direct=checked.diagnostics.direct_values.direct_draws,
        diagnostics=diagnostics(fit))
end

function _normalized_mgmfrm_report_prior_policy(target)
    metadata = _mgmfrm_normalized_prior_metadata(target)
    rows = NamedTuple[]
    for (block, parameter, key) in ((:person, :person_sd, :person), (:item, :item_sd, :item),
            (:item_dimension_discrimination, :log_discrimination_sd, :log_loading),
            (:rater, :rater_sd, :severity), (:rater_consistency, :log_consistency_sd, :log_consistency),
            (:item_steps, :step_sd, :item_steps))
        info = getproperty(metadata.blocks, key)
        centered = hasproperty(info, :kernel_sd)
        push!(rows, (; block, parameter, value=getproperty(metadata.prior.scales, parameter),
            meaning=centered ? "Kernel SD of a normalized zero-sum Gaussian block" : "SD of independent normal coordinates",
            estimated=false, distribution=info.distribution, mean=info.mean,
            marginal_sd=centered ? info.marginal_sd : info.sd,
            contrast_sd=centered ? info.contrast_sd : missing,
            active=centered ? info.scale_active : true))
    end
    return (; status=:computed, rows, n_rows=length(rows), prior=metadata.prior,
        prior_metadata=merge(metadata, (; public_fit=true)),
        interpretation=metadata.prior_label * ". For a centered block of length n, marginal SD is kernel SD times sqrt((n-1)/n), and pairwise contrast SD is sqrt(2) times kernel SD when a contrast exists. Source log-consistency means depend on the distinguished rater and are reported explicitly. Density is declared on last-reconstructed free coordinates; no additional lognormal Jacobian is added. All scales are fixed inputs; statistical acceptance is not established.")
end
