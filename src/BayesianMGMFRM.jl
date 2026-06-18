"""
    BayesianMGMFRM

Tools for preparing long-format many-facet Rasch rating data.

The current public API is intentionally limited to deterministic indexing,
pre-fit data validation, minimal RSM/PCM design scaffolding, and an initial
Bayesian fitting and predictive-check path for small validation examples.
Production HMC/NUTS, generalized discrimination terms, group/DFF effects, and
Multidimensional Generalized Many-Facet Rasch Model (MGMFRM) terms are planned
work and are not exposed as public fitting APIs yet.
"""
module BayesianMGMFRM

export FacetData,
    FacetDesign,
    FacetSpec,
    MFRMFit,
    MFRMPrior,
    ValidationIssue,
    ValidationReport,
    coverage_matrix,
    coverage_summary,
    evidence_metadata,
    fit,
    getdesign,
    logposterior,
    mfrm_spec,
    pointwise_loglikelihood,
    pointwise_loglikelihood_matrix,
    posterior_predict,
    posterior_predictive_check,
    posterior_summary,
    prior_predict,
    prior_predictive_check,
    rater_overlap,
    threshold_map_data,
    validate_design

include("evidence_metadata.jl")
include("facet_workflow.jl")
include("bayesian_fit.jl")

# Validation target used by the analytic-gradient test suite.
# Public model-fitting APIs will be introduced with the data/spec layer.
include("faithful_fastlogp.jl")

end
