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
            executable = true,
            note = :current_guarded_default,
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
            executable = false,
            note = :requires_public_generalized_prior_constructor,
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
            executable = false,
            note = :requires_public_generalized_prior_constructor,
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
        :public_generalized_prior_variants,
        :fresh_seed_attempt_complete_evaluation_runner,
        :prediction_and_decision_stability_scorers,
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
            sparse_raters_per_person = 2,
            source_sample_size_candidates = (;
                persons = (50, 100),
                items = (5, 15),
                raters = (5, 15),
            ),
            final_sample_size_cells = :pending_runtime_only_resource_probe,
            evaluation_replications = :pending_coverage_precision_review,
            anchor_proportion_axis = :excluded_until_anchor_fit_contract_exists,
        ),
        priors = (;
            parameter_space = :raw_unconstrained_coordinates,
            jacobian_policy = :none_raw_coordinate_density,
            prior_predictive_required_before_refits = true,
            regimes = _mgmfrm_validation_prior_regimes(),
            importance_reweighting_is_final_evidence = false,
            actual_refits_required = true,
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
        ),
        readiness = (;
            stage_a_complete = false,
            blockers,
            n_blockers = length(blockers),
            next_work_order = blockers,
            next_gate = :implement_blockers_then_freeze_before_fresh_evaluation,
        ),
        claim_scope = :planning_contract_not_validation_evidence,
    )
end
