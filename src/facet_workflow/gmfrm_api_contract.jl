function _gmfrm_experimental_public_evidence_rows()
    return [
        (evidence = :fit_ready_compiler_manifest, status = :done,
            artifact = :gmfrm_fit_ready_compiler_candidate),
        (evidence = :raw_to_direct_transform_diagnostics, status = :done,
            artifact = :gmfrm_promotion_candidate_transform_diagnostics),
        (evidence = :direct_pointwise_fixture, status = :done,
            artifact = :gmfrm_promotion_candidate_pointwise_fixture),
        (evidence = :bridgestan_fit_ready_oracle, status = :done,
            artifact = :fit_ready_scalar_gmfrm_bridge_oracle),
        (evidence = :candidate_chain_study, status = :done,
            artifact = "test/fixtures/gmfrm_candidate_chain_study.json"),
        (evidence = :recovery_smoke_study, status = :done,
            artifact = "test/fixtures/gmfrm_recovery_smoke.json"),
        (evidence = :fit_artifact_manifest_for_experimental_public, status = :done,
            artifact = :experimental_public_fit_artifact_contract),
        (evidence = :rater_step_public_option_policy, status = :done,
            artifact = :gmfrm_rater_step_public_option_policy),
        (evidence = :item_discrimination_promotion_decision, status = :done,
            artifact = :gmfrm_item_discrimination_promotion_decision),
        (evidence = :stress_chain_grid, status = :done,
            artifact = "test/fixtures/gmfrm_stress_chain_grid.json"),
        (evidence = :baseline_comparison, status = :done,
            artifact = "test/fixtures/gmfrm_baseline_comparison.json"),
        (evidence = :baseline_calibration_grid, status = :done,
            artifact = "test/fixtures/gmfrm_baseline_calibration_grid.json"),
        (evidence = :interval_decision_grid, status = :done,
            artifact = "test/fixtures/gmfrm_interval_decision_grid.json"),
        (evidence = :sparse_design_grid, status = :done,
            artifact = "test/fixtures/gmfrm_sparse_design_grid.json"),
        (evidence = :waic_influence_review, status = :done,
            artifact = "test/fixtures/gmfrm_waic_influence_review.json"),
        (evidence = :psis_loo_review, status = :done,
            artifact = "test/fixtures/gmfrm_psis_loo_review.json"),
        (evidence = :exact_loo_or_kfold_review, status = :done,
            artifact = "test/fixtures/gmfrm_exact_loo_or_kfold_review.json"),
        (evidence = :guarded_exposure_review, status = :done,
            artifact = "test/fixtures/gmfrm_guarded_exposure_review.json"),
        (evidence = :guarded_fit_api_dry_run, status = :done,
            artifact = "test/fixtures/gmfrm_guarded_fit_api_dry_run.json"),
        (evidence = :guarded_fit_method_wiring, status = :done,
            artifact = "test/fixtures/gmfrm_guarded_fit_method_wiring.json"),
        (evidence = :experimental_fit_validation_grid, status = :done,
            artifact = "test/fixtures/gmfrm_experimental_fit_validation_grid.json"),
        (evidence = :posterior_predictive_grid, status = :done,
            artifact = "test/fixtures/gmfrm_posterior_predictive_grid.json"),
        (evidence = :sparse_pathology_recovery_grid, status = :done,
            artifact = "test/fixtures/gmfrm_sparse_pathology_recovery_grid.json"),
        (evidence = :prior_likelihood_sensitivity_grid, status = :done,
            artifact =
                "test/fixtures/gmfrm_prior_likelihood_sensitivity_grid.json"),
        (evidence = :real_data_case_study, status = :done,
            artifact = "test/fixtures/gmfrm_real_data_case_study.json"),
        (evidence = :claim_recovery_reproduction_archive, status = :done,
            artifact =
                "test/fixtures/gmfrm_claim_recovery_reproduction_archive.json"),
        (evidence = :broader_experimental_exposure_decision_review,
            status = :done,
            artifact =
                "test/fixtures/gmfrm_broader_experimental_exposure_decision_review.json"),
        (evidence = :mgmfrm_baseline_comparison, status = :done,
            artifact = "test/fixtures/mgmfrm_baseline_comparison.json"),
        (evidence = :mgmfrm_sparse_recovery_grid, status = :done,
            artifact = "test/fixtures/mgmfrm_sparse_recovery_grid.json"),
        (evidence = :dff_estimand_validation_grid, status = :done,
            artifact = "test/fixtures/gmfrm_dff_estimand_validation_grid.json"),
        (evidence = :manuscript_scale_simulation_grid, status = :done,
            artifact =
                "test/fixtures/gmfrm_manuscript_scale_simulation_grid.json"),
        (evidence = :full_paper_reproduction_archive, status = :done,
            artifact =
                "test/fixtures/gmfrm_full_paper_reproduction_archive.json"),
        (evidence = :direct_prior_jacobian_policy, status = :done,
            artifact = :generalized_raw_prior_jacobian_policy),
        (evidence = :raw_prior_control_manifest, status = :done,
            artifact = :generalized_raw_prior_control_manifest),
        (evidence = :public_caveat_docs, status = :done,
            artifact = "docs/src/fitting.md#guarded-generalized-model-caveats"),
    ]
end

function _gmfrm_experimental_public_blocker_rows()
    return NamedTuple[]
end

function _gmfrm_experimental_public_api_decision(blueprint)
    evidence_rows = _gmfrm_experimental_public_evidence_rows()
    blocker_rows = _gmfrm_experimental_public_blocker_rows()
    return (;
        schema = "bayesianmgmfrm.gmfrm_experimental_public_api_decision.v1",
        family = :gmfrm,
        scope = blueprint.scope,
        status = :experimental_public,
        decision = :enable_guarded_experimental,
        public_fit = true,
        experimental_public = true,
        fit_ready = true,
        proposed_entrypoint = _EXPERIMENTAL_CANONICAL_ENTRYPOINT,
        legacy_entrypoint = _EXPERIMENTAL_LEGACY_ENTRYPOINT,
        public_target_label = _GMFRM_PUBLIC_TARGET_LABEL,
        public_target_description = _GMFRM_PUBLIC_TARGET_DESCRIPTION,
        internal_target_constructor = _GMFRM_INTERNAL_TARGET_CONSTRUCTOR,
        internal_sampler_diagnostic_constructor =
            _GMFRM_INTERNAL_SAMPLER_DIAGNOSTIC_CONSTRUCTOR,
        rater_step_public_option_policy =
            _gmfrm_rater_step_public_option_policy(blueprint),
        item_discrimination_promotion_decision =
            _gmfrm_item_discrimination_promotion_decision(blueprint),
        target_constructor = _GMFRM_INTERNAL_TARGET_CONSTRUCTOR,
        sampler_diagnostic_constructor =
            _GMFRM_INTERNAL_SAMPLER_DIAGNOSTIC_CONSTRUCTOR,
        candidate_chain_study_artifact =
            "test/fixtures/gmfrm_candidate_chain_study.json",
        stress_chain_grid_artifact = "test/fixtures/gmfrm_stress_chain_grid.json",
        recovery_smoke_artifact = "test/fixtures/gmfrm_recovery_smoke.json",
        baseline_comparison_artifact =
            "test/fixtures/gmfrm_baseline_comparison.json",
        baseline_calibration_grid_artifact =
            "test/fixtures/gmfrm_baseline_calibration_grid.json",
        interval_decision_grid_artifact =
            "test/fixtures/gmfrm_interval_decision_grid.json",
        sparse_design_grid_artifact =
            "test/fixtures/gmfrm_sparse_design_grid.json",
        waic_influence_review_artifact =
            "test/fixtures/gmfrm_waic_influence_review.json",
        psis_loo_review_artifact =
            "test/fixtures/gmfrm_psis_loo_review.json",
        exact_loo_or_kfold_review_artifact =
            "test/fixtures/gmfrm_exact_loo_or_kfold_review.json",
        guarded_exposure_review_artifact =
            "test/fixtures/gmfrm_guarded_exposure_review.json",
        guarded_fit_api_dry_run_artifact =
            "test/fixtures/gmfrm_guarded_fit_api_dry_run.json",
        guarded_fit_method_wiring_artifact =
            "test/fixtures/gmfrm_guarded_fit_method_wiring.json",
        experimental_fit_validation_grid_artifact =
            "test/fixtures/gmfrm_experimental_fit_validation_grid.json",
        posterior_predictive_grid_artifact =
            "test/fixtures/gmfrm_posterior_predictive_grid.json",
        sparse_pathology_recovery_grid_artifact =
            "test/fixtures/gmfrm_sparse_pathology_recovery_grid.json",
        prior_likelihood_sensitivity_grid_artifact =
            "test/fixtures/gmfrm_prior_likelihood_sensitivity_grid.json",
        real_data_case_study_artifact =
            "test/fixtures/gmfrm_real_data_case_study.json",
        claim_recovery_reproduction_archive_artifact =
            "test/fixtures/gmfrm_claim_recovery_reproduction_archive.json",
        broader_experimental_exposure_decision_review_artifact =
            "test/fixtures/gmfrm_broader_experimental_exposure_decision_review.json",
        mgmfrm_baseline_comparison_artifact =
            "test/fixtures/mgmfrm_baseline_comparison.json",
        mgmfrm_sparse_recovery_grid_artifact =
            "test/fixtures/mgmfrm_sparse_recovery_grid.json",
        dff_estimand_validation_grid_artifact =
            "test/fixtures/gmfrm_dff_estimand_validation_grid.json",
        manuscript_scale_simulation_grid_artifact =
            "test/fixtures/gmfrm_manuscript_scale_simulation_grid.json",
        full_paper_reproduction_archive_artifact =
            "test/fixtures/gmfrm_full_paper_reproduction_archive.json",
        baseline_comparison_interpretation = (;
            status = :initial_smoke_done,
            comparison_target = :same_observation_waic,
            interpretation = :inconclusive_high_variance_smoke,
            public_exposure_support = :insufficient_alone,
            required_followup = :satisfied_by_baseline_calibration_grid_artifact,
        ),
        baseline_calibration_grid_interpretation = (;
            status = :grid_recorded,
            comparison_target = :same_observation_waic_and_expected_score_calibration,
            interpretation = :all_scenarios_passed_with_high_variance_waic_warnings,
            public_exposure_support = :reviewed_insufficient_for_public_fit,
            required_followup = :satisfied_by_interval_decision_grid_artifact,
        ),
        interval_decision_grid_interpretation = (;
            status = :grid_recorded,
            comparison_target =
                :direct_parameter_interval_coverage_and_keep_internal_stability,
            interpretation = :intervals_finite_and_keep_internal_decision_stable,
            public_exposure_support =
                :satisfied_for_sparse_design_grid_followup,
            required_followup = :satisfied_by_sparse_design_grid_artifact,
        ),
        sparse_design_grid_interpretation = (;
            status = :grid_recorded,
            comparison_target =
                :sparse_connected_design_validation_interval_and_decision_stability,
            interpretation =
                :sparse_designs_passed_with_recorded_validation_warnings,
            public_exposure_support =
                :satisfied_for_waic_influence_followup,
            required_followup = :satisfied_by_waic_influence_review_artifact,
        ),
        waic_influence_review_interpretation = (;
            status = :review_recorded,
            comparison_target =
                :pointwise_waic_influence_and_flagged_observation_sensitivity,
            interpretation =
                :flagged_observation_removal_changes_some_model_ranks,
            public_exposure_support =
                :satisfied_for_psis_loo_followup,
            required_followup = :satisfied_by_psis_loo_review_artifact,
        ),
        psis_loo_review_interpretation = (;
            status = :review_recorded,
            comparison_target = :raw_importance_loo_pareto_k_screen,
            interpretation =
                :high_pareto_k_requires_exact_loo_or_kfold,
            public_exposure_support =
                :satisfied_for_exact_loo_or_kfold_followup,
            required_followup =
                :satisfied_by_exact_loo_or_kfold_review_artifact,
        ),
        exact_loo_or_kfold_review_interpretation = (;
            status = :review_recorded,
            comparison_target = :heldout_observation_kfold_refit_log_score,
            interpretation =
                :kfold_refit_review_satisfied_exact_loo_followup,
            public_exposure_support =
                :satisfied_for_guarded_fit_api_dry_run_followup,
            required_followup = :satisfied_by_guarded_fit_api_dry_run_artifact,
        ),
        guarded_exposure_review_interpretation = (;
            status = :review_recorded,
            review_target = :experimental_public_scalar_gmfrm,
            interpretation =
                :local_evidence_reviewed_full_archive_recorded_and_broader_exposure_decision_recorded,
            public_exposure_support = :guarded_scalar_gmfrm_only,
            required_followup = :manual_publication_or_registration_by_user_only,
        ),
        guarded_fit_api_dry_run_interpretation = (;
            status = :dry_run_recorded,
            review_target = :guarded_experimental_scalar_gmfrm_fit_entrypoint,
            interpretation =
                :guarded_entrypoint_contract_dry_run_passed_but_method_not_wired,
            public_exposure_support =
                :satisfied_by_guarded_fit_method_wiring,
            required_followup = :satisfied_by_guarded_fit_method_wiring,
        ),
        guarded_fit_method_wiring_interpretation = (;
            status = :method_wired,
            review_target = :guarded_experimental_scalar_gmfrm_fit_entrypoint,
            interpretation =
                :scalar_gmfrm_guarded_experimental_fit_method_enabled,
            public_exposure_support =
                :satisfied_for_experimental_fit_validation_grid_followup,
            required_followup = :experimental_fit_validation_grid,
        ),
        experimental_fit_validation_grid_interpretation = (;
            status = :grid_recorded,
            review_target = :guarded_experimental_scalar_gmfrm_fit_entrypoint,
            interpretation =
                :guarded_scalar_gmfrm_experimental_fit_validation_grid_passed_ppc_and_sparse_pathology_checked,
            public_exposure_support =
                :satisfied_by_sparse_pathology_recovery_grid,
            required_followup = :scalar_gmfrm_prior_likelihood_sensitivity_grid,
        ),
        posterior_predictive_grid_interpretation = (;
            status = :grid_recorded,
            review_target = :guarded_experimental_scalar_gmfrm_fit_entrypoint,
            interpretation =
                :guarded_scalar_gmfrm_posterior_predictive_grid_passed,
            public_exposure_support =
                :satisfied_by_sparse_pathology_recovery_grid,
            required_followup = :scalar_gmfrm_prior_likelihood_sensitivity_grid,
        ),
        sparse_pathology_recovery_grid_interpretation = (;
            status = :grid_recorded,
            review_target = :guarded_experimental_scalar_gmfrm_fit_entrypoint,
            interpretation =
                :guarded_scalar_gmfrm_sparse_pathology_recovery_grid_passed,
            public_exposure_support =
                :satisfied_by_prior_likelihood_sensitivity_grid,
            required_followup = :scalar_gmfrm_real_data_case_study,
        ),
        prior_likelihood_sensitivity_grid_interpretation = (;
            status = :grid_recorded,
            review_target = :guarded_experimental_scalar_gmfrm_fit_entrypoint,
            interpretation =
                :guarded_scalar_gmfrm_prior_likelihood_sensitivity_grid_passed,
            public_exposure_support =
                :satisfied_by_real_data_case_study,
            required_followup = :claim_level_recovery_and_reproduction_archive,
        ),
        real_data_case_study_interpretation = (;
            status = :case_study_recorded,
            review_target = :guarded_experimental_scalar_gmfrm_fit_entrypoint,
            interpretation =
                :guarded_scalar_gmfrm_real_data_case_study_passed,
            public_exposure_support =
                :satisfied_by_claim_recovery_reproduction_archive,
            required_followup = :broader_experimental_exposure_decision_review,
        ),
        claim_recovery_reproduction_archive_interpretation = (;
            status = :archive_recorded,
            review_target = :guarded_experimental_scalar_gmfrm_claim_support,
            interpretation =
                :claim_level_recovery_reproduction_archive_recorded,
            public_exposure_support =
                :satisfied_by_broader_experimental_exposure_decision_review,
            required_followup =
                :satisfied_by_broader_experimental_exposure_decision_review,
        ),
        broader_experimental_exposure_decision_review_interpretation = (;
            status = :decision_recorded,
            review_target = :broader_generalized_model_exposure,
            interpretation =
                :broader_exposure_review_recorded_full_archive_available_keep_broader_claims_blocked,
            public_exposure_support = :guarded_scalar_gmfrm_only,
            required_followup = :manual_publication_or_registration_by_user_only,
        ),
        mgmfrm_baseline_comparison_interpretation = (;
            status = :comparison_recorded,
            comparison_target =
                :confirmatory_mgmfrm_same_observation_waic_against_mfrm_baselines,
            interpretation =
                :baseline_comparison_recorded_keep_mgmfrm_internal,
            public_exposure_support = :insufficient_for_mgmfrm_public_fit,
            required_followup = :manual_public_scope_review_for_mgmfrm_fit,
        ),
        mgmfrm_sparse_recovery_grid_interpretation = (;
            status = :grid_recorded,
            review_target = :confirmatory_mgmfrm_sparse_connected_recovery,
            interpretation =
                :sparse_recovery_grid_recorded_keep_mgmfrm_internal,
            public_exposure_support = :insufficient_for_broader_public_claims,
            required_followup = :manual_public_scope_review_for_mgmfrm_fit,
        ),
        dff_estimand_validation_grid_interpretation = (;
            status = :grid_recorded,
            review_target = :dff_estimand_validation_evidence,
            interpretation =
                :dff_estimands_predeclared_keep_model_effects_validation_only,
            public_exposure_support =
                :satisfied_for_gate_e_followup_without_dff_model_effect_fit,
            required_followup = :future_dff_model_effect_fit_policy,
        ),
        manuscript_scale_simulation_grid_interpretation = (;
            status = :grid_recorded,
            review_target = :gate_e_broader_generalized_claim_evidence,
            interpretation =
                :manuscript_scale_grid_recorded_full_archive_available,
            public_exposure_support =
                :full_archive_recorded_without_broader_fit,
            required_followup = :manual_publication_or_registration_by_user_only,
        ),
        full_paper_reproduction_archive_interpretation = (;
            status = :archive_recorded,
            review_target = :full_local_reproduction_bundle,
            interpretation =
                :full_archive_recorded_without_publication_or_registration,
            public_exposure_support =
                :local_full_reproduction_archive_recorded,
            required_followup = :manual_publication_or_registration_by_user_only,
        ),
        caveat_docs_artifact =
            "docs/src/fitting.md#guarded-generalized-model-caveats",
        prior_jacobian_policy =
            _generalized_raw_prior_jacobian_policy(
                :gmfrm,
                blueprint.scope;
                public_fit = true,
                experimental_public = true),
        raw_prior_control_manifest =
            _generalized_raw_prior_control_manifest(
                blueprint;
                public_fit = true,
                experimental_public = true),
        fit_artifact_contract = _experimental_fit_artifact_contract(
            :gmfrm,
            blueprint.scope;
            bridge_artifact = :fit_ready_scalar_gmfrm_bridge_oracle,
            candidate_chain_study_artifact =
                "test/fixtures/gmfrm_candidate_chain_study.json",
            recovery_smoke_artifact = "test/fixtures/gmfrm_recovery_smoke.json",
            caveat_docs_artifact =
                "docs/src/fitting.md#guarded-generalized-model-caveats",
            public_fit = true,
            experimental_public = true,
            artifact_kind = :experimental_generalized_fit_artifact),
        accepted_candidate_options = _gmfrm_experimental_candidate_option_rows(),
        rejected_public_options = _gmfrm_experimental_rejected_option_rows(),
        evidence_rows,
        blocker_rows,
        summary = (;
            fit_allowed = true,
            canonical_namespace_enabled = true,
            experimental_keyword_enabled = true,
            legacy_keyword_status = :compatibility_only,
            n_evidence_done = count(row -> row.status === :done, evidence_rows),
            n_evidence_pending = count(row -> row.status === :pending, evidence_rows),
            n_evidence_blocked = count(row -> row.status === :blocked, evidence_rows),
            n_blockers = length(blocker_rows),
            next_gate = :manual_publication_or_registration_by_user_only,
        ),
    )
end

function _gmfrm_direct_parameterization_candidate(blueprint)
    return (;
        schema = "bayesianmgmfrm.gmfrm_direct_parameterization_candidate.v1",
        family = :gmfrm,
        scope = blueprint.scope,
        status = :internal_promotion_candidate,
        public_fit = false,
        fit_ready = false,
        fixture_only = blueprint.fixture_only,
        density_space = :constrained_direct,
        prior_policy = :derived_from_raw_candidate_no_direct_prior,
        jacobian_policy = :not_applicable_for_direct_likelihood,
        n_parameters = length(blueprint.constrained_parameter_names),
        parameter_names = copy(blueprint.constrained_parameter_names),
        blocks = _block_manifest_rows(
            blueprint.constrained_blocks,
            blueprint.constrained_parameter_names,
        ),
        source_transforms = _source_transform_manifest_rows(blueprint),
    )
end
