function check_gmfrm_claim_recovery_reproduction_archive_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.gmfrm_claim_recovery_reproduction_archive.v1"
    @test String(fixture[:family]) == "gmfrm"
    @test String(fixture[:scope]) == "scalar_gmfrm_fit_ready_candidate"
    @test String(fixture[:status]) ==
        "claim_recovery_reproduction_archive_recorded"
    @test String(fixture[:decision]) == "keep_guarded_experimental"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) ==
        "scalar_gmfrm_claim_recovery_reproduction_archive_v1"
    @test String(protocol[:review_kind]) ==
        "local_claim_recovery_reproduction_archive"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test Bool(protocol[:local_only])
    @test String(protocol[:archive_scope]) ==
        "fast_and_full_local_reproduction_manifest"
    @test Bool(thresholds[:require_all_fixture_artifacts_present])
    @test Bool(thresholds[:require_all_expected_schemas])
    @test Bool(thresholds[:require_all_expected_sha256_matches])
    @test Bool(thresholds[:require_all_fixture_summaries_passed])
    @test Bool(thresholds[:require_all_fixture_artifact_contracts_valid])
    @test Bool(thresholds[:require_all_generator_scripts_present])
    @test Bool(thresholds[:require_all_code_doc_references_present])
    @test Bool(thresholds[:require_all_external_sources_present])
    @test Bool(thresholds[:require_all_commands_local_only])
    @test Bool(thresholds[:require_no_publication_commands])
    @test Bool(thresholds[:require_guarded_exposure_review_passed])
    @test Bool(thresholds[:require_real_data_case_study_passed])

    fixture_records = fixture[:fixture_records]
    @test length(fixture_records) == 27
    @test Set(String(row[:artifact]) for row in fixture_records) == Set([
        "candidate_chain_study",
        "stress_chain_grid",
        "recovery_smoke_study",
        "baseline_comparison",
        "baseline_calibration_grid",
        "interval_decision_grid",
        "sparse_design_grid",
        "waic_influence_review",
        "psis_loo_review",
        "exact_loo_or_kfold_review",
        "local_dependence_known_truth_preflight",
        "local_dependence_calibration_scorer_preflight",
        "local_dependence_pilot_protocol_preflight",
        "local_dependence_pilot_batch_execution_harness",
        "local_dependence_pilot_bounded_canonical_smoke_receipt",
        "guarded_fit_method_wiring",
        "experimental_fit_validation_grid",
        "posterior_predictive_grid",
        "sparse_pathology_recovery_grid",
        "prior_likelihood_sensitivity_grid",
        "real_data_case_study",
        "guarded_fit_api_dry_run",
        "tam_direct_agreement_policy_refinement_execution_snapshot",
        "tam_direct_agreement_multireplication",
        "tam_direct_agreement_raw_archive_audit",
        "tam_direct_agreement_post_execution_review_packet",
        "guarded_exposure_review",
    ])
    immutable_sha256 = Dict(
        "local_dependence_pilot_bounded_canonical_smoke_receipt" =>
            "de7f1ffab4002e99b75c86d64efbe73deca695b97ac45b0cf177afa5398b58c3",
        "tam_direct_agreement_policy_refinement_execution_snapshot" =>
            "03fe1a903d4fd218b5ab3e5ad51f5133ec1d8f274fafcea0bf8ac330876d8f4e",
    )
    for row in fixture_records
        artifact = String(row[:artifact])
        immutable = Bool(row[:immutable])
        @test Bool(row[:exists])
        @test Bool(row[:schema_matches])
        @test Bool(row[:summary_passed])
        @test Bool(row[:artifact_contract_valid])
        @test Bool(row[:sha256_matches])
        if immutable
            @test haskey(immutable_sha256, artifact)
            @test String(row[:regeneration_policy]) ==
                "immutable_snapshot_no_regeneration"
            @test isnothing(row[:generator])
            @test isnothing(row[:generator_exists])
            @test isnothing(row[:generation_command])
            @test isnothing(row[:env_var])
            @test String(row[:expected_sha256]) ==
                immutable_sha256[artifact]
            @test String(row[:sha256]) == String(row[:expected_sha256])
        else
            @test String(row[:regeneration_policy]) == "generator_replay"
            @test Bool(row[:generator_exists])
            @test occursin("julia --project=. scripts/generate_",
                String(row[:generation_command]))
            @test !isempty(String(row[:env_var]))
            @test isnothing(row[:expected_sha256])
        end
        if startswith(artifact, "tam_direct_agreement")
            @test String(row[:evidence_scope]) ==
                "mfrm_tam_overlap_nontransfer"
        end
        if artifact ==
                "local_dependence_known_truth_preflight"
            @test String(row[:evidence_scope]) ==
                "ld1a_generator_preflight_noncalibration"
        end
        if artifact ==
                "local_dependence_calibration_scorer_preflight"
            @test String(row[:evidence_scope]) ==
                "ld1b0_scorer_protocol_preflight_noncalibration"
        end
        if artifact ==
                "local_dependence_pilot_protocol_preflight"
            @test String(row[:evidence_scope]) ==
                "ld1b1_pilot_execution_protocol_preflight_noncalibration"
        end
        if artifact ==
                "local_dependence_pilot_batch_execution_harness"
            @test String(row[:evidence_scope]) ==
                "ld1b1_pilot_batch_harness_preflight_noncalibration"
        end
        if artifact ==
                "local_dependence_pilot_bounded_canonical_smoke_receipt"
            @test String(row[:evidence_scope]) ==
                "ld1b1_bounded_canonical_smoke_nonpilot"
        end
        if artifact == "guarded_exposure_review"
            @test String(row[:hash_policy]) ==
                "existence_only_avoids_archive_review_hash_cycle"
            @test isnothing(row[:sha256])
        else
            @test String(row[:hash_policy]) == "sha256"
            @test String(row[:sha256]) ==
                file_sha256(joinpath(root, String(row[:path])))
        end
    end

    source_records = fixture[:source_records]
    @test length(source_records) == 2
    @test Set(String(row[:path]) for row in source_records) == Set([
        "../Simulation/data/writing_long.csv",
        "../Simulation/data/speaking_long.csv",
    ])
    for row in source_records
        @test Bool(row[:exists])
        @test String(row[:hash_policy]) == "sha256_when_available"
        check_fixture_sha256_when_available(
            root, String(row[:path]), String(row[:sha256]))
        @test Int(row[:line_count]) > 100_000
    end

    code_doc_records = fixture[:code_doc_records]
    @test length(code_doc_records) == 64
    @test all(row -> Bool(row[:exists]), code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_gmfrm_claim_recovery_reproduction_archive.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) == "scripts/local_json.jl",
        code_doc_records)
    @test all(path -> any(row -> String(row[:path]) == path,
            code_doc_records), [
        "scripts/generate_mgmfrm_tam_direct_agreement_multireplication.jl",
        "scripts/generate_mgmfrm_tam_direct_agreement_multireplication_aggregate.jl",
    ])
    @test any(row -> String(row[:path]) == "src/testlet_design_audit.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) == "src/model_contract.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) == "test/model_contract.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) == "src/local_dependence.jl",
        code_doc_records)
    @test all(path -> any(row -> String(row[:path]) == path,
            code_doc_records), [
        "src/local_dependence_known_truth_dgp.jl",
        "src/local_dependence_simulation.jl",
        "src/local_dependence_calibration.jl",
        "src/local_dependence_calibration_pilot.jl",
        "test/local_dependence_simulation.jl",
        "test/local_dependence_calibration.jl",
        "test/local_dependence_calibration_artifact.jl",
        "test/local_dependence_calibration_pilot.jl",
        "test/local_dependence_pilot_protocol_artifact.jl",
        "test/local_dependence_pilot_batch_execution_harness.jl",
        "test/local_dependence_pilot_attempt_archive.jl",
        "test/local_dependence_pilot_calibration_semantics.jl",
        "test/local_dependence_pilot_recovery.jl",
        "test/local_dependence_pilot_precommit_recovery.jl",
        "test/local_dependence_pilot_controller_receipts.jl",
        "test/local_dependence_pilot_job_worker.jl",
        "scripts/generate_local_dependence_known_truth_preflight.jl",
        "scripts/generate_local_dependence_calibration_scorer_preflight.jl",
        "scripts/generate_local_dependence_pilot_protocol_preflight.jl",
        "scripts/generate_local_dependence_pilot_batch_execution_harness.jl",
        "scripts/run_local_dependence_calibration_pilot_batch.jl",
        "scripts/local_dependence_pilot_attempt_archive.jl",
        "scripts/local_dependence_pilot_calibration_semantics.jl",
        "scripts/local_dependence_pilot_recovery.jl",
        "scripts/run_local_dependence_calibration_pilot_job.jl",
        "docs/src/api-validation-evidence.md",
    ])
    @test any(row -> String(row[:path]) == "test/testlet_design_audit.jl",
        code_doc_records)
    @test all(path -> any(row -> String(row[:path]) == path,
            code_doc_records), [
        "test/local_dependence_contract.jl",
        "test/local_dependence_summary.jl",
        "test/predictive_standardized_residuals.jl",
        "test/testlet_overlap_contract.jl",
    ])
    @test any(row -> String(row[:path]) ==
        "docs/src/mgmfrm-research-roadmap.md", code_doc_records)
    code_doc_integrity = [
        ScientificPayloadDigest.reference_integrity_status(
            String(row[:sha256]),
            file_sha256(joinpath(root, String(row[:path])));
            reference_kind = :code_doc,
        ) for row in code_doc_records
    ]
    @test all(row -> row.provenance_policy_accepted, code_doc_integrity)
    @test all(row -> !row.scientific_equivalence_verified,
        code_doc_integrity)

    full_commands = fixture[:full_regeneration_commands]
    @test length(full_commands) == 26
    @test [Int(row[:step]) for row in full_commands] == collect(1:26)
    @test all(row -> Bool(row[:local_only]), full_commands)
    @test any(row -> String(row[:artifact]) ==
        "tam_direct_agreement_multireplication" &&
        String(row[:command]) ==
            "julia --project=. scripts/generate_mgmfrm_tam_direct_agreement_multireplication_aggregate.jl",
        full_commands)
    @test !any(row -> String(row[:artifact]) ==
        "tam_direct_agreement_policy_refinement_execution_snapshot",
        full_commands)
    @test any(row -> String(row[:artifact]) ==
        "local_dependence_known_truth_preflight", full_commands)
    @test any(row -> String(row[:artifact]) ==
        "local_dependence_calibration_scorer_preflight", full_commands)
    @test any(row -> String(row[:artifact]) ==
        "local_dependence_pilot_protocol_preflight", full_commands)
    @test any(row -> String(row[:artifact]) ==
        "local_dependence_pilot_batch_execution_harness", full_commands)
    @test String(full_commands[end - 1][:artifact]) ==
        "claim_recovery_reproduction_archive"
    @test String(full_commands[end][:artifact]) == "guarded_exposure_review"

    verification = fixture[:verification_commands]
    @test length(verification) == 4
    @test Set(String(row[:name]) for row in verification) == Set([
        "package_tests",
        "documentation_build",
        "local_pre_registration_gate",
        "whitespace_check",
    ])
    @test all(row -> Bool(row[:local_only]), verification)
    @test all(row -> String(row[:execution]) == "required_before_claim_use",
        verification)
    @test all(row -> !occursin("git push", String(row[:command])), verification)

    cycle_breaks = fixture[:cycle_break_references]
    @test length(cycle_breaks) == 1
    @test String(cycle_breaks[1][:artifact]) ==
        "test/fixtures/gmfrm_guarded_exposure_review.json"
    @test String(cycle_breaks[1][:hash_policy]) == "existence_only"

    decision = fixture[:decision_record]
    @test Bool(decision[:public_fit_allowed])
    @test Bool(decision[:experimental_keyword_enabled])
    @test String(decision[:public_exposure_support]) ==
        "satisfied_for_broader_experimental_exposure_decision_followup"
    @test String(decision[:interpretation]) ==
        "claim_level_recovery_reproduction_archive_recorded"
    @test String(decision[:tam_direct_evidence_scope]) ==
        "mfrm_tam_overlap_nontransfer"
    @test Bool(decision[:tam_direct_evidence_transfers_to_scalar_gmfrm]) ==
        false
    @test Bool(decision[:tam_independent_review_completed]) == false
    @test String(decision[:required_followup]) ==
        "broader_experimental_exposure_decision_review"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test String(summary[:pass_scope]) ==
        "contract_and_blocker_preservation_only"
    @test Bool(summary[:artifact_contract_valid])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:local_only])
    @test Int(summary[:n_fixture_artifacts]) == length(fixture_records)
    @test Int(summary[:n_source_records]) == length(source_records)
    @test Int(summary[:n_code_doc_records]) == length(code_doc_records)
    @test Int(summary[:n_full_regeneration_commands]) == length(full_commands)
    @test Int(summary[:n_verification_commands]) == length(verification)
    @test Bool(summary[:all_fixture_artifacts_present])
    @test Bool(summary[:all_expected_schemas])
    @test Bool(summary[:all_expected_sha256_matches])
    @test Bool(summary[:all_fixture_summaries_passed])
    @test Bool(summary[:all_fixture_artifact_contracts_valid])
    @test Bool(summary[:all_generator_scripts_present])
    @test Bool(summary[:all_code_doc_references_present])
    @test Bool(summary[:all_external_sources_present])
    @test Bool(summary[:all_commands_local_only])
    @test Bool(summary[:no_publication_commands])
    @test Bool(summary[:guarded_exposure_review_passed])
    @test Bool(summary[:real_data_case_study_passed])
    @test Bool(summary[:tam_direct_primary_gate_passed])
    @test Bool(summary[:tam_raw_archive_integrity_passed])
    @test Bool(summary[:tam_post_packet_integrity_passed])
    @test Bool(summary[:tam_independent_review_completed]) == false
    @test Bool(summary[:tam_execution_input_lineage_exact])
    @test Bool(summary[:tam_pre_execution_exact_input_lineage]) == false
    @test Bool(summary[
        :tam_direct_evidence_transfers_to_scalar_gmfrm]) == false
    @test Set(String(blocker) for blocker in summary[:remaining_public_blockers]) ==
        Set([
            "broader_experimental_exposure_decision_review_missing",
            "tam_direct_independent_review_pending",
            "tam_pre_execution_refinement_lineage_adjudication_pending",
        ])
    @test String(summary[:recommendation]) ==
        "keep_guarded_experimental_until_broader_exposure_decision_review"
    @test String(summary[:next_gate]) ==
        "broader_experimental_exposure_decision_review"
end

function check_gmfrm_full_paper_reproduction_archive_fixture(
        fixture_path::AbstractString)
    root = dirname(dirname(@__DIR__))
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.gmfrm_full_paper_reproduction_archive.v1"
    @test String(fixture[:family]) == "gmfrm"
    @test String(fixture[:scope]) == "full_paper_reproduction_archive"
    @test String(fixture[:status]) == "full_paper_reproduction_archive_recorded"
    @test String(fixture[:decision]) ==
        "archive_full_and_fast_reproduction_bundle_local_only"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])
    @test Bool(fixture[:broader_public_fit]) == false
    @test Bool(fixture[:publication_or_registration_action]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) ==
        "gmfrm_full_paper_reproduction_archive_v1"
    @test String(protocol[:review_kind]) ==
        "local_full_paper_reproduction_archive"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test Bool(protocol[:local_only])
    @test String(protocol[:archive_scope]) ==
        "full_and_fast_local_reproduction_manifest"
    @test Bool(thresholds[:require_all_fixture_artifacts_present])
    @test Bool(thresholds[:require_all_expected_schemas])
    @test Bool(thresholds[:require_all_expected_sha256_matches])
    @test Bool(thresholds[:require_all_fixture_summaries_passed])
    @test Bool(thresholds[:require_all_fixture_artifact_contracts_valid])
    @test Bool(thresholds[:require_all_generator_scripts_present])
    @test Bool(thresholds[:require_all_code_doc_references_present])
    @test Bool(thresholds[:require_all_external_sources_present])
    @test Bool(thresholds[:require_full_regeneration_commands_recorded])
    @test Bool(thresholds[:require_verification_commands_recorded])
    @test Bool(thresholds[:require_all_commands_local_only])
    @test Bool(thresholds[:require_no_publication_commands])
    @test Bool(thresholds[:require_guarded_exposure_review_passed])
    @test Bool(thresholds[:require_broader_exposure_review_passed])
    @test Bool(thresholds[:require_manuscript_scale_simulation_grid_passed])
    @test Bool(thresholds[:require_tam_direct_execution_recorded])
    @test Bool(thresholds[:require_tam_raw_archive_integrity_passed])
    @test Bool(thresholds[:require_tam_post_execution_packet_integrity_passed])
    @test Bool(thresholds[:require_tam_independent_review_pending_recorded])
    @test Bool(thresholds[:require_tam_pre_execution_lineage_mismatch_recorded])
    @test Bool(thresholds[:require_tam_evidence_nontransfer_to_gmfrm_mgmfrm])
    @test Bool(thresholds[:require_mgmfrm_sparse_recovery_grid_passed])
    @test Bool(thresholds[:require_mgmfrm_report_shape_simulation_grid_passed])
    @test Bool(thresholds[:require_mgmfrm_q_matrix_validation_expansion_passed])
    @test Bool(thresholds[
        :require_mgmfrm_empirical_q_matrix_recovery_policy_passed])
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
    @test Bool(thresholds[
        :require_mgmfrm_publication_grade_refit_pilot_results_review_passed])
    @test Bool(thresholds[
        :require_mgmfrm_publication_grade_refit_sampler_remediation_review_passed])
    @test Bool(thresholds[
        :require_mgmfrm_publication_grade_refit_scalar_remediation_comparison_passed])
    @test Bool(thresholds[
        :require_mgmfrm_publication_grade_refit_batch_expansion_plan_passed])
    @test Bool(thresholds[
        :require_mgmfrm_publication_grade_refit_batch_smoke_execution_review_passed])
    @test Bool(thresholds[
        :require_mgmfrm_publication_grade_refit_well_specified_scenario_execution_review_passed])
    @test Bool(thresholds[
        :require_mgmfrm_publication_grade_refit_batch_results_review_passed])
    @test Bool(thresholds[
        :require_mgmfrm_publication_grade_threshold_model_weight_policy_review_passed])
    @test Bool(thresholds[
        :require_mgmfrm_external_construct_dataset_and_independent_public_scope_review_passed])
    @test String(thresholds[
        :mgmfrm_external_construct_dataset_and_independent_public_scope_review_passed_semantics]) ==
        "artifact_contract_and_blocker_preservation_only"
    @test Bool(thresholds[
        :require_mgmfrm_external_construct_dataset_and_independent_public_scope_review_artifact_contract_valid])
    @test Bool(thresholds[
        :require_mgmfrm_external_construct_attachment_intake_preflight_passed])
    @test String(thresholds[
        :mgmfrm_external_construct_attachment_intake_preflight_passed_semantics]) ==
        "artifact_contract_and_blocker_preservation_only"
    @test Bool(thresholds[
        :require_mgmfrm_external_construct_attachment_intake_preflight_artifact_contract_valid])
    @test Bool(thresholds[
        :require_mgmfrm_external_construct_attachment_request_packet_passed])
    @test String(thresholds[
        :mgmfrm_external_construct_attachment_request_packet_passed_semantics]) ==
        "artifact_contract_and_blocker_preservation_only"
    @test Bool(thresholds[
        :require_mgmfrm_external_construct_attachment_request_packet_artifact_contract_valid])
    @test Bool(thresholds[
        :require_external_construct_evidence_pass_implies_attached_and_valid])
    @test Bool(thresholds[
        :require_external_construct_public_claim_release_gate_requires_zero_blockers])
    @test Bool(thresholds[
        :require_external_construct_gate_states_consistent])
    @test Bool(thresholds[:require_mgmfrm_guarded_fit_method_wiring_passed])
    @test Bool(thresholds[:require_mgmfrm_guarded_fit_validation_grid_passed])
    @test Bool(thresholds[:require_mgmfrm_guarded_fit_api_dry_run_passed])
    @test Bool(thresholds[:require_mgmfrm_guarded_fit_public_exposure_review_passed])
    @test Bool(thresholds[:require_prediction_target_and_model_weight_policy_passed])

    fixture_records = fixture[:fixture_records]
    expected_paths = Dict(
        "source_gmfrm_bridge_logdensity" =>
            "test/fixtures/source_gmfrm_bridge_logdensity.json",
        "source_mgmfrm_bridge_logdensity" =>
            "test/fixtures/source_mgmfrm_bridge_logdensity.json",
        "candidate_chain_study" =>
            "test/fixtures/gmfrm_candidate_chain_study.json",
        "stress_chain_grid" =>
            "test/fixtures/gmfrm_stress_chain_grid.json",
        "recovery_smoke_study" =>
            "test/fixtures/gmfrm_recovery_smoke.json",
        "baseline_comparison" =>
            "test/fixtures/gmfrm_baseline_comparison.json",
        "baseline_calibration_grid" =>
            "test/fixtures/gmfrm_baseline_calibration_grid.json",
        "interval_decision_grid" =>
            "test/fixtures/gmfrm_interval_decision_grid.json",
        "sparse_design_grid" =>
            "test/fixtures/gmfrm_sparse_design_grid.json",
        "waic_influence_review" =>
            "test/fixtures/gmfrm_waic_influence_review.json",
        "psis_loo_review" =>
            "test/fixtures/gmfrm_psis_loo_review.json",
        "exact_loo_or_kfold_review" =>
            "test/fixtures/gmfrm_exact_loo_or_kfold_review.json",
        "local_dependence_known_truth_preflight" =>
            "test/fixtures/local_dependence_known_truth_preflight.json",
        "local_dependence_calibration_scorer_preflight" =>
            "test/fixtures/local_dependence_calibration_scorer_preflight.json",
        "local_dependence_pilot_protocol_preflight" =>
            "test/fixtures/local_dependence_pilot_protocol_preflight.json",
        "local_dependence_pilot_batch_execution_harness" =>
            "test/fixtures/local_dependence_pilot_batch_execution_harness.json",
        "local_dependence_pilot_bounded_canonical_smoke_receipt" =>
            "test/fixtures/local_dependence_pilot_bounded_canonical_smoke_receipt.json",
        "guarded_fit_api_dry_run" =>
            "test/fixtures/gmfrm_guarded_fit_api_dry_run.json",
        "guarded_fit_method_wiring" =>
            "test/fixtures/gmfrm_guarded_fit_method_wiring.json",
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
        "tam_direct_agreement_policy_refinement_execution_snapshot" =>
            "test/fixtures/mgmfrm_tam_direct_agreement_policy_refinement_execution_snapshot.json",
        "tam_direct_agreement_multireplication" =>
            "test/fixtures/mgmfrm_tam_direct_agreement_multireplication.json",
        "tam_direct_agreement_raw_archive_audit" =>
            "test/fixtures/mgmfrm_tam_direct_agreement_raw_archive_audit.json",
        "tam_direct_agreement_post_execution_review_packet" =>
            "test/fixtures/mgmfrm_tam_direct_agreement_post_execution_review_packet.json",
        "broader_experimental_exposure_decision_review" =>
            "test/fixtures/gmfrm_broader_experimental_exposure_decision_review.json",
        "dff_estimand_validation_grid" =>
            "test/fixtures/gmfrm_dff_estimand_validation_grid.json",
        "manuscript_scale_simulation_grid" =>
            "test/fixtures/gmfrm_manuscript_scale_simulation_grid.json",
        "guarded_exposure_review" =>
            "test/fixtures/gmfrm_guarded_exposure_review.json",
        "mgmfrm_candidate_chain_study" =>
            "test/fixtures/mgmfrm_candidate_chain_study.json",
        "mgmfrm_recovery_smoke" =>
            "test/fixtures/mgmfrm_recovery_smoke.json",
        "mgmfrm_baseline_comparison" =>
            "test/fixtures/mgmfrm_baseline_comparison.json",
        "mgmfrm_sparse_recovery_grid" =>
            "test/fixtures/mgmfrm_sparse_recovery_grid.json",
        "mgmfrm_report_shape_simulation_grid" =>
            "test/fixtures/mgmfrm_report_shape_simulation_grid.json",
        "mgmfrm_q_matrix_validation_expansion" =>
            "test/fixtures/mgmfrm_q_matrix_validation_expansion.json",
        "mgmfrm_empirical_q_matrix_recovery_policy" =>
            "test/fixtures/mgmfrm_empirical_q_matrix_recovery_policy.json",
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
        "mgmfrm_publication_grade_refit_pilot_results_review" =>
            "test/fixtures/mgmfrm_publication_grade_refit_pilot_results_review.json",
        "mgmfrm_publication_grade_refit_sampler_remediation_review" =>
            "test/fixtures/mgmfrm_publication_grade_refit_sampler_remediation_review.json",
        "mgmfrm_publication_grade_refit_scalar_remediation_comparison" =>
            "test/fixtures/mgmfrm_publication_grade_refit_scalar_remediation_comparison.json",
        "mgmfrm_publication_grade_refit_batch_expansion_plan" =>
            "test/fixtures/mgmfrm_publication_grade_refit_batch_expansion_plan.json",
        "mgmfrm_publication_grade_refit_batch_smoke_execution_review" =>
            "test/fixtures/mgmfrm_publication_grade_refit_batch_smoke_execution_review.json",
        "mgmfrm_publication_grade_refit_well_specified_scenario_execution_review" =>
            "test/fixtures/mgmfrm_publication_grade_refit_well_specified_scenario_execution_review.json",
        "mgmfrm_publication_grade_refit_batch_results_review" =>
            "test/fixtures/mgmfrm_publication_grade_refit_batch_results_review.json",
        "mgmfrm_publication_grade_threshold_model_weight_policy_review" =>
            "test/fixtures/mgmfrm_publication_grade_threshold_model_weight_policy_review.json",
        "mgmfrm_external_construct_dataset_and_independent_public_scope_review" =>
            "test/fixtures/mgmfrm_external_construct_dataset_and_independent_public_scope_review.json",
        "mgmfrm_external_construct_attachment_intake_preflight" =>
            "test/fixtures/mgmfrm_external_construct_attachment_intake_preflight.json",
        "mgmfrm_external_construct_attachment_request_packet" =>
            "test/fixtures/mgmfrm_external_construct_attachment_request_packet.json",
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
    )
    @test length(fixture_records) == length(expected_paths)
    @test Set(String(row[:artifact]) for row in fixture_records) ==
        Set(keys(expected_paths))
    immutable_sha256 = Dict(
        "local_dependence_pilot_bounded_canonical_smoke_receipt" =>
            "de7f1ffab4002e99b75c86d64efbe73deca695b97ac45b0cf177afa5398b58c3",
        "tam_direct_agreement_policy_refinement_execution_snapshot" =>
            "03fe1a903d4fd218b5ab3e5ad51f5133ec1d8f274fafcea0bf8ac330876d8f4e",
    )
    for row in fixture_records
        artifact = String(row[:artifact])
        path = String(row[:path])
        immutable = Bool(row[:immutable])
        @test expected_paths[artifact] == path
        @test Bool(row[:exists])
        @test Bool(row[:schema_matches])
        @test Bool(row[:summary_passed])
        @test Bool(row[:artifact_contract_valid])
        @test Bool(row[:sha256_matches])
        if immutable
            @test haskey(immutable_sha256, artifact)
            @test String(row[:regeneration_policy]) ==
                "immutable_snapshot_no_regeneration"
            @test isnothing(row[:generator])
            @test isnothing(row[:generator_exists])
            @test isnothing(row[:generation_command])
            @test isnothing(row[:env_var])
            @test String(row[:expected_sha256]) ==
                immutable_sha256[artifact]
            @test String(row[:sha256]) == String(row[:expected_sha256])
        else
            @test String(row[:regeneration_policy]) == "generator_replay"
            @test Bool(row[:generator_exists])
            @test !isempty(String(row[:env_var]))
            @test isnothing(row[:expected_sha256])
        end
        if artifact ==
                "mgmfrm_publication_grade_refit_batch_results_review"
            @test occursin("--read-local-artifacts",
                String(row[:generation_command]))
        end
        if artifact in (
                "broader_experimental_exposure_decision_review",
                "guarded_exposure_review",
                "manuscript_scale_simulation_grid")
            @test startswith(String(row[:hash_policy]),
                "existence_only_avoids_full_archive")
            @test isnothing(row[:sha256])
        else
            @test String(row[:hash_policy]) == "sha256"
            check_generated_fixture_reference(
                root,
                path,
                String(row[:sha256]),
            )
        end
    end

    code_doc_records = fixture[:code_doc_records]
    @test length(code_doc_records) == 125
    @test all(row -> Bool(row[:exists]), code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_gmfrm_full_paper_reproduction_archive.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "examples/guarded_gmfrm.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "docs/src/mgmfrm-research-roadmap.md", code_doc_records)
    @test any(row -> String(row[:path]) == "src/local_dependence.jl",
        code_doc_records)
    @test all(path -> any(row -> String(row[:path]) == path,
            code_doc_records), [
        "src/local_dependence_known_truth_dgp.jl",
        "src/local_dependence_simulation.jl",
        "src/local_dependence_calibration.jl",
        "src/local_dependence_calibration_pilot.jl",
        "test/local_dependence_simulation.jl",
        "test/local_dependence_calibration.jl",
        "test/local_dependence_calibration_artifact.jl",
        "test/local_dependence_calibration_pilot.jl",
        "test/local_dependence_pilot_protocol_artifact.jl",
        "test/local_dependence_pilot_batch_execution_harness.jl",
        "test/local_dependence_pilot_attempt_archive.jl",
        "test/local_dependence_pilot_calibration_semantics.jl",
        "test/local_dependence_pilot_recovery.jl",
        "test/local_dependence_pilot_precommit_recovery.jl",
        "test/local_dependence_pilot_controller_receipts.jl",
        "test/local_dependence_pilot_job_worker.jl",
        "scripts/generate_local_dependence_known_truth_preflight.jl",
        "scripts/generate_local_dependence_calibration_scorer_preflight.jl",
        "scripts/generate_local_dependence_pilot_protocol_preflight.jl",
        "scripts/generate_local_dependence_pilot_batch_execution_harness.jl",
        "scripts/run_local_dependence_calibration_pilot_batch.jl",
        "scripts/local_dependence_pilot_attempt_archive.jl",
        "scripts/local_dependence_pilot_calibration_semantics.jl",
        "scripts/local_dependence_pilot_recovery.jl",
        "scripts/run_local_dependence_calibration_pilot_job.jl",
    ])
    @test all(path -> any(row -> String(row[:path]) == path,
            code_doc_records), [
        "test/facets_compatibility_stats.jl",
        "test/generalized_guard_contract.jl",
        "test/local_dependence_contract.jl",
        "test/local_dependence_summary.jl",
        "test/predictive_standardized_residuals.jl",
        "test/publication_grade_policy_contract.jl",
        "test/testlet_design_audit.jl",
        "test/testlet_overlap_contract.jl",
    ])
    @test any(row -> String(row[:path]) ==
        "scripts/generate_mgmfrm_report_shape_simulation_grid.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_mgmfrm_q_matrix_validation_expansion.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_mgmfrm_empirical_q_matrix_recovery_policy.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_mgmfrm_empirical_q_matrix_recovery_simulation_grid.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_mgmfrm_q_candidate_real_fit_diagnostic_linkage.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_mgmfrm_q_revision_cross_validation_policy.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_mgmfrm_q_revision_construct_validity_review.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_mgmfrm_guarded_local_fit_entrypoint.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_mgmfrm_fit_metric_threshold_sensitivity.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_mgmfrm_construct_reviewed_q_fit_reporting_policy.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_mgmfrm_heldout_prediction_validation_policy.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_mgmfrm_validation_split_model_comparison_policy.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_mgmfrm_heldout_prediction_simulation_grid.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_mgmfrm_heldout_prediction_execution.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_mgmfrm_full_heldout_refit_or_construct_validation_review.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_mgmfrm_full_heldout_mcmc_refit_execution_plan.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_mgmfrm_full_heldout_mcmc_refit_batch_smoke.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_mgmfrm_full_heldout_mcmc_refit_fold1_pilot.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_mgmfrm_full_heldout_mcmc_refit_fold1_scoring.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_mgmfrm_full_heldout_mcmc_refit_candidate_batch_scoring.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_mgmfrm_full_heldout_mcmc_refit_anchor_scoring.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_mgmfrm_publication_grade_refit_gate.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_mgmfrm_publication_grade_refit_pilot_plan.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_mgmfrm_fit_threshold_q_heldout_linkage.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_mgmfrm_publication_grade_refit_pilot_execution_harness.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/run_mgmfrm_publication_grade_refit_job.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/run_mgmfrm_publication_grade_refit_batch.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_mgmfrm_publication_grade_refit_pilot_results_review.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_mgmfrm_publication_grade_refit_sampler_remediation_review.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_mgmfrm_publication_grade_refit_scalar_remediation_comparison.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_mgmfrm_publication_grade_refit_batch_expansion_plan.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_mgmfrm_publication_grade_refit_batch_smoke_execution_review.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_mgmfrm_publication_grade_refit_well_specified_scenario_execution_review.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_mgmfrm_publication_grade_refit_batch_results_review.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_mgmfrm_publication_grade_threshold_model_weight_policy_review.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_mgmfrm_external_construct_dataset_and_independent_public_scope_review.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_mgmfrm_external_construct_attachment_intake_preflight.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_mgmfrm_external_construct_attachment_request_packet.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_mgmfrm_tam_direct_agreement_multireplication.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_mgmfrm_tam_direct_agreement_multireplication_aggregate.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_mgmfrm_tam_direct_agreement_raw_archive_audit.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_mgmfrm_tam_direct_agreement_post_execution_review_packet.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_mgmfrm_guarded_fit_method_wiring.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_mgmfrm_guarded_fit_validation_grid.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_mgmfrm_guarded_fit_api_dry_run.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_mgmfrm_guarded_fit_public_exposure_review.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) == "src/model_contract.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) == "test/model_contract.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_gmfrm_prediction_target_and_model_weight_policy.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_mgmfrm_manual_public_scope_review_for_fit.jl",
        code_doc_records)
    code_doc_integrity = [
        ScientificPayloadDigest.reference_integrity_status(
            String(row[:sha256]),
            file_sha256(joinpath(root, String(row[:path])));
            reference_kind = :code_doc,
        ) for row in code_doc_records
    ]
    @test all(row -> row.provenance_policy_accepted, code_doc_integrity)
    @test all(row -> !row.scientific_equivalence_verified,
        code_doc_integrity)

    source_records = fixture[:source_records]
    @test length(source_records) == 2
    @test Set(String(row[:path]) for row in source_records) == Set([
        "../Simulation/data/writing_long.csv",
        "../Simulation/data/speaking_long.csv",
    ])
    for row in source_records
        @test Bool(row[:exists])
        check_fixture_sha256_when_available(
            root, String(row[:path]), String(row[:sha256]))
        @test Int(row[:line_count]) > 100_000
    end

    full_commands = fixture[:full_regeneration_commands]
    @test length(full_commands) == 77
    @test [Int(row[:step]) for row in full_commands] == collect(1:77)
    @test allunique(String(row[:artifact]) for row in full_commands)
    @test all(row -> Bool(row[:local_only]), full_commands)
    @test any(row -> String(row[:artifact]) ==
        "local_dependence_known_truth_preflight", full_commands)
    @test any(row -> String(row[:artifact]) ==
        "local_dependence_calibration_scorer_preflight", full_commands)
    @test any(row -> String(row[:artifact]) ==
        "local_dependence_pilot_protocol_preflight", full_commands)
    @test any(row -> String(row[:artifact]) ==
        "local_dependence_pilot_batch_execution_harness", full_commands)
    @test any(row -> String(row[:artifact]) ==
        "mgmfrm_report_shape_simulation_grid", full_commands)
    @test any(row -> String(row[:artifact]) ==
        "mgmfrm_q_matrix_validation_expansion", full_commands)
    @test any(row -> String(row[:artifact]) ==
        "mgmfrm_empirical_q_matrix_recovery_policy", full_commands)
    @test any(row -> String(row[:artifact]) ==
        "mgmfrm_empirical_q_matrix_recovery_simulation_grid", full_commands)
    @test any(row -> String(row[:artifact]) ==
        "mgmfrm_q_candidate_real_fit_diagnostic_linkage", full_commands)
    @test any(row -> String(row[:artifact]) ==
        "mgmfrm_q_revision_cross_validation_policy", full_commands)
    @test any(row -> String(row[:artifact]) ==
        "mgmfrm_q_revision_construct_validity_review", full_commands)
    @test any(row -> String(row[:artifact]) ==
        "mgmfrm_guarded_local_fit_entrypoint", full_commands)
    @test any(row -> String(row[:artifact]) ==
        "mgmfrm_fit_metric_threshold_sensitivity", full_commands)
    @test any(row -> String(row[:artifact]) ==
        "mgmfrm_construct_reviewed_q_fit_reporting_policy", full_commands)
    @test any(row -> String(row[:artifact]) ==
        "mgmfrm_heldout_prediction_validation_policy", full_commands)
    @test any(row -> String(row[:artifact]) ==
        "mgmfrm_validation_split_model_comparison_policy", full_commands)
    @test any(row -> String(row[:artifact]) ==
        "mgmfrm_heldout_prediction_simulation_grid", full_commands)
    @test any(row -> String(row[:artifact]) ==
        "mgmfrm_heldout_prediction_execution", full_commands)
    @test any(row -> String(row[:artifact]) ==
        "mgmfrm_full_heldout_refit_or_construct_validation_review",
        full_commands)
    @test any(row -> String(row[:artifact]) ==
        "mgmfrm_full_heldout_mcmc_refit_execution_plan",
        full_commands)
    @test any(row -> String(row[:artifact]) ==
        "mgmfrm_full_heldout_mcmc_refit_batch_smoke",
        full_commands)
    @test any(row -> String(row[:artifact]) ==
        "mgmfrm_full_heldout_mcmc_refit_fold1_pilot",
        full_commands)
    @test any(row -> String(row[:artifact]) ==
        "mgmfrm_full_heldout_mcmc_refit_fold1_scoring",
        full_commands)
    @test any(row -> String(row[:artifact]) ==
        "mgmfrm_full_heldout_mcmc_refit_candidate_batch_scoring",
        full_commands)
    @test any(row -> String(row[:artifact]) ==
        "mgmfrm_full_heldout_mcmc_refit_anchor_scoring",
        full_commands)
    @test any(row -> String(row[:artifact]) ==
        "mgmfrm_publication_grade_refit_gate",
        full_commands)
    @test any(row -> String(row[:artifact]) ==
        "mgmfrm_publication_grade_refit_pilot_plan",
        full_commands)
    @test any(row -> String(row[:artifact]) ==
        "mgmfrm_fit_threshold_q_heldout_linkage",
        full_commands)
    @test any(row -> String(row[:artifact]) ==
        "mgmfrm_publication_grade_refit_pilot_execution_harness",
        full_commands)
    @test any(row -> String(row[:artifact]) ==
        "mgmfrm_publication_grade_refit_pilot_results_review",
        full_commands)
    @test any(row -> String(row[:artifact]) ==
        "mgmfrm_publication_grade_refit_sampler_remediation_review",
        full_commands)
    @test any(row -> String(row[:artifact]) ==
        "mgmfrm_publication_grade_refit_scalar_remediation_comparison",
        full_commands)
    @test any(row -> String(row[:artifact]) ==
        "mgmfrm_publication_grade_refit_batch_expansion_plan",
        full_commands)
    @test any(row -> String(row[:artifact]) ==
        "mgmfrm_publication_grade_refit_batch_smoke_execution_review",
        full_commands)
    @test any(row -> String(row[:artifact]) ==
        "mgmfrm_publication_grade_refit_well_specified_scenario_execution_review",
        full_commands)
    @test any(row -> String(row[:artifact]) ==
        "mgmfrm_publication_grade_refit_batch_results_review",
        full_commands)
    batch_review_command = only(row for row in full_commands
        if String(row[:artifact]) ==
            "mgmfrm_publication_grade_refit_batch_results_review")
    @test occursin("--read-local-artifacts",
        String(batch_review_command[:command]))

    function command_generator_basename(command)
        token = only(filter(part -> startswith(part, "scripts/"),
            split(String(command))))
        return basename(token)
    end

    function collect_hashed_fixture_paths!(paths::Set{String}, value)
        if value isa AbstractDict
            sha = get(value, :sha256, nothing)
            if sha isa AbstractString && !isempty(sha)
                for key in (:path, :artifact)
                    candidate = get(value, key, nothing)
                    if candidate isa AbstractString &&
                            startswith(candidate, "test/fixtures/")
                        push!(paths, String(candidate))
                    end
                end
            end
            for child in values(value)
                collect_hashed_fixture_paths!(paths, child)
            end
        elseif value isa AbstractVector
            for child in value
                collect_hashed_fixture_paths!(paths, child)
            end
        end
        return paths
    end

    step_by_artifact = Dict(
        String(row[:artifact]) => Int(row[:step]) for row in full_commands)
    artifact_by_generator = Dict(
        command_generator_basename(row[:command]) => String(row[:artifact])
        for row in full_commands)
    artifact_by_path = Dict{String,String}()
    for row in fixture_records
        Bool(row[:immutable]) && continue
        generator = basename(String(row[:generator]))
        @test haskey(artifact_by_generator, generator)
        haskey(artifact_by_generator, generator) || continue
        artifact_by_path[String(row[:path])] =
            artifact_by_generator[generator]
    end

    @testset "full regeneration SHA dependency order" begin
        for (consumer_path, consumer) in artifact_by_path
            document = JSON3.read(read(joinpath(root, consumer_path), String))
            dependencies = collect_hashed_fixture_paths!(
                Set{String}(), document)
            for dependency_path in dependencies
                haskey(artifact_by_path, dependency_path) || continue
                dependency = artifact_by_path[dependency_path]
                dependency == consumer && continue
                @test step_by_artifact[dependency] <
                    step_by_artifact[consumer]
            end
        end
    end
    @test any(row -> String(row[:artifact]) ==
        "mgmfrm_publication_grade_threshold_model_weight_policy_review",
        full_commands)
    @test any(row -> String(row[:artifact]) ==
        "mgmfrm_external_construct_dataset_and_independent_public_scope_review",
        full_commands)
    @test any(row -> String(row[:artifact]) ==
        "mgmfrm_external_construct_attachment_intake_preflight",
        full_commands)
    @test any(row -> String(row[:artifact]) ==
        "mgmfrm_external_construct_attachment_request_packet",
        full_commands)
    @test any(row -> String(row[:artifact]) ==
        "prediction_target_and_model_weight_policy", full_commands)
    @test any(row -> String(row[:artifact]) ==
        "tam_direct_agreement_multireplication" &&
        String(row[:command]) ==
            "julia --project=. scripts/generate_mgmfrm_tam_direct_agreement_multireplication_aggregate.jl",
        full_commands)
    @test !any(row -> String(row[:artifact]) ==
        "tam_direct_agreement_policy_refinement_execution_snapshot",
        full_commands)
    @test String(full_commands[end - 3][:artifact]) ==
        "gmfrm_full_paper_reproduction_archive"
    @test String(full_commands[end][:artifact]) == "gmfrm_guarded_exposure_review"

    verification = fixture[:verification_commands]
    @test length(verification) == 4
    @test Set(String(row[:name]) for row in verification) == Set([
        "package_tests",
        "documentation_build",
        "local_pre_registration_gate",
        "whitespace_check",
    ])
    @test all(row -> Bool(row[:local_only]), verification)
    @test all(row -> String(row[:execution]) == "required_before_claim_use",
        verification)
    @test all(row -> !occursin("git push", String(row[:command])),
        verification)

    cycle_breaks = fixture[:cycle_break_references]
    @test length(cycle_breaks) == 3
    @test Set(String(row[:hash_policy]) for row in cycle_breaks) ==
        Set(["existence_only"])

    decision = fixture[:decision_record]
    @test String(decision[:selected_decision]) ==
        "full_paper_reproduction_archive_recorded_local_only"
    @test Bool(decision[:scalar_guarded_fit_allowed])
    @test Bool(decision[:broader_generalized_fit_allowed]) == false
    @test Bool(decision[:mgmfrm_fit_allowed])
    @test !Bool(decision[:manuscript_reproducibility_claims_supported])
    @test Bool(decision[:publication_or_registration_action]) == false
    @test String(decision[:tam_direct_evidence_scope]) ==
        "mfrm_tam_overlap_nontransfer"
    @test Bool(decision[
        :tam_direct_evidence_transfers_to_gmfrm_or_mgmfrm]) == false
    @test Bool(decision[:tam_independent_review_completed]) == false
    @test String(decision[:required_followup]) ==
        "manual_publication_or_registration_by_user_only"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test String(summary[:pass_scope]) ==
        "contract_and_blocker_preservation_only"
    @test Bool(summary[:artifact_contract_valid])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:local_only])
    @test Int(summary[:n_fixture_artifacts]) == length(fixture_records)
    @test Int(summary[:n_code_doc_records]) == length(code_doc_records)
    @test Int(summary[:n_source_records]) == length(source_records)
    @test Int(summary[:n_full_regeneration_commands]) == length(full_commands)
    @test Int(summary[:n_verification_commands]) == length(verification)
    @test Bool(summary[:all_fixture_artifacts_present])
    @test Bool(summary[:all_expected_schemas])
    @test Bool(summary[:all_expected_sha256_matches])
    @test Bool(summary[:all_fixture_summaries_passed])
    @test Bool(summary[:all_fixture_artifact_contracts_valid])
    @test Bool(summary[:external_construct_gate_states_consistent])
    @test Bool(summary[:all_generator_scripts_present])
    @test Bool(summary[:all_code_doc_references_present])
    @test Bool(summary[:all_external_sources_present])
    @test Bool(summary[:full_regeneration_commands_recorded])
    @test Bool(summary[:verification_commands_recorded])
    @test Bool(summary[:all_commands_local_only])
    @test Bool(summary[:no_publication_commands])
    @test Bool(summary[:claim_recovery_reproduction_archive_passed])
    @test Bool(summary[:tam_direct_primary_gate_passed])
    @test Bool(summary[:tam_raw_archive_integrity_passed])
    @test Bool(summary[:tam_post_packet_integrity_passed])
    @test Bool(summary[:tam_independent_review_completed]) == false
    @test Bool(summary[:tam_execution_input_lineage_exact])
    @test Bool(summary[:tam_pre_execution_exact_input_lineage]) == false
    @test Bool(summary[
        :tam_direct_evidence_transfers_to_gmfrm_or_mgmfrm]) == false
    @test Bool(summary[:guarded_exposure_review_passed])
    @test Bool(summary[:broader_experimental_exposure_decision_review_passed])
    @test Bool(summary[:manuscript_scale_simulation_grid_passed])
    @test Bool(summary[:mgmfrm_sparse_recovery_grid_passed])
    @test Bool(summary[:mgmfrm_report_shape_simulation_grid_passed])
    @test Bool(summary[:mgmfrm_q_matrix_validation_expansion_passed])
    @test Bool(summary[:mgmfrm_empirical_q_matrix_recovery_policy_passed])
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
    @test Bool(summary[
        :mgmfrm_publication_grade_refit_pilot_results_review_passed])
    @test Bool(summary[
        :mgmfrm_publication_grade_refit_sampler_remediation_review_passed])
    @test Bool(summary[
        :mgmfrm_publication_grade_refit_scalar_remediation_comparison_passed])
    @test Bool(summary[
        :mgmfrm_publication_grade_refit_batch_expansion_plan_passed])
    @test Bool(summary[
        :mgmfrm_publication_grade_refit_batch_smoke_execution_review_passed])
    @test Bool(summary[
        :mgmfrm_publication_grade_refit_well_specified_scenario_execution_review_passed])
    @test Bool(summary[
        :mgmfrm_publication_grade_refit_batch_results_review_passed])
    @test Bool(summary[
        :mgmfrm_publication_grade_threshold_model_weight_policy_review_passed])
    @test Bool(summary[
        :mgmfrm_external_construct_dataset_and_independent_public_scope_review_passed])
    @test String(summary[
        :mgmfrm_external_construct_dataset_and_independent_public_scope_review_passed_semantics]) ==
        "artifact_contract_and_blocker_preservation_only"
    @test Bool(summary[
        :mgmfrm_external_construct_dataset_and_independent_public_scope_review_artifact_contract_valid])
    @test Bool(summary[
        :mgmfrm_external_construct_attachment_intake_preflight_passed])
    @test String(summary[
        :mgmfrm_external_construct_attachment_intake_preflight_passed_semantics]) ==
        "artifact_contract_and_blocker_preservation_only"
    @test Bool(summary[
        :mgmfrm_external_construct_attachment_intake_preflight_artifact_contract_valid])
    @test Bool(summary[
        :mgmfrm_external_construct_attachment_request_packet_passed])
    @test String(summary[
        :mgmfrm_external_construct_attachment_request_packet_passed_semantics]) ==
        "artifact_contract_and_blocker_preservation_only"
    @test Bool(summary[
        :mgmfrm_external_construct_attachment_request_packet_artifact_contract_valid])
    @test Bool(summary[
        :mgmfrm_external_construct_dataset_manifest_attached_and_valid]) ==
        false
    @test Bool(summary[
        :mgmfrm_external_construct_dataset_file_integrity_verified]) == false
    @test Bool(summary[
        :mgmfrm_external_construct_validation_evidence_attached_and_valid]) ==
        false
    @test Bool(summary[
        :mgmfrm_external_construct_validation_evidence_passed]) == false
    @test Bool(summary[
        :mgmfrm_independent_public_scope_review_attached_and_valid]) == false
    @test Bool(summary[
        :mgmfrm_independent_public_scope_review_gate_passed]) == false
    @test Bool(summary[:mgmfrm_public_claim_release_decision_signed]) == false
    @test Bool(summary[
        :mgmfrm_external_construct_public_claim_release_gate_passed]) == false
    @test Int(summary[:mgmfrm_external_construct_public_blocker_count]) == 5
    @test !Bool(summary[
        :mgmfrm_external_construct_validation_evidence_passed]) ||
        Bool(summary[
            :mgmfrm_external_construct_validation_evidence_attached_and_valid])
    @test !Bool(summary[
        :mgmfrm_external_construct_public_claim_release_gate_passed]) ||
        Int(summary[:mgmfrm_external_construct_public_blocker_count]) == 0
    @test Bool(summary[:mgmfrm_guarded_fit_method_wiring_passed])
    @test Bool(summary[:mgmfrm_guarded_fit_validation_grid_passed])
    @test Bool(summary[:mgmfrm_guarded_fit_api_dry_run_passed])
    @test Bool(summary[:mgmfrm_guarded_fit_public_exposure_review_passed])
    @test Bool(summary[:prediction_target_and_model_weight_policy_passed])
    @test Bool(summary[:mgmfrm_manual_public_scope_review_for_fit_passed])
    @test !Bool(summary[:manuscript_reproducibility_claims_supported])
    @test Int(summary[:n_blockers]) == 2
    @test Set(String.(summary[:remaining_public_blockers])) == Set([
        "tam_direct_independent_review_pending",
        "tam_pre_execution_refinement_lineage_adjudication_pending",
    ])
    @test String(summary[:recommendation]) ==
        "full_paper_reproduction_archive_recorded_keep_publication_manual"
    @test String(summary[:next_gate]) ==
        "manual_publication_or_registration_by_user_only"
end
