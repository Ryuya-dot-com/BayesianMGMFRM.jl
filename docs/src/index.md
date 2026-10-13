# BayesianMGMFRM.jl

!!! note "Unreleased documentation preview — 13 October 2026"
    This manual includes unreleased interfaces and examples. It is not the
    documentation of an installed release. Model support and scientific
    acceptance remain as stated on each page.

This snapshot includes the saved-result comparison, sensitivity, classification,
ranking, ordinal alpha and complete-crossed ICC candidates. Candidate-only
examples require the matching development source; updating this website does not
install those interfaces or make them part of a released package. Consult
[Scope and Releases](scope.md) before choosing an analysis.

This successor includes the opt-in `Experimental.MeanProfilePrior`, corrected
restricted-slope K-fold aggregation and accurate fixed/estimated loading labels.
Use the matching successor source below. The earlier
[13 October preview](https://ryuya-dot-com.github.io/BayesianMGMFRM.jl/preview/20261013/)
remains available at its original revision and does not contain these additions.

## [Find an answer by task](@id find-by-task)

Start with the question you need to answer; you do not need to know a function
name first. The explanation links lead to concepts, then to executable examples
and the exact function help.

| Your question | Start here | What you should be able to decide |
| --- | --- | --- |
| What do persons, raters, facets and dimensions mean? | [Getting Started](learning-guide.md), including [five or more facets](learning-guide.md#facets-levels-dimensions) | Which influence each data column represents; whether the model actually estimates it |
| Which MFRM/GMFRM/MGMFRM route fits my question? | [Model choices](learning-guide.md#Choose-assumptions-before-choosing-a-model-name), [current support](scope.md#Current-Support) | Dimension, slope and threshold choices; which routes remain experimental |
| How are rating probabilities calculated? | [Worked explanation](rating-model-theory.md), then [model equations](model-equations.md) | How a parameter change affects a category probability; who owns the thresholds |
| How does estimation work in Julia or Stan? | [From model to posterior draws](fitting.md#calculation-route), then [sampler controls](fitting.md#Backends-and-Sampler-Controls) | Model versus sampler; warmup, chains, uncertainty and numerical warnings |
| How do I choose and check priors? | [Prior implications](bayesian-workflow.md#3.-Check-Prior-Implications), [sensitivity](prior-sensitivity.md) | Whether generated ratings are plausible on the declared scale |
| How do I obtain intervals, diagnostics and useful reports? | [Reading Results](interpreting-results.md), [reporting API](api-saved-reporting.md) | Posterior uncertainty versus MCMC error; supported report scope |
| How can I compare models or plan a study? | [Comparison workflow](common_prediction_comparison.md), [operation limits](scope.md#common-operation-support) | Aligned prediction targets; recovery tools versus a still-unavailable general design runner |
| Where are help and runnable examples? | [Julia help](learning-guide.md#Use-Julia-help-and-examples), [examples](examples.md), [API by task](api.md) | Inspect data without fitting first; then run a model-specific example |
| How can I reopen and share results? | [Reports and reproducibility](fitting.md#Reports-and-Reproducibility) | A same-environment fit cache versus a portable computed JSON report |

## Install this development preview

Use Julia 1.10.8 or newer and a separate analysis project:

```julia
using Pkg
Pkg.activate("rating-preview")
Pkg.add(url="https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl",
    rev="development/20261013-successor")
Pkg.pin("BayesianMGMFRM")
```

Keep the project's `Project.toml` and `Manifest.toml`. For the exact published
snapshot, replace `rev` with the commit shown on the
[preview landing page](https://ryuya-dot-com.github.io/BayesianMGMFRM.jl/).
This successor branch contains the APIs described in this manual. The earlier
preview, `main` and the registered release may differ. Installation is
not scientific acceptance or a stable release.

Examples ship with the package and can be located independently of your working
directory:

```julia
using BayesianMGMFRM
include(joinpath(pkgdir(BayesianMGMFRM), "examples", "inspect_ratings.jl"))
```

This first example inspects artificial ratings and constructs a specification;
it performs no fitting. Continue with the [examples](examples.md).

See the [Visualization Gallery](visualization-gallery.md) for Wright Maps,
Pathway Maps and MGMFRM response surfaces with worked reading guidance.

`BayesianMGMFRM.jl` provides conservative Bayesian workflows for many-facet
Rasch measurement. It combines long-format rating-data validation, identified
model construction, Bayesian fitting, diagnostics, predictive checks,
portable reports, and optional figures directly from saved or newly fitted
models.

## New to Many-Facet Models?

Start with the [beginner's guide](learning-guide.md). It follows a concrete
rating example and separates the research question, data design and model choice.
No Julia or Bayesian modeling experience is needed to read it.

1. [Getting Started](learning-guide.md): persons, items, raters, dimensions and
   the differences between MFRM, GMFRM and MGMFRM.
2. [How Rating Models Work](rating-model-theory.md): category probabilities,
   a worked calculation, priors, identification and ability correlation.
3. [Reading Results and Comparing Models](interpreting-results.md): uncertainty,
   diagnostics, predictive comparison and simulation for study planning.

For executable Julia workflows, continue to the [short runnable examples](examples.md).

## What Is Supported

The stable fitting surface covers MFRM with rating-scale or partial-credit
steps. The following additional configurations require explicit experimental
opt-in:

- a fixed-coefficient multidimensional MFRM with independent abilities;
- a two-dimensional between-item MFRM with estimated population correlation;
- either admitted multidimensional MFRM route with an explicit exchangeable
  rater prior and a supplied rater kernel SD;
- a one-dimensional scalar GMFRM with item discrimination and rater consistency;
- a multidimensional fixed-Q confirmatory MGMFRM with independent abilities;
- that independent MGMFRM with an explicitly normalized exchangeable or source
  prior, whose scales and target differ from the raw prior;
- an explicit two-dimensional correlated MGMFRM, currently covering fitting,
  summaries, diagnostics, MCSE, prior/conditional posterior prediction, manual
  caches and report/figure bundles. This workflow remains experimental.

Broader discrimination structures, exploratory loadings, higher-dimensional
correlation estimation, and fitted DFF effects are not supported. See
[Scope and Releases](scope.md) for the exact boundary and
[Experimental Models](experimental.md) for the limited API.
Before choosing MGMFRM, review [what is estimated and what is fixed](scope.md#What-Changes-When-You-Choose-MGMFRM):
its fixed Q pattern still has estimated active loadings, and its rater
consistency parameter has a different meaning from reliability.
The [common-operation table](scope.md#common-operation-support) connects each
route to fitting, comparison, recovery and reporting, while the
[scientific-evidence table](scope.md#current-scientific-evidence) distinguishes
implemented operations from supported inferential claims.

## Recommended Path

The sequence below uses the stable MFRM entry points. For multidimensional MFRM
or GMFRM/MGMFRM, follow the [model-specific fitting and prior routes](bayesian-workflow.md#2.-Inspect-the-Model-Before-Fitting).

1. Build long-format ratings with [`FacetData`](@ref).
2. Run [`validate_design`](@ref) and inspect coverage, connectedness, category
   use, optional groups, and anchors.
3. Create an [`mfrm_spec`](@ref) and review its constraints.
   [`getdesign`](@ref) provides optional parameter inspection.
4. Use [`prior_predictive_check`](@ref) before fitting.
5. Call `fit(spec; backend = :advancedhmc, ...)` with explicit sampling settings
   for the supported stable model. Bare `fit(spec)` selects random-walk
   Metropolis and one chain; see [how estimation works](fitting.md#calculation-route).
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
    "learning-guide.md",
    "rating-model-theory.md",
    "interpreting-results.md",
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
