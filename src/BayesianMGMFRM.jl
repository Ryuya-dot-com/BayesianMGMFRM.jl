"""
    BayesianMGMFRM

Tools for preparing long-format many-facet Rasch rating data.

The current public API is intentionally limited to deterministic indexing,
pre-fit data validation, MFRM/GMFRM/MGMFRM specification manifests, minimal
RSM/PCM design scaffolding, and initial Bayesian fitting, predictive-check, and
WAIC / raw importance-sampling LOO paths for small validation examples. The
minimal MFRM/RSM/PCM design can be fit with a random-walk example backend, an
initial AdvancedHMC/NUTS backend, or a Turing/NUTS backend. A guarded
experimental scalar GMFRM rater-discrimination path is available through
`fit(spec; experimental = true)`.
Broader generalized discrimination likelihoods, group/DFF model effects, and
Multidimensional Generalized Many-Facet Rasch Model (MGMFRM) fitting are planned
work and are not exposed as public fitting APIs yet.
"""
module BayesianMGMFRM

export FacetData,
    FacetDesign,
    FacetSpec,
    GMFRMFit,
    MFRMLogDensity,
    MFRMFit,
    MFRMPrior,
    ValidationIssue,
    ValidationReport,
    anchor_linking_summary,
    artifact_content_hash,
    calibration_table,
    constraint_table,
    coverage_matrix,
    coverage_summary,
    compare_models,
    compare_kfold,
    cached_fit,
    calibration_plot_data,
    design_row_table,
    dff_report,
    domain_compilation_summary,
    evidence_metadata,
    expected_scores,
    fair_average_summary,
    fit,
    fit_archive_manifest,
    fit_artifact,
    fit_cache_key,
    fit_metadata,
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
    sampler_diagnostics,
    save_fit_cache,
    sensitivity_comparison,
    sensitivity_comparison_summary,
    separation_reliability_summary,
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
