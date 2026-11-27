function check_mgmfrm_fit_threshold_q_heldout_linkage_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_fit_threshold_q_heldout_linkage.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) == "fit_threshold_q_heldout_linkage"
    @test String(fixture[:status]) ==
        "fit_threshold_q_heldout_linkage_recorded"
    @test String(fixture[:decision]) ==
        "record_fit_threshold_q_heldout_linkage_keep_public_claims_blocked"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])
    @test Bool(fixture[:local_only])
    @test Bool(fixture[:pilot_only])
    @test Bool(fixture[:publication_or_registration_action]) == false
    @test Bool(fixture[:public_fit_metric_claim]) == false
    @test Bool(fixture[:public_q_revision_claim]) == false
    @test Bool(fixture[:public_model_weight_claim]) == false
    @test Bool(fixture[:sparse_mgmfrm_superiority_claim]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) ==
        "mgmfrm_fit_threshold_q_heldout_linkage_v1"
    @test String(protocol[:review_kind]) ==
        "local_fit_threshold_q_heldout_linkage"
    @test Bool(protocol[:local_only])
    @test Bool(protocol[:pilot_only])
    @test String(protocol[:decision_target]) ==
        "connect_threshold_profiles_q_diagnostics_and_fold1_heldout_scores"
    @test Bool(thresholds[:require_fit_metric_threshold_sensitivity_passed])
    @test Bool(thresholds[
        :require_empirical_q_matrix_recovery_simulation_grid_passed])
    @test Bool(thresholds[:require_heldout_prediction_simulation_grid_passed])
    @test Bool(thresholds[:require_fold1_scoring_passed])
    @test Bool(thresholds[:require_all_scenario_link_rows_recorded])
    @test Bool(thresholds[:require_threshold_profile_link_rows_recorded])
    @test Bool(thresholds[:require_q_recovery_link_rows_recorded])
    @test Bool(thresholds[:require_parameter_absorption_rows_recorded])
    @test Bool(thresholds[:require_fold1_observed_rank_recorded])
    @test Bool(thresholds[:require_observed_vs_expected_rank_match_recorded])
    @test Bool(thresholds[:require_any_observed_expected_mismatch_flagged])
    @test Bool(thresholds[:require_anchor_limitations_recorded])
    @test Bool(thresholds[:require_no_single_threshold_profile_promoted])
    @test Bool(thresholds[:require_no_automatic_q_revision])
    @test Bool(thresholds[:require_no_public_fit_metric_claim])
    @test Bool(thresholds[:require_no_public_q_revision_claim])
    @test Bool(thresholds[:require_no_public_model_weight_claim])
    @test Bool(thresholds[:require_no_sparse_superiority_claim])

    inputs = fixture[:input_artifacts]
    expected_inputs = Dict(
        "mgmfrm_fit_metric_threshold_sensitivity" =>
            "test/fixtures/mgmfrm_fit_metric_threshold_sensitivity.json",
        "mgmfrm_empirical_q_matrix_recovery_simulation_grid" =>
            "test/fixtures/mgmfrm_empirical_q_matrix_recovery_simulation_grid.json",
        "mgmfrm_heldout_prediction_simulation_grid" =>
            "test/fixtures/mgmfrm_heldout_prediction_simulation_grid.json",
        "mgmfrm_full_heldout_mcmc_refit_fold1_scoring" =>
            "test/fixtures/mgmfrm_full_heldout_mcmc_refit_fold1_scoring.json",
    )
    @test length(inputs) == length(expected_inputs)
    @test Set(String(row[:artifact]) for row in inputs) ==
        Set(keys(expected_inputs))
    for row in inputs
        artifact = String(row[:artifact])
        @test String(row[:path]) == expected_inputs[artifact]
        @test Bool(row[:exists])
        @test Bool(row[:schema_matches])
        @test Bool(row[:summary_passed])
        @test String(row[:sha256]) ==
            file_sha256(joinpath(root, String(row[:path])))
    end
    heldout_simulation = JSON3.read(read(joinpath(root,
        expected_inputs["mgmfrm_heldout_prediction_simulation_grid"]), String))
    fold1_scoring = JSON3.read(read(joinpath(root,
        expected_inputs[
            "mgmfrm_full_heldout_mcmc_refit_fold1_scoring"]), String))
    expected_scenario_rows = heldout_simulation[:scenario_rows]
    fold1_rank_rows = fold1_scoring[:candidate_rank_rows]

    scenarios = Set([
        "well_specified_current_q",
        "missing_loading_revised_q",
        "sparse_signal_current_q",
        "rater_method_noise",
        "weak_dimension_ambiguous",
    ])
    scenario_rows = fixture[:scenario_link_rows]
    @test length(scenario_rows) == 5
    @test Set(String(row[:scenario]) for row in scenario_rows) == scenarios
    @test all(row -> Bool(row[:public_claim_allowed]) == false,
        scenario_rows)
    n_observed_expected_matches = count(
        row -> Bool(row[:observed_best_matches_expected]), scenario_rows)
    n_observed_expected_mismatches = count(
        row -> !Bool(row[:observed_best_matches_expected]), scenario_rows)
    n_expected_models_not_scored = count(
        row -> !Bool(row[:expected_model_scored_fold1]), scenario_rows)
    @test n_observed_expected_matches + n_observed_expected_mismatches ==
        length(scenario_rows)
    @test n_observed_expected_mismatches > 0
    @test n_expected_models_not_scored == 1
    @test all(row -> isfinite(Float64(row[:observed_fold1_best_elpd])) &&
            isfinite(Float64(row[:observed_fold1_best_mae])) &&
            isfinite(Float64(row[:delta_elpd_waic])) &&
            isfinite(Float64(row[:delta_elpd_loo])) &&
            isfinite(Float64(row[:max_abs_common_direct_parameter_shift])),
        scenario_rows)
    for scenario_row in scenario_rows
        scenario = String(scenario_row[:scenario])
        expected_row = only(row for row in expected_scenario_rows
            if String(row[:scenario]) == scenario)
        ranks = [row for row in fold1_rank_rows
            if String(row[:scenario]) == scenario]
        best_elpd = only(row for row in ranks if Int(row[:rank]) == 1)
        best_mae = first(sort(ranks;
            by = row -> Float64(row[:heldout_expected_score_mae])))
        expected_model = String(expected_row[:expected_best_model])
        observed_model = String(best_elpd[:model])
        expected_model_scored = any(
            row -> String(row[:model]) == expected_model, ranks)
        observed_matches_expected =
            expected_model_scored && observed_model == expected_model
        expected_interpretation = observed_matches_expected ?
            "fold1_pilot_matches_predeclared_expected_best" :
            "fold1_pilot_differs_or_expected_anchor_not_scored"

        @test String(scenario_row[:expected_best_model]) == expected_model
        @test String(scenario_row[:observed_fold1_best_model]) ==
            observed_model
        @test Float64(scenario_row[:observed_fold1_best_elpd]) ==
            Float64(best_elpd[:heldout_elpd])
        @test Bool(scenario_row[:expected_model_scored_fold1]) ==
            expected_model_scored
        @test Bool(scenario_row[:observed_best_matches_expected]) ==
            observed_matches_expected
        @test String(scenario_row[:observed_fold1_best_mae_model]) ==
            String(best_mae[:model])
        @test Float64(scenario_row[:observed_fold1_best_mae]) ==
            Float64(best_mae[:heldout_expected_score_mae])
        @test String(scenario_row[:interpretation]) ==
            expected_interpretation
    end
    missing_loading = only(row for row in scenario_rows
        if String(row[:scenario]) == "missing_loading_revised_q")
    @test String(missing_loading[:expected_best_model]) ==
        "construct_reviewed_revised_q_mgmfrm"
    rater_noise = only(row for row in scenario_rows
        if String(row[:scenario]) == "rater_method_noise")
    @test String(rater_noise[:expected_best_model]) == "scalar_gmfrm_baseline"
    @test Bool(rater_noise[:expected_model_scored_fold1]) == false
    @test String(rater_noise[:q_recovery_scenario]) ==
        "rater_consistency_noise_false_positive_manual_only"
    @test Bool(rater_noise[:q_false_candidate])

    threshold_rows = fixture[:threshold_profile_link_rows]
    @test length(threshold_rows) == 20
    @test Set(String(row[:scenario]) for row in threshold_rows) == scenarios
    @test all(row -> Bool(row[:public_claim_allowed]) == false,
        threshold_rows)
    @test count(row -> !Bool(row[:ranking_stable_under_profile]),
        threshold_rows) == 5
    @test any(row -> String(row[:scenario]) == "rater_method_noise" &&
        String(row[:threshold_profile]) == "strict_bayesian_workflow" &&
        !Bool(row[:ranking_stable_under_profile]), threshold_rows)

    q_rows = fixture[:q_recovery_link_rows]
    @test length(q_rows) == 5
    @test all(row -> Bool(row[:q_revision_claim_allowed]) == false,
        q_rows)
    @test count(row -> Bool(row[:q_false_candidate]), q_rows) == 1
    @test any(row -> String(row[:scenario]) == "rater_method_noise" &&
        String(row[:q_action]) == "flag_noisy_candidate_manual_review",
        q_rows)

    absorption_rows = fixture[:parameter_absorption_rows]
    @test length(absorption_rows) == 5
    @test all(row -> Bool(row[:public_fit_metric_claim_allowed]) == false,
        absorption_rows)
    @test all(row -> isfinite(Float64(row[:max_abs_common_direct_parameter_shift])) &&
            isfinite(Float64(row[:delta_elpd_waic])) &&
            isfinite(Float64(row[:delta_elpd_loo])),
        absorption_rows)

    anchor_rows = fixture[:anchor_limitation_rows]
    @test length(anchor_rows) == 6
    @test Set(String(row[:blocker]) for row in anchor_rows) == Set([
        "fold1_only_remaining_folds_not_scored",
        "full_125_unit_refit_batch_not_completed",
        "comparison_anchor_mcmc_refits_not_run",
        "publication_grade_chains_and_draws_not_run",
        "external_construct_dataset_missing",
        "independent_public_scope_review_missing",
    ])
    @test all(row -> Bool(row[:carried_into_linkage]), anchor_rows)
    @test all(row -> Bool(row[:resolved]) == false, anchor_rows)

    decision = fixture[:decision_record]
    @test String(decision[:selected_decision]) ==
        "fit_threshold_q_heldout_linkage_recorded_local_only"
    @test Bool(decision[:threshold_profiles_promoted]) == false
    @test Bool(decision[:automatic_q_revision_allowed]) == false
    @test Bool(decision[:fold1_observed_scores_used_for_public_claims]) ==
        false
    @test Bool(decision[:observed_expected_mismatches_require_followup])
    @test Bool(decision[:scalar_and_null_anchor_scores_required])
    @test Bool(decision[:full_batch_required])
    @test Bool(decision[:external_construct_validation_required])

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:local_only])
    @test Bool(summary[:pilot_only])
    @test Bool(summary[:all_input_artifacts_present])
    @test Bool(summary[:all_expected_schemas])
    @test Bool(summary[:all_input_summaries_passed])
    @test Bool(summary[:fit_metric_threshold_sensitivity_passed])
    @test Bool(summary[:empirical_q_matrix_recovery_simulation_grid_passed])
    @test Bool(summary[:heldout_prediction_simulation_grid_passed])
    @test Bool(summary[:fold1_scoring_passed])
    @test Bool(summary[:all_scenario_link_rows_recorded])
    @test Bool(summary[:threshold_profile_link_rows_recorded])
    @test Bool(summary[:q_recovery_link_rows_recorded])
    @test Bool(summary[:parameter_absorption_rows_recorded])
    @test Bool(summary[:fold1_observed_rank_recorded])
    @test Bool(summary[:observed_vs_expected_rank_match_recorded])
    @test Bool(summary[:any_observed_expected_mismatch_flagged])
    @test Bool(summary[:anchor_limitations_recorded])
    @test Bool(summary[:no_single_threshold_profile_promoted])
    @test Bool(summary[:no_automatic_q_revision])
    @test Bool(summary[:no_public_fit_metric_claim])
    @test Bool(summary[:no_public_q_revision_claim])
    @test Bool(summary[:no_public_model_weight_claim])
    @test Bool(summary[:no_sparse_superiority_claim])
    @test Int(summary[:n_input_artifacts]) == length(inputs)
    @test Int(summary[:n_scenario_link_rows]) == 5
    @test Int(summary[:n_threshold_profile_link_rows]) == 20
    @test Int(summary[:n_q_recovery_link_rows]) == 5
    @test Int(summary[:n_parameter_absorption_rows]) == 5
    @test Int(summary[:n_anchor_limitation_rows]) == 6
    @test Int(summary[:n_observed_expected_matches]) ==
        n_observed_expected_matches
    @test Int(summary[:n_observed_expected_mismatches]) ==
        n_observed_expected_mismatches
    @test Int(summary[:n_expected_models_not_scored]) ==
        n_expected_models_not_scored
    @test Int(summary[:n_threshold_unstable_rows]) == 5
    @test Int(summary[:n_q_false_candidate_links]) == 1
    @test isfinite(Float64(summary[:fold1_total_heldout_elpd]))
    @test isfinite(Float64(summary[:fold1_mean_heldout_log_predictive_density]))
    @test Int(summary[:fold1_n_blockers]) == 6
    @test String(summary[:recommendation]) ==
        "use_linkage_to_prioritize_full_batch_and_construct_validation_not_public_claims"
    @test String(summary[:next_gate]) ==
        "full_heldout_mgmfrm_mcmc_refit_full_batch_or_external_construct_dataset"
end

function check_mgmfrm_uto_style_retained_draw_budget_guidance_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_uto_style_retained_draw_budget_guidance.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) ==
        "uto_style_retained_draw_budget_guidance"
    @test String(fixture[:status]) == "local_budget_guidance_documented"
    @test Bool(fixture[:local_only])
    @test Bool(fixture[:publication_or_registration_action]) == false
    @test Bool(fixture[:package_default_change]) == false
    @test Bool(fixture[:fit_api_change]) == false
    @test Bool(fixture[:sampler_level_thinning_api]) == false
    @test Bool(fixture[:public_fit_metric_claim]) == false
    @test Bool(fixture[:public_q_revision_claim]) == false
    @test Bool(fixture[:automatic_q_revision]) == false
    @test Bool(fixture[:public_model_weight_claim]) == false
    @test Bool(fixture[:sparse_mgmfrm_superiority_claim]) == false

    policy = fixture[:guidance_policy]
    @test Int(policy[:recommended_min_chains]) == 4
    @test Int(policy[:recommended_min_warmup_per_chain]) == 128
    @test Int(policy[:recommended_min_draws_per_chain]) == 512
    @test Int(policy[:warmup_sensitivity_checked_at]) == 256
    @test Bool(policy[:thinning_primary_fix]) == false
    @test Bool(policy[:broader_scenario_replication_required_for_defaults])
    @test Bool(policy[:public_claim_allowed]) == false

    source_rows = fixture[:source_gate_rows]
    @test length(source_rows) == 4
    @test Set(String(row[:gate]) for row in source_rows) == Set([
        "rank_normalized_draws_x4",
        "retained_draw_budget_extension",
        "independent_seed_replication",
        "warmup_thinning_sensitivity",
    ])
    rank_gate = only(row for row in source_rows
        if String(row[:gate]) == "rank_normalized_draws_x4")
    @test Int(rank_gate[:warmup_per_chain]) == 128
    @test Int(rank_gate[:draws_per_chain]) == 256
    @test Int(rank_gate[:rank_warning_rows]) == 3
    @test Int(rank_gate[:geometry_warning_rows]) == 0
    extension = only(row for row in source_rows
        if String(row[:gate]) == "retained_draw_budget_extension")
    @test Int(extension[:draws_per_chain]) == 512
    @test Int(extension[:rank_warning_rows]) == 0
    @test Int(extension[:clearance_rows]) == 3
    warmup = only(row for row in source_rows
        if String(row[:gate]) == "warmup_thinning_sensitivity")
    @test Int(warmup[:warmup_per_chain]) == 256
    @test Int(warmup[:draws_per_chain]) == 512
    @test Int(warmup[:rank_warning_rows]) == 0
    @test Int(warmup[:thinning_warning_rows]) == 5

    recommendations = fixture[:recommendation_rows]
    @test length(recommendations) == 5
    @test any(row -> String(row[:recommendation]) ==
        "local_mgmfrm_diagnostic_budget" &&
        occursin("4 chains", String(row[:guidance])) &&
        occursin("512 retained draws", String(row[:guidance])) &&
        Bool(row[:public_claim_allowed]) == false,
        recommendations)
    @test any(row -> String(row[:recommendation]) == "thinning_policy" &&
        String(row[:status]) == "ready_for_documentation" &&
        occursin("5/6", String(row[:guidance])) &&
        Bool(row[:public_claim_allowed]) == false,
        recommendations)
    @test any(row -> String(row[:recommendation]) == "package_default_policy" &&
        String(row[:status]) == "blocked_for_default_change" &&
        Bool(row[:public_claim_allowed]) == false,
        recommendations)

    prompts = fixture[:prompt_rows]
    @test any(row -> String(row[:prompt]) == "can_package_defaults_change_now" &&
        String(row[:answer]) == "no" &&
        Bool(row[:public_claim_allowed]) == false,
        prompts)
    @test any(row -> String(row[:prompt]) ==
        "should_thinning_be_added_as_primary_api_fix" &&
        String(row[:answer]) == "no",
        prompts)

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Int(summary[:n_source_gates]) == 4
    @test Int(summary[:n_recommendations]) == 5
    @test Int(summary[:recommended_min_chains]) == 4
    @test Int(summary[:recommended_min_warmup_per_chain]) == 128
    @test Int(summary[:recommended_min_draws_per_chain]) == 512
    @test Int(summary[:n_rank_warnings_at_256_draws]) == 3
    @test Int(summary[:n_rank_warnings_at_512_draws]) == 0
    @test Int(summary[:n_full_rank_warnings_after_warmup_doubling]) == 0
    @test Int(summary[:n_thinning_rank_warnings]) == 5
    @test Bool(summary[:package_default_change]) == false
    @test Bool(summary[:thinning_primary_fix]) == false
    @test Bool(summary[:no_public_fit_metric_claim])
    @test Bool(summary[:no_public_q_revision_claim])
    @test Bool(summary[:no_automatic_q_revision])
    @test Bool(summary[:no_public_model_weight_claim])
    @test Bool(summary[:no_sparse_superiority_claim])
    @test String(summary[:next_gate]) ==
        "surface_budget_guidance_in_user_facing_reports"
end

function check_mgmfrm_recommended_budget_empirical_gate_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_recommended_budget_empirical_gate.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) == "recommended_budget_empirical_gate"
    @test String(fixture[:status]) ==
        "recommended_budget_empirical_gate_recorded"
    @test Bool(fixture[:local_only])
    @test Bool(fixture[:publication_or_registration_action]) == false
    @test Bool(fixture[:package_default_change]) == false
    @test Bool(fixture[:fit_api_change]) == false
    @test Bool(fixture[:public_fit_metric_claim]) == false
    @test Bool(fixture[:public_q_revision_claim]) == false
    @test Bool(fixture[:automatic_q_revision]) == false
    @test Bool(fixture[:public_model_weight_claim]) == false
    @test Bool(fixture[:sparse_mgmfrm_superiority_claim]) == false

    local_policy = fixture[:local_threshold_policy]
    @test Int(local_policy[:chains]) == 4
    @test Int(local_policy[:warmup_per_chain]) == 128
    @test Int(local_policy[:draws_per_chain]) == 512
    @test Float64(local_policy[:max_rhat]) == 1.01
    @test Float64(local_policy[:min_ess]) == 400.0
    @test Int(local_policy[:max_divergences]) == 0
    @test Int(local_policy[:max_treedepth]) == 0
    @test Float64(local_policy[:min_ebfmi]) == 0.3

    publication_policy = fixture[:publication_comparator_policy]
    @test Int(publication_policy[:chains]) == 4
    @test Int(publication_policy[:warmup_per_chain]) == 500
    @test Int(publication_policy[:draws_per_chain]) == 1000
    @test Float64(publication_policy[:max_rhat]) == 1.01

    input_artifacts = fixture[:input_artifacts]
    @test length(input_artifacts) == 19
    @test any(row -> String(row[:artifact]) ==
        "retained_draw_budget_guidance" &&
        String(row[:path]) ==
            "test/fixtures/mgmfrm_uto_style_retained_draw_budget_guidance.json",
        input_artifacts)
    @test count(row -> occursin("_recommended_result",
        String(row[:artifact])), input_artifacts) == 3
    @test count(row -> occursin("_publication_result",
        String(row[:artifact])), input_artifacts) == 3

    rows = fixture[:model_comparison_rows]
    @test length(rows) == 3
    @test Set(String(row[:model]) for row in rows) == Set([
        "confirmatory_mgmfrm_current_q",
        "construct_reviewed_revised_q_mgmfrm",
        "sparse_mgmfrm_current_q",
    ])
    @test all(row -> Int(row[:recommended_controls][:chains]) == 4 &&
            Int(row[:recommended_controls][:warmup_per_chain]) == 128 &&
            Int(row[:recommended_controls][:draws_per_chain]) == 512,
        rows)
    @test all(row -> Int(row[:publication_controls][:chains]) == 4 &&
            Int(row[:publication_controls][:warmup_per_chain]) == 500 &&
            Int(row[:publication_controls][:draws_per_chain]) == 1000,
        rows)
    @test all(row -> Bool(row[:local_control_passed]), rows)
    @test all(row -> Bool(row[:local_geometry_passed]), rows)
    @test all(row -> Bool(row[:local_ess_passed]), rows)
    @test all(row -> Bool(row[:local_finite_passed]), rows)
    @test all(row -> Bool(row[:local_ppc_passed]), rows)
    @test all(row -> Bool(row[:publication_reference_gate_passed]), rows)
    @test all(row -> Bool(row[:public_claim_allowed]) == false, rows)

    confirmatory = only(row for row in rows
        if String(row[:model]) == "confirmatory_mgmfrm_current_q")
    @test Bool(confirmatory[:local_gate_passed])
    @test Bool(confirmatory[:local_rank_passed])
    @test Float64(confirmatory[:recommended_metrics][:max_rhat]) < 1.01
    @test Float64(confirmatory[:recommended_metrics][:heldout_elpd]) ≈
        -11.680301348336437 atol = 1e-10

    construct = only(row for row in rows
        if String(row[:model]) == "construct_reviewed_revised_q_mgmfrm")
    @test Bool(construct[:local_gate_passed]) == false
    @test Bool(construct[:local_rank_passed]) == false
    @test Float64(construct[:recommended_metrics][:max_rhat]) > 1.01
    @test Float64(construct[:recommended_metrics][:max_rhat]) < 1.011
    @test Float64(construct[:deltas][:heldout_elpd]) ≈
        -0.09757312491638537 atol = 1e-10

    sparse = only(row for row in rows
        if String(row[:model]) == "sparse_mgmfrm_current_q")
    @test Bool(sparse[:local_gate_passed])
    @test Bool(sparse[:local_rank_passed])
    @test Float64(sparse[:recommended_metrics][:max_rhat]) < 1.01

    failures = fixture[:recommended_publication_gate_failure_rows]
    @test length(failures) == 7
    @test count(row -> String(row[:failure_class]) ==
        "publication_grade_budget_threshold_not_targeted", failures) == 6
    @test count(row -> String(row[:failure_class]) ==
        "sampler_or_rank_warning", failures) == 1
    rank_failure = only(row for row in failures
        if String(row[:failure_class]) == "sampler_or_rank_warning")
    @test String(rank_failure[:model]) ==
        "construct_reviewed_revised_q_mgmfrm"
    @test String(rank_failure[:diagnostic]) == "rank_normalized_rhat_max"
    @test Float64(rank_failure[:value]) > 1.01
    @test Float64(rank_failure[:threshold]) == 1.01

    findings = fixture[:finding_rows]
    @test length(findings) == 5
    @test any(row -> String(row[:finding]) ==
        "recommended_budget_empirical_gate_partially_passed" &&
        String(row[:severity]) == "warning" &&
        occursin("2/3", String(row[:evidence])),
        findings)
    @test any(row -> String(row[:finding]) ==
        "publication_grade_budget_thresholds_not_targeted" &&
        String(row[:severity]) == "blocker",
        findings)
    @test any(row -> String(row[:finding]) ==
        "borderline_rank_warning_detected" &&
        String(row[:severity]) == "warning",
        findings)

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:empirical_gate_passed]) == false
    @test Int(summary[:n_models]) == 3
    @test Int(summary[:n_recommended_budget_runs]) == 3
    @test Int(summary[:n_local_gate_passed]) == 2
    @test Int(summary[:n_publication_reference_gate_passed]) == 3
    @test Int(summary[:n_local_geometry_passed]) == 3
    @test Int(summary[:n_recommended_publication_gate_failures]) == 7
    @test Int(summary[:n_publication_budget_threshold_failures]) == 6
    @test Int(summary[:n_sampler_or_rank_failures]) == 1
    @test Float64(summary[:max_abs_heldout_elpd_delta_vs_publication]) ≈
        0.10987342163689284 atol = 1e-10
    @test Float64(summary[
        :max_abs_heldout_expected_score_mae_delta_vs_publication]) ≈
        0.003981681516425306 atol = 1e-12
    @test Bool(summary[:no_public_fit_metric_claim])
    @test Bool(summary[:no_public_q_revision_claim])
    @test Bool(summary[:no_automatic_q_revision])
    @test Bool(summary[:no_public_model_weight_claim])
    @test Bool(summary[:no_sparse_superiority_claim])
    @test String(summary[:recommendation]) ==
        "target_construct_reviewed_revised_q_rank_warning_before_broadening"
    @test String(summary[:next_gate]) ==
        "construct_reviewed_revised_q_extended_budget_followup"
end

function check_mgmfrm_construct_reviewed_revised_q_extended_budget_followup_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_construct_reviewed_revised_q_extended_budget_followup.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) ==
        "construct_reviewed_revised_q_extended_budget_followup"
    @test String(fixture[:status]) ==
        "construct_reviewed_revised_q_extended_budget_followup_recorded"
    @test Bool(fixture[:local_only])
    @test Bool(fixture[:publication_or_registration_action]) == false
    @test Bool(fixture[:package_default_change]) == false
    @test Bool(fixture[:fit_api_change]) == false
    @test Bool(fixture[:public_fit_metric_claim]) == false
    @test Bool(fixture[:public_q_revision_claim]) == false
    @test Bool(fixture[:automatic_q_revision]) == false
    @test Bool(fixture[:public_model_weight_claim]) == false
    @test Bool(fixture[:sparse_mgmfrm_superiority_claim]) == false
    @test String(fixture[:model]) == "construct_reviewed_revised_q_mgmfrm"
    @test String(fixture[:execution_unit_id]) ==
        "well_specified_current_q__construct_reviewed_revised_q_mgmfrm__fold1"

    policy = fixture[:local_threshold_policy]
    @test Int(policy[:chains]) == 4
    @test Int(policy[:warmup_per_chain]) == 128
    @test Int(policy[:draws_per_chain]) == 512
    @test Float64(policy[:max_rhat]) == 1.01
    @test Float64(policy[:min_ess]) == 400.0
    @test Int(policy[:max_divergences]) == 0
    @test Int(policy[:max_treedepth]) == 0
    @test Float64(policy[:min_ebfmi]) == 0.3

    input_artifacts = fixture[:input_artifacts]
    @test length(input_artifacts) == 19
    @test any(row -> String(row[:artifact]) ==
        "recommended_budget_empirical_gate" &&
        String(row[:path]) ==
            "test/fixtures/mgmfrm_recommended_budget_empirical_gate.json",
        input_artifacts)
    @test count(row -> endswith(String(row[:artifact]), "_result"),
        input_artifacts) == 6
    @test count(row -> endswith(String(row[:artifact]), "_diagnostics"),
        input_artifacts) == 6
    @test count(row -> endswith(String(row[:artifact]), "_heldout"),
        input_artifacts) == 6

    rows = fixture[:profile_rows]
    @test length(rows) == 6
    @test Set(String(row[:profile]) for row in rows) == Set([
        "recommended_4_128_512_ta080",
        "draws_only_4_128_1000_ta080",
        "warmup_only_4_256_512_ta080",
        "warmup_draws_4_256_1000_ta080",
        "warmup_draws_4_256_1000_ta090",
        "publication_4_500_1000_ta080",
    ])
    @test all(row -> String(row[:model]) ==
        "construct_reviewed_revised_q_mgmfrm", rows)
    @test all(row -> Bool(row[:local_control_passed]), rows)
    @test all(row -> Bool(row[:local_geometry_passed]), rows)
    @test all(row -> Bool(row[:local_ess_passed]), rows)
    @test all(row -> Bool(row[:local_finite_passed]), rows)
    @test all(row -> Bool(row[:local_ppc_passed]), rows)
    @test all(row -> Bool(row[:public_claim_allowed]) == false, rows)

    baseline = only(row for row in rows
        if String(row[:profile]) == "recommended_4_128_512_ta080")
    @test Bool(baseline[:local_gate_passed]) == false
    @test Bool(baseline[:local_rank_passed]) == false
    @test String(baseline[:diagnostic_flag]) == "mcmc_warning"
    @test Float64(baseline[:metrics][:max_rhat]) ≈
        1.0108927615632282 atol = 1e-12

    draws_only = only(row for row in rows
        if String(row[:profile]) == "draws_only_4_128_1000_ta080")
    @test Bool(draws_only[:local_gate_passed])
    @test Bool(draws_only[:local_rank_passed])
    @test Int(draws_only[:controls][:warmup_per_chain]) == 128
    @test Int(draws_only[:controls][:draws_per_chain]) == 1000
    @test Float64(draws_only[:metrics][:max_rhat]) ≈
        1.003008359484065 atol = 1e-12
    @test Float64(draws_only[:metrics][:min_ess]) >
        Float64(baseline[:metrics][:min_ess])

    warmup_only = only(row for row in rows
        if String(row[:profile]) == "warmup_only_4_256_512_ta080")
    @test Bool(warmup_only[:local_gate_passed])
    @test Bool(warmup_only[:local_rank_passed])
    @test Int(warmup_only[:controls][:warmup_per_chain]) == 256
    @test Int(warmup_only[:controls][:draws_per_chain]) == 512
    @test Float64(warmup_only[:metrics][:max_rhat]) ≈
        1.0051275094304761 atol = 1e-12

    warmup_draws = only(row for row in rows
        if String(row[:profile]) == "warmup_draws_4_256_1000_ta080")
    @test Bool(warmup_draws[:local_gate_passed])
    @test Float64(warmup_draws[:controls][:target_acceptance]) == 0.8
    @test Float64(warmup_draws[:metrics][:max_rhat]) ≈
        1.002046203833123 atol = 1e-12

    target_accept = only(row for row in rows
        if String(row[:profile]) == "warmup_draws_4_256_1000_ta090")
    @test Bool(target_accept[:local_gate_passed])
    @test Float64(target_accept[:controls][:target_acceptance]) == 0.9
    @test Float64(target_accept[:metrics][:heldout_elpd]) ≈
        -11.69225866610247 atol = 1e-10

    publication = only(row for row in rows
        if String(row[:profile]) == "publication_4_500_1000_ta080")
    @test Bool(publication[:local_gate_passed])
    @test Bool(publication[:publication_gate_passed])
    @test Int(publication[:controls][:warmup_per_chain]) == 500
    @test Int(publication[:controls][:draws_per_chain]) == 1000
    @test Float64(publication[:metrics][:max_rhat]) ≈
        1.0017699327380145 atol = 1e-12

    failures = fixture[:publication_gate_failure_rows]
    @test length(failures) == 8
    @test count(row -> String(row[:failure_class]) ==
        "publication_grade_budget_threshold_not_targeted", failures) == 7
    @test count(row -> String(row[:failure_class]) ==
        "sampler_or_rank_warning", failures) == 1
    rank_failure = only(row for row in failures
        if String(row[:failure_class]) == "sampler_or_rank_warning")
    @test String(rank_failure[:profile]) == "recommended_4_128_512_ta080"
    @test String(rank_failure[:diagnostic]) == "rank_normalized_rhat_max"
    @test Float64(rank_failure[:value]) ≈
        1.0108927615632282 atol = 1e-12

    findings = fixture[:finding_rows]
    @test length(findings) == 6
    @test any(row -> String(row[:finding]) ==
        "retained_draw_extension_cleared_warning" &&
        String(row[:severity]) == "info" &&
        occursin("4/128/1000", String(row[:evidence])),
        findings)
    @test any(row -> String(row[:finding]) ==
        "warmup_extension_also_cleared_warning" &&
        String(row[:severity]) == "info" &&
        occursin("4/256/512", String(row[:evidence])),
        findings)
    @test any(row -> String(row[:finding]) ==
        "target_acceptance_not_required_for_clearance" &&
        occursin("0.8 and 0.9", String(row[:evidence])),
        findings)
    @test any(row -> String(row[:finding]) == "public_claims_remain_blocked" &&
        String(row[:severity]) == "blocker",
        findings)

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:baseline_recommended_budget_passed]) == false
    @test Bool(summary[:baseline_rank_passed]) == false
    @test Float64(summary[:baseline_max_rhat]) ≈
        1.0108927615632282 atol = 1e-12
    @test Int(summary[:n_followup_profiles]) == 4
    @test Int(summary[:n_followup_profiles_passed]) == 4
    @test Bool(summary[:all_followup_profiles_passed])
    @test Bool(summary[:draws_only_cleared])
    @test Bool(summary[:warmup_only_cleared])
    @test Bool(summary[:warmup_draws_cleared])
    @test Bool(summary[:target_acceptance_0p9_cleared])
    @test Bool(summary[:target_acceptance_0p9_required]) == false
    @test Bool(summary[:retained_draw_extension_sufficient])
    @test Bool(summary[:warmup_extension_also_sufficient])
    @test Bool(summary[:publication_comparator_passed])
    @test Int(summary[:n_profiles]) == 6
    @test Int(summary[:n_local_gate_passed]) == 5
    @test Int(summary[:n_geometry_passed]) == 6
    @test Int(summary[:n_publication_gate_failures]) == 8
    @test Int(summary[:n_publication_budget_threshold_failures]) == 7
    @test Int(summary[:n_sampler_or_rank_failures]) == 1
    @test String(summary[:best_rhat_profile]) ==
        "publication_4_500_1000_ta080"
    @test Float64(summary[:best_rhat]) ≈
        1.0017699327380145 atol = 1e-12
    @test String(summary[:best_heldout_elpd_profile]) ==
        "warmup_draws_4_256_1000_ta090"
    @test Float64(summary[:best_heldout_elpd]) ≈
        -11.69225866610247 atol = 1e-10
    @test Float64(summary[:max_abs_heldout_elpd_delta_vs_publication]) ≈
        0.10530375193166996 atol = 1e-10
    @test Bool(summary[:no_public_fit_metric_claim])
    @test Bool(summary[:no_public_q_revision_claim])
    @test Bool(summary[:no_automatic_q_revision])
    @test Bool(summary[:no_public_model_weight_claim])
    @test Bool(summary[:no_sparse_mgmfrm_superiority_claim])
    @test String(summary[:recommendation]) ==
        "use_retained_draw_extension_for_construct_reviewed_revised_q_replication"
    @test String(summary[:next_gate]) ==
        "construct_reviewed_revised_q_1000_draw_scenario_replication"
end

function check_mgmfrm_construct_reviewed_revised_q_1000_draw_scenario_replication_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_construct_reviewed_revised_q_1000_draw_scenario_replication.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) ==
        "construct_reviewed_revised_q_1000_draw_scenario_replication"
    @test String(fixture[:status]) ==
        "construct_reviewed_revised_q_1000_draw_scenario_replication_recorded"
    @test Bool(fixture[:local_only])
    @test Bool(fixture[:publication_or_registration_action]) == false
    @test Bool(fixture[:package_default_change]) == false
    @test Bool(fixture[:fit_api_change]) == false
    @test Bool(fixture[:public_fit_metric_claim]) == false
    @test Bool(fixture[:public_q_revision_claim]) == false
    @test Bool(fixture[:automatic_q_revision]) == false
    @test Bool(fixture[:public_model_weight_claim]) == false
    @test Bool(fixture[:sparse_mgmfrm_superiority_claim]) == false
    @test String(fixture[:model]) == "construct_reviewed_revised_q_mgmfrm"

    policy = fixture[:local_threshold_policy]
    @test Int(policy[:chains]) == 4
    @test Int(policy[:warmup_per_chain]) == 128
    @test Int(policy[:draws_per_chain]) == 1000
    @test Float64(policy[:max_rhat]) == 1.01
    @test Float64(policy[:min_ess]) == 400.0
    @test Int(policy[:max_divergences]) == 0
    @test Int(policy[:max_treedepth]) == 0
    @test Float64(policy[:min_ebfmi]) == 0.3

    input_artifacts = fixture[:input_artifacts]
    @test length(input_artifacts) == 25
    @test any(row -> String(row[:artifact]) ==
        "previous_extended_budget_followup_fixture" &&
        String(row[:path]) ==
            "test/fixtures/mgmfrm_construct_reviewed_revised_q_extended_budget_followup.json",
        input_artifacts)
    @test count(row -> endswith(String(row[:artifact]), "_result"),
        input_artifacts) == 8
    @test count(row -> endswith(String(row[:artifact]), "_diagnostics"),
        input_artifacts) == 8
    @test count(row -> endswith(String(row[:artifact]), "_heldout"),
        input_artifacts) == 8

    rows = fixture[:profile_rows]
    @test length(rows) == 8
    @test Set(String(row[:profile]) for row in rows) == Set([
        "well_specified_fold1_4_128_1000_ta080",
        "well_specified_fold2_4_128_1000_ta080",
        "well_specified_fold2_4_128_1000_ta090",
        "well_specified_fold2_4_256_1000_ta080",
        "well_specified_fold2_4_256_1000_ta090",
        "well_specified_fold3_4_128_1000_ta080",
        "missing_loading_fold1_4_128_1000_ta080",
        "missing_loading_fold1_4_500_1000_ta080",
    ])
    @test all(row -> String(row[:model]) ==
        "construct_reviewed_revised_q_mgmfrm", rows)
    @test all(row -> Bool(row[:local_rank_passed]), rows)
    @test all(row -> Bool(row[:local_ess_passed]), rows)
    @test all(row -> Bool(row[:local_finite_passed]), rows)
    @test all(row -> Bool(row[:local_ppc_passed]), rows)
    @test all(row -> Bool(row[:public_claim_allowed]) == false, rows)
    @test count(row -> Bool(row[:local_gate_passed]), rows) == 7
    @test count(row -> Bool(row[:local_geometry_passed]), rows) == 7

    fold2_default = only(row for row in rows
        if String(row[:profile]) == "well_specified_fold2_4_128_1000_ta080")
    @test Bool(fold2_default[:local_gate_passed]) == false
    @test Bool(fold2_default[:local_rank_passed])
    @test Bool(fold2_default[:local_geometry_passed]) == false
    @test String(fold2_default[:diagnostic_flag]) == "sampler_warning"
    @test Float64(fold2_default[:metrics][:max_rhat]) ≈
        1.0034817809997079 atol = 1e-12
    @test Float64(fold2_default[:metrics][:min_ess]) ≈
        2496.3162502948094 atol = 1e-9
    @test Int(fold2_default[:metrics][:n_divergences]) == 1

    fold2_target_accept = only(row for row in rows
        if String(row[:profile]) == "well_specified_fold2_4_128_1000_ta090")
    @test Bool(fold2_target_accept[:local_gate_passed])
    @test Int(fold2_target_accept[:controls][:warmup_per_chain]) == 128
    @test Int(fold2_target_accept[:controls][:draws_per_chain]) == 1000
    @test Float64(fold2_target_accept[:controls][:target_acceptance]) == 0.9
    @test Int(fold2_target_accept[:metrics][:n_divergences]) == 0
    @test Float64(fold2_target_accept[:metrics][:max_rhat]) ≈
        1.0033941138892781 atol = 1e-12

    fold2_warmup = only(row for row in rows
        if String(row[:profile]) == "well_specified_fold2_4_256_1000_ta080")
    @test Bool(fold2_warmup[:local_gate_passed])
    @test Int(fold2_warmup[:controls][:warmup_per_chain]) == 256
    @test Float64(fold2_warmup[:controls][:target_acceptance]) == 0.8
    @test Int(fold2_warmup[:metrics][:n_divergences]) == 0
    @test Float64(fold2_warmup[:metrics][:max_rhat]) ≈
        1.0013516979545556 atol = 1e-12

    missing_light = only(row for row in rows
        if String(row[:profile]) == "missing_loading_fold1_4_128_1000_ta080")
    missing_heavy = only(row for row in rows
        if String(row[:profile]) == "missing_loading_fold1_4_500_1000_ta080")
    @test Bool(missing_light[:local_gate_passed])
    @test Bool(missing_heavy[:local_gate_passed])
    @test Bool(missing_heavy[:publication_gate_passed])
    @test Float64(missing_light[:metrics][:heldout_elpd]) ≈
        -13.90650417151769 atol = 1e-10
    @test Float64(missing_heavy[:metrics][:heldout_elpd]) ≈
        -13.890467429280312 atol = 1e-10

    failures = fixture[:publication_gate_failure_rows]
    @test length(failures) == 8
    @test count(row -> String(row[:failure_class]) ==
        "publication_grade_budget_threshold_not_targeted", failures) == 7
    @test count(row -> String(row[:failure_class]) ==
        "sampler_or_geometry_warning", failures) == 1
    divergence_failure = only(row for row in failures
        if String(row[:failure_class]) == "sampler_or_geometry_warning")
    @test String(divergence_failure[:profile]) ==
        "well_specified_fold2_4_128_1000_ta080"
    @test String(divergence_failure[:diagnostic]) == "divergence_count_max"
    @test Int(divergence_failure[:value]) == 1

    findings = fixture[:finding_rows]
    @test length(findings) == 6
    @test any(row -> String(row[:finding]) ==
        "default_1000_draw_profiles_clear_rank" &&
        String(row[:severity]) == "info" &&
        occursin("4/4", String(row[:evidence])),
        findings)
    @test any(row -> String(row[:finding]) ==
        "default_profile_geometry_failure_observed" &&
        String(row[:severity]) == "warning" &&
        occursin("fold2 divergences = 1", String(row[:evidence])),
        findings)
    @test any(row -> String(row[:finding]) ==
        "target_acceptance_cleared_fold2_geometry" &&
        String(row[:severity]) == "info",
        findings)
    @test any(row -> String(row[:finding]) ==
        "public_claims_remain_blocked" &&
        String(row[:severity]) == "blocker",
        findings)

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Int(summary[:n_profiles]) == 8
    @test Int(summary[:n_default_4_128_1000_profiles]) == 4
    @test Int(summary[:n_default_4_128_1000_local_passed]) == 3
    @test Int(summary[:n_default_4_128_1000_rank_passed]) == 4
    @test Int(summary[:n_default_4_128_1000_geometry_passed]) == 3
    @test Bool(summary[:default_4_128_1000_rank_replicated])
    @test Bool(summary[:default_4_128_1000_geometry_clean]) == false
    @test Int(summary[:n_remedial_fold2_profiles]) == 3
    @test Int(summary[:n_remedial_fold2_profiles_passed]) == 3
    @test Bool(summary[:target_acceptance_0p9_cleared_fold2_geometry])
    @test Bool(summary[:warmup_256_cleared_fold2_geometry])
    @test Int(summary[:n_local_gate_passed]) == 7
    @test Int(summary[:n_rank_passed]) == 8
    @test Int(summary[:n_geometry_passed]) == 7
    @test Int(summary[:n_publication_gate_passed]) == 1
    @test Int(summary[:n_publication_gate_failures]) == 8
    @test Int(summary[:n_publication_budget_threshold_failures]) == 7
    @test Int(summary[:n_sampler_or_geometry_failures]) == 1
    @test Float64(summary[:max_rhat]) ≈
        1.0034817809997079 atol = 1e-12
    @test Float64(summary[:min_ess]) ≈
        1549.514017564035 atol = 1e-9
    @test Int(summary[:total_divergences]) == 1
    @test Float64(summary[
        :missing_loading_light_vs_heavy_heldout_elpd_delta]) ≈
        -0.01603674223737883 atol = 1e-12
    @test Float64(summary[:missing_loading_light_vs_heavy_mae_delta]) ≈
        0.0028393560509898386 atol = 1e-12
    @test String(summary[:best_rhat_profile]) ==
        "well_specified_fold2_4_256_1000_ta080"
    @test Float64(summary[:best_rhat]) ≈
        1.0013516979545556 atol = 1e-12
    @test String(summary[:best_heldout_elpd_profile]) ==
        "well_specified_fold1_4_128_1000_ta080"
    @test Float64(summary[:best_heldout_elpd]) ≈
        -11.774989736873781 atol = 1e-10
    @test Bool(summary[:no_public_fit_metric_claim])
    @test Bool(summary[:no_public_q_revision_claim])
    @test Bool(summary[:no_automatic_q_revision])
    @test Bool(summary[:no_public_model_weight_claim])
    @test Bool(summary[:no_sparse_mgmfrm_superiority_claim])
    @test String(summary[:recommendation]) ==
        "retain_1000_draw_rank_guidance_but_add_geometry_remediation_branch"
    @test String(summary[:next_gate]) ==
        "expand_1000_draw_geometry_branch_across_remaining_construct_reviewed_revised_q_cells"
end

function check_mgmfrm_construct_reviewed_revised_q_1000_draw_geometry_branch_expansion_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_construct_reviewed_revised_q_1000_draw_geometry_branch_expansion.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) ==
        "construct_reviewed_revised_q_1000_draw_geometry_branch_expansion"
    @test String(fixture[:status]) ==
        "construct_reviewed_revised_q_1000_draw_geometry_branch_expansion_recorded"
    @test Bool(fixture[:local_only])
    @test Bool(fixture[:publication_or_registration_action]) == false
    @test Bool(fixture[:package_default_change]) == false
    @test Bool(fixture[:fit_api_change]) == false
    @test Bool(fixture[:public_fit_metric_claim]) == false
    @test Bool(fixture[:public_q_revision_claim]) == false
    @test Bool(fixture[:automatic_q_revision]) == false
    @test Bool(fixture[:public_model_weight_claim]) == false
    @test Bool(fixture[:sparse_mgmfrm_superiority_claim]) == false
    @test String(fixture[:model]) == "construct_reviewed_revised_q_mgmfrm"

    policy = fixture[:local_threshold_policy]
    @test Int(policy[:chains]) == 4
    @test Int(policy[:warmup_per_chain]) == 128
    @test Int(policy[:draws_per_chain]) == 1000
    @test Float64(policy[:max_rhat]) == 1.01
    @test Float64(policy[:min_ess]) == 400.0
    @test Int(policy[:max_divergences]) == 0
    @test Int(policy[:max_treedepth]) == 0
    @test Float64(policy[:min_ebfmi]) == 0.3

    input_artifacts = fixture[:input_artifacts]
    @test length(input_artifacts) == 109
    @test any(row -> String(row[:artifact]) ==
        "previous_1000_draw_scenario_replication_fixture" &&
        String(row[:path]) ==
            "test/fixtures/mgmfrm_construct_reviewed_revised_q_1000_draw_scenario_replication.json",
        input_artifacts)

    rows = fixture[:default_profile_rows]
    @test length(rows) == 25
    @test Set(String(row[:scenario]) for row in rows) == Set([
        "missing_loading_revised_q",
        "rater_method_noise",
        "sparse_signal_current_q",
        "weak_dimension_ambiguous",
        "well_specified_current_q",
    ])
    @test all(row -> String(row[:model]) ==
        "construct_reviewed_revised_q_mgmfrm", rows)
    @test all(row -> Int(row[:controls][:chains]) == 4, rows)
    @test all(row -> Int(row[:controls][:warmup_per_chain]) == 128, rows)
    @test all(row -> Int(row[:controls][:draws_per_chain]) == 1000, rows)
    @test all(row -> Float64(row[:controls][:target_acceptance]) == 0.8, rows)
    @test all(row -> Bool(row[:local_rank_passed]), rows)
    @test all(row -> Bool(row[:local_ess_passed]), rows)
    @test all(row -> Bool(row[:local_finite_passed]), rows)
    @test all(row -> Bool(row[:local_ppc_passed]), rows)
    @test all(row -> Bool(row[:public_claim_allowed]) == false, rows)
    @test count(row -> Bool(row[:local_gate_passed]), rows) == 23
    @test count(row -> Bool(row[:local_geometry_passed]), rows) == 23

    geometry_failures = fixture[:default_geometry_failure_rows]
    @test length(geometry_failures) == 2
    @test Set(String(row[:execution_unit_id]) for row in geometry_failures) ==
        Set([
            "well_specified_current_q__construct_reviewed_revised_q_mgmfrm__fold2",
            "well_specified_current_q__construct_reviewed_revised_q_mgmfrm__fold4",
        ])
    @test all(row -> String(row[:scenario]) == "well_specified_current_q",
        geometry_failures)
    @test all(row -> Bool(row[:local_rank_passed]), geometry_failures)
    @test all(row -> Bool(row[:local_geometry_passed]) == false,
        geometry_failures)
    @test all(row -> Int(row[:metrics][:n_divergences]) == 1,
        geometry_failures)
    fold2_failure = only(row for row in geometry_failures
        if Int(row[:fold]) == 2)
    @test Float64(fold2_failure[:metrics][:max_rhat]) ≈
        1.0034817809997079 atol = 1e-12
    fold4_failure = only(row for row in geometry_failures
        if Int(row[:fold]) == 4)
    @test Float64(fold4_failure[:metrics][:max_rhat]) ≈
        1.002306871488902 atol = 1e-12

    remediation = fixture[:remediation_rows]
    @test length(remediation) == 6
    @test all(row -> String(row[:scenario]) == "well_specified_current_q",
        remediation)
    @test Set(Int(row[:fold]) for row in remediation) == Set([2, 4])
    @test count(row -> Int(row[:fold]) == 2, remediation) == 3
    @test count(row -> Int(row[:fold]) == 4, remediation) == 3
    @test all(row -> Bool(row[:local_gate_passed]), remediation)
    @test all(row -> Bool(row[:local_geometry_passed]), remediation)
    @test all(row -> Int(row[:metrics][:n_divergences]) == 0, remediation)
    @test count(row -> String(row[:role]) ==
        "target_acceptance_geometry_remediation", remediation) == 2
    @test count(row -> String(row[:role]) ==
        "warmup_geometry_remediation", remediation) == 2
    @test count(row -> String(row[:role]) ==
        "combined_geometry_remediation", remediation) == 2

    comparators = fixture[:missing_loading_publication_comparator_rows]
    @test length(comparators) == 5
    @test all(row -> String(row[:scenario]) == "missing_loading_revised_q",
        comparators)
    @test all(row -> Bool(row[:light_local_gate_passed]), comparators)
    @test all(row -> Bool(row[:heavy_local_gate_passed]), comparators)
    @test all(row -> Bool(row[:heavy_publication_gate_passed]), comparators)
    @test maximum(abs(Float64(row[:heldout_elpd_delta]))
        for row in comparators) ≈ 0.303148708829017 atol = 1e-12
    @test maximum(abs(Float64(row[:heldout_expected_score_mae_delta]))
        for row in comparators) ≈ 0.006586446310166805 atol = 1e-12

    scenario_rows = fixture[:scenario_summary_rows]
    @test length(scenario_rows) == 5
    well_specified = only(row for row in scenario_rows
        if String(row[:scenario]) == "well_specified_current_q")
    @test Int(well_specified[:n_default_profiles]) == 5
    @test Int(well_specified[:n_default_local_gate_passed]) == 3
    @test Int(well_specified[:n_default_rank_passed]) == 5
    @test Int(well_specified[:n_default_geometry_passed]) == 3
    @test Int(well_specified[:total_divergences]) == 2
    @test all(row -> String(row[:scenario]) == "well_specified_current_q" ||
        (Int(row[:n_default_local_gate_passed]) == 5 &&
         Int(row[:n_default_geometry_passed]) == 5 &&
         Int(row[:total_divergences]) == 0),
        scenario_rows)

    findings = fixture[:finding_rows]
    @test length(findings) == 5
    @test any(row -> String(row[:finding]) ==
        "full_default_1000_draw_rank_replicated" &&
        String(row[:severity]) == "info" &&
        occursin("25/25", String(row[:evidence])),
        findings)
    @test any(row -> String(row[:finding]) ==
        "default_geometry_failures_localized" &&
        String(row[:severity]) == "warning" &&
        occursin("2 default geometry failures", String(row[:evidence])),
        findings)
    @test any(row -> String(row[:finding]) ==
        "geometry_remediation_branch_cleared_failures" &&
        String(row[:severity]) == "info" &&
        occursin("6/6", String(row[:evidence])),
        findings)
    @test any(row -> String(row[:finding]) ==
        "public_claims_remain_blocked" &&
        String(row[:severity]) == "blocker",
        findings)

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Int(summary[:n_default_profiles]) == 25
    @test Int(summary[:n_default_local_gate_passed]) == 23
    @test Int(summary[:n_default_rank_passed]) == 25
    @test Int(summary[:n_default_ess_passed]) == 25
    @test Int(summary[:n_default_geometry_passed]) == 23
    @test Bool(summary[:default_1000_draw_rank_replicated])
    @test Bool(summary[:default_1000_draw_geometry_clean]) == false
    @test Int(summary[:n_default_local_failures]) == 2
    @test Int(summary[:n_default_geometry_failure_cells]) == 2
    @test Bool(summary[:all_default_geometry_failures_in_well_specified_current_q])
    @test Float64(summary[:max_default_rhat]) ≈
        1.0091157507458468 atol = 1e-12
    @test Float64(summary[:min_default_ess]) ≈
        605.1565245673509 atol = 1e-9
    @test Float64(summary[:min_default_ebfmi]) ≈
        0.8281855851576145 atol = 1e-12
    @test Int(summary[:total_default_divergences]) == 2
    @test Int(summary[:n_remediation_profiles]) == 6
    @test Int(summary[:n_remediation_profiles_passed]) == 6
    @test Bool(summary[:all_remediation_profiles_passed])
    @test Bool(summary[:target_acceptance_0p9_cleared_all_geometry_failures])
    @test Bool(summary[:warmup_256_cleared_all_geometry_failures])
    @test Bool(summary[:combined_256_0p9_cleared_all_geometry_failures])
    @test Int(summary[:n_missing_loading_publication_comparisons]) == 5
    @test Float64(summary[
        :max_abs_missing_loading_light_vs_heavy_heldout_elpd_delta]) ≈
        0.303148708829017 atol = 1e-12
    @test Float64(summary[
        :mean_missing_loading_light_vs_heavy_heldout_elpd_delta]) ≈
        -0.0016608810196526492 atol = 1e-12
    @test Float64(summary[
        :max_abs_missing_loading_light_vs_heavy_mae_delta]) ≈
        0.006586446310166805 atol = 1e-12
    @test Bool(summary[:no_public_fit_metric_claim])
    @test Bool(summary[:no_public_q_revision_claim])
    @test Bool(summary[:no_automatic_q_revision])
    @test Bool(summary[:no_public_model_weight_claim])
    @test Bool(summary[:no_sparse_mgmfrm_superiority_claim])
    @test String(summary[:recommendation]) ==
        "retain_1000_draw_rank_guidance_with_geometry_remediation_branch"
    @test String(summary[:next_gate]) ==
        "join_construct_reviewed_revised_q_budget_diagnostics_to_model_comparison_and_calibration"
end
