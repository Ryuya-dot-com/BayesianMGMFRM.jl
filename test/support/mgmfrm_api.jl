function check_mgmfrm_guarded_fit_method_wiring_fixture(fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_guarded_fit_method_wiring.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) == "minimal_confirmatory_mgmfrm_candidate"
    @test String(fixture[:status]) == "guarded_fit_method_wiring_recorded"
    @test String(fixture[:decision]) == "enable_guarded_experimental"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])
    @test Bool(fixture[:publication_or_registration_action]) == false
    @test Bool(fixture[:entrypoint_enabled])

    protocol = fixture[:protocol]
    @test String(protocol[:protocol_id]) ==
        "confirmatory_mgmfrm_guarded_fit_method_wiring_v1"
    @test String(protocol[:review_kind]) ==
        "local_confirmatory_mgmfrm_guarded_fit_method_wiring"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test Bool(protocol[:entrypoint_enabled])
    @test String(protocol[:public_target_label]) ==
        "guarded_confirmatory_mgmfrm_logdensity"
    @test String(protocol[:public_target_description]) ==
        "guarded fixed-Q confirmatory MGMFRM log density"
    @test String(protocol[:internal_target_constructor]) ==
        "_mgmfrm_guarded_local_fit_logdensity"
    rules = protocol[:decision_rules]
    @test Bool(rules[:require_entrypoint_enabled])
    @test Bool(rules[:require_non_experimental_fit_rejection])
    @test Bool(rules[:require_experimental_spec_fit_success])
    @test Bool(rules[:require_artifact_contract_satisfied])
    @test Bool(rules[:validation_grid_required_before_public_entrypoint])

    target = fixture[:target_review]
    @test String(target[:constructor]) == "_source_fixture_logdensity"
    @test String(target[:family]) == "mgmfrm"
    @test String(target[:scope]) == "mgmfrm_source_aligned"
    @test Int(target[:n_raw_parameters]) == 12
    @test Int(target[:n_direct_parameters]) == 14

    sampler = fixture[:sampler_review]
    sampler_summary = sampler[:summary]
    @test String(sampler[:schema]) ==
        "bayesianmgmfrm.mgmfrm_confirmatory_candidate_sampler_diagnostics.v1"
    @test Bool(sampler[:protocol_passed])
    @test Bool(sampler_summary[:passed])
    @test Int(sampler_summary[:n_divergences]) == 0
    @test Int(sampler_summary[:n_failed_direct_constraints]) == 0
    @test Int(sampler_summary[:n_nonfinite_direct_loglikelihood]) == 0

    contract = fixture[:artifact_contract_review]
    @test String(contract[:schema]) ==
        "bayesianmgmfrm.experimental_generalized_fit_artifact_contract.v1"
    @test Bool(contract[:public_fit])
    @test Bool(contract[:experimental_public])
    @test Int(contract[:n_required_fields]) == 26
    @test "initialization_policy" in String.(contract[:required_field_names])
    @test "initialization_rows" in String.(contract[:required_field_names])
    @test "fixed_q_invariance_rows" in
        String.(contract[:required_field_names])
    @test Bool(contract[:all_required_fields_present])
    @test Bool(contract[:all_required_provenance_recorded])

    preview = fixture[:fit_artifact_preview]
    @test String(preview[:schema]) ==
        "bayesianmgmfrm.mgmfrm_guarded_fit_artifact_preview.v1"
    @test Bool(preview[:public_fit])
    @test Bool(preview[:experimental_public])
    @test String(preview[:public_target_label]) ==
        "guarded_confirmatory_mgmfrm_logdensity"
    @test String(preview[:public_target_description]) ==
        "guarded fixed-Q confirmatory MGMFRM log density"
    @test String(preview[:internal_target_constructor]) ==
        "_mgmfrm_guarded_local_fit_logdensity"
    @test String(preview[:internal_sampler_diagnostic_constructor]) ==
        "_mgmfrm_guarded_local_fit_sampler_diagnostics"
    @test String(preview[:raw_prior_control_schema]) ==
        "bayesianmgmfrm.generalized_raw_prior_control_manifest.v1"
    @test Int(preview[:n_raw_prior_control_rows]) == 7
    @test Bool(preview[:raw_prior_control_all_active_scales_resolved])
    @test !Bool(preview[:raw_prior_control_direct_scale_priors_enabled])
    @test String(preview[:parameter_layout_schema]) ==
        "bayesianmgmfrm.fit_ready_parameter_layout.v1"
    @test String(preview[:parameter_layout_scope]) ==
        "minimal_confirmatory_mgmfrm_candidate"
    @test Int(preview[:raw_to_direct_transform_count]) >= 1
    @test Int(preview[:raw_parameter_count]) == 12
    @test Int(preview[:direct_parameter_count]) == 14
    @test String(preview[:raw_posterior_row_schema]) ==
        "bayesianmgmfrm.posterior_summary_row_schema.v1"
    @test String(preview[:direct_posterior_row_schema]) ==
        "bayesianmgmfrm.posterior_summary_row_schema.v1"
    @test "parameter" in String.(preview[:direct_posterior_row_fields])
    @test "probability_of_direction" in
        String.(preview[:direct_posterior_row_fields])
    @test Vector{Int}(preview[:pointwise_loglikelihood_shape]) == [64, 6]
    @test [Bool.(row) for row in preview[:q_matrix]] ==
        [[true, false], [false, true]]
    @test String(preview[:latent_correlation]) == "identity_fixed"
    @test String(preview[:ability_scale]) == "standard_normal_by_dimension"
    @test String(preview[:initialization_policy][:schema]) ==
        "bayesianmgmfrm.mgmfrm_initialization_policy.v1"
    @test String(preview[:initialization_policy][:initial_source]) ==
        "user_supplied_raw"
    @test Bool(preview[:initialization_policy][:finite_initial_logdensity])
    @test !Bool(preview[:initialization_policy][:fallback_used])
    @test Int(preview[:n_initialization_rows]) == 4
    @test any(row -> String(row[:policy]) == "initial_logdensity" &&
        String(row[:status]) == "finite" &&
        Bool(row[:passed]),
        preview[:initialization_rows])
    @test Int(preview[:n_fixed_q_invariance_rows]) == 9
    @test any(row -> String(row[:policy]) == "latent_correlation" &&
        String(row[:status]) == "fixed_identity" &&
        Bool(row[:passed]),
        preview[:fixed_q_invariance_rows])
    @test any(row -> String(row[:policy]) == "direct_constraints" &&
        String(row[:status]) == "passed" &&
        Int(row[:value]) == 0,
        preview[:fixed_q_invariance_rows])
    @test any(row -> String(row[:policy]) == "exploratory_loading" &&
        String(row[:status]) == "blocked",
        preview[:fixed_q_invariance_rows])

    fixture_refs = fixture[:fixture_references]
    @test length(fixture_refs) == 5
    @test all(row -> Bool(row[:exists]), fixture_refs)
    @test all(row -> String(row[:sha256]) ==
        file_sha256(joinpath(root, String(row[:path]))), fixture_refs)

    boundary_checks = fixture[:fit_boundary_checks]
    @test length(boundary_checks) == 4
    @test all(row -> Bool(row[:passed]), boundary_checks)
    @test any(row -> String(row[:check]) ==
        "fit_experimental_mgmfrm_guarded_enabled" &&
        String(row[:actual_status]) == "succeeded", boundary_checks)

    decision = fixture[:decision_record]
    @test Bool(decision[:public_fit_allowed])
    @test Bool(decision[:experimental_keyword_enabled])
    @test String(decision[:required_followup]) ==
        "mgmfrm_guarded_fit_validation_grid"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:entrypoint_enabled])
    @test Bool(summary[:public_fit_allowed])
    @test Bool(summary[:experimental_keyword_enabled])
    @test Bool(summary[:target_constructor_available])
    @test Bool(summary[:raw_to_direct_transform_available])
    @test Bool(summary[:sampler_protocol_passed])
    @test Bool(summary[:artifact_contract_satisfied])
    @test Bool(summary[:pointwise_loglikelihood_shape_valid])
    @test Bool(summary[:all_fit_boundary_checks_passed])
    @test Bool(summary[:experimental_spec_fit_succeeded])
    @test Bool(summary[:all_fixture_references_present])
    @test Set(String(blocker) for blocker in summary[:remaining_public_blockers]) ==
        Set(["mgmfrm_guarded_fit_validation_grid_missing"])
    @test String(summary[:recommendation]) ==
        "guarded_entrypoint_enabled_validate_grid_next"
    @test String(summary[:next_gate]) == "mgmfrm_guarded_fit_validation_grid"
end

function check_mgmfrm_guarded_fit_validation_grid_fixture(fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_guarded_fit_validation_grid.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) == "minimal_confirmatory_mgmfrm_candidate"
    @test String(fixture[:status]) == "guarded_fit_validation_grid_recorded"
    @test String(fixture[:decision]) == "enable_guarded_experimental"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])
    @test Bool(fixture[:publication_or_registration_action]) == false

    protocol = fixture[:protocol]
    @test String(protocol[:protocol_id]) ==
        "confirmatory_mgmfrm_guarded_fit_validation_grid_v1"
    @test String(protocol[:review_kind]) ==
        "local_confirmatory_mgmfrm_guarded_fit_validation_grid"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test Bool(protocol[:entrypoint_enabled])
    thresholds = protocol[:thresholds]
    @test Bool(thresholds[:require_bridge_oracle_present])
    @test Bool(thresholds[:require_candidate_chain_passed])
    @test Bool(thresholds[:require_recovery_smoke_passed])
    @test Bool(thresholds[:require_baseline_comparison_passed])
    @test Bool(thresholds[:require_sparse_recovery_grid_passed])
    @test Bool(thresholds[:require_report_shape_simulation_grid_passed])
    @test Bool(thresholds[:require_q_matrix_validation_expansion_passed])
    @test Bool(thresholds[:require_guarded_fit_method_wiring_passed])
    @test Bool(thresholds[:require_sampler_protocol_passed])
    @test Bool(thresholds[:require_artifact_contract_satisfied])
    @test Bool(thresholds[:require_fit_boundary_checks_passed])
    @test Bool(thresholds[:require_experimental_spec_fit_success])
    @test Bool(thresholds[:require_entrypoint_enabled])
    @test Bool(thresholds[:require_no_publication_or_registration_action])

    input_artifacts = fixture[:input_artifacts]
    expected_paths = Dict(
        "bridge_oracle" =>
            "test/fixtures/source_mgmfrm_bridge_logdensity.json",
        "candidate_chain_study" =>
            "test/fixtures/mgmfrm_candidate_chain_study.json",
        "recovery_smoke" =>
            "test/fixtures/mgmfrm_recovery_smoke.json",
        "baseline_comparison" =>
            "test/fixtures/mgmfrm_baseline_comparison.json",
        "sparse_recovery_grid" =>
            "test/fixtures/mgmfrm_sparse_recovery_grid.json",
        "report_shape_simulation_grid" =>
            "test/fixtures/mgmfrm_report_shape_simulation_grid.json",
        "q_matrix_validation_expansion" =>
            "test/fixtures/mgmfrm_q_matrix_validation_expansion.json",
        "guarded_fit_method_wiring" =>
            "test/fixtures/mgmfrm_guarded_fit_method_wiring.json",
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
        recorded = String(row[:sha256])
        path = joinpath(root, String(row[:path]))
        # The archived grid consumed the 13-scenario Q study. Later grids can
        # reference the 15-scenario successor at the same recorded path.
        if artifact == "q_matrix_validation_expansion" &&
                recorded == "414b69842a9364102af1270f8e4fee793d40c46f189aff17e537648803c20346"
            path = joinpath(dirname(path), "mgmfrm_q_matrix_validation_expansion_13_scenarios.json")
        end
        @test recorded == file_sha256(path)
    end

    validation_rows = fixture[:validation_rows]
    @test length(validation_rows) == 8
    @test Set(String(row[:scenario]) for row in validation_rows) == Set([
        "bridge_and_chain_oracles",
        "full_crossed_recovery_smoke",
        "baseline_model_comparison",
        "sparse_connected_recovery_grid",
        "report_shape_simulation_grid",
        "q_matrix_validation_expansion",
        "guarded_method_contract",
        "current_guarded_fit_boundary",
    ])
    @test all(row -> Bool(row[:evidence]), validation_rows)

    decision = fixture[:decision_record]
    @test Bool(decision[:public_fit_allowed])
    @test Bool(decision[:experimental_keyword_enabled])
    @test String(decision[:public_exposure_support]) ==
        "validation_grid_satisfies_guarded_entrypoint_boundary"
    @test String(decision[:interpretation]) ==
        "confirmatory_mgmfrm_guarded_fit_validation_grid_recorded_entrypoint_enabled"
    @test String(decision[:required_followup]) ==
        "mgmfrm_guarded_fit_api_dry_run"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:entrypoint_enabled])
    @test Bool(summary[:public_fit_allowed])
    @test Bool(summary[:experimental_keyword_enabled])
    @test Bool(summary[:all_input_artifacts_present])
    @test Bool(summary[:all_expected_schemas])
    @test Bool(summary[:all_input_summaries_passed])
    @test Bool(summary[:all_validation_rows_passed])
    @test Bool(summary[:no_publication_commands])
    @test Bool(summary[:bridge_oracle_present])
    @test Bool(summary[:candidate_chain_study_passed])
    @test Bool(summary[:recovery_smoke_passed])
    @test Bool(summary[:baseline_comparison_passed])
    @test Bool(summary[:sparse_recovery_grid_passed])
    @test Bool(summary[:report_shape_simulation_grid_passed])
    @test Bool(summary[:q_matrix_validation_expansion_passed])
    @test Bool(summary[:guarded_fit_method_wiring_passed])
    @test Bool(summary[:sparse_grid_all_validations_passed])
    @test Bool(summary[:sparse_grid_all_sampler_passed])
    @test Bool(summary[:report_shape_all_report_shapes_passed])
    @test Bool(summary[:report_shape_all_diagnostics_shapes_passed])
    @test Bool(summary[:report_shape_all_artifact_shapes_passed])
    @test Bool(summary[:report_shape_all_waic_shapes_passed])
    @test Bool(summary[:report_shape_all_posterior_predictive_shapes_passed])
    @test Bool(summary[:q_matrix_all_expected_validation_outcomes])
    @test Bool(summary[:q_matrix_all_expected_spec_outcomes])
    @test Bool(summary[
        :q_matrix_all_invalid_default_q_scenarios_blocked_before_fit])
    @test Bool(summary[:q_matrix_policy_validation_scenarios_recorded])
    @test Bool(summary[:q_matrix_warning_scenarios_not_rejected])
    @test Bool(summary[:q_matrix_valid_scenarios_preview_design])
    @test Bool(summary[:q_matrix_research_basis_recorded])
    @test Bool(summary[:method_sampler_protocol_passed])
    @test Bool(summary[:method_artifact_contract_satisfied])
    @test Bool(summary[:method_fit_boundary_checks_passed])
    @test Bool(summary[:method_experimental_spec_fit_succeeded])
    @test Int(summary[:n_input_artifacts]) == length(input_artifacts)
    @test Int(summary[:n_validation_rows]) == length(validation_rows)
    @test Int(summary[:n_passed_validation_rows]) == length(validation_rows)
    @test Set(String(blocker) for blocker in summary[:remaining_public_blockers]) ==
        Set(["mgmfrm_guarded_fit_api_dry_run_missing"])
    @test String(summary[:recommendation]) ==
        "guarded_entrypoint_validated_run_api_dry_run_next"
    @test String(summary[:next_gate]) == "mgmfrm_guarded_fit_api_dry_run"
end

function check_mgmfrm_guarded_fit_api_dry_run_fixture(fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_guarded_fit_api_dry_run.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) == "minimal_confirmatory_mgmfrm_candidate"
    @test String(fixture[:status]) == "guarded_fit_api_dry_run_recorded"
    @test String(fixture[:decision]) == "enable_guarded_experimental"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])
    @test Bool(fixture[:publication_or_registration_action]) == false
    @test Bool(fixture[:entrypoint_enabled])

    protocol = fixture[:protocol]
    @test String(protocol[:protocol_id]) ==
        "confirmatory_mgmfrm_guarded_fit_api_dry_run_v1"
    @test String(protocol[:review_kind]) ==
        "local_confirmatory_mgmfrm_guarded_fit_api_contract_dry_run"
    @test Bool(protocol[:dry_run_only])
    @test Bool(protocol[:entrypoint_enabled])
    @test String(protocol[:public_target_label]) ==
        "guarded_confirmatory_mgmfrm_logdensity"
    @test String(protocol[:public_target_description]) ==
        "guarded fixed-Q confirmatory MGMFRM log density"
    @test String(protocol[:internal_target_constructor]) ==
        "_mgmfrm_guarded_local_fit_logdensity"
    rules = protocol[:decision_rules]
    @test Bool(rules[:require_validation_grid_passed])
    @test Bool(rules[:require_gradient_diagnostics_passed])
    @test Bool(rules[:public_exposure_review_required_before_broader_claims])

    input_artifacts = fixture[:input_artifacts]
    expected_paths = Dict(
        "bridge_oracle" =>
            "test/fixtures/source_mgmfrm_bridge_logdensity.json",
        "guarded_fit_method_wiring" =>
            "test/fixtures/mgmfrm_guarded_fit_method_wiring.json",
        "guarded_fit_validation_grid" =>
            "test/fixtures/mgmfrm_guarded_fit_validation_grid.json",
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
        @test String(row[:sha256]) ==
            file_sha256(joinpath(root, String(row[:path])))
    end

    boundary_checks = fixture[:fit_boundary_checks]
    @test length(boundary_checks) == 4
    @test all(row -> Bool(row[:passed]), boundary_checks)
    @test any(row -> String(row[:check]) ==
        "fit_experimental_mgmfrm_guarded_enabled" &&
        String(row[:actual_status]) == "succeeded", boundary_checks)

    contract = fixture[:artifact_contract_review]
    @test String(contract[:schema]) ==
        "bayesianmgmfrm.experimental_generalized_fit_artifact_contract.v1"
    @test Bool(contract[:public_fit])
    @test Bool(contract[:experimental_public])
    @test Int(contract[:n_required_fields]) == 26
    @test "initialization_policy" in String.(contract[:required_field_names])
    @test "initialization_rows" in String.(contract[:required_field_names])
    @test "fixed_q_invariance_rows" in
        String.(contract[:required_field_names])
    @test Bool(contract[:all_required_fields_recorded])
    @test Bool(contract[:all_required_provenance_recorded])

    target = fixture[:target_dry_run]
    @test String(target[:public_target_label]) ==
        "guarded_confirmatory_mgmfrm_logdensity"
    @test String(target[:public_target_description]) ==
        "guarded fixed-Q confirmatory MGMFRM log density"
    @test String(target[:internal_target_constructor]) ==
        "_mgmfrm_guarded_local_fit_logdensity"
    @test String(target[:target]) == "_source_fixture_logdensity"
    @test Int(target[:n_raw_parameters]) == 12
    @test Int(target[:n_direct_parameters]) == 14
    @test Int(target[:n_observations]) == 6
    @test Bool(target[:finite_logdensity])
    @test Bool(target[:finite_direct_parameters])
    @test Bool(target[:finite_pointwise_loglikelihood])
    gradient = target[:gradient_diagnostics]
    @test Bool(gradient[:passed])
    @test Int(gradient[:n_checked]) == 6
    @test Int(gradient[:n_failed]) == 0
    @test Float64(gradient[:max_abs_error]) <=
        Float64(gradient[:max_tolerance])

    decision = fixture[:decision_record]
    @test Bool(decision[:public_fit_allowed])
    @test Bool(decision[:experimental_keyword_enabled])
    @test String(decision[:required_followup]) ==
        "mgmfrm_guarded_fit_public_exposure_review"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:dry_run_only])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:entrypoint_enabled])
    @test Bool(summary[:guarded_fit_validation_grid_passed])
    @test Bool(summary[:validation_grid_all_rows_passed])
    @test Bool(summary[:all_fit_boundary_checks_passed])
    @test Bool(summary[:experimental_spec_fit_succeeded])
    @test Bool(summary[:artifact_contract_satisfied])
    @test Bool(summary[:target_logdensity_finite])
    @test Bool(summary[:target_gradient_diagnostics_passed])
    @test Int(summary[:n_input_artifacts]) == length(input_artifacts)
    @test Int(summary[:n_fit_boundary_checks]) == length(boundary_checks)
    @test Set(String(blocker) for blocker in summary[:remaining_public_blockers]) ==
        Set(["mgmfrm_guarded_fit_public_exposure_review_missing"])
    @test String(summary[:recommendation]) ==
        "guarded_entrypoint_api_dry_run_recorded_review_public_exposure_next"
    @test String(summary[:next_gate]) ==
        "mgmfrm_guarded_fit_public_exposure_review"
end

function check_mgmfrm_guarded_fit_public_exposure_review_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_guarded_fit_public_exposure_review.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) == "minimal_confirmatory_mgmfrm_candidate"
    @test String(fixture[:status]) ==
        "guarded_fit_public_exposure_review_recorded"
    @test String(fixture[:decision]) == "enable_guarded_experimental"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])
    @test Bool(fixture[:publication_or_registration_action]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) ==
        "confirmatory_mgmfrm_guarded_fit_public_exposure_review_v1"
    @test String(protocol[:review_kind]) ==
        "local_confirmatory_mgmfrm_guarded_fit_public_exposure_review"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test Bool(protocol[:local_only])
    @test String(protocol[:entrypoint_under_review]) ==
        "fit(spec; experimental = true)"
    @test Bool(thresholds[:require_bridge_oracle_present])
    @test Bool(thresholds[:require_candidate_chain_study_passed])
    @test Bool(thresholds[:require_recovery_smoke_passed])
    @test Bool(thresholds[:require_baseline_comparison_passed])
    @test Bool(thresholds[:require_sparse_recovery_grid_passed])
    @test Bool(thresholds[:require_guarded_fit_method_wiring_passed])
    @test Bool(thresholds[:require_guarded_fit_validation_grid_passed])
    @test Bool(thresholds[:require_guarded_fit_api_dry_run_passed])
    @test Bool(thresholds[:require_dff_estimand_validation_grid_passed])
    @test Bool(thresholds[:require_fit_boundary_checks_passed])
    @test Bool(thresholds[:require_manifest_enables_guarded_mgmfrm_fit])
    @test Bool(thresholds[:require_prediction_target_and_model_weight_blocker])
    @test Bool(thresholds[:require_no_publication_or_registration_action])

    input_artifacts = fixture[:input_artifacts]
    expected_paths = Dict(
        "bridge_oracle" =>
            "test/fixtures/source_mgmfrm_bridge_logdensity.json",
        "candidate_chain_study" =>
            "test/fixtures/mgmfrm_candidate_chain_study.json",
        "recovery_smoke" =>
            "test/fixtures/mgmfrm_recovery_smoke.json",
        "baseline_comparison" =>
            "test/fixtures/mgmfrm_baseline_comparison.json",
        "sparse_recovery_grid" =>
            "test/fixtures/mgmfrm_sparse_recovery_grid.json",
        "guarded_fit_method_wiring" =>
            "test/fixtures/mgmfrm_guarded_fit_method_wiring.json",
        "guarded_fit_validation_grid" =>
            "test/fixtures/mgmfrm_guarded_fit_validation_grid.json",
        "guarded_fit_api_dry_run" =>
            "test/fixtures/mgmfrm_guarded_fit_api_dry_run.json",
        "dff_estimand_validation_grid" =>
            "test/fixtures/gmfrm_dff_estimand_validation_grid.json",
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
        @test String(row[:sha256]) ==
            file_sha256(joinpath(root, String(row[:path])))
    end

    boundary_checks = fixture[:fit_boundary_checks]
    @test length(boundary_checks) == 4
    @test all(row -> Bool(row[:passed]), boundary_checks)

    manifest = fixture[:manifest_snapshot]
    @test String(manifest[:candidate_status]) == "internal_fit_ready_candidate"
    @test String(manifest[:experimental_decision_status]) == "experimental_public"
    @test String(manifest[:experimental_decision]) == "enable_guarded_experimental"
    @test Bool(manifest[:experimental_summary][:fit_allowed])
    @test Bool(manifest[:experimental_summary][:experimental_keyword_enabled])

    review_rows = fixture[:review_rows]
    @test length(review_rows) == 11
    @test any(row -> String(row[:gate]) == "guarded_fit_api_dry_run" &&
        String(row[:status]) == "passed" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) == "current_guarded_fit_boundary" &&
        String(row[:status]) == "passed" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) ==
        "prediction_target_and_model_weight_policy" &&
        String(row[:status]) == "blocked" &&
        Bool(row[:evidence]) == false, review_rows)

    blocker_rows = fixture[:blocker_rows]
    @test length(blocker_rows) == 1
    @test String(blocker_rows[1][:blocker]) ==
        "prediction_target_and_model_weight_policy_missing"
    @test String(blocker_rows[1][:severity]) == "blocking"

    decision = fixture[:decision_record]
    @test Bool(decision[:public_fit_allowed])
    @test Bool(decision[:experimental_keyword_enabled])
    @test Bool(decision[:current_manifest_fit_allowed])
    @test Bool(decision[:current_manifest_experimental_keyword_enabled])
    @test String(decision[:public_exposure_support]) ==
        "review_recorded_guarded_fit_enabled_until_prediction_target_and_model_weight_policy"
    @test String(decision[:required_followup]) ==
        "prediction_target_and_model_weight_policy"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:reviewed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:local_only])
    @test Bool(summary[:public_fit_allowed])
    @test Bool(summary[:experimental_keyword_enabled])
    @test Bool(summary[:current_manifest_fit_allowed])
    @test Bool(summary[:current_manifest_experimental_keyword_enabled])
    @test Bool(summary[:all_input_artifacts_present])
    @test Bool(summary[:all_expected_schemas])
    @test Bool(summary[:all_input_summaries_passed])
    @test Bool(summary[:all_fit_boundary_checks_passed])
    @test Bool(summary[:current_manifest_guarded_fit_enabled])
    @test Bool(summary[:no_publication_commands])
    @test Bool(summary[:bridge_oracle_present])
    @test Bool(summary[:mgmfrm_candidate_chain_study_passed])
    @test Bool(summary[:mgmfrm_recovery_smoke_passed])
    @test Bool(summary[:mgmfrm_baseline_comparison_passed])
    @test Bool(summary[:mgmfrm_sparse_recovery_grid_passed])
    @test Bool(summary[:mgmfrm_guarded_fit_method_wiring_passed])
    @test Bool(summary[:mgmfrm_guarded_fit_validation_grid_passed])
    @test Bool(summary[:mgmfrm_guarded_fit_api_dry_run_passed])
    @test Bool(summary[:dff_estimand_validation_grid_passed])
    @test Bool(summary[:method_fit_boundary_checks_passed])
    @test Bool(summary[:method_experimental_spec_fit_succeeded])
    @test Bool(summary[:validation_all_rows_passed])
    @test Bool(summary[:api_dry_run_fit_boundary_checks_passed])
    @test Bool(summary[:api_dry_run_experimental_spec_fit_succeeded])
    @test Bool(summary[:api_dry_run_gradient_diagnostics_passed])
    @test Bool(summary[:dff_model_effects_allowed]) == false
    @test Int(summary[:n_input_artifacts]) == length(input_artifacts)
    @test Int(summary[:n_fit_boundary_checks]) == length(boundary_checks)
    @test Int(summary[:n_review_rows]) == length(review_rows)
    @test Int(summary[:n_blockers]) == length(blocker_rows)
    @test Set(String(blocker) for blocker in summary[:remaining_public_blockers]) ==
        Set(["prediction_target_and_model_weight_policy_missing"])
    @test String(summary[:recommendation]) ==
        "guarded_mgmfrm_fit_enabled_keep_weight_claims_blocked_until_policy"
    @test String(summary[:next_gate]) ==
        "prediction_target_and_model_weight_policy"
end

function check_gmfrm_prediction_target_and_model_weight_policy_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.gmfrm_prediction_target_and_model_weight_policy.v1"
    @test String(fixture[:family]) == "gmfrm"
    @test String(fixture[:scope]) ==
        "prediction_target_and_model_weight_policy"
    @test String(fixture[:status]) ==
        "prediction_target_and_model_weight_policy_recorded"
    @test String(fixture[:decision]) ==
        "select_heldout_kfold_for_local_weight_policy"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])
    @test Bool(fixture[:broader_public_fit]) == false
    @test Bool(fixture[:publication_or_registration_action]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) ==
        "gmfrm_prediction_target_and_model_weight_policy_v1"
    @test String(protocol[:review_kind]) ==
        "local_prediction_target_and_model_weight_policy"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test Bool(protocol[:local_only])
    @test String(protocol[:primary_prediction_target]) ==
        "heldout_observation_log_score"
    @test Bool(thresholds[:require_sparse_design_grid_passed])
    @test Bool(thresholds[:require_waic_influence_review_passed])
    @test Bool(thresholds[:require_psis_loo_review_passed])
    @test Bool(thresholds[:require_exact_loo_or_kfold_review_passed])
    @test Bool(thresholds[:require_guarded_scalar_fit_evidence_passed])
    @test Bool(thresholds[:require_mgmfrm_public_exposure_review_passed])
    @test Bool(thresholds[:require_dff_estimand_validation_grid_passed])
    @test Bool(thresholds[:require_same_data_waic_blocked_for_weight_claims])
    @test Bool(thresholds[:require_raw_psis_loo_blocked_for_weight_claims])
    @test Bool(thresholds[:require_heldout_kfold_target_selected])
    @test Bool(thresholds[:require_mgmfrm_weight_claims_blocked_until_public_scope_review])
    @test Bool(thresholds[:require_no_publication_or_registration_action])

    input_artifacts = fixture[:input_artifacts]
    expected_paths = Dict(
        "sparse_design_grid" =>
            "test/fixtures/gmfrm_sparse_design_grid.json",
        "waic_influence_review" =>
            "test/fixtures/gmfrm_waic_influence_review.json",
        "psis_loo_review" =>
            "test/fixtures/gmfrm_psis_loo_review.json",
        "exact_loo_or_kfold_review" =>
            "test/fixtures/gmfrm_exact_loo_or_kfold_review.json",
        "guarded_fit_api_dry_run" =>
            "test/fixtures/gmfrm_guarded_fit_api_dry_run.json",
        "guarded_fit_method_wiring" =>
            "test/fixtures/gmfrm_guarded_fit_method_wiring.json",
        "experimental_fit_validation_grid" =>
            "test/fixtures/gmfrm_experimental_fit_validation_grid.json",
        "posterior_predictive_grid" =>
            "test/fixtures/gmfrm_posterior_predictive_grid.json",
        "mgmfrm_baseline_comparison" =>
            "test/fixtures/mgmfrm_baseline_comparison.json",
        "mgmfrm_sparse_recovery_grid" =>
            "test/fixtures/mgmfrm_sparse_recovery_grid.json",
        "mgmfrm_guarded_fit_public_exposure_review" =>
            "test/fixtures/mgmfrm_guarded_fit_public_exposure_review.json",
        "dff_estimand_validation_grid" =>
            "test/fixtures/gmfrm_dff_estimand_validation_grid.json",
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
        @test String(row[:sha256]) ==
            file_sha256(joinpath(root, String(row[:path])))
    end

    target_rows = fixture[:prediction_target_rows]
    @test length(target_rows) == 3
    @test any(row -> String(row[:target]) == "same_observation_waic" &&
        String(row[:status]) == "diagnostic_only" &&
        Bool(row[:allowed_for_model_weight_claims]) == false, target_rows)
    @test any(row -> String(row[:target]) == "raw_importance_loo" &&
        String(row[:status]) == "diagnostic_only" &&
        Bool(row[:allowed_for_model_weight_claims]) == false, target_rows)
    @test any(row -> String(row[:target]) == "heldout_observation_log_score" &&
        String(row[:status]) == "selected_primary_local_target" &&
        Bool(row[:allowed_for_model_weight_claims]) &&
        Bool(row[:evidence]), target_rows)

    policy_rows = fixture[:model_weight_policy_rows]
    @test length(policy_rows) == 3
    @test any(row -> String(row[:surface]) == "scalar_gmfrm_guarded_fit" &&
        Bool(row[:allowed_for_local_model_weight_reporting]) &&
        Bool(row[:evidence]), policy_rows)
    @test any(row -> String(row[:surface]) == "confirmatory_mgmfrm_fit" &&
        String(row[:status]) == "policy_recorded_fit_allowed_weights_blocked" &&
        Bool(row[:allowed_for_local_model_weight_reporting]) == false &&
        String(row[:required_followup]) ==
            "guarded_local_mgmfrm_fit_entrypoint", policy_rows)
    @test any(row -> String(row[:surface]) == "dff_model_effects" &&
        String(row[:status]) == "validation_only" &&
        Bool(row[:allowed_for_local_model_weight_reporting]) == false,
        policy_rows)

    blockers = fixture[:blocker_rows]
    @test length(blockers) == 1
    @test String(blockers[1][:blocker]) ==
        "manual_public_scope_review_for_mgmfrm_fit_missing"
    @test String(blockers[1][:severity]) == "blocking"

    decision = fixture[:decision_record]
    @test String(decision[:selected_prediction_target]) ==
        "heldout_observation_log_score"
    @test Bool(decision[:same_data_waic_weight_claims_allowed]) == false
    @test Bool(decision[:raw_psis_loo_weight_claims_allowed]) == false
    @test Bool(decision[:scalar_local_model_weight_reporting_allowed])
    @test Bool(decision[:mgmfrm_weight_claims_allowed]) == false
    @test Bool(decision[:manuscript_sparse_mgmfrm_claims_allowed]) == false
    @test Bool(decision[:mgmfrm_fit_allowed])
    @test String(decision[:required_followup]) ==
        "manual_public_scope_review_for_mgmfrm_fit"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:policy_recorded])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:local_only])
    @test Bool(summary[:all_input_artifacts_present])
    @test Bool(summary[:all_expected_schemas])
    @test Bool(summary[:all_input_summaries_passed])
    @test Bool(summary[:same_data_waic_blocked])
    @test Bool(summary[:raw_psis_loo_blocked])
    @test Bool(summary[:heldout_kfold_selected])
    @test String(summary[:primary_prediction_target]) ==
        "heldout_observation_log_score"
    @test Bool(summary[:scalar_local_model_weight_reporting_allowed])
    @test Bool(summary[:public_model_weight_claims_allowed]) == false
    @test Bool(summary[:mgmfrm_fit_allowed])
    @test Bool(summary[:mgmfrm_weight_claims_allowed]) == false
    @test Bool(summary[:manuscript_sparse_mgmfrm_claims_allowed]) == false
    @test Bool(summary[:current_mgmfrm_manifest_guarded_fit_enabled])
    @test Bool(summary[:mgmfrm_fit_boundary_checks_passed])
    @test Bool(summary[:no_publication_commands])
    @test Int(summary[:n_input_artifacts]) == length(input_artifacts)
    @test Int(summary[:n_prediction_target_rows]) == length(target_rows)
    @test Int(summary[:n_model_weight_policy_rows]) == length(policy_rows)
    @test Int(summary[:n_blockers]) == length(blockers)
    @test Set(String(blocker) for blocker in summary[:remaining_public_blockers]) ==
        Set(["manual_public_scope_review_for_mgmfrm_fit_missing"])
    @test String(summary[:recommendation]) ==
        "use_heldout_kfold_for_local_weights_keep_mgmfrm_claims_blocked"
    @test String(summary[:next_gate]) ==
        "manual_public_scope_review_for_mgmfrm_fit"
end
