@testset "local-dependence estimand contract" begin
    contract = local_dependence_contract()
    @test contract.schema ==
        "bayesianmgmfrm.local_dependence_contract.v1"
    @test contract.status === :calibration_pending
    @test contract.frozen_profile
    @test !contract.decision_labels_available
    @test !contract.mechanism_interpretation_eligible

    single = contract.pair_families.single_rating_item_q3
    @test single.common_unit_key == (:response_id,)
    @test single.uniqueness_key == (:response_id, :item)
    @test single.applicability ===
        :one_rater_per_response_and_one_rating_per_response_item
    @test single.multiple_rater_action === :not_applicable
    @test single.criterion_split_action === :not_applicable
    @test single.applicability_scope == (:testlet_id,)
    @test single.inapplicable_action ===
        :skip_inapplicable_testlet_strata_and_report
    @test single.estimation_strata == (:testlet_id,)

    within_rater = contract.pair_families.within_rater_item_q3
    @test within_rater.common_unit_key == (:response_id, :rater)
    @test within_rater.uniqueness_key ==
        (:response_id, :rater, :item)
    @test within_rater.repeated_response_rule ===
        :distinct_response_id_per_occasion

    rater_pair = contract.pair_families.rater_on_shared_response_criterion
    @test rater_pair.common_unit_key == (:response_id, :item)
    @test rater_pair.uniqueness_key ==
        (:response_id, :item, :rater)
    @test rater_pair.common_response_count_reporting === :required
    @test rater_pair.single_response_concentration_action ===
        :report_and_block_mechanism_interpretation
    @test contract.pair_families.aggregated_person_testlet_item_q3.status ===
        :not_available
    @test !contract.pair_families.aggregated_person_testlet_item_q3.implicit_aggregation
    @test contract.pair_families.cross_rater_cross_item_residual_pair.status ===
        :not_available
    @test !contract.pair_families.cross_rater_cross_item_residual_pair.implicit_pairing

    @test contract.matching.duplicate_policy === :error
    @test contract.matching.duplicate_policy_scope ===
        :applicable_family_only
    @test contract.matching.evaluation_order[1:2] ==
        (:family_applicability, :family_uniqueness)
    @test contract.matching.aggregation === :none
    @test contract.matching.posterior_draw_policy ===
        :distinct_without_replacement
    @test contract.matching.duplicate_draw_indices_action === :error
    @test contract.matching.support_by_draw ===
        :count_pairwise_complete_valid_common_units
    @test contract.matching.pairwise_validity ===
        :left_and_right_valid_on_same_draw
    @test contract.matching.common_unit_weighting === :equal
    @test contract.matching.draw_weighting === :equal
    @test contract.matching.min_common_units == 20
    @test contract.matching.min_eligible_draws == 100
    @test contract.matching.min_eligible_draw_fraction == 0.9
    @test contract.pair_statistic.statistic === :pearson_correlation
    @test contract.pair_statistic.undefined_action ===
        :exclude_draw_and_report_reason

    @test contract.adjusted_q3.centering ===
        :equal_weight_mean_of_eligible_item_pairs_within_family_testlet_and_draw
    @test contract.adjusted_q3.centering_scope ==
        (:pair_family, :testlet_id, :draw)
    @test contract.adjusted_q3.minimum_pairs_for_centering == 2
    @test contract.adjusted_q3.centering_pair_sets ===
        :side_specific_overall_supported_pairs
    pair_evidence = contract.multiplicity.pair_evidence
    @test pair_evidence.tail === :two_sided_absolute
    @test pair_evidence.finite_sample_correction ===
        :add_one_to_numerator_and_denominator
    @test pair_evidence.minimum_paired_draws == 100
    @test pair_evidence.replicated_datasets_per_parameter_draw == 1
    @test pair_evidence.tail_fraction_mcse ===
        :iid_plugin_bernoulli_reference_standard_error
    @test pair_evidence.monte_carlo_reporting ==
        (:n_eligible_paired_draws, :tail_fraction_mcse)
    @test contract.multiplicity.localization.scope ===
        :within_each_enabled_pair_family
    @test contract.multiplicity.localization.decision_status ===
        :specified_but_disabled_until_calibrated
    global_decision = contract.multiplicity.dataset_decision
    @test global_decision.scope ===
        :all_enabled_families_and_eligible_pairs
    @test global_decision.statistic ===
        :maximum_absolute_raw_pair_correlation
    @test global_decision.pair_set ===
        :overall_supported_observed_replicated_intersection_by_draw
    @test global_decision.minimum_paired_draws == 100
    @test global_decision.minimum_paired_draw_fraction == 0.9
    @test global_decision.decision_status ===
        :specified_but_disabled_until_calibrated
    @test !contract.predictive_checks.marginal_whole_cluster.row_level_loo_is_sufficient

    @test_throws ArgumentError local_dependence_contract(
        min_common_units = 10,
    )
    custom = local_dependence_contract(
        profile = :custom_unvalidated,
        min_common_units = 10,
        min_eligible_draws = 40,
        min_eligible_draw_fraction = 0.8,
        pair_fdr_alpha = 0.1,
        global_fwer_alpha = 0.1,
        variance_tolerance = 0.0,
        correlation_variance_tolerance = 1e-10,
    )
    @test !custom.frozen_profile
    @test custom.thresholds.min_common_units == 10
    @test custom.thresholds.min_eligible_draws == 40
    @test custom.thresholds.min_eligible_draw_fraction == 0.8
    @test custom.thresholds.pair_fdr_alpha == 0.1
    @test custom.thresholds.global_fwer_alpha == 0.1
    @test custom.thresholds.variance_tolerance == 0.0
    @test custom.thresholds.correlation_variance_tolerance == 1e-10

    @test_throws ArgumentError local_dependence_contract(
        profile = :unknown,
    )
    @test_throws ArgumentError local_dependence_contract(
        profile = :custom_unvalidated,
        min_eligible_draws = 0,
    )
    @test_throws ArgumentError local_dependence_contract(
        profile = :custom_unvalidated,
        min_eligible_draw_fraction = 0.0,
    )
    @test_throws ArgumentError local_dependence_contract(
        profile = :custom_unvalidated,
        correlation_variance_tolerance = -1.0,
    )
end
