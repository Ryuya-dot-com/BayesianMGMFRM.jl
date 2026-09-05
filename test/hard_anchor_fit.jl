using Test
using BayesianMGMFRM
using ForwardDiff
using Random

@testset "stable individual hard-anchor fitting" begin
    table = (;
        person = ["P1", "P1", "P1", "P2", "P2", "P2"],
        rater = ["R1", "R2", "R1", "R1", "R2", "R1"],
        item = ["I1", "I1", "I2", "I1", "I2", "I2"],
        score = [0, 1, 2, 1, 0, 2],
    )
    data = FacetData(table;
        person = :person,
        rater = :rater,
        item = :item,
        score = :score)

    plain = getdesign(mfrm_spec(data))
    anchored_spec = mfrm_spec(data; anchors = [(;
        block = :rater,
        level = "R2",
        value = 0.25,
        type = :hard,
    )])
    @test anchored_spec.estimation_status === :fit_supported
    anchored = getdesign(anchored_spec)
    @test anchored.identification[:rater] === :hard_anchor
    @test anchored.identification[:item] === :reference_first
    @test anchored.parameter_names[anchored.blocks[:rater]] == ["rater[R1]"]
    @test "rater[R2]" ∉ anchored.parameter_names

    plain_params = zeros(length(plain.parameter_names))
    anchored_params = zeros(length(anchored.parameter_names))
    plain_params[only(plain.blocks[:rater])] = 0.25
    @test loglikelihood(plain, plain_params) ≈
        loglikelihood(anchored, anchored_params)
    @test logprior(anchored, anchored_params) >
        logprior(plain, plain_params)

    predictor_rows = linear_predictor_values(anchored, anchored_params)
    anchored_predictor = only(filter(
        row -> row.row == 2 && row.category_index == 2,
        predictor_rows,
    ))
    @test anchored_predictor.rater_parameter_status === :hard_anchor
    @test anchored_predictor.rater_parameter_index === missing
    @test anchored_predictor.rater_fixed_value === 0.25
    @test anchored_predictor.rater_value === 0.25
    @test anchored_predictor.location_value === -0.25

    draw_matrix = repeat(reshape(anchored_params, 1, :), 3, 1)
    wright_rows = wright_map_data(
        anchored,
        draw_matrix;
        facets = :rater,
        include_thresholds = false,
    )
    fixed_rater = only(filter(row -> row.level == "R2", wright_rows))
    free_rater = only(filter(row -> row.level == "R1", wright_rows))
    @test fixed_rater.status === :hard_anchor
    @test fixed_rater.is_fixed
    @test fixed_rater.fixed_value === 0.25
    @test fixed_rater.position_lower === 0.25
    @test fixed_rater.position_upper === 0.25
    @test free_rater.status === :estimated
    @test !free_rater.is_fixed

    rater_rows = rater_diagnostics(anchored, draw_matrix)
    fixed_rater_diagnostic = only(filter(row -> row.level == "R2", rater_rows))
    @test fixed_rater_diagnostic.severity_status === :hard_anchor
    @test fixed_rater_diagnostic.severity_is_fixed
    @test !fixed_rater_diagnostic.severity_reference
    @test fixed_rater_diagnostic.severity_fixed_value === 0.25
    @test fixed_rater_diagnostic.severity_lower === 0.25
    @test fixed_rater_diagnostic.severity_upper === 0.25

    manifest = model_manifest(anchored)
    fixed_coordinates = manifest.design.fixed_coordinates
    @test manifest.design.n_fixed_coordinates == 2
    @test any(row -> row.block === :rater && row.level == "R2" &&
        row.value === 0.25 && row.status === :hard_anchor && !row.sampled,
        fixed_coordinates)
    @test any(row -> row.block === :item && row.level == "I1" &&
        row.value === 0.0 && row.status === :reference_zero && !row.sampled,
        fixed_coordinates)
    public_manifest = model_manifest(anchored; view = :public)
    @test public_manifest.design.n_fixed_coordinates == 2
    @test public_manifest.design.fixed_coordinates == fixed_coordinates

    item_spec = mfrm_spec(data; anchors = [(;
        block = :item_difficulty,
        target = "I2",
        value = -0.3,
        type = :fixed,
    )])
    item_design = getdesign(item_spec)
    @test item_design.parameter_names[item_design.blocks[:item]] == ["item[I1]"]
    item_rows = design_row_table(item_design)
    fixed_item_row = only(filter(row -> row.row == 3, item_rows))
    @test fixed_item_row.item == "I2"
    @test fixed_item_row.item_parameter_status === :hard_anchor
    @test fixed_item_row.item_fixed_value === -0.3

    fully_anchored = getdesign(mfrm_spec(data; anchors = [
        (; block = :rater, level = "R1", value = -0.1, type = :hard),
        (; block = :rater, level = "R2", value = 0.2, type = :hard),
    ]))
    @test isempty(fully_anchored.blocks[:rater])
    fully_anchored_params = zeros(length(fully_anchored.parameter_names))
    fully_anchored_rows = linear_predictor_values(
        fully_anchored,
        fully_anchored_params,
    )
    @test all(row -> row.rater_parameter_status === :hard_anchor,
        fully_anchored_rows)
    fully_anchored_draws = repeat(
        reshape(fully_anchored_params, 1, :),
        3,
        1,
    )
    fully_anchored_homogeneity = rater_homogeneity_summary(
        fully_anchored,
        fully_anchored_draws;
        draw_indices = 1:3,
    )
    fixed_contrast = only(fully_anchored_homogeneity.contrast_rows)
    @test fixed_contrast.rater_a_status === :hard_anchor
    @test fixed_contrast.rater_b_status === :hard_anchor
    @test fixed_contrast.rater_a_is_fixed
    @test fixed_contrast.rater_b_is_fixed
    @test fixed_contrast.rater_a_fixed_value == -0.1
    @test fixed_contrast.rater_b_fixed_value == 0.2
    @test !fixed_contrast.rater_a_reference
    @test !fixed_contrast.rater_b_reference
    @test !fixed_contrast.rater_a_posterior_estimated
    @test !fixed_contrast.rater_b_posterior_estimated
    @test fixed_contrast.contrast_estimation_status === :fixed_contrast
    @test fixed_contrast.contrast_is_fixed
    @test !fixed_contrast.contrast_posterior_estimated
    @test fixed_contrast.contrast_interval_type ===
        :not_applicable_fixed_contrast
    @test ismissing(fixed_contrast.interval_probability)
    @test ismissing(fixed_contrast.lower_probability)
    @test ismissing(fixed_contrast.upper_probability)
    @test fixed_contrast.contrast_uncertainty_status ===
        :not_applicable_both_coordinates_fixed
    @test fixed_contrast.probability_basis === :fixed_contrast
    @test fixed_contrast.n_draws == 3
    @test fixed_contrast.n_uncertainty_draws == 0
    @test fixed_contrast.draw_role ===
        :fixed_value_replication_not_uncertainty
    @test fixed_contrast.caveat ===
        :fixed_contrast_not_posterior_uncertainty_or_score_agreement
    @test fixed_contrast.severity_difference_mean ≈ -0.3
    @test fixed_contrast.severity_difference_lower ≈ -0.3
    @test fixed_contrast.severity_difference_upper ≈ -0.3
    @test fixed_contrast.probability_negative == 1.0
    @test fully_anchored_homogeneity.summary.n_fixed_contrasts == 1
    @test fully_anchored_homogeneity.summary.n_partially_estimated_contrasts == 0
    @test fully_anchored_homogeneity.summary.n_posterior_estimated_contrasts == 0
    @test fully_anchored_homogeneity.summary.contains_fixed_contrasts
    @test fully_anchored_homogeneity.summary.contains_fixed_coordinate_contrasts
    @test fully_anchored_homogeneity.policy.fixed_coordinate_contrast_policy ===
        :label_fixed_partially_estimated_and_posterior_contrasts
    @test fully_anchored_homogeneity.policy.fixed_contrast_uncertainty ===
        :not_applicable
    @test fully_anchored_homogeneity.policy.interval_type_scope ===
        :nonfixed_contrasts_only
    @test fully_anchored_homogeneity.policy.fixed_contrast_interval_type ===
        :not_applicable_fixed_contrast
    @test fully_anchored_homogeneity.policy.fixed_contrast_interval_probabilities ===
        :not_applicable
    @test fully_anchored_homogeneity.caveat ===
        :fixed_severity_contrasts_are_not_posterior_uncertainty_or_score_agreement

    fully_anchored_fit = MFRMFit(
        fully_anchored,
        MFRMPrior(),
        fully_anchored_draws,
        zeros(size(fully_anchored_draws, 1)),
        1.0,
        ones(Int, size(fully_anchored_draws, 1)),
        collect(1:size(fully_anchored_draws, 1)),
        [1.0],
        :julia,
        :random_walk_metropolis,
        0,
        0.1,
    )
    fully_anchored_report = fit_report(
        fully_anchored_fit;
        include_category_functioning = false,
        include_posterior_predictive = false,
        include_calibration = false,
        include_waic = false,
        include_loo = false,
        include_artifact = false,
        draw_indices = 1:3,
    )
    @test fully_anchored_report.report_status === :complete
    @test fully_anchored_report.fixed_coordinates.summary.n_hard_anchors == 2
    @test fully_anchored_report.fixed_coordinates.summary.hard_anchor_counts ==
        (rater = 2, item = 0)
    @test fully_anchored_report.fixed_coordinates.summary.within_facet_anchor_contrast_restriction
    @test fully_anchored_report.fixed_coordinates.n_warning_rows == 3
    contrast_warning = only(filter(
        row -> row.code ===
            :multiple_hard_anchors_fix_within_facet_contrasts,
        fully_anchored_report.fixed_coordinates.warning_rows,
    ))
    @test contrast_warning.n_coordinates == 2
    @test contrast_warning.action ===
        :validate_anchor_contrasts_and_run_contamination_sensitivity
    @test occursin("within-facet contrasts", contrast_warning.message)
    @test fully_anchored_report.rater_homogeneity.status === :computed
    @test fully_anchored_report.rater_homogeneity.n_warning_rows == 0
    report_fixed_contrast = only(
        fully_anchored_report.rater_homogeneity.contrast_rows,
    )
    @test report_fixed_contrast.contrast_estimation_status === :fixed_contrast
    @test report_fixed_contrast.contrast_uncertainty_status ===
        :not_applicable_both_coordinates_fixed
    fully_anchored_public_report = fit_report_public(fully_anchored_report)
    @test fully_anchored_public_report.fixed_coordinates.n_warning_rows == 3
    @test fully_anchored_public_report.fixed_coordinates.summary.within_facet_anchor_contrast_restriction
    public_fixed_contrast = only(
        fully_anchored_public_report.rater_homogeneity.contrast_rows,
    )
    @test public_fixed_contrast.rater_a_status === :hard_anchor
    @test public_fixed_contrast.rater_b_status === :hard_anchor
    @test public_fixed_contrast.contrast_is_fixed
    @test !public_fixed_contrast.contrast_posterior_estimated
    @test public_fixed_contrast.probability_basis === :fixed_contrast

    duplicate_spec = mfrm_spec(data; anchors = [
        (; block = :rater, level = "R2", value = 0.2, type = :hard),
        (; block = :rater, level = "R2", value = 0.2, type = :hard),
    ])
    @test duplicate_spec.estimation_status === :specified_only
    @test_throws ArgumentError getdesign(duplicate_spec)

    soft_spec = mfrm_spec(data; anchors = [(;
        block = :rater,
        level = "R2",
        value = 0.2,
        type = :soft,
        scale = 0.1,
    )])
    @test soft_spec.estimation_status === :specified_only
    @test_throws ArgumentError getdesign(soft_spec)

    fitted = fit(anchored;
        ndraws = 4,
        warmup = 2,
        chains = 1,
        step_size = 0.02,
        seed = 20260815)
    @test size(fitted.draws) == (4, length(anchored.parameter_names))
    fitted_fixed = only(filter(
        row -> row.level == "R2",
        wright_map_data(fitted;
            facets = :rater,
            include_thresholds = false),
    ))
    @test fitted_fixed.status === :hard_anchor
    @test fitted_fixed.position_lower === 0.25
    @test fitted_fixed.position_upper === 0.25

    report = fit_report(fitted;
        include_posterior_predictive = false,
        include_category_functioning = false,
        include_rater_homogeneity = false,
        include_calibration = false,
        include_waic = false,
        include_loo = false,
        include_artifact = false,
    )
    @test report.report_status === :complete
    @test report.fixed_coordinates.status === :computed
    @test report.fixed_coordinates.schema ==
        "bayesianmgmfrm.fit_report_fixed_coordinates.v1"
    @test report.fixed_coordinates.n_rows == 2
    @test report.fixed_coordinates.n_warning_rows == 2
    @test report.fixed_coordinates.summary.n_hard_anchors == 1
    @test report.fixed_coordinates.summary.hard_anchor_counts ==
        (rater = 1, item = 0)
    @test report.fixed_coordinates.summary.n_default_reference_coordinates == 1
    @test report.fixed_coordinates.summary.hard_anchor_warning
    @test report.fixed_coordinates.summary.hard_anchor_value_uncertainty_status ===
        :not_propagated_exact_fixed_values
    @test report.fixed_coordinates.summary.hard_anchor_prior_coordinate_dependence
    @test !report.fixed_coordinates.summary.within_facet_anchor_contrast_restriction
    @test !report.fixed_coordinates.summary.fixed_coordinates_in_posterior_rows
    fixed_report_row = only(filter(
        row -> row.facet === :rater && row.level == "R2",
        report.fixed_coordinates.rows,
    ))
    @test fixed_report_row.parameter == "rater[R2]"
    @test fixed_report_row.fixed_value === 0.25
    @test fixed_report_row.constraint === :hard_anchor
    @test !fixed_report_row.sampled
    @test !fixed_report_row.prior_applied
    @test !fixed_report_row.posterior_estimated
    @test fixed_report_row.uncertainty_status ===
        :not_applicable_fixed_by_identification
    @test !any(row -> row.parameter == "rater[R2]", report.posterior.rows)
    anchor_warning = only(filter(
        row -> row.code === :hard_anchor_fixed_not_estimated,
        report.fixed_coordinates.warning_rows,
    ))
    @test anchor_warning.code === :hard_anchor_fixed_not_estimated
    @test anchor_warning.severity === :warning
    @test anchor_warning.n_coordinates == 1
    @test anchor_warning.action ===
        :interpret_fixed_coordinate_rows_as_constants
    @test occursin("excluded from posterior summaries", anchor_warning.message)
    @test occursin(
        "externally estimated anchor values is not propagated",
        anchor_warning.message,
    )
    prior_warning = only(filter(
        row -> row.code ===
            :hard_anchor_zero_centered_prior_coordinate_dependence,
        report.fixed_coordinates.warning_rows,
    ))
    @test prior_warning.severity === :warning
    @test prior_warning.n_coordinates == 1
    @test prior_warning.action ===
        :treat_anchor_and_free_coordinate_prior_as_joint_model_assumption
    @test occursin("not shifted with hard-anchor values", prior_warning.message)
    fixed_section = only(filter(
        row -> row.section === :fixed_coordinates,
        fit_report_sections(report),
    ))
    @test fixed_section.status === :computed
    @test fixed_section.row_fields == [:rows, :warning_rows]
    @test fixed_section.n_rows == 4
    @test fit_report_rows(report, :fixed_coordinates) ===
        report.fixed_coordinates.rows
    @test fit_report_rows(
        report,
        :fixed_coordinates;
        row_field = :warning_rows,
    ) === report.fixed_coordinates.warning_rows

    public_report = fit_report_public(report)
    @test public_report.fixed_coordinates.n_rows == 2
    @test public_report.fixed_coordinates.n_warning_rows == 2
    public_fixed = only(filter(
        row -> row.facet === :rater && row.level == "R2",
        public_report.fixed_coordinates.rows,
    ))
    @test public_fixed.fixed_value === 0.25
    @test public_fixed.constraint === :hard_anchor
    markdown = fit_report_markdown(public_report; max_rows = 4)
    @test occursin("## Warnings", markdown)
    @test occursin("hard_anchor_fixed_not_estimated", markdown)
    @test occursin(
        "hard_anchor_zero_centered_prior_coordinate_dependence",
        markdown,
    )
    @test occursin("### fixed_coordinates / rows", markdown)
    @test occursin("rater[R2]", markdown)
    @test occursin("0.25", markdown)

    combined_warning_report = fit_report(fitted;
        include_posterior_predictive = false,
        category_functioning_min_count = 100,
        category_functioning_min_proportion = 0.0,
        include_calibration = false,
        include_waic = false,
        include_loo = false,
        include_artifact = false,
        draw_indices = 1:4,
    )
    @test combined_warning_report.report_status === :complete
    @test combined_warning_report.fixed_coordinates.n_warning_rows == 2
    @test combined_warning_report.category_functioning.n_warning_rows == 1
    @test combined_warning_report.category_functioning.summary.n_review_rows >=
        combined_warning_report.category_functioning.summary.n_usage_rows
    combined_category_warning = only(
        combined_warning_report.category_functioning.warning_rows,
    )
    @test combined_category_warning.n_affected_rows ==
        combined_warning_report.category_functioning.summary.n_review_rows
    @test combined_warning_report.rater_homogeneity.n_warning_rows == 0
    mixed_contrast = only(
        combined_warning_report.rater_homogeneity.contrast_rows,
    )
    @test mixed_contrast.rater_a_status === :estimated
    @test mixed_contrast.rater_b_status === :hard_anchor
    @test !mixed_contrast.rater_a_reference
    @test !mixed_contrast.rater_b_reference
    @test mixed_contrast.contrast_estimation_status ===
        :partially_estimated_contrast
    @test mixed_contrast.contrast_uncertainty_status ===
        :posterior_uncertainty_from_estimated_coordinate_only
    @test mixed_contrast.interval_probability == 0.95
    @test mixed_contrast.lower_probability ≈ 0.025
    @test mixed_contrast.upper_probability ≈ 0.975
    @test mixed_contrast.n_uncertainty_draws == mixed_contrast.n_draws
    @test mixed_contrast.draw_role === :posterior_uncertainty
    @test mixed_contrast.caveat ===
        :posterior_contrast_includes_one_fixed_coordinate_not_score_agreement_or_bias_proof
    @test combined_warning_report.rater_homogeneity.summary.n_partially_estimated_contrasts ==
        1
    combined_markdown = fit_report_markdown(combined_warning_report)
    @test occursin("## Warnings", combined_markdown)
    @test occursin("hard_anchor_fixed_not_estimated", combined_markdown)
    @test occursin(
        "category_functioning_review_recommended",
        combined_markdown,
    )

    plain_fitted = fit(plain;
        ndraws = 2,
        warmup = 0,
        chains = 1,
        step_size = 0.02,
        seed = 20260817,
    )
    plain_report = fit_report(plain_fitted;
        include_posterior_predictive = false,
        include_category_functioning = false,
        include_rater_homogeneity = false,
        include_calibration = false,
        include_waic = false,
        include_loo = false,
        include_artifact = false,
    )
    @test plain_report.fixed_coordinates.n_rows == 2
    @test plain_report.fixed_coordinates.summary.n_hard_anchors == 0
    @test plain_report.fixed_coordinates.summary.hard_anchor_counts ==
        (rater = 0, item = 0)
    @test plain_report.fixed_coordinates.summary.n_default_reference_coordinates == 2
    @test isempty(plain_report.fixed_coordinates.warning_rows)
    @test !plain_report.fixed_coordinates.summary.hard_anchor_warning
    @test plain_report.fixed_coordinates.summary.hard_anchor_value_uncertainty_status ===
        :not_applicable
    @test !plain_report.fixed_coordinates.summary.hard_anchor_prior_coordinate_dependence
    @test !plain_report.fixed_coordinates.summary.within_facet_anchor_contrast_restriction
    @test !occursin("## Warnings", fit_report_markdown(plain_report))

    anchored_gradient = ForwardDiff.gradient(
        params -> logposterior(anchored, params),
        anchored_params,
    )
    @test length(anchored_gradient) == length(anchored.parameter_names)
    @test all(isfinite, anchored_gradient)
    hmc_fitted = fit(anchored;
        backend = :advancedhmc,
        ndraws = 2,
        warmup = 2,
        chains = 1,
        seed = 20260816,
        progress = false)
    @test size(hmc_fitted.draws) == (2, length(anchored.parameter_names))
    @test all(isfinite, hmc_fitted.log_posterior)

    mktempdir() do directory
        cache_path = joinpath(directory, "anchored-fit.jls")
        record = save_fit_cache(cache_path, fitted)
        loaded = load_fit_cache(cache_path)
        @test isequal(record.fit.design.spec.anchors, anchored_spec.anchors)
        @test loaded.design.parameter_names == anchored.parameter_names
        loaded_fixed = only(filter(
            row -> row.block === :rater && row.level == "R2",
            model_manifest(loaded).design.fixed_coordinates,
        ))
        @test loaded_fixed.value === 0.25
        @test loaded_fixed.status === :hard_anchor
        @test !loaded_fixed.sampled

        report_path = joinpath(directory, "anchored-fit-report.json")
        save_fit_report(report_path, public_report)
        loaded_report = load_fit_report(report_path)
        @test loaded_report["fixed_coordinates"]["n_rows"] == 2
        @test loaded_report["fixed_coordinates"]["n_warning_rows"] == 2
        loaded_fixed_report_row = only(filter(
            row -> row["facet"] == "rater" && row["level"] == "R2",
            loaded_report["fixed_coordinates"]["rows"],
        ))
        @test loaded_fixed_report_row["fixed_value"] == 0.25
        @test loaded_fixed_report_row["constraint"] == "hard_anchor"

        fully_anchored_report_path = joinpath(
            directory,
            "fully-anchored-fit-report.json",
        )
        save_fit_report(
            fully_anchored_report_path,
            fully_anchored_public_report,
        )
        loaded_fully_anchored_report = load_fit_report(
            fully_anchored_report_path,
        )
        @test any(
            row -> row["code"] ==
                "multiple_hard_anchors_fix_within_facet_contrasts",
            loaded_fully_anchored_report["fixed_coordinates"]["warning_rows"],
        )
        loaded_fixed_contrast = only(
            loaded_fully_anchored_report["rater_homogeneity"]["contrast_rows"],
        )
        @test loaded_fixed_contrast["rater_a_status"] == "hard_anchor"
        @test loaded_fixed_contrast["rater_b_status"] == "hard_anchor"
        @test loaded_fixed_contrast["contrast_estimation_status"] ==
            "fixed_contrast"
        @test loaded_fixed_contrast["contrast_uncertainty_status"] ==
            "not_applicable_both_coordinates_fixed"
        @test loaded_fixed_contrast["probability_basis"] == "fixed_contrast"
        @test loaded_fixed_contrast["interval_probability"] === nothing
        @test loaded_fixed_contrast["lower_probability"] === nothing
        @test loaded_fixed_contrast["upper_probability"] === nothing
    end
end

@testset "known-truth anchor gauge and contamination boundary" begin
    events = [(person, rater, item)
        for person in 1:4 for rater in 1:3 for item in 1:3]
    table = (;
        person = ["P$(row[1])" for row in events],
        rater = ["R$(row[2])" for row in events],
        item = ["I$(row[3])" for row in events],
        score = [mod(row[1] + 2row[2] + 3row[3], 4) for row in events],
    )
    data = FacetData(table;
        person = :person,
        rater = :rater,
        item = :item,
        score = :score,
        category_levels = 0:3)
    sparse_events = [(person, rater, item)
        for (person, rater) in ((1, 1), (2, 1), (2, 2), (3, 2), (3, 3), (4, 3))
        for item in 1:3]
    sparse_data = FacetData((;
        person = ["P$(row[1])" for row in sparse_events],
        rater = ["R$(row[2])" for row in sparse_events],
        item = ["I$(row[3])" for row in sparse_events],
        score = [mod(row[1] + 2row[2] + 3row[3], 4) for row in sparse_events],
    );
        person = :person,
        rater = :rater,
        item = :item,
        score = :score,
        category_levels = 0:3)
    person_truth = [-0.9, -0.3, 0.3, 0.9]
    rater_truth = [-0.6, 0.1, 0.5]
    item_truth = [-0.4, 0.2, 0.7]
    threshold_truth = [0.20, -0.10, -0.15, 0.05, 0.10, -0.20]

    function encoded_truth(truth_data, anchors)
        design = getdesign(mfrm_spec(truth_data;
            thresholds = :partial_credit,
            anchors))
        fixed = BayesianMGMFRM._stable_hard_anchor_map(design)
        rater_shifts = [value - rater_truth[index]
            for (index, value) in sort(collect(fixed[:rater]))]
        item_shifts = [value - item_truth[index]
            for (index, value) in sort(collect(fixed[:item]))]
        rater_shift = isempty(rater_shifts) ? -rater_truth[1] : first(rater_shifts)
        item_shift = isempty(item_shifts) ? -item_truth[1] : first(item_shifts)
        representable = all(shift -> shift ≈ rater_shift, rater_shifts) &&
            all(shift -> shift ≈ item_shift, item_shifts)
        free_raters = isempty(fixed[:rater]) ? (2:length(rater_truth)) :
            [index for index in eachindex(rater_truth)
                if !haskey(fixed[:rater], index)]
        free_items = isempty(fixed[:item]) ? (2:length(item_truth)) :
            [index for index in eachindex(item_truth)
                if !haskey(fixed[:item], index)]
        params = zeros(length(design.parameter_names))
        params[design.blocks[:person]] .=
            person_truth .+ rater_shift .+ item_shift
        params[design.blocks[:rater]] .= rater_truth[free_raters] .+ rater_shift
        params[design.blocks[:item]] .= item_truth[free_items] .+ item_shift
        params[design.blocks[:thresholds]] .= threshold_truth
        probabilities = dropdims(predictive_probabilities(
            design,
            reshape(params, 1, :),
        ); dims = 1)
        return (; design, params, probabilities, representable)
    end

    hard(block, level, value) = (; block, level, value, type = :hard)
    clean_raters = [
        hard(:rater, "R1", rater_truth[1]),
        hard(:rater, "R3", rater_truth[3]),
    ]
    clean_items = [
        hard(:item, "I1", item_truth[1]),
        hard(:item, "I3", item_truth[3]),
    ]
    scenarios = (
        (; name = :default_references, anchors = NamedTuple[], equivalent = true),
        (; name = :one_clean_rater,
            anchors = [clean_raters[1]], equivalent = true),
        (; name = :one_shifted_rater,
            anchors = [hard(:rater, "R3", rater_truth[3] + 0.4)],
            equivalent = true),
        (; name = :one_shifted_item,
            anchors = [hard(:item, "I3", item_truth[3] - 0.3)],
            equivalent = true),
        (; name = :one_shifted_each,
            anchors = [hard(:rater, "R3", rater_truth[3] + 0.4),
                hard(:item, "I3", item_truth[3] - 0.3)],
            equivalent = true),
        (; name = :two_clean_raters, anchors = clean_raters, equivalent = true),
        (; name = :two_clean_items, anchors = clean_items, equivalent = true),
        (; name = :two_clean_each,
            anchors = vcat(clean_raters, clean_items), equivalent = true),
        (; name = :contaminated_rater_contrast,
            anchors = [clean_raters[1],
                hard(:rater, "R3", rater_truth[3] + 0.4)],
            equivalent = false),
        (; name = :contaminated_item_contrast,
            anchors = [clean_items[1],
                hard(:item, "I3", item_truth[3] - 0.3)],
            equivalent = false),
        (; name = :contaminated_rater_and_item_contrasts,
            anchors = [clean_raters[1],
                hard(:rater, "R3", rater_truth[3] + 0.4),
                clean_items[1],
                hard(:item, "I3", item_truth[3] - 0.3)],
            equivalent = false),
    )

    for truth_data in (data, sparse_data)
        oracle = encoded_truth(truth_data, NamedTuple[])
        shifted_gauge = encoded_truth(truth_data, [
            hard(:rater, "R3", rater_truth[3] + 0.4),
            hard(:item, "I3", item_truth[3] - 0.3),
        ])
        prior_scales = (0.5, 1.0, 2.0, 4.0)
        logprior_gaps = [
            logprior(shifted_gauge.design, shifted_gauge.params,
                MFRMPrior(; person_sd = 1.5scale,
                    rater_sd = scale,
                    item_sd = scale,
                    step_sd = scale)) -
            logprior(oracle.design, oracle.params,
                MFRMPrior(; person_sd = 1.5scale,
                    rater_sd = scale,
                    item_sd = scale,
                    step_sd = scale))
            for scale in prior_scales
        ]
        @test loglikelihood(shifted_gauge.design, shifted_gauge.params) ≈
            loglikelihood(oracle.design, oracle.params) atol = 1e-12
        @test abs(logprior_gaps[2]) > 1e-6
        @test all(isapprox(gap * scale^2, logprior_gaps[2];
                rtol = 1e-12, atol = 1e-12)
            for (gap, scale) in zip(logprior_gaps, prior_scales))
        for scenario in scenarios
            candidate = encoded_truth(truth_data, scenario.anchors)
            @test candidate.representable == scenario.equivalent
            maximum_error = maximum(abs,
                candidate.probabilities .- oracle.probabilities)
            if scenario.equivalent
                @test maximum_error < 1e-12
            else
                @test maximum_error > 1e-4
                kl = sum(oracle.probabilities .* log.(
                    oracle.probabilities ./ candidate.probabilities))
                @test kl > 0

                sampled_log_score_gap = 0.0
                for seed in 1:100
                    rng = MersenneTwister(seed)
                    for row in axes(oracle.probabilities, 1)
                        category = searchsortedfirst(
                            cumsum(oracle.probabilities[row, :]),
                            rand(rng),
                        )
                        sampled_log_score_gap +=
                            log(oracle.probabilities[row, category]) -
                            log(candidate.probabilities[row, category])
                    end
                end
                @test sampled_log_score_gap > 0
            end
        end

        deletion_rows = NamedTuple[]
        for (block, prefix, truth, perturbation) in (
                (:rater, "R", rater_truth, 0.4),
                (:item, "I", item_truth, -0.3))
            for clean_index in eachindex(truth),
                    contaminated_index in eachindex(truth)
                clean_index == contaminated_index && continue
                clean = hard(block, "$prefix$clean_index", truth[clean_index])
                contaminated = hard(block, "$prefix$contaminated_index",
                    truth[contaminated_index] + perturbation)
                pair = encoded_truth(truth_data, [clean, contaminated])
                without_clean = encoded_truth(truth_data, [contaminated])
                without_contaminated = encoded_truth(truth_data, [clean])
                push!(deletion_rows, (;
                    pair_representable = pair.representable,
                    pair_error = maximum(abs,
                        pair.probabilities .- oracle.probabilities),
                    single_representable = without_clean.representable &&
                        without_contaminated.representable,
                    without_clean_error = maximum(abs,
                        without_clean.probabilities .- oracle.probabilities),
                    without_contaminated_error = maximum(abs,
                        without_contaminated.probabilities .-
                        oracle.probabilities),
                ))
            end
        end
        @test length(deletion_rows) == 12
        @test all(row -> !row.pair_representable, deletion_rows)
        @test minimum(row.pair_error for row in deletion_rows) > 1e-4
        @test all(row -> row.single_representable, deletion_rows)
        @test maximum(max(row.without_clean_error,
                row.without_contaminated_error) for row in deletion_rows) < 1e-12
    end
end

@testset "hard-anchor combination stress matrix" begin
    person = String[]
    rater = String[]
    item = String[]
    score = Int[]
    for p in 1:4, r in 1:3, i in 1:3
        push!(person, "P$p")
        push!(rater, "R$r")
        push!(item, "I$i")
        push!(score, mod(p + 2r + 3i, 4))
    end
    table = (; person, rater, item, score)
    data = FacetData(table;
        person = :person,
        rater = :rater,
        item = :item,
        score = :score)

    rater_anchors = NamedTuple[
        (; block = :rater_severity, facet_level = "R1", value = -40.0,
            kind = :fixed),
        (; block = :raters, target = "R2", value = -0.25, type = :hard),
        (; block = :rater, parameter = "R3", value = 40.0,
            anchor_type = :hard_anchor),
    ]
    item_anchors = NamedTuple[
        (; block = :item_difficulty, facet_level = "I1", value = 30.0,
            kind = :hard),
        (; block = :items, target = "I2", value = 0.5, type = :fixed),
        (; block = :item, parameter = "I3", value = -30.0,
            anchor_type = :hard_anchor),
    ]

    selected(mask, candidates) = NamedTuple[
        candidates[index]
        for index in eachindex(candidates)
        if !iszero(mask & (1 << (index - 1)))
    ]

    for thresholds in (:rating_scale, :partial_credit)
        plain = getdesign(mfrm_spec(data; thresholds))
        n_thresholds = thresholds === :rating_scale ? 2 : 6
        for rater_mask in 0:7, item_mask in 0:7
            anchors = vcat(
                selected(rater_mask, rater_anchors),
                selected(item_mask, item_anchors),
            )
            spec = mfrm_spec(data; thresholds, anchors)
            design = getdesign(spec)
            n_rater_anchors = count_ones(rater_mask)
            n_item_anchors = count_ones(item_mask)
            n_free_raters = iszero(rater_mask) ? 2 : 3 - n_rater_anchors
            n_free_items = iszero(item_mask) ? 2 : 3 - n_item_anchors
            @test length(design.parameter_names) ==
                4 + n_free_raters + n_free_items + n_thresholds

            manifest = model_manifest(design)
            @test manifest.design.n_fixed_coordinates ==
                (iszero(rater_mask) ? 1 : n_rater_anchors) +
                (iszero(item_mask) ? 1 : n_item_anchors)
            @test count(row -> row.status === :hard_anchor,
                manifest.design.fixed_coordinates) ==
                n_rater_anchors + n_item_anchors

            params = 0.03 .* collect(eachindex(design.parameter_names)) .- 0.2
            likelihood = loglikelihood(design, params)
            @test isfinite(likelihood)
            @test isfinite(logposterior(design, params))
            probabilities = predictive_probabilities(
                design,
                reshape(params, 1, :),
            )
            @test all(isfinite, probabilities)
            @test all(isapprox.(
                vec(sum(probabilities; dims = 3)),
                1.0;
                atol = 1e-12,
                rtol = 0,
            ))

            reversed_design = getdesign(mfrm_spec(data;
                thresholds,
                anchors = reverse(anchors),
            ))
            @test reversed_design.parameter_names == design.parameter_names
            @test model_manifest(reversed_design).design.fixed_coordinates ==
                manifest.design.fixed_coordinates
            @test loglikelihood(reversed_design, params) == likelihood

            rater_values = [
                BayesianMGMFRM._stable_facet_value(design, params, :rater, index)
                for index in eachindex(data.rater_levels)
            ]
            item_values = [
                BayesianMGMFRM._stable_facet_value(design, params, :item, index)
                for index in eachindex(data.item_levels)
            ]
            plain_params = similar(params, length(plain.parameter_names))
            plain_params[plain.blocks[:person]] .=
                params[design.blocks[:person]] .- item_values[1] .- rater_values[1]
            plain_params[plain.blocks[:rater]] .=
                rater_values[2:end] .- rater_values[1]
            plain_params[plain.blocks[:item]] .=
                item_values[2:end] .- item_values[1]
            plain_params[plain.blocks[:thresholds]] .= params[design.blocks[:thresholds]]
            @test loglikelihood(plain, plain_params) ≈ likelihood atol = 1e-10

            if !isempty(anchors)
                plan = anchor_refit_plan(spec; require_provenance = false)
                @test plan.candidate_supported
                @test plan.numerical_fit_supported
                @test plan.n_anchors == length(anchors)
            end
        end
    end

    mixed_anchors = vcat(selected(0b101, rater_anchors),
        selected(0b110, item_anchors))
    permuted_table = (;
        person = reverse(table.person),
        rater = reverse(table.rater),
        item = reverse(table.item),
        score = reverse(table.score),
    )
    original_design = getdesign(mfrm_spec(data;
        thresholds = :partial_credit,
        anchors = mixed_anchors,
    ))
    reordered_design = getdesign(mfrm_spec(data;
        thresholds = :partial_credit,
        anchors = reverse(mixed_anchors),
    ))
    @test design_identity(reordered_design).value ==
        design_identity(original_design).value
    @test fit_cache_key(reordered_design; seed = 20260904) ==
        fit_cache_key(original_design; seed = 20260904)
    changed_anchors = copy(mixed_anchors)
    changed_anchors[1] = merge(changed_anchors[1],
        (; value = changed_anchors[1].value + 0.1))
    changed_design = getdesign(mfrm_spec(data;
        thresholds = :partial_credit,
        anchors = changed_anchors,
    ))
    @test fit_cache_key(changed_design; seed = 20260904) !=
        fit_cache_key(original_design; seed = 20260904)
    permuted_design = getdesign(mfrm_spec(FacetData(permuted_table;
        person = :person,
        rater = :rater,
        item = :item,
        score = :score);
        thresholds = :partial_credit,
        anchors = mixed_anchors,
    ))
    @test Set(original_design.parameter_names) == Set(permuted_design.parameter_names)
    value_by_name = Dict(
        name => 0.001 * sum(codeunits(name))
        for name in original_design.parameter_names
    )
    original_params = [value_by_name[name] for name in original_design.parameter_names]
    permuted_params = [value_by_name[name] for name in permuted_design.parameter_names]
    @test loglikelihood(original_design, original_params) ≈
        loglikelihood(permuted_design, permuted_params) atol = 1e-10

    extreme_design = getdesign(mfrm_spec(data;
        thresholds = :partial_credit,
        anchors = vcat(rater_anchors, item_anchors),
    ))
    extreme_params = zeros(length(extreme_design.parameter_names))
    @test isempty(extreme_design.blocks[:rater])
    @test isempty(extreme_design.blocks[:item])
    @test all(isfinite, ForwardDiff.gradient(
        params -> logposterior(extreme_design, params),
        extreme_params,
    ))
    extreme_fit = fit(extreme_design;
        ndraws = 2,
        warmup = 0,
        chains = 1,
        step_size = 0.01,
        seed = 20260904,
    )
    @test size(extreme_fit.draws) == (2, length(extreme_design.parameter_names))
    @test all(isfinite, extreme_fit.log_posterior)

    mktempdir() do directory
        for thresholds in (:rating_scale, :partial_credit)
            fixed_fit = thresholds === :partial_credit ? extreme_fit : fit(
                mfrm_spec(data; thresholds,
                    anchors = vcat(rater_anchors, item_anchors));
                ndraws = 2, warmup = 0, chains = 1,
                step_size = 0.01, seed = 20260904)
            cache_path = joinpath(directory, "$(thresholds)-all-fixed.jls")
            save_fit_cache(cache_path, fixed_fit)
            restored = load_fit_cache(cache_path)
            @test isempty(restored.design.blocks[:rater])
            @test isempty(restored.design.blocks[:item])
            @test restored.design.parameter_names == fixed_fit.design.parameter_names
            @test restored.draws == fixed_fit.draws
            @test model_manifest(restored).design.fixed_coordinates ==
                model_manifest(fixed_fit).design.fixed_coordinates
            @test predictive_probabilities(restored.design, restored.draws) ==
                predictive_probabilities(fixed_fit.design, fixed_fit.draws)
            report = fit_report(restored;
                include_posterior_predictive = false,
                include_calibration = false, include_waic = false,
                include_loo = false, include_artifact = false)
            @test report.fixed_coordinates.summary.n_hard_anchors == 6
            report_path = joinpath(directory, "$(thresholds)-all-fixed.json")
            save_fit_report(report_path, fit_report_public(report))
            @test load_fit_report(report_path)["fixed_coordinates"]["summary"][
                "n_hard_anchors"] == 6
        end
    end

    disconnected_table = (;
        person = ["P1", "P1", "P2", "P2", "P3", "P3", "P4", "P4",
            "P5", "P5"],
        rater = ["R1", "R2", "R1", "R2", "R3", "R4", "R3", "R4",
            "R2", "R3"],
        item = fill("I1", 10),
        response_id = ["A", "A", "B", "B", "C", "C", "D", "D",
            "E-left", "E-right"],
        score = [0, 1, 1, 2, 0, 1, 1, 2, 1, 1],
    )
    linking_anchors = [
        (; block = :rater, level = "R1", value = -0.2, type = :hard),
        (; block = :rater, level = "R3", value = 0.3, type = :hard),
    ]
    disconnected_data = FacetData(disconnected_table;
        person = :person,
        rater = :rater,
        item = :item,
        response_id = :response_id,
        score = :score)
    disconnected_spec = mfrm_spec(disconnected_data; anchors = linking_anchors)
    @test disconnected_spec.estimation_status === :fit_supported
    disconnected = anchor_linking_summary(disconnected_spec; unit = :response_id)
    @test disconnected.anchor_status === :declared
    @test disconnected.n_hard_anchors == 2
    @test disconnected.rater_linking_status === :disconnected
    @test !disconnected.passed

    strictly_disconnected_data = FacetData((;
        person = disconnected_table.person[1:8],
        rater = disconnected_table.rater[1:8],
        item = disconnected_table.item[1:8],
        response_id = disconnected_table.response_id[1:8],
        score = disconnected_table.score[1:8],
    );
        person = :person,
        rater = :rater,
        item = :item,
        response_id = :response_id,
        score = :score)
    @test_throws ArgumentError mfrm_spec(strictly_disconnected_data;
        anchors = linking_anchors)

    graph_disconnected_data = FacetData((;
        person = disconnected_table.person[1:8],
        rater = disconnected_table.rater[1:8],
        item = vcat(fill("I1", 4), fill("I2", 4)),
        score = disconnected_table.score[1:8],
    );
        person = :person,
        rater = :rater,
        item = :item,
        score = :score)
    disconnected_suggestion = only(row for row in validation_suggestions(
        validate_design(graph_disconnected_data),
    ) if row.code === :disconnected_design)
    @test disconnected_suggestion.action === :add_links_or_split_design
    @test occursin(
        "Individual parameter anchors do not create graph links",
        disconnected_suggestion.suggestion,
    )
    @test_throws ArgumentError mfrm_spec(graph_disconnected_data;
        anchors = linking_anchors)

    bridged_table = merge(disconnected_table, (;
        response_id = vcat(disconnected_table.response_id[1:8], ["E", "E"]),
    ))
    bridged_data = FacetData(bridged_table;
        person = :person,
        rater = :rater,
        item = :item,
        response_id = :response_id,
        score = :score)
    bridged_spec = mfrm_spec(bridged_data; anchors = linking_anchors)
    @test anchor_linking_summary(bridged_spec;
        unit = :response_id,
        min_shared_units = 1,
    ).passed
    weak_bridge = anchor_linking_summary(bridged_spec;
        unit = :response_id,
        min_shared_units = 2,
    )
    @test weak_bridge.rater_linking_status === :disconnected
    @test weak_bridge.n_weak_links == 1
    @test !weak_bridge.passed

    invalid_combinations = (
        NamedTuple[
            (; block = :rater, level = "R2", value = 0.0, type = :hard),
            (; block = :rater_severity, target = "R2", value = 0.0,
                kind = :fixed),
        ],
        NamedTuple[
            (; block = :item, level = "I2", value = 0.0, type = :hard),
            (; block = :item_difficulty, target = "I2", value = 0.0,
                type = :soft, scale = 0.1),
        ],
        NamedTuple[
            (; block = :rater, level = "R1", value = 0.0, type = :hard,
                prior_scale = 0.1),
        ],
    )
    for anchors in invalid_combinations
        invalid_spec = mfrm_spec(data; anchors)
        @test invalid_spec.estimation_status === :specified_only
        @test_throws ArgumentError getdesign(invalid_spec)
        @test !anchor_refit_plan(invalid_spec;
            require_provenance = false).candidate_supported
    end
end
