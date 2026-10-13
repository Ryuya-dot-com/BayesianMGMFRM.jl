"""
    BayesianMGMFRM.Experimental

Namespace for multidimensional MFRM and generalized models available in limited,
experimental configurations but are not part of the stable MFRM fitting
contract.

Use [`BayesianMGMFRM.Experimental.preview`](@ref),
[`BayesianMGMFRM.Experimental.prior_predictive_check`](@ref),
[`BayesianMGMFRM.Experimental.fit`](@ref), and
[`BayesianMGMFRM.Experimental.cached_fit`](@ref) instead of adding
`experimental = true` to the stable entry points. The legacy keyword remains
available for source compatibility for GMFRM/MGMFRM. Fixed-coefficient
multidimensional MFRM uses `Experimental.fit` and manual
`save_fit_cache`/`load_fit_cache`, and both prior-predictive entries; preview and automatic cache
entries in this namespace still accept only GMFRM/MGMFRM.

The narrower
[`BayesianMGMFRM.Experimental.free_latent_correlation_2d_candidate`](@ref)
entry point exposes a density-and-gradient target only. It has no fit result or
cache path through that density-only entry. Use `correlated(spec)` with an
explicit `GeneralizedPrior` for the separate, limited correlated MGMFRM fitting
and manual-cache workflow. The density target's companion functions expose the transformed
correlation state and finite-difference gradient checks. Inspect
[`BayesianMGMFRM.Experimental.surface_contract`](@ref) for the exact accepted
configurations and constraints.
"""
module Experimental

const _PACKAGE = parentmodule(@__MODULE__)
const _FacetSpec = getfield(_PACKAGE, :FacetSpec)

"""
Result of experimental scalar GMFRM fitting. Inspect estimates with
`posterior_summary` and sampling quality with `diagnostics`.
"""
const GMFRMFit = getfield(_PACKAGE, :GMFRMFit)

"""
Result of experimental fixed-Q MGMFRM fitting. Inspect estimates with
`posterior_summary` and sampling quality with `diagnostics`.
"""
const MGMFRMFit = getfield(_PACKAGE, :MGMFRMFit)

"""
Result of experimental fixed-coefficient multidimensional MFRM fitting.
Use `Experimental.fit(spec)` to estimate and `save_fit_cache`/`load_fit_cache`
to save and reopen a result.
"""
const MultidimensionalMFRMFit = getfield(_PACKAGE, :MultidimensionalMFRMFit)

"""
Experimental prior-scale type for GMFRM and MGMFRM fits. Its six
standard deviations apply to independent normal priors on raw unconstrained
coordinates, not directly to transformed model parameters.
For an explicit correlated MGMFRM specification, ability pairs are conditionally
bivariate normal with these marginal SDs and the specification's LKJ correlation;
the other raw-coordinate priors retain their meanings.
"""
const GeneralizedPrior = getfield(_PACKAGE, :GeneralizedPrior)

"""
    NormalizedMGMFRMPrior(; prior_model, person_sd, rater_sd, item_sd,
        log_discrimination_sd, log_consistency_sd, step_sd, source_rater=nothing)

Explicit normalized prior for independent fixed-Q MGMFRM with estimated positive
loadings and rater consistency. All six scales and `prior_model` are required.
Use `:exchangeable` for symmetric centered blocks, or `:source` with an explicit
`source_rater` ID for the reference prior with shifted log-consistency means.
Rater, log-consistency and item-step scales are kernel SDs: a block of length n
has marginal SD `tau*sqrt((n-1)/n)` and pairwise contrast SD `sqrt(2)*tau`.
Other scales are SDs of independent normal raw coordinates. No scientific
scale or default is selected by this constructor. This is distinct from the
fixed-coefficient MFRM `ExchangeablePrior` and the raw `GeneralizedPrior`.

Use with `fit`, `prior_predict` and `prior_predictive_check`. Correlated models
and automatic request caching are unavailable; use manual fit caches.
"""
const NormalizedMGMFRMPrior = getfield(_PACKAGE, :_NormalizedMGMFRMPrior)

"""
    MeanProfilePrior(model, base; item_means, step_means, category_levels, units)

Opt-in fixed location/step means for independent D1 item-owned PCM with
`model = slope_restriction(spec; item_slopes=:fixed_one, rater_consistency=:fixed_one)`
and `base = NormalizedMGMFRMPrior(prior_model=:exchangeable, ...)`.
`item_means` and `step_means` are dictionaries keyed by every actual item ID.
Each step vector contains K-1 adjacent-transition means, sums to zero and excludes
the structural baseline. `category_levels` must match the full declared order.
Person and rater means remain zero; the item mean carries the reference location.

Explicit `units=:raw` or `:unit_logit` applies to the supplied means only.
Unit-logit means are divided by 1.7; all six base-prior SDs remain raw-scale inputs.
No numerical prior or default is chosen. Values are copied, canonicalized and
bound to item/category IDs in saved results and refit requests.

Step residual covariance is `step_sd^2*(I-ones(H,H)/H)`, H=K-1. Nonconstant
means make the full step prior nonexchangeable, despite exchangeable residuals.
Ordered means do not enforce hard ordering. Binary responses have zero step shape.
Probabilities at prior means are not integrated prior-predictive probabilities.
Use `prior_predictive_check` to examine the joint prior before fitting.

Supports Julia raw-coordinate `fit`, prior prediction, summaries, reports,
existing-level K-fold refit planning and manual fit caches. Automatic caching,
CmdStan fitting, free slopes, correlated/multidimensional models and learned
profile hyperparameters are unavailable. This is experimental engineering
support, not recovery/SBC or scientific acceptance of any application prior.
"""
const MeanProfilePrior = getfield(_PACKAGE, :_MGMFRMMeanProfilePrior)

"""
Result of `Experimental.fit(spec; prior=NormalizedMGMFRMPrior(...))`.
Also represents `slope_restriction` fits; inspect `fit_metadata` for the saved
coefficient policy. Supports summaries, MCSE, diagnostics, existing-row prediction, manual fit
caches, reports and optional figures. Its saved prior retains distribution,
kernel scales and the source rater identity. Scientific acceptance is separate.
"""
const NormalizedMGMFRMFit = getfield(_PACKAGE, :_NormalizedMGMFRMFit)

"""
    slope_restriction(spec; item_slopes, rater_consistency)

Specify a matched one-dimensional, item-step MGMFRM with item slopes
`:fixed_one` or `:estimated_positive` and `rater_consistency=:fixed_one`.
Both keywords are required. The input is copied. Its response equation is
`log(P(Y=k)/P(Y=k-1)) = 1.7*(a[i]*theta[p]-b[i]-r[j]-t[i,k])`.
The threshold owner, coefficient placement and literal 1.7 scale do not change.
Fixed-one slopes map to unit-logit PCM only after rescaling locations, steps
and their prior SDs by 1.7; this is not the existing scalar rater-step GMFRM.

Pass the result and an explicit `NormalizedMGMFRMPrior(prior_model=:exchangeable,
...)` to `fit`, `prior_predict` or `prior_predictive_check`. All six prior inputs
remain required; log-consistency SD is inactive, and log-discrimination SD is
also inactive for fixed item slopes. Fixed blocks have no sampled coordinates
or density factors. These inputs do not act as near-zero-variance priors.

This first route supports Julia `backend=:advancedhmc`, raw coordinates and
manual `save_fit_cache`/`load_fit_cache`. It returns `NormalizedMGMFRMFit` with
the restriction bound to target identity, reduced raw coordinates and fixed
coefficients reconstructed in model summaries. Inspect the order with
`surface_contract(model; prior).raw_parameter_names` before supplying `init`.
Summaries, MCSE, diagnostics, existing-level prediction, reports and common
K-fold refit planning retain the policy and numerical warnings. CmdStan fitting,
other sampling coordinates, source priors, correlations, higher dimensions,
anchors and automatic caches are unavailable through this wrapper. Supported
operations do not establish recovery, SBC or model-selection performance.
"""
function slope_restriction(spec::_FacetSpec; item_slopes::Symbol, rater_consistency::Symbol)
    getfield(_PACKAGE, :_SlopeRestrictedSpec)(spec; item_slopes, rater_consistency)
end

function surface_contract(spec::getfield(_PACKAGE, :_SlopeRestrictedSpec); prior)
    target = getfield(_PACKAGE, :_normalized_mgmfrm_target)(spec, prior)
    return (; family=:mgmfrm, status=:experimental, dimensions=1,
        step_owner=:item, thresholds=:partial_credit, likelihood_scale=1.7,
        loading_policy=spec.item_slopes, rater_consistency=:fixed_one,
        location=:prior_anchored, latent_correlation=:identity_fixed,
        raw_parameter_names=copy(target.blueprint.parameter_names),
        direct_parameter_names=copy(target.blueprint.constrained_parameter_names),
        prior=getfield(_PACKAGE, :_mgmfrm_normalized_prior_metadata)(target),
        supported_backends=(:advancedhmc,), sampling_coordinates=(:raw,),
        fit_enabled=true, automatic_cache_enabled=false, manual_cache_enabled=true,
        scientific_acceptance=:not_established)
end


"""
Two-dimensional MFRM specification with estimated population correlation.
Construct with [`correlated`](@ref).
"""
const CorrelatedMFRMSpec = getfield(_PACKAGE, :CorrelatedMFRMSpec)

"""
Result of experimental correlated MFRM fitting. `direct_posterior_summary`
and `plot_posterior(...; block = :latent_correlation)` report rho on its
correlation scale. Reports default to reader-facing output; diagnostics must
be checked before interpreting estimates.
"""
const CorrelatedMFRMFit = getfield(_PACKAGE, :_CorrelatedMFRMFit)

"""
Two-dimensional between-item MGMFRM specification with estimated positive
loadings, rater consistency and population correlation. Construct with
`correlated(spec; lkj_eta = 2)` and explicitly supply `GeneralizedPrior` to `fit`.
"""
const CorrelatedMGMFRMSpec = getfield(_PACKAGE, :_CorrelatedMGMFRMSpec)

"""
Experimental correlated MGMFRM result. Supports raw/direct summaries, MCSE,
diagnostics, metadata, full fit artifacts and manual `save_fit_cache`/`load_fit_cache`.
Direct summaries and default MCSE report rho; raw summaries report Fisher z.
Supports category probabilities and posterior prediction for existing rating
rows, reader-facing reports, tables and optional CairoMakie figures. Report
bundles preserve model identity, diagnostic warnings and figure inputs.
"""
const CorrelatedMGMFRMFit = getfield(_PACKAGE, :_CorrelatedMGMFRMFit)

"""
    ExchangeablePrior(; rater_kernel_sd, person_sd = 1.5, item_sd = 1.0, step_sd = 1.0)

Prior for fixed-coefficient multidimensional MFRM with exchangeable, zero-sum
rater severities. Pass the same `prior` to `prior_predictive_check` and `fit`,
with an independent specification or `correlated(spec)`, on either backend.
All scales must be finite and positive. The rater scale is required: for R
raters, marginal SD is `rater_kernel_sd * sqrt((R-1)/R)` and pairwise contrast
SD is `sqrt(2) * rater_kernel_sd`. It is not the independent-free-coordinate
`rater_sd` of `MFRMPrior`; choosing the same number does not match those priors.
Ability, item and free-step scales keep their `MFRMPrior` meanings. Correlated
abilities additionally use the LKJ shape specified by `correlated`. Scales are
fixed inputs, not estimated hyperparameters. Unsupported for scalar MFRM,
GMFRM and MGMFRM. The default prior remains `MFRMPrior()`.
"""
const ExchangeablePrior = getfield(_PACKAGE, :_ExchangeablePrior)

"""
Result of `Experimental.fit(...; prior = ExchangeablePrior(...))` for independent
or correlated multidimensional MFRM. Supports summaries, diagnostics, report
bundles, plots, and `save_fit_cache`/`load_fit_cache`. Reports default to
reader-facing output and retain the selected prior and sampler warnings.
"""
const ExchangeableMFRMFit = getfield(_PACKAGE, :_ExchangeableMFRMFit)

"""
    correlated(spec; lkj_eta = 2)

Estimate population correlation between the two named ability dimensions of
a fixed-coefficient MFRM or an estimated-loading MGMFRM.
For MFRM, pass the returned specification to `Experimental.fit`
with `backend = :advancedhmc` (Julia) or `:cmdstan` and `prior = MFRMPrior(...)`
or [`ExchangeablePrior`](@ref).
The input specification is copied and retains its independent-model meaning.

Requires `family = :mfrm`, exactly two dimensions, partial-credit thresholds,
between-item Q with at least two pure items per dimension, and observations in
both dimensions for every person. Anchors and fitted bias terms are unavailable.
Q coefficients and rater consistency are fixed at one; locations use unit
logits and zero-centered priors. Direct ability pairs have covariance
`person_sd^2 * [1 rho; rho 1]`. `lkj_eta` is a fixed positive integer LKJ shape
on rho; it is not a standard deviation. Sampling uses `rho = tanh(z)` with
the transformation Jacobian. A custom `init` ends in Fisher z, not rho.

Use `prior_predictive_check` before fitting, and `save_fit_cache`/`load_fit_cache`
to save and reopen MFRM results. Automatic request caching is unavailable.

For `family = :mgmfrm`, the same 2D pure-Q and observation-coverage restrictions
apply, with estimated positive active loadings and product-one rater consistency.
Pass an explicit `prior = GeneralizedPrior(...)` to `Experimental.fit`; there is
no implicit prior choice for this combined model. Locations/loading scales are
prior-anchored and the response equation retains its literal 1.7 multiplier.
Both backends return `CorrelatedMGMFRMFit`, supporting raw/direct summaries,
MCSE, diagnostics, existing-row prediction, full fit artifacts and manual
save/reload. Pass the same explicit prior to `prior_predictive_check` before
fitting. Reports, exports and optional CairoMakie figures preserve the model,
prior, diagnostic warnings and conditional prediction target after reload.
"""
correlated(spec::_FacetSpec; lkj_eta = 2) = spec.family === :mgmfrm ?
    CorrelatedMGMFRMSpec(spec; lkj_eta) : CorrelatedMFRMSpec(spec; lkj_eta)

function surface_contract(spec::CorrelatedMGMFRMSpec)
    checked = CorrelatedMGMFRMSpec(spec.base_spec; lkj_eta = spec.lkj_eta)
    return merge(_family_surface_contract(:mgmfrm), (;
        scope = :correlated_2d_mgmfrm_raw_prior, maximum_dimensions = 2,
        item_structure = :between_item, minimum_pure_items_per_dimension = 2,
        person_dimension_observation_coverage = :complete,
        latent_correlation = :free_2d, likelihood_scale = 1.7,
        expected_blocks = (:person, :rater_free, :item, :log_item_dimension_discrimination,
            :log_rater_consistency_free, :item_steps, :z_latent_correlation),
        prior = (; constructor = :GeneralizedPrior, explicit_prior_required = true,
            ability = :conditional_bivariate_normal, other_free_coordinates = :independent_normal_raw_coordinates,
            correlation = :normalized_lkj_2d, lkj_eta = checked.lkj_eta,
            maximum_lkj_eta = getfield(_PACKAGE, :_MAX_INTEGER_LKJ_ETA),
            parameter_space = :raw_unconstrained_coordinates, density_measure = :d_raw_d_zrho,
            correlation_prior_measure = :d_rho, correlation_transform = :tanh,
            correlation_log_jacobian = :log_one_minus_rho_squared,
            prior_predict_available = true, prior_predictive_check_available = true),
        result_type = :CorrelatedMGMFRMFit, fit_enabled = true, manual_cache_enabled = true,
        claim_scope = :two_dimensional_between_item_correlated_mgmfrm_raw_prior,
        record_warmup_default = true,
        automatic_cache_enabled = false, predictive_checks_available = true,
        prediction_target = :existing_rating_rows, new_facet_levels = false,
        predictive_probabilities_available = true, posterior_predict_available = true,
        reports_available = true, plots_available = true, scientific_acceptance = :not_established))
end

function surface_contract(spec::CorrelatedMFRMSpec)
    return merge(_mfrm_surface_contract(), (;
        scope = :correlated_fixed_coefficient_mfrm, maximum_dimensions = 2,
        item_structure = :between_item, minimum_pure_items_per_dimension = 2,
        person_dimension_observation_coverage = :complete,
        expected_blocks = (:person, :rater_free, :item, :item_steps, :z_latent_correlation),
        latent_correlation = :free_2d,
        prior = (; constructor = :MFRMPrior, ability = :bivariate_normal,
            exchangeable_constructor = :ExchangeablePrior, exchangeable_rater_scale = :kernel_sd,
            other_free_coordinates = :independent_normal, correlation = :lkj_2d,
            lkj_eta = spec.lkj_eta, maximum_lkj_eta = getfield(_PACKAGE, :_MAX_INTEGER_LKJ_ETA),
            density_measure = :d_beta_d_zrho,
            correlation_prior_measure = :d_rho, correlation_transform = :tanh,
            correlation_log_jacobian = :log_one_minus_rho_squared,
            prior_predict_available = true, prior_predictive_check_available = true),
        claim_scope = :two_dimensional_between_item_fixed_coefficient_mfrm))
end

# Intentionally export no bindings. Fully qualified access is the quarantine
# boundary while the package-root compatibility names remain available.

function _family_surface_contract(family::Symbol)
    capability = getfield(_PACKAGE, :_guarded_generalized_fit_capability)(family)
    retained_draws = getfield(
        _PACKAGE,
        :_GENERALIZED_DEFAULT_RETAINED_DRAWS_PER_CHAIN,
    )
    warmup = getfield(_PACKAGE, :_GENERALIZED_DEFAULT_WARMUP_PER_CHAIN)
    chains = getfield(_PACKAGE, :_GENERALIZED_DEFAULT_CHAINS)
    return (
        family = capability.family,
        status = :experimental,
        scope = family === :gmfrm ?
            :scalar_rater_consistency_gmfrm :
            :fixed_q_confirmatory_mgmfrm,
        minimum_dimensions = capability.minimum_dimensions,
        maximum_dimensions = capability.maximum_dimensions,
        threshold_regimes = capability.threshold_regimes,
        discrimination = capability.spec_discrimination,
        fixed_q_required = capability.requires_fixed_q,
        anchors_allowed = capability.allows_anchors,
        fitted_dff_allowed = capability.allows_validation_bias_terms,
        kernel_discrimination = capability.kernel_discrimination,
        kernel_threshold_block = capability.kernel_threshold_block,
        discrimination_structure = family === :gmfrm ?
            :item_discrimination_times_rater_consistency :
            :fixed_q_item_dimension_discrimination_with_rater_consistency,
        step_sharing = family === :gmfrm ?
            :rater_specific_shared_across_items_and_persons :
            :item_specific_shared_across_raters_and_dimensions,
        step_constraint = :first_step_zero_remaining_steps_sum_to_zero,
        expected_blocks = capability.expected_blocks,
        latent_correlation = family === :mgmfrm ? :identity_fixed : :not_applicable,
        prior = (;
            constructor = :GeneralizedPrior,
            parameter_space = :raw_unconstrained_coordinates,
            family = :independent_zero_centered_normal,
            custom_scales_allowed = true,
            prior_predict_available = true,
            prior_predictive_check_available = true,
            direct_scale_prior_allowed = false,
            jacobian_policy = :none_raw_coordinate_density,
        ),
        normalized_prior = family === :mgmfrm ? (;
            constructor=:NormalizedMGMFRMPrior, result_type=:NormalizedMGMFRMFit,
            prior_models=(:exchangeable, :source), all_scales_required=true,
            centered_scale_convention=:kernel_sd, source_rater_required_for=:source,
            latent_correlation=:identity_fixed, sampling_coordinates=:raw,
            advancedhmc_sampling_coordinates=(:raw, :orthogonal_person_mean_item_offset),
            automatic_cache_enabled=false, manual_cache_operations=(:save_fit_cache, :load_fit_cache),
            scientific_acceptance=:not_established) : nothing,
        backend = :advancedhmc,
        supported_backends = (:advancedhmc, :cmdstan),
        sampler_defaults = (;
            warmup_per_chain = warmup,
            retained_draws_per_chain = retained_draws,
            chains,
            total_iterations_per_chain = warmup + retained_draws,
            warmup_fraction = warmup / (warmup + retained_draws),
            profile = :computational_default_not_analysis_guidance,
        ),
        claim_scope = family === :gmfrm ?
            :scalar_rater_consistency_only :
            :fixed_q_confirmatory_only,
    )
end

function _mfrm_surface_contract()
    return (;
        family = :mfrm, status = :experimental,
        scope = :fixed_coefficient_multidimensional_mfrm,
        minimum_dimensions = 2, maximum_dimensions = nothing,
        threshold_regimes = (:partial_credit,), discrimination = (:none,),
        fixed_q_required = true, anchors_allowed = false, fitted_dff_allowed = false,
        kernel_discrimination = :fixed_q_coefficients, rater_consistency = :fixed_one,
        step_sharing = :item_specific_shared_across_raters_dimensions_and_persons,
        step_constraint = :first_step_zero_remaining_steps_sum_to_zero,
        expected_blocks = (:person, :rater_free, :item, :item_steps),
        latent_correlation = :identity_fixed, location = :prior_anchored,
        scale_convention = :unit_logit,
        prior = (; constructor = :MFRMPrior, parameter_space = :unit_logit_free,
            exchangeable_constructor = :ExchangeablePrior, exchangeable_rater_scale = :kernel_sd,
            family = :independent_zero_centered_normal, custom_scales_allowed = true,
            prior_predict_available = true, prior_predictive_check_available = true,
            jacobian_policy = :none_declared_free_coordinate_density),
        backend = :advancedhmc, supported_backends = (:advancedhmc, :cmdstan),
        sampler_defaults = _family_surface_contract(:mgmfrm).sampler_defaults,
        record_warmup_default = true, fit_enabled = true, automatic_cache_enabled = false,
        manual_cache_operations = (:save_fit_cache, :load_fit_cache),
        claim_scope = :fixed_coefficient_multidimensional_mfrm)
end

function _free_latent_correlation_2d_contract()
    return (;
        family = :mgmfrm,
        status = :experimental,
        scope = :mgmfrm_2d_free_latent_correlation,
        entrypoint =
            "BayesianMGMFRM.Experimental.free_latent_correlation_2d_candidate(spec)",
        dimensions = 2,
        q_matrix = :fixed_simple_structure,
        minimum_pure_items_per_dimension = 2,
        person_dimension_observation_coverage = :complete,
        thresholds = (:partial_credit,),
        discrimination_selector = (:none,),
        kernel_discrimination = :q_masked_item_dimension,
        latent_correlation = :free_tanh_coordinate,
        latent_correlation_prior = :normalized_lkj_2d,
        lkj_eta = :fixed_positive_integer,
        default_lkj_eta = 2,
        maximum_lkj_eta = getfield(_PACKAGE, :_MAX_INTEGER_LKJ_ETA),
        anchors_allowed = false,
        fitted_dff_allowed = false,
        fit_enabled = false,
        cache_enabled = false,
        available_operations = (
            :state,
            :gradient_diagnostics,
        ),
        evidence_scope = :density_and_gradient_diagnostics_only,
        result_type = :named_tuple_only,
    )
end

function _require_generalized_spec(spec, caller::AbstractString)
    if spec isa CorrelatedMGMFRMSpec
        detail = caller in ("Experimental.cached_fit", "Experimental.fit_cache_key") ?
            "use Experimental.fit, then save_fit_cache/load_fit_cache" : "inspect surface_contract(spec) for available operations"
        throw(ArgumentError("$caller is not yet available for correlated MGMFRM; $detail"))
    end
    spec isa _FacetSpec ||
        throw(ArgumentError("$caller requires a FacetSpec"))
    spec.family in (:gmfrm, :mgmfrm) ||
        throw(ArgumentError(
            "$caller accepts only family = :gmfrm or :mgmfrm; " *
            "use BayesianMGMFRM.fit for the stable MFRM surface",
        ))
    return spec
end

function _reject_legacy_keyword(kwargs, caller::AbstractString)
    :experimental in keys(kwargs) || return nothing
    throw(ArgumentError(
        "$caller is already inside BayesianMGMFRM.Experimental; " *
        "remove the experimental keyword",
    ))
end

"""
    surface_contract()
    surface_contract(family)
    surface_contract(correlated_spec)
    surface_contract(slope_spec; prior)

Return the machine-readable stability boundary for the experimental namespace.
The zero-argument form describes the executable configurations and constraints
for independent fixed-coefficient MFRM and both generalized families.
Pass `:mfrm`, `:gmfrm` or `:mgmfrm` for one family contract, or a
specification returned by `correlated` for its correlation model contract.
For `slope_restriction`, pass that wrapper and its explicit `prior` to inspect
the actual free-parameter layout and Julia-only backend. Family-level backend
lists do not apply to every prior/wrapper combination. In particular, fixed/free
slope and mean-profile fits share `NormalizedMGMFRMFit` with other normalized
models but have narrower fitting restrictions. Inspect `fit_metadata` on a
saved result; the result type alone does not identify its coefficient/prior policy.
"""
function surface_contract()
    return (
        schema = "bayesianmgmfrm.experimental_surface.v1",
        stability = :experimental,
        compatibility = :may_change_in_minor_release,
        entrypoint = getfield(_PACKAGE, :_EXPERIMENTAL_CANONICAL_ENTRYPOINT),
        legacy_entrypoint = getfield(_PACKAGE, :_EXPERIMENTAL_LEGACY_ENTRYPOINT),
        legacy_status = :compatibility_only,
        reader_facing_bindings = (
            :GMFRMFit,
            :MGMFRMFit,
            :MultidimensionalMFRMFit,
            :CorrelatedMFRMSpec,
            :CorrelatedMFRMFit,
            :CorrelatedMGMFRMSpec,
            :CorrelatedMGMFRMFit,
            :ExchangeablePrior,
            :ExchangeableMFRMFit,
            :GeneralizedPrior,
            :NormalizedMGMFRMPrior,
            :MeanProfilePrior,
            :NormalizedMGMFRMFit,
            :cached_fit,
            :correlated,
            :slope_restriction,
            :fit,
            :fit_cache_key,
            :free_latent_correlation_2d_candidate,
            :free_latent_correlation_2d_contract,
            :free_latent_correlation_2d_diagnostics,
            :free_latent_correlation_2d_state,
            :preview,
            :prior_predict,
            :prior_predictive_check,
            :surface_contract,
        ),
        families = (
            mfrm = _mfrm_surface_contract(),
            gmfrm = _family_surface_contract(:gmfrm),
            mgmfrm = _family_surface_contract(:mgmfrm),
        ),
        candidate_surfaces = (
            mgmfrm_free_latent_correlation_2d =
                _free_latent_correlation_2d_contract(),
        ),
    )
end

"""
    free_latent_correlation_2d_contract()

Return the experimental capability contract for the two-dimensional free
latent-correlation density. The surface provides diagnostic operations only:
it has no fit result or cache integration and does not alter the
identity-correlation MGMFRM fit.
"""
free_latent_correlation_2d_contract() =
    _free_latent_correlation_2d_contract()

function surface_contract(family::Symbol)
    family === :mfrm && return _mfrm_surface_contract()
    family in (:gmfrm, :mgmfrm) ||
        throw(ArgumentError("family must be :mfrm, :gmfrm or :mgmfrm"))
    return _family_surface_contract(family)
end

"""
    preview(spec)

Compile an inspectable design for a representable GMFRM or MGMFRM
specification without fitting it. A successful preview does not imply that the
configuration is executable; inspect [`surface_contract`](@ref) or
`model_equation(spec).experimental_fit_available` before fitting.
"""
function preview(spec)
    checked = _require_generalized_spec(spec, "Experimental.preview")
    return getfield(_PACKAGE, :getdesign)(checked; preview = true)
end

"""
    prior_predict(spec; ndraws = 1000,
        rng = Random.default_rng())

Generate score replications from the declared prior of a supported specification.
Fixed-coefficient MFRM uses `MFRMPrior()` in unit logits; pass `correlated(spec)`
to use its joint ability/LKJ prior. Either MFRM specification also accepts
`prior = ExchangeablePrior(rater_kernel_sd = ...)`. GMFRM/MGMFRM use `GeneralizedPrior()` on raw
coordinates. Correlated MGMFRM requires an explicit `GeneralizedPrior` and uses
its joint ability/LKJ prior, including the literal 1.7 response multiplier.
Rows are independent replications of the existing rating design;
this operation does not fit a posterior. Use a local `MersenneTwister` for
reproducibility without advancing the global RNG.
"""
function prior_predict(spec; kwargs...)
    _reject_legacy_keyword(kwargs, "Experimental.prior_predict")
    if get(kwargs, :prior, nothing) isa Union{NormalizedMGMFRMPrior,MeanProfilePrior}
        options = Base.structdiff((; kwargs...), (; prior=nothing))
        return getfield(_PACKAGE, :_normalized_mgmfrm_prior_check)(spec, kwargs[:prior]; options...).replicated_scores
    end
    spec isa CorrelatedMGMFRMSpec &&
        return getfield(_PACKAGE, :_mgmfrm_correlated_2d_prior_predict)(spec; kwargs...)
    if spec isa CorrelatedMFRMSpec || spec isa _FacetSpec && getfield(_PACKAGE, :_is_mfrm_fixed_q)(spec)
        return getfield(_PACKAGE, :_fixed_q_prior_predict)(spec; kwargs...)
    end
    checked = _require_generalized_spec(spec, "Experimental.prior_predict")
    return getfield(
        _PACKAGE,
        :_experimental_generalized_prior_predict,
    )(checked; kwargs...)
end

"""
    prior_predictive_check(spec; ndraws = 1000,
        rng = Random.default_rng(), min_category_probability = 0.01,
        prior_warning_probability = 0.95, wide_facet_range_fraction = 0.8)

Generate prior parameter draws and replicated scores for a supported model.
Fixed-coefficient MFRM uses `MFRMPrior()`; `correlated(spec)` also samples its
LKJ correlation and conditional bivariate ability prior. The result includes
the selected prior; pass `prior = ExchangeablePrior(rater_kernel_sd = ...)`
to give all raters a common marginal severity distribution. It also includes
free-coordinate draws, reconstructed `model_coordinates`, and a
`parameter_summary` with central 95% prior intervals. Fixed Q coefficients,
fixed marginal scales and reconstructed sum constraints retain their fitting
meaning. Generalized models instead separate raw and constrained direct draws
under `GeneralizedPrior()`. Correlated MGMFRM requires the explicit prior used
for fitting; its last raw column is Fisher z and its last direct column is rho.
It draws the normalized LKJ prior on rho and conditional bivariate abilities;
the other free raw coordinates retain their declared normal priors.

All results work with `predictive_check_summary(check)` and
`BayesianMGMFRM.plot_predictive(check)`; fixed-coefficient MFRM also supports
`BayesianMGMFRM.plot_prior(check)`. Plotting requires CairoMakie. Observed ratings
serve only as a comparison; they do not update the prior. Simulations reuse
the supplied persons, items, raters and rating rows, not new facet levels.
"""
function prior_predictive_check(spec; kwargs...)
    _reject_legacy_keyword(kwargs, "Experimental.prior_predictive_check")
    if get(kwargs, :prior, nothing) isa Union{NormalizedMGMFRMPrior,MeanProfilePrior}
        options = Base.structdiff((; kwargs...), (; prior=nothing))
        return getfield(_PACKAGE, :_normalized_mgmfrm_prior_check)(spec, kwargs[:prior]; options...)
    end
    spec isa CorrelatedMGMFRMSpec &&
        return getfield(_PACKAGE, :_mgmfrm_correlated_2d_prior_predictive_check)(spec; kwargs...)
    if spec isa CorrelatedMFRMSpec || spec isa _FacetSpec && getfield(_PACKAGE, :_is_mfrm_fixed_q)(spec)
        return getfield(_PACKAGE, :_fixed_q_prior_predictive_check)(spec; kwargs...)
    end
    checked = _require_generalized_spec(
        spec,
        "Experimental.prior_predictive_check",
    )
    return getfield(
        _PACKAGE,
        :_experimental_generalized_prior_predictive_check,
    )(checked; kwargs...)
end

"""
    free_latent_correlation_2d_candidate(spec; lkj_eta = 2)

Construct a log-density target for an exactly two-dimensional, fixed
simple-structure Q MGMFRM. `lkj_eta` must be a positive integer. This function
does not fit the model or integrate with the fit cache.
"""
function free_latent_correlation_2d_candidate(spec; lkj_eta = 2)
    checked = _require_generalized_spec(
        spec,
        "Experimental.free_latent_correlation_2d_candidate",
    )
    checked.family === :mgmfrm || throw(ArgumentError(
        "Experimental.free_latent_correlation_2d_candidate requires " *
        "family = :mgmfrm",
    ))
    return getfield(
        _PACKAGE,
        :_mgmfrm_free_latent_correlation_2d_logdensity,
    )(checked; lkj_eta)
end

"""
    free_latent_correlation_2d_state(candidate, raw_params)

Return the transformed correlation state for a raw parameter vector.
"""
function free_latent_correlation_2d_state(candidate, raw_params)
    return getfield(
        _PACKAGE,
        :_mgmfrm_free_latent_correlation_2d_state,
    )(candidate, raw_params)
end

"""
    free_latent_correlation_2d_diagnostics(spec, raw_params; kwargs...)

Compare automatic and central-difference gradients and verify that introducing
the correlation coordinate leaves the fixed-Q MGMFRM response likelihood
unchanged. The returned reader-facing projection describes the experimental
density evaluation, gradient checks, and likelihood-consistency check. The
function is diagnostic only and does not run MCMC.
"""
function free_latent_correlation_2d_diagnostics(
        spec,
        raw_params;
        lkj_eta = 2,
        kwargs...)
    checked = _require_generalized_spec(
        spec,
        "Experimental.free_latent_correlation_2d_diagnostics",
    )
    checked.family === :mgmfrm || throw(ArgumentError(
        "Experimental.free_latent_correlation_2d_diagnostics requires " *
        "family = :mgmfrm",
    ))
    full = getfield(
        _PACKAGE,
        :_mgmfrm_free_latent_correlation_2d_diagnostics,
    )(checked, raw_params; lkj_eta, kwargs...)
    return (;
        schema =
            "bayesianmgmfrm.experimental_free_latent_correlation_2d_diagnostics.v1",
        family = :mgmfrm,
        stability = :experimental,
        diagnostic_scope = :free_latent_correlation_2d_density,
        automatic_differentiation = full.ad_backend,
        n_raw_parameters = full.n_raw_parameters,
        raw_parameter_names = full.raw_parameter_names,
        correlation = full.correlation,
        density_evaluation = (;
            log_density = full.logdensity,
            gradient = full.gradient,
        ),
        finite_difference_checks = full.finite_difference_rows,
        response_likelihood_check = (;
            identity_correlation_log_likelihood =
                full.likelihood_identity.base,
            free_correlation_log_likelihood =
                full.likelihood_identity.candidate,
            absolute_difference = full.likelihood_identity.abs_error,
            unchanged = full.likelihood_identity.passed,
        ),
        summary = (;
            status = full.summary.passed ? :passed : :failed,
            passed = full.summary.passed,
            n_coordinates_checked = full.summary.n_checked,
            n_coordinates_failed = full.summary.n_failed,
            finite_log_density = full.summary.finite_logdensity,
            finite_gradient = full.summary.finite_gradient,
            maximum_absolute_difference = full.summary.max_abs_error,
            maximum_tolerance = full.summary.max_tolerance,
        ),
    )
end

"""
    free_latent_correlation_2d_sampler_smoke(spec;
        raw_initial = nothing, lkj_eta = 2, kwargs...)

Run a short AdvancedHMC/NUTS diagnostic and return a `NamedTuple`. This checks
that the density can execute; it is not a fit result, convergence assessment,
cache artifact, or recovery result.
"""
function free_latent_correlation_2d_sampler_smoke(
        spec;
        raw_initial = nothing,
        lkj_eta = 2,
        kwargs...)
    candidate = free_latent_correlation_2d_candidate(spec; lkj_eta)
    initial = raw_initial === nothing ?
        getfield(_PACKAGE, :initial_params)(candidate) : raw_initial
    return getfield(
        _PACKAGE,
        :_mgmfrm_free_latent_correlation_2d_sample_bundle,
    )(candidate, initial; kwargs...)
end

"""
    free_latent_correlation_2d_oracle_profile(spec, base_raw;
        lkj_eta = 2, kwargs...)

Evaluate the one-dimensional correlation profile conditional on fixed,
complete person abilities and all other raw coordinates. This fast oracle
diagnostic does not test recovery from observed responses.
"""
function free_latent_correlation_2d_oracle_profile(
        spec,
        base_raw;
        lkj_eta = 2,
        kwargs...)
    candidate = free_latent_correlation_2d_candidate(spec; lkj_eta)
    return getfield(
        _PACKAGE,
        :_mgmfrm_free_latent_correlation_2d_oracle_profile,
    )(candidate, base_raw; kwargs...)
end

"""
    free_latent_correlation_2d_known_truth_fixture(; kwargs...)

Generate a validated response-level known-truth dataset for the experimental 2D
free-correlation density. The result describes the data-generating process; it
is not recovery evidence.
"""
function free_latent_correlation_2d_known_truth_fixture(; kwargs...)
    return getfield(
        _PACKAGE,
        :_mgmfrm_free_latent_correlation_2d_known_truth_fixture,
    )(; kwargs...)
end

"""
    free_latent_correlation_2d_recovery_pilot(fixture; kwargs...)

Run the experimental density against one known-truth response dataset. This
single-dataset result does not verify replicated recovery or change the stable
MGMFRM fitting surface.
"""
function free_latent_correlation_2d_recovery_pilot(fixture; kwargs...)
    return getfield(
        _PACKAGE,
        :_mgmfrm_free_latent_correlation_2d_recovery_pilot,
    )(fixture; kwargs...)
end

"""
    free_latent_correlation_2d_study_plan()

Return the fixed replicated-recovery study specification. This does not
generate responses or execute MCMC.
"""
function free_latent_correlation_2d_study_plan()
    return getfield(
        _PACKAGE,
        :_mgmfrm_free_latent_correlation_2d_study_plan,
    )()
end

"""
    free_latent_correlation_2d_study_ledger(plan)

Initialize an immutable ledger containing every planned study unit.
"""
function free_latent_correlation_2d_study_ledger(plan)
    return getfield(
        _PACKAGE,
        :_mgmfrm_free_latent_correlation_2d_study_ledger,
    )(plan)
end

"""
    free_latent_correlation_2d_study_apply_result(
        ledger,
        result;
        authorization = nothing,
    )

Return a new ledger with one primary unit result recorded. Planned units are
never removed, including categorized failures and unauthorized evaluation
executions supplied without an authorization artifact. A supplied malformed,
non-authorizing, cross-ledger, or result-mismatched authorization artifact is
rejected with `ArgumentError`; it is never treated as if it were absent. A
valid frozen feasibility decision may be supplied as `authorization`.
"""
function free_latent_correlation_2d_study_apply_result(
        ledger,
        result;
        authorization = nothing)
    return getfield(
        _PACKAGE,
        :_mgmfrm_free_latent_correlation_2d_study_apply_result,
    )(ledger, result; authorization)
end

"""
    free_latent_correlation_2d_study_feasibility_decision(ledger)

Freeze the computation-only feasibility decision used to authorize evaluation
unit execution. Recovery outcomes do not enter this decision.
"""
function free_latent_correlation_2d_study_feasibility_decision(ledger)
    return getfield(
        _PACKAGE,
        :_mgmfrm_free_latent_correlation_2d_study_feasibility_decision,
    )(ledger)
end

"""
    free_latent_correlation_2d_study_unit_preflight(
        plan, unit_id; authorization = nothing)

Validate one study unit and its phase requirements without generating data or
running MCMC.
"""
function free_latent_correlation_2d_study_unit_preflight(
        plan,
        unit_id;
        authorization = nothing)
    return getfield(
        _PACKAGE,
        :_mgmfrm_free_latent_correlation_2d_study_unit_preflight,
    )(plan, unit_id; authorization)
end

"""
    free_latent_correlation_2d_study_resource_probe(
        plan,
        unit_id;
        execute_measurement = false,
        repetitions = 3,
    )

Return an MCMC-free resource measurement plan by default. With
`execute_measurement = true`, generate the specified feasibility dataset and
time only the initial ForwardDiff log-density-and-gradient evaluation. A passing
measurement describes that operation only and is not recovery evidence.
"""
function free_latent_correlation_2d_study_resource_probe(
        plan,
        unit_id;
        execute_measurement::Bool = false,
        repetitions = 3)
    return getfield(
        _PACKAGE,
        :_mgmfrm_free_latent_correlation_2d_study_resource_probe,
    )(
        plan,
        unit_id;
        execute_measurement,
        repetitions,
    )
end

"""
    free_latent_correlation_2d_study_run_unit(
        plan, unit_id; execute_mcmc = false, authorization = nothing)

Validate one study unit without sampling. This compatibility entry point does
not execute MCMC; `execute_mcmc = true` is rejected.
"""
function free_latent_correlation_2d_study_run_unit(
        plan,
        unit_id;
        execute_mcmc::Bool = false,
        authorization = nothing)
    return getfield(
        _PACKAGE,
        :_mgmfrm_free_latent_correlation_2d_study_run_unit,
    )(plan, unit_id; execute_mcmc, authorization)
end

"""
    free_latent_correlation_2d_study_dry_run(plan; max_units = 2)

Generate a bounded subset of feasibility datasets. The dry-run never executes
MCMC and is not recovery evidence.
"""
function free_latent_correlation_2d_study_dry_run(
        plan;
        max_units = 2)
    return getfield(
        _PACKAGE,
        :_mgmfrm_free_latent_correlation_2d_study_dry_run,
    )(plan; max_units)
end

"""
    free_latent_correlation_2d_study_score(ledger)

Apply the deterministic scorer to a validated study ledger. Incomplete or
ineligible ledgers return a non-ready score; no score publishes a fit or claims
replicated recovery.
"""
function free_latent_correlation_2d_study_score(ledger)
    return getfield(
        _PACKAGE,
        :_mgmfrm_free_latent_correlation_2d_study_score,
    )(ledger)
end

"""
    fit(spec; kwargs...)

Fit a supported multidimensional MFRM or generalized specification experimentally.
Callers should not pass an `experimental` keyword. Family-specific structural
constraints are validated before numerical execution. Pass `correlated(spec)`
to estimate population correlation for two between-item MFRM dimensions; both
backends then return `CorrelatedMFRMFit` when using `MFRMPrior`.
The unwrapped configurations described below accept `backend = :advancedhmc`
or `:cmdstan`, subject to their category restrictions. The `slope_restriction`
and `MeanProfilePrior` routes are Julia/AdvancedHMC-only; see their separate
requirements below. A supported family does not admit every prior/backend pair.
For an MGMFRM `correlated(spec)`, an explicit `prior = GeneralizedPrior(...)`
is required. Both backends return `CorrelatedMGMFRMFit`; summaries, MCSE,
diagnostics, existing-row prediction and manual fit caches are available.
Reports and optional CairoMakie figures preserve the saved prior and diagnostic
warnings; automatic request caching remains unavailable.

For independent fixed-Q MGMFRM, explicitly pass `NormalizedMGMFRMPrior(...)`
to use normalized exchangeable/source priors and return `NormalizedMGMFRMFit`.
Both backends support manual caches and saved-result reports/figures. This
prior requires all six scales and, for `:source`, a distinguished rater ID.
AdvancedHMC also accepts `sampling_coordinates = :orthogonal_person_mean_item_offset`;
CmdStan requires `:raw`. Inspect coordinates with `fit_metadata(result).sampler_controls`.
Automatic request caching is unavailable. This unwrapped normalized route admits
binary categories on Julia; CmdStan requires at least three categories.

For `slope_restriction(spec; item_slopes, rater_consistency=:fixed_one)`, supply
an explicit exchangeable `NormalizedMGMFRMPrior`. The wrapper requires D1,
item-owned partial-credit steps, `backend=:advancedhmc` and
`sampling_coordinates=:raw`. Its optional `MeanProfilePrior` additionally
requires `item_slopes=:fixed_one` and explicit item/category IDs and mean units.
Both return `NormalizedMGMFRMFit` and support manual caches and existing-level
refit planning. CmdStan, alternative coordinates, source priors and correlated
specifications are unavailable for these wrappers. Use
`surface_contract(model; prior)` before supplying initial coordinates and
`fit_metadata(result)` to distinguish the saved policies.

The independent MGMFRM kernel also accepts `dimensions=1` with an explicit
all-active, one-column Q. This is an item-step generalized model for comparison
with higher-dimensional MGMFRM, not the existing rater-step scalar GMFRM.
It retains the 1.7 likelihood constant, coefficient placement and prior rules.
Matching the model structure does not establish predictive superiority or
calibration. The correlated wrapper still requires two dimensions.

An unwrapped independent MGMFRM with `GeneralizedPrior` accepts
`sampling_coordinates = :orthogonal_person_mean_item_offset` with AdvancedHMC.
This rotates person coordinates and shifts item coordinates while preserving
the complete joint prior and likelihood. Initial values and jitter use raw
coordinates; returned draws and diagnostics also retain their raw/model meanings.
The default is `:raw`. Automatic request caching distinguishes the optional
coordinates; default cache keys are unchanged. The option does not apply to
correlated specifications or fixed-coefficient multidimensional MFRM.

An unwrapped fixed-coefficient multidimensional MFRM (`family = :mfrm`,
`dimensions >= 2`, fixed `q_matrix`, partial-credit thresholds) has independent
abilities. Use `MFRMPrior`
for independent normal priors on free unit-logit coordinates. Q coefficients
and rater consistency are fixed; latent correlation is identity and locations
are prior-anchored. With `MFRMPrior`, both backends return `MultidimensionalMFRMFit`, with warmup
sampler statistics recorded by default (`record_warmup = true`). Save and reload
with `save_fit_cache`/`load_fit_cache`; automatic request caching is unavailable.
Shared sampler controls include `ndraws`, `warmup`, `chains`, `seed`, `init`,
`step_size`, `target_accept`, `max_depth`, and stored diagnostic thresholds.
CmdStan additionally accepts `cmdstan_path` and `cmdstan_cache_dir`.
For exchangeable zero-sum rater severities, explicitly pass
`prior = ExchangeablePrior(rater_kernel_sd = ...)`. Both independent and
correlated specifications then return `ExchangeableMFRMFit`, with the same
summary, report, plotting and manual cache operations.
"""
function fit(spec; kwargs...)
    _reject_legacy_keyword(kwargs, "Experimental.fit")
    spec isa getfield(_PACKAGE, :_SlopeRestrictedSpec) && !(get(kwargs, :prior, nothing) isa Union{NormalizedMGMFRMPrior,MeanProfilePrior}) &&
        throw(ArgumentError("slope_restriction requires an explicit NormalizedMGMFRMPrior"))
    if get(kwargs, :prior, nothing) isa Union{NormalizedMGMFRMPrior,MeanProfilePrior}
        options = Base.structdiff((; kwargs...), (; prior=nothing))
        return getfield(_PACKAGE, :_normalized_mgmfrm_fit)(spec, kwargs[:prior]; options...)
    end
    if haskey(kwargs, :sampling_coordinates) &&
            (spec isa CorrelatedMGMFRMSpec || spec isa CorrelatedMFRMSpec ||
                (spec isa _FacetSpec && getfield(_PACKAGE, :_is_mfrm_fixed_q)(spec)))
        throw(ArgumentError("sampling_coordinates is available for independent fixed-Q MGMFRM only"))
    end
    if spec isa CorrelatedMGMFRMSpec
        return getfield(_PACKAGE, :_mgmfrm_correlated_2d_fit)(spec; kwargs...)
    end
    if spec isa CorrelatedMFRMSpec
        return getfield(_PACKAGE, :_mfrm_correlated_2d_fit)(spec; kwargs...)
    end
    if spec isa _FacetSpec && getfield(_PACKAGE, :_is_mfrm_fixed_q)(spec)
        return getfield(_PACKAGE, :_mfrm_fixed_q_fit)(spec; kwargs...)
    end
    checked = _require_generalized_spec(spec, "Experimental.fit")
    return getfield(_PACKAGE, :_fit_guarded_generalized)(checked; kwargs...)
end

"""
    fit_cache_key(spec; backend = :advancedhmc, kwargs...)

Return the deterministic cache key for an experimental generalized fit request.
The namespace records the experimental identity and selects the generalized
backend unless the backend is overridden explicitly.
"""
function fit_cache_key(spec; backend::Symbol = :advancedhmc, kwargs...)
    get(kwargs, :prior, nothing) isa Union{NormalizedMGMFRMPrior,MeanProfilePrior} && throw(ArgumentError(
        "normalized MGMFRM requires fit followed by save_fit_cache/load_fit_cache; automatic request caching is unavailable"))
    checked = _require_generalized_spec(spec, "Experimental.fit_cache_key")
    _reject_legacy_keyword(kwargs, "Experimental.fit_cache_key")
    return getfield(_PACKAGE, :fit_cache_key)(
        checked;
        experimental = true,
        backend,
        kwargs...,
    )
end

"""
    cached_fit(spec; backend = :advancedhmc, kwargs...)

Run or load an experimental generalized fit through the package cache while
keeping its experimental identity explicit in the cache contract. The
generalized backend is selected by default.
"""
function cached_fit(spec; backend::Symbol = :advancedhmc, kwargs...)
    get(kwargs, :prior, nothing) isa Union{NormalizedMGMFRMPrior,MeanProfilePrior} && throw(ArgumentError(
        "normalized MGMFRM requires fit followed by save_fit_cache/load_fit_cache; automatic request caching is unavailable"))
    checked = _require_generalized_spec(spec, "Experimental.cached_fit")
    _reject_legacy_keyword(kwargs, "Experimental.cached_fit")
    return getfield(_PACKAGE, :cached_fit)(
        checked;
        experimental = true,
        backend,
        kwargs...,
    )
end

end
