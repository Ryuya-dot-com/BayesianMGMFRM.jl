"""
    BayesianMGMFRM.Experimental

Namespace for generalized model surfaces that are available in limited,
experimental configurations but are not part of the stable MFRM fitting
contract.

Use [`BayesianMGMFRM.Experimental.preview`](@ref),
[`BayesianMGMFRM.Experimental.fit`](@ref), and
[`BayesianMGMFRM.Experimental.cached_fit`](@ref) instead of adding
`experimental = true` to the stable entry points. The legacy keyword remains
available for source compatibility during the namespace migration.

The narrower
[`BayesianMGMFRM.Experimental.free_latent_correlation_2d_candidate`](@ref)
entry point exposes a density-and-gradient target only. It has no fit result or
cache path. Its reader-facing companion functions expose the transformed
correlation state and finite-difference gradient checks. Inspect
[`BayesianMGMFRM.Experimental.surface_contract`](@ref) for the exact accepted
configurations and constraints.
"""
module Experimental

const _PACKAGE = parentmodule(@__MODULE__)
const _FacetSpec = getfield(_PACKAGE, :FacetSpec)

"""
Compatibility alias for the experimental scalar GMFRM result type. The defining
type remains at package root so existing serialized fit caches keep their
Julia type identity during the namespace migration.
"""
const GMFRMFit = getfield(_PACKAGE, :GMFRMFit)

"""
Compatibility alias for the experimental fixed-Q MGMFRM result type. The defining
type remains at package root so existing serialized fit caches keep their
Julia type identity during the namespace migration.
"""
const MGMFRMFit = getfield(_PACKAGE, :MGMFRMFit)

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
        backend = :advancedhmc,
        supported_backends = family === :gmfrm ?
            (:advancedhmc, :cmdstan) : (:advancedhmc,),
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

Return the machine-readable stability boundary for the experimental namespace.
The zero-argument form describes the executable configurations and constraints
for both generalized families. Pass `:gmfrm` or `:mgmfrm` for one family
contract.
"""
function surface_contract()
    return (
        schema = "bayesianmgmfrm.experimental_surface.v1",
        stability = :experimental,
        compatibility = :may_change_in_minor_release,
        entrypoint = getfield(_PACKAGE, :_EXPERIMENTAL_CANONICAL_ENTRYPOINT),
        legacy_entrypoint = getfield(_PACKAGE, :_EXPERIMENTAL_LEGACY_ENTRYPOINT),
        legacy_status = :compatibility_only,
        families = (
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
    family in (:gmfrm, :mgmfrm) ||
        throw(ArgumentError("family must be :gmfrm or :mgmfrm"))
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

Fit a supported generalized specification through the experimental namespace.
Callers should not pass an `experimental` keyword. Family-specific structural
constraints are validated before numerical execution. Scalar GMFRM accepts
`backend = :advancedhmc` or `:cmdstan`; fixed-Q MGMFRM currently accepts only
`:advancedhmc`.
"""
function fit(spec; kwargs...)
    checked = _require_generalized_spec(spec, "Experimental.fit")
    _reject_legacy_keyword(kwargs, "Experimental.fit")
    return getfield(_PACKAGE, :_fit_guarded_generalized)(checked; kwargs...)
end

"""
    fit_cache_key(spec; backend = :advancedhmc, kwargs...)

Return the deterministic cache key for an experimental generalized fit request.
The namespace records the experimental identity and selects the generalized
backend unless the backend is overridden explicitly.
"""
function fit_cache_key(spec; backend::Symbol = :advancedhmc, kwargs...)
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
