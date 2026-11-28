function _source_transform_declarations(family::Symbol)
    family === :gmfrm && return NamedTuple[
        (raw_block = :person, constrained_block = :person, transform = :identity,
            constraint = :free, prior_block = :person),
        (raw_block = :rater, constrained_block = :rater, transform = :identity,
            constraint = :free, prior_block = :rater),
        (raw_block = :item_free, constrained_block = :item, transform = :sum_to_zero_last,
            constraint = :sum_to_zero, prior_block = :item),
        (raw_block = :log_item_discrimination_free, constrained_block = :item_discrimination,
            transform = :geometric_mean_one_log_last, constraint = :geometric_mean_one,
            prior_block = :log_item_discrimination),
        (raw_block = :log_rater_consistency, constrained_block = :rater_consistency,
            transform = :positive_log, constraint = :positive,
            prior_block = :log_rater_consistency),
        (raw_block = :rater_steps, constrained_block = :rater_steps, transform = :identity,
            constraint = :first_step_zero_sum_to_zero, prior_block = :rater_steps),
    ]
    family === :mgmfrm && return NamedTuple[
        (raw_block = :person, constrained_block = :person, transform = :identity,
            constraint = :multidimensional_location_gauge, prior_block = :person),
        (raw_block = :rater_free, constrained_block = :rater, transform = :sum_to_zero_last,
            constraint = :sum_to_zero, prior_block = :rater),
        (raw_block = :item, constrained_block = :item, transform = :identity,
            constraint = :free, prior_block = :item),
        (raw_block = :log_item_dimension_discrimination,
            constrained_block = :item_dimension_discrimination,
            transform = :positive_log_q_mask, constraint = :confirmatory_q_mask,
            prior_block = :log_item_dimension_discrimination),
        (raw_block = :log_rater_consistency_free, constrained_block = :rater_consistency,
            transform = :geometric_mean_one_log_last, constraint = :geometric_mean_one,
            prior_block = :log_rater_consistency),
        (raw_block = :item_steps, constrained_block = :item_steps, transform = :identity,
            constraint = :first_step_zero_sum_to_zero, prior_block = :item_steps),
    ]
    return NamedTuple[]
end

function _source_transform_manifest_rows(blueprint)
    rows = NamedTuple[]
    for declaration in _source_transform_declarations(blueprint.family)
        raw_range = blueprint.blocks[declaration.raw_block]
        constrained_range = blueprint.constrained_blocks[declaration.constrained_block]
        raw_indices = collect(raw_range)
        constrained_indices = collect(constrained_range)
        push!(rows, merge(declaration, (;
            raw_first_parameter = isempty(raw_indices) ? missing : first(raw_indices),
            raw_last_parameter = isempty(raw_indices) ? missing : last(raw_indices),
            raw_n_parameters = length(raw_indices),
            raw_parameter_names = isempty(raw_indices) ? String[] : copy(blueprint.parameter_names[raw_indices]),
            constrained_first_parameter = isempty(constrained_indices) ? missing : first(constrained_indices),
            constrained_last_parameter = isempty(constrained_indices) ? missing : last(constrained_indices),
            constrained_n_parameters = length(constrained_indices),
            constrained_parameter_names = isempty(constrained_indices) ? String[] :
                copy(blueprint.constrained_parameter_names[constrained_indices]),
            jacobian_policy = :none_raw_coordinate_density,
        )))
    end
    return rows
end

function _raw_prior_parameter_space(raw_block::Symbol)
    raw_block in (:log_item_discrimination_free,
        :log_item_dimension_discrimination,
        :log_rater_consistency,
        :log_rater_consistency_free) &&
        return :raw_log_positive_coordinate
    raw_block in (:rater_steps, :item_steps) &&
        return :raw_constrained_step_coordinate
    return :raw_unconstrained_coordinate
end

function _raw_prior_public_surface_role(family::Symbol, raw_block::Symbol)
    family === :gmfrm && raw_block === :log_rater_consistency &&
        return :guarded_scalar_gmfrm_core
    family === :gmfrm && raw_block === :log_item_discrimination_free &&
        return :source_block_active_public_item_target_preview_only
    family === :mgmfrm && raw_block === :log_item_dimension_discrimination &&
        return :fixed_q_loading_core
    family === :mgmfrm && raw_block === :log_rater_consistency_free &&
        return :fixed_q_rater_consistency_core
    raw_block in (:rater_steps, :item_steps) &&
        return :source_step_block_not_public_option
    return :guarded_generalized_support_block
end

function _generalized_raw_prior_control_rows(blueprint)
    rows = NamedTuple[]
    for transform in _source_transform_manifest_rows(blueprint)
        scale_parameter = _surface_prior_scale(
            transform.prior_block,
            transform.constrained_block,
        )
        push!(rows, (;
            schema = "bayesianmgmfrm.generalized_raw_prior_control_row.v1",
            family = blueprint.family,
            scope = blueprint.scope,
            status = :active,
            density_space = :raw_unconstrained,
            raw_block = transform.raw_block,
            constrained_block = transform.constrained_block,
            prior_block = transform.prior_block,
            parameter_space = _raw_prior_parameter_space(transform.raw_block),
            prior_family = :normal,
            location = 0.0,
            scale_parameter,
            scale = missing,
            scale_status = :symbolic_control,
            direct_scale_prior = false,
            jacobian_policy = transform.jacobian_policy,
            transform = transform.transform,
            constraint = transform.constraint,
            raw_n_parameters = transform.raw_n_parameters,
            raw_parameter_names = copy(transform.raw_parameter_names),
            constrained_n_parameters = transform.constrained_n_parameters,
            constrained_parameter_names = copy(transform.constrained_parameter_names),
            independent_by_parameter = true,
            public_surface_role =
                _raw_prior_public_surface_role(blueprint.family, transform.raw_block),
        ))
    end
    push!(rows, (;
        schema = "bayesianmgmfrm.generalized_raw_prior_control_row.v1",
        family = blueprint.family,
        scope = blueprint.scope,
        status = :blocked,
        density_space = :raw_unconstrained,
        raw_block = missing,
        constrained_block = :direct_scale_generalized_priors,
        prior_block = missing,
        parameter_space = :direct_constrained_parameter,
        prior_family = :not_enabled,
        location = 0.0,
        scale_parameter = :not_applicable,
        scale = missing,
        scale_status = :not_applicable,
        direct_scale_prior = true,
        jacobian_policy = :requires_future_log_jacobian_policy,
        transform = :not_enabled,
        constraint = :not_enabled,
        raw_n_parameters = 0,
        raw_parameter_names = String[],
        constrained_n_parameters = 0,
        constrained_parameter_names = String[],
        independent_by_parameter = false,
        public_surface_role = :blocked_direct_scale_prior_policy,
    ))
    return rows
end

function _generalized_raw_prior_control_manifest(blueprint;
        public_fit::Bool = false,
        experimental_public::Bool = public_fit)
    rows = _generalized_raw_prior_control_rows(blueprint)
    return (;
        schema = "bayesianmgmfrm.generalized_raw_prior_control_manifest.v1",
        family = blueprint.family,
        scope = blueprint.scope,
        status = :policy_recorded,
        density_space = :raw_unconstrained,
        prior_policy = :independent_normal_raw_coordinates,
        direct_scale_priors = false,
        direct_prior_policy = :not_enabled_raw_coordinate_priors_only,
        jacobian_policy = :none_raw_coordinate_density,
        public_fit,
        experimental_public,
        rows,
        n_rows = length(rows),
        summary = (;
            n_active_rows = count(row -> row.status === :active, rows),
            n_blocked_rows = count(row -> row.status === :blocked, rows),
            raw_rater_consistency_control_recorded =
                any(row -> row.raw_block in
                    (:log_rater_consistency, :log_rater_consistency_free), rows),
            item_discrimination_source_control_recorded =
                any(row -> row.raw_block in
                    (:log_item_discrimination_free,
                        :log_item_dimension_discrimination), rows),
            direct_scale_generalized_priors_enabled = false,
            all_active_rows_no_jacobian =
                all(row -> row.status !== :active ||
                    row.jacobian_policy === :none_raw_coordinate_density, rows),
        ),
    )
end

function _fit_ready_candidate_constraint_rows(blueprint)
    rows = NamedTuple[]
    for transform in _source_transform_manifest_rows(blueprint)
        push!(rows, (;
            raw_block = transform.raw_block,
            constrained_block = transform.constrained_block,
            constraint = transform.constraint,
            transform = transform.transform,
            status = :internal_fit_ready_candidate,
            prior_block = transform.prior_block,
            raw_n_parameters = transform.raw_n_parameters,
            constrained_n_parameters = transform.constrained_n_parameters,
            jacobian_policy = transform.jacobian_policy,
        ))
    end
    return rows
end

const _GMFRM_PUBLIC_TARGET_LABEL = :guarded_scalar_gmfrm_logdensity
const _GMFRM_PUBLIC_TARGET_DESCRIPTION = "guarded scalar GMFRM log density"
const _GMFRM_INTERNAL_TARGET_CONSTRUCTOR = :_gmfrm_promotion_candidate_logdensity
const _GMFRM_INTERNAL_GRADIENT_DIAGNOSTIC_CONSTRUCTOR =
    :_gmfrm_promotion_candidate_diagnostics
const _GMFRM_INTERNAL_SAMPLER_DIAGNOSTIC_CONSTRUCTOR =
    :_gmfrm_promotion_candidate_sampler_diagnostics
const _MGMFRM_PUBLIC_TARGET_LABEL = :guarded_confirmatory_mgmfrm_logdensity
const _MGMFRM_PUBLIC_TARGET_DESCRIPTION =
    "guarded fixed-Q confirmatory MGMFRM log density"
const _MGMFRM_INTERNAL_TARGET_CONSTRUCTOR =
    :_mgmfrm_guarded_local_fit_logdensity
const _MGMFRM_INTERNAL_SAMPLER_DIAGNOSTIC_CONSTRUCTOR =
    :_mgmfrm_guarded_local_fit_sampler_diagnostics

function _gmfrm_rater_step_public_option_policy(blueprint)
    return (;
        schema = "bayesianmgmfrm.gmfrm_rater_step_public_option_policy.v1",
        family = :gmfrm,
        scope = blueprint.scope,
        status = :policy_recorded,
        source_block = :rater_steps,
        source_block_status = :internal_source_model_block,
        internal_block_enabled = true,
        public_option = :rater_steps,
        public_keyword_enabled = false,
        public_option_status = :blocked_until_policy_gate,
        blocker = :rater_step_public_option_policy_not_promoted,
        next_gate = :rater_step_public_option_policy,
        required_before_public_rejection = true,
        rationale = :rater_steps_are_source_equation_terms_not_public_fit_options,
    )
end

function _gmfrm_item_discrimination_promotion_decision(blueprint)
    return (;
        schema = "bayesianmgmfrm.gmfrm_item_discrimination_promotion_decision.v1",
        family = :gmfrm,
        scope = blueprint.scope,
        status = :decision_recorded,
        decision = :keep_preview_only_for_v0_1_1,
        public_option = :discrimination,
        requested_public_value = :item,
        guarded_public_value = :rater,
        source_block = :item_discrimination,
        source_block_status = :enabled_within_guarded_rater_consistency_surface,
        preview_design_available = true,
        public_fit_enabled = false,
        internal_promotion_target_enabled = false,
        blocked_option = :discrimination,
        blocked_value = :item,
        blocker = :item_discrimination_promotion_target_not_selected,
        next_gate = :item_discrimination_promotion_decision,
        required_before_promotion = (
            :separate_item_discrimination_estimand,
            :bridge_oracle,
            :candidate_chain_study,
            :recovery_smoke,
            :prior_sensitivity,
            :artifact_contract_review,
        ),
        rationale =
            :v0_1_1_keeps_only_guarded_rater_consistency_scalar_gmfrm_fit,
    )
end

function _gmfrm_fit_ready_compiler_candidate(blueprint)
    return (;
        schema = "bayesianmgmfrm.gmfrm_fit_ready_compiler_candidate.v1",
        family = :gmfrm,
        scope = :scalar_gmfrm_fit_ready_candidate,
        status = :internal_fit_ready_candidate,
        public_fit = false,
        fit_ready = false,
        fixture_only = false,
        compiler_stage = :fit_ready_candidate,
        source_oracle = :scalar_gmfrm_source_aligned,
        density_space = :raw_unconstrained,
        prior_policy = :independent_normal_raw_coordinates,
        direct_prior_policy = :not_enabled_raw_coordinate_priors_only,
        jacobian_policy = :none_raw_coordinate_density,
        raw_prior_control_manifest =
            _generalized_raw_prior_control_manifest(blueprint),
        public_target_label = _GMFRM_PUBLIC_TARGET_LABEL,
        public_target_description = _GMFRM_PUBLIC_TARGET_DESCRIPTION,
        internal_target_constructor = _GMFRM_INTERNAL_TARGET_CONSTRUCTOR,
        rater_step_public_option_policy =
            _gmfrm_rater_step_public_option_policy(blueprint),
        item_discrimination_promotion_decision =
            _gmfrm_item_discrimination_promotion_decision(blueprint),
        n_raw_parameters = blueprint.n_parameters,
        raw_parameter_names = copy(blueprint.parameter_names),
        constrained_parameter_names = copy(blueprint.constrained_parameter_names),
        raw_blocks = _block_manifest_rows(blueprint.blocks, blueprint.parameter_names),
        constrained_blocks = _block_manifest_rows(
            blueprint.constrained_blocks,
            blueprint.constrained_parameter_names,
        ),
        transforms = _source_transform_manifest_rows(blueprint),
        constraints = _fit_ready_candidate_constraint_rows(blueprint),
        unsupported_public_options = [
            :direct_scale_priors,
            :dff_effects,
            :multidimensional_ability,
            :free_latent_correlation,
            :item_discrimination_public_target,
            :public_rater_steps,
            :hierarchical_rater_thresholds,
        ],
    )
end

function _promotion_candidate_gate_rows(family::Symbol)
    family === :gmfrm && return [
        (gate = :raw_transform_manifest, status = :done,
            evidence = :design_raw_parameterization),
        (gate = :fit_ready_compiler_manifest, status = :done,
            evidence = :gmfrm_fit_ready_compiler_candidate),
        (gate = :direct_parameter_metadata, status = :done,
            evidence = :constrained_block_manifest),
        (gate = :raw_to_direct_transform, status = :done,
            evidence = :promotion_candidate_transform_diagnostics),
        (gate = :direct_pointwise_fixture, status = :done,
            evidence = :promotion_candidate_pointwise_fixture),
        (gate = :pointwise_likelihood_fixture, status = :done,
            evidence = :source_aligned_julia_fixture),
        (gate = :logdensity_gradient_check, status = :done,
            evidence = :forwarddiff_finite_difference_test),
        (gate = :bridge_oracle_check, status = :done,
            evidence = :bridgestan_logdensity_gradient_fixture),
        (gate = :bridge_direct_parameter_check, status = :done,
            evidence = :bridgestan_constrained_parameter_fixture),
        (gate = :hmc_smoke_check, status = :done,
            evidence = :advancedhmc_fixture_smoke_test),
        (gate = :public_fit_api, status = :blocked,
            evidence = :fit_rejects_specified_only_gmfrm),
        (gate = :production_diagnostics, status = :done,
            evidence = :promotion_candidate_sampler_diagnostics),
        (gate = :candidate_chain_study, status = :done,
            evidence = :gmfrm_candidate_chain_study_fixture),
        (gate = :stress_chain_grid, status = :done,
            evidence = :gmfrm_stress_chain_grid_fixture),
        (gate = :recovery_smoke_study, status = :done,
            evidence = :gmfrm_recovery_smoke_fixture),
        (gate = :baseline_comparison, status = :done,
            evidence = :gmfrm_baseline_comparison_fixture),
        (gate = :baseline_calibration_grid, status = :done,
            evidence = :gmfrm_baseline_calibration_grid_fixture),
        (gate = :interval_decision_grid, status = :done,
            evidence = :gmfrm_interval_decision_grid_fixture),
        (gate = :sparse_design_grid, status = :done,
            evidence = :gmfrm_sparse_design_grid_fixture),
        (gate = :waic_influence_review, status = :done,
            evidence = :gmfrm_waic_influence_review_fixture),
        (gate = :psis_loo_review, status = :done,
            evidence = :gmfrm_psis_loo_review_fixture),
        (gate = :exact_loo_or_kfold_review, status = :done,
            evidence = :gmfrm_exact_loo_or_kfold_review_fixture),
        (gate = :guarded_exposure_review, status = :done,
            evidence = :gmfrm_guarded_exposure_review_fixture),
        (gate = :guarded_fit_api_dry_run, status = :done,
            evidence = :gmfrm_guarded_fit_api_dry_run_fixture),
        (gate = :guarded_fit_method_wiring, status = :done,
            evidence = :gmfrm_guarded_fit_method_wiring_fixture),
        (gate = :experimental_fit_validation_grid, status = :done,
            evidence = :gmfrm_experimental_fit_validation_grid_fixture),
        (gate = :posterior_predictive_grid, status = :done,
            evidence = :gmfrm_posterior_predictive_grid_fixture),
        (gate = :sparse_pathology_recovery_grid, status = :done,
            evidence = :gmfrm_sparse_pathology_recovery_grid_fixture),
        (gate = :prior_likelihood_sensitivity_grid, status = :done,
            evidence = :gmfrm_prior_likelihood_sensitivity_grid_fixture),
        (gate = :real_data_case_study, status = :done,
            evidence = :gmfrm_real_data_case_study_fixture),
        (gate = :claim_recovery_reproduction_archive, status = :done,
            evidence = :gmfrm_claim_recovery_reproduction_archive_fixture),
        (gate = :broader_experimental_exposure_decision_review, status = :done,
            evidence = :gmfrm_broader_experimental_exposure_decision_review_fixture),
        (gate = :direct_scale_prior_jacobian_policy, status = :done,
            evidence = :raw_prior_jacobian_policy_decision),
        (gate = :experimental_public_api, status = :done,
            evidence = :gmfrm_experimental_public_api_decision),
    ]
    return NamedTuple[]
end

function _gmfrm_experimental_candidate_option_rows()
    capability = _guarded_generalized_fit_capability(:gmfrm)
    return [
        (option = :entrypoint, value = _EXPERIMENTAL_CANONICAL_ENTRYPOINT,
            status = :enabled_guarded,
            note = :scalar_gmfrm_only),
        (option = :legacy_entrypoint, value = _EXPERIMENTAL_LEGACY_ENTRYPOINT,
            status = :compatibility_only,
            note = :source_compatibility_during_namespace_migration),
        (option = :family, value = capability.family,
            status = :candidate_only,
            note = :scalar_gmfrm_before_mgmfrm),
        (option = :dimensions, value = capability.minimum_dimensions,
            status = :candidate_only,
            note = :one_dimensional_only),
        (option = :thresholds, value = only(capability.threshold_regimes),
            status = :candidate_only,
            note = :source_aligned_rater_step_kernel),
        (option = :discrimination, value = only(capability.spec_discrimination),
            status = :candidate_only,
            note = :source_aligned_scalar_gmfrm_fixture),
        (option = :validation_bias_terms, value = (),
            status = :candidate_only,
            note = :validation_only_not_fitted),
        (option = :anchors, value = (),
            status = :candidate_only,
            note = :anchor_likelihood_not_implemented),
        (option = :density_space, value = :raw_unconstrained,
            status = :candidate_only,
            note = :raw_coordinate_prior_contract_required),
        (option = :rater_steps, value = :internal_source_block,
            status = :candidate_only,
            note = :not_a_public_fit_option),
    ]
end

function _gmfrm_experimental_rejected_option_rows()
    return [
        (option = :thresholds, value = :rating_scale,
            status = :blocked,
            blocker = :guarded_generalized_threshold_contract),
        (option = :anchors, value = :nonempty,
            status = :blocked,
            blocker = :generalized_anchor_likelihood_not_implemented),
        (option = :family, value = :mgmfrm,
            status = :blocked,
            blocker = :mgmfrm_baseline_sparse_prior_policy_pending),
        (option = :dimensions, value = :multidimensional,
            status = :blocked,
            blocker = :mgmfrm_public_scope_not_promoted),
        (option = :discrimination, value = :item,
            status = :blocked,
            blocker = :item_discrimination_promotion_target_not_selected),
        (option = :direct_scale_priors, value = :constrained_direct,
            status = :blocked,
            blocker = :raw_prior_policy_selected_for_candidate),
        (option = :bias_or_dff_terms, value = :model_effects,
            status = :blocked,
            blocker = :dff_model_effect_fit_policy_not_promoted),
        (option = :hierarchical_rater_thresholds, value = :enabled,
            status = :blocked,
            blocker = :pooling_and_identification_policy_missing),
        (option = :rater_steps, value = :public_option,
            status = :blocked,
            blocker = :rater_step_public_option_policy_not_promoted),
        (option = :model_comparison_weights, value = :loo_or_stacking,
            status = :blocked,
            blocker = :psis_loo_pareto_k_target_missing),
    ]
end

function _experimental_fit_artifact_contract_field_rows(family::Symbol)
    rows = [
        (field = :schema, status = :required,
            note = :family_specific_experimental_fit_artifact_schema),
        (field = :experimental_public, status = :required,
            note = :true_only_when_guarded_entrypoint_is_enabled),
        (field = :public_fit, status = :required,
            note = :must_match_manifest_decision),
        (field = :family, status = :required,
            note = :generalized_family_name),
        (field = :scope, status = :required,
            note = :narrow_candidate_scope),
        (field = :public_target_label, status = :required,
            note = :stable_user_facing_guarded_fit_target_name),
        (field = :internal_target_constructor, status = :required,
            note = :private_helper_name_kept_as_compatibility_metadata),
        (field = :density_space, status = :required,
            note = :raw_unconstrained_or_documented_direct_policy),
        (field = :raw_prior_control_manifest, status = :required,
            note = :block_level_raw_prior_controls_and_no_jacobian_policy),
        (field = :parameter_layout, status = :required,
            note = :compiler_generated_raw_direct_blocks_transforms_and_constraints),
        (field = :raw_parameter_names, status = :required,
            note = :sampler_coordinate_order),
        (field = :direct_parameter_names, status = :required,
            note = :interpretable_constrained_order),
        (field = :raw_to_direct_transform, status = :required,
            note = :constraint_and_jacobian_policy_provenance),
        (field = :sampler_controls, status = :required,
            note = :backend_seed_warmup_draws_chains_and_metric),
        (field = :diagnostics, status = :required,
            note = :rhat_ess_divergence_treedepth_and_ebfmi_rows),
        (field = :pointwise_loglikelihood, status = :required,
            note = :observation_ordered_loglikelihood_matrix),
        (field = :caveat_docs_artifact, status = :required,
            note = :guarded_generalized_model_caveats),
        (field = :fixture_provenance, status = :required,
            note = :bridge_chain_recovery_artifact_paths_and_hashes),
        (field = :raw_posterior_row_schema, status = :required,
            note = :raw_posterior_summary_fields_and_compiler_block_provenance),
        (field = :direct_posterior_row_schema, status = :required,
            note = :direct_posterior_summary_fields_and_compiler_block_provenance),
    ]
    family === :mgmfrm || return rows
    return [
        rows...,
        (field = :q_matrix, status = :required,
            note = :fixed_confirmatory_mask),
        (field = :latent_correlation, status = :required,
            note = :identity_fixed_for_first_candidate),
        (field = :ability_scale, status = :required,
            note = :standard_normal_gauge),
        (field = :initialization_policy, status = :required,
            note = :raw_initial_source_fallback_and_finite_logdensity_policy),
        (field = :initialization_rows, status = :required,
            note = :row_level_initial_raw_direct_and_chain_jitter_checks),
        (field = :fixed_q_invariance_rows, status = :required,
            note = :fixed_q_sign_identity_correlation_and_blocked_rotation_checks),
    ]
end

function _experimental_fit_artifact_contract_provenance_rows(;
        bridge_artifact,
        candidate_chain_study_artifact,
        recovery_smoke_artifact,
        caveat_docs_artifact)
    return [
        (artifact = :bridge_oracle, status = :required,
            value = bridge_artifact,
            hash_policy = :sha256_when_exported),
        (artifact = :candidate_chain_study, status = :required,
            value = candidate_chain_study_artifact,
            hash_policy = :sha256_when_exported),
        (artifact = :recovery_smoke_study, status = :required,
            value = recovery_smoke_artifact,
            hash_policy = :sha256_when_exported),
        (artifact = :caveat_docs, status = :required,
            value = caveat_docs_artifact,
            hash_policy = :git_blob_or_sha256_when_exported),
    ]
end

function _experimental_fit_artifact_contract(family::Symbol,
        scope::Symbol;
        bridge_artifact,
        candidate_chain_study_artifact,
        recovery_smoke_artifact,
        caveat_docs_artifact,
        public_fit::Bool = false,
        experimental_public::Bool = public_fit,
        artifact_kind::Symbol = public_fit ?
            :experimental_generalized_fit_artifact :
            :future_experimental_generalized_fit_artifact)
    required_fields = _experimental_fit_artifact_contract_field_rows(family)
    provenance_rows = _experimental_fit_artifact_contract_provenance_rows(;
        bridge_artifact,
        candidate_chain_study_artifact,
        recovery_smoke_artifact,
        caveat_docs_artifact)
    return (;
        schema = "bayesianmgmfrm.experimental_generalized_fit_artifact_contract.v1",
        family,
        scope,
        status = :contract_recorded,
        public_fit,
        experimental_public,
        artifact_kind,
        required_fields,
        provenance_rows,
        summary = (;
            n_required_fields = length(required_fields),
            n_required_provenance_artifacts = length(provenance_rows),
            enables_public_fit = public_fit,
        ),
    )
end

function _generalized_raw_prior_jacobian_policy(family::Symbol,
        scope::Symbol;
        public_fit::Bool = false,
        experimental_public::Bool = public_fit)
    return (;
        schema = "bayesianmgmfrm.generalized_raw_prior_jacobian_policy.v1",
        family,
        scope,
        status = :policy_recorded,
        density_space = :raw_unconstrained,
        prior_policy = :independent_normal_raw_coordinates,
        direct_scale_priors = false,
        direct_prior_policy = :not_enabled_raw_coordinate_priors_only,
        jacobian_policy = :none_raw_coordinate_density,
        direct_parameter_summaries = :deterministic_transforms_of_raw_draws,
        public_fit,
        experimental_public,
        notes = [
            :no_log_jacobian_for_raw_coordinate_density,
            :direct_scale_priors_require_future_jacobian_policy,
            :direct_parameters_are_interpretable_transforms_not_prior_scales,
        ],
    )
end
