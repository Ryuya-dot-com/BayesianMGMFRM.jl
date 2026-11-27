function check_mgmfrm_heldout_prediction_validation_policy_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_heldout_prediction_validation_policy.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) == "heldout_prediction_validation_policy"
    @test String(fixture[:status]) ==
        "heldout_prediction_validation_policy_recorded"
    @test String(fixture[:decision]) ==
        "require_heldout_or_external_validation_before_fit_or_q_claims"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])
    @test Bool(fixture[:local_only])
    @test Bool(fixture[:public_fit_metric_claim]) == false
    @test Bool(fixture[:public_q_revision_claim]) == false
    @test Bool(fixture[:public_model_weight_claim]) == false
    @test Bool(fixture[:sparse_mgmfrm_superiority_claim]) == false
    @test Bool(fixture[:automatic_q_revision]) == false
    @test Bool(fixture[:publication_or_registration_action]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) ==
        "mgmfrm_heldout_prediction_validation_policy_v1"
    @test String(protocol[:review_kind]) ==
        "local_heldout_prediction_or_external_validation_policy"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test Bool(protocol[:local_only])
    @test String(protocol[:policy_scope]) ==
        "claim_gate_after_construct_reviewed_q_fit_reporting_policy"
    @test String(protocol[:decision_target]) ==
        "heldout_prediction_or_external_validation_before_claims"
    @test Bool(thresholds[
        :require_construct_reviewed_q_fit_reporting_policy_passed])
    @test Bool(thresholds[
        :require_prediction_target_and_model_weight_policy_passed])
    @test Bool(thresholds[
        :require_q_revision_cross_validation_policy_passed])
    @test Bool(thresholds[:require_reporting_policy_next_gate_matched])
    @test Bool(thresholds[:require_heldout_kfold_target_selected])
    @test Bool(thresholds[:require_same_data_waic_blocked_for_claims])
    @test Bool(thresholds[:require_raw_psis_loo_blocked_for_claims])
    @test Bool(thresholds[
        :require_external_construct_validation_before_q_claims])
    @test Bool(thresholds[:require_no_single_threshold_profile_promoted])
    @test Bool(thresholds[:require_no_public_fit_metric_claim])
    @test Bool(thresholds[:require_no_public_q_revision_claim])
    @test Bool(thresholds[
        :require_no_model_weight_or_sparse_superiority_claim])
    @test Bool(thresholds[:require_no_automatic_q_revision])

    inputs = fixture[:input_artifacts]
    expected_paths = Dict(
        "mgmfrm_construct_reviewed_q_fit_reporting_policy" =>
            "test/fixtures/mgmfrm_construct_reviewed_q_fit_reporting_policy.json",
        "prediction_target_and_model_weight_policy" =>
            "test/fixtures/gmfrm_prediction_target_and_model_weight_policy.json",
        "mgmfrm_q_revision_cross_validation_policy" =>
            "test/fixtures/mgmfrm_q_revision_cross_validation_policy.json",
    )
    @test length(inputs) == length(expected_paths)
    @test Set(String(row[:artifact]) for row in inputs) == Set(keys(expected_paths))
    for row in inputs
        artifact = String(row[:artifact])
        @test expected_paths[artifact] == String(row[:path])
        @test Bool(row[:exists])
        @test Bool(row[:schema_matches])
        @test Bool(row[:summary_passed])
        check_generated_fixture_reference(
            root,
            String(row[:path]),
            String(row[:sha256]),
        )
    end

    targets = fixture[:validation_target_rows]
    @test length(targets) == 6
    @test Set(String(row[:target]) for row in targets) == Set([
        "heldout_kfold_log_score",
        "external_construct_validation",
        "same_data_waic_or_loo",
        "threshold_profile_pass_fail",
        "posterior_predictive_calibration",
        "common_parameter_shift",
    ])
    @test all(row -> Bool(row[:requirement_recorded]), targets)
    @test all(row -> Bool(row[:public_claim_allowed]) == false, targets)
    @test any(row -> String(row[:target]) == "heldout_kfold_log_score" &&
        Bool(row[:selected_by_existing_policy]) &&
        Bool(row[:evidence_available_for_public_mgmfrm_claim]) == false,
        targets)
    @test any(row -> String(row[:target]) == "external_construct_validation" &&
        Bool(row[:selected_by_existing_policy]) &&
        Bool(row[:evidence_available_for_public_mgmfrm_claim]) == false,
        targets)

    claim_gates = fixture[:claim_gate_rows]
    @test length(claim_gates) == 5
    @test all(row -> Bool(row[:public_claim_allowed]) == false, claim_gates)
    @test any(row -> String(row[:claim]) ==
        "construct_reviewed_q_fit_metric_claim" &&
        String(row[:status]) ==
            "blocked_until_heldout_or_external_validation" &&
        Bool(row[:local_reporting_allowed]), claim_gates)
    @test any(row -> String(row[:claim]) == "candidate_q_revision_claim" &&
        String(row[:required_evidence]) ==
            "external_construct_validation_plus_cross_validation",
        claim_gates)
    @test any(row -> String(row[:claim]) == "automatic_q_revision" &&
        String(row[:status]) == "blocked", claim_gates)
    @test any(row -> String(row[:claim]) == "local_appendix_diagnostics" &&
        Bool(row[:local_reporting_allowed]) &&
        Bool(row[:public_claim_allowed]) == false, claim_gates)

    links = fixture[:evidence_link_rows]
    @test length(links) == 3
    @test all(row -> Bool(row[:link_satisfied]), links)
    @test Set(String(row[:artifact]) for row in links) == Set(keys(expected_paths))

    decision = fixture[:decision_record]
    @test String(decision[:selected_decision]) ==
        "require_heldout_or_external_validation_before_fit_or_q_claims"
    @test Bool(decision[:validation_policy_recorded])
    @test Bool(decision[:heldout_kfold_selected_from_scalar_policy])
    @test Bool(decision[:heldout_mgmfrm_prediction_study_completed]) == false
    @test Bool(decision[:external_construct_validation_completed]) == false
    @test Bool(decision[:same_data_waic_claim_allowed]) == false
    @test Bool(decision[:raw_psis_loo_claim_allowed]) == false
    @test Bool(decision[:threshold_only_fit_claim_allowed]) == false
    @test Bool(decision[:public_fit_metric_claim_allowed]) == false
    @test Bool(decision[:public_q_revision_claim_allowed]) == false
    @test Bool(decision[:model_weight_or_sparse_superiority_claim_allowed]) ==
        false
    @test Bool(decision[:automatic_q_revision_allowed]) == false
    @test Bool(decision[:local_appendix_diagnostics_allowed])
    @test String(decision[:required_followup]) ==
        "heldout_mgmfrm_prediction_or_external_validation_study"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:local_only])
    @test Bool(summary[:all_input_artifacts_present])
    @test Bool(summary[:all_expected_schemas])
    @test Bool(summary[:all_input_summaries_passed])
    @test Bool(summary[:input_next_gate_matched])
    @test Bool(summary[
        :construct_reviewed_q_fit_reporting_policy_passed])
    @test Bool(summary[:prediction_target_and_model_weight_policy_passed])
    @test Bool(summary[:mgmfrm_q_revision_cross_validation_policy_passed])
    @test Bool(summary[:heldout_kfold_selected_from_scalar_policy])
    @test Bool(summary[:heldout_or_external_validation_required])
    @test Bool(summary[
        :external_construct_validation_required_for_q_claims])
    @test Bool(summary[:same_data_waic_claim_blocked])
    @test Bool(summary[:raw_psis_loo_claim_blocked])
    @test Bool(summary[:threshold_profile_only_claim_blocked])
    @test Bool(summary[:no_single_threshold_profile_promoted])
    @test Bool(summary[:no_public_fit_metric_claim])
    @test Bool(summary[:no_public_q_revision_claim])
    @test Bool(summary[:no_automatic_q_revision])
    @test Bool(summary[:no_model_weight_or_sparse_superiority_claim])
    @test Bool(summary[:all_claim_gate_rows_block_public_claims])
    @test Bool(summary[:all_validation_requirements_recorded])
    @test Bool(summary[:all_evidence_links_satisfied])
    @test Int(summary[:n_input_artifacts]) == length(inputs)
    @test Int(summary[:n_validation_target_rows]) == length(targets)
    @test Int(summary[:n_claim_gate_rows]) == length(claim_gates)
    @test Int(summary[:n_evidence_link_rows]) == length(links)
    @test Int(summary[:n_validation_policy_cells]) == 14
    @test Int(summary[:n_unmet_public_claim_requirements]) == 2
    @test Int(summary[:n_blockers]) == 2
    @test Set(String(blocker) for blocker in
        summary[:remaining_public_blockers]) == Set([
            "heldout_mgmfrm_prediction_study_missing",
            "external_construct_validation_missing",
        ])
    @test String(summary[:recommendation]) ==
        "run_heldout_mgmfrm_prediction_or_external_validation_before_claims"
    @test String(summary[:next_gate]) ==
        "heldout_mgmfrm_prediction_or_external_validation_study"
end

function check_mgmfrm_validation_split_model_comparison_policy_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_validation_split_model_comparison_policy.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) ==
        "validation_split_model_comparison_policy"
    @test String(fixture[:status]) ==
        "validation_split_model_comparison_policy_recorded"
    @test String(fixture[:decision]) ==
        "predeclare_heldout_split_and_model_comparison_before_validation_study"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])
    @test Bool(fixture[:local_only])
    @test Bool(fixture[:heldout_validation_study_completed]) == false
    @test Bool(fixture[:external_construct_validation_completed]) == false
    @test Bool(fixture[:publication_or_registration_action]) == false
    @test Bool(fixture[:public_fit_metric_claim]) == false
    @test Bool(fixture[:public_q_revision_claim]) == false
    @test Bool(fixture[:public_model_weight_claim]) == false
    @test Bool(fixture[:sparse_mgmfrm_superiority_claim]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) ==
        "mgmfrm_validation_split_model_comparison_policy_v1"
    @test String(protocol[:review_kind]) ==
        "local_validation_split_and_model_comparison_policy"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test Bool(protocol[:local_only])
    @test String(protocol[:policy_scope]) ==
        "pre_execution_protocol_for_heldout_mgmfrm_prediction_validation"
    @test String(protocol[:decision_target]) ==
        "predeclare_split_units_leakage_guards_and_comparison_models"
    @test Bool(thresholds[
        :require_heldout_prediction_validation_policy_passed])
    @test Bool(thresholds[
        :require_prediction_target_and_model_weight_policy_passed])
    @test Bool(thresholds[
        :require_q_revision_cross_validation_policy_passed])
    @test Bool(thresholds[
        :require_construct_reviewed_q_fit_reporting_policy_passed])
    @test Bool(thresholds[:require_heldout_policy_next_gate_matched])
    @test Bool(thresholds[:require_primary_holdout_target_selected])
    @test Bool(thresholds[:require_split_policy_recorded])
    @test Bool(thresholds[:require_comparison_model_set_recorded])
    @test Bool(thresholds[:require_all_leakage_guards_recorded])
    @test Bool(thresholds[
        :require_all_claim_rules_block_public_claims_before_execution])
    @test Bool(thresholds[:require_same_data_fit_metrics_diagnostic_only])
    @test Bool(thresholds[:require_no_public_fit_metric_claim])
    @test Bool(thresholds[:require_no_public_q_revision_claim])
    @test Bool(thresholds[
        :require_no_model_weight_or_sparse_superiority_claim])
    @test Bool(thresholds[:require_no_publication_or_registration_action])

    inputs = fixture[:input_artifacts]
    expected_paths = Dict(
        "mgmfrm_heldout_prediction_validation_policy" =>
            "test/fixtures/mgmfrm_heldout_prediction_validation_policy.json",
        "prediction_target_and_model_weight_policy" =>
            "test/fixtures/gmfrm_prediction_target_and_model_weight_policy.json",
        "mgmfrm_q_revision_cross_validation_policy" =>
            "test/fixtures/mgmfrm_q_revision_cross_validation_policy.json",
        "mgmfrm_construct_reviewed_q_fit_reporting_policy" =>
            "test/fixtures/mgmfrm_construct_reviewed_q_fit_reporting_policy.json",
    )
    @test length(inputs) == length(expected_paths)
    @test Set(String(row[:artifact]) for row in inputs) ==
        Set(keys(expected_paths))
    for row in inputs
        artifact = String(row[:artifact])
        @test expected_paths[artifact] == String(row[:path])
        @test Bool(row[:exists])
        @test Bool(row[:schema_matches])
        @test Bool(row[:summary_passed])
        @test String(row[:sha256]) ==
            file_sha256(joinpath(root, String(row[:path])))
    end

    splits = fixture[:split_policy_rows]
    @test length(splits) == 4
    @test Set(String(row[:split]) for row in splits) == Set([
        "observation_kfold",
        "respondent_holdout",
        "item_holdout",
        "scenario_replicate_holdout",
    ])
    @test count(row -> Bool(row[:selected_for_first_execution]), splits) == 1
    @test any(row -> String(row[:split]) == "observation_kfold" &&
        String(row[:role]) == "primary_heldout_prediction_target" &&
        Bool(row[:selected_for_first_execution]), splits)
    @test all(row -> Bool(row[:leakage_guard_required]), splits)

    models = fixture[:comparison_model_rows]
    @test length(models) == 5
    @test Set(String(row[:model]) for row in models) == Set([
        "scalar_gmfrm_baseline",
        "confirmatory_mgmfrm_current_q",
        "sparse_mgmfrm_current_q",
        "construct_reviewed_revised_q_mgmfrm",
        "null_or_intercept_reference",
    ])
    @test all(row -> Bool(row[:included]), models)
    @test any(row -> String(row[:model]) ==
        "construct_reviewed_revised_q_mgmfrm" &&
        String(row[:claim_scope]) ==
            "blocked_until_external_construct_validation", models)

    metrics = fixture[:metric_rows]
    @test length(metrics) == 5
    @test any(row -> String(row[:metric]) ==
        "heldout_log_predictive_density" &&
        String(row[:role]) == "primary_predictive_metric", metrics)
    @test all(row -> Bool(row[:public_claim_requires_execution]), metrics)

    leakage_guards = fixture[:leakage_guard_rows]
    @test length(leakage_guards) == 6
    @test Set(String(row[:guard]) for row in leakage_guards) == Set([
        "fold_assignment_before_fit",
        "q_revision_train_only",
        "threshold_profiles_locked_before_fit",
        "model_weight_claim_heldout_only",
        "same_data_diagnostics_not_claim_targets",
        "external_validation_not_used_for_tuning",
    ])
    @test all(row -> Bool(row[:requirement_recorded]), leakage_guards)
    @test all(row -> Bool(row[:public_claim_blocked_if_unsatisfied]),
        leakage_guards)

    claim_rules = fixture[:claim_rule_rows]
    @test length(claim_rules) == 5
    @test all(row -> Bool(row[:public_claim_allowed]) == false, claim_rules)
    @test any(row -> String(row[:claim]) ==
        "heldout_prediction_improvement" &&
        Bool(row[:execution_completed]) == false, claim_rules)
    @test any(row -> String(row[:claim]) == "local_protocol_description" &&
        Bool(row[:execution_completed]), claim_rules)

    links = fixture[:evidence_link_rows]
    @test length(links) == 4
    @test all(row -> Bool(row[:link_satisfied]), links)
    @test Set(String(row[:artifact]) for row in links) == Set(keys(expected_paths))

    decision = fixture[:decision_record]
    @test String(decision[:selected_decision]) ==
        "predeclare_heldout_split_and_model_comparison_before_validation_study"
    @test Bool(decision[:split_policy_recorded])
    @test Bool(decision[:comparison_model_set_recorded])
    @test String(decision[:primary_split]) == "observation_kfold"
    @test String(decision[:primary_prediction_target]) ==
        "heldout_observation_log_score"
    @test Bool(decision[:heldout_validation_study_completed]) == false
    @test Bool(decision[:external_construct_validation_completed]) == false
    @test Bool(decision[:same_data_fit_metrics_diagnostic_only])
    @test Bool(decision[:public_fit_metric_claim_allowed]) == false
    @test Bool(decision[:public_q_revision_claim_allowed]) == false
    @test Bool(decision[
        :model_weight_or_sparse_superiority_claim_allowed]) == false
    @test String(decision[:required_followup]) ==
        "heldout_mgmfrm_prediction_simulation_grid"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:local_only])
    @test Bool(summary[:all_input_artifacts_present])
    @test Bool(summary[:all_expected_schemas])
    @test Bool(summary[:all_input_summaries_passed])
    @test Bool(summary[:heldout_policy_next_gate_matched])
    @test Bool(summary[:heldout_prediction_validation_policy_passed])
    @test Bool(summary[:prediction_target_and_model_weight_policy_passed])
    @test Bool(summary[:mgmfrm_q_revision_cross_validation_policy_passed])
    @test Bool(summary[
        :mgmfrm_construct_reviewed_q_fit_reporting_policy_passed])
    @test Bool(summary[:primary_holdout_target_selected])
    @test Bool(summary[:split_policy_recorded])
    @test Bool(summary[:comparison_model_set_recorded])
    @test Bool(summary[:all_metrics_predeclared])
    @test Bool(summary[:all_leakage_guards_recorded])
    @test Bool(summary[:all_evidence_links_satisfied])
    @test Bool(summary[:all_claim_rules_block_public_claims])
    @test Bool(summary[:same_data_fit_metrics_diagnostic_only])
    @test Bool(summary[:no_public_fit_metric_claim])
    @test Bool(summary[:no_public_q_revision_claim])
    @test Bool(summary[:no_automatic_q_revision])
    @test Bool(summary[:no_model_weight_or_sparse_superiority_claim])
    @test Bool(summary[:heldout_validation_study_completed]) == false
    @test Bool(summary[:external_construct_validation_completed]) == false
    @test Bool(summary[:validation_execution_required])
    @test Int(summary[:n_input_artifacts]) == length(inputs)
    @test Int(summary[:n_split_policy_rows]) == length(splits)
    @test Int(summary[:n_comparison_model_rows]) == length(models)
    @test Int(summary[:n_metric_rows]) == length(metrics)
    @test Int(summary[:n_leakage_guard_rows]) == length(leakage_guards)
    @test Int(summary[:n_claim_rule_rows]) == length(claim_rules)
    @test Int(summary[:n_evidence_link_rows]) == length(links)
    @test Int(summary[:n_validation_split_policy_cells]) == 29
    @test Int(summary[:n_unmet_public_claim_requirements]) == 3
    @test Int(summary[:n_blockers]) == 3
    @test Set(String(blocker) for blocker in
        summary[:remaining_public_blockers]) == Set([
            "heldout_split_execution_missing",
            "heldout_model_comparison_results_missing",
            "external_construct_validation_missing",
        ])
    @test String(summary[:recommendation]) ==
        "run_predeclared_heldout_prediction_simulation_or_external_validation"
    @test String(summary[:next_gate]) ==
        "heldout_mgmfrm_prediction_simulation_grid"
end

function check_mgmfrm_heldout_prediction_simulation_grid_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_heldout_prediction_simulation_grid.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) == "heldout_prediction_simulation_grid"
    @test String(fixture[:status]) ==
        "heldout_prediction_simulation_grid_recorded"
    @test String(fixture[:decision]) ==
        "record_pre_execution_heldout_prediction_simulation_grid"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])
    @test Bool(fixture[:local_only])
    @test Bool(fixture[:heldout_prediction_execution_completed]) == false
    @test Bool(fixture[:observed_heldout_results_recorded]) == false
    @test Bool(fixture[:publication_or_registration_action]) == false
    @test Bool(fixture[:public_fit_metric_claim]) == false
    @test Bool(fixture[:public_q_revision_claim]) == false
    @test Bool(fixture[:public_model_weight_claim]) == false
    @test Bool(fixture[:sparse_mgmfrm_superiority_claim]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) ==
        "mgmfrm_heldout_prediction_simulation_grid_v1"
    @test String(protocol[:review_kind]) ==
        "local_heldout_prediction_simulation_grid"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test Bool(protocol[:local_only])
    @test String(protocol[:policy_scope]) ==
        "pre_execution_grid_for_heldout_mgmfrm_prediction_comparison"
    @test String(protocol[:decision_target]) ==
        "fix_scenarios_splits_metrics_and_threshold_sensitivity_before_execution"
    @test Bool(thresholds[
        :require_validation_split_model_comparison_policy_passed])
    @test Bool(thresholds[
        :require_fit_metric_threshold_sensitivity_passed])
    @test Bool(thresholds[
        :require_empirical_q_matrix_recovery_simulation_grid_passed])
    @test Bool(thresholds[
        :require_construct_reviewed_q_fit_reporting_policy_passed])
    @test Bool(thresholds[:require_split_policy_next_gate_matched])
    @test Bool(thresholds[:require_predeclared_splits_carried_forward])
    @test Bool(thresholds[:require_all_comparison_models_planned])
    @test Bool(thresholds[:require_all_scenarios_predeclared])
    @test Bool(thresholds[:require_all_metric_surface_values_finite])
    @test Bool(thresholds[:require_threshold_impact_rows_recorded])
    @test Bool(thresholds[:require_leakage_guards_carried_forward])
    @test Bool(thresholds[:require_all_claim_rules_block_public_claims])
    @test Bool(thresholds[:require_no_public_fit_metric_claim])
    @test Bool(thresholds[:require_no_public_model_weight_claim])
    @test Bool(thresholds[:require_no_sparse_superiority_claim])
    @test Bool(thresholds[:require_no_publication_or_registration_action])

    inputs = fixture[:input_artifacts]
    expected_paths = Dict(
        "mgmfrm_validation_split_model_comparison_policy" =>
            "test/fixtures/mgmfrm_validation_split_model_comparison_policy.json",
        "mgmfrm_fit_metric_threshold_sensitivity" =>
            "test/fixtures/mgmfrm_fit_metric_threshold_sensitivity.json",
        "mgmfrm_empirical_q_matrix_recovery_simulation_grid" =>
            "test/fixtures/mgmfrm_empirical_q_matrix_recovery_simulation_grid.json",
        "mgmfrm_construct_reviewed_q_fit_reporting_policy" =>
            "test/fixtures/mgmfrm_construct_reviewed_q_fit_reporting_policy.json",
    )
    @test length(inputs) == length(expected_paths)
    @test Set(String(row[:artifact]) for row in inputs) ==
        Set(keys(expected_paths))
    for row in inputs
        artifact = String(row[:artifact])
        @test expected_paths[artifact] == String(row[:path])
        @test Bool(row[:exists])
        @test Bool(row[:schema_matches])
        @test Bool(row[:summary_passed])
        @test String(row[:sha256]) ==
            file_sha256(joinpath(root, String(row[:path])))
    end

    splits = fixture[:split_execution_rows]
    @test length(splits) == 4
    @test count(row -> Bool(row[:selected_for_first_execution]), splits) == 1
    @test any(row -> String(row[:split]) == "observation_kfold" &&
        Bool(row[:selected_for_first_execution]) &&
        Bool(row[:leakage_guard_required]), splits)
    @test all(row -> Float64(row[:minimum_train_fraction]) >= 0.8, splits)

    models = fixture[:comparison_model_rows]
    @test length(models) == 5
    @test Set(String(row[:model]) for row in models) == Set([
        "scalar_gmfrm_baseline",
        "confirmatory_mgmfrm_current_q",
        "sparse_mgmfrm_current_q",
        "construct_reviewed_revised_q_mgmfrm",
        "null_or_intercept_reference",
    ])
    @test all(row -> Bool(row[:planned_for_execution]), models)

    metrics = fixture[:metric_rows]
    @test length(metrics) == 5
    @test Set(String(row[:metric]) for row in metrics) == Set([
        "heldout_log_predictive_density",
        "heldout_response_accuracy_or_rank_score",
        "heldout_calibration_error",
        "posterior_predictive_discrepancy",
        "simulation_parameter_recovery_shift",
    ])

    scenarios = fixture[:scenario_rows]
    @test length(scenarios) == 5
    @test count(row -> Bool(row[:expected_rank_stable]) == false,
        scenarios) == 1
    @test count(row -> Bool(row[:external_construct_validation_needed]),
        scenarios) == 2
    @test Set(String(row[:scenario]) for row in scenarios) == Set([
        "well_specified_current_q",
        "missing_loading_revised_q",
        "sparse_signal_current_q",
        "rater_method_noise",
        "weak_dimension_ambiguous",
    ])

    scenario_models = fixture[:scenario_model_summary_rows]
    @test length(scenario_models) == 25
    @test any(row -> String(row[:scenario]) == "missing_loading_revised_q" &&
        String(row[:model]) == "construct_reviewed_revised_q_mgmfrm" &&
        Int(row[:expected_primary_rank]) == 1 &&
        Bool(row[:expected_primary_best]), scenario_models)
    @test any(row -> String(row[:scenario]) == "rater_method_noise" &&
        String(row[:model]) == "scalar_gmfrm_baseline" &&
        Int(row[:expected_primary_rank]) == 1, scenario_models)
    @test all(row -> Bool(row[:public_claim_allowed]) == false,
        scenario_models)

    metric_surface = fixture[:metric_surface_rows]
    @test length(metric_surface) == 125
    @test all(row -> isfinite(Float64(row[:expected_value])),
        metric_surface)
    @test all(row -> Bool(row[:observed_heldout_result]) == false,
        metric_surface)
    @test all(row -> Bool(row[:simulation_design_value]), metric_surface)
    @test all(row -> Bool(row[:public_claim_allowed]) == false,
        metric_surface)
    @test any(row -> String(row[:scenario]) == "sparse_signal_current_q" &&
        String(row[:model]) == "sparse_mgmfrm_current_q" &&
        String(row[:metric]) == "heldout_log_predictive_density" &&
        Bool(row[:expected_best_for_metric]), metric_surface)

    threshold_profiles = fixture[:threshold_profile_rows]
    threshold_impacts = fixture[:threshold_impact_rows]
    @test length(threshold_profiles) == 4
    @test length(threshold_impacts) == 20
    @test all(row -> Bool(row[:used_for_claim]) == false,
        threshold_profiles)
    @test any(row -> String(row[:scenario]) ==
        "weak_dimension_ambiguous" &&
        Bool(row[:ranking_stable_under_profile]) == false,
        threshold_impacts)
    @test all(row -> Bool(row[:public_claim_allowed]) == false,
        threshold_impacts)

    leakage_guards = fixture[:leakage_guard_rows]
    @test length(leakage_guards) == 6
    @test all(row -> Bool(row[:carried_from_policy]), leakage_guards)
    @test all(row -> Bool(row[:public_claim_blocked_if_unsatisfied]),
        leakage_guards)

    claim_rules = fixture[:claim_rule_rows]
    @test length(claim_rules) == 5
    @test all(row -> Bool(row[:public_claim_allowed]) == false, claim_rules)
    @test any(row -> String(row[:claim]) ==
        "model_weight_or_sparse_mgmfrm_superiority" &&
        Bool(row[:execution_completed]) == false, claim_rules)

    links = fixture[:evidence_link_rows]
    @test length(links) == 4
    @test all(row -> Bool(row[:link_satisfied]), links)

    best_counts = fixture[:best_model_count_rows]
    @test Set((String(row[:model]), Int(row[:n])) for row in best_counts) ==
        Set([
            ("scalar_gmfrm_baseline", 1),
            ("confirmatory_mgmfrm_current_q", 2),
            ("sparse_mgmfrm_current_q", 1),
            ("construct_reviewed_revised_q_mgmfrm", 1),
        ])

    decision = fixture[:decision_record]
    @test String(decision[:selected_decision]) ==
        "record_pre_execution_heldout_prediction_simulation_grid"
    @test Bool(decision[:split_policy_carried_forward])
    @test Bool(decision[:comparison_model_set_carried_forward])
    @test Bool(decision[:scenario_grid_recorded])
    @test Bool(decision[:threshold_profiles_carried_forward])
    @test Bool(decision[:heldout_prediction_execution_completed]) == false
    @test Bool(decision[:observed_heldout_results_recorded]) == false
    @test Bool(decision[:public_fit_metric_claim_allowed]) == false
    @test Bool(decision[:public_q_revision_claim_allowed]) == false
    @test Bool(decision[
        :model_weight_or_sparse_superiority_claim_allowed]) == false
    @test String(decision[:required_followup]) ==
        "heldout_mgmfrm_prediction_execution"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:local_only])
    @test Bool(summary[:all_input_artifacts_present])
    @test Bool(summary[:all_expected_schemas])
    @test Bool(summary[:all_input_summaries_passed])
    @test Bool(summary[:validation_split_model_comparison_policy_passed])
    @test Bool(summary[:fit_metric_threshold_sensitivity_passed])
    @test Bool(summary[
        :empirical_q_matrix_recovery_simulation_grid_passed])
    @test Bool(summary[:construct_reviewed_q_fit_reporting_policy_passed])
    @test Bool(summary[:split_policy_next_gate_matched])
    @test Bool(summary[:predeclared_splits_carried_forward])
    @test Bool(summary[:all_comparison_models_planned])
    @test Bool(summary[:all_scenarios_predeclared])
    @test Bool(summary[:all_metric_surface_values_finite])
    @test Bool(summary[:threshold_impact_rows_recorded])
    @test Bool(summary[:leakage_guards_carried_forward])
    @test Bool(summary[:all_evidence_links_satisfied])
    @test Bool(summary[:all_claim_rules_block_public_claims])
    @test Bool(summary[:no_public_fit_metric_claim])
    @test Bool(summary[:no_public_q_revision_claim])
    @test Bool(summary[:no_public_model_weight_claim])
    @test Bool(summary[:no_sparse_superiority_claim])
    @test Bool(summary[:heldout_prediction_execution_completed]) == false
    @test Bool(summary[:observed_heldout_results_recorded]) == false
    @test Bool(summary[:heldout_execution_required])
    @test Int(summary[:n_input_artifacts]) == length(inputs)
    @test Int(summary[:n_split_execution_rows]) == length(splits)
    @test Int(summary[:n_comparison_model_rows]) == length(models)
    @test Int(summary[:n_metric_rows]) == length(metrics)
    @test Int(summary[:n_scenarios]) == length(scenarios)
    @test Int(summary[:n_scenario_model_summary_rows]) ==
        length(scenario_models)
    @test Int(summary[:n_metric_surface_rows]) == length(metric_surface)
    @test Int(summary[:n_threshold_profiles]) == length(threshold_profiles)
    @test Int(summary[:n_threshold_impact_rows]) == length(threshold_impacts)
    @test Int(summary[:n_leakage_guard_rows]) == length(leakage_guards)
    @test Int(summary[:n_claim_rule_rows]) == length(claim_rules)
    @test Int(summary[:n_evidence_link_rows]) == length(links)
    @test Int(summary[:n_heldout_simulation_grid_cells]) == 125
    @test Int(summary[:n_rank_unstable_scenarios]) == 1
    @test Int(summary[:n_external_construct_validation_scenarios]) == 2
    @test Int(summary[:n_blockers]) == 3
    @test Set(String(blocker) for blocker in
        summary[:remaining_public_blockers]) == Set([
            "heldout_prediction_execution_missing",
            "external_construct_validation_missing",
            "model_rank_stability_not_observed",
        ])
    @test String(summary[:recommendation]) ==
        "run_heldout_mgmfrm_prediction_execution_before_model_weight_or_sparse_claims"
    @test String(summary[:next_gate]) ==
        "heldout_mgmfrm_prediction_execution"
end

function check_mgmfrm_heldout_prediction_execution_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_heldout_prediction_execution.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) == "heldout_prediction_execution"
    @test String(fixture[:status]) ==
        "heldout_prediction_execution_recorded"
    @test String(fixture[:decision]) ==
        "record_deterministic_heldout_prediction_execution"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])
    @test Bool(fixture[:local_only])
    @test Bool(fixture[:heldout_prediction_execution_completed])
    @test Bool(fixture[:observed_heldout_results_recorded])
    @test Bool(fixture[:mcmc_refit_execution_completed]) == false
    @test Bool(fixture[:full_refit_execution_required])
    @test Bool(fixture[:publication_or_registration_action]) == false
    @test Bool(fixture[:public_fit_metric_claim]) == false
    @test Bool(fixture[:public_q_revision_claim]) == false
    @test Bool(fixture[:public_model_weight_claim]) == false
    @test Bool(fixture[:sparse_mgmfrm_superiority_claim]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) ==
        "mgmfrm_heldout_prediction_execution_v1"
    @test String(protocol[:review_kind]) ==
        "local_deterministic_heldout_prediction_execution"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test Bool(protocol[:local_only])
    @test String(protocol[:execution_engine]) ==
        "deterministic_synthetic_metric_runner_no_mcmc_refit"
    @test String(protocol[:primary_split]) == "observation_kfold"
    @test Int(protocol[:n_folds]) == 5
    @test Int(protocol[:n_execution_observations_per_scenario]) == 40
    @test Bool(thresholds[:require_pre_execution_grid_passed])
    @test Bool(thresholds[
        :require_validation_split_model_comparison_policy_passed])
    @test Bool(thresholds[:require_fit_metric_threshold_sensitivity_passed])
    @test Bool(thresholds[:require_observation_kfold_selected])
    @test Bool(thresholds[:require_all_comparison_models_executed])
    @test Bool(thresholds[:require_all_scenarios_executed])
    @test Bool(thresholds[:require_fold_assignments_materialized])
    @test Bool(thresholds[:require_all_observations_held_out_once])
    @test Bool(thresholds[:require_observed_metric_rows_recorded])
    @test Bool(thresholds[:require_all_observed_metric_values_finite])
    @test Bool(thresholds[:require_rank_stability_review_recorded])
    @test Bool(thresholds[:require_threshold_profile_observed_rows_recorded])
    @test Bool(thresholds[:require_model_weight_rows_recorded])
    @test Bool(thresholds[:require_all_claim_rules_block_public_claims])
    @test Bool(thresholds[:require_no_public_fit_metric_claim])
    @test Bool(thresholds[:require_no_public_q_revision_claim])
    @test Bool(thresholds[:require_no_public_model_weight_claim])
    @test Bool(thresholds[:require_no_sparse_superiority_claim])
    @test Bool(thresholds[:require_no_publication_or_registration_action])

    inputs = fixture[:input_artifacts]
    expected_paths = Dict(
        "mgmfrm_heldout_prediction_simulation_grid" =>
            "test/fixtures/mgmfrm_heldout_prediction_simulation_grid.json",
        "mgmfrm_validation_split_model_comparison_policy" =>
            "test/fixtures/mgmfrm_validation_split_model_comparison_policy.json",
        "mgmfrm_fit_metric_threshold_sensitivity" =>
            "test/fixtures/mgmfrm_fit_metric_threshold_sensitivity.json",
    )
    @test length(inputs) == length(expected_paths)
    @test Set(String(row[:artifact]) for row in inputs) ==
        Set(keys(expected_paths))
    for row in inputs
        artifact = String(row[:artifact])
        @test expected_paths[artifact] == String(row[:path])
        @test Bool(row[:exists])
        @test Bool(row[:schema_matches])
        @test Bool(row[:summary_passed])
        @test String(row[:sha256]) ==
            file_sha256(joinpath(root, String(row[:path])))
    end

    scenario_names = Set([
        "well_specified_current_q",
        "missing_loading_revised_q",
        "sparse_signal_current_q",
        "rater_method_noise",
        "weak_dimension_ambiguous",
    ])
    model_names = Set([
        "scalar_gmfrm_baseline",
        "confirmatory_mgmfrm_current_q",
        "sparse_mgmfrm_current_q",
        "construct_reviewed_revised_q_mgmfrm",
        "null_or_intercept_reference",
    ])
    metric_names = Set([
        "heldout_log_predictive_density",
        "heldout_response_accuracy_or_rank_score",
        "heldout_calibration_error",
        "posterior_predictive_discrepancy",
        "simulation_parameter_recovery_shift",
    ])

    fold_assignments = fixture[:fold_assignment_rows]
    @test length(fold_assignments) == 25
    @test Set(String(row[:scenario]) for row in fold_assignments) ==
        scenario_names
    @test Set(Int(row[:fold]) for row in fold_assignments) == Set(1:5)
    @test all(row -> String(row[:split]) == "observation_kfold",
        fold_assignments)
    @test all(row -> Int(row[:n_observations]) == 40, fold_assignments)
    @test all(row -> Int(row[:n_train_observations]) == 32,
        fold_assignments)
    @test all(row -> Int(row[:n_heldout_observations]) == 8,
        fold_assignments)
    @test all(row -> Float64(row[:train_fraction]) ≈ 0.8,
        fold_assignments)
    @test all(row -> Bool(row[:fold_assignment_materialized]),
        fold_assignments)
    @test all(row -> Bool(row[:train_only_q_revision_guard_satisfied]),
        fold_assignments)
    for scenario in scenario_names
        scenario_folds = [
            row for row in fold_assignments if String(row[:scenario]) == scenario
        ]
        @test length(scenario_folds) == 5
        @test Set(Int(row[:fold]) for row in scenario_folds) == Set(1:5)
        heldout_observations = sort(reduce(vcat,
            [Int.(row[:heldout_observations]) for row in scenario_folds]))
        @test heldout_observations == collect(1:40)
    end

    fold_metrics = fixture[:fold_model_metric_rows]
    @test length(fold_metrics) == 625
    @test Set(String(row[:scenario]) for row in fold_metrics) == scenario_names
    @test Set(String(row[:model]) for row in fold_metrics) == model_names
    @test Set(String(row[:metric]) for row in fold_metrics) == metric_names
    @test Set(Int(row[:fold]) for row in fold_metrics) == Set(1:5)
    @test all(row -> isfinite(Float64(row[:observed_value])), fold_metrics)
    @test all(row -> Bool(row[:observed_heldout_result]), fold_metrics)
    @test all(row -> Bool(row[:mcmc_refit_result]) == false, fold_metrics)
    @test all(row -> Bool(row[:public_claim_allowed]) == false,
        fold_metrics)
    @test all(row -> String(row[:execution_engine]) ==
        "deterministic_synthetic_metric_runner_no_mcmc_refit", fold_metrics)

    scenario_models = fixture[:scenario_model_summary_rows]
    @test length(scenario_models) == 25
    @test all(row -> Bool(row[:observed_heldout_result]), scenario_models)
    @test all(row -> Bool(row[:mcmc_refit_result]) == false,
        scenario_models)
    @test all(row -> Bool(row[:public_claim_allowed]) == false,
        scenario_models)
    @test any(row -> String(row[:scenario]) ==
        "well_specified_current_q" &&
        String(row[:model]) == "confirmatory_mgmfrm_current_q" &&
        Int(row[:observed_primary_rank]) == 1 &&
        Bool(row[:observed_primary_best]), scenario_models)
    @test any(row -> String(row[:scenario]) ==
        "missing_loading_revised_q" &&
        String(row[:model]) == "construct_reviewed_revised_q_mgmfrm" &&
        Int(row[:observed_primary_rank]) == 1 &&
        Bool(row[:observed_primary_best]), scenario_models)
    @test any(row -> String(row[:scenario]) ==
        "sparse_signal_current_q" &&
        String(row[:model]) == "sparse_mgmfrm_current_q" &&
        Int(row[:observed_primary_rank]) == 1 &&
        Bool(row[:observed_primary_best]), scenario_models)
    @test any(row -> String(row[:scenario]) == "rater_method_noise" &&
        String(row[:model]) == "scalar_gmfrm_baseline" &&
        Int(row[:observed_primary_rank]) == 1 &&
        Bool(row[:observed_primary_best]), scenario_models)

    rank_stability = fixture[:rank_stability_rows]
    @test length(rank_stability) == 5
    @test count(row -> Bool(row[:rank_stable_observed]) == false,
        rank_stability) == 1
    @test count(row -> Bool(row[:external_construct_validation_needed]),
        rank_stability) == 2
    weak = only(row for row in rank_stability
        if String(row[:scenario]) == "weak_dimension_ambiguous")
    @test Bool(weak[:rank_stable_observed]) == false
    @test Int(weak[:n_unique_best_models]) == 3
    @test String.(weak[:best_model_by_fold]) == [
        "confirmatory_mgmfrm_current_q",
        "sparse_mgmfrm_current_q",
        "construct_reviewed_revised_q_mgmfrm",
        "confirmatory_mgmfrm_current_q",
        "sparse_mgmfrm_current_q",
    ]
    @test all(row -> Bool(row[:public_claim_allowed]) == false,
        rank_stability)

    threshold_rows = fixture[:threshold_profile_observed_rows]
    @test length(threshold_rows) == 20
    @test any(row -> String(row[:scenario]) ==
        "weak_dimension_ambiguous" &&
        Bool(row[:threshold_profile_sensitive]), threshold_rows)
    @test all(row -> String(row[:claim_decision]) == "diagnostic_only",
        threshold_rows)
    @test all(row -> Bool(row[:public_claim_allowed]) == false,
        threshold_rows)

    model_weights = fixture[:model_weight_rows]
    @test length(model_weights) == 25
    @test Set(String(row[:scenario]) for row in model_weights) ==
        scenario_names
    @test Set(String(row[:model]) for row in model_weights) == model_names
    @test all(row -> String(row[:primary_metric]) ==
        "heldout_log_predictive_density", model_weights)
    @test all(row -> String(row[:weight_source]) ==
        "observed_deterministic_heldout_metrics", model_weights)
    @test all(row -> Bool(row[:public_model_weight_claim_allowed]) == false,
        model_weights)
    for scenario in scenario_names
        scenario_weight =
            sum(Float64(row[:normalized_weight]) for row in model_weights
                if String(row[:scenario]) == scenario)
        @test scenario_weight ≈ 1.0 atol=1e-5
    end

    guards = fixture[:execution_guard_rows]
    @test length(guards) == 6
    @test all(row -> Bool(row[:public_claim_blocked_if_unsatisfied]),
        guards)
    @test any(row -> String(row[:guard]) ==
        "full_mcmc_refit_required_before_public_weight_claims" &&
        Bool(row[:satisfied]) == false, guards)
    @test any(row -> String(row[:guard]) ==
        "external_construct_validation_required_for_q_revision" &&
        Bool(row[:satisfied]) == false, guards)

    claim_rules = fixture[:claim_rule_rows]
    @test length(claim_rules) == 5
    @test all(row -> Bool(row[:execution_completed]), claim_rules)
    @test all(row -> Bool(row[:public_claim_allowed]) == false,
        claim_rules)
    @test any(row -> String(row[:claim]) ==
        "model_weight_or_sparse_mgmfrm_superiority" &&
        Bool(row[:full_mcmc_refit_completed]) == false, claim_rules)
    @test any(row -> String(row[:claim]) == "q_revision_improvement" &&
        Bool(row[:external_construct_validation_completed]) == false,
        claim_rules)

    links = fixture[:evidence_link_rows]
    @test length(links) == 3
    @test all(row -> Bool(row[:link_satisfied]), links)

    decision = fixture[:decision_record]
    @test String(decision[:selected_decision]) ==
        "record_deterministic_heldout_prediction_execution"
    @test Bool(decision[:heldout_prediction_execution_completed])
    @test Bool(decision[:observed_heldout_results_recorded])
    @test Bool(decision[:mcmc_refit_execution_completed]) == false
    @test Bool(decision[:public_fit_metric_claim_allowed]) == false
    @test Bool(decision[:public_q_revision_claim_allowed]) == false
    @test Bool(decision[
        :model_weight_or_sparse_superiority_claim_allowed]) == false
    @test String(decision[:required_followup]) ==
        "full_heldout_mgmfrm_refit_or_external_construct_validation_review"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:local_only])
    @test Bool(summary[:all_input_artifacts_present])
    @test Bool(summary[:all_expected_schemas])
    @test Bool(summary[:all_input_summaries_passed])
    @test Bool(summary[:pre_execution_grid_passed])
    @test Bool(summary[:validation_split_model_comparison_policy_passed])
    @test Bool(summary[:fit_metric_threshold_sensitivity_passed])
    @test Bool(summary[:observation_kfold_selected])
    @test Bool(summary[:all_comparison_models_executed])
    @test Bool(summary[:all_scenarios_executed])
    @test Bool(summary[:fold_assignments_materialized])
    @test Bool(summary[:all_observations_held_out_once])
    @test Bool(summary[:observed_metric_rows_recorded])
    @test Bool(summary[:all_observed_metric_values_finite])
    @test Bool(summary[:rank_stability_review_recorded])
    @test Bool(summary[:threshold_profile_observed_rows_recorded])
    @test Bool(summary[:model_weight_rows_recorded])
    @test Bool(summary[:all_evidence_links_satisfied])
    @test Bool(summary[:all_claim_rules_block_public_claims])
    @test Bool(summary[:no_public_fit_metric_claim])
    @test Bool(summary[:no_public_q_revision_claim])
    @test Bool(summary[:no_public_model_weight_claim])
    @test Bool(summary[:no_sparse_superiority_claim])
    @test Bool(summary[:heldout_prediction_execution_completed])
    @test Bool(summary[:observed_heldout_results_recorded])
    @test Bool(summary[:mcmc_refit_execution_completed]) == false
    @test Bool(summary[:deterministic_synthetic_execution])
    @test Bool(summary[:full_refit_execution_required])
    @test Int(summary[:n_input_artifacts]) == length(inputs)
    @test Int(summary[:n_scenarios]) == 5
    @test Int(summary[:n_models]) == 5
    @test Int(summary[:n_metrics]) == 5
    @test Int(summary[:n_folds]) == 5
    @test Int(summary[:n_execution_observations_per_scenario]) == 40
    @test Int(summary[:n_fold_assignment_rows]) == length(fold_assignments)
    @test Int(summary[:n_fold_model_metric_rows]) == length(fold_metrics)
    @test Int(summary[:n_observed_metric_cells]) == 625
    @test Int(summary[:n_scenario_model_summary_rows]) ==
        length(scenario_models)
    @test Int(summary[:n_rank_stability_rows]) == length(rank_stability)
    @test Int(summary[:n_rank_unstable_scenarios]) == 1
    @test Int(summary[:n_external_construct_validation_scenarios]) == 2
    @test Int(summary[:n_threshold_profile_observed_rows]) ==
        length(threshold_rows)
    @test Int(summary[:n_model_weight_rows]) == length(model_weights)
    @test Int(summary[:n_execution_guard_rows]) == length(guards)
    @test Int(summary[:n_claim_rule_rows]) == length(claim_rules)
    @test Int(summary[:n_evidence_link_rows]) == length(links)
    @test Int(summary[:n_blockers]) == 4
    @test Set(String(blocker) for blocker in
        summary[:remaining_public_blockers]) == Set([
            "full_mcmc_refit_execution_missing",
            "external_construct_validation_missing",
            "rank_stability_not_satisfied_for_all_scenarios",
            "post_execution_public_scope_review_missing",
        ])
    @test String(summary[:recommendation]) ==
        "use_observed_execution_as_local_smoke_keep_claims_blocked_until_full_refit_and_external_validation"
    @test String(summary[:next_gate]) ==
        "full_heldout_mgmfrm_refit_or_external_construct_validation_review"
end

function check_mgmfrm_full_heldout_refit_or_construct_validation_review_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_full_heldout_refit_or_construct_validation_review.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) ==
        "full_heldout_refit_or_construct_validation_review"
    @test String(fixture[:status]) ==
        "full_refit_and_construct_validation_review_recorded"
    @test String(fixture[:decision]) ==
        "record_full_refit_and_construct_validation_requirements"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])
    @test Bool(fixture[:local_only])
    @test Bool(fixture[:heldout_prediction_execution_completed])
    @test Bool(fixture[:full_mcmc_refit_execution_completed]) == false
    @test Bool(fixture[:external_construct_validation_completed]) == false
    @test Bool(fixture[:publication_or_registration_action]) == false
    @test Bool(fixture[:public_fit_metric_claim]) == false
    @test Bool(fixture[:public_q_revision_claim]) == false
    @test Bool(fixture[:public_model_weight_claim]) == false
    @test Bool(fixture[:sparse_mgmfrm_superiority_claim]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) ==
        "mgmfrm_full_heldout_refit_or_construct_validation_review_v1"
    @test String(protocol[:review_kind]) ==
        "local_full_heldout_refit_or_construct_validation_review"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test Bool(protocol[:local_only])
    @test String(protocol[:decision_scope]) ==
        "requirements_before_public_mgmfrm_heldout_or_q_claims"
    @test String(protocol[:next_execution_target]) ==
        "full_heldout_mgmfrm_mcmc_refit_execution_or_external_construct_dataset_review"
    @test Bool(thresholds[:require_heldout_prediction_execution_passed])
    @test Bool(thresholds[:require_heldout_execution_next_gate_matched])
    @test Bool(thresholds[:require_full_mcmc_refit_required])
    @test Bool(thresholds[:require_observed_metric_cells_recorded])
    @test Bool(thresholds[:require_rank_instability_carried_forward])
    @test Bool(thresholds[
        :require_external_construct_validation_requirements_recorded])
    @test Bool(thresholds[:require_refit_execution_plan_recorded])
    @test Bool(thresholds[
        :require_model_claims_blocked_until_refit_and_validation])
    @test Bool(thresholds[:require_no_public_fit_metric_claim])
    @test Bool(thresholds[:require_no_public_q_revision_claim])
    @test Bool(thresholds[:require_no_public_model_weight_claim])
    @test Bool(thresholds[:require_no_sparse_superiority_claim])
    @test Bool(thresholds[:require_no_publication_or_registration_action])

    inputs = fixture[:input_artifacts]
    expected_paths = Dict(
        "mgmfrm_heldout_prediction_execution" =>
            "test/fixtures/mgmfrm_heldout_prediction_execution.json",
        "mgmfrm_q_revision_construct_validity_review" =>
            "test/fixtures/mgmfrm_q_revision_construct_validity_review.json",
        "mgmfrm_validation_split_model_comparison_policy" =>
            "test/fixtures/mgmfrm_validation_split_model_comparison_policy.json",
    )
    @test length(inputs) == length(expected_paths)
    @test Set(String(row[:artifact]) for row in inputs) ==
        Set(keys(expected_paths))
    for row in inputs
        artifact = String(row[:artifact])
        @test String(row[:path]) == expected_paths[artifact]
        @test Bool(row[:exists])
        @test Bool(row[:schema_matches])
        @test Bool(row[:summary_passed])
        @test String(row[:sha256]) ==
            file_sha256(joinpath(root, String(row[:path])))
    end

    scenario_names = Set([
        "well_specified_current_q",
        "missing_loading_revised_q",
        "sparse_signal_current_q",
        "rater_method_noise",
        "weak_dimension_ambiguous",
    ])
    model_names = Set([
        "scalar_gmfrm_baseline",
        "confirmatory_mgmfrm_current_q",
        "sparse_mgmfrm_current_q",
        "construct_reviewed_revised_q_mgmfrm",
        "null_or_intercept_reference",
    ])

    refit_requirements = fixture[:refit_requirement_rows]
    @test length(refit_requirements) == 5
    @test Set(String(row[:scenario]) for row in refit_requirements) ==
        scenario_names
    @test all(row -> Bool(row[:full_mcmc_refit_required]),
        refit_requirements)
    @test all(row -> Bool(row[:full_mcmc_refit_completed]) == false,
        refit_requirements)
    @test all(row -> Bool(row[:public_claim_allowed]) == false,
        refit_requirements)
    @test count(row -> Bool(row[:external_construct_validation_required]),
        refit_requirements) == 2
    weak = only(row for row in refit_requirements
        if String(row[:scenario]) == "weak_dimension_ambiguous")
    @test Bool(weak[:observed_rank_stable]) == false
    @test Int(weak[:n_unique_best_models]) == 3
    @test String(weak[:refit_scope]) == "rank_ambiguity_resolution_refit"
    @test String(weak[:priority]) == "highest"
    missing_loading = only(row for row in refit_requirements
        if String(row[:scenario]) == "missing_loading_revised_q")
    @test Bool(missing_loading[:external_construct_validation_required])
    @test String(missing_loading[:observed_best_model]) ==
        "construct_reviewed_revised_q_mgmfrm"
    @test String(missing_loading[:refit_scope]) ==
        "construct_linked_refit_confirmation"
    @test String(missing_loading[:priority]) == "high"

    refit_plan = fixture[:model_refit_plan_rows]
    @test length(refit_plan) == 5
    @test Set(String(row[:model]) for row in refit_plan) == model_names
    @test all(row -> Bool(row[:included_in_full_refit]), refit_plan)
    @test all(row -> Bool(row[:mcmc_refit_required]), refit_plan)
    @test all(row -> Bool(row[:mcmc_refit_completed]) == false, refit_plan)
    @test all(row -> Int(row[:minimum_chains]) == 4, refit_plan)
    @test all(row -> Int(row[:minimum_draws_per_chain]) == 1000, refit_plan)
    @test all(row -> Set(String.(row[:required_diagnostics])) ==
        Set([
            "rhat",
            "ess",
            "divergence_count",
            "posterior_predictive_check",
        ]), refit_plan)
    @test all(row -> Bool(row[
        :deterministic_metric_reuse_for_public_claim]) == false, refit_plan)
    @test all(row -> Bool(row[:public_model_weight_claim_allowed]) == false,
        refit_plan)

    construct_validation = fixture[:external_construct_validation_rows]
    @test length(construct_validation) == 2
    @test Set(String(row[:scenario]) for row in construct_validation) ==
        Set(["missing_loading_revised_q", "weak_dimension_ambiguous"])
    @test all(row -> Bool(row[:external_construct_validation_completed]) ==
        false, construct_validation)
    @test all(row -> Bool(row[:public_q_revision_claim_allowed]) == false,
        construct_validation)
    @test all(row -> Bool(row[:public_model_superiority_claim_allowed]) ==
        false, construct_validation)

    claim_rules = fixture[:claim_rule_rows]
    @test length(claim_rules) == 5
    @test all(row -> Bool(row[:full_mcmc_refit_completed]) == false,
        claim_rules)
    @test all(row -> Bool(row[:external_construct_validation_completed]) ==
        false, claim_rules)
    @test all(row -> Bool(row[:public_claim_allowed]) == false, claim_rules)

    blockers = fixture[:blocker_rows]
    @test length(blockers) == 4
    @test Set(String(row[:blocker]) for row in blockers) == Set([
        "full_mcmc_refit_execution_missing",
        "external_construct_validation_missing",
        "rank_ambiguity_resolution_refit_missing",
        "independent_public_scope_review_missing",
    ])
    @test all(row -> Bool(row[:resolved]) == false, blockers)

    evidence_links = fixture[:evidence_link_rows]
    @test length(evidence_links) == 3
    @test all(row -> Bool(row[:link_satisfied]), evidence_links)

    decision = fixture[:decision_record]
    @test String(decision[:selected_decision]) ==
        "record_full_refit_and_construct_validation_requirements"
    @test Bool(decision[:heldout_prediction_execution_completed])
    @test Bool(decision[:full_mcmc_refit_execution_completed]) == false
    @test Bool(decision[:external_construct_validation_completed]) == false
    @test Bool(decision[:refit_or_external_validation_review_completed])
    @test Bool(decision[:public_fit_metric_claim_allowed]) == false
    @test Bool(decision[:public_q_revision_claim_allowed]) == false
    @test Bool(decision[
        :model_weight_or_sparse_superiority_claim_allowed]) == false
    @test String(decision[:required_followup]) ==
        "full_heldout_mgmfrm_mcmc_refit_execution_or_external_construct_dataset_review"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:local_only])
    @test Bool(summary[:all_input_artifacts_present])
    @test Bool(summary[:all_expected_schemas])
    @test Bool(summary[:all_input_summaries_passed])
    @test Bool(summary[:heldout_prediction_execution_passed])
    @test Bool(summary[:heldout_execution_next_gate_matched])
    @test Bool(summary[:construct_validity_review_passed])
    @test Bool(summary[:validation_split_model_comparison_policy_passed])
    @test Bool(summary[:full_mcmc_refit_required])
    @test Bool(summary[:observed_metric_cells_recorded])
    @test Bool(summary[:rank_instability_carried_forward])
    @test Bool(summary[:external_construct_validation_requirements_recorded])
    @test Bool(summary[:refit_execution_plan_recorded])
    @test Bool(summary[:all_claim_rules_block_public_claims])
    @test Bool(summary[:all_evidence_links_satisfied])
    @test Bool(summary[:no_public_fit_metric_claim])
    @test Bool(summary[:no_public_q_revision_claim])
    @test Bool(summary[:no_public_model_weight_claim])
    @test Bool(summary[:no_sparse_superiority_claim])
    @test Bool(summary[:heldout_prediction_execution_completed])
    @test Bool(summary[:full_mcmc_refit_execution_completed]) == false
    @test Bool(summary[:external_construct_validation_completed]) == false
    @test Bool(summary[:refit_or_external_validation_review_completed])
    @test Int(summary[:n_input_artifacts]) == length(inputs)
    @test Int(summary[:n_refit_requirement_rows]) == length(refit_requirements)
    @test Int(summary[:n_model_refit_plan_rows]) == length(refit_plan)
    @test Int(summary[:n_external_construct_validation_rows]) ==
        length(construct_validation)
    @test Int(summary[:n_claim_rule_rows]) == length(claim_rules)
    @test Int(summary[:n_blocker_rows]) == length(blockers)
    @test Int(summary[:n_evidence_link_rows]) == length(evidence_links)
    @test Int(summary[:n_review_cells]) == 17
    @test Int(summary[:n_observed_metric_cells]) == 625
    @test Int(summary[:n_rank_unstable_scenarios]) == 1
    @test Int(summary[:n_external_construct_validation_scenarios]) == 2
    @test Int(summary[:n_blockers]) == 4
    @test Set(String(blocker) for blocker in
        summary[:remaining_public_blockers]) == Set([
            "full_mcmc_refit_execution_missing",
            "external_construct_validation_missing",
            "rank_ambiguity_resolution_refit_missing",
            "independent_public_scope_review_missing",
        ])
    @test String(summary[:recommendation]) ==
        "execute_full_heldout_refit_or_attach_external_construct_validation_before_claims"
    @test String(summary[:next_gate]) ==
        "full_heldout_mgmfrm_mcmc_refit_execution_or_external_construct_dataset_review"
end
