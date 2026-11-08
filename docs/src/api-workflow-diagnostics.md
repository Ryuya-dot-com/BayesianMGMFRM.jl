# Workflow and Diagnostics API

!!! note "Unreleased documentation preview — 13 October 2026"
    This manual includes unreleased interfaces and examples. It is not the
    documentation of an installed release. Model support and scientific
    acceptance remain as stated on each page.

```@docs
diagnostics
sampler_diagnostics
mcmc_diagnostics
parameter_block_diagnostics
posterior_mcse
posterior_summary
BayesianMGMFRM.posterior_contrast
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
qualify
facet_summary
category_summary
contrast
event_probabilities
reliability
ranking
classification
criteria
predictive_check
```

The [Saved-fit Reporting API](api-saved-reporting.md) groups the common
reliability, agreement and category reports.

## [Compare observed and expected ratings](@id observed-expected-calibration)

Use `calibration_table` to ask whether groups of observed rating rows have
averages close to their model expectations. Its fitted-result methods accept
`MFRMFit`, `GMFRMFit` and `MGMFRMFit`; the experimental normalized and correlated
result types have separate reporting contracts. A model family name alone does
not establish that this function accepts its result type.

For an existing supported fit, use all its retained draws without refitting or
generating replicated outcomes:

```julia
rows = calibration_table(fit; target=:expected_score, bins=10, interval=0.9)
points = calibration_plot_data(rows)
[(; bin=p.bin, ratings=p.n_observations, observed=p.observed_mean,
    expected=p.predicted_mean, lower=p.predicted_lower,
    upper=p.predicted_upper, probability=p.interval_probability) for p in points]
```

Group rows by `target` and `category` before drawing multiple series. Put
`predicted_mean` on the horizontal axis and `observed_mean` on the vertical axis,
with the equality line as a reference. Display `n_observations` in the table or
point labels; it counts rating rows, not unique people. `n_draws` is the number
of selected parameter draws and is not an effective sample size.

Each bin is formed from posterior mean predictions, separately for each target.
The observed and expected means use the same rows with equal rating weight,
retaining their item and rater conditions. These are not ability-conditioned
response curves, a standardized reference panel, or independent held-out
predictions. Tied predictions can be split across bins to balance row counts;
the reported prediction ranges may therefore touch or overlap.

The horizontal interval is an equal-tail posterior interval for the bin's
**mean expected value**. Its probabilities travel with the plot data. It is
different from the range of row predictions (`predicted_bin_lower/upper`), a
prediction interval for replicated ratings, and Monte Carlo uncertainty.
`:outside_interval` describes a discrepancy; it is not a calibrated significance
test or a reason to remove a person, rater or category. Sampling diagnostics and
the precision needed for the analysis must be assessed separately.

For a category-use proportion, request `target=:category_probability` and an
explicit score label with `category=...`. An ordinal high-score category is not
automatically a correct answer. For variation in replicated ratings use
`posterior_predictive_check`; that operation generates new outcomes. For
conditional category curves across more fitted-result types, use the
owner-aware `category_report` described below.

The plot-data conversion accepts older reduced rows, preserving available
values and returning `missing` for absent counts, median or interval
probabilities. Keep the complete calibration table and its fit/report provenance;
the plot rows alone do not archive the model, source environment or diagnostics.

For owner-aware category summaries across the eight common saved-fit types,
use [`BayesianMGMFRM.category_report`](@ref). Its expected-use posterior intervals
differ from the replicated-use intervals below. Optional profiles specify the
item, rater, plotted dimension and every fixed other ability. Request it through `fit_report(...; reporting=(; category=(...), ...))`
to add the distinct `category_report` section; the historical section below
keeps its original interpretation.

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
