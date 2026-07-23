"""
    BayesianMGMFRM

Tools for preparing long-format many-facet Rasch rating data.

The current public API is intentionally limited to deterministic indexing,
pre-fit data validation, MFRM/GMFRM/MGMFRM specification manifests, minimal
RSM/PCM design scaffolding, and initial Bayesian fitting, predictive-check, and
WAIC / raw or PSIS-smoothed importance-sampling LOO paths for small validation
examples. The minimal MFRM/RSM/PCM design can be fit with a random-walk example
backend, an initial AdvancedHMC/NUTS backend, or a Turing/NUTS backend. Guarded
experimental generalized paths are available through
`BayesianMGMFRM.Experimental.fit(spec)` for source-aligned
`thresholds = :partial_credit`
specs without anchors or fitted DFF terms. The scalar rater-consistency GMFRM
configuration requires `discrimination = :rater`; the fixed-Q confirmatory MGMFRM
configuration requires `dimensions >= 2` and the generic compatibility selector
`discrimination = :none`. Unsupported manifest options are rejected before
numerical execution rather than silently reinterpreted. Broader generalized
discrimination likelihoods, group/DFF model effects, anchors, rating-scale
generalized kernels, exploratory MGMFRM fitting, and free-correlation fitting
remain planned work.
An exactly two-dimensional free-latent-correlation log-density and gradient
candidate is quarantined separately at
`BayesianMGMFRM.Experimental.free_latent_correlation_2d_candidate`. A
response-level known-truth generator and a quarantined single-dataset
multichain recovery pilot are available in the same quarantine. They return
NamedTuples only, never set replicated recovery to verified, and are not
connected to the public fitting, result-type, or cache contracts.
A frozen 525-unit replicated-study roster, denominator-preserving ledger,
fail-closed single-unit preflight, MCMC-free initial-gradient resource probe,
bounded fixture dry run, pre-execution archive diagnostic, and versioned pure
scorer are also available only through the experimental quarantine. The
pre-execution runner cannot create or interpret a scientific attempt, and the
compact result contract does not yet persist raw draws for independent
diagnostic recalculation. No replicated scientific study has been executed,
and none of these controls promotes or verifies free-correlation recovery. The
frozen v2 plan and 525-unit roster are pinned in the experimental contract;
the initial-gradient decision, bounded short-NUTS profile, and atomic
scientific-worker gates remain incomplete.
"""
module BayesianMGMFRM

export FacetData,
    FacetDesign,
    FacetSpec,
    GMFRMFit,
    MGMFRMFit,
    MFRMLogDensity,
    MFRMFit,
    MFRMPrior,
    ValidationIssue,
    ValidationReport,
    anchor_refit_plan,
    anchor_linking_summary,
    artifact_content_hash,
    benchmark_result_row,
    benchmark_summary,
    calibration_table,
    constraint_table,
    coverage_matrix,
    coverage_summary,
    compare_models,
    compare_kfold,
    cached_fit,
    calibration_plot_data,
    case_study_provenance_manifest,
    comparison_evidence_row,
    comparison_evidence_summary,
    diagnostic_map_data,
    design_identity,
    design_row_table,
    dff_report,
    domain_compilation_summary,
    evidence_metadata,
    evidence_artifact_schema_policy,
    expected_scores,
    facets_compatibility_stats,
    facets_report,
    facet_response_table,
    fair_average_summary,
    falsification_rule_summary,
    falsification_rules,
    fit,
    fit_archive_manifest,
    fit_artifact,
    fit_cache_key,
    fit_metadata,
    fit_report,
    fit_report_public,
    fit_report_dossier,
    fit_report_dossier_markdown,
    fit_report_markdown,
    fit_reproduction_manifest,
    fit_report_section,
    fit_report_sections,
    fit_report_rows,
    fit_ready_parameter_layout,
    fit_stats,
    getdesign,
    identification_declarations,
    diagnostics,
    initial_params,
    kfold,
    kfold_diagnostics,
    kfold_plan,
    kfold_plan_diagnostics,
    kfold_refit,
    kfold_refit_comparison,
    kfold_sensitivity_comparison,
    loglikelihood,
    loo,
    loo_diagnostics,
    loo_refit,
    loo_refit_comparison,
    loo_refit_plan,
    logposterior,
    logprior,
    linear_predictor_table,
    linear_predictor_values,
    local_dependence_calibration_contract,
    local_dependence_calibration_pilot_contract,
    local_dependence_calibration_pilot_preflight,
    local_dependence_calibration_row,
    local_dependence_calibration_summary,
    local_dependence_contract,
    local_dependence_simulation_grid,
    local_dependence_summary,
    model_equation,
    mcmc_diagnostics,
    model_manifest,
    model_ladder,
    model_surface_audit,
    mfrm_spec,
    parameter_block_diagnostics,
    parameter_recovery,
    parameter_recovery_plot_data,
    parameter_recovery_summary,
    pointwise_loglikelihood,
    pointwise_loglikelihood_matrix,
    posterior_predict,
    posterior_predictive_check,
    posterior_summary,
    psis_loo,
    prior_likelihood_sensitivity,
    predictive_check_summary,
    predictive_probabilities,
    predictive_residuals,
    predictive_standardized_residuals,
    predictive_variances,
    prior_predict,
    prior_predictive_check,
    q_matrix_validation,
    rater_diagnostics,
    rater_overlap,
    rating_design_audit,
    related_software_capability_matrix,
    residual_summary,
    release_gate_check,
    release_scope_summary,
    load_fit_cache,
    load_fit_report_dossier,
    load_fit_report,
    load_fit_report_bundle,
    load_fit_report_tables,
    sampler_diagnostics,
    save_fit_cache,
    save_fit_report_dossier,
    save_fit_report_dossier_markdown,
    save_fit_report,
    save_fit_report_bundle,
    save_fit_report_markdown,
    save_fit_report_tables,
    sensitivity_comparison,
    sensitivity_comparison_summary,
    separation_reliability_summary,
    simulation_grid,
    simulation_grid_summary,
    simulate_local_dependence,
    simulate_responses,
    stan_validation_row,
    stan_validation_summary,
    threshold_map_data,
    testlet_design_audit,
    validate_design,
    validation_suggestions,
    predictive_check_plot_data,
    wright_map_data,
    waic,
    waic_diagnostics

include("evidence_metadata.jl")
include("facet_workflow.jl")
include("model_contract.jl")
include("testlet_design_audit.jl")
include("bayesian_fit.jl")
include("mgmfrm_free_correlation_candidate.jl")
include("mgmfrm_free_correlation_recovery.jl")
include("mgmfrm_free_correlation_study.jl")
include("mgmfrm_free_correlation_resource_probe.jl")
include("mgmfrm_free_correlation_study_scoring.jl")
include("experimental.jl")
include("anchor_refit_plan.jl")
include("local_dependence.jl")
include("local_dependence_known_truth_dgp.jl")
include("local_dependence_simulation.jl")
include("local_dependence_calibration.jl")
include("local_dependence_calibration_pilot.jl")

# Scalar validation target used by the analytic-gradient test suite.
include("scalar_validation_logp.jl")

end
