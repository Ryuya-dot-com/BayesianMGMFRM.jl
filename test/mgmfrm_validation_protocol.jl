using Test
using BayesianMGMFRM

@testset "Stage-A MGMFRM validation protocol" begin
    protocol = mgmfrm_validation_protocol()
    @test protocol.schema ==
        "bayesianmgmfrm.mgmfrm_validation_protocol.v1"
    @test protocol.status === :stage_a_draft_execution_blocked
    @test !protocol.protocol_frozen
    @test !protocol.evaluation_started
    @test protocol.claim_scope === :planning_contract_not_validation_evidence

    target = protocol.claim_target
    @test target.primary_branch === :mgmfrm_fixed_q_between_item_gpcm
    @test target.dimensions == 2
    @test target.q_policy ===
        :fixed_confirmatory_with_pure_items_per_dimension
    @test target.latent_correlation === :identity_fixed
    @test target.source_scale_constant == 1.7
    @test target.normal_ogive_minimax_reference_constant == 1.702
    @test target.promotion_domain === :between_item_only
    @test :mixed_between_and_within_item in target.boundary_evidence
    @test :free_latent_correlation in target.excluded
    @test :fitted_dff_testlet_halo_or_rater_task_effects in target.excluded

    source = protocol.source_anchor
    @test source.source === :uto_2021
    @test source.equation == 6
    @test source.parameter_recovery_axes.persons == (50, 100)
    @test source.parameter_recovery_axes.items == (5, 15)
    @test source.parameter_recovery_axes.raters == (5, 15)
    @test source.parameter_recovery_axes.dimensions == (1, 2, 3)
    @test source.parameter_recovery_axes.replications == 30
    @test source.category_count == 4
    @test source.sparse_design_anchor.raters_per_person == 2
    @test source.overlap_with_package === :partial_not_exact
    @test :source_unrestricted_item_dimension_loading_surface in
        source.nonoverlap

    identification = protocol.identification
    @test !identification.likelihood_only_identification_claim
    @test identification.prior_supplied_location_scale.person_ability ===
        :standard_normal_by_dimension
    @test !identification.source_dimension_sorting_required

    primary_blocks = Set(row.block for row in protocol.estimands
        if row.priority === :primary)
    @test primary_blocks == Set((
        :item_difficulty,
        :rater_severity,
        :item_dimension_discrimination,
        :rater_consistency,
        :item_steps,
        :prediction,
    ))
    @test protocol.intervals.primary ==
        (probability = 0.90, kind = :equal_tailed)
    @test protocol.intervals.hdi_role ===
        :secondary_sensitivity_not_primary_coverage

    design = protocol.design_domain
    @test :dense_fully_crossed in design.required_axes
    @test :connected_sparse_systematic_link in design.required_axes
    @test :q_misspecification in design.required_axes
    @test design.categories == 4
    @test design.sparse_raters_per_person == 2
    @test design.anchor_proportion_axis ===
        :excluded_until_anchor_fit_contract_exists

    regimes = protocol.priors.regimes
    @test Tuple(row.regime for row in regimes) == (
        :implementation_reference,
        :source_aligned,
        :strong_regularizing,
    )
    @test all(row.fit_executable for row in regimes)
    @test all(!row.prior_predictive_executable for row in regimes)
    @test all(!row.executable for row in regimes)
    @test only(row for row in regimes
        if row.regime === :implementation_reference).
            scales.log_discrimination_sd == 0.5
    @test only(row for row in regimes
        if row.regime === :source_aligned).
            scales.log_discrimination_sd == 1.0
    @test protocol.priors.actual_refits_required
    @test !protocol.priors.importance_reweighting_is_final_evidence

    @test protocol.sampler.chains == 4
    @test protocol.sampler.warmup_per_chain == 1000
    @test protocol.sampler.retained_per_chain == 1000
    @test protocol.sampler.thinning == 1
    @test protocol.sampler.target_accept == 0.90
    @test protocol.backends.primary === :advancedhmc
    @test protocol.backends.reference === :cmdstan
    @test !protocol.backends.speed_ranking_allowed

    @test protocol.failure_accounting.denominator ===
        :all_predeclared_attempts
    @test !protocol.failure_accounting.successful_fits_only_summary_allowed
    @test protocol.failure_accounting.typed_terminal_status_required
    @test protocol.computation_gate.max_rank_normalized_rhat == 1.01
    @test protocol.computation_gate.min_bulk_ess == 400.0
    @test protocol.computation_gate.max_divergences == 0

    @test !protocol.scientific_decision.thresholds_frozen
    @test !protocol.scientific_decision.pilot_values_may_define_thresholds
    @test !protocol.scientific_decision.complexity_increase_is_automatic
    @test !protocol.readiness.stage_a_complete
    @test protocol.readiness.n_blockers == 4
    @test Set(protocol.readiness.blockers) == Set((
        :generalized_prior_predictive_execution,
        :fresh_seed_attempt_complete_evaluation_runner,
        :prediction_and_decision_stability_scorers,
        :independent_scientific_threshold_review,
    ))
end
