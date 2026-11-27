function check_mgmfrm_q_candidate_real_fit_diagnostic_linkage_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_q_candidate_real_fit_diagnostic_linkage.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) == "q_candidate_real_fit_diagnostic_linkage"
    @test String(fixture[:status]) ==
        "q_candidate_real_fit_diagnostic_linkage_recorded"
    @test String(fixture[:decision]) ==
        "keep_candidate_q_fit_linkage_diagnostic_only"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])
    @test Bool(fixture[:empirical_q_recovery_public]) == false
    @test Bool(fixture[:publication_or_registration_action]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) ==
        "mgmfrm_q_candidate_real_fit_diagnostic_linkage_v1"
    @test String(protocol[:review_kind]) ==
        "local_q_candidate_real_fit_diagnostic_linkage"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test Bool(protocol[:local_only])
    @test String(protocol[:entrypoint]) == "fit(spec; experimental = true)"
    @test String(protocol[:fit_kind]) ==
        "guarded_confirmatory_mgmfrm_short_fit"
    @test Bool(thresholds[:require_empirical_q_matrix_recovery_simulation_grid_passed])
    @test Bool(thresholds[:require_all_linkage_scenarios_checked])
    @test Bool(thresholds[:require_candidate_q_validation_checked])
    @test Bool(thresholds[:require_all_fit_attempts_succeeded])
    @test Bool(thresholds[:require_all_fit_terms_finite])
    @test Bool(thresholds[:require_all_direct_constraints_passed])
    @test Bool(thresholds[:require_fixed_q_diagnostic_rows_recorded])
    @test Bool(thresholds[:require_invalid_candidates_blocked_before_fit])
    @test Bool(thresholds[:require_no_automatic_q_revision])
    @test Bool(thresholds[:require_no_public_q_revision_claim])
    @test Bool(thresholds[:require_no_mcmc_convergence_claim])
    @test Bool(thresholds[:require_no_publication_or_registration_action])

    input_artifacts = fixture[:input_artifacts]
    @test length(input_artifacts) == 1
    input = only(input_artifacts)
    @test String(input[:artifact]) ==
        "empirical_q_matrix_recovery_simulation_grid"
    @test String(input[:path]) ==
        "test/fixtures/mgmfrm_empirical_q_matrix_recovery_simulation_grid.json"
    @test Bool(input[:exists])
    @test Bool(input[:schema_matches])
    @test Bool(input[:summary_passed])
    @test String(input[:sha256]) ==
        file_sha256(joinpath(root, String(input[:path])))

    rows = fixture[:scenario_rows]
    @test length(rows) == 5
    @test Set(String(row[:scenario]) for row in rows) == Set([
        "retained_declared_q_fit_linked",
        "missing_loading_candidate_fit_linked",
        "extra_loading_candidate_fit_linked",
        "false_positive_candidate_fit_diagnostic_only",
        "invalid_duplicate_dimension_candidate_blocked_before_fit",
    ])
    @test all(row -> Bool(row[:summary][:passed]), rows)
    @test all(row -> Bool(row[:public_revision_allowed]) == false, rows)
    @test all(row -> Bool(row[:automatic_revision_allowed]) == false, rows)
    @test all(row -> Bool(row[:public_claim_allowed]) == false, rows)
    @test all(row -> Bool(row[:declared_fit][:fit_succeeded]), rows)
    @test all(row -> Bool(row[:declared_fit][:finite_logposterior]) &&
        Bool(row[:declared_fit][:finite_direct_loglikelihood]) &&
        Bool(row[:declared_fit][:finite_pointwise_loglikelihood]) &&
        Bool(row[:declared_fit][:direct_constraints_passed]) &&
        Bool(row[:declared_fit][:fixed_q_diagnostic_rows_recorded]) &&
        Bool(row[:declared_fit][:artifact_content_hash_recorded]) &&
        Bool(row[:declared_fit][:waic_recorded]),
        rows)
    attempted = filter(row -> Bool(row[:candidate_fit][:fit_attempted]), rows)
    @test length(attempted) == 4
    @test all(row -> Bool(row[:candidate_fit][:fit_succeeded]) &&
        Bool(row[:candidate_fit][:public_fit]) &&
        Bool(row[:candidate_fit][:experimental_public]) &&
        Bool(row[:candidate_fit][:fit_ready]) &&
        Bool(row[:candidate_fit][:finite_logposterior]) &&
        Bool(row[:candidate_fit][:finite_direct_loglikelihood]) &&
        Bool(row[:candidate_fit][:finite_pointwise_loglikelihood]) &&
        Bool(row[:candidate_fit][:direct_constraints_passed]) &&
        Bool(row[:candidate_fit][:fixed_q_diagnostic_rows_recorded]) &&
        Bool(row[:candidate_fit][:artifact_content_hash_recorded]) &&
        Bool(row[:candidate_fit][:waic_recorded]) &&
        String(row[:candidate_fit][:fit_object]) == "MGMFRMFit" &&
        String(row[:candidate_fit][:diagnostic_schema]) ==
            "bayesianmgmfrm.mgmfrm_guarded_local_fit_diagnostics.v1" &&
        String(row[:candidate_fit][:sampler_diagnostic_schema]) ==
            "bayesianmgmfrm.mgmfrm_guarded_local_fit_sampler_diagnostics.v1" &&
        String(row[:candidate_fit][:artifact_schema]) ==
            "bayesianmgmfrm.mgmfrm_experimental_fit_artifact.v1",
        attempted)
    @test any(row -> String(row[:scenario]) ==
        "false_positive_candidate_fit_diagnostic_only" &&
        String(row[:source_action]) == "flag_noisy_candidate_manual_review" &&
        Bool(row[:candidate_fit][:fit_succeeded]) &&
        String(row[:summary][:interpretation]) ==
            "diagnostic_linkage_only_no_public_q_revision",
        rows)
    blocked = only(row for row in rows if
        String(row[:scenario]) ==
            "invalid_duplicate_dimension_candidate_blocked_before_fit")
    @test Bool(blocked[:candidate_fit][:q_matrix_validation][:passed]) == false
    @test Bool(blocked[:candidate_fit][:fit_attempted]) == false
    @test Bool(blocked[:summary][:invalid_candidate_blocked_before_fit])
    @test "duplicate_dimension_columns" in
        String.(blocked[:candidate_fit][:q_matrix_validation][:error_checks])

    decision = fixture[:decision_record]
    @test Bool(decision[:real_fit_diagnostic_linkage_recorded])
    @test Bool(decision[:candidate_suggestions_allowed])
    @test Bool(decision[:automatic_q_revision_allowed]) == false
    @test Bool(decision[:public_q_revision_claim_allowed]) == false
    @test Bool(decision[:convergence_claim_allowed]) == false
    @test String(decision[:required_followup]) ==
        "cross_validated_q_revision_policy_for_q_candidates"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:empirical_q_matrix_recovery_simulation_grid_passed])
    @test Bool(summary[:all_linkage_scenarios_checked])
    @test Bool(summary[:candidate_q_validation_checked])
    @test Bool(summary[:all_fit_attempts_succeeded])
    @test Bool(summary[:all_fit_terms_finite])
    @test Bool(summary[:all_direct_constraints_passed])
    @test Bool(summary[:fixed_q_diagnostic_rows_recorded])
    @test Bool(summary[:invalid_candidates_blocked_before_fit])
    @test Bool(summary[:no_automatic_q_revision])
    @test Bool(summary[:no_public_q_revision_claim])
    @test Bool(summary[:no_mcmc_convergence_claim])
    @test Int(summary[:n_scenarios]) == length(rows)
    @test Int(summary[:n_passed_scenarios]) == length(rows)
    @test Int(summary[:n_candidate_fit_attempts]) == 4
    @test Int(summary[:n_candidate_fit_successes]) == 4
    @test Int(summary[:n_declared_fit_successes]) == 5
    @test Int(summary[:n_invalid_candidates_blocked_before_fit]) == 1
    @test Int(summary[:n_public_revisions_allowed]) == 0
    @test Int(summary[:n_automatic_revisions_allowed]) == 0
    @test Set(String(blocker) for blocker in summary[:remaining_public_blockers]) ==
        Set([
            "cross_validated_q_revision_policy_missing",
            "construct_validity_manual_review_missing",
        ])
    @test String(summary[:recommendation]) ==
        "use_candidate_q_real_fit_linkage_for_local_diagnostics_only"
    @test String(summary[:next_gate]) ==
        "cross_validated_q_revision_policy_for_q_candidates"
end

function check_mgmfrm_q_revision_cross_validation_policy_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_q_revision_cross_validation_policy.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) == "q_revision_cross_validation_policy"
    @test String(fixture[:status]) ==
        "q_revision_cross_validation_policy_recorded"
    @test String(fixture[:decision]) ==
        "keep_cross_validated_q_revision_manual_review_only"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])
    @test Bool(fixture[:empirical_q_recovery_public]) == false
    @test Bool(fixture[:q_revision_public]) == false
    @test Bool(fixture[:publication_or_registration_action]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) ==
        "mgmfrm_q_revision_cross_validation_policy_v1"
    @test String(protocol[:review_kind]) ==
        "local_q_revision_cross_validation_policy"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test Bool(protocol[:local_only])
    @test Int(protocol[:cross_validation][:folds]) == 3
    @test String(protocol[:cross_validation][:score]) ==
        "deterministic_holdout_elpd_surrogate"
    @test Bool(thresholds[
        :require_q_candidate_real_fit_diagnostic_linkage_passed])
    @test Bool(thresholds[:require_public_reference_records_recorded])
    @test Bool(thresholds[:require_all_policy_scenarios_checked])
    @test Bool(thresholds[:require_all_candidate_q_validations_checked])
    @test Bool(thresholds[
        :require_all_cv_eligible_candidates_have_fold_rows])
    @test Float64(thresholds[:require_minimum_mean_holdout_elpd_delta]) == 0.20
    @test Float64(thresholds[:require_minimum_fold_win_rate]) ≈ 2 / 3
    @test Int(thresholds[:require_maximum_loading_complexity_increase]) == 1
    @test Bool(thresholds[:require_false_positive_candidate_rejected])
    @test Bool(thresholds[:require_invalid_candidates_excluded_from_cv])
    @test Bool(thresholds[
        :require_supported_candidates_remain_manual_review_only])
    @test Bool(thresholds[
        :require_construct_validity_manual_review_before_public_revision])
    @test Bool(thresholds[:require_no_automatic_q_revision])
    @test Bool(thresholds[:require_no_public_q_revision_claim])
    @test Bool(thresholds[:require_no_publication_or_registration_action])

    reference_records = fixture[:reference_records]
    @test length(reference_records) == 4
    @test all(row -> all(key -> !occursin("item_key", String(key)),
        keys(row)), reference_records)
    @test all(row -> String(row[:source]) == "doi", reference_records)
    @test Set(String(row[:doi]) for row in reference_records) == Set([
        "10.1007/s11336-015-9467-8",
        "10.21449/ijate.407193",
        "10.1177/0013164418814898",
        "10.1177/0146621620909904",
    ])

    input_artifacts = fixture[:input_artifacts]
    @test length(input_artifacts) == 1
    input = only(input_artifacts)
    @test String(input[:artifact]) ==
        "q_candidate_real_fit_diagnostic_linkage"
    @test String(input[:path]) ==
        "test/fixtures/mgmfrm_q_candidate_real_fit_diagnostic_linkage.json"
    @test Bool(input[:exists])
    @test Bool(input[:schema_matches])
    @test Bool(input[:summary_passed])
    @test String(input[:sha256]) ==
        file_sha256(joinpath(root, String(input[:path])))

    rows = fixture[:scenario_rows]
    @test length(rows) == 5
    @test Set(String(row[:scenario]) for row in rows) == Set([
        "retained_declared_q_cv_no_change",
        "missing_loading_candidate_cv_supported_manual_gate",
        "extra_loading_candidate_cv_supported_manual_gate",
        "false_positive_candidate_rejected_by_cv",
        "invalid_duplicate_dimension_candidate_excluded_from_cv",
    ])
    @test all(row -> Bool(row[:summary][:passed]), rows)
    @test all(row -> Bool(row[:summary][:candidate_validation_checked]), rows)
    @test all(row -> Bool(row[:public_revision_allowed]) == false, rows)
    @test all(row -> Bool(row[:automatic_revision_allowed]) == false, rows)
    @test all(row -> Bool(row[:public_claim_allowed]) == false, rows)
    @test count(row -> Bool(row[:cv_attempted]), rows) == 4
    @test sum(length(row[:cv_fold_rows]) for row in rows) == 12
    @test count(row -> Bool(row[:cv_supported]), rows) == 2

    supported = filter(row -> Bool(row[:cv_supported]), rows)
    @test Set(String(row[:scenario]) for row in supported) == Set([
        "missing_loading_candidate_cv_supported_manual_gate",
        "extra_loading_candidate_cv_supported_manual_gate",
    ])
    @test all(row -> String(row[:decision]) ==
        "manual_review_candidate_supported_by_cv" &&
        Bool(row[:construct_review_required]) &&
        Bool(row[:summary][:supported_manual_only]) &&
        Float64(row[:mean_delta_candidate_minus_declared]) >= 0.20 &&
        Float64(row[:fold_win_rate]) >= 2 / 3, supported)

    retained = only(row for row in rows if
        String(row[:scenario]) == "retained_declared_q_cv_no_change")
    @test String(retained[:decision]) == "retain_declared_q"
    @test Bool(retained[:cv_supported]) == false
    @test Float64(retained[:mean_delta_candidate_minus_declared]) == 0.0

    false_positive = only(row for row in rows if
        String(row[:scenario]) == "false_positive_candidate_rejected_by_cv")
    @test String(false_positive[:decision]) ==
        "reject_candidate_not_cross_validated"
    @test Bool(false_positive[:cv_supported]) == false
    @test Float64(false_positive[:mean_delta_candidate_minus_declared]) < 0.0
    @test Bool(false_positive[:summary][:false_positive_rejected])

    invalid = only(row for row in rows if String(row[:scenario]) ==
        "invalid_duplicate_dimension_candidate_excluded_from_cv")
    @test Bool(invalid[:candidate_q_validation][:passed]) == false
    @test Bool(invalid[:cv_attempted]) == false
    @test isempty(invalid[:cv_fold_rows])
    @test String(invalid[:decision]) == "exclude_invalid_candidate_before_cv"
    @test Bool(invalid[:source_linkage][:invalid_candidate_blocked_before_fit])
    @test Bool(invalid[:summary][:invalid_candidate_excluded_from_cv])

    policy_rows = fixture[:policy_rows]
    @test length(policy_rows) == 4
    @test Set(String(row[:policy]) for row in policy_rows) == Set([
        "kfold_holdout_delta",
        "fold_win_rate",
        "loading_complexity_guard",
        "construct_validity_manual_review",
    ])
    @test any(row -> String(row[:policy]) ==
        "construct_validity_manual_review" &&
        String(row[:status]) == "required_before_public_revision",
        policy_rows)

    decision = fixture[:decision_record]
    @test Bool(decision[:cross_validated_q_revision_policy_recorded])
    @test Bool(decision[:candidate_suggestions_allowed])
    @test Bool(decision[:manual_review_candidates_allowed])
    @test Bool(decision[:automatic_q_revision_allowed]) == false
    @test Bool(decision[:public_q_revision_claim_allowed]) == false
    @test Bool(decision[:public_q_revision_allowed]) == false
    @test Bool(decision[:construct_validity_manual_review_required])
    @test String(decision[:required_followup]) ==
        "construct_validity_manual_review_for_q_revision_candidates"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:q_candidate_real_fit_diagnostic_linkage_passed])
    @test Bool(summary[:public_reference_records_recorded])
    @test Bool(summary[:all_policy_scenarios_checked])
    @test Bool(summary[:all_candidate_q_validations_checked])
    @test Bool(summary[:all_cv_eligible_candidates_have_fold_rows])
    @test Bool(summary[:false_positive_candidate_rejected])
    @test Bool(summary[:invalid_candidates_excluded_from_cv])
    @test Bool(summary[:supported_candidates_remain_manual_review_only])
    @test Bool(summary[:construct_validity_manual_review_required])
    @test Bool(summary[:no_automatic_q_revision])
    @test Bool(summary[:no_public_q_revision_claim])
    @test Int(summary[:n_reference_records]) == 4
    @test Int(summary[:n_scenarios]) == length(rows)
    @test Int(summary[:n_passed_scenarios]) == length(rows)
    @test Int(summary[:n_cv_attempted_scenarios]) == 4
    @test Int(summary[:n_cv_fold_rows]) == 12
    @test Int(summary[:n_cv_supported_candidates]) == 2
    @test Int(summary[:n_supported_manual_review_candidates]) == 2
    @test Int(summary[:n_false_positive_candidates_rejected]) == 1
    @test Int(summary[:n_invalid_candidates_excluded_from_cv]) == 1
    @test Int(summary[:n_public_revisions_allowed]) == 0
    @test Int(summary[:n_automatic_revisions_allowed]) == 0
    @test Set(String(blocker) for blocker in summary[:remaining_public_blockers]) ==
        Set(["construct_validity_manual_review_missing"])
    @test String(summary[:recommendation]) ==
        "use_cross_validated_q_policy_for_manual_review_candidates_only"
    @test String(summary[:next_gate]) ==
        "construct_validity_manual_review_for_q_revision_candidates"
end

function check_mgmfrm_q_revision_construct_validity_review_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_q_revision_construct_validity_review.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) ==
        "q_revision_construct_validity_review"
    @test String(fixture[:status]) ==
        "q_revision_construct_validity_review_recorded"
    @test String(fixture[:decision]) ==
        "keep_construct_validated_q_revisions_manual_local_only"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])
    @test Bool(fixture[:empirical_q_recovery_public]) == false
    @test Bool(fixture[:q_revision_public]) == false
    @test Bool(fixture[:publication_or_registration_action]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) ==
        "mgmfrm_q_revision_construct_validity_review_v1"
    @test String(protocol[:review_kind]) ==
        "local_q_revision_construct_validity_review"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test Bool(protocol[:local_only])
    @test String(protocol[:review_scope]) ==
        "cv_supported_q_revision_candidates"
    @test String(protocol[:review_materials]) ==
        "synthetic_rubric_trace_fixture"
    @test Bool(thresholds[
        :require_q_revision_cross_validation_policy_passed])
    @test Bool(thresholds[:require_supported_candidates_available])
    @test Bool(thresholds[:require_all_supported_candidates_reviewed])
    @test Bool(thresholds[
        :require_non_supported_candidates_not_reviewed_as_revisions])
    @test Bool(thresholds[:require_all_construct_map_evidence_recorded])
    @test Bool(thresholds[:require_all_item_rubric_alignment_recorded])
    @test Bool(thresholds[:require_all_dimension_label_consistency_recorded])
    @test Bool(thresholds[:require_all_expected_response_process_recorded])
    @test Bool(thresholds[:require_all_local_dependence_risk_checked])
    @test Bool(thresholds[:require_reviewer_agreement_recorded])
    @test Bool(thresholds[
        :require_supported_candidates_remain_manual_local_only])
    @test Bool(thresholds[:require_no_automatic_q_revision])
    @test Bool(thresholds[:require_no_public_q_revision_claim])
    @test Bool(thresholds[:require_no_publication_or_registration_action])

    reference_records = fixture[:reference_records]
    @test length(reference_records) == 5
    @test all(row -> all(key -> !occursin("item_key", String(key)),
        keys(row)), reference_records)
    @test all(row -> String(row[:source]) == "doi", reference_records)
    @test Set(String(row[:doi]) for row in reference_records) == Set([
        "10.1007/s41237-021-00144-w",
        "10.1007/s11336-015-9467-8",
        "10.21449/ijate.407193",
        "10.1177/0013164418814898",
        "10.1177/0146621620909904",
    ])

    input_artifacts = fixture[:input_artifacts]
    @test length(input_artifacts) == 1
    input = only(input_artifacts)
    @test String(input[:artifact]) == "q_revision_cross_validation_policy"
    @test String(input[:path]) ==
        "test/fixtures/mgmfrm_q_revision_cross_validation_policy.json"
    @test Bool(input[:exists])
    @test Bool(input[:schema_matches])
    @test Bool(input[:summary_passed])
    @test String(input[:sha256]) ==
        file_sha256(joinpath(root, String(input[:path])))

    criteria = fixture[:review_criteria]
    @test length(criteria) == 6
    @test Set(String(row[:criterion]) for row in criteria) == Set([
        "construct_map_trace",
        "item_rubric_alignment",
        "dimension_label_consistency",
        "expected_response_process",
        "local_dependence_or_method_risk",
        "reviewer_agreement",
    ])
    @test all(row -> Bool(row[:required]), criteria)

    rows = fixture[:construct_review_rows]
    @test length(rows) == 2
    @test Set(String(row[:scenario]) for row in rows) == Set([
        "missing_loading_candidate_cv_supported_manual_gate",
        "extra_loading_candidate_cv_supported_manual_gate",
    ])
    @test all(row -> Bool(row[:source_cv][:cv_supported]), rows)
    @test all(row -> Bool(row[:construct_review_completed]) &&
        Bool(row[:construct_review_supported]) &&
        String(row[:decision]) ==
            "construct_validity_supported_manual_local_candidate" &&
        Bool(row[:manual_local_q_revision_candidate_allowed]) &&
        Bool(row[:public_revision_allowed]) == false &&
        Bool(row[:automatic_revision_allowed]) == false &&
        Bool(row[:public_claim_allowed]) == false &&
        Bool(row[:summary][:passed]) &&
        Bool(row[:summary][:manual_local_only]) &&
        length(row[:criterion_results]) == length(criteria) &&
        all(result -> String(result[:status]) == "passed",
            row[:criterion_results]) &&
        length(row[:reviewer_rows]) == 2,
        rows)

    excluded = fixture[:excluded_candidate_rows]
    @test length(excluded) == 3
    @test Set(String(row[:exclusion_reason]) for row in excluded) == Set([
        "declared_q_retained_no_revision_candidate",
        "candidate_rejected_by_cross_validation",
        "invalid_candidate_excluded_before_cv",
    ])
    @test all(row -> Bool(row[:construct_review_completed]) == false &&
        Bool(row[:public_revision_allowed]) == false &&
        Bool(row[:automatic_revision_allowed]) == false &&
        Bool(row[:public_claim_allowed]) == false,
        excluded)

    reviewer_rows = fixture[:reviewer_rows]
    @test length(reviewer_rows) == 4
    @test Set(String(row[:reviewer_role]) for row in reviewer_rows) == Set([
        "rubric_content_reviewer",
        "measurement_model_reviewer",
    ])
    @test all(row -> String(row[:review_material]) ==
        "synthetic_rubric_trace_fixture" &&
        String(row[:decision]) == "support_manual_local_candidate" &&
        Int(row[:unresolved_concerns]) == 0,
        reviewer_rows)

    decision = fixture[:decision_record]
    @test Bool(decision[:construct_validity_manual_review_recorded])
    @test Bool(decision[:construct_validity_manual_review_completed])
    @test Bool(decision[:candidate_suggestions_allowed])
    @test Bool(decision[:manual_local_q_revision_candidates_allowed])
    @test Bool(decision[:automatic_q_revision_allowed]) == false
    @test Bool(decision[:public_q_revision_claim_allowed]) == false
    @test Bool(decision[:public_q_revision_allowed]) == false
    @test String(decision[:required_followup]) ==
        "guarded_local_mgmfrm_fit_entrypoint"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:q_revision_cross_validation_policy_passed])
    @test Bool(summary[:supported_candidates_available])
    @test Bool(summary[:all_supported_candidates_reviewed])
    @test Bool(summary[:non_supported_candidates_not_reviewed_as_revisions])
    @test Bool(summary[:all_construct_map_evidence_recorded])
    @test Bool(summary[:all_item_rubric_alignment_recorded])
    @test Bool(summary[:all_dimension_label_consistency_recorded])
    @test Bool(summary[:all_expected_response_process_recorded])
    @test Bool(summary[:all_local_dependence_risk_checked])
    @test Bool(summary[:reviewer_agreement_recorded])
    @test Bool(summary[:construct_validity_manual_review_completed])
    @test Bool(summary[:construct_validity_supported_for_all_reviewed])
    @test Bool(summary[:supported_candidates_remain_manual_local_only])
    @test Bool(summary[:no_automatic_q_revision])
    @test Bool(summary[:no_public_q_revision_claim])
    @test Int(summary[:n_reference_records]) == 5
    @test Int(summary[:n_review_criteria]) == length(criteria)
    @test Int(summary[:n_cv_supported_candidates]) == 2
    @test Int(summary[:n_construct_review_rows]) == length(rows)
    @test Int(summary[:n_construct_supported_candidates]) == 2
    @test Int(summary[:n_excluded_candidate_rows]) == length(excluded)
    @test Int(summary[:n_reviewer_rows]) == length(reviewer_rows)
    @test Int(summary[:n_public_revisions_allowed]) == 0
    @test Int(summary[:n_automatic_revisions_allowed]) == 0
    @test Int(summary[:n_blockers]) == 0
    @test isempty(summary[:remaining_public_blockers])
    @test String(summary[:recommendation]) ==
        "use_construct_reviewed_q_candidates_as_local_manual_inputs_only"
    @test String(summary[:next_gate]) == "guarded_local_mgmfrm_fit_entrypoint"
end

function check_mgmfrm_guarded_local_fit_entrypoint_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_guarded_local_fit_entrypoint.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) ==
        "construct_reviewed_q_guarded_local_fit_entrypoint"
    @test String(fixture[:status]) ==
        "guarded_local_fit_entrypoint_recorded"
    @test String(fixture[:decision]) ==
        "enable_construct_reviewed_q_candidates_for_manual_local_guarded_fit"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])
    @test Bool(fixture[:local_only])
    @test Bool(fixture[:dry_run_only])
    @test Bool(fixture[:q_revision_public]) == false
    @test Bool(fixture[:automatic_q_revision]) == false
    @test Bool(fixture[:broader_mgmfrm_claim]) == false
    @test Bool(fixture[:publication_or_registration_action]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) ==
        "mgmfrm_guarded_local_fit_entrypoint_v1"
    @test String(protocol[:review_kind]) ==
        "local_construct_reviewed_q_candidate_fit_entrypoint"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test Bool(protocol[:local_only])
    @test Bool(protocol[:dry_run_only])
    @test String(protocol[:entrypoint]) == "fit(spec; experimental = true)"
    @test String(protocol[:candidate_source]) ==
        "construct_reviewed_q_revision_candidates"
    @test String(protocol[:fit_controls][:backend]) == "advancedhmc"
    @test String(protocol[:fit_controls][:sampler]) == "nuts"
    @test Int(protocol[:fit_controls][:chains]) == 1
    @test Int(protocol[:fit_controls][:warmup]) == 0
    @test Int(protocol[:fit_controls][:draws]) == 1
    @test Bool(thresholds[
        :require_q_revision_construct_validity_review_passed])
    @test Bool(thresholds[:require_guarded_fit_api_dry_run_passed])
    @test Bool(thresholds[
        :require_construct_reviewed_candidates_available])
    @test Bool(thresholds[
        :require_all_construct_reviewed_candidates_checked])
    @test Bool(thresholds[:require_all_candidate_q_validations_passed])
    @test Bool(thresholds[:require_all_candidate_specs_previewed])
    @test Bool(thresholds[:require_non_experimental_fit_rejection])
    @test Bool(thresholds[:require_unsupported_backend_rejection])
    @test Bool(thresholds[
        :require_all_guarded_fit_attempts_succeeded])
    @test Bool(thresholds[:require_fit_outputs_finite])
    @test Bool(thresholds[
        :require_all_candidates_remain_manual_local_only])
    @test Bool(thresholds[:require_no_automatic_q_revision])
    @test Bool(thresholds[:require_no_public_q_revision_claim])
    @test Bool(thresholds[:require_no_broader_mgmfrm_claim])
    @test Bool(thresholds[
        :require_no_publication_or_registration_action])

    input_artifacts = fixture[:input_artifacts]
    expected_paths = Dict(
        "q_revision_construct_validity_review" =>
            "test/fixtures/mgmfrm_q_revision_construct_validity_review.json",
        "guarded_fit_api_dry_run" =>
            "test/fixtures/mgmfrm_guarded_fit_api_dry_run.json",
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
        check_generated_fixture_reference(
            root,
            String(row[:path]),
            String(row[:sha256]),
        )
    end

    rows = fixture[:fit_entrypoint_rows]
    @test length(rows) == 2
    @test Set(String(row[:scenario]) for row in rows) == Set([
        "missing_loading_candidate_cv_supported_manual_gate",
        "extra_loading_candidate_cv_supported_manual_gate",
    ])
    @test all(row -> Bool(row[:construct_review_supported]) &&
        Bool(row[:manual_local_q_revision_candidate_allowed]) &&
        Bool(row[:public_revision_allowed]) == false &&
        Bool(row[:automatic_revision_allowed]) == false &&
        Bool(row[:public_claim_allowed]) == false,
        rows)
    for row in rows
        @test Bool(row[:q_validation][:passed])
        @test Bool(row[:q_validation][:fixed_q_confirmatory])
        @test Int(row[:q_validation][:n_error_rows]) == 0
        @test Int(row[:q_validation][:n_duplicate_dimension_groups]) == 0
        @test Int(row[:q_validation][
            :n_dimension_facet_subgraphs_disconnected]) == 0
        @test Bool(row[:preview_summary][:design_preview_succeeded])
        @test String(row[:preview_summary][:spec_estimation_status]) ==
            "specified_only"
        @test Bool(row[:preview_summary][:fit_ready_layout_available])
        boundary = row[:boundary_checks]
        @test length(boundary) == 2
        @test all(check -> Bool(check[:passed]) &&
            String(check[:actual_status]) == "rejected" &&
            Bool(check[:rejected]) &&
            String(check[:error_type]) == "ArgumentError",
            boundary)
        fit = row[:guarded_fit][:summary]
        @test Bool(row[:guarded_fit][:succeeded])
        @test String(fit[:returned_type]) == "MGMFRMFit"
        @test String(fit[:backend]) == "advancedhmc"
        @test String(fit[:sampler]) == "nuts"
        @test Int(fit[:n_observations]) == 18
        @test Int(fit[:n_items]) == 3
        @test Int(fit[:n_dimensions]) == 2
        @test Int(fit[:n_draws]) == 1
        @test Int(fit[:n_pointwise_observations]) == 18
        @test Bool(fit[:finite_log_posterior])
        @test Bool(fit[:finite_raw_draws])
        @test Bool(fit[:finite_direct_draws])
        @test Bool(fit[:finite_direct_loglikelihood])
        @test Bool(fit[:finite_pointwise_loglikelihood])
        @test Bool(fit[:output_finite])
        @test String(fit[:diagnostic_flag]) == "insufficient_chains"
        @test Int(fit[:n_nonfinite_logdensity]) == 0
        @test Int(fit[:n_nonfinite_direct_loglikelihood]) == 0
        @test Int(fit[:n_failed_direct_constraints]) == 0
        @test Int(fit[:n_divergences]) == 0
        @test Int(fit[:n_max_treedepth]) == 0
        @test Bool(row[:summary][:passed])
        @test Bool(row[:summary][:q_validation_passed])
        @test Bool(row[:summary][:spec_previewed])
        @test Bool(row[:summary][:non_experimental_fit_rejected])
        @test Bool(row[:summary][:unsupported_backend_rejected])
        @test Bool(row[:summary][:guarded_fit_attempt_succeeded])
        @test Bool(row[:summary][:fit_outputs_finite])
        @test Bool(row[:summary][:manual_local_only])
    end
    add_loading = only(row for row in rows
        if String(row[:scenario]) ==
            "missing_loading_candidate_cv_supported_manual_gate")
    @test String(add_loading[:operation]) == "add_loading"
    @test Int(add_loading[:q_validation][:n_warning_rows]) == 1
    @test String.(add_loading[:q_validation][:warning_checks]) ==
        ["cross_loading_policy"]
    @test Int(add_loading[:q_validation][:n_cross_loading_items]) == 1
    @test Int(add_loading[:guarded_fit][:summary][:n_raw_parameters]) == 18
    @test Int(add_loading[:guarded_fit][:summary][:n_direct_parameters]) == 20
    drop_loading = only(row for row in rows
        if String(row[:scenario]) ==
            "extra_loading_candidate_cv_supported_manual_gate")
    @test String(drop_loading[:operation]) == "drop_loading"
    @test Int(drop_loading[:q_validation][:n_warning_rows]) == 0
    @test Int(drop_loading[:q_validation][:n_cross_loading_items]) == 0
    @test Int(drop_loading[:guarded_fit][:summary][:n_raw_parameters]) == 17
    @test Int(drop_loading[:guarded_fit][:summary][:n_direct_parameters]) == 19

    decision = fixture[:decision_record]
    @test Bool(decision[:local_guarded_fit_entrypoint_recorded])
    @test Bool(decision[
        :construct_reviewed_q_candidates_can_be_fit_locally])
    @test Bool(decision[:manual_local_q_revision_candidates_allowed])
    @test Bool(decision[:automatic_q_revision_allowed]) == false
    @test Bool(decision[:public_q_revision_claim_allowed]) == false
    @test Bool(decision[:broader_mgmfrm_claim_allowed]) == false
    @test String(decision[:required_followup]) ==
        "construct_reviewed_q_fit_reporting_policy"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:local_only])
    @test Bool(summary[:dry_run_only])
    @test Bool(summary[:all_input_artifacts_present])
    @test Bool(summary[:all_expected_schemas])
    @test Bool(summary[:all_input_summaries_passed])
    @test Bool(summary[:q_revision_construct_validity_review_passed])
    @test Bool(summary[:guarded_fit_api_dry_run_passed])
    @test Bool(summary[:construct_reviewed_candidates_available])
    @test Bool(summary[:all_construct_reviewed_candidates_checked])
    @test Bool(summary[:all_candidate_q_validations_passed])
    @test Bool(summary[:all_candidate_specs_previewed])
    @test Bool(summary[:non_experimental_fit_rejected])
    @test Bool(summary[:unsupported_backend_rejected])
    @test Bool(summary[:all_guarded_fit_attempts_succeeded])
    @test Bool(summary[:fit_outputs_finite])
    @test Bool(summary[:all_candidates_remain_manual_local_only])
    @test Bool(summary[:no_automatic_q_revision])
    @test Bool(summary[:no_public_q_revision_claim])
    @test Bool(summary[:no_broader_mgmfrm_claim])
    @test Int(summary[:n_input_artifacts]) == length(input_artifacts)
    @test Int(summary[:n_construct_reviewed_candidates]) == 2
    @test Int(summary[:n_fit_entrypoint_rows]) == length(rows)
    @test Int(summary[:n_guarded_fit_attempts]) == length(rows)
    @test Int(summary[:n_successful_guarded_fit_attempts]) == length(rows)
    @test Int(summary[:n_fit_rejection_checks]) == 4
    @test Int(summary[:n_candidate_q_validation_warnings]) == 1
    @test Int(summary[:n_public_revisions_allowed]) == 0
    @test Int(summary[:n_automatic_revisions_allowed]) == 0
    @test Int(summary[:n_public_claims_allowed]) == 0
    @test Int(summary[:n_blockers]) == 0
    @test isempty(summary[:remaining_public_blockers])
    @test String(summary[:recommendation]) ==
        "use_construct_reviewed_q_candidates_for_manual_local_guarded_fit_only"
    @test String(summary[:next_gate]) ==
        "construct_reviewed_q_fit_reporting_policy"
end

function check_mgmfrm_fit_metric_threshold_sensitivity_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_fit_metric_threshold_sensitivity.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) ==
        "construct_reviewed_q_fit_metric_threshold_sensitivity"
    @test String(fixture[:status]) ==
        "fit_metric_threshold_sensitivity_recorded"
    @test String(fixture[:decision]) ==
        "record_metric_threshold_sensitivity_keep_reporting_policy_local_only"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])
    @test Bool(fixture[:local_only])
    @test Bool(fixture[:q_revision_public]) == false
    @test Bool(fixture[:automatic_q_revision]) == false
    @test Bool(fixture[:public_fit_metric_claim]) == false
    @test Bool(fixture[:publication_or_registration_action]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) ==
        "mgmfrm_fit_metric_threshold_sensitivity_v1"
    @test String(protocol[:review_kind]) ==
        "local_construct_reviewed_q_fit_metric_threshold_sensitivity"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test Bool(protocol[:local_only])
    @test String(protocol[:entrypoint]) == "fit(spec; experimental = true)"
    @test String(protocol[:existing_model_fit_surface]) ==
        "mfrm_fit_stats_infit_outfit"
    @test Int(protocol[:sampler][:chains]) == 1
    @test Int(protocol[:sampler][:draws]) == 4
    @test Int(protocol[:sampler][:warmup]) == 0
    @test Int(protocol[:mfrm_baseline_sampler][:chains]) == 2
    @test Int(protocol[:mfrm_baseline_sampler][:draws]) == 4
    @test Bool(thresholds[
        :require_q_revision_construct_validity_review_passed])
    @test Bool(thresholds[:require_guarded_local_fit_entrypoint_passed])
    @test Bool(thresholds[:require_reference_records_public_only])
    @test Bool(thresholds[:require_threshold_profiles_recorded])
    @test Bool(thresholds[:require_simulation_regimes_recorded])
    @test Bool(thresholds[:require_all_mgmfrm_fit_pairs_succeeded])
    @test Bool(thresholds[:require_all_fit_metric_values_finite])
    @test Bool(thresholds[:require_mfrm_baseline_mean_square_recorded])
    @test Bool(thresholds[:require_existing_model_comparison_recorded])
    @test Bool(thresholds[:require_parameter_shift_recorded])
    @test Bool(thresholds[:require_no_single_threshold_profile_promoted])
    @test Bool(thresholds[:require_no_mcmc_convergence_claim])
    @test Bool(thresholds[:require_no_automatic_q_revision])
    @test Bool(thresholds[:require_no_public_q_revision_claim])
    @test Bool(thresholds[:require_no_public_fit_metric_claim])

    input_artifacts = fixture[:input_artifacts]
    expected_inputs = Dict(
        "q_revision_construct_validity_review" =>
            "test/fixtures/mgmfrm_q_revision_construct_validity_review.json",
        "guarded_local_fit_entrypoint" =>
            "test/fixtures/mgmfrm_guarded_local_fit_entrypoint.json",
    )
    @test length(input_artifacts) == length(expected_inputs)
    @test Set(String(row[:artifact]) for row in input_artifacts) ==
        Set(keys(expected_inputs))
    for row in input_artifacts
        artifact = String(row[:artifact])
        @test expected_inputs[artifact] == String(row[:path])
        @test Bool(row[:exists])
        @test Bool(row[:schema_matches])
        @test Bool(row[:summary_passed])
        check_generated_fixture_reference(
            root,
            String(row[:path]),
            String(row[:sha256]),
        )
    end

    references = fixture[:reference_records]
    @test length(references) == 7
    @test all(row -> !(:item_key in keys(row)), references)
    @test Set(String(row[:source]) for row in references) == Set(["doi", "url"])
    @test Set(String(row[:doi]) for row in references if !isnothing(row[:doi])) ==
        Set([
            "10.1007/s11222-016-9696-4",
            "10.1214/20-BA1221",
            "10.1177/0146621605285517",
            "10.1177/0146621616677520",
        ])
    @test all(row -> startswith(String(row[:url]), "http"), references)

    profiles = fixture[:threshold_profiles]
    @test length(profiles) == 4
    @test Set(String(row[:profile]) for row in profiles) == Set([
        "strict_bayesian_workflow",
        "screening_workflow",
        "exploratory_rasch_lenient",
        "sample_size_mean_square",
    ])
    @test any(row -> String(row[:mean_square_rule]) == "sample_size",
        profiles)
    regimes = fixture[:simulation_regimes]
    @test length(regimes) == 3
    @test Set(String(row[:regime]) for row in regimes) == Set([
        "balanced_reference",
        "item3_secondary_dimension_signal",
        "rater_method_noise",
    ])

    mfrm_metrics = fixture[:mfrm_metric_rows]
    mfrm_stats = fixture[:mfrm_fit_stat_rows]
    mfrm_thresholds = fixture[:mfrm_threshold_evaluation_rows]
    mgmfrm_rows = fixture[:mgmfrm_fit_rows]
    mgmfrm_thresholds = fixture[:mgmfrm_threshold_evaluation_rows]
    shifts = fixture[:parameter_shift_rows]
    comparisons = fixture[:metric_comparison_rows]
    existing = fixture[:existing_model_comparison_rows]
    @test length(mfrm_metrics) == 3
    @test length(mfrm_stats) == 9
    @test length(mfrm_thresholds) == 12
    @test length(mgmfrm_rows) == 12
    @test length(mgmfrm_thresholds) == 48
    @test length(shifts) == 6
    @test length(comparisons) == 6
    @test length(existing) == 12
    @test all(row -> Bool(row[:finite_metric_surface]), mfrm_metrics)
    @test all(row -> Bool(row[:finite_metric_surface]), mgmfrm_rows)
    @test all(row -> Int(row[:n_observations]) == 18, mgmfrm_rows)
    @test all(row -> Int(row[:n_draws]) == 4, mgmfrm_rows)
    @test all(row -> Bool(row[:diagnostic_summary][
        :mcmc_convergence_claim_allowed]) == false, mgmfrm_rows)
    @test all(row -> String(row[:reporting_blocker]) ==
        "short_local_fit_no_mcmc_convergence_claim", mgmfrm_thresholds)
    @test any(row -> Int(row[:n_metric_flags]) > 0, mgmfrm_thresholds)
    @test all(row -> Int(row[:n_common_direct_parameters]) > 0, shifts)
    @test all(row -> Float64(row[:mean_abs_common_direct_parameter_shift]) >= 0,
        shifts)
    @test all(row -> String(row[:interpretation]) ==
        "local_diagnostic_only_not_q_revision_evidence", comparisons)
    @test all(row -> String(row[:interpretation]) ==
        "existing_model_reference_only_not_model_superiority_claim", existing)

    decision = fixture[:decision_record]
    @test Bool(decision[:existing_mfrm_fit_stats_used_as_reference])
    @test Bool(decision[:mgmfrm_infit_outfit_directly_supported]) == false
    @test Bool(decision[:mgmfrm_waic_loo_ppc_calibration_recorded])
    @test Bool(decision[:mcmc_convergence_claim_allowed]) == false
    @test Bool(decision[:automatic_q_revision_allowed]) == false
    @test Bool(decision[:public_q_revision_claim_allowed]) == false
    @test Bool(decision[:public_fit_metric_claim_allowed]) == false
    @test String(decision[:required_followup]) ==
        "construct_reviewed_q_fit_reporting_policy"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:local_only])
    @test Bool(summary[:all_input_artifacts_present])
    @test Bool(summary[:all_expected_schemas])
    @test Bool(summary[:all_input_summaries_passed])
    @test Bool(summary[:q_revision_construct_validity_review_passed])
    @test Bool(summary[:guarded_local_fit_entrypoint_passed])
    @test Bool(summary[:reference_records_public_only])
    @test Int(summary[:n_reference_records]) == length(references)
    @test Int(summary[:n_threshold_profiles]) == length(profiles)
    @test Int(summary[:n_simulation_regimes]) == length(regimes)
    @test Int(summary[:n_construct_reviewed_candidates]) == 2
    @test Int(summary[:n_mfrm_baseline_fit_objects]) == length(mfrm_metrics)
    @test Int(summary[:n_mfrm_fit_stat_rows]) == length(mfrm_stats)
    @test Int(summary[:n_mfrm_threshold_evaluation_rows]) ==
        length(mfrm_thresholds)
    @test Int(summary[:n_mgmfrm_fit_pairs]) == 6
    @test Int(summary[:n_mgmfrm_fit_objects]) == length(mgmfrm_rows)
    @test Int(summary[:n_mgmfrm_threshold_evaluation_rows]) ==
        length(mgmfrm_thresholds)
    @test Int(summary[:n_parameter_shift_rows]) == length(shifts)
    @test Int(summary[:n_metric_comparison_rows]) == length(comparisons)
    @test Int(summary[:n_existing_model_comparison_rows]) == length(existing)
    @test Int(summary[:n_fit_metric_evidence_cells]) == 78
    @test Bool(summary[:all_mgmfrm_fit_pairs_succeeded])
    @test Bool(summary[:all_fit_metric_values_finite])
    @test Bool(summary[:all_parameter_shift_values_finite])
    @test Bool(summary[:threshold_profiles_change_at_least_one_flag])
    @test Bool(summary[:mfrm_baseline_mean_square_recorded])
    @test Bool(summary[:existing_model_comparison_recorded])
    @test Bool(summary[:parameter_shift_recorded])
    @test Bool(summary[:infit_outfit_mgmfrm_directly_supported]) == false
    @test Bool(summary[:no_single_threshold_profile_promoted])
    @test Bool(summary[:no_mcmc_convergence_claim])
    @test Bool(summary[:no_automatic_q_revision])
    @test Bool(summary[:no_public_q_revision_claim])
    @test Bool(summary[:no_public_fit_metric_claim])
    @test Bool(summary[:public_fit_metric_claim_allowed]) == false
    @test Int(summary[:n_blockers]) == 0
    @test isempty(summary[:remaining_public_blockers])
    @test String(summary[:recommendation]) ==
        "report_metric_sensitivity_as_local_diagnostic_appendix_only"
    @test String(summary[:next_gate]) ==
        "construct_reviewed_q_fit_reporting_policy"
end

function check_mgmfrm_construct_reviewed_q_fit_reporting_policy_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_construct_reviewed_q_fit_reporting_policy.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) ==
        "construct_reviewed_q_fit_reporting_policy"
    @test String(fixture[:status]) ==
        "construct_reviewed_q_fit_reporting_policy_recorded"
    @test String(fixture[:decision]) ==
        "keep_fit_metrics_local_report_threshold_sensitivity_only"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])
    @test Bool(fixture[:local_only])
    @test Bool(fixture[:public_fit_metric_claim]) == false
    @test Bool(fixture[:public_q_revision_claim]) == false
    @test Bool(fixture[:automatic_q_revision]) == false
    @test Bool(fixture[:publication_or_registration_action]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) ==
        "mgmfrm_construct_reviewed_q_fit_reporting_policy_v1"
    @test String(protocol[:review_kind]) ==
        "local_construct_reviewed_q_fit_reporting_policy"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test Bool(protocol[:local_only])
    @test String(protocol[:decision_target]) ==
        "construct_reviewed_q_fit_reporting_policy"
    @test String(protocol[:policy_scope]) == "local_diagnostic_appendix_only"
    @test Bool(thresholds[:require_fit_metric_threshold_sensitivity_passed])
    @test Bool(thresholds[:require_threshold_profile_decision_surface])
    @test Bool(thresholds[
        :require_candidate_declared_indicator_conflicts_recorded])
    @test Bool(thresholds[:require_existing_mfrm_reference_comparison_recorded])
    @test Bool(thresholds[:require_parameter_shift_impact_recorded])
    @test Bool(thresholds[:require_no_single_threshold_profile_promoted])
    @test Bool(thresholds[:require_no_automatic_q_revision])
    @test Bool(thresholds[:require_no_public_q_revision_claim])
    @test Bool(thresholds[:require_no_public_fit_metric_claim])

    inputs = fixture[:input_artifacts]
    @test length(inputs) == 1
    input = only(inputs)
    @test String(input[:artifact]) == "mgmfrm_fit_metric_threshold_sensitivity"
    @test String(input[:path]) ==
        "test/fixtures/mgmfrm_fit_metric_threshold_sensitivity.json"
    @test Bool(input[:exists])
    @test Bool(input[:schema_matches])
    @test Bool(input[:summary_passed])
    @test String(input[:next_gate]) ==
        "construct_reviewed_q_fit_reporting_policy"
    @test String(input[:sha256]) ==
        file_sha256(joinpath(root, String(input[:path])))

    profile_rows = fixture[:threshold_profile_decision_rows]
    @test length(profile_rows) == 4
    @test Set(String(row[:profile]) for row in profile_rows) == Set([
        "strict_bayesian_workflow",
        "screening_workflow",
        "exploratory_rasch_lenient",
        "sample_size_mean_square",
    ])
    @test all(row -> Int(row[:n_mfrm_threshold_rows]) == 3,
        profile_rows)
    @test all(row -> Int(row[:n_mgmfrm_threshold_rows]) == 12,
        profile_rows)
    @test all(row -> Bool(row[:mgmfrm_decision_is_threshold_sensitive]),
        profile_rows)
    strict_profile = only(row for row in profile_rows
                          if String(row[:profile]) == "strict_bayesian_workflow")
    exploratory_profile = only(row for row in profile_rows
                               if String(row[:profile]) ==
                                  "exploratory_rasch_lenient")
    @test Int(strict_profile[:n_mfrm_profile_failures]) == 3
    @test Int(strict_profile[:n_mgmfrm_metric_profile_passes_without_mcmc]) == 0
    @test Int(strict_profile[:n_mgmfrm_metric_profile_failures_without_mcmc]) ==
        Int(strict_profile[:n_mgmfrm_threshold_rows])
    @test Float64(strict_profile[:mean_mgmfrm_metric_flags]) >
        Float64(exploratory_profile[:mean_mgmfrm_metric_flags])
    @test Int(exploratory_profile[
        :n_mgmfrm_metric_profile_passes_without_mcmc]) == 3

    scenario_rows = fixture[:scenario_impact_rows]
    @test length(scenario_rows) == 6
    @test all(row -> Int(row[:n_common_direct_parameters]) == 19,
        scenario_rows)
    @test all(row -> String(row[:parameter_shift_band]) ==
        "moderate_local_shift", scenario_rows)
    @test any(row -> String(row[:predictive_direction]) ==
        "candidate_lower_waic_and_looic", scenario_rows)
    @test any(row -> String(row[:predictive_direction]) ==
        "declared_lower_waic_and_looic", scenario_rows)
    @test all(row -> Int(row[:n_common_direct_parameters_shifted_gt_0_25]) == 0,
        scenario_rows)
    @test all(row -> String(row[:q_revision_implication]) ==
        "manual_construct_review_only_not_automatic_q_revision", scenario_rows)

    conflict_rows = fixture[:indicator_conflict_rows]
    @test length(conflict_rows) == length(scenario_rows)
    @test count(row -> Int(row[:n_indicator_pair_conflicts]) > 0,
        conflict_rows) == 5
    @test any(row -> String(row[:conflict_level]) == "none", conflict_rows)
    @test all(row -> String(row[:reporting_decision]) ==
        "report_conflict_matrix_not_single_fit_decision", conflict_rows)

    existing_rows = fixture[:existing_model_reference_rows]
    @test length(existing_rows) == 12
    @test Set(String(row[:current_model]) for row in existing_rows) == Set([
        "declared_q",
        "construct_reviewed_candidate_q",
    ])
    @test all(row -> String(row[:reference_role]) ==
        "existing_mfrm_reference_only_not_model_superiority_claim",
        existing_rows)

    policy_rows = fixture[:reporting_policy_rows]
    @test length(policy_rows) == 6
    @test Set(String(row[:surface]) for row in policy_rows) == Set([
        "mfrm_infit_outfit",
        "mgmfrm_waic_loo",
        "mgmfrm_ppc_calibration",
        "direct_parameter_shift",
        "q_revision",
        "single_fit_threshold",
    ])
    @test all(row -> Bool(row[:public_claim_allowed]) == false, policy_rows)
    @test any(row -> String(row[:surface]) == "single_fit_threshold" &&
        String(row[:reporting_role]) == "not_promoted", policy_rows)

    decision = fixture[:decision_record]
    @test String(decision[:selected_decision]) ==
        "keep_fit_metrics_local_report_threshold_sensitivity_only"
    @test Bool(decision[:existing_mfrm_fit_stats_used_as_reference])
    @test Bool(decision[:candidate_declared_indicator_conflicts_recorded])
    @test Bool(decision[:parameter_shift_impact_recorded])
    @test Bool(decision[:mcmc_convergence_claim_allowed]) == false
    @test Bool(decision[:automatic_q_revision_allowed]) == false
    @test Bool(decision[:public_q_revision_claim_allowed]) == false
    @test Bool(decision[:public_fit_metric_claim_allowed]) == false
    @test String(decision[:required_followup]) ==
        "heldout_prediction_or_external_validation_before_claims"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:local_only])
    @test Bool(summary[:all_input_artifacts_present])
    @test Bool(summary[:all_expected_schemas])
    @test Bool(summary[:all_input_summaries_passed])
    @test Bool(summary[:fit_metric_threshold_sensitivity_passed])
    @test Bool(summary[:input_next_gate_matched])
    @test Bool(summary[:threshold_profile_surface_recorded])
    @test Bool(summary[:indicator_conflicts_recorded])
    @test Bool(summary[:existing_model_reference_recorded])
    @test Bool(summary[:parameter_shift_impact_recorded])
    @test Bool(summary[:all_policy_rows_block_public_claims])
    @test Bool(summary[:no_single_threshold_profile_promoted])
    @test Bool(summary[:no_automatic_q_revision])
    @test Bool(summary[:no_public_q_revision_claim])
    @test Bool(summary[:no_public_fit_metric_claim])
    @test Bool(summary[:public_fit_metric_claim_allowed]) == false
    @test Bool(summary[:public_q_revision_claim_allowed]) == false
    @test Int(summary[:n_input_artifacts]) == length(inputs)
    @test Int(summary[:n_threshold_profile_decision_rows]) ==
        length(profile_rows)
    @test Int(summary[:n_scenario_impact_rows]) == length(scenario_rows)
    @test Int(summary[:n_indicator_conflict_rows]) == length(conflict_rows)
    @test Int(summary[:n_existing_model_reference_rows]) == length(existing_rows)
    @test Int(summary[:n_reporting_policy_rows]) == length(policy_rows)
    @test Int(summary[:n_reporting_evidence_cells]) == 34
    @test Int(summary[:n_conflict_rows_with_conflicts]) == 5
    @test Int(summary[:n_moderate_or_larger_parameter_shift_rows]) == 6
    @test Int(summary[:n_blockers]) == 0
    @test isempty(summary[:remaining_public_blockers])
    @test String(summary[:recommendation]) ==
        "report_construct_reviewed_q_fit_metrics_as_local_appendix_only"
    @test String(summary[:next_gate]) ==
        "heldout_prediction_or_external_validation_before_claims"
end
