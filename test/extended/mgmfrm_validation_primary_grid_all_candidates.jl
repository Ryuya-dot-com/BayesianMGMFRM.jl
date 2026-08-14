using Test
using BayesianMGMFRM

# Explicit extended check: this materializes all 16 four-category candidate
# datasets and their probability arrays. Keep it out of the default test entry
# point so ordinary package tests remain resource-aware.
@testset "MGMFRM primary-grid all-candidate preflight" begin
    preflight = mgmfrm_validation_primary_grid_preflight()

    @test preflight.status === :preflight_complete
    @test preflight.summary.n_candidates == 16
    @test preflight.summary.n_preflight_passed == 16
    @test preflight.summary.n_preflight_rejected == 0
    @test preflight.summary.all_candidates_accounted_for
    @test all(row -> row.preflight_passed, preflight.rows)
    @test all(row -> row.fit_eligible, preflight.rows)
    @test all(row -> row.truth_parameters_valid, preflight.rows)
    @test all(generated -> generated.data.category_levels == [1, 2, 3, 4],
        preflight.cases)
end
