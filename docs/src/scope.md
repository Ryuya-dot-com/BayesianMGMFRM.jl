# Scope and Releases

`BayesianMGMFRM.jl` follows a conservative release policy: a model family is
documented as supported only when its likelihood, parameterization, fitting
path, diagnostics, and user-facing examples are covered together.

## Current Support

| Model surface | Status | Notes |
|:--|:--|:--|
| MFRM with rating-scale or partial-credit steps | Supported | Available through the documented design, fitting, diagnostic, and reporting workflow. |
| Scalar rater-consistency GMFRM | Experimental | Enter through `BayesianMGMFRM.Experimental`; the documented structural restrictions remain mandatory. |
| Fixed-Q confirmatory MGMFRM | Experimental | Enter through `BayesianMGMFRM.Experimental`; requires at least two dimensions and a fixed confirmatory loading design. |
| Broader generalized discrimination structures | Not supported | No stable fitting claim is made. |
| Exploratory or freely estimated multidimensional loading structures | Not supported | Availability of the experimental fixed-Q configuration does not imply exploratory MGMFRM support. |
| Group and differential facet functioning effects | Not supported for fitting | Design validation may describe these terms, but estimation is not yet exposed. |
| Testlet, response-cluster, and rater-halo effects | Not supported for fitting | Explicit identifiers, structural auditing, standardized residual inputs, known-truth simulation, calibration-scorer validation, and MCMC-free pilot-plan validation are available; pilot execution, repeated calibration, and fitted cluster effects are not. |

Experimental features may change in a compatible minor release and should be
used with sensitivity checks. They must not be described as stable equivalents
of external software or as evidence for broader MGMFRM support.
The namespace is an explicit experimental stability boundary, not a maturity claim.
`BayesianMGMFRM.Experimental.surface_contract()` records its exact current
configurations and constraints. The historical `experimental = true` keyword is a
compatibility route and does not define the forward-looking API.

LD1a supplies a 22-scenario known-truth generator, LD1b0 validates the
calibration scorer and denominator rules, and LD1b1 freezes a 30-replication
pilot plan for each scenario. These layers validate study design and scoring
without running a fit or MCMC. They therefore provide no repeated-calibration,
power, diagnostic-decision, or mechanism-identification evidence. Controlled
benchmark-response placement remains a separate temporal-identification study,
and clustered or dynamic effects remain unsupported for fitting.

## Release Direction

- The `0.1.x` series prioritizes reliability, diagnostics, reproducible reports,
  and clearer separation between stable and experimental functionality.
- A future minor release may stabilize a narrowly defined fixed-Q generalized
  subset only after implementation, inference, documentation, and independent
  validation checks all pass.
- Broader generalized, exploratory multidimensional, and differential facet
  functioning models remain later research and implementation work.
- External validation and publication claims are evaluated separately from
  package-version readiness.

The registered release remains the default installation. Development versions
may contain unreleased behavior and should be pinned to an explicit revision
when used in reproducible work.
