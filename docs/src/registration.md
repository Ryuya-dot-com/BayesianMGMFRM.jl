# Version Update Handoff

This page records the manual handoff boundary for the BayesianMGMFRM.jl
version `0.1.1` update in Julia General. It does not publish anything, update
the registry, or approve research claims.

Before requesting the version update, run the full local gate from the
repository root:

```bash
julia --startup-file=no scripts/pre_registration_gate.jl --expected-version=0.1.1
```

The gate checks project metadata, General AutoMerge-facing package and origin
URL shape, clean temporary-environment import, `Pkg.test()`, the minimal
example, the guarded scalar GMFRM example, the guarded fixed-Q MGMFRM example,
Documenter with a 100 KiB rendered-page hard limit, Aqua package hygiene,
`git diff --check`, and the reader-facing wording / skipped-test scan. CI runs
the hygiene subset in a lighter mode because the matrix test and documentation
jobs cover `Pkg.test()` and the docs build separately, while the stricter
reader-facing wording scan remains part of final local release verification.

The machine-readable release boundary is available from
[`release_scope_summary`](@ref):

```julia
using BayesianMGMFRM

scope = release_scope_summary(; include_evidence = true)
scope.summary.next_gate
```

The expected release boundary is
`manual_publication_or_registration_by_user_only`. The package records local
evidence rows for guarded generalized fitting, fit-cache identity, reproduction
guardrails, documentation page-size checks, and release-verification gate
availability, while keeping `publication_or_registration_action = false`.

After the version-update commit has been merged to `main` and CI is green,
print the manual Registrator trigger message:

```bash
julia --project=. scripts/registration_handoff.jl --strict --expected-version=0.1.1
```

The script verifies the local release boundary and prints a copy-paste
Registrator comment. It does not call GitHub, Registrator, General, or any
publication endpoint.

## Manual Checklist

- Package name: `BayesianMGMFRM`
- Repository name for General: `BayesianMGMFRM.jl`
- Origin URL shape: resolves to `BayesianMGMFRM.jl` with or without a `.git`
  suffix
- Release version: `0.1.1`
- License: MIT
- Local gate:
  `julia --startup-file=no scripts/pre_registration_gate.jl --expected-version=0.1.1`
- CI gate: documentation, release-verification gate, and Julia 1 / 1.10 tests
  on Ubuntu, macOS, and Windows pass on the version-update commit.
- Trigger template:
  `julia --project=. scripts/registration_handoff.jl --strict --expected-version=0.1.1`
  runs from `main` with no tracked worktree changes.
- Registry and publication actions: performed only by the user; the scripts do
  not contact external services.

## Manual Trigger Template

The GitHub App workflow for Registrator is to comment on the commit or branch
whose version should be registered. For this repository, the final trigger
should be posted by the user on the green `main` version-update commit:

```text
@JuliaRegistrator register

Release notes:

Release 0.1.1 of BayesianMGMFRM.jl. This release provides a
conservative Bayesian many-facet Rasch workflow scaffold covering
long-format data validation, design inspection, minimal MFRM/RSM/PCM
fitting, and guarded scalar GMFRM / fixed-Q confirmatory MGMFRM
experiments. Broader GMFRM/MGMFRM fitting, fitted DFF effects,
model-weight or sparse-superiority claims, manuscript claims, and
publication actions remain out of scope.
```

See the Registrator GitHub App instructions and the General registry guidance
before triggering the request:

- [Registrator GitHub App workflow](https://github.com/JuliaRegistries/Registrator.jl#via-the-github-app)
- [General registration README](https://github.com/JuliaRegistries/General#registering-a-package-in-general)

## Scope Boundary

Registration of version `0.1.1` in General should be treated as an update to
the current public package slice: data validation, design inspection, minimal
MFRM/RSM/PCM fitting, and guarded scalar GMFRM / fixed-Q confirmatory MGMFRM
experiments. It is not a claim of broad GMFRM/MGMFRM fitting support, DFF model
effects, model-weight superiority, sparse-design superiority, or manuscript
readiness.

After General accepts version `0.1.1`, verify that a fresh Julia environment
resolves the registered version before announcing the update.
