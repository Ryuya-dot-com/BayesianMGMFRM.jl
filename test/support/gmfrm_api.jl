function check_gmfrm_guarded_fit_api_dry_run_fixture(fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.gmfrm_guarded_fit_api_dry_run.v1"
    @test String(fixture[:family]) == "gmfrm"
    @test String(fixture[:scope]) == "scalar_gmfrm_fit_ready_candidate"
    @test String(fixture[:status]) == "internal_guarded_fit_api_dry_run"
    @test String(fixture[:decision]) == "keep_internal"
    @test Bool(fixture[:public_fit]) == false
    @test Bool(fixture[:experimental_public]) == false
    @test Bool(fixture[:fit_ready]) == false
    @test String(fixture[:proposed_entrypoint]) ==
        "BayesianMGMFRM.Experimental.fit(spec)"
    @test Bool(fixture[:entrypoint_enabled]) == false

    protocol = fixture[:protocol]
    rules = protocol[:decision_rules]
    @test String(protocol[:protocol_id]) ==
        "scalar_gmfrm_guarded_fit_api_dry_run_v1"
    @test String(protocol[:review_kind]) ==
        "local_guarded_fit_api_contract_dry_run"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test Bool(protocol[:dry_run_only])
    @test String(protocol[:proposed_entrypoint]) == "fit(spec; experimental = true)"
    @test Bool(protocol[:entrypoint_enabled]) == false
    @test Bool(protocol[:superseded_by_guarded_fit_method_wiring])
    @test Bool(protocol[:superseded_by_prior_likelihood_sensitivity_grid])
    @test Bool(protocol[:superseded_by_real_data_case_study])
    @test Bool(protocol[:superseded_by_claim_recovery_reproduction_archive])
    @test Bool(protocol[:superseded_by_broader_experimental_exposure_decision_review])
    @test String(protocol[:public_target_label]) ==
        "guarded_scalar_gmfrm_logdensity"
    @test String(protocol[:public_target_description]) ==
        "guarded scalar GMFRM log density"
    @test String(protocol[:internal_target_constructor]) ==
        "_gmfrm_promotion_candidate_logdensity"
    @test String(protocol[:internal_diagnostics_constructor]) ==
        "_gmfrm_promotion_candidate_diagnostics"
    @test String(protocol[:target_constructor]) ==
        "_gmfrm_promotion_candidate_logdensity"
    @test String(protocol[:diagnostics_constructor]) ==
        "_gmfrm_promotion_candidate_diagnostics"
    @test Bool(rules[:require_specified_only_public_fit_rejection])
    @test Bool(rules[:require_preview_design_experimental_keyword_rejection])
    @test Bool(rules[:require_artifact_contract_recorded])
    @test Bool(rules[:require_required_fields_recorded])
    @test Bool(rules[:require_required_provenance_recorded])
    @test Bool(rules[:require_file_evidence_present])
    @test Bool(rules[:require_finite_internal_target])
    @test Bool(rules[:require_gradient_diagnostics_passed])
    @test Bool(rules[:guarded_fit_method_wiring_required_before_public_exposure])

    rejection_checks = fixture[:fit_rejection_checks]
    @test length(rejection_checks) == 2
    public_rejection = only(row for row in rejection_checks
        if String(row[:check]) == "fit_specified_only_gmfrm")
    @test Bool(public_rejection[:rejected])
    @test String(public_rejection[:error_type]) == "ArgumentError"
    @test occursin("specified_only", String(public_rejection[:message]))
    experimental_rejection = only(row for row in rejection_checks
        if String(row[:check]) == "fit_preview_design_with_experimental_keyword")
    @test Bool(experimental_rejection[:rejected])
    @test String(experimental_rejection[:error_type]) == "MethodError"
    @test occursin("unsupported keyword argument \"experimental\"",
        String(experimental_rejection[:message]))

    contract = fixture[:artifact_contract_review]
    @test String(contract[:schema]) ==
        "bayesianmgmfrm.experimental_generalized_fit_artifact_contract.v1"
    @test String(contract[:status]) == "contract_recorded"
    @test Bool(contract[:public_fit])
    @test Bool(contract[:experimental_public])
    @test String(contract[:artifact_kind]) ==
        "experimental_generalized_fit_artifact"
    @test Int(contract[:n_required_fields]) == 20
    @test Int(contract[:n_required_provenance_artifacts]) == 4
    @test Bool(contract[:all_required_fields_recorded])
    @test Bool(contract[:all_required_provenance_recorded])
    @test Set(String(field) for field in contract[:required_field_names]) == Set([
        "schema",
        "experimental_public",
        "public_fit",
        "family",
        "scope",
        "public_target_label",
        "internal_target_constructor",
        "density_space",
        "raw_prior_control_manifest",
        "parameter_layout",
        "raw_parameter_names",
        "direct_parameter_names",
        "raw_to_direct_transform",
        "sampler_controls",
        "diagnostics",
        "pointwise_loglikelihood",
        "caveat_docs_artifact",
        "fixture_provenance",
        "raw_posterior_row_schema",
        "direct_posterior_row_schema",
    ])

    evidence_rows = fixture[:evidence_reference_rows]
    @test length(evidence_rows) >= 20
    @test all(row -> Bool(row[:exists]), evidence_rows)
    self_reference = only(row for row in evidence_rows
        if String(row[:evidence]) == "guarded_fit_api_dry_run")
    @test String(self_reference[:reference_kind]) == "current_artifact_self"
    @test String(self_reference[:artifact]) ==
        "test/fixtures/gmfrm_guarded_fit_api_dry_run.json"
    broader_reference = only(row for row in evidence_rows
        if String(row[:evidence]) == "broader_experimental_exposure_decision_review")
    @test String(broader_reference[:reference_kind]) ==
        "broader_review_cycle_break"
    @test isnothing(broader_reference[:sha256])
    manuscript_reference = only(row for row in evidence_rows
        if String(row[:evidence]) == "manuscript_scale_simulation_grid")
    @test String(manuscript_reference[:reference_kind]) ==
        "manuscript_grid_cycle_break"
    @test isnothing(manuscript_reference[:sha256])
    full_archive_reference = only(row for row in evidence_rows
        if String(row[:evidence]) == "full_paper_reproduction_archive")
    @test String(full_archive_reference[:reference_kind]) ==
        "full_archive_cycle_break"
    @test isnothing(full_archive_reference[:sha256])
    for row in evidence_rows
        String(row[:reference_kind]) == "local_file" || continue
        path = first(split(String(row[:artifact]), '#'; limit = 2))
        reference_kind = splitext(path)[2] in
            (".jl", ".md", ".toml", ".yml", ".yaml") ?
            :code_doc : :generated_artifact
        integrity = ScientificPayloadDigest.reference_integrity_status(
            String(row[:sha256]),
            file_sha256(joinpath(root, path));
            reference_kind,
        )
        @test integrity.provenance_policy_accepted
    end

    target = fixture[:target_dry_run]
    @test String(target[:public_target_label]) ==
        "guarded_scalar_gmfrm_logdensity"
    @test String(target[:public_target_description]) ==
        "guarded scalar GMFRM log density"
    @test String(target[:internal_target_constructor]) ==
        "_gmfrm_promotion_candidate_logdensity"
    @test String(target[:internal_diagnostics_constructor]) ==
        "_gmfrm_promotion_candidate_diagnostics"
    @test String(target[:target]) == "_gmfrm_promotion_candidate_logdensity"
    @test String(target[:diagnostics]) == "_gmfrm_promotion_candidate_diagnostics"
    @test Int(target[:n_raw_parameters]) == length(target[:raw_parameter_names])
    @test Int(target[:n_checked_gradient_coordinates]) == 6
    @test Bool(target[:finite_logdensity])
    @test isfinite(Float64(target[:logdensity]))
    @test String(target[:diagnostics_flag]) == "ok"
    @test Bool(target[:diagnostics_passed])
    @test Int(target[:n_failed_gradient_checks]) == 0
    @test Float64(target[:max_abs_error]) <= Float64(target[:max_tolerance])

    manifest = fixture[:manifest_snapshot]
    @test String(manifest[:candidate_status]) == "internal_promotion_candidate"
    @test String(manifest[:compiler_stage]) == "fit_ready_candidate"
    @test String(manifest[:public_target_label]) ==
        "guarded_scalar_gmfrm_logdensity"
    @test String(manifest[:public_target_description]) ==
        "guarded scalar GMFRM log density"
    @test String(manifest[:internal_target_constructor]) ==
        "_gmfrm_promotion_candidate_logdensity"
    @test String(manifest[:internal_diagnostic_constructor]) ==
        "_gmfrm_promotion_candidate_diagnostics"
    @test String(manifest[:internal_sampler_diagnostic_constructor]) ==
        "_gmfrm_promotion_candidate_sampler_diagnostics"
    policy = manifest[:rater_step_public_option_policy]
    @test String(policy[:schema]) ==
        "bayesianmgmfrm.gmfrm_rater_step_public_option_policy.v1"
    @test String(policy[:source_block]) == "rater_steps"
    @test String(policy[:source_block_status]) == "internal_source_model_block"
    @test Bool(policy[:internal_block_enabled])
    @test String(policy[:public_option]) == "rater_steps"
    @test Bool(policy[:public_keyword_enabled]) == false
    @test String(policy[:public_option_status]) == "blocked_until_policy_gate"
    @test String(policy[:blocker]) ==
        "rater_step_public_option_policy_not_promoted"
    @test String(policy[:next_gate]) == "rater_step_public_option_policy"
    item_decision = manifest[:item_discrimination_promotion_decision]
    @test String(item_decision[:schema]) ==
        "bayesianmgmfrm.gmfrm_item_discrimination_promotion_decision.v1"
    @test String(item_decision[:decision]) == "keep_preview_only_for_v0_1_1"
    @test String(item_decision[:source_block]) == "item_discrimination"
    @test Bool(item_decision[:public_fit_enabled]) == false
    @test Bool(item_decision[:internal_promotion_target_enabled]) == false
    @test String(item_decision[:next_gate]) ==
        "item_discrimination_promotion_decision"
    @test Bool(manifest[:experimental_public_ready])
    @test String(manifest[:decision_public_target_label]) ==
        "guarded_scalar_gmfrm_logdensity"
    @test String(manifest[:decision_internal_target_constructor]) ==
        "_gmfrm_promotion_candidate_logdensity"
    decision_policy = manifest[:decision_rater_step_public_option_policy]
    @test String(decision_policy[:public_option]) == "rater_steps"
    @test Bool(decision_policy[:public_keyword_enabled]) == false
    @test String(decision_policy[:next_gate]) ==
        "rater_step_public_option_policy"
    decision_item = manifest[:decision_item_discrimination_promotion_decision]
    @test String(decision_item[:decision]) == "keep_preview_only_for_v0_1_1"
    @test String(decision_item[:blocked_option]) == "discrimination"
    @test String(decision_item[:blocked_value]) == "item"
    @test String(decision_item[:next_gate]) ==
        "item_discrimination_promotion_decision"
    @test String(manifest[:experimental_decision_status]) == "experimental_public"
    @test String(manifest[:experimental_decision]) == "enable_guarded_experimental"
    @test Bool(manifest[:experimental_summary][:fit_allowed])
    @test Bool(manifest[:experimental_summary][:canonical_namespace_enabled])
    @test Bool(manifest[:experimental_summary][:experimental_keyword_enabled])
    @test String(manifest[:experimental_summary][:legacy_keyword_status]) ==
        "compatibility_only"
    @test Int(manifest[:experimental_summary][:n_evidence_done]) >= 25
    @test String(manifest[:experimental_summary][:next_gate]) ==
        "manual_publication_or_registration_by_user_only"

    decision = fixture[:decision_record]
    @test Bool(decision[:public_fit_allowed]) == false
    @test Bool(decision[:experimental_keyword_enabled]) == false
    @test Bool(decision[:current_manifest_fit_allowed])
    @test Bool(decision[:current_manifest_experimental_keyword_enabled])
    @test String(decision[:public_exposure_support]) ==
        "guarded_scalar_gmfrm_only"
    @test String(decision[:interpretation]) ==
        "guarded_entrypoint_contract_dry_run_superseded_by_broader_exposure_decision_review"
    @test String(decision[:required_followup]) ==
        "manual_publication_or_registration_by_user_only"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:dry_run_only])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:entrypoint_enabled]) == false
    @test Bool(summary[:superseded_by_guarded_fit_method_wiring])
    @test Bool(summary[:superseded_by_experimental_fit_validation_grid])
    @test Bool(summary[:superseded_by_posterior_predictive_grid])
    @test Bool(summary[:superseded_by_sparse_pathology_recovery_grid])
    @test Bool(summary[:superseded_by_prior_likelihood_sensitivity_grid])
    @test Bool(summary[:superseded_by_real_data_case_study])
    @test Bool(summary[:superseded_by_claim_recovery_reproduction_archive])
    @test Bool(summary[:superseded_by_broader_experimental_exposure_decision_review])
    @test Bool(summary[:superseded_by_full_paper_reproduction_archive])
    @test Bool(summary[:public_fit_allowed]) == false
    @test Bool(summary[:experimental_keyword_enabled]) == false
    @test Bool(summary[:current_manifest_fit_allowed])
    @test Bool(summary[:current_manifest_experimental_keyword_enabled])
    @test Bool(summary[:fit_rejects_specified_only_gmfrm])
    @test Bool(summary[:fit_preview_rejects_experimental_keyword])
    @test Bool(summary[:artifact_contract_recorded])
    @test Bool(summary[:all_required_artifact_fields_recorded])
    @test Bool(summary[:all_required_provenance_artifacts_recorded])
    @test Bool(summary[:all_file_evidence_present])
    @test Bool(summary[:rater_step_public_option_policy_recorded])
    @test Bool(summary[:item_discrimination_promotion_decision_recorded])
    @test Bool(summary[:target_logdensity_finite])
    @test Bool(summary[:target_diagnostics_passed])
    @test isempty(summary[:remaining_public_blockers])
    @test String(summary[:recommendation]) ==
        "full_archive_recorded_keep_guarded_scalar_gmfrm_only"
    @test String(summary[:next_gate]) ==
        "manual_publication_or_registration_by_user_only"
end

function check_gmfrm_guarded_fit_method_wiring_fixture(fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.gmfrm_guarded_fit_method_wiring.v1"
    @test String(fixture[:family]) == "gmfrm"
    @test String(fixture[:scope]) == "scalar_gmfrm_fit_ready_candidate"
    @test String(fixture[:status]) == "guarded_experimental_fit_method_wired"
    @test String(fixture[:decision]) == "enable_guarded_experimental"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])
    @test String(fixture[:proposed_entrypoint]) == "fit(spec; experimental = true)"
    @test Bool(fixture[:entrypoint_enabled])

    protocol = fixture[:protocol]
    sampler = protocol[:sampler]
    rules = protocol[:decision_rules]
    @test String(protocol[:protocol_id]) ==
        "scalar_gmfrm_guarded_fit_method_wiring_v1"
    @test String(protocol[:review_kind]) ==
        "local_guarded_experimental_fit_method_wiring"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test String(protocol[:proposed_entrypoint]) == "fit(spec; experimental = true)"
    @test Bool(protocol[:entrypoint_enabled])
    @test String(protocol[:public_target_label]) ==
        "guarded_scalar_gmfrm_logdensity"
    @test String(protocol[:public_target_description]) ==
        "guarded scalar GMFRM log density"
    @test String(protocol[:internal_target_constructor]) ==
        "_gmfrm_promotion_candidate_logdensity"
    @test String(protocol[:internal_diagnostics_constructor]) ==
        "_gmfrm_promotion_candidate_sampler_diagnostics"
    @test String(sampler[:backend]) == "advancedhmc"
    @test String(sampler[:sampler]) == "nuts"
    @test Int(sampler[:chains]) == 2
    @test Int(sampler[:warmup]) == 4
    @test Int(sampler[:draws]) == 4
    @test Int(sampler[:max_depth]) == 8
    @test String(sampler[:metric]) == "unit"
    @test Float64(sampler[:rhat_threshold]) == 100.0
    @test Float64(sampler[:ess_threshold]) == 1.0
    @test Bool(rules[:require_guarded_experimental_fit_success])
    @test Bool(rules[:require_artifact_contract_satisfied])
    @test Bool(rules[:require_unsupported_public_options_rejected])
    @test Bool(rules[:sparse_pathology_recovery_grid_required_before_broader_exposure])

    manifest = fixture[:manifest_snapshot]
    @test String(manifest[:candidate_status]) == "internal_promotion_candidate"
    @test String(manifest[:compiler_stage]) == "fit_ready_candidate"
    @test String(manifest[:public_target_label]) ==
        "guarded_scalar_gmfrm_logdensity"
    @test String(manifest[:public_target_description]) ==
        "guarded scalar GMFRM log density"
    @test String(manifest[:internal_target_constructor]) ==
        "_gmfrm_promotion_candidate_logdensity"
    @test String(manifest[:internal_diagnostic_constructor]) ==
        "_gmfrm_promotion_candidate_diagnostics"
    @test String(manifest[:internal_sampler_diagnostic_constructor]) ==
        "_gmfrm_promotion_candidate_sampler_diagnostics"
    policy = manifest[:rater_step_public_option_policy]
    @test String(policy[:schema]) ==
        "bayesianmgmfrm.gmfrm_rater_step_public_option_policy.v1"
    @test String(policy[:source_block]) == "rater_steps"
    @test String(policy[:source_block_status]) == "internal_source_model_block"
    @test Bool(policy[:internal_block_enabled])
    @test String(policy[:public_option]) == "rater_steps"
    @test Bool(policy[:public_keyword_enabled]) == false
    @test String(policy[:public_option_status]) == "blocked_until_policy_gate"
    @test String(policy[:blocker]) ==
        "rater_step_public_option_policy_not_promoted"
    @test String(policy[:next_gate]) == "rater_step_public_option_policy"
    item_decision = manifest[:item_discrimination_promotion_decision]
    @test String(item_decision[:schema]) ==
        "bayesianmgmfrm.gmfrm_item_discrimination_promotion_decision.v1"
    @test String(item_decision[:decision]) == "keep_preview_only_for_v0_1_1"
    @test String(item_decision[:source_block]) == "item_discrimination"
    @test Bool(item_decision[:public_fit_enabled]) == false
    @test Bool(item_decision[:internal_promotion_target_enabled]) == false
    @test String(item_decision[:next_gate]) ==
        "item_discrimination_promotion_decision"
    @test Bool(manifest[:experimental_public_ready])
    @test String(manifest[:decision_public_target_label]) ==
        "guarded_scalar_gmfrm_logdensity"
    @test String(manifest[:decision_internal_target_constructor]) ==
        "_gmfrm_promotion_candidate_logdensity"
    decision_policy = manifest[:decision_rater_step_public_option_policy]
    @test String(decision_policy[:public_option]) == "rater_steps"
    @test Bool(decision_policy[:public_keyword_enabled]) == false
    @test String(decision_policy[:next_gate]) ==
        "rater_step_public_option_policy"
    decision_item = manifest[:decision_item_discrimination_promotion_decision]
    @test String(decision_item[:decision]) == "keep_preview_only_for_v0_1_1"
    @test String(decision_item[:blocked_option]) == "discrimination"
    @test String(decision_item[:blocked_value]) == "item"
    @test String(decision_item[:next_gate]) ==
        "item_discrimination_promotion_decision"
    @test String(manifest[:experimental_decision_status]) == "experimental_public"
    @test String(manifest[:experimental_decision]) == "enable_guarded_experimental"
    @test Bool(manifest[:experimental_summary][:fit_allowed])
    @test Bool(manifest[:experimental_summary][:experimental_keyword_enabled])
    @test Int(manifest[:experimental_summary][:n_evidence_done]) >= 23
    @test String(manifest[:experimental_summary][:next_gate]) ==
        "manual_publication_or_registration_by_user_only"

    fit_record = fixture[:fit_record]
    @test String(fit_record[:type]) == "GMFRMFit"
    @test String(fit_record[:backend]) == "advancedhmc"
    @test String(fit_record[:sampler]) == "nuts"
    @test Vector{Int}(fit_record[:raw_draws_shape]) == [8, 17]
    @test Vector{Int}(fit_record[:direct_draws_shape]) == [8, 19]
    @test Vector{Int}(fit_record[:pointwise_loglikelihood_shape]) == [8, 36]
    @test Int(fit_record[:n_chain_acceptance_rates]) == 2
    @test Int(fit_record[:n_sampler_stats]) == 8

    metadata = fixture[:metadata_review]
    @test String(metadata[:family]) == "gmfrm"
    @test Int(metadata[:dimensions]) == 1
    @test String(metadata[:discrimination]) == "rater"
    @test Bool(metadata[:public_fit])
    @test Bool(metadata[:experimental_public])
    @test String(metadata[:density_space]) == "raw_unconstrained"
    @test Int(metadata[:n_draws]) == 8
    @test Int(metadata[:n_chains]) == 2
    @test Int(metadata[:draws_per_chain]) == 4

    diagnostics_review = fixture[:diagnostics_review]
    @test String(diagnostics_review[:schema]) ==
        "bayesianmgmfrm.gmfrm_experimental_fit_diagnostics.v1"
    @test Bool(diagnostics_review[:public_fit])
    @test Bool(diagnostics_review[:experimental_public])
    diagnostic_summary = diagnostics_review[:summary]
    @test String(diagnostic_summary[:flag]) == "ok"
    @test Bool(diagnostic_summary[:passed])
    @test Int(diagnostic_summary[:n_sampler_warnings]) == 0
    @test Int(diagnostic_summary[:n_divergences]) == 0
    @test Int(diagnostic_summary[:n_max_treedepth]) == 0
    @test Int(diagnostic_summary[:n_failed_direct_constraints]) == 0

    contract = fixture[:artifact_contract_review]
    @test String(contract[:schema]) ==
        "bayesianmgmfrm.experimental_generalized_fit_artifact_contract.v1"
    @test Bool(contract[:public_fit])
    @test Bool(contract[:experimental_public])
    @test String(contract[:artifact_kind]) ==
        "experimental_generalized_fit_artifact"
    @test Int(contract[:n_required_fields]) == 20
    @test Int(contract[:n_required_provenance_artifacts]) == 4
    @test Bool(contract[:all_required_fields_present])
    @test Bool(contract[:all_required_provenance_recorded])
    @test Bool(contract[:enables_public_fit])

    artifact = fixture[:artifact_review]
    @test String(artifact[:schema]) ==
        "bayesianmgmfrm.gmfrm_experimental_fit_artifact.v1"
    @test String(artifact[:status]) == "experimental_public_fit_artifact"
    @test Bool(artifact[:public_fit])
    @test Bool(artifact[:experimental_public])
    @test Bool(artifact[:fit_ready])
    @test String(artifact[:public_target_label]) ==
        "guarded_scalar_gmfrm_logdensity"
    @test String(artifact[:public_target_description]) ==
        "guarded scalar GMFRM log density"
    @test String(artifact[:internal_target_constructor]) ==
        "_gmfrm_promotion_candidate_logdensity"
    @test String(artifact[:internal_sampler_diagnostic_constructor]) ==
        "_gmfrm_promotion_candidate_sampler_diagnostics"
    @test String(artifact[:density_space]) == "raw_unconstrained"
    @test String(artifact[:raw_prior_control_schema]) ==
        "bayesianmgmfrm.generalized_raw_prior_control_manifest.v1"
    @test Int(artifact[:n_raw_prior_control_rows]) == 7
    @test Bool(artifact[:raw_prior_control_all_active_scales_resolved])
    @test !Bool(artifact[:raw_prior_control_direct_scale_priors_enabled])
    @test Vector{Int}(artifact[:pointwise_loglikelihood_shape]) == [8, 36]
    @test String(artifact[:caveat_docs_artifact]) ==
        "docs/src/fitting.md#guarded-generalized-model-caveats"
    @test Int(artifact[:n_fixture_provenance_rows]) == 4

    @test Bool(fixture[:waic_review][:all_top_level_numeric_finite])
    @test Bool(fixture[:loo_review][:all_top_level_numeric_finite])
    @test Int(fixture[:information_criterion_rows][:n_waic_rows]) == 36
    @test Int(fixture[:information_criterion_rows][:n_loo_rows]) == 36

    rejection_checks = fixture[:fit_rejection_checks]
    @test length(rejection_checks) == 6
    @test all(check -> Bool(check[:rejected]), rejection_checks)
    @test Set(String(check[:check]) for check in rejection_checks) == Set([
        "fit_specified_only_gmfrm_without_experimental",
        "fit_preview_design_with_experimental_keyword",
        "fit_experimental_unsupported_backend",
        "fit_experimental_public_mfrm_prior",
        "fit_experimental_dff_effects",
        "fit_experimental_non_rater_discrimination",
    ])
    rejection_by_check =
        Dict(Symbol(check[:check]) => check for check in rejection_checks)
    @test String(
        rejection_by_check[:fit_experimental_unsupported_backend][:blocked_option],
    ) == "backend"
    @test String(rejection_by_check[:fit_experimental_unsupported_backend][:next_gate]) ==
        "advancedhmc_guarded_sampler_policy"
    @test String(
        rejection_by_check[:fit_experimental_public_mfrm_prior][:blocked_option],
    ) == "prior"
    @test String(rejection_by_check[:fit_experimental_public_mfrm_prior][:next_gate]) ==
        "scalar_gmfrm_prior_likelihood_sensitivity_grid"
    @test String(
        rejection_by_check[:fit_experimental_dff_effects][:blocked_option],
    ) == "dff_effects"
    @test String(rejection_by_check[:fit_experimental_dff_effects][:next_gate]) ==
        "gmfrm_dff_estimand_validation_grid"
    @test String(
        rejection_by_check[:fit_experimental_non_rater_discrimination][:blocked_option],
    ) == "discrimination"
    @test String(
        rejection_by_check[:fit_experimental_non_rater_discrimination][:next_gate],
    ) == "item_discrimination_promotion_decision"
    for check_name in (
            :fit_experimental_unsupported_backend,
            :fit_experimental_public_mfrm_prior,
            :fit_experimental_dff_effects,
            :fit_experimental_non_rater_discrimination)
        message = String(rejection_by_check[check_name][:message])
        @test occursin("does not support", message)
        @test occursin("Supported configuration:", message)
        @test !occursin("blocked_option", message)
        @test !occursin("next_gate", message)
        @test Bool(rejection_by_check[check_name][:actionable_gate_message])
    end

    decision = fixture[:decision_record]
    @test Bool(decision[:public_fit_allowed])
    @test Bool(decision[:experimental_keyword_enabled])
    @test String(decision[:public_exposure_support]) ==
        "satisfied_by_sparse_pathology_recovery_grid"
    @test String(decision[:interpretation]) ==
        "guarded_scalar_gmfrm_experimental_fit_method_wired_validated_ppc_and_sparse_pathology_checked_locally"
    @test String(decision[:required_followup]) ==
        "scalar_gmfrm_prior_likelihood_sensitivity_grid"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:entrypoint_enabled])
    @test Bool(summary[:public_fit_allowed])
    @test Bool(summary[:experimental_keyword_enabled])
    @test Bool(summary[:gmfrm_fit_returned])
    @test Bool(summary[:artifact_contract_satisfied])
    @test Bool(summary[:pointwise_loglikelihood_shape_valid])
    @test Bool(summary[:waic_and_loo_finite])
    @test Bool(summary[:all_unsupported_public_options_rejected])
    @test Bool(summary[:actionable_gate_messages_passed])
    @test Int(summary[:n_actionable_gate_messages]) >= 4
    @test Bool(summary[:rater_step_public_option_policy_recorded])
    @test Bool(summary[:item_discrimination_promotion_decision_recorded])
    @test Bool(summary[:superseded_by_experimental_fit_validation_grid])
    @test Bool(summary[:superseded_by_posterior_predictive_grid])
    @test Bool(summary[:superseded_by_sparse_pathology_recovery_grid])
    @test Set(String(blocker) for blocker in summary[:remaining_public_blockers]) ==
        Set(["scalar_gmfrm_prior_likelihood_sensitivity_grid_missing"])
    @test String(summary[:recommendation]) ==
        "keep_guarded_experimental_until_prior_likelihood_sensitivity_grid"
    @test String(summary[:next_gate]) ==
        "scalar_gmfrm_prior_likelihood_sensitivity_grid"
end

function check_gmfrm_experimental_fit_validation_grid_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.gmfrm_experimental_fit_validation_grid.v1"
    @test String(fixture[:family]) == "gmfrm"
    @test String(fixture[:scope]) == "scalar_gmfrm_fit_ready_candidate"
    @test String(fixture[:status]) ==
        "guarded_experimental_fit_validation_grid_recorded"
    @test String(fixture[:decision]) == "keep_guarded_experimental"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])

    protocol = fixture[:protocol]
    sampler = protocol[:sampler]
    diagnostics = protocol[:diagnostics]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) ==
        "scalar_gmfrm_experimental_fit_validation_grid_v1"
    @test String(protocol[:review_kind]) ==
        "local_guarded_experimental_fit_validation_grid"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test Bool(protocol[:superseded_by_sparse_pathology_recovery_grid])
    @test String(protocol[:entrypoint_under_validation]) ==
        "fit(spec; experimental = true)"
    @test String(protocol[:simulation_source]) ==
        "scalar_gmfrm_baseline_calibration_grid_scenarios"
    @test Int(protocol[:data_grid][:observations]) == 36
    @test String(sampler[:backend]) == "advancedhmc"
    @test String(sampler[:sampler]) == "nuts"
    @test Int(sampler[:chains]) == 2
    @test Int(sampler[:warmup]) == 12
    @test Int(sampler[:draws]) == 12
    @test Int(sampler[:max_depth]) == 8
    @test String(sampler[:metric]) == "unit"
    @test String(sampler[:ad_backend]) == "ForwardDiff"
    @test Bool(sampler[:split_chains])
    @test Float64(diagnostics[:rhat_threshold]) == 100.0
    @test Float64(diagnostics[:ess_threshold]) == 1.0
    @test Int(diagnostics[:loo_min_tail_draws]) == 5
    @test Int(thresholds[:n_scenarios]) == 3
    @test Int(thresholds[:n_observations]) == 36
    @test Bool(thresholds[:require_guarded_fit_returned])
    @test Bool(thresholds[:require_public_fit_metadata])
    @test Bool(thresholds[:require_artifact_contract_satisfied])
    @test Bool(thresholds[:require_pointwise_shape])
    @test Bool(thresholds[:require_information_criteria_finite])
    @test Bool(thresholds[:require_no_divergences])
    @test Bool(thresholds[:require_no_max_treedepth])
    @test Bool(thresholds[:require_no_failed_direct_constraints])
    @test Float64(thresholds[:max_direct_parameter_mean_absolute_error]) == 5.0
    @test Float64(thresholds[:max_direct_block_mean_absolute_error]) == 3.0

    scenarios = fixture[:scenarios]
    @test length(scenarios) == 3
    @test Set(String(row[:scenario]) for row in scenarios) == Set([
        "near_rasch",
        "moderate_generalized",
        "stronger_generalized",
    ])
    for scenario in scenarios
        @test Int(scenario[:simulated_data][:n_observations]) == 36
        @test length(scenario[:simulated_data][:score_counts]) >= 1
        @test length(scenario[:simulated_data][:person_levels]) == 4
        @test length(scenario[:simulated_data][:rater_levels]) == 3
        @test length(scenario[:simulated_data][:item_levels]) == 3
        fit_record = scenario[:fit_record]
        @test String(fit_record[:type]) == "GMFRMFit"
        @test String(fit_record[:backend]) == "advancedhmc"
        @test String(fit_record[:sampler]) == "nuts"
        @test Vector{Int}(fit_record[:raw_draws_shape]) == [24, 17]
        @test Vector{Int}(fit_record[:direct_draws_shape]) == [24, 19]
        @test Vector{Int}(fit_record[:pointwise_loglikelihood_shape]) == [24, 36]

        metadata = scenario[:metadata_review]
        @test Bool(metadata[:public_fit])
        @test Bool(metadata[:experimental_public])
        @test String(metadata[:family]) == "gmfrm"
        @test Int(metadata[:dimensions]) == 1
        @test String(metadata[:discrimination]) == "rater"
        @test Int(metadata[:n_draws]) == 24
        @test Int(metadata[:n_chains]) == 2
        @test Int(metadata[:draws_per_chain]) == 12
        @test Int(metadata[:n_parameters]) == 17
        @test Int(metadata[:n_direct_parameters]) == 19

        diagnostic_summary = scenario[:diagnostics_review][:summary]
        @test String(scenario[:diagnostics_review][:schema]) ==
            "bayesianmgmfrm.gmfrm_experimental_fit_diagnostics.v1"
        @test Bool(scenario[:diagnostics_review][:public_fit])
        @test Bool(scenario[:diagnostics_review][:experimental_public])
        @test String(diagnostic_summary[:flag]) == "ok"
        @test Bool(diagnostic_summary[:passed])
        @test Int(diagnostic_summary[:n_divergences]) == 0
        @test Int(diagnostic_summary[:n_max_treedepth]) == 0
        @test Int(diagnostic_summary[:n_failed_direct_constraints]) == 0
        @test Int(diagnostic_summary[:n_nonfinite_logdensity]) == 0
        @test Int(diagnostic_summary[:n_nonfinite_direct_loglikelihood]) == 0

        artifact = scenario[:artifact_review]
        @test String(artifact[:schema]) ==
            "bayesianmgmfrm.gmfrm_experimental_fit_artifact.v1"
        @test Bool(artifact[:public_fit])
        @test Bool(artifact[:experimental_public])
        @test Bool(artifact[:fit_ready])
        @test String(artifact[:density_space]) == "raw_unconstrained"
        @test String(artifact[:raw_prior_control_schema]) ==
            "bayesianmgmfrm.generalized_raw_prior_control_manifest.v1"
        @test Int(artifact[:n_raw_prior_control_rows]) == 7
        @test Bool(artifact[:raw_prior_control_all_active_scales_resolved])
        @test !Bool(artifact[:raw_prior_control_direct_scale_priors_enabled])
        @test Vector{Int}(artifact[:pointwise_loglikelihood_shape]) == [24, 36]
        @test Int(artifact[:n_fixture_provenance_rows]) == 4

        contract = scenario[:artifact_contract_review]
        @test String(contract[:schema]) ==
            "bayesianmgmfrm.experimental_generalized_fit_artifact_contract.v1"
        @test Bool(contract[:public_fit])
        @test Bool(contract[:experimental_public])
        @test String(contract[:artifact_kind]) ==
            "experimental_generalized_fit_artifact"
        @test Int(contract[:n_required_fields]) == 20
        @test Int(contract[:n_required_provenance_artifacts]) == 4
        @test Bool(contract[:all_required_fields_present])
        @test Bool(contract[:all_required_provenance_recorded])
        @test Bool(contract[:enables_public_fit])

        @test Bool(scenario[:waic_review][:all_top_level_numeric_finite])
        @test Bool(scenario[:loo_review][:all_top_level_numeric_finite])
        @test Int(scenario[:information_criterion_rows][:n_waic_rows]) == 36
        @test Int(scenario[:information_criterion_rows][:n_loo_rows]) == 36
        @test length(scenario[:direct_recovery_rows]) == 19
        @test all(row -> Bool(row[:finite]), scenario[:direct_recovery_rows])
        @test all(row -> Bool(row[:all_finite]),
            scenario[:direct_recovery_by_block])

        scenario_summary = scenario[:summary]
        @test Bool(scenario_summary[:passed])
        @test Bool(scenario_summary[:pointwise_shape_valid])
        @test Bool(scenario_summary[:artifact_contract_satisfied])
        @test Bool(scenario_summary[:information_criteria_finite])
        @test Int(scenario_summary[:n_divergences]) == 0
        @test Int(scenario_summary[:n_max_treedepth]) == 0
        @test Int(scenario_summary[:n_failed_direct_constraints]) == 0
        @test Int(scenario_summary[:n_nonfinite_logdensity]) == 0
        @test Int(scenario_summary[:n_nonfinite_direct_loglikelihood]) == 0
        @test Float64(scenario_summary[:max_direct_parameter_mean_absolute_error]) <=
            Float64(thresholds[:max_direct_parameter_mean_absolute_error])
        @test Float64(scenario_summary[:max_direct_block_mean_absolute_error]) <=
            Float64(thresholds[:max_direct_block_mean_absolute_error])
    end

    decision = fixture[:decision_record]
    @test Bool(decision[:public_fit_allowed])
    @test Bool(decision[:experimental_keyword_enabled])
    @test String(decision[:public_exposure_support]) ==
        "satisfied_by_sparse_pathology_recovery_grid"
    @test String(decision[:interpretation]) ==
        "guarded_scalar_gmfrm_experimental_fit_validation_grid_passed_ppc_and_sparse_pathology_checked"
    @test String(decision[:required_followup]) ==
        "scalar_gmfrm_prior_likelihood_sensitivity_grid"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:superseded_by_posterior_predictive_grid])
    @test Bool(summary[:superseded_by_sparse_pathology_recovery_grid])
    @test Int(summary[:n_scenarios]) == 3
    @test Int(summary[:n_passed_scenarios]) == 3
    @test Int(summary[:n_total_draws_per_scenario]) == 24
    @test Bool(summary[:all_guarded_fit_returned])
    @test Bool(summary[:all_artifact_contracts_satisfied])
    @test Bool(summary[:all_pointwise_shapes_valid])
    @test Bool(summary[:all_information_criteria_finite])
    @test Bool(summary[:all_no_divergences])
    @test Bool(summary[:all_no_max_treedepth])
    @test Bool(summary[:all_no_failed_direct_constraints])
    @test Float64(summary[:max_direct_parameter_mean_absolute_error]) <=
        Float64(thresholds[:max_direct_parameter_mean_absolute_error])
    @test Float64(summary[:max_direct_block_mean_absolute_error]) <=
        Float64(thresholds[:max_direct_block_mean_absolute_error])
    @test Set(String(blocker) for blocker in summary[:remaining_public_blockers]) ==
        Set(["scalar_gmfrm_prior_likelihood_sensitivity_grid_missing"])
    @test String(summary[:recommendation]) ==
        "keep_guarded_experimental_until_prior_likelihood_sensitivity_grid"
    @test String(summary[:next_gate]) ==
        "scalar_gmfrm_prior_likelihood_sensitivity_grid"
end

function check_gmfrm_posterior_predictive_grid_fixture(fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.gmfrm_posterior_predictive_grid.v1"
    @test String(fixture[:family]) == "gmfrm"
    @test String(fixture[:scope]) == "scalar_gmfrm_fit_ready_candidate"
    @test String(fixture[:status]) ==
        "guarded_experimental_posterior_predictive_grid_recorded"
    @test String(fixture[:decision]) == "keep_guarded_experimental"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])

    protocol = fixture[:protocol]
    sampler = protocol[:sampler]
    diagnostics = protocol[:diagnostics]
    posterior_predictive = protocol[:posterior_predictive]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) ==
        "scalar_gmfrm_posterior_predictive_grid_v1"
    @test String(protocol[:review_kind]) ==
        "local_guarded_experimental_posterior_predictive_grid"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test Bool(protocol[:superseded_by_sparse_pathology_recovery_grid])
    @test String(protocol[:entrypoint_under_validation]) ==
        "posterior_predictive_check(fit(spec; experimental = true))"
    @test String(protocol[:simulation_source]) ==
        "scalar_gmfrm_experimental_fit_validation_grid_scenarios"
    @test Int(protocol[:data_grid][:observations]) == 36
    @test String(sampler[:backend]) == "advancedhmc"
    @test String(sampler[:sampler]) == "nuts"
    @test Int(sampler[:chains]) == 2
    @test Int(sampler[:warmup]) == 12
    @test Int(sampler[:draws]) == 12
    @test Int(sampler[:max_depth]) == 8
    @test String(sampler[:metric]) == "unit"
    @test String(sampler[:ad_backend]) == "ForwardDiff"
    @test Bool(sampler[:split_chains])
    @test Float64(diagnostics[:rhat_threshold]) == 100.0
    @test Float64(diagnostics[:ess_threshold]) == 1.0
    @test Int(diagnostics[:loo_min_tail_draws]) == 5
    @test String(posterior_predictive[:draw_policy]) == "all_fit_draws"
    @test Float64(posterior_predictive[:interval]) == 0.9
    @test Int(posterior_predictive[:calibration_bins]) == 3
    @test String(posterior_predictive[:category_calibration]) ==
        "highest_observed_category"
    @test Int(thresholds[:n_scenarios]) == 3
    @test Int(thresholds[:n_observations]) == 36
    @test Int(thresholds[:n_replicates_per_scenario]) == 24
    @test Int(thresholds[:n_summary_rows]) == 14
    @test Bool(thresholds[:require_ppc_returned])
    @test Bool(thresholds[:require_replicated_scores_in_categories])
    @test Bool(thresholds[:require_probability_sums])
    @test Bool(thresholds[:require_summary_rows_finite])
    @test Bool(thresholds[:require_mean_score_inside_interval])
    @test Bool(thresholds[:require_calibration_rows_finite])

    reviewed = fixture[:reviewed_artifacts]
    @test length(reviewed) == 1
    reviewed_validation_grid = only(reviewed)
    @test String(reviewed_validation_grid[:artifact]) ==
        "test/fixtures/gmfrm_experimental_fit_validation_grid.json"
    @test Bool(reviewed_validation_grid[:exists])
    @test String(reviewed_validation_grid[:sha256]) ==
        file_sha256(joinpath(root, String(reviewed_validation_grid[:artifact])))

    scenarios = fixture[:scenarios]
    @test length(scenarios) == 3
    @test Set(String(row[:scenario]) for row in scenarios) == Set([
        "near_rasch",
        "moderate_generalized",
        "stronger_generalized",
    ])
    for scenario in scenarios
        @test Int(scenario[:simulated_data][:n_observations]) == 36
        @test length(scenario[:simulated_data][:score_counts]) >= 1
        @test length(scenario[:simulated_data][:person_levels]) == 4
        @test length(scenario[:simulated_data][:rater_levels]) == 3
        @test length(scenario[:simulated_data][:item_levels]) == 3
        @test Vector{Int}(scenario[:simulated_data][:category_levels]) == [0, 1, 2]

        fit_record = scenario[:fit_record]
        @test String(fit_record[:type]) == "GMFRMFit"
        @test String(fit_record[:backend]) == "advancedhmc"
        @test String(fit_record[:sampler]) == "nuts"
        @test Vector{Int}(fit_record[:raw_draws_shape]) == [24, 17]
        @test Vector{Int}(fit_record[:direct_draws_shape]) == [24, 19]
        @test Vector{Int}(fit_record[:pointwise_loglikelihood_shape]) == [24, 36]

        predictive = scenario[:predictive_probability_review]
        @test Vector{Int}(predictive[:shape]) == [24, 36, 3]
        @test Bool(predictive[:probability_sums_valid])
        @test Float64(predictive[:max_probability_sum_error]) <= 1.0e-12
        @test Vector{Int}(predictive[:expected_scores][:shape]) == [24, 36]
        @test Bool(predictive[:expected_scores][:all_finite])
        @test Float64(predictive[:expected_scores][:minimum]) >= 0.0
        @test Float64(predictive[:expected_scores][:maximum]) <= 2.0
        @test Vector{Int}(predictive[:predictive_variances][:shape]) == [24, 36]
        @test Bool(predictive[:predictive_variances][:all_finite])
        @test Float64(predictive[:predictive_variances][:minimum]) >= -sqrt(eps())
        @test Vector{Int}(predictive[:predictive_residuals][:shape]) == [24, 36]
        @test Bool(predictive[:predictive_residuals][:all_finite])
        @test Bool(predictive[:expected_scores_in_range])

        ppc = scenario[:posterior_predictive_review]
        @test Vector{Int}(ppc[:draw_indices]) == collect(1:24)
        @test Vector{Int}(ppc[:replicated_scores_shape]) == [24, 36]
        @test Bool(ppc[:replicated_scores_in_categories])
        @test Int(ppc[:n_summary_rows]) == 14
        @test length(ppc[:summary_rows]) == 14
        @test length(ppc[:summary_group_rows]) == 5
        @test all(row -> Int(row[:n_replicates]) == 24, ppc[:summary_rows])
        @test all(row -> String(row[:flag]) in ("ok", "outside_interval"),
            ppc[:summary_rows])
        @test Set(String(row[:statistic]) for row in ppc[:summary_group_rows]) ==
            Set(["mean_score", "category_proportion", "person_mean",
                "rater_mean", "item_mean"])

        calibration = scenario[:calibration_review]
        @test Int(calibration[:top_category]) == 2
        @test Int(calibration[:n_rows]) == 6
        @test Bool(calibration[:all_rows_finite])
        @test length(calibration[:expected_score_rows]) == 3
        @test length(calibration[:category_probability_rows]) == 3
        @test all(row -> String(row[:target]) == "expected_score",
            calibration[:expected_score_rows])
        @test all(row -> String(row[:target]) == "category_probability",
            calibration[:category_probability_rows])
        @test all(row -> Int(row[:n_draws]) == 24,
            calibration[:expected_score_rows])
        @test all(row -> Int(row[:n_draws]) == 24,
            calibration[:category_probability_rows])
        @test Float64(calibration[:max_absolute_calibration_error]) <=
            Float64(thresholds[:max_absolute_calibration_error])

        scenario_summary = scenario[:summary]
        @test Bool(scenario_summary[:passed])
        @test Bool(scenario_summary[:ppc_returned])
        @test Int(scenario_summary[:n_replicates]) == 24
        @test Int(scenario_summary[:n_summary_rows]) == 14
        @test Bool(scenario_summary[:replicated_scores_in_categories])
        @test Bool(scenario_summary[:probability_sums_valid])
        @test Bool(scenario_summary[:summary_rows_finite])
        @test Bool(scenario_summary[:calibration_rows_finite])
        @test Bool(scenario_summary[:mean_score_inside_interval])
        @test Bool(scenario_summary[:expected_scores_in_range])
        @test Bool(scenario_summary[:predictive_variances_nonnegative])
        @test Float64(scenario_summary[:outside_interval_rate]) <=
            Float64(thresholds[:max_summary_outside_interval_rate])
        @test Float64(scenario_summary[:max_absolute_summary_error]) <=
            Float64(thresholds[:max_absolute_summary_error])
        @test Float64(scenario_summary[:max_absolute_mean_score_error]) <=
            Float64(thresholds[:max_absolute_mean_score_error])
        @test Float64(scenario_summary[:max_absolute_category_proportion_error]) <=
            Float64(thresholds[:max_absolute_category_proportion_error])
        @test Float64(scenario_summary[:max_absolute_calibration_error]) <=
            Float64(thresholds[:max_absolute_calibration_error])
    end

    decision = fixture[:decision_record]
    @test Bool(decision[:public_fit_allowed])
    @test Bool(decision[:experimental_keyword_enabled])
    @test String(decision[:public_exposure_support]) ==
        "satisfied_by_sparse_pathology_recovery_grid"
    @test String(decision[:interpretation]) ==
        "guarded_scalar_gmfrm_posterior_predictive_grid_passed"
    @test String(decision[:required_followup]) ==
        "scalar_gmfrm_prior_likelihood_sensitivity_grid"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:superseded_by_sparse_pathology_recovery_grid])
    @test Int(summary[:n_scenarios]) == 3
    @test Int(summary[:n_passed_scenarios]) == 3
    @test Int(summary[:n_replicates_per_scenario]) == 24
    @test Bool(summary[:all_ppc_returned])
    @test Bool(summary[:all_replicated_scores_in_categories])
    @test Bool(summary[:all_probability_sums_valid])
    @test Bool(summary[:all_summary_rows_finite])
    @test Bool(summary[:all_calibration_rows_finite])
    @test Bool(summary[:all_mean_scores_inside_interval])
    @test Float64(summary[:max_outside_interval_rate]) <=
        Float64(thresholds[:max_summary_outside_interval_rate])
    @test Float64(summary[:max_absolute_summary_error]) <=
        Float64(thresholds[:max_absolute_summary_error])
    @test Float64(summary[:max_absolute_mean_score_error]) <=
        Float64(thresholds[:max_absolute_mean_score_error])
    @test Float64(summary[:max_absolute_category_proportion_error]) <=
        Float64(thresholds[:max_absolute_category_proportion_error])
    @test Float64(summary[:max_absolute_calibration_error]) <=
        Float64(thresholds[:max_absolute_calibration_error])
    @test Set(String(blocker) for blocker in summary[:remaining_public_blockers]) ==
        Set(["scalar_gmfrm_prior_likelihood_sensitivity_grid_missing"])
    @test String(summary[:recommendation]) ==
        "keep_guarded_experimental_until_prior_likelihood_sensitivity_grid"
    @test String(summary[:next_gate]) ==
        "scalar_gmfrm_prior_likelihood_sensitivity_grid"
end
