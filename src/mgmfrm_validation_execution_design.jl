# Frozen design-only choices used by the blocked MGMFRM analysis profile.

function _mgmfrm_analysis_heldout_design()
    return (;
        target = :conditional_existing_level_heldout_response,
        interpretation =
            :new_rating_for_person_item_and_rater_levels_present_in_training,
        primary_metric = :heldout_log_score,
        secondary_known_truth_metrics = (
            :category_probability_error,
            :expected_score_error,
            :calibration,
        ),
        plan_function = :kfold_plan,
        preflight_function = :kfold_plan_diagnostics,
        refit_function = :kfold_refit,
        k = 5,
        heldout_unit = :observation,
        group_by = nothing,
        shuffle = true,
        fold_assignment = :seeded_balanced_before_any_fit,
        split_seed_namespace = :heldout_fold_assignment,
        nominal_training_fraction = 0.80,
        required_training_support =
            (:person, :rater, :item, :category, :declared_optional_facets),
        preflight_facets = :all,
        failed_preflight_status = :pre_fit_rejected,
        same_folds_required_across =
            (:models, :backends, :prior_regimes),
        q_selection_uses_heldout_responses = false,
        prior_selection_uses_heldout_responses = false,
        scientific_threshold_selection_uses_heldout_responses = false,
        same_data_waic_or_loo_role = :diagnostic_only,
        unsupported_targets = (
            :new_person_generalization,
            :new_item_generalization,
            :new_rater_generalization,
        ),
        unsupported_reason =
            :new_level_marginalization_or_hierarchical_pooling_not_implemented,
        execution_status = :public_plan_preflight_and_refit_path_available,
    )
end

function _mgmfrm_analysis_retry_design()
    return (;
        automatic_retry_allowed = false,
        primary_attempt = 1,
        primary_outcome_overwritable = false,
        primary_denominator_changed_by_remediation = false,
        remediation_role = :separate_nonpromotional_record,
        maximum_sampler_remediations_per_primary_attempt = 1,
        sampler_remediation_eligible_conditions = (
            :fit_failed,
            :completed_computational_gate_failed,
        ),
        sampler_remediation_controls = (;
            chains = 4,
            warmup_per_chain = 1000,
            retained_per_chain = 1000,
            thinning = 1,
            target_accept = 0.95,
            max_depth = 14,
            metric = :diagonal,
            unchanged = (:data, :folds, :model, :q, :prior),
            seed = :new_deterministic_remediation_namespace,
        ),
        maximum_postprocessing_recomputations_per_primary_attempt = 1,
        postprocessing_recomputation_eligible_statuses =
            (:diagnostic_failed, :scoring_failed),
        postprocessing_reuses_retained_fit = true,
        ineligible_conditions = (
            :generation_failed,
            :pre_fit_rejected,
            :scientific_gate_failed,
        ),
        original_error_preserved = true,
        all_changes_recorded = true,
        remediation_can_rescue_primary_scientific_result = false,
    )
end

function _mgmfrm_prior_response_cell(cell_id::Symbol, design::Symbol,
        response_pattern::Symbol, prior_regime::Symbol)
    return (;
        cell_id,
        axis = :prior_response,
        design,
        response_pattern,
        prior_regime,
        q_structure = :pure_between_item_two_dimensions,
        backend = :advancedhmc,
        sample_size_binding = :response_stress_fixture_dimensions,
        execution_status = :existing_generator_and_fit_path,
        claim_role = :robustness_only,
    )
end

function _mgmfrm_prior_response_sensitivity_cells()
    return (
        _mgmfrm_prior_response_cell(:prior_response_01,
            :dense_fully_crossed, :regular_all_categories, :source_aligned),
        _mgmfrm_prior_response_cell(:prior_response_02,
            :connected_sparse_systematic_link, :regular_all_categories,
            :strong_regularizing),
        _mgmfrm_prior_response_cell(:prior_response_03,
            :dense_fully_crossed, :unused_interior_category_3,
            :strong_regularizing),
        _mgmfrm_prior_response_cell(:prior_response_04,
            :connected_sparse_systematic_link, :unused_interior_category_3,
            :source_aligned),
        _mgmfrm_prior_response_cell(:prior_response_05,
            :dense_fully_crossed, :all_maximum_person, :source_aligned),
        _mgmfrm_prior_response_cell(:prior_response_06,
            :connected_sparse_systematic_link, :all_maximum_person,
            :strong_regularizing),
        _mgmfrm_prior_response_cell(:prior_response_07,
            :dense_fully_crossed, :all_minimum_rater, :strong_regularizing),
        _mgmfrm_prior_response_cell(:prior_response_08,
            :connected_sparse_systematic_link, :all_minimum_rater,
            :source_aligned),
        _mgmfrm_prior_response_cell(:prior_response_09,
            :connected_sparse_systematic_link,
            :combined_unused_category_and_boundary_patterns,
            :source_aligned),
        _mgmfrm_prior_response_cell(:prior_response_10,
            :connected_sparse_systematic_link,
            :combined_unused_category_and_boundary_patterns,
            :strong_regularizing),
    )
end

function _mgmfrm_structure_cell(cell_id::Symbol, axis::Symbol, design::Symbol,
        generating_family::Symbol, generating_q::Symbol, fitted_q::Symbol,
        candidate_models, expected_role::Symbol)
    return (;
        cell_id,
        axis,
        design,
        response_pattern = :regular_all_categories,
        prior_regime = :implementation_reference,
        backend = :advancedhmc,
        generating_family,
        generating_q,
        fitted_q,
        candidate_models,
        expected_role,
        sample_size_binding = :selected_representative_runtime_cell,
        execution_status = :exact_cell_selected_analysis_adapter_pending,
    )
end

function _mgmfrm_structure_comparison_cells()
    pure = :pure_between_balanced_by_dimension
    mixed = :mixed_one_crossloading_with_pure_anchor_per_dimension
    invalid_within = :all_items_crossload_two_dimensions_aliased_columns
    candidates =
        (:mfrm_partial_credit, :mgmfrm_fixed_q_between_item_gpcm)
    return (
        _mgmfrm_structure_cell(:structure_01, :fixed_q_boundary,
            :dense_fully_crossed, :mgmfrm, mixed, mixed,
            (:mgmfrm_fixed_q_within_or_mixed_gpcm,),
            :crossloading_boundary_recovery),
        _mgmfrm_structure_cell(:structure_02, :fixed_q_boundary,
            :connected_sparse_systematic_link, :mgmfrm, mixed, mixed,
            (:mgmfrm_fixed_q_within_or_mixed_gpcm,),
            :sparse_crossloading_boundary_recovery),
        _mgmfrm_structure_cell(:structure_03,
            :structural_negative_control, :dense_fully_crossed, :mgmfrm,
            pure, invalid_within,
            (:mgmfrm_fixed_q_within_or_mixed_gpcm,),
            :must_be_rejected_before_fit),
        _mgmfrm_structure_cell(:structure_04, :q_misspecification,
            :connected_sparse_systematic_link, :mgmfrm, mixed, pure,
            (:mgmfrm_fixed_q_between_item_gpcm,),
            :omit_true_crossloading),
        _mgmfrm_structure_cell(:structure_05, :q_misspecification,
            :dense_fully_crossed, :mgmfrm, pure, mixed,
            (:mgmfrm_fixed_q_within_or_mixed_gpcm,),
            :add_false_crossloading),
        _mgmfrm_structure_cell(:structure_06,
            :unidimensional_baseline_comparison, :dense_fully_crossed,
            :mgmfrm, pure, pure, candidates,
            :multidimensional_signal_comparison),
        _mgmfrm_structure_cell(:structure_07,
            :unidimensional_baseline_comparison,
            :connected_sparse_systematic_link, :mgmfrm, pure, pure,
            candidates, :sparse_multidimensional_signal_comparison),
        _mgmfrm_structure_cell(:structure_08,
            :unidimensional_baseline_comparison, :dense_fully_crossed,
            :mfrm, :not_applicable, pure, candidates,
            :unidimensional_false_positive_control),
        _mgmfrm_structure_cell(:structure_09,
            :unidimensional_baseline_comparison,
            :connected_sparse_systematic_link, :mfrm, :not_applicable,
            pure, candidates, :sparse_unidimensional_false_positive_control),
    )
end

function _mgmfrm_primary_response_cells()
    return Tuple((;
            cell_id = row.attempt_id,
            design = row.design,
            response_pattern = row.response_pattern,
            prior_regime = :implementation_reference,
            backend = :advancedhmc,
            q_structure = row.q_structure,
            execution_status = :existing_generator_and_fit_path,
        ) for row in mgmfrm_response_stress_plan())
end

function _mgmfrm_analysis_sensitivity_design(protocol)
    primary_response_cells = _mgmfrm_primary_response_cells()
    prior_response_cells = _mgmfrm_prior_response_sensitivity_cells()
    structure_comparison_cells = _mgmfrm_structure_comparison_cells()
    backend_conformance_cells =
        protocol.backends.reference_subset.paired_stratum_cells
    n_sensitivity_role_cells = length(prior_response_cells) +
        length(structure_comparison_cells) +
        length(backend_conformance_cells)
    return (;
        primary_response_cells,
        prior_response_cells,
        structure_comparison_cells,
        backend_conformance_cells,
        n_primary_response_cells = length(primary_response_cells),
        n_prior_response_cells = length(prior_response_cells),
        n_structure_comparison_cells = length(structure_comparison_cells),
        n_backend_conformance_cells = length(backend_conformance_cells),
        n_sensitivity_role_cells,
        role_cells_are_not_fit_attempts = true,
        reuse_identical_fits_across_roles = true,
        exact_fit_attempts =
            :pending_sample_size_replication_and_cross_role_deduplication,
        raw_cross_family_discrimination_comparison_allowed = false,
        common_comparison_space = (
            :linear_predictor,
            :category_probability,
            :expected_score,
            :heldout_log_score,
        ),
        scientific_thresholds_applied = false,
    )
end

function _mgmfrm_validation_execution_design_contract(protocol)
    heldout = _mgmfrm_analysis_heldout_design()
    retry = _mgmfrm_analysis_retry_design()
    sensitivity = _mgmfrm_analysis_sensitivity_design(protocol)
    return (;
        schema =
            "bayesianmgmfrm.mgmfrm_validation_execution_design_contract.v1",
        object = :mgmfrm_validation_execution_design_contract,
        status = :design_choices_frozen_execution_not_started,
        design_choices_frozen = true,
        execution_started = false,
        heldout,
        retry,
        sensitivity,
        portability = (;
            repository_path_required = false,
            commit_identity_required = false,
            fixture_hash_required = false,
            artifact_byte_identity_required = false,
            package_api_surface =
                (:kfold_plan, :kfold_plan_diagnostics, :kfold_refit,
                    :mgmfrm_response_stress_plan,
                    :mgmfrm_response_stress_fit_attempts),
            cmdstan_required_only_for_reference_cells = true,
        ),
        scientific_thresholds_frozen = false,
        validation_evidence_available = false,
        claim_scope = :design_contract_not_validation_evidence,
    )
end

"""
    mgmfrm_validation_execution_design_contract()

Return the frozen, non-executing design choices for held-out prediction,
retry/remediation, and stratified MGMFRM sensitivity cells. The contract uses
package APIs and semantic identifiers only; it has no repository path, commit,
or fixture-hash dependency.

The primary held-out target is five-fold observation prediction conditional on
person, item, and rater levels represented in every training fold. New-level
person, item, or rater prediction remains unsupported. Remediation never
overwrites a primary attempt, and the listed sensitivity cells are role cells,
not a workload count. No data are generated and no model is fitted.
"""
function mgmfrm_validation_execution_design_contract()
    return _mgmfrm_validation_execution_design_contract(
        mgmfrm_validation_protocol())
end
