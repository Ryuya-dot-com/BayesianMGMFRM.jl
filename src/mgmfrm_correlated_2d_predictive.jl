# Prior and conditional existing-row prediction for the explicit correlated model.
function _mgmfrm_correlated_2d_prior_draws(target, ndraws::Int, rng::AbstractRNG)
    ndraws >= 1 || throw(ArgumentError("ndraws must be positive"))
    base = target.base
    draws = Matrix{Float64}(undef, ndraws, target.blueprint.n_parameters)
    for row in eachrow(draws)
        for i in 1:base.blueprint.n_parameters
            row[i] = _source_fixture_prior_sd(base, i) * randn(rng)
        end
        # In two dimensions (rho + 1)/2 ~ Beta(eta, eta), on d_rho.
        rho = 2rand(rng, Turing.Beta(target.prior.lkj_eta, target.prior.lkj_eta)) - 1
        -1 < rho < 1 || throw(ArgumentError("LKJ draw reached an unrepresentable correlation boundary"))
        row[end] = atanh(rho)
        for i in first(base.blueprint.blocks[:person]):2:last(base.blueprint.blocks[:person])
            row[i + 1] = rho * row[i] + sqrt((1 - rho) * (1 + rho)) * row[i + 1]
        end
    end
    all(isfinite, draws) || throw(ArgumentError("correlated MGMFRM prior draws are non-finite"))
    return draws
end

function _mgmfrm_correlated_2d_prior_bundle(spec::_CorrelatedMGMFRMSpec;
        prior = nothing, ndraws::Int = 1000, rng::AbstractRNG = Random.default_rng())
    target = _mgmfrm_correlated_2d_target(spec, prior)
    raw = _mgmfrm_correlated_2d_prior_draws(target, ndraws, rng)
    direct = reduce(vcat, (permutedims(_guarded_generalized_direct_params(target.base,
        view(raw, d, target.blueprint.base_parameter_range))) for d in axes(raw, 1)))
    _mgmfrm_direct_draws_for_prediction(target.base.design, direct, "Experimental.prior_predict")
    return (; target, raw, direct)
end

function _mgmfrm_correlated_2d_prior_predict(spec::_CorrelatedMGMFRMSpec;
        prior = nothing, ndraws::Int = 1000, rng::AbstractRNG = Random.default_rng())
    bundle = _mgmfrm_correlated_2d_prior_bundle(spec; prior, ndraws, rng)
    return _replicate_scores_mgmfrm_direct(bundle.target.base.design, bundle.direct, rng)
end

function _mgmfrm_correlated_2d_prediction_metadata(target)
    spec = target.base.design.spec
    return (; model_family = :mgmfrm, model = :mgmfrm_correlated_2d_raw_prior,
        stability = :experimental, scientific_acceptance = :not_established,
        prediction_target = :existing_rating_rows, new_facet_levels = false,
        dimension_labels = copy(spec.dimension_labels), q_matrix = copy(spec.q_matrix),
        likelihood_scale = 1.7, latent_correlation = :free_2d,
        target_identity = _mgmfrm_correlated_2d_identity(target),
        prior = (; scales = _source_fixture_prior_values(target.prior.source_prior),
            ability = :conditional_bivariate_normal,
            other_free_coordinates = :independent_normal_raw_coordinates,
            correlation = :normalized_lkj_2d, lkj_eta = target.prior.lkj_eta,
            correlation_prior_measure = :d_rho, density_measure = :d_raw_d_zrho,
            correlation_log_jacobian = :log_one_minus_rho_squared))
end

function _mgmfrm_correlated_2d_prior_predictive_check(spec::_CorrelatedMGMFRMSpec;
        prior = nothing, ndraws::Int = 1000, rng::AbstractRNG = Random.default_rng(),
        min_category_probability::Real = 0.01, prior_warning_probability::Real = 0.95,
        wide_facet_range_fraction::Real = 0.8)
    _check_prior_implication_controls(; min_category_probability, prior_warning_probability, wide_facet_range_fraction)
    bundle = _mgmfrm_correlated_2d_prior_bundle(spec; prior, ndraws, rng)
    target = bundle.target
    replicated = _replicate_scores_mgmfrm_direct(target.base.design, bundle.direct, rng)
    # Share the existing score/facet/group summaries, without inventing posterior indices.
    check = Base.structdiff(_posterior_predictive_check(target.base.design.spec, replicated, nothing),
        (; draw_indices = nothing))
    implication_diagnostics = _prior_predictive_implication_diagnostics(target.base.design.spec.data,
        check.observed, check.replicated; min_category_probability,
        prior_warning_probability, wide_facet_range_fraction)
    blueprint = _mgmfrm_correlated_2d_sample_blueprint(target)
    return merge(check, _mgmfrm_correlated_2d_prediction_metadata(target), (;
        schema = "bayesianmgmfrm.correlated_mgmfrm_prior_predictive_check.v1",
        prediction_conditioning = :joint_prior, parameter_space = :raw_unconstrained_and_fisher_z,
        parameter_draws = bundle.raw, raw_parameter_draws = bundle.raw,
        direct_parameter_draws = hcat(bundle.direct, tanh.(bundle.raw[:, end])),
        raw_parameter_names = copy(blueprint.parameter_names),
        direct_parameter_names = copy(blueprint.constrained_parameter_names), implication_diagnostics))
end

function _mgmfrm_correlated_2d_prediction_bundle(fit::_CorrelatedMGMFRMFit, ndraws, draw_indices, rng)
    checked = _mgmfrm_correlated_2d_samples(fit)
    record, run = checked.record, checked.record.run
    indices = _posterior_draw_indices(run, ndraws, draw_indices, rng)
    target = _mgmfrm_free_latent_correlation_2d_logdensity(record.spec;
        prior = _SourceFixturePrior(; record.prior.scales...), lkj_eta = record.prior.lkj_eta)
    # Ability pairs are already joint posterior draws. Do not apply rho again.
    direct = checked.diagnostics.direct_values.direct_draws[indices, 1:end-1]
    return (; checked, target, direct, indices)
end

"""
    predictive_probabilities(fit::Experimental.CorrelatedMGMFRMFit;
        ndraws = nothing, draw_indices = nothing, rng = Random.default_rng())

Category probabilities conditional on each retained joint draw for the existing
rating rows. The array is draws by observations by categories, in the saved
category order. With no selection all draws are used; `ndraws` samples with
replacement, while `draw_indices` preserves the requested order and duplicates.
Abilities already incorporate population correlation; it is not applied again.
New persons, items and raters are outside this prediction target.
"""
function predictive_probabilities(fit::_CorrelatedMGMFRMFit;
        ndraws::Union{Nothing,Int} = nothing, draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    bundle = _mgmfrm_correlated_2d_prediction_bundle(fit, ndraws, draw_indices, rng)
    return _mgmfrm_predictive_probabilities_direct(bundle.target.base.design, bundle.direct)
end

"""
    posterior_predict(fit::Experimental.CorrelatedMGMFRMFit; kwargs...)

Simulate scores for the existing rating rows from joint posterior draws, using
the draw-selection controls of `predictive_probabilities`. Entries use the saved
integer category labels; rows are replicated datasets. Use a local seeded RNG
to reproduce both draw selection and score simulation after reloading a fit.
"""
function posterior_predict(fit::_CorrelatedMGMFRMFit;
        ndraws::Union{Nothing,Int} = nothing, draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    bundle = _mgmfrm_correlated_2d_prediction_bundle(fit, ndraws, draw_indices, rng)
    return _replicate_scores_mgmfrm_direct(bundle.target.base.design, bundle.direct, rng)
end

"""
    posterior_predictive_check(fit::Experimental.CorrelatedMGMFRMFit; kwargs...)

Compare observed and replicated score summaries for the existing rating design.
Uses the selection and RNG controls of `predictive_probabilities` and returns
resolved draw indices, model/prior identity and stored sampling-quality status.
`predictive_check_summary(check; include_grouped = true)` includes observed
design-block summaries. Same-data agreement does not establish convergence,
parameter recovery or predictive performance for new facet levels.
"""
function posterior_predictive_check(fit::_CorrelatedMGMFRMFit;
        ndraws::Union{Nothing,Int} = nothing, draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    bundle = _mgmfrm_correlated_2d_prediction_bundle(fit, ndraws, draw_indices, rng)
    replicated = _replicate_scores_mgmfrm_direct(bundle.target.base.design, bundle.direct, rng)
    check = _posterior_predictive_check(bundle.target.base.design.spec, replicated, bundle.indices)
    return merge(check, _mgmfrm_correlated_2d_prediction_metadata(bundle.target), (;
        schema = "bayesianmgmfrm.correlated_mgmfrm_posterior_predictive_check.v1",
        prediction_conditioning = :joint_posterior_existing_levels,
        backend = bundle.checked.record.run.backend,
        source_sample_content_hash = bundle.checked.record.content_hash,
        sampling_quality = bundle.checked.diagnostics.flag))
end
