# Scope and Releases

`BayesianMGMFRM.jl` follows a conservative release policy: a model family is
documented as supported only when its likelihood, parameterization, fitting
path, diagnostics, and user-facing examples are covered together.

## Current Support

| Model surface | Status | Notes |
|:--|:--|:--|
| MFRM with rating-scale or partial-credit steps | Supported | Available through the documented design, fitting, diagnostic, and reporting workflow. |
| Scalar GMFRM: item discrimination × rater consistency | Experimental | Enter through `BayesianMGMFRM.Experimental`; the documented structural restrictions remain mandatory. |
| Fixed-Q confirmatory MGMFRM | Experimental | Enter through `BayesianMGMFRM.Experimental`; requires at least two dimensions and a fixed confirmatory loading design. |
| Broader generalized discrimination structures | Not supported | No stable fitting claim is made. |
| Exploratory loading patterns or free latent correlations | Not supported for fitting | Fixed-Q fits estimate positive active loadings but keep the zero pattern and identity latent correlation fixed. A separate two-dimensional correlation density has no public sampler. |
| Group and differential facet functioning effects | Not supported for fitting | Design validation may describe these terms, but estimation is not yet exposed. |
| Testlet, response-cluster, and rater-halo effects | Not supported for fitting | Explicit identifiers, structural checks, and residual/predictive summaries are available. These report-only summaries provide no calibrated decision or mechanism classification. |

Experimental features may change in a minor release and should be
used with sensitivity checks. They must not be described as stable equivalents
of external software or as evidence for broader MGMFRM support.
The namespace is an explicit experimental stability boundary, not a maturity claim.
`BayesianMGMFRM.Experimental.surface_contract()` records its exact current
configurations and constraints. The historical `experimental = true` keyword is a
compatibility route and does not define the forward-looking API.

## Interpreting Support and Versions

“Supported” describes the documented implementation boundary, not proof of
convergence or validity for a new dataset. Experimental availability does not
establish recovery, robustness, or external-software agreement. Known-truth
simulation and protocol helpers have their own [research API
reference](api-validation-evidence.md); their presence does not change the
fitting boundary above.

The registered release remains the default installation. Development versions
may contain unreleased behavior and should be pinned to an explicit revision
when used in reproducible work.

Read the manual and examples for the installed revision. Development
documentation can describe features absent from an earlier registered release.
