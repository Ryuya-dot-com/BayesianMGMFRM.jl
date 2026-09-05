using BayesianMGMFRM
using Test

function _fixed_q_identification_data(person, rater, item, score)
    return FacetData((; person, rater, item, score);
        person = :person,
        rater = :rater,
        item = :item,
        score = :score,
    )
end

@testset "fixed-Q structural identification gate" begin
    simple_data = _fixed_q_identification_data(
        ["P1", "P1", "P2", "P2"],
        ["R1", "R2", "R2", "R1"],
        ["I1", "I2", "I1", "I2"],
        [0, 1, 1, 2],
    )
    simple_q = Bool[1 0; 0 1]
    simple = q_matrix_validation(simple_data;
        dimensions = 2,
        q_matrix = simple_q,
    )
    @test simple.passed
    @test simple.identification.schema ==
        "bayesianmgmfrm.fixed_q_identification.v1"
    @test simple.identification.status ===
        :conservative_stable_structure_ready
    @test simple.identification.likelihood_support.q_structural_rank == 2
    @test simple.identification.likelihood_support.
        q_full_column_structural_rank
    @test simple.identification.likelihood_support.
        all_persons_full_dimension_rank
    @test simple.identification.interpretation_support.
        pure_item_counts_per_dimension == (1, 1)
    @test simple.identification.prior_anchor.population_prior ===
        :standard_normal_by_dimension
    @test simple.identification.prior_anchor.latent_correlation ===
        :identity_fixed
    @test !simple.identification.prior_anchor.
        likelihood_only_identification_claim
    @test simple.identification.guarded_fit_structure_ready
    @test simple.identification.conservative_stable_structure_ready
    @test isempty(simple.identification.promotion_blockers)

    cyclic_data = _fixed_q_identification_data(
        repeat(["P1", "P2", "P3"]; inner = 3),
        ["R1", "R2", "R1", "R2", "R1", "R2", "R1", "R2", "R1"],
        repeat(["I1", "I2", "I3"], 3),
        [0, 1, 2, 1, 2, 0, 2, 0, 1],
    )
    cyclic_q = Bool[
        1 1 0
        0 1 1
        1 0 1
    ]
    cyclic = q_matrix_validation(cyclic_data;
        dimensions = 3,
        q_matrix = cyclic_q,
    )
    @test cyclic.passed
    @test cyclic.summary.q_structural_rank == 3
    @test cyclic.summary.q_full_column_structural_rank
    @test cyclic.summary.all_persons_full_dimension_rank
    @test !cyclic.summary.all_dimensions_have_pure_items
    @test cyclic.identification.status ===
        :guarded_generic_fixed_q_review_required
    @test cyclic.identification.guarded_fit_structure_ready
    @test !cyclic.identification.conservative_stable_structure_ready
    @test :pure_item_interpretation_support in
        cyclic.identification.promotion_blockers

    partial_person_data = _fixed_q_identification_data(
        [
            "P1", "P1", "P1", "P1",
            "P2", "P2",
            "P3", "P3", "P3", "P3",
        ],
        [
            "R1", "R1", "R2", "R2",
            "R1", "R2",
            "R1", "R1", "R2", "R2",
        ],
        [
            "I1", "I2", "I1", "I2",
            "I1", "I1",
            "I1", "I2", "I1", "I2",
        ],
        [0, 1, 1, 2, 1, 2, 2, 0, 0, 1],
    )
    partial = q_matrix_validation(partial_person_data;
        dimensions = 2,
        q_matrix = simple_q,
    )
    @test partial.passed
    @test partial.summary.q_full_column_structural_rank
    @test !partial.summary.all_persons_full_dimension_rank
    @test partial.summary.minimum_person_structural_rank == 1
    @test partial.summary.n_persons_incomplete_dimension_support == 1
    @test partial.identification.status ===
        :guarded_prior_anchored_person_dimensions
    @test partial.identification.guarded_fit_structure_ready
    @test !partial.identification.conservative_stable_structure_ready
    @test :person_dimension_likelihood_support in
        partial.identification.promotion_blockers
    @test any(row ->
            row.check === :person_dimension_likelihood_support &&
            row.status === :some_person_dimensions_are_prior_anchored &&
            row.severity === :warning,
        partial.rows)
    incomplete_person = only(row for row in
        partial.identification.likelihood_support.person_rows
        if !row.full_column_rank)
    @test incomplete_person.person_label == "P2"
    @test incomplete_person.structural_rank == 1
    @test incomplete_person.unobserved_dimension_labels == ("dim=2",)
    @test mfrm_spec(partial_person_data;
        family = :mgmfrm,
        dimensions = 2,
        q_matrix = simple_q).family === :mgmfrm

    rank_data = _fixed_q_identification_data(
        repeat(["P1", "P2"]; inner = 4),
        repeat(["R1", "R2"], 4),
        repeat(["I1", "I2", "I3", "I4"], 2),
        [0, 1, 2, 1, 1, 2, 0, 2],
    )
    rank_deficient_q = Bool[
        1 0 1 0
        0 1 1 0
        0 0 0 1
        0 0 0 1
    ]
    rank_deficient = q_matrix_validation(rank_data;
        dimensions = 4,
        q_matrix = rank_deficient_q,
    )
    @test !rank_deficient.passed
    @test rank_deficient.summary.n_duplicate_dimension_groups == 0
    @test rank_deficient.summary.q_structural_rank == 3
    @test !rank_deficient.summary.q_full_column_structural_rank
    @test rank_deficient.identification.status ===
        :rejected_fixed_q_structure
    @test !rank_deficient.identification.guarded_fit_structure_ready
    @test any(row ->
            row.check === :global_loading_structural_rank &&
            row.status === :structurally_rank_deficient &&
            row.severity === :error,
        rank_deficient.rows)
    @test_throws ArgumentError mfrm_spec(rank_data;
        family = :mgmfrm,
        dimensions = 4,
        q_matrix = rank_deficient_q,
    )

    missing = q_matrix_validation(simple_data;
        dimensions = 2,
        q_matrix = nothing,
    )
    @test !missing.passed
    @test missing.identification === nothing
end
