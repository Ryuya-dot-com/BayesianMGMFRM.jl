"""
    BayesianMGMFRM.Experimental

Explicit namespace for generalized model surfaces that are available for
methodological review and controlled experiments, but are not part of the
stable MFRM fitting contract.

Use [`BayesianMGMFRM.Experimental.preview`](@ref),
[`BayesianMGMFRM.Experimental.fit`](@ref), and
[`BayesianMGMFRM.Experimental.cached_fit`](@ref) instead of adding
`experimental = true` to the stable entry points. The legacy keyword remains
available for source compatibility during the namespace migration.

The narrower
[`BayesianMGMFRM.Experimental.free_latent_correlation_2d_candidate`](@ref)
entry point exposes a density-and-gradient candidate only. It has no fit,
result, or cache path; adjacent quarantined helpers provide diagnostics,
fixtures, pilots, and pre-execution study controls without changing that
boundary.

The namespace is an API quarantine, not evidence that a generalized model has
been promoted. Inspect
[`BayesianMGMFRM.Experimental.surface_contract`](@ref) for the exact accepted
configurations and evidence gates.
"""
module Experimental

const _PACKAGE = parentmodule(@__MODULE__)
const _FacetSpec = getfield(_PACKAGE, :FacetSpec)

"""
Compatibility alias for the guarded scalar GMFRM result type. The defining
type remains at package root so existing serialized fit caches keep their
Julia type identity during the namespace migration.
"""
const GMFRMFit = getfield(_PACKAGE, :GMFRMFit)

"""
Compatibility alias for the guarded fixed-Q MGMFRM result type. The defining
type remains at package root so existing serialized fit caches keep their
Julia type identity during the namespace migration.
"""
const MGMFRMFit = getfield(_PACKAGE, :MGMFRMFit)

# Intentionally export no bindings. Fully qualified access is the quarantine
# boundary while the package-root compatibility names remain available.

const _STABLE_PUBLIC_GATES = (
    :source_equation_alignment,
    :identified_parameterization,
    :gradient_validation,
    :hmc_geometry,
    :known_truth_recovery,
    :predictive_validation,
    :prior_and_likelihood_sensitivity,
    :reproducibility_archive,
    :independent_public_scope_review,
)

const _EXTERNAL_VALIDATED_GATES = (
    :overlap_target_comparability,
    :known_truth_external_software_comparison,
    :external_construct_evidence,
    :real_data_validation_evidence,
)

function _family_surface_contract(family::Symbol)
    capability = getfield(_PACKAGE, :_guarded_generalized_fit_capability)(family)
    return (
        family = capability.family,
        status = :experimental,
        scope = capability.scope,
        minimum_dimensions = capability.minimum_dimensions,
        maximum_dimensions = capability.maximum_dimensions,
        threshold_regimes = capability.threshold_regimes,
        discrimination = capability.spec_discrimination,
        fixed_q_required = capability.requires_fixed_q,
        anchors_allowed = capability.allows_anchors,
        fitted_dff_allowed = capability.allows_validation_bias_terms,
        kernel_discrimination = capability.kernel_discrimination,
        kernel_threshold_block = capability.kernel_threshold_block,
        expected_blocks = capability.expected_blocks,
        latent_correlation = family === :mgmfrm ? :identity_fixed : :not_applicable,
        backend = :advancedhmc,
        claim_scope = family === :gmfrm ?
            :guarded_scalar_rater_consistency_only :
            :fixed_q_confirmatory_only,
    )
end

function _free_latent_correlation_2d_contract()
    return (;
        family = :mgmfrm,
        status = :internal_density_candidate,
        scope = :mgmfrm_2d_free_latent_correlation_candidate,
        entrypoint =
            "BayesianMGMFRM.Experimental.free_latent_correlation_2d_candidate(spec)",
        diagnostics_entrypoint =
            "BayesianMGMFRM.Experimental.free_latent_correlation_2d_diagnostics(spec, raw_params)",
        sampler_smoke_entrypoint =
            "BayesianMGMFRM.Experimental.free_latent_correlation_2d_sampler_smoke(spec)",
        oracle_profile_entrypoint =
            "BayesianMGMFRM.Experimental.free_latent_correlation_2d_oracle_profile(spec, base_raw)",
        known_truth_fixture_entrypoint =
            "BayesianMGMFRM.Experimental.free_latent_correlation_2d_known_truth_fixture()",
        recovery_pilot_entrypoint =
            "BayesianMGMFRM.Experimental.free_latent_correlation_2d_recovery_pilot(fixture)",
        study_plan_entrypoint =
            "BayesianMGMFRM.Experimental.free_latent_correlation_2d_study_plan()",
        study_ledger_entrypoint =
            "BayesianMGMFRM.Experimental.free_latent_correlation_2d_study_ledger(plan)",
        study_apply_result_entrypoint =
            "BayesianMGMFRM.Experimental.free_latent_correlation_2d_study_apply_result(ledger, result; authorization=nothing)",
        study_feasibility_decision_entrypoint =
            "BayesianMGMFRM.Experimental.free_latent_correlation_2d_study_feasibility_decision(ledger)",
        study_unit_preflight_entrypoint =
            "BayesianMGMFRM.Experimental.free_latent_correlation_2d_study_unit_preflight(plan, unit_id)",
        study_resource_probe_entrypoint =
            "BayesianMGMFRM.Experimental.free_latent_correlation_2d_study_resource_probe(plan, unit_id; execute_measurement=false, repetitions=3)",
        study_run_unit_entrypoint =
            "BayesianMGMFRM.Experimental.free_latent_correlation_2d_study_run_unit(plan, unit_id; execute_mcmc=false)",
        study_dry_run_entrypoint =
            "BayesianMGMFRM.Experimental.free_latent_correlation_2d_study_dry_run(plan; max_units=2)",
        study_score_entrypoint =
            "BayesianMGMFRM.Experimental.free_latent_correlation_2d_study_score(ledger)",
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
        sampler_smoke_enabled = true,
        sampler_smoke_claim_scope = :execution_smoke_not_recovery,
        oracle_profile_enabled = true,
        oracle_profile_claim_scope =
            :oracle_complete_latent_profile_not_response_recovery,
        known_truth_fixture_enabled = true,
        known_truth_fixture_claim_scope = :response_level_dgp_not_recovery,
        recovery_pilot_enabled = true,
        recovery_pilot_modes = (:diagnostic_smoke, :scientific),
        recovery_pilot_sampler_defaults = (;
            max_depth = 10,
            metric = :diagonal,
        ),
        replicated_study_layer_enabled = true,
        replicated_study_status =
            :frozen_v2_plan_preexecution_controls_and_deterministic_scoring_scientific_execution_not_started,
        replicated_study_plan_id =
            "mgmfrm_free_latent_correlation_2d_recovery_study_v2",
        replicated_study_plan_fingerprint =
            "d3f39355bf16c8ae984b58f5b2c52b5ab81ccbbe26a68379e31d0281b2beb4e3",
        replicated_study_unit_roster_sha256 =
            "0c4939ab76a0e5f78c2dd13896446c51a7faecdff65288b5b94c9c957cc62d08",
        replicated_study_primary_units = 525,
        replicated_study_feasibility_units = 25,
        replicated_study_evaluation_units = 500,
        replicated_study_scientific_mcmc_units_executed = 0,
        replicated_study_batch_execution_enabled = false,
        replicated_study_run_unit_entrypoint_preflight_only = true,
        replicated_study_run_unit_entrypoint_scientific_execution_enabled =
            false,
        replicated_study_dry_run_mcmc_enabled = false,
        replicated_study_resource_probe_enabled = true,
        replicated_study_resource_probe_default_executes_measurement = false,
        replicated_study_resource_probe_executes_mcmc = false,
        replicated_study_frozen_plan_resource_probe_completed = false,
        replicated_study_short_nuts_resource_profile_completed = false,
        replicated_study_preexecution_archive_runner_enabled = true,
        replicated_study_preexecution_archive_runner_scientific_execution_enabled =
            false,
        replicated_study_atomic_scientific_worker_ready = false,
        replicated_study_preload_immutable_source_snapshot_ready = false,
        replicated_study_independently_recalculable_raw_draw_archive_ready =
            false,
        replicated_study_operational_execution_authorized = false,
        replicated_study_scientific_execution_authorized = false,
        replicated_study_scientific_execution_required_gates =
            (:protocol, :operational, :atomic_archive_receipt),
        replicated_study_deterministic_scorer_enabled = true,
        replicated_study_score_claims_recovery = false,
        scientific_pilot_minimum = (;
            chains = 4,
            warmup_per_chain = 500,
            draws_per_chain = 500,
        ),
        end_to_end_response_recovery_status =
            :internal_single_dataset_pilot_available,
        reproducibility_archive_status = :pending_closed_set_refresh,
        result_type = :named_tuple_only,
        promotion_effect = :none,
        next_gate =
            :initial_gradient_resource_probe_then_short_nuts_profile_and_atomic_runner,
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
The zero-argument form describes both guarded generalized families and their
stable-public and external-validation evidence gates. Pass `:gmfrm` or
`:mgmfrm` for one family contract.
"""
function surface_contract()
    return (
        schema = "bayesianmgmfrm.experimental_surface.v1",
        stability = :experimental,
        compatibility = :may_change_in_minor_release,
        entrypoint = getfield(_PACKAGE, :_EXPERIMENTAL_CANONICAL_ENTRYPOINT),
        legacy_entrypoint = getfield(_PACKAGE, :_EXPERIMENTAL_LEGACY_ENTRYPOINT),
        legacy_status = :compatibility_only,
        root_fit_type_exports = :transitional_compatibility,
        families = (
            gmfrm = _family_surface_contract(:gmfrm),
            mgmfrm = _family_surface_contract(:mgmfrm),
        ),
        candidate_surfaces = (
            mgmfrm_free_latent_correlation_2d =
                _free_latent_correlation_2d_contract(),
        ),
        stable_public_gates = _STABLE_PUBLIC_GATES,
        external_validated_gates = _EXTERNAL_VALIDATED_GATES,
        automatic_promotion = false,
    )
end

"""
    free_latent_correlation_2d_contract()

Return the executable quarantine contract for the two-dimensional free latent
correlation density candidate. This surface has only a diagnostic sampler
smoke: it has no public fit result or cache integration and does not alter the
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

Compile an inspectable design for a guarded GMFRM or MGMFRM specification
without fitting it. This always uses the package's preview-only compiler path.
"""
function preview(spec)
    checked = _require_generalized_spec(spec, "Experimental.preview")
    return getfield(_PACKAGE, :getdesign)(checked; preview = true)
end

"""
    free_latent_correlation_2d_candidate(spec; lkj_eta = 2)

Construct the quarantined order-0 log-density target for an exactly
two-dimensional, fixed simple-structure Q MGMFRM. `lkj_eta` is a fixed positive
integer in this dependency-free first slice. This function does not fit,
cache, or promote the candidate.
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

Return the transformed correlation state for a candidate raw vector.
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
the correlation coordinate leaves the guarded MGMFRM response likelihood
unchanged. The function is diagnostic only and does not run MCMC.
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
    return getfield(
        _PACKAGE,
        :_mgmfrm_free_latent_correlation_2d_diagnostics,
    )(checked, raw_params; lkj_eta, kwargs...)
end

"""
    free_latent_correlation_2d_sampler_smoke(spec;
        raw_initial = nothing, lkj_eta = 2, kwargs...)

Run the candidate through a private AdvancedHMC/NUTS execution path and return
a NamedTuple bundle. This is an execution smoke, not a fit result, convergence
assessment, cache artifact, or recovery result.
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

Generate a validated response-level known-truth fixture for the quarantined 2D
free-correlation candidate. The result is a DGP bundle, not recovery evidence.
"""
function free_latent_correlation_2d_known_truth_fixture(; kwargs...)
    return getfield(
        _PACKAGE,
        :_mgmfrm_free_latent_correlation_2d_known_truth_fixture,
    )(; kwargs...)
end

"""
    free_latent_correlation_2d_recovery_pilot(fixture; kwargs...)

Run the quarantined candidate against one known-truth response fixture. Even in
scientific mode, this single-dataset result does not verify replicated recovery
or promote the public MGMFRM surface.
"""
function free_latent_correlation_2d_recovery_pilot(fixture; kwargs...)
    return getfield(
        _PACKAGE,
        :_mgmfrm_free_latent_correlation_2d_recovery_pilot,
    )(fixture; kwargs...)
end

"""
    free_latent_correlation_2d_study_plan()

Return the frozen, locally preregistered replicated-recovery study plan. This
does not generate responses or execute MCMC.
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
executions. A valid frozen feasibility decision may be supplied as
`authorization`; missing or invalid authorization is retained as a visible
protocol violation instead of dropping the result.
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

Validate one frozen unit and its phase gate without generating data or running
MCMC.
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

Return an MCMC-free resource-probe plan by default. With
`execute_measurement = true`, generate the fixed feasibility fixture and time
only the candidate's initial ForwardDiff log-density-and-gradient evaluation.
Even a passing gradient profile does not authorize scientific execution while
the bounded short-NUTS profile, a future atomic single-unit scientific worker,
a pre-load immutable source snapshot, and an independently recalculable
raw-draw archive remain pending. The existing archive harness is
pre-execution-only and is not that scientific worker.
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

Preflight one unit. This compatibility entry point is permanently
preflight-only: `execute_mcmc = true` always fails closed. Future scientific
execution must use a separate non-public atomic single-unit worker after the
bounded short-NUTS profile, pre-load immutable source snapshot, and
independently recalculable raw-draw archive gates are completed. Changing the
operational gate alone cannot enable scientific execution here. The existing
pre-execution harness cannot create a scientific attempt, and no batch executor
is exposed.
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

Generate a bounded subset of feasibility fixtures only. The dry-run never
executes MCMC and is not recovery evidence.
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

Apply the frozen deterministic scorer to a validated study ledger. Incomplete,
unauthorized, or feasibility-blocked ledgers return a blocked score; no score
publishes a fit, promotes the candidate, or claims replicated recovery.
"""
function free_latent_correlation_2d_study_score(ledger)
    return getfield(
        _PACKAGE,
        :_mgmfrm_free_latent_correlation_2d_study_score,
    )(ledger)
end

"""
    fit(spec; kwargs...)

Fit a guarded generalized specification through the experimental namespace.
The namespace supplies the opt-in state; callers should not pass an
`experimental` keyword. All family-specific structural guards remain active.
"""
function fit(spec; kwargs...)
    checked = _require_generalized_spec(spec, "Experimental.fit")
    _reject_legacy_keyword(kwargs, "Experimental.fit")
    return getfield(_PACKAGE, :_fit_guarded_generalized)(checked; kwargs...)
end

"""
    fit_cache_key(spec; backend = :advancedhmc, kwargs...)

Return the deterministic cache key for a guarded generalized fit request.
The namespace supplies the experimental identity bit and guarded generalized
backend automatically unless the backend is overridden explicitly.
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

Run or load a guarded generalized fit through the package cache while keeping
the experimental identity bit explicit in the cache contract. The guarded
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
