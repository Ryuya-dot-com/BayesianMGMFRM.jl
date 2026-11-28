function check_mgmfrm_full_heldout_mcmc_refit_execution_plan_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_full_heldout_mcmc_refit_execution_plan.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) ==
        "full_heldout_mcmc_refit_execution_plan"
    @test String(fixture[:status]) == "full_mcmc_refit_workload_materialized"
    @test String(fixture[:decision]) ==
        "record_full_mcmc_refit_execution_workload"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])
    @test Bool(fixture[:local_only])
    @test Bool(fixture[:heldout_prediction_execution_completed])
    @test Bool(fixture[:full_mcmc_refit_execution_plan_recorded])
    @test Bool(fixture[:full_mcmc_refit_execution_completed]) == false
    @test Bool(fixture[:external_construct_dataset_attached]) == false
    @test Bool(fixture[:external_construct_validation_completed]) == false
    @test Bool(fixture[:publication_or_registration_action]) == false
    @test Bool(fixture[:public_fit_metric_claim]) == false
    @test Bool(fixture[:public_q_revision_claim]) == false
    @test Bool(fixture[:public_model_weight_claim]) == false
    @test Bool(fixture[:sparse_mgmfrm_superiority_claim]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) ==
        "mgmfrm_full_heldout_mcmc_refit_execution_plan_v1"
    @test String(protocol[:review_kind]) ==
        "local_full_heldout_mcmc_refit_execution_plan"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test Bool(protocol[:local_only])
    @test String(protocol[:decision_scope]) ==
        "materialize_full_mcmc_refit_workload_before_public_claims"
    @test String(protocol[:refit_split]) == "observation_kfold"
    @test String(protocol[:target_execution_unit]) == "scenario_model_fold"
    @test String(protocol[:next_execution_target]) ==
        "full_heldout_mgmfrm_mcmc_refit_batch_execution_or_external_construct_dataset_attachment"
    @test Bool(thresholds[:require_full_refit_review_passed])
    @test Bool(thresholds[:require_heldout_prediction_execution_passed])
    @test Bool(thresholds[:require_validation_split_policy_passed])
    @test Bool(thresholds[:require_construct_validity_review_passed])
    @test Bool(thresholds[:require_full_mcmc_refit_required])
    @test Bool(thresholds[
        :require_all_scenario_model_fold_units_materialized])
    @test Bool(thresholds[:require_diagnostic_thresholds_recorded])
    @test Bool(thresholds[:require_execution_budget_recorded])
    @test Bool(thresholds[:require_external_construct_dataset_review_recorded])
    @test Bool(thresholds[
        :require_model_claims_blocked_until_refit_and_validation])
    @test Bool(thresholds[:require_no_public_fit_metric_claim])
    @test Bool(thresholds[:require_no_public_q_revision_claim])
    @test Bool(thresholds[:require_no_public_model_weight_claim])
    @test Bool(thresholds[:require_no_sparse_superiority_claim])
    @test Bool(thresholds[:require_no_publication_or_registration_action])

    inputs = fixture[:input_artifacts]
    expected_paths = Dict(
        "mgmfrm_full_heldout_refit_or_construct_validation_review" =>
            "test/fixtures/mgmfrm_full_heldout_refit_or_construct_validation_review.json",
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

    execution_units = fixture[:execution_unit_rows]
    @test length(execution_units) == 125
    @test Set(String(row[:scenario]) for row in execution_units) ==
        scenario_names
    @test Set(String(row[:model]) for row in execution_units) == model_names
    @test Set(Int(row[:fold]) for row in execution_units) == Set(1:5)
    @test length(unique(String(row[:execution_unit_id])
        for row in execution_units)) == length(execution_units)
    @test length(unique(Int(row[:random_seed]) for row in execution_units)) ==
        length(execution_units)
    @test all(row -> String(row[:split]) == "observation_kfold",
        execution_units)
    @test all(row -> Int(row[:n_train_observations]) == 32,
        execution_units)
    @test all(row -> Int(row[:n_heldout_observations]) == 8,
        execution_units)
    @test all(row -> length(row[:heldout_observations]) == 8,
        execution_units)
    @test all(row -> String(row[:primary_metric]) ==
        "heldout_log_predictive_density", execution_units)
    @test all(row -> String(row[:refit_target]) ==
        "heldout_observation_log_score", execution_units)
    @test all(row -> Int(row[:minimum_chains]) == 4, execution_units)
    @test all(row -> Int(row[:minimum_draws_per_chain]) == 1000,
        execution_units)
    @test all(row -> Int(row[:minimum_warmup_per_chain]) == 500,
        execution_units)
    @test all(row -> String(row[:execution_status]) == "planned_not_executed",
        execution_units)
    @test all(row -> Bool(row[:full_mcmc_refit_completed]) == false,
        execution_units)
    @test all(row -> Bool(row[:diagnostics_observed]) == false,
        execution_units)
    @test all(row -> Bool(row[:pointwise_loglikelihood_required]),
        execution_units)
    @test all(row -> Bool(row[:posterior_predictive_check_required]),
        execution_units)
    @test all(row -> Bool(row[
        :deterministic_metric_reuse_for_public_claim]) == false,
        execution_units)
    @test all(row -> Bool(row[:public_claim_allowed]) == false,
        execution_units)
    @test count(row -> Bool(row[:rank_ambiguity_resolution_required]),
        execution_units) == 25
    @test count(row -> Bool(row[:external_construct_validation_required]),
        execution_units) == 50

    diagnostics = fixture[:diagnostic_threshold_rows]
    @test length(diagnostics) == 7
    @test Set(String(row[:diagnostic]) for row in diagnostics) == Set([
        "rhat_max",
        "ess_bulk_min",
        "ess_tail_min",
        "divergence_count_max",
        "max_treedepth_count_max",
        "pointwise_loglikelihood_finite",
        "posterior_predictive_check_recorded",
    ])
    @test all(row -> Bool(row[:required]), diagnostics)
    @test all(row -> Bool(row[:observed]) == false, diagnostics)
    @test all(row -> Bool(row[:public_claim_blocked_if_missing]),
        diagnostics)

    budgets = fixture[:execution_budget_rows]
    @test length(budgets) == 5
    @test Set(String(row[:model]) for row in budgets) == model_names
    @test all(row -> Int(row[:n_execution_units]) == 25, budgets)
    @test all(row -> Int(row[:n_scenarios]) == 5, budgets)
    @test all(row -> Int(row[:n_folds]) == 5, budgets)
    @test all(row -> Int(row[:chains_per_unit]) == 4, budgets)
    @test all(row -> Int(row[:draws_per_chain]) == 1000, budgets)
    @test all(row -> Int(row[:warmup_per_chain]) == 500, budgets)
    @test all(row -> Int(row[:planned_posterior_draws]) == 100_000,
        budgets)
    @test all(row -> Int(row[:planned_warmup_iterations]) == 50_000,
        budgets)
    @test all(row -> Bool(row[:batch_runner_required]), budgets)
    @test all(row -> Bool(row[:full_mcmc_refit_completed]) == false,
        budgets)

    external_reviews = fixture[:external_construct_dataset_review_rows]
    @test length(external_reviews) == 2
    @test Set(String(row[:scenario]) for row in external_reviews) ==
        Set(["missing_loading_revised_q", "weak_dimension_ambiguous"])
    @test all(row -> Bool(row[:external_dataset_attached]) == false,
        external_reviews)
    @test all(row -> Bool(row[:external_dataset_review_completed]) == false,
        external_reviews)
    @test all(row -> Bool(row[
        :mcmc_refit_can_proceed_without_public_q_claim]), external_reviews)
    @test all(row -> Bool(row[:public_q_revision_claim_allowed]) == false,
        external_reviews)
    @test all(row -> Bool(row[:public_model_superiority_claim_allowed]) ==
        false, external_reviews)

    claim_rules = fixture[:claim_rule_rows]
    @test length(claim_rules) == 5
    @test all(row -> Bool(row[:execution_plan_recorded]), claim_rules)
    @test all(row -> Bool(row[:full_mcmc_refit_completed]) == false,
        claim_rules)
    @test all(row -> Bool(row[:external_construct_validation_completed]) ==
        false, claim_rules)
    @test all(row -> Bool(row[:public_claim_allowed]) == false, claim_rules)

    blockers = fixture[:blocker_rows]
    @test length(blockers) == 5
    @test Set(String(row[:blocker]) for row in blockers) == Set([
        "full_mcmc_refit_batches_not_executed",
        "external_construct_dataset_missing",
        "convergence_diagnostics_not_observed",
        "posterior_predictive_refit_checks_missing",
        "independent_public_scope_review_missing",
    ])
    @test all(row -> Bool(row[:resolved]) == false, blockers)

    evidence_links = fixture[:evidence_link_rows]
    @test length(evidence_links) == 4
    @test all(row -> Bool(row[:link_satisfied]), evidence_links)

    decision = fixture[:decision_record]
    @test String(decision[:selected_decision]) ==
        "record_full_mcmc_refit_execution_workload"
    @test Bool(decision[:full_mcmc_refit_execution_plan_recorded])
    @test Bool(decision[:full_mcmc_refit_execution_completed]) == false
    @test Bool(decision[:external_construct_dataset_attached]) == false
    @test Bool(decision[:external_construct_validation_completed]) == false
    @test Bool(decision[:public_fit_metric_claim_allowed]) == false
    @test Bool(decision[:public_q_revision_claim_allowed]) == false
    @test Bool(decision[
        :model_weight_or_sparse_superiority_claim_allowed]) == false
    @test String(decision[:required_followup]) ==
        "full_heldout_mgmfrm_mcmc_refit_batch_execution_or_external_construct_dataset_attachment"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:local_only])
    @test Bool(summary[:all_input_artifacts_present])
    @test Bool(summary[:all_expected_schemas])
    @test Bool(summary[:all_input_summaries_passed])
    @test Bool(summary[:full_refit_review_passed])
    @test Bool(summary[:heldout_prediction_execution_passed])
    @test Bool(summary[:validation_split_policy_passed])
    @test Bool(summary[:construct_validity_review_passed])
    @test Bool(summary[:prior_review_next_gate_matched])
    @test Bool(summary[:full_mcmc_refit_required])
    @test Bool(summary[:full_mcmc_refit_execution_plan_recorded])
    @test Bool(summary[:full_mcmc_refit_execution_completed]) == false
    @test Bool(summary[:external_construct_dataset_attached]) == false
    @test Bool(summary[:external_construct_validation_completed]) == false
    @test Bool(summary[:all_scenario_model_fold_units_materialized])
    @test Bool(summary[:diagnostic_thresholds_recorded])
    @test Bool(summary[:execution_budget_recorded])
    @test Bool(summary[:external_construct_dataset_review_recorded])
    @test Bool(summary[:all_claim_rules_block_public_claims])
    @test Bool(summary[:all_evidence_links_satisfied])
    @test Bool(summary[:no_public_fit_metric_claim])
    @test Bool(summary[:no_public_q_revision_claim])
    @test Bool(summary[:no_public_model_weight_claim])
    @test Bool(summary[:no_sparse_superiority_claim])
    @test Int(summary[:n_input_artifacts]) == length(inputs)
    @test Int(summary[:n_execution_unit_rows]) == length(execution_units)
    @test Int(summary[:n_diagnostic_threshold_rows]) == length(diagnostics)
    @test Int(summary[:n_execution_budget_rows]) == length(budgets)
    @test Int(summary[:n_external_construct_dataset_review_rows]) ==
        length(external_reviews)
    @test Int(summary[:n_claim_rule_rows]) == length(claim_rules)
    @test Int(summary[:n_blocker_rows]) == length(blockers)
    @test Int(summary[:n_evidence_link_rows]) == length(evidence_links)
    @test Int(summary[:n_review_cells]) == 144
    @test Int(summary[:n_scenarios]) == 5
    @test Int(summary[:n_models]) == 5
    @test Int(summary[:n_folds]) == 5
    @test Int(summary[:n_planned_chains]) == 500
    @test Int(summary[:n_planned_posterior_draws]) == 500_000
    @test Int(summary[:n_planned_warmup_iterations]) == 250_000
    @test Int(summary[:n_external_construct_validation_scenarios]) == 2
    @test Int(summary[:n_rank_ambiguity_execution_units]) == 25
    @test Int(summary[:n_external_construct_execution_units]) == 50
    @test Int(summary[:n_blockers]) == 5
    @test Set(String(blocker) for blocker in
        summary[:remaining_public_blockers]) == Set([
            "full_mcmc_refit_batches_not_executed",
            "external_construct_dataset_missing",
            "convergence_diagnostics_not_observed",
            "posterior_predictive_refit_checks_missing",
            "independent_public_scope_review_missing",
        ])
    @test String(summary[:recommendation]) ==
        "execute_refit_batches_or_attach_external_construct_dataset_before_public_claims"
    @test String(summary[:next_gate]) ==
        "full_heldout_mgmfrm_mcmc_refit_batch_execution_or_external_construct_dataset_attachment"
end

function check_mgmfrm_full_heldout_mcmc_refit_batch_smoke_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_full_heldout_mcmc_refit_batch_smoke.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) ==
        "full_heldout_mcmc_refit_batch_smoke"
    @test String(fixture[:status]) ==
        "representative_batch_smoke_refits_completed"
    @test String(fixture[:decision]) ==
        "record_representative_refit_batch_smoke_keep_claims_blocked"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])
    @test Bool(fixture[:local_only])
    @test Bool(fixture[:smoke_only])
    @test Bool(fixture[:representative_batch_smoke_completed])
    @test Bool(fixture[:full_mcmc_refit_execution_plan_recorded])
    @test Bool(fixture[:full_mcmc_refit_execution_completed]) == false
    @test Bool(fixture[:full_125_unit_batch_completed]) == false
    @test Bool(fixture[:heldout_predictive_scores_computed]) == false
    @test Bool(fixture[:external_construct_dataset_attached]) == false
    @test Bool(fixture[:external_construct_validation_completed]) == false
    @test Bool(fixture[:publication_or_registration_action]) == false
    @test Bool(fixture[:public_fit_metric_claim]) == false
    @test Bool(fixture[:public_q_revision_claim]) == false
    @test Bool(fixture[:public_model_weight_claim]) == false
    @test Bool(fixture[:sparse_mgmfrm_superiority_claim]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    controls = protocol[:fit_controls]
    @test String(protocol[:protocol_id]) ==
        "mgmfrm_full_heldout_mcmc_refit_batch_smoke_v1"
    @test String(protocol[:review_kind]) ==
        "local_full_heldout_mcmc_refit_batch_smoke"
    @test Bool(protocol[:smoke_only])
    @test String(protocol[:execution_scope]) ==
        "representative_scenario_model_fold_smoke"
    @test String(controls[:backend]) == "advancedhmc"
    @test String(controls[:sampler]) == "nuts"
    @test Int(controls[:chains]) == 1
    @test Int(controls[:draws]) == 1
    @test Int(controls[:warmup]) == 0
    @test Int(controls[:seed_base]) == 20260731
    @test Bool(thresholds[:require_execution_plan_passed])
    @test Bool(thresholds[:require_guarded_local_fit_entrypoint_passed])
    @test Bool(thresholds[
        :require_q_revision_construct_validity_review_passed])
    @test Bool(thresholds[:require_representative_units_selected])
    @test Bool(thresholds[:require_smoke_fit_attempts_succeeded])
    @test Bool(thresholds[:require_smoke_outputs_finite])
    @test Bool(thresholds[:require_training_pointwise_loglikelihood_recorded])
    @test Bool(thresholds[:require_publication_grade_diagnostics_blocked])
    @test Bool(thresholds[:require_full_125_unit_batch_not_claimed])
    @test Bool(thresholds[
        :require_heldout_predictive_scores_blocked_until_full_batch])
    @test Bool(thresholds[:require_external_construct_dataset_still_required])
    @test Bool(thresholds[:require_no_public_fit_metric_claim])
    @test Bool(thresholds[:require_no_public_q_revision_claim])
    @test Bool(thresholds[:require_no_public_model_weight_claim])
    @test Bool(thresholds[:require_no_sparse_superiority_claim])
    @test Bool(thresholds[:require_no_publication_or_registration_action])

    inputs = fixture[:input_artifacts]
    expected_inputs = Dict(
        "mgmfrm_full_heldout_mcmc_refit_execution_plan" =>
            "test/fixtures/mgmfrm_full_heldout_mcmc_refit_execution_plan.json",
        "mgmfrm_guarded_local_fit_entrypoint" =>
            "test/fixtures/mgmfrm_guarded_local_fit_entrypoint.json",
        "mgmfrm_q_revision_construct_validity_review" =>
            "test/fixtures/mgmfrm_q_revision_construct_validity_review.json",
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

    expected_units = Set([
        "well_specified_current_q__confirmatory_mgmfrm_current_q__fold1",
        "missing_loading_revised_q__construct_reviewed_revised_q_mgmfrm__fold1",
        "weak_dimension_ambiguous__sparse_mgmfrm_current_q__fold1",
    ])
    expected_profiles = Dict(
        "well_specified_current_q__confirmatory_mgmfrm_current_q__fold1" =>
            ("current_q_6_item_2d", 6, 2, false, false),
        "missing_loading_revised_q__construct_reviewed_revised_q_mgmfrm__fold1" =>
            ("construct_reviewed_candidate_q_3_item_2d", 3, 2, true, false),
        "weak_dimension_ambiguous__sparse_mgmfrm_current_q__fold1" =>
            ("sparse_current_q_5_item_3d", 5, 3, true, true),
    )

    selected = fixture[:selected_execution_unit_rows]
    @test length(selected) == 3
    @test Set(String(row[:execution_unit_id]) for row in selected) ==
        expected_units
    for row in selected
        id = String(row[:execution_unit_id])
        profile, _, _, external_required, rank_required =
            expected_profiles[id]
        @test String(row[:q_profile]) == profile
        @test Int(row[:fold]) == 1
        @test Int(row[:n_train_observations]) == 32
        @test Int(row[:n_heldout_observations]) == 8
        @test length(row[:heldout_observations]) == 8
        @test Int(row[:planned_minimum_chains]) == 4
        @test Int(row[:planned_minimum_draws_per_chain]) == 1000
        @test Int(row[:planned_minimum_warmup_per_chain]) == 500
        @test Int(row[:smoke_chains]) == 1
        @test Int(row[:smoke_draws_per_chain]) == 1
        @test Int(row[:smoke_warmup_per_chain]) == 0
        @test Bool(row[:external_construct_validation_required]) ==
            external_required
        @test Bool(row[:rank_ambiguity_resolution_required]) ==
            rank_required
        @test String(row[:full_unit_execution_status]) ==
            "planned_not_executed"
        @test Bool(row[:public_claim_allowed]) == false
    end

    fits = fixture[:smoke_fit_rows]
    @test length(fits) == 3
    @test Set(String(row[:execution_unit_id]) for row in fits) ==
        expected_units
    @test all(row -> String(row[:returned_type]) == "MGMFRMFit", fits)
    @test all(row -> Bool(row[:fit_succeeded]), fits)
    @test all(row -> Bool(row[:smoke_only]), fits)
    @test all(row -> Int(row[:n_train_observations]) == 32, fits)
    @test all(row -> Int(row[:n_heldout_observations]) == 8, fits)
    @test all(row -> Int(row[:n_training_pointwise_loglikelihood_rows]) == 1,
        fits)
    @test all(row -> Int(row[:n_training_pointwise_observations]) == 32,
        fits)
    @test all(row -> String(row[:backend]) == "advancedhmc", fits)
    @test all(row -> String(row[:sampler]) == "nuts", fits)
    @test all(row -> Int(row[:chains]) == 1, fits)
    @test all(row -> Int(row[:draws_per_chain]) == 1, fits)
    @test all(row -> Int(row[:warmup]) == 0, fits)
    @test all(row -> Bool(row[:validation_passed]), fits)
    @test all(row -> Bool(row[:q_validation_passed]), fits)
    @test all(row -> Bool(row[:finite_log_posterior]), fits)
    @test all(row -> Bool(row[:finite_raw_draws]), fits)
    @test all(row -> Bool(row[:finite_direct_draws]), fits)
    @test all(row -> Bool(row[:finite_direct_loglikelihood]), fits)
    @test all(row -> Bool(row[:finite_training_pointwise_loglikelihood]),
        fits)
    @test all(row -> String(row[:diagnostic_flag]) == "insufficient_chains",
        fits)
    @test all(row -> Bool(row[:diagnostic_passed]) == false, fits)
    @test all(row -> Int(row[:n_divergences]) == 0, fits)
    @test all(row -> Int(row[:n_max_treedepth]) == 0, fits)
    @test all(row -> Bool(row[:rhat_evaluable]) == false, fits)
    @test all(row -> Bool(row[:ess_evaluable]) == false, fits)
    @test all(row -> Bool(row[:heldout_predictive_score_computed]) == false,
        fits)
    @test all(row -> Bool(row[:posterior_predictive_check_recorded]) == false,
        fits)
    @test all(row -> Bool(row[:public_claim_allowed]) == false, fits)
    for row in fits
        id = String(row[:execution_unit_id])
        q_profile, n_items, n_dimensions, _, _ = expected_profiles[id]
        @test String(row[:q_profile]) == q_profile
        @test Int(row[:n_items]) == n_items
        @test Int(row[:n_dimensions]) == n_dimensions
        @test Int(row[:n_persons]) == 4
        @test Int(row[:n_raters]) == 2
        @test Int(row[:n_categories]) == 3
    end

    diagnostic_checks = fixture[:diagnostic_check_rows]
    @test length(diagnostic_checks) == 27
    @test all(row -> Bool(row[:passed]), diagnostic_checks)
    @test all(row -> Bool(row[:blocks_public_claim]), diagnostic_checks)
    @test Set(String(row[:check]) for row in diagnostic_checks) == Set([
        "smoke_fit_succeeded",
        "finite_log_posterior",
        "finite_raw_and_direct_draws",
        "finite_training_pointwise_loglikelihood",
        "zero_divergences",
        "zero_max_treedepth_hits",
        "publication_grade_rhat_not_evaluable_in_smoke",
        "publication_grade_ess_not_evaluable_in_smoke",
        "heldout_predictive_score_not_computed_in_smoke",
    ])
    for id in expected_units
        @test count(row -> String(row[:execution_unit_id]) == id,
            diagnostic_checks) == 9
    end

    blockers = fixture[:blocker_rows]
    @test length(blockers) == 5
    @test Set(String(row[:blocker]) for row in blockers) == Set([
        "full_125_unit_refit_batch_not_completed",
        "publication_grade_chains_and_draws_not_run",
        "heldout_predictive_scores_not_computed",
        "external_construct_dataset_missing",
        "independent_public_scope_review_missing",
    ])
    @test all(row -> Bool(row[:resolved]) == false, blockers)

    decision = fixture[:decision_record]
    @test String(decision[:selected_decision]) ==
        "record_representative_refit_batch_smoke_keep_claims_blocked"
    @test Bool(decision[:representative_batch_smoke_completed])
    @test Bool(decision[:full_mcmc_refit_execution_completed]) == false
    @test Bool(decision[:full_125_unit_batch_completed]) == false
    @test Bool(decision[:heldout_predictive_scores_computed]) == false
    @test Bool(decision[:external_construct_dataset_attached]) == false
    @test Bool(decision[:external_construct_validation_completed]) == false
    @test Bool(decision[:public_fit_metric_claim_allowed]) == false
    @test Bool(decision[:public_q_revision_claim_allowed]) == false
    @test Bool(decision[
        :model_weight_or_sparse_superiority_claim_allowed]) == false
    @test String(decision[:required_followup]) ==
        "full_heldout_mgmfrm_mcmc_refit_full_batch_execution_or_external_construct_dataset_attachment"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:local_only])
    @test Bool(summary[:smoke_only])
    @test Bool(summary[:all_input_artifacts_present])
    @test Bool(summary[:all_expected_schemas])
    @test Bool(summary[:all_input_summaries_passed])
    @test Bool(summary[:execution_plan_passed])
    @test Bool(summary[:guarded_local_fit_entrypoint_passed])
    @test Bool(summary[:q_revision_construct_validity_review_passed])
    @test Bool(summary[:representative_batch_smoke_completed])
    @test Bool(summary[:representative_units_selected])
    @test Bool(summary[:smoke_fit_attempts_succeeded])
    @test Bool(summary[:smoke_outputs_finite])
    @test Bool(summary[:training_pointwise_loglikelihood_recorded])
    @test Bool(summary[:publication_grade_diagnostics_blocked])
    @test Bool(summary[:full_125_unit_batch_not_claimed])
    @test Bool(summary[:heldout_predictive_scores_blocked_until_full_batch])
    @test Bool(summary[:external_construct_dataset_still_required])
    @test Bool(summary[:full_mcmc_refit_execution_completed]) == false
    @test Bool(summary[:full_125_unit_batch_completed]) == false
    @test Bool(summary[:heldout_predictive_scores_computed]) == false
    @test Bool(summary[:external_construct_dataset_attached]) == false
    @test Bool(summary[:external_construct_validation_completed]) == false
    @test Bool(summary[:no_public_fit_metric_claim])
    @test Bool(summary[:no_public_q_revision_claim])
    @test Bool(summary[:no_public_model_weight_claim])
    @test Bool(summary[:no_sparse_superiority_claim])
    @test Int(summary[:n_input_artifacts]) == length(inputs)
    @test Int(summary[:n_planned_execution_units]) == 125
    @test Int(summary[:n_selected_execution_unit_rows]) == length(selected)
    @test Int(summary[:n_smoke_fit_rows]) == length(fits)
    @test Int(summary[:n_diagnostic_check_rows]) ==
        length(diagnostic_checks)
    @test Int(summary[:n_blocker_rows]) == length(blockers)
    @test Int(summary[:n_review_cells]) == 33
    @test Int(summary[:n_smoke_training_observations]) == 96
    @test Int(summary[:n_smoke_heldout_observations]) == 24
    @test Int(summary[:n_training_pointwise_loglikelihood_cells]) == 96
    @test Int(summary[:n_publication_grade_fit_rows]) == 0
    @test Int(summary[:n_full_execution_units_completed]) == 0
    @test Int(summary[:n_blockers]) == 5
    @test Set(String(blocker) for blocker in
        summary[:remaining_public_blockers]) == Set([
            "full_125_unit_refit_batch_not_completed",
            "publication_grade_chains_and_draws_not_run",
            "heldout_predictive_scores_not_computed",
            "external_construct_dataset_missing",
            "independent_public_scope_review_missing",
        ])
    @test String(summary[:recommendation]) ==
        "use_smoke_as_runner_check_execute_full_batch_or_attach_external_dataset_next"
    @test String(summary[:next_gate]) ==
        "full_heldout_mgmfrm_mcmc_refit_full_batch_execution_or_external_construct_dataset_attachment"
end

function check_mgmfrm_full_heldout_mcmc_refit_fold1_pilot_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_full_heldout_mcmc_refit_fold1_pilot.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) ==
        "full_heldout_mcmc_refit_fold1_pilot"
    @test String(fixture[:status]) ==
        "fold1_mgmfrm_candidate_pilot_refits_completed"
    @test String(fixture[:decision]) ==
        "record_fold1_mgmfrm_candidate_pilot_keep_full_batch_claims_blocked"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])
    @test Bool(fixture[:local_only])
    @test Bool(fixture[:pilot_only])
    @test Bool(fixture[:smoke_only])
    @test Bool(fixture[:fold1_pilot_completed])
    @test Bool(fixture[:representative_batch_smoke_completed])
    @test Bool(fixture[:full_mcmc_refit_execution_completed]) == false
    @test Bool(fixture[:full_125_unit_batch_completed]) == false
    @test Bool(fixture[:heldout_predictive_scores_computed]) == false
    @test Bool(fixture[:external_construct_dataset_attached]) == false
    @test Bool(fixture[:external_construct_validation_completed]) == false
    @test Bool(fixture[:publication_or_registration_action]) == false
    @test Bool(fixture[:public_fit_metric_claim]) == false
    @test Bool(fixture[:public_q_revision_claim]) == false
    @test Bool(fixture[:public_model_weight_claim]) == false
    @test Bool(fixture[:sparse_mgmfrm_superiority_claim]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    controls = protocol[:fit_controls]
    @test String(protocol[:protocol_id]) ==
        "mgmfrm_full_heldout_mcmc_refit_fold1_pilot_v1"
    @test String(protocol[:review_kind]) ==
        "local_full_heldout_mcmc_refit_fold1_pilot"
    @test Bool(protocol[:pilot_only])
    @test Bool(protocol[:smoke_only])
    @test String(protocol[:execution_scope]) == "fold1_scenario_model_pilot"
    @test Int(protocol[:selected_fold]) == 1
    @test String(protocol[:candidate_family_scope]) ==
        "fixed_q_mgmfrm_candidates_only"
    @test String(protocol[:comparison_anchor_policy]) ==
        "record_not_fit_in_mgmfrm_candidate_pilot"
    @test String(controls[:backend]) == "advancedhmc"
    @test String(controls[:sampler]) == "nuts"
    @test Int(controls[:chains]) == 1
    @test Int(controls[:draws]) == 1
    @test Int(controls[:warmup]) == 0
    @test Int(controls[:seed_base]) == 20260801
    @test Bool(thresholds[:require_execution_plan_passed])
    @test Bool(thresholds[:require_batch_smoke_passed])
    @test Bool(thresholds[:require_fold1_units_selected])
    @test Bool(thresholds[:require_all_scenarios_covered])
    @test Bool(thresholds[:require_all_models_recorded])
    @test Bool(thresholds[
        :require_mgmfrm_candidate_fit_attempts_succeeded])
    @test Bool(thresholds[:require_mgmfrm_candidate_outputs_finite])
    @test Bool(thresholds[:require_q_validations_passed])
    @test Bool(thresholds[:require_comparison_anchors_recorded_not_claimed])
    @test Bool(thresholds[:require_full_125_unit_batch_not_claimed])
    @test Bool(thresholds[
        :require_heldout_predictive_scores_blocked_until_full_batch])
    @test Bool(thresholds[:require_no_publication_or_registration_action])

    inputs = fixture[:input_artifacts]
    expected_inputs = Dict(
        "mgmfrm_full_heldout_mcmc_refit_execution_plan" =>
            "test/fixtures/mgmfrm_full_heldout_mcmc_refit_execution_plan.json",
        "mgmfrm_full_heldout_mcmc_refit_batch_smoke" =>
            "test/fixtures/mgmfrm_full_heldout_mcmc_refit_batch_smoke.json",
        "mgmfrm_guarded_local_fit_entrypoint" =>
            "test/fixtures/mgmfrm_guarded_local_fit_entrypoint.json",
        "mgmfrm_q_revision_construct_validity_review" =>
            "test/fixtures/mgmfrm_q_revision_construct_validity_review.json",
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
    scenarios = Set([
        "well_specified_current_q",
        "missing_loading_revised_q",
        "sparse_signal_current_q",
        "rater_method_noise",
        "weak_dimension_ambiguous",
    ])
    models = Set([
        "scalar_gmfrm_baseline",
        "confirmatory_mgmfrm_current_q",
        "sparse_mgmfrm_current_q",
        "construct_reviewed_revised_q_mgmfrm",
        "null_or_intercept_reference",
    ])
    candidate_models = Set([
        "confirmatory_mgmfrm_current_q",
        "sparse_mgmfrm_current_q",
        "construct_reviewed_revised_q_mgmfrm",
    ])
    anchor_models = Set([
        "scalar_gmfrm_baseline",
        "null_or_intercept_reference",
    ])

    units = fixture[:pilot_execution_unit_rows]
    @test length(units) == 25
    @test Set(String(row[:scenario]) for row in units) == scenarios
    @test Set(String(row[:model]) for row in units) == models
    @test all(row -> Int(row[:fold]) == 1, units)
    @test all(row -> Int(row[:n_train_observations]) == 32, units)
    @test all(row -> Int(row[:n_heldout_observations]) == 8, units)
    @test all(row -> Bool(row[:public_claim_allowed]) == false, units)
    @test count(row -> Bool(row[:fit_attempted]), units) == 15
    @test count(row -> !Bool(row[:fit_attempted]), units) == 10
    @test Set(String(row[:model]) for row in units
        if Bool(row[:fit_attempted])) == candidate_models
    @test Set(String(row[:model]) for row in units
        if !Bool(row[:fit_attempted])) == anchor_models
    @test all(row -> String(row[:pilot_family]) ==
        "mgmfrm_fixed_q_candidate", filter(row -> Bool(row[:fit_attempted]), units))

    fits = fixture[:candidate_fit_rows]
    @test length(fits) == 15
    @test Set(String(row[:scenario]) for row in fits) == scenarios
    @test Set(String(row[:model]) for row in fits) == candidate_models
    @test all(row -> String(row[:returned_type]) == "MGMFRMFit", fits)
    @test all(row -> Bool(row[:fit_succeeded]), fits)
    @test all(row -> Bool(row[:pilot_only]), fits)
    @test all(row -> Bool(row[:smoke_only]), fits)
    @test all(row -> Int(row[:fold]) == 1, fits)
    @test all(row -> Int(row[:n_train_observations]) == 32, fits)
    @test all(row -> Int(row[:n_heldout_observations]) == 8, fits)
    @test all(row -> Int(row[:n_training_pointwise_loglikelihood_rows]) == 1,
        fits)
    @test all(row -> Int(row[:n_training_pointwise_observations]) == 32,
        fits)
    @test all(row -> String(row[:backend]) == "advancedhmc", fits)
    @test all(row -> String(row[:sampler]) == "nuts", fits)
    @test all(row -> Int(row[:chains]) == 1, fits)
    @test all(row -> Int(row[:draws_per_chain]) == 1, fits)
    @test all(row -> Int(row[:warmup]) == 0, fits)
    @test all(row -> Bool(row[:validation_passed]), fits)
    @test all(row -> Bool(row[:q_validation_passed]), fits)
    @test all(row -> Bool(row[:finite_log_posterior]), fits)
    @test all(row -> Bool(row[:finite_raw_draws]), fits)
    @test all(row -> Bool(row[:finite_direct_draws]), fits)
    @test all(row -> Bool(row[:finite_direct_loglikelihood]), fits)
    @test all(row -> Bool(row[:finite_training_pointwise_loglikelihood]),
        fits)
    @test all(row -> String(row[:diagnostic_flag]) == "insufficient_chains",
        fits)
    @test all(row -> Bool(row[:diagnostic_passed]) == false, fits)
    @test all(row -> Int(row[:n_divergences]) == 0, fits)
    @test all(row -> Int(row[:n_max_treedepth]) == 0, fits)
    @test all(row -> Bool(row[:rhat_evaluable]) == false, fits)
    @test all(row -> Bool(row[:ess_evaluable]) == false, fits)
    @test all(row -> Bool(row[:heldout_predictive_score_computed]) == false,
        fits)
    @test all(row -> Bool(row[:posterior_predictive_check_recorded]) == false,
        fits)
    @test all(row -> Bool(row[:public_claim_allowed]) == false, fits)
    for scenario in scenarios
        @test count(row -> String(row[:scenario]) == scenario, fits) == 3
    end
    for model in candidate_models
        @test count(row -> String(row[:model]) == model, fits) == 5
    end
    @test count(row -> Int(row[:n_dimensions]) == 2, fits) == 9
    @test count(row -> Int(row[:n_dimensions]) == 3, fits) == 6

    anchors = fixture[:comparison_anchor_rows]
    @test length(anchors) == 10
    @test Set(String(row[:model]) for row in anchors) == anchor_models
    @test all(row -> Int(row[:fold]) == 1, anchors)
    @test all(row -> Bool(row[:fit_attempted]) == false, anchors)
    @test all(row -> String(row[:not_fit_reason]) ==
        "not_a_fixed_q_mgmfrm_candidate_in_fold1_pilot", anchors)
    @test all(row -> Bool(row[:heldout_predictive_score_computed]) == false,
        anchors)
    @test all(row -> Bool(row[:full_batch_required_before_public_claim]),
        anchors)
    @test all(row -> Bool(row[:public_claim_allowed]) == false, anchors)

    coverage = fixture[:coverage_rows]
    @test length(coverage) == 25
    @test all(row -> Bool(row[:selected_for_fold1_pilot]), coverage)
    @test count(row -> Bool(row[:mgmfrm_fit_attempted]), coverage) == 15
    @test count(row -> Bool(row[:covered_by_candidate_fit]), coverage) == 15
    @test count(row -> Bool(row[:comparison_anchor_recorded]), coverage) == 10
    @test all(row -> Bool(row[:heldout_predictive_score_computed]) == false,
        coverage)
    @test all(row -> Bool(row[:public_claim_allowed]) == false, coverage)

    diagnostic_checks = fixture[:diagnostic_check_rows]
    @test length(diagnostic_checks) == 150
    @test all(row -> Bool(row[:passed]), diagnostic_checks)
    @test all(row -> Bool(row[:blocks_public_claim]), diagnostic_checks)
    @test Set(String(row[:check]) for row in diagnostic_checks) == Set([
        "pilot_fit_succeeded",
        "q_validation_passed",
        "finite_log_posterior",
        "finite_raw_and_direct_draws",
        "finite_training_pointwise_loglikelihood",
        "zero_divergences",
        "zero_max_treedepth_hits",
        "publication_grade_rhat_not_evaluable_in_pilot",
        "publication_grade_ess_not_evaluable_in_pilot",
        "heldout_predictive_score_not_computed_in_pilot",
    ])
    for row in fits
        id = String(row[:execution_unit_id])
        @test count(check -> String(check[:execution_unit_id]) == id,
            diagnostic_checks) == 10
    end

    blockers = fixture[:blocker_rows]
    @test length(blockers) == 6
    @test Set(String(row[:blocker]) for row in blockers) == Set([
        "full_125_unit_refit_batch_not_completed",
        "comparison_anchor_mcmc_refits_not_run_in_pilot",
        "publication_grade_chains_and_draws_not_run",
        "heldout_predictive_scores_not_computed",
        "external_construct_dataset_missing",
        "independent_public_scope_review_missing",
    ])
    @test all(row -> Bool(row[:resolved]) == false, blockers)

    decision = fixture[:decision_record]
    @test String(decision[:selected_decision]) ==
        "record_fold1_mgmfrm_candidate_pilot_keep_full_batch_claims_blocked"
    @test Bool(decision[:representative_batch_smoke_completed])
    @test Bool(decision[:fold1_pilot_completed])
    @test Bool(decision[:full_mcmc_refit_execution_completed]) == false
    @test Bool(decision[:full_125_unit_batch_completed]) == false
    @test Bool(decision[:heldout_predictive_scores_computed]) == false
    @test Bool(decision[:external_construct_dataset_attached]) == false
    @test Bool(decision[:external_construct_validation_completed]) == false
    @test Bool(decision[:public_fit_metric_claim_allowed]) == false
    @test Bool(decision[:public_q_revision_claim_allowed]) == false
    @test Bool(decision[
        :model_weight_or_sparse_superiority_claim_allowed]) == false
    @test String(decision[:required_followup]) ==
        "full_heldout_mgmfrm_mcmc_refit_full_batch_execution_or_external_construct_dataset_attachment"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:local_only])
    @test Bool(summary[:pilot_only])
    @test Bool(summary[:smoke_only])
    @test Bool(summary[:all_input_artifacts_present])
    @test Bool(summary[:all_expected_schemas])
    @test Bool(summary[:all_input_summaries_passed])
    @test Bool(summary[:execution_plan_passed])
    @test Bool(summary[:batch_smoke_passed])
    @test Bool(summary[:guarded_local_fit_entrypoint_passed])
    @test Bool(summary[:q_revision_construct_validity_review_passed])
    @test Bool(summary[:fold1_units_selected])
    @test Bool(summary[:all_scenarios_covered])
    @test Bool(summary[:all_models_recorded])
    @test Bool(summary[:mgmfrm_candidate_fit_attempts_succeeded])
    @test Bool(summary[:mgmfrm_candidate_outputs_finite])
    @test Bool(summary[:q_validations_passed])
    @test Bool(summary[:training_pointwise_loglikelihood_recorded])
    @test Bool(summary[:publication_grade_diagnostics_blocked])
    @test Bool(summary[:comparison_anchors_recorded_not_claimed])
    @test Bool(summary[:full_125_unit_batch_not_claimed])
    @test Bool(summary[:heldout_predictive_scores_blocked_until_full_batch])
    @test Bool(summary[:external_construct_dataset_still_required])
    @test Bool(summary[:full_mcmc_refit_execution_completed]) == false
    @test Bool(summary[:full_125_unit_batch_completed]) == false
    @test Bool(summary[:heldout_predictive_scores_computed]) == false
    @test Bool(summary[:external_construct_dataset_attached]) == false
    @test Bool(summary[:external_construct_validation_completed]) == false
    @test Bool(summary[:no_public_fit_metric_claim])
    @test Bool(summary[:no_public_q_revision_claim])
    @test Bool(summary[:no_public_model_weight_claim])
    @test Bool(summary[:no_sparse_superiority_claim])
    @test Int(summary[:n_input_artifacts]) == length(inputs)
    @test Int(summary[:n_planned_execution_units]) == 125
    @test Int(summary[:n_fold1_execution_unit_rows]) == 25
    @test Int(summary[:n_candidate_fit_rows]) == 15
    @test Int(summary[:n_comparison_anchor_rows]) == 10
    @test Int(summary[:n_coverage_rows]) == 25
    @test Int(summary[:n_diagnostic_check_rows]) == 150
    @test Int(summary[:n_blocker_rows]) == 6
    @test Int(summary[:n_review_cells]) == 225
    @test Int(summary[:n_scenarios]) == 5
    @test Int(summary[:n_models]) == 5
    @test Int(summary[:n_mgmfrm_candidate_models]) == 3
    @test Int(summary[:n_candidate_training_observations]) == 480
    @test Int(summary[:n_candidate_heldout_observations]) == 120
    @test Int(summary[:n_training_pointwise_loglikelihood_cells]) == 480
    @test Int(summary[:n_publication_grade_fit_rows]) == 0
    @test Int(summary[:n_full_execution_units_completed]) == 0
    @test Int(summary[:n_blockers]) == 6
    @test Set(String(blocker) for blocker in
        summary[:remaining_public_blockers]) == Set([
            "full_125_unit_refit_batch_not_completed",
            "comparison_anchor_mcmc_refits_not_run_in_pilot",
            "publication_grade_chains_and_draws_not_run",
            "heldout_predictive_scores_not_computed",
            "external_construct_dataset_missing",
            "independent_public_scope_review_missing",
        ])
    @test String(summary[:recommendation]) ==
        "use_fold1_pilot_to_expand_to_remaining_folds_or_attach_external_dataset_next"
    @test String(summary[:next_gate]) ==
        "full_heldout_mgmfrm_mcmc_refit_full_batch_execution_or_external_construct_dataset_attachment"
end

function check_mgmfrm_full_heldout_mcmc_refit_fold1_scoring_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_full_heldout_mcmc_refit_fold1_scoring.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) ==
        "full_heldout_mcmc_refit_fold1_scoring"
    @test String(fixture[:status]) ==
        "fold1_mgmfrm_candidate_heldout_scores_recorded"
    @test String(fixture[:decision]) ==
        "record_fold1_heldout_scores_keep_full_batch_claims_blocked"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])
    @test Bool(fixture[:local_only])
    @test Bool(fixture[:pilot_only])
    @test Bool(fixture[:smoke_only])
    @test Bool(fixture[:fold1_pilot_completed])
    @test Bool(fixture[:fold1_heldout_predictive_scores_computed])
    @test Bool(fixture[:heldout_predictive_scores_computed])
    @test Bool(fixture[:full_mcmc_refit_execution_completed]) == false
    @test Bool(fixture[:full_125_unit_batch_completed]) == false
    @test Bool(fixture[:full_heldout_predictive_scores_computed]) == false
    @test Bool(fixture[:comparison_anchor_scores_computed]) == false
    @test Bool(fixture[:publication_or_registration_action]) == false
    @test Bool(fixture[:public_fit_metric_claim]) == false
    @test Bool(fixture[:public_q_revision_claim]) == false
    @test Bool(fixture[:public_model_weight_claim]) == false
    @test Bool(fixture[:sparse_mgmfrm_superiority_claim]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    controls = protocol[:fit_controls]
    @test String(protocol[:protocol_id]) ==
        "mgmfrm_full_heldout_mcmc_refit_fold1_scoring_v1"
    @test String(protocol[:review_kind]) ==
        "local_full_heldout_mcmc_refit_fold1_scoring"
    @test Bool(protocol[:pilot_only])
    @test Bool(protocol[:smoke_only])
    @test String(protocol[:execution_scope]) ==
        "fold1_mgmfrm_candidate_heldout_scoring"
    @test Int(protocol[:selected_fold]) == 1
    @test String(protocol[:scoring_target]) ==
        "heldout_pointwise_log_predictive_density"
    @test String(protocol[:expected_score_target]) ==
        "observed_minus_expected_score_residual"
    @test String(protocol[:comparison_scope]) ==
        "fixed_q_mgmfrm_candidates_only"
    @test String(protocol[:comparison_anchor_policy]) ==
        "recorded_in_pilot_not_scored_here"
    @test String(controls[:backend]) == "advancedhmc"
    @test String(controls[:sampler]) == "nuts"
    @test Int(controls[:chains]) == 1
    @test Int(controls[:draws]) == 1
    @test Int(controls[:warmup]) == 0
    @test Bool(thresholds[:require_execution_plan_passed])
    @test Bool(thresholds[:require_fold1_pilot_passed])
    @test Bool(thresholds[:require_all_candidate_scores_recorded])
    @test Bool(thresholds[:require_all_pointwise_scores_recorded])
    @test Bool(thresholds[:require_all_score_values_finite])
    @test Bool(thresholds[:require_expected_score_residuals_recorded])
    @test Bool(thresholds[
        :require_training_heldout_alignment_rows_recorded])
    @test Bool(thresholds[:require_candidate_rank_rows_recorded])
    @test Bool(thresholds[:require_comparison_anchors_not_scored])
    @test Bool(thresholds[:require_no_publication_or_registration_action])

    inputs = fixture[:input_artifacts]
    expected_inputs = Dict(
        "mgmfrm_full_heldout_mcmc_refit_execution_plan" =>
            "test/fixtures/mgmfrm_full_heldout_mcmc_refit_execution_plan.json",
        "mgmfrm_full_heldout_mcmc_refit_fold1_pilot" =>
            "test/fixtures/mgmfrm_full_heldout_mcmc_refit_fold1_pilot.json",
        "mgmfrm_heldout_prediction_execution" =>
            "test/fixtures/mgmfrm_heldout_prediction_execution.json",
        "mgmfrm_validation_split_model_comparison_policy" =>
            "test/fixtures/mgmfrm_validation_split_model_comparison_policy.json",
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

    candidate_models = Set([
        "confirmatory_mgmfrm_current_q",
        "sparse_mgmfrm_current_q",
        "construct_reviewed_revised_q_mgmfrm",
    ])
    scenarios = Set([
        "well_specified_current_q",
        "missing_loading_revised_q",
        "sparse_signal_current_q",
        "rater_method_noise",
        "weak_dimension_ambiguous",
    ])

    scores = fixture[:candidate_score_rows]
    @test length(scores) == 15
    @test Set(String(row[:scenario]) for row in scores) == scenarios
    @test Set(String(row[:model]) for row in scores) == candidate_models
    @test all(row -> Int(row[:fold]) == 1, scores)
    @test all(row -> Bool(row[:fit_succeeded]), scores)
    @test all(row -> Bool(row[:layout_matches]), scores)
    @test all(row -> Int(row[:n_train_observations]) == 32, scores)
    @test all(row -> Int(row[:n_heldout_observations]) == 8, scores)
    @test all(row -> Int(row[:n_draws]) == 1, scores)
    @test all(row -> Bool(row[:all_pointwise_scores_finite]), scores)
    @test all(row -> Bool(row[:expected_score_residuals_finite]), scores)
    @test all(row -> Bool(row[:finite_direct_draws]), scores)
    @test all(row -> Bool(row[:finite_training_pointwise_loglikelihood]),
        scores)
    @test all(row -> Bool(row[:finite_heldout_pointwise_loglikelihood]),
        scores)
    @test all(row -> String(row[:diagnostic_flag]) ==
        "insufficient_chains", scores)
    @test all(row -> Bool(row[:diagnostic_passed]) == false, scores)
    @test all(row -> Bool(row[:publication_grade_diagnostics_blocked]),
        scores)
    @test all(row -> Int(row[:n_divergences]) == 0, scores)
    @test all(row -> Int(row[:n_max_treedepth]) == 0, scores)
    @test all(row -> Bool(row[:heldout_predictive_score_computed]), scores)
    @test all(row -> Bool(row[:public_fit_metric_claim_allowed]) == false,
        scores)
    @test all(row -> Bool(row[:public_model_weight_claim_allowed]) == false,
        scores)
    @test all(row -> Bool(row[:sparse_superiority_claim_allowed]) == false,
        scores)
    @test all(row -> isfinite(Float64(row[:heldout_elpd])) &&
            isfinite(Float64(row[:heldout_mean_log_predictive_density])) &&
            isfinite(Float64(row[:heldout_expected_score_mae])) &&
            isfinite(Float64(row[:heldout_expected_score_rmse])),
        scores)
    for scenario in scenarios
        @test count(row -> String(row[:scenario]) == scenario, scores) == 3
    end

    pointwise = fixture[:heldout_pointwise_rows]
    @test length(pointwise) == 120
    @test all(row -> Bool(row[:finite_score]), pointwise)
    @test all(row -> Bool(row[:public_claim_allowed]) == false, pointwise)
    @test all(row -> Int(row[:fold]) == 1, pointwise)
    @test all(row -> Int(row[:heldout_position]) in 1:8, pointwise)
    @test all(row -> 0 <= Int(row[:observed_score]) <= 2, pointwise)
    @test all(row -> isfinite(Float64(row[:pointwise_log_predictive_density])) &&
            isfinite(Float64(row[:expected_score_mean])) &&
            isfinite(Float64(row[:observed_minus_expected_score])) &&
            isfinite(Float64(row[:absolute_expected_score_error])) &&
            isfinite(Float64(row[:squared_expected_score_error])),
        pointwise)
    for row in scores
        id = String(row[:execution_unit_id])
        @test count(point -> String(point[:execution_unit_id]) == id,
            pointwise) == 8
    end

    ranks = fixture[:candidate_rank_rows]
    @test length(ranks) == 15
    @test all(row -> String(row[:comparison_scope]) ==
        "fixed_q_mgmfrm_candidates_fold1_only", ranks)
    @test all(row -> Bool(row[:public_model_weight_claim_allowed]) == false,
        ranks)
    @test all(row -> Bool(row[:sparse_superiority_claim_allowed]) == false,
        ranks)
    @test all(row -> String(row[:interpretation]) ==
        "descriptive_fold1_pilot_rank_no_public_superiority_claim", ranks)
    for scenario in scenarios
        scenario_ranks = [row for row in ranks
            if String(row[:scenario]) == scenario]
        @test sort([Int(row[:rank]) for row in scenario_ranks]) == [1, 2, 3]
        @test count(row -> Bool(row[:best_model_in_fold1_pilot]),
            scenario_ranks) == 1
        @test all(row -> Float64(row[:delta_elpd_from_best]) <= 0.0,
            scenario_ranks)
    end

    alignment = fixture[:training_heldout_alignment_rows]
    @test length(alignment) == 15
    @test all(row -> String(row[:threshold_interpretation]) ==
        "descriptive_metric_shift_no_threshold_profile_promoted", alignment)
    @test all(row -> Bool(row[:publication_grade_diagnostics_blocked]),
        alignment)
    @test all(row -> Bool(row[:public_fit_metric_claim_allowed]) == false,
        alignment)
    @test all(row -> isfinite(Float64(row[:training_mean_log_predictive_density])) &&
            isfinite(Float64(row[:heldout_mean_log_predictive_density])) &&
            isfinite(Float64(row[:train_heldout_mean_log_predictive_gap])) &&
            isfinite(Float64(row[:heldout_expected_score_mae])) &&
            isfinite(Float64(row[:heldout_expected_score_rmse])),
        alignment)

    anchors = fixture[:comparison_anchor_rows]
    @test length(anchors) == 10
    @test all(row -> Bool(row[:fit_attempted]) == false, anchors)
    @test all(row -> Bool(row[:heldout_predictive_score_computed]) == false,
        anchors)
    @test all(row -> String(row[:not_scored_reason]) ==
        "comparison_anchor_not_refit_in_fold1_mgmfrm_scoring", anchors)
    @test all(row -> Bool(row[:public_claim_allowed]) == false, anchors)

    blockers = fixture[:blocker_rows]
    @test length(blockers) == 6
    @test Set(String(row[:blocker]) for row in blockers) == Set([
        "fold1_only_remaining_folds_not_scored",
        "full_125_unit_refit_batch_not_completed",
        "comparison_anchor_mcmc_refits_not_run",
        "publication_grade_chains_and_draws_not_run",
        "external_construct_dataset_missing",
        "independent_public_scope_review_missing",
    ])
    @test all(row -> Bool(row[:resolved]) == false, blockers)

    decision = fixture[:decision_record]
    @test String(decision[:selected_decision]) ==
        "record_fold1_heldout_scores_keep_full_batch_claims_blocked"
    @test Bool(decision[:fold1_pilot_completed])
    @test Bool(decision[:fold1_heldout_predictive_scores_computed])
    @test Bool(decision[:full_mcmc_refit_execution_completed]) == false
    @test Bool(decision[:full_125_unit_batch_completed]) == false
    @test Bool(decision[:full_heldout_predictive_scores_computed]) == false
    @test Bool(decision[:comparison_anchor_scores_computed]) == false
    @test Bool(decision[:public_fit_metric_claim_allowed]) == false
    @test Bool(decision[:public_q_revision_claim_allowed]) == false
    @test Bool(decision[
        :model_weight_or_sparse_superiority_claim_allowed]) == false

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:local_only])
    @test Bool(summary[:pilot_only])
    @test Bool(summary[:smoke_only])
    @test Bool(summary[:all_input_artifacts_present])
    @test Bool(summary[:all_expected_schemas])
    @test Bool(summary[:all_input_summaries_passed])
    @test Bool(summary[:execution_plan_passed])
    @test Bool(summary[:fold1_pilot_passed])
    @test Bool(summary[:heldout_prediction_execution_passed])
    @test Bool(summary[:validation_split_policy_passed])
    @test Bool(summary[:fold1_pilot_completed])
    @test Bool(summary[:all_candidate_scores_recorded])
    @test Bool(summary[:all_pointwise_scores_recorded])
    @test Bool(summary[:all_score_values_finite])
    @test Bool(summary[:expected_score_residuals_recorded])
    @test Bool(summary[:training_heldout_alignment_rows_recorded])
    @test Bool(summary[:candidate_rank_rows_recorded])
    @test Bool(summary[:comparison_anchors_not_scored])
    @test Bool(summary[:full_125_unit_batch_not_completed])
    @test Bool(summary[:publication_grade_diagnostics_blocked])
    @test Bool(summary[:full_heldout_scores_blocked_until_full_batch])
    @test Bool(summary[:no_public_fit_metric_claim])
    @test Bool(summary[:no_public_q_revision_claim])
    @test Bool(summary[:no_public_model_weight_claim])
    @test Bool(summary[:no_sparse_superiority_claim])
    @test Bool(summary[:fold1_heldout_predictive_scores_computed])
    @test Bool(summary[:heldout_predictive_scores_computed])
    @test Bool(summary[:full_heldout_predictive_scores_computed]) == false
    @test Bool(summary[:comparison_anchor_scores_computed]) == false
    @test Int(summary[:n_input_artifacts]) == length(inputs)
    @test Int(summary[:n_candidate_score_rows]) == 15
    @test Int(summary[:n_heldout_pointwise_rows]) == 120
    @test Int(summary[:n_candidate_rank_rows]) == 15
    @test Int(summary[:n_training_heldout_alignment_rows]) == 15
    @test Int(summary[:n_comparison_anchor_rows]) == 10
    @test Int(summary[:n_blocker_rows]) == 6
    @test Int(summary[:n_review_cells]) == 175
    @test Int(summary[:n_scenarios]) == 5
    @test Int(summary[:n_models]) == 3
    @test Int(summary[:n_candidate_heldout_observations]) == 120
    @test isfinite(Float64(summary[:total_heldout_elpd]))
    @test isfinite(Float64(summary[:mean_heldout_log_predictive_density]))
    @test isfinite(Float64(summary[:mean_heldout_expected_score_mae]))
    @test Int(summary[:n_publication_grade_fit_rows]) == 0
    @test Int(summary[:n_full_execution_units_completed]) == 0
    @test Int(summary[:n_blockers]) == 6
    @test Set(String(blocker) for blocker in
        summary[:remaining_public_blockers]) == Set([
            "fold1_only_remaining_folds_not_scored",
            "full_125_unit_refit_batch_not_completed",
            "comparison_anchor_mcmc_refits_not_run",
            "publication_grade_chains_and_draws_not_run",
            "external_construct_dataset_missing",
            "independent_public_scope_review_missing",
        ])
    @test String(summary[:recommendation]) ==
        "use_fold1_scores_to_validate_scoring_surface_then_expand_to_remaining_folds"
    @test String(summary[:next_gate]) ==
        "full_heldout_mgmfrm_mcmc_refit_full_batch_execution_or_external_construct_dataset_attachment"
end

function check_mgmfrm_full_heldout_mcmc_refit_candidate_batch_scoring_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_full_heldout_mcmc_refit_candidate_batch_scoring.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) ==
        "full_heldout_mcmc_refit_candidate_batch_scoring"
    @test String(fixture[:status]) ==
        "fixed_q_mgmfrm_candidate_all_fold_scores_recorded"
    @test String(fixture[:decision]) ==
        "record_all_fold_candidate_scores_keep_anchor_and_public_claims_blocked"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])
    @test Bool(fixture[:local_only])
    @test Bool(fixture[:pilot_only])
    @test Bool(fixture[:smoke_only])
    @test Bool(fixture[:fold1_scoring_completed])
    @test Bool(fixture[:fixed_q_mgmfrm_candidate_batch_completed])
    @test Bool(fixture[:fixed_q_mgmfrm_candidate_heldout_scores_computed])
    @test Bool(fixture[:full_mcmc_refit_execution_completed]) == false
    @test Bool(fixture[:full_125_unit_batch_completed]) == false
    @test Bool(fixture[:full_heldout_predictive_scores_computed]) == false
    @test Bool(fixture[:comparison_anchor_scores_computed]) == false
    @test Bool(fixture[:publication_or_registration_action]) == false
    @test Bool(fixture[:public_fit_metric_claim]) == false
    @test Bool(fixture[:public_q_revision_claim]) == false
    @test Bool(fixture[:public_model_weight_claim]) == false
    @test Bool(fixture[:sparse_mgmfrm_superiority_claim]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    controls = protocol[:fit_controls]
    @test String(protocol[:protocol_id]) ==
        "mgmfrm_full_heldout_mcmc_refit_candidate_batch_scoring_v1"
    @test String(protocol[:review_kind]) ==
        "local_full_heldout_mcmc_refit_candidate_batch_scoring"
    @test String(protocol[:execution_scope]) ==
        "all_fold_fixed_q_mgmfrm_candidate_scoring"
    @test [Int(value) for value in protocol[:selected_folds]] == [1, 2, 3, 4, 5]
    @test String(protocol[:candidate_family_scope]) ==
        "fixed_q_mgmfrm_candidates_only"
    @test String(protocol[:comparison_anchor_policy]) ==
        "recorded_not_refit_or_scored_in_candidate_batch"
    @test String(protocol[:fit_seed_policy]) ==
        "execution_plan_seed_plus_candidate_batch_offset"
    @test String(controls[:backend]) == "advancedhmc"
    @test String(controls[:sampler]) == "nuts"
    @test Int(controls[:chains]) == 1
    @test Int(controls[:draws]) == 1
    @test Int(controls[:warmup]) == 0
    @test Bool(thresholds[:require_execution_plan_passed])
    @test Bool(thresholds[:require_fold1_scoring_passed])
    @test Bool(thresholds[:require_all_candidate_folds_selected])
    @test Bool(thresholds[:require_all_candidate_refits_succeeded])
    @test Bool(thresholds[:require_all_candidate_scores_recorded])
    @test Bool(thresholds[:require_all_pointwise_scores_recorded])
    @test Bool(thresholds[:require_all_folds_covered_for_each_candidate])
    @test Bool(thresholds[:require_scenario_model_kfold_rows_recorded])
    @test Bool(thresholds[:require_comparison_anchors_recorded_not_scored])
    @test Bool(thresholds[:require_full_125_unit_batch_not_completed])
    @test Bool(thresholds[:require_anchor_model_comparison_blocked])
    @test Bool(thresholds[:require_no_publication_or_registration_action])

    inputs = fixture[:input_artifacts]
    expected_inputs = Dict(
        "mgmfrm_full_heldout_mcmc_refit_execution_plan" =>
            "test/fixtures/mgmfrm_full_heldout_mcmc_refit_execution_plan.json",
        "mgmfrm_full_heldout_mcmc_refit_fold1_scoring" =>
            "test/fixtures/mgmfrm_full_heldout_mcmc_refit_fold1_scoring.json",
        "mgmfrm_heldout_prediction_execution" =>
            "test/fixtures/mgmfrm_heldout_prediction_execution.json",
        "mgmfrm_validation_split_model_comparison_policy" =>
            "test/fixtures/mgmfrm_validation_split_model_comparison_policy.json",
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

    candidate_models = Set([
        "confirmatory_mgmfrm_current_q",
        "sparse_mgmfrm_current_q",
        "construct_reviewed_revised_q_mgmfrm",
    ])
    scenarios = Set([
        "well_specified_current_q",
        "missing_loading_revised_q",
        "sparse_signal_current_q",
        "rater_method_noise",
        "weak_dimension_ambiguous",
    ])

    candidate_units = fixture[:candidate_execution_unit_rows]
    @test length(candidate_units) == 75
    @test Set(String(row[:scenario]) for row in candidate_units) == scenarios
    @test Set(String(row[:model]) for row in candidate_units) ==
        candidate_models
    @test Set(Int(row[:fold]) for row in candidate_units) == Set(1:5)
    @test all(row -> String(row[:batch_family]) ==
        "mgmfrm_fixed_q_candidate", candidate_units)
    @test all(row -> Bool(row[:fit_attempted]), candidate_units)
    @test all(row -> Int(row[:n_train_observations]) == 32,
        candidate_units)
    @test all(row -> Int(row[:n_heldout_observations]) == 8,
        candidate_units)
    @test all(row -> Bool(row[:public_claim_allowed]) == false,
        candidate_units)

    scores = fixture[:candidate_score_rows]
    @test length(scores) == 75
    @test Set(String(row[:scenario]) for row in scores) == scenarios
    @test Set(String(row[:model]) for row in scores) == candidate_models
    @test Set(Int(row[:fold]) for row in scores) == Set(1:5)
    @test all(row -> Bool(row[:fit_succeeded]), scores)
    @test all(row -> Bool(row[:layout_matches]), scores)
    @test all(row -> Bool(row[:q_validation_passed]), scores)
    @test all(row -> Int(row[:n_train_observations]) == 32, scores)
    @test all(row -> Int(row[:n_heldout_observations]) == 8, scores)
    @test all(row -> Int(row[:n_draws]) == 1, scores)
    @test all(row -> Bool(row[:all_pointwise_scores_finite]), scores)
    @test all(row -> Bool(row[:expected_score_residuals_finite]), scores)
    @test all(row -> Bool(row[:finite_direct_draws]), scores)
    @test all(row -> Bool(row[:finite_training_pointwise_loglikelihood]),
        scores)
    @test all(row -> Bool(row[:finite_heldout_pointwise_loglikelihood]),
        scores)
    @test all(row -> String(row[:diagnostic_flag]) ==
        "insufficient_chains", scores)
    @test all(row -> Bool(row[:diagnostic_passed]) == false, scores)
    @test all(row -> Bool(row[:publication_grade_diagnostics_blocked]),
        scores)
    @test all(row -> Bool(row[:heldout_predictive_score_computed]), scores)
    @test all(row -> Bool(row[:public_fit_metric_claim_allowed]) == false,
        scores)
    @test all(row -> Bool(row[:public_model_weight_claim_allowed]) == false,
        scores)
    @test all(row -> Bool(row[:sparse_superiority_claim_allowed]) == false,
        scores)
    @test all(row -> isfinite(Float64(row[:heldout_elpd])) &&
            isfinite(Float64(row[:heldout_mean_log_predictive_density])) &&
            isfinite(Float64(row[:heldout_expected_score_mae])) &&
            isfinite(Float64(row[:heldout_expected_score_rmse])),
        scores)
    for scenario in scenarios, model in candidate_models
        @test count(row -> String(row[:scenario]) == scenario &&
                         String(row[:model]) == model, scores) == 5
    end

    pointwise = fixture[:heldout_pointwise_rows]
    @test length(pointwise) == 600
    @test all(row -> Bool(row[:finite_score]), pointwise)
    @test all(row -> Bool(row[:public_claim_allowed]) == false, pointwise)
    @test all(row -> Int(row[:fold]) in 1:5, pointwise)
    @test all(row -> Int(row[:heldout_position]) in 1:8, pointwise)
    @test all(row -> 0 <= Int(row[:observed_score]) <= 2, pointwise)
    @test all(row -> isfinite(Float64(row[:pointwise_log_predictive_density])) &&
            isfinite(Float64(row[:expected_score_mean])) &&
            isfinite(Float64(row[:observed_minus_expected_score])) &&
            isfinite(Float64(row[:absolute_expected_score_error])) &&
            isfinite(Float64(row[:squared_expected_score_error])),
        pointwise)
    for row in scores
        id = String(row[:execution_unit_id])
        @test count(point -> String(point[:execution_unit_id]) == id,
            pointwise) == 8
    end

    fold_completion = fixture[:fold_completion_rows]
    @test length(fold_completion) == 25
    @test all(row -> Bool(row[:candidate_fold_complete]), fold_completion)
    @test all(row -> Int(row[:n_candidate_models_scored]) == 3,
        fold_completion)
    @test all(row -> Int(row[:n_heldout_pointwise_rows]) == 24,
        fold_completion)
    @test all(row -> Bool(row[:public_claim_allowed]) == false,
        fold_completion)

    kfold_rows = fixture[:scenario_model_kfold_rows]
    @test length(kfold_rows) == 15
    @test all(row -> Int(row[:n_folds]) == 5, kfold_rows)
    @test all(row -> Int(row[:n_heldout_observations]) == 40, kfold_rows)
    @test all(row -> Bool(row[:all_folds_scored]), kfold_rows)
    @test all(row -> Bool(row[:all_scores_finite]), kfold_rows)
    @test all(row -> Bool(row[:publication_grade_diagnostics_blocked]),
        kfold_rows)
    @test all(row -> String(row[:comparison_scope]) ==
        "fixed_q_mgmfrm_candidates_all_folds_only", kfold_rows)
    @test all(row -> Bool(row[:public_model_weight_claim_allowed]) == false,
        kfold_rows)
    @test all(row -> Bool(row[:sparse_superiority_claim_allowed]) == false,
        kfold_rows)
    @test all(row -> isfinite(Float64(row[:heldout_elpd])) &&
            isfinite(Float64(row[:heldout_mean_log_predictive_density])) &&
            isfinite(Float64(row[:kfoldic])) &&
            isfinite(Float64(row[:heldout_expected_score_mae])) &&
            isfinite(Float64(row[:heldout_expected_score_rmse])),
        kfold_rows)

    ranks = fixture[:candidate_rank_rows]
    @test length(ranks) == 15
    @test all(row -> String(row[:comparison_scope]) ==
        "fixed_q_mgmfrm_candidates_all_folds_only", ranks)
    @test all(row -> String(row[:interpretation]) ==
        "descriptive_candidate_batch_rank_no_anchor_or_public_superiority_claim",
        ranks)
    @test all(row -> Bool(row[:public_model_weight_claim_allowed]) == false,
        ranks)
    @test all(row -> Bool(row[:sparse_superiority_claim_allowed]) == false,
        ranks)
    for scenario in scenarios
        scenario_ranks = [row for row in ranks
            if String(row[:scenario]) == scenario]
        @test sort([Int(row[:rank]) for row in scenario_ranks]) == [1, 2, 3]
        @test count(row -> Bool(row[:best_model_in_candidate_batch]),
            scenario_ranks) == 1
        @test all(row -> Float64(row[:delta_elpd_from_best]) <= 0.0,
            scenario_ranks)
    end

    anchors = fixture[:comparison_anchor_rows]
    @test length(anchors) == 50
    @test Set(String(row[:model]) for row in anchors) == Set([
        "scalar_gmfrm_baseline",
        "null_or_intercept_reference",
    ])
    @test all(row -> Bool(row[:fit_attempted]) == false, anchors)
    @test all(row -> Bool(row[:heldout_predictive_score_computed]) == false,
        anchors)
    @test all(row -> String(row[:not_scored_reason]) ==
        "comparison_anchor_not_refit_in_fixed_q_candidate_batch", anchors)
    @test all(row -> Bool(row[:public_claim_allowed]) == false, anchors)

    blockers = fixture[:blocker_rows]
    @test length(blockers) == 5
    @test Set(String(row[:blocker]) for row in blockers) == Set([
        "full_125_unit_refit_batch_not_completed",
        "comparison_anchor_mcmc_refits_not_run",
        "publication_grade_chains_and_draws_not_run",
        "external_construct_dataset_missing",
        "independent_public_scope_review_missing",
    ])
    @test all(row -> Bool(row[:resolved]) == false, blockers)

    decision = fixture[:decision_record]
    @test String(decision[:selected_decision]) ==
        "record_all_fold_candidate_scores_keep_anchor_and_public_claims_blocked"
    @test Bool(decision[:fold1_scoring_completed])
    @test Bool(decision[:fixed_q_mgmfrm_candidate_batch_completed])
    @test Bool(decision[:full_mcmc_refit_execution_completed]) == false
    @test Bool(decision[:full_125_unit_batch_completed]) == false
    @test Bool(decision[:full_heldout_predictive_scores_computed]) == false
    @test Bool(decision[:comparison_anchor_scores_computed]) == false
    @test Bool(decision[:public_fit_metric_claim_allowed]) == false
    @test Bool(decision[:public_q_revision_claim_allowed]) == false
    @test Bool(decision[
        :model_weight_or_sparse_superiority_claim_allowed]) == false
    @test String(decision[:required_followup]) ==
        "run_scalar_and_reference_anchor_refits_or_external_construct_dataset_review"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:local_only])
    @test Bool(summary[:pilot_only])
    @test Bool(summary[:smoke_only])
    @test Bool(summary[:all_input_artifacts_present])
    @test Bool(summary[:all_expected_schemas])
    @test Bool(summary[:all_input_summaries_passed])
    @test Bool(summary[:execution_plan_passed])
    @test Bool(summary[:fold1_scoring_passed])
    @test Bool(summary[:heldout_prediction_execution_passed])
    @test Bool(summary[:validation_split_policy_passed])
    @test Bool(summary[:all_candidate_folds_selected])
    @test Bool(summary[:all_candidate_refits_succeeded])
    @test Bool(summary[:all_candidate_scores_recorded])
    @test Bool(summary[:all_pointwise_scores_recorded])
    @test Bool(summary[:all_score_values_finite])
    @test Bool(summary[:all_folds_covered_for_each_candidate])
    @test Bool(summary[:scenario_model_kfold_rows_recorded])
    @test Bool(summary[:candidate_rank_rows_recorded])
    @test Bool(summary[:comparison_anchors_recorded_not_scored])
    @test Bool(summary[:full_125_unit_batch_not_completed])
    @test Bool(summary[:publication_grade_diagnostics_blocked])
    @test Bool(summary[:anchor_model_comparison_blocked])
    @test Bool(summary[:external_construct_dataset_still_required])
    @test Bool(summary[:no_public_fit_metric_claim])
    @test Bool(summary[:no_public_q_revision_claim])
    @test Bool(summary[:no_public_model_weight_claim])
    @test Bool(summary[:no_sparse_superiority_claim])
    @test Bool(summary[:fixed_q_mgmfrm_candidate_batch_completed])
    @test Bool(summary[:fixed_q_mgmfrm_candidate_heldout_scores_computed])
    @test Bool(summary[:full_125_unit_batch_completed]) == false
    @test Bool(summary[:full_heldout_predictive_scores_computed]) == false
    @test Bool(summary[:comparison_anchor_scores_computed]) == false
    @test Int(summary[:n_input_artifacts]) == length(inputs)
    @test Int(summary[:n_planned_execution_units]) == 125
    @test Int(summary[:n_candidate_execution_unit_rows]) == 75
    @test Int(summary[:n_candidate_score_rows]) == 75
    @test Int(summary[:n_heldout_pointwise_rows]) == 600
    @test Int(summary[:n_fold_completion_rows]) == 25
    @test Int(summary[:n_scenario_model_kfold_rows]) == 15
    @test Int(summary[:n_candidate_rank_rows]) == 15
    @test Int(summary[:n_comparison_anchor_rows]) == 50
    @test Int(summary[:n_blocker_rows]) == 5
    @test Int(summary[:n_review_cells]) == 855
    @test Int(summary[:n_scenarios]) == 5
    @test Int(summary[:n_models]) == 3
    @test Int(summary[:n_folds]) == 5
    @test Int(summary[:n_candidate_heldout_observations]) == 600
    @test isfinite(Float64(summary[:total_heldout_elpd]))
    @test isfinite(Float64(summary[:mean_heldout_log_predictive_density]))
    @test isfinite(Float64(summary[:mean_heldout_expected_score_mae]))
    @test Int(summary[:n_publication_grade_fit_rows]) == 0
    @test Int(summary[:n_full_execution_units_completed]) == 75
    @test Int(summary[:n_full_execution_units_remaining]) == 50
    @test Int(summary[:n_blockers]) == 5
    @test Set(String(blocker) for blocker in
        summary[:remaining_public_blockers]) == Set([
            "full_125_unit_refit_batch_not_completed",
            "comparison_anchor_mcmc_refits_not_run",
            "publication_grade_chains_and_draws_not_run",
            "external_construct_dataset_missing",
            "independent_public_scope_review_missing",
        ])
    @test String(summary[:recommendation]) ==
        "run_scalar_and_reference_anchor_refits_or_attach_external_construct_dataset_next"
    @test String(summary[:next_gate]) ==
        "run_scalar_and_reference_anchor_refits_or_external_construct_dataset_review"
end

function check_mgmfrm_full_heldout_mcmc_refit_anchor_scoring_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_full_heldout_mcmc_refit_anchor_scoring.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) ==
        "full_heldout_mcmc_refit_anchor_scoring"
    @test String(fixture[:status]) ==
        "scalar_and_reference_anchor_scores_recorded"
    @test String(fixture[:decision]) ==
        "record_anchor_scores_join_candidate_comparison_keep_public_claims_blocked"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])
    @test Bool(fixture[:local_only])
    @test Bool(fixture[:pilot_only])
    @test Bool(fixture[:smoke_only])
    @test Bool(fixture[:scalar_anchor_scores_computed])
    @test Bool(fixture[:reference_anchor_scores_computed])
    @test Bool(fixture[:comparison_anchor_scores_computed])
    @test Bool(fixture[:full_125_unit_scoring_completed])
    @test Bool(fixture[:full_heldout_predictive_scores_computed])
    @test Bool(fixture[:full_mcmc_refit_execution_completed]) == false
    @test Bool(fixture[:full_125_unit_mcmc_refit_batch_completed]) == false
    @test Bool(fixture[:publication_or_registration_action]) == false
    @test Bool(fixture[:public_fit_metric_claim]) == false
    @test Bool(fixture[:public_q_revision_claim]) == false
    @test Bool(fixture[:public_model_weight_claim]) == false
    @test Bool(fixture[:sparse_mgmfrm_superiority_claim]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    controls = protocol[:fit_controls]
    reference_controls = protocol[:reference_controls]
    @test String(protocol[:protocol_id]) ==
        "mgmfrm_full_heldout_mcmc_refit_anchor_scoring_v1"
    @test String(protocol[:review_kind]) ==
        "local_full_heldout_anchor_scoring"
    @test String(protocol[:execution_scope]) ==
        "all_fold_scalar_and_reference_anchor_scoring"
    @test [Int(value) for value in protocol[:selected_folds]] == [1, 2, 3, 4, 5]
    @test Set(String(value) for value in protocol[:anchor_models]) == Set([
        "scalar_gmfrm_baseline",
        "null_or_intercept_reference",
    ])
    @test String(protocol[:comparison_scope]) ==
        "fixed_q_mgmfrm_candidates_with_scalar_and_reference_anchors"
    @test String(controls[:backend]) == "advancedhmc"
    @test String(controls[:sampler]) == "nuts"
    @test Int(controls[:chains]) == 1
    @test Int(controls[:draws]) == 1
    @test Int(controls[:warmup]) == 0
    @test String(reference_controls[:smoothing]) == "symmetric_dirichlet"
    @test Float64(reference_controls[:alpha]) == 1.0
    @test [Int(value) for value in reference_controls[:categories]] == [0, 1, 2]
    @test Bool(thresholds[:require_anchor_units_selected])
    @test Bool(thresholds[:require_scalar_anchor_refits_succeeded])
    @test Bool(thresholds[:require_reference_anchor_scores_recorded])
    @test Bool(thresholds[:require_combined_model_kfold_rows_recorded])
    @test Bool(thresholds[:require_combined_rank_rows_recorded])
    @test Bool(thresholds[:require_candidate_and_anchor_scores_cover_125_units])
    @test Bool(thresholds[:require_no_publication_or_registration_action])

    inputs = fixture[:input_artifacts]
    expected_inputs = Dict(
        "mgmfrm_full_heldout_mcmc_refit_execution_plan" =>
            "test/fixtures/mgmfrm_full_heldout_mcmc_refit_execution_plan.json",
        "mgmfrm_full_heldout_mcmc_refit_candidate_batch_scoring" =>
            "test/fixtures/mgmfrm_full_heldout_mcmc_refit_candidate_batch_scoring.json",
        "mgmfrm_heldout_prediction_execution" =>
            "test/fixtures/mgmfrm_heldout_prediction_execution.json",
        "mgmfrm_validation_split_model_comparison_policy" =>
            "test/fixtures/mgmfrm_validation_split_model_comparison_policy.json",
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

    scenarios = Set([
        "well_specified_current_q",
        "missing_loading_revised_q",
        "sparse_signal_current_q",
        "rater_method_noise",
        "weak_dimension_ambiguous",
    ])
    anchor_models = Set([
        "scalar_gmfrm_baseline",
        "null_or_intercept_reference",
    ])

    units = fixture[:anchor_execution_unit_rows]
    @test length(units) == 50
    @test Set(String(row[:scenario]) for row in units) == scenarios
    @test Set(String(row[:model]) for row in units) == anchor_models
    @test Set(Int(row[:fold]) for row in units) == Set(1:5)
    @test all(row -> Int(row[:n_train_observations]) == 32, units)
    @test all(row -> Int(row[:n_heldout_observations]) == 8, units)
    @test all(row -> Bool(row[:public_claim_allowed]) == false, units)

    scores = fixture[:anchor_score_rows]
    @test length(scores) == 50
    @test Set(String(row[:scenario]) for row in scores) == scenarios
    @test Set(String(row[:model]) for row in scores) == anchor_models
    @test Set(Int(row[:fold]) for row in scores) == Set(1:5)
    @test count(row -> String(row[:model]) == "scalar_gmfrm_baseline",
        scores) == 25
    @test count(row -> String(row[:model]) == "null_or_intercept_reference",
        scores) == 25
    @test all(row -> Bool(row[:fit_succeeded]), scores)
    @test all(row -> Bool(row[:scoring_succeeded]), scores)
    @test all(row -> Int(row[:n_train_observations]) == 32, scores)
    @test all(row -> Int(row[:n_heldout_observations]) == 8, scores)
    @test all(row -> Bool(row[:all_pointwise_scores_finite]), scores)
    @test all(row -> Bool(row[:expected_score_residuals_finite]), scores)
    @test all(row -> Bool(row[:finite_training_pointwise_loglikelihood]),
        scores)
    @test all(row -> Bool(row[:finite_heldout_pointwise_loglikelihood]),
        scores)
    @test all(row -> Bool(row[:publication_grade_diagnostics_blocked]),
        scores)
    @test all(row -> Bool(row[:heldout_predictive_score_computed]), scores)
    @test all(row -> Bool(row[:public_fit_metric_claim_allowed]) == false,
        scores)
    @test all(row -> Bool(row[:public_model_weight_claim_allowed]) == false,
        scores)
    @test all(row -> Bool(row[:sparse_superiority_claim_allowed]) == false,
        scores)
    @test all(row -> isfinite(Float64(row[:heldout_elpd])) &&
            isfinite(Float64(row[:heldout_mean_log_predictive_density])) &&
            isfinite(Float64(row[:heldout_expected_score_mae])) &&
            isfinite(Float64(row[:heldout_expected_score_rmse])),
        scores)
    @test all(row -> String(row[:model]) != "scalar_gmfrm_baseline" ||
            (Bool(row[:mcmc_refit_attempted]) &&
             !Bool(row[:analytic_reference_scored]) &&
             String(row[:returned_type]) == "GMFRMFit"),
        scores)
    @test all(row -> String(row[:model]) != "null_or_intercept_reference" ||
            (!Bool(row[:mcmc_refit_attempted]) &&
             Bool(row[:analytic_reference_scored]) &&
             String(row[:returned_type]) == "AnalyticInterceptReference"),
        scores)
    for scenario in scenarios, model in anchor_models
        @test count(row -> String(row[:scenario]) == scenario &&
                         String(row[:model]) == model, scores) == 5
    end

    pointwise = fixture[:heldout_pointwise_rows]
    @test length(pointwise) == 400
    @test all(row -> Bool(row[:finite_score]), pointwise)
    @test all(row -> Bool(row[:public_claim_allowed]) == false, pointwise)
    @test all(row -> Int(row[:fold]) in 1:5, pointwise)
    @test all(row -> Int(row[:heldout_position]) in 1:8, pointwise)
    @test all(row -> 0 <= Int(row[:observed_score]) <= 2, pointwise)
    @test all(row -> isfinite(Float64(row[:pointwise_log_predictive_density])) &&
            isfinite(Float64(row[:expected_score_mean])) &&
            isfinite(Float64(row[:observed_minus_expected_score])) &&
            isfinite(Float64(row[:absolute_expected_score_error])) &&
            isfinite(Float64(row[:squared_expected_score_error])),
        pointwise)
    for row in scores
        id = String(row[:execution_unit_id])
        @test count(point -> String(point[:execution_unit_id]) == id,
            pointwise) == 8
    end

    reference_probabilities = fixture[:reference_probability_rows]
    @test length(reference_probabilities) == 75
    @test Set(Int(row[:category]) for row in reference_probabilities) ==
        Set([0, 1, 2])
    for score in scores
        String(score[:model]) == "null_or_intercept_reference" || continue
        probability_rows = [row for row in reference_probabilities
            if String(row[:execution_unit_id]) ==
               String(score[:execution_unit_id])]
        @test length(probability_rows) == 3
        @test sum(Float64(row[:smoothed_probability])
            for row in probability_rows) ≈ 1.0
    end

    fold_completion = fixture[:anchor_fold_completion_rows]
    @test length(fold_completion) == 25
    @test all(row -> Bool(row[:anchor_fold_complete]), fold_completion)
    @test all(row -> Int(row[:n_anchor_models_scored]) == 2,
        fold_completion)
    @test all(row -> Int(row[:n_heldout_pointwise_rows]) == 16,
        fold_completion)

    anchor_kfold = fixture[:anchor_scenario_model_kfold_rows]
    @test length(anchor_kfold) == 10
    @test all(row -> Int(row[:n_folds]) == 5, anchor_kfold)
    @test all(row -> Int(row[:n_heldout_observations]) == 40,
        anchor_kfold)
    @test all(row -> Bool(row[:all_folds_scored]), anchor_kfold)
    @test all(row -> Bool(row[:all_scores_finite]), anchor_kfold)
    @test all(row -> String(row[:comparison_scope]) ==
        "anchor_models_all_folds_only", anchor_kfold)

    combined = fixture[:combined_scenario_model_kfold_rows]
    @test length(combined) == 25
    @test Set(String(row[:model]) for row in combined) == Set([
        "confirmatory_mgmfrm_current_q",
        "sparse_mgmfrm_current_q",
        "construct_reviewed_revised_q_mgmfrm",
        "scalar_gmfrm_baseline",
        "null_or_intercept_reference",
    ])
    @test all(row -> Int(row[:n_folds]) == 5, combined)
    @test all(row -> Int(row[:n_heldout_observations]) == 40, combined)
    @test all(row -> String(row[:comparison_scope]) ==
        "fixed_q_mgmfrm_candidates_with_scalar_and_reference_anchors",
        combined)
    @test all(row -> Bool(row[:public_model_weight_claim_allowed]) == false,
        combined)
    @test all(row -> Bool(row[:sparse_superiority_claim_allowed]) == false,
        combined)

    ranks = fixture[:combined_rank_rows]
    @test length(ranks) == 25
    @test all(row -> String(row[:interpretation]) ==
        "descriptive_full_scoring_rank_no_public_superiority_claim", ranks)
    @test all(row -> Bool(row[:public_model_weight_claim_allowed]) == false,
        ranks)
    @test all(row -> Bool(row[:sparse_superiority_claim_allowed]) == false,
        ranks)
    for scenario in scenarios
        scenario_ranks = [row for row in ranks
            if String(row[:scenario]) == scenario]
        @test sort([Int(row[:rank]) for row in scenario_ranks]) ==
            [1, 2, 3, 4, 5]
        @test count(row -> Bool(row[
            :best_model_in_descriptive_125_unit_comparison]),
            scenario_ranks) == 1
        @test all(row -> Float64(row[:delta_elpd_from_best]) <= 0.0,
            scenario_ranks)
    end

    resolved = fixture[:resolved_gate_rows]
    @test length(resolved) == 3
    @test all(row -> Bool(row[:resolved]), resolved)
    @test all(row -> Bool(row[:public_claim_allowed]) == false, resolved)

    blockers = fixture[:blocker_rows]
    @test length(blockers) == 5
    @test Set(String(row[:blocker]) for row in blockers) == Set([
        "publication_grade_chains_and_draws_not_run",
        "reference_anchor_is_analytic_not_mcmc_refit",
        "external_construct_dataset_missing",
        "public_model_weight_calibration_not_authorized",
        "independent_public_scope_review_missing",
    ])
    @test all(row -> Bool(row[:resolved]) == false, blockers)

    decision = fixture[:decision_record]
    @test String(decision[:selected_decision]) ==
        "record_anchor_scores_join_candidate_comparison_keep_public_claims_blocked"
    @test Bool(decision[:scalar_anchor_scores_computed])
    @test Bool(decision[:reference_anchor_scores_computed])
    @test Bool(decision[:comparison_anchor_scores_computed])
    @test Bool(decision[:full_125_unit_scoring_completed])
    @test Bool(decision[:full_mcmc_refit_execution_completed]) == false
    @test Bool(decision[:full_125_unit_mcmc_refit_batch_completed]) == false
    @test Bool(decision[:public_fit_metric_claim_allowed]) == false
    @test Bool(decision[:public_q_revision_claim_allowed]) == false
    @test Bool(decision[
        :model_weight_or_sparse_superiority_claim_allowed]) == false
    @test String(decision[:required_followup]) ==
        "publication_grade_refit_diagnostics_or_external_construct_dataset_review"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:all_input_artifacts_present])
    @test Bool(summary[:all_expected_schemas])
    @test Bool(summary[:all_input_summaries_passed])
    @test Bool(summary[:anchor_units_selected])
    @test Bool(summary[:scalar_anchor_refits_succeeded])
    @test Bool(summary[:reference_anchor_scores_recorded])
    @test Bool(summary[:all_anchor_scores_recorded])
    @test Bool(summary[:all_anchor_pointwise_scores_recorded])
    @test Bool(summary[:all_anchor_score_values_finite])
    @test Bool(summary[:anchor_fold_completion_rows_recorded])
    @test Bool(summary[:anchor_kfold_rows_recorded])
    @test Bool(summary[:combined_model_kfold_rows_recorded])
    @test Bool(summary[:combined_rank_rows_recorded])
    @test Bool(summary[:candidate_and_anchor_scores_cover_125_units])
    @test Bool(summary[:comparison_anchor_scores_computed])
    @test Bool(summary[:publication_grade_diagnostics_blocked])
    @test Bool(summary[:external_construct_dataset_still_required])
    @test Bool(summary[:no_public_fit_metric_claim])
    @test Bool(summary[:no_public_q_revision_claim])
    @test Bool(summary[:no_public_model_weight_claim])
    @test Bool(summary[:no_sparse_superiority_claim])
    @test Bool(summary[:full_125_unit_scoring_completed])
    @test Bool(summary[:full_heldout_predictive_scores_computed])
    @test Bool(summary[:full_mcmc_refit_execution_completed]) == false
    @test Bool(summary[:full_125_unit_mcmc_refit_batch_completed]) == false
    @test Int(summary[:n_planned_execution_units]) == 125
    @test Int(summary[:n_candidate_score_rows]) == 75
    @test Int(summary[:n_candidate_pointwise_rows]) == 600
    @test Int(summary[:n_anchor_execution_unit_rows]) == 50
    @test Int(summary[:n_anchor_score_rows]) == 50
    @test Int(summary[:n_scalar_anchor_score_rows]) == 25
    @test Int(summary[:n_reference_anchor_score_rows]) == 25
    @test Int(summary[:n_anchor_heldout_pointwise_rows]) == 400
    @test Int(summary[:n_reference_probability_rows]) == 75
    @test Int(summary[:n_anchor_fold_completion_rows]) == 25
    @test Int(summary[:n_anchor_scenario_model_kfold_rows]) == 10
    @test Int(summary[:n_combined_scenario_model_kfold_rows]) == 25
    @test Int(summary[:n_combined_rank_rows]) == 25
    @test Int(summary[:n_full_execution_units_scored]) == 125
    @test Int(summary[:n_full_execution_units_remaining_for_scoring]) == 0
    @test Int(summary[:n_candidate_and_anchor_pointwise_rows]) == 1000
    @test isfinite(Float64(summary[:total_anchor_heldout_elpd]))
    @test isfinite(Float64(summary[:mean_anchor_heldout_log_predictive_density]))
    @test isfinite(Float64(summary[:mean_anchor_heldout_expected_score_mae]))
    @test Int(summary[:n_publication_grade_anchor_fit_rows]) == 0
    @test Set(String(blocker) for blocker in
        summary[:remaining_public_blockers]) == Set([
            "publication_grade_chains_and_draws_not_run",
            "reference_anchor_is_analytic_not_mcmc_refit",
            "external_construct_dataset_missing",
            "public_model_weight_calibration_not_authorized",
            "independent_public_scope_review_missing",
        ])
    @test String(summary[:recommendation]) ==
        "use_descriptive_125_unit_comparison_to_plan_publication_grade_refits_or_external_construct_dataset_review"
    @test String(summary[:next_gate]) ==
        "publication_grade_refit_diagnostics_or_external_construct_dataset_review"
end
