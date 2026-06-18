# BayesianMGMFRM.jl

`BayesianMGMFRM.jl` is an early Julia package scaffold for many-facet Rasch
measurement workflows.

The current public slice focuses on:

- long-format rating data via [`FacetData`](@ref);
- pre-fit design validation via [`validate_design`](@ref);
- minimal MFRM specification and design inspection via [`mfrm_spec`](@ref) and
  [`getdesign`](@ref);
- initial Bayesian fitting for the minimal identified design via [`fit`](@ref),
  [`MFRMPrior`](@ref), and [`posterior_summary`](@ref);
- prior and posterior predictive replication via [`prior_predict`](@ref),
  [`prior_predictive_check`](@ref), [`posterior_predict`](@ref), and
  [`posterior_predictive_check`](@ref);
- report-ready predictive-check summaries via [`predictive_check_summary`](@ref);
- observation-level predictive probabilities, expected scores, variances, and
  residuals via [`predictive_probabilities`](@ref), [`expected_scores`](@ref),
  [`predictive_variances`](@ref), and [`predictive_residuals`](@ref);
- posterior infit/outfit summaries by facet level via [`fit_stats`](@ref);
- WAIC model-comparison summaries via [`waic`](@ref) and
  [`compare_models`](@ref);
- fit-independent reporting data via [`coverage_summary`](@ref),
  [`coverage_matrix`](@ref), [`rater_overlap`](@ref), and
  [`threshold_map_data`](@ref);
- test-suite validation against Julia and BridgeStan scalar fixtures.

Production HMC/NUTS sampling, PSIS-LOO, generalized discrimination terms,
group/DFF model terms, and Multidimensional Generalized Many-Facet Rasch Model
(MGMFRM) fitting APIs are planned work and are not exposed yet.

```@contents
Pages = ["data-validation.md", "fitting.md", "api.md"]
Depth = 2
```
