# Experimental Model API

!!! note "Unreleased documentation preview — 13 October 2026"
    This manual includes unreleased interfaces and examples. It is not the
    documentation of an installed release. Model support and scientific
    acceptance remain as stated on each page.

These entries describe the callable experimental model types and functions.
Their availability does not establish scientific support beyond the documented
model and prior configurations. Read the [experimental model guide](experimental.md)
for equations, identifying constraints, prior scales, fitting examples and limitations.
For saved prediction comparison and named recovery, use the separate
[prediction and recovery candidate reference](api-prediction-recovery.md).

```@docs
BayesianMGMFRM.Experimental
BayesianMGMFRM.Experimental.GMFRMFit
BayesianMGMFRM.Experimental.MGMFRMFit
BayesianMGMFRM.Experimental.MultidimensionalMFRMFit
BayesianMGMFRM.Experimental.CorrelatedMFRMSpec
BayesianMGMFRM.Experimental.CorrelatedMFRMFit
BayesianMGMFRM.Experimental.CorrelatedMGMFRMSpec
BayesianMGMFRM.Experimental.CorrelatedMGMFRMFit
BayesianMGMFRM.Experimental.ExchangeablePrior
BayesianMGMFRM.Experimental.ExchangeableMFRMFit
BayesianMGMFRM.Experimental.correlated
BayesianMGMFRM.Experimental.joint_rating_spec
BayesianMGMFRM.Experimental.slope_restriction
BayesianMGMFRM.Experimental.GeneralizedPrior
BayesianMGMFRM.Experimental.NormalizedMGMFRMPrior
BayesianMGMFRM.Experimental.MeanProfilePrior
BayesianMGMFRM.Experimental.NormalizedMGMFRMFit
BayesianMGMFRM.Experimental.surface_contract
BayesianMGMFRM.Experimental.free_latent_correlation_2d_contract
BayesianMGMFRM.Experimental.preview
BayesianMGMFRM.Experimental.prior_predict
BayesianMGMFRM.Experimental.prior_predictive_check
BayesianMGMFRM.Experimental.free_latent_correlation_2d_candidate
BayesianMGMFRM.Experimental.free_latent_correlation_2d_state
BayesianMGMFRM.Experimental.free_latent_correlation_2d_diagnostics
BayesianMGMFRM.Experimental.fit
BayesianMGMFRM.Experimental.fit_cache_key
BayesianMGMFRM.Experimental.cached_fit
```

## Joint ratings

Local candidate; see the [workflow guide](joint-ratings.md).

```@docs
BayesianMGMFRM.Experimental.JointRatings
BayesianMGMFRM.Experimental.JointRatings.contract
BayesianMGMFRM.Experimental.JointRatings.model
BayesianMGMFRM.Experimental.JointRatings.fit
BayesianMGMFRM.Experimental.JointRatings.verified_stan
BayesianMGMFRM.Experimental.JointRatings.load_result
BayesianMGMFRM.Experimental.JointRatings.save_result
BayesianMGMFRM.Experimental.JointRatings.report
BayesianMGMFRM.Experimental.JointRatings.contrast
BayesianMGMFRM.Experimental.JointRatings.predict
BayesianMGMFRM.Experimental.JointRatings.score
BayesianMGMFRM.Experimental.JointRatings.save_report
```

## Recovery planning

See [Plan a rating study](design-planning.md) for score-free inputs, actual-score
binding, saved-fit review and complete-outcome accounting.

```@docs
BayesianMGMFRM.Experimental.RecoveryPlanning
BayesianMGMFRM.Experimental.RecoveryPlanning.contract
BayesianMGMFRM.Experimental.RecoveryPlanning.prepare
BayesianMGMFRM.Experimental.RecoveryPlanning.prepare_sbc
BayesianMGMFRM.Experimental.RecoveryPlanning.prior_input
BayesianMGMFRM.Experimental.RecoveryPlanning.bind_prior_draw
BayesianMGMFRM.Experimental.RecoveryPlanning.generator_input
BayesianMGMFRM.Experimental.RecoveryPlanning.bind_observations
BayesianMGMFRM.Experimental.RecoveryPlanning.observation_table
BayesianMGMFRM.Experimental.RecoveryPlanning.bind_data
BayesianMGMFRM.Experimental.RecoveryPlanning.review_fit
BayesianMGMFRM.Experimental.RecoveryPlanning.summarize_recovery
BayesianMGMFRM.Experimental.RecoveryPlanning.review_sbc_fit
BayesianMGMFRM.Experimental.RecoveryPlanning.summarize_sbc
BayesianMGMFRM.Experimental.RecoveryPlanning.ledger
BayesianMGMFRM.Experimental.RecoveryPlanning.record_stage
BayesianMGMFRM.Experimental.RecoveryPlanning.relocate_ledger
BayesianMGMFRM.Experimental.RecoveryPlanning.review
```

## Rater drift fitting and reports

`BayesianMGMFRM.Experimental.RaterDrift` provides regular-grid input,
fitting, original-environment native restoration, computed reports and descriptive
static/RW1 comparison. See [Rater Drift: Fitting, Static Comparison and Saved Results](rater-drift.md)
for the full API reference and its fitting/interpretation limits.

## Three-outcome saved results

Use [input inspection](data-validation.md#three-outcome-input) to check a labelled
9/9/2 no-state input before analysis. The [fitting guide](fitting.md#three-outcome-fitting)
connects an explicit reference prior, plan, four-chain fit and native restoration.

See [Read a saved three-outcome analysis](api-saved-reporting.md#three-outcome-saved-reports)
for the computed-report boundary, conditions and warning-preserving workflow.

```@docs
BayesianMGMFRM.Experimental.ThreeIndicator
BayesianMGMFRM.Experimental.ThreeIndicator.contract
BayesianMGMFRM.Experimental.ThreeIndicator.inspect_input
BayesianMGMFRM.Experimental.ThreeIndicator.prepare
BayesianMGMFRM.Experimental.ThreeIndicator.fit
BayesianMGMFRM.Experimental.ThreeIndicator.load_fit
BayesianMGMFRM.Experimental.ThreeIndicator.summarize
BayesianMGMFRM.Experimental.ThreeIndicator.load_report
BayesianMGMFRM.Experimental.ThreeIndicator.report
BayesianMGMFRM.Experimental.ThreeIndicator.save_report
```

## Concurrent three-outcome study

See [the two-study input, mathematics, fitting and probability-contrast guide](concurrent-three-outcome.md).

```@docs
BayesianMGMFRM.Experimental.ThreeIndicator.ConcurrentPrior
```

## Observed-group rater severity

See [the model, input and interpretation guide](rater-group-effects.md).

```@docs
BayesianMGMFRM.Experimental.RaterGroupEffects.Prior
BayesianMGMFRM.Experimental.RaterGroupEffects.model
BayesianMGMFRM.Experimental.RaterGroupEffects.design
BayesianMGMFRM.Experimental.RaterGroupEffects.contract
BayesianMGMFRM.Experimental.RaterGroupEffects.target_identity
BayesianMGMFRM.Experimental.RaterGroupEffects.fit
BayesianMGMFRM.Experimental.RaterGroupEffects.report
BayesianMGMFRM.Experimental.RaterGroupEffects.contrast
BayesianMGMFRM.Experimental.RaterGroupEffects.category_report
BayesianMGMFRM.Experimental.RaterGroupEffects.category_predictive_check
BayesianMGMFRM.Experimental.RaterGroupEffects.save_result
BayesianMGMFRM.Experimental.RaterGroupEffects.load_result
BayesianMGMFRM.Experimental.RaterGroupEffects.save_report
```

See the [Correlated3D API](correlated-3d.md#API) for the separate three-trait model, generator, fitter, named reports and source-bound persistence.

