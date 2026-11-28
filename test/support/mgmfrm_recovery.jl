function check_mgmfrm_recovery_smoke_fixture(fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) == "bayesianmgmfrm.mgmfrm_recovery_smoke.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) == "minimal_confirmatory_mgmfrm_candidate"
    @test String(fixture[:status]) == "internal_fit_ready_candidate"
    @test Bool(fixture[:public_fit]) == false
    @test Bool(fixture[:experimental_public]) == false
    @test Bool(fixture[:fit_ready]) == false
    @test String(fixture[:target]) == "_source_fixture_logdensity"
    @test Int(fixture[:dimensions]) == 2
    @test json_bool_matrix(fixture[:q_matrix]) == Bool[1 0; 0 1]
    @test String(fixture[:latent_correlation]) == "identity_fixed"
    @test String(fixture[:ability_scale]) == "unit_variance_by_dimension"
    @test Float64(fixture[:source_scale]) == 1.7

    protocol = fixture[:protocol]
    grid = protocol[:grid]
    sampler = protocol[:sampler]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) == "confirmatory_mgmfrm_recovery_smoke_v1"
    @test Int(protocol[:simulation_seed]) == 20260721
    @test Int(protocol[:sampler_seed]) == 20260722
    @test Int(grid[:persons]) == 4
    @test Int(grid[:items]) == 2
    @test Int(grid[:raters]) == 3
    @test Int(grid[:categories]) == 3
    @test Int(grid[:dimensions]) == 2
    @test json_bool_matrix(grid[:q_matrix]) == Bool[1 0; 0 1]
    @test String(grid[:rating_density]) == "full_crossed"
    @test Int(grid[:observations]) == 24
    @test String(sampler[:backend]) == "advancedhmc"
    @test String(sampler[:sampler]) == "nuts"
    @test Int(sampler[:chains]) == 2
    @test Int(sampler[:warmup]) == 32
    @test Int(sampler[:draws]) == 32
    @test Float64(sampler[:target_accept]) == 0.8
    @test Int(sampler[:max_depth]) == 8
    @test String(sampler[:metric]) == "unit"
    @test Float64(thresholds[:max_rhat]) == 1.35
    @test Float64(thresholds[:min_ess]) == 6.0
    @test Float64(thresholds[:min_ebfmi]) == 0.3
    @test Float64(thresholds[:max_block_mean_absolute_error]) == 0.9
    @test Float64(thresholds[:max_parameter_absolute_error]) == 1.8
    @test Float64(thresholds[:min_block_coverage_rate]) == 0.0

    raw_names = Vector{String}(fixture[:raw_parameter_order])
    direct_names = Vector{String}(fixture[:direct_parameter_order])
    @test length(raw_names) == 18
    @test length(direct_names) == 20
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
        "item_dimension_discrimination",
        "rater_consistency",
        "item_steps",
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

function check_mgmfrm_baseline_comparison_fixture(fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) == "bayesianmgmfrm.mgmfrm_baseline_comparison.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) == "minimal_confirmatory_mgmfrm_candidate"
    @test String(fixture[:status]) == "internal_baseline_comparison"
    @test Bool(fixture[:public_fit]) == false
    @test Bool(fixture[:experimental_public]) == false
    @test Bool(fixture[:fit_ready]) == false
    @test Int(fixture[:dimensions]) == 2
    @test [Bool.(row) for row in fixture[:q_matrix]] ==
        [[true, false], [false, true]]
    @test String(fixture[:latent_correlation]) == "identity_fixed"

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) ==
        "confirmatory_mgmfrm_baseline_comparison_v1"
    @test String(protocol[:simulation_source]) ==
        "confirmatory_mgmfrm_recovery_smoke_v1"
    @test Int(protocol[:simulation_seed]) == 20260721
    @test Int(thresholds[:minimum_models]) == 3
    @test Int(thresholds[:n_observations]) == 24
    @test Bool(thresholds[:require_same_observations])
    @test Bool(thresholds[:require_finite_elpd])
    @test Bool(thresholds[:require_finite_weights])
    @test String(protocol[:mgmfrm_sampler][:backend]) == "advancedhmc"
    @test Int(protocol[:mgmfrm_sampler][:seed]) == 20260722
    @test Int(protocol[:mgmfrm_sampler][:draws]) == 32
    @test String(protocol[:baseline_sampler][:backend]) == "advancedhmc"
    @test Int(protocol[:baseline_sampler][:draws]) == 32
    @test Int(protocol[:baseline_sampler][:seeds][:partial_credit]) == 20260762
    @test Int(protocol[:baseline_sampler][:seeds][:rating_scale]) == 20260763

    simulated = fixture[:simulated_data]
    @test Int(simulated[:n_observations]) == 24
    @test sum(Int(row[:n]) for row in simulated[:score_counts]) == 24
    @test length(simulated[:person_levels]) == 4
    @test length(simulated[:rater_levels]) == 3
    @test length(simulated[:item_levels]) == 2
    @test Set(Int(level) for level in simulated[:category_levels]) == Set([0, 1, 2])
    @test String(simulated[:truth_source]) == "mgmfrm_recovery_smoke_truth"

    model_rows = fixture[:model_rows]
    @test length(model_rows) == 3
    @test [Int(row[:rank]) for row in model_rows] == [1, 2, 3]
    @test issorted([Float64(row[:elpd_waic]) for row in model_rows]; rev = true)
    @test Set(String(row[:model]) for row in model_rows) == Set([
        "mgmfrm_internal_candidate",
        "mfrm_partial_credit",
        "mfrm_rating_scale",
    ])
    @test all(row -> Int(row[:n_observations]) == 24, model_rows)
    @test all(row -> Int(row[:n_draws]) == 64, model_rows)
    @test all(row -> isfinite(Float64(row[:elpd_waic])) &&
        isfinite(Float64(row[:waic])), model_rows)
    @test all(row -> isfinite(Float64(row[:relative_weight])), model_rows)
    @test sum(Float64(row[:relative_weight]) for row in model_rows) ≈ 1.0
    @test all(row -> String(row[:criterion]) == "waic", model_rows)
    @test all(row -> String(row[:warning]) in ("ok", "high_loglik_variance"),
        model_rows)
    @test all(row -> Bool(row[:sampler_summary][:internal_passed]), model_rows)
    @test all(row -> Int(row[:sampler_summary][:n_divergences]) == 0, model_rows)
    @test all(row -> Int(row[:sampler_summary][:n_max_treedepth]) == 0,
        model_rows)

    mgmfrm_row = only(row for row in model_rows
        if String(row[:model]) == "mgmfrm_internal_candidate")
    @test String(mgmfrm_row[:family]) == "mgmfrm"
    @test String(mgmfrm_row[:source]) == "internal_source_fixture_candidate"
    @test String(mgmfrm_row[:threshold_regime]) ==
        "confirmatory_fixed_q_multidimensional_partial_credit"
    @test Bool(mgmfrm_row[:public_fit]) == false
    @test Int(mgmfrm_row[:n_parameters]) == 18
    @test String(simulated[:raw_parameter_order_sha256]) ==
        String(mgmfrm_row[:parameter_order_sha256])
    @test String(simulated[:direct_parameter_order_sha256]) ==
        String(mgmfrm_row[:direct_parameter_order_sha256])
    @test Float64(mgmfrm_row[:elpd_difference]) <= 0.0

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
    @test Int(summary[:mgmfrm_rank]) == Int(mgmfrm_row[:rank])
    @test Float64(summary[:mgmfrm_elpd_difference]) ≈
        Float64(mgmfrm_row[:elpd_difference])
    @test Float64(summary[:mgmfrm_relative_weight]) ≈
        Float64(mgmfrm_row[:relative_weight])
    @test Bool(summary[:any_high_variance_waic])
    @test Bool(summary[:public_fit_allowed]) == false
    @test Bool(summary[:experimental_keyword_enabled]) == false
    @test String(summary[:recommendation]) == "keep_internal_until_sparse_recovery_grid"
    @test String(summary[:next_gate]) == "mgmfrm_sparse_recovery_grid"
end

function check_mgmfrm_sparse_recovery_grid_fixture(fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) == "bayesianmgmfrm.mgmfrm_sparse_recovery_grid.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) == "minimal_confirmatory_mgmfrm_candidate"
    @test String(fixture[:status]) == "internal_sparse_recovery_grid"
    @test String(fixture[:decision]) == "keep_internal"
    @test Bool(fixture[:public_fit]) == false
    @test Bool(fixture[:experimental_public]) == false
    @test Bool(fixture[:fit_ready]) == false
    @test Int(fixture[:dimensions]) == 2
    @test [Bool.(row) for row in fixture[:q_matrix]] ==
        [[true, false], [false, true]]
    @test String(fixture[:latent_correlation]) == "identity_fixed"

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    diagnostics = protocol[:diagnostics]
    recovery_thresholds = protocol[:recovery]
    @test String(protocol[:protocol_id]) ==
        "confirmatory_mgmfrm_sparse_recovery_grid_v1"
    @test String(protocol[:review_kind]) ==
        "local_confirmatory_mgmfrm_sparse_recovery_grid"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test Int(thresholds[:n_scenarios]) == 3
    @test Int(thresholds[:min_observations]) == 16
    @test Int(thresholds[:max_observations]) == 20
    @test Bool(thresholds[:require_all_scenarios_passed])
    @test Bool(thresholds[:require_validation_passed])
    @test Bool(thresholds[:require_connected_design])
    @test Bool(thresholds[:require_full_location_rank])
    @test Bool(thresholds[:require_same_parameter_order])
    @test Bool(thresholds[:require_sampler_passed])
    @test Bool(thresholds[:require_finite_logdensity])
    @test Bool(thresholds[:require_finite_pointwise_loglikelihood])
    @test Bool(thresholds[:require_finite_waic])
    @test String(thresholds[:public_exposure_decision]) == "keep_internal"
    @test Float64(diagnostics[:max_rhat]) == 1.6
    @test Float64(diagnostics[:min_ess]) == 4.0
    @test Int(diagnostics[:n_divergences]) == 0
    @test Int(diagnostics[:n_max_treedepth]) == 0
    @test Float64(recovery_thresholds[:max_block_mean_absolute_error]) == 2.5
    @test Float64(recovery_thresholds[:max_parameter_absolute_error]) == 4.0

    reviewed = fixture[:reviewed_artifacts]
    @test Set(String(row[:artifact]) for row in reviewed) == Set([
        "test/fixtures/mgmfrm_recovery_smoke.json",
        "test/fixtures/mgmfrm_baseline_comparison.json",
    ])
    @test all(row -> Bool(row[:exists]), reviewed)
    @test all(row -> String(row[:sha256]) ==
        file_sha256(joinpath(root, String(row[:artifact]))), reviewed)

    scenarios = fixture[:scenarios]
    @test length(scenarios) == 3
    @test Set(String(row[:scenario]) for row in scenarios) == Set([
        "rater_item_bridge_sparse",
        "alternating_dimension_bridge_sparse",
        "leave_one_pair_out_sparse",
    ])
    @test Set(String(row[:sparse_pattern]) for row in scenarios) == Set([
        "rater_item_bridge",
        "alternating_dimension_bridge",
        "leave_one_pair_out",
    ])
    for scenario in scenarios
        scenario_summary = scenario[:summary]
        validation = scenario[:validation]
        sampler = scenario[:sampler_summary]
        pointwise = scenario[:pointwise_loglikelihood_review]
        @test Bool(scenario_summary[:passed])
        @test Int(scenario_summary[:n_observations]) ==
            Int(scenario[:design_density][:n_observations])
        @test 16 <= Int(scenario_summary[:n_observations]) <= 20
        @test Bool(scenario_summary[:validation_passed])
        @test Bool(validation[:passed])
        @test Int(validation[:n_errors]) == 0
        @test Int(validation[:n_components]) == 1
        @test Bool(validation[:location_design_full_rank])
        @test Bool(scenario_summary[:parameter_order_matches_reference])
        @test String(scenario_summary[:sampler_flag]) == "ok"
        @test Bool(sampler[:internal_passed])
        @test Int(scenario_summary[:n_divergences]) == 0
        @test Int(scenario_summary[:n_max_treedepth]) == 0
        @test Int(scenario_summary[:n_failed_direct_constraints]) == 0
        @test Int(scenario_summary[:n_nonfinite_logdensity]) == 0
        @test Int(scenario_summary[:n_nonfinite_direct_loglikelihood]) == 0
        @test Float64(scenario_summary[:max_rhat]) <= 1.6
        @test Float64(scenario_summary[:min_ess]) >= 4.0
        @test Int(pointwise[:n_nonfinite]) == 0
        @test Bool(scenario_summary[:waic_finite])
        @test Float64(scenario_summary[:max_block_mean_absolute_error]) <=
            Float64(recovery_thresholds[:max_block_mean_absolute_error])
        @test Float64(scenario_summary[:max_parameter_absolute_error]) <=
            Float64(recovery_thresholds[:max_parameter_absolute_error])
        @test Float64(scenario_summary[:min_block_coverage_rate]) >=
            Float64(recovery_thresholds[:min_block_coverage_rate])
    end

    decision = fixture[:decision_record]
    @test String(decision[:selected_decision]) == "keep_internal"
    @test Bool(decision[:public_fit_allowed]) == false
    @test Bool(decision[:experimental_keyword_enabled]) == false
    @test String(decision[:public_exposure_support]) ==
        "insufficient_for_mgmfrm_public_fit"
    @test String(decision[:interpretation]) ==
        "confirmatory_mgmfrm_sparse_recovery_grid_recorded_keep_internal"
    @test String(decision[:required_followup]) ==
        "dff_estimand_and_validation_grid"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Int(summary[:n_scenarios]) == length(scenarios)
    @test Int(summary[:n_passed_scenarios]) == length(scenarios)
    @test Int(summary[:n_observations_minimum]) >= 16
    @test Int(summary[:n_observations_maximum]) <= 20
    @test Bool(summary[:all_validations_passed])
    @test Bool(summary[:all_location_designs_full_rank])
    @test Bool(summary[:all_parameter_orders_match_reference])
    @test Bool(summary[:all_sampler_passed])
    @test Bool(summary[:all_no_divergences])
    @test Bool(summary[:all_no_max_treedepth])
    @test Bool(summary[:all_no_failed_direct_constraints])
    @test Bool(summary[:all_no_nonfinite_logdensity])
    @test Bool(summary[:all_no_nonfinite_direct_loglikelihood])
    @test Bool(summary[:all_waic_finite])
    @test Float64(summary[:max_block_mean_absolute_error]) <=
        Float64(recovery_thresholds[:max_block_mean_absolute_error])
    @test Float64(summary[:max_parameter_absolute_error]) <=
        Float64(recovery_thresholds[:max_parameter_absolute_error])
    @test Bool(summary[:public_fit_allowed]) == false
    @test Bool(summary[:experimental_keyword_enabled]) == false
    @test Set(String(blocker) for blocker in summary[:remaining_public_blockers]) ==
        Set([
            "dff_estimand_and_validation_evidence_missing",
            "manuscript_scale_simulation_grid_missing",
            "full_paper_reproduction_archive_missing",
        ])
    @test String(summary[:recommendation]) ==
        "keep_mgmfrm_internal_until_dff_and_gate_e_evidence"
    @test String(summary[:next_gate]) == "dff_estimand_and_validation_grid"
end

function check_mgmfrm_report_shape_simulation_grid_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_report_shape_simulation_grid.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) == "minimal_confirmatory_mgmfrm_candidate"
    @test String(fixture[:status]) == "report_shape_simulation_grid_recorded"
    @test String(fixture[:decision]) == "keep_guarded_fixed_q_only"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) ==
        "confirmatory_mgmfrm_report_shape_simulation_grid_v1"
    @test String(protocol[:review_kind]) ==
        "local_confirmatory_mgmfrm_report_shape_simulation_grid"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test Int(protocol[:scenario_count]) == 3
    @test Bool(thresholds[:require_all_scenarios_passed])
    @test Bool(thresholds[:require_report_shape_passed])
    @test Bool(thresholds[:require_diagnostics_shape_passed])
    @test Bool(thresholds[:require_artifact_shape_passed])
    @test Bool(thresholds[:require_waic_shape_passed])
    @test Bool(thresholds[:require_posterior_predictive_shape_passed])
    @test String(thresholds[:public_exposure_decision]) ==
        "guarded_fixed_q_only"

    scenarios = fixture[:scenarios]
    @test length(scenarios) == 3
    @test Set(String(row[:scenario]) for row in scenarios) == Set([
        "simple_2d_full_crossed",
        "simple_3d_full_crossed",
        "cross_loading_3d_full_crossed",
    ])
    @test Set(Int(row[:dimensions]) for row in scenarios) == Set([2, 3])
    @test any(row -> String(row[:q_shape]) ==
        "fixed_confirmatory_cross_loading", scenarios)
    for scenario in scenarios
        summary = scenario[:summary]
        report = scenario[:report_shape]
        diagnostics = scenario[:diagnostics_shape]
        artifact = scenario[:artifact_shape]
        waic_shape = scenario[:waic_shape]
        ppc = scenario[:posterior_predictive_shape]
        finite = scenario[:finite]
        @test Bool(summary[:passed])
        @test Bool(summary[:q_validation_passed])
        @test Bool(summary[:finite_initial_logdensity])
        @test Bool(summary[:finite_pointwise_loglikelihood])
        @test Bool(summary[:no_failed_direct_constraints])
        @test Bool(summary[:report_shape_passed])
        @test Bool(summary[:diagnostics_shape_passed])
        @test Bool(summary[:artifact_shape_passed])
        @test Bool(summary[:waic_shape_passed])
        @test Bool(summary[:posterior_predictive_shape_passed])
        @test Bool(report[:passed])
        @test Bool(report[:q_matrix_passed])
        @test String(report[:posterior_status]) == "computed"
        @test String(report[:direct_posterior_status]) == "computed"
        @test String(report[:calibration_status]) == "computed"
        @test String(report[:waic_status]) == "computed"
        @test Int(report[:posterior_rows]) == Int(scenario[:n_raw_parameters])
        @test Int(report[:direct_posterior_rows]) ==
            Int(scenario[:n_direct_parameters])
        @test Bool(diagnostics[:passed])
        @test Bool(diagnostics[:direct_constraints_passed])
        @test Int(diagnostics[:raw_parameter_rows]) ==
            Int(scenario[:n_raw_parameters])
        @test Int(diagnostics[:direct_parameter_rows]) ==
            Int(scenario[:n_direct_parameters])
        @test Bool(artifact[:passed])
        @test Int(artifact[:raw_parameter_names]) ==
            Int(scenario[:n_raw_parameters])
        @test Int(artifact[:direct_parameter_names]) ==
            Int(scenario[:n_direct_parameters])
        @test Vector{Int}(artifact[:pointwise_shape]) ==
            Vector{Int}(scenario[:pointwise_loglikelihood_shape])
        @test Bool(waic_shape[:passed])
        @test Int(waic_shape[:n_draws]) == Int(scenario[:n_draws])
        @test Int(waic_shape[:n_observations]) ==
            Int(scenario[:n_observations])
        @test Bool(ppc[:passed])
        @test Vector{Int}(ppc[:replicated_shape]) ==
            [Int(scenario[:n_draws]), Int(scenario[:n_observations])]
        @test Bool(finite[:log_posterior_finite])
        @test Bool(finite[:direct_draws_finite])
        @test Int(finite[:n_nonfinite_pointwise]) == 0
    end

    decision = fixture[:decision_record]
    @test Bool(decision[:public_fit_allowed])
    @test Bool(decision[:experimental_keyword_enabled])
    @test String(decision[:required_followup]) ==
        "q_matrix_validation_expansion"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Int(summary[:n_scenarios]) == length(scenarios)
    @test Int(summary[:n_passed_scenarios]) == length(scenarios)
    @test Set(Int(value) for value in summary[:dimensions_covered]) == Set([2, 3])
    @test Bool(summary[:all_q_validation_passed])
    @test Bool(summary[:all_report_shapes_passed])
    @test Bool(summary[:all_diagnostics_shapes_passed])
    @test Bool(summary[:all_artifact_shapes_passed])
    @test Bool(summary[:all_waic_shapes_passed])
    @test Bool(summary[:all_posterior_predictive_shapes_passed])
    @test Bool(summary[:all_no_failed_direct_constraints])
    @test Bool(summary[:all_finite_pointwise_loglikelihood])
    @test Bool(summary[:public_fit_allowed])
    @test Bool(summary[:experimental_keyword_enabled])
    @test Set(String(blocker) for blocker in summary[:remaining_public_blockers]) ==
        Set([
            "free_latent_correlation_policy_missing",
            "exploratory_loading_policy_missing",
            "broad_generalized_mgmfrm_validation_missing",
        ])
    @test String(summary[:recommendation]) ==
        "keep_fixed_q_confirmatory_guarded_continue_q_validation_expansion"
    @test String(summary[:next_gate]) == "q_matrix_validation_expansion"
end

function check_mgmfrm_q_matrix_validation_expansion_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_q_matrix_validation_expansion.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) == "minimal_confirmatory_mgmfrm_candidate"
    @test String(fixture[:status]) == "q_matrix_validation_expansion_recorded"
    @test String(fixture[:decision]) == "keep_guarded_fixed_q_only"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) ==
        "confirmatory_mgmfrm_q_matrix_validation_expansion_v1"
    @test String(protocol[:review_kind]) ==
        "local_confirmatory_mgmfrm_q_matrix_validation_expansion"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test Int(protocol[:scenario_count]) == 15
    @test Bool(thresholds[:require_all_expected_validation_outcomes])
    @test Bool(thresholds[:require_all_expected_spec_outcomes])
    @test Bool(thresholds[
        :require_all_invalid_default_q_scenarios_blocked_before_fit])
    @test Bool(thresholds[:require_policy_validation_scenarios_recorded])
    @test Bool(thresholds[:require_warning_scenarios_not_rejected])
    @test Bool(thresholds[:require_valid_scenarios_preview_design])
    @test Bool(thresholds[:require_research_basis_recorded])
    @test String(thresholds[:public_exposure_decision]) ==
        "guarded_fixed_q_only"

    research_basis = fixture[:research_basis]
    @test length(research_basis) >= 5
    @test Set(String(row[:key]) for row in research_basis) == Set([
        "uto_2021_mgmfrm",
        "da_silva_2019_mirt_q_matrix",
        "de_la_torre_chiu_2016_gdi",
        "terzi_de_la_torre_2018_iterative",
        "chalmers_2012_mirt",
    ])
    @test all(row -> !isempty(String(row[:url])), research_basis)
    @test all(row -> !isempty(String(row[:doi])), research_basis)

    scenarios = fixture[:scenarios]
    @test length(scenarios) == 15
    @test Set(String(row[:scenario]) for row in scenarios) == Set([
        "valid_simple_2d",
        "valid_confirmatory_cross_loading",
        "missing_q_matrix",
        "non_matrix_q_matrix",
        "non_binary_entries",
        "item_shape_mismatch",
        "dimension_shape_mismatch",
        "empty_item_row",
        "empty_dimension_column",
        "duplicate_dimension_columns",
        "blocked_cross_loading_policy",
        "warning_no_single_loading_anchor",
        "structurally_rank_deficient_nonduplicate_columns",
        "warning_person_dimension_prior_anchored",
        "warning_dimension_facet_disconnected",
    ])
    for scenario in scenarios
        summary = scenario[:summary]
        @test Bool(summary[:passed])
        @test Bool(summary[:validation_outcome_matches])
        @test Bool(summary[:spec_outcome_matches])
        @test Bool(scenario[:validation_passed]) ==
            Bool(scenario[:expected_validation_passed])
        if String(scenario[:expected_spec_default]) == "throws"
            @test Bool(summary[:default_prefit_block_required])
            @test Bool(summary[:default_prefit_blocked])
            @test String(scenario[:spec_default][:outcome]) == "throws"
            @test Bool(scenario[:spec_default][:error_contains_invalid_q])
        elseif String(scenario[:expected_spec_default]) == "succeeded"
            @test Bool(summary[:default_prefit_block_required]) == false
            @test String(scenario[:spec_default][:outcome]) == "succeeded"
            @test Bool(scenario[:spec_default][:preview_design_succeeded])
        end
    end
    @test any(row -> String(row[:scenario]) == "missing_q_matrix" &&
        "required_q_matrix" in String.(row[:error_checks]), scenarios)
    @test any(row -> String(row[:scenario]) == "non_binary_entries" &&
        "binary_mask_schema" in String.(row[:error_checks]), scenarios)
    @test any(row -> String(row[:scenario]) == "item_shape_mismatch" &&
        "shape" in String.(row[:error_checks]), scenarios)
    @test any(row -> String(row[:scenario]) == "duplicate_dimension_columns" &&
        "duplicate_dimension_columns" in String.(row[:error_checks]), scenarios)
    @test any(row -> String(row[:scenario]) ==
        "valid_confirmatory_cross_loading" &&
        "cross_loading_policy" in String.(row[:warning_checks]), scenarios)
    @test any(row -> String(row[:scenario]) ==
        "warning_dimension_facet_disconnected" &&
        "dimension_facet_subgraph_coverage" in String.(row[:warning_checks]),
        scenarios)
    @test any(row -> String(row[:scenario]) ==
        "structurally_rank_deficient_nonduplicate_columns" &&
        "global_loading_structural_rank" in String.(row[:error_checks]),
        scenarios)
    @test any(row -> String(row[:scenario]) ==
        "warning_person_dimension_prior_anchored" &&
        "person_dimension_likelihood_support" in
            String.(row[:warning_checks]),
        scenarios)

    decision = fixture[:decision_record]
    @test Bool(decision[:public_fit_allowed])
    @test Bool(decision[:experimental_keyword_enabled])
    @test String(decision[:required_followup]) ==
        "empirical_q_matrix_recovery_policy"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Int(summary[:n_scenarios]) == length(scenarios)
    @test Int(summary[:n_passed_scenarios]) == length(scenarios)
    @test Int(summary[:n_validation_passed]) == 5
    @test Int(summary[:n_validation_failed]) == 10
    @test Bool(summary[:all_expected_validation_outcomes])
    @test Bool(summary[:all_expected_spec_outcomes])
    @test Bool(summary[:all_invalid_default_q_scenarios_blocked_before_fit])
    @test Int(summary[:n_invalid_default_q_scenarios]) == 9
    @test Bool(summary[:policy_validation_scenarios_recorded])
    @test Int(summary[:n_policy_validation_scenarios]) == 1
    @test Bool(summary[:warning_scenarios_not_rejected])
    @test Bool(summary[:valid_scenarios_preview_design])
    @test Bool(summary[:research_basis_recorded])
    structural_checks = Set(String(check) for check in
        summary[:structural_checks_covered])
    @test issubset(Set([
        "required_q_matrix",
        "matrix_schema",
        "binary_mask_schema",
        "shape",
        "empty_item_rows",
        "empty_dimensions",
        "duplicate_dimension_columns",
        "global_loading_structural_rank",
        "person_dimension_likelihood_support",
        "cross_loading_policy",
        "positive_loading_identification",
        "ability_population_identification_anchor",
        "fixed_q_identification_gate",
        "dimension_facet_subgraph_coverage",
    ]), structural_checks)
    @test Set(String(blocker) for blocker in summary[:remaining_public_blockers]) ==
        Set([
            "empirical_q_matrix_recovery_policy_missing",
            "free_latent_correlation_policy_missing",
            "exploratory_loading_policy_missing",
            "broad_generalized_mgmfrm_validation_missing",
        ])
    @test String(summary[:recommendation]) ==
        "keep_fixed_q_confirmatory_guarded_continue_empirical_q_policy"
    @test String(summary[:next_gate]) == "empirical_q_matrix_recovery_policy"
end

function check_mgmfrm_empirical_q_matrix_recovery_policy_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_empirical_q_matrix_recovery_policy.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) == "empirical_q_matrix_recovery_policy"
    @test String(fixture[:status]) ==
        "empirical_q_matrix_recovery_policy_recorded"
    @test String(fixture[:decision]) ==
        "keep_empirical_q_recovery_diagnostic_only"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])
    @test Bool(fixture[:empirical_q_recovery_public]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) ==
        "mgmfrm_empirical_q_matrix_recovery_policy_v1"
    @test String(protocol[:review_kind]) ==
        "local_empirical_q_matrix_recovery_policy"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test Bool(protocol[:local_only])
    @test Bool(thresholds[:require_q_matrix_validation_expansion_passed])
    @test Bool(thresholds[:require_uto_reference_record])
    @test Bool(thresholds[:require_research_basis_recorded])
    @test Bool(thresholds[:require_all_candidate_policy_scenarios_passed])
    @test Bool(thresholds[:require_invalid_suggested_q_blocked])
    @test Bool(thresholds[:require_ambiguous_or_weak_design_no_auto_revision])
    @test Bool(thresholds[:require_all_candidate_suggestions_validation_checked])
    @test Bool(thresholds[:require_no_public_automatic_q_revision])
    @test Bool(thresholds[:require_no_publication_or_registration_action])

    reference_records = fixture[:reference_records]
    @test length(reference_records) == 1
    uto = only(reference_records)
    @test all(key -> !occursin("item_key", String(key)), keys(uto))
    @test all(key -> !occursin("duplicate", String(key)), keys(uto))
    @test String(uto[:source]) == "doi"
    @test String(uto[:doi]) == "10.1007/s41237-021-00144-w"
    @test String(uto[:journal]) == "Behaviormetrika"
    @test Int(uto[:scite_snapshot][:total_citing_publications]) >= 0

    research_basis = fixture[:research_basis]
    @test length(research_basis) >= 5
    @test any(row -> String(row[:key]) == "uto_2021_mgmfrm" &&
        String(row[:source]) == "doi" &&
        all(key -> !occursin("item_key", String(key)), keys(row)),
        research_basis)
    @test Set(String(row[:key]) for row in research_basis) == Set([
        "uto_2021_mgmfrm",
        "da_silva_2019_mirt_q_matrix",
        "de_la_torre_chiu_2016_gdi",
        "terzi_de_la_torre_2018_iterative",
        "najera_2020_q_matrix_cutoffs",
    ])

    input_artifacts = fixture[:input_artifacts]
    @test length(input_artifacts) == 1
    input = only(input_artifacts)
    @test String(input[:artifact]) == "q_matrix_validation_expansion"
    @test String(input[:path]) ==
        "test/fixtures/mgmfrm_q_matrix_validation_expansion.json"
    @test Bool(input[:exists])
    @test Bool(input[:schema_matches])
    @test Bool(input[:summary_passed])
    check_generated_fixture_reference(
        root,
        String(input[:path]),
        String(input[:sha256]),
    )

    rows = fixture[:candidate_policy_rows]
    @test length(rows) == 9
    @test Set(String(row[:scenario]) for row in rows) == Set([
        "true_q_retained",
        "missing_loading_candidate_flagged",
        "extra_loading_candidate_flagged",
        "ambiguous_loading_deferred",
        "empty_item_candidate_blocked",
        "empty_dimension_candidate_blocked",
        "duplicate_dimension_candidate_blocked",
        "simple_structure_cross_loading_policy_blocked",
        "weak_dimension_facet_link_deferred",
    ])
    @test all(row -> Bool(row[:summary][:passed]), rows)
    @test all(row -> Bool(row[:summary][:candidate_validation_checked]), rows)
    @test all(row -> Bool(row[:automatic_revision_allowed]) == false, rows)
    @test all(row -> Bool(row[:public_recovery_allowed]) == false, rows)
    @test any(row -> String(row[:scenario]) ==
        "missing_loading_candidate_flagged" &&
        String(row[:action]) == "flag_missing_loading_candidate" &&
        Int(row[:summary][:n_operations]) == 1 &&
        Bool(row[:validation_passed]), rows)
    @test any(row -> String(row[:scenario]) ==
        "extra_loading_candidate_flagged" &&
        String(row[:action]) == "flag_extra_loading_candidate" &&
        Int(row[:summary][:n_operations]) == 1 &&
        Bool(row[:validation_passed]), rows)
    @test any(row -> String(row[:scenario]) ==
        "ambiguous_loading_deferred" &&
        String(row[:action]) == "defer_ambiguous_loading_evidence" &&
        Int(row[:summary][:n_ambiguous_operations]) == 1, rows)
    @test any(row -> String(row[:scenario]) ==
        "empty_item_candidate_blocked" &&
        "empty_item_rows" in String.(row[:error_checks]) &&
        Bool(row[:summary][:invalid_candidate_blocked]), rows)
    @test any(row -> String(row[:scenario]) ==
        "duplicate_dimension_candidate_blocked" &&
        "duplicate_dimension_columns" in String.(row[:error_checks]) &&
        Bool(row[:summary][:invalid_candidate_blocked]), rows)
    @test any(row -> String(row[:scenario]) ==
        "simple_structure_cross_loading_policy_blocked" &&
        "cross_loading_policy" in String.(row[:error_checks]) &&
        String(row[:action]) == "block_policy_candidate_revision", rows)
    @test any(row -> String(row[:scenario]) ==
        "weak_dimension_facet_link_deferred" &&
        "dimension_facet_subgraph_coverage" in String.(row[:warning_checks]) &&
        Bool(row[:summary][:deferred_candidate]), rows)

    decision = fixture[:decision_record]
    @test Bool(decision[:empirical_q_recovery_allowed]) == false
    @test Bool(decision[:automatic_q_revision_allowed]) == false
    @test Bool(decision[:candidate_suggestions_allowed])
    @test String(decision[:required_followup]) ==
        "empirical_q_matrix_recovery_simulation_grid"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:q_matrix_validation_expansion_passed])
    @test Bool(summary[:uto_reference_recorded])
    @test Bool(summary[:research_basis_recorded])
    @test Bool(summary[:all_candidate_policy_scenarios_passed])
    @test Bool(summary[:invalid_suggested_q_blocked])
    @test Bool(summary[:ambiguous_or_weak_design_no_auto_revision])
    @test Bool(summary[:all_candidate_suggestions_validation_checked])
    @test Bool(summary[:no_public_automatic_q_revision])
    @test Bool(summary[:empirical_q_recovery_allowed]) == false
    @test Bool(summary[:candidate_suggestions_allowed])
    @test Int(summary[:n_reference_records]) == 1
    @test Int(summary[:n_candidate_policy_scenarios]) == length(rows)
    @test Int(summary[:n_passed_candidate_policy_scenarios]) == length(rows)
    @test Int(summary[:n_invalid_candidate_scenarios]) == 4
    @test Int(summary[:n_deferred_candidate_scenarios]) == 2
    @test Int(summary[:n_automatic_revisions_allowed]) == 0
    @test Set(String(blocker) for blocker in summary[:remaining_public_blockers]) ==
        Set([
            "empirical_q_matrix_recovery_simulation_grid_missing",
            "real_fit_diagnostic_linkage_missing",
            "cross_validated_q_revision_policy_missing",
            "construct_validity_manual_review_missing",
        ])
    @test String(summary[:recommendation]) ==
        "use_candidate_q_policy_for_local_diagnostics_only_then_run_recovery_simulation_grid"
    @test String(summary[:next_gate]) ==
        "empirical_q_matrix_recovery_simulation_grid"
end

function check_mgmfrm_empirical_q_matrix_recovery_simulation_grid_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_empirical_q_matrix_recovery_simulation_grid.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) ==
        "empirical_q_matrix_recovery_simulation_grid"
    @test String(fixture[:status]) ==
        "empirical_q_matrix_recovery_simulation_grid_recorded"
    @test String(fixture[:decision]) ==
        "keep_empirical_q_recovery_local_diagnostic_only"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])
    @test Bool(fixture[:empirical_q_recovery_public]) == false
    @test Bool(fixture[:publication_or_registration_action]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) ==
        "mgmfrm_empirical_q_matrix_recovery_simulation_grid_v1"
    @test String(protocol[:review_kind]) ==
        "local_empirical_q_matrix_recovery_simulation_grid"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test Bool(protocol[:local_only])
    @test Bool(thresholds[:require_empirical_q_matrix_recovery_policy_passed])
    @test Bool(thresholds[:require_q_matrix_reference_records_recorded])
    @test Bool(thresholds[:require_research_basis_recorded])
    @test Bool(thresholds[:require_all_scenarios_passed])
    @test Bool(thresholds[:require_all_candidate_validations_checked])
    @test Bool(thresholds[:require_candidate_exactness_recorded])
    @test Bool(thresholds[:require_false_public_promotion_rate_zero])
    @test Bool(thresholds[:require_no_automatic_q_revision])
    @test Bool(thresholds[:require_no_public_recovery_claim])
    @test Bool(thresholds[:require_no_publication_or_registration_action])

    reference_records = fixture[:q_matrix_reference_records]
    @test length(reference_records) == 7
    @test all(row -> all(key -> !occursin("item_key", String(key)),
        keys(row)), reference_records)
    @test all(row -> String(row[:source]) == "doi", reference_records)
    @test Set(String(row[:doi]) for row in reference_records) ==
        Set([
            "10.1007/s11336-015-9467-8",
            "10.1177/0013164418814898",
            "10.21449/ijate.407193",
            "10.1177/0146621620909904",
            "10.1177/0146621613488436",
            "10.1177/0146621616686021",
            "10.1177/0013164414539162",
        ])
    @test length(fixture[:scite_q_matrix_snapshot]) == 7
    @test all(row -> all(key -> !occursin("item_key", String(key)),
        keys(row)),
        fixture[:scite_q_matrix_snapshot])
    @test length(fixture[:research_basis]) == 7

    input_artifacts = fixture[:input_artifacts]
    @test length(input_artifacts) == 1
    input = only(input_artifacts)
    @test String(input[:artifact]) == "empirical_q_matrix_recovery_policy"
    @test String(input[:path]) ==
        "test/fixtures/mgmfrm_empirical_q_matrix_recovery_policy.json"
    @test Bool(input[:exists])
    @test Bool(input[:schema_matches])
    @test Bool(input[:summary_passed])
    @test String(input[:sha256]) ==
        file_sha256(joinpath(root, String(input[:path])))

    thresholds_row = fixture[:candidate_thresholds]
    @test Float64(thresholds_row[:add_loading]) == 0.75
    @test Float64(thresholds_row[:drop_loading]) == 0.25
    @test Float64(thresholds_row[:ambiguous_low]) == 0.45
    @test Float64(thresholds_row[:ambiguous_high]) == 0.55

    rows = fixture[:scenario_rows]
    @test length(rows) == 12
    @test Set(String(row[:scenario]) for row in rows) == Set([
        "well_separated_true_q_retained",
        "missing_loading_recovered_as_candidate",
        "extra_loading_removed_as_candidate",
        "ambiguous_cross_loading_deferred",
        "high_noise_false_add_not_promoted",
        "low_signal_false_drop_not_promoted",
        "duplicate_dimension_false_add_blocked",
        "weak_dimension_design_deferred",
        "iterative_single_item_missing_loading_candidate",
        "rater_consistency_noise_false_positive_manual_only",
        "three_dimension_anchor_recovery_retained",
        "sparse_isolated_attribute_design_retained",
    ])
    @test all(row -> Bool(row[:summary][:passed]), rows)
    @test all(row -> Bool(row[:summary][:candidate_validation_checked]), rows)
    @test all(row -> Bool(row[:automatic_revision_allowed]) == false, rows)
    @test all(row -> Bool(row[:public_recovery_allowed]) == false, rows)
    @test all(row -> Bool(row[:public_claim_allowed]) == false, rows)
    @test any(row -> String(row[:scenario]) ==
        "missing_loading_recovered_as_candidate" &&
        String(row[:action]) == "flag_missing_loading_candidate" &&
        Bool(row[:candidate_exact_recovery]) &&
        Bool(row[:candidate_improves_f1]), rows)
    @test any(row -> String(row[:scenario]) ==
        "extra_loading_removed_as_candidate" &&
        String(row[:action]) == "flag_extra_loading_candidate" &&
        Bool(row[:candidate_exact_recovery]) &&
        Bool(row[:candidate_improves_f1]), rows)
    @test any(row -> String(row[:scenario]) ==
        "high_noise_false_add_not_promoted" &&
        String(row[:action]) == "flag_noisy_candidate_manual_review" &&
        Bool(row[:false_candidate]) &&
        Bool(row[:summary][:false_candidate_manual_only]), rows)
    @test any(row -> String(row[:scenario]) ==
        "low_signal_false_drop_not_promoted" &&
        String(row[:action]) == "flag_noisy_candidate_manual_review" &&
        Bool(row[:false_candidate]) &&
        Bool(row[:summary][:false_candidate_manual_only]), rows)
    @test any(row -> String(row[:scenario]) ==
        "duplicate_dimension_false_add_blocked" &&
        "duplicate_dimension_columns" in String.(row[:error_checks]) &&
        Bool(row[:summary][:invalid_candidate_blocked]), rows)
    @test any(row -> String(row[:scenario]) ==
        "weak_dimension_design_deferred" &&
        "dimension_facet_subgraph_coverage" in String.(row[:warning_checks]) &&
        Bool(row[:summary][:deferred_candidate]), rows)
    @test any(row -> String(row[:scenario]) ==
        "rater_consistency_noise_false_positive_manual_only" &&
        String(row[:rater_consistency_profile]) ==
            "single_rater_pattern_false_positive" &&
        Bool(row[:false_candidate]), rows)

    decision = fixture[:decision_record]
    @test Bool(decision[:empirical_q_recovery_allowed]) == false
    @test Bool(decision[:automatic_q_revision_allowed]) == false
    @test Bool(decision[:candidate_suggestions_allowed])
    @test Bool(decision[:public_recovery_claim_allowed]) == false
    @test String(decision[:required_followup]) ==
        "real_fit_diagnostic_linkage_for_q_candidates"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:empirical_q_matrix_recovery_policy_passed])
    @test Bool(summary[:q_matrix_reference_records_recorded])
    @test Bool(summary[:research_basis_recorded])
    @test Bool(summary[:all_scenarios_passed])
    @test Bool(summary[:all_candidate_validations_checked])
    @test Bool(summary[:candidate_exactness_recorded])
    @test Bool(summary[:false_public_promotion_rate_zero])
    @test Bool(summary[:no_automatic_q_revision])
    @test Bool(summary[:no_public_recovery_claim])
    @test Bool(summary[:empirical_q_recovery_allowed]) == false
    @test Int(summary[:n_q_matrix_reference_records]) == 7
    @test Int(summary[:n_scenarios]) == length(rows)
    @test Int(summary[:n_passed_scenarios]) == length(rows)
    @test Int(summary[:n_candidate_exact_recoveries]) == 8
    @test Int(summary[:n_candidate_improved_over_declared]) == 3
    @test Int(summary[:n_false_candidate_scenarios]) == 4
    @test Int(summary[:n_deferred_scenarios]) == 2
    @test Int(summary[:n_blocked_scenarios]) == 1
    @test Int(summary[:n_public_revisions_allowed]) == 0
    @test Int(summary[:n_automatic_revisions_allowed]) == 0
    @test Float64(summary[:false_public_promotion_rate]) == 0.0
    @test Set(String(blocker) for blocker in summary[:remaining_public_blockers]) ==
        Set([
            "real_fit_diagnostic_linkage_missing",
            "cross_validated_q_revision_policy_missing",
            "construct_validity_manual_review_missing",
        ])
    @test String(summary[:recommendation]) ==
        "use_q_recovery_simulation_grid_for_local_candidate_diagnostics_only"
    @test String(summary[:next_gate]) ==
        "real_fit_diagnostic_linkage_for_q_candidates"
end
