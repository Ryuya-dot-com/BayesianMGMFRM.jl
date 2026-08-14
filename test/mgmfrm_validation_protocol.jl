using Test
using BayesianMGMFRM

@testset "Stage-A MGMFRM validation protocol" begin
    protocol = mgmfrm_validation_protocol()
    @test protocol.schema ==
        "bayesianmgmfrm.mgmfrm_validation_protocol.v1"
    @test protocol.status === :stage_a_draft_execution_blocked
    @test !protocol.protocol_frozen
    @test !protocol.evaluation_started
    @test protocol.claim_scope === :planning_contract_not_validation_evidence

    target = protocol.claim_target
    @test target.primary_branch === :mgmfrm_fixed_q_between_item_gpcm
    @test target.dimensions == 2
    @test target.q_policy ===
        :fixed_confirmatory_with_pure_items_per_dimension
    @test target.latent_correlation === :identity_fixed
    @test target.source_scale_constant == 1.7
    @test target.normal_ogive_minimax_reference_constant == 1.702
    @test target.promotion_domain === :between_item_only
    @test :mixed_between_and_within_item in target.boundary_evidence
    @test :free_latent_correlation in target.excluded
    @test :fitted_dff_testlet_halo_or_rater_task_effects in target.excluded

    source = protocol.source_anchor
    @test source.source === :uto_2021
    @test source.equation == 6
    @test source.parameter_recovery_axes.persons == (50, 100)
    @test source.parameter_recovery_axes.items == (5, 15)
    @test source.parameter_recovery_axes.raters == (5, 15)
    @test source.parameter_recovery_axes.dimensions == (1, 2, 3)
    @test source.parameter_recovery_axes.replications == 30
    @test source.category_count == 4
    @test source.sparse_design_anchor.raters_per_person == 2
    @test source.overlap_with_package === :partial_not_exact
    @test :source_unrestricted_item_dimension_loading_surface in
        source.nonoverlap

    identification = protocol.identification
    @test !identification.likelihood_only_identification_claim
    @test identification.prior_supplied_location_scale.person_ability ===
        :standard_normal_by_dimension
    @test !identification.source_dimension_sorting_required

    primary_blocks = Set(row.block for row in protocol.estimands
        if row.priority === :primary)
    @test primary_blocks == Set((
        :item_difficulty,
        :rater_severity,
        :item_dimension_discrimination,
        :rater_consistency,
        :item_steps,
        :prediction,
    ))
    @test protocol.estimand_policy.primary_inference_units ==
        (:identified_parameter_block, :heldout_response)
    @test protocol.estimand_policy.person_ability_role ===
        :secondary_no_hard_individual_recovery_gate
    @test !protocol.estimand_policy.raw_parameter_pooling_across_incompatible_scales
    @test protocol.scale_harmonization.primary.constant == 1.7
    @test protocol.scale_harmonization.normal_ogive_reference.constant == 1.702
    @test protocol.scale_harmonization.normal_ogive_reference.likelihood_refit_status ===
        :not_currently_executable
    @test !protocol.scale_harmonization.normal_ogive_reference.required_for_primary_promotion
    @test protocol.intervals.primary ==
        (probability = 0.90, kind = :equal_tailed)
    @test protocol.intervals.hdi_role ===
        :secondary_sensitivity_not_primary_coverage

    design = protocol.design_domain
    @test :dense_fully_crossed in design.required_axes
    @test :connected_sparse_systematic_link in design.required_axes
    @test :q_misspecification in design.required_axes
    @test design.categories == 4
    @test design.sparse_raters_per_person == 2
    @test design.q_scope.primary ===
        :pure_between_item_one_active_dimension_per_item
    @test design.q_scope.misspecification ==
        (:omit_true_active_dimension, :add_false_active_dimension)
    @test design.sparse_design.connectivity_and_location_rank_must_pass_before_fit
    @test design.sparse_design.disconnected_negative_control ===
        :must_be_rejected_before_fit
    @test :unused_interior_category_3 in
        design.response_pattern_stress.scenarios
    @test design.response_pattern_stress.dense_combined_pattern_excluded
    @test design.response_pattern_stress.sampler_free_preflight ===
        :ordinal_response_pattern_audit
    @test design.response_pattern_stress.plan_function ===
        :mgmfrm_response_stress_plan
    @test design.response_pattern_stress.generator_function ===
        :simulate_mgmfrm_response_stress
    @test design.response_pattern_stress.attempt_preflight_function ===
        :mgmfrm_response_stress_preflight
    @test design.response_pattern_stress.fit_attempt_function ===
        :mgmfrm_response_stress_fit_attempts
    @test design.response_pattern_stress.fit_attempt_profile ===
        :wiring_smoke_only
    @test design.response_pattern_stress.fit_attempt_default_resource_bound == 1
    @test design.response_pattern_stress.fit_attempt_terminal_statuses == (
        :generation_failed,
        :pre_fit_rejected,
        :fit_failed,
        :diagnostic_failed,
        :completed,
    )
    @test design.response_pattern_stress.analysis_profile ===
        :draft_contract_implemented_execution_blocked
    @test design.response_pattern_stress.analysis_contract_function ===
        :mgmfrm_validation_analysis_contract
    @test design.response_pattern_stress.global_single_category_action ===
        :reject_before_fit
    @test design.response_pattern_stress.no_automatic_scientific_failure_from_pattern_alone
    @test design.response_pattern_stress.repeated_fit_evidence === :not_run
    @test design.response_pattern_stress.generation_status ===
        :sampler_free_generator_implemented
    @test design.response_pattern_stress.fit_and_diagnostic_attempt_status ===
        :bounded_wiring_smoke_implemented_without_convergence_or_scientific_scoring
    @test design.anchor_proportion_axis ===
        :excluded_until_anchor_fit_contract_exists

    regimes = protocol.priors.regimes
    @test Tuple(row.regime for row in regimes) == (
        :implementation_reference,
        :source_aligned,
        :strong_regularizing,
    )
    @test all(row.fit_executable for row in regimes)
    @test all(row.prior_predictive_executable for row in regimes)
    @test all(row.executable for row in regimes)
    @test only(row for row in regimes
        if row.regime === :implementation_reference).
            scales.log_discrimination_sd == 0.5
    @test only(row for row in regimes
        if row.regime === :source_aligned).
            scales.log_discrimination_sd == 1.0
    @test protocol.priors.actual_refits_required
    @test !protocol.priors.importance_reweighting_is_final_evidence
    @test protocol.priors.sensitivity_contract.full_primary_grid_regime ===
        :implementation_reference
    @test protocol.priors.sensitivity_contract.all_regime_refit_scope ===
        :predeclared_stratified_subset_not_full_cartesian
    @test protocol.priors.sensitivity_contract.required_prior_regimes == (
        :implementation_reference, :source_aligned, :strong_regularizing)
    @test !protocol.priors.sensitivity_contract.select_regime_from_pilot_results

    @test protocol.sampler.chains == 4
    @test protocol.sampler.warmup_per_chain == 1000
    @test protocol.sampler.retained_per_chain == 1000
    @test protocol.sampler.thinning == 1
    @test protocol.sampler.target_accept == 0.90
    @test protocol.backends.primary === :advancedhmc
    @test protocol.backends.reference === :cmdstan
    @test !protocol.backends.speed_ranking_allowed
    @test :connected_sparse_systematic_link in
        protocol.backends.reference_subset.required_design_strata
    @test protocol.backends.reference_subset.selection ===
        :five_predeclared_paired_stratum_cells_not_full_cartesian
    @test length(protocol.backends.reference_subset.paired_stratum_cells) == 5
    @test Set(row.response for row in
        protocol.backends.reference_subset.paired_stratum_cells) == Set((
            :regular_all_categories,
            :unused_interior_category_3,
            :all_maximum_person,
            :all_minimum_rater,
        ))
    @test protocol.backends.disagreement_action ===
        :investigate_parameterization_or_implementation_before_scientific_scoring

    @test protocol.execution_design.function_name ===
        :mgmfrm_validation_execution_design_contract
    @test protocol.execution_design.primary_heldout_target ===
        :conditional_existing_level_heldout_response
    @test protocol.execution_design.primary_heldout_folds == 5
    @test !protocol.execution_design.retry_primary_outcome_overwritable
    @test protocol.execution_design.n_exact_sensitivity_role_cells == 24
    @test !protocol.execution_design.role_cells_are_fit_attempt_count
    @test protocol.execution_design.resource_probe_function ===
        :mgmfrm_validation_resource_probe
    @test protocol.execution_design.primary_grid_candidate_function ===
        :mgmfrm_validation_primary_grid_candidates
    @test protocol.execution_design.primary_grid_generator_function ===
        :simulate_mgmfrm_validation_primary_candidate
    @test protocol.execution_design.primary_grid_preflight_function ===
        :mgmfrm_validation_primary_grid_preflight
    @test protocol.execution_design.primary_gradient_resource_plan_function ===
        :mgmfrm_validation_primary_resource_plan
    @test protocol.execution_design.primary_gradient_resource_plan ===
        :implemented_sequential_execution_pending
    @test protocol.execution_design.primary_short_nuts_resource_adapter ===
        :implemented_execution_memory_guarded
    @test protocol.execution_design.primary_grid_candidates ===
        :implemented_generation_preflight_execution_blocked
    @test protocol.execution_design.initial_gradient_resource_probe ===
        :implemented_explicit_execution_memory_guarded
    @test protocol.execution_design.bounded_short_nuts_resource_probe ===
        :implemented_explicit_execution_memory_guarded
    @test protocol.execution_design.isolated_resource_probe_function ===
        :mgmfrm_validation_isolated_resource_probe
    @test protocol.execution_design.isolated_resource_probe ===
        :implemented_for_stress_and_primary_parent_child_memory_guarded
    @test protocol.execution_design.isolated_resource_review_function ===
        :mgmfrm_validation_isolated_resource_review
    @test protocol.execution_design.isolated_resource_review ===
        :implemented_threshold_free_manual_progression_only
    @test protocol.execution_design.scaled_resource_plan_function ===
        :mgmfrm_validation_scaled_resource_plan
    @test protocol.execution_design.scaled_resource_plan ===
        :implemented_sequential_execution_not_started
    @test protocol.execution_design.peak_memory_attribution ===
        :dedicated_worker_surface_implemented_execution_pending

    @test protocol.failure_accounting.denominator ===
        :all_predeclared_attempts
    @test !protocol.failure_accounting.successful_fits_only_summary_allowed
    @test protocol.failure_accounting.typed_terminal_status_required
    @test protocol.scoring.predictive_recovery.function_name ===
        :mgmfrm_predictive_recovery_score
    @test protocol.scoring.predictive_recovery.known_truth_required
    @test !protocol.scoring.predictive_recovery.thresholds_applied
    @test protocol.scoring.decision_stability.function_name ===
        :mgmfrm_decision_stability_score
    @test protocol.scoring.decision_stability.caller_supplied_cutpoints
    @test !protocol.scoring.decision_stability.thresholds_applied
    @test protocol.computation_gate.max_rank_normalized_rhat == 1.01
    @test protocol.computation_gate.min_bulk_ess == 400.0
    @test protocol.computation_gate.max_divergences == 0

    @test !protocol.scientific_decision.thresholds_frozen
    @test !protocol.scientific_decision.pilot_values_may_define_thresholds
    @test !protocol.scientific_decision.complexity_increase_is_automatic
    @test protocol.scientific_decision.criterion_layers.structural ===
        :prefit_pass_or_reject_without_sampling
    @test protocol.scientific_decision.averaging_cannot_hide_failed_stress_stratum
    @test !protocol.scientific_decision.stress_pattern_presence_is_automatic_failure
    @test !protocol.readiness.stage_a_complete
    @test protocol.readiness.n_blockers == 2
    @test Set(protocol.readiness.blockers) == Set((
        :fresh_seed_attempt_complete_evaluation_runner,
        :independent_scientific_threshold_review,
    ))
    @test protocol.readiness.completed_enablers.
        attempt_complete_sampler_free_preflight === :implemented
    @test protocol.readiness.completed_enablers.
        bounded_fit_and_diagnostic_wiring_smoke === :implemented
    @test protocol.readiness.completed_enablers.
        fit_and_diagnostic_attempt_phases ===
        :wiring_smoke_implemented_analysis_pending
    @test protocol.readiness.completed_enablers.
        attempt_complete_analysis_contract ===
        :implemented_execution_blocked
    @test protocol.readiness.completed_enablers.
        heldout_retry_and_sensitivity_design ===
        :frozen_before_evaluation
    @test protocol.readiness.completed_enablers.
        primary_grid_candidate_surface ===
        :implemented_generation_preflight_execution_blocked
    @test protocol.readiness.completed_enablers.
        primary_gradient_resource_plan_surface ===
        :implemented_sequential_execution_pending
    @test protocol.readiness.completed_enablers.
        primary_short_nuts_resource_adapter_surface ===
        :implemented_execution_memory_guarded
    @test protocol.readiness.completed_enablers.
        initial_gradient_resource_probe_surface ===
        :implemented_execution_memory_guarded
    @test protocol.readiness.completed_enablers.
        bounded_short_nuts_resource_probe_surface ===
        :implemented_execution_memory_guarded
    @test protocol.readiness.completed_enablers.
        scaled_resource_plan_surface ===
        :implemented_sequential_execution_pending
    @test protocol.readiness.completed_enablers.
        isolated_resource_probe_surface ===
        :implemented_execution_pending
    @test protocol.readiness.completed_enablers.
        isolated_resource_review_surface ===
        :implemented_threshold_free
    @test protocol.readiness.completed_enablers.
        attempt_complete_analysis_profile ===
        :draft_contract_implemented_execution_blocked
end
