"""
    BayesianMGMFRM

Tools for preparing long-format many-facet Rasch rating data.

The current public API is intentionally limited to deterministic indexing,
pre-fit data validation, MFRM/GMFRM/MGMFRM specification manifests, minimal
RSM/PCM design scaffolding, and initial Bayesian fitting, predictive-check, and
WAIC / raw importance-sampling LOO paths for small validation examples. The
minimal MFRM/RSM/PCM design can be fit with a random-walk example backend, an
    initial AdvancedHMC/NUTS backend, or a Turing/NUTS backend. Guarded
    experimental generalized paths are available through
    `fit(spec; experimental = true)` for the scalar rater-discrimination GMFRM
    candidate and the fixed-Q two-dimensional confirmatory MGMFRM candidate.
    Broader generalized discrimination likelihoods, group/DFF model effects, and
    exploratory MGMFRM fitting remain planned work.
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
    comparison_evidence_row,
    comparison_evidence_summary,
    design_row_table,
    dff_report,
    domain_compilation_summary,
    evidence_metadata,
    expected_scores,
    fair_average_summary,
    falsification_rule_summary,
    falsification_rules,
    fit,
    fit_archive_manifest,
    fit_artifact,
    fit_cache_key,
    fit_metadata,
    fit_report,
    fit_report_markdown,
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
    loglikelihood,
    loo,
    loo_diagnostics,
    logposterior,
    logprior,
    linear_predictor_table,
    linear_predictor_values,
    model_equation,
    mcmc_diagnostics,
    model_manifest,
    model_ladder,
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
    predictive_check_summary,
    predictive_probabilities,
    predictive_residuals,
    predictive_variances,
    prior_predict,
    prior_predictive_check,
    rater_diagnostics,
    rater_overlap,
    residual_summary,
    load_fit_cache,
    load_fit_report,
    load_fit_report_bundle,
    sampler_diagnostics,
    save_fit_cache,
    save_fit_report,
    save_fit_report_bundle,
    save_fit_report_markdown,
    save_fit_report_tables,
    sensitivity_comparison,
    sensitivity_comparison_summary,
    separation_reliability_summary,
    simulation_grid,
    simulation_grid_summary,
    simulate_responses,
    stan_validation_row,
    stan_validation_summary,
    threshold_map_data,
    validate_design,
    validation_suggestions,
    predictive_check_plot_data,
    wright_map_data,
    waic,
    waic_diagnostics

include("evidence_metadata.jl")
include("facet_workflow.jl")
include("bayesian_fit.jl")

# Scalar validation target used by the analytic-gradient test suite.
include("scalar_validation_logp.jl")

end
