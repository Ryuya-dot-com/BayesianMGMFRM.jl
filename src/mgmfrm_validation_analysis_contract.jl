# Non-executing Stage-A analysis contract for the fixed-Q MGMFRM candidate.

const _MGMFRM_ANALYSIS_PROFILE = :fixed_q_mgmfrm_analysis_v1_draft
const _MGMFRM_ANALYSIS_TERMINAL_STATUSES = (
    :generation_failed,
    :pre_fit_rejected,
    :fit_failed,
    :diagnostic_failed,
    :scoring_failed,
    :completed,
)

function _mgmfrm_analysis_fixed_components()
    return (
        (code = :claim_and_identification,
            state = :fixed_in_stage_a_draft,
            source = :claim_target_and_identification),
        (code = :estimands,
            state = :fixed_in_stage_a_draft,
            source = :estimands_and_estimand_policy),
        (code = :scale_harmonization,
            state = :fixed_in_stage_a_draft,
            source = :scale_harmonization),
        (code = :interval_policy,
            state = :fixed_in_stage_a_draft,
            source = :intervals),
        (code = :fixed_q_design_scope,
            state = :fixed_in_stage_a_draft,
            source = :design_domain),
        (code = :prior_regimes,
            state = :fixed_in_stage_a_draft,
            source = :priors),
        (code = :sampler_controls,
            state = :fixed_in_stage_a_draft,
            source = :sampler),
        (code = :computational_gate,
            state = :fixed_in_stage_a_draft,
            source = :computation_gate),
        (code = :backend_conformance_subset,
            state = :fixed_in_stage_a_draft,
            source = :backends),
        (code = :attempt_denominator_and_seed_policy,
            state = :fixed_in_stage_a_draft,
            source = :failure_accounting_and_seeds),
        (code = :heldout_prediction_design,
            state = :fixed_before_evaluation,
            source = :mgmfrm_validation_execution_design_contract),
        (code = :retry_and_remediation_design,
            state = :fixed_before_evaluation,
            source = :mgmfrm_validation_execution_design_contract),
        (code = :stratified_sensitivity_cells,
            state = :fixed_before_evaluation,
            source = :mgmfrm_validation_execution_design_contract),
    )
end

function _mgmfrm_analysis_open_decisions(protocol, primary_grid_candidates)
    return (
        (;
            code = :final_primary_grid_cells,
            current_state = (;
                protocol_state =
                    protocol.design_domain.final_sample_size_cells,
                n_candidate_cells = primary_grid_candidates.summary.
                    n_candidate_cells,
                cells_frozen = primary_grid_candidates.cells_frozen,
                resource_envelope_covers_all_candidates =
                    primary_grid_candidates.summary.
                        current_resource_envelope_covers_all_candidates,
                primary_generator_implemented =
                    primary_grid_candidates.summary.
                        primary_four_category_generator_implemented,
                staged_review_status =
                    primary_grid_candidates.staged_review.status,
                n_provisional_staged_review_cells =
                    primary_grid_candidates.staged_review.
                        n_provisional_cells,
                staged_review_cells_frozen =
                    primary_grid_candidates.staged_review.cells_frozen,
            ),
            required_resolution =
                :freeze_exact_cells_after_resource_review,
            pilot_role = :runtime_and_operability_only,
            blocks_execution = true,
        ),
        (;
            code = :evaluation_replications,
            current_state = protocol.design_domain.evaluation_replications,
            required_resolution =
                :freeze_from_monte_carlo_precision_and_resource_review,
            pilot_role = :runtime_and_operability_only,
            blocks_execution = true,
        ),
        (;
            code = :analysis_resource_policy,
            current_state = :not_declared,
            required_resolution =
                :freeze_job_batch_runtime_memory_and_storage_caps,
            pilot_role = :runtime_and_operability_only,
            blocks_execution = true,
        ),
        (;
            code = :scientific_thresholds_and_independent_review,
            current_state =
                protocol.scientific_decision.primary_recovery_and_prediction_rules,
            required_resolution =
                :freeze_recovery_prediction_and_decision_rules_after_independent_review,
            pilot_role = :must_not_define_scientific_thresholds,
            blocks_execution = true,
        ),
    )
end

"""
    mgmfrm_validation_analysis_contract()

Return the non-executing analysis-profile contract for the narrow fixed-Q
MGMFRM validation program. The result separates Stage-A components that are
already specified from decisions that still block fresh-seed evaluation.

The contract fixes the four-chain sampler controls, computational diagnostics,
estimands, interval and scale policies, prior regimes, held-out design,
retry/remediation rules, stratified sensitivity cells, backend-conformance
cells, terminal statuses, seed rules, and all-attempt denominator. It does not
choose unresolved sample-size cells, replication counts, resource caps, or
scientific thresholds.

This function generates no data, runs no sampler, and cannot authorize an
analysis. Runtime pilots may inform resource choices only; they cannot set
scientific thresholds. The provisional staged primary-grid review narrows the
next decisions but does not freeze cells or require automatic short-NUTS
progression.
"""
function mgmfrm_validation_analysis_contract()
    protocol = mgmfrm_validation_protocol()
    execution_design = _mgmfrm_validation_execution_design_contract(protocol)
    fixed_components = _mgmfrm_analysis_fixed_components()
    primary_grid_candidates = execution_design.primary_grid_candidates
    open_decisions = _mgmfrm_analysis_open_decisions(
        protocol,
        primary_grid_candidates,
    )
    blocking_decisions = Tuple(
        row.code for row in open_decisions if row.blocks_execution)
    sampler = merge(protocol.sampler, (;
        total_warmup_transitions =
            protocol.sampler.chains * protocol.sampler.warmup_per_chain,
        total_retained_draws =
            protocol.sampler.chains * protocol.sampler.retained_per_chain,
    ))
    response_stress_source_cases = length(mgmfrm_response_stress_plan())

    return (;
        schema =
            "bayesianmgmfrm.mgmfrm_validation_analysis_contract.v1",
        object = :mgmfrm_validation_analysis_contract,
        profile = _MGMFRM_ANALYSIS_PROFILE,
        status = :analysis_contract_execution_blocked,
        contract_frozen = false,
        execution_allowed = false,
        evaluation_started = false,
        protocol_schema = protocol.schema,
        protocol_status = protocol.status,
        claim_target = protocol.claim_target,
        identification = protocol.identification,
        estimands = protocol.estimands,
        estimand_policy = protocol.estimand_policy,
        scale_harmonization = protocol.scale_harmonization,
        intervals = protocol.intervals,
        design_domain = protocol.design_domain,
        sampler,
        computation_gate = protocol.computation_gate,
        priors = protocol.priors,
        backends = protocol.backends,
        seeds = protocol.seeds,
        scoring = protocol.scoring,
        scientific_decision = protocol.scientific_decision,
        execution_design,
        attempts = (;
            unit = (:scenario, :replication, :model, :backend, :prior_regime),
            initial_status = :not_started,
            terminal_statuses = _MGMFRM_ANALYSIS_TERMINAL_STATUSES,
            exactly_one_terminal_status_per_planned_attempt = true,
            finalization_requires_zero_not_started = true,
            denominator = protocol.failure_accounting.denominator,
            successful_fits_only_summary_allowed =
                protocol.failure_accounting.successful_fits_only_summary_allowed,
            original_error_preserved =
                protocol.failure_accounting.original_error_preserved,
            primary_attempt = execution_design.retry.primary_attempt,
            primary_outcome_overwritable_by_retry =
                execution_design.retry.primary_outcome_overwritable,
            retry_role = execution_design.retry.remediation_role,
            completed_implies_computational_pass = false,
            completed_implies_scientific_pass = false,
            wiring_function = :mgmfrm_response_stress_fit_attempts,
            wiring_profile = :wiring_smoke,
            analysis_executor = :not_implemented,
        ),
        workload = (;
            source_sample_size_candidates =
                protocol.design_domain.source_sample_size_candidates,
            final_primary_grid_cells =
                protocol.design_domain.final_sample_size_cells,
            primary_grid_candidate_cells =
                primary_grid_candidates.summary.n_candidate_cells,
            primary_grid_candidate_observation_range = (
                primary_grid_candidates.summary.
                    minimum_expected_observations,
                primary_grid_candidates.summary.
                    maximum_expected_observations,
            ),
            primary_grid_candidates_above_current_short_nuts_bound =
                primary_grid_candidates.summary.
                    n_above_current_short_nuts_probe_bound,
            primary_grid_resource_envelope_complete =
                primary_grid_candidates.summary.
                    current_resource_envelope_covers_all_candidates,
            primary_four_category_generator_implemented =
                primary_grid_candidates.summary.
                    primary_four_category_generator_implemented,
            provisional_primary_grid_stages =
                length(primary_grid_candidates.staged_review.stages),
            provisional_primary_grid_cells =
                primary_grid_candidates.staged_review.n_provisional_cells,
            provisional_primary_grid_supports_factorial_inference =
                primary_grid_candidates.staged_review.limitations.
                    full_factorial_inference_supported,
            evaluation_replications =
                protocol.design_domain.evaluation_replications,
            response_stress_source_cases,
            backend_conformance_cells = length(
                protocol.backends.reference_subset.paired_stratum_cells),
            prior_response_sensitivity_cells =
                execution_design.sensitivity.n_prior_response_cells,
            structure_comparison_cells =
                execution_design.sensitivity.n_structure_comparison_cells,
            sensitivity_role_cells =
                execution_design.sensitivity.n_sensitivity_role_cells,
            exact_analysis_attempts =
                :not_computable_until_grid_subsets_and_replications_are_frozen,
            full_cartesian_expansion_allowed = false,
        ),
        fixed_components,
        open_decisions,
        readiness = (;
            fixed_component_count = length(fixed_components),
            open_decision_count = length(open_decisions),
            blocking_decisions,
            n_blockers = length(blocking_decisions),
            protocol_frozen = protocol.protocol_frozen,
            scientific_thresholds_frozen =
                protocol.scientific_decision.thresholds_frozen,
            analysis_executor_implemented = false,
            execution_allowed = false,
        ),
        pilot_policy = (;
            role = :runtime_and_operability_only,
            function_name = :mgmfrm_validation_resource_probe,
            initial_gradient_probe_implemented = true,
            initial_gradient_probe_executed = false,
            initial_gradient_memory_preflight_required = true,
            short_nuts_function_name =
                :mgmfrm_validation_short_nuts_resource_probe,
            short_nuts_probe_implemented = true,
            short_nuts_probe_executed = false,
            isolated_function_name =
                :mgmfrm_validation_isolated_resource_probe,
            isolated_probe_implemented = true,
            isolated_probe_executed = false,
            isolated_review_function_name =
                :mgmfrm_validation_isolated_resource_review,
            isolated_review_implemented = true,
            mcmc_executed = false,
            short_nuts_execution_required = false,
            additional_short_nuts_execution_automatically_required = false,
            new_sampling_requires_a_cell_specific_resource_decision = true,
            gradient_timing_may_freeze_final_resource_policy = false,
            values_may_define_scientific_thresholds = false,
            values_may_rank_backends = false,
            values_are_validation_evidence = false,
        ),
        next_work_order = (
            :review_provisional_stage_contrasts_and_existing_resource_records,
            :decide_the_narrowest_scientifically_defensible_stage,
            :review_later_stage_resource_feasibility_without_automatic_sampling,
            :freeze_primary_grid_replications_and_resource_caps,
            :obtain_independent_scientific_threshold_review,
            :freeze_analysis_profile,
            :implement_attempt_complete_analysis_executor,
            :start_fresh_seed_evaluation,
        ),
        claim_scope = :planning_contract_not_validation_evidence,
    )
end
