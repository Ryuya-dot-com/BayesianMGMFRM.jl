# Prediction and Recovery API

!!! note "Unreleased documentation preview — 13 October 2026"
    This manual includes unreleased interfaces and examples. It is not the
    documentation of an installed release. Model support and scientific
    acceptance remain as stated on each page.

These functions operate on existing data specifications, saved fits, or
evaluation records and are not yet part of a registered release. Use
`BayesianMGMFRM.` when calling unexported helpers. They do not automatically fit
candidate models or choose a winning model or design.

The [saved prediction and recovery guide](common_prediction_comparison.md)
connects these operations to saved-fit examples, model/dimension/Q choices,
diagnostic warnings, failure accounting and interpretation limits.
Existing exported comparison and vector-truth recovery APIs retain their meanings.

## Existing-row prediction and comparison

These methods evaluate fitted levels. WAIC and raw importance-sampling LOO are
training-data approximations. Standard PSIS is a separate, chain-aware option;
the historical Hill approximation remains explicit. None is a refitted K-fold
score or new-level prediction. See each function's supported inputs and uncertainty limits.

```@docs
BayesianMGMFRM.prediction_observations
BayesianMGMFRM.observation_alignment
BayesianMGMFRM.prediction_criteria
BayesianMGMFRM.compare_predictions
```

## Known-level K-fold preparation and scoring

Prepare the same declared split for each candidate model, then supply the matching
saved training fits. The complete planned fold roster determines missing/failed
status. Aggregation optionally estimates first-order MCMC error (`mcse=:delta`)
conditional on fixed data/splits, with explicit independence assumptions for
combining fold/model errors. It does not estimate data-sampling K-fold SE or
execute refits. See the [worked numerical-error guide](common_prediction_comparison.md#Numerical-error-of-the-K-fold-comparison).

```@docs
BayesianMGMFRM.prediction_refit_plan
BayesianMGMFRM.prediction_fold_observations
BayesianMGMFRM.prediction_kfold
BayesianMGMFRM.compare_kfold_predictions
```

## Named truth and independent-dataset summaries

Truths must use the model's native scale and identifying constraints. Structural
constants do not count as estimated coverage. Summaries of fixed-truth replications
require the full dataset roster and a documented independence declaration before
reporting replication SE; this neither verifies generation nor performs SBC.
Optional `mcse_limits` in `recovery_replications` adds a separate summary requiring
small mean and central-endpoint MCSE while retaining global warnings and the full
planned denominator. See [computational versus measurement precision](common_prediction_comparison.md#Require-small-Monte-Carlo-error)
for a worked call and interpretation. No numerical tolerance is chosen for you.
The [saved-width example](common_prediction_comparison.md#Compare-interval-width-with-your-research-target)
then compares each dataset's interval width with a user-supplied measurement
target, keeping numerical exclusions and missing outcomes visible. It is an
example function loaded with `include`, not another package API or design-selection rule.

```@docs
BayesianMGMFRM.recovery_quantities
BayesianMGMFRM.recovery_evaluation
BayesianMGMFRM.recovery_replications
BayesianMGMFRM.design_precision_plot_data
BayesianMGMFRM.plot_design_precision
```
