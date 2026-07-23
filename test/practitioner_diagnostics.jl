using Test
using Random
using BayesianMGMFRM

@testset "MFRM practitioner category and rater diagnostics" begin
    table = (
        person = ["E1", "E1", "E2", "E2", "E1", "E3", "E3", "E2"],
        rater = ["A", "B", "B", "C", "D", "D", "A", "C"],
        item = ["I1", "I1", "I1", "I1", "I2", "I2", "I3", "I2"],
        score = [0, 1, 2, 1, 1, 1, 0, 2],
    )
    data = FacetData(
        table;
        person = :person,
        rater = :rater,
        item = :item,
        score = :score,
    )
    rsm_design = getdesign(mfrm_spec(data; thresholds = :rating_scale))
    draws = zeros(4, length(rsm_design.parameter_names))
    rater_block = rsm_design.blocks[:rater]
    draws[:, rater_block[1]] .= 0.50 # B; A is the fixed reference.
    draws[:, rater_block[2]] .= 0.05 # C.
    draws[:, rater_block[3]] .= -0.40 # D.
    draws[:, only(rsm_design.blocks[:thresholds])] .= 0.60

    fit_result = MFRMFit(
        rsm_design,
        MFRMPrior(),
        draws,
        zeros(size(draws, 1)),
        1.0,
        ones(Int, size(draws, 1)),
        collect(1:size(draws, 1)),
        [1.0],
        :julia,
        :random_walk_metropolis,
        0,
        0.1,
    )

    category_summary = category_functioning_summary(
        rsm_design,
        draws;
        draw_indices = 1:4,
        rng = MersenneTwister(41),
        interval = 0.8,
        min_count = 1,
        min_proportion = 0.0,
        order_probability_threshold = 0.75,
    )
    @test category_summary.schema ==
        "bayesianmgmfrm.category_functioning_summary.v1"
    @test category_summary.object === :category_functioning_summary
    @test category_summary.model_family === :mfrm
    @test category_summary.thresholds === :rating_scale
    @test category_summary.draw_indices == (1, 2, 3, 4)
    @test length(category_summary.usage_rows) ==
        (1 + length(data.rater_levels) + length(data.item_levels)) *
        length(data.category_levels)
    @test Set(row.facet for row in category_summary.usage_rows) ==
        Set((:overall, :rater, :item))
    @test all(row -> row.n_replicates == 4, category_summary.usage_rows)
    @test all(row -> 0 <= row.replicated_proportion_mean <= 1,
        category_summary.usage_rows)
    @test all(row -> row.replicated_proportion_lower <=
        row.replicated_proportion_median <= row.replicated_proportion_upper,
        category_summary.usage_rows)
    @test any(row -> row.observed_flag === :skipped,
        category_summary.usage_rows)
    @test all(row -> !row.automatic_category_collapse,
        category_summary.usage_rows)
    @test all(row -> row.interval_type ===
        :central_posterior_predictive_replication,
        category_summary.usage_rows)
    @test length(category_summary.threshold_rows) ==
        length(data.category_levels) - 1
    @test all(row -> ismissing(row.item), category_summary.threshold_rows)
    @test first(category_summary.threshold_rows).ordering_flag === :not_applicable
    last_threshold = last(category_summary.threshold_rows)
    @test last_threshold.ordering_flag === :likely_disordered
    @test last_threshold.probability_step_greater_than_previous == 0.0
    @test all(row -> !row.automatic_category_collapse,
        category_summary.threshold_rows)
    @test all(row -> row.interval_type === :central_posterior_parameter,
        category_summary.threshold_rows)
    @test !category_summary.policy.automatic_category_collapse
    @test !category_summary.policy.refit_performed
    @test category_summary.policy.usage_interval_type ===
        :central_posterior_predictive_replication
    @test category_summary.policy.threshold_interval_type ===
        :central_posterior_parameter

    fit_category_summary = category_functioning_summary(
        fit_result;
        draw_indices = 1:4,
        rng = MersenneTwister(41),
        interval = 0.8,
        min_count = 1,
        min_proportion = 0.0,
        order_probability_threshold = 0.75,
    )
    @test isequal(fit_category_summary.usage_rows, category_summary.usage_rows)
    @test isequal(fit_category_summary.threshold_rows,
        category_summary.threshold_rows)

    pcm_design = getdesign(mfrm_spec(data; thresholds = :partial_credit))
    pcm_draws = zeros(3, length(pcm_design.parameter_names))
    pcm_summary = category_functioning_summary(
        pcm_design,
        pcm_draws;
        draw_indices = [1, 2, 3],
        rng = MersenneTwister(42),
        min_count = 1,
        min_proportion = 0.0,
        order_probability_threshold = 0.75,
    )
    @test pcm_summary.thresholds === :partial_credit
    @test length(pcm_summary.threshold_rows) ==
        length(data.item_levels) * (length(data.category_levels) - 1)
    @test Set(row.item for row in pcm_summary.threshold_rows) ==
        Set(data.item_levels)
    @test all(row -> row.threshold_type === :item_partial_credit_step,
        pcm_summary.threshold_rows)

    @test_throws ArgumentError category_functioning_summary(
        rsm_design, draws; interval = 1.0)
    @test_throws ArgumentError category_functioning_summary(
        rsm_design, draws; min_count = 0)
    @test_throws ArgumentError category_functioning_summary(
        rsm_design, draws; min_proportion = -0.1)
    @test_throws ArgumentError category_functioning_summary(
        rsm_design, draws; order_probability_threshold = 0.5)
    @test_throws ArgumentError category_functioning_summary(
        rsm_design, draws; ndraws = 0)
    @test_throws ArgumentError category_functioning_summary(
        rsm_design, draws; ndraws = 2, draw_indices = [1, 2])
    @test_throws ArgumentError category_functioning_summary(
        rsm_design, draws; draw_indices = [0])

    homogeneity = rater_homogeneity_summary(
        rsm_design,
        draws;
        draw_indices = 1:4,
        severity_rope = 0.10,
        rope_probability_threshold = 0.75,
        interval = 0.8,
        overlap_unit = :person_item,
    )
    @test homogeneity.schema ==
        "bayesianmgmfrm.rater_homogeneity_summary.v1"
    @test homogeneity.object === :rater_homogeneity_summary
    @test homogeneity.summary.n_raters == 4
    @test homogeneity.summary.n_contrasts == 6
    @test homogeneity.summary.n_direct_contrasts == 2
    @test homogeneity.summary.n_network_contrasts == 1
    @test homogeneity.summary.n_disconnected_contrasts == 3
    @test homogeneity.summary.rater_network_status === :disconnected
    @test homogeneity.summary.shared_unit_overlap_network_status ===
        :disconnected
    @test homogeneity.summary.common_response_status === :person_item_proxy
    @test !homogeneity.summary.common_response_linking_verified
    @test homogeneity.summary.model_identification_status ===
        :full_rank_connected
    @test homogeneity.summary.validation_passed
    @test homogeneity.summary.location_design_full_rank
    @test homogeneity.summary.location_design_rank ==
        homogeneity.summary.location_design_n_parameters
    @test homogeneity.summary.location_design_n_parameters ==
        length(data.person_levels) + length(data.rater_levels) - 1 +
        length(data.item_levels) - 1
    @test homogeneity.summary.n_model_identification_unsupported_contrasts == 0
    @test homogeneity.summary.interpretation_supported
    @test all(row -> row.model_identification_support ===
        :full_rank_connected, homogeneity.contrast_rows)
    @test all(row -> row.model_identification_supported,
        homogeneity.contrast_rows)
    a_b = only(row for row in homogeneity.contrast_rows
        if row.rater_a == "A" && row.rater_b == "B")
    @test a_b.rater_a_reference
    @test !a_b.rater_b_reference
    @test a_b.severity_difference_mean == -0.5
    @test a_b.probability_negative == 1.0
    @test a_b.direction === :negative
    @test a_b.practical_equivalence === :outside_rope
    @test a_b.support === :direct
    @test a_b.shared_unit_overlap_support === :direct
    @test a_b.support_compatibility_alias === :shared_unit_overlap_support
    @test a_b.interpretation === :positive_means_rater_a_more_severe
    a_c = only(row for row in homogeneity.contrast_rows
        if row.rater_a == "A" && row.rater_b == "C")
    @test a_c.severity_difference_mean ≈ -0.05
    @test a_c.practical_equivalence === :inside_rope
    @test a_c.support === :network
    @test a_c.shared_unit_overlap_support === :network
    @test a_c.model_identification_supported
    a_d = only(row for row in homogeneity.contrast_rows
        if row.rater_a == "A" && row.rater_b == "D")
    @test a_d.support === :disconnected
    @test a_d.shared_unit_overlap_support === :disconnected
    @test a_d.shared_persons == 2
    @test a_d.shared_items == 0
    @test a_d.direct_additive_link
    @test a_d.model_identification_path === :shared_person_or_item
    @test a_d.model_identification_support === :full_rank_connected
    @test a_d.model_identification_supported
    @test a_d.interpretation_status === :diagnostic
    @test a_d.caveat ===
        :additive_model_identified_without_requested_shared_unit_overlap

    response_table = merge(table, (;
        response_id = ["X1", "X1", "X2", "X2", "X3", "X4", "X5", "X6"],
    ))
    response_data = FacetData(
        response_table;
        person = :person,
        rater = :rater,
        item = :item,
        score = :score,
        response_id = :response_id,
    )
    response_design = getdesign(mfrm_spec(
        response_data;
        thresholds = :rating_scale,
    ))
    response_homogeneity = rater_homogeneity_summary(
        response_design,
        draws;
        draw_indices = 1:4,
        overlap_unit = :response_id,
    )
    @test response_homogeneity.summary.common_response_status ===
        :verified_common_response
    @test response_homogeneity.summary.common_response_linking_verified
    @test all(row -> row.common_response_status === :verified_common_response,
        response_homogeneity.contrast_rows)
    @test all(row -> row.common_response_linking_verified,
        response_homogeneity.contrast_rows)

    fit_homogeneity = rater_homogeneity_summary(
        fit_result;
        draw_indices = 1:4,
        severity_rope = 0.10,
        rope_probability_threshold = 0.75,
        interval = 0.8,
    )
    @test isequal(fit_homogeneity.contrast_rows, homogeneity.contrast_rows)
    no_rope = rater_homogeneity_summary(
        fit_result;
        draw_indices = [1, 2],
    )
    @test all(row -> row.practical_equivalence === :not_requested,
        no_rope.contrast_rows)
    @test no_rope.policy.practical_margin_source === :not_requested

    @test_throws ArgumentError rater_homogeneity_summary(
        fit_result; interval = 1.0)
    @test_throws ArgumentError rater_homogeneity_summary(
        fit_result; severity_rope = -0.1)
    @test_throws ArgumentError rater_homogeneity_summary(
        fit_result; rope_probability_threshold = 0.0)
    @test_throws ArgumentError rater_homogeneity_summary(
        fit_result; min_shared_units = 0)
    @test_throws ArgumentError rater_homogeneity_summary(
        fit_result; ndraws = 2, draw_indices = [1, 2])
    @test_throws ArgumentError rater_homogeneity_summary(
        fit_result; overlap_unit = :testlet_id)

    rank_deficient_table = (
        person = ["E1", "E1", "E2", "E2", "E1", "E3", "E3", "E2"],
        rater = ["A", "B", "B", "C", "D", "D", "A", "C"],
        item = ["I1", "I1", "I2", "I2", "I2", "I2", "I3", "I2"],
        score = [0, 1, 2, 1, 1, 1, 0, 2],
    )
    rank_deficient_data = FacetData(
        rank_deficient_table;
        person = :person,
        rater = :rater,
        item = :item,
        score = :score,
    )
    rank_deficient_validation = validate_design(rank_deficient_data)
    @test !rank_deficient_validation.passed
    @test any(issue -> issue.code === :rank_deficient_design &&
        issue.severity === :error, rank_deficient_validation.issues)
    @test_throws ArgumentError mfrm_spec(
        rank_deficient_data;
        thresholds = :rating_scale,
        validation_report = rank_deficient_validation,
    )
end
