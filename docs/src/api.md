# API

## Public API

```@docs
BayesianMGMFRM
FacetData
ValidationIssue
ValidationReport
FacetSpec
FacetDesign
MFRMPrior
MFRMFit
coverage_matrix
coverage_summary
validate_design
mfrm_spec
getdesign
fit
logposterior
BayesianMGMFRM.pointwise_loglikelihood
pointwise_loglikelihood_matrix
posterior_predict
posterior_predictive_check
posterior_summary
rater_overlap
threshold_map_data
evidence_metadata
```

## Internal Validation Targets

The scalar faithful log-density helpers are used by the test suite while the
full GMFRM/MGMFRM compiler is being built. They are not fitting APIs. The scalar
target is a narrow `D = 1`, `I = 1` Uto-2021-style algebraic validation fixture;
its rater-consistency prior convention evaluates a lognormal density on
constrained transformed `alpha_r` values.
