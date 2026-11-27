const _EXPERIMENTAL_CANONICAL_ENTRYPOINT =
    "BayesianMGMFRM.Experimental.fit(spec)"
const _EXPERIMENTAL_LEGACY_ENTRYPOINT =
    "BayesianMGMFRM.fit(spec; experimental = true)"

function _guarded_generalized_fit_capability(family::Symbol)
    if family === :gmfrm
        return (;
            family,
            scope = :scalar_gmfrm_guarded_experimental,
            minimum_dimensions = 1,
            maximum_dimensions = 1,
            threshold_regimes = (:partial_credit,),
            spec_discrimination = (:rater,),
            requires_fixed_q = false,
            allows_validation_bias_terms = false,
            allows_anchors = false,
            kernel_discrimination = (:item_discrimination, :rater_consistency),
            kernel_threshold_block = :rater_steps,
            expected_blocks =
                (:person, :rater, :item, :item_discrimination,
                    :rater_consistency, :rater_steps),
        )
    elseif family === :mgmfrm
        return (;
            family,
            scope = :fixed_q_confirmatory_mgmfrm_guarded_experimental,
            minimum_dimensions = 1,
            maximum_dimensions = nothing,
            threshold_regimes = (:partial_credit,),
            spec_discrimination = (:none,),
            requires_fixed_q = true,
            allows_validation_bias_terms = false,
            allows_anchors = false,
            kernel_discrimination =
                (:item_dimension_discrimination, :rater_consistency),
            kernel_threshold_block = :item_steps,
            expected_blocks =
                (:person, :rater, :item, :item_dimension_discrimination,
                    :rater_consistency, :item_steps),
        )
    end
    throw(ArgumentError(
        "guarded generalized fitting supports only family = :gmfrm or :mgmfrm; got :$family",
    ))
end

"""
    model_ladder(; view = :full)

Return the package's machine-readable model ladder. Rows distinguish the
implemented minimal MFRM/RSM/PCM fitting slice, documented
generalized fit surfaces, and broader specified-only GMFRM/MGMFRM
configurations. The ladder is documentation data: it is used to keep claims
about fitting support separate from claims about representable specification
intent. The compatibility default `view = :full` retains the original ladder
rows. Use `view = :public` for rows with explicit stability, fit entrypoint,
and claim scope fields.
"""
function model_ladder(; view::Symbol = :full)
    view in (:full, :public) ||
        throw(ArgumentError("view must be :full or :public"))
    gmfrm_capability = _guarded_generalized_fit_capability(:gmfrm)
    mgmfrm_capability = _guarded_generalized_fit_capability(:mgmfrm)
    rows = [
        (;
            family = :mfrm,
            scope = :minimal_mfrm_rsm_pcm,
            dimensions = "1",
            discrimination = :none,
            threshold_regimes = (:rating_scale, :partial_credit),
            estimation_status = :fit_supported,
            public_fit = true,
            experimental_public = false,
            identification = (:reference_first_rater, :reference_first_item, :sum_to_zero_thresholds),
            note = "implemented additive one-dimensional many-facet Rasch location model",
        ),
        (;
            family = :mfrm,
            scope = :fixed_coefficient_multidimensional_mfrm,
            dimensions = ">= 2",
            discrimination = :none,
            threshold_regimes = (:partial_credit,),
            estimation_status = :experimental_public,
            public_fit = true,
            experimental_public = true,
            identification = (:fixed_q_coefficients, :identity_latent_correlation,
                :prior_anchored_locations, :sum_to_zero_raters, :item_step_constraints),
            note = "fixed-coefficient multidimensional MFRM in unit logits through BayesianMGMFRM.Experimental.fit(spec)",
        ),
        (;
            family = :gmfrm,
            scope = gmfrm_capability.scope,
            dimensions = "1",
            discrimination = gmfrm_capability.spec_discrimination,
            spec_discrimination = gmfrm_capability.spec_discrimination,
            kernel_discrimination = gmfrm_capability.kernel_discrimination,
            threshold_regimes = gmfrm_capability.threshold_regimes,
            estimation_status = :experimental_public,
            public_fit = true,
            experimental_public = true,
            identification = (:item_discrimination_product_constraint, :rater_consistency_positive, :rater_step_constraints),
            note = "guarded scalar rater-consistency GMFRM through BayesianMGMFRM.Experimental.fit(spec)",
        ),
        (;
            family = :mgmfrm,
            scope = mgmfrm_capability.scope,
            dimensions = ">= 2",
            discrimination = mgmfrm_capability.kernel_discrimination,
            spec_discrimination = mgmfrm_capability.spec_discrimination,
            kernel_discrimination = mgmfrm_capability.kernel_discrimination,
            threshold_regimes = mgmfrm_capability.threshold_regimes,
            estimation_status = :experimental_public,
            public_fit = true,
            experimental_public = true,
            identification = (:fixed_confirmatory_q_mask, :identity_latent_correlation, :standard_normal_ability_scale, :positive_q_masked_loadings),
            note = "guarded fixed-Q confirmatory MGMFRM through BayesianMGMFRM.Experimental.fit(spec)",
        ),
        (;
            family = :gmfrm,
            scope = :planned_generalized_mfrm,
            dimensions = "1",
            discrimination = (:global, :rater, :item, :rater_item),
            threshold_regimes = (:rating_scale, :partial_credit),
            estimation_status = :specified_only,
            public_fit = false,
            experimental_public = false,
            identification = (:item_discrimination_product_constraint, :rater_consistency_positive, :rater_step_constraints),
            note = "source-aligned preview for broader manifests and constraint review; broad fitting remains planned",
        ),
        (;
            family = :mgmfrm,
            scope = :planned_multidimensional_gmfrm,
            dimensions = ">= 2",
            discrimination = (:none, :global, :rater, :item, :rater_item),
            threshold_regimes = (:rating_scale, :partial_credit),
            estimation_status = :specified_only,
            public_fit = false,
            experimental_public = false,
            identification = (:confirmatory_q_mask, :rater_consistency_product_constraint, :item_step_constraints),
            note = "source-aligned preview for broader manifests and multidimensional gauge review; broad fitting remains planned",
        ),
    ]
    return view === :public ? [_public_model_ladder_row(row) for row in rows] : rows
end

function _public_model_ladder_row(row)
    availability = if row.estimation_status === :fit_supported
        (;
            stability = :stable,
            fit_available = true,
            entrypoint = "BayesianMGMFRM.fit(spec)",
            claim_scope = :minimal_mfrm_rsm_pcm,
        )
    elseif row.estimation_status === :experimental_public
        (;
            stability = :experimental,
            fit_available = true,
            entrypoint = _EXPERIMENTAL_CANONICAL_ENTRYPOINT,
            claim_scope = row.family === :mfrm ? :fixed_coefficient_multidimensional_mfrm :
                row.family === :gmfrm ? :scalar_rater_consistency_only : :fixed_q_confirmatory_only,
        )
    else
        (;
            stability = :not_supported,
            fit_available = false,
            entrypoint = missing,
            claim_scope = :specification_and_design_inspection_only,
        )
    end
    base = (;
        schema = "bayesianmgmfrm.model_ladder_row_public.v1",
        family = row.family,
        availability...,
        dimensions = row.dimensions,
        discrimination = row.discrimination,
        threshold_regimes = row.threshold_regimes,
        identification = row.identification,
        note = row.note,
    )
    if haskey(row, :spec_discrimination)
        return merge(base, (;
            spec_discrimination = row.spec_discrimination,
            kernel_discrimination = row.kernel_discrimination,
        ))
    end
    return base
end

function _release_scope_fit_surface_rows()
    gmfrm_capability = _guarded_generalized_fit_capability(:gmfrm)
    mgmfrm_capability = _guarded_generalized_fit_capability(:mgmfrm)
    return (
        (;
            surface = :minimal_mfrm_rsm_pcm,
            family = :mfrm,
            scope = :minimal_mfrm_rsm_pcm,
            status = :public_fit_supported,
            entrypoint = "fit(spec)",
            experimental_public = false,
            public_fit = true,
            claim_scope = :small_model_workflow_scaffold,
            note = "MFRM/RSM/PCM posterior fitting and report helpers for the minimal identified design",
        ),
        (;
            surface = :fixed_coefficient_multidimensional_mfrm,
            family = :mfrm,
            scope = :fixed_coefficient_multidimensional_mfrm,
            status = :guarded_experimental_public,
            entrypoint = _EXPERIMENTAL_CANONICAL_ENTRYPOINT,
            experimental_public = true,
            public_fit = true,
            claim_scope = :fixed_coefficient_multidimensional_mfrm,
            threshold_regimes = (:partial_credit,),
            spec_discrimination = (:none,),
            q_matrix_policy = :fixed_coefficients,
            anchors_allowed = false,
            validation_bias_terms_allowed = false,
            note = "unit-logit fixed-coefficient MFRM with identity latent correlation; operability does not imply scientific validation",
        ),
        (;
            surface = :correlated_fixed_coefficient_mfrm,
            family = :mfrm,
            scope = :correlated_fixed_coefficient_mfrm,
            status = :guarded_experimental_public,
            entrypoint = "BayesianMGMFRM.Experimental.fit(BayesianMGMFRM.Experimental.correlated(spec))",
            experimental_public = true,
            public_fit = true,
            claim_scope = :two_dimensional_between_item_fixed_coefficient_mfrm,
            threshold_regimes = (:partial_credit,),
            spec_discrimination = (:none,),
            q_matrix_policy = :fixed_between_item_coefficients,
            anchors_allowed = false,
            validation_bias_terms_allowed = false,
            note = "two-dimensional unit-logit MFRM with estimated population correlation; operability does not imply scientific validation",
        ),
        (;
            surface = :scalar_gmfrm_guarded_experimental,
            family = :gmfrm,
            scope = :scalar_gmfrm_fit_ready_candidate,
            status = :guarded_experimental_public,
            entrypoint = _EXPERIMENTAL_CANONICAL_ENTRYPOINT,
            legacy_entrypoint = _EXPERIMENTAL_LEGACY_ENTRYPOINT,
            experimental_public = true,
            public_fit = true,
            claim_scope = :guarded_scalar_rater_consistency_only,
            threshold_regimes = gmfrm_capability.threshold_regimes,
            spec_discrimination = gmfrm_capability.spec_discrimination,
            q_matrix_policy = :not_used,
            anchors_allowed = gmfrm_capability.allows_anchors,
            validation_bias_terms_allowed =
                gmfrm_capability.allows_validation_bias_terms,
            completed_gate = :v0_1_1_generalized_refinement,
            next_gate = :v0_1_2_fixed_q_productionization,
            note = "guarded scalar rater-consistency GMFRM, without broader generalized claims",
        ),
        (;
            surface = :fixed_q_confirmatory_mgmfrm_guarded_experimental,
            family = :mgmfrm,
            scope = :minimal_confirmatory_mgmfrm_candidate,
            status = :guarded_experimental_public,
            entrypoint = _EXPERIMENTAL_CANONICAL_ENTRYPOINT,
            legacy_entrypoint = _EXPERIMENTAL_LEGACY_ENTRYPOINT,
            experimental_public = true,
            public_fit = true,
            claim_scope = :fixed_q_confirmatory_only,
            threshold_regimes = mgmfrm_capability.threshold_regimes,
            spec_discrimination = mgmfrm_capability.spec_discrimination,
            q_matrix_policy = :fixed_confirmatory,
            anchors_allowed = mgmfrm_capability.allows_anchors,
            validation_bias_terms_allowed =
                mgmfrm_capability.allows_validation_bias_terms,
            completed_gate = :v0_1_1_generalized_refinement,
            next_gate = :v0_1_2_fixed_q_productionization,
            note = "guarded fixed-Q confirmatory MGMFRM, without model-weight or sparse-superiority claims",
        ),
    )
end

function _release_scope_status_vocabulary_rows()
    return (
        (;
            status = :supported,
            current_aliases = (:fit_supported, :public_fit_supported),
            public_fit = true,
            experimental_public = false,
            stable_public = false,
            external_validated = false,
            meaning = "ordinary fit-supported public workflow for the current release scope",
        ),
        (;
            status = :experimental_public,
            current_aliases = (
                :experimental_public,
                :guarded_experimental,
                :guarded_experimental_public,
            ),
            public_fit = true,
            experimental_public = true,
            stable_public = false,
            external_validated = false,
            meaning = "narrow guarded fit path with explicit caveats and blocked broad claims",
        ),
        (;
            status = :specified_only,
            current_aliases = (:specified_only,),
            public_fit = false,
            experimental_public = false,
            stable_public = false,
            external_validated = false,
            meaning = "manifest and preview surface only; ordinary fitting is rejected",
        ),
        (;
            status = :blocked,
            current_aliases = (
                :blocked,
                :out_of_scope,
                :not_public_fit_api,
                :not_a_public_fit_api,
                :manual_only,
            ),
            public_fit = false,
            experimental_public = false,
            stable_public = false,
            external_validated = false,
            meaning = "unsupported or claim-blocked surface",
        ),
        (;
            status = :stable_public,
            current_aliases = (:stable_public,),
            public_fit = true,
            experimental_public = false,
            stable_public = true,
            external_validated = false,
            meaning = "ordinary package claims backed by simulation, sensitivity, and reproducibility evidence",
        ),
        (;
            status = :external_validated,
            current_aliases = (:external_validated,),
            public_fit = true,
            experimental_public = false,
            stable_public = true,
            external_validated = true,
            meaning = "post-v0.2.0 external validation claims backed by known-truth R-package simulations and later real-data evidence",
        ),
    )
end

function _status_policy_label(estimation_status::Symbol;
        public_fit::Bool = estimation_status === :fit_supported,
        experimental_public::Bool = false,
        stable_public::Bool = false,
        external_validated::Bool = false)
    external_validated && return :external_validated
    stable_public && return :stable_public
    experimental_public && return :experimental_public
    public_fit && return :supported
    estimation_status === :specified_only && return :specified_only
    return :blocked
end

function _status_policy_blocked_claims(family::Symbol, status_label::Symbol)
    blocked = Symbol[
        :dff_model_effects,
        :model_weight_or_superiority,
    ]
    status_label !== :external_validated && append!(blocked, (
        :r_package_overlap_comparison,
        :real_data_validation,
        :external_validation,
    ))
    family in (:gmfrm, :mgmfrm) &&
        status_label in (:experimental_public, :specified_only, :blocked) &&
        push!(blocked, :broad_generalized_fit)
    family === :mgmfrm && push!(blocked, :sparse_mgmfrm_superiority)
    status_label in (:specified_only, :blocked) && push!(blocked, :public_fit)
    !(status_label in (:stable_public, :external_validated)) &&
        push!(blocked, :stable_public_claim)
    return Tuple(blocked)
end

function _status_policy_manifest(family::Symbol,
        estimation_status::Symbol;
        public_fit::Bool = estimation_status === :fit_supported,
        experimental_public::Bool = false,
        fit_ready::Bool = public_fit,
        stable_public::Bool = false,
        external_validated::Bool = false,
        claim_scope = missing)
    normalized_stable_public = stable_public || external_validated
    normalized_experimental_public = experimental_public && !normalized_stable_public
    normalized_public_fit =
        public_fit || normalized_experimental_public || normalized_stable_public
    normalized_fit_ready = fit_ready || normalized_public_fit
    status_label = _status_policy_label(
        estimation_status;
        public_fit = normalized_public_fit,
        experimental_public = normalized_experimental_public,
        stable_public = normalized_stable_public,
        external_validated,
    )
    return (;
        schema = "bayesianmgmfrm.status_policy.v1",
        family,
        estimation_status,
        status_label,
        public_fit = normalized_public_fit,
        experimental_public = normalized_experimental_public,
        fit_ready = normalized_fit_ready,
        stable_public = normalized_stable_public,
        external_validated,
        claim_scope,
        blocked_claims = _status_policy_blocked_claims(family, status_label),
        next_gate = status_label === :experimental_public ?
            :v0_1_2_fixed_q_productionization :
            status_label === :specified_only ?
            :promotion_review :
            status_label === :supported ?
            :ordinary_supported_workflow :
            status_label === :stable_public ?
            :post_v0_2_external_validation :
            status_label === :external_validated ?
            :maintain_external_validation_evidence :
            :scope_or_design_repair,
    )
end

function _release_scope_blocked_option_rows()
    rows = NamedTuple[]
    for row in _gmfrm_experimental_rejected_option_rows()
        push!(rows, merge((family = :gmfrm, scope = :scalar_gmfrm_fit_ready_candidate), row))
    end
    for row in _mgmfrm_experimental_rejected_option_rows()
        push!(rows, merge((family = :mgmfrm, scope = :minimal_confirmatory_mgmfrm_candidate), row))
    end
    return Tuple(rows)
end

function _release_scope_blocked_claim_rows()
    return (
        (;
            claim = :broad_generalized_fit,
            status = :blocked,
            blocker = :manual_public_scope_release_decision_required,
            note = "only the guarded scalar GMFRM and fixed-Q confirmatory MGMFRM surfaces are enabled",
        ),
        (;
            claim = :dff_model_effects,
            status = :blocked,
            blocker = :future_dff_model_effect_fit_policy,
            note = "DFF support is validation and screening only",
        ),
        (;
            claim = :model_weight_or_superiority,
            status = :blocked,
            blocker = :model_weight_or_superiority_claim_not_promoted,
            note = "WAIC, raw LOO, and K-fold helpers record diagnostics but do not authorize model-weight claims",
        ),
        (;
            claim = :sparse_mgmfrm_superiority,
            status = :blocked,
            blocker = :broader_sparse_mgmfrm_claim_scope_not_promoted,
            note = "local sparse evidence supports guarded experimentation only",
        ),
        (;
            claim = :r_package_overlap_comparison,
            status = :blocked,
            blocker = :post_v0_2_known_truth_simulation_comparison_required,
            note = "overlap comparisons with R packages are post-v0.2.0 validation evidence",
        ),
        (;
            claim = :real_data_validation,
            status = :blocked,
            blocker = :post_v0_2_external_validation_sequence_required,
            note = "real-data validation is not a v0.1.x or v0.2.0 release gate",
        ),
        (;
            claim = :external_validation,
            status = :blocked,
            blocker = :post_v0_2_external_validation_sequence_required,
            note = "external validation claims require later known-truth comparisons before real-data claims",
        ),
        (;
            claim = :publication_or_registration,
            status = :manual_only,
            blocker = :manual_publication_or_registration_by_user_only,
            note = "the package records local evidence but performs no publication or registration action",
        ),
    )
end

_release_scope_progress_evidence_scopes() = (
    :free_latent_correlation_operational_prerequisites,
    :free_latent_correlation_scientific_execution,
    :v0_1_2_ld1b_integration,
    :ld1b_scientific_execution,
)

function _release_scope_current_ld1b_integration_gate_rows()
    return (
        (gate = :fixed_q_guarded_exposure_boundary,
            gate_status = :complete,
            evidence_scope = :tracked_release_metadata),
        (gate = :ld1b_scoring_authorization_and_denominator,
            gate_status = :complete,
            evidence_scope = :tracked_frozen_contract),
        (gate = :batch_harness_seal_and_launched_attempt_retirement,
            gate_status = :complete_local_worktree,
            evidence_scope = :local_dirty_worktree),
        (gate = :terminal_public_contract_semantic_replay,
            gate_status = :complete_local_worktree,
            evidence_scope = :local_dirty_worktree),
        (gate = :canonical_single_job_worker,
            gate_status = :complete_local_worktree,
            evidence_scope = :local_dirty_worktree),
        (gate = :final_worker_source_pinning_and_identity_regeneration,
            gate_status = :complete_local_worktree,
            evidence_scope = :local_dirty_worktree),
        (gate = :bounded_canonical_smoke_on_pinned_source,
            gate_status = :complete_local_worktree,
            evidence_scope = :local_dirty_worktree),
        (gate = :independent_pinned_recovery_readiness_review,
            gate_status = :open,
            evidence_scope = :none),
        (gate = :authorized_660_job_pilot_execution_review_and_freeze,
            gate_status = :open,
            evidence_scope = :none),
    )
end

function _release_scope_progress_evidence_rows()
    free_correlation_plan = _mgmfrm_free_latent_correlation_2d_study_plan()
    free_correlation_plan.checks.passed || throw(AssertionError(
        "free-correlation progress evidence requires the validated frozen v2 plan",
    ))
    free_correlation_plan.resource_policy.initial_gradient_probe.
        short_nuts_profile_required || throw(AssertionError(
        "free-correlation progress denominator requires short-NUTS profiling",
    ))
    free_correlation_plan.resource_policy.initial_gradient_probe.
        atomic_runner_required || throw(AssertionError(
        "free-correlation progress denominator requires an atomic worker",
    ))
    free_correlation_operational_gates = (
        (gate = :passing_mcmc_free_initial_gradient_resource_profile,
            gate_status = :failed),
        (gate = :passing_bounded_short_nuts_resource_profile,
            gate_status = :pending),
        (gate = :atomic_single_unit_scientific_worker,
            gate_status = :pending),
    )
    free_correlation_operational_denominator = 1 +
        Int(free_correlation_plan.resource_policy.initial_gradient_probe.
            short_nuts_profile_required) +
        Int(free_correlation_plan.resource_policy.initial_gradient_probe.
            atomic_runner_required)
    length(free_correlation_operational_gates) ==
        free_correlation_operational_denominator || throw(AssertionError(
        "free-correlation operational denominator does not match the frozen prerequisites",
    ))
    free_correlation_operational_numerator = count(
        row -> row.gate_status === :passed,
        free_correlation_operational_gates,
    )
    free_correlation_feasibility_denominator =
        free_correlation_plan.phases.feasibility.n_units
    free_correlation_evaluation_denominator =
        free_correlation_plan.denominator_policy.n_planned_evaluation_units
    free_correlation_scientific_denominator =
        free_correlation_feasibility_denominator +
        free_correlation_evaluation_denominator
    length(free_correlation_plan.units) ==
        free_correlation_scientific_denominator || throw(AssertionError(
        "free-correlation scientific denominator does not match the frozen roster",
    ))

    ld1b_contract = local_dependence_calibration_pilot_contract()
    ld1b_fit_denominator = ld1b_contract.planning.n_fit_jobs
    ld1b_rejection_denominator =
        ld1b_contract.planning.n_pre_fit_rejection_jobs
    ld1b_scientific_denominator = ld1b_contract.planning.n_jobs
    ld1b_fit_denominator + ld1b_rejection_denominator ==
        ld1b_scientific_denominator || throw(AssertionError(
        "LD1b scientific denominator does not match its frozen routing contract",
    ))
    ld1b_integration_gates =
        _release_scope_current_ld1b_integration_gate_rows()
    ld1b_integration_numerator = count(
        row -> row.gate_status in (:complete, :complete_local_worktree),
        ld1b_integration_gates,
    )

    return (
        (family = :mgmfrm,
            scope = :free_latent_correlation_operational_prerequisites,
            evidence = :operational_gate_attainment,
            record_status = :current_progress_recorded,
            gate_status = :not_passed,
            execution_status = :mcmc_free_initial_gradient_profile_failed,
            numerator = free_correlation_operational_numerator,
            denominator = free_correlation_operational_denominator,
            attainment_percent = round(
                100 * free_correlation_operational_numerator /
                free_correlation_operational_denominator;
                digits = 1,
            ),
            denominator_kind = :conjunctive_pre_scientific_operational_gates,
            counts_toward_scientific_denominator = false,
            source_artifact =
                :mgmfrm_free_latent_correlation_2d_resource_probe_receipt,
            source_contract = free_correlation_plan.plan_id,
            gate_rows = free_correlation_operational_gates),
        (family = :mgmfrm,
            scope = :free_latent_correlation_scientific_execution,
            evidence = :scientific_execution_progress,
            record_status = :current_progress_recorded,
            gate_status = :blocked_by_operational_prerequisites,
            execution_status = :not_executed,
            numerator = 0,
            denominator = free_correlation_scientific_denominator,
            attainment_percent = round(
                100 * 0 / free_correlation_scientific_denominator;
                digits = 1,
            ),
            denominator_kind = :frozen_scientific_study_units,
            counts_toward_scientific_denominator = true,
            source_artifact =
                :mgmfrm_free_latent_correlation_2d_study_plan_v2,
            source_contract = free_correlation_plan.plan_id,
            source_artifact_sha256 = free_correlation_plan.plan_fingerprint,
            component_counts = (;
                computation_only_feasibility = (;
                    numerator = 0,
                    denominator = free_correlation_feasibility_denominator),
                recovery_evaluation = (;
                    numerator = 0,
                    denominator = free_correlation_evaluation_denominator))),
        (family = :local_dependence,
            scope = :v0_1_2_ld1b_integration,
            evidence = :integration_gate_attainment,
            record_status = :current_dirty_worktree_snapshot_recorded,
            gate_status = :partially_attained_local_worktree_only,
            execution_status =
                :bounded_verification_mcmc_nonpilot_integration_evidence_only,
            numerator = ld1b_integration_numerator,
            denominator = length(ld1b_integration_gates),
            attainment_percent = round(
                100 * ld1b_integration_numerator /
                length(ld1b_integration_gates);
                digits = 1,
            ),
            denominator_kind = :ordered_integration_acceptance_gates,
            counts_toward_scientific_denominator = false,
            source_artifact = :roadmap_current_v0_1_2_ld1b_integration_checklist,
            release_lineage_verified = false,
            scientific_numerator_contribution = 0,
            gate_rows = ld1b_integration_gates),
        (family = :local_dependence,
            scope = :ld1b_scientific_execution,
            evidence = :scientific_execution_progress,
            record_status = :current_progress_recorded,
            gate_status = :blocked_by_open_integration_gates,
            execution_status = :not_executed,
            numerator = 0,
            denominator = ld1b_scientific_denominator,
            attainment_percent = round(
                100 * 0 / ld1b_scientific_denominator;
                digits = 1,
            ),
            denominator_kind = :frozen_pilot_primary_jobs,
            counts_toward_scientific_denominator = true,
            source_artifact = :local_dependence_calibration_pilot_contract_v1,
            source_contract_schema = ld1b_contract.schema,
            component_counts = (;
                eligible_fitting_jobs = (;
                    numerator = 0,
                    denominator = ld1b_fit_denominator),
                planned_structural_rejections = (;
                    numerator = 0,
                    denominator = ld1b_rejection_denominator))),
    )
end

function _release_scope_evidence_rows()
    rows = NamedTuple[]
    for row in _gmfrm_experimental_public_evidence_rows()
        push!(rows, merge((family = :gmfrm, scope = :scalar_gmfrm_fit_ready_candidate), row))
    end
    for row in _mgmfrm_experimental_public_evidence_rows()
        push!(rows, merge((family = :mgmfrm, scope = :minimal_confirmatory_mgmfrm_candidate), row))
    end
    append!(rows, [
        (family = :all_package_surfaces,
            scope = :general_registration_readiness,
            evidence = :pre_registration_gate_available,
            status = :done,
            artifact = :scripts_pre_registration_gate),
        (family = :all_package_surfaces,
            scope = :documentation_readiness,
            evidence = :documenter_html_page_size_gate,
            status = :done,
            artifact = :docs_make),
        (family = :gmfrm,
            scope = :scalar_gmfrm_fit_ready_candidate,
            evidence = :guarded_generalized_fit_cache,
            status = :done,
            artifact = :cached_fit_experimental_gmfrm),
        (family = :mgmfrm,
            scope = :minimal_confirmatory_mgmfrm_candidate,
            evidence = :guarded_generalized_fit_cache,
            status = :done,
            artifact = :cached_fit_experimental_mgmfrm),
        (family = :all_fit_objects,
            scope = :fit_reproduction_manifest,
            evidence = :fit_reproduction_cache_identity_check,
            status = :done,
            artifact = :fit_reproduction_manifest),
        (family = :gmfrm_mgmfrm,
            scope = :v0_1_1_generalized_refinement,
            evidence = :implementation_checklist_created,
            status = :done,
            phase_status = :completed,
            historical_release = true,
            artifact = :docs_src_v0_1_1_implementation_checklist),
        (family = :all_evidence_artifacts,
            scope = :evidence_schema_policy,
            evidence = :evidence_artifact_schema_policy,
            status = :done,
            artifact = :evidence_artifact_schema_policy),
        (family = :all_package_surfaces,
            scope = :status_synchronization,
            evidence = :release_gate_check,
            status = :done,
            artifact = :release_gate_check),
        (family = :all_related_software,
            scope = :positioning_and_non_superiority,
            evidence = :related_software_capability_matrix,
            status = :done,
            artifact = :related_software_capability_matrix),
    ])
    append!(rows, _release_scope_progress_evidence_rows())
    return Tuple(rows)
end

"""
    release_scope_summary(; include_evidence = false)

Return a machine-readable summary of the package's current release scope. The
summary lists the public fit surfaces that are currently enabled, the
unsupported generalized options that remain rejected, and the broad claims that
remain blocked. Set `include_evidence = true` to include the local evidence rows
recorded by the guarded GMFRM/MGMFRM exposure manifests plus the current
fit-cache, reproduction-manifest, documentation-size, and pre-registration gate
guardrails. The evidence rows also retain separate machine-readable operational,
integration, and scientific denominators for the free-correlation and local-dependence
studies; operational or dirty-worktree attainment does not enter a
scientific numerator.

This is a release-scope guardrail, not a statistical validation result and not a
publication or registration action.
"""
function release_scope_summary(; include_evidence::Bool = false)
    fit_surfaces = _release_scope_fit_surface_rows()
    blocked_options = _release_scope_blocked_option_rows()
    blocked_claims = _release_scope_blocked_claim_rows()
    status_vocabulary = _release_scope_status_vocabulary_rows()
    evidence_policy = evidence_artifact_schema_policy(:release_scope_evidence;
        include_environment = false,
        include_cache_provenance = true,
        raw_data_status = :not_included,
        unsupported_claims = Tuple(row.claim for row in blocked_claims))
    evidence_rows = include_evidence ? _release_scope_evidence_rows() : NamedTuple[]
    development_version = string(pkgversion(@__MODULE__))
    development_phase = development_version in ("0.1.2", "0.2.0-DEV") ?
        :v0_1_2_fixed_q_productionization :
        :release_scope_phase_update_required
    return (;
        schema = "bayesianmgmfrm.release_scope_summary.v1",
        object = :release_scope_summary,
        status = :scope_recorded,
        status_vocabulary,
        evidence_artifact_schema_policy = evidence_policy,
        public_fit_surfaces = fit_surfaces,
        blocked_public_options = blocked_options,
        blocked_claims,
        evidence_rows,
        summary = (;
            n_status_vocabulary_rows = length(status_vocabulary),
            n_public_fit_surfaces = length(fit_surfaces),
            n_guarded_experimental_surfaces =
                count(row -> row.experimental_public, fit_surfaces),
            n_blocked_public_options = length(blocked_options),
            n_blocked_claims = length(blocked_claims),
            n_evidence_rows = length(evidence_rows),
            n_progress_evidence_rows = count(
                row -> row.scope in _release_scope_progress_evidence_scopes(),
                evidence_rows,
            ),
            minimal_mfrm_fit_allowed = true,
            scalar_gmfrm_guarded_fit_allowed = true,
            fixed_q_mgmfrm_guarded_fit_allowed = true,
            guarded_generalized_fit_cache_ready = true,
            fit_reproduction_cache_identity_checked = true,
            documenter_html_page_size_gate = true,
            pre_registration_gate_available = true,
            evidence_artifact_schema_policy_recorded = true,
            related_software_capability_matrix_recorded = true,
            general_registration_manual_only = true,
            broader_generalized_fit_allowed = false,
            dff_model_effects_allowed = false,
            model_weight_claims_allowed = false,
            sparse_superiority_claims_allowed = false,
            publication_or_registration_action = false,
            development_version,
            development_phase,
            development_next_gate = development_phase,
            v0_1_1_generalized_refinement_planned = true,
            v0_1_1_generalized_refinement_planned_field_semantics =
                :historical_plan_record_present,
            v0_1_1_generalized_refinement_completed = true,
            v0_1_1_generalized_refinement_status = :completed,
            next_gate = :manual_publication_or_registration_by_user_only,
        ),
    )
end
