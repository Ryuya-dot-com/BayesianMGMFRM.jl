"""
    BayesianMGMFRM

Tools for preparing long-format many-facet Rasch rating data.

The current public API is intentionally limited to deterministic indexing,
pre-fit data validation, and minimal RSM/PCM design scaffolding. Bayesian
fitting, generalized discrimination terms, group/DFF effects, and
Multidimensional Generalized Many-Facet Rasch Model (MGMFRM) terms are planned
work and are not exposed as public fitting APIs yet.
"""
module BayesianMGMFRM

export FacetData,
    FacetDesign,
    FacetSpec,
    ValidationIssue,
    ValidationReport,
    coverage_matrix,
    coverage_summary,
    evidence_metadata,
    getdesign,
    mfrm_spec,
    pointwise_loglikelihood,
    rater_overlap,
    threshold_map_data,
    validate_design

include("evidence_metadata.jl")
include("facet_workflow.jl")

# Validation target used by the analytic-gradient test suite.
# Public model-fitting APIs will be introduced with the data/spec layer.
include("faithful_fastlogp.jl")

end
