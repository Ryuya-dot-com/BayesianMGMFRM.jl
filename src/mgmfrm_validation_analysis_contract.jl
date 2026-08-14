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

function _mgmfrm_analysis_open_decisions(protocol)
    return (
        (;
            code = :final_primary_grid_cells,
            current_state = protocol.design_domain.final_sample_size_cells,
            required_resolution =
                :freeze_exact_cells_after_bounded_short_nuts_and_resource_review,
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
scientific thresholds.
"""
function mgmfrm_validation_analysis_contract()
    protocol = mgmfrm_validation_protocol()
    execution_design = _mgmfrm_validation_execution_design_contract(protocol)
    fixed_components = _mgmfrm_analysis_fixed_components()
    open_decisions = _mgmfrm_analysis_open_decisions(protocol)
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
            mcmc_executed = false,
            bounded_short_nuts_probe_required = true,
            gradient_timing_may_freeze_final_resource_policy = false,
            values_may_define_scientific_thresholds = false,
            values_may_rank_backends = false,
            values_are_validation_evidence = false,
        ),
        next_work_order = (
            :run_initial_gradient_resource_probe,
            :run_bounded_short_nuts_resource_probe,
            :freeze_primary_grid_replications_and_resource_caps,
            :obtain_independent_scientific_threshold_review,
            :freeze_analysis_profile,
            :implement_attempt_complete_analysis_executor,
            :start_fresh_seed_evaluation,
        ),
        claim_scope = :planning_contract_not_validation_evidence,
    )
end
