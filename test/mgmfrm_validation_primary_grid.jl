using Test
using BayesianMGMFRM

@testset "MGMFRM primary-grid candidates" begin
    contract = mgmfrm_validation_primary_grid_candidates()

    @test contract.schema ==
        "bayesianmgmfrm.mgmfrm_validation_primary_grid_candidates.v1"
    @test contract.object ===
        :mgmfrm_validation_primary_grid_candidates
    @test contract.status ===
        :candidate_grid_enumerated_execution_blocked
    @test !contract.cells_frozen
    @test !contract.evaluation_replications_frozen
    @test !contract.execution_allowed
    @test contract.claim_scope ===
        :candidate_enumeration_not_validation_evidence

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
    @test !contract.summary.primary_four_category_generator_implemented

    @test Set(row.design for row in rows) == Set((
        :dense_fully_crossed,
        :connected_sparse_systematic_link,
    ))
    @test Set(row.persons for row in rows) == Set((50, 100))
    @test Set(row.items for row in rows) == Set((5, 15))
    @test Set(row.raters for row in rows) == Set((5, 15))
    @test all(row -> row.dimensions == 2, rows)
    @test all(row -> row.categories == 4, rows)
    @test all(row -> row.q_structure ===
        :pure_between_item_one_active_dimension_per_item, rows)
    @test all(row -> row.pure_items_per_dimension ==
        (row.items ÷ 2, row.items - row.items ÷ 2), rows)
    @test all(row -> row.generator_status ===
        :primary_four_category_known_truth_generator_pending, rows)
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
    @test sparse_smallest.expected_observations == 500
    @test sparse_smallest.within_current_gradient_probe_bound
    @test sparse_smallest.within_current_short_nuts_probe_bound

    @test :implement_primary_four_category_known_truth_generator in
        contract.blockers
    @test :extend_resource_envelope_or_narrow_candidate_grid in
        contract.blockers
end
