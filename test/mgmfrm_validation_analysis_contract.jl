using Test
using BayesianMGMFRM

@testset "MGMFRM validation analysis contract" begin
    contract = mgmfrm_validation_analysis_contract()

    @test contract.schema ==
        "bayesianmgmfrm.mgmfrm_validation_analysis_contract.v1"
    @test contract.object === :mgmfrm_validation_analysis_contract
    @test contract.profile === :fixed_q_mgmfrm_analysis_v1_draft
    @test contract.status === :analysis_contract_execution_blocked
    @test !contract.contract_frozen
    @test !contract.execution_allowed
    @test !contract.evaluation_started
    @test contract.claim_scope === :planning_contract_not_validation_evidence

    @test contract.sampler.chains == 4
    @test contract.sampler.warmup_per_chain == 1000
    @test contract.sampler.retained_per_chain == 1000
    @test contract.sampler.thinning == 1
    @test contract.sampler.total_warmup_transitions == 4000
    @test contract.sampler.total_retained_draws == 4000
    @test contract.sampler.target_accept == 0.90
    @test contract.sampler.max_depth == 12

    @test contract.attempts.terminal_statuses == (
        :generation_failed,
        :pre_fit_rejected,
        :fit_failed,
        :diagnostic_failed,
        :scoring_failed,
        :completed,
    )
    @test contract.attempts.initial_status === :not_started
    @test contract.attempts.exactly_one_terminal_status_per_planned_attempt
    @test contract.attempts.finalization_requires_zero_not_started
    @test contract.attempts.denominator === :all_predeclared_attempts
    @test !contract.attempts.successful_fits_only_summary_allowed
    @test contract.attempts.original_error_preserved
    @test contract.attempts.primary_attempt == 1
    @test !contract.attempts.primary_outcome_overwritable_by_retry
    @test contract.attempts.retry_role === :separate_nonpromotional_record
    @test !contract.attempts.completed_implies_computational_pass
    @test !contract.attempts.completed_implies_scientific_pass
    @test contract.attempts.analysis_executor === :not_implemented

    @test contract.design_domain.q_scope.primary ===
        :pure_between_item_one_active_dimension_per_item
    @test contract.identification.prior_supplied_location_scale.person_ability ===
        :standard_normal_by_dimension
    @test contract.scoring.predictive_recovery.known_truth_required
    @test !contract.scoring.predictive_recovery.thresholds_applied
    @test !contract.scientific_decision.thresholds_frozen

    @test contract.workload.response_stress_source_cases == 9
    @test contract.workload.backend_conformance_cells == 5
    @test contract.workload.prior_response_sensitivity_cells == 10
    @test contract.workload.structure_comparison_cells == 9
    @test contract.workload.sensitivity_role_cells == 24
    @test contract.workload.final_primary_grid_cells ===
        :pending_bounded_short_nuts_and_resource_review
    @test contract.workload.evaluation_replications ===
        :pending_coverage_precision_review
    @test !contract.workload.full_cartesian_expansion_allowed

    @test contract.readiness.fixed_component_count == 13
    @test contract.readiness.open_decision_count == 4
    @test contract.readiness.n_blockers == 4
    @test !contract.readiness.protocol_frozen
    @test !contract.readiness.scientific_thresholds_frozen
    @test !contract.readiness.analysis_executor_implemented
    @test !contract.readiness.execution_allowed
    @test Set(contract.readiness.blocking_decisions) == Set((
        :final_primary_grid_cells,
        :evaluation_replications,
        :analysis_resource_policy,
        :scientific_thresholds_and_independent_review,
    ))
    @test all(row -> row.blocks_execution, contract.open_decisions)

    @test contract.pilot_policy.role === :runtime_and_operability_only
    @test !contract.pilot_policy.values_may_define_scientific_thresholds
    @test !contract.pilot_policy.values_may_rank_backends
    @test !contract.pilot_policy.values_are_validation_evidence
    @test contract.pilot_policy.initial_gradient_probe_implemented
    @test contract.pilot_policy.short_nuts_probe_implemented
    @test !contract.pilot_policy.short_nuts_probe_executed
    @test contract.pilot_policy.short_nuts_function_name ===
        :mgmfrm_validation_short_nuts_resource_probe
    @test !contract.pilot_policy.mcmc_executed
    @test contract.pilot_policy.short_nuts_execution_required
    @test !contract.pilot_policy.
        gradient_timing_may_freeze_final_resource_policy
    @test contract.execution_design.design_choices_frozen
    @test contract.execution_design.sensitivity.n_sensitivity_role_cells == 24
    @test first(contract.next_work_order) ===
        :run_initial_gradient_resource_probe
    @test contract.next_work_order[2] ===
        :run_memory_guarded_bounded_short_nuts_resource_probe
    @test :run_scaled_resource_cells_sequentially in
        contract.next_work_order
    @test :review_process_isolated_peak_rss in contract.next_work_order
    @test last(contract.next_work_order) === :start_fresh_seed_evaluation
end
