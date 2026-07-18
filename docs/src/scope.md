# Scope and Releases

`BayesianMGMFRM.jl` follows a conservative release policy: a model family is
documented as supported only when its likelihood, parameterization, fitting
path, diagnostics, and user-facing examples are covered together.

## Current Support

| Model surface | Status | Notes |
|:--|:--|:--|
| MFRM with rating-scale or partial-credit steps | Supported | Available through the documented design, fitting, diagnostic, and reporting workflow. |
| Scalar rater-consistency GMFRM | Experimental | Requires explicit opt-in and the documented structural restrictions. |
| Fixed-Q confirmatory MGMFRM | Experimental | Requires explicit opt-in, at least two dimensions, and a fixed confirmatory loading design. |
| Broader generalized discrimination structures | Not supported | No stable fitting claim is made. |
| Exploratory or freely estimated multidimensional loading structures | Not supported | Confirmatory fixed-Q support does not imply exploratory MGMFRM support. |
| Group and differential facet functioning effects | Not supported for fitting | Design validation may describe these terms, but estimation is not yet exposed. |

Experimental features may change in a compatible minor release and should be
used with sensitivity checks. They must not be described as stable equivalents
of external software or as evidence for broader MGMFRM support.

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
