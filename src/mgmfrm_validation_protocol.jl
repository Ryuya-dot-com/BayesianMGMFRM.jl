function _mgmfrm_validation_source_anchor()
    return (;
        source = :uto_2021,
        doi = "10.1007/s41237-021-00144-w",
        url = "https://link.springer.com/article/10.1007/s41237-021-00144-w",
        equation = 6,
        source_scale_constant = 1.7,
        normal_ogive_minimax_reference_constant = 1.702,
        category_count = 4,
        parameter_recovery_axes = (;
            persons = (50, 100),
            items = (5, 15),
            raters = (5, 15),
            dimensions = (1, 2, 3),
            replications = 30,
        ),
        source_prior = (;
            parameter_space = :declared_parameter_and_log_parameter_blocks,
            family = :normal,
            location = 0.0,
            scale = 1.0,
            blocks = (
                :person_ability,
                :log_item_dimension_discrimination,
                :log_rater_consistency,
                :item_difficulty,
                :rater_severity,
                :item_steps,
            ),
        ),
        estimator = :nuts_via_rstan,
        retained_periods = 2000:4000,
        sparse_design_anchor = (;
            design = :systematic_link,
            raters_per_person = 2,
        ),
        overlap_with_package = :partial_not_exact,
        nonoverlap = (
            :source_unrestricted_item_dimension_loading_surface,
            :package_fixed_q_loading_mask,
            :source_dimension_relabeling_after_fit,
            :package_dimension_labels_fixed_by_q,
        ),
        interpretation = :source_design_anchor_not_package_validation_result,
    )
end

function _mgmfrm_validation_prior_regimes()
    return (
        (;
            regime = :implementation_reference,
            role = :primary,
            scales = (;
                person_sd = 1.0,
                rater_sd = 1.0,
                item_sd = 1.0,
                log_discrimination_sd = 0.5,
                log_consistency_sd = 0.5,
                step_sd = 1.0,
            ),
            fit_executable = true,
            prior_predictive_executable = true,
            executable = true,
            note = :typed_refit_and_prior_predictive_available,
        ),
        (;
            regime = :source_aligned,
            role = :sensitivity,
            scales = (;
                person_sd = 1.0,
                rater_sd = 1.0,
                item_sd = 1.0,
                log_discrimination_sd = 1.0,
                log_consistency_sd = 1.0,
                step_sd = 1.0,
            ),
            fit_executable = true,
            prior_predictive_executable = true,
            executable = true,
            note = :typed_refit_and_prior_predictive_available,
        ),
        (;
            regime = :strong_regularizing,
            role = :sensitivity,
            scales = (;
                person_sd = 1.0,
                rater_sd = 0.5,
                item_sd = 0.5,
                log_discrimination_sd = 0.25,
                log_consistency_sd = 0.25,
                step_sd = 0.5,
            ),
            fit_executable = true,
            prior_predictive_executable = true,
            executable = true,
            note = :typed_refit_and_prior_predictive_available,
        ),
    )
end

function _mgmfrm_validation_estimands()
    return (
        (block = :item_difficulty, priority = :primary,
            scale = :direct_identified, summaries = (:bias, :mae, :rmse,
                :coverage, :interval_width)),
        (block = :rater_severity, priority = :primary,
            scale = :direct_sum_to_zero, summaries = (:bias, :mae, :rmse,
                :coverage, :interval_width)),
        (block = :item_dimension_discrimination, priority = :primary,
            scale = :direct_positive_q_active, summaries = (:bias, :mae,
                :rmse, :coverage, :interval_width)),
        (block = :rater_consistency, priority = :primary,
            scale = :direct_positive_geometric_mean_one,
            summaries = (:bias, :mae, :rmse, :coverage, :interval_width)),
        (block = :item_steps, priority = :primary,
            scale = :direct_constrained_within_item,
            summaries = (:bias, :mae, :rmse, :coverage, :interval_width)),
        (block = :person_ability, priority = :secondary,
            scale = :direct_standard_normal_by_dimension,
            summaries = (:bias, :rmse, :coverage, :truth_correlation)),
        (block = :prediction, priority = :primary,
            scale = :observed_category_and_expected_score,
            summaries = (:category_probability_error,
                :expected_score_error, :calibration, :heldout_log_score)),
    )
end

"""
    mgmfrm_validation_protocol()

Return the machine-readable Stage-A draft for scientific validation of the
narrow fixed-Q confirmatory MGMFRM branch.

The protocol separates decisions already fixed by the implemented likelihood
from execution and decision components that remain blocked. It does not run a
simulation, fit a model, authorize a stable claim, or treat earlier pilots as
evaluation evidence. `status == :stage_a_draft_execution_blocked` remains in
force until every item in `readiness.blockers` has an executable contract and
independent review.
"""
function mgmfrm_validation_protocol()
    blockers = (
        :fresh_seed_attempt_complete_evaluation_runner,
        :independent_scientific_threshold_review,
    )
    return (;
        schema = "bayesianmgmfrm.mgmfrm_validation_protocol.v1",
        object = :mgmfrm_validation_protocol,
        status = :stage_a_draft_execution_blocked,
        protocol_frozen = false,
        evaluation_started = false,
        claim_target = (;
            family = :mgmfrm,
            primary_branch = :mgmfrm_fixed_q_between_item_gpcm,
            dimensions = 2,
            q_policy = :fixed_confirmatory_with_pure_items_per_dimension,
            loading_sign = :positive,
            latent_correlation = :identity_fixed,
            source_scale_constant = 1.7,
            normal_ogive_minimax_reference_constant = 1.702,
            scale_policy = :source_literal_primary_reference_constant_metadata,
            promotion_domain = :between_item_only,
            boundary_evidence = (:within_item_fixed_cross_loading,
                :mixed_between_and_within_item),
            excluded = (
                :unrestricted_loadings,
                :exploratory_q,
                :free_latent_correlation,
                :nonadditive_dimension_aggregation,
                :fitted_dff_testlet_halo_or_rater_task_effects,
                :arbitrary_facet_specific_steps,
            ),
        ),
        source_anchor = _mgmfrm_validation_source_anchor(),
        identification = (;
            likelihood_structure = (
                :fixed_q,
                :positive_active_loadings,
                :fixed_dimension_labels,
                :sum_to_zero_rater_severity,
                :geometric_mean_one_rater_consistency,
                :constrained_item_steps,
            ),
            prior_supplied_location_scale = (;
                person_ability = :standard_normal_by_dimension,
                latent_correlation = :identity_fixed,
            ),
            likelihood_only_identification_claim = false,
            source_dimension_sorting_required = false,
            reason = :fixed_q_labels_dimensions_before_fitting,
        ),
        estimands = _mgmfrm_validation_estimands(),
        estimand_policy = (;
            primary_inference_units = (:identified_parameter_block,
                :heldout_response),
            direct_parameter_recovery_requires = (;
                same_q = true,
                same_identification_constraints = true,
                same_scale_constant = true,
            ),
            cross_scale_comparison_space = (
                :linear_predictor,
                :category_probability,
                :expected_score,
                :heldout_log_score,
            ),
            person_ability_role = :secondary_no_hard_individual_recovery_gate,
            extreme_person_rule =
                :report_separately_and_assess_prior_sensitivity,
            raw_parameter_pooling_across_incompatible_scales = false,
        ),
        scale_harmonization = (;
            primary = (;
                constant = 1.7,
                role = :source_literal_uto_2021_equation_6,
                implementation = :julia_and_cmdstan,
            ),
            normal_ogive_reference = (;
                constant = 1.702,
                role = :named_numerical_reference_not_source_correction,
                likelihood_refit_status = :not_currently_executable,
                required_for_primary_promotion = false,
                required_before_scale_robustness_claim = true,
            ),
            scalar_mfrm_reference = (;
                constant = 1.0,
                direct_discrimination_comparison_allowed = false,
            ),
            harmonized_targets = (
                :linear_predictor,
                :category_probability,
                :expected_score,
                :heldout_log_score,
            ),
            rule = :do_not_compare_raw_discriminations_without_scale_conversion,
        ),
        intervals = (;
            primary = (probability = 0.90, kind = :equal_tailed),
            secondary = ((probability = 0.95, kind = :equal_tailed),),
            descriptive_only = ((probability = 0.66,
                kind = :equal_tailed),),
            hdi_role = :secondary_sensitivity_not_primary_coverage,
            reason = :hdi_not_invariant_under_nonlinear_reexpression,
        ),
        design_domain = (;
            required_axes = (
                :dense_fully_crossed,
                :connected_sparse_systematic_link,
                :between_item_fixed_q,
                :mixed_fixed_q_boundary,
                :q_misspecification,
                :unidimensional_response_overlap,
            ),
            categories = 4,
            q_scope = (;
                primary = :pure_between_item_one_active_dimension_per_item,
                boundary = (:fixed_within_item_cross_loading,
                    :fixed_mixed_between_and_within_item),
                misspecification = (:omit_true_active_dimension,
                    :add_false_active_dimension),
                q_known_in_simulation = true,
                exploratory_q_estimation = false,
                pure_item_structural_floor =
                    :at_least_one_pure_item_per_dimension,
                floor_is_scientific_recovery_threshold = false,
            ),
            sparse_raters_per_person = 2,
            sparse_design = (;
                primary = :connected_systematic_link,
                raters_per_person = 2,
                connectivity_and_location_rank_must_pass_before_fit = true,
                disconnected_negative_control = :must_be_rejected_before_fit,
                arbitrary_missingness_assumed_ignorable = false,
                additional_missingness_mechanism = :not_in_primary_scope,
                report = (:graph_components, :location_rank,
                    :rater_overlap, :category_support),
            ),
            response_pattern_stress = (;
                role = :five_category_sensitivity_not_source_grid_replacement,
                category_levels = (1, 2, 3, 4, 5),
                scenarios = (
                    :regular_all_categories,
                    :unused_interior_category_3,
                    :all_maximum_person,
                    :all_minimum_rater,
                    :combined_unused_category_and_boundary_patterns,
                ),
                combined_pattern_design =
                    :connected_sparse_with_nonintersecting_target_person_and_rater,
                dense_combined_pattern_excluded = true,
                dense_exclusion_reason =
                    :all_maximum_person_and_all_minimum_rater_conflict_in_their_shared_cells,
                missing_category_is_missing_response = false,
                sampler_free_preflight = :ordinal_response_pattern_audit,
                plan_function = :mgmfrm_response_stress_plan,
                generator_function = :simulate_mgmfrm_response_stress,
                attempt_preflight_function =
                    :mgmfrm_response_stress_preflight,
                fit_attempt_function =
                    :mgmfrm_response_stress_fit_attempts,
                fit_attempt_profile = :wiring_smoke_only,
                fit_attempt_default_resource_bound = 1,
                fit_attempt_terminal_statuses = (
                    :generation_failed,
                    :pre_fit_rejected,
                    :fit_failed,
                    :diagnostic_failed,
                    :completed,
                ),
                analysis_profile =
                    :draft_contract_implemented_execution_blocked,
                analysis_contract_function =
                    :mgmfrm_validation_analysis_contract,
                global_single_category_action = :reject_before_fit,
                local_boundary_pattern_action =
                    :fit_with_proper_priors_report_separately_and_refit_prior_regimes,
                no_automatic_scientific_failure_from_pattern_alone = true,
                generation_status = :sampler_free_generator_implemented,
                preflight_status =
                    :attempt_denominator_and_typed_generation_failures_implemented,
                fit_and_diagnostic_attempt_status =
                    :bounded_wiring_smoke_implemented_without_convergence_or_scientific_scoring,
                repeated_fit_evidence = :not_run,
            ),
            source_sample_size_candidates = (;
                persons = (50, 100),
                items = (5, 15),
                raters = (5, 15),
            ),
            final_sample_size_cells =
                :pending_bounded_short_nuts_and_resource_review,
            evaluation_replications = :pending_coverage_precision_review,
            anchor_proportion_axis = :excluded_until_anchor_fit_contract_exists,
        ),
        priors = (;
            parameter_space = :raw_unconstrained_coordinates,
            jacobian_policy = :none_raw_coordinate_density,
            constructor =
                "BayesianMGMFRM.Experimental.GeneralizedPrior",
            prior_predictive_required_before_refits = true,
            regimes = _mgmfrm_validation_prior_regimes(),
            importance_reweighting_is_final_evidence = false,
            actual_refits_required = true,
            sensitivity_contract = (;
                full_primary_grid_regime = :implementation_reference,
                all_regime_refit_scope =
                    :predeclared_stratified_subset_not_full_cartesian,
                required_design_strata = (:dense_fully_crossed,
                    :connected_sparse_systematic_link),
                required_response_strata = (:regular_all_categories,
                    :unused_interior_category_3, :all_maximum_person,
                    :all_minimum_rater),
                required_prior_regimes = (:implementation_reference,
                    :source_aligned, :strong_regularizing),
                outputs = (:prior_predictive_category_use,
                    :posterior_prior_overlap, :parameter_recovery,
                    :predictive_recovery, :decision_stability),
                importance_reweighting_only = :screening_not_final_evidence,
                select_regime_from_pilot_results = false,
            ),
        ),
        sampler = (;
            algorithm = :nuts,
            chains = 4,
            warmup_per_chain = 1000,
            retained_per_chain = 1000,
            thinning = 1,
            target_accept = 0.90,
            max_depth = 12,
            metric = :diagonal,
            pilot_role = :runtime_and_operability_only,
            evaluation_profile_mutable_after_results = false,
        ),
        backends = (;
            primary = :advancedhmc,
            reference = :cmdstan,
            cmdstan_scope = :predeclared_stratified_conformance_subset,
            same_data_truth_prior_and_estimand_required = true,
            speed_ranking_allowed = false,
            feature_parity_required = false,
            comparison_targets = (:log_density, :gradient,
                :identified_parameter_summary, :category_probability,
                :sampler_diagnostics, :terminal_status),
            reference_subset = (;
                required_design_strata = (:dense_fully_crossed,
                    :connected_sparse_systematic_link),
                required_response_strata = (:regular_all_categories,
                    :unused_interior_category_3, :all_maximum_person,
                    :all_minimum_rater),
                required_prior_strata = (:implementation_reference,
                    :source_aligned),
                selection =
                    :five_predeclared_paired_stratum_cells_not_full_cartesian,
                paired_stratum_cells = (
                    (id = :backend_01, design = :dense_fully_crossed,
                        q = :between_item, response = :regular_all_categories,
                        prior = :implementation_reference),
                    (id = :backend_02,
                        design = :connected_sparse_systematic_link,
                        q = :between_item,
                        response = :regular_all_categories,
                        prior = :source_aligned),
                    (id = :backend_03, design = :dense_fully_crossed,
                        q = :between_item,
                        response = :unused_interior_category_3,
                        prior = :source_aligned),
                    (id = :backend_04,
                        design = :connected_sparse_systematic_link,
                        q = :between_item,
                        response = :all_maximum_person,
                        prior = :implementation_reference),
                    (id = :backend_05,
                        design = :connected_sparse_systematic_link,
                        q = :mixed_fixed_boundary,
                        response = :all_minimum_rater,
                        prior = :source_aligned),
                ),
            ),
            disagreement_action =
                :investigate_parameterization_or_implementation_before_scientific_scoring,
        ),
        execution_design = (;
            function_name =
                :mgmfrm_validation_execution_design_contract,
            status =
                :heldout_retry_and_stratified_sensitivity_choices_frozen,
            primary_heldout_target =
                :conditional_existing_level_heldout_response,
            primary_heldout_folds = 5,
            retry_primary_outcome_overwritable = false,
            n_exact_sensitivity_role_cells = 24,
            role_cells_are_fit_attempt_count = false,
            resource_probe_function =
                :mgmfrm_validation_resource_probe,
            initial_gradient_resource_probe =
                :implemented_optional_measurement_not_validation_evidence,
            bounded_short_nuts_resource_probe = :pending,
            repository_or_sha_identity_required = false,
        ),
        seeds = (;
            evaluation_seed_family = :fresh_not_used_by_prior_pilots,
            deterministic_by = (:scenario, :replication, :model, :chain),
            reuse_across_backends_for_paired_cells = true,
            tune_rules_after_seeded_results = false,
        ),
        failure_accounting = (;
            denominator = :all_predeclared_attempts,
            successful_fits_only_summary_allowed = false,
            typed_terminal_status_required = true,
            original_error_preserved = true,
            retry_policy_must_be_predeclared = true,
        ),
        scoring = (;
            predictive_recovery = (;
                function_name = :mgmfrm_predictive_recovery_score,
                targets = (
                    :category_probability_error,
                    :expected_score_error,
                    :proper_log_score_regret,
                ),
                known_truth_required = true,
                thresholds_applied = false,
            ),
            decision_stability = (;
                function_name = :mgmfrm_decision_stability_score,
                targets = (
                    :absolute_shift,
                    :pairwise_order_disagreement,
                    :classification_flip,
                ),
                caller_supplied_cutpoints = true,
                thresholds_applied = false,
            ),
        ),
        computation_gate = (;
            max_rank_normalized_rhat = 1.01,
            min_bulk_ess = 400.0,
            min_tail_ess = 400.0,
            max_divergences = 0,
            max_treedepth_hits = 0,
            complete_chain_ebfmi_required = true,
            failed_gate_counts_as_failed_attempt = true,
        ),
        scientific_decision = (;
            thresholds_frozen = false,
            pilot_values_may_define_thresholds = false,
            primary_recovery_and_prediction_rules = :pending_independent_review,
            any_missing_required_cell_blocks_promotion = true,
            failure_action = :narrow_claim_or_supported_design_domain,
            complexity_increase_is_automatic = false,
            criterion_layers = (;
                structural = :prefit_pass_or_reject_without_sampling,
                computational = :all_attempt_diagnostics_gate,
                scientific = :independently_frozen_recovery_prediction_and_decision_rules,
                robustness = :prior_sparse_q_and_response_pattern_strata_reported_separately,
            ),
            averaging_cannot_hide_failed_stress_stratum = true,
            backend_agreement_is_necessary_not_sufficient = true,
            stress_pattern_presence_is_automatic_failure = false,
        ),
        readiness = (;
            stage_a_complete = false,
            blockers,
            n_blockers = length(blockers),
            completed_enablers = (;
                response_stress_plan = :implemented,
                response_stress_generator = :implemented,
                attempt_complete_sampler_free_preflight = :implemented,
                bounded_fit_and_diagnostic_wiring_smoke = :implemented,
                fit_and_diagnostic_attempt_phases =
                    :wiring_smoke_implemented_analysis_pending,
                attempt_complete_analysis_contract =
                    :implemented_execution_blocked,
                heldout_retry_and_sensitivity_design =
                    :frozen_before_evaluation,
                initial_gradient_resource_probe_surface =
                    :implemented_measurement_optional,
                attempt_complete_analysis_profile =
                    :draft_contract_implemented_execution_blocked,
            ),
            next_work_order = blockers,
            next_gate = :implement_blockers_then_freeze_before_fresh_evaluation,
        ),
        claim_scope = :planning_contract_not_validation_evidence,
    )
end
