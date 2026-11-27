function check_gmfrm_guarded_exposure_review_fixture(fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) == "bayesianmgmfrm.gmfrm_guarded_exposure_review.v1"
    @test String(fixture[:family]) == "gmfrm"
    @test String(fixture[:scope]) == "scalar_gmfrm_fit_ready_candidate"
    @test String(fixture[:status]) == "guarded_exposure_review_recorded"
    @test String(fixture[:decision]) == "enable_guarded_experimental"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) == "scalar_gmfrm_guarded_exposure_review_v1"
    @test String(protocol[:review_kind]) == "local_guarded_exposure_review"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test String(protocol[:entrypoint_under_review]) == "fit(spec; experimental = true)"
    @test Bool(thresholds[:require_candidate_chain_passed])
    @test Bool(thresholds[:require_stress_chain_grid_passed])
    @test Bool(thresholds[:require_recovery_smoke_passed])
    @test Bool(thresholds[:require_baseline_comparison_passed])
    @test Bool(thresholds[:require_baseline_calibration_grid_passed])
    @test Bool(thresholds[:require_interval_decision_grid_passed])
    @test Bool(thresholds[:require_sparse_design_grid_passed])
    @test Bool(thresholds[:require_waic_influence_review_passed])
    @test Bool(thresholds[:require_psis_loo_review_passed])
    @test Bool(thresholds[:require_exact_loo_or_kfold_review_passed])
    @test Bool(thresholds[:require_guarded_fit_api_dry_run_passed])
    @test Bool(thresholds[:require_guarded_fit_method_wiring_passed])
    @test Bool(thresholds[:require_experimental_fit_validation_grid_passed])
    @test Bool(thresholds[:require_posterior_predictive_grid_passed])
    @test Bool(thresholds[:require_sparse_pathology_recovery_grid_passed])
    @test Bool(thresholds[:require_prior_likelihood_sensitivity_grid_passed])
    @test Bool(thresholds[:require_real_data_case_study_passed])
    @test Bool(thresholds[:require_claim_recovery_reproduction_archive_passed])
    @test Bool(thresholds[:require_broader_experimental_exposure_decision_review_passed])
    @test Bool(thresholds[:require_tam_direct_execution_recorded])
    @test Bool(thresholds[:require_tam_raw_archive_integrity_passed])
    @test Bool(thresholds[:require_tam_post_execution_packet_integrity_passed])
    @test Bool(thresholds[:require_tam_evidence_nontransfer_to_gmfrm_mgmfrm])
    @test Bool(thresholds[:require_tam_independent_review_pending_recorded])
    @test Bool(thresholds[:require_tam_pre_execution_lineage_mismatch_recorded])
    @test Bool(thresholds[:require_mgmfrm_sparse_recovery_grid_passed])
    @test Bool(thresholds[:require_mgmfrm_guarded_fit_method_wiring_passed])
    @test Bool(thresholds[:require_mgmfrm_guarded_fit_validation_grid_passed])
    @test Bool(thresholds[:require_mgmfrm_guarded_fit_api_dry_run_passed])
    @test Bool(thresholds[:require_mgmfrm_guarded_fit_public_exposure_review_passed])
    @test Bool(thresholds[:require_prediction_target_and_model_weight_policy_passed])
    @test Bool(thresholds[:require_dff_estimand_validation_grid_passed])
    @test Bool(thresholds[
        :require_mgmfrm_heldout_prediction_validation_policy_passed])
    @test Bool(thresholds[
        :require_mgmfrm_heldout_prediction_simulation_grid_passed])
    @test Bool(thresholds[
        :require_mgmfrm_heldout_prediction_execution_passed])
    @test Bool(thresholds[
        :require_mgmfrm_full_heldout_refit_or_construct_validation_review_passed])
    @test Bool(thresholds[
        :require_mgmfrm_full_heldout_mcmc_refit_execution_plan_passed])
    @test Bool(thresholds[
        :require_mgmfrm_full_heldout_mcmc_refit_batch_smoke_passed])
    @test Bool(thresholds[
        :require_mgmfrm_full_heldout_mcmc_refit_fold1_pilot_passed])
    @test Bool(thresholds[
        :require_mgmfrm_full_heldout_mcmc_refit_fold1_scoring_passed])
    @test Bool(thresholds[
        :require_mgmfrm_full_heldout_mcmc_refit_candidate_batch_scoring_passed])
    @test Bool(thresholds[
        :require_mgmfrm_full_heldout_mcmc_refit_anchor_scoring_passed])
    @test Bool(thresholds[
        :require_mgmfrm_publication_grade_refit_gate_passed])
    @test Bool(thresholds[
        :require_mgmfrm_publication_grade_refit_pilot_plan_passed])
    @test Bool(thresholds[
        :require_mgmfrm_fit_threshold_q_heldout_linkage_passed])
    @test Bool(thresholds[:high_variance_waic_blocks_public_exposure])
    @test Bool(thresholds[:psis_loo_or_exact_loo_required_before_exposure])
    @test Bool(thresholds[:high_pareto_k_blocks_public_exposure])
    @test Bool(thresholds[:exact_loo_or_kfold_required_before_exposure])
    @test Bool(thresholds[:guarded_fit_api_dry_run_required_before_exposure])
    @test Bool(thresholds[:guarded_fit_method_wiring_required_before_exposure])
    @test Bool(thresholds[:experimental_fit_validation_grid_required_before_exposure])
    @test Bool(thresholds[:posterior_predictive_grid_required_before_exposure])
    @test Bool(thresholds[:sparse_pathology_recovery_grid_required_before_exposure])
    @test Bool(thresholds[:prior_likelihood_sensitivity_grid_required_before_exposure])
    @test Bool(thresholds[:real_data_case_study_required_before_exposure])
    @test Bool(thresholds[:claim_level_recovery_and_reproduction_archive_required_before_exposure])
    @test Bool(thresholds[:broader_experimental_exposure_decision_review_required_before_exposure])

    reviewed = fixture[:reviewed_artifacts]
    @test length(reviewed) == 32
    expected_artifacts = Dict(
        "candidate_chain_study" =>
            "test/fixtures/gmfrm_candidate_chain_study.json",
        "stress_chain_grid" =>
            "test/fixtures/gmfrm_stress_chain_grid.json",
        "recovery_smoke_study" =>
            "test/fixtures/gmfrm_recovery_smoke.json",
        "baseline_comparison" =>
            "test/fixtures/gmfrm_baseline_comparison.json",
        "baseline_calibration_grid" =>
            "test/fixtures/gmfrm_baseline_calibration_grid.json",
        "interval_decision_grid" =>
            "test/fixtures/gmfrm_interval_decision_grid.json",
        "sparse_design_grid" =>
            "test/fixtures/gmfrm_sparse_design_grid.json",
        "waic_influence_review" =>
            "test/fixtures/gmfrm_waic_influence_review.json",
        "psis_loo_review" =>
            "test/fixtures/gmfrm_psis_loo_review.json",
        "exact_loo_or_kfold_review" =>
            "test/fixtures/gmfrm_exact_loo_or_kfold_review.json",
        "guarded_fit_api_dry_run" =>
            "test/fixtures/gmfrm_guarded_fit_api_dry_run.json",
        "guarded_fit_method_wiring" =>
            "test/fixtures/gmfrm_guarded_fit_method_wiring.json",
        "experimental_fit_validation_grid" =>
            "test/fixtures/gmfrm_experimental_fit_validation_grid.json",
        "posterior_predictive_grid" =>
            "test/fixtures/gmfrm_posterior_predictive_grid.json",
        "sparse_pathology_recovery_grid" =>
            "test/fixtures/gmfrm_sparse_pathology_recovery_grid.json",
        "prior_likelihood_sensitivity_grid" =>
            "test/fixtures/gmfrm_prior_likelihood_sensitivity_grid.json",
        "real_data_case_study" =>
            "test/fixtures/gmfrm_real_data_case_study.json",
        "claim_recovery_reproduction_archive" =>
            "test/fixtures/gmfrm_claim_recovery_reproduction_archive.json",
        "broader_experimental_exposure_decision_review" =>
            "test/fixtures/gmfrm_broader_experimental_exposure_decision_review.json",
        "mgmfrm_sparse_recovery_grid" =>
            "test/fixtures/mgmfrm_sparse_recovery_grid.json",
        "mgmfrm_guarded_fit_method_wiring" =>
            "test/fixtures/mgmfrm_guarded_fit_method_wiring.json",
        "mgmfrm_guarded_fit_validation_grid" =>
            "test/fixtures/mgmfrm_guarded_fit_validation_grid.json",
        "mgmfrm_guarded_fit_api_dry_run" =>
            "test/fixtures/mgmfrm_guarded_fit_api_dry_run.json",
        "mgmfrm_guarded_fit_public_exposure_review" =>
            "test/fixtures/mgmfrm_guarded_fit_public_exposure_review.json",
        "prediction_target_and_model_weight_policy" =>
            "test/fixtures/gmfrm_prediction_target_and_model_weight_policy.json",
        "mgmfrm_manual_public_scope_review_for_fit" =>
            "test/fixtures/mgmfrm_manual_public_scope_review_for_fit.json",
        "dff_estimand_validation_grid" =>
            "test/fixtures/gmfrm_dff_estimand_validation_grid.json",
        "manuscript_scale_simulation_grid" =>
            "test/fixtures/gmfrm_manuscript_scale_simulation_grid.json",
        "tam_direct_agreement_multireplication" =>
            "test/fixtures/mgmfrm_tam_direct_agreement_multireplication.json",
        "tam_direct_agreement_raw_archive_audit" =>
            "test/fixtures/mgmfrm_tam_direct_agreement_raw_archive_audit.json",
        "tam_direct_agreement_post_execution_review_packet" =>
            "test/fixtures/mgmfrm_tam_direct_agreement_post_execution_review_packet.json",
        "full_paper_reproduction_archive" =>
            "test/fixtures/gmfrm_full_paper_reproduction_archive.json",
    )
    @test Set(String(row[:artifact]) for row in reviewed) ==
        Set(keys(expected_artifacts))
    for row in reviewed
        artifact = String(row[:artifact])
        path = String(row[:path])
        @test expected_artifacts[artifact] == path
        @test String(row[:sha256]) == file_sha256(joinpath(root, path))
        if artifact in ("mgmfrm_sparse_recovery_grid",
                "mgmfrm_guarded_fit_method_wiring",
                "mgmfrm_guarded_fit_validation_grid",
                "mgmfrm_guarded_fit_api_dry_run",
                "mgmfrm_guarded_fit_public_exposure_review",
                "mgmfrm_manual_public_scope_review_for_fit")
            @test String(row[:family]) == "mgmfrm"
            @test String(row[:scope]) ==
                "minimal_confirmatory_mgmfrm_candidate"
        elseif artifact == "dff_estimand_validation_grid"
            @test String(row[:family]) == "gmfrm"
            @test String(row[:scope]) ==
                "dff_estimand_and_validation_grid"
        elseif artifact == "prediction_target_and_model_weight_policy"
            @test String(row[:family]) == "gmfrm"
            @test String(row[:scope]) ==
                "prediction_target_and_model_weight_policy"
        elseif artifact == "manuscript_scale_simulation_grid"
            @test String(row[:family]) == "gmfrm"
            @test String(row[:scope]) == "manuscript_scale_simulation_grid"
        elseif startswith(artifact, "tam_direct_agreement")
            @test String(row[:family]) == "mfrm"
            @test startswith(String(row[:scope]), "tam_direct_")
        elseif artifact == "full_paper_reproduction_archive"
            @test String(row[:family]) == "gmfrm"
            @test String(row[:scope]) == "full_paper_reproduction_archive"
        elseif artifact == "broader_experimental_exposure_decision_review"
            @test String(row[:family]) == "gmfrm"
            @test String(row[:scope]) == "broader_generalized_exposure_decision"
        else
            @test String(row[:family]) == "gmfrm"
            @test String(row[:scope]) == "scalar_gmfrm_fit_ready_candidate"
        end
        if startswith(artifact, "tam_direct_agreement")
            @test isnothing(row[:public_fit])
            @test isnothing(row[:experimental_public])
            @test isnothing(row[:fit_ready])
        elseif artifact in (
                "guarded_fit_method_wiring",
                "experimental_fit_validation_grid",
                "posterior_predictive_grid",
                "sparse_pathology_recovery_grid",
                "prior_likelihood_sensitivity_grid",
                "real_data_case_study",
                "claim_recovery_reproduction_archive",
                "broader_experimental_exposure_decision_review",
                "prediction_target_and_model_weight_policy",
                "mgmfrm_guarded_fit_method_wiring",
                "mgmfrm_guarded_fit_validation_grid",
                "mgmfrm_guarded_fit_api_dry_run",
                "mgmfrm_guarded_fit_public_exposure_review",
                "mgmfrm_manual_public_scope_review_for_fit",
                "manuscript_scale_simulation_grid",
                "full_paper_reproduction_archive")
            @test Bool(row[:public_fit])
            @test Bool(row[:experimental_public])
            @test Bool(row[:fit_ready])
        else
            @test Bool(row[:public_fit]) == false
            @test Bool(row[:fit_ready]) == false
        end
    end

    chain = only(row for row in reviewed
        if String(row[:artifact]) == "candidate_chain_study")
    @test Bool(chain[:summary][:overall_passed])
    @test Int(chain[:summary][:n_divergences]) == 0
    @test Int(chain[:summary][:n_max_treedepth]) == 0
    stress = only(row for row in reviewed
        if String(row[:artifact]) == "stress_chain_grid")
    @test Bool(stress[:summary][:overall_passed])
    @test Int(stress[:summary][:n_scenarios]) == 3
    recovery = only(row for row in reviewed
        if String(row[:artifact]) == "recovery_smoke_study")
    @test Bool(recovery[:summary][:passed])
    @test String(recovery[:summary][:sampler_flag]) == "ok"
    baseline = only(row for row in reviewed
        if String(row[:artifact]) == "baseline_comparison")
    @test Bool(baseline[:summary][:passed])
    @test Bool(baseline[:summary][:any_high_variance_waic])
    grid = only(row for row in reviewed
        if String(row[:artifact]) == "baseline_calibration_grid")
    @test Bool(grid[:summary][:passed])
    @test Int(grid[:summary][:n_passed_scenarios]) == 3
    @test Bool(grid[:summary][:any_high_variance_waic])
    interval_grid = only(row for row in reviewed
        if String(row[:artifact]) == "interval_decision_grid")
    @test Bool(interval_grid[:summary][:passed])
    @test Int(interval_grid[:summary][:n_passed_scenarios]) == 3
    @test Int(interval_grid[:summary][:keep_internal_decision_count]) == 3
    @test String(interval_grid[:summary][:decision_stability]) ==
        "stable_keep_internal"
    @test Bool(interval_grid[:summary][:any_high_variance_waic])
    sparse_grid = only(row for row in reviewed
        if String(row[:artifact]) == "sparse_design_grid")
    @test Bool(sparse_grid[:summary][:passed])
    @test Int(sparse_grid[:summary][:n_passed_scenarios]) == 3
    @test Int(sparse_grid[:summary][:n_sparse_validation_records]) == 3
    @test Bool(sparse_grid[:summary][:all_sparse_validations_passed])
    @test Bool(sparse_grid[:summary][:all_location_designs_full_rank])
    @test Int(sparse_grid[:summary][:keep_internal_decision_count]) == 3
    @test String(sparse_grid[:summary][:decision_stability]) ==
        "stable_keep_internal"
    @test String(sparse_grid[:summary][:next_gate]) ==
        "scalar_gmfrm_waic_influence_review"
    waic_review = only(row for row in reviewed
        if String(row[:artifact]) == "waic_influence_review")
    @test Bool(waic_review[:summary][:passed])
    @test Int(waic_review[:summary][:n_scenario_reviews]) == 6
    @test Int(waic_review[:summary][:n_passed_scenarios]) == 6
    @test Int(waic_review[:summary][:n_flagged_model_observations]) > 0
    @test Int(waic_review[:summary][:n_best_model_changes_after_flagged_removal]) >= 1
    @test Bool(waic_review[:summary][:all_masked_comparisons_finite])
    @test String(waic_review[:summary][:next_gate]) ==
        "scalar_gmfrm_psis_loo_review"
    psis_review = only(row for row in reviewed
        if String(row[:artifact]) == "psis_loo_review")
    @test Bool(psis_review[:summary][:passed])
    @test Int(psis_review[:summary][:n_scenario_reviews]) == 6
    @test Int(psis_review[:summary][:n_passed_scenarios]) == 6
    @test Int(psis_review[:summary][:n_high_pareto_model_observations]) > 0
    @test Float64(psis_review[:summary][:max_pareto_k]) > 0.7
    @test Bool(psis_review[:summary][:all_loo_comparisons_finite])
    @test Bool(psis_review[:summary][:any_high_pareto_k])
    @test Bool(psis_review[:summary][:psis_smoothing_enabled]) == false
    @test String(psis_review[:summary][:next_gate]) ==
        "scalar_gmfrm_exact_loo_or_kfold_review"
    exact_review = only(row for row in reviewed
        if String(row[:artifact]) == "exact_loo_or_kfold_review")
    @test Bool(exact_review[:summary][:passed])
    @test Int(exact_review[:summary][:n_scenario_reviews]) == 6
    @test Int(exact_review[:summary][:n_passed_scenarios]) == 6
    @test Int(exact_review[:summary][:n_fold_model_records]) == 54
    @test Bool(exact_review[:summary][:all_observations_held_out_once])
    @test Bool(exact_review[:summary][:all_parameter_orders_matched])
    @test Bool(exact_review[:summary][:all_samplers_passed])
    @test Bool(exact_review[:summary][:all_kfold_comparisons_finite])
    @test String(exact_review[:summary][:next_gate]) ==
        "scalar_gmfrm_guarded_fit_api_dry_run"
    dry_run = only(row for row in reviewed
        if String(row[:artifact]) == "guarded_fit_api_dry_run")
    @test Bool(dry_run[:summary][:passed])
    @test Bool(dry_run[:summary][:dry_run_only])
    @test Bool(dry_run[:summary][:publication_or_registration_action]) == false
    @test Bool(dry_run[:summary][:entrypoint_enabled]) == false
    @test Bool(dry_run[:summary][:superseded_by_guarded_fit_method_wiring])
    @test Bool(dry_run[:summary][:public_fit_allowed]) == false
    @test Bool(dry_run[:summary][:experimental_keyword_enabled]) == false
    @test Bool(dry_run[:summary][:current_manifest_fit_allowed])
    @test Bool(dry_run[:summary][:current_manifest_experimental_keyword_enabled])
    @test Bool(dry_run[:summary][:fit_rejects_specified_only_gmfrm])
    @test Bool(dry_run[:summary][:fit_preview_rejects_experimental_keyword])
    @test Bool(dry_run[:summary][:artifact_contract_recorded])
    @test Bool(dry_run[:summary][:all_required_artifact_fields_recorded])
    @test Bool(dry_run[:summary][:all_required_provenance_artifacts_recorded])
    @test Bool(dry_run[:summary][:all_file_evidence_present])
    @test Bool(dry_run[:summary][:target_logdensity_finite])
    @test Bool(dry_run[:summary][:target_diagnostics_passed])
    @test Bool(dry_run[:summary][:superseded_by_real_data_case_study])
    @test Bool(dry_run[:summary][:superseded_by_claim_recovery_reproduction_archive])
    @test Bool(dry_run[:summary][:superseded_by_broader_experimental_exposure_decision_review])
    @test Bool(dry_run[:summary][:superseded_by_full_paper_reproduction_archive])
    @test String(dry_run[:summary][:next_gate]) ==
        "manual_publication_or_registration_by_user_only"
    method_wiring = only(row for row in reviewed
        if String(row[:artifact]) == "guarded_fit_method_wiring")
    @test Bool(method_wiring[:summary][:passed])
    @test Bool(method_wiring[:summary][:publication_or_registration_action]) == false
    @test Bool(method_wiring[:summary][:entrypoint_enabled])
    @test Bool(method_wiring[:summary][:public_fit_allowed])
    @test Bool(method_wiring[:summary][:experimental_keyword_enabled])
    @test Bool(method_wiring[:summary][:gmfrm_fit_returned])
    @test Bool(method_wiring[:summary][:artifact_contract_satisfied])
    @test Bool(method_wiring[:summary][:pointwise_loglikelihood_shape_valid])
    @test Bool(method_wiring[:summary][:waic_and_loo_finite])
    @test Bool(method_wiring[:summary][:all_unsupported_public_options_rejected])
    @test String(method_wiring[:summary][:next_gate]) ==
        "scalar_gmfrm_prior_likelihood_sensitivity_grid"
    validation_grid = only(row for row in reviewed
        if String(row[:artifact]) == "experimental_fit_validation_grid")
    @test Bool(validation_grid[:summary][:passed])
    @test Bool(validation_grid[:summary][:publication_or_registration_action]) == false
    @test Int(validation_grid[:summary][:n_scenarios]) == 3
    @test Int(validation_grid[:summary][:n_passed_scenarios]) == 3
    @test Bool(validation_grid[:summary][:all_guarded_fit_returned])
    @test Bool(validation_grid[:summary][:all_artifact_contracts_satisfied])
    @test Bool(validation_grid[:summary][:all_pointwise_shapes_valid])
    @test Bool(validation_grid[:summary][:all_information_criteria_finite])
    @test Bool(validation_grid[:summary][:all_no_divergences])
    @test Bool(validation_grid[:summary][:all_no_max_treedepth])
    @test Bool(validation_grid[:summary][:all_no_failed_direct_constraints])
    @test String(validation_grid[:summary][:next_gate]) ==
        "scalar_gmfrm_prior_likelihood_sensitivity_grid"
    posterior_predictive_grid = only(row for row in reviewed
        if String(row[:artifact]) == "posterior_predictive_grid")
    @test Bool(posterior_predictive_grid[:summary][:passed])
    @test Bool(posterior_predictive_grid[:summary][:publication_or_registration_action]) == false
    @test Int(posterior_predictive_grid[:summary][:n_scenarios]) == 3
    @test Int(posterior_predictive_grid[:summary][:n_passed_scenarios]) == 3
    @test Bool(posterior_predictive_grid[:summary][:all_ppc_returned])
    @test Bool(posterior_predictive_grid[:summary][:all_replicated_scores_in_categories])
    @test Bool(posterior_predictive_grid[:summary][:all_probability_sums_valid])
    @test Bool(posterior_predictive_grid[:summary][:all_summary_rows_finite])
    @test Bool(posterior_predictive_grid[:summary][:all_calibration_rows_finite])
    @test Bool(posterior_predictive_grid[:summary][:all_mean_scores_inside_interval])
    @test String(posterior_predictive_grid[:summary][:next_gate]) ==
        "scalar_gmfrm_prior_likelihood_sensitivity_grid"
    sparse_pathology_grid = only(row for row in reviewed
        if String(row[:artifact]) == "sparse_pathology_recovery_grid")
    @test Bool(sparse_pathology_grid[:summary][:passed])
    @test Bool(sparse_pathology_grid[:summary][:publication_or_registration_action]) == false
    @test Int(sparse_pathology_grid[:summary][:n_scenarios]) == 3
    @test Int(sparse_pathology_grid[:summary][:n_passed_scenarios]) == 3
    @test Int(sparse_pathology_grid[:summary][:n_replicates_per_scenario]) == 24
    @test Bool(sparse_pathology_grid[:summary][:all_validations_passed])
    @test Bool(sparse_pathology_grid[:summary][:all_location_designs_full_rank])
    @test Bool(sparse_pathology_grid[:summary][:all_guarded_fit_returned])
    @test Bool(sparse_pathology_grid[:summary][:all_pointwise_shapes_valid])
    @test Bool(sparse_pathology_grid[:summary][:all_information_criteria_finite])
    @test Bool(sparse_pathology_grid[:summary][:all_no_divergences])
    @test Bool(sparse_pathology_grid[:summary][:all_no_max_treedepth])
    @test Bool(sparse_pathology_grid[:summary][:all_no_failed_direct_constraints])
    @test Bool(sparse_pathology_grid[:summary][:all_ppc_returned])
    @test Bool(sparse_pathology_grid[:summary][:all_replicated_scores_in_categories])
    @test Bool(sparse_pathology_grid[:summary][:all_probability_sums_valid])
    @test Bool(sparse_pathology_grid[:summary][:all_summary_rows_finite])
    @test Bool(sparse_pathology_grid[:summary][:all_calibration_rows_finite])
    @test String(sparse_pathology_grid[:summary][:next_gate]) ==
        "scalar_gmfrm_prior_likelihood_sensitivity_grid"
    prior_likelihood_grid = only(row for row in reviewed
        if String(row[:artifact]) == "prior_likelihood_sensitivity_grid")
    @test Bool(prior_likelihood_grid[:summary][:passed])
    @test Bool(prior_likelihood_grid[:summary][:publication_or_registration_action]) == false
    @test Int(prior_likelihood_grid[:summary][:n_scenarios]) == 3
    @test Int(prior_likelihood_grid[:summary][:n_passed_scenarios]) == 3
    @test Int(prior_likelihood_grid[:summary][:n_sensitivity_cells]) == 45
    @test Int(prior_likelihood_grid[:summary][:n_prior_profiles]) == 5
    @test Int(prior_likelihood_grid[:summary][:n_likelihood_powers]) == 3
    @test Bool(prior_likelihood_grid[:summary][:all_cells_finite])
    @test Bool(prior_likelihood_grid[:summary][:all_baseline_identity])
    @test Float64(prior_likelihood_grid[:summary][:min_weight_ess_rate]) >= 0.05
    @test Float64(prior_likelihood_grid[:summary][:max_weight]) <= 1.0
    @test Float64(prior_likelihood_grid[:summary][:max_direct_parameter_mean_shift]) <= 3.0
    @test Float64(prior_likelihood_grid[:summary][:max_direct_block_mean_shift]) <= 2.0
    @test Float64(prior_likelihood_grid[:summary][:max_expected_score_shift]) <= 1.25
    @test Float64(prior_likelihood_grid[:summary][:max_top_category_probability_shift]) <= 0.60
    @test Float64(prior_likelihood_grid[:summary][:max_loglikelihood_mean_shift]) <= 20.0
    @test Float64(prior_likelihood_grid[:summary][:max_logposterior_decomposition_error]) <=
        1.0e-8
    @test String(prior_likelihood_grid[:summary][:next_gate]) ==
        "scalar_gmfrm_real_data_case_study"
    real_data_case_study = only(row for row in reviewed
        if String(row[:artifact]) == "real_data_case_study")
    @test Bool(real_data_case_study[:summary][:passed])
    @test Bool(real_data_case_study[:summary][:publication_or_registration_action]) == false
    @test Int(real_data_case_study[:summary][:n_cases]) == 2
    @test Int(real_data_case_study[:summary][:n_passed_cases]) == 2
    @test Int(real_data_case_study[:summary][:n_observations_total]) == 72
    @test Int(real_data_case_study[:summary][:n_replicates_per_case]) == 24
    @test Bool(real_data_case_study[:summary][:all_source_files_available])
    @test Bool(real_data_case_study[:summary][:all_validations_passed])
    @test Bool(real_data_case_study[:summary][:all_complete_crossing])
    @test Bool(real_data_case_study[:summary][:all_guarded_fit_returned])
    @test Bool(real_data_case_study[:summary][:all_baseline_fits_returned])
    @test Bool(real_data_case_study[:summary][:all_pointwise_shapes_valid])
    @test Bool(real_data_case_study[:summary][:all_information_criteria_finite])
    @test Bool(real_data_case_study[:summary][:all_model_comparisons_finite])
    @test Bool(real_data_case_study[:summary][:all_no_divergences])
    @test Bool(real_data_case_study[:summary][:all_no_max_treedepth])
    @test Bool(real_data_case_study[:summary][:all_no_failed_direct_constraints])
    @test Bool(real_data_case_study[:summary][:all_no_nonfinite_logdensity])
    @test Bool(real_data_case_study[:summary][:all_no_nonfinite_direct_loglikelihood])
    @test Bool(real_data_case_study[:summary][:all_ppc_returned])
    @test Bool(real_data_case_study[:summary][:all_replicated_scores_in_categories])
    @test Bool(real_data_case_study[:summary][:all_probability_sums_valid])
    @test Bool(real_data_case_study[:summary][:all_summary_rows_finite])
    @test Bool(real_data_case_study[:summary][:all_calibration_rows_finite])
    @test String(real_data_case_study[:summary][:next_gate]) ==
        "claim_level_recovery_and_reproduction_archive"
    claim_archive = only(row for row in reviewed
        if String(row[:artifact]) == "claim_recovery_reproduction_archive")
    @test Bool(claim_archive[:summary][:passed])
    @test Bool(claim_archive[:summary][:publication_or_registration_action]) == false
    @test Bool(claim_archive[:summary][:local_only])
    @test Int(claim_archive[:summary][:n_fixture_artifacts]) == 27
    @test Int(claim_archive[:summary][:n_source_records]) == 2
    @test Int(claim_archive[:summary][:n_code_doc_records]) == 64
    @test Int(claim_archive[:summary][:n_full_regeneration_commands]) == 26
    @test Int(claim_archive[:summary][:n_verification_commands]) == 4
    @test Bool(claim_archive[:summary][:all_fixture_artifacts_present])
    @test Bool(claim_archive[:summary][:all_expected_schemas])
    @test Bool(claim_archive[:summary][:all_fixture_summaries_passed])
    @test Bool(claim_archive[:summary][:all_generator_scripts_present])
    @test Bool(claim_archive[:summary][:all_code_doc_references_present])
    @test Bool(claim_archive[:summary][:all_external_sources_present])
    @test Bool(claim_archive[:summary][:all_commands_local_only])
    @test Bool(claim_archive[:summary][:no_publication_commands])
    @test Bool(claim_archive[:summary][:guarded_exposure_review_passed])
    @test Bool(claim_archive[:summary][:real_data_case_study_passed])
    @test Bool(claim_archive[:summary][:tam_direct_primary_gate_passed])
    @test Bool(claim_archive[:summary][:tam_raw_archive_integrity_passed])
    @test Bool(claim_archive[:summary][:tam_post_packet_integrity_passed])
    @test Bool(claim_archive[:summary][:tam_independent_review_completed]) ==
        false
    @test Bool(claim_archive[:summary][:tam_execution_input_lineage_exact])
    @test Bool(claim_archive[:summary][
        :tam_pre_execution_exact_input_lineage]) == false
    @test String(claim_archive[:summary][:next_gate]) ==
        "broader_experimental_exposure_decision_review"
    broader_review = only(row for row in reviewed
        if String(row[:artifact]) == "broader_experimental_exposure_decision_review")
    @test Bool(broader_review[:summary][:passed])
    @test Bool(broader_review[:summary][:publication_or_registration_action]) == false
    @test Bool(broader_review[:summary][:local_only])
    @test Bool(broader_review[:summary][:all_input_artifacts_present])
    @test Bool(broader_review[:summary][:all_expected_schemas])
    @test Bool(broader_review[:summary][:all_required_inputs_passed])
    @test Bool(broader_review[:summary][:guarded_exposure_review_passed])
    @test Bool(broader_review[:summary][:claim_recovery_reproduction_archive_passed])
    @test Bool(broader_review[:summary][:real_data_case_study_passed])
    @test Bool(broader_review[:summary][:mgmfrm_bridge_oracle_present])
    @test Bool(broader_review[:summary][:mgmfrm_candidate_chain_study_passed])
    @test Bool(broader_review[:summary][:mgmfrm_recovery_smoke_passed])
    @test Bool(broader_review[:summary][:mgmfrm_baseline_comparison_passed])
    @test Bool(broader_review[:summary][:mgmfrm_sparse_recovery_grid_passed])
    @test Bool(broader_review[:summary][:mgmfrm_guarded_fit_method_wiring_passed])
    @test Bool(broader_review[:summary][:mgmfrm_guarded_fit_validation_grid_passed])
    @test Bool(broader_review[:summary][:mgmfrm_guarded_fit_api_dry_run_passed])
    @test Bool(broader_review[:summary][:mgmfrm_guarded_fit_public_exposure_review_passed])
    @test Bool(broader_review[:summary][:prediction_target_and_model_weight_policy_passed])
    @test Bool(broader_review[:summary][:mgmfrm_manual_public_scope_review_for_fit_passed])
    @test Bool(broader_review[:summary][:dff_estimand_validation_grid_passed])
    @test Bool(broader_review[:summary][:manuscript_scale_simulation_grid_passed])
    @test Bool(broader_review[:summary][:full_paper_reproduction_archive_passed])
    @test Bool(broader_review[:summary][:tam_direct_primary_gate_passed])
    @test Bool(broader_review[:summary][:tam_raw_archive_integrity_passed])
    @test Bool(broader_review[:summary][:tam_post_packet_integrity_passed])
    @test Bool(broader_review[:summary][:tam_independent_review_completed]) ==
        false
    @test Bool(broader_review[:summary][:tam_execution_input_lineage_exact])
    @test Bool(broader_review[:summary][
        :tam_pre_execution_exact_input_lineage]) == false
    @test Int(broader_review[:summary][:n_input_artifacts]) == 20
    @test Int(broader_review[:summary][:n_scope_decisions]) == 7
    @test Int(broader_review[:summary][:n_risk_rows]) == 7
    @test Int(broader_review[:summary][:n_blockers]) == 2
    @test Bool(broader_review[:summary][:scalar_guarded_fit_allowed])
    @test Bool(broader_review[:summary][:broader_generalized_fit_allowed]) == false
    @test Bool(broader_review[:summary][:mgmfrm_fit_allowed])
    @test Bool(broader_review[:summary][:dff_model_effects_allowed]) == false
    @test Bool(broader_review[:summary][:model_weights_allowed]) == false
    @test Bool(broader_review[:summary][:manuscript_claims_allowed]) == false
    @test Bool(broader_review[:summary][:tam_public_validation_allowed]) ==
        false
    @test Bool(broader_review[:summary][:no_publication_commands])
    @test String(broader_review[:summary][:next_gate]) ==
        "guarded_local_mgmfrm_fit_entrypoint"
    dff_grid = only(row for row in reviewed
        if String(row[:artifact]) == "dff_estimand_validation_grid")
    @test Bool(dff_grid[:summary][:passed])
    @test Bool(dff_grid[:summary][:publication_or_registration_action]) == false
    @test Bool(dff_grid[:summary][:local_only])
    @test Int(dff_grid[:summary][:n_estimands]) == 5
    @test Int(dff_grid[:summary][:n_scenarios]) == 4
    @test Int(dff_grid[:summary][:n_passed_scenarios]) == 4
    @test Int(dff_grid[:summary][:n_validation_error_scenarios]) == 1
    @test Int(dff_grid[:summary][:n_sparse_warning_scenarios]) >= 1
    @test Int(dff_grid[:summary][:n_empty_warning_scenarios]) >= 1
    @test Bool(dff_grid[:summary][:all_expected_outcomes_matched])
    @test Bool(dff_grid[:summary][:all_valid_dff_terms_retained_as_validation_only])
    @test Bool(dff_grid[:summary][:dff_model_effects_allowed]) == false
    @test String(dff_grid[:summary][:next_gate]) ==
        "manuscript_scale_simulation_grid"
    manuscript_grid = only(row for row in reviewed
        if String(row[:artifact]) == "manuscript_scale_simulation_grid")
    @test Bool(manuscript_grid[:summary][:passed])
    @test Bool(manuscript_grid[:summary][:publication_or_registration_action]) == false
    @test Bool(manuscript_grid[:summary][:local_only])
    @test Bool(manuscript_grid[:summary][:all_input_artifacts_present])
    @test Bool(manuscript_grid[:summary][:all_expected_schemas])
    @test Bool(manuscript_grid[:summary][:all_input_summaries_passed])
    @test Bool(manuscript_grid[:summary][:all_primary_checks_passed])
    @test Int(manuscript_grid[:summary][:n_input_artifacts]) == 35
    @test Int(manuscript_grid[:summary][:total_evidence_cells]) == 5608
    @test Int(manuscript_grid[:summary][:minimum_required_evidence_cells]) == 60
    @test Bool(manuscript_grid[:summary][:prediction_target_and_model_weight_policy_passed])
    @test Bool(manuscript_grid[:summary][
        :mgmfrm_q_revision_cross_validation_policy_passed])
    @test Bool(manuscript_grid[:summary][
        :mgmfrm_q_revision_construct_validity_review_passed])
    @test Bool(manuscript_grid[:summary][
        :mgmfrm_guarded_local_fit_entrypoint_passed])
    @test Bool(manuscript_grid[:summary][
        :mgmfrm_fit_metric_threshold_sensitivity_passed])
    @test Bool(manuscript_grid[:summary][
        :mgmfrm_construct_reviewed_q_fit_reporting_policy_passed])
    @test Bool(manuscript_grid[:summary][
        :mgmfrm_heldout_prediction_validation_policy_passed])
    @test Bool(manuscript_grid[:summary][
        :mgmfrm_validation_split_model_comparison_policy_passed])
    @test Bool(manuscript_grid[:summary][
        :mgmfrm_heldout_prediction_simulation_grid_passed])
    @test Bool(manuscript_grid[:summary][
        :mgmfrm_heldout_prediction_execution_passed])
    @test Bool(manuscript_grid[:summary][
        :mgmfrm_full_heldout_refit_or_construct_validation_review_passed])
    @test Bool(manuscript_grid[:summary][
        :mgmfrm_full_heldout_mcmc_refit_execution_plan_passed])
    @test Bool(manuscript_grid[:summary][
        :mgmfrm_full_heldout_mcmc_refit_batch_smoke_passed])
    @test Bool(manuscript_grid[:summary][
        :mgmfrm_full_heldout_mcmc_refit_fold1_pilot_passed])
    @test Bool(manuscript_grid[:summary][
        :mgmfrm_full_heldout_mcmc_refit_fold1_scoring_passed])
    @test Bool(manuscript_grid[:summary][
        :mgmfrm_full_heldout_mcmc_refit_candidate_batch_scoring_passed])
    @test Bool(manuscript_grid[:summary][
        :mgmfrm_full_heldout_mcmc_refit_anchor_scoring_passed])
    @test Bool(manuscript_grid[:summary][
        :mgmfrm_publication_grade_refit_gate_passed])
    @test Bool(manuscript_grid[:summary][
        :mgmfrm_publication_grade_refit_pilot_plan_passed])
    @test Bool(manuscript_grid[:summary][
        :mgmfrm_fit_threshold_q_heldout_linkage_passed])
    @test Bool(manuscript_grid[:summary][
        :mgmfrm_publication_grade_refit_pilot_execution_harness_passed])
    @test Bool(manuscript_grid[:summary][:full_paper_reproduction_archive_passed])
    @test Bool(manuscript_grid[:summary][:manuscript_claims_allowed]) == false
    @test String(manuscript_grid[:summary][:next_gate]) ==
        "execute_publication_grade_refit_pilot_or_attach_external_construct_dataset"
    full_archive = only(row for row in reviewed
        if String(row[:artifact]) == "full_paper_reproduction_archive")
    @test Bool(full_archive[:summary][:passed])
    @test String(full_archive[:summary][:pass_scope]) ==
        "contract_and_blocker_preservation_only"
    @test Bool(full_archive[:summary][:artifact_contract_valid])
    @test Bool(full_archive[:summary][:publication_or_registration_action]) == false
    @test Bool(full_archive[:summary][:local_only])
    @test Bool(full_archive[:summary][:all_fixture_artifacts_present])
    @test Bool(full_archive[:summary][:all_expected_schemas])
    @test Bool(full_archive[:summary][:all_fixture_summaries_passed])
    @test Bool(full_archive[:summary][
        :all_fixture_artifact_contracts_valid])
    @test Bool(full_archive[:summary][:all_code_doc_references_present])
    @test Bool(full_archive[:summary][:all_external_sources_present])
    @test Bool(full_archive[:summary][:all_commands_local_only])
    @test Bool(full_archive[:summary][:no_publication_commands])
    @test Bool(full_archive[:summary][:tam_direct_primary_gate_passed])
    @test Bool(full_archive[:summary][:tam_raw_archive_integrity_passed])
    @test Bool(full_archive[:summary][:tam_post_packet_integrity_passed])
    @test Bool(full_archive[:summary][:tam_independent_review_completed]) ==
        false
    @test Bool(full_archive[:summary][:tam_execution_input_lineage_exact])
    @test Bool(full_archive[:summary][
        :tam_pre_execution_exact_input_lineage]) == false
    @test Bool(full_archive[:summary][
        :tam_direct_evidence_transfers_to_gmfrm_or_mgmfrm]) == false
    @test Int(full_archive[:summary][:n_fixture_artifacts]) == 79
    @test Int(full_archive[:summary][:n_code_doc_records]) == 125
    @test Int(full_archive[:summary][:n_full_regeneration_commands]) == 77
    @test Int(full_archive[:summary][:n_verification_commands]) == 4
    @test Bool(full_archive[:summary][:mgmfrm_report_shape_simulation_grid_passed])
    @test Bool(full_archive[:summary][:mgmfrm_q_matrix_validation_expansion_passed])
    @test Bool(full_archive[:summary][
        :mgmfrm_empirical_q_matrix_recovery_policy_passed])
    @test Bool(full_archive[:summary][
        :mgmfrm_empirical_q_matrix_recovery_simulation_grid_passed])
    @test Bool(full_archive[:summary][
        :mgmfrm_q_candidate_real_fit_diagnostic_linkage_passed])
    @test Bool(full_archive[:summary][
        :mgmfrm_q_revision_cross_validation_policy_passed])
    @test Bool(full_archive[:summary][
        :mgmfrm_q_revision_construct_validity_review_passed])
    @test Bool(full_archive[:summary][
        :mgmfrm_guarded_local_fit_entrypoint_passed])
    @test Bool(full_archive[:summary][
        :mgmfrm_fit_metric_threshold_sensitivity_passed])
    @test Bool(full_archive[:summary][
        :mgmfrm_construct_reviewed_q_fit_reporting_policy_passed])
    @test Bool(full_archive[:summary][
        :mgmfrm_heldout_prediction_validation_policy_passed])
    @test Bool(full_archive[:summary][
        :mgmfrm_validation_split_model_comparison_policy_passed])
    @test Bool(full_archive[:summary][
        :mgmfrm_heldout_prediction_simulation_grid_passed])
    @test Bool(full_archive[:summary][
        :mgmfrm_heldout_prediction_execution_passed])
    @test Bool(full_archive[:summary][
        :mgmfrm_full_heldout_refit_or_construct_validation_review_passed])
    @test Bool(full_archive[:summary][
        :mgmfrm_full_heldout_mcmc_refit_execution_plan_passed])
    @test Bool(full_archive[:summary][
        :mgmfrm_full_heldout_mcmc_refit_batch_smoke_passed])
    @test Bool(full_archive[:summary][
        :mgmfrm_full_heldout_mcmc_refit_fold1_pilot_passed])
    @test Bool(full_archive[:summary][
        :mgmfrm_full_heldout_mcmc_refit_fold1_scoring_passed])
    @test Bool(full_archive[:summary][
        :mgmfrm_full_heldout_mcmc_refit_candidate_batch_scoring_passed])
    @test Bool(full_archive[:summary][
        :mgmfrm_full_heldout_mcmc_refit_anchor_scoring_passed])
    @test Bool(full_archive[:summary][
        :mgmfrm_publication_grade_refit_gate_passed])
    @test Bool(full_archive[:summary][
        :mgmfrm_publication_grade_refit_pilot_plan_passed])
    @test Bool(full_archive[:summary][
        :mgmfrm_fit_threshold_q_heldout_linkage_passed])
    @test Bool(full_archive[:summary][
        :mgmfrm_publication_grade_refit_pilot_execution_harness_passed])
    @test Bool(full_archive[:summary][
        :mgmfrm_publication_grade_refit_pilot_results_review_passed])
    @test Bool(full_archive[:summary][
        :mgmfrm_publication_grade_threshold_model_weight_policy_review_passed])
    @test Bool(full_archive[:summary][
        :mgmfrm_external_construct_dataset_and_independent_public_scope_review_passed])
    @test String(full_archive[:summary][
        :mgmfrm_external_construct_dataset_and_independent_public_scope_review_passed_semantics]) ==
        "artifact_contract_and_blocker_preservation_only"
    @test Bool(full_archive[:summary][
        :mgmfrm_external_construct_dataset_and_independent_public_scope_review_artifact_contract_valid])
    @test Bool(full_archive[:summary][
        :mgmfrm_external_construct_attachment_intake_preflight_passed])
    @test String(full_archive[:summary][
        :mgmfrm_external_construct_attachment_intake_preflight_passed_semantics]) ==
        "artifact_contract_and_blocker_preservation_only"
    @test Bool(full_archive[:summary][
        :mgmfrm_external_construct_attachment_intake_preflight_artifact_contract_valid])
    @test Bool(full_archive[:summary][
        :mgmfrm_external_construct_attachment_request_packet_passed])
    @test String(full_archive[:summary][
        :mgmfrm_external_construct_attachment_request_packet_passed_semantics]) ==
        "artifact_contract_and_blocker_preservation_only"
    @test Bool(full_archive[:summary][
        :mgmfrm_external_construct_attachment_request_packet_artifact_contract_valid])
    @test Bool(full_archive[:summary][
        :mgmfrm_external_construct_dataset_manifest_attached_and_valid]) ==
        false
    @test Bool(full_archive[:summary][
        :mgmfrm_external_construct_dataset_file_integrity_verified]) == false
    @test Bool(full_archive[:summary][
        :mgmfrm_external_construct_validation_evidence_attached_and_valid]) ==
        false
    @test Bool(full_archive[:summary][
        :mgmfrm_external_construct_validation_evidence_passed]) == false
    @test Bool(full_archive[:summary][
        :mgmfrm_independent_public_scope_review_attached_and_valid]) == false
    @test Bool(full_archive[:summary][
        :mgmfrm_independent_public_scope_review_gate_passed]) == false
    @test Bool(full_archive[:summary][
        :mgmfrm_public_claim_release_decision_signed]) == false
    @test Bool(full_archive[:summary][
        :mgmfrm_external_construct_public_claim_release_gate_passed]) == false
    @test Int(full_archive[:summary][
        :mgmfrm_external_construct_public_blocker_count]) == 5
    @test Bool(full_archive[:summary][:prediction_target_and_model_weight_policy_passed])
    @test !Bool(full_archive[:summary][:manuscript_reproducibility_claims_supported])
    @test Int(full_archive[:summary][:n_blockers]) == 2
    @test String(full_archive[:summary][:next_gate]) ==
        "manual_publication_or_registration_by_user_only"
    mgmfrm_sparse_grid = only(row for row in reviewed
        if String(row[:artifact]) == "mgmfrm_sparse_recovery_grid")
    @test Bool(mgmfrm_sparse_grid[:summary][:passed])
    @test Int(mgmfrm_sparse_grid[:summary][:n_scenarios]) == 3
    @test Int(mgmfrm_sparse_grid[:summary][:n_passed_scenarios]) == 3
    @test Bool(mgmfrm_sparse_grid[:summary][:all_validations_passed])
    @test Bool(mgmfrm_sparse_grid[:summary][:all_location_designs_full_rank])
    @test Bool(mgmfrm_sparse_grid[:summary][:all_parameter_orders_match_reference])
    @test Bool(mgmfrm_sparse_grid[:summary][:all_sampler_passed])
    @test Bool(mgmfrm_sparse_grid[:summary][:all_waic_finite])
    @test Bool(mgmfrm_sparse_grid[:summary][:public_fit_allowed]) == false
    @test String(mgmfrm_sparse_grid[:summary][:next_gate]) ==
        "dff_estimand_and_validation_grid"
    mgmfrm_method = only(row for row in reviewed
        if String(row[:artifact]) == "mgmfrm_guarded_fit_method_wiring")
    @test Bool(mgmfrm_method[:summary][:passed])
    @test Bool(mgmfrm_method[:summary][:entrypoint_enabled])
    @test Bool(mgmfrm_method[:summary][:public_fit_allowed])
    @test Bool(mgmfrm_method[:summary][:sampler_protocol_passed])
    @test Bool(mgmfrm_method[:summary][:artifact_contract_satisfied])
    @test Bool(mgmfrm_method[:summary][:all_fit_boundary_checks_passed])
    @test Bool(mgmfrm_method[:summary][:experimental_spec_fit_succeeded])
    @test String(mgmfrm_method[:summary][:next_gate]) ==
        "mgmfrm_guarded_fit_validation_grid"
    mgmfrm_validation = only(row for row in reviewed
        if String(row[:artifact]) == "mgmfrm_guarded_fit_validation_grid")
    @test Bool(mgmfrm_validation[:summary][:passed])
    @test Bool(mgmfrm_validation[:summary][:entrypoint_enabled])
    @test Bool(mgmfrm_validation[:summary][:public_fit_allowed])
    @test Bool(mgmfrm_validation[:summary][:all_validation_rows_passed])
    @test Bool(mgmfrm_validation[:summary][:guarded_fit_method_wiring_passed])
    @test Bool(mgmfrm_validation[:summary][:method_sampler_protocol_passed])
    @test Bool(mgmfrm_validation[:summary][:method_artifact_contract_satisfied])
    @test Bool(mgmfrm_validation[:summary][:method_fit_boundary_checks_passed])
    @test Bool(mgmfrm_validation[:summary][:method_experimental_spec_fit_succeeded])
    @test String(mgmfrm_validation[:summary][:next_gate]) ==
        "mgmfrm_guarded_fit_api_dry_run"
    mgmfrm_api_dry_run = only(row for row in reviewed
        if String(row[:artifact]) == "mgmfrm_guarded_fit_api_dry_run")
    @test Bool(mgmfrm_api_dry_run[:summary][:passed])
    @test Bool(mgmfrm_api_dry_run[:summary][:dry_run_only])
    @test Bool(mgmfrm_api_dry_run[:summary][:entrypoint_enabled])
    @test Bool(mgmfrm_api_dry_run[:summary][:guarded_fit_validation_grid_passed])
    @test Bool(mgmfrm_api_dry_run[:summary][:validation_grid_all_rows_passed])
    @test Bool(mgmfrm_api_dry_run[:summary][:all_fit_boundary_checks_passed])
    @test Bool(mgmfrm_api_dry_run[:summary][:experimental_spec_fit_succeeded])
    @test Bool(mgmfrm_api_dry_run[:summary][:artifact_contract_satisfied])
    @test Bool(mgmfrm_api_dry_run[:summary][:target_gradient_diagnostics_passed])
    @test String(mgmfrm_api_dry_run[:summary][:next_gate]) ==
        "mgmfrm_guarded_fit_public_exposure_review"
    mgmfrm_public_review = only(row for row in reviewed
        if String(row[:artifact]) == "mgmfrm_guarded_fit_public_exposure_review")
    @test Bool(mgmfrm_public_review[:summary][:passed])
    @test Bool(mgmfrm_public_review[:summary][:reviewed])
    @test Bool(mgmfrm_public_review[:summary][:publication_or_registration_action]) == false
    @test Bool(mgmfrm_public_review[:summary][:local_only])
    @test Bool(mgmfrm_public_review[:summary][:public_fit_allowed])
    @test Bool(mgmfrm_public_review[:summary][:experimental_keyword_enabled])
    @test Bool(mgmfrm_public_review[:summary][:all_input_artifacts_present])
    @test Bool(mgmfrm_public_review[:summary][:all_expected_schemas])
    @test Bool(mgmfrm_public_review[:summary][:all_input_summaries_passed])
    @test Bool(mgmfrm_public_review[:summary][:all_fit_boundary_checks_passed])
    @test Bool(mgmfrm_public_review[:summary][:current_manifest_guarded_fit_enabled])
    @test Bool(mgmfrm_public_review[:summary][:no_publication_commands])
    @test Bool(mgmfrm_public_review[:summary][:mgmfrm_guarded_fit_api_dry_run_passed])
    @test Bool(mgmfrm_public_review[:summary][:dff_estimand_validation_grid_passed])
    @test Int(mgmfrm_public_review[:summary][:n_input_artifacts]) == 9
    @test Int(mgmfrm_public_review[:summary][:n_blockers]) == 1
    @test String(mgmfrm_public_review[:summary][:next_gate]) ==
        "prediction_target_and_model_weight_policy"
    prediction_policy = only(row for row in reviewed
        if String(row[:artifact]) ==
            "prediction_target_and_model_weight_policy")
    @test Bool(prediction_policy[:summary][:passed])
    @test Bool(prediction_policy[:summary][:policy_recorded])
    @test Bool(prediction_policy[:summary][:same_data_waic_blocked])
    @test Bool(prediction_policy[:summary][:raw_psis_loo_blocked])
    @test Bool(prediction_policy[:summary][:heldout_kfold_selected])
    @test Bool(prediction_policy[:summary][:scalar_local_model_weight_reporting_allowed])
    @test Bool(prediction_policy[:summary][:mgmfrm_fit_allowed])
    @test Bool(prediction_policy[:summary][:mgmfrm_weight_claims_allowed]) == false
    @test String(prediction_policy[:summary][:next_gate]) ==
        "manual_public_scope_review_for_mgmfrm_fit"

    review_rows = fixture[:review_rows]
    @test any(row -> String(row[:gate]) == "candidate_chain_study" &&
        String(row[:status]) == "passed", review_rows)
    @test any(row -> String(row[:gate]) == "baseline_calibration_grid" &&
        String(row[:status]) == "passed_with_caution", review_rows)
    @test any(row -> String(row[:gate]) == "interval_decision_grid" &&
        String(row[:status]) == "passed_with_caution", review_rows)
    @test any(row -> String(row[:gate]) == "sparse_design_grid" &&
        String(row[:status]) == "passed_with_caution", review_rows)
    @test any(row -> String(row[:gate]) == "waic_influence_review" &&
        String(row[:status]) == "passed_with_caution", review_rows)
    @test any(row -> String(row[:gate]) == "psis_loo_review" &&
        String(row[:status]) == "passed_with_caution", review_rows)
    @test any(row -> String(row[:gate]) == "exact_loo_or_kfold_review" &&
        String(row[:status]) == "passed_with_caution", review_rows)
    @test any(row -> String(row[:gate]) == "guarded_fit_api_dry_run" &&
        String(row[:status]) == "passed" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) == "guarded_fit_method_wiring" &&
        String(row[:status]) == "passed" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) == "experimental_fit_validation_grid" &&
        String(row[:status]) == "passed" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) == "scalar_gmfrm_posterior_predictive_grid" &&
        String(row[:status]) == "passed" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) == "scalar_gmfrm_sparse_pathology_recovery_grid" &&
        String(row[:status]) == "passed" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) == "scalar_gmfrm_prior_likelihood_sensitivity_grid" &&
        String(row[:status]) == "passed" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) == "scalar_gmfrm_real_data_case_study" &&
        String(row[:status]) == "passed" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) == "claim_level_recovery_and_reproduction_archive" &&
        String(row[:status]) == "passed" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) == "broader_experimental_exposure_decision_review" &&
        String(row[:status]) == "passed" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) == "confirmatory_mgmfrm_sparse_recovery_grid" &&
        String(row[:status]) == "passed" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) == "confirmatory_mgmfrm_guarded_fit_method_wiring" &&
        String(row[:status]) == "passed" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) == "confirmatory_mgmfrm_guarded_fit_validation_grid" &&
        String(row[:status]) == "passed" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) == "confirmatory_mgmfrm_guarded_fit_api_dry_run" &&
        String(row[:status]) == "passed" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) ==
        "confirmatory_mgmfrm_guarded_fit_public_exposure_review" &&
        String(row[:status]) == "passed_with_policy_blocker" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) ==
        "prediction_target_and_model_weight_policy" &&
        String(row[:status]) == "passed_with_scope_blocker" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) ==
        "confirmatory_mgmfrm_fit_metric_threshold_sensitivity" &&
        String(row[:status]) == "passed_with_policy_blocker" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) ==
        "confirmatory_mgmfrm_construct_reviewed_q_fit_reporting_policy" &&
        String(row[:status]) == "passed_with_policy_blocker" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) ==
        "confirmatory_mgmfrm_heldout_prediction_validation_policy" &&
        String(row[:status]) == "passed_with_policy_blocker" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) ==
        "confirmatory_mgmfrm_validation_split_model_comparison_policy" &&
        String(row[:status]) == "passed_with_policy_blocker" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) ==
        "confirmatory_mgmfrm_heldout_prediction_simulation_grid" &&
        String(row[:status]) == "passed_with_policy_blocker" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) ==
        "confirmatory_mgmfrm_heldout_prediction_execution" &&
        String(row[:status]) == "passed_with_policy_blocker" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) ==
        "confirmatory_mgmfrm_full_heldout_refit_or_construct_validation_review" &&
        String(row[:status]) == "passed_with_policy_blocker" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) ==
        "confirmatory_mgmfrm_full_heldout_mcmc_refit_execution_plan" &&
        String(row[:status]) == "passed_with_policy_blocker" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) ==
        "confirmatory_mgmfrm_full_heldout_mcmc_refit_batch_smoke" &&
        String(row[:status]) == "passed_with_policy_blocker" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) ==
        "confirmatory_mgmfrm_full_heldout_mcmc_refit_fold1_pilot" &&
        String(row[:status]) == "passed_with_policy_blocker" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) ==
        "confirmatory_mgmfrm_full_heldout_mcmc_refit_fold1_scoring" &&
        String(row[:status]) == "passed_with_policy_blocker" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) ==
        "confirmatory_mgmfrm_full_heldout_mcmc_refit_candidate_batch_scoring" &&
        String(row[:status]) == "passed_with_policy_blocker" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) ==
        "confirmatory_mgmfrm_full_heldout_mcmc_refit_anchor_scoring" &&
        String(row[:status]) == "passed_with_policy_blocker" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) ==
        "confirmatory_mgmfrm_publication_grade_refit_gate" &&
        String(row[:status]) == "passed_with_policy_blocker" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) ==
        "confirmatory_mgmfrm_publication_grade_refit_pilot_plan" &&
        String(row[:status]) == "passed_with_policy_blocker" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) ==
        "confirmatory_mgmfrm_fit_threshold_q_heldout_linkage" &&
        String(row[:status]) == "passed_with_policy_blocker" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) ==
        "confirmatory_mgmfrm_publication_grade_refit_pilot_execution_harness" &&
        String(row[:status]) == "passed_with_policy_blocker" &&
        Bool(row[:evidence]), review_rows)
    external_construct_review_row = only(row for row in review_rows
        if String(row[:gate]) ==
            "confirmatory_mgmfrm_external_construct_dataset_and_independent_public_scope_review")
    @test String(external_construct_review_row[:status]) ==
        "contract_valid_claims_blocked"
    @test Bool(external_construct_review_row[:evidence])
    @test Bool(external_construct_review_row[:compatibility_passed])
    @test String(external_construct_review_row[
        :compatibility_passed_semantics]) ==
        "artifact_contract_and_blocker_preservation_only"
    @test Bool(external_construct_review_row[
        :external_construct_validation_evidence_passed]) == false
    @test Bool(external_construct_review_row[
        :independent_public_scope_review_gate_passed]) == false
    @test Bool(external_construct_review_row[
        :public_claim_release_gate_passed]) == false
    @test any(row -> String(row[:gate]) ==
        "confirmatory_mgmfrm_external_construct_attachment_intake_preflight" &&
        String(row[:status]) == "contract_valid_claims_blocked" &&
        Bool(row[:compatibility_passed]) &&
        String(row[:compatibility_passed_semantics]) ==
            "artifact_contract_and_blocker_preservation_only" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) ==
        "confirmatory_mgmfrm_external_construct_attachment_request_packet" &&
        String(row[:status]) == "contract_valid_claims_blocked" &&
        Bool(row[:compatibility_passed]) &&
        String(row[:compatibility_passed_semantics]) ==
            "artifact_contract_and_blocker_preservation_only" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) == "dff_estimand_and_validation_grid" &&
        String(row[:status]) == "passed" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) == "manuscript_scale_simulation_grid" &&
        String(row[:status]) == "passed" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) ==
        "tam_direct_agreement_multireplication" &&
        String(row[:status]) == "passed_local_nontransfer" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) ==
        "tam_direct_agreement_raw_archive_audit" &&
        String(row[:status]) == "passed" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) ==
        "tam_direct_post_execution_review" &&
        String(row[:status]) == "passed_with_policy_blocker" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) == "full_paper_reproduction_archive" &&
        String(row[:status]) == "passed" &&
        Bool(row[:evidence]), review_rows)

    blocker_rows = fixture[:blocker_rows]
    @test Set(String(row[:blocker]) for row in blocker_rows) == Set([
        "tam_direct_independent_review_pending",
        "tam_pre_execution_refinement_lineage_adjudication_pending",
    ])
    @test all(row -> !Bool(row[:resolved]) &&
        !Bool(row[:blocks_guarded_local_scalar_fit]), blocker_rows)

    decision_record = fixture[:decision_record]
    @test String(decision_record[:public_exposure_support]) ==
        "guarded_scalar_gmfrm_only"
    @test String(decision_record[:interpretation]) ==
        "local_evidence_reviewed_manual_scope_review_recorded_and_broader_exposure_decision_recorded"
    @test String(decision_record[:tam_direct_evidence_scope]) ==
        "mfrm_tam_overlap_nontransfer"
    @test Bool(decision_record[
        :tam_direct_evidence_transfers_to_gmfrm_or_mgmfrm]) == false
    @test Bool(decision_record[:tam_independent_review_completed]) == false
    @test Bool(decision_record[:publication_grade_pilot_runner_materialized])
    @test String(decision_record[:required_followup]) ==
        "execute_publication_grade_refit_pilot_or_attach_external_construct_dataset"

    summary = fixture[:summary]
    @test Bool(summary[:reviewed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:all_local_evidence_passed])
    @test Bool(summary[:any_high_variance_waic])
    @test Bool(summary[:any_high_pareto_k])
    @test Bool(summary[:exact_loo_or_kfold_review_passed])
    @test Bool(summary[:guarded_fit_api_dry_run_passed])
    @test Bool(summary[:guarded_fit_method_wiring_passed])
    @test Bool(summary[:experimental_fit_validation_grid_passed])
    @test Bool(summary[:posterior_predictive_grid_passed])
    @test Bool(summary[:sparse_pathology_recovery_grid_passed])
    @test Bool(summary[:prior_likelihood_sensitivity_grid_passed])
    @test Bool(summary[:real_data_case_study_passed])
    @test Bool(summary[:claim_recovery_reproduction_archive_passed])
    @test Bool(summary[:broader_experimental_exposure_decision_review_passed])
    @test Bool(summary[:mgmfrm_sparse_recovery_grid_passed])
    @test Bool(summary[:mgmfrm_guarded_fit_method_wiring_passed])
    @test Bool(summary[:mgmfrm_guarded_fit_validation_grid_passed])
    @test Bool(summary[:mgmfrm_guarded_fit_api_dry_run_passed])
    @test Bool(summary[:mgmfrm_guarded_fit_public_exposure_review_passed])
    @test Bool(summary[:mgmfrm_q_matrix_validation_expansion_passed])
    @test Bool(summary[:mgmfrm_empirical_q_matrix_recovery_policy_passed])
    @test Bool(summary[
        :mgmfrm_empirical_q_matrix_recovery_simulation_grid_passed])
    @test Bool(summary[:mgmfrm_q_candidate_real_fit_diagnostic_linkage_passed])
    @test Bool(summary[:mgmfrm_q_revision_cross_validation_policy_passed])
    @test Bool(summary[:mgmfrm_q_revision_construct_validity_review_passed])
    @test Bool(summary[:mgmfrm_guarded_local_fit_entrypoint_passed])
    @test Bool(summary[:mgmfrm_fit_metric_threshold_sensitivity_passed])
    @test Bool(summary[
        :mgmfrm_construct_reviewed_q_fit_reporting_policy_passed])
    @test Bool(summary[
        :mgmfrm_heldout_prediction_validation_policy_passed])
    @test Bool(summary[
        :mgmfrm_validation_split_model_comparison_policy_passed])
    @test Bool(summary[:mgmfrm_heldout_prediction_simulation_grid_passed])
    @test Bool(summary[:mgmfrm_heldout_prediction_execution_passed])
    @test Bool(summary[
        :mgmfrm_full_heldout_refit_or_construct_validation_review_passed])
    @test Bool(summary[
        :mgmfrm_full_heldout_mcmc_refit_execution_plan_passed])
    @test Bool(summary[
        :mgmfrm_full_heldout_mcmc_refit_batch_smoke_passed])
    @test Bool(summary[
        :mgmfrm_full_heldout_mcmc_refit_fold1_pilot_passed])
    @test Bool(summary[
        :mgmfrm_full_heldout_mcmc_refit_fold1_scoring_passed])
    @test Bool(summary[
        :mgmfrm_full_heldout_mcmc_refit_candidate_batch_scoring_passed])
    @test Bool(summary[
        :mgmfrm_full_heldout_mcmc_refit_anchor_scoring_passed])
    @test Bool(summary[:mgmfrm_publication_grade_refit_gate_passed])
    @test Bool(summary[:mgmfrm_publication_grade_refit_pilot_plan_passed])
    @test Bool(summary[:mgmfrm_fit_threshold_q_heldout_linkage_passed])
    @test Bool(summary[
        :mgmfrm_publication_grade_refit_pilot_execution_harness_passed])
    @test Bool(summary[
        :mgmfrm_publication_grade_refit_pilot_results_review_passed])
    @test Bool(summary[
        :mgmfrm_publication_grade_refit_sampler_remediation_review_passed])
    @test Bool(summary[
        :mgmfrm_publication_grade_refit_scalar_remediation_comparison_passed])
    @test Bool(summary[
        :mgmfrm_publication_grade_refit_batch_expansion_plan_passed])
    @test Bool(summary[
        :mgmfrm_publication_grade_refit_batch_results_review_passed])
    @test Bool(summary[
        :mgmfrm_publication_grade_threshold_model_weight_policy_review_passed])
    @test Bool(summary[
        :mgmfrm_external_construct_dataset_and_independent_public_scope_review_passed])
    @test String(summary[
        :mgmfrm_external_construct_dataset_and_independent_public_scope_review_passed_semantics]) ==
        "artifact_contract_and_blocker_preservation_only"
    @test Bool(summary[
        :mgmfrm_external_construct_dataset_and_independent_public_scope_review_artifact_contract_valid])
    @test Bool(summary[
        :mgmfrm_external_construct_attachment_intake_preflight_passed])
    @test String(summary[
        :mgmfrm_external_construct_attachment_intake_preflight_passed_semantics]) ==
        "artifact_contract_and_blocker_preservation_only"
    @test Bool(summary[
        :mgmfrm_external_construct_attachment_intake_preflight_artifact_contract_valid])
    @test Bool(summary[
        :mgmfrm_external_construct_attachment_request_packet_passed])
    @test String(summary[
        :mgmfrm_external_construct_attachment_request_packet_passed_semantics]) ==
        "artifact_contract_and_blocker_preservation_only"
    @test Bool(summary[
        :mgmfrm_external_construct_attachment_request_packet_artifact_contract_valid])
    @test Bool(summary[
        :mgmfrm_external_construct_dataset_manifest_attached_and_valid]) ==
        false
    @test Bool(summary[
        :mgmfrm_external_construct_dataset_file_integrity_verified]) == false
    @test Bool(summary[
        :mgmfrm_external_construct_validation_evidence_attached_and_valid]) ==
        false
    @test Bool(summary[
        :mgmfrm_external_construct_validation_evidence_passed]) == false
    @test Bool(summary[
        :mgmfrm_independent_public_scope_review_attached_and_valid]) == false
    @test Bool(summary[
        :mgmfrm_independent_public_scope_review_gate_passed]) == false
    @test Bool(summary[:mgmfrm_public_claim_release_decision_signed]) == false
    @test Bool(summary[
        :mgmfrm_external_construct_public_claim_release_gate_passed]) == false
    @test Int(summary[:mgmfrm_external_construct_public_blocker_count]) == 5
    @test !Bool(summary[
        :mgmfrm_external_construct_validation_evidence_passed]) ||
        Bool(summary[
            :mgmfrm_external_construct_validation_evidence_attached_and_valid])
    @test !Bool(summary[
        :mgmfrm_external_construct_public_claim_release_gate_passed]) ||
        Int(summary[:mgmfrm_external_construct_public_blocker_count]) == 0
    @test Bool(summary[:prediction_target_and_model_weight_policy_passed])
    @test Bool(summary[:dff_estimand_validation_grid_passed])
    @test Bool(summary[:manuscript_scale_simulation_grid_passed])
    @test Bool(summary[:full_paper_reproduction_archive_passed])
    @test Bool(summary[:tam_direct_agreement_multireplication_passed])
    @test Bool(summary[:tam_direct_agreement_raw_archive_audit_passed])
    @test Bool(summary[:tam_direct_post_execution_review_packet_passed])
    @test Bool(summary[:tam_direct_primary_gate_passed])
    @test Bool(summary[:tam_raw_archive_integrity_passed])
    @test Bool(summary[:tam_post_packet_integrity_passed])
    @test Bool(summary[:tam_independent_review_completed]) == false
    @test Bool(summary[:tam_execution_input_lineage_exact])
    @test Bool(summary[:tam_pre_execution_exact_input_lineage]) == false
    @test Bool(summary[
        :tam_direct_evidence_transfers_to_gmfrm_or_mgmfrm]) == false
    @test Bool(summary[:scalar_guarded_fit_allowed])
    @test Bool(summary[:broader_generalized_fit_allowed]) == false
    @test Bool(summary[:mgmfrm_fit_allowed])
    @test Int(summary[:n_reviewed_artifacts]) == length(reviewed)
    @test Int(summary[:n_review_rows]) == length(review_rows)
    @test Int(summary[:n_blockers]) == length(blocker_rows)
    @test Bool(summary[:fit_allowed])
    @test Bool(summary[:experimental_keyword_enabled])
    @test Bool(summary[:publication_grade_pilot_runner_materialized])
    @test String(summary[:recommendation]) ==
        "manual_scope_review_recorded_execute_publication_grade_refit_pilot_next"
    @test String(summary[:next_gate]) ==
        "execute_publication_grade_refit_pilot_or_attach_external_construct_dataset"
end
