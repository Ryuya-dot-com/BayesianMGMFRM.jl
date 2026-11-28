function check_mgmfrm_publication_grade_refit_batch_results_review_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_publication_grade_refit_batch_results_review.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) ==
        "publication_grade_refit_batch_results_review"
    @test String(fixture[:status]) ==
        "publication_grade_refit_batch_results_review_recorded"
    @test String(fixture[:decision]) ==
        "record_publication_grade_refit_batch_results_state"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])
    @test Bool(fixture[:local_only])
    @test Bool(fixture[:batch_only])
    @test Bool(fixture[:local_artifacts_ignored_for_fixture]) == false
    @test Bool(fixture[:publication_or_registration_action]) == false
    @test Bool(fixture[:publication_grade_batch_results_review_recorded])
    @test Bool(fixture[:full_125_unit_publication_grade_batch_completed])
    @test Bool(fixture[:public_fit_metric_claim]) == false
    @test Bool(fixture[:public_q_revision_claim]) == false
    @test Bool(fixture[:public_model_weight_claim]) == false
    @test Bool(fixture[:sparse_mgmfrm_superiority_claim]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) ==
        "mgmfrm_publication_grade_refit_batch_results_review_v1"
    @test String(protocol[:review_kind]) ==
        "local_publication_grade_refit_batch_results_review"
    @test String(protocol[:source_plan]) ==
        "mgmfrm_publication_grade_refit_batch_expansion_plan"
    @test Int(protocol[:expected_execution_units]) == 125
    @test Int(protocol[:expected_mcmc_execution_units]) == 100
    @test Int(protocol[:expected_analytic_reference_units]) == 25
    @test Bool(thresholds[:require_batch_plan_passed])
    @test Bool(thresholds[:require_result_review_rows_recorded])
    @test Bool(thresholds[:require_missing_or_valid_job_artifacts])
    @test Bool(thresholds[:require_fit_metric_threshold_sensitivity_passed])
    @test Bool(thresholds[:require_threshold_profiles_recorded])
    @test Bool(thresholds[:require_threshold_profile_job_rows_recorded])
    @test Bool(thresholds[:require_threshold_profile_model_summary_rows_recorded])
    @test Bool(thresholds[:require_threshold_profile_scenario_model_summary_rows_recorded])
    @test Bool(thresholds[:require_model_summary_rows_recorded])
    @test Bool(thresholds[:require_scenario_model_summary_rows_recorded])
    @test Bool(thresholds[:require_descriptive_only_rankings])
    @test Bool(thresholds[:require_no_single_threshold_profile_promoted])
    @test Bool(thresholds[:require_all_public_claims_blocked])
    @test Bool(thresholds[:require_no_publication_or_registration_action])

    inputs = fixture[:input_artifacts]
    @test length(inputs) == 2
    input_by_artifact = Dict(String(row[:artifact]) => row for row in inputs)
    plan = input_by_artifact[
        "mgmfrm_publication_grade_refit_batch_expansion_plan"]
    @test String(plan[:artifact]) ==
        "mgmfrm_publication_grade_refit_batch_expansion_plan"
    @test String(plan[:path]) ==
        "test/fixtures/mgmfrm_publication_grade_refit_batch_expansion_plan.json"
    @test Bool(plan[:exists])
    @test Bool(plan[:schema_matches])
    @test Bool(plan[:summary_passed])
    @test String(plan[:sha256]) ==
        file_sha256(joinpath(root, String(plan[:path])))
    threshold_input =
        input_by_artifact["mgmfrm_fit_metric_threshold_sensitivity"]
    @test String(threshold_input[:path]) ==
        "test/fixtures/mgmfrm_fit_metric_threshold_sensitivity.json"
    @test Bool(threshold_input[:exists])
    @test Bool(threshold_input[:schema_matches])
    @test Bool(threshold_input[:summary_passed])
    @test String(threshold_input[:sha256]) ==
        file_sha256(joinpath(root, String(threshold_input[:path])))
    @test Int(threshold_input[:summary][:n_threshold_profiles]) == 4
    @test Bool(threshold_input[:summary][
        :threshold_profiles_change_at_least_one_flag])
    @test Bool(threshold_input[:summary][
        :no_single_threshold_profile_promoted])

    rows = fixture[:job_result_review_rows]
    @test length(rows) == 125
    @test count(row -> Bool(row[:mcmc_refit_required]), rows) == 100
    @test count(row -> Bool(row[:analytic_reference_scored]), rows) == 25
    @test all(row -> Bool(row[:artifacts_complete]), rows)
    @test all(row -> Bool(row[:execution_observed]), rows)
    @test all(row -> Bool(row[:dry_run_observed]) == false, rows)
    @test all(row -> Bool(row[:diagnostics_observed]), rows)
    @test all(row -> Bool(row[:diagnostic_gate_passed]), rows)
    @test all(row -> Bool(row[:heldout_predictive_score_computed]), rows)
    @test all(row -> Bool(row[:public_claim_allowed]) == false, rows)
    for row in rows
        result_artifact = row[:result_artifact]
        @test Bool(result_artifact[:exists])
        @test String(result_artifact[:status]) ==
            "publication_grade_refit_batch_job_executed"
        @test Bool(result_artifact[:schema_matches])
        @test Bool(result_artifact[:summary_passed])

        diagnostic_artifact = row[:diagnostic_artifact]
        @test Bool(diagnostic_artifact[:exists])
        @test String(diagnostic_artifact[:status]) ==
            "publication_grade_refit_batch_job_diagnostics_recorded"
        @test Bool(diagnostic_artifact[:schema_matches])
        @test Bool(diagnostic_artifact[:summary_passed])

        heldout_artifact = row[:heldout_artifact]
        @test Bool(heldout_artifact[:exists])
        @test String(heldout_artifact[:status]) ==
            "publication_grade_refit_batch_job_heldout_score_recorded"
        @test Bool(heldout_artifact[:schema_matches])
        @test Bool(heldout_artifact[:summary_passed])
    end

    model_rows = fixture[:model_summary_rows]
    @test length(model_rows) == 5
    @test sum(Int(row[:n_execution_units]) for row in model_rows) == 125
    @test sum(Int(row[:n_mcmc_execution_units]) for row in model_rows) == 100
    @test sum(Int(row[:n_analytic_reference_units]) for row in model_rows) ==
        25
    @test all(row -> Int(row[:n_executed_units]) ==
        Int(row[:n_execution_units]), model_rows)
    @test sum(Int(row[:n_diagnostic_gate_passed_units])
        for row in model_rows) == 125
    scalar_model = only(row for row in model_rows
        if String(row[:model]) == "scalar_gmfrm_baseline")
    @test Int(scalar_model[:n_diagnostic_gate_passed_units]) == 25
    @test all(row -> Bool(row[:public_claim_allowed]) == false, model_rows)

    scenario_model_rows = fixture[:scenario_model_summary_rows]
    @test length(scenario_model_rows) == 25
    @test sum(Int(row[:n_execution_units]) for row in scenario_model_rows) ==
        125
    @test all(row -> Int(row[:n_executed_units]) ==
        Int(row[:n_execution_units]), scenario_model_rows)
    @test all(row -> Bool(row[:public_claim_allowed]) == false,
        scenario_model_rows)

    profile_rows = fixture[:threshold_profile_rows]
    @test length(profile_rows) == 4
    @test Set(String(row[:profile]) for row in profile_rows) == Set([
        "strict_bayesian_workflow",
        "screening_workflow",
        "exploratory_rasch_lenient",
        "sample_size_mean_square",
    ])
    @test all(row -> String(row[:heldout_threshold_binding]) ==
        "calibration_abs_threshold_times_score_range_proxy", profile_rows)
    @test all(row -> Float64(row[:score_range_proxy]) == 2.0,
        profile_rows)
    @test all(row -> Bool(row[:public_fit_metric_claim_allowed]) == false,
        profile_rows)

    threshold_job_rows = fixture[:threshold_profile_job_rows]
    @test length(threshold_job_rows) == 500
    @test count(row -> Bool(row[:mcmc_refit_required]),
        threshold_job_rows) == 400
    @test all(row -> Bool(row[:execution_observed]), threshold_job_rows)
    @test all(row -> Bool(row[:threshold_profile_evaluable]),
        threshold_job_rows)
    @test count(row -> Bool(row[:threshold_profile_passed]),
        threshold_job_rows) == 24
    @test sum(Int(row[:n_threshold_flags]) for row in threshold_job_rows) ==
        476
    @test all(row -> Int(row[:n_missing_profile_inputs]) == 0,
        threshold_job_rows)
    @test all(row -> Bool(row[:threshold_profile_promoted]) == false,
        threshold_job_rows)
    @test all(row -> Bool(row[:public_fit_metric_claim_allowed]) == false,
        threshold_job_rows)

    threshold_model_rows = fixture[:threshold_profile_model_summary_rows]
    @test length(threshold_model_rows) == 20
    @test sum(Int(row[:n_threshold_profile_rows])
        for row in threshold_model_rows) == 500
    @test all(row -> Int(row[:n_evaluable_rows]) ==
        Int(row[:n_threshold_profile_rows]), threshold_model_rows)
    @test all(row -> Bool(row[:threshold_profile_promoted]) == false,
        threshold_model_rows)

    threshold_scenario_model_rows =
        fixture[:threshold_profile_scenario_model_summary_rows]
    @test length(threshold_scenario_model_rows) == 100
    @test sum(Int(row[:n_threshold_profile_rows])
        for row in threshold_scenario_model_rows) == 500
    @test all(row -> Int(row[:n_evaluable_rows]) ==
        Int(row[:n_threshold_profile_rows]), threshold_scenario_model_rows)
    @test all(row -> Bool(row[:threshold_profile_promoted]) == false,
        threshold_scenario_model_rows)

    @test length(fixture[:heldout_model_rank_rows]) == 125
    @test isempty(fixture[:diagnostic_failure_rows])

    blockers = fixture[:blocker_rows]
    @test length(blockers) == 5
    @test count(row -> Bool(row[:resolved]), blockers) == 3
    @test count(row -> Bool(row[:resolved]) == false, blockers) == 2

    decision = fixture[:decision_record]
    @test String(decision[:selected_decision]) ==
        "record_publication_grade_batch_results_review"
    @test Bool(decision[:batch_plan_recorded])
    @test Bool(decision[:all_125_units_executed])
    @test Bool(decision[:all_expected_job_artifacts_present])
    @test Bool(decision[:all_expected_job_artifacts_valid])
    @test Bool(decision[:diagnostics_observed])
    @test Bool(decision[:all_mcmc_diagnostic_gates_passed])
    @test Bool(decision[:threshold_profiles_recorded])
    @test Bool(decision[
        :threshold_profiles_inherited_change_at_least_one_flag])
    @test Bool(decision[:threshold_profiles_change_observed_batch_flag])
    @test Bool(decision[:threshold_profiles_promoted]) == false
    @test Bool(decision[:public_fit_metric_claim_allowed]) == false
    @test Bool(decision[:public_model_weight_claim_allowed]) == false
    @test Bool(decision[:sparse_superiority_claim_allowed]) == false
    @test String(decision[:required_followup]) ==
        "compare_publication_grade_batch_against_threshold_and_model_weight_policy"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:local_only])
    @test Bool(summary[:batch_only])
    @test Bool(summary[:local_artifacts_ignored_for_fixture]) == false
    @test Bool(summary[:batch_plan_present])
    @test Bool(summary[:batch_plan_schema_matches])
    @test Bool(summary[:batch_plan_passed])
    @test Bool(summary[:fit_metric_threshold_sensitivity_present])
    @test Bool(summary[:fit_metric_threshold_sensitivity_schema_matches])
    @test Bool(summary[:fit_metric_threshold_sensitivity_passed])
    @test Bool(summary[:result_review_rows_recorded])
    @test Bool(summary[:all_125_units_materialized])
    @test Bool(summary[:all_125_units_executed])
    @test Bool(summary[:missing_or_valid_job_artifacts])
    @test Bool(summary[:threshold_profiles_recorded])
    @test Bool(summary[:threshold_profile_job_rows_recorded])
    @test Bool(summary[:threshold_profile_model_summary_rows_recorded])
    @test Bool(summary[
        :threshold_profile_scenario_model_summary_rows_recorded])
    @test Bool(summary[
        :threshold_profiles_inherited_change_at_least_one_flag])
    @test Bool(summary[:threshold_profiles_change_observed_batch_flag])
    @test Bool(summary[:no_single_threshold_profile_promoted])
    @test Bool(summary[:all_expected_job_artifacts_present])
    @test Bool(summary[:all_expected_job_artifacts_valid])
    @test Bool(summary[:all_executed_diagnostics_observed])
    @test Bool(summary[:all_mcmc_diagnostic_gates_passed])
    @test Bool(summary[:no_public_fit_metric_claim])
    @test Bool(summary[:no_public_q_revision_claim])
    @test Bool(summary[:no_public_model_weight_claim])
    @test Bool(summary[:no_sparse_superiority_claim])
    @test Int(summary[:n_input_artifacts]) == 2
    @test Int(summary[:n_threshold_profiles]) == 4
    @test Int(summary[:n_threshold_profile_job_rows]) == 500
    @test Int(summary[:n_threshold_profile_model_summary_rows]) == 20
    @test Int(summary[:n_threshold_profile_scenario_model_summary_rows]) == 100
    @test Int(summary[:n_threshold_profile_evaluable_rows]) == 500
    @test Int(summary[:n_threshold_profile_passed_rows]) == 24
    @test Int(summary[:n_threshold_profile_flagged_rows]) == 476
    @test Int(summary[:n_batch_execution_job_rows]) == 125
    @test Int(summary[:n_mcmc_execution_jobs]) == 100
    @test Int(summary[:n_analytic_reference_jobs]) == 25
    @test Int(summary[:n_expected_job_artifacts]) == 375
    @test Int(summary[:n_present_job_artifacts]) == 375
    @test Int(summary[:n_valid_job_artifacts]) == 375
    @test Int(summary[:n_complete_artifact_units]) == 125
    @test Int(summary[:n_executed_units]) == 125
    @test Int(summary[:n_dry_run_units]) == 0
    @test Int(summary[:n_diagnostics_observed_units]) == 125
    @test Int(summary[:n_diagnostic_gate_passed_units]) == 125
    @test Int(summary[:n_heldout_scored_units]) == 125
    @test Int(summary[:n_model_summary_rows]) == 5
    @test Int(summary[:n_scenario_model_summary_rows]) == 25
    @test Int(summary[:n_heldout_model_rank_rows]) == 125
    @test Int(summary[:n_diagnostic_failure_rows]) == 0
    @test Int(summary[:n_blocker_rows]) == 5
    @test Int(summary[:n_blockers]) == 2
    @test Set(String(blocker) for blocker in
        summary[:remaining_public_blockers]) == Set([
            "external_construct_dataset_missing",
            "independent_public_scope_review_missing",
        ])
    @test String(summary[:recommendation]) ==
        "review_batch_fit_thresholds_and_model_weight_sensitivity_keep_claims_blocked"
    @test String(summary[:next_gate]) ==
        "compare_publication_grade_batch_against_threshold_and_model_weight_policy"
end

function check_mgmfrm_publication_grade_threshold_model_weight_policy_review_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_publication_grade_threshold_model_weight_policy_review.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) ==
        "publication_grade_threshold_model_weight_policy_review"
    @test String(fixture[:status]) ==
        "publication_grade_threshold_model_weight_policy_review_recorded"
    @test String(fixture[:decision]) ==
        "record_threshold_model_weight_policy_comparison_keep_claims_blocked"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:local_only])
    @test Bool(fixture[:publication_or_registration_action]) == false
    @test Bool(fixture[:public_fit_metric_claim]) == false
    @test Bool(fixture[:public_q_revision_claim]) == false
    @test Bool(fixture[:public_model_weight_claim]) == false
    @test Bool(fixture[:sparse_mgmfrm_superiority_claim]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) ==
        "mgmfrm_publication_grade_threshold_model_weight_policy_review_v1"
    @test String(protocol[:review_kind]) ==
        "local_publication_grade_threshold_model_weight_policy_review"
    @test String(protocol[:source_gate]) ==
        "compare_publication_grade_batch_against_threshold_and_model_weight_policy"
    @test String(protocol[:primary_prediction_target]) ==
        "heldout_observation_log_score"
    @test Bool(thresholds[:require_publication_grade_batch_results_review_passed])
    @test Bool(thresholds[:require_fit_metric_threshold_sensitivity_passed])
    @test Bool(thresholds[
        :require_prediction_target_and_model_weight_policy_passed])
    @test Bool(thresholds[:require_manual_public_scope_review_for_fit_passed])
    @test Bool(thresholds[:require_all_125_units_executed])
    @test Bool(thresholds[:require_all_mcmc_diagnostic_gates_passed])
    @test Bool(thresholds[:require_zero_diagnostic_failure_rows])
    @test Bool(thresholds[:require_threshold_profile_batch_rows_recorded])
    @test Bool(thresholds[
        :require_threshold_profiles_change_observed_batch_flag])
    @test Bool(thresholds[:require_no_single_threshold_profile_promoted])
    @test Bool(thresholds[
        :require_model_weight_policy_blocks_public_weight_claims])
    @test Bool(thresholds[
        :require_manual_scope_review_blocks_public_weight_claims])
    @test Bool(thresholds[:require_no_public_fit_metric_claim])
    @test Bool(thresholds[:require_no_public_model_weight_claim])
    @test Bool(thresholds[:require_no_sparse_superiority_claim])
    @test Bool(thresholds[:require_no_publication_or_registration_action])

    expected_inputs = Dict(
        "mgmfrm_publication_grade_refit_batch_results_review" =>
            "test/fixtures/mgmfrm_publication_grade_refit_batch_results_review.json",
        "mgmfrm_fit_metric_threshold_sensitivity" =>
            "test/fixtures/mgmfrm_fit_metric_threshold_sensitivity.json",
        "prediction_target_and_model_weight_policy" =>
            "test/fixtures/gmfrm_prediction_target_and_model_weight_policy.json",
        "mgmfrm_manual_public_scope_review_for_fit" =>
            "test/fixtures/mgmfrm_manual_public_scope_review_for_fit.json",
    )
    inputs = fixture[:input_artifacts]
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

    profile_rows = fixture[:threshold_profile_decision_rows]
    @test length(profile_rows) == 4
    @test sum(Int(row[:n_threshold_profile_rows]) for row in profile_rows) ==
        500
    @test sum(Int(row[:n_passed_rows]) for row in profile_rows) == 24
    @test sum(Int(row[:n_flagged_rows]) for row in profile_rows) == 476
    @test all(row -> Bool(row[:threshold_profile_promoted]) == false,
        profile_rows)
    exploratory = only(row for row in profile_rows
        if String(row[:profile]) == "exploratory_rasch_lenient")
    @test Int(exploratory[:n_passed_rows]) == 24
    @test Float64(exploratory[:pass_rate]) ≈ 0.192

    model_rows = fixture[:model_weight_policy_alignment_rows]
    @test length(model_rows) == 5
    @test String(model_rows[1][:model]) == "null_or_intercept_reference"
    @test Float64(model_rows[1][:local_diagnostic_weight]) ≈ 1.0
    scalar = only(row for row in model_rows
        if String(row[:model]) == "scalar_gmfrm_baseline")
    @test String(scalar[:policy_surface]) == "scalar_gmfrm_guarded_fit"
    @test Bool(scalar[:policy_local_weight_reporting_allowed])
    @test Float64(scalar[:local_diagnostic_weight]) < 1e-20
    sparse = only(row for row in model_rows
        if String(row[:model]) == "sparse_mgmfrm_current_q")
    @test Int(sparse[:n_threshold_profile_passed_rows]) == 1
    @test Int(sparse[:n_threshold_profile_flagged_rows]) == 99
    @test all(row -> Bool(row[:public_model_weight_claim_allowed]) == false,
        model_rows)
    @test all(row -> Bool(row[:public_fit_metric_claim_allowed]) == false,
        model_rows)
    @test all(row -> Bool(row[:sparse_superiority_claim_allowed]) == false,
        model_rows)

    claim_rows = fixture[:claim_gate_rows]
    @test length(claim_rows) == 5
    @test count(row -> String(row[:status]) == "blocked", claim_rows) == 4
    @test any(row -> String(row[:claim]) == "diagnostic_gate_claim" &&
        String(row[:status]) == "local_diagnostic_passed" &&
        Int(row[:n_diagnostic_failure_rows]) == 0, claim_rows)
    @test all(row -> Bool(row[:public_claim_allowed]) == false, claim_rows)

    blockers = fixture[:blocker_rows]
    @test length(blockers) == 5
    @test count(row -> Bool(row[:resolved]), blockers) == 3
    @test count(row -> !Bool(row[:resolved]), blockers) == 2

    decision = fixture[:decision_record]
    @test String(decision[:selected_decision]) ==
        "threshold_model_weight_policy_review_recorded_local_only"
    @test Bool(decision[:publication_grade_batch_completed])
    @test Bool(decision[:all_mcmc_diagnostic_gates_passed])
    @test Bool(decision[:threshold_profiles_promoted]) == false
    @test String(decision[:best_total_heldout_elpd_model]) ==
        "null_or_intercept_reference"
    @test Bool(decision[:local_diagnostic_weights_recorded])
    @test Bool(decision[:public_fit_metric_claim_allowed]) == false
    @test Bool(decision[:public_model_weight_claim_allowed]) == false
    @test Bool(decision[:sparse_superiority_claim_allowed]) == false
    @test String(decision[:required_followup]) ==
        "attach_external_construct_dataset_and_independent_public_scope_review"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:local_only])
    @test Bool(summary[:all_input_artifacts_present])
    @test Bool(summary[:all_expected_schemas])
    @test Bool(summary[:all_input_summaries_passed])
    @test Bool(summary[:publication_grade_batch_results_review_passed])
    @test Bool(summary[:fit_metric_threshold_sensitivity_passed])
    @test Bool(summary[:prediction_target_and_model_weight_policy_passed])
    @test Bool(summary[:manual_public_scope_review_for_fit_passed])
    @test Bool(summary[:all_125_units_executed])
    @test Bool(summary[:all_mcmc_diagnostic_gates_passed])
    @test Bool(summary[:zero_diagnostic_failures])
    @test Bool(summary[:threshold_profile_batch_rows_recorded])
    @test Bool(summary[:threshold_profiles_change_observed_batch_flag])
    @test Bool(summary[:no_single_threshold_profile_promoted])
    @test Bool(summary[:policy_blocks_public_model_weight_claims])
    @test Bool(summary[:manual_scope_review_blocks_public_model_weight_claims])
    @test Bool(summary[:no_public_fit_metric_claim])
    @test Bool(summary[:no_public_q_revision_claim])
    @test Bool(summary[:no_public_model_weight_claim])
    @test Bool(summary[:no_sparse_superiority_claim])
    @test Int(summary[:n_input_artifacts]) == 4
    @test Int(summary[:n_threshold_profile_decision_rows]) == 4
    @test Int(summary[:n_model_weight_policy_alignment_rows]) == 5
    @test Int(summary[:n_claim_gate_rows]) == 5
    @test Int(summary[:n_threshold_profile_job_rows]) == 500
    @test Int(summary[:n_threshold_profile_passed_rows]) == 24
    @test Int(summary[:n_threshold_profile_flagged_rows]) == 476
    @test Int(summary[:n_batch_execution_job_rows]) == 125
    @test Int(summary[:n_diagnostic_failure_rows]) == 0
    @test String(summary[:best_total_heldout_elpd_model]) ==
        "null_or_intercept_reference"
    @test Float64(summary[:null_or_intercept_reference_local_weight]) ≈ 1.0
    @test Float64(summary[:scalar_gmfrm_baseline_local_weight]) < 1e-20
    @test Int(summary[:n_blocker_rows]) == 5
    @test Int(summary[:n_blockers]) == 2
    @test Set(String(blocker) for blocker in
        summary[:remaining_public_blockers]) == Set([
            "external_construct_dataset_missing",
            "independent_public_scope_review_missing",
        ])
    @test String(summary[:recommendation]) ==
        "keep_public_threshold_model_weight_q_revision_and_sparse_claims_blocked"
    @test String(summary[:next_gate]) ==
        "attach_external_construct_dataset_and_independent_public_scope_review"
end

function check_mgmfrm_external_construct_dataset_and_independent_public_scope_review_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_external_construct_dataset_and_independent_public_scope_review.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) ==
        "external_construct_dataset_and_independent_public_scope_review"
    @test String(fixture[:status]) ==
        "external_construct_dataset_and_independent_public_scope_review_recorded"
    @test String(fixture[:decision]) ==
        "record_external_construct_and_independent_review_requirements_keep_claims_blocked"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:local_only])
    @test Bool(fixture[:publication_or_registration_action]) == false
    @test Bool(fixture[:external_construct_dataset_attached]) == false
    @test Bool(fixture[
        :external_construct_dataset_manifest_attached_and_valid]) == false
    @test Bool(fixture[
        :external_construct_dataset_file_integrity_verified]) == false
    @test Bool(fixture[:external_construct_validation_completed]) == false
    @test Bool(fixture[
        :external_construct_validation_evidence_attached_and_valid]) == false
    @test Bool(fixture[:external_construct_validation_evidence_passed]) ==
        false
    @test Bool(fixture[:independent_public_scope_review_completed]) == false
    @test Bool(fixture[
        :independent_public_scope_review_attached_and_valid]) == false
    @test Bool(fixture[:independent_public_scope_review_gate_passed]) == false
    @test Bool(fixture[:public_claim_release_decision_signed]) == false
    @test Bool(fixture[:public_claim_release_gate_passed]) == false
    @test Bool(fixture[:public_fit_metric_claim]) == false
    @test Bool(fixture[:public_q_revision_claim]) == false
    @test Bool(fixture[:public_model_weight_claim]) == false
    @test Bool(fixture[:sparse_mgmfrm_superiority_claim]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) ==
        "mgmfrm_external_construct_dataset_and_independent_public_scope_review_v1"
    @test String(protocol[:review_kind]) ==
        "local_external_construct_dataset_and_independent_public_scope_review"
    @test String(protocol[:source_gate]) ==
        "attach_external_construct_dataset_and_independent_public_scope_review"
    @test String(protocol[:decision_scope]) ==
        "requirements_before_public_mgmfrm_construct_model_weight_or_sparse_claims"
    @test Bool(thresholds[
        :require_threshold_model_weight_policy_review_passed])
    @test Bool(thresholds[
        :require_threshold_model_weight_policy_review_next_gate_matched])
    @test Bool(thresholds[
        :require_full_heldout_refit_or_construct_validation_review_passed])
    @test Bool(thresholds[
        :require_publication_grade_batch_results_review_passed])
    @test Bool(thresholds[:require_manual_public_scope_review_for_fit_passed])
    @test Bool(thresholds[:require_publication_grade_batch_completed])
    @test Bool(thresholds[:require_external_construct_requirements_recorded])
    @test Bool(thresholds[:require_external_attachment_schema_recorded])
    @test Bool(thresholds[:require_independent_review_schema_recorded])
    @test Bool(thresholds[:require_missing_external_dataset_manifest_recorded])
    @test Bool(thresholds[
        :require_missing_independent_review_manifest_recorded])
    @test Bool(thresholds[:require_no_public_fit_metric_claim])
    @test Bool(thresholds[:require_no_public_q_revision_claim])
    @test Bool(thresholds[:require_no_public_model_weight_claim])
    @test Bool(thresholds[:require_no_sparse_superiority_claim])
    @test Bool(thresholds[:require_no_publication_or_registration_action])
    @test Bool(thresholds[
        :require_pass_scope_contract_and_blocker_preservation_only])
    @test Bool(thresholds[
        :require_external_evidence_pass_implies_attached_and_valid])
    @test Bool(thresholds[
        :require_public_claim_release_gate_requires_zero_blockers])

    expected_inputs = Dict(
        "mgmfrm_publication_grade_threshold_model_weight_policy_review" =>
            "test/fixtures/mgmfrm_publication_grade_threshold_model_weight_policy_review.json",
        "mgmfrm_full_heldout_refit_or_construct_validation_review" =>
            "test/fixtures/mgmfrm_full_heldout_refit_or_construct_validation_review.json",
        "mgmfrm_publication_grade_refit_batch_results_review" =>
            "test/fixtures/mgmfrm_publication_grade_refit_batch_results_review.json",
        "mgmfrm_manual_public_scope_review_for_fit" =>
            "test/fixtures/mgmfrm_manual_public_scope_review_for_fit.json",
    )
    inputs = fixture[:input_artifacts]
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

    attachments = fixture[:attachment_records]
    @test length(attachments) == 2
    @test Set(String(row[:artifact]) for row in attachments) == Set([
        "external_construct_dataset_manifest",
        "independent_public_scope_review_manifest",
    ])
    @test all(row -> Bool(row[:attachment_required]), attachments)
    @test all(row -> Bool(row[:exists]) == false, attachments)
    @test all(row -> isnothing(row[:sha256]), attachments)
    @test all(row -> Bool(row[:schema_matches]) == false, attachments)
    @test all(row -> Bool(row[:artifact_contract_valid]) == false,
        attachments)
    @test all(row -> Bool(row[:attachment_and_valid]) == false,
        attachments)
    @test any(row -> String(row[:path]) ==
        "test/fixtures/external/mgmfrm_external_construct_dataset_manifest.json",
        attachments)
    @test any(row -> String(row[:path]) ==
        "test/fixtures/external/mgmfrm_independent_public_scope_review_manifest.json",
        attachments)

    external_rows = fixture[:external_construct_requirement_rows]
    @test length(external_rows) == 2
    @test Set(String(row[:scenario]) for row in external_rows) == Set([
        "missing_loading_revised_q",
        "weak_dimension_ambiguous",
    ])
    @test all(row -> String(row[:status]) ==
        "blocked_external_construct_dataset_missing", external_rows)
    @test all(row -> Bool(row[:external_construct_dataset_manifest_attached]) ==
        false, external_rows)
    @test all(row -> Bool(row[:external_construct_validation_completed]) ==
        false, external_rows)
    @test all(row -> Bool(row[:public_q_revision_claim_allowed]) == false,
        external_rows)
    @test all(row -> Bool(row[:public_model_superiority_claim_allowed]) == false,
        external_rows)

    attachment_requirements = fixture[:attachment_requirement_rows]
    @test length(attachment_requirements) == 12
    @test count(row -> String(row[:attachment]) ==
        "external_construct_dataset_manifest", attachment_requirements) == 6
    @test count(row -> String(row[:attachment]) ==
        "independent_public_scope_review_manifest",
        attachment_requirements) == 6
    @test any(row -> String(row[:requirement]) == "observation_crosswalk",
        attachment_requirements)
    @test any(row -> String(row[:requirement]) == "signed_public_scope_decision",
        attachment_requirements)

    independent_rows = fixture[:independent_review_requirement_rows]
    @test length(independent_rows) == 4
    @test Set(String(row[:review_surface]) for row in independent_rows) == Set([
        "fit_metric_claim",
        "model_weight_claim",
        "q_revision_claim",
        "sparse_superiority_claim",
    ])
    @test all(row -> Bool(row[:independent_review_completed]) == false,
        independent_rows)
    @test all(row -> Bool(row[:public_claim_allowed]) == false,
        independent_rows)

    claim_rows = fixture[:claim_release_rows]
    @test length(claim_rows) == 5
    @test count(row -> Bool(row[:external_construct_dataset_required]),
        claim_rows) == 4
    @test all(row -> Bool(row[:independent_public_scope_review_required]),
        claim_rows)
    @test all(row -> Bool(row[:public_claim_allowed]) == false, claim_rows)
    @test any(row -> String(row[:claim]) == "publication_grade_fit_metric_claim" &&
        String(row[:release_status]) ==
            "blocked_independent_public_scope_review_missing",
        claim_rows)

    blockers = fixture[:blocker_rows]
    @test length(blockers) == 5
    @test all(row -> Bool(row[:resolved]) == false, blockers)
    @test Set(String(row[:blocker]) for row in blockers) == Set([
        "external_construct_dataset_manifest_missing",
        "external_construct_validation_not_completed",
        "independent_public_scope_review_manifest_missing",
        "independent_public_scope_review_not_completed",
        "public_claim_release_decision_not_signed",
    ])

    evidence_rows = fixture[:evidence_link_rows]
    @test length(evidence_rows) == 5
    @test all(row -> Bool(row[:link_satisfied]), evidence_rows)
    @test any(row -> String(row[:evidence]) ==
        "threshold_model_weight_policy_review_next_gate", evidence_rows)
    @test any(row -> String(row[:evidence]) ==
        "external_attachment_manifests", evidence_rows)

    decision = fixture[:decision_record]
    @test String(decision[:selected_decision]) ==
        "external_construct_and_independent_review_gate_recorded"
    @test Bool(decision[:publication_grade_batch_completed])
    @test Bool(decision[:threshold_model_weight_policy_review_completed])
    @test Bool(decision[:local_manual_scope_review_satisfied])
    @test Bool(decision[:external_construct_dataset_attached]) == false
    @test Bool(decision[
        :external_construct_dataset_manifest_attached_and_valid]) == false
    @test Bool(decision[
        :external_construct_dataset_file_integrity_verified]) == false
    @test Bool(decision[:external_construct_validation_completed]) == false
    @test Bool(decision[
        :external_construct_validation_evidence_attached_and_valid]) == false
    @test Bool(decision[:external_construct_validation_evidence_passed]) ==
        false
    @test Bool(decision[:independent_public_scope_review_completed]) == false
    @test Bool(decision[
        :independent_public_scope_review_attached_and_valid]) == false
    @test Bool(decision[:independent_public_scope_review_gate_passed]) == false
    @test Bool(decision[:public_claim_release_decision_signed]) == false
    @test Bool(decision[:public_claim_release_gate_passed]) == false
    @test Bool(decision[:public_fit_metric_claim_allowed]) == false
    @test Bool(decision[:public_q_revision_claim_allowed]) == false
    @test Bool(decision[:public_model_weight_claim_allowed]) == false
    @test Bool(decision[:sparse_superiority_claim_allowed]) == false
    @test String(decision[:required_followup]) ==
        "provide_external_construct_dataset_manifest_and_independent_public_scope_review"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test String(summary[:pass_scope]) ==
        "contract_and_blocker_preservation_only"
    @test Bool(summary[:artifact_contract_valid])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:local_only])
    @test Bool(summary[:all_input_artifacts_present])
    @test Bool(summary[:all_expected_schemas])
    @test Bool(summary[:all_input_summaries_passed])
    @test Bool(summary[:threshold_model_weight_policy_review_passed])
    @test Bool(summary[:threshold_model_weight_policy_review_next_gate_matched])
    @test Bool(summary[
        :full_heldout_refit_or_construct_validation_review_passed])
    @test Bool(summary[:publication_grade_batch_results_review_passed])
    @test Bool(summary[:manual_public_scope_review_for_fit_passed])
    @test Bool(summary[:manual_public_scope_review_satisfied])
    @test Bool(summary[:publication_grade_batch_completed])
    @test Bool(summary[:all_mcmc_diagnostic_gates_passed])
    @test Bool(summary[:external_construct_requirements_recorded])
    @test Bool(summary[:external_attachment_schema_recorded])
    @test Bool(summary[:independent_review_schema_recorded])
    @test Bool(summary[:missing_external_dataset_manifest_recorded])
    @test Bool(summary[:missing_independent_review_manifest_recorded])
    @test Bool(summary[:external_construct_dataset_manifest_present]) == false
    @test Bool(summary[
        :independent_public_scope_review_manifest_present]) == false
    @test Bool(summary[:external_construct_dataset_attached]) == false
    @test Bool(summary[
        :external_construct_dataset_manifest_attached_and_valid]) == false
    @test Bool(summary[
        :external_construct_dataset_file_integrity_verified]) == false
    @test Bool(summary[:external_construct_validation_completed]) == false
    @test Bool(summary[
        :external_construct_validation_evidence_attached_and_valid]) == false
    @test Bool(summary[:external_construct_validation_evidence_passed]) ==
        false
    @test Bool(summary[:independent_public_scope_review_completed]) == false
    @test Bool(summary[
        :independent_public_scope_review_attached_and_valid]) == false
    @test Bool(summary[:independent_public_scope_review_gate_passed]) == false
    @test Bool(summary[:public_claim_release_decision_signed]) == false
    @test Bool(summary[:public_claim_release_gate_passed]) == false
    @test Bool(summary[:all_public_claims_blocked])
    @test Bool(summary[:no_public_fit_metric_claim])
    @test Bool(summary[:no_public_q_revision_claim])
    @test Bool(summary[:no_public_model_weight_claim])
    @test Bool(summary[:no_sparse_superiority_claim])
    @test Int(summary[:n_input_artifacts]) == 4
    @test Int(summary[:n_attachment_records]) == 2
    @test Int(summary[:n_external_construct_requirement_rows]) == 2
    @test Int(summary[:n_attachment_requirement_rows]) == 12
    @test Int(summary[:n_independent_review_requirement_rows]) == 4
    @test Int(summary[:n_claim_release_rows]) == 5
    @test Int(summary[:n_blocker_rows]) == 5
    @test Int(summary[:n_evidence_link_rows]) == 5
    @test Int(summary[:n_review_cells]) == 33
    @test Int(summary[:n_external_construct_validation_scenarios]) == 2
    @test Int(summary[:n_blockers]) == 5
    @test !Bool(summary[:external_construct_validation_evidence_passed]) ||
        Bool(summary[
            :external_construct_validation_evidence_attached_and_valid])
    @test !Bool(summary[:public_claim_release_gate_passed]) ||
        Int(summary[:n_blockers]) == 0
    @test Set(String(blocker) for blocker in
        summary[:remaining_public_blockers]) == Set([
            "external_construct_dataset_manifest_missing",
            "external_construct_validation_not_completed",
            "independent_public_scope_review_manifest_missing",
            "independent_public_scope_review_not_completed",
            "public_claim_release_decision_not_signed",
        ])
    @test String(summary[:recommendation]) ==
        "attach_external_construct_dataset_manifest_and_independent_review_before_public_claims"
    @test String(summary[:next_gate]) ==
        "provide_external_construct_dataset_manifest_and_independent_public_scope_review"
end

function check_mgmfrm_external_construct_attachment_intake_preflight_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_external_construct_attachment_intake_preflight.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) ==
        "external_construct_attachment_intake_preflight"
    @test String(fixture[:status]) ==
        "external_construct_attachment_intake_preflight_recorded"
    @test String(fixture[:decision]) ==
        "record_manifest_intake_preflight_keep_public_claims_blocked"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:local_only])
    @test Bool(fixture[:publication_or_registration_action]) == false
    @test Bool(fixture[:external_construct_dataset_manifest_valid]) == false
    @test Bool(fixture[:independent_public_scope_review_manifest_valid]) ==
        false
    @test Bool(fixture[
        :external_construct_dataset_manifest_attached_and_valid]) == false
    @test Bool(fixture[
        :external_construct_dataset_file_integrity_verified]) == false
    @test Bool(fixture[
        :external_construct_validation_evidence_attached_and_valid]) == false
    @test Bool(fixture[:external_construct_validation_evidence_passed]) ==
        false
    @test Bool(fixture[
        :independent_public_scope_review_attached_and_valid]) == false
    @test Bool(fixture[:independent_public_scope_review_gate_passed]) == false
    @test Bool(fixture[:public_claim_release_decision_signed]) == false
    @test Bool(fixture[:public_claim_release_gate_passed]) == false
    @test Bool(fixture[:public_fit_metric_claim]) == false
    @test Bool(fixture[:public_q_revision_claim]) == false
    @test Bool(fixture[:public_model_weight_claim]) == false
    @test Bool(fixture[:sparse_mgmfrm_superiority_claim]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) ==
        "mgmfrm_external_construct_attachment_intake_preflight_v1"
    @test String(protocol[:review_kind]) ==
        "local_attachment_intake_preflight"
    @test String(protocol[:source_gate]) ==
        "provide_external_construct_dataset_manifest_and_independent_public_scope_review"
    @test String(protocol[:decision_scope]) ==
        "preflight_before_external_construct_or_independent_review_attachment_is_accepted"
    @test Bool(thresholds[:require_external_construct_gate_review_passed])
    @test String(thresholds[
        :external_construct_gate_review_passed_semantics]) ==
        "artifact_contract_and_blocker_preservation_only"
    @test Bool(thresholds[
        :require_external_construct_gate_artifact_contract_valid])
    @test Bool(thresholds[:require_external_construct_gate_next_gate_matched])
    @test Bool(thresholds[:require_external_manifest_field_spec_recorded])
    @test Bool(thresholds[:require_independent_review_field_spec_recorded])
    @test Bool(thresholds[:require_missing_manifest_paths_recorded])
    @test Bool(thresholds[
        :require_no_public_claim_release_without_valid_manifests])
    @test Bool(thresholds[:require_no_publication_or_registration_action])
    @test Bool(thresholds[
        :require_external_evidence_pass_implies_attached_and_valid])
    @test Bool(thresholds[
        :require_public_claim_release_gate_requires_zero_blockers])

    inputs = fixture[:input_artifacts]
    @test length(inputs) == 1
    gate = only(inputs)
    @test String(gate[:artifact]) ==
        "mgmfrm_external_construct_dataset_and_independent_public_scope_review"
    @test String(gate[:path]) ==
        "test/fixtures/mgmfrm_external_construct_dataset_and_independent_public_scope_review.json"
    @test Bool(gate[:exists])
    @test Bool(gate[:schema_matches])
    @test Bool(gate[:summary_passed])
    @test String(gate[:pass_scope]) ==
        "contract_and_blocker_preservation_only"
    @test Bool(gate[:artifact_contract_valid])
    @test Bool(gate[
        :external_construct_dataset_manifest_attached_and_valid]) == false
    @test Bool(gate[
        :external_construct_dataset_file_integrity_verified]) == false
    @test Bool(gate[:external_construct_validation_evidence_passed]) == false
    @test Bool(gate[
        :independent_public_scope_review_attached_and_valid]) == false
    @test Bool(gate[:independent_public_scope_review_gate_passed]) == false
    @test Bool(gate[:public_claim_release_gate_passed]) == false
    @test String(gate[:expected_schema]) ==
        "bayesianmgmfrm.mgmfrm_external_construct_dataset_and_independent_public_scope_review.v1"
    @test String(gate[:schema]) ==
        "bayesianmgmfrm.mgmfrm_external_construct_dataset_and_independent_public_scope_review.v1"
    @test String(gate[:next_gate]) ==
        "provide_external_construct_dataset_manifest_and_independent_public_scope_review"
    @test Int(gate[:n_blockers]) == 5
    @test String(gate[:sha256]) ==
        file_sha256(joinpath(root, String(gate[:path])))

    manifests = fixture[:manifest_records]
    @test length(manifests) == 2
    @test Set(String(row[:artifact]) for row in manifests) == Set([
        "external_construct_dataset_manifest",
        "independent_public_scope_review_manifest",
    ])
    @test all(row -> Bool(row[:exists]) == false, manifests)
    @test all(row -> isnothing(row[:sha256]), manifests)
    @test all(row -> Bool(row[:schema_matches]) == false, manifests)
    @test all(row -> Bool(row[:all_required_fields_present]) == false,
        manifests)
    @test all(row -> Bool(row[:summary_passed]) == false, manifests)
    @test all(row -> Bool(row[:manifest_valid]) == false, manifests)
    @test all(row -> Bool(row[:artifact_contract_valid]) == false,
        manifests)
    @test all(row -> Bool(row[:attachment_and_valid]) == false, manifests)
    external_manifest = only(row for row in manifests
        if String(row[:artifact]) == "external_construct_dataset_manifest")
    independent_review = only(row for row in manifests
        if String(row[:artifact]) == "independent_public_scope_review_manifest")
    @test String(external_manifest[:path]) ==
        "test/fixtures/external/mgmfrm_external_construct_dataset_manifest.json"
    @test String(independent_review[:path]) ==
        "test/fixtures/external/mgmfrm_independent_public_scope_review_manifest.json"
    @test String(external_manifest[:expected_schema]) ==
        "bayesianmgmfrm.external_construct_dataset_manifest.v1"
    @test String(independent_review[:expected_schema]) ==
        "bayesianmgmfrm.independent_public_scope_review_manifest.v1"
    @test Int(external_manifest[:required_field_count]) == 13
    @test Int(independent_review[:required_field_count]) == 12
    @test Int(external_manifest[:present_required_field_count]) == 0
    @test Int(independent_review[:present_required_field_count]) == 0

    field_rows = fixture[:manifest_field_rows]
    @test length(field_rows) == 25
    @test count(row -> String(row[:attachment]) ==
        "external_construct_dataset_manifest", field_rows) == 13
    @test count(row -> String(row[:attachment]) ==
        "independent_public_scope_review_manifest", field_rows) == 12
    @test all(row -> Bool(row[:required]), field_rows)
    @test all(row -> Bool(row[:present]) == false, field_rows)
    @test all(row -> String(row[:status]) ==
        "pending_attachment_manifest_missing", field_rows)
    @test any(row -> String(row[:field]) == "observation_crosswalk" &&
        String(row[:purpose]) == "score_table_linkage", field_rows)
    @test any(row -> String(row[:field]) == "construct_anchor_records" &&
        String(row[:purpose]) == "construct_validity_anchor", field_rows)
    @test any(row -> String(row[:field]) == "claim_decision_table" &&
        String(row[:purpose]) == "claim_release_control", field_rows)
    @test any(row -> String(row[:field]) == "signature" &&
        String(row[:purpose]) == "review_signoff", field_rows)

    checks = fixture[:preflight_check_rows]
    @test length(checks) == 9
    @test all(row -> Bool(row[:public_claim_release_allowed]) == false,
        checks)
    @test any(row -> String(row[:check]) ==
        "external_construct_gate_review_passed" &&
        Bool(row[:satisfied]) && String(row[:status]) == "passed", checks)
    @test any(row -> String(row[:check]) ==
        "external_construct_gate_artifact_contract_valid" &&
        Bool(row[:satisfied]) && String(row[:status]) == "passed", checks)
    @test any(row -> String(row[:check]) ==
        "external_construct_gate_next_gate_matched" &&
        Bool(row[:satisfied]) && String(row[:status]) == "passed", checks)
    @test any(row -> String(row[:check]) ==
        "external_construct_dataset_manifest_valid" &&
        Bool(row[:satisfied]) == false &&
        String(row[:status]) == "blocked_missing_or_invalid_manifest", checks)
    @test any(row -> String(row[:check]) ==
        "independent_public_scope_review_manifest_valid" &&
        Bool(row[:satisfied]) == false &&
        String(row[:status]) == "blocked_missing_or_invalid_manifest", checks)
    @test any(row -> String(row[:check]) ==
        "external_construct_validation_not_claimed_without_manifest" &&
        Bool(row[:satisfied]) &&
        String(row[:status]) == "passed_blocker_retained", checks)
    @test any(row -> String(row[:check]) ==
        "independent_public_claim_release_not_signed_without_review" &&
        Bool(row[:satisfied]) &&
        String(row[:status]) == "passed_blocker_retained", checks)

    claim_rows = fixture[:claim_release_preflight_rows]
    @test length(claim_rows) == 5
    @test count(row -> Bool(row[
        :external_construct_dataset_manifest_required]), claim_rows) == 4
    @test all(row -> Bool(row[
        :independent_public_scope_review_manifest_required]), claim_rows)
    @test all(row -> Bool(row[
        :external_construct_dataset_manifest_valid]) == false, claim_rows)
    @test all(row -> Bool(row[
        :independent_public_scope_review_manifest_valid]) == false,
        claim_rows)
    @test all(row -> Bool(row[:public_claim_release_allowed]) == false,
        claim_rows)
    @test all(row -> String(row[:status]) ==
        "blocked_until_valid_external_inputs_and_independent_release_decision",
        claim_rows)
    @test any(row -> String(row[:claim]) ==
        "publication_grade_fit_metric_claim" &&
        Bool(row[:external_construct_dataset_manifest_required]) == false,
        claim_rows)

    blockers = fixture[:blocker_rows]
    @test length(blockers) == 5
    @test all(row -> Bool(row[:resolved]) == false, blockers)
    @test Set(String(row[:blocker]) for row in blockers) == Set([
        "external_construct_dataset_manifest_missing_or_invalid",
        "external_construct_dataset_file_integrity_unverified",
        "independent_public_scope_review_manifest_missing_or_invalid",
        "independent_public_scope_review_signature_missing",
        "public_claim_release_decision_not_signed",
    ])

    decision = fixture[:decision_record]
    @test String(decision[:selected_decision]) ==
        "external_attachment_intake_preflight_recorded"
    @test Bool(decision[:external_construct_dataset_manifest_valid]) == false
    @test Bool(decision[
        :independent_public_scope_review_manifest_valid]) == false
    @test Bool(decision[
        :external_construct_dataset_manifest_attached_and_valid]) == false
    @test Bool(decision[
        :external_construct_dataset_file_integrity_verified]) == false
    @test Bool(decision[
        :external_construct_validation_evidence_attached_and_valid]) == false
    @test Bool(decision[:external_construct_validation_evidence_passed]) ==
        false
    @test Bool(decision[
        :independent_public_scope_review_attached_and_valid]) == false
    @test Bool(decision[:independent_public_scope_review_gate_passed]) == false
    @test Bool(decision[:public_claim_release_decision_signed]) == false
    @test Bool(decision[:public_claim_release_gate_passed]) == false
    @test Bool(decision[:public_claim_release_allowed]) == false
    @test String(decision[:required_followup]) ==
        "attach_valid_external_construct_dataset_manifest_and_independent_public_scope_review_manifest"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test String(summary[:pass_scope]) ==
        "contract_and_blocker_preservation_only"
    @test Bool(summary[:artifact_contract_valid])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:local_only])
    @test Bool(summary[:external_construct_gate_review_passed])
    @test String(summary[
        :external_construct_gate_review_passed_semantics]) ==
        "artifact_contract_and_blocker_preservation_only"
    @test Bool(summary[:external_construct_gate_artifact_contract_valid])
    @test Bool(summary[:external_construct_gate_next_gate_matched])
    @test Bool(summary[:external_manifest_field_spec_recorded])
    @test Bool(summary[:independent_review_field_spec_recorded])
    @test Bool(summary[:missing_manifest_paths_recorded])
    @test Bool(summary[:external_construct_dataset_manifest_present]) ==
        false
    @test Bool(summary[
        :independent_public_scope_review_manifest_present]) == false
    @test Bool(summary[:external_construct_dataset_manifest_valid]) == false
    @test Bool(summary[
        :independent_public_scope_review_manifest_valid]) == false
    @test Bool(summary[
        :external_construct_dataset_manifest_attached_and_valid]) == false
    @test Bool(summary[
        :external_construct_dataset_file_integrity_verified]) == false
    @test Bool(summary[
        :external_construct_validation_evidence_attached_and_valid]) == false
    @test Bool(summary[:external_construct_validation_evidence_passed]) ==
        false
    @test Bool(summary[
        :independent_public_scope_review_attached_and_valid]) == false
    @test Bool(summary[:independent_public_scope_review_gate_passed]) == false
    @test Bool(summary[:public_claim_release_decision_signed]) == false
    @test Bool(summary[:public_claim_release_gate_passed]) == false
    @test Bool(summary[:no_public_claim_release])
    @test Bool(summary[:no_public_fit_metric_claim])
    @test Bool(summary[:no_public_q_revision_claim])
    @test Bool(summary[:no_public_model_weight_claim])
    @test Bool(summary[:no_sparse_superiority_claim])
    @test Int(summary[:n_input_artifacts]) == 1
    @test Int(summary[:n_manifest_records]) == 2
    @test Int(summary[:n_external_manifest_required_fields]) == 13
    @test Int(summary[:n_independent_review_required_fields]) == 12
    @test Int(summary[:n_manifest_field_rows]) == 25
    @test Int(summary[:n_preflight_check_rows]) == 9
    @test Int(summary[:n_claim_release_preflight_rows]) == 5
    @test Int(summary[:n_blocker_rows]) == 5
    @test Int(summary[:n_blockers]) == 5
    @test !Bool(summary[:external_construct_validation_evidence_passed]) ||
        Bool(summary[
            :external_construct_validation_evidence_attached_and_valid])
    @test !Bool(summary[:public_claim_release_gate_passed]) ||
        Int(summary[:n_blockers]) == 0
    @test Set(String(blocker) for blocker in
        summary[:remaining_public_blockers]) == Set([
            "external_construct_dataset_manifest_missing_or_invalid",
            "external_construct_dataset_file_integrity_unverified",
            "independent_public_scope_review_manifest_missing_or_invalid",
            "independent_public_scope_review_signature_missing",
            "public_claim_release_decision_not_signed",
        ])
    @test String(summary[:recommendation]) ==
        "attach_valid_external_manifests_before_public_claim_release"
    @test String(summary[:next_gate]) ==
        "attach_valid_external_construct_dataset_manifest_and_independent_public_scope_review_manifest"
end

function check_mgmfrm_external_construct_attachment_request_packet_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_external_construct_attachment_request_packet.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) ==
        "external_construct_attachment_request_packet"
    @test String(fixture[:status]) ==
        "external_construct_attachment_request_packet_recorded"
    @test String(fixture[:decision]) ==
        "record_external_attachment_request_packet_keep_public_claims_blocked"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:local_only])
    @test Bool(fixture[:publication_or_registration_action]) == false
    @test Bool(fixture[:external_evidence_created]) == false
    @test Bool(fixture[:external_manifest_files_written]) == false
    @test Bool(fixture[:independent_review_manifest_written]) == false
    @test Bool(fixture[
        :external_construct_dataset_manifest_attached_and_valid]) == false
    @test Bool(fixture[
        :external_construct_dataset_file_integrity_verified]) == false
    @test Bool(fixture[
        :external_construct_validation_evidence_attached_and_valid]) == false
    @test Bool(fixture[:external_construct_validation_evidence_passed]) ==
        false
    @test Bool(fixture[
        :independent_public_scope_review_attached_and_valid]) == false
    @test Bool(fixture[:independent_public_scope_review_gate_passed]) == false
    @test Bool(fixture[:public_claim_release_decision_signed]) == false
    @test Bool(fixture[:public_claim_release_gate_passed]) == false
    @test Bool(fixture[:public_fit_metric_claim]) == false
    @test Bool(fixture[:public_q_revision_claim]) == false
    @test Bool(fixture[:public_model_weight_claim]) == false
    @test Bool(fixture[:sparse_mgmfrm_superiority_claim]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) ==
        "mgmfrm_external_construct_attachment_request_packet_v1"
    @test String(protocol[:review_kind]) ==
        "local_external_attachment_request_packet"
    @test String(protocol[:source_gate]) ==
        "attach_valid_external_construct_dataset_manifest_and_independent_public_scope_review_manifest"
    @test String(protocol[:decision_scope]) ==
        "make_external_attachment_requirements_actionable_without_creating_external_evidence"
    @test Bool(thresholds[:require_preflight_passed])
    @test String(thresholds[:preflight_passed_semantics]) ==
        "artifact_contract_and_blocker_preservation_only"
    @test Bool(thresholds[:require_preflight_artifact_contract_valid])
    @test Bool(thresholds[:require_preflight_next_gate_matched])
    @test Bool(thresholds[:require_manifest_templates_recorded])
    @test Bool(thresholds[:require_attachment_checklist_recorded])
    @test Bool(thresholds[:require_rejection_conditions_recorded])
    @test Bool(thresholds[:require_no_placeholder_values_marked_valid])
    @test Bool(thresholds[:require_no_public_claim_release])
    @test Bool(thresholds[:require_no_publication_or_registration_action])
    @test Bool(thresholds[
        :require_external_evidence_pass_implies_attached_and_valid])
    @test Bool(thresholds[
        :require_public_claim_release_gate_requires_zero_blockers])

    inputs = fixture[:input_artifacts]
    @test length(inputs) == 1
    preflight = only(inputs)
    @test String(preflight[:artifact]) ==
        "mgmfrm_external_construct_attachment_intake_preflight"
    @test String(preflight[:path]) ==
        "test/fixtures/mgmfrm_external_construct_attachment_intake_preflight.json"
    @test Bool(preflight[:exists])
    @test Bool(preflight[:schema_matches])
    @test Bool(preflight[:summary_passed])
    @test String(preflight[:pass_scope]) ==
        "contract_and_blocker_preservation_only"
    @test Bool(preflight[:artifact_contract_valid])
    @test Bool(preflight[
        :external_construct_dataset_manifest_attached_and_valid]) == false
    @test Bool(preflight[
        :external_construct_dataset_file_integrity_verified]) == false
    @test Bool(preflight[
        :external_construct_validation_evidence_attached_and_valid]) == false
    @test Bool(preflight[:external_construct_validation_evidence_passed]) ==
        false
    @test Bool(preflight[
        :independent_public_scope_review_attached_and_valid]) == false
    @test Bool(preflight[:independent_public_scope_review_gate_passed]) ==
        false
    @test Bool(preflight[:public_claim_release_decision_signed]) == false
    @test Bool(preflight[:public_claim_release_gate_passed]) == false
    @test String(preflight[:sha256]) ==
        file_sha256(joinpath(root, String(preflight[:path])))
    @test Int(preflight[:n_manifest_field_rows]) == 25
    @test Int(preflight[:n_blockers]) == 5
    @test String(preflight[:next_gate]) ==
        "attach_valid_external_construct_dataset_manifest_and_independent_public_scope_review_manifest"

    templates = fixture[:manifest_template_records]
    @test length(templates) == 2
    @test Set(String(row[:artifact]) for row in templates) == Set([
        "external_construct_dataset_manifest",
        "independent_public_scope_review_manifest",
    ])
    @test all(row -> Bool(row[:template_recorded]), templates)
    @test all(row -> Bool(row[:user_supplied_required]), templates)
    @test all(row -> Bool(row[:source_preflight_manifest_valid]) == false,
        templates)
    @test all(row -> Bool(row[:evidence_attached]) == false, templates)
    @test all(row -> Bool(row[:placeholder_values_allowed]) == false,
        templates)
    @test all(row -> Bool(row[:public_claim_release_allowed]) == false,
        templates)
    external_template = only(row for row in templates
        if String(row[:artifact]) == "external_construct_dataset_manifest")
    independent_template = only(row for row in templates
        if String(row[:artifact]) == "independent_public_scope_review_manifest")
    @test String(external_template[:target_path]) ==
        "test/fixtures/external/mgmfrm_external_construct_dataset_manifest.json"
    @test String(independent_template[:target_path]) ==
        "test/fixtures/external/mgmfrm_independent_public_scope_review_manifest.json"
    @test String(external_template[:expected_schema]) ==
        "bayesianmgmfrm.external_construct_dataset_manifest.v1"
    @test String(independent_template[:expected_schema]) ==
        "bayesianmgmfrm.independent_public_scope_review_manifest.v1"
    @test Int(external_template[:required_field_count]) == 13
    @test Int(independent_template[:required_field_count]) == 12

    field_rows = fixture[:template_field_rows]
    @test length(field_rows) == 25
    @test count(row -> String(row[:attachment]) ==
        "external_construct_dataset_manifest", field_rows) == 13
    @test count(row -> String(row[:attachment]) ==
        "independent_public_scope_review_manifest", field_rows) == 12
    @test all(row -> Bool(row[:required]), field_rows)
    @test all(row -> Bool(row[:completed]) == false, field_rows)
    @test all(row -> Bool(row[:attachment_valid]) == false, field_rows)
    @test all(row -> Bool(row[:public_claim_release_allowed]) == false,
        field_rows)
    @test all(row -> String(row[:placeholder_policy]) ==
        "user_supplied_no_default", field_rows)
    @test all(row -> String(row[:source_preflight_status]) ==
        "pending_attachment_manifest_missing", field_rows)
    @test any(row -> String(row[:field]) == "file_records" &&
        String(row[:validation_rule]) ==
            "all_file_records_have_path_role_sha256", field_rows)
    @test any(row -> String(row[:field]) == "observation_crosswalk" &&
        String(row[:validation_rule]) ==
            "must_include_person_item_rater_score_and_fold_keys",
        field_rows)
    @test any(row -> String(row[:field]) ==
        "external_construct_dataset_manifest_sha256" &&
        String(row[:validation_rule]) ==
            "must_match_attached_external_manifest_sha256", field_rows)
    @test any(row -> String(row[:field]) == "signature" &&
        String(row[:validation_rule]) ==
            "must_include_dated_signature_or_audit_record", field_rows)

    checklist = fixture[:attachment_checklist_rows]
    @test length(checklist) == 10
    @test [Int(row[:step]) for row in checklist] == collect(1:10)
    @test all(row -> Bool(row[:required]), checklist)
    @test all(row -> Bool(row[:complete]) == false, checklist)
    @test all(row -> Bool(row[:blocks_public_claim_release]), checklist)
    @test any(row -> String(row[:action]) ==
        "hash_all_external_dataset_files", checklist)
    @test any(row -> String(row[:action]) ==
        "bind_independent_review_to_external_manifest_hash", checklist)
    @test any(row -> String(row[:action]) ==
        "rerun_attachment_preflight_and_public_scope_gate", checklist)

    rejections = fixture[:rejection_rows]
    @test length(rejections) == 6
    @test all(row -> Bool(row[:active]), rejections)
    @test all(row -> Bool(row[:reject_attachment]), rejections)
    @test all(row -> Bool(row[:public_claim_release_allowed]) == false,
        rejections)
    @test Set(String(row[:condition]) for row in rejections) == Set([
        "manifest_schema_mismatch",
        "required_field_missing_or_placeholder",
        "file_sha256_missing_or_unresolved",
        "observation_crosswalk_missing_required_keys",
        "independent_review_unsigned_or_conflicted",
        "claim_decision_allows_release_without_valid_external_attachment",
    ])

    claim_rows = fixture[:claim_release_request_rows]
    @test length(claim_rows) == 5
    @test count(row -> Bool(row[
        :external_construct_dataset_manifest_required]), claim_rows) == 4
    @test all(row -> Bool(row[
        :independent_public_scope_review_manifest_required]), claim_rows)
    @test all(row -> Bool(row[:attachment_packet_complete]) == false,
        claim_rows)
    @test all(row -> Bool(row[:valid_external_inputs_attached]) == false,
        claim_rows)
    @test all(row -> Bool(row[:public_claim_release_allowed]) == false,
        claim_rows)

    decision = fixture[:decision_record]
    @test String(decision[:selected_decision]) ==
        "external_attachment_request_packet_recorded"
    @test Bool(decision[:external_evidence_created]) == false
    @test Bool(decision[:placeholder_values_marked_valid]) == false
    @test Bool(decision[
        :external_construct_dataset_manifest_attached_and_valid]) == false
    @test Bool(decision[
        :external_construct_dataset_file_integrity_verified]) == false
    @test Bool(decision[
        :external_construct_validation_evidence_attached_and_valid]) == false
    @test Bool(decision[:external_construct_validation_evidence_passed]) ==
        false
    @test Bool(decision[
        :independent_public_scope_review_attached_and_valid]) == false
    @test Bool(decision[:independent_public_scope_review_gate_passed]) == false
    @test Bool(decision[:public_claim_release_decision_signed]) == false
    @test Bool(decision[:public_claim_release_gate_passed]) == false
    @test Bool(decision[:public_claim_release_allowed]) == false
    @test String(decision[:required_followup]) ==
        "attach_valid_external_construct_dataset_manifest_and_independent_public_scope_review_manifest"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test String(summary[:pass_scope]) ==
        "contract_and_blocker_preservation_only"
    @test Bool(summary[:artifact_contract_valid])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:local_only])
    @test Bool(summary[:preflight_passed])
    @test String(summary[:preflight_passed_semantics]) ==
        "artifact_contract_and_blocker_preservation_only"
    @test Bool(summary[:preflight_artifact_contract_valid])
    @test Bool(summary[:preflight_schema_matches])
    @test Bool(summary[:preflight_next_gate_matched])
    @test Bool(summary[:manifest_templates_recorded])
    @test Bool(summary[:attachment_checklist_recorded])
    @test Bool(summary[:rejection_conditions_recorded])
    @test Bool(summary[:no_placeholder_values_marked_valid])
    @test Bool(summary[:no_public_claim_release])
    @test Bool(summary[:external_evidence_created]) == false
    @test Bool(summary[:external_manifest_files_written]) == false
    @test Bool(summary[:independent_review_manifest_written]) == false
    @test Bool(summary[
        :external_construct_dataset_manifest_attached_and_valid]) == false
    @test Bool(summary[
        :external_construct_dataset_file_integrity_verified]) == false
    @test Bool(summary[
        :external_construct_validation_evidence_attached_and_valid]) == false
    @test Bool(summary[:external_construct_validation_evidence_passed]) ==
        false
    @test Bool(summary[
        :independent_public_scope_review_attached_and_valid]) == false
    @test Bool(summary[:independent_public_scope_review_gate_passed]) == false
    @test Bool(summary[:public_claim_release_decision_signed]) == false
    @test Bool(summary[:public_claim_release_gate_passed]) == false
    @test Int(summary[:n_input_artifacts]) == 1
    @test Int(summary[:n_manifest_template_records]) == 2
    @test Int(summary[:n_template_field_rows]) == 25
    @test Int(summary[:n_external_manifest_template_fields]) == 13
    @test Int(summary[:n_independent_review_template_fields]) == 12
    @test Int(summary[:n_attachment_checklist_rows]) == 10
    @test Int(summary[:n_rejection_rows]) == 6
    @test Int(summary[:n_claim_release_request_rows]) == 5
    @test Int(summary[:n_blockers]) == 6
    @test !Bool(summary[:external_construct_validation_evidence_passed]) ||
        Bool(summary[
            :external_construct_validation_evidence_attached_and_valid])
    @test !Bool(summary[:public_claim_release_gate_passed]) ||
        Int(summary[:n_blockers]) == 0
    @test Set(String(blocker) for blocker in
        summary[:remaining_public_blockers]) == Set([
            "manifest_schema_mismatch",
            "required_field_missing_or_placeholder",
            "file_sha256_missing_or_unresolved",
            "observation_crosswalk_missing_required_keys",
            "independent_review_unsigned_or_conflicted",
            "claim_decision_allows_release_without_valid_external_attachment",
        ])
    @test String(summary[:recommendation]) ==
        "send_attachment_request_packet_to_data_owner_and_independent_reviewer"
    @test String(summary[:next_gate]) ==
        "attach_valid_external_construct_dataset_manifest_and_independent_public_scope_review_manifest"
end
