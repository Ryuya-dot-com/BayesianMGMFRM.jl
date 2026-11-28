function check_gmfrm_recovery_smoke_fixture(fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) == "bayesianmgmfrm.gmfrm_recovery_smoke.v1"
    @test String(fixture[:family]) == "gmfrm"
    @test String(fixture[:scope]) == "scalar_gmfrm_fit_ready_candidate"
    @test String(fixture[:status]) == "internal_promotion_candidate"
    @test Bool(fixture[:public_fit]) == false
    @test Bool(fixture[:experimental_public]) == false
    @test Bool(fixture[:fit_ready]) == false
    @test String(fixture[:target]) == "_gmfrm_promotion_candidate_logdensity"

    protocol = fixture[:protocol]
    grid = protocol[:grid]
    sampler = protocol[:sampler]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) == "scalar_gmfrm_recovery_smoke_v1"
    @test Int(protocol[:simulation_seed]) == 20260701
    @test Int(protocol[:sampler_seed]) == 20260702
    @test Int(grid[:persons]) == 4
    @test Int(grid[:items]) == 3
    @test Int(grid[:raters]) == 3
    @test Int(grid[:categories]) == 3
    @test String(grid[:rating_density]) == "full_crossed"
    @test Int(grid[:observations]) == 36
    @test String(sampler[:backend]) == "advancedhmc"
    @test String(sampler[:sampler]) == "nuts"
    @test Int(sampler[:chains]) == 2
    @test Int(sampler[:warmup]) == 64
    @test Int(sampler[:draws]) == 64
    @test Float64(sampler[:target_accept]) == 0.85
    @test Int(sampler[:max_depth]) == 6
    @test String(sampler[:metric]) == "unit"
    @test Float64(thresholds[:max_rhat]) == 1.2
    @test Float64(thresholds[:min_ess]) == 12.0
    @test Float64(thresholds[:min_ebfmi]) == 0.3
    @test Float64(thresholds[:max_block_mean_absolute_error]) == 0.5
    @test Float64(thresholds[:max_parameter_absolute_error]) == 1.0
    @test Float64(thresholds[:min_block_coverage_rate]) == 0.5

    raw_names = Vector{String}(fixture[:raw_parameter_order])
    direct_names = Vector{String}(fixture[:direct_parameter_order])
    @test length(raw_names) == 17
    @test length(direct_names) == 19
    @test String(fixture[:raw_parameter_order_sha256]) == test_parameter_order_hash(raw_names)
    @test String(fixture[:direct_parameter_order_sha256]) ==
        test_parameter_order_hash(direct_names)
    @test length(Vector{Float64}(fixture[:truth][:raw_parameter_values])) == length(raw_names)
    @test length(Vector{Float64}(fixture[:truth][:direct_parameter_values])) ==
        length(direct_names)

    simulated = fixture[:simulated_data]
    @test Int(simulated[:n_observations]) == Int(grid[:observations])
    @test sum(Int(row[:n]) for row in simulated[:score_counts]) == Int(grid[:observations])
    @test Set(Int(row[:score]) for row in simulated[:score_counts]) == Set([0, 1, 2])
    @test length(simulated[:person_levels]) == Int(grid[:persons])
    @test length(simulated[:rater_levels]) == Int(grid[:raters])
    @test length(simulated[:item_levels]) == Int(grid[:items])

    sampler_summary = fixture[:sampler_summary]
    @test String(sampler_summary[:internal_flag]) == "ok"
    @test Bool(sampler_summary[:internal_passed])
    @test Int(sampler_summary[:n_chains]) == Int(sampler[:chains])
    @test Int(sampler_summary[:draws_per_chain]) == Int(sampler[:draws])
    @test Int(sampler_summary[:total_draws]) ==
        Int(sampler[:chains]) * Int(sampler[:draws])
    @test Float64(sampler_summary[:max_rhat]) <= Float64(thresholds[:max_rhat])
    @test Float64(sampler_summary[:min_ess]) >= Float64(thresholds[:min_ess])
    @test Float64(sampler_summary[:e_bfmi]) >= Float64(thresholds[:min_ebfmi])
    @test Int(sampler_summary[:n_divergences]) == 0
    @test Int(sampler_summary[:n_max_treedepth]) == 0
    @test Int(sampler_summary[:n_failed_direct_constraints]) == 0
    @test Int(sampler_summary[:n_nonfinite_logdensity]) == 0
    @test Int(sampler_summary[:n_nonfinite_direct_loglikelihood]) == 0

    recovery_rows = fixture[:recovery_rows]
    recovery_by_block = fixture[:recovery_by_block]
    @test length(recovery_rows) == length(direct_names)
    @test length(recovery_by_block) == 6
    @test Set(String(row[:group]) for row in recovery_by_block) == Set([
        "person",
        "rater",
        "item",
        "item_discrimination",
        "rater_consistency",
        "rater_steps",
    ])
    @test all(row -> Float64(row[:absolute_bias]) <=
        Float64(thresholds[:max_parameter_absolute_error]), recovery_rows)
    @test all(row -> Float64(row[:mean_absolute_error]) <=
        Float64(thresholds[:max_block_mean_absolute_error]), recovery_by_block)
    @test all(row -> Float64(row[:coverage_rate]) >=
        Float64(thresholds[:min_block_coverage_rate]), recovery_by_block)

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Int(summary[:n_parameters]) == length(direct_names)
    @test Int(summary[:n_blocks]) == length(recovery_by_block)
    @test Float64(summary[:max_block_mean_absolute_error]) <=
        Float64(thresholds[:max_block_mean_absolute_error])
    @test Float64(summary[:max_parameter_absolute_error]) <=
        Float64(thresholds[:max_parameter_absolute_error])
    @test Float64(summary[:min_block_coverage_rate]) >=
        Float64(thresholds[:min_block_coverage_rate])
    @test String(fixture[:baseline_comparison][:status]) == "pending"
end

function check_gmfrm_baseline_comparison_fixture(fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) == "bayesianmgmfrm.gmfrm_baseline_comparison.v1"
    @test String(fixture[:family]) == "gmfrm"
    @test String(fixture[:scope]) == "scalar_gmfrm_fit_ready_candidate"
    @test String(fixture[:status]) == "internal_baseline_comparison"
    @test Bool(fixture[:public_fit]) == false
    @test Bool(fixture[:experimental_public]) == false
    @test Bool(fixture[:fit_ready]) == false

    protocol = fixture[:protocol]
    @test String(protocol[:protocol_id]) == "scalar_gmfrm_baseline_comparison_v1"
    @test String(protocol[:simulation_source]) == "scalar_gmfrm_recovery_smoke_v1"
    @test Int(protocol[:simulation_seed]) == 20260701
    @test Int(protocol[:thresholds][:minimum_models]) == 3
    @test Int(protocol[:thresholds][:n_observations]) == 36
    @test Bool(protocol[:thresholds][:require_same_observations])
    @test Bool(protocol[:thresholds][:require_finite_elpd])
    @test Bool(protocol[:thresholds][:require_finite_weights])
    @test String(protocol[:gmfrm_sampler][:backend]) == "advancedhmc"
    @test Int(protocol[:gmfrm_sampler][:draws]) == 64
    @test String(protocol[:baseline_sampler][:backend]) == "advancedhmc"
    @test Int(protocol[:baseline_sampler][:draws]) == 64
    @test Int(protocol[:baseline_sampler][:seeds][:partial_credit]) == 20260742
    @test Int(protocol[:baseline_sampler][:seeds][:rating_scale]) == 20260743

    simulated = fixture[:simulated_data]
    @test Int(simulated[:n_observations]) == 36
    @test sum(Int(row[:n]) for row in simulated[:score_counts]) == 36
    @test length(simulated[:person_levels]) == 4
    @test length(simulated[:rater_levels]) == 3
    @test length(simulated[:item_levels]) == 3
    @test Set(Int(level) for level in simulated[:category_levels]) == Set([0, 1, 2])
    @test String(simulated[:truth_source]) == "gmfrm_recovery_smoke_truth"

    model_rows = fixture[:model_rows]
    @test length(model_rows) == 3
    @test [Int(row[:rank]) for row in model_rows] == [1, 2, 3]
    @test issorted([Float64(row[:elpd_waic]) for row in model_rows]; rev = true)
    @test Set(String(row[:model]) for row in model_rows) == Set([
        "gmfrm_internal_candidate",
        "mfrm_partial_credit",
        "mfrm_rating_scale",
    ])
    @test all(row -> Int(row[:n_observations]) == 36, model_rows)
    @test all(row -> Int(row[:n_draws]) == 128, model_rows)
    @test all(row -> isfinite(Float64(row[:elpd_waic])), model_rows)
    @test all(row -> isfinite(Float64(row[:waic])), model_rows)
    @test all(row -> isfinite(Float64(row[:relative_weight])), model_rows)
    @test sum(Float64(row[:relative_weight]) for row in model_rows) ≈ 1.0
    @test all(row -> String(row[:criterion]) == "waic", model_rows)
    @test all(row -> String(row[:warning]) in ("ok", "high_loglik_variance"),
        model_rows)
    @test all(row -> Bool(row[:sampler_summary][:internal_passed]), model_rows)
    @test all(row -> Int(row[:sampler_summary][:n_divergences]) == 0, model_rows)
    @test all(row -> Int(row[:sampler_summary][:n_max_treedepth]) == 0,
        model_rows)

    gmfrm_row = only(row for row in model_rows
        if String(row[:model]) == "gmfrm_internal_candidate")
    @test String(gmfrm_row[:family]) == "gmfrm"
    @test String(gmfrm_row[:source]) == "internal_raw_candidate"
    @test String(gmfrm_row[:threshold_regime]) == "generalized_partial_credit"
    @test Bool(gmfrm_row[:public_fit]) == false
    @test Int(gmfrm_row[:n_parameters]) == 17
    @test String(simulated[:raw_parameter_order_sha256]) ==
        String(gmfrm_row[:parameter_order_sha256])
    @test String(simulated[:direct_parameter_order_sha256]) ==
        String(gmfrm_row[:direct_parameter_order_sha256])
    @test Float64(gmfrm_row[:elpd_difference]) <= 0.0
    @test Float64(gmfrm_row[:se_elpd_difference]) >
        abs(Float64(gmfrm_row[:elpd_difference]))

    baseline_rows = [row for row in model_rows if String(row[:family]) == "mfrm"]
    @test length(baseline_rows) == 2
    @test all(row -> String(row[:source]) == "public_minimal_fit", baseline_rows)
    @test all(row -> Bool(row[:public_fit]), baseline_rows)
    @test Set(String(row[:threshold_regime]) for row in baseline_rows) ==
        Set(["partial_credit", "rating_scale"])

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:comparison_executed])
    @test Int(summary[:n_models]) == length(model_rows)
    @test String(summary[:best_model]) == String(model_rows[1][:model])
    @test Int(summary[:gmfrm_rank]) == Int(gmfrm_row[:rank])
    @test Float64(summary[:gmfrm_elpd_difference]) ≈
        Float64(gmfrm_row[:elpd_difference])
    @test Float64(summary[:gmfrm_relative_weight]) ≈
        Float64(gmfrm_row[:relative_weight])
    @test Bool(summary[:any_high_variance_waic])
    @test String(summary[:recommendation]) ==
        "keep_internal_until_guarded_exposure_decision"
end

function check_gmfrm_baseline_calibration_grid_fixture(fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) == "bayesianmgmfrm.gmfrm_baseline_calibration_grid.v1"
    @test String(fixture[:family]) == "gmfrm"
    @test String(fixture[:scope]) == "scalar_gmfrm_fit_ready_candidate"
    @test String(fixture[:status]) == "internal_baseline_calibration_grid"
    @test Bool(fixture[:public_fit]) == false
    @test Bool(fixture[:experimental_public]) == false
    @test Bool(fixture[:fit_ready]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) == "scalar_gmfrm_baseline_calibration_grid_v1"
    @test String(protocol[:simulation_source]) == "scalar_gmfrm_recovery_smoke_grid_variant"
    @test Set(String(model) for model in protocol[:models]) == Set([
        "gmfrm_internal_candidate",
        "mfrm_partial_credit",
        "mfrm_rating_scale",
    ])
    @test String(protocol[:calibration][:target]) == "expected_score"
    @test Int(protocol[:calibration][:bins]) == 3
    @test Int(thresholds[:n_scenarios]) == 3
    @test Int(thresholds[:n_models_per_scenario]) == 3
    @test Int(thresholds[:n_observations]) == 36
    @test Bool(thresholds[:require_all_scenarios_passed])
    @test Bool(thresholds[:require_same_observations])
    @test Bool(thresholds[:require_finite_elpd])
    @test Bool(thresholds[:require_finite_calibration])
    @test Bool(thresholds[:require_sampler_passed])
    @test Float64(thresholds[:max_expected_score_rmse]) == 1.25
    @test Float64(thresholds[:max_mean_absolute_calibration_error]) == 0.75

    scenarios = fixture[:scenarios]
    @test length(scenarios) == Int(thresholds[:n_scenarios])
    @test Set(String(scenario[:scenario]) for scenario in scenarios) == Set([
        "near_rasch",
        "moderate_generalized",
        "stronger_generalized",
    ])
    for scenario in scenarios
        simulated = scenario[:simulated_data]
        @test Int(simulated[:n_observations]) == Int(thresholds[:n_observations])
        @test sum(Int(row[:n]) for row in simulated[:score_counts]) ==
            Int(thresholds[:n_observations])
        @test Set(Int(row[:score]) for row in simulated[:score_counts]) ==
            Set([0, 1, 2])
        @test length(simulated[:person_levels]) == 4
        @test length(simulated[:rater_levels]) == 3
        @test length(simulated[:item_levels]) == 3
        @test Set(Int(level) for level in simulated[:category_levels]) == Set([0, 1, 2])

        model_rows = scenario[:model_rows]
        @test length(model_rows) == Int(thresholds[:n_models_per_scenario])
        @test [Int(row[:rank]) for row in model_rows] == [1, 2, 3]
        @test issorted([Float64(row[:elpd_waic]) for row in model_rows]; rev = true)
        @test Set(String(row[:model]) for row in model_rows) == Set([
            "gmfrm_internal_candidate",
            "mfrm_partial_credit",
            "mfrm_rating_scale",
        ])
        @test all(row -> Int(row[:n_observations]) == Int(thresholds[:n_observations]),
            model_rows)
        @test all(row -> Int(row[:n_draws]) == 128, model_rows)
        @test all(row -> isfinite(Float64(row[:elpd_waic])) &&
            isfinite(Float64(row[:waic])), model_rows)
        @test all(row -> isfinite(Float64(row[:relative_weight])), model_rows)
        @test sum(Float64(row[:relative_weight]) for row in model_rows) ≈ 1.0
        @test all(row -> Bool(row[:sampler_summary][:internal_passed]), model_rows)
        @test all(row -> Int(row[:sampler_summary][:n_divergences]) == 0, model_rows)
        @test all(row -> Int(row[:sampler_summary][:n_max_treedepth]) == 0,
            model_rows)
        @test all(row -> length(row[:expected_score_calibration]) == 3, model_rows)
        @test all(row -> Float64(row[:predictive_metrics][:expected_score_rmse]) <=
            Float64(thresholds[:max_expected_score_rmse]), model_rows)
        @test all(row -> Float64(row[:predictive_metrics][:mean_absolute_calibration_error]) <=
            Float64(thresholds[:max_mean_absolute_calibration_error]), model_rows)
        @test all(row -> String(row[:warning]) in ("ok", "high_loglik_variance"),
            model_rows)

        gmfrm_row = only(row for row in model_rows
            if String(row[:model]) == "gmfrm_internal_candidate")
        @test String(gmfrm_row[:family]) == "gmfrm"
        @test String(gmfrm_row[:source]) == "internal_raw_candidate"
        @test Bool(gmfrm_row[:public_fit]) == false
        @test Int(gmfrm_row[:n_parameters]) == 17
        @test String(gmfrm_row[:direct_parameter_order_sha256]) != "null"

        baseline_rows = [row for row in model_rows if String(row[:family]) == "mfrm"]
        @test length(baseline_rows) == 2
        @test all(row -> String(row[:source]) == "public_minimal_fit", baseline_rows)
        @test all(row -> Bool(row[:public_fit]), baseline_rows)

        summary = scenario[:summary]
        @test Bool(summary[:passed])
        @test String(summary[:best_model]) == String(model_rows[1][:model])
        @test Int(summary[:gmfrm_rank]) == Int(gmfrm_row[:rank])
        @test Float64(summary[:gmfrm_expected_score_rmse]) ≈
            Float64(gmfrm_row[:predictive_metrics][:expected_score_rmse])
        @test Float64(summary[:gmfrm_mean_absolute_calibration_error]) ≈
            Float64(gmfrm_row[:predictive_metrics][:mean_absolute_calibration_error])
    end

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Int(summary[:n_scenarios]) == length(scenarios)
    @test Int(summary[:n_passed_scenarios]) == length(scenarios)
    @test Int(summary[:n_models]) == length(scenarios) * Int(thresholds[:n_models_per_scenario])
    @test Int(summary[:n_public_baseline_models]) == 2 * length(scenarios)
    @test Int(summary[:n_internal_candidate_models]) == length(scenarios)
    @test sum(Int(row[:n]) for row in summary[:best_model_counts]) == length(scenarios)
    @test Float64(summary[:max_expected_score_rmse]) <=
        Float64(thresholds[:max_expected_score_rmse])
    @test Float64(summary[:max_mean_absolute_calibration_error]) <=
        Float64(thresholds[:max_mean_absolute_calibration_error])
    @test Bool(summary[:any_high_variance_waic])
    @test String(summary[:recommendation]) ==
        "keep_internal_until_public_exposure_review"
end

function check_gmfrm_interval_decision_grid_fixture(fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) == "bayesianmgmfrm.gmfrm_interval_decision_grid.v1"
    @test String(fixture[:family]) == "gmfrm"
    @test String(fixture[:scope]) == "scalar_gmfrm_fit_ready_candidate"
    @test String(fixture[:status]) == "internal_interval_decision_grid"
    @test Bool(fixture[:public_fit]) == false
    @test Bool(fixture[:experimental_public]) == false
    @test Bool(fixture[:fit_ready]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) == "scalar_gmfrm_interval_decision_grid_v1"
    @test String(protocol[:simulation_source]) == "scalar_gmfrm_baseline_calibration_grid_v1"
    @test Set(String(scenario) for scenario in protocol[:scenarios]) == Set([
        "near_rasch",
        "moderate_generalized",
        "stronger_generalized",
    ])
    @test Set(Float64(interval) for interval in protocol[:intervals]) == Set([0.8, 0.95])
    @test Set(String(model) for model in protocol[:models]) == Set([
        "gmfrm_internal_candidate",
        "mfrm_partial_credit",
        "mfrm_rating_scale",
    ])
    @test String(protocol[:decision_rules][:prediction_target]) == "same_observation_waic"
    @test String(protocol[:decision_rules][:public_exposure_decision]) == "keep_internal"
    @test Bool(protocol[:decision_rules][:require_all_samplers_passed])
    @test Bool(protocol[:decision_rules][:high_variance_waic_blocks_public_exposure])
    @test Bool(protocol[:decision_rules][:sparse_design_grid_required_before_exposure])
    @test Bool(protocol[:decision_rules][:psis_loo_or_influence_review_required_before_exposure])
    @test Int(thresholds[:n_scenarios]) == 3
    @test Int(thresholds[:n_models_per_scenario]) == 3
    @test Int(thresholds[:n_observations]) == 36
    @test Bool(thresholds[:require_same_observations])
    @test Bool(thresholds[:require_sampler_passed])
    @test Bool(thresholds[:require_finite_intervals])
    @test Bool(thresholds[:require_decision_stability])

    scenarios = fixture[:scenarios]
    @test length(scenarios) == Int(thresholds[:n_scenarios])
    @test Set(String(scenario[:scenario]) for scenario in scenarios) ==
        Set(String(scenario) for scenario in protocol[:scenarios])
    for scenario in scenarios
        simulated = scenario[:simulated_data]
        @test Int(simulated[:n_observations]) == Int(thresholds[:n_observations])
        @test sum(Int(row[:n]) for row in simulated[:score_counts]) ==
            Int(thresholds[:n_observations])
        @test length(scenario[:gmfrm_parameter_order]) == 19
        @test String(scenario[:gmfrm_parameter_order_sha256]) != "null"

        model_rows = scenario[:model_rows]
        @test length(model_rows) == Int(thresholds[:n_models_per_scenario])
        @test [Int(row[:rank]) for row in model_rows] == [1, 2, 3]
        @test all(row -> Int(row[:n_observations]) == Int(thresholds[:n_observations]),
            model_rows)
        @test all(row -> Bool(row[:sampler_summary][:internal_passed]), model_rows)
        gmfrm_row = only(row for row in model_rows
            if String(row[:model]) == "gmfrm_internal_candidate")
        @test String(gmfrm_row[:family]) == "gmfrm"
        @test Bool(gmfrm_row[:public_fit]) == false
        @test Int(gmfrm_row[:n_parameters]) == 17
        @test String(gmfrm_row[:direct_parameter_order_sha256]) ==
            String(scenario[:gmfrm_parameter_order_sha256])

        interval_rows = scenario[:interval_coverage]
        @test length(interval_rows) == 2
        @test Set(Float64(row[:interval_probability]) for row in interval_rows) ==
            Set([0.8, 0.95])
        for interval_row in interval_rows
            @test length(interval_row[:recovery_by_block]) == 6
            @test Int(interval_row[:summary][:n_parameters]) == 19
            @test Int(interval_row[:summary][:n_blocks]) == 6
            @test Bool(interval_row[:summary][:all_intervals_finite])
            @test Float64(interval_row[:summary][:overall_coverage_rate]) >= 0.8
            @test Float64(interval_row[:summary][:min_block_coverage_rate]) >= 0.0
            @test all(row -> String(row[:flag]) in ("ok", "coverage_below_nominal"),
                interval_row[:recovery_by_block])
        end

        decision = scenario[:decision]
        @test String(decision[:selected_decision]) == "keep_internal"
        @test Bool(decision[:public_fit_allowed]) == false
        @test Bool(decision[:experimental_keyword_enabled]) == false
        @test String(decision[:prediction_target]) == "same_observation_waic"
        @test Bool(decision[:all_samplers_passed])
        @test Bool(decision[:any_high_variance_waic])
        @test Set(String(row[:blocker]) for row in decision[:blocker_rows]) ==
            Set(["high_variance_waic_requires_followup", "sparse_design_grid_missing"])

        summary = scenario[:summary]
        @test Bool(summary[:passed])
        @test String(summary[:selected_decision]) == "keep_internal"
        @test Bool(summary[:any_high_variance_waic])
        @test Float64(summary[:min_interval_coverage_rate]) >= 0.8
        @test Float64(summary[:min_block_coverage_rate]) >= 0.0
    end

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Int(summary[:n_scenarios]) == length(scenarios)
    @test Int(summary[:n_passed_scenarios]) == length(scenarios)
    @test Int(summary[:n_interval_records]) == 2 * length(scenarios)
    @test Int(summary[:n_models]) == 3 * length(scenarios)
    @test Bool(summary[:all_local_intervals_finite])
    @test Float64(summary[:min_interval_coverage_rate]) >= 0.8
    @test Float64(summary[:min_block_coverage_rate]) >= 0.0
    @test Int(summary[:keep_internal_decision_count]) == length(scenarios)
    @test String(summary[:decision_stability]) == "stable_keep_internal"
    @test Bool(summary[:any_high_variance_waic])
    @test Set(String(blocker) for blocker in summary[:remaining_public_blockers]) ==
        Set(["high_variance_waic_requires_followup", "sparse_design_grid_missing"])
    @test String(summary[:recommendation]) == "keep_internal_until_sparse_and_waic_followup"
    @test String(summary[:next_gate]) == "scalar_gmfrm_sparse_design_grid"
end

function check_gmfrm_sparse_design_grid_fixture(fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) == "bayesianmgmfrm.gmfrm_sparse_design_grid.v1"
    @test String(fixture[:family]) == "gmfrm"
    @test String(fixture[:scope]) == "scalar_gmfrm_fit_ready_candidate"
    @test String(fixture[:status]) == "internal_sparse_design_grid"
    @test Bool(fixture[:public_fit]) == false
    @test Bool(fixture[:experimental_public]) == false
    @test Bool(fixture[:fit_ready]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) == "scalar_gmfrm_sparse_design_grid_v1"
    @test String(protocol[:simulation_source]) == "scalar_gmfrm_interval_decision_grid_v1"
    @test Int(protocol[:full_crossed_observations]) == 36
    @test String(protocol[:sparse_designs][:rating_density]) == "sparse_connected"
    @test Set(String(pattern) for pattern in protocol[:sparse_designs][:patterns]) ==
        Set(["half_crossed_parity", "reference_bridge", "cyclic_missing_item_cells"])
    @test String(protocol[:validation][:bias_terms][1][1]) == "rater"
    @test String(protocol[:validation][:bias_terms][1][2]) == "item"
    @test Int(protocol[:validation][:min_cell_count]) == 3
    @test Bool(protocol[:validation][:require_no_validation_errors])
    @test Bool(protocol[:validation][:require_connected_design])
    @test Bool(protocol[:validation][:require_full_location_rank])
    @test Bool(protocol[:validation][:warnings_recorded_not_blocking])
    @test Set(Float64(interval) for interval in protocol[:intervals]) == Set([0.8, 0.95])
    @test Set(String(model) for model in protocol[:models]) == Set([
        "gmfrm_internal_candidate",
        "mfrm_partial_credit",
        "mfrm_rating_scale",
    ])
    @test String(protocol[:decision_rules][:prediction_target]) == "same_observation_waic"
    @test String(protocol[:decision_rules][:public_exposure_decision]) == "keep_internal"
    @test Bool(protocol[:decision_rules][:sparse_design_grid_recorded])
    @test Bool(protocol[:decision_rules][:require_all_samplers_passed])
    @test Bool(protocol[:decision_rules][:high_variance_waic_blocks_public_exposure])
    @test Bool(protocol[:decision_rules][:psis_loo_or_influence_review_required_before_exposure])
    @test Int(thresholds[:n_scenarios]) == 3
    @test Int(thresholds[:n_models_per_scenario]) == 3
    @test Int(thresholds[:min_observations]) == 18
    @test Int(thresholds[:max_observations]) == 35
    @test Bool(thresholds[:require_same_observations_within_scenario])
    @test Bool(thresholds[:require_sampler_passed])
    @test Bool(thresholds[:require_finite_elpd])
    @test Bool(thresholds[:require_finite_calibration])
    @test Bool(thresholds[:require_finite_intervals])
    @test Bool(thresholds[:require_decision_stability])

    scenarios = fixture[:scenarios]
    @test length(scenarios) == Int(thresholds[:n_scenarios])
    @test Set(String(scenario[:scenario]) for scenario in scenarios) == Set([
        "balanced_parity_sparse",
        "reference_bridge_sparse",
        "cyclic_missing_item_sparse",
    ])
    for scenario in scenarios
        density = scenario[:design_density]
        simulated = scenario[:simulated_data]
        n_observations = Int(density[:n_observations])
        @test Int(density[:full_crossed_observations]) == Int(protocol[:full_crossed_observations])
        @test Int(thresholds[:min_observations]) <= n_observations <=
            Int(thresholds[:max_observations])
        @test n_observations < Int(protocol[:full_crossed_observations])
        @test Float64(density[:observed_fraction]) < 1.0
        @test Int(density[:missing_observations]) > 0
        @test Int(simulated[:n_observations]) == n_observations
        @test sum(Int(row[:n]) for row in simulated[:score_counts]) == n_observations
        @test Set(Int(row[:score]) for row in simulated[:score_counts]) == Set([0, 1, 2])
        @test length(simulated[:person_levels]) == 4
        @test length(simulated[:rater_levels]) == 3
        @test length(simulated[:item_levels]) == 3
        @test Set(Int(level) for level in simulated[:category_levels]) == Set([0, 1, 2])

        validation = scenario[:validation]
        @test Bool(validation[:passed])
        @test Int(validation[:n_errors]) == 0
        @test Int(validation[:n_warnings]) >= 1
        @test Int(validation[:n_components]) == 1
        @test Int(validation[:location_design_rank]) == 8
        @test Int(validation[:n_location_parameters]) == 8
        @test Bool(validation[:location_design_full_rank])
        issue_codes = Set(String(code) for code in validation[:issue_codes])
        @test issubset(issue_codes,
            Set(["unobserved_item_category", "sparse_dff_cell"]))
        @test !isempty(issue_codes)
        @test all(row -> String(row[:severity]) == "warning",
            validation[:issue_rows])
        @test !isempty(validation[:dff_cell_counts])

        model_rows = scenario[:model_rows]
        @test length(model_rows) == Int(thresholds[:n_models_per_scenario])
        @test [Int(row[:rank]) for row in model_rows] == [1, 2, 3]
        @test Set(String(row[:model]) for row in model_rows) == Set([
            "gmfrm_internal_candidate",
            "mfrm_partial_credit",
            "mfrm_rating_scale",
        ])
        @test all(row -> Int(row[:n_observations]) == n_observations, model_rows)
        @test all(row -> Int(row[:n_draws]) == 128, model_rows)
        @test all(row -> Bool(row[:sampler_summary][:internal_passed]), model_rows)
        @test all(row -> Int(row[:sampler_summary][:n_divergences]) == 0, model_rows)
        @test all(row -> Int(row[:sampler_summary][:n_max_treedepth]) == 0,
            model_rows)
        @test all(row -> isfinite(Float64(row[:elpd_waic])) &&
            isfinite(Float64(row[:waic])), model_rows)
        @test all(row -> isfinite(Float64(row[:predictive_metrics][:expected_score_rmse])) &&
            isfinite(Float64(row[:predictive_metrics][:mean_absolute_calibration_error])),
            model_rows)
        @test all(row -> String(row[:warning]) in ("ok", "high_loglik_variance"),
            model_rows)
        @test sum(Float64(row[:relative_weight]) for row in model_rows) ≈ 1.0
        gmfrm_row = only(row for row in model_rows
            if String(row[:model]) == "gmfrm_internal_candidate")
        @test String(gmfrm_row[:family]) == "gmfrm"
        @test Bool(gmfrm_row[:public_fit]) == false
        @test Int(gmfrm_row[:n_parameters]) == 17
        @test String(gmfrm_row[:direct_parameter_order_sha256]) ==
            String(scenario[:gmfrm_parameter_order_sha256])

        interval_rows = scenario[:interval_coverage]
        @test length(interval_rows) == 2
        @test Set(Float64(row[:interval_probability]) for row in interval_rows) ==
            Set([0.8, 0.95])
        for interval_row in interval_rows
            @test length(interval_row[:recovery_by_block]) == 6
            @test Int(interval_row[:summary][:n_parameters]) == 19
            @test Int(interval_row[:summary][:n_blocks]) == 6
            @test Bool(interval_row[:summary][:all_intervals_finite])
            @test Float64(interval_row[:summary][:overall_coverage_rate]) >= 0.8
            @test Float64(interval_row[:summary][:min_block_coverage_rate]) >= 0.0
        end

        decision = scenario[:decision]
        @test String(decision[:selected_decision]) == "keep_internal"
        @test Bool(decision[:public_fit_allowed]) == false
        @test Bool(decision[:experimental_keyword_enabled]) == false
        @test Bool(decision[:all_samplers_passed])
        @test Set(String(row[:blocker]) for row in decision[:blocker_rows]) ==
            Set(["high_variance_waic_requires_followup"])

        summary = scenario[:summary]
        @test Bool(summary[:passed])
        @test String(summary[:selected_decision]) == "keep_internal"
        @test Bool(summary[:validation_passed])
        @test Int(summary[:location_design_rank]) == 8
        @test Int(summary[:n_location_parameters]) == 8
        @test Float64(summary[:min_interval_coverage_rate]) >= 0.8
    end

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Int(summary[:n_scenarios]) == length(scenarios)
    @test Int(summary[:n_passed_scenarios]) == length(scenarios)
    @test Int(summary[:n_sparse_validation_records]) == length(scenarios)
    @test Int(summary[:n_interval_records]) == 2 * length(scenarios)
    @test Int(summary[:n_models]) == 3 * length(scenarios)
    @test Int(summary[:n_observations_minimum]) >= Int(thresholds[:min_observations])
    @test Int(summary[:n_observations_maximum]) < Int(protocol[:full_crossed_observations])
    @test Bool(summary[:all_sparse_validations_passed])
    @test Bool(summary[:all_location_designs_full_rank])
    @test Bool(summary[:all_local_intervals_finite])
    @test Float64(summary[:min_interval_coverage_rate]) >= 0.8
    @test Float64(summary[:min_block_coverage_rate]) >= 0.0
    @test Int(summary[:keep_internal_decision_count]) == length(scenarios)
    @test String(summary[:decision_stability]) == "stable_keep_internal"
    @test Bool(summary[:any_high_variance_waic])
    @test Set(String(blocker) for blocker in summary[:remaining_public_blockers]) ==
        Set(["high_variance_waic_requires_followup"])
    @test String(summary[:recommendation]) == "keep_internal_until_waic_followup"
    @test String(summary[:next_gate]) == "scalar_gmfrm_waic_influence_review"
end
