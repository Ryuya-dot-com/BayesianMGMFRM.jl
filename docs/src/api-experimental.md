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
BayesianMGMFRM.Experimental.slope_restriction
BayesianMGMFRM.Experimental.GeneralizedPrior
BayesianMGMFRM.Experimental.NormalizedMGMFRMPrior
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
