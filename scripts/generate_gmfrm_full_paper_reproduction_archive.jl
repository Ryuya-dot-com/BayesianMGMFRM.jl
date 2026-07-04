#!/usr/bin/env julia

using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures",
        "gmfrm_full_paper_reproduction_archive.json")

include(joinpath(@__DIR__, "local_json.jl"))

const REPRODUCTION_FIXTURES = [
    (name = :source_gmfrm_bridge_logdensity,
        path = "test/fixtures/source_gmfrm_bridge_logdensity.json",
        expected_schema = "bayesianmgmfrm.source_gmfrm_bridge_logdensity.v1",
        generator = "scripts/generate_source_bridge_fixtures.py",
        env_var = "MFRM_SOURCE_GMFRM_BRIDGE_LOGDENSITY_FIXTURE",
        pass_policy = :schema_only,
        hash_policy = :sha256),
    (name = :source_mgmfrm_bridge_logdensity,
        path = "test/fixtures/source_mgmfrm_bridge_logdensity.json",
        expected_schema = "bayesianmgmfrm.source_mgmfrm_bridge_logdensity.v1",
        generator = "scripts/generate_source_bridge_fixtures.py",
        env_var = "MFRM_SOURCE_MGMFRM_BRIDGE_LOGDENSITY_FIXTURE",
        pass_policy = :schema_only,
        hash_policy = :sha256),
    (name = :candidate_chain_study,
        path = "test/fixtures/gmfrm_candidate_chain_study.json",
        expected_schema = "bayesianmgmfrm.gmfrm_candidate_chain_study.v1",
        generator = "scripts/generate_gmfrm_candidate_chain_study.jl",
        env_var = "MFRM_GMFRM_CANDIDATE_CHAIN_STUDY_FIXTURE",
        pass_policy = :summary_passed,
        hash_policy = :sha256),
    (name = :stress_chain_grid,
        path = "test/fixtures/gmfrm_stress_chain_grid.json",
        expected_schema = "bayesianmgmfrm.gmfrm_stress_chain_grid.v1",
        generator = "scripts/generate_gmfrm_stress_chain_grid.jl",
        env_var = "MFRM_GMFRM_STRESS_CHAIN_GRID_FIXTURE",
        pass_policy = :summary_passed,
        hash_policy = :sha256),
    (name = :recovery_smoke_study,
        path = "test/fixtures/gmfrm_recovery_smoke.json",
        expected_schema = "bayesianmgmfrm.gmfrm_recovery_smoke.v1",
        generator = "scripts/generate_gmfrm_recovery_smoke.jl",
        env_var = "MFRM_GMFRM_RECOVERY_SMOKE_FIXTURE",
        pass_policy = :summary_passed,
        hash_policy = :sha256),
    (name = :baseline_comparison,
        path = "test/fixtures/gmfrm_baseline_comparison.json",
        expected_schema = "bayesianmgmfrm.gmfrm_baseline_comparison.v1",
        generator = "scripts/generate_gmfrm_baseline_comparison.jl",
        env_var = "MFRM_GMFRM_BASELINE_COMPARISON_FIXTURE",
        pass_policy = :summary_passed,
        hash_policy = :sha256),
    (name = :baseline_calibration_grid,
        path = "test/fixtures/gmfrm_baseline_calibration_grid.json",
        expected_schema = "bayesianmgmfrm.gmfrm_baseline_calibration_grid.v1",
        generator = "scripts/generate_gmfrm_baseline_calibration_grid.jl",
        env_var = "MFRM_GMFRM_BASELINE_CALIBRATION_GRID_FIXTURE",
        pass_policy = :summary_passed,
        hash_policy = :sha256),
    (name = :interval_decision_grid,
        path = "test/fixtures/gmfrm_interval_decision_grid.json",
        expected_schema = "bayesianmgmfrm.gmfrm_interval_decision_grid.v1",
        generator = "scripts/generate_gmfrm_interval_decision_grid.jl",
        env_var = "MFRM_GMFRM_INTERVAL_DECISION_GRID_FIXTURE",
        pass_policy = :summary_passed,
        hash_policy = :sha256),
    (name = :sparse_design_grid,
        path = "test/fixtures/gmfrm_sparse_design_grid.json",
        expected_schema = "bayesianmgmfrm.gmfrm_sparse_design_grid.v1",
        generator = "scripts/generate_gmfrm_sparse_design_grid.jl",
        env_var = "MFRM_GMFRM_SPARSE_DESIGN_GRID_FIXTURE",
        pass_policy = :summary_passed,
        hash_policy = :sha256),
    (name = :waic_influence_review,
        path = "test/fixtures/gmfrm_waic_influence_review.json",
        expected_schema = "bayesianmgmfrm.gmfrm_waic_influence_review.v1",
        generator = "scripts/generate_gmfrm_waic_influence_review.jl",
        env_var = "MFRM_GMFRM_WAIC_INFLUENCE_REVIEW_FIXTURE",
        pass_policy = :summary_passed,
        hash_policy = :sha256),
    (name = :psis_loo_review,
        path = "test/fixtures/gmfrm_psis_loo_review.json",
        expected_schema = "bayesianmgmfrm.gmfrm_psis_loo_review.v1",
        generator = "scripts/generate_gmfrm_psis_loo_review.jl",
        env_var = "MFRM_GMFRM_PSIS_LOO_REVIEW_FIXTURE",
        pass_policy = :summary_passed,
        hash_policy = :sha256),
    (name = :exact_loo_or_kfold_review,
        path = "test/fixtures/gmfrm_exact_loo_or_kfold_review.json",
        expected_schema = "bayesianmgmfrm.gmfrm_exact_loo_or_kfold_review.v1",
        generator = "scripts/generate_gmfrm_exact_loo_or_kfold_review.jl",
        env_var = "MFRM_GMFRM_EXACT_LOO_OR_KFOLD_REVIEW_FIXTURE",
        pass_policy = :summary_passed,
        hash_policy = :sha256),
    (name = :guarded_fit_api_dry_run,
        path = "test/fixtures/gmfrm_guarded_fit_api_dry_run.json",
        expected_schema = "bayesianmgmfrm.gmfrm_guarded_fit_api_dry_run.v1",
        generator = "scripts/generate_gmfrm_guarded_fit_api_dry_run.jl",
        env_var = "MFRM_GMFRM_GUARDED_FIT_API_DRY_RUN_FIXTURE",
        pass_policy = :summary_passed,
        hash_policy = :sha256),
    (name = :guarded_fit_method_wiring,
        path = "test/fixtures/gmfrm_guarded_fit_method_wiring.json",
        expected_schema = "bayesianmgmfrm.gmfrm_guarded_fit_method_wiring.v1",
        generator = "scripts/generate_gmfrm_guarded_fit_method_wiring.jl",
        env_var = "MFRM_GMFRM_GUARDED_FIT_METHOD_WIRING_FIXTURE",
        pass_policy = :summary_passed,
        hash_policy = :sha256),
    (name = :experimental_fit_validation_grid,
        path = "test/fixtures/gmfrm_experimental_fit_validation_grid.json",
        expected_schema =
            "bayesianmgmfrm.gmfrm_experimental_fit_validation_grid.v1",
        generator = "scripts/generate_gmfrm_experimental_fit_validation_grid.jl",
        env_var = "MFRM_GMFRM_EXPERIMENTAL_FIT_VALIDATION_GRID_FIXTURE",
        pass_policy = :summary_passed,
        hash_policy = :sha256),
    (name = :posterior_predictive_grid,
        path = "test/fixtures/gmfrm_posterior_predictive_grid.json",
        expected_schema =
            "bayesianmgmfrm.gmfrm_posterior_predictive_grid.v1",
        generator = "scripts/generate_gmfrm_posterior_predictive_grid.jl",
        env_var = "MFRM_GMFRM_POSTERIOR_PREDICTIVE_GRID_FIXTURE",
        pass_policy = :summary_passed,
        hash_policy = :sha256),
    (name = :sparse_pathology_recovery_grid,
        path = "test/fixtures/gmfrm_sparse_pathology_recovery_grid.json",
        expected_schema =
            "bayesianmgmfrm.gmfrm_sparse_pathology_recovery_grid.v1",
        generator = "scripts/generate_gmfrm_sparse_pathology_recovery_grid.jl",
        env_var = "MFRM_GMFRM_SPARSE_PATHOLOGY_RECOVERY_GRID_FIXTURE",
        pass_policy = :summary_passed,
        hash_policy = :sha256),
    (name = :prior_likelihood_sensitivity_grid,
        path = "test/fixtures/gmfrm_prior_likelihood_sensitivity_grid.json",
        expected_schema =
            "bayesianmgmfrm.gmfrm_prior_likelihood_sensitivity_grid.v1",
        generator = "scripts/generate_gmfrm_prior_likelihood_sensitivity_grid.jl",
        env_var = "MFRM_GMFRM_PRIOR_LIKELIHOOD_SENSITIVITY_GRID_FIXTURE",
        pass_policy = :summary_passed,
        hash_policy = :sha256),
    (name = :real_data_case_study,
        path = "test/fixtures/gmfrm_real_data_case_study.json",
        expected_schema = "bayesianmgmfrm.gmfrm_real_data_case_study.v1",
        generator = "scripts/generate_gmfrm_real_data_case_study.jl",
        env_var = "MFRM_GMFRM_REAL_DATA_CASE_STUDY_FIXTURE",
        pass_policy = :summary_passed,
        hash_policy = :sha256),
    (name = :claim_recovery_reproduction_archive,
        path = "test/fixtures/gmfrm_claim_recovery_reproduction_archive.json",
        expected_schema =
            "bayesianmgmfrm.gmfrm_claim_recovery_reproduction_archive.v1",
        generator = "scripts/generate_gmfrm_claim_recovery_reproduction_archive.jl",
        env_var =
            "MFRM_GMFRM_CLAIM_RECOVERY_REPRODUCTION_ARCHIVE_FIXTURE",
        pass_policy = :summary_passed,
        hash_policy = :sha256),
    (name = :broader_experimental_exposure_decision_review,
        path =
            "test/fixtures/gmfrm_broader_experimental_exposure_decision_review.json",
        expected_schema =
            "bayesianmgmfrm.gmfrm_broader_experimental_exposure_decision_review.v1",
        generator =
            "scripts/generate_gmfrm_broader_experimental_exposure_decision_review.jl",
        env_var =
            "MFRM_GMFRM_BROADER_EXPERIMENTAL_EXPOSURE_DECISION_REVIEW_FIXTURE",
        pass_policy = :summary_passed,
        hash_policy = :existence_only_avoids_full_archive_broader_review_cycle),
    (name = :dff_estimand_validation_grid,
        path = "test/fixtures/gmfrm_dff_estimand_validation_grid.json",
        expected_schema =
            "bayesianmgmfrm.gmfrm_dff_estimand_validation_grid.v1",
        generator = "scripts/generate_gmfrm_dff_estimand_validation_grid.jl",
        env_var = "MFRM_GMFRM_DFF_ESTIMAND_VALIDATION_GRID_FIXTURE",
        pass_policy = :summary_passed,
        hash_policy = :sha256),
    (name = :manuscript_scale_simulation_grid,
        path = "test/fixtures/gmfrm_manuscript_scale_simulation_grid.json",
        expected_schema =
            "bayesianmgmfrm.gmfrm_manuscript_scale_simulation_grid.v1",
        generator = "scripts/generate_gmfrm_manuscript_scale_simulation_grid.jl",
        env_var = "MFRM_GMFRM_MANUSCRIPT_SCALE_SIMULATION_GRID_FIXTURE",
        pass_policy = :summary_passed,
        hash_policy =
            :existence_only_avoids_full_archive_manuscript_grid_cycle),
    (name = :guarded_exposure_review,
        path = "test/fixtures/gmfrm_guarded_exposure_review.json",
        expected_schema = "bayesianmgmfrm.gmfrm_guarded_exposure_review.v1",
        generator = "scripts/generate_gmfrm_guarded_exposure_review.jl",
        env_var = "MFRM_GMFRM_GUARDED_EXPOSURE_REVIEW_FIXTURE",
        pass_policy = :summary_passed,
        hash_policy = :existence_only_avoids_full_archive_guarded_review_cycle),
    (name = :mgmfrm_candidate_chain_study,
        path = "test/fixtures/mgmfrm_candidate_chain_study.json",
        expected_schema = "bayesianmgmfrm.mgmfrm_candidate_chain_study.v1",
        generator = "scripts/generate_mgmfrm_candidate_chain_study.jl",
        env_var = "MFRM_MGMFRM_CANDIDATE_CHAIN_STUDY_FIXTURE",
        pass_policy = :summary_passed,
        hash_policy = :sha256),
    (name = :mgmfrm_recovery_smoke,
        path = "test/fixtures/mgmfrm_recovery_smoke.json",
        expected_schema = "bayesianmgmfrm.mgmfrm_recovery_smoke.v1",
        generator = "scripts/generate_mgmfrm_recovery_smoke.jl",
        env_var = "MFRM_MGMFRM_RECOVERY_SMOKE_FIXTURE",
        pass_policy = :summary_passed,
        hash_policy = :sha256),
    (name = :mgmfrm_baseline_comparison,
        path = "test/fixtures/mgmfrm_baseline_comparison.json",
        expected_schema = "bayesianmgmfrm.mgmfrm_baseline_comparison.v1",
        generator = "scripts/generate_mgmfrm_baseline_comparison.jl",
        env_var = "MFRM_MGMFRM_BASELINE_COMPARISON_FIXTURE",
        pass_policy = :summary_passed,
        hash_policy = :sha256),
    (name = :mgmfrm_sparse_recovery_grid,
        path = "test/fixtures/mgmfrm_sparse_recovery_grid.json",
        expected_schema = "bayesianmgmfrm.mgmfrm_sparse_recovery_grid.v1",
        generator = "scripts/generate_mgmfrm_sparse_recovery_grid.jl",
        env_var = "MFRM_MGMFRM_SPARSE_RECOVERY_GRID_FIXTURE",
        pass_policy = :summary_passed,
        hash_policy = :sha256),
    (name = :mgmfrm_report_shape_simulation_grid,
        path = "test/fixtures/mgmfrm_report_shape_simulation_grid.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_report_shape_simulation_grid.v1",
        generator = "scripts/generate_mgmfrm_report_shape_simulation_grid.jl",
        env_var = "MFRM_MGMFRM_REPORT_SHAPE_SIMULATION_GRID_FIXTURE",
        pass_policy = :summary_passed,
        hash_policy = :sha256),
    (name = :mgmfrm_q_matrix_validation_expansion,
        path = "test/fixtures/mgmfrm_q_matrix_validation_expansion.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_q_matrix_validation_expansion.v1",
        generator = "scripts/generate_mgmfrm_q_matrix_validation_expansion.jl",
        env_var = "MFRM_MGMFRM_Q_MATRIX_VALIDATION_EXPANSION_FIXTURE",
        pass_policy = :summary_passed,
        hash_policy = :sha256),
    (name = :mgmfrm_empirical_q_matrix_recovery_policy,
        path = "test/fixtures/mgmfrm_empirical_q_matrix_recovery_policy.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_empirical_q_matrix_recovery_policy.v1",
        generator =
            "scripts/generate_mgmfrm_empirical_q_matrix_recovery_policy.jl",
        env_var = "MFRM_MGMFRM_EMPIRICAL_Q_MATRIX_RECOVERY_POLICY_FIXTURE",
        pass_policy = :summary_passed,
        hash_policy = :sha256),
    (name = :mgmfrm_empirical_q_matrix_recovery_simulation_grid,
        path =
            "test/fixtures/mgmfrm_empirical_q_matrix_recovery_simulation_grid.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_empirical_q_matrix_recovery_simulation_grid.v1",
        generator =
            "scripts/generate_mgmfrm_empirical_q_matrix_recovery_simulation_grid.jl",
        env_var =
            "MFRM_MGMFRM_EMPIRICAL_Q_MATRIX_RECOVERY_SIMULATION_GRID_FIXTURE",
        pass_policy = :summary_passed,
        hash_policy = :sha256),
    (name = :mgmfrm_q_candidate_real_fit_diagnostic_linkage,
        path =
            "test/fixtures/mgmfrm_q_candidate_real_fit_diagnostic_linkage.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_q_candidate_real_fit_diagnostic_linkage.v1",
        generator =
            "scripts/generate_mgmfrm_q_candidate_real_fit_diagnostic_linkage.jl",
        env_var =
            "MFRM_MGMFRM_Q_CANDIDATE_REAL_FIT_DIAGNOSTIC_LINKAGE_FIXTURE",
        pass_policy = :summary_passed,
        hash_policy = :sha256),
    (name = :mgmfrm_q_revision_cross_validation_policy,
        path =
            "test/fixtures/mgmfrm_q_revision_cross_validation_policy.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_q_revision_cross_validation_policy.v1",
        generator =
            "scripts/generate_mgmfrm_q_revision_cross_validation_policy.jl",
        env_var =
            "MFRM_MGMFRM_Q_REVISION_CROSS_VALIDATION_POLICY_FIXTURE",
        pass_policy = :summary_passed,
        hash_policy = :sha256),
    (name = :mgmfrm_q_revision_construct_validity_review,
        path =
            "test/fixtures/mgmfrm_q_revision_construct_validity_review.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_q_revision_construct_validity_review.v1",
        generator =
            "scripts/generate_mgmfrm_q_revision_construct_validity_review.jl",
        env_var =
            "MFRM_MGMFRM_Q_REVISION_CONSTRUCT_VALIDITY_REVIEW_FIXTURE",
        pass_policy = :summary_passed,
        hash_policy = :sha256),
    (name = :mgmfrm_guarded_local_fit_entrypoint,
        path =
            "test/fixtures/mgmfrm_guarded_local_fit_entrypoint.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_guarded_local_fit_entrypoint.v1",
        generator =
            "scripts/generate_mgmfrm_guarded_local_fit_entrypoint.jl",
        env_var =
            "MFRM_MGMFRM_GUARDED_LOCAL_FIT_ENTRYPOINT_FIXTURE",
        pass_policy = :summary_passed,
        hash_policy = :sha256),
    (name = :mgmfrm_guarded_fit_method_wiring,
        path = "test/fixtures/mgmfrm_guarded_fit_method_wiring.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_guarded_fit_method_wiring.v1",
        generator = "scripts/generate_mgmfrm_guarded_fit_method_wiring.jl",
        env_var = "MFRM_MGMFRM_GUARDED_FIT_METHOD_WIRING_FIXTURE",
        pass_policy = :summary_passed,
        hash_policy = :sha256),
    (name = :mgmfrm_guarded_fit_validation_grid,
        path = "test/fixtures/mgmfrm_guarded_fit_validation_grid.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_guarded_fit_validation_grid.v1",
        generator = "scripts/generate_mgmfrm_guarded_fit_validation_grid.jl",
        env_var = "MFRM_MGMFRM_GUARDED_FIT_VALIDATION_GRID_FIXTURE",
        pass_policy = :summary_passed,
        hash_policy = :sha256),
    (name = :mgmfrm_guarded_fit_api_dry_run,
        path = "test/fixtures/mgmfrm_guarded_fit_api_dry_run.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_guarded_fit_api_dry_run.v1",
        generator = "scripts/generate_mgmfrm_guarded_fit_api_dry_run.jl",
        env_var = "MFRM_MGMFRM_GUARDED_FIT_API_DRY_RUN_FIXTURE",
        pass_policy = :summary_passed,
        hash_policy = :sha256),
    (name = :mgmfrm_guarded_fit_public_exposure_review,
        path = "test/fixtures/mgmfrm_guarded_fit_public_exposure_review.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_guarded_fit_public_exposure_review.v1",
        generator =
            "scripts/generate_mgmfrm_guarded_fit_public_exposure_review.jl",
        env_var =
            "MFRM_MGMFRM_GUARDED_FIT_PUBLIC_EXPOSURE_REVIEW_FIXTURE",
        pass_policy = :summary_passed,
        hash_policy = :sha256),
    (name = :prediction_target_and_model_weight_policy,
        path =
            "test/fixtures/gmfrm_prediction_target_and_model_weight_policy.json",
        expected_schema =
            "bayesianmgmfrm.gmfrm_prediction_target_and_model_weight_policy.v1",
        generator =
            "scripts/generate_gmfrm_prediction_target_and_model_weight_policy.jl",
        env_var =
            "MFRM_GMFRM_PREDICTION_TARGET_AND_MODEL_WEIGHT_POLICY_FIXTURE",
        pass_policy = :summary_passed,
        hash_policy = :sha256),
    (name = :mgmfrm_manual_public_scope_review_for_fit,
        path =
            "test/fixtures/mgmfrm_manual_public_scope_review_for_fit.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_manual_public_scope_review_for_fit.v1",
        generator =
            "scripts/generate_mgmfrm_manual_public_scope_review_for_fit.jl",
        env_var =
            "MFRM_MGMFRM_MANUAL_PUBLIC_SCOPE_REVIEW_FOR_FIT_FIXTURE",
        pass_policy = :summary_passed,
        hash_policy = :sha256),
]

const CODE_AND_DOC_PATHS = [
    "Project.toml",
    "README.md",
    "NEWS.md",
    "ROADMAP.md",
    "src/BayesianMGMFRM.jl",
    "src/bayesian_fit.jl",
    "src/facet_workflow.jl",
    "test/runtests.jl",
    "test/fixtures/README.md",
    "docs/make.jl",
    "docs/src/index.md",
    "docs/src/api.md",
    "docs/src/data-validation.md",
    "docs/src/fitting.md",
    "docs/src/model-equations.md",
    "docs/src/roadmap.md",
    "scripts/local_json.jl",
    "scripts/pre_registration_gate.jl",
    "scripts/generate_source_bridge_fixtures.py",
    "scripts/generate_gmfrm_full_paper_reproduction_archive.jl",
    "scripts/generate_mgmfrm_report_shape_simulation_grid.jl",
    "scripts/generate_mgmfrm_q_matrix_validation_expansion.jl",
    "scripts/generate_mgmfrm_empirical_q_matrix_recovery_policy.jl",
    "scripts/generate_mgmfrm_empirical_q_matrix_recovery_simulation_grid.jl",
    "scripts/generate_mgmfrm_q_candidate_real_fit_diagnostic_linkage.jl",
    "scripts/generate_mgmfrm_q_revision_cross_validation_policy.jl",
    "scripts/generate_mgmfrm_q_revision_construct_validity_review.jl",
    "scripts/generate_mgmfrm_guarded_local_fit_entrypoint.jl",
    "scripts/generate_mgmfrm_guarded_fit_method_wiring.jl",
    "scripts/generate_mgmfrm_guarded_fit_validation_grid.jl",
    "scripts/generate_mgmfrm_guarded_fit_api_dry_run.jl",
    "scripts/generate_mgmfrm_guarded_fit_public_exposure_review.jl",
    "scripts/generate_gmfrm_prediction_target_and_model_weight_policy.jl",
    "scripts/generate_mgmfrm_manual_public_scope_review_for_fit.jl",
    "test/stan/source_gmfrm_fixture.stan",
    "test/stan/source_mgmfrm_fixture.stan",
]

const EXTERNAL_SOURCE_PATHS = [
    "../Simulation/data/writing_long.csv",
    "../Simulation/data/speaking_long.csv",
]

const FULL_REGENERATION_COMMANDS = [
    (artifact = :source_bridge_logdensity_fixtures,
        command = "python scripts/generate_source_bridge_fixtures.py"),
    (artifact = :gmfrm_candidate_chain_study,
        command = "julia --project=. scripts/generate_gmfrm_candidate_chain_study.jl"),
    (artifact = :gmfrm_stress_chain_grid,
        command = "julia --project=. scripts/generate_gmfrm_stress_chain_grid.jl"),
    (artifact = :gmfrm_recovery_smoke,
        command = "julia --project=. scripts/generate_gmfrm_recovery_smoke.jl"),
    (artifact = :gmfrm_baseline_comparison,
        command = "julia --project=. scripts/generate_gmfrm_baseline_comparison.jl"),
    (artifact = :gmfrm_baseline_calibration_grid,
        command = "julia --project=. scripts/generate_gmfrm_baseline_calibration_grid.jl"),
    (artifact = :gmfrm_interval_decision_grid,
        command = "julia --project=. scripts/generate_gmfrm_interval_decision_grid.jl"),
    (artifact = :gmfrm_sparse_design_grid,
        command = "julia --project=. scripts/generate_gmfrm_sparse_design_grid.jl"),
    (artifact = :gmfrm_waic_influence_review,
        command = "julia --project=. scripts/generate_gmfrm_waic_influence_review.jl"),
    (artifact = :gmfrm_psis_loo_review,
        command = "julia --project=. scripts/generate_gmfrm_psis_loo_review.jl"),
    (artifact = :gmfrm_exact_loo_or_kfold_review,
        command = "julia --project=. scripts/generate_gmfrm_exact_loo_or_kfold_review.jl"),
    (artifact = :gmfrm_guarded_fit_method_wiring,
        command = "julia --project=. scripts/generate_gmfrm_guarded_fit_method_wiring.jl"),
    (artifact = :gmfrm_experimental_fit_validation_grid,
        command = "julia --project=. scripts/generate_gmfrm_experimental_fit_validation_grid.jl"),
    (artifact = :gmfrm_posterior_predictive_grid,
        command = "julia --project=. scripts/generate_gmfrm_posterior_predictive_grid.jl"),
    (artifact = :gmfrm_sparse_pathology_recovery_grid,
        command = "julia --project=. scripts/generate_gmfrm_sparse_pathology_recovery_grid.jl"),
    (artifact = :gmfrm_prior_likelihood_sensitivity_grid,
        command = "julia --project=. scripts/generate_gmfrm_prior_likelihood_sensitivity_grid.jl"),
    (artifact = :gmfrm_real_data_case_study,
        command = "julia --project=. scripts/generate_gmfrm_real_data_case_study.jl"),
    (artifact = :gmfrm_guarded_fit_api_dry_run,
        command = "julia --project=. scripts/generate_gmfrm_guarded_fit_api_dry_run.jl"),
    (artifact = :gmfrm_claim_recovery_reproduction_archive,
        command = "julia --project=. scripts/generate_gmfrm_claim_recovery_reproduction_archive.jl"),
    (artifact = :mgmfrm_candidate_chain_study,
        command = "julia --project=. scripts/generate_mgmfrm_candidate_chain_study.jl"),
    (artifact = :mgmfrm_recovery_smoke,
        command = "julia --project=. scripts/generate_mgmfrm_recovery_smoke.jl"),
    (artifact = :mgmfrm_baseline_comparison,
        command = "julia --project=. scripts/generate_mgmfrm_baseline_comparison.jl"),
    (artifact = :mgmfrm_sparse_recovery_grid,
        command = "julia --project=. scripts/generate_mgmfrm_sparse_recovery_grid.jl"),
    (artifact = :mgmfrm_report_shape_simulation_grid,
        command =
            "julia --project=. scripts/generate_mgmfrm_report_shape_simulation_grid.jl"),
    (artifact = :mgmfrm_q_matrix_validation_expansion,
        command =
            "julia --project=. scripts/generate_mgmfrm_q_matrix_validation_expansion.jl"),
    (artifact = :mgmfrm_empirical_q_matrix_recovery_policy,
        command =
            "julia --project=. scripts/generate_mgmfrm_empirical_q_matrix_recovery_policy.jl"),
    (artifact = :mgmfrm_empirical_q_matrix_recovery_simulation_grid,
        command =
            "julia --project=. scripts/generate_mgmfrm_empirical_q_matrix_recovery_simulation_grid.jl"),
    (artifact = :mgmfrm_q_candidate_real_fit_diagnostic_linkage,
        command =
            "julia --project=. scripts/generate_mgmfrm_q_candidate_real_fit_diagnostic_linkage.jl"),
    (artifact = :mgmfrm_q_revision_cross_validation_policy,
        command =
            "julia --project=. scripts/generate_mgmfrm_q_revision_cross_validation_policy.jl"),
    (artifact = :mgmfrm_q_revision_construct_validity_review,
        command =
            "julia --project=. scripts/generate_mgmfrm_q_revision_construct_validity_review.jl"),
    (artifact = :mgmfrm_guarded_local_fit_entrypoint,
        command =
            "julia --project=. scripts/generate_mgmfrm_guarded_local_fit_entrypoint.jl"),
    (artifact = :mgmfrm_guarded_fit_method_wiring,
        command = "julia --project=. scripts/generate_mgmfrm_guarded_fit_method_wiring.jl"),
    (artifact = :mgmfrm_guarded_fit_validation_grid,
        command = "julia --project=. scripts/generate_mgmfrm_guarded_fit_validation_grid.jl"),
    (artifact = :mgmfrm_guarded_fit_api_dry_run,
        command = "julia --project=. scripts/generate_mgmfrm_guarded_fit_api_dry_run.jl"),
    (artifact = :mgmfrm_guarded_fit_public_exposure_review,
        command =
            "julia --project=. scripts/generate_mgmfrm_guarded_fit_public_exposure_review.jl"),
    (artifact = :prediction_target_and_model_weight_policy,
        command =
            "julia --project=. scripts/generate_gmfrm_prediction_target_and_model_weight_policy.jl"),
    (artifact = :mgmfrm_manual_public_scope_review_for_fit,
        command =
            "julia --project=. scripts/generate_mgmfrm_manual_public_scope_review_for_fit.jl"),
    (artifact = :gmfrm_dff_estimand_validation_grid,
        command = "julia --project=. scripts/generate_gmfrm_dff_estimand_validation_grid.jl"),
    (artifact = :gmfrm_full_paper_reproduction_archive,
        command = "julia --project=. scripts/generate_gmfrm_full_paper_reproduction_archive.jl"),
    (artifact = :gmfrm_manuscript_scale_simulation_grid,
        command = "julia --project=. scripts/generate_gmfrm_manuscript_scale_simulation_grid.jl"),
    (artifact = :gmfrm_broader_experimental_exposure_decision_review,
        command =
            "julia --project=. scripts/generate_gmfrm_broader_experimental_exposure_decision_review.jl"),
    (artifact = :gmfrm_guarded_exposure_review,
        command = "julia --project=. scripts/generate_gmfrm_guarded_exposure_review.jl"),
]

const VERIFICATION_COMMANDS = [
    (name = :package_tests,
        command = "julia --project=. -e 'import Pkg; Pkg.test()'",
        execution = :required_before_claim_use),
    (name = :documentation_build,
        command = "julia --project=docs docs/make.jl",
        execution = :required_before_claim_use),
    (name = :local_pre_registration_gate,
        command =
            "julia --startup-file=no scripts/pre_registration_gate.jl --skip-tests --skip-docs --skip-public-wording",
        execution = :required_before_claim_use),
    (name = :whitespace_check,
        command = "git diff --check",
        execution = :required_before_claim_use),
]

const PROTOCOL = (;
    protocol_id = "gmfrm_full_paper_reproduction_archive_v1",
    review_kind = :local_full_paper_reproduction_archive,
    publication_or_registration_action = false,
    local_only = true,
    target = :full_local_reproduction_bundle_for_guarded_scalar_gmfrm_and_minimal_mgmfrm,
    archive_scope = :full_and_fast_local_reproduction_manifest,
    thresholds = (;
        require_all_fixture_artifacts_present = true,
        require_all_expected_schemas = true,
        require_all_fixture_summaries_passed = true,
        require_all_generator_scripts_present = true,
        require_all_code_doc_references_present = true,
        require_all_external_sources_present = true,
        require_full_regeneration_commands_recorded = true,
        require_verification_commands_recorded = true,
        require_all_commands_local_only = true,
        require_no_publication_commands = true,
        require_guarded_exposure_review_passed = true,
        require_broader_exposure_review_passed = true,
        require_manuscript_scale_simulation_grid_passed = true,
        require_mgmfrm_sparse_recovery_grid_passed = true,
        require_mgmfrm_report_shape_simulation_grid_passed = true,
        require_mgmfrm_q_matrix_validation_expansion_passed = true,
        require_mgmfrm_empirical_q_matrix_recovery_policy_passed = true,
        require_mgmfrm_empirical_q_matrix_recovery_simulation_grid_passed =
            true,
        require_mgmfrm_q_candidate_real_fit_diagnostic_linkage_passed = true,
        require_mgmfrm_q_revision_cross_validation_policy_passed = true,
        require_mgmfrm_q_revision_construct_validity_review_passed = true,
        require_mgmfrm_guarded_local_fit_entrypoint_passed = true,
        require_mgmfrm_guarded_fit_method_wiring_passed = true,
        require_mgmfrm_guarded_fit_validation_grid_passed = true,
        require_mgmfrm_guarded_fit_api_dry_run_passed = true,
        require_mgmfrm_guarded_fit_public_exposure_review_passed = true,
        require_prediction_target_and_model_weight_policy_passed = true,
        require_mgmfrm_manual_public_scope_review_for_fit_passed = true,
    ),
)

function usage()
    return """
    Generate the local full-paper reproduction archive artifact.

    This archive records local fixture, code/doc, source-data, command, seed,
    and hash evidence. It does not publish, register, push, upload, or create a
    public release.

    Usage:
      julia --project=. scripts/generate_gmfrm_full_paper_reproduction_archive.jl [--output PATH]
    """
end

function parse_args(args)
    output = DEFAULT_OUTPUT
    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--output"
            index < length(args) || error("--output requires a path")
            output = abspath(args[index + 1])
            index += 2
        elseif arg in ("-h", "--help")
            println(usage())
            exit(0)
        else
            error("unknown argument: $arg")
        end
    end
    return output
end

project_version() = String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])
file_sha256(path::AbstractString) = bytes2hex(open(sha256, path))
local_path(path::AbstractString) = normpath(joinpath(ROOT, path))

function parse_json_string_literal(chars::Vector{Char}, index::Int)
    chars[index] == '"' || error("expected JSON string at character $index")
    io = IOBuffer()
    escaped = false
    index += 1
    while index <= length(chars)
        char = chars[index]
        if escaped
            if char == '"' || char == '\\' || char == '/'
                print(io, char)
            elseif char == 'n'
                print(io, '\n')
            elseif char == 'r'
                print(io, '\r')
            elseif char == 't'
                print(io, '\t')
            else
                error("unsupported JSON escape sequence \\$char")
            end
            escaped = false
        elseif char == '\\'
            escaped = true
        elseif char == '"'
            return String(take!(io)), index + 1
        else
            print(io, char)
        end
        index += 1
    end
    error("unterminated JSON string")
end

function skip_ws(chars::Vector{Char}, index::Int)
    while index <= length(chars) && chars[index] in (' ', '\n', '\r', '\t')
        index += 1
    end
    return index
end

function json_value_end(chars::Vector{Char}, index::Int)
    index = skip_ws(chars, index)
    depth = 0
    in_string = false
    escaped = false
    while index <= length(chars)
        char = chars[index]
        if in_string
            if escaped
                escaped = false
            elseif char == '\\'
                escaped = true
            elseif char == '"'
                in_string = false
            end
        elseif char == '"'
            in_string = true
        elseif char == '{' || char == '['
            depth += 1
        elseif char == '}' || char == ']'
            depth == 0 && return index - 1
            depth -= 1
        elseif char == ',' && depth == 0
            return index - 1
        end
        index += 1
    end
    return length(chars)
end

function json_value_for_key(text::AbstractString, key::AbstractString)
    chars = collect(text)
    index = skip_ws(chars, 1)
    chars[index] == '{' || error("expected JSON object")
    index += 1
    while index <= length(chars)
        index = skip_ws(chars, index)
        index > length(chars) && break
        chars[index] == '}' && break
        parsed_key, index = parse_json_string_literal(chars, index)
        index = skip_ws(chars, index)
        chars[index] == ':' || error("expected ':' after JSON key $parsed_key")
        index = skip_ws(chars, index + 1)
        value_start = index
        value_stop = json_value_end(chars, value_start)
        parsed_key == key && return strip(String(chars[value_start:value_stop]))
        index = skip_ws(chars, value_stop + 1)
        if index <= length(chars) && chars[index] == ','
            index += 1
        end
    end
    return nothing
end

function required_value(text::AbstractString, key::AbstractString)
    value = json_value_for_key(text, key)
    value === nothing && error("JSON field `$key` not found")
    return value
end

function json_string(text::AbstractString, key::AbstractString)
    parsed, _ = parse_json_string_literal(collect(required_value(text, key)), 1)
    return parsed
end

function json_optional_bool(text::AbstractString, key::AbstractString)
    value = json_value_for_key(text, key)
    value === nothing && return missing
    value == "true" && return true
    value == "false" && return false
    value == "null" && return missing
    error("JSON field `$key` is not boolean or null")
end

function json_summary(text::AbstractString)
    return json_value_for_key(text, "summary")
end

function summary_passed(spec, summary)
    spec.pass_policy === :schema_only && return true
    summary === nothing && return false
    for key in ("passed", "overall_passed", "reviewed")
        value = json_optional_bool(summary, key)
        value === missing || return Bool(value)
    end
    if spec.name === :guarded_exposure_review
        value = json_optional_bool(summary, "all_local_evidence_passed")
        return value === missing ? false : Bool(value)
    end
    return false
end

function command_is_local_only(command::AbstractString)
    banned = [
        "git push",
        "gh release",
        "gh repo",
        "Registrator",
        "Pkg.register",
        "registry add",
        "publish",
        "upload",
    ]
    lowered = lowercase(command)
    return all(!occursin(lowercase(term), lowered) for term in banned)
end

function fixture_record(spec)
    path = local_path(spec.path)
    exists = isfile(path)
    text = exists ? read(path, String) : ""
    schema = exists ? json_string(text, "schema") : missing
    summary = exists ? json_summary(text) : nothing
    schema_matches = exists && schema == spec.expected_schema
    sha_policy = spec.hash_policy
    return (;
        artifact = spec.name,
        path = spec.path,
        exists,
        hash_policy = sha_policy,
        sha256 = exists && sha_policy === :sha256 ? file_sha256(path) : missing,
        expected_schema = spec.expected_schema,
        schema,
        schema_matches,
        generator = spec.generator,
        generation_command = if endswith(spec.generator, ".py")
            "python $(spec.generator)"
        else
            "julia --project=. $(spec.generator)"
        end,
        env_var = spec.env_var,
        generator_exists = isfile(local_path(spec.generator)),
        summary_present = summary !== nothing,
        summary_passed = exists && schema_matches && summary_passed(spec, summary),
    )
end

function path_record(path)
    resolved = local_path(path)
    return (;
        path,
        exists = isfile(resolved),
        sha256 = isfile(resolved) ? file_sha256(resolved) : missing,
        line_count = isfile(resolved) ? countlines(resolved) : missing,
    )
end

function command_record(spec, step::Int)
    return (;
        step,
        spec...,
        local_only = command_is_local_only(spec.command),
    )
end

function record_by_name(records, name::Symbol)
    for record in records
        record.artifact === name && return record
    end
    error("record not found: $name")
end

function build_artifact()
    fixture_records = [fixture_record(spec) for spec in REPRODUCTION_FIXTURES]
    code_doc_records = [path_record(path) for path in CODE_AND_DOC_PATHS]
    source_records = [path_record(path) for path in EXTERNAL_SOURCE_PATHS]
    regeneration_commands = [
        command_record(spec, index)
        for (index, spec) in enumerate(FULL_REGENERATION_COMMANDS)
    ]
    verification_commands = [
        command_record(spec, index)
        for (index, spec) in enumerate(VERIFICATION_COMMANDS)
    ]

    guarded = record_by_name(fixture_records, :guarded_exposure_review)
    broader = record_by_name(
        fixture_records, :broader_experimental_exposure_decision_review)
    manuscript = record_by_name(fixture_records, :manuscript_scale_simulation_grid)
    claim = record_by_name(fixture_records, :claim_recovery_reproduction_archive)
    mgmfrm_sparse = record_by_name(fixture_records, :mgmfrm_sparse_recovery_grid)
    mgmfrm_report_shape =
        record_by_name(fixture_records, :mgmfrm_report_shape_simulation_grid)
    mgmfrm_q_expansion =
        record_by_name(fixture_records, :mgmfrm_q_matrix_validation_expansion)
    mgmfrm_q_recovery_policy =
        record_by_name(fixture_records,
            :mgmfrm_empirical_q_matrix_recovery_policy)
    mgmfrm_q_recovery_simulation =
        record_by_name(fixture_records,
            :mgmfrm_empirical_q_matrix_recovery_simulation_grid)
    mgmfrm_q_fit_linkage =
        record_by_name(fixture_records,
            :mgmfrm_q_candidate_real_fit_diagnostic_linkage)
    mgmfrm_q_cv_policy =
        record_by_name(fixture_records,
            :mgmfrm_q_revision_cross_validation_policy)
    mgmfrm_q_construct_review =
        record_by_name(fixture_records,
            :mgmfrm_q_revision_construct_validity_review)
    mgmfrm_local_fit_entrypoint =
        record_by_name(fixture_records, :mgmfrm_guarded_local_fit_entrypoint)
    mgmfrm_method =
        record_by_name(fixture_records, :mgmfrm_guarded_fit_method_wiring)
    mgmfrm_validation =
        record_by_name(fixture_records, :mgmfrm_guarded_fit_validation_grid)
    mgmfrm_api_dry_run =
        record_by_name(fixture_records, :mgmfrm_guarded_fit_api_dry_run)
    mgmfrm_public_review =
        record_by_name(fixture_records,
            :mgmfrm_guarded_fit_public_exposure_review)
    prediction_policy =
        record_by_name(fixture_records,
            :prediction_target_and_model_weight_policy)
    mgmfrm_scope_review =
        record_by_name(fixture_records,
            :mgmfrm_manual_public_scope_review_for_fit)

    all_fixture_artifacts_present = all(record -> record.exists, fixture_records)
    all_expected_schemas = all(record -> record.schema_matches, fixture_records)
    all_fixture_summaries_passed =
        all(record -> record.summary_passed, fixture_records)
    all_generator_scripts_present =
        all(record -> record.generator_exists, fixture_records)
    all_code_doc_references_present =
        all(record -> record.exists, code_doc_records)
    all_external_sources_present = all(record -> record.exists, source_records)
    full_regeneration_commands_recorded = !isempty(regeneration_commands)
    verification_commands_recorded = !isempty(verification_commands)
    all_commands_local_only =
        all(record -> record.local_only, regeneration_commands) &&
        all(record -> record.local_only, verification_commands)
    no_publication_commands = all_commands_local_only

    passed = all_fixture_artifacts_present &&
        all_expected_schemas &&
        all_fixture_summaries_passed &&
        all_generator_scripts_present &&
        all_code_doc_references_present &&
        all_external_sources_present &&
        full_regeneration_commands_recorded &&
        verification_commands_recorded &&
        all_commands_local_only &&
        no_publication_commands &&
        guarded.summary_passed &&
        broader.summary_passed &&
        manuscript.summary_passed &&
        mgmfrm_sparse.summary_passed &&
        mgmfrm_report_shape.summary_passed &&
        mgmfrm_q_expansion.summary_passed &&
        mgmfrm_q_recovery_policy.summary_passed &&
        mgmfrm_q_recovery_simulation.summary_passed &&
        mgmfrm_q_fit_linkage.summary_passed &&
        mgmfrm_q_cv_policy.summary_passed &&
        mgmfrm_q_construct_review.summary_passed &&
        mgmfrm_local_fit_entrypoint.summary_passed &&
        mgmfrm_method.summary_passed &&
        mgmfrm_validation.summary_passed &&
        mgmfrm_api_dry_run.summary_passed &&
        mgmfrm_public_review.summary_passed &&
        prediction_policy.summary_passed &&
        mgmfrm_scope_review.summary_passed

    return (;
        schema = "bayesianmgmfrm.gmfrm_full_paper_reproduction_archive.v1",
        family = :gmfrm,
        scope = :full_paper_reproduction_archive,
        status = :full_paper_reproduction_archive_recorded,
        decision = :archive_full_and_fast_reproduction_bundle_local_only,
        public_fit = true,
        experimental_public = true,
        fit_ready = true,
        broader_public_fit = false,
        publication_or_registration_action = false,
        package = (;
            name = "BayesianMGMFRM",
            version = project_version(),
            julia_version = string(VERSION),
        ),
        protocol = PROTOCOL,
        fixture_records,
        code_doc_records,
        source_records,
        full_regeneration_commands = regeneration_commands,
        verification_commands,
        cycle_break_references = [
            (artifact =
                    "test/fixtures/gmfrm_broader_experimental_exposure_decision_review.json",
                reason = :avoid_full_archive_broader_review_hash_cycle,
                hash_policy = :existence_only),
            (artifact = "test/fixtures/gmfrm_guarded_exposure_review.json",
                reason = :avoid_full_archive_guarded_review_hash_cycle,
                hash_policy = :existence_only),
            (artifact =
                    "test/fixtures/gmfrm_manuscript_scale_simulation_grid.json",
                reason = :avoid_full_archive_manuscript_grid_hash_cycle,
                hash_policy = :existence_only),
        ],
        decision_record = (;
            selected_decision =
                :full_paper_reproduction_archive_recorded_local_only,
            scalar_guarded_fit_allowed = true,
            broader_generalized_fit_allowed = false,
            mgmfrm_fit_allowed = true,
            dff_model_effects_allowed = false,
            model_weights_allowed = false,
            manuscript_reproducibility_claims_supported = true,
            publication_or_registration_action = false,
            public_exposure_support =
                :local_full_reproduction_archive_recorded,
            interpretation =
                :full_archive_recorded_without_publication_or_registration,
            required_followup = :manual_publication_or_registration_by_user_only,
        ),
        summary = (;
            passed,
            publication_or_registration_action = false,
            local_only = true,
            all_fixture_artifacts_present,
            all_expected_schemas,
            all_fixture_summaries_passed,
            all_generator_scripts_present,
            all_code_doc_references_present,
            all_external_sources_present,
            full_regeneration_commands_recorded,
            verification_commands_recorded,
            all_commands_local_only,
            no_publication_commands,
            n_fixture_artifacts = length(fixture_records),
            n_code_doc_records = length(code_doc_records),
            n_source_records = length(source_records),
            n_full_regeneration_commands = length(regeneration_commands),
            n_verification_commands = length(verification_commands),
            claim_recovery_reproduction_archive_passed = claim.summary_passed,
            guarded_exposure_review_passed = guarded.summary_passed,
            broader_experimental_exposure_decision_review_passed =
                broader.summary_passed,
            manuscript_scale_simulation_grid_passed = manuscript.summary_passed,
            mgmfrm_sparse_recovery_grid_passed = mgmfrm_sparse.summary_passed,
            mgmfrm_report_shape_simulation_grid_passed =
                mgmfrm_report_shape.summary_passed,
            mgmfrm_q_matrix_validation_expansion_passed =
                mgmfrm_q_expansion.summary_passed,
            mgmfrm_empirical_q_matrix_recovery_policy_passed =
                mgmfrm_q_recovery_policy.summary_passed,
            mgmfrm_empirical_q_matrix_recovery_simulation_grid_passed =
                mgmfrm_q_recovery_simulation.summary_passed,
            mgmfrm_q_candidate_real_fit_diagnostic_linkage_passed =
                mgmfrm_q_fit_linkage.summary_passed,
            mgmfrm_q_revision_cross_validation_policy_passed =
                mgmfrm_q_cv_policy.summary_passed,
            mgmfrm_q_revision_construct_validity_review_passed =
                mgmfrm_q_construct_review.summary_passed,
            mgmfrm_guarded_local_fit_entrypoint_passed =
                mgmfrm_local_fit_entrypoint.summary_passed,
            mgmfrm_guarded_fit_method_wiring_passed =
                mgmfrm_method.summary_passed,
            mgmfrm_guarded_fit_validation_grid_passed =
                mgmfrm_validation.summary_passed,
            mgmfrm_guarded_fit_api_dry_run_passed =
                mgmfrm_api_dry_run.summary_passed,
            mgmfrm_guarded_fit_public_exposure_review_passed =
                mgmfrm_public_review.summary_passed,
            prediction_target_and_model_weight_policy_passed =
                prediction_policy.summary_passed,
            mgmfrm_manual_public_scope_review_for_fit_passed =
                mgmfrm_scope_review.summary_passed,
            scalar_guarded_fit_allowed = true,
            broader_generalized_fit_allowed = false,
            mgmfrm_fit_allowed = true,
            dff_model_effects_allowed = false,
            model_weights_allowed = false,
            manuscript_reproducibility_claims_supported = true,
            n_blockers = 0,
            remaining_public_blockers = Symbol[],
            recommendation =
                :full_paper_reproduction_archive_recorded_keep_publication_manual,
            next_gate = :manual_publication_or_registration_by_user_only,
        ),
    )
end

function main(args)
    output = parse_args(args)
    artifact = build_artifact()
    write_artifact(output, artifact)
    println("wrote ", relpath(output, ROOT))
    println("passed=", artifact.summary.passed,
        " fixtures=", artifact.summary.n_fixture_artifacts,
        " next_gate=", artifact.summary.next_gate)
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
