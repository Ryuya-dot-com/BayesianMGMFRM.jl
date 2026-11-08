# Fitting and Artifact API

!!! note "Unreleased documentation preview — 13 October 2026"
    This manual includes unreleased interfaces and examples. It is not the
    documentation of an installed release. Model support and scientific
    acceptance remain as stated on each page.

## Stable fitting and shared artifacts

```@docs
SamplingProgress
progress_snapshot
MFRMPrior
MFRMLogDensity
MFRMFit
fit
fit_metadata
fit_artifact
fit_archive_manifest
artifact_content_hash
cached_fit
fit_cache_key
save_fit_cache
load_fit_cache
fit_report
fit_report_health
fit_report_public
fit_report_markdown
fit_report_dossier
fit_report_dossier_markdown
fit_reproduction_manifest
fit_report_section
fit_report_sections
fit_report_rows
load_fit_report
load_fit_report_dossier
load_fit_report_bundle
load_fit_report_tables
save_fit_report
save_fit_report_dossier
save_fit_report_dossier_markdown
save_fit_report_bundle
save_fit_report_markdown
save_fit_report_tables
related_software_capability_matrix
prepare_fit
run_chain_worker
worker_status
collect_fit
save_fit
load_fit
save_report
load_report
```

## Optional analysis figures

Load CairoMakie to use `BayesianMGMFRM.plot(x; kind = ...)` or the specialized
qualified entry points below. They return editable Figures and use the numerical
summary functions documented in this manual. `plot_wright` and `plot_pathway`
accept stable unidimensional MFRM fits only.

```@docs
BayesianMGMFRM.plot
BayesianMGMFRM.plot_posterior
BayesianMGMFRM.plot_prior
BayesianMGMFRM.plot_diagnostics
BayesianMGMFRM.plot_predictive
BayesianMGMFRM.plot_wright
BayesianMGMFRM.wright_ridge_data
BayesianMGMFRM.plot_pathway
BayesianMGMFRM.item_response_surface
BayesianMGMFRM.plot_response_surface
```

## Experimental saved multidimensional MFRM reports

For an existing fixed-coefficient multidimensional MFRM cache, use
`load_fit_cache` followed by `fit_report`. Reports include the rating-design
audit, free and reconstructed parameter summaries, diagnostics, conditional
predictive checks and reproducibility information. Fixed coefficients and
derived coordinates are labelled separately; unsupported analyses state their
reasons. Reporting uses the fit's saved diagnostic settings.
Fits made with `Experimental.ExchangeablePrior` use these same operations;
their saved prior supplies the kernel, marginal and contrast severity scales.

Set `include_prior_predictive = true` to add simulation summaries from the
saved model and priors. Control its draw budget with `prior_predictive_ndraws`,
its parameter interval with `prior_interval`, and reproducibility with `seed`.
Figure bundles additionally accept `prior` and `prior_predictive`; their
PDF/SVG figures and numerical JSON use the same report summaries.

```julia
restored = load_fit_cache("multidimensional-fit.jls")
report = fit_report(restored; posterior_lower = 0.05, posterior_upper = 0.95,
    seed = 42)
save_fit_report_bundle("multidimensional-report", fit_report_public(report))
artifact = fit_artifact(restored; view = :public)
```

Posterior bounds must define a central interval strictly inside `(0, 1)`.
These experimental models use unit logits and fixed Q coefficients. Abilities
are independent by default; `Experimental.correlated(spec)` estimates population
correlation for two between-item dimensions. Correlated reports default to
`view = :public` and include rho intervals and diagnostics. Estimate with
`BayesianMGMFRM.Experimental.fit`; see the
[multidimensional example](examples.md#Fixed-coefficient-multidimensional-MFRM).
Earlier independent-model caches remain readable. Saving a correlated fit
records its model and actual priors separately.
These saved-result reports need neither sampling nor CairoMakie. A complete
report means that its requested sections ran successfully; inspect the MCMC
diagnostics separately.

Load CairoMakie to plot an ability dimension by its stored name and save a
report with figures:

```julia
using CairoMakie
dimension = fit_metadata(restored).dimension_labels[1]
figure = BayesianMGMFRM.plot_posterior(restored; block = :person, dimension)
save("ability.pdf", figure)
save_fit_report_bundle("multidimensional-figures", restored; view = :public,
    figures = (posterior = (; block = :person, dimension),
        diagnostics = (; block = :person, dimension), predictive = (;)),
    posterior_lower = 0.05, posterior_upper = 0.95,
    predictive_interval = 0.9, seed = 42)
reopened = load_fit_report_bundle("multidimensional-figures")
```

Posterior and trace/rank plots use model coordinates in unit logits. Fixed
coefficients have no credible interval or convergence diagnostic. The predictive
figure checks the observed rating design using the report's exact replicated
category summaries. Bundles include PDF/SVG figures and their numerical JSON
inputs; reopening and verifying a bundle does not require CairoMakie. For large
fits, select a smaller set of exact parameter names or explicitly increase
`max_parameters` and the figure size. Whole-fit MCMC warnings remain visible.

## Experimental model-scale summaries

Use this qualified function for transformed GMFRM/MGMFRM parameters.
`posterior_summary` retains its raw-coordinate meaning for those fits.

```@docs
BayesianMGMFRM.direct_posterior_summary
```

## Experimental compatibility types

Earlier code may use `GMFRMFit` and `MGMFRMFit` at the package root. New
generalized workflows should access these result types through
`BayesianMGMFRM.Experimental`; see
[Experimental Models](experimental.md).

```@docs
GMFRMFit
MGMFRMFit
```

## Carry joint draws into another calculation

For `MFRMFit`, `GMFRMFit` and `MGMFRMFit`, request retained draws explicitly:

```julia
artifact = fit_artifact(fitted; view=:public, include_draws=true,
    include_environment=false)
artifact.draw_index.chain_ids
artifact.draw_index.iterations
artifact.fit_metadata.prior
```

Each matrix row is one joint posterior draw, excluding warmup. The row index
matches `draws` for scalar MFRM and both `raw_draws` and `direct_draws` for the
listed generalized fit types. Scalar columns follow `parameter_names`. For
generalized fits, the full view includes both matrices with `raw_parameter_names`
and `direct_parameter_names`; the public view retains only `direct_draws` and
`direct_parameter_names`. Do not mix those coordinate systems. With `include_draws=false`, the row index
and matrices are omitted. Older artifacts may lack these fields: obtain them
from the original fit rather than guessing from a matrix's size. Separate
recorded, normalized and correlated result types retain their existing artifact
contracts; this example does not establish a common export for every model.

For a saved scalar Rasch/PCM/RSM fit, the example below writes ordinary JSON
with rows of numbers, exact parameter names, chain/iteration indices, actual
prior settings, model constraints, prior/reference warnings, warmup and retained
diagnostics, and posterior intervals with MCSE. It performs no sampling:

```julia
using BayesianMGMFRM
include(joinpath(pkgdir(BayesianMGMFRM), "examples", "joint_draw_handoff.jl"))
fitted = load_fit_cache("analysis-fit.jls")
receipt = JointDrawHandoff.write_json("joint-draws.json", fitted)
```

The cache must be opened in its compatible source/Julia/dependency environment.
This is a scalar example, not a new universal serialization API. JSON rows
preserve their parameter pairing; stored user IDs are not anonymized. The
returned SHA-256 verifies the file bytes. The embedded source-artifact hash
identifies the original Julia object, not the JSON file's different encoding.
Retain the receipt and the report's numerical and model warnings with the file.

A Python calculation can then use the same row for both effects:

```python
import json
import numpy as np
with open("joint-draws.json", encoding="utf-8") as source:
    saved = json.load(source)
x = np.asarray(saved["draws"], dtype=float)
names = saved["parameter_names"]
# Existing binary Rasch example: item I01 is the fixed zero reference.
delta = x[:, names.index("item[I03]")] - x[:, names.index("item[I02]")]
print(delta.mean(), np.quantile(delta, [0.025, 0.975]))
```

Check that the intended IDs exist and read the diagnostic/MCSE information
before interpreting the interval. Differences, predictions and decision
probabilities must be computed row by row; subtracting interval endpoints or
independently sorting/resampling columns destroys joint uncertainty. Sorting
rows within each chain is legitimate only if every parameter and its row index
move together. Preserve iteration order when computing autocorrelation or MCSE.
Fixed reference effects are constants, not missing sampled columns; follow the
saved constraints when a requested contrast includes one.

This connection makes uncertainty available for another computation. Using
posterior means as error-free regression predictors, or fitting a separate
regression to every draw and calling it a joint model, is not justified by this
export. An outcome-linked model needs its own likelihood, priors and validation;
retained measurement draws do not automatically incorporate outcome feedback.
The [fit and decision guide](migration-facets-conquest.md#Comparing-fit-and-decisions)
explains reference changes and prior sensitivity. The saved example validates
transport, not general calibration or a preferred prior.
