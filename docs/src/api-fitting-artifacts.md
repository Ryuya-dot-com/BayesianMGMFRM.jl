# Fitting and Artifact API

## Stable fitting and shared artifacts

```@docs
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
```

## Optional analysis figures

Load CairoMakie to use these qualified entry points. They return editable
Figures and use the numerical summary functions documented in this manual.
`plot_wright` accepts stable MFRM fits only.

```@docs
BayesianMGMFRM.plot_posterior
BayesianMGMFRM.plot_prior
BayesianMGMFRM.plot_diagnostics
BayesianMGMFRM.plot_predictive
BayesianMGMFRM.plot_wright
```

## Experimental saved multidimensional MFRM reports

For an existing fixed-coefficient multidimensional MFRM cache, use
`load_fit_cache` followed by `fit_report`. Reports include the rating-design
audit, free and reconstructed parameter summaries, diagnostics, conditional
predictive checks and reproducibility information. Fixed coefficients and
derived coordinates are labelled separately; unsupported analyses state their
reasons. Reporting uses the fit's saved diagnostic settings.

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
[multidimensional example](examples.md#fixed-coefficient-multidimensional-mfrm).
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
