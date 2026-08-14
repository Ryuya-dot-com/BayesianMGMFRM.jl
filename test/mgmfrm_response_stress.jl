using Test
using BayesianMGMFRM

@testset "MGMFRM five-category response stress preflight" begin
    plan = mgmfrm_response_stress_plan()
    @test length(plan) == 9
    @test count(row -> row.design === :dense_fully_crossed, plan) == 4
    @test count(row ->
        row.design === :connected_sparse_systematic_link, plan) == 5
    @test !any(row ->
        row.design === :dense_fully_crossed &&
        row.response_pattern ===
            :combined_unused_category_and_boundary_patterns,
        plan)
    @test all(row -> row.status === :predeclared_not_run, plan)
    @test all(row -> row.n_categories == 5, plan)
    @test length(unique(row.attempt_id for row in plan)) == length(plan)

    @test_throws ArgumentError mgmfrm_response_stress_plan(
        design_strata = (:unknown,),
    )
    @test_throws ArgumentError mgmfrm_response_stress_plan(
        response_patterns = (:all_maximum_person, :all_maximum_person),
    )
    @test_throws ArgumentError mgmfrm_response_stress_plan(n_raters = 2)
    @test_throws ArgumentError mgmfrm_response_stress_plan(
        n_persons = 4, n_raters = 5,
    )
    @test_throws ArgumentError mgmfrm_response_stress_plan(
        design_strata = (:dense_fully_crossed,),
        response_patterns =
            (:combined_unused_category_and_boundary_patterns,),
    )

    for n_items in (5, 15)
        odd_plan = mgmfrm_response_stress_plan(
            design_strata = (:connected_sparse_systematic_link,),
            response_patterns = (:regular_all_categories,),
            n_items = n_items,
        )
        odd_row = only(odd_plan)
        @test odd_row.pure_items_per_dimension ==
            (n_items ÷ 2, n_items - n_items ÷ 2)
        @test odd_row.pure_item_balance_rule ===
            :dimension_count_difference_at_most_one
        odd_case = simulate_mgmfrm_response_stress(odd_row)
        @test odd_case.preflight_passed
        @test odd_case.fit_eligible
        @test Tuple(vec(sum(odd_case.q_matrix; dims = 1))) ==
            odd_row.pure_items_per_dimension
    end

    cases = Dict{Tuple{Symbol,Symbol},Any}()
    for row in plan
        generated = simulate_mgmfrm_response_stress(row)
        cases[(row.design, row.response_pattern)] = generated
        @test generated.status === :stress_case_generated
        @test generated.preflight_passed
        @test generated.fit_eligible
        @test generated.fit_evidence === :not_run
        @test generated.scientific_decision === :not_applied
        @test generated.data.category_levels == [1, 2, 3, 4, 5]
        @test generated.validation.passed
        @test generated.q_validation.passed
        @test generated.q_validation.identification.
            conservative_stable_structure_ready
        @test generated.pattern_check.passed
        @test !isempty(generated.raw_truth)
        @test length(generated.direct_truth) ==
            length(generated.design.parameter_names)
        @test all(isfinite, generated.raw_truth)
        @test all(isfinite, generated.direct_truth)
        @test size(generated.truth_category_probabilities) ==
            (1, generated.data.n, 5)
        @test all(isfinite, generated.truth_category_probabilities)
        @test generated.truth_probabilities_valid
        @test generated.maximum_probability_sum_error <= 1e-10
    end

    dense_regular = cases[(:dense_fully_crossed, :regular_all_categories)]
    sparse_regular = cases[
        (:connected_sparse_systematic_link, :regular_all_categories)]
    @test dense_regular.data.n == 12 * 4 * 3
    @test sparse_regular.data.n == 12 * 4 * 2
    @test isempty(dense_regular.changed_rows)
    @test isempty(sparse_regular.changed_rows)
    @test dense_regular.probability_truth_role ===
        :observed_data_generating_probability

    skipped = cases[
        (:connected_sparse_systematic_link, :unused_interior_category_3)]
    @test skipped.response_pattern_audit.category_scale.
        unobserved_interior_categories == (3,)
    @test !isempty(skipped.changed_rows)
    @test skipped.probability_truth_role ===
        :pre_intervention_reference_probability

    all_maximum = cases[
        (:connected_sparse_systematic_link, :all_maximum_person)]
    @test "P1" in
        all_maximum.response_pattern_audit.flags.extreme_person_levels

    all_minimum = cases[
        (:connected_sparse_systematic_link, :all_minimum_rater)]
    @test "R1" in
        all_minimum.response_pattern_audit.flags.boundary_rater_levels

    combined = cases[
        (:connected_sparse_systematic_link,
            :combined_unused_category_and_boundary_patterns)]
    @test "P2" in
        combined.response_pattern_audit.flags.extreme_person_levels
    @test "R1" in
        combined.response_pattern_audit.flags.boundary_rater_levels
    person_index = findfirst(==("P2"), combined.data.person_levels)
    rater_index = findfirst(==("R1"), combined.data.rater_levels)
    @test !any(row ->
        combined.data.person[row] == person_index &&
        combined.data.rater[row] == rater_index,
        1:combined.data.n)

    preflight = mgmfrm_response_stress_preflight(plan)
    @test preflight.status === :preflight_complete
    @test preflight.summary.n_attempts == 9
    @test preflight.summary.n_terminal_attempts == 9
    @test preflight.summary.n_preflight_passed == 9
    @test preflight.summary.n_pre_fit_rejected == 0
    @test preflight.summary.n_generation_failed == 0
    @test preflight.summary.denominator_preserved
    @test all(row -> row.terminal_status === :preflight_passed,
        preflight.rows)
    @test all(row -> row.truth_probabilities_valid, preflight.rows)
    @test preflight.fit_evidence === :not_run
    @test preflight.next_gate ===
        :implement_attempt_complete_fit_and_diagnostic_phases

    malformed = merge(first(plan), (;
        attempt_id = :malformed_pattern,
        response_pattern = :not_a_response_pattern,
    ))
    failed = mgmfrm_response_stress_preflight([malformed])
    @test failed.status === :preflight_complete_with_recorded_failures
    @test failed.summary.n_attempts == 1
    @test failed.summary.n_terminal_attempts == 1
    @test failed.summary.n_generation_failed == 1
    @test failed.summary.denominator_preserved
    failed_row = only(failed.rows)
    @test failed_row.terminal_status === :generation_failed
    @test failed_row.error_phase === :generation_and_preflight
    @test failed_row.error isa ArgumentError
    @test occursin("unsupported response pattern", failed_row.error_message)
    @test only(failed.cases) === missing

    @test_throws ArgumentError mgmfrm_response_stress_preflight(NamedTuple[])
    duplicate_ids = [first(plan), merge(last(plan), (;
        attempt_id = first(plan).attempt_id,
    ))]
    @test_throws ArgumentError mgmfrm_response_stress_preflight(duplicate_ids)
    @test_throws ArgumentError mgmfrm_response_stress_preflight(
        plan; truth_scale = 0.0)
end
