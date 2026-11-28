function check_mgmfrm_publication_grade_refit_gate_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_publication_grade_refit_gate.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) == "publication_grade_refit_gate"
    @test String(fixture[:status]) == "publication_grade_refit_gate_defined"
    @test String(fixture[:decision]) ==
        "record_publication_grade_refit_diagnostics_and_pilot_scope"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])
    @test Bool(fixture[:local_only])
    @test Bool(fixture[:publication_grade_gate_defined])
    @test Bool(fixture[:publication_grade_pilot_executed]) == false
    @test Bool(fixture[:full_125_unit_publication_grade_batch_completed]) == false
    @test Bool(fixture[:publication_or_registration_action]) == false
    @test Bool(fixture[:public_fit_metric_claim]) == false
    @test Bool(fixture[:public_q_revision_claim]) == false
    @test Bool(fixture[:public_model_weight_claim]) == false
    @test Bool(fixture[:sparse_mgmfrm_superiority_claim]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    controls = protocol[:fit_controls]
    @test String(protocol[:protocol_id]) ==
        "mgmfrm_publication_grade_refit_gate_v1"
    @test String(protocol[:review_kind]) ==
        "local_publication_grade_refit_gate_definition"
    @test String(protocol[:gate_scope]) ==
        "publication_grade_refit_diagnostics_or_external_construct_dataset_review"
    @test String(protocol[:pilot_scope]) ==
        "one_scenario_one_fold_all_comparison_models"
    @test String(protocol[:pilot_scenario]) == "well_specified_current_q"
    @test Int(protocol[:pilot_fold]) == 1
    @test String(controls[:backend]) == "advancedhmc"
    @test String(controls[:sampler]) == "nuts"
    @test Int(controls[:chains]) == 4
    @test Int(controls[:warmup_per_chain]) == 500
    @test Int(controls[:draws_per_chain]) == 1000
    @test Float64(controls[:target_acceptance]) == 0.8
    @test Bool(thresholds[:require_input_artifacts_passed])
    @test Bool(thresholds[:require_anchor_scoring_completed])
    @test Bool(thresholds[:require_diagnostic_gate_rows_recorded])
    @test Bool(thresholds[:require_metric_profile_rows_recorded])
    @test Bool(thresholds[:require_pilot_scope_recorded])
    @test Bool(thresholds[:require_claim_rules_block_public_claims])
    @test Bool(thresholds[:require_publication_grade_pilot_not_yet_executed])
    @test Bool(thresholds[:require_full_batch_not_yet_executed])
    @test Bool(thresholds[:require_no_public_fit_metric_claim])
    @test Bool(thresholds[:require_no_public_q_revision_claim])
    @test Bool(thresholds[:require_no_public_model_weight_claim])
    @test Bool(thresholds[:require_no_sparse_superiority_claim])

    inputs = fixture[:input_artifacts]
    expected_inputs = Dict(
        "mgmfrm_full_heldout_mcmc_refit_execution_plan" =>
            "test/fixtures/mgmfrm_full_heldout_mcmc_refit_execution_plan.json",
        "mgmfrm_full_heldout_mcmc_refit_anchor_scoring" =>
            "test/fixtures/mgmfrm_full_heldout_mcmc_refit_anchor_scoring.json",
        "mgmfrm_validation_split_model_comparison_policy" =>
            "test/fixtures/mgmfrm_validation_split_model_comparison_policy.json",
        "mgmfrm_fit_threshold_q_heldout_linkage" =>
            "test/fixtures/mgmfrm_fit_threshold_q_heldout_linkage.json",
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

    diagnostics = fixture[:diagnostic_gate_rows]
    @test length(diagnostics) == 12
    @test Set(String(row[:diagnostic]) for row in diagnostics) == Set([
        "chains_min",
        "warmup_per_chain_min",
        "draws_per_chain_min",
        "rank_normalized_rhat_max",
        "ess_bulk_min",
        "ess_tail_min",
        "divergence_count_max",
        "max_treedepth_count_max",
        "ebfmi_min",
        "pointwise_loglikelihood_finite",
        "posterior_predictive_check_recorded",
        "expected_score_calibration_recorded",
    ])
    @test all(row -> Bool(row[:required_for_pilot]), diagnostics)
    @test all(row -> Bool(row[:required_for_full_batch]), diagnostics)
    @test all(row -> Bool(row[:public_claim_blocked_if_missing]),
        diagnostics)

    metrics = fixture[:metric_profile_rows]
    @test length(metrics) == 6
    @test Set(String(row[:metric]) for row in metrics) == Set([
        "heldout_elpd",
        "kfoldic",
        "posterior_infit_outfit",
        "posterior_predictive_category_use",
        "expected_score_mae_rmse_bias",
        "q_recovery_or_mismatch_flag",
    ])
    @test all(row -> Bool(row[:public_claim_allowed_from_pilot_alone]) == false,
        metrics)

    pilot_scope = fixture[:pilot_scope_rows]
    @test length(pilot_scope) == 3
    @test Set(String(row[:pilot_stage]) for row in pilot_scope) == Set([
        "single_cell_publication_grade_pilot",
        "scenario_coverage_expansion",
        "full_kfold_batch",
    ])
    @test String(pilot_scope[1][:scenario]) == "well_specified_current_q"
    @test Int(pilot_scope[1][:fold]) == 1
    @test Set(String(value) for value in pilot_scope[1][:models]) == Set([
        "scalar_gmfrm_baseline",
        "confirmatory_mgmfrm_current_q",
        "sparse_mgmfrm_current_q",
        "construct_reviewed_revised_q_mgmfrm",
        "null_or_intercept_reference",
    ])
    @test all(row -> Bool(row[:public_claim_allowed]) == false, pilot_scope)

    claims = fixture[:claim_rule_rows]
    @test length(claims) == 5
    @test all(row -> Bool(row[:pilot_sufficient]) == false, claims)
    @test all(row -> Bool(row[:public_claim_allowed]) == false, claims)

    blockers = fixture[:blocker_rows]
    @test length(blockers) == 4
    @test all(row -> Bool(row[:resolved]) == false, blockers)

    decision = fixture[:decision_record]
    @test String(decision[:selected_decision]) ==
        "record_publication_grade_refit_gate_before_running_heavy_pilot"
    @test Bool(decision[:gate_definition_recorded])
    @test Bool(decision[:anchor_scoring_completed])
    @test Bool(decision[:publication_grade_pilot_executed]) == false
    @test String(decision[:required_followup]) ==
        "publication_grade_refit_pilot_plan"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:all_input_artifacts_present])
    @test Bool(summary[:all_expected_schemas])
    @test Bool(summary[:all_input_summaries_passed])
    @test Bool(summary[:publication_grade_gate_defined])
    @test Bool(summary[:anchor_scoring_completed])
    @test Bool(summary[:diagnostic_gate_rows_recorded])
    @test Bool(summary[:metric_profile_rows_recorded])
    @test Bool(summary[:pilot_scope_recorded])
    @test Bool(summary[:claim_rules_block_public_claims])
    @test Bool(summary[:publication_grade_pilot_required])
    @test Bool(summary[:publication_grade_pilot_executed]) == false
    @test Bool(summary[:full_125_unit_publication_grade_batch_completed]) == false
    @test Bool(summary[:external_construct_dataset_still_required])
    @test Bool(summary[:no_public_fit_metric_claim])
    @test Bool(summary[:no_public_q_revision_claim])
    @test Bool(summary[:no_public_model_weight_claim])
    @test Bool(summary[:no_sparse_superiority_claim])
    @test Int(summary[:n_input_artifacts]) == 4
    @test Int(summary[:n_diagnostic_gate_rows]) == 12
    @test Int(summary[:n_metric_profile_rows]) == 6
    @test Int(summary[:n_pilot_scope_rows]) == 3
    @test Int(summary[:n_claim_rule_rows]) == 5
    @test Int(summary[:n_blocker_rows]) == 4
    @test Int(summary[:n_review_cells]) == 26
    @test Int(summary[:n_planned_full_execution_units]) == 125
    @test Int(summary[:n_anchor_scored_execution_units]) == 125
    @test Int(summary[:planned_chains_per_unit]) == 4
    @test Int(summary[:planned_draws_per_chain]) == 1000
    @test Int(summary[:planned_warmup_per_chain]) == 500
    @test String(summary[:recommendation]) ==
        "freeze_gate_and_prepare_single_cell_publication_grade_pilot"
    @test String(summary[:next_gate]) ==
        "publication_grade_refit_pilot_plan"
end

function check_mgmfrm_publication_grade_refit_pilot_plan_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_publication_grade_refit_pilot_plan.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) == "publication_grade_refit_pilot_plan"
    @test String(fixture[:status]) ==
        "publication_grade_refit_pilot_planned_not_executed"
    @test String(fixture[:decision]) ==
        "record_single_cell_publication_grade_refit_pilot_plan"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])
    @test Bool(fixture[:local_only])
    @test Bool(fixture[:pilot_only])
    @test Bool(fixture[:publication_grade_gate_defined])
    @test Bool(fixture[:publication_grade_pilot_plan_recorded])
    @test Bool(fixture[:publication_grade_pilot_executed]) == false
    @test Bool(fixture[:full_125_unit_publication_grade_batch_completed]) == false
    @test Bool(fixture[:publication_or_registration_action]) == false
    @test Bool(fixture[:public_fit_metric_claim]) == false
    @test Bool(fixture[:public_q_revision_claim]) == false
    @test Bool(fixture[:public_model_weight_claim]) == false
    @test Bool(fixture[:sparse_mgmfrm_superiority_claim]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    controls = protocol[:fit_controls]
    @test String(protocol[:protocol_id]) ==
        "mgmfrm_publication_grade_refit_pilot_plan_v1"
    @test String(protocol[:review_kind]) ==
        "local_publication_grade_refit_pilot_plan"
    @test String(protocol[:execution_scope]) ==
        "single_scenario_single_fold_all_comparison_models"
    @test String(protocol[:selected_scenario]) == "well_specified_current_q"
    @test Int(protocol[:selected_fold]) == 1
    @test Set(String(value) for value in protocol[:selected_models]) == Set([
        "scalar_gmfrm_baseline",
        "confirmatory_mgmfrm_current_q",
        "sparse_mgmfrm_current_q",
        "construct_reviewed_revised_q_mgmfrm",
        "null_or_intercept_reference",
    ])
    @test String(controls[:backend]) == "advancedhmc"
    @test String(controls[:sampler]) == "nuts"
    @test Int(controls[:chains]) == 4
    @test Int(controls[:warmup_per_chain]) == 500
    @test Int(controls[:draws_per_chain]) == 1000
    @test Int(controls[:seed_offset]) == 300000
    @test Bool(thresholds[:require_gate_passed])
    @test Bool(thresholds[:require_execution_plan_passed])
    @test Bool(thresholds[:require_anchor_scoring_passed])
    @test Bool(thresholds[:require_selected_units_recorded])
    @test Bool(thresholds[:require_all_five_models_selected])
    @test Bool(thresholds[:require_publication_grade_controls_match_gate])
    @test Bool(thresholds[:require_diagnostic_placeholders_recorded])
    @test Bool(thresholds[:require_pilot_execution_not_yet_run])
    @test Bool(thresholds[:require_full_batch_not_yet_run])
    @test Bool(thresholds[:require_no_public_fit_metric_claim])
    @test Bool(thresholds[:require_no_public_q_revision_claim])
    @test Bool(thresholds[:require_no_public_model_weight_claim])
    @test Bool(thresholds[:require_no_sparse_superiority_claim])

    inputs = fixture[:input_artifacts]
    expected_inputs = Dict(
        "mgmfrm_publication_grade_refit_gate" =>
            "test/fixtures/mgmfrm_publication_grade_refit_gate.json",
        "mgmfrm_full_heldout_mcmc_refit_execution_plan" =>
            "test/fixtures/mgmfrm_full_heldout_mcmc_refit_execution_plan.json",
        "mgmfrm_full_heldout_mcmc_refit_anchor_scoring" =>
            "test/fixtures/mgmfrm_full_heldout_mcmc_refit_anchor_scoring.json",
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

    selected = fixture[:selected_pilot_unit_rows]
    @test length(selected) == 5
    @test Set(String(row[:model]) for row in selected) == Set([
        "scalar_gmfrm_baseline",
        "confirmatory_mgmfrm_current_q",
        "sparse_mgmfrm_current_q",
        "construct_reviewed_revised_q_mgmfrm",
        "null_or_intercept_reference",
    ])
    @test all(row -> String(row[:scenario]) == "well_specified_current_q",
        selected)
    @test all(row -> Int(row[:fold]) == 1, selected)
    @test count(row -> Bool(row[:mcmc_refit_required]), selected) == 4
    @test count(row -> Bool(row[:analytic_reference_scored]), selected) == 1
    @test all(row -> Bool(row[:publication_grade_pilot_executed]) == false,
        selected)
    @test all(row -> Bool(row[:public_claim_allowed]) == false, selected)
    @test all(row -> Int(row[:n_train_observations]) == 32, selected)
    @test all(row -> Int(row[:n_heldout_observations]) == 8, selected)

    controls_rows = fixture[:execution_control_rows]
    @test length(controls_rows) == 5
    @test count(row -> Bool(row[:mcmc_refit_required]), controls_rows) == 4
    @test all(row -> !Bool(row[:mcmc_refit_required]) ||
            (String(row[:backend]) == "advancedhmc" &&
             String(row[:sampler]) == "nuts" &&
             Int(row[:chains]) == 4 &&
             Int(row[:warmup_per_chain]) == 500 &&
             Int(row[:draws_per_chain]) == 1000),
        controls_rows)
    @test all(row -> Bool(row[:public_claim_allowed]) == false, controls_rows)

    diagnostics = fixture[:diagnostic_placeholder_rows]
    @test length(diagnostics) == 60
    @test all(row -> Bool(row[:observed]) == false, diagnostics)
    @test all(row -> Bool(row[:passed]) == false, diagnostics)
    @test all(row -> Bool(row[:blocks_public_claim]), diagnostics)
    for row in selected
        id = String(row[:execution_unit_id])
        @test count(diag -> String(diag[:execution_unit_id]) == id,
            diagnostics) == 12
    end

    blockers = fixture[:blocker_rows]
    @test length(blockers) == 5
    @test all(row -> Bool(row[:resolved]) == false, blockers)

    decision = fixture[:decision_record]
    @test String(decision[:selected_decision]) ==
        "record_publication_grade_single_cell_pilot_before_heavy_refit"
    @test Bool(decision[:publication_grade_gate_defined])
    @test Bool(decision[:publication_grade_pilot_plan_recorded])
    @test Bool(decision[:publication_grade_pilot_executed]) == false
    @test String(decision[:required_followup]) ==
        "execute_publication_grade_refit_pilot_or_attach_external_construct_dataset"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:all_input_artifacts_present])
    @test Bool(summary[:all_expected_schemas])
    @test Bool(summary[:all_input_summaries_passed])
    @test Bool(summary[:gate_passed])
    @test Bool(summary[:execution_plan_passed])
    @test Bool(summary[:anchor_scoring_passed])
    @test Bool(summary[:publication_grade_gate_defined])
    @test Bool(summary[:publication_grade_pilot_plan_recorded])
    @test Bool(summary[:selected_units_recorded])
    @test Bool(summary[:all_five_models_selected])
    @test String(summary[:selected_scenario]) == "well_specified_current_q"
    @test Int(summary[:selected_fold]) == 1
    @test Bool(summary[:publication_grade_controls_match_gate])
    @test Bool(summary[:diagnostic_placeholders_recorded])
    @test Bool(summary[:publication_grade_pilot_executed]) == false
    @test Bool(summary[:full_125_unit_publication_grade_batch_completed]) == false
    @test Bool(summary[:external_construct_dataset_still_required])
    @test Bool(summary[:no_public_fit_metric_claim])
    @test Bool(summary[:no_public_q_revision_claim])
    @test Bool(summary[:no_public_model_weight_claim])
    @test Bool(summary[:no_sparse_superiority_claim])
    @test Int(summary[:n_input_artifacts]) == 3
    @test Int(summary[:n_selected_pilot_unit_rows]) == 5
    @test Int(summary[:n_mcmc_pilot_units]) == 4
    @test Int(summary[:n_analytic_reference_units]) == 1
    @test Int(summary[:n_execution_control_rows]) == 5
    @test Int(summary[:n_diagnostic_placeholder_rows]) == 60
    @test Int(summary[:n_blocker_rows]) == 5
    @test Int(summary[:n_review_cells]) == 70
    @test Int(summary[:planned_chains]) == 16
    @test Int(summary[:planned_posterior_draws]) == 16000
    @test Int(summary[:planned_warmup_iterations]) == 8000
    @test String(summary[:recommendation]) ==
        "run_single_cell_publication_grade_pilot_then_compare_to_smoke_anchor_scoring"
    @test String(summary[:next_gate]) ==
        "execute_publication_grade_refit_pilot_or_attach_external_construct_dataset"
end

function check_mgmfrm_publication_grade_refit_pilot_execution_harness_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_publication_grade_refit_pilot_execution_harness.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) ==
        "publication_grade_refit_pilot_execution_harness"
    @test String(fixture[:status]) ==
        "publication_grade_refit_pilot_execution_harness_recorded"
    @test String(fixture[:decision]) ==
        "record_publication_grade_refit_pilot_execution_harness"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])
    @test Bool(fixture[:harness_ready])
    @test Bool(fixture[:execution_ready])
    @test Bool(fixture[:local_only])
    @test Bool(fixture[:pilot_only])
    @test Bool(fixture[:publication_or_registration_action]) == false
    @test Bool(fixture[:publication_grade_gate_defined])
    @test Bool(fixture[:publication_grade_pilot_plan_recorded])
    @test Bool(fixture[:publication_grade_pilot_execution_harness_recorded])
    @test Bool(fixture[:publication_grade_pilot_runner_materialized])
    @test Bool(fixture[:publication_grade_pilot_executed]) == false
    @test Bool(fixture[:full_125_unit_publication_grade_batch_completed]) ==
        false
    @test Bool(fixture[:public_fit_metric_claim]) == false
    @test Bool(fixture[:public_q_revision_claim]) == false
    @test Bool(fixture[:public_model_weight_claim]) == false
    @test Bool(fixture[:sparse_mgmfrm_superiority_claim]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    controls = protocol[:fit_controls]
    @test String(protocol[:protocol_id]) ==
        "mgmfrm_publication_grade_refit_pilot_execution_harness_v1"
    @test String(protocol[:review_kind]) ==
        "local_publication_grade_refit_pilot_execution_harness"
    @test String(protocol[:execution_scope]) ==
        "single_scenario_single_fold_publication_grade_execution_harness"
    @test String(protocol[:selected_scenario]) == "well_specified_current_q"
    @test Int(protocol[:selected_fold]) == 1
    @test String(protocol[:runner_script]) ==
        "scripts/run_mgmfrm_publication_grade_refit_job.jl"
    @test String(controls[:backend]) == "advancedhmc"
    @test String(controls[:sampler]) == "nuts"
    @test Int(controls[:chains]) == 4
    @test Int(controls[:warmup_per_chain]) == 500
    @test Int(controls[:draws_per_chain]) == 1000
    @test Float64(controls[:target_acceptance]) == 0.8
    @test Bool(thresholds[:require_pilot_plan_passed])
    @test Bool(thresholds[:require_gate_passed])
    @test Bool(thresholds[:require_fold1_scoring_passed])
    @test Bool(thresholds[:require_anchor_scoring_passed])
    @test Bool(thresholds[:require_fit_threshold_linkage_passed])
    @test Bool(thresholds[:require_execution_jobs_materialized])
    @test Bool(thresholds[:require_execution_commands_recorded])
    @test Bool(thresholds[:require_runner_state_recorded])
    @test Bool(thresholds[:require_result_artifact_targets_recorded])
    @test Bool(thresholds[:require_diagnostic_capture_manifest_recorded])
    @test Bool(thresholds[:require_comparison_hooks_recorded])
    @test Bool(thresholds[:require_publication_grade_pilot_not_yet_executed])
    @test Bool(thresholds[:require_full_batch_not_yet_executed])
    @test Bool(thresholds[:require_no_public_fit_metric_claim])
    @test Bool(thresholds[:require_no_public_q_revision_claim])
    @test Bool(thresholds[:require_no_public_model_weight_claim])
    @test Bool(thresholds[:require_no_sparse_superiority_claim])

    inputs = fixture[:input_artifacts]
    expected_inputs = Dict(
        "mgmfrm_publication_grade_refit_pilot_plan" =>
            "test/fixtures/mgmfrm_publication_grade_refit_pilot_plan.json",
        "mgmfrm_publication_grade_refit_gate" =>
            "test/fixtures/mgmfrm_publication_grade_refit_gate.json",
        "mgmfrm_full_heldout_mcmc_refit_fold1_scoring" =>
            "test/fixtures/mgmfrm_full_heldout_mcmc_refit_fold1_scoring.json",
        "mgmfrm_full_heldout_mcmc_refit_anchor_scoring" =>
            "test/fixtures/mgmfrm_full_heldout_mcmc_refit_anchor_scoring.json",
        "mgmfrm_fit_threshold_q_heldout_linkage" =>
            "test/fixtures/mgmfrm_fit_threshold_q_heldout_linkage.json",
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

    jobs = fixture[:execution_job_rows]
    @test length(jobs) == 5
    @test count(row -> Bool(row[:mcmc_refit_required]), jobs) == 4
    @test count(row -> Bool(row[:analytic_reference_scored]), jobs) == 1
    @test all(row -> String(row[:scenario]) == "well_specified_current_q",
        jobs)
    @test all(row -> Int(row[:fold]) == 1, jobs)
    @test all(row -> String(row[:execution_status]) == "ready_not_executed",
        jobs)
    @test all(row -> Bool(row[:publication_grade_pilot_executed]) == false,
        jobs)
    @test all(row -> Bool(row[:diagnostics_observed]) == false, jobs)
    @test all(row -> Bool(row[:public_claim_allowed]) == false, jobs)
    @test all(row -> !Bool(row[:mcmc_refit_required]) ||
            (String(row[:backend]) == "advancedhmc" &&
             String(row[:sampler]) == "nuts" &&
             Int(row[:chains]) == 4 &&
             Int(row[:warmup_per_chain]) == 500 &&
             Int(row[:draws_per_chain]) == 1000),
        jobs)

    commands = fixture[:execution_command_rows]
    @test length(commands) == 5
    @test all(row -> Bool(row[:runner_script_required]), commands)
    @test all(row -> Bool(row[:runner_script_exists]), commands)
    @test all(row -> String(row[:command_status]) == "ready_not_executed",
        commands)
    @test all(row -> Bool(row[:execute_now]) == false, commands)
    @test all(row -> Bool(row[:local_only]), commands)
    @test all(row -> Bool(row[:publication_or_registration_action]) == false,
        commands)
    @test all(row -> !occursin("git push", String(row[:command])), commands)

    targets = fixture[:result_artifact_target_rows]
    @test length(targets) == 15
    @test Set(String(row[:artifact_target]) for row in targets) == Set([
        "fit_result",
        "diagnostic_summary",
        "heldout_score_summary",
    ])
    @test all(row -> Bool(row[:exists]) == false, targets)
    @test all(row -> Bool(row[:required_before_public_claim]), targets)
    @test all(row -> Bool(row[:public_claim_allowed]) == false, targets)

    diagnostics = fixture[:diagnostic_capture_rows]
    @test length(diagnostics) == 60
    @test all(row -> Bool(row[:observed]) == false, diagnostics)
    @test all(row -> Bool(row[:passed]) == false, diagnostics)
    @test all(row -> Bool(row[:blocks_public_claim]), diagnostics)
    for row in jobs
        id = String(row[:execution_unit_id])
        @test count(diag -> String(diag[:execution_unit_id]) == id,
            diagnostics) == 12
    end

    comparisons = fixture[:comparison_hook_rows]
    @test length(comparisons) == 5
    @test Set(String(row[:hook]) for row in comparisons) == Set([
        "publication_grade_vs_fold1_smoke_heldout_elpd",
        "publication_grade_vs_anchor_scores",
        "diagnostic_gate_pass_fail_snapshot",
        "fit_threshold_q_heldout_linkage_review",
        "parameter_absorption_and_q_mismatch_review",
    ])
    @test all(row -> String(row[:comparison_status]) == "planned_not_executed",
        comparisons)
    @test all(row -> Bool(row[:public_claim_allowed]) == false, comparisons)

    blockers = fixture[:blocker_rows]
    @test length(blockers) == 7
    @test count(row -> Bool(row[:resolved]), blockers) == 1
    runner_blocker = only(row for row in blockers
        if String(row[:blocker]) == "publication_grade_runner_not_materialized")
    @test Bool(runner_blocker[:resolved])

    decision = fixture[:decision_record]
    @test String(decision[:selected_decision]) ==
        "record_execution_harness_runner_materialized_before_heavy_refit"
    @test Bool(decision[:publication_grade_gate_defined])
    @test Bool(decision[:publication_grade_pilot_plan_recorded])
    @test Bool(decision[:publication_grade_pilot_execution_harness_recorded])
    @test Bool(decision[:publication_grade_pilot_runner_materialized])
    @test Bool(decision[:publication_grade_pilot_executed]) == false
    @test String(decision[:required_followup]) ==
        "execute_publication_grade_refit_pilot_or_attach_external_construct_dataset"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:all_input_artifacts_present])
    @test Bool(summary[:all_expected_schemas])
    @test Bool(summary[:all_input_summaries_passed])
    @test Bool(summary[:pilot_plan_passed])
    @test Bool(summary[:gate_passed])
    @test Bool(summary[:fold1_scoring_passed])
    @test Bool(summary[:anchor_scoring_passed])
    @test Bool(summary[:fit_threshold_linkage_passed])
    @test Bool(summary[:publication_grade_pilot_execution_harness_recorded])
    @test Bool(summary[:publication_grade_pilot_runner_materialized])
    @test Bool(summary[:execution_jobs_materialized])
    @test Bool(summary[:execution_commands_recorded])
    @test Bool(summary[:runner_state_recorded])
    @test Bool(summary[:result_artifact_targets_recorded])
    @test Bool(summary[:diagnostic_capture_manifest_recorded])
    @test Bool(summary[:comparison_hooks_recorded])
    @test Bool(summary[:publication_grade_pilot_executed]) == false
    @test Bool(summary[:full_125_unit_publication_grade_batch_completed]) ==
        false
    @test Bool(summary[:external_construct_dataset_still_required])
    @test Bool(summary[:no_public_fit_metric_claim])
    @test Bool(summary[:no_public_q_revision_claim])
    @test Bool(summary[:no_public_model_weight_claim])
    @test Bool(summary[:no_sparse_superiority_claim])
    @test Int(summary[:n_input_artifacts]) == 5
    @test Int(summary[:n_execution_job_rows]) == 5
    @test Int(summary[:n_mcmc_execution_jobs]) == 4
    @test Int(summary[:n_analytic_reference_jobs]) == 1
    @test Int(summary[:n_execution_command_rows]) == 5
    @test Int(summary[:n_result_artifact_target_rows]) == 15
    @test Int(summary[:n_diagnostic_capture_rows]) == 60
    @test Int(summary[:n_comparison_hook_rows]) == 5
    @test Int(summary[:n_blocker_rows]) == 7
    @test Int(summary[:n_review_cells]) == 90
    @test Int(summary[:planned_chains]) == 16
    @test Int(summary[:planned_posterior_draws]) == 16000
    @test Int(summary[:planned_warmup_iterations]) == 8000
    @test Set(String(blocker) for blocker in
        summary[:remaining_public_blockers]) == Set([
            "publication_grade_pilot_not_executed",
            "diagnostics_not_observed",
            "fit_metric_thresholds_not_reestimated_under_publication_grade_draws",
            "full_125_unit_publication_grade_batch_not_executed",
            "external_construct_dataset_missing",
            "independent_public_scope_review_missing",
        ])
    @test String(summary[:recommendation]) ==
        "execute_single_cell_publication_grade_pilot_or_attach_external_dataset"
    @test String(summary[:next_gate]) ==
        "execute_publication_grade_refit_pilot_or_attach_external_construct_dataset"
end

function check_mgmfrm_publication_grade_refit_pilot_results_review_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_publication_grade_refit_pilot_results_review.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) ==
        "publication_grade_refit_pilot_results_review"
    @test String(fixture[:status]) ==
        "publication_grade_refit_pilot_results_review_recorded"
    @test String(fixture[:decision]) ==
        "record_publication_grade_refit_pilot_results_state"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])
    @test Bool(fixture[:local_only])
    @test Bool(fixture[:pilot_only])
    @test Bool(fixture[:local_artifacts_ignored_for_fixture])
    @test Bool(fixture[:publication_or_registration_action]) == false
    @test Bool(fixture[:publication_grade_gate_defined])
    @test Bool(fixture[:publication_grade_pilot_plan_recorded])
    @test Bool(fixture[:publication_grade_pilot_execution_harness_recorded])
    @test Bool(fixture[:publication_grade_pilot_results_review_recorded])
    @test Bool(fixture[:publication_grade_pilot_executed]) == false
    @test Bool(fixture[:full_125_unit_publication_grade_batch_completed]) ==
        false
    @test Bool(fixture[:public_fit_metric_claim]) == false
    @test Bool(fixture[:public_q_revision_claim]) == false
    @test Bool(fixture[:public_model_weight_claim]) == false
    @test Bool(fixture[:sparse_mgmfrm_superiority_claim]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) ==
        "mgmfrm_publication_grade_refit_pilot_results_review_v1"
    @test String(protocol[:review_kind]) ==
        "local_publication_grade_refit_pilot_results_review"
    @test String(protocol[:source_harness]) ==
        "mgmfrm_publication_grade_refit_pilot_execution_harness"
    @test Int(protocol[:expected_execution_units]) == 5
    @test Int(protocol[:expected_mcmc_execution_units]) == 4
    @test Int(protocol[:expected_analytic_reference_units]) == 1
    @test Int(protocol[:expected_artifacts_per_unit]) == 3
    @test Bool(thresholds[:require_harness_passed])
    @test Bool(thresholds[:require_result_artifact_rows_recorded])
    @test Bool(thresholds[:require_missing_or_valid_job_artifacts])
    @test Bool(thresholds[:require_heldout_rank_rows_when_scores_complete])
    @test Bool(thresholds[:require_diagnostic_failure_rows_when_observed])
    @test Bool(thresholds[:require_descriptive_only_model_rankings])
    @test Bool(thresholds[:require_all_public_claims_blocked])
    @test Bool(thresholds[:require_no_publication_or_registration_action])

    inputs = fixture[:input_artifacts]
    @test length(inputs) == 1
    harness = only(inputs)
    @test String(harness[:artifact]) ==
        "mgmfrm_publication_grade_refit_pilot_execution_harness"
    @test String(harness[:path]) ==
        "test/fixtures/mgmfrm_publication_grade_refit_pilot_execution_harness.json"
    @test Bool(harness[:exists])
    @test Bool(harness[:schema_matches])
    @test Bool(harness[:summary_passed])
    @test String(harness[:sha256]) ==
        file_sha256(joinpath(root, String(harness[:path])))

    rows = fixture[:job_result_review_rows]
    @test length(rows) == 5
    @test Set(String(row[:model]) for row in rows) == Set([
        "scalar_gmfrm_baseline",
        "confirmatory_mgmfrm_current_q",
        "sparse_mgmfrm_current_q",
        "construct_reviewed_revised_q_mgmfrm",
        "null_or_intercept_reference",
    ])
    @test all(row -> String(row[:scenario]) == "well_specified_current_q",
        rows)
    @test all(row -> Int(row[:fold]) == 1, rows)
    @test count(row -> Bool(row[:mcmc_refit_required]), rows) == 4
    @test count(row -> Bool(row[:analytic_reference_scored]), rows) == 1
    @test all(row -> Bool(row[:artifacts_complete]) == false, rows)
    @test all(row -> Bool(row[:execution_observed]) == false, rows)
    @test all(row -> Bool(row[:diagnostics_observed]) == false, rows)
    @test all(row -> Bool(row[:diagnostic_gate_passed]) == false, rows)
    @test all(row -> Bool(row[:heldout_predictive_score_computed]) == false,
        rows)
    @test all(row -> Bool(row[:public_claim_allowed]) == false, rows)
    for row in rows
        for key in (:result_artifact, :diagnostic_artifact, :heldout_artifact)
            artifact = row[key]
            @test Bool(artifact[:exists]) == false
            @test String(artifact[:status]) == "missing"
            @test Bool(artifact[:schema_matches]) == false
            @test Bool(artifact[:summary_passed]) == false
        end
        @test endswith(String(row[:result_artifact][:path]), "_result.json")
        @test endswith(String(row[:diagnostic_artifact][:path]),
            "_diagnostics.json")
        @test endswith(String(row[:heldout_artifact][:path]),
            "_heldout_score.json")
    end
    @test length(fixture[:heldout_model_rank_rows]) == 0
    @test length(fixture[:diagnostic_failure_rows]) == 0

    blockers = fixture[:blocker_rows]
    @test length(blockers) == 7
    @test all(row -> Bool(row[:resolved]) == false, blockers)

    decision = fixture[:decision_record]
    @test String(decision[:selected_decision]) ==
        "record_publication_grade_pilot_results_review"
    @test Bool(decision[
        :publication_grade_pilot_execution_harness_recorded])
    @test Bool(decision[:publication_grade_pilot_executed]) == false
    @test Bool(decision[:diagnostics_observed]) == false
    @test Bool(decision[:heldout_scores_cover_selected_units]) == false
    @test Bool(decision[:sampler_diagnostic_failure_detected]) == false
    @test Bool(decision[:heldout_rank_review_recorded])
    @test Bool(decision[:diagnostic_failure_review_recorded])
    @test String(decision[:required_followup]) ==
        "execute_remaining_publication_grade_refit_pilot_jobs_or_attach_external_construct_dataset"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:local_only])
    @test Bool(summary[:pilot_only])
    @test Bool(summary[:local_artifacts_ignored_for_fixture])
    @test Bool(summary[:harness_present])
    @test Bool(summary[:harness_schema_matches])
    @test Bool(summary[:harness_passed])
    @test Bool(summary[:result_review_rows_recorded])
    @test Bool(summary[:missing_or_valid_job_artifacts])
    @test Bool(summary[:partial_execution_detected]) == false
    @test Bool(summary[:publication_grade_pilot_executed]) == false
    @test Bool(summary[:all_five_pilot_jobs_executed]) == false
    @test Bool(summary[:all_expected_job_artifacts_present]) == false
    @test Bool(summary[:all_executed_diagnostics_observed]) == false
    @test Bool(summary[:all_mcmc_diagnostic_gates_passed]) == false
    @test Bool(summary[:sampler_diagnostic_failure_detected]) == false
    @test Bool(summary[:heldout_scores_cover_selected_units]) == false
    @test Bool(summary[:heldout_rank_review_recorded])
    @test Bool(summary[:diagnostic_failure_review_recorded])
    @test Bool(summary[:external_construct_dataset_still_required])
    @test Bool(summary[:no_public_fit_metric_claim])
    @test Bool(summary[:no_public_q_revision_claim])
    @test Bool(summary[:no_public_model_weight_claim])
    @test Bool(summary[:no_sparse_superiority_claim])
    @test Int(summary[:n_input_artifacts]) == 1
    @test Int(summary[:n_expected_execution_units]) == 5
    @test Int(summary[:n_mcmc_execution_units]) == 4
    @test Int(summary[:n_analytic_reference_units]) == 1
    @test Int(summary[:n_job_result_review_rows]) == 5
    @test Int(summary[:n_heldout_model_rank_rows]) == 0
    @test Int(summary[:n_diagnostic_failure_rows]) == 0
    @test Int(summary[:n_mcmc_diagnostic_failure_rows]) == 0
    @test Int(summary[:n_expected_job_artifacts]) == 15
    @test Int(summary[:n_present_job_artifacts]) == 0
    @test Int(summary[:n_valid_job_artifacts]) == 0
    @test Int(summary[:n_complete_execution_units]) == 0
    @test Int(summary[:n_executed_execution_units]) == 0
    @test Int(summary[:n_diagnostics_observed_units]) == 0
    @test Int(summary[:n_diagnostic_gate_passed_units]) == 0
    @test Int(summary[:n_heldout_score_units]) == 0
    @test Int(summary[:n_blocker_rows]) == 7
    @test Int(summary[:n_blockers]) == 7
    @test summary[:best_heldout_model] === nothing
    @test summary[:best_mcmc_heldout_model] === nothing
    @test summary[:best_diagnostic_passed_mcmc_model] === nothing
    @test Bool(summary[:reference_best_heldout_score]) == false
    @test summary[:mcmc_model_beat_reference_on_heldout_elpd] === nothing
    @test Set(String(blocker) for blocker in
        summary[:remaining_public_blockers]) == Set([
            "publication_grade_pilot_not_executed",
            "publication_grade_results_artifacts_missing",
            "diagnostics_not_observed",
            "fit_metric_thresholds_not_reestimated_under_publication_grade_draws",
            "full_125_unit_publication_grade_batch_not_executed",
            "external_construct_dataset_missing",
            "independent_public_scope_review_missing",
        ])
    @test String(summary[:recommendation]) ==
        "execute_missing_publication_grade_pilot_jobs_keep_claims_blocked"
    @test String(summary[:next_gate]) ==
        "execute_remaining_publication_grade_refit_pilot_jobs_or_attach_external_construct_dataset"
end

function check_mgmfrm_publication_grade_refit_brms_like_single_cell_execution_review_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_publication_grade_refit_brms_like_single_cell_execution_review.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) ==
        "publication_grade_refit_brms_like_single_cell_execution_review"
    @test String(fixture[:status]) ==
        "publication_grade_refit_brms_like_single_cell_executed"
    @test String(fixture[:decision]) ==
        "record_brms_like_single_cell_revised_q_publication_grade_execution"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:local_only])
    @test Bool(fixture[:pilot_only])
    @test Bool(fixture[:single_cell_only])
    @test Bool(fixture[:local_artifacts_required_for_generation])
    @test Bool(fixture[:publication_or_registration_action]) == false
    @test Bool(fixture[:publication_grade_gate_defined])
    @test Bool(fixture[:publication_grade_pilot_plan_recorded])
    @test Bool(fixture[:publication_grade_pilot_execution_harness_recorded])
    @test Bool(fixture[:publication_grade_brms_like_single_cell_executed])
    @test Bool(fixture[:full_publication_grade_pilot_executed]) == false
    @test Bool(fixture[:full_125_unit_publication_grade_batch_completed]) ==
        false
    @test Bool(fixture[:public_fit_metric_claim]) == false
    @test Bool(fixture[:public_q_revision_claim]) == false
    @test Bool(fixture[:public_model_weight_claim]) == false
    @test Bool(fixture[:sparse_mgmfrm_superiority_claim]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) ==
        "mgmfrm_publication_grade_refit_brms_like_single_cell_execution_review_v1"
    @test String(protocol[:review_kind]) ==
        "local_brms_like_single_cell_publication_grade_execution_review"
    @test String(protocol[:source_runner]) ==
        "run_mgmfrm_publication_grade_refit_job"
    @test String(protocol[:execution_unit_id]) ==
        "well_specified_current_q__construct_reviewed_revised_q_mgmfrm__fold1"
    @test Int(thresholds[:require_chains]) == 4
    @test Int(thresholds[:require_warmup_per_chain]) == 1000
    @test Int(thresholds[:require_draws_per_chain]) == 1000
    @test Int(thresholds[:require_total_retained_draws]) == 4000
    @test Float64(thresholds[:require_rank_normalized_rhat_max]) == 1.01
    @test Float64(thresholds[:require_ess_min]) == 400.0
    @test Int(thresholds[:require_divergence_count_max]) == 0
    @test Int(thresholds[:require_max_treedepth_count_max]) == 0
    @test Float64(thresholds[:require_ebfmi_min]) == 0.3
    @test Bool(thresholds[:require_public_claims_blocked])

    inputs = fixture[:input_artifacts]
    @test length(inputs) == 3
    @test Set(String(row[:kind]) for row in inputs) ==
        Set(["result", "diagnostics", "heldout"])
    @test all(row -> Bool(row[:exists]), inputs)
    @test all(row -> Bool(row[:schema_matches]), inputs)
    @test all(row -> Bool(row[:summary_passed]), inputs)
    @test all(row -> Bool(row[:dry_run]) == false, inputs)
    @test all(row -> Bool(row[:public_claim_allowed]) == false, inputs)
    @test only(row for row in inputs if String(row[:kind]) == "result")[
        :executed] == true
    @test all(row -> startswith(String(row[:path]),
        "artifacts/publication_grade_refit_pilot_brms_like/"), inputs)

    execution = fixture[:execution_summary]
    @test String(execution[:execution_unit_id]) ==
        "well_specified_current_q__construct_reviewed_revised_q_mgmfrm__fold1"
    @test String(execution[:scenario]) == "well_specified_current_q"
    @test String(execution[:model]) ==
        "construct_reviewed_revised_q_mgmfrm"
    @test Int(execution[:fold]) == 1
    @test String(execution[:model_family]) == "mgmfrm"
    @test String(execution[:q_profile]) == "construct_reviewed_q_6_item_2d"
    @test Int(execution[:fit_seed]) == 2026375701
    @test String(execution[:backend]) == "advancedhmc"
    @test String(execution[:sampler]) == "nuts"
    @test Float64(execution[:target_acceptance]) == 0.8
    @test Int(execution[:chains]) == 4
    @test Int(execution[:warmup_per_chain]) == 1000
    @test Int(execution[:draws_per_chain]) == 1000
    @test Int(execution[:total_retained_draws]) == 4000
    @test Int(execution[:n_train_observations]) == 32
    @test Int(execution[:n_heldout_observations]) == 8
    @test Int(execution[:n_dimensions]) == 2
    @test Int(execution[:n_items]) == 6
    @test Bool(execution[:q_validation_passed])
    @test Int(execution[:n_q_validation_warnings]) == 1
    @test Bool(execution[:fit_succeeded])
    @test Bool(execution[:scoring_succeeded])
    @test String(execution[:returned_type]) == "MGMFRMFit"

    sampler = fixture[:sampler_summary]
    @test String(sampler[:diagnostic_flag]) == "ok"
    @test Bool(sampler[:diagnostic_passed])
    @test Float64(sampler[:max_rhat]) <= 1.01
    @test Float64(sampler[:min_ess]) >= 400.0
    @test Float64(sampler[:e_bfmi]) >= 0.3
    @test Int(sampler[:n_divergences]) == 0
    @test Int(sampler[:n_max_treedepth]) == 0
    @test Int(sampler[:n_nonfinite_logdensity]) == 0
    @test Int(sampler[:n_failed_direct_constraints]) == 0
    @test String(sampler[:diagnostic_surface_flag]) == "ok"
    @test Bool(sampler[:diagnostic_surface_passed])

    heldout = fixture[:heldout_summary]
    @test Bool(heldout[:heldout_predictive_score_computed])
    @test Int(heldout[:n_heldout_pointwise_rows]) == 8
    @test isfinite(Float64(heldout[:heldout_elpd]))
    @test isfinite(Float64(heldout[:heldout_mean_log_predictive_density]))
    @test Float64(heldout[:heldout_expected_score_mae]) >= 0.0
    @test Float64(heldout[:heldout_expected_score_rmse]) >= 0.0
    @test Bool(heldout[:all_pointwise_scores_finite])

    rows = fixture[:diagnostic_review_rows]
    @test length(rows) == 12
    @test all(row -> Bool(row[:applicable]), rows)
    @test all(row -> Bool(row[:observed]), rows)
    @test all(row -> Bool(row[:passed]), rows)
    @test all(row -> Bool(row[:public_claim_allowed]) == false, rows)
    @test Set(String(row[:diagnostic]) for row in rows) == Set([
        "chains_min",
        "warmup_per_chain_min",
        "draws_per_chain_min",
        "rank_normalized_rhat_max",
        "ess_bulk_min",
        "ess_tail_min",
        "divergence_count_max",
        "max_treedepth_count_max",
        "ebfmi_min",
        "pointwise_loglikelihood_finite",
        "posterior_predictive_check_recorded",
        "expected_score_calibration_recorded",
    ])
    @test only(row for row in rows if String(row[:diagnostic]) ==
        "warmup_per_chain_min")[:value] == 1000

    blockers = fixture[:blocker_rows]
    @test length(blockers) == 6
    @test count(row -> Bool(row[:resolved]), blockers) == 1
    @test Set(String(row[:blocker]) for row in blockers
        if !Bool(row[:resolved])) == Set([
        "remaining_publication_grade_pilot_jobs_not_executed",
        "fit_metric_thresholds_not_reestimated_under_publication_grade_draws",
        "full_125_unit_publication_grade_batch_not_executed",
        "external_construct_dataset_missing",
        "independent_public_scope_review_missing",
    ])

    decision = fixture[:decision_record]
    @test String(decision[:selected_decision]) ==
        "record_brms_like_single_cell_execution_keep_claims_blocked"
    @test Bool(decision[:brms_like_budget_observed])
    @test Bool(decision[:single_cell_execution_passed])
    @test Bool(decision[:full_publication_grade_pilot_executed]) == false
    @test Bool(decision[:full_publication_grade_batch_completed]) == false
    @test Bool(decision[:public_fit_metric_claim_allowed]) == false
    @test Bool(decision[:public_q_revision_claim_allowed]) == false
    @test Bool(decision[:public_model_weight_claim_allowed]) == false
    @test Bool(decision[:sparse_mgmfrm_superiority_claim_allowed]) == false
    @test String(decision[:required_followup]) ==
        "execute_remaining_publication_grade_refit_pilot_jobs_or_attach_external_construct_dataset"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:local_only])
    @test Bool(summary[:pilot_only])
    @test Bool(summary[:single_cell_only])
    @test Bool(summary[:all_artifacts_valid])
    @test Bool(summary[:brms_like_budget_observed])
    @test Bool(summary[:publication_grade_brms_like_single_cell_executed])
    @test Bool(summary[:full_publication_grade_pilot_executed]) == false
    @test Bool(summary[:full_125_unit_publication_grade_batch_completed]) ==
        false
    @test Bool(summary[:fit_succeeded])
    @test Bool(summary[:scoring_succeeded])
    @test Bool(summary[:diagnostic_gate_passed])
    @test Bool(summary[:all_diagnostics_passed])
    @test Bool(summary[:all_public_claims_blocked])
    @test Bool(summary[:q_validation_passed])
    @test Int(summary[:n_q_validation_warnings]) == 1
    @test Float64(summary[:max_rhat]) <= 1.01
    @test Float64(summary[:min_ess]) >= 400.0
    @test Float64(summary[:e_bfmi]) >= 0.3
    @test Int(summary[:n_divergences]) == 0
    @test Int(summary[:n_max_treedepth]) == 0
    @test Int(summary[:n_input_artifacts]) == 3
    @test Int(summary[:n_diagnostic_review_rows]) == 12
    @test Int(summary[:n_failed_diagnostic_review_rows]) == 0
    @test Int(summary[:n_blocker_rows]) == 6
    @test Int(summary[:n_resolved_blockers]) == 1
    @test Int(summary[:n_blockers]) == 5
    @test Set(String(blocker) for blocker in
        summary[:remaining_public_blockers]) == Set([
        "remaining_publication_grade_pilot_jobs_not_executed",
        "fit_metric_thresholds_not_reestimated_under_publication_grade_draws",
        "full_125_unit_publication_grade_batch_not_executed",
        "external_construct_dataset_missing",
        "independent_public_scope_review_missing",
    ])
    @test String(summary[:recommendation]) ==
        "execute_remaining_publication_grade_pilot_jobs_keep_claims_blocked"
    @test String(summary[:next_gate]) ==
        "execute_remaining_publication_grade_refit_pilot_jobs_or_attach_external_construct_dataset"
end

function check_mgmfrm_publication_grade_refit_brms_like_pilot_execution_review_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_publication_grade_refit_brms_like_pilot_execution_review.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) ==
        "publication_grade_refit_brms_like_pilot_execution_review"
    @test String(fixture[:status]) ==
        "publication_grade_refit_brms_like_pilot_executed"
    @test String(fixture[:decision]) ==
        "record_brms_like_publication_grade_pilot_execution"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:local_only])
    @test Bool(fixture[:pilot_only])
    @test Bool(fixture[:local_artifacts_required_for_generation])
    @test Bool(fixture[:publication_or_registration_action]) == false
    @test Bool(fixture[:publication_grade_brms_like_pilot_executed])
    @test Bool(fixture[:full_125_unit_publication_grade_batch_completed]) ==
        false
    @test Bool(fixture[:public_fit_metric_claim]) == false
    @test Bool(fixture[:public_q_revision_claim]) == false
    @test Bool(fixture[:public_model_weight_claim]) == false
    @test Bool(fixture[:sparse_mgmfrm_superiority_claim]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) ==
        "mgmfrm_publication_grade_refit_brms_like_pilot_execution_review_v1"
    @test String(protocol[:review_kind]) ==
        "local_brms_like_publication_grade_pilot_execution_review"
    @test Int(protocol[:expected_execution_units]) == 5
    @test Int(protocol[:expected_mcmc_execution_units]) == 4
    @test Int(protocol[:expected_analytic_reference_units]) == 1
    @test Int(protocol[:expected_artifacts_per_unit]) == 3
    @test Int(thresholds[:require_chains]) == 4
    @test Int(thresholds[:require_warmup_per_chain]) == 1000
    @test Int(thresholds[:require_draws_per_chain]) == 1000
    @test Int(thresholds[:require_total_retained_draws]) == 4000
    @test Float64(thresholds[:require_rank_normalized_rhat_max]) == 1.01
    @test Float64(thresholds[:require_ess_min]) == 400.0
    @test Int(thresholds[:require_divergence_count_max]) == 0
    @test Int(thresholds[:require_max_treedepth_count_max]) == 0
    @test Float64(thresholds[:require_ebfmi_min]) == 0.3
    @test Bool(thresholds[:require_public_claims_blocked])

    inputs = fixture[:input_artifacts]
    @test length(inputs) == 15
    @test count(row -> String(row[:kind]) == "result", inputs) == 5
    @test count(row -> String(row[:kind]) == "diagnostics", inputs) == 5
    @test count(row -> String(row[:kind]) == "heldout", inputs) == 5
    @test all(row -> Bool(row[:exists]), inputs)
    @test all(row -> Bool(row[:schema_matches]), inputs)
    @test all(row -> Bool(row[:summary_passed]), inputs)
    @test all(row -> Bool(row[:dry_run]) == false, inputs)
    @test all(row -> Bool(row[:public_claim_allowed]) == false, inputs)

    rows = fixture[:job_review_rows]
    @test length(rows) == 5
    @test Set(String(row[:model]) for row in rows) == Set([
        "scalar_gmfrm_baseline",
        "confirmatory_mgmfrm_current_q",
        "sparse_mgmfrm_current_q",
        "construct_reviewed_revised_q_mgmfrm",
        "null_or_intercept_reference",
    ])
    @test all(row -> Bool(row[:executed]), rows)
    @test all(row -> Bool(row[:dry_run]) == false, rows)
    @test all(row -> Bool(row[:artifacts_complete]), rows)
    @test count(row -> Bool(row[:mcmc_refit_required]), rows) == 4
    @test count(row -> Bool(row[:analytic_reference_scored]), rows) == 1
    @test count(row -> Bool(row[:diagnostic_gate_passed]) &&
        Bool(row[:mcmc_refit_required]), rows) == 3
    @test all(row -> Bool(row[:public_claim_allowed]) == false, rows)

    mcmc_rows = [row for row in rows if Bool(row[:mcmc_refit_required])]
    @test all(row -> Int(row[:chains]) == 4, mcmc_rows)
    @test all(row -> Int(row[:warmup_per_chain]) >= 1000, mcmc_rows)
    @test all(row -> Int(row[:draws_per_chain]) == 1000, mcmc_rows)
    @test all(row -> Int(row[:total_retained_draws]) == 4000, mcmc_rows)
    @test all(row -> Float64(row[:max_rhat]) <= 1.01, mcmc_rows)
    @test all(row -> Float64(row[:min_ess]) >= 400.0, mcmc_rows)
    @test all(row -> Float64(row[:e_bfmi]) >= 0.3, mcmc_rows)
    @test count(row -> Int(row[:n_divergences]) > 0, mcmc_rows) == 1
    scalar = only(row for row in rows
        if String(row[:model]) == "scalar_gmfrm_baseline")
    @test Bool(scalar[:diagnostic_gate_passed]) == false
    @test String(scalar[:sampler_flag]) == "sampler_warning"
    @test Int(scalar[:n_divergences]) == 2
    @test Float64(scalar[:heldout_elpd]) ≈ -10.163856267085027

    ranks = fixture[:heldout_model_rank_rows]
    @test length(ranks) == 5
    @test String(first(ranks)[:model]) == "null_or_intercept_reference"
    @test Int(first(ranks)[:rank]) == 1
    @test Bool(first(ranks)[:analytic_reference_scored])
    @test String(ranks[2][:model]) == "scalar_gmfrm_baseline"
    @test Bool(ranks[2][:diagnostic_gate_passed]) == false
    @test String(ranks[3][:model]) == "sparse_mgmfrm_current_q"
    @test Bool(ranks[3][:diagnostic_gate_passed])
    @test all(row -> Bool(row[:descriptive_only]), ranks)
    @test all(row -> Bool(row[:public_model_weight_claim_allowed]) == false,
        ranks)

    failures = fixture[:diagnostic_failure_rows]
    @test length(failures) == 1
    failure = only(failures)
    @test String(failure[:model]) == "scalar_gmfrm_baseline"
    @test String(failure[:diagnostic]) == "divergence_count_max"
    @test Int(failure[:value]) == 2
    @test Int(failure[:threshold]) == 0
    @test Bool(failure[:public_claim_allowed]) == false

    blockers = fixture[:blocker_rows]
    @test length(blockers) == 9
    @test count(row -> Bool(row[:resolved]), blockers) == 3
    @test Set(String(row[:blocker]) for row in blockers
        if !Bool(row[:resolved])) == Set([
        "fit_metric_thresholds_not_reestimated_under_publication_grade_draws",
        "sampler_diagnostic_failure_detected",
        "null_reference_best_heldout_score",
        "full_125_unit_publication_grade_batch_not_executed",
        "external_construct_dataset_missing",
        "independent_public_scope_review_missing",
    ])

    decision = fixture[:decision_record]
    @test String(decision[:selected_decision]) ==
        "record_full_brms_like_pilot_execution_keep_claims_blocked"
    @test Bool(decision[:publication_grade_brms_like_pilot_executed])
    @test Bool(decision[:all_mcmc_diagnostic_gates_passed]) == false
    @test Bool(decision[:sampler_diagnostic_failure_detected])
    @test Bool(decision[:reference_best_heldout_score])
    @test Bool(decision[:mcmc_model_beat_reference_on_heldout_elpd]) == false
    @test Bool(decision[:public_fit_metric_claim_allowed]) == false
    @test Bool(decision[:public_q_revision_claim_allowed]) == false
    @test Bool(decision[:public_model_weight_claim_allowed]) == false
    @test Bool(decision[:sparse_mgmfrm_superiority_claim_allowed]) == false
    @test String(decision[:required_followup]) ==
        "review_scalar_sampler_divergences_before_batch_expansion"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:local_only])
    @test Bool(summary[:pilot_only])
    @test Bool(summary[:all_artifacts_valid])
    @test Bool(summary[:publication_grade_brms_like_pilot_executed])
    @test Bool(summary[:all_five_pilot_jobs_executed])
    @test Bool(summary[:all_expected_job_artifacts_present])
    @test Bool(summary[:all_executed_diagnostics_observed])
    @test Bool(summary[:all_mcmc_diagnostic_gates_passed]) == false
    @test Bool(summary[:sampler_diagnostic_failure_detected])
    @test Bool(summary[:reference_best_heldout_score])
    @test Bool(summary[:mcmc_model_beat_reference_on_heldout_elpd]) == false
    @test Bool(summary[:no_public_claim_allowed])
    @test Int(summary[:n_input_artifacts]) == 15
    @test Int(summary[:n_expected_execution_units]) == 5
    @test Int(summary[:n_mcmc_execution_units]) == 4
    @test Int(summary[:n_analytic_reference_units]) == 1
    @test Int(summary[:n_job_review_rows]) == 5
    @test Int(summary[:n_heldout_model_rank_rows]) == 5
    @test Int(summary[:n_diagnostic_failure_rows]) == 1
    @test Int(summary[:n_mcmc_diagnostic_failure_rows]) == 1
    @test Int(summary[:n_diagnostic_gate_passed_mcmc_units]) == 3
    @test String(summary[:best_heldout_model]) ==
        "null_or_intercept_reference"
    @test String(summary[:best_mcmc_heldout_model]) ==
        "scalar_gmfrm_baseline"
    @test String(summary[:best_diagnostic_passed_mcmc_model]) ==
        "sparse_mgmfrm_current_q"
    @test Int(summary[:n_blocker_rows]) == 9
    @test Int(summary[:n_resolved_blockers]) == 3
    @test Int(summary[:n_blockers]) == 6
    @test String(summary[:recommendation]) ==
        "review_scalar_sampler_divergences_keep_claims_blocked"
    @test String(summary[:next_gate]) ==
        "review_scalar_sampler_divergences_before_batch_expansion"
end
