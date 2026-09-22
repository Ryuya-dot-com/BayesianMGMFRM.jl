# BayesianMGMFRM.jl

`BayesianMGMFRM.jl` provides conservative Bayesian workflows for many-facet
Rasch measurement. It combines long-format rating-data validation, identified
model construction, Bayesian fitting, diagnostics, predictive checks,
portable reports, and optional figures directly from saved or newly fitted
models. Start with the [short runnable examples](examples.md).

## What Is Supported

The stable fitting surface covers MFRM with rating-scale or partial-credit
steps. Multidimensional configurations are available only with explicit
experimental opt-in:

- a fixed-coefficient multidimensional MFRM with independent abilities;
- a two-dimensional between-item MFRM with estimated population correlation;
- a one-dimensional scalar GMFRM with item discrimination and rater consistency;
- a multidimensional fixed-Q confirmatory MGMFRM with independent abilities;
- an explicit two-dimensional correlated MGMFRM, currently covering fitting,
  summaries, diagnostics, MCSE, prior/conditional posterior prediction, manual
  caches and report/figure bundles. This workflow remains experimental.

Broader discrimination structures, exploratory loadings, higher-dimensional
correlation estimation, and fitted DFF effects are not supported. See
[Scope and Releases](scope.md) for the exact boundary and
[Experimental Models](experimental.md) for the limited API.

## Recommended Path

1. Build long-format ratings with [`FacetData`](@ref).
2. Run [`validate_design`](@ref) and inspect coverage, connectedness, category
   use, optional groups, and anchors.
3. Create an [`mfrm_spec`](@ref) and review its constraints.
   [`getdesign`](@ref) provides optional parameter inspection.
4. Use [`prior_predictive_check`](@ref) before fitting.
5. Call `fit(spec)` for the supported stable model.
6. Review [`sampler_diagnostics`](@ref), [`mcmc_diagnostics`](@ref),
   [`parameter_block_diagnostics`](@ref), and [`diagnostics`](@ref).
7. Inspect estimand-specific [`posterior_mcse`](@ref), posterior, predictive,
   calibration, residual, and sensitivity results. The [plotting
   guide](fitting.md#Posterior-interval-figures) shows figures from a fit.
8. Export `fit_report(fit; view = :public)` or
   [`fit_report_public`](@ref) for reader-facing structured data, or use
   [`fit_report_markdown`](@ref) for Markdown. Check report completeness with
   [`fit_report_health`](@ref) or set `require_complete = true`.

## Documentation

- [Data Validation](data-validation.md) explains the input contract and design
  checks.
- [Model Equations](model-equations.md) records the mathematical and source
  contracts.
- [Bayesian Workflow](bayesian-workflow.md) presents the analysis sequence and
  interpretation checks.
- [Bayesian Fitting](fitting.md) covers backends, experimental restrictions,
  diagnostics, and reports.
- [Experimental Models](experimental.md) documents the provisional
  namespace and its stability boundary.
- [Examples](examples.md) points to runnable scripts.
- [Migrating from FACETS and ACER ConQuest](migration-facets-conquest.md)
  maps the overlapping RSM/PCM models, sign and identification conventions,
  estimator differences, and supported individual hard anchors.
- [Scope and Releases](scope.md) states supported and unsupported surfaces.
- [API](api.md) lists the public functions by workflow.

```@contents
Pages = [
    "data-validation.md",
    "model-equations.md",
    "bayesian-workflow.md",
    "fitting.md",
    "experimental.md",
    "examples.md",
    "migration-facets-conquest.md",
    "scope.md",
    "api.md",
    "api-data-design.md",
    "api-fitting-artifacts.md",
    "api-workflow-diagnostics.md",
    "api-validation-evidence.md",
]
Depth = 2
```
