# BayesianMGMFRM.jl

`BayesianMGMFRM.jl` provides conservative Bayesian workflows for many-facet
Rasch measurement. It combines long-format rating-data validation, identified
model construction, Bayesian fitting, diagnostics, predictive checks, and
portable reports.

## What Is Supported

The stable fitting surface covers MFRM with rating-scale or partial-credit
steps. Two generalized configurations are available only with explicit
experimental opt-in:

- a one-dimensional scalar rater-consistency GMFRM;
- a multidimensional fixed-Q confirmatory MGMFRM.

Broader discrimination structures, exploratory loadings, free latent
correlations, and fitted DFF effects are not supported. See
[Scope and Releases](scope.md) for the exact boundary and
[Experimental Generalized Models](experimental.md) for the quarantined API.

## Recommended Path

1. Build long-format ratings with [`FacetData`](@ref).
2. Run [`validate_design`](@ref) and inspect coverage, connectedness, category
   use, optional groups, and anchors.
3. Create an [`mfrm_spec`](@ref), then inspect [`getdesign`](@ref),
   [`constraint_table`](@ref), and [`model_manifest`](@ref).
4. Use [`prior_predictive_check`](@ref) before fitting.
5. Fit the supported design with [`fit`](@ref).
6. Review [`sampler_diagnostics`](@ref), [`mcmc_diagnostics`](@ref),
   [`parameter_block_diagnostics`](@ref), and [`diagnostics`](@ref).
7. Inspect posterior, predictive, calibration, residual, and sensitivity rows.
8. Export `fit_report(fit; view = :public)` or
   [`fit_report_public`](@ref) for reader-facing structured data, or use
   [`fit_report_markdown`](@ref) for Markdown.

## Documentation

- [Data Validation](data-validation.md) explains the input contract and design
  checks.
- [Model Equations](model-equations.md) records the mathematical and source
  contracts.
- [Bayesian Workflow](bayesian-workflow.md) presents the analysis sequence and
  interpretation checks.
- [Bayesian Fitting](fitting.md) covers backends, experimental restrictions,
  diagnostics, and reports.
- [Experimental Generalized Models](experimental.md) documents the provisional
  namespace and its promotion boundary.
- [Examples](examples.md) points to runnable scripts.
- [Migrating from FACETS and ACER ConQuest](migration-facets-conquest.md)
  maps the overlapping RSM/PCM models, sign and identification conventions,
  estimator differences, and the staged anchor-refitting policy.
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
