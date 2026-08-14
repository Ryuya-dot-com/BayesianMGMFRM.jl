using Random
using Test
using BayesianMGMFRM

@testset "MGMFRM validation execution design" begin
    contract = mgmfrm_validation_execution_design_contract()

    @test contract.schema ==
        "bayesianmgmfrm.mgmfrm_validation_execution_design_contract.v1"
    @test contract.object ===
        :mgmfrm_validation_execution_design_contract
    @test contract.status === :design_choices_frozen_execution_not_started
    @test contract.design_choices_frozen
    @test !contract.execution_started
    @test contract.claim_scope === :design_contract_not_validation_evidence

    heldout = contract.heldout
    @test heldout.target ===
        :conditional_existing_level_heldout_response
    @test heldout.primary_metric === :heldout_log_score
    @test heldout.plan_function === :kfold_plan
    @test heldout.preflight_function === :kfold_plan_diagnostics
    @test heldout.refit_function === :kfold_refit
    @test heldout.k == 5
    @test heldout.heldout_unit === :observation
    @test isnothing(heldout.group_by)
    @test heldout.shuffle
    @test heldout.nominal_training_fraction == 0.80
    @test heldout.preflight_facets === :all
    @test heldout.failed_preflight_status === :pre_fit_rejected
    @test !heldout.q_selection_uses_heldout_responses
    @test !heldout.prior_selection_uses_heldout_responses
    @test !heldout.scientific_threshold_selection_uses_heldout_responses
    @test :new_person_generalization in heldout.unsupported_targets
    @test heldout.execution_status ===
        :public_plan_preflight_and_refit_path_available

    for design in (:dense_fully_crossed,
            :connected_sparse_systematic_link)
        source_row = only(mgmfrm_response_stress_plan(
            design_strata = (design,),
            response_patterns = (:regular_all_categories,),
        ))
        case = simulate_mgmfrm_response_stress(source_row)
        fold_plan = kfold_plan(
            case.spec;
            k = heldout.k,
            group_by = heldout.group_by,
            shuffle = heldout.shuffle,
            rng = MersenneTwister(20260815),
        )
        preflight = kfold_plan_diagnostics(
            case.spec,
            fold_plan;
            facets = heldout.preflight_facets,
        )
        @test fold_plan.n_folds == 5
        @test preflight.passed
        @test preflight.n_blocking_rows == 0
    end

    retry = contract.retry
    @test !retry.automatic_retry_allowed
    @test retry.primary_attempt == 1
    @test !retry.primary_outcome_overwritable
    @test !retry.primary_denominator_changed_by_remediation
    @test retry.maximum_sampler_remediations_per_primary_attempt == 1
    @test retry.sampler_remediation_eligible_conditions == (
        :fit_failed,
        :completed_computational_gate_failed,
    )
    @test retry.sampler_remediation_controls.target_accept == 0.95
    @test retry.sampler_remediation_controls.max_depth == 14
    @test retry.sampler_remediation_controls.unchanged ==
        (:data, :folds, :model, :q, :prior)
    @test retry.maximum_postprocessing_recomputations_per_primary_attempt == 1
    @test retry.postprocessing_recomputation_eligible_statuses ==
        (:diagnostic_failed, :scoring_failed)
    @test retry.postprocessing_reuses_retained_fit
    @test :pre_fit_rejected in retry.ineligible_conditions
    @test !retry.remediation_can_rescue_primary_scientific_result

    sensitivity = contract.sensitivity
    @test sensitivity.n_primary_response_cells == 9
    @test sensitivity.n_prior_response_cells == 10
    @test sensitivity.n_structure_comparison_cells == 9
    @test sensitivity.n_backend_conformance_cells == 5
    @test sensitivity.n_sensitivity_role_cells == 24
    @test sensitivity.role_cells_are_not_fit_attempts
    @test sensitivity.reuse_identical_fits_across_roles
    @test !sensitivity.raw_cross_family_discrimination_comparison_allowed
    @test !sensitivity.scientific_thresholds_applied

    @test Set(row.prior_regime for row in
        sensitivity.prior_response_cells) ==
        Set((:source_aligned, :strong_regularizing))
    @test Set(row.design for row in sensitivity.prior_response_cells) ==
        Set((:dense_fully_crossed, :connected_sparse_systematic_link))
    @test Set(row.response_pattern for row in
        sensitivity.prior_response_cells) == Set((
        :regular_all_categories,
        :unused_interior_category_3,
        :all_maximum_person,
        :all_minimum_rater,
        :combined_unused_category_and_boundary_patterns,
    ))
    @test length(unique(row.cell_id for row in
        sensitivity.prior_response_cells)) == 10

    structure = sensitivity.structure_comparison_cells
    @test count(row -> row.axis === :fixed_q_boundary, structure) == 2
    @test count(row -> row.axis === :q_misspecification, structure) == 2
    @test count(row ->
        row.axis === :unidimensional_baseline_comparison,
        structure) == 4
    negative = only(row for row in structure
        if row.axis === :structural_negative_control)
    @test negative.expected_role === :must_be_rejected_before_fit
    @test negative.fitted_q ===
        :all_items_crossload_two_dimensions_aliased_columns
    @test all(row -> :mfrm_partial_credit in row.candidate_models,
        filter(row -> row.axis === :unidimensional_baseline_comparison,
            structure))
    @test all(row -> :mgmfrm_fixed_q_between_item_gpcm in
            row.candidate_models,
        filter(row -> row.axis === :unidimensional_baseline_comparison,
            structure))

    dense_row = only(mgmfrm_response_stress_plan(
        design_strata = (:dense_fully_crossed,),
        response_patterns = (:regular_all_categories,),
    ))
    dense_case = simulate_mgmfrm_response_stress(dense_row)
    mixed_q = Bool[1 0; 1 1; 0 1; 0 1]
    mixed_q_report = q_matrix_validation(
        dense_case.data;
        dimensions = 2,
        q_matrix = mixed_q,
    )
    @test mixed_q_report.passed
    @test mixed_q_report.identification.guarded_fit_structure_ready
    @test mixed_q_report.identification.status ===
        :conservative_stable_structure_ready
    aliased_q_report = q_matrix_validation(
        dense_case.data;
        dimensions = 2,
        q_matrix = trues(4, 2),
    )
    @test !aliased_q_report.passed
    @test aliased_q_report.summary.n_duplicate_dimension_groups == 1
    @test !aliased_q_report.identification.guarded_fit_structure_ready

    portability = contract.portability
    @test !portability.repository_path_required
    @test !portability.commit_identity_required
    @test !portability.fixture_hash_required
    @test !portability.artifact_byte_identity_required
    @test :kfold_refit in portability.package_api_surface
    @test portability.cmdstan_required_only_for_reference_cells
    @test contract.resource_probe.operation ===
        :forwarddiff_logdensity_and_gradient
    @test !contract.resource_probe.mcmc_allowed
    @test !contract.resource_probe.
        final_resource_policy_may_be_frozen_from_this_probe_alone
    @test contract.short_nuts_resource_probe.profile ===
        :short_nuts_resource_probe
    @test contract.short_nuts_resource_probe.controls.warmup == 25
    @test contract.short_nuts_resource_probe.controls.ndraws == 25
    @test contract.short_nuts_resource_probe.
        explicit_execution_required
    @test !contract.short_nuts_resource_probe.convergence_assessed
    @test contract.short_nuts_resource_probe.
        scaled_resource_plan_function ===
        :mgmfrm_validation_scaled_resource_plan
    @test contract.isolated_resource_probe.cell_execution === :exactly_one
    @test contract.isolated_resource_probe.
        parent_memory_preflight_required
    @test contract.isolated_resource_probe.
        child_memory_preflight_required
    @test !contract.isolated_resource_probe.
        source_or_commit_hash_required
    @test contract.isolated_resource_review.function_name ===
        :mgmfrm_validation_isolated_resource_review
    @test !contract.isolated_resource_review.execution_allowed
    @test !contract.isolated_resource_review.automatic_progression_allowed
    @test !contract.isolated_resource_review.thresholds_applied
    @test :mgmfrm_validation_scaled_resource_plan in
        contract.portability.package_api_surface
    @test :mgmfrm_validation_isolated_resource_probe in
        contract.portability.package_api_surface
    @test :mgmfrm_validation_isolated_resource_review in
        contract.portability.package_api_surface
    @test !contract.scientific_thresholds_frozen
    @test !contract.validation_evidence_available
end
