# Bayesian Workflow

The current package exposes the early pieces needed for a Bayesian many-facet
Rasch workflow, including initial AdvancedHMC/NUTS and Turing/NUTS paths for
the minimal MFRM/RSM/PCM design. A guarded scalar GMFRM experimental path is
also available for the one-dimensional rater-discrimination promotion candidate through
`fit(spec; experimental = true)`. Broader GMFRM/MGMFRM fitting remains planned
work, but specified-only GMFRM/MGMFRM configs can already be recorded in
manifests, constraint tables, and identification declarations.
`getdesign(spec; preview = true)` can also compile a non-fit-ready parameter
blueprint for those configurations, so future Bayesian checks can be added
without changing the data layer.

## Recommended Sequence

1. Build long-format rating data with [`FacetData`](@ref).
2. Run pre-fit checks with [`validate_design`](@ref), [`coverage_summary`](@ref),
   and [`coverage_matrix`](@ref).
3. Inspect supported and specified-only model families with [`model_ladder`](@ref).
4. Declare a minimal MFRM/RSM/PCM specification with [`mfrm_spec`](@ref), then
   inspect the source-traced mathematical contract with [`model_equation`](@ref),
   constraints with [`constraint_table`](@ref), normalized identification
   declarations with [`identification_declarations`](@ref), and the identified
   parameter design with [`getdesign`](@ref). Use
   [`fit_ready_parameter_layout`](@ref) when sampler-coordinate and
   constrained-coordinate block ranges are needed.
   For specified-only GMFRM/MGMFRM review, use `getdesign(spec; preview = true)`,
   `design_row_table(spec; preview = true)`, and
   `linear_predictor_table(spec; preview = true)`. Use
   `fit(spec; experimental = true)` only for the guarded scalar GMFRM
   rater-discrimination candidate.
5. Choose weakly informative scales with [`MFRMPrior`](@ref).
6. For external sampler or AD experiments, build an [`MFRMLogDensity`](@ref)
   target and a deterministic start with [`initial_params`](@ref); use
   [`linear_predictor_values`](@ref), [`loglikelihood`](@ref),
   [`logprior`](@ref), and [`logposterior`](@ref) to inspect the category-score
   and scalar target components.
7. Run [`prior_predictive_check`](@ref) and summarize it with
   [`predictive_check_summary`](@ref) before fitting.
8. Fit the current minimal model with [`fit`](@ref), or use
   [`cached_fit`](@ref) with a stable `cache_path` and integer `seed` to avoid
   recomputation when [`fit_cache_key`](@ref) still matches. Use
   `backend = :advancedhmc` or `backend = :turing` for NUTS paths and
   `chains >= 2` when convergence diagnostics are needed. The default gradient
   path is `ad_backend = :ForwardDiff`; `:ReverseDiff` can be selected for the
   direct AdvancedHMC backend when that AD package is available, and
   `:analytic` is reserved for AdvancedHMC targets that expose a native
   `LogDensityProblems.logdensity_and_gradient` method. The Turing backend
   currently uses ForwardDiff only.
9. Record fit-level metadata with [`fit_metadata`](@ref).
10. Record data/spec/design/fit provenance with [`model_manifest`](@ref), then
   create a cached-fit reproducibility artifact with [`fit_artifact`](@ref).
11. Inspect the integrated diagnostic surface with [`diagnostics`](@ref), or use
   [`sampler_diagnostics`](@ref), [`mcmc_diagnostics`](@ref), and
   [`parameter_block_diagnostics`](@ref) separately when lower-level rows are
   needed.
12. Inspect parameters with [`posterior_summary`](@ref), then inspect
   observation-level predictions with [`predictive_probabilities`](@ref),
   [`expected_scores`](@ref), [`predictive_variances`](@ref), and
   [`predictive_residuals`](@ref).
13. Run [`posterior_predictive_check`](@ref), summarize it with
   [`predictive_check_summary`](@ref), and inspect binned calibration with
   [`calibration_table`](@ref).
14. Inspect posterior residual summaries with [`residual_summary`](@ref), and
   facet-level infit/outfit with [`fit_stats`](@ref).
15. Compare same-observation candidate models with [`waic`](@ref), raw
    importance-sampling [`loo`](@ref), and [`compare_models`](@ref); inspect
    influential WAIC rows with [`waic_diagnostics`](@ref) and unstable LOO rows
    with [`loo_diagnostics`](@ref).

## Calibration

[`calibration_table`](@ref) is the closest current analogue to a binned
Bayesian calibration check. By default it bins observations by posterior
expected score and compares the observed mean score in each bin with posterior
predicted means. For binary or highest-category reporting, use
`target = :category_probability`; use `category = :all` for one block per
ordinal score category, or `target = :all` for expected-score rows plus all
category-probability rows.

```julia
calibration_table(fit_result; bins = 5)
calibration_table(fit_result; target = :category_probability, bins = 5)
calibration_table(fit_result; target = :category_probability, category = 2, bins = 5)
calibration_table(fit_result; target = :category_probability, category = :all, bins = 5)
calibration_table(fit_result; target = :all, bins = 5)
```

## Current Limits

The current `backend = :julia` sampler is a random-walk Metropolis path for
small validation examples. `backend = :advancedhmc` provides a direct
AdvancedHMC/NUTS path for the minimal design using [`MFRMLogDensity`](@ref),
and `backend = :turing` wraps the same target in a Turing model with a flat
vector parameter and `Turing.@addlogprob!`. The direct AdvancedHMC path routes
through a shared gradient target adapter, with target-provided analytic
gradients used when explicitly selected and otherwise AD-backed gradients
selected by `ad_backend`; the Turing path currently uses ForwardDiff.
[`sampler_diagnostics`](@ref) reports chain-level acceptance rates,
log-posterior summaries, divergent-transition counts, max-tree-depth hits, and
E-BFMI when available, and
[`mcmc_diagnostics`](@ref) provides classical split R-hat and
autocorrelation-based ESS when at least two chains are available.
[`parameter_block_diagnostics`](@ref) aggregates those parameter rows by
identified design block.
[`diagnostics`](@ref) combines those rows into a single pass/fail summary and
includes HMC/NUTS fields when the selected backend produces them. The package
exposes raw importance-sampling [`loo`](@ref) and [`loo_diagnostics`](@ref)
with Hill-estimated Pareto-k screening plus supplied heldout-refit
[`kfold`](@ref) and [`compare_kfold`](@ref) summaries, but it does not yet
perform PSIS smoothing, exact LOO refits, or refit-managed cross-validation.
It also does not yet expose grouped cross-validation by person/item,
power-scaling prior sensitivity, covariate terms, random slopes, generalized
discrimination likelihoods, or multidimensional MGMFRM fitting. Specified-only
GMFRM/MGMFRM rows in [`constraint_table`](@ref) and
[`identification_declarations`](@ref) are provenance and design-review data,
not fitted likelihood terms.

Until those pieces are added, treat [`waic`](@ref), [`waic_diagnostics`](@ref),
[`loo`](@ref), [`loo_diagnostics`](@ref), [`kfold`](@ref),
[`compare_models`](@ref), [`compare_kfold`](@ref),
[`posterior_predictive_check`](@ref), [`calibration_table`](@ref), and
[`fit_stats`](@ref) as small-model workflow scaffolding rather than a complete
production Bayesian model-comparison stack. The `relative_weight` returned by
[`compare_models`](@ref) or [`compare_kfold`](@ref) is an Akaike-style weight
for a declared prediction target, not a posterior model probability.
`compare_models` checks the comparison contract up front: observation data and
row order, ordinal category levels, latent dimensionality, and any fixed
Q-matrix must match, and the returned rows carry those contract fields for
reporting. `compare_kfold` similarly requires the same heldout observation
order and fold assignment order.
[`sensitivity_comparison`](@ref) uses the same scoring path and adds declared
axis values plus baseline-relative differences for fit-supported threshold,
prior, backend, sampler, or custom externally labelled regimes.
