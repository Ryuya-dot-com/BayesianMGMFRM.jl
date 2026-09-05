# Workflow and Diagnostics API

```@docs
diagnostics
sampler_diagnostics
mcmc_diagnostics
parameter_block_diagnostics
posterior_mcse
posterior_summary
BayesianMGMFRM.pointwise_loglikelihood
pointwise_loglikelihood_matrix
waic
waic_diagnostics
loo
psis_loo
loo_diagnostics
loo_refit
loo_refit_comparison
loo_refit_plan
kfold
kfold_diagnostics
kfold_plan
kfold_plan_diagnostics
kfold_refit
kfold_refit_comparison
compare_kfold
compare_models
sensitivity_comparison
sensitivity_comparison_summary
kfold_sensitivity_comparison
prior_likelihood_sensitivity
posterior_predict
posterior_predictive_check
prior_predict
prior_predictive_check
predictive_check_summary
predictive_check_plot_data
predictive_probabilities
expected_scores
predictive_variances
predictive_residuals
predictive_standardized_residuals
local_dependence_contract
local_dependence_summary
calibration_table
calibration_plot_data
wright_map_data
diagnostic_map_data
fair_average_summary
dff_report
separation_reliability_summary
rater_diagnostics
rater_homogeneity_summary
category_functioning_summary
residual_summary
fit_stats
facets_report
facets_compatibility_stats
```

For a fitted minimal MFRM/RSM/PCM model, category-use and pairwise rater
diagnostics can be requested without changing the fitted data or model:

```julia
categories = category_functioning_summary(
    fit_result;
    ndraws = 200,
    min_count = 5,
)

raters = rater_homogeneity_summary(
    fit_result;
    ndraws = 200,
    severity_rope = 0.10, # use a substantively declared margin
)
```

`categories.usage_rows` and `categories.threshold_rows` retain predictive and
step-order review flags, but never collapse categories automatically.
`raters.contrast_rows` computes paired severity differences; a positive
`severity_a - severity_b` means rater A is more severe. Coordinate rows identify
the default fixed reference, declared hard anchors, and estimated severities.
A two-fixed-coordinate contrast is an exact constant with zero uncertainty
draws, a not-applicable interval type and interval probabilities, and
deterministic sign/ROPE
probabilities. A one-fixed-coordinate contrast has posterior uncertainty only
from the estimated side. A ROPE is not assumed unless the analysis supplies
one.

[`fit_report`](@ref) includes both summaries by default for stable MFRM fits:
`category_functioning.usage_rows`, `category_functioning.threshold_rows`, and
`rater_homogeneity.contrast_rows` are available in structured, public,
Markdown, JSON, and table outputs. Category review flags become one aggregate
report warning and never cause automatic recoding. Set
`include_category_functioning = false` or
`include_rater_homogeneity = false` for an independent opt-out. Generalized
fits leave both stable-only report sections unrequested by default and return
`unsupported` if either is requested explicitly. A one-rater stable fit returns
zero contrast rows with `contrast_availability = :not_applicable_single_rater`;
the empty pair set is not labelled connected evidence of homogeneity. Empty row
fields survive public JSON, table, and bundle round trips. Markdown omits empty
previews unless `include_empty = true` is requested.

For PCM reports using an explicitly declared category scale, unobserved
endpoints remain present as skipped category-use rows and do not reduce the
item-specific threshold-row universe.
