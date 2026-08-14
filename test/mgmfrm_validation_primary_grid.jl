using Test
using BayesianMGMFRM

@testset "MGMFRM primary-grid candidates" begin
    contract = mgmfrm_validation_primary_grid_candidates()

    @test contract.schema ==
        "bayesianmgmfrm.mgmfrm_validation_primary_grid_candidates.v1"
    @test contract.object ===
        :mgmfrm_validation_primary_grid_candidates
    @test contract.status ===
        :candidate_grid_generation_ready_execution_blocked
    @test !contract.cells_frozen
    @test !contract.evaluation_replications_frozen
    @test !contract.execution_allowed
    @test contract.claim_scope ===
        :candidate_generation_preflight_not_validation_evidence

    rows = contract.cells
    @test length(rows) == 16
    @test length(unique(row.cell_id for row in rows)) == 16
    @test contract.summary.n_candidate_cells == 16
    @test contract.summary.n_dense_cells == 8
    @test contract.summary.n_sparse_cells == 8
    @test contract.summary.minimum_expected_observations == 500
    @test contract.summary.maximum_expected_observations == 22_500
    @test contract.summary.n_within_current_gradient_probe_bound == 14
    @test contract.summary.n_above_current_gradient_probe_bound == 2
    @test contract.summary.n_within_current_short_nuts_probe_bound == 7
    @test contract.summary.n_above_current_short_nuts_probe_bound == 9
    @test !contract.summary.
        current_resource_envelope_covers_all_candidates
    @test contract.summary.primary_four_category_generator_implemented

    @test Set(row.design for row in rows) == Set((
        :dense_fully_crossed,
        :connected_sparse_systematic_link,
    ))
    @test Set(row.persons for row in rows) == Set((50, 100))
    @test Set(row.items for row in rows) == Set((5, 15))
    @test Set(row.raters for row in rows) == Set((5, 15))
    @test all(row -> row.dimensions == 2, rows)
    @test all(row -> row.categories == 4, rows)
    @test all(row -> row.object ===
        :mgmfrm_validation_primary_grid_candidate, rows)
    @test all(row -> row.q_structure ===
        :pure_between_item_one_active_dimension_per_item, rows)
    @test all(row -> row.pure_items_per_dimension ==
        (row.items ÷ 2, row.items - row.items ÷ 2), rows)
    @test all(row -> row.mean_person_assignments_per_rater ==
        row.persons * row.raters_per_person / row.raters, rows)
    @test all(row -> row.mean_ratings_per_rater ==
        row.expected_observations / row.raters, rows)
    @test all(row -> row.rater_coverage_fraction ==
        row.raters_per_person / row.raters, rows)
    @test all(row -> row.dimension_support_role ===
        (row.items == 5 ? :package_fixed_q_minimum_support_stress :
         :package_fixed_q_larger_support_candidate), rows)
    @test all(row -> row.generator_status ===
        :public_primary_four_category_known_truth_generator, rows)
    @test all(row -> row.seed_role ===
        :structural_preflight_only_not_evaluation, rows)
    @test length(unique(row.preflight_seed for row in rows)) == 16
    @test all(row -> row.status === :candidate_not_frozen, rows)
    @test all(row -> !row.execution_authorized, rows)

    dense_largest = only(row for row in rows
        if row.design === :dense_fully_crossed && row.persons == 100 &&
            row.items == 15 && row.raters == 15)
    @test dense_largest.expected_observations == 22_500
    @test dense_largest.expected_probability_cells == 90_000
    @test !dense_largest.within_current_gradient_probe_bound
    @test !dense_largest.within_current_short_nuts_probe_bound

    sparse_smallest = only(row for row in rows
        if row.design === :connected_sparse_systematic_link &&
            row.persons == 50 && row.items == 5 && row.raters == 5)
    @test sparse_smallest.raters_per_person == 2
    @test sparse_smallest.rater_coverage_fraction == 0.4
    @test sparse_smallest.rater_coverage_role ===
        :higher_sparse_per_rater_coverage_candidate
    @test sparse_smallest.expected_observations == 500
    @test sparse_smallest.within_current_gradient_probe_bound
    @test sparse_smallest.within_current_short_nuts_probe_bound

    sparse_lowest_coverage = only(row for row in rows
        if row.design === :connected_sparse_systematic_link &&
            row.persons == 50 && row.items == 5 && row.raters == 15)
    @test sparse_lowest_coverage.rater_coverage_fraction == 2 / 15
    @test sparse_lowest_coverage.mean_person_assignments_per_rater ==
        100 / 15
    @test sparse_lowest_coverage.rater_coverage_role ===
        :lowest_sparse_per_rater_coverage_candidate

    @test :implement_primary_four_category_known_truth_generator ∉
        contract.blockers
    @test :extend_resource_envelope_or_narrow_candidate_grid in
        contract.blockers

    precision = mgmfrm_validation_replication_precision(
        (50, 100, 200, 400);
        coverage_mcse_target = 0.02,
        binary_rate_mcse_target = 0.025,
        bias_error_sd_reference = 0.20,
        bias_mcse_target = 0.01,
    )
    @test precision.schema ==
        "bayesianmgmfrm.mgmfrm_validation_replication_precision.v1"
    @test precision.object === :mgmfrm_validation_replication_precision
    @test precision.status ===
        :precision_reference_not_replication_freeze
    @test precision.minimum_replications.coverage == 119
    @test precision.minimum_replications.binary_rate_worst_case == 400
    @test precision.minimum_replications.bias == 400
    @test precision.rows[2].nominal_coverage_mcse ≈
        sqrt(0.95 * 0.05 / 100)
    @test precision.rows[2].binary_rate_worst_case_mcse == 0.05
    @test precision.rows[2].bias_mcse_reference == 0.02
    @test !precision.rows[2].coverage_target_met
    @test precision.rows[3].coverage_target_met
    @test !precision.rows[3].binary_rate_target_met
    @test precision.rows[4].binary_rate_target_met
    @test precision.rows[4].bias_target_met
    @test precision.assumptions.bias_error_sd_source ===
        :caller_supplied_reference
    @test precision.failure_accounting.binary_failure_rate_covered
    @test precision.failure_accounting.bias_mcse_conditional_on_numeric_errors
    @test !precision.failure_accounting.
        failed_fits_may_be_dropped_from_planned_denominator
    @test precision.failure_accounting.failure_sensitivity_policy_required
    @test !precision.replication_count_selected
    @test !precision.precision_targets_selected
    @test !precision.execution_authorized
    @test precision.scientific_decision === :not_applied
    @test precision.claim_scope ===
        :mcse_planning_not_validation_evidence

    unresolved_bias = mgmfrm_validation_replication_precision(100;
        bias_mcse_target = 0.01,
    )
    @test unresolved_bias.bias_precision_status === :reference_sd_required
    @test ismissing(unresolved_bias.rows[1].bias_mcse_reference)
    @test ismissing(unresolved_bias.rows[1].bias_target_met)
    @test ismissing(unresolved_bias.minimum_replications.bias)
    @test ismissing(unresolved_bias.targets.coverage_mcse)
    @test_throws ArgumentError mgmfrm_validation_replication_precision(())
    @test_throws ArgumentError mgmfrm_validation_replication_precision((50, 50))
    @test_throws ArgumentError mgmfrm_validation_replication_precision((50, 50.0))
    @test_throws ArgumentError mgmfrm_validation_replication_precision(0)
    @test_throws ArgumentError mgmfrm_validation_replication_precision(
        100;
        nominal_coverage = 1.0,
    )
    @test_throws ArgumentError mgmfrm_validation_replication_precision(
        100;
        binary_rate_mcse_target = 0.0,
    )

    resource_plan = mgmfrm_validation_primary_resource_plan()
    @test resource_plan.schema ==
        "bayesianmgmfrm.mgmfrm_validation_primary_resource_plan.v1"
    @test resource_plan.object ===
        :mgmfrm_validation_primary_resource_plan
    @test resource_plan.status === :predeclared_not_run
    @test resource_plan.expected_observations ==
        (500, 1_250, 3_750, 7_500)
    @test resource_plan.expected_probability_cells ==
        (2_000, 5_000, 15_000, 30_000)
    @test length(resource_plan.rows) == 4
    @test all(row -> row.object ===
        :mgmfrm_validation_primary_grid_candidate, resource_plan.rows)
    @test all(row -> row.categories == 4, resource_plan.rows)
    @test length(unique(row.source_candidate_cell_id
        for row in resource_plan.rows)) == 4
    @test length(unique(row.resource_seed for row in resource_plan.rows)) == 4
    @test all(row -> row.seed_role ===
        :resource_probe_only_not_evaluation, resource_plan.rows)
    @test all(row -> row.within_current_gradient_probe_bound,
        resource_plan.rows)
    @test all(row -> row.within_current_short_nuts_probe_bound,
        resource_plan.rows[1:2])
    @test all(row -> !row.within_current_short_nuts_probe_bound,
        resource_plan.rows[3:4])
    @test resource_plan.execution_mode ===
        :one_cell_per_explicit_invocation
    @test !resource_plan.automatic_progression_allowed
    @test !resource_plan.all_primary_axes_covered
    @test !resource_plan.all_primary_candidates_measured
    @test resource_plan.short_nuts_adapter_available
    @test resource_plan.n_current_short_nuts_eligible_cells == 2
    @test !resource_plan.final_analysis_grid_selected
    @test !resource_plan.mcmc_executed
    @test !resource_plan.primary_evaluation_seed_used
    @test resource_plan.scientific_decision === :not_applied

    smallest_case = simulate_mgmfrm_validation_primary_candidate(
        sparse_smallest,
    )
    @test smallest_case.status === :primary_candidate_generated
    @test smallest_case.data.n == sparse_smallest.expected_observations
    @test smallest_case.data.category_levels == [1, 2, 3, 4]
    @test smallest_case.preflight_passed
    @test smallest_case.fit_eligible
    @test smallest_case.validation.passed
    @test smallest_case.q_validation.passed
    @test smallest_case.category_support_passed
    @test smallest_case.observation_count_passed
    @test smallest_case.truth_probabilities_valid
    @test smallest_case.truth_parameters_valid
    @test size(smallest_case.truth_category_probabilities) ==
        (1, sparse_smallest.expected_observations, 4)
    @test Tuple(vec(sum(smallest_case.q_matrix; dims = 1))) ==
        sparse_smallest.pure_items_per_dimension
    @test smallest_case.fit_evidence === :not_run
    @test smallest_case.scientific_decision === :not_applied

    caller_seed_case = simulate_mgmfrm_validation_primary_candidate(
        sparse_smallest;
        seed = 42,
    )
    @test caller_seed_case.seed == 42
    @test caller_seed_case.seed_role === :caller_supplied

    dense_smallest = only(row for row in rows
        if row.design === :dense_fully_crossed && row.persons == 50 &&
            row.items == 5 && row.raters == 5)
    smoke_cells = (dense_smallest, sparse_smallest)
    smoke_contract = merge(contract, (;
        cells = smoke_cells,
        summary = merge(contract.summary, (;
            n_candidate_cells = length(smoke_cells),
        )),
    ))
    preflight = mgmfrm_validation_primary_grid_preflight(smoke_contract)
    @test preflight.status === :preflight_complete
    @test preflight.summary.n_candidates == 2
    @test preflight.summary.n_preflight_passed == 2
    @test preflight.summary.n_preflight_rejected == 0
    @test preflight.summary.all_candidates_accounted_for
    @test all(row -> row.preflight_passed, preflight.rows)
    @test all(row -> row.truth_parameters_valid, preflight.rows)
    @test all(row -> row.fit_eligible, preflight.rows)
    @test all(generated -> generated.data.category_levels == [1, 2, 3, 4],
        preflight.cases)
    @test all(generated -> generated.data.n ==
        generated.candidate.expected_observations, preflight.cases)
    @test preflight.fit_evidence === :not_run
    @test preflight.scientific_decision === :not_applied

    malformed = merge(sparse_smallest, (; categories = 5))
    @test_throws ArgumentError simulate_mgmfrm_validation_primary_candidate(
        malformed,
    )
    @test_throws ArgumentError simulate_mgmfrm_validation_primary_candidate(
        sparse_smallest;
        truth_scale = 0.0,
    )
end
