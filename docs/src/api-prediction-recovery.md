# Prediction and Recovery Candidate API

!!! note "Unreleased documentation preview — 13 October 2026"
    This manual includes unreleased interfaces and examples. It is not the
    documentation of an installed release. Model support and scientific
    acceptance remain as stated on each page.

These qualified functions are available in this isolated candidate, which has
not been merged or released. Use `BayesianMGMFRM.` when calling them. They consume
existing data specifications, fit caches or evaluation records; they do not
automatically fit candidate models or choose a winning model or design.

The [saved prediction and recovery guide](common_prediction_comparison.md)
connects these operations to saved-fit examples, model/dimension/Q choices,
diagnostic warnings, failure accounting and interpretation limits.
Existing exported comparison and vector-truth recovery APIs retain their meanings.

## Existing-row prediction and comparison

These methods evaluate fitted levels. WAIC and raw importance-sampling LOO are
training-data approximations; they are not heldout K-fold scores, reference-validated
PSIS or new-level prediction. See each function's supported inputs and uncertainty limits.

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

```@docs
BayesianMGMFRM.recovery_quantities
BayesianMGMFRM.recovery_evaluation
BayesianMGMFRM.recovery_replications
```
