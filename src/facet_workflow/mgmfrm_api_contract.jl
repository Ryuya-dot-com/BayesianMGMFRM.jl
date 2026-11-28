function _mgmfrm_confirmatory_candidate_gate_rows()
    return [
        (gate = :confirmatory_q_mask, status = :done,
            evidence = :facet_spec_q_matrix),
        (gate = :fixed_identity_latent_correlation, status = :done,
            evidence = :mgmfrm_gauge_manifest),
        (gate = :standard_normal_ability_scale, status = :done,
            evidence = :mgmfrm_gauge_manifest),
        (gate = :positive_interpreted_loadings, status = :done,
            evidence = :log_link_q_masked_loadings),
        (gate = :source_fixture_logdensity, status = :done,
            evidence = :mgmfrm_source_fixture_logdensity),
        (gate = :bridge_source_oracle, status = :done,
            evidence = :source_mgmfrm_bridge_logdensity_fixture),
        (gate = :fit_ready_raw_transform_manifest, status = :done,
            evidence = :mgmfrm_fit_ready_candidate_transform_manifest),
        (gate = :fit_ready_pointwise_fixture, status = :done,
            evidence = :mgmfrm_confirmatory_candidate_pointwise_fixture),
        (gate = :fit_ready_bridge_pointwise_oracle, status = :done,
            evidence = :fit_ready_confirmatory_mgmfrm_bridge_oracle),
        (gate = :sampler_diagnostic_study, status = :done,
            evidence = :mgmfrm_candidate_chain_study_fixture),
        (gate = :recovery_smoke_study, status = :done,
            evidence = :mgmfrm_recovery_smoke_fixture),
        (gate = :public_fit_api, status = :done,
            evidence = :mgmfrm_experimental_public_api_decision),
    ]
end

function _mgmfrm_confirmatory_gauge_rows(design::FacetDesign)
    return [
        (gauge = :q_matrix, status = :fixed,
            value = _q_matrix_manifest(design.spec.q_matrix),
            note = :confirmatory_item_dimension_mask),
        (gauge = :latent_correlation, status = :fixed,
            value = :identity,
            note = :no_free_latent_correlation_in_first_candidate),
        (gauge = :ability_location, status = :fixed,
            value = :zero_by_dimension,
            note = :source_standard_normal_ability_distribution),
        (gauge = :ability_scale, status = :fixed,
            value = :unit_variance_by_dimension,
            note = :source_standard_normal_ability_distribution),
        (gauge = :loading_sign, status = :fixed,
            value = :positive_q_masked_loadings,
            note = :interpreted_loadings_use_log_link),
        (gauge = :source_scale, status = :fixed,
            value = 1.7,
            note = :uto_ueno_logistic_scaling_constant),
    ]
end

function _mgmfrm_confirmatory_sign_rows()
    return [
        (block = :item_dimension_discrimination,
            rule = :positive_interpreted_q_masked_loadings,
            transform = :log_link,
            status = :fixed_for_candidate),
        (block = :rater_consistency,
            rule = :positive_geometric_mean_one,
            transform = :geometric_mean_one_log_last,
            status = :fixed_for_candidate),
        (block = :rater,
            rule = :sum_to_zero,
            transform = :sum_to_zero_last,
            status = :fixed_for_candidate),
        (block = :item_steps,
            rule = :first_step_zero_sum_to_zero,
            transform = :identity_with_last_derived,
            status = :source_fixture_only),
    ]
end

function _mgmfrm_confirmatory_evidence_rows()
    return [
        (evidence = :q_matrix_manifest, status = :done,
            artifact = :model_manifest_spec_q_matrix),
        (evidence = :source_linear_predictor_fixture, status = :done,
            artifact = :mgmfrm_source_fixture_values),
        (evidence = :raw_transform_fixture, status = :done,
            artifact = :mgmfrm_source_constrained_params_from_unconstrained),
        (evidence = :bridgestan_source_oracle, status = :done,
            artifact = "test/fixtures/source_mgmfrm_bridge_logdensity.json"),
        (evidence = :fit_ready_transform_manifest, status = :done,
            artifact = :mgmfrm_confirmatory_candidate_transform_manifest),
        (evidence = :fit_ready_pointwise_fixture, status = :done,
            artifact = :mgmfrm_confirmatory_candidate_pointwise_fixture),
        (evidence = :fit_ready_bridge_pointwise_oracle, status = :done,
            artifact = "test/fixtures/source_mgmfrm_bridge_logdensity.json#confirmatory_candidate"),
        (evidence = :raw_prior_control_manifest, status = :done,
            artifact = :generalized_raw_prior_control_manifest),
        (evidence = :sampler_diagnostic_study, status = :done,
            artifact = "test/fixtures/mgmfrm_candidate_chain_study.json"),
        (evidence = :recovery_smoke_study, status = :done,
            artifact = "test/fixtures/mgmfrm_recovery_smoke.json"),
    ]
end

function _mgmfrm_confirmatory_blocker_rows()
    return NamedTuple[]
end

function _mgmfrm_experimental_candidate_option_rows()
    capability = _guarded_generalized_fit_capability(:mgmfrm)
    return [
        (option = :entrypoint, value = _EXPERIMENTAL_CANONICAL_ENTRYPOINT,
            status = :enabled_guarded_experimental,
            note = :fixed_q_confirmatory_mgmfrm_only),
        (option = :legacy_entrypoint, value = _EXPERIMENTAL_LEGACY_ENTRYPOINT,
            status = :compatibility_only,
            note = :source_compatibility_during_namespace_migration),
        (option = :family, value = capability.family,
            status = :enabled_guarded_experimental,
            note = :confirmatory_mgmfrm_after_scalar_gmfrm),
        (option = :dimensions, value = :two_or_more,
            status = :enabled_guarded_experimental,
            note = :fixed_q_confirmatory_dimensions_two_or_more),
        (option = :q_matrix, value = :fixed_confirmatory,
            status = :enabled_guarded_experimental,
            note = :no_exploratory_loading_search),
        (option = :thresholds, value = only(capability.threshold_regimes),
            status = :enabled_guarded_experimental,
            note = :source_aligned_item_step_kernel),
        (option = :discrimination, value = only(capability.spec_discrimination),
            status = :enabled_guarded_experimental,
            note = :generic_selector_unused_q_masked_loadings_are_internal),
        (option = :validation_bias_terms, value = (),
            status = :enabled_guarded_experimental,
            note = :validation_only_not_fitted),
        (option = :anchors, value = (),
            status = :enabled_guarded_experimental,
            note = :anchor_likelihood_not_implemented),
        (option = :latent_correlation, value = :identity_fixed,
            status = :enabled_guarded_experimental,
            note = :no_rotation_or_correlation_estimation),
    ]
end

function _mgmfrm_experimental_rejected_option_rows()
    return [
        (option = :thresholds, value = :rating_scale,
            status = :blocked,
            blocker = :guarded_generalized_threshold_contract),
        (option = :discrimination, value = :nondefault_generic_selector,
            status = :blocked,
            blocker = :mgmfrm_generic_discrimination_not_implemented),
        (option = :bias_or_dff_terms, value = :model_effects,
            status = :blocked,
            blocker = :mgmfrm_dff_model_effects_not_implemented),
        (option = :anchors, value = :nonempty,
            status = :blocked,
            blocker = :generalized_anchor_likelihood_not_implemented),
        (option = :q_matrix, value = :estimated_or_free,
            status = :blocked,
            blocker = :q_matrix_selection_not_implemented),
        (option = :latent_correlation, value = :free,
            status = :blocked,
            blocker = :rotation_and_correlation_policy_missing),
        (option = :direct_scale_priors, value = :constrained_direct,
            status = :blocked,
            blocker = :raw_prior_policy_selected_for_candidate),
        (option = :sparse_design_claims, value = :enabled,
            status = :blocked_broader_claim,
            blocker = :broader_sparse_mgmfrm_claim_scope_not_promoted),
        (option = :baseline_comparison, value = :mfrm_rsm_pcm_comparison,
            status = :evidence_only_for_guarded_fit,
            blocker = :model_weight_or_superiority_claim_not_promoted),
    ]
end

function _mgmfrm_experimental_public_evidence_rows()
    return [
        (evidence = :confirmatory_gauge_manifest, status = :done,
            artifact = :mgmfrm_confirmatory_candidate),
        (evidence = :fit_ready_transform_manifest, status = :done,
            artifact = :mgmfrm_confirmatory_candidate_transform_manifest),
        (evidence = :bridgestan_fit_ready_oracle, status = :done,
            artifact = "test/fixtures/source_mgmfrm_bridge_logdensity.json#confirmatory_candidate"),
        (evidence = :candidate_chain_study, status = :done,
            artifact = "test/fixtures/mgmfrm_candidate_chain_study.json"),
        (evidence = :recovery_smoke_study, status = :done,
            artifact = "test/fixtures/mgmfrm_recovery_smoke.json"),
        (evidence = :public_caveat_docs, status = :done,
            artifact = "docs/src/fitting.md#guarded-generalized-model-caveats"),
        (evidence = :fit_artifact_manifest_for_experimental_public, status = :done,
            artifact = :experimental_public_fit_artifact_contract),
        (evidence = :baseline_comparison, status = :done,
            artifact = "test/fixtures/mgmfrm_baseline_comparison.json"),
        (evidence = :sparse_recovery_grid, status = :done,
            artifact = "test/fixtures/mgmfrm_sparse_recovery_grid.json"),
        (evidence = :guarded_fit_method_wiring, status = :done,
            artifact = "test/fixtures/mgmfrm_guarded_fit_method_wiring.json"),
        (evidence = :guarded_fit_validation_grid, status = :done,
            artifact = "test/fixtures/mgmfrm_guarded_fit_validation_grid.json"),
        (evidence = :guarded_fit_api_dry_run, status = :done,
            artifact = "test/fixtures/mgmfrm_guarded_fit_api_dry_run.json"),
        (evidence = :guarded_local_fit_entrypoint, status = :done,
            artifact = :_fit_guarded_mgmfrm),
        (evidence = :guarded_fit_public_exposure_review, status = :done,
            artifact =
                "test/fixtures/mgmfrm_guarded_fit_public_exposure_review.json"),
        (evidence = :prediction_target_and_model_weight_policy, status = :done,
            artifact =
                "test/fixtures/gmfrm_prediction_target_and_model_weight_policy.json"),
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
    ]
end

function _mgmfrm_experimental_public_blocker_rows()
    return NamedTuple[]
end

function _mgmfrm_experimental_public_api_decision(blueprint)
    evidence_rows = _mgmfrm_experimental_public_evidence_rows()
    blocker_rows = _mgmfrm_experimental_public_blocker_rows()
    return (;
        schema = "bayesianmgmfrm.mgmfrm_experimental_public_api_decision.v1",
        family = :mgmfrm,
        scope = blueprint.scope,
        status = :experimental_public,
        decision = :enable_guarded_experimental,
        public_fit = true,
        experimental_public = true,
        fit_ready = true,
        proposed_entrypoint = _EXPERIMENTAL_CANONICAL_ENTRYPOINT,
        legacy_entrypoint = _EXPERIMENTAL_LEGACY_ENTRYPOINT,
        public_target_label = _MGMFRM_PUBLIC_TARGET_LABEL,
        public_target_description = _MGMFRM_PUBLIC_TARGET_DESCRIPTION,
        internal_target_constructor = _MGMFRM_INTERNAL_TARGET_CONSTRUCTOR,
        internal_sampler_diagnostic_constructor =
            _MGMFRM_INTERNAL_SAMPLER_DIAGNOSTIC_CONSTRUCTOR,
        target_constructor = :_source_fixture_logdensity,
        guarded_local_entrypoint = :_fit_guarded_mgmfrm,
        guarded_local_fit_target_constructor =
            _MGMFRM_INTERNAL_TARGET_CONSTRUCTOR,
        guarded_local_fit_sampler_diagnostic_constructor =
            _MGMFRM_INTERNAL_SAMPLER_DIAGNOSTIC_CONSTRUCTOR,
        guarded_local_fit_artifact_schema =
            "bayesianmgmfrm.mgmfrm_experimental_fit_artifact.v1",
        experimental_fit_artifact_schema =
            "bayesianmgmfrm.mgmfrm_experimental_fit_artifact.v1",
        candidate_chain_study_artifact =
            "test/fixtures/mgmfrm_candidate_chain_study.json",
        recovery_smoke_artifact = "test/fixtures/mgmfrm_recovery_smoke.json",
        baseline_comparison_artifact =
            "test/fixtures/mgmfrm_baseline_comparison.json",
        sparse_recovery_grid_artifact =
            "test/fixtures/mgmfrm_sparse_recovery_grid.json",
        guarded_fit_method_wiring_artifact =
            "test/fixtures/mgmfrm_guarded_fit_method_wiring.json",
        guarded_fit_validation_grid_artifact =
            "test/fixtures/mgmfrm_guarded_fit_validation_grid.json",
        guarded_fit_api_dry_run_artifact =
            "test/fixtures/mgmfrm_guarded_fit_api_dry_run.json",
        guarded_fit_public_exposure_review_artifact =
            "test/fixtures/mgmfrm_guarded_fit_public_exposure_review.json",
        prediction_target_and_model_weight_policy_artifact =
            "test/fixtures/gmfrm_prediction_target_and_model_weight_policy.json",
        dff_estimand_validation_grid_artifact =
            "test/fixtures/gmfrm_dff_estimand_validation_grid.json",
        manuscript_scale_simulation_grid_artifact =
            "test/fixtures/gmfrm_manuscript_scale_simulation_grid.json",
        full_paper_reproduction_archive_artifact =
            "test/fixtures/gmfrm_full_paper_reproduction_archive.json",
        caveat_docs_artifact =
            "docs/src/fitting.md#guarded-generalized-model-caveats",
        prior_jacobian_policy =
            _generalized_raw_prior_jacobian_policy(
                :mgmfrm,
                blueprint.scope;
                public_fit = true,
                experimental_public = true),
        raw_prior_control_manifest =
            _generalized_raw_prior_control_manifest(
                blueprint;
                public_fit = true,
                experimental_public = true),
        fit_artifact_contract = _experimental_fit_artifact_contract(
            :mgmfrm,
            blueprint.scope;
            bridge_artifact =
                "test/fixtures/source_mgmfrm_bridge_logdensity.json#confirmatory_candidate",
            candidate_chain_study_artifact =
                "test/fixtures/mgmfrm_candidate_chain_study.json",
            recovery_smoke_artifact = "test/fixtures/mgmfrm_recovery_smoke.json",
            caveat_docs_artifact =
                "docs/src/fitting.md#guarded-generalized-model-caveats",
            public_fit = true,
            experimental_public = true,
            artifact_kind = :experimental_generalized_fit_artifact),
        accepted_candidate_options = _mgmfrm_experimental_candidate_option_rows(),
        rejected_public_options = _mgmfrm_experimental_rejected_option_rows(),
        guarded_fit_public_exposure_review_interpretation = (;
            status = :review_recorded,
            review_target = :confirmatory_mgmfrm_guarded_fit_public_exposure,
            interpretation =
                :guarded_mgmfrm_public_exposure_review_recorded_enable_guarded_experimental,
            public_exposure_support =
                :supports_fixed_q_confirmatory_mgmfrm_experimental_fit,
            required_followup =
                :satisfied_by_prediction_target_and_model_weight_policy,
        ),
        prediction_target_and_model_weight_policy_interpretation = (;
            status = :policy_recorded,
            review_target =
                :guarded_scalar_gmfrm_and_confirmatory_mgmfrm_claim_boundaries,
            interpretation =
                :heldout_kfold_selected_enable_guarded_mgmfrm_fit_without_weight_claims,
            public_exposure_support =
                :guarded_confirmatory_mgmfrm_fit_enabled_no_weight_claims,
            required_followup = :manual_publication_or_registration_by_user_only,
        ),
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

function _mgmfrm_confirmatory_candidate(blueprint, design::FacetDesign)
    evidence_rows = _mgmfrm_confirmatory_evidence_rows()
    blocker_rows = _mgmfrm_confirmatory_blocker_rows()
    return (;
        schema = "bayesianmgmfrm.mgmfrm_confirmatory_candidate.v1",
        family = :mgmfrm,
        scope = blueprint.scope,
        status = blueprint.status,
        public_fit = true,
        experimental_public = true,
        fit_ready = true,
        fixture_only = blueprint.fixture_only,
        source_fixture_only = false,
        compiler_stage = blueprint.compiler_stage,
        source_oracle = :mgmfrm_source_aligned,
        fit_ready_transform_ready = true,
        fit_ready_pointwise_oracle_ready = true,
        dimensions = design.spec.dimensions,
        q_matrix = _q_matrix_manifest(design.spec.q_matrix),
        latent_correlation = :identity_fixed,
        ability_location = :zero_by_dimension,
        ability_scale = :unit_variance_by_dimension,
        source_scale = 1.7,
        interpreted_loading_sign = :positive,
        raw_parameter_names = copy(blueprint.parameter_names),
        raw_blocks = _block_manifest_rows(blueprint.blocks, blueprint.parameter_names),
        constrained_parameter_names = copy(blueprint.constrained_parameter_names),
        constrained_blocks = _block_manifest_rows(
            blueprint.constrained_blocks,
            blueprint.constrained_parameter_names,
        ),
        raw_prior_control_manifest =
            _generalized_raw_prior_control_manifest(
                blueprint;
                public_fit = true,
                experimental_public = true),
        gauge_rows = _mgmfrm_confirmatory_gauge_rows(design),
        sign_positive_rules = _mgmfrm_confirmatory_sign_rows(),
        evidence_rows,
        blocker_rows,
        candidate_gates = _mgmfrm_confirmatory_candidate_gate_rows(),
        experimental_public_api_decision =
            _mgmfrm_experimental_public_api_decision(blueprint),
        summary = (;
            candidate_frozen = true,
            fit_allowed = true,
            n_evidence_done = count(row -> row.status === :done, evidence_rows),
            n_evidence_pending = count(row -> row.status === :pending, evidence_rows),
            n_blockers = length(blocker_rows),
            next_gate = :manual_publication_or_registration_by_user_only,
        ),
    )
end

function _raw_parameterization_promotion_candidate(blueprint)
    blueprint.family === :gmfrm || return nothing
    return (;
        schema = "bayesianmgmfrm.gmfrm_promotion_candidate.v1",
        family = :gmfrm,
        scope = blueprint.scope,
        status = :internal_promotion_candidate,
        public_fit = false,
        fit_ready = false,
        fixture_only = blueprint.fixture_only,
        compiler_stage = blueprint.compiler_stage,
        source_oracle = :scalar_gmfrm_source_aligned,
        transform_ready = true,
        logdensity_ready = true,
        bridge_oracle_ready = true,
        bridge_direct_ready = true,
        direct_pointwise_ready = true,
        sampler_smoke_ready = true,
        production_diagnostics_ready = true,
        candidate_chain_study_ready = true,
        stress_chain_grid_ready = true,
        recovery_smoke_ready = true,
        baseline_comparison_ready = true,
        baseline_calibration_grid_ready = true,
        interval_decision_grid_ready = true,
        sparse_design_grid_ready = true,
        waic_influence_review_ready = true,
        psis_loo_review_ready = true,
        exact_loo_or_kfold_review_ready = true,
        guarded_exposure_review_ready = true,
        guarded_fit_api_dry_run_ready = true,
        guarded_fit_method_wiring_ready = true,
        experimental_fit_validation_grid_ready = true,
        posterior_predictive_grid_ready = true,
        sparse_pathology_recovery_grid_ready = true,
        prior_likelihood_sensitivity_grid_ready = true,
        real_data_case_study_ready = true,
        claim_recovery_reproduction_archive_ready = true,
        broader_experimental_exposure_decision_review_ready = true,
        fit_ready_compiler_ready = true,
        experimental_public_ready = true,
        public_target_label = _GMFRM_PUBLIC_TARGET_LABEL,
        public_target_description = _GMFRM_PUBLIC_TARGET_DESCRIPTION,
        internal_target_constructor = _GMFRM_INTERNAL_TARGET_CONSTRUCTOR,
        internal_diagnostic_constructor =
            _GMFRM_INTERNAL_GRADIENT_DIAGNOSTIC_CONSTRUCTOR,
        internal_sampler_diagnostic_constructor =
            _GMFRM_INTERNAL_SAMPLER_DIAGNOSTIC_CONSTRUCTOR,
        rater_step_public_option_policy =
            _gmfrm_rater_step_public_option_policy(blueprint),
        item_discrimination_promotion_decision =
            _gmfrm_item_discrimination_promotion_decision(blueprint),
        target_constructor = _GMFRM_INTERNAL_TARGET_CONSTRUCTOR,
        diagnostic_constructor = _GMFRM_INTERNAL_GRADIENT_DIAGNOSTIC_CONSTRUCTOR,
        sampler_diagnostic_constructor =
            _GMFRM_INTERNAL_SAMPLER_DIAGNOSTIC_CONSTRUCTOR,
        pointwise_fixture_constructor = :_gmfrm_promotion_candidate_pointwise_fixture,
        compiler_blueprint_constructor = :_gmfrm_fit_ready_candidate_blueprint,
        density_space = :raw_unconstrained,
        prior_policy = :independent_normal_raw_coordinates,
        jacobian_policy = :none_raw_coordinate_density,
        raw_prior_control_manifest =
            _generalized_raw_prior_control_manifest(blueprint),
        n_raw_parameters = blueprint.n_parameters,
        raw_parameter_names = copy(blueprint.parameter_names),
        raw_blocks = _block_manifest_rows(blueprint.blocks, blueprint.parameter_names),
        fit_ready_compiler = _gmfrm_fit_ready_compiler_candidate(blueprint),
        direct_parameterization = _gmfrm_direct_parameterization_candidate(blueprint),
        experimental_public_api =
            _gmfrm_experimental_public_api_decision(blueprint),
        candidate_gates = _promotion_candidate_gate_rows(:gmfrm),
    )
end

function _raw_parameterization_manifest(design::FacetDesign)
    _is_mfrm_fixed_q(design.spec) && return _mfrm_fixed_q_parameter_layout(design)
    if design.spec.family === :gmfrm
        source_blueprint = _gmfrm_source_unconstrained_blueprint(design)
        candidate_blueprint = _gmfrm_fit_ready_candidate_blueprint(design)
        confirmatory_candidate = nothing
    elseif design.spec.family === :mgmfrm
        source_blueprint = _mgmfrm_source_unconstrained_blueprint(design)
        candidate_blueprint = _mgmfrm_fit_ready_candidate_blueprint(design)
        confirmatory_candidate = _mgmfrm_confirmatory_candidate(candidate_blueprint, design)
    else
        return nothing
    end
    return (;
        schema = "bayesianmgmfrm.raw_parameterization.v1",
        family = source_blueprint.family,
        status = :internal_source_fixture,
        public_fit = false,
        fit_ready = source_blueprint.fit_ready,
        fixture_only = source_blueprint.fixture_only,
        density_space = :raw_unconstrained,
        prior_policy = :independent_normal_raw_coordinates,
        jacobian_policy = :none_raw_coordinate_density,
        n_raw_parameters = source_blueprint.n_parameters,
        raw_parameter_names = copy(source_blueprint.parameter_names),
        constrained_parameter_names = copy(source_blueprint.constrained_parameter_names),
        raw_blocks = _block_manifest_rows(source_blueprint.blocks, source_blueprint.parameter_names),
        constrained_blocks = _block_manifest_rows(
            source_blueprint.constrained_blocks,
            source_blueprint.constrained_parameter_names,
        ),
        transforms = _source_transform_manifest_rows(source_blueprint),
        promotion_candidate = _raw_parameterization_promotion_candidate(candidate_blueprint),
        confirmatory_candidate,
    )
end
