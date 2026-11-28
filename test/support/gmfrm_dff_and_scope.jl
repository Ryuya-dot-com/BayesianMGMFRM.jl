function check_gmfrm_dff_estimand_validation_grid_fixture(fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.gmfrm_dff_estimand_validation_grid.v1"
    @test String(fixture[:family]) == "gmfrm"
    @test String(fixture[:scope]) == "dff_estimand_and_validation_grid"
    @test String(fixture[:status]) == "dff_estimand_validation_grid_recorded"
    @test String(fixture[:decision]) == "keep_dff_validation_only"
    @test Bool(fixture[:public_fit]) == false
    @test Bool(fixture[:experimental_public]) == false
    @test Bool(fixture[:fit_ready]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) ==
        "gmfrm_dff_estimand_validation_grid_v1"
    @test String(protocol[:review_kind]) ==
        "local_dff_estimand_and_validation_grid"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test Bool(protocol[:local_only])
    @test String(protocol[:entrypoint_under_review]) ==
        "validate_design(data; bias = terms)"
    @test Int(protocol[:min_cell_count]) == 3
    @test Set(String(facet) for facet in protocol[:supported_validation_facets]) ==
        Set(["person", "rater", "item", "group"])
    @test Bool(thresholds[:require_estimands_predeclared])
    @test Bool(thresholds[:require_reporting_scales_predeclared])
    @test Bool(thresholds[:require_positive_control_passes_without_warnings])
    @test Bool(thresholds[:require_sparse_warning_detected])
    @test Bool(thresholds[:require_empty_and_confounded_warning_detected])
    @test Bool(thresholds[:require_unknown_facet_error_detected])
    @test Bool(thresholds[:require_valid_dff_terms_retained_as_validation_only])
    @test Bool(thresholds[:require_no_public_fit_or_model_effect_promotion])
    @test String(thresholds[:public_exposure_decision]) == "keep_validation_only"

    reviewed = fixture[:reviewed_artifacts]
    @test length(reviewed) == 3
    expected_reviewed = Dict(
        "test/fixtures/gmfrm_guarded_exposure_review.json" =>
            "existence_only_avoids_guarded_review_dff_cycle",
        "test/fixtures/gmfrm_broader_experimental_exposure_decision_review.json" =>
            "existence_only_avoids_broader_review_dff_cycle",
        "test/fixtures/mgmfrm_sparse_recovery_grid.json" => "sha256",
    )
    @test Set(String(row[:artifact]) for row in reviewed) ==
        Set(keys(expected_reviewed))
    for row in reviewed
        artifact = String(row[:artifact])
        @test Bool(row[:exists])
        @test String(row[:hash_policy]) == expected_reviewed[artifact]
        if expected_reviewed[artifact] == "sha256"
            @test String(row[:sha256]) == file_sha256(joinpath(root, artifact))
        else
            @test isnothing(row[:sha256])
        end
    end

    estimands = fixture[:estimand_rows]
    @test length(estimands) == 5
    @test Set(String(row[:estimand]) for row in estimands) == Set([
        "rater_by_group_dff",
        "item_by_group_dff",
        "rater_by_item_interaction",
        "threshold_by_group_dff",
        "discrimination_by_group_dff",
    ])
    @test all(row -> String(row[:primary_scale]) == "logit", estimands)
    @test all(row -> Set(String(scale) for scale in row[:reporting_scales]) ==
        Set(["logit", "expected_score"]), estimands)
    @test count(row -> String(row[:current_status]) == "validation_only",
        estimands) == 3
    @test any(row -> String(row[:estimand]) == "threshold_by_group_dff" &&
        String(row[:current_status]) ==
            "predeclared_not_validated_by_current_bias_api",
        estimands)
    @test any(row -> String(row[:estimand]) == "discrimination_by_group_dff" &&
        String(row[:current_status]) ==
            "predeclared_requires_future_generalized_fit_policy",
        estimands)

    scenarios = fixture[:scenario_rows]
    @test length(scenarios) == 4
    @test Set(String(row[:scenario]) for row in scenarios) == Set([
        "balanced_group_crossed",
        "sparse_rater_group_cells",
        "empty_and_confounded_group_cells",
        "unknown_group_facet_rejected",
    ])
    @test all(row -> Bool(row[:summary][:passed]), scenarios)
    @test all(row -> Bool(row[:summary][:outcome_matches]), scenarios)
    @test all(row -> Bool(row[:summary][:validation_only_ok]), scenarios)

    balanced = only(row for row in scenarios
        if String(row[:scenario]) == "balanced_group_crossed")
    @test Bool(balanced[:validation][:passed])
    @test Int(balanced[:validation][:n_issues]) == 0
    @test String(balanced[:expected_support]) == "screening_supported"
    @test all(row -> String(row[:support]) == "screening_supported",
        balanced[:term_support])
    @test Bool(balanced[:spec_constraints][:spec_constructed])
    @test Bool(balanced[:spec_constraints][:all_dff_terms_validation_only])
    @test Set(String(block) for block in
        balanced[:spec_constraints][:validation_only_blocks]) == Set([
            "dff_item_group",
            "dff_rater_group",
            "dff_rater_item",
        ])

    sparse = only(row for row in scenarios
        if String(row[:scenario]) == "sparse_rater_group_cells")
    sparse_codes = Set(String(row[:code]) for row in sparse[:validation][:issue_counts])
    @test Bool(sparse[:validation][:passed])
    @test sparse_codes == Set(["sparse_dff_cell"])
    @test any(row -> String(row[:support]) == "sparse_screening_only",
        sparse[:term_support])

    empty = only(row for row in scenarios
        if String(row[:scenario]) == "empty_and_confounded_group_cells")
    empty_codes = Set(String(row[:code]) for row in empty[:validation][:issue_counts])
    @test Bool(empty[:validation][:passed])
    @test empty_codes == Set([
        "empty_dff_cell",
        "potential_dff_confounding",
        "sparse_dff_cell",
    ])
    @test any(row -> String(row[:support]) == "not_unpooled_estimable",
        empty[:term_support])

    unknown = only(row for row in scenarios
        if String(row[:scenario]) == "unknown_group_facet_rejected")
    unknown_codes =
        Set(String(row[:code]) for row in unknown[:validation][:issue_counts])
    @test Bool(unknown[:validation][:passed]) == false
    @test unknown_codes == Set(["unknown_bias_facet"])
    @test Bool(unknown[:spec_constraints][:spec_constructed]) == false

    decision = fixture[:decision_record]
    @test String(decision[:selected_decision]) == "keep_validation_only"
    @test Bool(decision[:dff_model_effects_allowed]) == false
    @test Bool(decision[:public_fit_allowed]) == false
    @test Bool(decision[:experimental_keyword_enabled]) == false
    @test String(decision[:public_exposure_support]) ==
        "dff_estimands_predeclared_validation_only"
    @test String(decision[:interpretation]) ==
        "dff_estimand_validation_grid_recorded_keep_model_effects_blocked"
    @test String(decision[:required_followup]) ==
        "manuscript_scale_simulation_grid"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:local_only])
    @test Int(summary[:n_estimands]) == length(estimands)
    @test Int(summary[:n_predeclared_reporting_scales]) == 2
    @test Int(summary[:n_scenarios]) == length(scenarios)
    @test Int(summary[:n_passed_scenarios]) == length(scenarios)
    @test Int(summary[:n_validation_passed_scenarios]) == 3
    @test Int(summary[:n_validation_error_scenarios]) == 1
    @test Int(summary[:n_sparse_warning_scenarios]) >= 1
    @test Int(summary[:n_empty_warning_scenarios]) >= 1
    @test Int(summary[:n_confounding_warning_scenarios]) >= 1
    @test Bool(summary[:all_expected_outcomes_matched])
    @test Bool(summary[:all_valid_dff_terms_retained_as_validation_only])
    @test Bool(summary[:all_estimands_predeclared])
    @test Bool(summary[:all_reporting_scales_predeclared])
    @test Bool(summary[:dff_model_effects_allowed]) == false
    @test Bool(summary[:public_fit_allowed]) == false
    @test Bool(summary[:experimental_keyword_enabled]) == false
    @test Set(String(blocker) for blocker in summary[:remaining_public_blockers]) ==
        Set([
            "manuscript_scale_simulation_grid_missing",
            "full_paper_reproduction_archive_missing",
        ])
    @test String(summary[:recommendation]) ==
        "keep_dff_validation_only_until_gate_e_and_archive_evidence"
    @test String(summary[:next_gate]) == "manuscript_scale_simulation_grid"
end

function check_gmfrm_manuscript_scale_simulation_grid_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.gmfrm_manuscript_scale_simulation_grid.v1"
    @test String(fixture[:family]) == "gmfrm"
    @test String(fixture[:scope]) == "manuscript_scale_simulation_grid"
    @test String(fixture[:status]) ==
        "manuscript_scale_simulation_grid_recorded"
    @test String(fixture[:decision]) ==
        "full_archive_recorded_keep_guarded_scalar_and_confirmatory_mgmfrm_only"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])
    @test Bool(fixture[:broader_public_fit]) == false
    @test Bool(fixture[:manuscript_claims_allowed]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) ==
        "gmfrm_manuscript_scale_simulation_grid_v1"
    @test String(protocol[:review_kind]) ==
        "local_manuscript_scale_simulation_evidence_grid"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test Bool(protocol[:local_only])
    @test String(protocol[:decision_target]) ==
        "gate_e_broader_generalized_claim_evidence"
    @test Bool(thresholds[:require_all_input_artifacts_present])
    @test Bool(thresholds[:require_all_expected_schemas])
    @test Bool(thresholds[:require_all_input_summaries_passed])
    @test Bool(thresholds[:require_scalar_fit_validation_grid_passed])
    @test Bool(thresholds[:require_posterior_predictive_grid_passed])
    @test Bool(thresholds[:require_sparse_pathology_recovery_grid_passed])
    @test Bool(thresholds[:require_prior_likelihood_sensitivity_grid_passed])
    @test Bool(thresholds[:require_real_data_case_study_passed])
    @test Bool(thresholds[:require_claim_archive_recorded])
    @test Bool(thresholds[:require_broader_review_passed])
    @test Bool(thresholds[:require_prediction_target_and_model_weight_policy_passed])
    @test Bool(thresholds[:require_dff_validation_grid_passed])
    @test Bool(thresholds[:require_mgmfrm_sparse_recovery_grid_passed])
    @test Bool(thresholds[
        :require_mgmfrm_empirical_q_matrix_recovery_simulation_grid_passed])
    @test Bool(thresholds[
        :require_mgmfrm_q_candidate_real_fit_diagnostic_linkage_passed])
    @test Bool(thresholds[
        :require_mgmfrm_q_revision_cross_validation_policy_passed])
    @test Bool(thresholds[
        :require_mgmfrm_q_revision_construct_validity_review_passed])
    @test Bool(thresholds[
        :require_mgmfrm_guarded_local_fit_entrypoint_passed])
    @test Bool(thresholds[
        :require_mgmfrm_fit_metric_threshold_sensitivity_passed])
    @test Bool(thresholds[
        :require_mgmfrm_construct_reviewed_q_fit_reporting_policy_passed])
    @test Bool(thresholds[
        :require_mgmfrm_heldout_prediction_validation_policy_passed])
    @test Bool(thresholds[
        :require_mgmfrm_validation_split_model_comparison_policy_passed])
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
    @test Bool(thresholds[
        :require_mgmfrm_publication_grade_refit_pilot_execution_harness_passed])
    @test Bool(thresholds[:require_full_paper_reproduction_archive_passed])
    @test Int(thresholds[:require_minimum_total_evidence_cells]) == 60
    @test Bool(thresholds[:require_no_publication_commands])
    @test Bool(thresholds[:require_full_archive_before_claims]) == false

    input_artifacts = fixture[:input_artifacts]
    expected_paths = Dict(
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
        "prediction_target_and_model_weight_policy" =>
            "test/fixtures/gmfrm_prediction_target_and_model_weight_policy.json",
        "mgmfrm_manual_public_scope_review_for_fit" =>
            "test/fixtures/mgmfrm_manual_public_scope_review_for_fit.json",
        "dff_estimand_validation_grid" =>
            "test/fixtures/gmfrm_dff_estimand_validation_grid.json",
        "mgmfrm_sparse_recovery_grid" =>
            "test/fixtures/mgmfrm_sparse_recovery_grid.json",
        "mgmfrm_empirical_q_matrix_recovery_simulation_grid" =>
            "test/fixtures/mgmfrm_empirical_q_matrix_recovery_simulation_grid.json",
        "mgmfrm_q_candidate_real_fit_diagnostic_linkage" =>
            "test/fixtures/mgmfrm_q_candidate_real_fit_diagnostic_linkage.json",
        "mgmfrm_q_revision_cross_validation_policy" =>
            "test/fixtures/mgmfrm_q_revision_cross_validation_policy.json",
        "mgmfrm_q_revision_construct_validity_review" =>
            "test/fixtures/mgmfrm_q_revision_construct_validity_review.json",
        "mgmfrm_guarded_local_fit_entrypoint" =>
            "test/fixtures/mgmfrm_guarded_local_fit_entrypoint.json",
        "mgmfrm_fit_metric_threshold_sensitivity" =>
            "test/fixtures/mgmfrm_fit_metric_threshold_sensitivity.json",
        "mgmfrm_construct_reviewed_q_fit_reporting_policy" =>
            "test/fixtures/mgmfrm_construct_reviewed_q_fit_reporting_policy.json",
        "mgmfrm_heldout_prediction_validation_policy" =>
            "test/fixtures/mgmfrm_heldout_prediction_validation_policy.json",
        "mgmfrm_validation_split_model_comparison_policy" =>
            "test/fixtures/mgmfrm_validation_split_model_comparison_policy.json",
        "mgmfrm_heldout_prediction_simulation_grid" =>
            "test/fixtures/mgmfrm_heldout_prediction_simulation_grid.json",
        "mgmfrm_heldout_prediction_execution" =>
            "test/fixtures/mgmfrm_heldout_prediction_execution.json",
        "mgmfrm_full_heldout_refit_or_construct_validation_review" =>
            "test/fixtures/mgmfrm_full_heldout_refit_or_construct_validation_review.json",
        "mgmfrm_full_heldout_mcmc_refit_execution_plan" =>
            "test/fixtures/mgmfrm_full_heldout_mcmc_refit_execution_plan.json",
        "mgmfrm_full_heldout_mcmc_refit_batch_smoke" =>
            "test/fixtures/mgmfrm_full_heldout_mcmc_refit_batch_smoke.json",
        "mgmfrm_full_heldout_mcmc_refit_fold1_pilot" =>
            "test/fixtures/mgmfrm_full_heldout_mcmc_refit_fold1_pilot.json",
        "mgmfrm_full_heldout_mcmc_refit_fold1_scoring" =>
            "test/fixtures/mgmfrm_full_heldout_mcmc_refit_fold1_scoring.json",
        "mgmfrm_full_heldout_mcmc_refit_candidate_batch_scoring" =>
            "test/fixtures/mgmfrm_full_heldout_mcmc_refit_candidate_batch_scoring.json",
        "mgmfrm_full_heldout_mcmc_refit_anchor_scoring" =>
            "test/fixtures/mgmfrm_full_heldout_mcmc_refit_anchor_scoring.json",
        "mgmfrm_publication_grade_refit_gate" =>
            "test/fixtures/mgmfrm_publication_grade_refit_gate.json",
        "mgmfrm_publication_grade_refit_pilot_plan" =>
            "test/fixtures/mgmfrm_publication_grade_refit_pilot_plan.json",
        "mgmfrm_fit_threshold_q_heldout_linkage" =>
            "test/fixtures/mgmfrm_fit_threshold_q_heldout_linkage.json",
        "mgmfrm_publication_grade_refit_pilot_execution_harness" =>
            "test/fixtures/mgmfrm_publication_grade_refit_pilot_execution_harness.json",
        "mgmfrm_publication_grade_refit_batch_expansion_plan" =>
            "test/fixtures/mgmfrm_publication_grade_refit_batch_expansion_plan.json",
        "full_paper_reproduction_archive" =>
            "test/fixtures/gmfrm_full_paper_reproduction_archive.json",
    )
    @test length(input_artifacts) == length(expected_paths)
    @test Set(String(row[:artifact]) for row in input_artifacts) ==
        Set(keys(expected_paths))
    for row in input_artifacts
        artifact = String(row[:artifact])
        @test expected_paths[artifact] == String(row[:path])
        @test Bool(row[:exists])
        @test Bool(row[:schema_matches])
        @test Bool(row[:summary_passed])
        @test Bool(row[:summary][:all_primary_checks])
        if String(row[:hash_policy]) == "sha256"
            @test String(row[:sha256]) ==
                file_sha256(joinpath(root, String(row[:path])))
        else
            @test String(row[:hash_policy]) in (
                "existence_only_avoids_dry_run_claim_manuscript_grid_cycle",
                "existence_only_avoids_broader_review_manuscript_grid_cycle",
                "existence_only_avoids_full_archive_manuscript_grid_cycle")
            @test isnothing(row[:sha256])
        end
    end

    evidence_rows = fixture[:evidence_rows]
    @test length(evidence_rows) == length(input_artifacts)
    @test all(row -> String(row[:status]) == "passed", evidence_rows)
    @test Int(sum(Int(row[:n_evidence_cells]) for row in evidence_rows)) == 5608
    @test any(row -> String(row[:gate]) == "prior_likelihood_sensitivity_grid" &&
        Int(row[:n_evidence_cells]) == 45, evidence_rows)
    @test any(row -> String(row[:gate]) ==
        "prediction_target_and_model_weight_policy" &&
        Int(row[:n_evidence_cells]) == 6, evidence_rows)
    @test any(row -> String(row[:gate]) ==
        "mgmfrm_empirical_q_matrix_recovery_simulation_grid" &&
        Int(row[:n_evidence_cells]) == 12 &&
        String(row[:key_check]) ==
            "mgmfrm_empirical_q_matrix_recovery_simulation", evidence_rows)
    @test any(row -> String(row[:gate]) ==
        "mgmfrm_q_candidate_real_fit_diagnostic_linkage" &&
        Int(row[:n_evidence_cells]) == 5 &&
        String(row[:key_check]) ==
            "mgmfrm_q_candidate_real_fit_diagnostic_linkage", evidence_rows)
    @test any(row -> String(row[:gate]) ==
        "mgmfrm_q_revision_cross_validation_policy" &&
        Int(row[:n_evidence_cells]) == 5 &&
        String(row[:key_check]) ==
            "mgmfrm_q_revision_cross_validation_policy", evidence_rows)
    @test any(row -> String(row[:gate]) ==
        "mgmfrm_q_revision_construct_validity_review" &&
        Int(row[:n_evidence_cells]) == 2 &&
        String(row[:key_check]) ==
            "mgmfrm_q_revision_construct_validity_review", evidence_rows)
    @test any(row -> String(row[:gate]) ==
        "mgmfrm_guarded_local_fit_entrypoint" &&
        Int(row[:n_evidence_cells]) == 2 &&
        String(row[:key_check]) ==
            "mgmfrm_guarded_local_fit_entrypoint", evidence_rows)
    @test any(row -> String(row[:gate]) ==
        "mgmfrm_fit_metric_threshold_sensitivity" &&
        Int(row[:n_evidence_cells]) == 78 &&
        String(row[:key_check]) ==
            "mgmfrm_fit_metric_threshold_sensitivity", evidence_rows)
    @test any(row -> String(row[:gate]) ==
        "mgmfrm_construct_reviewed_q_fit_reporting_policy" &&
        Int(row[:n_evidence_cells]) == 34 &&
        String(row[:key_check]) ==
            "mgmfrm_construct_reviewed_q_fit_reporting_policy", evidence_rows)
    @test any(row -> String(row[:gate]) ==
        "mgmfrm_heldout_prediction_validation_policy" &&
        Int(row[:n_evidence_cells]) == 14 &&
        String(row[:key_check]) ==
            "mgmfrm_heldout_prediction_validation_policy", evidence_rows)
    @test any(row -> String(row[:gate]) ==
        "mgmfrm_validation_split_model_comparison_policy" &&
        Int(row[:n_evidence_cells]) == 29 &&
        String(row[:key_check]) ==
            "mgmfrm_validation_split_model_comparison_policy", evidence_rows)
    @test any(row -> String(row[:gate]) ==
        "mgmfrm_heldout_prediction_simulation_grid" &&
        Int(row[:n_evidence_cells]) == 125 &&
        String(row[:key_check]) ==
            "mgmfrm_heldout_prediction_simulation_grid", evidence_rows)
    @test any(row -> String(row[:gate]) ==
        "mgmfrm_heldout_prediction_execution" &&
        Int(row[:n_evidence_cells]) == 625 &&
        String(row[:key_check]) ==
            "mgmfrm_heldout_prediction_execution", evidence_rows)
    @test any(row -> String(row[:gate]) ==
        "mgmfrm_full_heldout_refit_or_construct_validation_review" &&
        Int(row[:n_evidence_cells]) == 17 &&
        String(row[:key_check]) ==
            "mgmfrm_full_heldout_refit_or_construct_validation_review",
        evidence_rows)
    @test any(row -> String(row[:gate]) ==
        "mgmfrm_full_heldout_mcmc_refit_execution_plan" &&
        Int(row[:n_evidence_cells]) == 144 &&
        String(row[:key_check]) ==
            "mgmfrm_full_heldout_mcmc_refit_execution_plan",
        evidence_rows)
    @test any(row -> String(row[:gate]) ==
        "mgmfrm_full_heldout_mcmc_refit_batch_smoke" &&
        Int(row[:n_evidence_cells]) == 33 &&
        String(row[:key_check]) ==
            "mgmfrm_full_heldout_mcmc_refit_batch_smoke",
        evidence_rows)
    @test any(row -> String(row[:gate]) ==
        "mgmfrm_full_heldout_mcmc_refit_fold1_pilot" &&
        Int(row[:n_evidence_cells]) == 225 &&
        String(row[:key_check]) ==
            "mgmfrm_full_heldout_mcmc_refit_fold1_pilot",
        evidence_rows)
    @test any(row -> String(row[:gate]) ==
        "mgmfrm_full_heldout_mcmc_refit_fold1_scoring" &&
        Int(row[:n_evidence_cells]) == 175 &&
        String(row[:key_check]) ==
            "mgmfrm_full_heldout_mcmc_refit_fold1_scoring",
        evidence_rows)
    @test any(row -> String(row[:gate]) ==
        "mgmfrm_full_heldout_mcmc_refit_candidate_batch_scoring" &&
        Int(row[:n_evidence_cells]) == 855 &&
        String(row[:key_check]) ==
            "mgmfrm_full_heldout_mcmc_refit_candidate_batch_scoring",
        evidence_rows)
    @test any(row -> String(row[:gate]) ==
        "mgmfrm_full_heldout_mcmc_refit_anchor_scoring" &&
        Int(row[:n_evidence_cells]) == 668 &&
        String(row[:key_check]) ==
            "mgmfrm_full_heldout_mcmc_refit_anchor_scoring",
        evidence_rows)
    @test any(row -> String(row[:gate]) ==
        "mgmfrm_publication_grade_refit_gate" &&
        Int(row[:n_evidence_cells]) == 26 &&
        String(row[:key_check]) ==
            "mgmfrm_publication_grade_refit_gate",
        evidence_rows)
    @test any(row -> String(row[:gate]) ==
        "mgmfrm_publication_grade_refit_pilot_plan" &&
        Int(row[:n_evidence_cells]) == 70 &&
        String(row[:key_check]) ==
            "mgmfrm_publication_grade_refit_pilot_plan",
        evidence_rows)
    @test any(row -> String(row[:gate]) ==
        "mgmfrm_fit_threshold_q_heldout_linkage" &&
        Int(row[:n_evidence_cells]) == 35 &&
        String(row[:key_check]) ==
            "mgmfrm_fit_threshold_q_heldout_linkage",
        evidence_rows)
    @test any(row -> String(row[:gate]) ==
        "mgmfrm_publication_grade_refit_pilot_execution_harness" &&
        Int(row[:n_evidence_cells]) == 90 &&
        String(row[:key_check]) ==
            "mgmfrm_publication_grade_refit_pilot_execution_harness",
        evidence_rows)
    @test any(row -> String(row[:gate]) ==
        "mgmfrm_publication_grade_refit_batch_expansion_plan" &&
        Int(row[:n_evidence_cells]) == 2134 &&
        String(row[:key_check]) ==
            "mgmfrm_publication_grade_refit_batch_expansion_plan",
        evidence_rows)

    decisions = fixture[:claim_decision_rows]
    @test length(decisions) == 4
    @test any(row -> String(row[:claim]) == "guarded_scalar_gmfrm_fit" &&
        Bool(row[:public_claim_allowed]), decisions)
    @test any(row -> String(row[:claim]) ==
        "model_weights_or_sparse_mgmfrm_superiority" &&
        String(row[:decision]) ==
            "publication_grade_execution_harness_ready_keep_blocked_until_pilot_or_external_dataset_review" &&
        String(row[:required_followup]) ==
            "execute_publication_grade_refit_pilot_or_attach_external_construct_dataset",
        decisions)
    @test all(row -> String(row[:claim]) == "guarded_scalar_gmfrm_fit" ||
        Bool(row[:public_claim_allowed]) == false, decisions)

    blockers = fixture[:blocker_rows]
    @test isempty(blockers)

    decision = fixture[:decision_record]
    @test String(decision[:selected_decision]) ==
        "full_archive_recorded_keep_guarded_scalar_and_confirmatory_mgmfrm_only"
    @test Bool(decision[:scalar_guarded_fit_allowed])
    @test Bool(decision[:broader_generalized_fit_allowed]) == false
    @test Bool(decision[:manuscript_claims_allowed]) == false
    @test String(decision[:required_followup]) ==
        "execute_publication_grade_refit_pilot_or_attach_external_construct_dataset"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:local_only])
    @test Bool(summary[:all_input_artifacts_present])
    @test Bool(summary[:all_expected_schemas])
    @test Bool(summary[:all_input_summaries_passed])
    @test Bool(summary[:all_primary_checks_passed])
    @test Int(summary[:n_input_artifacts]) == length(input_artifacts)
    @test Int(summary[:n_evidence_rows]) == length(evidence_rows)
    @test Int(summary[:total_evidence_cells]) == 5608
    @test Int(summary[:minimum_required_evidence_cells]) == 60
    @test Bool(summary[:scalar_fit_validation_grid_passed])
    @test Bool(summary[:posterior_predictive_grid_passed])
    @test Bool(summary[:sparse_pathology_recovery_grid_passed])
    @test Bool(summary[:prior_likelihood_sensitivity_grid_passed])
    @test Bool(summary[:real_data_case_study_passed])
    @test Bool(summary[:claim_recovery_reproduction_archive_passed])
    @test Bool(summary[:broader_experimental_exposure_decision_review_passed])
    @test Bool(summary[:prediction_target_and_model_weight_policy_passed])
    @test Bool(summary[:mgmfrm_manual_public_scope_review_for_fit_passed])
    @test Bool(summary[:dff_estimand_validation_grid_passed])
    @test Bool(summary[:mgmfrm_sparse_recovery_grid_passed])
    @test Bool(summary[
        :mgmfrm_empirical_q_matrix_recovery_simulation_grid_passed])
    @test Bool(summary[:mgmfrm_q_candidate_real_fit_diagnostic_linkage_passed])
    @test Bool(summary[:mgmfrm_q_revision_cross_validation_policy_passed])
    @test Bool(summary[
        :mgmfrm_q_revision_construct_validity_review_passed])
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
    @test Bool(summary[:publication_grade_pilot_runner_materialized])
    @test Bool(summary[:full_paper_reproduction_archive_passed])
    @test Bool(summary[:manuscript_claims_allowed]) == false
    @test Bool(summary[:no_publication_commands])
    @test Int(summary[:n_blockers]) == 0
    @test isempty(summary[:remaining_public_blockers])
    @test String(summary[:recommendation]) ==
        "execute_single_cell_publication_grade_pilot_or_attach_external_dataset"
    @test String(summary[:next_gate]) ==
        "execute_publication_grade_refit_pilot_or_attach_external_construct_dataset"
end

function check_gmfrm_broader_experimental_exposure_decision_review_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.gmfrm_broader_experimental_exposure_decision_review.v1"
    @test String(fixture[:family]) == "gmfrm"
    @test String(fixture[:scope]) == "broader_generalized_exposure_decision"
    @test String(fixture[:status]) ==
        "broader_experimental_exposure_decision_review_recorded"
    @test String(fixture[:decision]) ==
        "keep_guarded_scalar_gmfrm_and_confirmatory_mgmfrm_only"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])
    @test Bool(fixture[:broader_public_fit]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) ==
        "gmfrm_broader_experimental_exposure_decision_review_v1"
    @test String(protocol[:review_kind]) ==
        "local_broader_experimental_exposure_decision"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test Bool(protocol[:local_only])
    @test String(protocol[:entrypoint_under_review]) ==
        "fit(spec; experimental = true)"
    @test Bool(thresholds[:require_guarded_exposure_review_passed])
    @test Bool(thresholds[:require_claim_recovery_reproduction_archive_passed])
    @test Bool(thresholds[:require_real_data_case_study_passed])
    @test Bool(thresholds[:require_mgmfrm_bridge_oracle_present])
    @test Bool(thresholds[:require_mgmfrm_candidate_chain_study_passed])
    @test Bool(thresholds[:require_mgmfrm_recovery_smoke_passed])
    @test Bool(thresholds[:require_mgmfrm_baseline_comparison_passed])
    @test Bool(thresholds[:require_mgmfrm_sparse_recovery_grid_passed])
    @test Bool(thresholds[:require_mgmfrm_guarded_fit_method_wiring_passed])
    @test Bool(thresholds[:require_mgmfrm_guarded_fit_validation_grid_passed])
    @test Bool(thresholds[:require_mgmfrm_guarded_fit_api_dry_run_passed])
    @test Bool(thresholds[:require_mgmfrm_guarded_fit_public_exposure_review_passed])
    @test Bool(thresholds[:require_prediction_target_and_model_weight_policy_passed])
    @test Bool(thresholds[:require_dff_estimand_validation_grid_passed])
    @test Bool(thresholds[:require_manuscript_scale_simulation_grid_passed])
    @test Bool(thresholds[:require_tam_direct_execution_recorded])
    @test Bool(thresholds[:require_tam_raw_archive_integrity_passed])
    @test Bool(thresholds[:require_tam_post_execution_packet_integrity_passed])
    @test Bool(thresholds[:require_tam_independent_review_pending_recorded])
    @test Bool(thresholds[:require_tam_pre_execution_lineage_mismatch_recorded])
    @test Bool(thresholds[:require_tam_evidence_nontransfer_to_gmfrm_mgmfrm])
    @test Bool(thresholds[:require_full_paper_reproduction_archive_passed])
    @test Bool(thresholds[:require_scalar_guarded_fit_kept_enabled])
    @test Bool(thresholds[:require_mgmfrm_fit_kept_internal])
    @test Bool(thresholds[:require_broader_generalized_fit_blocked])
    @test Bool(thresholds[:require_dff_model_effects_blocked])
    @test Bool(thresholds[:require_model_weights_blocked])
    @test Bool(thresholds[:require_manuscript_claims_blocked])
    @test Bool(thresholds[:require_no_publication_commands])

    input_artifacts = fixture[:input_artifacts]
    @test length(input_artifacts) == 20
    expected_paths = Dict(
        "guarded_exposure_review" =>
            "test/fixtures/gmfrm_guarded_exposure_review.json",
        "claim_recovery_reproduction_archive" =>
            "test/fixtures/gmfrm_claim_recovery_reproduction_archive.json",
        "real_data_case_study" =>
            "test/fixtures/gmfrm_real_data_case_study.json",
        "mgmfrm_candidate_chain_study" =>
            "test/fixtures/mgmfrm_candidate_chain_study.json",
        "mgmfrm_recovery_smoke" =>
            "test/fixtures/mgmfrm_recovery_smoke.json",
        "mgmfrm_baseline_comparison" =>
            "test/fixtures/mgmfrm_baseline_comparison.json",
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
        "mgmfrm_bridge_oracle" =>
            "test/fixtures/source_mgmfrm_bridge_logdensity.json",
    )
    @test Set(String(row[:artifact]) for row in input_artifacts) ==
        Set(keys(expected_paths))
    for row in input_artifacts
        artifact = String(row[:artifact])
        @test Bool(row[:exists])
        @test Bool(row[:schema_matches])
        @test Bool(row[:summary_passed])
        @test expected_paths[artifact] == String(row[:path])
        if artifact == "guarded_exposure_review"
            @test String(row[:hash_policy]) ==
                "existence_only_avoids_broader_review_guarded_exposure_cycle"
            @test isnothing(row[:sha256])
        elseif artifact == "full_paper_reproduction_archive"
            @test String(row[:hash_policy]) ==
                "existence_only_avoids_full_archive_broader_review_cycle"
            @test isnothing(row[:sha256])
        else
            @test String(row[:hash_policy]) == "sha256"
            @test String(row[:sha256]) ==
                file_sha256(joinpath(root, String(row[:path])))
        end
    end

    decisions = fixture[:scope_decision_rows]
    @test length(decisions) == 7
    scalar = only(row for row in decisions
        if String(row[:surface]) == "scalar_gmfrm_guarded_fit")
    @test String(scalar[:decision]) == "keep_enabled_guarded_experimental"
    @test Bool(scalar[:evidence])
    @test Bool(scalar[:public_fit])
    mgmfrm = only(row for row in decisions
        if String(row[:surface]) == "confirmatory_mgmfrm_fit")
    @test String(mgmfrm[:decision]) == "enable_guarded_experimental"
    @test Bool(mgmfrm[:evidence])
    @test Bool(mgmfrm[:public_fit])
    @test String(mgmfrm[:next_required_evidence]) ==
        "guarded_local_mgmfrm_fit_entrypoint"
    dff_surface = only(row for row in decisions
        if String(row[:surface]) == "dff_model_effects")
    @test String(dff_surface[:decision]) == "keep_blocked"
    @test Bool(dff_surface[:evidence])
    @test Bool(dff_surface[:public_fit]) == false
    @test String(dff_surface[:next_required_evidence]) ==
        "future_dff_model_effect_fit_policy"
    @test any(row -> String(row[:surface]) == "loo_or_stacking_model_weights" &&
        String(row[:decision]) == "policy_recorded_keep_public_claims_blocked" &&
        Bool(row[:evidence]) &&
        Bool(row[:public_fit]) == false, decisions)
    tam_surface = only(row for row in decisions
        if String(row[:surface]) == "tam_direct_mfrm_overlap_claim")
    @test String(tam_surface[:decision]) ==
        "record_nontransfer_keep_public_validation_blocked"
    @test Bool(tam_surface[:evidence])
    @test Bool(tam_surface[:public_fit]) == false

    blockers = fixture[:blocker_rows]
    @test Set(String(row[:blocker]) for row in blockers) == Set([
        "tam_direct_independent_review_pending",
        "tam_pre_execution_refinement_lineage_adjudication_pending",
    ])
    @test all(row -> !Bool(row[:resolved]) &&
        Bool(row[:does_not_block_guarded_local_fit]), blockers)

    cycle_breaks = fixture[:cycle_break_references]
    @test length(cycle_breaks) == 1
    @test String(cycle_breaks[1][:artifact]) ==
        "test/fixtures/gmfrm_guarded_exposure_review.json"
    @test String(cycle_breaks[1][:hash_policy]) == "existence_only"

    decision = fixture[:decision_record]
    @test Bool(decision[:scalar_guarded_fit_allowed])
    @test Bool(decision[:mgmfrm_fit_allowed])
    @test Bool(decision[:broader_generalized_fit_allowed]) == false
    @test Bool(decision[:tam_public_validation_allowed]) == false
    @test String(decision[:tam_direct_evidence_scope]) ==
        "mfrm_tam_overlap_nontransfer"
    @test Bool(decision[
        :tam_direct_evidence_transfers_to_gmfrm_or_mgmfrm]) == false
    @test Bool(decision[:tam_independent_review_completed]) == false
    @test String(decision[:public_exposure_support]) ==
        "guarded_scalar_gmfrm_and_fixed_q_mgmfrm_only"
    @test String(decision[:interpretation]) ==
        "broader_exposure_review_recorded_guarded_confirmatory_mgmfrm_enabled_keep_broader_claims_blocked"
    @test String(decision[:required_followup]) ==
        "guarded_local_mgmfrm_fit_entrypoint"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:local_only])
    @test Bool(summary[:all_input_artifacts_present])
    @test Bool(summary[:all_expected_schemas])
    @test Bool(summary[:all_required_inputs_passed])
    @test Bool(summary[:guarded_exposure_review_passed])
    @test Bool(summary[:claim_recovery_reproduction_archive_passed])
    @test Bool(summary[:real_data_case_study_passed])
    @test Bool(summary[:mgmfrm_bridge_oracle_present])
    @test Bool(summary[:mgmfrm_candidate_chain_study_passed])
    @test Bool(summary[:mgmfrm_recovery_smoke_passed])
    @test Bool(summary[:mgmfrm_baseline_comparison_passed])
    @test Bool(summary[:mgmfrm_sparse_recovery_grid_passed])
    @test Bool(summary[:mgmfrm_guarded_fit_method_wiring_passed])
    @test Bool(summary[:mgmfrm_guarded_fit_validation_grid_passed])
    @test Bool(summary[:mgmfrm_guarded_fit_api_dry_run_passed])
    @test Bool(summary[:mgmfrm_guarded_fit_public_exposure_review_passed])
    @test Bool(summary[:prediction_target_and_model_weight_policy_passed])
    @test Bool(summary[:mgmfrm_manual_public_scope_review_for_fit_passed])
    @test Bool(summary[:dff_estimand_validation_grid_passed])
    @test Bool(summary[:manuscript_scale_simulation_grid_passed])
    @test Bool(summary[:full_paper_reproduction_archive_passed])
    @test Bool(summary[:tam_direct_primary_gate_passed])
    @test Bool(summary[:tam_raw_archive_integrity_passed])
    @test Bool(summary[:tam_post_packet_integrity_passed])
    @test Bool(summary[:tam_independent_review_completed]) == false
    @test Bool(summary[:tam_execution_input_lineage_exact])
    @test Bool(summary[:tam_pre_execution_exact_input_lineage]) == false
    @test Bool(summary[
        :tam_direct_evidence_transfers_to_gmfrm_or_mgmfrm]) == false
    @test Int(summary[:n_input_artifacts]) == length(input_artifacts)
    @test Int(summary[:n_scope_decisions]) == length(decisions)
    @test Int(summary[:n_risk_rows]) == length(fixture[:risk_rows])
    @test Int(summary[:n_blockers]) == length(blockers)
    @test Bool(summary[:scalar_guarded_fit_allowed])
    @test Bool(summary[:broader_generalized_fit_allowed]) == false
    @test Bool(summary[:mgmfrm_fit_allowed])
    @test Bool(summary[:dff_model_effects_allowed]) == false
    @test Bool(summary[:model_weights_allowed]) == false
    @test Bool(summary[:manuscript_claims_allowed]) == false
    @test Bool(summary[:tam_public_validation_allowed]) == false
    @test Bool(summary[:no_publication_commands])
    @test Set(String.(summary[:remaining_public_blockers])) == Set([
        "tam_direct_independent_review_pending",
        "tam_pre_execution_refinement_lineage_adjudication_pending",
    ])
    @test String(summary[:recommendation]) ==
        "manual_scope_review_recorded_keep_guarded_scalar_and_confirmatory_mgmfrm_only"
    @test String(summary[:next_gate]) == "guarded_local_mgmfrm_fit_entrypoint"
end
