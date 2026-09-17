# BayesianMGMFRM.jl

[![CI](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/workflows/CI.yml)

`BayesianMGMFRM.jl` provides conservative Bayesian workflows for many-facet
Rasch measurement in Julia. It validates long-format rating designs, constructs
identified MFRM/RSM/PCM models, fits them with Bayesian samplers, and produces
diagnostic tables, portable reports, and optional figures directly from a fit.
Figures cover posterior intervals, chain diagnostics, posterior predictions,
and stable-MFRM Wright maps.

The package deliberately distinguishes supported models from experimental
ones. A successful experimental fit is evidence about that exact configuration;
it is not evidence for broader GMFRM or MGMFRM support.

## Installation

Install the registered release from Julia General:

```julia
using Pkg
Pkg.add("BayesianMGMFRM")
```

To test unreleased development code, install an explicit Git revision:

```julia
using Pkg
Pkg.add(url = "https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl", rev = "main")
```

Pin a commit or tag instead of `main` for reproducible analyses. This README
and its examples describe the same repository revision; a registered release
may not include development features shown here. Use the documentation and
examples for the version you install.

## Model Support

| Model surface | Status | Entry point |
|:--|:--|:--|
| One-dimensional MFRM with rating-scale or partial-credit steps | Supported | `mfrm_spec`, `fit(spec)` |
| Fixed-coefficient multidimensional MFRM | Experimental | `BayesianMGMFRM.Experimental.fit(spec)` |
| Two-dimensional correlated MFRM (between-item, fixed coefficients) | Experimental | `Experimental.correlated(spec)` then `Experimental.fit` |
| Scalar GMFRM: item discrimination × rater consistency | Experimental | `BayesianMGMFRM.Experimental.fit(spec)` |
| Fixed-Q confirmatory MGMFRM | Experimental | `BayesianMGMFRM.Experimental.fit(spec)` |
| Broader discrimination structures | Not supported | Specification review only where documented |
| Exploratory loadings or higher-dimensional correlation estimation | Not supported | No fitting API |
| Fitted DFF effects | Not supported | Screening and design diagnostics only |
| Testlet, response-cluster, or rater-halo effects | Not supported | Metadata checks and report-only residual summaries |

The fixed-coefficient multidimensional MFRM estimates a person ability vector,
item locations, rater severities and item-specific partial-credit steps in unit
logits. It fixes active Q coefficients and rater consistency to one, with
independent abilities by default and prior-anchored person/item locations.
For two between-item dimensions, use `BayesianMGMFRM.Experimental.correlated(spec)`
to estimate population correlation; see the [correlation guide](docs/src/experimental.md#correlated-ability-dimensions). Both Julia
and CmdStan support the [fit, cache and figure/report example](docs/src/examples.md#fixed-coefficient-multidimensional-mfrm).
Before fitting either model, use `Experimental.prior_predictive_check` with
`MFRMPrior`, then `BayesianMGMFRM.plot_prior` and `BayesianMGMFRM.plot_predictive`
to inspect abilities, correlation and rating implications. See the
[prior inspection example](docs/src/experimental.md#inspect-priors-before-fitting).

The experimental GMFRM configuration is one-dimensional and estimates positive
item/task discrimination multiplied by positive rater consistency. Its
partial-credit step vector is rater-specific and shared across items and
persons on the direct parameter scale. It does not accept anchors or fitted DFF
terms.
The experimental MGMFRM configuration requires at least two dimensions, a
fixed confirmatory Q-matrix, partial-credit steps, identity latent correlation,
no anchors, and no fitted DFF terms.

MGMFRM estimates a person ability vector and positive loadings in the active
Q cells. Its response equation uses an additive weighted ability sum. See the
[model equations](docs/src/model-equations.md) for the source terminology,
between-/within-item distinction, and step sharing, and the
[experimental guide](docs/src/experimental.md) for priors and identification.

## Quick Start

For a short runnable demonstration from the repository root:

```sh
julia --project=. examples/minimal.jl
```

It fits in Julia with AdvancedHMC/NUTS, prints diagnostics and posterior
summaries, and saves/reloads `fit.jls` in a new directory under `results/minimal/`.
The small 50-warmup/50-retained-draw settings per chain demonstrate the workflow;
they are not sufficient for inference. Add `--plots` with CairoMakie installed
to generate all four figures from the reloaded fit. Add `--cmdstan` to use a
configured CmdStan installation. See the [example guide](docs/src/examples.md#minimal-mfrm-workflow)
for setup, output files and regeneration without refitting.

```julia
using BayesianMGMFRM

ratings = (
    examinee = ["E1", "E1", "E1", "E1", "E2", "E2", "E2", "E2"],
    rater = ["R1", "R2", "R1", "R2", "R1", "R2", "R1", "R2"],
    item = ["I1", "I1", "I2", "I2", "I1", "I1", "I2", "I2"],
    score = [0, 1, 2, 0, 1, 2, 0, 2],
)

data = FacetData(ratings;
    person = :examinee,
    rater = :rater,
    item = :item,
    score = :score,
    category_levels = 0:2,
)

validation = validate_design(data)
validation.passed || error(validation)

# Sampler-free category-gap and boundary-response audit
response_patterns = ordinal_response_pattern_audit(data)

spec = mfrm_spec(data; thresholds = :partial_credit,
    validation_report = validation)

fit_result = fit(spec;
    backend = :advancedhmc,
    ndraws = 500,
    warmup = 500,
    chains = 4,
    seed = 20260718,
)

diagnostics(fit_result; view = :public)
posterior_summary(fit_result)
```

For editable analysis figures, install CairoMakie once with
`Pkg.add("CairoMakie")`, then use:

```julia
using CairoMakie
figure = BayesianMGMFRM.plot_posterior(fit_result; block = :rater)
save("rater-posterior.pdf", figure)

chains = BayesianMGMFRM.plot_diagnostics(fit_result; block = :rater)
save("rater-chains.pdf", chains)

predictive = BayesianMGMFRM.plot_predictive(fit_result; ndraws = 200, seed = 42)
save("category-predictive.pdf", predictive)

wright = BayesianMGMFRM.plot_wright(fit_result)
save("wright-map.pdf", wright)
```

Save the fit once, then regenerate figures from it in a later Julia session:

```julia
save_fit_cache("analysis-fit.jls", fit_result)
restored = load_fit_cache("analysis-fit.jls")
wright = BayesianMGMFRM.plot_wright(restored)
save("wright-map-reloaded.pdf", wright)
```

The interval figure shows medians and 95% central credible intervals. Fixed reference
values and anchors appear as diamonds without intervals. See the
[plotting guide](docs/src/fitting.md#posterior-interval-figures) for selection,
editing, SVG output, and regenerating figures from saved fits.
The diagnostic figure shows retained-chain traces and rank histograms, with
R-hat/ESS and whole-fit warnings. Single-chain rank comparisons are explicitly
unavailable; see the [diagnostic plotting guide](docs/src/fitting.md#chain-diagnostic-figures).
The predictive figure compares observed category proportions with replicated
ratings for the same fitted persons, items and raters. Its bars are predictive
intervals. See the [predictive plotting guide](docs/src/fitting.md#posterior-predictive-figures)
for draw selection and replay from a saved fit.
The stable MFRM Wright map places ability, severity, difficulty and item-step
boundaries on a shared logit scale. See the [Wright-map guide](docs/src/fitting.md#wright-map)
for signs, boundary interpretation and fixed anchors.

Small sampler settings are useful for smoke tests only. Substantive analyses
should predeclare sampler controls, inspect convergence and HMC diagnostics,
and repeat important conclusions under defensible prior and model choices.
An unused interior score category, an all-maximum person, or a constant-score
rater is warning-level stress evidence rather than an automatic fit failure;
inspect `response_patterns` and repeat those cases under predeclared priors.
One category across the entire dataset remains a pre-fit error.
Pass `category_levels` when the score form defines the intended ordinal scale.
For example, `category_levels = 0:2` preserves all three PCM categories even
when a realized sample happens to contain only scores 1 and 2; validation then
warns that endpoint 0 is unobserved instead of silently fitting a two-category
model. Without the keyword, the backward-compatible default remains the
contiguous range from the observed minimum through maximum.

Stable MFRM and both experimental families accept `backend = :cmdstan` as
an alternative to Julia sampling. CmdStan is optional; use
`cmdstan_backend_check()` to inspect the local runtime. Each CmdStan fit
currently needs a fresh empty `cmdstan_cache_dir`; automatic compiled-model
reuse and `cached_fit` are unavailable for this backend. See the
[backend guide](docs/src/fitting.md#backends-and-sampler-controls) for setup
and build restrictions. Saved fits can still be reloaded for reporting.

## Main Workflow

1. Encode ratings with `FacetData`, run `validate_design`, and review category
   use, connectedness, coverage, and any intended anchors.
2. Choose a model with `mfrm_spec`. Review its constraints and prior-predictive
   implications; `getdesign` is available for optional parameter inspection.
3. Call `fit(spec)` and inspect `diagnostics(fit_result; view = :public)`.
   Review convergence, sampler warnings, and `posterior_mcse` for the quantities
   you intend to report.
4. Examine posterior intervals, replicated ratings, residuals, and sensitivity
   to defensible priors and model choices. Figures accept the fitted object
   directly; their settings and interpretation are in the plotting guide above.
5. Generate `report = fit_report(fit_result)` and render it with
   `fit_report_markdown(report)`, or request `view = :public` for structured
   reader-facing rows. Retain the saved fit, source data, analysis code, and
   package/environment versions.

Check `fit_report_health(report)` before treating a report as complete. Set
`require_complete = true` on report generation/export when a failed requested
section should stop the export. Model status (`supported` or `experimental`)
and report completeness are separate from convergence or scientific validity.
See the [Bayesian workflow](docs/src/bayesian-workflow.md) for interpretation.
To save selected figures, captions and numerical inputs with a report, pass
`figures` to `save_fit_report_bundle` as shown in the
[figure bundle guide](docs/src/fitting.md#reports-with-figures).

## Experimental Generalized Models

Use `BayesianMGMFRM.Experimental.fit(spec)` for the restricted scalar GMFRM
and fixed-Q MGMFRM configurations. The [experimental guide](docs/src/experimental.md)
explains model specification, named dimensions, raw versus model coordinates,
and prior sensitivity.

Run the small end-to-end execution example with:

```bash
julia --project=. examples/guarded_gmfrm.jl
julia --project=. examples/guarded_mgmfrm.jl
```

Both examples print model-scale summaries and diagnostics, then save and reload
the fit. They use two chains with 50 warmup and 50 retained draws each; these
short demonstrations are not suitable for substantive inference. Add `--plots`
with CairoMakie installed to save three figures, or `--cmdstan` to select a
configured CmdStan runtime. See the [example guide](docs/src/examples.md#saved-generalized-fits-and-figures)
for named-dimension selection and editable figures from saved fits.

## Documentation

- [Data validation](docs/src/data-validation.md)
- [Model equations](docs/src/model-equations.md)
- [Bayesian workflow](docs/src/bayesian-workflow.md)
- [Bayesian fitting](docs/src/fitting.md)
- [Experimental generalized models](docs/src/experimental.md)
- [Examples](docs/src/examples.md)
- [FACETS and ConQuest migration](docs/src/migration-facets-conquest.md)
- [Scope and releases](docs/src/scope.md)
- [API overview](docs/src/api.md)
- [Release notes](NEWS.md)

Runnable examples are available in
[`examples/minimal.jl`](examples/minimal.jl),
[`examples/guarded_gmfrm.jl`](examples/guarded_gmfrm.jl), and
[`examples/guarded_mgmfrm.jl`](examples/guarded_mgmfrm.jl).

## Development

Run the ordinary package tests with:

```sh
julia --project=. -e 'using Pkg; Pkg.test()'
```

Documentation builds, CI test groups, distribution checks, optional research
checks, and environment policy are described in the existing
[development notes](docs/src/development-readme-ledger.md#development-checks).

## Citation

If you use the package in research, cite the software version and the primary
measurement-model sources appropriate to your analysis. DOI-traced model
sources are listed in the [model-equation documentation](docs/src/model-equations.md).

## License

MIT License. See [LICENSE](LICENSE).
