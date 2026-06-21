# Registration Handoff

This page records the manual handoff boundary for a first Julia General
registration request. It does not perform publication, package registration, or
manuscript-claim approval.

Before requesting registration, run the full local gate from the repository
root:

```bash
julia --startup-file=no scripts/pre_registration_gate.jl
```

The gate checks project metadata, clean temporary-environment import,
`Pkg.test()`, the minimal example, the guarded MGMFRM example, Documenter with a
100 KiB rendered-page hard limit, Aqua package hygiene, `git diff --check`, and
the public wording / skipped-test scan. CI runs the same gate in a lighter mode
because the matrix test and documentation jobs cover `Pkg.test()` and the docs
build separately.

The machine-readable release boundary is available from
[`release_scope_summary`](@ref):

```julia
using BayesianMGMFRM

scope = release_scope_summary(; include_evidence = true)
scope.summary.next_gate
```

The expected registration boundary is
`manual_publication_or_registration_by_user_only`. The package records local
evidence rows for guarded generalized fitting, fit-cache identity, reproduction
guardrails, documentation page-size checks, and pre-registration gate
availability, while keeping `publication_or_registration_action = false`.

## Manual Checklist

- Package name: `BayesianMGMFRM`
- Repository name for General: `BayesianMGMFRM.jl`
- Initial version: `0.1.0`
- License: MIT
- Local gate: `julia --startup-file=no scripts/pre_registration_gate.jl`
- CI gate: documentation, pre-registration gate, and Julia 1 / 1.10 tests on
  Ubuntu, macOS, and Windows pass on the registration commit.
- Registration action: performed manually by the user through the Julia
  Registrator workflow.

## Scope Boundary

General registration of version `0.1.0` should be treated as registration of the
current public package slice: data validation, design inspection, minimal
MFRM/RSM/PCM fitting, and guarded scalar GMFRM / fixed-Q confirmatory MGMFRM
experiments. It is not a claim of broad GMFRM/MGMFRM fitting support, DFF model
effects, model-weight superiority, sparse-design superiority, or manuscript
readiness.

After registration, update the installation instructions in the README and docs
only after the registered package is available from General.
