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
    @test homogeneity.summary.n_fixed_contrasts == 0
    @test homogeneity.summary.n_partially_estimated_contrasts == 3
    @test homogeneity.summary.n_posterior_estimated_contrasts == 3
    @test !homogeneity.summary.contains_fixed_contrasts
    @test homogeneity.summary.contains_fixed_coordinate_contrasts
    @test all(row -> row.model_identification_support ===
        :full_rank_connected, homogeneity.contrast_rows)
    @test all(row -> row.model_identification_supported,
        homogeneity.contrast_rows)
    a_b = only(row for row in homogeneity.contrast_rows
        if row.rater_a == "A" && row.rater_b == "B")
    @test a_b.rater_a_reference
    @test !a_b.rater_b_reference
    @test a_b.rater_a_status === :reference_zero
    @test a_b.rater_b_status === :estimated
    @test a_b.rater_a_is_fixed
    @test !a_b.rater_b_is_fixed
    @test a_b.rater_a_fixed_value == 0.0
    @test ismissing(a_b.rater_b_fixed_value)
    @test !a_b.rater_a_posterior_estimated
    @test a_b.rater_b_posterior_estimated
    @test a_b.contrast_estimation_status === :partially_estimated_contrast
    @test !a_b.contrast_is_fixed
    @test a_b.contrast_posterior_estimated
    @test a_b.contrast_interval_type === :central_posterior
    @test a_b.interval_probability == 0.8
    @test a_b.lower_probability ≈ 0.1
    @test a_b.upper_probability ≈ 0.9
    @test a_b.n_uncertainty_draws == a_b.n_draws
    @test a_b.draw_role === :posterior_uncertainty
    @test a_b.caveat ===
        :posterior_contrast_includes_one_fixed_coordinate_not_score_agreement_or_bias_proof
    @test a_b.contrast_uncertainty_status ===
        :posterior_uncertainty_from_estimated_coordinate_only
    @test a_b.probability_basis === :posterior_draws
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
    b_c = only(row for row in homogeneity.contrast_rows
        if row.rater_a == "B" && row.rater_b == "C")
    @test b_c.rater_a_status === :estimated
    @test b_c.rater_b_status === :estimated
    @test b_c.contrast_estimation_status === :posterior_estimated_contrast
    @test b_c.contrast_uncertainty_status ===
        :posterior_uncertainty_from_both_estimated_coordinates
    @test b_c.n_uncertainty_draws == b_c.n_draws
    @test b_c.draw_role === :posterior_uncertainty
    @test b_c.caveat ===
        :posterior_contrast_not_score_agreement_or_bias_proof
    @test homogeneity.policy.interval_type_scope ===
        :nonfixed_contrasts_only
    @test homogeneity.policy.fixed_contrast_interval_type ===
        :not_applicable_fixed_contrast
    @test homogeneity.policy.fixed_contrast_interval_probabilities ===
        :not_applicable
    @test homogeneity.caveat ===
        :severity_contrasts_include_fixed_coordinates_not_observed_score_agreement
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

    practitioner_report = fit_report(
        fit_result;
        include_posterior_predictive = false,
        include_calibration = false,
        include_waic = false,
        include_loo = false,
        include_artifact = false,
        draw_indices = 1:4,
        rng = MersenneTwister(41),
        category_functioning_interval = 0.8,
        category_functioning_min_count = 1,
        category_functioning_min_proportion = 0.0,
        category_order_probability_threshold = 0.75,
        rater_homogeneity_interval = 0.8,
        rater_severity_rope = 0.10,
        rater_rope_probability_threshold = 0.75,
        rater_overlap_unit = :person_item,
        rater_min_shared_units = 1,
    )
    @test practitioner_report.report_status === :complete
    @test practitioner_report.report_policy.include_category_functioning
    @test practitioner_report.report_policy.include_rater_homogeneity
    @test practitioner_report.report_policy.category_functioning_interval == 0.8
    @test practitioner_report.report_policy.category_functioning_min_count == 1
    @test practitioner_report.report_policy.category_functioning_min_proportion == 0.0
    @test practitioner_report.report_policy.category_order_probability_threshold == 0.75
    @test practitioner_report.report_policy.rater_homogeneity_interval == 0.8
    @test practitioner_report.report_policy.rater_severity_rope == 0.10
    @test practitioner_report.report_policy.rater_rope_probability_threshold == 0.75
    @test practitioner_report.report_policy.rater_overlap_unit === :person_item
    @test practitioner_report.report_policy.rater_min_shared_units == 1

    report_categories = practitioner_report.category_functioning
    @test report_categories.status === :computed
    @test report_categories.schema == category_summary.schema
    @test report_categories.object === :category_functioning_summary
    @test isequal(report_categories.usage_rows,
        collect(category_summary.usage_rows))
    @test isequal(report_categories.threshold_rows,
        collect(category_summary.threshold_rows))
    @test report_categories.n_warning_rows == 1
    category_warning = only(report_categories.warning_rows)
    @test category_warning.code ===
        :category_functioning_review_recommended
    @test category_warning.n_affected_rows ==
        report_categories.summary.n_review_rows
    @test category_warning.action ===
        :review_category_usage_and_step_rows_before_recode_or_refit

    report_raters = practitioner_report.rater_homogeneity
    @test report_raters.status === :computed
    @test report_raters.schema == homogeneity.schema
    @test report_raters.object === :rater_homogeneity_summary
    @test isequal(report_raters.contrast_rows,
        collect(homogeneity.contrast_rows))
    @test isempty(report_raters.warning_rows)
    @test report_raters.n_warning_rows == 0

    category_section = only(filter(
        row -> row.section === :category_functioning,
        fit_report_sections(practitioner_report),
    ))
    @test category_section.row_fields ==
        [:usage_rows, :threshold_rows, :warning_rows]
    @test category_section.n_rows ==
        length(report_categories.usage_rows) +
        length(report_categories.threshold_rows) + 1
    rater_section = only(filter(
        row -> row.section === :rater_homogeneity,
        fit_report_sections(practitioner_report),
    ))
    @test rater_section.row_fields == [:contrast_rows, :warning_rows]
    @test rater_section.n_rows == length(report_raters.contrast_rows)
    @test fit_report_rows(
        practitioner_report,
        :category_functioning;
        row_field = :usage_rows,
    ) === report_categories.usage_rows
    @test fit_report_rows(
        practitioner_report,
        :category_functioning;
        row_field = :threshold_rows,
    ) === report_categories.threshold_rows
    @test fit_report_rows(practitioner_report, :rater_homogeneity) ===
        report_raters.contrast_rows

    public_practitioner_report = fit_report_public(practitioner_report)
    @test public_practitioner_report.category_functioning.status === :computed
    @test public_practitioner_report.rater_homogeneity.status === :computed
    @test !hasproperty(
        public_practitioner_report.category_functioning,
        :data_signature,
    )
    @test !hasproperty(
        public_practitioner_report.rater_homogeneity,
        :data_signature,
    )
    @test length(public_practitioner_report.category_functioning.usage_rows) ==
        length(category_summary.usage_rows)
    @test length(public_practitioner_report.rater_homogeneity.contrast_rows) ==
        length(homogeneity.contrast_rows)
    practitioner_markdown = fit_report_markdown(
        public_practitioner_report;
        max_rows = 3,
    )
    @test occursin("## Warnings", practitioner_markdown)
    @test occursin("category_functioning_review_recommended",
        practitioner_markdown)
    @test occursin("### category_functioning / usage_rows",
        practitioner_markdown)
    @test occursin("### category_functioning / threshold_rows",
        practitioner_markdown)
    @test occursin("### rater_homogeneity / contrast_rows",
        practitioner_markdown)

    mktempdir() do directory
        path = joinpath(directory, "practitioner-report.json")
        save_fit_report(path, public_practitioner_report)
        loaded = load_fit_report(path)
        @test length(loaded["category_functioning"]["usage_rows"]) ==
            length(category_summary.usage_rows)
        @test length(loaded["rater_homogeneity"]["contrast_rows"]) ==
            length(homogeneity.contrast_rows)
        @test !haskey(loaded["category_functioning"], "data_signature")
        @test !haskey(loaded["rater_homogeneity"], "data_signature")
    end

    no_practitioner_report = fit_report(
        fit_result;
        include_category_functioning = false,
        include_rater_homogeneity = false,
        include_posterior_predictive = false,
        include_calibration = false,
        include_waic = false,
        include_loo = false,
        include_artifact = false,
    )
    @test no_practitioner_report.category_functioning.status === :not_requested
    @test no_practitioner_report.rater_homogeneity.status === :not_requested

    strict_overlap_report = fit_report(
        fit_result;
        include_category_functioning = false,
        include_posterior_predictive = false,
        include_calibration = false,
        include_waic = false,
        include_loo = false,
        include_artifact = false,
        draw_indices = 1:4,
        rater_min_shared_units = 100,
    )
    @test strict_overlap_report.report_status === :complete
    @test strict_overlap_report.rater_homogeneity.summary.n_contrasts == 6
    @test strict_overlap_report.rater_homogeneity.summary.n_disconnected_contrasts ==
        strict_overlap_report.rater_homogeneity.summary.n_contrasts
    @test strict_overlap_report.rater_homogeneity.summary.n_model_identification_unsupported_contrasts ==
        0
    @test strict_overlap_report.rater_homogeneity.summary.interpretation_supported
    @test strict_overlap_report.rater_homogeneity.n_warning_rows == 0

    invalid_category_report = fit_report(
        fit_result;
        category_functioning_min_count = 0,
        include_rater_homogeneity = false,
        include_posterior_predictive = false,
        include_calibration = false,
        include_waic = false,
        include_loo = false,
        include_artifact = false,
    )
    @test invalid_category_report.category_functioning.status === :error
    @test invalid_category_report.report_status === :incomplete
    @test :category_functioning in Tuple(
        row.section for row in
        invalid_category_report.report_health.error_sections)
    @test_throws ArgumentError fit_report(
        fit_result;
        category_functioning_min_count = 0,
        include_rater_homogeneity = false,
        include_posterior_predictive = false,
        include_calibration = false,
        include_waic = false,
        include_loo = false,
        include_artifact = false,
        on_section_error = :throw,
    )

    invalid_rater_report = fit_report(
        fit_result;
        include_category_functioning = false,
        rater_min_shared_units = 0,
        include_posterior_predictive = false,
        include_calibration = false,
        include_waic = false,
        include_loo = false,
        include_artifact = false,
    )
    @test invalid_rater_report.rater_homogeneity.status === :error
    @test invalid_rater_report.report_status === :incomplete
    @test :rater_homogeneity in Tuple(
        row.section for row in
        invalid_rater_report.report_health.error_sections)
    @test_throws ArgumentError fit_report(
        fit_result;
        include_category_functioning = false,
        rater_min_shared_units = 0,
        include_posterior_predictive = false,
        include_calibration = false,
        include_waic = false,
        include_loo = false,
        include_artifact = false,
        on_section_error = :throw,
    )

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

    single_rater_table = (;
        person = ["E1", "E1"],
        rater = ["R1", "R1"],
        item = ["I1", "I1"],
        score = [0, 1],
    )
    single_rater_data = FacetData(
        single_rater_table;
        person = :person,
        rater = :rater,
        item = :item,
        score = :score,
    )
    single_rater_design = getdesign(mfrm_spec(
        single_rater_data;
        thresholds = :rating_scale,
    ))
    single_rater_draws = zeros(
        64,
        length(single_rater_design.parameter_names),
    )
    single_rater_summary = rater_homogeneity_summary(
        single_rater_design,
        single_rater_draws;
        draw_indices = 1:64,
    )
    @test single_rater_summary.summary.n_raters == 1
    @test single_rater_summary.summary.n_contrasts == 0
    @test isempty(single_rater_summary.contrast_rows)
    @test !single_rater_summary.summary.pairwise_contrasts_available
    @test single_rater_summary.summary.contrast_availability ===
        :not_applicable_single_rater
    @test single_rater_summary.summary.rater_network_status === :single_rater
    @test single_rater_summary.summary.shared_unit_overlap_network_status ===
        :single_rater
    @test single_rater_summary.summary.model_identification_status ===
        :not_applicable_single_rater
    @test !single_rater_summary.summary.interpretation_supported
    @test single_rater_summary.summary.interpretation_status ===
        :not_applicable_single_rater
    @test single_rater_summary.caveat ===
        :pairwise_rater_homogeneity_not_applicable_single_rater

    single_rater_fit = MFRMFit(
        single_rater_design,
        MFRMPrior(),
        single_rater_draws,
        zeros(size(single_rater_draws, 1)),
        1.0,
        ones(Int, size(single_rater_draws, 1)),
        collect(1:size(single_rater_draws, 1)),
        [1.0],
        :julia,
        :random_walk_metropolis,
        0,
        0.1,
    )
    single_rater_report = fit_report(
        single_rater_fit;
        include_posterior_predictive = false,
        include_calibration = false,
        include_waic = false,
        include_loo = false,
        include_artifact = false,
        draw_indices = 1:64,
        rng = MersenneTwister(44),
        category_functioning_min_count = 1,
        category_functioning_min_proportion = 0.0,
    )
    @test single_rater_report.report_status === :complete
    @test single_rater_report.category_functioning.status === :computed
    @test single_rater_report.category_functioning.n_warning_rows == 0
    @test isempty(single_rater_report.category_functioning.warning_rows)
    @test single_rater_report.rater_homogeneity.status === :computed
    @test single_rater_report.rater_homogeneity.n_warning_rows == 0
    @test isempty(single_rater_report.rater_homogeneity.contrast_rows)
    @test single_rater_report.rater_homogeneity.summary.interpretation_status ===
        :not_applicable_single_rater
    single_rater_section = only(filter(
        row -> row.section === :rater_homogeneity,
        fit_report_sections(single_rater_report),
    ))
    @test single_rater_section.row_fields ==
        [:contrast_rows, :warning_rows]
    @test single_rater_section.n_rows == 0
    @test !occursin(
        "## Warnings",
        fit_report_markdown(single_rater_report),
    )
    single_rater_public_report = fit_report_public(single_rater_report)
    @test isempty(single_rater_public_report.rater_homogeneity.contrast_rows)
    @test single_rater_public_report.rater_homogeneity.summary.contrast_availability ===
        :not_applicable_single_rater
    @test !occursin(
        "### rater_homogeneity / contrast_rows",
        fit_report_markdown(single_rater_public_report),
    )
    single_rater_empty_markdown = fit_report_markdown(
        single_rater_public_report;
        include_empty = true,
    )
    @test occursin(
        "### rater_homogeneity / contrast_rows",
        single_rater_empty_markdown,
    )
    @test occursin("- Rows: 0", single_rater_empty_markdown)

    mktempdir() do directory
        report_path = joinpath(directory, "single-rater-report.json")
        save_fit_report(report_path, single_rater_public_report)
        loaded_report = load_fit_report(report_path)
        @test loaded_report["rater_homogeneity"]["status"] == "computed"
        @test isempty(
            loaded_report["rater_homogeneity"]["contrast_rows"],
        )
        @test loaded_report["rater_homogeneity"]["summary"]["contrast_availability"] ==
            "not_applicable_single_rater"
        loaded_rater_section = only(filter(
            row -> row.section === :rater_homogeneity,
            fit_report_sections(loaded_report),
        ))
        @test loaded_rater_section.row_fields ==
            [:contrast_rows, :warning_rows]
        @test loaded_rater_section.n_rows == 0

        table_directory = joinpath(directory, "tables")
        table_manifest = save_fit_report_tables(
            table_directory,
            loaded_report,
        )
        empty_contrast_manifest_row = only(filter(
            row -> row.section === :rater_homogeneity &&
                row.row_field === :contrast_rows,
            table_manifest.tables,
        ))
        @test empty_contrast_manifest_row.n_rows == 0
        @test isfile(joinpath(
            table_directory,
            empty_contrast_manifest_row.filename,
        ))
        loaded_tables = load_fit_report_tables(table_directory)
        loaded_empty_contrasts = only(filter(
            record -> record["section"] == "rater_homogeneity" &&
                record["row_field"] == "contrast_rows",
            loaded_tables,
        ))
        @test loaded_empty_contrasts["n_rows"] == 0
        @test isempty(loaded_empty_contrasts["rows"])

        bundle_directory = joinpath(directory, "bundle")
        bundle_manifest = save_fit_report_bundle(
            bundle_directory,
            loaded_report;
            include_empty = true,
        )
        @test bundle_manifest.report_content_hash.value ==
            single_rater_public_report.content_hash.value
        loaded_bundle_report = load_fit_report_bundle(bundle_directory)
        @test isempty(
            loaded_bundle_report["rater_homogeneity"]["contrast_rows"],
        )
        @test loaded_bundle_report["rater_homogeneity"]["summary"]["interpretation_status"] ==
            "not_applicable_single_rater"
        bundle_markdown = read(
            joinpath(bundle_directory, "fit_report.md"),
            String,
        )
        @test occursin(
            "### rater_homogeneity / contrast_rows",
            bundle_markdown,
        )
        bundle_tables = load_fit_report_tables(joinpath(
            bundle_directory,
            "tables",
        ))
        bundle_empty_contrasts = only(filter(
            record -> record["section"] == "rater_homogeneity" &&
                record["row_field"] == "contrast_rows",
            bundle_tables,
        ))
        @test bundle_empty_contrasts["n_rows"] == 0
        @test isempty(bundle_empty_contrasts["rows"])
    end

    declared_pcm_data = FacetData(
        table;
        person = :person,
        rater = :rater,
        item = :item,
        score = :score,
        category_levels = 0:3,
    )
    declared_pcm_validation = validate_design(declared_pcm_data)
    @test declared_pcm_validation.passed
    @test any(
        issue -> issue.code === :unobserved_declared_endpoint &&
            issue.severity === :warning,
        declared_pcm_validation.issues,
    )
    declared_pcm_design = getdesign(mfrm_spec(
        declared_pcm_data;
        thresholds = :partial_credit,
        validation_report = declared_pcm_validation,
    ))
    declared_pcm_draws = zeros(
        8,
        length(declared_pcm_design.parameter_names),
    )
    declared_pcm_fit = MFRMFit(
        declared_pcm_design,
        MFRMPrior(),
        declared_pcm_draws,
        zeros(size(declared_pcm_draws, 1)),
        1.0,
        ones(Int, size(declared_pcm_draws, 1)),
        collect(1:size(declared_pcm_draws, 1)),
        [1.0],
        :julia,
        :random_walk_metropolis,
        0,
        0.1,
    )
    declared_pcm_report = fit_report(
        declared_pcm_fit;
        include_rater_homogeneity = false,
        include_posterior_predictive = false,
        include_calibration = false,
        include_waic = false,
        include_loo = false,
        include_artifact = false,
        draw_indices = 1:8,
        rng = MersenneTwister(45),
    )
    @test declared_pcm_report.report_status === :complete
    @test declared_pcm_report.thresholds === :partial_credit
    @test declared_pcm_report.category_functioning.status === :computed
    @test length(declared_pcm_report.category_functioning.threshold_rows) ==
        length(declared_pcm_data.item_levels) *
        (length(declared_pcm_data.category_levels) - 1)
    @test Set(
        row.item for row in
        declared_pcm_report.category_functioning.threshold_rows
    ) == Set(declared_pcm_data.item_levels)
    declared_endpoint_rows = filter(
        row -> row.category == 3,
        declared_pcm_report.category_functioning.usage_rows,
    )
    @test length(declared_endpoint_rows) ==
        1 + length(declared_pcm_data.rater_levels) +
        length(declared_pcm_data.item_levels)
    @test all(row -> row.observed_count == 0, declared_endpoint_rows)
    @test all(row -> row.observed_flag === :skipped, declared_endpoint_rows)
    @test all(row -> row.review_recommended, declared_endpoint_rows)
    @test declared_pcm_report.category_functioning.n_warning_rows == 1
    declared_pcm_warning = only(
        declared_pcm_report.category_functioning.warning_rows,
    )
    @test declared_pcm_warning.n_affected_rows ==
        declared_pcm_report.category_functioning.summary.n_review_rows
    @test !declared_pcm_report.category_functioning.policy.automatic_category_collapse
    @test !declared_pcm_report.category_functioning.policy.refit_performed
    declared_pcm_public = fit_report_public(declared_pcm_report)
    @test any(
        row -> row.category == 3 && row.observed_flag === :skipped,
        declared_pcm_public.category_functioning.usage_rows,
    )
    @test length(declared_pcm_public.category_functioning.threshold_rows) == 9

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
