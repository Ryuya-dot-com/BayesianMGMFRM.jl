function check_mgmfrm_publication_grade_refit_sampler_remediation_review_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_publication_grade_refit_sampler_remediation_review.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) ==
        "publication_grade_refit_sampler_remediation_review"
    @test String(fixture[:status]) ==
        "publication_grade_refit_sampler_remediation_review_recorded"
    @test String(fixture[:decision]) ==
        "record_sampler_remediation_without_replacing_primary_pilot_result"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])
    @test Bool(fixture[:local_only])
    @test Bool(fixture[:pilot_only])
    @test Bool(fixture[:remediation_only])
    @test Bool(fixture[:local_artifacts_ignored_for_fixture])
    @test Bool(fixture[:publication_or_registration_action]) == false
    @test Bool(fixture[:public_fit_metric_claim]) == false
    @test Bool(fixture[:public_q_revision_claim]) == false
    @test Bool(fixture[:public_model_weight_claim]) == false
    @test Bool(fixture[:sparse_mgmfrm_superiority_claim]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) ==
        "mgmfrm_publication_grade_refit_sampler_remediation_review_v1"
    @test String(protocol[:review_kind]) ==
        "local_publication_grade_refit_sampler_remediation_review"
    @test String(protocol[:source_primary_review]) ==
        "mgmfrm_publication_grade_refit_pilot_results_review"
    @test String(protocol[:trigger_gate]) ==
        "review_sampler_diagnostic_failures_before_expand_batch"
    @test String(protocol[:remediation_scope]) ==
        "scalar_gmfrm_divergence_target_acceptance_escalation"
    @test Bool(thresholds[:require_primary_review_present])
    @test Bool(thresholds[:require_primary_review_passed])
    @test Bool(thresholds[:require_remediation_target_rows_recorded])
    @test Bool(thresholds[:require_missing_or_valid_remediation_artifacts])
    @test Bool(thresholds[:require_primary_pilot_results_preserved])
    @test Bool(thresholds[:require_remediation_descriptive_only])
    @test Bool(thresholds[:require_all_public_claims_blocked])
    @test Bool(thresholds[:require_no_publication_or_registration_action])

    inputs = fixture[:input_artifacts]
    @test length(inputs) == 1
    primary = only(inputs)
    @test String(primary[:artifact]) ==
        "mgmfrm_publication_grade_refit_pilot_results_review"
    @test String(primary[:path]) ==
        "test/fixtures/mgmfrm_publication_grade_refit_pilot_results_review.json"
    @test Bool(primary[:exists])
    @test Bool(primary[:schema_matches])
    @test Bool(primary[:summary_passed])
    @test String(primary[:sha256]) ==
        file_sha256(joinpath(root, String(primary[:path])))

    targets = fixture[:remediation_target_rows]
    @test length(targets) == 1
    target = only(targets)
    @test String(target[:remediation_id]) ==
        "well_specified_current_q__scalar_gmfrm_baseline__fold1__target_accept_0p90"
    @test String(target[:source_execution_unit_id]) ==
        "well_specified_current_q__scalar_gmfrm_baseline__fold1"
    @test String(target[:model]) == "scalar_gmfrm_baseline"
    @test String(target[:trigger_diagnostic]) == "divergence_count_max"
    @test Float64(target[:primary_target_acceptance]) == 0.8
    @test Float64(target[:remediation_target_acceptance]) == 0.9
    @test Int(target[:chains]) == 4
    @test Int(target[:warmup_per_chain]) == 500
    @test Int(target[:draws_per_chain]) == 1000
    @test Int(target[:seed]) == 2026375901
    @test occursin("--target-acceptance 0.9", String(target[:command]))
    @test endswith(String(target[:result_artifact_path]), "_result.json")
    @test Bool(target[:primary_result_replaced]) == false
    @test Bool(target[:public_claim_allowed]) == false

    rows = fixture[:remediation_review_rows]
    @test length(rows) == 1
    row = only(rows)
    @test String(row[:remediation_id]) == String(target[:remediation_id])
    @test Bool(row[:artifacts_complete]) == false
    @test Bool(row[:remediation_observed]) == false
    @test Bool(row[:diagnostic_gate_passed]) == false
    @test Bool(row[:primary_result_replaced]) == false
    @test Bool(row[:descriptive_only])
    @test Bool(row[:public_claim_allowed]) == false
    for key in (:result_artifact, :diagnostic_artifact, :heldout_artifact)
        artifact = row[key]
        @test Bool(artifact[:exists]) == false
        @test String(artifact[:status]) == "missing"
        @test Bool(artifact[:schema_matches]) == false
        @test Bool(artifact[:summary_passed]) == false
    end

    blockers = fixture[:blocker_rows]
    @test length(blockers) == 5
    @test all(blocker -> Bool(blocker[:resolved]) == false, blockers)

    decision = fixture[:decision_record]
    @test String(decision[:selected_decision]) ==
        "record_sampler_remediation_review_keep_primary_result"
    @test Bool(decision[:primary_pilot_results_reviewed])
    @test Bool(decision[:primary_sampler_diagnostic_failure_detected]) ==
        false
    @test Bool(decision[:remediation_success_observed]) == false
    @test Bool(decision[:primary_result_replaced]) == false
    @test Bool(decision[:public_fit_metric_claim_allowed]) == false
    @test Bool(decision[:public_model_weight_claim_allowed]) == false
    @test String(decision[:required_followup]) ==
        "execute_sampler_remediation_if_scalar_divergence_observed"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:local_only])
    @test Bool(summary[:pilot_only])
    @test Bool(summary[:remediation_only])
    @test Bool(summary[:local_artifacts_ignored_for_fixture])
    @test Bool(summary[:primary_review_present])
    @test Bool(summary[:primary_review_schema_matches])
    @test Bool(summary[:primary_review_passed])
    @test Bool(summary[:primary_sampler_diagnostic_failure_detected]) ==
        false
    @test Bool(summary[:remediation_target_rows_recorded])
    @test Bool(summary[:missing_or_valid_remediation_artifacts])
    @test Bool(summary[:all_expected_remediation_artifacts_present]) == false
    @test Bool(summary[:remediation_success_observed]) == false
    @test Bool(summary[:primary_result_preserved])
    @test Bool(summary[:no_public_fit_metric_claim])
    @test Bool(summary[:no_public_q_revision_claim])
    @test Bool(summary[:no_public_model_weight_claim])
    @test Bool(summary[:no_sparse_superiority_claim])
    @test Int(summary[:n_input_artifacts]) == 1
    @test Int(summary[:n_remediation_target_rows]) == 1
    @test Int(summary[:n_remediation_review_rows]) == 1
    @test Int(summary[:n_expected_remediation_artifacts]) == 3
    @test Int(summary[:n_present_remediation_artifacts]) == 0
    @test Int(summary[:n_valid_remediation_artifacts]) == 0
    @test Int(summary[:n_observed_remediation_units]) == 0
    @test Int(summary[:n_diagnostic_gate_passed_remediation_units]) == 0
    @test Int(summary[:n_blocker_rows]) == 5
    @test Int(summary[:n_blockers]) == 5
    @test String(summary[:recommendation]) ==
        "run_remediation_after_primary_sampler_failure_keep_claims_blocked"
    @test String(summary[:next_gate]) ==
        "execute_sampler_remediation_if_scalar_divergence_observed"
end

function check_mgmfrm_publication_grade_refit_brms_like_scalar_remediation_review_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_publication_grade_refit_brms_like_scalar_remediation_review.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) ==
        "publication_grade_refit_brms_like_scalar_remediation_review"
    @test String(fixture[:status]) ==
        "publication_grade_refit_brms_like_scalar_remediation_review_recorded"
    @test String(fixture[:decision]) ==
        "record_brms_like_scalar_target_acceptance_remediation"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:local_only])
    @test Bool(fixture[:pilot_only])
    @test Bool(fixture[:remediation_only])
    @test Bool(fixture[:local_artifacts_required_for_generation])
    @test Bool(fixture[:publication_or_registration_action]) == false
    @test Bool(fixture[:publication_grade_brms_like_pilot_executed])
    @test Bool(fixture[:full_125_unit_publication_grade_batch_completed]) ==
        false
    @test Bool(fixture[:public_fit_metric_claim]) == false
    @test Bool(fixture[:public_q_revision_claim]) == false
    @test Bool(fixture[:public_model_weight_claim]) == false
    @test Bool(fixture[:sparse_mgmfrm_superiority_claim]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) ==
        "mgmfrm_publication_grade_refit_brms_like_scalar_remediation_review_v1"
    @test String(protocol[:review_kind]) ==
        "local_brms_like_scalar_sampler_remediation_review"
    @test String(protocol[:source_runner]) ==
        "run_mgmfrm_publication_grade_refit_job"
    @test String(protocol[:source_pilot_review]) ==
        "mgmfrm_publication_grade_refit_brms_like_pilot_execution_review"
    @test String(protocol[:execution_unit_id]) ==
        "well_specified_current_q__scalar_gmfrm_baseline__fold1"
    @test String(protocol[:primary_artifact_suffix]) == "_4_1000_1000_ta080"
    @test String(protocol[:remediation_artifact_suffix]) ==
        "_4_1000_1000_ta090"
    @test Int(thresholds[:require_chains]) == 4
    @test Int(thresholds[:require_warmup_per_chain]) == 1000
    @test Int(thresholds[:require_draws_per_chain]) == 1000
    @test Int(thresholds[:require_total_retained_draws]) == 4000
    @test Float64(thresholds[:require_primary_target_acceptance]) == 0.8
    @test Float64(thresholds[:require_remediation_target_acceptance]) == 0.9
    @test Int(thresholds[:require_divergence_count_max]) == 0
    @test Float64(thresholds[:material_heldout_elpd_shift_threshold]) ==
        0.05
    @test Bool(thresholds[:require_primary_result_preserved])
    @test Bool(thresholds[:require_public_claims_blocked])

    review = fixture[:input_review_artifact]
    @test String(review[:artifact]) ==
        "mgmfrm_publication_grade_refit_brms_like_pilot_execution_review"
    @test String(review[:path]) ==
        "test/fixtures/mgmfrm_publication_grade_refit_brms_like_pilot_execution_review.json"
    @test Bool(review[:exists])
    @test Bool(review[:schema_matches])
    @test Bool(review[:summary_passed])
    @test Bool(review[:sampler_diagnostic_failure_detected])
    @test String(review[:sha256]) ==
        file_sha256(joinpath(root, String(review[:path])))

    inputs = fixture[:input_artifacts]
    @test length(inputs) == 6
    @test Set(String(row[:kind]) for row in inputs) == Set([
        "primary_result",
        "primary_diagnostics",
        "primary_heldout",
        "remediation_result",
        "remediation_diagnostics",
        "remediation_heldout",
    ])
    @test all(row -> Bool(row[:exists]), inputs)
    @test all(row -> Bool(row[:schema_matches]), inputs)
    @test all(row -> Bool(row[:summary_passed]), inputs)
    @test all(row -> Bool(row[:public_claim_allowed]) == false, inputs)
    @test all(row -> startswith(String(row[:path]),
        "artifacts/publication_grade_refit_pilot_brms_like/"), inputs)

    primary = fixture[:primary_scalar_summary]
    @test String(primary[:run_label]) == "primary_ta080"
    @test String(primary[:model]) == "scalar_gmfrm_baseline"
    @test Float64(primary[:target_acceptance]) == 0.8
    @test Int(primary[:chains]) == 4
    @test Int(primary[:warmup_per_chain]) == 1000
    @test Int(primary[:draws_per_chain]) == 1000
    @test Int(primary[:total_retained_draws]) == 4000
    @test Bool(primary[:diagnostic_gate_passed]) == false
    @test String(primary[:sampler_flag]) == "sampler_warning"
    @test Int(primary[:n_divergences]) == 2
    @test Float64(primary[:max_rhat]) <= 1.01
    @test Float64(primary[:min_ess]) >= 400.0
    @test Float64(primary[:e_bfmi]) >= 0.3
    @test Float64(primary[:heldout_elpd]) ≈ -10.163856267085027
    @test Bool(primary[:public_claim_allowed]) == false

    remediation = fixture[:remediated_scalar_summary]
    @test String(remediation[:run_label]) == "remediated_ta090"
    @test Float64(remediation[:target_acceptance]) == 0.9
    @test Int(remediation[:chains]) == 4
    @test Int(remediation[:warmup_per_chain]) == 1000
    @test Int(remediation[:draws_per_chain]) == 1000
    @test Int(remediation[:total_retained_draws]) == 4000
    @test Bool(remediation[:diagnostic_gate_passed])
    @test String(remediation[:sampler_flag]) == "ok"
    @test Int(remediation[:n_divergences]) == 0
    @test Float64(remediation[:max_rhat]) <= 1.01
    @test Float64(remediation[:min_ess]) >= 400.0
    @test Float64(remediation[:e_bfmi]) >= 0.3
    @test Float64(remediation[:heldout_elpd]) ≈ -10.15953696736171
    @test Bool(remediation[:public_claim_allowed]) == false

    comparison = fixture[:scalar_remediation_comparison_row]
    @test String(comparison[:comparison]) ==
        "primary_ta080_vs_remediated_ta090_scalar_gmfrm"
    @test Bool(comparison[:same_mcmc_budget])
    @test Bool(comparison[:primary_diagnostic_gate_passed]) == false
    @test Bool(comparison[:remediation_diagnostic_gate_passed])
    @test Int(comparison[:primary_n_divergences]) == 2
    @test Int(comparison[:remediation_n_divergences]) == 0
    @test Int(comparison[:delta_n_divergences_remediation_minus_primary]) ==
        -2
    @test Float64(comparison[:delta_heldout_elpd_remediation_minus_primary]) ≈
        0.004319299723317016
    @test Bool(comparison[:remediation_resolves_primary_divergence])
    @test Bool(comparison[:heldout_elpd_materially_changed]) == false
    @test Bool(comparison[:remediation_improves_heldout_elpd])
    @test Bool(comparison[:primary_result_replaced]) == false
    @test Bool(comparison[:descriptive_only])
    @test Bool(comparison[:public_claim_allowed]) == false

    policy = fixture[:batch_sampler_policy_row]
    @test String(policy[:policy]) ==
        "brms_like_publication_grade_scalar_sampler_setting"
    @test String(policy[:affected_model]) == "scalar_gmfrm_baseline"
    @test Float64(policy[:primary_target_acceptance]) == 0.8
    @test Float64(policy[:selected_batch_target_acceptance]) == 0.9
    @test Float64(policy[:default_non_scalar_target_acceptance]) == 0.8
    @test Int(policy[:selected_warmup_per_chain]) == 1000
    @test Int(policy[:selected_draws_per_chain]) == 1000
    @test String(policy[:selection_basis]) ==
        "local_brms_like_rerun_removed_scalar_divergences"
    @test Bool(policy[:primary_pilot_result_replaced]) == false
    @test Bool(policy[:batch_expansion_allowed_for_scalar_local_only])
    @test Bool(policy[:batch_expansion_allowed_for_public_claim]) == false
    @test Bool(policy[:requires_replication_across_folds])
    @test Bool(policy[:public_claim_allowed]) == false

    rows = fixture[:diagnostic_review_rows]
    @test length(rows) == 24
    @test count(row -> String(row[:run_label]) == "primary_ta080", rows) == 12
    @test count(row -> String(row[:run_label]) == "remediated_ta090", rows) ==
        12
    @test count(row -> Bool(row[:passed]) == false, rows) == 1
    failed = only(fixture[:failed_diagnostic_review_rows])
    @test String(failed[:run_label]) == "primary_ta080"
    @test String(failed[:diagnostic]) == "divergence_count_max"
    @test Int(failed[:value]) == 2
    @test Int(failed[:threshold]) == 0
    @test Bool(failed[:public_claim_allowed]) == false

    blockers = fixture[:blocker_rows]
    @test length(blockers) == 7
    @test count(row -> Bool(row[:resolved]), blockers) == 1
    @test String(only(row for row in blockers if Bool(row[:resolved]))[
        :blocker]) == "scalar_divergence_not_remediated"
    @test Set(String(row[:blocker]) for row in blockers
        if !Bool(row[:resolved])) == Set([
        "target_acceptance_policy_not_replicated_across_folds",
        "fit_metric_thresholds_not_reestimated_under_publication_grade_draws",
        "null_reference_best_heldout_score",
        "full_125_unit_publication_grade_batch_not_executed",
        "external_construct_dataset_missing",
        "independent_public_scope_review_missing",
    ])

    decision = fixture[:decision_record]
    @test String(decision[:selected_decision]) ==
        "use_target_acceptance_0p90_for_scalar_batch_local_only"
    @test Bool(decision[:primary_scalar_failure_reviewed])
    @test Bool(decision[:remediation_success_observed])
    @test Bool(decision[:same_mcmc_budget])
    @test Bool(decision[:primary_result_replaced]) == false
    @test Float64(decision[:scalar_batch_target_acceptance]) == 0.9
    @test Bool(decision[:scalar_batch_expansion_allowed_local_only])
    @test Bool(decision[:public_fit_metric_claim_allowed]) == false
    @test Bool(decision[:public_q_revision_claim_allowed]) == false
    @test Bool(decision[:public_model_weight_claim_allowed]) == false
    @test Bool(decision[:sparse_mgmfrm_superiority_claim_allowed]) == false
    @test String(decision[:required_followup]) ==
        "update_publication_grade_batch_plan_with_brms_like_scalar_target_acceptance_0p90"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:local_only])
    @test Bool(summary[:pilot_only])
    @test Bool(summary[:remediation_only])
    @test Bool(summary[:all_input_artifacts_valid])
    @test Bool(summary[:publication_grade_brms_like_pilot_executed])
    @test Bool(summary[:full_125_unit_publication_grade_batch_completed]) ==
        false
    @test Bool(summary[:primary_scalar_diagnostic_gate_passed]) == false
    @test Bool(summary[:remediated_scalar_diagnostic_gate_passed])
    @test Bool(summary[:primary_scalar_divergence_failure_recorded])
    @test Bool(summary[:remediation_success_observed])
    @test Bool(summary[:remediation_resolves_primary_divergence])
    @test Bool(summary[:same_mcmc_budget])
    @test Bool(summary[:heldout_elpd_materially_changed]) == false
    @test Bool(summary[:remediation_improves_heldout_elpd])
    @test Bool(summary[:primary_result_preserved])
    @test Float64(summary[:scalar_batch_target_acceptance]) == 0.9
    @test Bool(summary[:scalar_batch_expansion_allowed_local_only])
    @test Bool(summary[:scalar_batch_expansion_allowed_for_public_claim]) ==
        false
    @test Bool(summary[:no_public_claim_allowed])
    @test Int(summary[:primary_n_divergences]) == 2
    @test Int(summary[:remediation_n_divergences]) == 0
    @test Int(summary[:delta_n_divergences_remediation_minus_primary]) == -2
    @test Float64(summary[:delta_heldout_elpd_remediation_minus_primary]) ≈
        0.004319299723317016
    @test Int(summary[:n_input_artifacts]) == 6
    @test Int(summary[:n_diagnostic_review_rows]) == 24
    @test Int(summary[:n_failed_diagnostic_review_rows]) == 1
    @test Int(summary[:n_blocker_rows]) == 7
    @test Int(summary[:n_resolved_blockers]) == 1
    @test Int(summary[:n_blockers]) == 6
    @test String(summary[:recommendation]) ==
        "update_scalar_batch_policy_to_target_acceptance_0p90_keep_claims_blocked"
    @test String(summary[:next_gate]) ==
        "update_publication_grade_batch_plan_with_brms_like_scalar_target_acceptance_0p90"
end

function check_mgmfrm_publication_grade_refit_scalar_remediation_comparison_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_publication_grade_refit_scalar_remediation_comparison.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) ==
        "publication_grade_refit_scalar_remediation_comparison"
    @test String(fixture[:status]) ==
        "publication_grade_refit_scalar_remediation_comparison_recorded"
    @test String(fixture[:decision]) ==
        "record_scalar_remediation_comparison_before_batch_expansion"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])
    @test Bool(fixture[:local_only])
    @test Bool(fixture[:pilot_only])
    @test Bool(fixture[:remediation_only])
    @test Bool(fixture[:publication_or_registration_action]) == false
    @test Bool(fixture[:public_fit_metric_claim]) == false
    @test Bool(fixture[:public_q_revision_claim]) == false
    @test Bool(fixture[:public_model_weight_claim]) == false
    @test Bool(fixture[:sparse_mgmfrm_superiority_claim]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) ==
        "mgmfrm_publication_grade_refit_scalar_remediation_comparison_v1"
    @test String(protocol[:review_kind]) ==
        "local_publication_grade_scalar_remediation_comparison"
    @test String(protocol[:trigger_gate]) ==
        "review_remediated_scalar_against_primary_before_batch_expansion"
    @test String(protocol[:comparison_scope]) ==
        "primary_scalar_target_accept_0p80_vs_remediated_target_accept_0p90"
    @test String(protocol[:primary_execution_unit]) ==
        "well_specified_current_q__scalar_gmfrm_baseline__fold1"
    @test String(protocol[:remediation_id]) ==
        "well_specified_current_q__scalar_gmfrm_baseline__fold1__target_accept_0p90"
    @test Bool(thresholds[:require_primary_review_present])
    @test Bool(thresholds[:require_remediation_review_present])
    @test Bool(thresholds[:require_primary_scalar_row_recorded])
    @test Bool(thresholds[:require_remediation_scalar_row_recorded])
    @test Bool(thresholds[:require_primary_failure_or_pending_recorded])
    @test Bool(thresholds[:require_remediation_success_or_pending_recorded])
    @test Bool(thresholds[:require_primary_result_preserved])
    @test Bool(thresholds[:require_batch_sampler_policy_recorded])
    @test Bool(thresholds[:require_all_public_claims_blocked])
    @test Bool(thresholds[:require_no_publication_or_registration_action])

    inputs = fixture[:input_artifacts]
    expected_inputs = Dict(
        "mgmfrm_publication_grade_refit_pilot_results_review" =>
            "test/fixtures/mgmfrm_publication_grade_refit_pilot_results_review.json",
        "mgmfrm_publication_grade_refit_sampler_remediation_review" =>
            "test/fixtures/mgmfrm_publication_grade_refit_sampler_remediation_review.json",
    )
    @test length(inputs) == length(expected_inputs)
    @test Set(String(row[:artifact]) for row in inputs) ==
        Set(keys(expected_inputs))
    for row in inputs
        artifact = String(row[:artifact])
        @test String(row[:path]) == expected_inputs[artifact]
        @test Bool(row[:exists])
        @test Bool(row[:schema_matches])
        @test Bool(row[:summary_passed])
        @test String(row[:sha256]) ==
            file_sha256(joinpath(root, String(row[:path])))
    end

    primary = fixture[:scalar_primary_row]
    @test String(primary[:row_kind]) == "primary_scalar"
    @test String(primary[:execution_unit_id]) ==
        "well_specified_current_q__scalar_gmfrm_baseline__fold1"
    @test String(primary[:model]) == "scalar_gmfrm_baseline"
    @test Float64(primary[:target_acceptance]) == 0.8
    @test Bool(primary[:execution_observed]) == false
    @test Bool(primary[:diagnostic_gate_passed]) == false
    @test Bool(primary[:divergence_failure_recorded]) == false
    @test isnothing(primary[:n_divergences])
    @test Bool(primary[:primary_result_replaced]) == false
    @test Bool(primary[:descriptive_only])
    @test Bool(primary[:public_claim_allowed]) == false

    remediation = fixture[:scalar_remediation_row]
    @test String(remediation[:row_kind]) == "remediated_scalar"
    @test String(remediation[:remediation_id]) ==
        "well_specified_current_q__scalar_gmfrm_baseline__fold1__target_accept_0p90"
    @test String(remediation[:source_execution_unit_id]) ==
        "well_specified_current_q__scalar_gmfrm_baseline__fold1"
    @test Float64(remediation[:target_acceptance]) == 0.9
    @test Bool(remediation[:remediation_observed]) == false
    @test Bool(remediation[:diagnostic_gate_passed]) == false
    @test isnothing(remediation[:n_divergences])
    @test Bool(remediation[:primary_result_replaced]) == false
    @test Bool(remediation[:descriptive_only])
    @test Bool(remediation[:public_claim_allowed]) == false

    comparison = fixture[:scalar_comparison_row]
    @test String(comparison[:comparison]) ==
        "primary_scalar_vs_target_acceptance_remediation"
    @test Float64(comparison[:primary_target_acceptance]) == 0.8
    @test Float64(comparison[:remediation_target_acceptance]) == 0.9
    @test Bool(comparison[:primary_diagnostic_gate_passed]) == false
    @test Bool(comparison[:remediation_diagnostic_gate_passed]) == false
    @test Bool(comparison[:heldout_comparison_observed]) == false
    @test isnothing(comparison[:delta_heldout_elpd_remediation_minus_primary])
    @test Bool(comparison[:remediation_resolves_primary_divergence]) == false
    @test Bool(comparison[:remediation_improves_heldout_elpd]) == false
    @test Bool(comparison[:public_claim_allowed]) == false
    @test String(comparison[:interpretation]) ==
        "comparison_pending_local_artifacts"

    policy = fixture[:batch_sampler_policy_row]
    @test String(policy[:policy]) ==
        "publication_grade_batch_sampler_setting"
    @test String(policy[:affected_model]) == "scalar_gmfrm_baseline"
    @test Float64(policy[:primary_target_acceptance]) == 0.8
    @test isnothing(policy[:selected_batch_target_acceptance])
    @test Float64(policy[:fallback_batch_target_acceptance]) == 0.9
    @test String(policy[:selection_basis]) ==
        "await_local_remediation_before_batch_expansion"
    @test Bool(policy[:primary_pilot_result_replaced]) == false
    @test Bool(policy[:batch_expansion_allowed_for_scalar]) == false
    @test Bool(policy[:batch_expansion_allowed_for_public_claim]) == false
    @test Bool(policy[:requires_independent_replication])
    @test Bool(policy[:public_claim_allowed]) == false

    blockers = fixture[:blocker_rows]
    @test length(blockers) == 5
    @test all(blocker -> Bool(blocker[:resolved]) == false, blockers)

    decision = fixture[:decision_record]
    @test String(decision[:selected_decision]) ==
        "record_remediated_scalar_against_primary"
    @test Bool(decision[:primary_scalar_failure_reviewed]) == false
    @test Bool(decision[:remediation_success_observed]) == false
    @test Bool(decision[:primary_result_replaced]) == false
    @test isnothing(decision[:scalar_batch_target_acceptance])
    @test Bool(decision[:scalar_batch_expansion_allowed_local_only]) ==
        false
    @test Bool(decision[:public_fit_metric_claim_allowed]) == false
    @test Bool(decision[:public_model_weight_claim_allowed]) == false
    @test String(decision[:required_followup]) ==
        "execute_or_attach_scalar_remediation_comparison_before_batch_expansion"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:local_only])
    @test Bool(summary[:pilot_only])
    @test Bool(summary[:remediation_only])
    @test Bool(summary[:primary_review_present])
    @test Bool(summary[:primary_review_schema_matches])
    @test Bool(summary[:primary_review_passed])
    @test Bool(summary[:remediation_review_present])
    @test Bool(summary[:remediation_review_schema_matches])
    @test Bool(summary[:remediation_review_passed])
    @test Bool(summary[:primary_scalar_row_recorded]) == false
    @test Bool(summary[:primary_scalar_divergence_failure_recorded]) ==
        false
    @test Bool(summary[:remediation_scalar_row_recorded]) == false
    @test Bool(summary[:remediation_success_observed]) == false
    @test Bool(summary[:comparison_observed]) == false
    @test Bool(summary[:heldout_comparison_observed]) == false
    @test Bool(summary[:remediation_resolves_primary_divergence]) == false
    @test Bool(summary[:remediation_improves_heldout_elpd]) == false
    @test Bool(summary[:primary_result_preserved])
    @test Bool(summary[:scalar_batch_target_acceptance_policy_recorded])
    @test isnothing(summary[:scalar_batch_target_acceptance])
    @test Bool(summary[:scalar_batch_expansion_allowed_local_only]) ==
        false
    @test Bool(summary[:scalar_batch_expansion_allowed_for_public_claim]) ==
        false
    @test Bool(summary[:no_public_fit_metric_claim])
    @test Bool(summary[:no_public_q_revision_claim])
    @test Bool(summary[:no_public_model_weight_claim])
    @test Bool(summary[:no_sparse_superiority_claim])
    @test Int(summary[:n_input_artifacts]) == 2
    @test Int(summary[:n_blocker_rows]) == 5
    @test Int(summary[:n_blockers]) == 5
    @test String(summary[:recommendation]) ==
        "complete_scalar_remediation_comparison_keep_batch_expansion_blocked"
    @test String(summary[:next_gate]) ==
        "execute_or_attach_scalar_remediation_comparison_before_batch_expansion"
end

function check_mgmfrm_publication_grade_refit_batch_expansion_plan_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_publication_grade_refit_batch_expansion_plan.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) ==
        "publication_grade_refit_batch_expansion_plan"
    @test String(fixture[:status]) ==
        "publication_grade_refit_batch_expansion_plan_recorded"
    @test String(fixture[:decision]) ==
        "record_publication_grade_refit_batch_expansion_plan"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready]) == false
    @test Bool(fixture[:harness_ready])
    @test Bool(fixture[:execution_ready])
    @test Bool(fixture[:local_only])
    @test Bool(fixture[:publication_or_registration_action]) == false
    @test Bool(fixture[:publication_grade_batch_plan_recorded])
    @test Bool(fixture[:full_125_unit_publication_grade_batch_completed]) ==
        false
    @test Bool(fixture[:public_fit_metric_claim]) == false
    @test Bool(fixture[:public_q_revision_claim]) == false
    @test Bool(fixture[:public_model_weight_claim]) == false
    @test Bool(fixture[:sparse_mgmfrm_superiority_claim]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    controls = protocol[:fit_controls]
    @test String(protocol[:protocol_id]) ==
        "mgmfrm_publication_grade_refit_batch_expansion_plan_v1"
    @test String(protocol[:review_kind]) ==
        "local_publication_grade_refit_batch_expansion_plan"
    @test String(protocol[:execution_scope]) ==
        "full_scenario_model_fold_publication_grade_batch"
    @test String(protocol[:trigger_gate]) ==
        "expand_publication_grade_batch_with_scalar_target_acceptance_0p90_local_only"
    @test String(protocol[:runner_script]) ==
        "scripts/run_mgmfrm_publication_grade_refit_job.jl"
    @test Int(controls[:chains]) == 4
    @test Int(controls[:warmup_per_chain]) == 1000
    @test Int(controls[:draws_per_chain]) == 1000
    @test Float64(controls[:default_target_acceptance]) == 0.8
    @test Float64(controls[:scalar_remediated_target_acceptance]) == 0.9
    @test Int(controls[:seed_offset]) == 300000
    @test Bool(thresholds[:require_execution_plan_passed])
    @test Bool(thresholds[:require_gate_passed])
    @test Bool(thresholds[:require_brms_like_scalar_remediation_review_passed])
    @test Bool(thresholds[:require_scalar_remediation_success_observed])
    @test Bool(thresholds[:require_all_125_units_materialized])
    @test Bool(thresholds[:require_scalar_target_acceptance_policy_recorded])
    @test Bool(thresholds[:require_command_templates_recorded])
    @test Bool(thresholds[:require_result_artifact_targets_recorded])
    @test Bool(thresholds[:require_diagnostic_capture_manifest_recorded])
    @test Bool(thresholds[:require_runner_adapter_state_recorded])
    @test Bool(thresholds[:require_batch_execution_not_yet_run])
    @test Bool(thresholds[:require_no_publication_or_registration_action])

    inputs = fixture[:input_artifacts]
    expected_inputs = Dict(
        "mgmfrm_full_heldout_mcmc_refit_execution_plan" =>
            "test/fixtures/mgmfrm_full_heldout_mcmc_refit_execution_plan.json",
        "mgmfrm_publication_grade_refit_gate" =>
            "test/fixtures/mgmfrm_publication_grade_refit_gate.json",
        "mgmfrm_publication_grade_refit_brms_like_scalar_remediation_review" =>
            "test/fixtures/mgmfrm_publication_grade_refit_brms_like_scalar_remediation_review.json",
    )
    @test length(inputs) == length(expected_inputs)
    @test Set(String(row[:artifact]) for row in inputs) ==
        Set(keys(expected_inputs))
    for row in inputs
        artifact = String(row[:artifact])
        @test String(row[:path]) == expected_inputs[artifact]
        @test Bool(row[:exists])
        @test Bool(row[:schema_matches])
        @test Bool(row[:summary_passed])
        @test String(row[:sha256]) ==
            file_sha256(joinpath(root, String(row[:path])))
    end

    policies = fixture[:target_acceptance_policy_rows]
    @test length(policies) == 3
    scalar_policy = only(row for row in policies
        if String(row[:model_group]) == "scalar_gmfrm_baseline")
    @test Float64(scalar_policy[:target_acceptance]) == 0.9
    @test String(scalar_policy[:source]) ==
        "scalar_remediation_observed_policy"
    @test Bool(scalar_policy[:policy_ready_local_only])
    mgmfrm_policy = only(row for row in policies
        if String(row[:model_group]) == "mgmfrm_mcmc_candidates")
    @test Float64(mgmfrm_policy[:target_acceptance]) == 0.8
    @test Bool(mgmfrm_policy[:policy_ready_local_only])
    reference_policy = only(row for row in policies
        if String(row[:model_group]) == "null_or_intercept_reference")
    @test isnothing(reference_policy[:target_acceptance])
    @test Bool(reference_policy[:policy_ready_local_only])

    jobs = fixture[:batch_execution_job_rows]
    @test length(jobs) == 125
    @test count(row -> String(row[:model]) == "scalar_gmfrm_baseline",
        jobs) == 25
    @test count(row -> String(row[:model]) == "null_or_intercept_reference",
        jobs) == 25
    @test count(row -> Bool(row[:mcmc_refit_required]), jobs) == 100
    @test count(row -> Bool(row[:analytic_reference_scored]), jobs) == 25
    @test all(row -> Bool(row[:execute_now]) == false, jobs)
    @test all(row -> Bool(row[:public_claim_allowed]) == false, jobs)
    scalar_jobs = [row for row in jobs
        if String(row[:model]) == "scalar_gmfrm_baseline"]
    @test all(row -> Float64(row[:target_acceptance]) == 0.9, scalar_jobs)
    @test all(row -> String(row[:target_acceptance_source]) ==
        "scalar_remediation_observed_policy", scalar_jobs)
    @test all(row -> Int(row[:warmup_per_chain]) == 1000, scalar_jobs)
    mgmfrm_jobs = [row for row in jobs
        if String(row[:model]) in (
            "confirmatory_mgmfrm_current_q",
            "sparse_mgmfrm_current_q",
            "construct_reviewed_revised_q_mgmfrm")]
    @test length(mgmfrm_jobs) == 75
    @test all(row -> Float64(row[:target_acceptance]) == 0.8, mgmfrm_jobs)
    @test all(row -> Int(row[:warmup_per_chain]) == 1000, mgmfrm_jobs)
    @test all(row -> String(row[:target_acceptance_source]) ==
        "publication_grade_gate_default", mgmfrm_jobs)
    reference_jobs = [row for row in jobs
        if String(row[:model]) == "null_or_intercept_reference"]
    @test all(row -> isnothing(row[:target_acceptance]), reference_jobs)

    commands = fixture[:command_template_rows]
    @test length(commands) == 125
    @test all(row -> Bool(row[:runner_script_exists]), commands)
    @test all(row -> Bool(row[:runner_batch_plan_adapter_materialized]),
        commands)
    @test all(row -> String(row[:command_status]) ==
        "ready_not_executed", commands)
    @test all(row -> Bool(row[:execute_now]) == false, commands)
    @test all(row -> Bool(row[:local_only]), commands)
    @test all(row -> !occursin("git push", String(row[:command_template])),
        commands)
    @test any(row -> String(row[:model]) == "scalar_gmfrm_baseline" &&
        occursin("--target-acceptance 0.9",
            String(row[:command_template])), commands)
    @test any(row -> String(row[:model]) ==
        "confirmatory_mgmfrm_current_q" &&
        occursin("--target-acceptance 0.8",
            String(row[:command_template])), commands)
    @test any(row -> String(row[:model]) == "null_or_intercept_reference" &&
        occursin("--analytic-reference", String(row[:command_template])),
        commands)

    targets = fixture[:result_artifact_target_rows]
    @test length(targets) == 375
    @test all(row -> Bool(row[:exists]) == false, targets)
    @test all(row -> Bool(row[:required_before_public_claim]), targets)

    diagnostics = fixture[:diagnostic_capture_rows]
    @test length(diagnostics) == 1500
    @test all(row -> Bool(row[:observed]) == false, diagnostics)
    @test all(row -> Bool(row[:blocks_public_claim]), diagnostics)

    budgets = fixture[:model_budget_rows]
    @test length(budgets) == 5
    @test sum(Int(row[:n_execution_units]) for row in budgets) == 125
    @test sum(Int(row[:n_mcmc_execution_units]) for row in budgets) == 100
    @test sum(Int(row[:planned_chains]) for row in budgets) == 400
    scalar_budget = only(row for row in budgets
        if String(row[:model]) == "scalar_gmfrm_baseline")
    @test Float64(scalar_budget[:target_acceptance]) == 0.9
    @test Int(scalar_budget[:planned_posterior_draws]) == 100000

    comparisons = fixture[:comparison_hook_rows]
    @test length(comparisons) == 4
    @test all(row -> String(row[:comparison_status]) ==
        "planned_not_executed", comparisons)
    @test all(row -> Bool(row[:public_claim_allowed]) == false,
        comparisons)

    blockers = fixture[:blocker_rows]
    @test length(blockers) == 5
    @test count(row -> Bool(row[:resolved]), blockers) == 2
    runner_blocker = only(row for row in blockers
        if String(row[:blocker]) ==
           "publication_grade_batch_runner_adapter_not_materialized")
    @test Bool(runner_blocker[:resolved])
    @test Set(String(row[:blocker]) for row in blockers) == Set([
        "brms_like_scalar_remediation_not_observed",
        "publication_grade_batch_runner_adapter_not_materialized",
        "full_125_unit_publication_grade_batch_not_executed",
        "external_construct_dataset_missing",
        "independent_public_scope_review_missing",
    ])

    decision = fixture[:decision_record]
    @test String(decision[:selected_decision]) ==
        "record_full_batch_expansion_plan_before_heavy_execution"
    @test Bool(decision[:publication_grade_batch_plan_recorded])
    @test Bool(decision[:scalar_remediation_review_observed])
    @test Bool(decision[:scalar_remediation_comparison_observed])
    @test Bool(decision[:scalar_remediation_success_observed])
    @test Float64(decision[:scalar_target_acceptance]) == 0.9
    @test Bool(decision[:scalar_batch_sampler_policy_ready_local_only])
    @test Bool(decision[:batch_runner_adapter_materialized])
    @test Bool(decision[:batch_execution_ready_local_only])
    @test Bool(decision[:full_125_unit_publication_grade_batch_completed]) ==
        false
    @test Bool(decision[:public_fit_metric_claim_allowed]) == false
    @test Bool(decision[:public_q_revision_claim_allowed]) == false
    @test Bool(decision[
        :model_weight_or_sparse_superiority_claim_allowed]) == false
    @test String(decision[:required_followup]) ==
        "execute_publication_grade_refit_batch_locally"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:local_only])
    @test Bool(summary[:all_input_artifacts_present])
    @test Bool(summary[:all_expected_schemas])
    @test Bool(summary[:all_input_summaries_passed])
    @test Bool(summary[:execution_plan_passed])
    @test Bool(summary[:gate_passed])
    @test Bool(summary[:scalar_remediation_review_passed])
    @test Bool(summary[:scalar_remediation_comparison_passed])
    @test Bool(summary[:scalar_remediation_review_observed])
    @test Bool(summary[:scalar_remediation_comparison_observed])
    @test Bool(summary[:scalar_remediation_success_observed])
    @test Bool(summary[:scalar_target_acceptance_policy_recorded])
    @test Float64(summary[:scalar_target_acceptance]) == 0.9
    @test Bool(summary[:scalar_batch_sampler_policy_ready_local_only])
    @test Bool(summary[:batch_unit_rows_recorded])
    @test Bool(summary[:all_125_units_materialized])
    @test Bool(summary[:command_templates_recorded])
    @test Bool(summary[:result_artifact_targets_recorded])
    @test Bool(summary[:diagnostic_capture_manifest_recorded])
    @test Bool(summary[:runner_adapter_state_recorded])
    @test Bool(summary[:batch_runner_adapter_materialized])
    @test Bool(summary[:batch_execution_ready_local_only])
    @test Bool(summary[:full_125_unit_publication_grade_batch_completed]) ==
        false
    @test Bool(summary[:no_public_fit_metric_claim])
    @test Bool(summary[:no_public_q_revision_claim])
    @test Bool(summary[:no_public_model_weight_claim])
    @test Bool(summary[:no_sparse_superiority_claim])
    @test Int(summary[:n_input_artifacts]) == 3
    @test Int(summary[:n_batch_execution_job_rows]) == 125
    @test Int(summary[:n_mcmc_execution_jobs]) == 100
    @test Int(summary[:n_scalar_execution_jobs]) == 25
    @test Int(summary[:n_scalar_target_acceptance_0p90_jobs]) == 25
    @test Int(summary[:n_mgmfrm_target_acceptance_0p80_jobs]) == 75
    @test Int(summary[:n_analytic_reference_jobs]) == 25
    @test Int(summary[:n_command_template_rows]) == 125
    @test Int(summary[:n_result_artifact_target_rows]) == 375
    @test Int(summary[:n_diagnostic_capture_rows]) == 1500
    @test Int(summary[:n_model_budget_rows]) == 5
    @test Int(summary[:n_comparison_hook_rows]) == 4
    @test Int(summary[:n_blocker_rows]) == 5
    @test Int(summary[:n_review_cells]) == 2134
    @test Int(summary[:planned_chains]) == 400
    @test Int(summary[:planned_posterior_draws]) == 400000
    @test Int(summary[:planned_warmup_iterations]) == 400000
    @test Int(summary[:n_blockers]) == 3
    @test Set(String(blocker) for blocker in
        summary[:remaining_public_blockers]) == Set([
            "full_125_unit_publication_grade_batch_not_executed",
            "external_construct_dataset_missing",
            "independent_public_scope_review_missing",
        ])
    @test String(summary[:recommendation]) ==
        "execute_publication_grade_batch_locally_keep_claims_blocked"
    @test String(summary[:next_gate]) ==
        "execute_publication_grade_refit_batch_locally"
end

function check_mgmfrm_publication_grade_refit_batch_smoke_execution_review_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_publication_grade_refit_batch_smoke_execution_review.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) ==
        "publication_grade_refit_batch_smoke_execution_review"
    @test String(fixture[:status]) ==
        "publication_grade_refit_batch_smoke_execution_review_recorded"
    @test String(fixture[:decision]) ==
        "record_well_specified_fold1_batch_smoke_execution"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:local_only])
    @test Bool(fixture[:smoke_only])
    @test Bool(fixture[:publication_or_registration_action]) == false
    @test Bool(fixture[:publication_grade_batch_plan_recorded])
    @test Bool(fixture[:publication_grade_batch_smoke_executed])
    @test Bool(fixture[:full_125_unit_publication_grade_batch_completed]) ==
        false
    @test Bool(fixture[:public_fit_metric_claim]) == false
    @test Bool(fixture[:public_q_revision_claim]) == false
    @test Bool(fixture[:public_model_weight_claim]) == false
    @test Bool(fixture[:sparse_mgmfrm_superiority_claim]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) ==
        "mgmfrm_publication_grade_refit_batch_smoke_execution_review_v1"
    @test String(protocol[:review_kind]) ==
        "local_publication_grade_batch_smoke_execution_review"
    @test String(protocol[:source_orchestrator]) ==
        "run_mgmfrm_publication_grade_refit_batch"
    @test String(protocol[:source_runner]) ==
        "run_mgmfrm_publication_grade_refit_job"
    @test String(protocol[:source_plan]) ==
        "mgmfrm_publication_grade_refit_batch_expansion_plan"
    @test String(protocol[:scenario]) == "well_specified_current_q"
    @test Int(protocol[:fold]) == 1
    @test Int(protocol[:expected_execution_units]) == 5
    @test Int(protocol[:expected_mcmc_execution_units]) == 4
    @test Int(protocol[:expected_analytic_reference_units]) == 1
    @test Int(thresholds[:require_manifest_attempted_jobs]) == 5
    @test Int(thresholds[:require_failed_jobs]) == 0
    @test Int(thresholds[:require_chains]) == 4
    @test Int(thresholds[:require_warmup_per_chain]) == 1000
    @test Int(thresholds[:require_draws_per_chain]) == 1000
    @test Float64(thresholds[:require_scalar_target_acceptance]) == 0.9
    @test Float64(thresholds[:require_fixed_q_target_acceptance]) == 0.8
    @test Int(thresholds[:require_divergence_count_max]) == 0
    @test Bool(thresholds[:require_public_claims_blocked])

    inputs = fixture[:input_artifacts]
    @test length(inputs) == 2
    input_by_artifact = Dict(String(row[:artifact]) => row for row in inputs)
    plan = input_by_artifact[
        "mgmfrm_publication_grade_refit_batch_expansion_plan"]
    @test String(plan[:path]) ==
        "test/fixtures/mgmfrm_publication_grade_refit_batch_expansion_plan.json"
    @test Bool(plan[:exists])
    @test Bool(plan[:schema_matches])
    @test Bool(plan[:summary_passed])
    @test Bool(plan[:batch_execution_ready_local_only])
    @test Float64(plan[:scalar_target_acceptance]) == 0.9
    @test Int(plan[:planned_warmup_iterations]) == 400000
    @test String(plan[:sha256]) ==
        file_sha256(joinpath(root, String(plan[:path])))
    manifest =
        input_by_artifact["mgmfrm_publication_grade_refit_batch_orchestrator_run"]
    @test String(manifest[:path]) ==
        "artifacts/publication_grade_refit_batch/orchestrator_well_specified_fold1_smoke_brms_like.json"
    @test Bool(manifest[:exists])
    @test Bool(manifest[:schema_matches])
    @test Bool(manifest[:summary_passed])
    @test String(manifest[:action]) == "execute"
    @test Int(manifest[:n_matching_jobs]) == 5
    @test Int(manifest[:n_attempted_jobs]) == 5
    @test Int(manifest[:n_failed_jobs]) == 0
    @test Int(manifest[:n_successful_action_jobs]) == 5
    @test Int(manifest[:n_complete_after]) >= 5
    @test String(manifest[:next_gate]) ==
        "run_remaining_publication_grade_refit_batch_jobs"

    job_inputs = fixture[:job_input_artifacts]
    @test length(job_inputs) == 15
    @test count(row -> String(row[:kind]) == "result", job_inputs) == 5
    @test count(row -> String(row[:kind]) == "diagnostics", job_inputs) == 5
    @test count(row -> String(row[:kind]) == "heldout", job_inputs) == 5
    @test all(row -> Bool(row[:exists]), job_inputs)
    @test all(row -> Bool(row[:schema_matches]), job_inputs)
    @test all(row -> Bool(row[:summary_passed]), job_inputs)
    @test all(row -> Bool(row[:public_claim_allowed]) == false, job_inputs)

    selected = fixture[:manifest_selected_job_rows]
    @test length(selected) == 5
    @test all(row -> Bool(row[:selected_for_action]), selected)
    @test all(row -> String(row[:action_status]) == "executed", selected)
    @test all(row -> String(row[:status_after]) == "complete_executed",
        selected)
    @test all(row -> Bool(row[:public_claim_allowed]) == false, selected)

    rows = fixture[:job_review_rows]
    @test length(rows) == 5
    @test Set(String(row[:model]) for row in rows) == Set([
        "scalar_gmfrm_baseline",
        "confirmatory_mgmfrm_current_q",
        "sparse_mgmfrm_current_q",
        "construct_reviewed_revised_q_mgmfrm",
        "null_or_intercept_reference",
    ])
    @test all(row -> Bool(row[:executed]), rows)
    @test all(row -> Bool(row[:dry_run]) == false, rows)
    @test all(row -> Bool(row[:artifacts_complete]), rows)
    @test all(row -> Bool(row[:diagnostic_gate_passed]), rows)
    @test all(row -> Int(row[:n_divergences]) == 0, rows)
    @test all(row -> Bool(row[:public_claim_allowed]) == false, rows)

    mcmc_rows = [row for row in rows if Bool(row[:mcmc_refit_required])]
    @test length(mcmc_rows) == 4
    @test all(row -> Int(row[:chains]) == 4, mcmc_rows)
    @test all(row -> Int(row[:warmup_per_chain]) >= 1000, mcmc_rows)
    @test all(row -> Int(row[:draws_per_chain]) == 1000, mcmc_rows)
    @test all(row -> Int(row[:total_retained_draws]) == 4000, mcmc_rows)
    @test all(row -> Float64(row[:max_rhat]) <= 1.01, mcmc_rows)
    @test all(row -> Float64(row[:min_ess]) >= 400.0, mcmc_rows)
    @test all(row -> Float64(row[:e_bfmi]) >= 0.3, mcmc_rows)
    scalar = only(row for row in rows
        if String(row[:model]) == "scalar_gmfrm_baseline")
    @test Float64(scalar[:target_acceptance]) == 0.9
    @test String(scalar[:sampler_flag]) == "ok"
    @test Float64(scalar[:heldout_elpd]) ≈ -10.15953696736171
    fixed_q_rows = [row for row in mcmc_rows
        if String(row[:model]) != "scalar_gmfrm_baseline"]
    @test all(row -> Float64(row[:target_acceptance]) == 0.8,
        fixed_q_rows)

    ranks = fixture[:heldout_model_rank_rows]
    @test length(ranks) == 5
    @test String(first(ranks)[:model]) == "null_or_intercept_reference"
    @test Int(first(ranks)[:rank]) == 1
    @test Bool(first(ranks)[:analytic_reference_scored])
    @test String(ranks[2][:model]) == "scalar_gmfrm_baseline"
    @test Bool(ranks[2][:diagnostic_gate_passed])
    @test Float64(ranks[2][:heldout_elpd]) ≈ -10.15953696736171
    @test String(ranks[3][:model]) == "sparse_mgmfrm_current_q"
    @test all(row -> Bool(row[:descriptive_only]), ranks)
    @test all(row -> Bool(row[:public_model_weight_claim_allowed]) == false,
        ranks)
    @test isempty(fixture[:diagnostic_failure_rows])

    blockers = fixture[:blocker_rows]
    @test length(blockers) == 8
    @test count(row -> Bool(row[:resolved]), blockers) == 3
    @test Set(String(row[:blocker]) for row in blockers
        if !Bool(row[:resolved])) == Set([
        "null_reference_best_heldout_score",
        "fit_metric_thresholds_not_reestimated_under_publication_grade_batch",
        "full_125_unit_publication_grade_batch_not_executed",
        "external_construct_dataset_missing",
        "independent_public_scope_review_missing",
    ])

    decision = fixture[:decision_record]
    @test String(decision[:selected_decision]) ==
        "continue_batch_execution_after_successful_smoke"
    @test Bool(decision[:batch_smoke_executed])
    @test Bool(decision[:all_mcmc_diagnostic_gates_passed])
    @test Bool(decision[:scalar_target_acceptance_policy_confirmed])
    @test Bool(decision[:reference_best_heldout_score])
    @test Bool(decision[:public_fit_metric_claim_allowed]) == false
    @test Bool(decision[:public_model_weight_claim_allowed]) == false
    @test Bool(decision[:sparse_superiority_claim_allowed]) == false
    @test String(decision[:required_followup]) ==
        "run_remaining_publication_grade_refit_batch_jobs"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:local_only])
    @test Bool(summary[:smoke_only])
    @test Bool(summary[:all_artifacts_valid])
    @test Bool(summary[:publication_grade_batch_smoke_executed])
    @test Bool(summary[:full_125_unit_publication_grade_batch_completed]) ==
        false
    @test Bool(summary[:all_mcmc_diagnostic_gates_passed])
    @test Bool(summary[:scalar_target_acceptance_policy_confirmed])
    @test Bool(summary[:reference_best_heldout_score])
    @test Bool(summary[:no_public_claim_allowed])
    @test Int(summary[:n_input_artifacts]) == 2
    @test Int(summary[:n_job_input_artifacts]) == 15
    @test Int(summary[:n_manifest_selected_job_rows]) == 5
    @test Int(summary[:n_job_review_rows]) == 5
    @test Int(summary[:n_mcmc_execution_units]) == 4
    @test Int(summary[:n_analytic_reference_units]) == 1
    @test Int(summary[:n_diagnostic_failure_rows]) == 0
    @test Int(summary[:n_manifest_attempted_jobs]) == 5
    @test Int(summary[:n_manifest_failed_jobs]) == 0
    @test Int(summary[:n_manifest_successful_action_jobs]) == 5
    @test Int(summary[:n_batch_complete_after_manifest]) >= 5
    @test String(summary[:best_heldout_model]) ==
        "null_or_intercept_reference"
    @test String(summary[:best_mcmc_heldout_model]) ==
        "scalar_gmfrm_baseline"
    @test String(summary[:best_diagnostic_passed_mcmc_model]) ==
        "scalar_gmfrm_baseline"
    @test Float64(summary[:scalar_heldout_elpd]) ≈ -10.15953696736171
    @test Int(summary[:scalar_n_divergences]) == 0
    @test Int(summary[:n_blocker_rows]) == 8
    @test Int(summary[:n_resolved_blockers]) == 3
    @test Int(summary[:n_blockers]) == 5
    @test String(summary[:recommendation]) ==
        "run_remaining_publication_grade_refit_batch_jobs_keep_claims_blocked"
    @test String(summary[:next_gate]) ==
        "run_remaining_publication_grade_refit_batch_jobs"
end

function check_mgmfrm_publication_grade_refit_well_specified_scenario_execution_review_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_publication_grade_refit_well_specified_scenario_execution_review.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) ==
        "publication_grade_refit_well_specified_scenario_execution_review"
    @test String(fixture[:status]) ==
        "publication_grade_refit_well_specified_scenario_execution_review_recorded"
    @test String(fixture[:decision]) ==
        "record_well_specified_scenario_publication_grade_execution"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:local_only])
    @test Bool(fixture[:scenario_only])
    @test Bool(fixture[:publication_or_registration_action]) == false
    @test Bool(fixture[:publication_grade_batch_plan_recorded])
    @test Bool(fixture[:publication_grade_well_specified_scenario_executed])
    @test Bool(fixture[:full_125_unit_publication_grade_batch_completed]) ==
        false
    @test Bool(fixture[:public_fit_metric_claim]) == false
    @test Bool(fixture[:public_q_revision_claim]) == false
    @test Bool(fixture[:public_model_weight_claim]) == false
    @test Bool(fixture[:sparse_mgmfrm_superiority_claim]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) ==
        "mgmfrm_publication_grade_refit_well_specified_scenario_execution_review_v1"
    @test String(protocol[:review_kind]) ==
        "local_publication_grade_well_specified_scenario_execution_review"
    @test String(protocol[:source_orchestrator]) ==
        "run_mgmfrm_publication_grade_refit_batch"
    @test String(protocol[:source_runner]) ==
        "run_mgmfrm_publication_grade_refit_job"
    @test String(protocol[:source_plan]) ==
        "mgmfrm_publication_grade_refit_batch_expansion_plan"
    @test String(protocol[:scenario]) == "well_specified_current_q"
    @test Int(protocol[:expected_execution_units]) == 25
    @test Int(protocol[:expected_folds]) == 5
    @test Int(protocol[:expected_models_per_fold]) == 5
    @test Int(protocol[:expected_mcmc_execution_units]) == 20
    @test Int(protocol[:expected_analytic_reference_units]) == 5
    @test Int(thresholds[:require_manifest_matching_jobs]) == 25
    @test Int(thresholds[:require_manifest_attempted_jobs]) == 20
    @test Int(thresholds[:require_failed_jobs]) == 0
    @test Int(thresholds[:require_chains]) == 4
    @test Int(thresholds[:require_warmup_per_chain]) == 1000
    @test Int(thresholds[:require_draws_per_chain]) == 1000
    @test Float64(thresholds[:require_scalar_target_acceptance]) == 0.9
    @test Float64(thresholds[:require_fixed_q_target_acceptance]) == 0.8
    @test Int(thresholds[:require_divergence_count_max]) == 0
    @test Bool(thresholds[:require_public_claims_blocked])

    inputs = fixture[:input_artifacts]
    @test length(inputs) == 2
    input_by_artifact = Dict(String(row[:artifact]) => row for row in inputs)
    plan = input_by_artifact[
        "mgmfrm_publication_grade_refit_batch_expansion_plan"]
    @test String(plan[:path]) ==
        "test/fixtures/mgmfrm_publication_grade_refit_batch_expansion_plan.json"
    @test Bool(plan[:exists])
    @test Bool(plan[:schema_matches])
    @test Bool(plan[:summary_passed])
    @test Bool(plan[:batch_execution_ready_local_only])
    @test Float64(plan[:scalar_target_acceptance]) == 0.9
    @test Int(plan[:n_batch_execution_job_rows]) == 125
    @test Int(plan[:planned_warmup_iterations]) == 400000
    @test String(plan[:sha256]) ==
        file_sha256(joinpath(root, String(plan[:path])))
    manifest =
        input_by_artifact["mgmfrm_publication_grade_refit_batch_orchestrator_run"]
    @test String(manifest[:path]) ==
        "artifacts/publication_grade_refit_batch/orchestrator_well_specified_scenario_brms_like.json"
    @test Bool(manifest[:exists])
    @test Bool(manifest[:schema_matches])
    @test Bool(manifest[:summary_passed])
    @test String(manifest[:action]) == "execute"
    @test Int(manifest[:n_plan_jobs]) == 125
    @test Int(manifest[:n_matching_jobs]) == 25
    @test Int(manifest[:n_selected_for_action]) == 20
    @test Int(manifest[:n_attempted_jobs]) == 20
    @test Int(manifest[:n_failed_jobs]) == 0
    @test Int(manifest[:n_successful_action_jobs]) == 20
    @test Int(manifest[:n_skipped_jobs]) == 5
    @test Int(manifest[:n_complete_after]) >= 50
    @test String(manifest[:next_gate]) ==
        "run_remaining_publication_grade_refit_batch_jobs"

    job_inputs = fixture[:job_input_artifacts]
    @test length(job_inputs) == 75
    @test count(row -> String(row[:kind]) == "result", job_inputs) == 25
    @test count(row -> String(row[:kind]) == "diagnostics", job_inputs) == 25
    @test count(row -> String(row[:kind]) == "heldout", job_inputs) == 25
    @test all(row -> Bool(row[:exists]), job_inputs)
    @test all(row -> Bool(row[:schema_matches]), job_inputs)
    @test all(row -> Bool(row[:summary_passed]), job_inputs)
    @test all(row -> Bool(row[:public_claim_allowed]) == false, job_inputs)

    selected = fixture[:manifest_selected_job_rows]
    @test length(selected) == 20
    @test all(row -> Bool(row[:selected_for_action]), selected)
    @test all(row -> String(row[:action_status]) == "executed", selected)
    @test all(row -> String(row[:status_after]) == "complete_executed",
        selected)
    @test Set(Int(row[:fold]) for row in selected) == Set(2:5)
    @test all(row -> Bool(row[:public_claim_allowed]) == false, selected)

    rows = fixture[:job_review_rows]
    @test length(rows) == 25
    @test Set(Int(row[:fold]) for row in rows) == Set(1:5)
    @test Set(String(row[:model]) for row in rows) == Set([
        "scalar_gmfrm_baseline",
        "confirmatory_mgmfrm_current_q",
        "sparse_mgmfrm_current_q",
        "construct_reviewed_revised_q_mgmfrm",
        "null_or_intercept_reference",
    ])
    @test all(row -> Bool(row[:executed]), rows)
    @test all(row -> Bool(row[:dry_run]) == false, rows)
    @test all(row -> Bool(row[:artifacts_complete]), rows)
    @test all(row -> Bool(row[:public_claim_allowed]) == false, rows)
    @test count(row -> Bool(row[:mcmc_refit_required]), rows) == 20
    @test count(row -> Bool(row[:analytic_reference_scored]), rows) == 5

    mcmc_rows = [row for row in rows if Bool(row[:mcmc_refit_required])]
    @test all(row -> Int(row[:chains]) == 4, mcmc_rows)
    @test all(row -> Int(row[:warmup_per_chain]) >= 1000, mcmc_rows)
    @test all(row -> Int(row[:draws_per_chain]) == 1000, mcmc_rows)
    @test all(row -> Int(row[:total_retained_draws]) == 4000, mcmc_rows)
    @test all(row -> Float64(row[:max_rhat]) <= 1.01, mcmc_rows)
    @test all(row -> Float64(row[:min_ess]) >= 400.0, mcmc_rows)
    @test all(row -> Float64(row[:e_bfmi]) >= 0.3, mcmc_rows)
    scalar_rows = sort([row for row in rows
        if String(row[:model]) == "scalar_gmfrm_baseline"];
        by = row -> Int(row[:fold]))
    @test length(scalar_rows) == 5
    @test all(row -> Float64(row[:target_acceptance]) >= 0.9,
        scalar_rows)
    @test [Int(row[:n_divergences]) for row in scalar_rows] ==
        [0, 0, 0, 0, 0]
    @test all(row -> Bool(row[:diagnostic_gate_passed]), scalar_rows)
    fixed_q_rows = [row for row in mcmc_rows
        if String(row[:model]) != "scalar_gmfrm_baseline"]
    @test all(row -> Float64(row[:target_acceptance]) == 0.8,
        fixed_q_rows)
    @test all(row -> Int(row[:n_divergences]) == 0, fixed_q_rows)
    @test all(row -> Bool(row[:diagnostic_gate_passed]), fixed_q_rows)

    model_rows = fixture[:model_summary_rows]
    @test length(model_rows) == 5
    model_by_name = Dict(String(row[:model]) => row for row in model_rows)
    scalar_summary = model_by_name["scalar_gmfrm_baseline"]
    @test Int(scalar_summary[:n_execution_units]) == 5
    @test Int(scalar_summary[:n_diagnostic_gate_passed_units]) == 5
    @test Int(scalar_summary[:n_divergences]) == 0
    @test Float64(scalar_summary[:mean_heldout_elpd]) ≈
        -11.055754604356197
    null_summary = model_by_name["null_or_intercept_reference"]
    @test Int(null_summary[:n_analytic_reference_units]) == 5
    @test Int(null_summary[:n_diagnostic_gate_passed_units]) == 5
    @test Float64(null_summary[:mean_heldout_elpd]) ≈ -9.019229062706467
    @test all(row -> Bool(row[:all_public_claims_blocked]), model_rows)

    fold_bests = fixture[:fold_best_rows]
    @test length(fold_bests) == 5
    @test all(row -> String(row[:best_model]) ==
        "null_or_intercept_reference", fold_bests)
    @test all(row -> Bool(row[:best_is_analytic_reference]), fold_bests)
    @test all(row -> Bool(row[:public_model_weight_claim_allowed]) == false,
        fold_bests)

    ranks = fixture[:heldout_model_rank_rows]
    @test length(ranks) == 25
    @test count(row -> Int(row[:rank]) == 1, ranks) == 5
    @test all(row -> Bool(row[:descriptive_only]), ranks)
    @test all(row -> Bool(row[:public_model_weight_claim_allowed]) == false,
        ranks)
    @test all(row -> Bool(row[:public_fit_metric_claim_allowed]) == false,
        ranks)
    @test all(row -> String(row[:model]) == "null_or_intercept_reference",
        [row for row in ranks if Int(row[:rank]) == 1])

    failures = fixture[:diagnostic_failure_rows]
    @test isempty(failures)

    blockers = fixture[:blocker_rows]
    @test length(blockers) == 8
    @test count(row -> Bool(row[:resolved]), blockers) == 3
    @test Set(String(row[:blocker]) for row in blockers
        if !Bool(row[:resolved])) == Set([
        "null_reference_best_all_well_specified_folds",
        "fit_metric_thresholds_not_reestimated_under_publication_grade_batch",
        "remaining_100_unit_publication_grade_batch_not_executed",
        "external_construct_dataset_missing",
        "independent_public_scope_review_missing",
    ])

    decision = fixture[:decision_record]
    @test String(decision[:selected_decision]) ==
        "continue_batch_execution_after_well_specified_scenario_review"
    @test Bool(decision[:well_specified_scenario_executed])
    @test Bool(decision[:all_mcmc_diagnostic_gates_passed])
    @test Bool(decision[:scalar_target_acceptance_policy_applied])
    @test Bool(decision[:scalar_target_acceptance_policy_stable_across_folds])
    @test Bool(decision[:reference_best_all_folds])
    @test Bool(decision[:public_fit_metric_claim_allowed]) == false
    @test Bool(decision[:public_model_weight_claim_allowed]) == false
    @test Bool(decision[:sparse_superiority_claim_allowed]) == false
    @test String(decision[:required_followup]) ==
        "run_remaining_publication_grade_refit_batch_jobs"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:local_only])
    @test Bool(summary[:scenario_only])
    @test Bool(summary[:all_artifacts_valid])
    @test Bool(summary[:publication_grade_well_specified_scenario_executed])
    @test Bool(summary[:full_125_unit_publication_grade_batch_completed]) ==
        false
    @test Bool(summary[:all_mcmc_diagnostic_gates_passed])
    @test Bool(summary[:scalar_target_acceptance_policy_applied])
    @test Bool(summary[:scalar_target_acceptance_policy_stable_across_folds])
    @test Bool(summary[:reference_best_all_folds])
    @test Bool(summary[:no_public_claim_allowed])
    @test Int(summary[:n_input_artifacts]) == 2
    @test Int(summary[:n_job_input_artifacts]) == 75
    @test Int(summary[:n_manifest_selected_job_rows]) == 20
    @test Int(summary[:n_job_review_rows]) == 25
    @test Int(summary[:n_model_summary_rows]) == 5
    @test Int(summary[:n_fold_best_rows]) == 5
    @test Int(summary[:n_mcmc_execution_units]) == 20
    @test Int(summary[:n_analytic_reference_units]) == 5
    @test Int(summary[:n_diagnostic_failure_rows]) == 0
    @test Int(summary[:n_heldout_model_rank_rows]) == 25
    @test Int(summary[:n_manifest_matching_jobs]) == 25
    @test Int(summary[:n_manifest_selected_for_action]) == 20
    @test Int(summary[:n_manifest_attempted_jobs]) == 20
    @test Int(summary[:n_manifest_skipped_jobs]) == 5
    @test Int(summary[:n_manifest_failed_jobs]) == 0
    @test Int(summary[:n_manifest_successful_action_jobs]) == 20
    @test Int(summary[:n_batch_complete_after_manifest]) >= 50
    @test Int(summary[:n_batch_pending_after_manifest]) == 75
    @test Int(summary[:n_scalar_diagnostic_gate_passed]) == 5
    @test [Int(row[:n_divergences]) for row in
        summary[:scalar_divergences_by_fold]] == [0, 0, 0, 0, 0]
    @test Int(summary[:scalar_total_divergences]) == 0
    @test isempty(summary[:folds_with_scalar_divergences])
    @test all(row -> String(row[:model]) == "null_or_intercept_reference",
        summary[:best_heldout_models_by_fold])
    @test Int(summary[:n_blocker_rows]) == 8
    @test Int(summary[:n_resolved_blockers]) == 3
    @test Int(summary[:n_blockers]) == 5
    @test String(summary[:recommendation]) ==
        "run_remaining_publication_grade_refit_batch_jobs_keep_claims_blocked"
    @test String(summary[:next_gate]) ==
        "run_remaining_publication_grade_refit_batch_jobs"
end
