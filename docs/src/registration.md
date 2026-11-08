# Versioning and Saved-Result Migration

A package version and a development source revision identify different things.
Several development revisions can retain the same package version. Record the
exact source revision, Julia version and complete dependency environment with
an analysis. The [supported scope](scope.md) describes model/prior/backend
combinations; an experimental interface remains experimental after publication.

## Pin an analysis environment

Use a separate Julia project for an analysis and preserve its `Project.toml`
and `Manifest.toml`. For a development version, also record the Git revision.
The [installation instructions](index.md#Install-this-development-preview)
identify the source described by this manual. Do not infer the available methods from the
version number alone.

Native `.jls` files should be reopened in their original trusted Julia and
complete dependency environment. Pinning only this package is insufficient.
Do not bypass an integrity error or assume that a newer Julia cache can be
opened by an older Julia. Portable JSON shares computed results, not posterior
draws or a refittable model.

## Cite the source used

Use the `CITATION.cff` supplied with the source you actually used. The current
development version is `0.1.2 (unreleased)`; no release date or version DOI is
assigned to it. Record the exact Git revision or an archived source snapshot
alongside the version. A package version alone cannot distinguish development
revisions. Keep the source archive with the analysis when a revision cannot
identify local modifications.

For a published release, use that release's citation metadata and verified
version DOI when one exists. Do not transfer an earlier release's date or DOI
to a development snapshot. Cite the measurement-model sources appropriate to
the analysis separately, as listed in [Model Equations](model-equations.md).

## Preserve the statistical target

| Change | Effect on an existing analysis |
| :--- | :--- |
| A different model, prior, slope policy or mean profile | Defines a different target and requires its own inference. It cannot be applied by relabeling a saved posterior. |
| A report-label or formatting correction | Regenerate the report from a compatible saved fit, retaining the original report, requests and interval settings. |
| A comparison-aggregation correction | Recompute from the matching saved fold scores; retain missing folds and warnings. A full-data fit cannot substitute for a missing fold fit. |
| A documentation-only change | Does not improve convergence, calibration or the statistical validity of an existing result. |

For report regeneration without new replicated ratings, first reopen a compatible
`fit` using [the saved-result instructions](api-saved-reporting.md#saved-result-reproduction).
Then:

```julia
using BayesianMGMFRM
# The legacy MFRM category section also generates replicated ratings.
legacy_options = fit isa MFRMFit ?
    (; include_category_functioning=false, include_rater_homogeneity=false) : (;)
report = fit_report(fit; legacy_options...,
    include_prior_predictive=false,
    include_posterior_predictive=false,
    on_section_error=:throw)
```

Disabling posterior-predictive reporting alone does not disable ordinary
MFRM's separate legacy category-functioning section. The example omits it
and legacy rater homogeneity explicitly; other fit types do not accept those
legacy section options.

Supply the original reporting requests, intervals and other options explicitly.
Defaults do not recover those choices or the previous report's predictive
sections. Write to a new destination and record the source revision used.
Loading an existing JSON report preserves its original text; it does not apply
new reporting code. See [saved-result reproduction](api-saved-reporting.md#saved-result-reproduction).

Current summaries compute `probability_equal` by counting draws exactly equal
to the reference. Older summaries used `1 - probability_positive -
probability_negative`, which can leave a tiny negative or positive remainder
even when no draw equals the reference. Recorded-fit readers recognize only
that exact historical formula when comparing regenerated summaries; all stored
hashes and other summary checks remain in force. Loading retains the original
artifact. A newly computed summary uses the count, while an archived JSON report
retains its original value. An observed zero tie count does not establish the
posterior probability of a point-null hypothesis.

## Restore or update

To restore an analysis, use its archived environment and pinned source in a
separate project, retaining the original results. To update the software,
first check the changed behavior and environment compatibility. Documentation
and selected tests do not establish fitting support on a previously untested
Julia version or platform.

For package-development checks and documentation builds, see
[Contributing](contributing.md). Distribution and registration scripts in
`scripts/` have their own usage instructions; scripts that run package tests
or examples can perform fitting. A successful local check does not itself
publish a package or change a registry entry.
