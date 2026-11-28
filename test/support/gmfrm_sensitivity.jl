function check_gmfrm_sparse_pathology_recovery_grid_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.gmfrm_sparse_pathology_recovery_grid.v1"
    @test String(fixture[:family]) == "gmfrm"
    @test String(fixture[:scope]) == "scalar_gmfrm_fit_ready_candidate"
    @test String(fixture[:status]) ==
        "guarded_experimental_sparse_pathology_recovery_grid_recorded"
    @test String(fixture[:decision]) == "keep_guarded_experimental"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])

    protocol = fixture[:protocol]
    sampler = protocol[:sampler]
    diagnostics = protocol[:diagnostics]
    posterior_predictive = protocol[:posterior_predictive]
    thresholds = protocol[:thresholds]
    sparse_pathologies = protocol[:sparse_pathologies]
    validation_protocol = protocol[:validation]
    @test String(protocol[:protocol_id]) ==
        "scalar_gmfrm_sparse_pathology_recovery_grid_v1"
    @test String(protocol[:review_kind]) ==
        "local_guarded_experimental_sparse_pathology_recovery_grid"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test String(protocol[:entrypoint_under_validation]) ==
        "fit(spec; experimental = true) on sparse connected pathologies"
    @test String(protocol[:simulation_source]) ==
        "scalar_gmfrm_sparse_design_grid_scenarios"
    @test Set(String(protocol_id) for protocol_id in protocol[:reviewed_protocols]) ==
        Set([
            "scalar_gmfrm_sparse_design_grid_v1",
            "scalar_gmfrm_posterior_predictive_grid_v1",
        ])
    @test String(sparse_pathologies[:rating_density]) == "sparse_connected"
    @test Int(sparse_pathologies[:persons]) == 4
    @test Int(sparse_pathologies[:raters]) == 3
    @test Int(sparse_pathologies[:items]) == 3
    @test Int(sparse_pathologies[:categories]) == 3
    @test Set(String(pattern) for pattern in sparse_pathologies[:patterns]) == Set([
        "half_crossed_parity",
        "reference_bridge",
        "cyclic_missing_item_cells",
    ])
    @test Bool(validation_protocol[:require_no_validation_errors])
    @test Bool(validation_protocol[:require_connected_design])
    @test Bool(validation_protocol[:require_full_location_rank])
    @test Bool(validation_protocol[:warnings_recorded_not_blocking])
    @test String(sampler[:backend]) == "advancedhmc"
    @test String(sampler[:sampler]) == "nuts"
    @test Int(sampler[:chains]) == 2
    @test Int(sampler[:warmup]) == 12
    @test Int(sampler[:draws]) == 12
    @test Int(sampler[:max_depth]) == 8
    @test String(sampler[:metric]) == "unit"
    @test String(sampler[:ad_backend]) == "ForwardDiff"
    @test Bool(sampler[:split_chains])
    @test Float64(diagnostics[:rhat_threshold]) == 100.0
    @test Float64(diagnostics[:ess_threshold]) == 1.0
    @test Int(diagnostics[:loo_min_tail_draws]) == 5
    @test String(posterior_predictive[:draw_policy]) == "all_fit_draws"
    @test Float64(posterior_predictive[:interval]) == 0.9
    @test Int(posterior_predictive[:calibration_bins]) == 3
    @test String(posterior_predictive[:category_calibration]) ==
        "highest_observed_category"
    @test Int(thresholds[:n_scenarios]) == 3
    @test Int(thresholds[:min_observations]) == 18
    @test Int(thresholds[:max_observations]) == 35
    @test Int(thresholds[:n_replicates_per_scenario]) == 24
    @test Int(thresholds[:n_summary_rows]) == 14
    @test Bool(thresholds[:require_validation_passed])
    @test Bool(thresholds[:require_connected_design])
    @test Bool(thresholds[:require_full_location_rank])
    @test Bool(thresholds[:require_guarded_fit_returned])
    @test Bool(thresholds[:require_pointwise_shape])
    @test Bool(thresholds[:require_information_criteria_finite])
    @test Bool(thresholds[:require_no_divergences])
    @test Bool(thresholds[:require_no_max_treedepth])
    @test Bool(thresholds[:require_no_failed_direct_constraints])
    @test Bool(thresholds[:require_no_nonfinite_logdensity])
    @test Bool(thresholds[:require_no_nonfinite_direct_loglikelihood])
    @test Bool(thresholds[:require_replicated_scores_in_categories])
    @test Bool(thresholds[:require_probability_sums])
    @test Bool(thresholds[:require_summary_rows_finite])
    @test Bool(thresholds[:require_calibration_rows_finite])
    @test Float64(thresholds[:max_direct_parameter_mean_absolute_error]) == 8.0
    @test Float64(thresholds[:max_direct_block_mean_absolute_error]) == 5.0
    @test Float64(thresholds[:max_summary_outside_interval_rate]) == 0.85
    @test Float64(thresholds[:max_absolute_summary_error]) == 1.25
    @test Float64(thresholds[:max_absolute_mean_score_error]) == 1.0
    @test Float64(thresholds[:max_absolute_category_proportion_error]) == 1.0
    @test Float64(thresholds[:max_absolute_calibration_error]) == 1.25

    reviewed = fixture[:reviewed_artifacts]
    @test length(reviewed) == 2
    @test Set(String(row[:artifact]) for row in reviewed) == Set([
        "test/fixtures/gmfrm_sparse_design_grid.json",
        "test/fixtures/gmfrm_posterior_predictive_grid.json",
    ])
    for row in reviewed
        artifact = String(row[:artifact])
        @test Bool(row[:exists])
        @test String(row[:sha256]) == file_sha256(joinpath(root, artifact))
    end

    scenarios = fixture[:scenarios]
    @test length(scenarios) == 3
    @test Set(String(row[:scenario]) for row in scenarios) == Set([
        "balanced_parity_sparse",
        "reference_bridge_sparse",
        "cyclic_missing_item_sparse",
    ])
    @test Set(String(row[:sparse_pattern]) for row in scenarios) == Set([
        "half_crossed_parity",
        "reference_bridge",
        "cyclic_missing_item_cells",
    ])
    for scenario in scenarios
        n_observations = Int(scenario[:simulated_data][:n_observations])
        density = scenario[:design_density]
        @test String(density[:rating_density]) == "sparse_connected"
        @test Int(density[:n_observations]) == n_observations
        @test Int(density[:full_crossed_observations]) == 36
        @test Int(thresholds[:min_observations]) <= n_observations <=
            Int(thresholds[:max_observations])
        @test 0.0 < Float64(density[:observed_fraction]) < 1.0
        @test Int(density[:missing_observations]) > 0

        simulated = scenario[:simulated_data]
        @test Vector{Int}(simulated[:category_levels]) == [0, 1, 2]
        @test length(simulated[:person_levels]) == 4
        @test length(simulated[:rater_levels]) == 3
        @test length(simulated[:item_levels]) == 3
        @test length(simulated[:score_counts]) >= 1

        validation = scenario[:validation]
        @test Int(validation[:n_observations]) == n_observations
        @test Bool(validation[:passed])
        @test Int(validation[:n_errors]) == 0
        @test Int(validation[:n_warnings]) >= 1
        @test Int(validation[:n_components]) == 1
        @test Bool(validation[:location_design_full_rank])
        @test length(validation[:issue_rows]) >= 1
        @test length(validation[:issue_codes]) >= 1
        pathology_profile = scenario[:sparse_pathology_profile]
        @test Int(pathology_profile[:n_observations]) == n_observations
        @test Int(pathology_profile[:n_warnings]) == Int(validation[:n_warnings])
        @test Int(pathology_profile[:n_components]) == 1
        @test Bool(pathology_profile[:location_design_full_rank])
        @test length(pathology_profile[:warning_codes]) >= 1

        fit_record = scenario[:fit_record]
        @test String(fit_record[:type]) == "GMFRMFit"
        @test String(fit_record[:backend]) == "advancedhmc"
        @test String(fit_record[:sampler]) == "nuts"
        @test Vector{Int}(fit_record[:raw_draws_shape]) == [24, 17]
        @test Vector{Int}(fit_record[:direct_draws_shape]) == [24, 19]
        @test Vector{Int}(fit_record[:pointwise_loglikelihood_shape]) ==
            [24, n_observations]

        metadata = scenario[:metadata_review]
        @test Bool(metadata[:public_fit])
        @test Bool(metadata[:experimental_public])
        @test String(metadata[:family]) == "gmfrm"
        @test Int(metadata[:dimensions]) == 1
        @test String(metadata[:discrimination]) == "rater"
        @test Int(metadata[:n_draws]) == 24
        @test Int(metadata[:n_chains]) == 2
        @test Int(metadata[:draws_per_chain]) == 12
        @test Int(metadata[:n_parameters]) == 17
        @test Int(metadata[:n_direct_parameters]) == 19

        diagnostic_summary = scenario[:diagnostics_review][:summary]
        @test String(scenario[:diagnostics_review][:schema]) ==
            "bayesianmgmfrm.gmfrm_experimental_fit_diagnostics.v1"
        @test Bool(scenario[:diagnostics_review][:public_fit])
        @test Bool(scenario[:diagnostics_review][:experimental_public])
        @test String(diagnostic_summary[:flag]) == "ok"
        @test Bool(diagnostic_summary[:passed])
        @test Int(diagnostic_summary[:n_divergences]) == 0
        @test Int(diagnostic_summary[:n_max_treedepth]) == 0
        @test Int(diagnostic_summary[:n_failed_direct_constraints]) == 0
        @test Int(diagnostic_summary[:n_nonfinite_logdensity]) == 0
        @test Int(diagnostic_summary[:n_nonfinite_direct_loglikelihood]) == 0

        information = scenario[:information_criteria_review]
        @test Bool(information[:all_top_level_numeric_finite])
        @test Bool(information[:waic][:all_top_level_numeric_finite])
        @test Bool(information[:loo][:all_top_level_numeric_finite])
        @test Int(information[:waic][:n_observations]) == n_observations
        @test Int(information[:loo][:n_observations]) == n_observations
        @test length(scenario[:direct_recovery_rows]) == 19
        @test all(row -> Bool(row[:finite]), scenario[:direct_recovery_rows])
        @test length(scenario[:direct_recovery_by_block]) == 6
        @test all(row -> Bool(row[:all_finite]),
            scenario[:direct_recovery_by_block])

        predictive = scenario[:predictive_probability_review]
        @test Vector{Int}(predictive[:shape]) == [24, n_observations, 3]
        @test Bool(predictive[:probability_sums_valid])
        @test Float64(predictive[:max_probability_sum_error]) <= 1.0e-12
        @test Vector{Int}(predictive[:expected_scores][:shape]) ==
            [24, n_observations]
        @test Bool(predictive[:expected_scores][:all_finite])
        @test Float64(predictive[:expected_scores][:minimum]) >= 0.0
        @test Float64(predictive[:expected_scores][:maximum]) <= 2.0
        @test Vector{Int}(predictive[:predictive_variances][:shape]) ==
            [24, n_observations]
        @test Bool(predictive[:predictive_variances][:all_finite])
        @test Float64(predictive[:predictive_variances][:minimum]) >= -sqrt(eps())
        @test Bool(predictive[:expected_scores_in_range])

        ppc = scenario[:posterior_predictive_review]
        @test Vector{Int}(ppc[:replicated_scores_shape]) ==
            [24, n_observations]
        @test Bool(ppc[:replicated_scores_in_categories])
        @test Int(ppc[:n_summary_rows]) == 14
        @test length(ppc[:summary_rows]) == 14
        @test length(ppc[:summary_group_rows]) == 5
        @test all(row -> Int(row[:n_replicates]) == 24, ppc[:summary_rows])
        @test all(row -> String(row[:flag]) in ("ok", "outside_interval"),
            ppc[:summary_rows])
        @test Set(String(row[:statistic]) for row in ppc[:summary_group_rows]) ==
            Set(["mean_score", "category_proportion", "person_mean",
                "rater_mean", "item_mean"])

        calibration = scenario[:calibration_review]
        @test Int(calibration[:top_category]) == 2
        @test Int(calibration[:n_rows]) == 6
        @test Bool(calibration[:all_rows_finite])
        @test length(calibration[:expected_score_rows]) == 3
        @test length(calibration[:category_probability_rows]) == 3
        @test all(row -> String(row[:target]) == "expected_score",
            calibration[:expected_score_rows])
        @test all(row -> String(row[:target]) == "category_probability",
            calibration[:category_probability_rows])
        @test Float64(calibration[:max_absolute_calibration_error]) <=
            Float64(thresholds[:max_absolute_calibration_error])

        scenario_summary = scenario[:summary]
        @test Bool(scenario_summary[:passed])
        @test Int(scenario_summary[:n_observations]) == n_observations
        @test Bool(scenario_summary[:validation_passed])
        @test Int(scenario_summary[:validation_warnings]) >= 1
        @test Bool(scenario_summary[:location_design_full_rank])
        @test Bool(scenario_summary[:pointwise_shape_valid])
        @test Bool(scenario_summary[:information_criteria_finite])
        @test Int(scenario_summary[:n_divergences]) == 0
        @test Int(scenario_summary[:n_max_treedepth]) == 0
        @test Int(scenario_summary[:n_failed_direct_constraints]) == 0
        @test Int(scenario_summary[:n_nonfinite_logdensity]) == 0
        @test Int(scenario_summary[:n_nonfinite_direct_loglikelihood]) == 0
        @test Bool(scenario_summary[:ppc_returned])
        @test Int(scenario_summary[:n_replicates]) == 24
        @test Int(scenario_summary[:n_summary_rows]) == 14
        @test Bool(scenario_summary[:replicated_scores_in_categories])
        @test Bool(scenario_summary[:probability_sums_valid])
        @test Bool(scenario_summary[:summary_rows_finite])
        @test Bool(scenario_summary[:calibration_rows_finite])
        @test Bool(scenario_summary[:expected_scores_in_range])
        @test Bool(scenario_summary[:predictive_variances_nonnegative])
        @test Float64(scenario_summary[:max_direct_parameter_mean_absolute_error]) <=
            Float64(thresholds[:max_direct_parameter_mean_absolute_error])
        @test Float64(scenario_summary[:max_direct_block_mean_absolute_error]) <=
            Float64(thresholds[:max_direct_block_mean_absolute_error])
        @test Float64(scenario_summary[:outside_interval_rate]) <=
            Float64(thresholds[:max_summary_outside_interval_rate])
        @test Float64(scenario_summary[:max_absolute_summary_error]) <=
            Float64(thresholds[:max_absolute_summary_error])
        @test Float64(scenario_summary[:max_absolute_mean_score_error]) <=
            Float64(thresholds[:max_absolute_mean_score_error])
        @test Float64(scenario_summary[:max_absolute_category_proportion_error]) <=
            Float64(thresholds[:max_absolute_category_proportion_error])
        @test Float64(scenario_summary[:max_absolute_calibration_error]) <=
            Float64(thresholds[:max_absolute_calibration_error])
    end

    decision = fixture[:decision_record]
    @test Bool(decision[:public_fit_allowed])
    @test Bool(decision[:experimental_keyword_enabled])
    @test String(decision[:public_exposure_support]) ==
        "satisfied_for_scalar_gmfrm_prior_likelihood_sensitivity_grid_followup"
    @test String(decision[:interpretation]) ==
        "guarded_scalar_gmfrm_sparse_pathology_recovery_grid_passed"
    @test String(decision[:required_followup]) ==
        "scalar_gmfrm_prior_likelihood_sensitivity_grid"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Int(summary[:n_scenarios]) == 3
    @test Int(summary[:n_passed_scenarios]) == 3
    @test Int(summary[:n_replicates_per_scenario]) == 24
    @test Int(summary[:n_observations_minimum]) == 18
    @test Int(summary[:n_observations_maximum]) == 28
    @test Bool(summary[:all_validations_passed])
    @test Bool(summary[:all_location_designs_full_rank])
    @test Bool(summary[:all_guarded_fit_returned])
    @test Bool(summary[:all_pointwise_shapes_valid])
    @test Bool(summary[:all_information_criteria_finite])
    @test Bool(summary[:all_no_divergences])
    @test Bool(summary[:all_no_max_treedepth])
    @test Bool(summary[:all_no_failed_direct_constraints])
    @test Bool(summary[:all_no_nonfinite_logdensity])
    @test Bool(summary[:all_no_nonfinite_direct_loglikelihood])
    @test Bool(summary[:all_ppc_returned])
    @test Bool(summary[:all_replicated_scores_in_categories])
    @test Bool(summary[:all_probability_sums_valid])
    @test Bool(summary[:all_summary_rows_finite])
    @test Bool(summary[:all_calibration_rows_finite])
    @test Float64(summary[:max_direct_parameter_mean_absolute_error]) <=
        Float64(thresholds[:max_direct_parameter_mean_absolute_error])
    @test Float64(summary[:max_direct_block_mean_absolute_error]) <=
        Float64(thresholds[:max_direct_block_mean_absolute_error])
    @test Float64(summary[:max_outside_interval_rate]) <=
        Float64(thresholds[:max_summary_outside_interval_rate])
    @test Float64(summary[:max_absolute_summary_error]) <=
        Float64(thresholds[:max_absolute_summary_error])
    @test Float64(summary[:max_absolute_mean_score_error]) <=
        Float64(thresholds[:max_absolute_mean_score_error])
    @test Float64(summary[:max_absolute_category_proportion_error]) <=
        Float64(thresholds[:max_absolute_category_proportion_error])
    @test Float64(summary[:max_absolute_calibration_error]) <=
        Float64(thresholds[:max_absolute_calibration_error])
    @test Set(String(blocker) for blocker in summary[:remaining_public_blockers]) ==
        Set(["scalar_gmfrm_prior_likelihood_sensitivity_grid_missing"])
    @test String(summary[:recommendation]) ==
        "keep_guarded_experimental_until_prior_likelihood_sensitivity_grid"
    @test String(summary[:next_gate]) ==
        "scalar_gmfrm_prior_likelihood_sensitivity_grid"
end

function check_gmfrm_prior_likelihood_sensitivity_grid_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.gmfrm_prior_likelihood_sensitivity_grid.v1"
    @test String(fixture[:family]) == "gmfrm"
    @test String(fixture[:scope]) == "scalar_gmfrm_fit_ready_candidate"
    @test String(fixture[:status]) ==
        "guarded_experimental_prior_likelihood_sensitivity_grid_recorded"
    @test String(fixture[:decision]) == "keep_guarded_experimental"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    sampler = protocol[:sampler]
    sensitivity = protocol[:sensitivity_method]
    @test String(protocol[:protocol_id]) ==
        "scalar_gmfrm_prior_likelihood_sensitivity_grid_v1"
    @test String(protocol[:review_kind]) ==
        "local_guarded_experimental_prior_likelihood_sensitivity_grid"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test String(protocol[:entrypoint_under_validation]) ==
        "importance-reweighted fit(spec; experimental = true) prior and likelihood sensitivity"
    @test String(protocol[:simulation_source]) ==
        "scalar_gmfrm_sparse_pathology_recovery_grid_scenarios"
    @test Set(String(protocol_id) for protocol_id in protocol[:reviewed_protocols]) ==
        Set([
            "scalar_gmfrm_sparse_pathology_recovery_grid_v1",
            "scalar_gmfrm_guarded_exposure_review_v1",
        ])
    @test String(sensitivity[:draw_source]) ==
        "guarded_experimental_gmfrm_fit_draws"
    @test String(sensitivity[:prior_sensitivity]) ==
        "raw_coordinate_importance_reweighting"
    @test String(sensitivity[:likelihood_sensitivity]) ==
        "power_likelihood_tempering"
    @test String(sensitivity[:refit_policy]) ==
        "not_refit_local_guarded_screen"
    @test String(sensitivity[:normalization]) ==
        "self_normalized_importance_weights"
    @test String(sampler[:backend]) == "advancedhmc"
    @test String(sampler[:sampler]) == "nuts"
    @test Int(sampler[:chains]) == 2
    @test Int(sampler[:warmup]) == 12
    @test Int(sampler[:draws]) == 12
    @test Int(sampler[:max_depth]) == 8
    @test String(sampler[:metric]) == "unit"

    @test length(protocol[:prior_profiles]) == 5
    @test Set(String(profile[:name]) for profile in protocol[:prior_profiles]) == Set([
        "baseline_raw_prior",
        "globally_tighter_raw_prior",
        "globally_weaker_raw_prior",
        "tighter_generalized_scale_prior",
        "weaker_generalized_scale_prior",
    ])
    @test Float64.(protocol[:likelihood_powers]) == [0.8, 1.0, 1.2]
    @test Int(thresholds[:n_scenarios]) == 3
    @test Int(thresholds[:n_prior_profiles]) == 5
    @test Int(thresholds[:n_likelihood_powers]) == 3
    @test Int(thresholds[:n_sensitivity_cells]) == 15
    @test Int(thresholds[:n_draws_per_cell]) == 24
    @test Bool(thresholds[:require_guarded_fit_returned])
    @test Bool(thresholds[:require_all_logweights_finite])
    @test Bool(thresholds[:require_baseline_identity])
    @test Bool(thresholds[:require_all_direct_shifts_finite])
    @test Bool(thresholds[:require_all_predictive_shifts_finite])
    @test Float64(thresholds[:require_weight_ess_rate_minimum]) == 0.05
    @test Float64(thresholds[:max_direct_parameter_mean_shift]) == 3.0
    @test Float64(thresholds[:max_direct_block_mean_shift]) == 2.0
    @test Float64(thresholds[:max_expected_score_shift]) == 1.25
    @test Float64(thresholds[:max_top_category_probability_shift]) == 0.60
    @test Float64(thresholds[:max_loglikelihood_mean_shift]) == 20.0
    @test Float64(thresholds[:max_logposterior_decomposition_error]) == 1.0e-8

    reviewed = fixture[:reviewed_artifacts]
    @test length(reviewed) == 2
    @test Set(String(row[:artifact]) for row in reviewed) == Set([
        "test/fixtures/gmfrm_sparse_pathology_recovery_grid.json",
        "test/fixtures/gmfrm_guarded_exposure_review.json",
    ])
    sparse_reference = only(row for row in reviewed
        if String(row[:artifact]) ==
            "test/fixtures/gmfrm_sparse_pathology_recovery_grid.json")
    @test Bool(sparse_reference[:exists])
    @test String(sparse_reference[:hash_policy]) == "sha256"
    @test String(sparse_reference[:sha256]) ==
        file_sha256(joinpath(root, String(sparse_reference[:artifact])))
    guarded_reference = only(row for row in reviewed
        if String(row[:artifact]) ==
            "test/fixtures/gmfrm_guarded_exposure_review.json")
    @test Bool(guarded_reference[:exists])
    @test String(guarded_reference[:hash_policy]) ==
        "existence_only_avoids_cyclic_review_hash"
    @test isnothing(guarded_reference[:sha256])

    scenarios = fixture[:scenarios]
    @test length(scenarios) == 3
    @test Set(String(row[:scenario]) for row in scenarios) == Set([
        "balanced_parity_sparse",
        "reference_bridge_sparse",
        "cyclic_missing_item_sparse",
    ])
    @test Set(String(row[:sparse_pattern]) for row in scenarios) == Set([
        "half_crossed_parity",
        "reference_bridge",
        "cyclic_missing_item_cells",
    ])
    for scenario in scenarios
        n_observations = Int(scenario[:n_observations])
        fit_record = scenario[:fit_record]
        @test String(fit_record[:type]) == "GMFRMFit"
        @test Vector{Int}(fit_record[:raw_draws_shape]) == [24, 17]
        @test Vector{Int}(fit_record[:direct_draws_shape]) == [24, 19]
        @test Vector{Int}(fit_record[:pointwise_loglikelihood_shape]) ==
            [24, n_observations]

        baseline_prior = scenario[:baseline_prior]
        @test Float64(baseline_prior[:person_sd]) == 1.0
        @test Float64(baseline_prior[:rater_sd]) == 1.0
        @test Float64(baseline_prior[:item_sd]) == 1.0
        @test Float64(baseline_prior[:log_discrimination_sd]) == 0.5
        @test Float64(baseline_prior[:log_consistency_sd]) == 0.5
        @test Float64(baseline_prior[:step_sd]) == 1.0
        decomposition = scenario[:baseline_logposterior_decomposition]
        @test Bool(decomposition[:passed])
        @test Float64(decomposition[:maximum_absolute_error]) <=
            Float64(thresholds[:max_logposterior_decomposition_error])

        cells = scenario[:sensitivity_cells]
        @test length(cells) == 15
        @test Set(String(cell[:prior_profile]) for cell in cells) == Set([
            "baseline_raw_prior",
            "globally_tighter_raw_prior",
            "globally_weaker_raw_prior",
            "tighter_generalized_scale_prior",
            "weaker_generalized_scale_prior",
        ])
        @test Set(Float64(cell[:likelihood_power]) for cell in cells) ==
            Set([0.8, 1.0, 1.2])
        baseline_cell = only(cell for cell in cells
            if String(cell[:prior_profile]) == "baseline_raw_prior" &&
                Float64(cell[:likelihood_power]) == 1.0)
        @test Float64(baseline_cell[:summary][:max_direct_parameter_mean_shift]) <=
            1.0e-10
        @test Float64(baseline_cell[:summary][:max_expected_score_shift]) <=
            1.0e-10
        @test Float64(baseline_cell[:summary][:max_top_category_probability_shift]) <=
            1.0e-10

        for cell in cells
            @test Int(cell[:n_draws]) == 24
            weight = cell[:weight_review]
            @test Bool(weight[:all_logweights_finite])
            @test Float64(weight[:logweight_range]) >= 0.0
            @test Float64(weight[:effective_sample_size]) >= 1.0
            @test Float64(weight[:effective_sample_size_rate]) >=
                Float64(thresholds[:require_weight_ess_rate_minimum])
            @test 0.0 <= Float64(weight[:maximum_weight]) <= 1.0
            @test 0.0 <= Float64(weight[:normalized_entropy]) <=
                1.0 + 10eps(Float64)

            prior_review = cell[:logprior_review]
            @test Bool(prior_review[:baseline][:all_finite])
            @test Bool(prior_review[:sensitivity][:all_finite])
            @test Bool(prior_review[:delta][:all_finite])
            loglikelihood = cell[:loglikelihood_review]
            @test isfinite(Float64(loglikelihood[:baseline_mean]))
            @test isfinite(Float64(loglikelihood[:weighted_mean]))
            @test Float64(loglikelihood[:absolute_shift]) <=
                Float64(thresholds[:max_loglikelihood_mean_shift])

            direct_rows = cell[:direct_parameter_shift_rows]
            @test length(direct_rows) == 19
            @test all(row -> Bool(row[:finite]), direct_rows)
            @test all(row -> isfinite(Float64(row[:absolute_shift])), direct_rows)
            block_rows = cell[:direct_block_shift_rows]
            @test length(block_rows) == 6
            @test all(row -> Bool(row[:all_finite]), block_rows)
            @test all(row -> Float64(row[:mean_absolute_shift]) <=
                Float64(thresholds[:max_direct_block_mean_shift]), block_rows)

            predictive = cell[:predictive_shift_review]
            @test Float64(predictive[:expected_score_max_absolute_shift]) <=
                Float64(thresholds[:max_expected_score_shift])
            @test Float64(predictive[:top_category_probability_max_absolute_shift]) <=
                Float64(thresholds[:max_top_category_probability_shift])

            cell_summary = cell[:summary]
            @test Bool(cell_summary[:all_logweights_finite])
            @test Float64(cell_summary[:weight_ess_rate]) >=
                Float64(thresholds[:require_weight_ess_rate_minimum])
            @test Float64(cell_summary[:max_direct_parameter_mean_shift]) <=
                Float64(thresholds[:max_direct_parameter_mean_shift])
            @test Float64(cell_summary[:max_direct_block_mean_shift]) <=
                Float64(thresholds[:max_direct_block_mean_shift])
            @test Float64(cell_summary[:max_expected_score_shift]) <=
                Float64(thresholds[:max_expected_score_shift])
            @test Float64(cell_summary[:max_top_category_probability_shift]) <=
                Float64(thresholds[:max_top_category_probability_shift])
            @test Float64(cell_summary[:loglikelihood_mean_absolute_shift]) <=
                Float64(thresholds[:max_loglikelihood_mean_shift])
        end

        scenario_summary = scenario[:summary]
        @test Bool(scenario_summary[:passed])
        @test Int(scenario_summary[:n_sensitivity_cells]) == 15
        @test Int(scenario_summary[:n_prior_profiles]) == 5
        @test Int(scenario_summary[:n_likelihood_powers]) == 3
        @test Bool(scenario_summary[:all_cells_finite])
        @test Bool(scenario_summary[:baseline_identity])
        @test Float64(scenario_summary[:min_weight_ess_rate]) >=
            Float64(thresholds[:require_weight_ess_rate_minimum])
        @test Float64(scenario_summary[:max_weight]) <= 1.0
        @test Float64(scenario_summary[:max_direct_parameter_mean_shift]) <=
            Float64(thresholds[:max_direct_parameter_mean_shift])
        @test Float64(scenario_summary[:max_direct_block_mean_shift]) <=
            Float64(thresholds[:max_direct_block_mean_shift])
        @test Float64(scenario_summary[:max_expected_score_shift]) <=
            Float64(thresholds[:max_expected_score_shift])
        @test Float64(scenario_summary[:max_top_category_probability_shift]) <=
            Float64(thresholds[:max_top_category_probability_shift])
        @test Float64(scenario_summary[:max_loglikelihood_mean_shift]) <=
            Float64(thresholds[:max_loglikelihood_mean_shift])
        @test Float64(scenario_summary[:max_logposterior_decomposition_error]) <=
            Float64(thresholds[:max_logposterior_decomposition_error])
    end

    decision = fixture[:decision_record]
    @test Bool(decision[:public_fit_allowed])
    @test Bool(decision[:experimental_keyword_enabled])
    @test String(decision[:public_exposure_support]) ==
        "satisfied_for_scalar_gmfrm_real_data_case_study_followup"
    @test String(decision[:interpretation]) ==
        "guarded_scalar_gmfrm_prior_likelihood_sensitivity_grid_passed"
    @test String(decision[:required_followup]) ==
        "scalar_gmfrm_real_data_case_study"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Int(summary[:n_scenarios]) == 3
    @test Int(summary[:n_passed_scenarios]) == 3
    @test Int(summary[:n_sensitivity_cells]) == 45
    @test Int(summary[:n_prior_profiles]) == 5
    @test Int(summary[:n_likelihood_powers]) == 3
    @test Bool(summary[:all_cells_finite])
    @test Bool(summary[:all_baseline_identity])
    @test Float64(summary[:min_weight_ess_rate]) >=
        Float64(thresholds[:require_weight_ess_rate_minimum])
    @test Float64(summary[:max_weight]) <= 1.0
    @test Float64(summary[:max_direct_parameter_mean_shift]) <=
        Float64(thresholds[:max_direct_parameter_mean_shift])
    @test Float64(summary[:max_direct_block_mean_shift]) <=
        Float64(thresholds[:max_direct_block_mean_shift])
    @test Float64(summary[:max_expected_score_shift]) <=
        Float64(thresholds[:max_expected_score_shift])
    @test Float64(summary[:max_top_category_probability_shift]) <=
        Float64(thresholds[:max_top_category_probability_shift])
    @test Float64(summary[:max_loglikelihood_mean_shift]) <=
        Float64(thresholds[:max_loglikelihood_mean_shift])
    @test Float64(summary[:max_logposterior_decomposition_error]) <=
        Float64(thresholds[:max_logposterior_decomposition_error])
    @test Set(String(blocker) for blocker in summary[:remaining_public_blockers]) ==
        Set(["scalar_gmfrm_real_data_case_study_missing"])
    @test String(summary[:recommendation]) ==
        "keep_guarded_experimental_until_real_data_case_study"
    @test String(summary[:next_gate]) ==
        "scalar_gmfrm_real_data_case_study"
end

function check_gmfrm_real_data_case_study_fixture(fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.gmfrm_real_data_case_study.v1"
    @test String(fixture[:family]) == "gmfrm"
    @test String(fixture[:scope]) == "scalar_gmfrm_fit_ready_candidate"
    @test String(fixture[:status]) ==
        "guarded_experimental_real_data_case_study_recorded"
    @test String(fixture[:decision]) == "keep_guarded_experimental"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    selection = protocol[:selection]
    source_policy = protocol[:source_policy]
    @test String(protocol[:protocol_id]) ==
        "scalar_gmfrm_real_data_case_study_v1"
    @test String(protocol[:review_kind]) ==
        "local_guarded_experimental_real_data_case_study"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test Bool(protocol[:local_only])
    @test Bool(source_policy[:source_files_external_to_package])
    @test Bool(source_policy[:artifact_rows_anonymized])
    @test Bool(source_policy[:no_raw_text_exported])
    @test Int(selection[:person_count]) == 4
    @test Int(selection[:rater_count]) == 3
    @test Int(selection[:criterion_count]) == 3
    @test Bool(selection[:require_complete_crossing_after_selection])
    @test Int(thresholds[:n_cases]) == 2
    @test Int(thresholds[:n_observations_per_case]) == 36
    @test Int(thresholds[:n_replicates_per_case]) == 24
    @test Bool(thresholds[:require_source_file_available])
    @test Bool(thresholds[:require_validation_passed])
    @test Bool(thresholds[:require_complete_crossing])
    @test Bool(thresholds[:require_guarded_fit_returned])
    @test Bool(thresholds[:require_baseline_fits_returned])
    @test Bool(thresholds[:require_model_comparison_finite])

    reviewed = fixture[:reviewed_artifacts]
    @test length(reviewed) == 4
    @test Set(String(row[:artifact]) for row in reviewed) == Set([
        "../Simulation/data/writing_long.csv",
        "../Simulation/data/speaking_long.csv",
        "test/fixtures/gmfrm_prior_likelihood_sensitivity_grid.json",
        "test/fixtures/gmfrm_guarded_exposure_review.json",
    ])
    for row in reviewed
        @test Bool(row[:exists])
        if String(row[:hash_policy]) == "sha256"
            check_fixture_sha256_when_available(
                root, String(row[:artifact]), String(row[:sha256]))
        else
            @test String(row[:hash_policy]) ==
                "existence_only_avoids_cyclic_review_hash"
            @test isnothing(row[:sha256])
        end
    end

    cases = fixture[:cases]
    @test length(cases) == 2
    @test Set(String(case[:case_id]) for case in cases) == Set([
        "writing_icnale_small_slice",
        "speaking_icnale_small_slice",
    ])
    for case in cases
        selected = case[:selected_data]
        @test Int(selected[:n_observations]) == 36
        @test Bool(selected[:complete_crossing])
        @test length(selected[:person_levels]) == 4
        @test length(selected[:rater_levels]) == 3
        @test length(selected[:item_levels]) == 3
        @test Vector{Int}(selected[:category_levels]) == [0, 1, 2]

        validation = case[:validation]
        @test Bool(validation[:passed])
        @test Int(validation[:n_errors]) == 0
        @test Int(validation[:n_warnings]) >= 0
        @test all(row -> String(row[:severity]) == "warning",
            validation[:issue_rows])
        @test Bool(validation[:location_design_full_rank])

        metadata = case[:metadata_review]
        @test Bool(metadata[:public_fit])
        @test Bool(metadata[:experimental_public])
        @test String(metadata[:family]) == "gmfrm"
        @test Int(metadata[:n_draws]) == 24
        @test Int(metadata[:n_parameters]) == 17
        @test Int(metadata[:n_direct_parameters]) == 19

        fit_record = case[:fit_record]
        @test String(fit_record[:type]) == "GMFRMFit"
        @test Vector{Int}(fit_record[:raw_draws_shape]) == [24, 17]
        @test Vector{Int}(fit_record[:direct_draws_shape]) == [24, 19]
        @test Vector{Int}(fit_record[:pointwise_loglikelihood_shape]) == [24, 36]

        diagnostics = case[:diagnostics_review][:summary]
        @test Bool(diagnostics[:passed])
        @test Int(diagnostics[:n_divergences]) == 0
        @test Int(diagnostics[:n_max_treedepth]) == 0
        @test Int(diagnostics[:n_failed_direct_constraints]) == 0
        @test Int(diagnostics[:n_nonfinite_logdensity]) == 0
        @test Int(diagnostics[:n_nonfinite_direct_loglikelihood]) == 0

        information = case[:information_criteria_review]
        @test Bool(information[:all_top_level_numeric_finite])
        @test String(information[:waic][:criterion]) == "waic"
        @test String(information[:loo][:criterion]) == "loo"

        ppc = case[:posterior_predictive_review]
        @test Vector{Int}(ppc[:replicated_scores_shape]) == [24, 36]
        @test Bool(ppc[:replicated_scores_in_categories])
        @test Int(ppc[:n_summary_rows]) == 14
        @test all(row -> String(row[:flag]) in ("ok", "outside_interval"),
            ppc[:summary_rows])

        calibration = case[:calibration_review]
        @test Int(calibration[:top_category]) == 2
        @test Int(calibration[:n_rows]) == 6
        @test Bool(calibration[:all_rows_finite])
        @test Float64(calibration[:max_absolute_calibration_error]) <=
            Float64(thresholds[:max_absolute_calibration_error])

        model_records = case[:model_records]
        @test length(model_records) == 3
        @test Set(String(row[:model]) for row in model_records) == Set([
            "guarded_scalar_gmfrm",
            "public_mfrm_partial_credit",
            "public_mfrm_rating_scale",
        ])
        @test all(row -> Bool(row[:information_criteria][:all_top_level_numeric_finite]),
            model_records)

        comparison = case[:model_comparison]
        @test length(comparison) == 3
        @test [Int(row[:rank]) for row in comparison] == [1, 2, 3]
        @test all(row -> String(row[:criterion]) == "waic", comparison)
        @test all(row -> isfinite(Float64(row[:elpd_waic])) &&
            isfinite(Float64(row[:waic])), comparison)
        @test sum(Float64(row[:relative_weight]) for row in comparison) ≈ 1.0

        summary = case[:summary]
        @test Bool(summary[:passed])
        @test Int(summary[:n_observations]) == 36
        @test Bool(summary[:complete_crossing])
        @test Bool(summary[:validation_passed])
        @test Bool(summary[:guarded_fit_returned])
        @test Bool(summary[:baseline_fits_returned])
        @test Bool(summary[:pointwise_shape_valid])
        @test Bool(summary[:information_criteria_finite])
        @test Bool(summary[:model_comparison_finite])
        @test Bool(summary[:ppc_returned])
        @test Int(summary[:n_replicates]) == 24
        @test Bool(summary[:replicated_scores_in_categories])
        @test Bool(summary[:probability_sums_valid])
        @test Bool(summary[:summary_rows_finite])
        @test Bool(summary[:calibration_rows_finite])
        @test Float64(summary[:outside_interval_rate]) <=
            Float64(thresholds[:max_summary_outside_interval_rate])
        @test Float64(summary[:max_absolute_summary_error]) <=
            Float64(thresholds[:max_absolute_summary_error])
        @test Float64(summary[:max_absolute_calibration_error]) <=
            Float64(thresholds[:max_absolute_calibration_error])
    end

    decision = fixture[:decision_record]
    @test Bool(decision[:public_fit_allowed])
    @test Bool(decision[:experimental_keyword_enabled])
    @test String(decision[:public_exposure_support]) ==
        "satisfied_for_scalar_gmfrm_manuscript_claim_followup"
    @test String(decision[:interpretation]) ==
        "guarded_scalar_gmfrm_real_data_case_study_passed"
    @test String(decision[:required_followup]) ==
        "claim_level_recovery_and_reproduction_archive"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Int(summary[:n_cases]) == 2
    @test Int(summary[:n_passed_cases]) == 2
    @test Int(summary[:n_observations_total]) == 72
    @test Int(summary[:n_replicates_per_case]) == 24
    @test Bool(summary[:all_source_files_available])
    @test Bool(summary[:all_validations_passed])
    @test Bool(summary[:all_complete_crossing])
    @test Bool(summary[:all_guarded_fit_returned])
    @test Bool(summary[:all_baseline_fits_returned])
    @test Bool(summary[:all_pointwise_shapes_valid])
    @test Bool(summary[:all_information_criteria_finite])
    @test Bool(summary[:all_model_comparisons_finite])
    @test Bool(summary[:all_no_divergences])
    @test Bool(summary[:all_no_max_treedepth])
    @test Bool(summary[:all_no_failed_direct_constraints])
    @test Bool(summary[:all_no_nonfinite_logdensity])
    @test Bool(summary[:all_no_nonfinite_direct_loglikelihood])
    @test Bool(summary[:all_ppc_returned])
    @test Bool(summary[:all_replicated_scores_in_categories])
    @test Bool(summary[:all_probability_sums_valid])
    @test Bool(summary[:all_summary_rows_finite])
    @test Bool(summary[:all_calibration_rows_finite])
    @test Float64(summary[:max_outside_interval_rate]) <=
        Float64(thresholds[:max_summary_outside_interval_rate])
    @test Float64(summary[:max_absolute_summary_error]) <=
        Float64(thresholds[:max_absolute_summary_error])
    @test Float64(summary[:max_absolute_calibration_error]) <=
        Float64(thresholds[:max_absolute_calibration_error])
    @test Set(String(blocker) for blocker in summary[:remaining_public_blockers]) ==
        Set(["claim_level_recovery_and_reproduction_archive_missing"])
    @test String(summary[:recommendation]) ==
        "keep_guarded_experimental_until_claim_level_recovery_and_archive"
    @test String(summary[:next_gate]) ==
        "claim_level_recovery_and_reproduction_archive"
end
