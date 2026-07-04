# Registration Handoff

This page records the manual handoff boundary for a first Julia General
registration request. It does not perform publication, package registration, or
manuscript-claim approval.

Before requesting registration, run the full local gate from the repository
root:

```bash
julia --startup-file=no scripts/pre_registration_gate.jl
```

The gate checks project metadata, General AutoMerge-facing package and origin
URL shape, clean temporary-environment import, `Pkg.test()`, the minimal
example, the guarded MGMFRM example, Documenter with a 100 KiB rendered-page
hard limit, Aqua package hygiene, `git diff --check`, and the public wording /
skipped-test scan. CI runs the hygiene subset in a lighter mode because the
matrix test and documentation jobs cover `Pkg.test()` and the docs build
separately, while the stricter public wording scan remains a manual
pre-registration check.

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

After the registration commit has been merged to `main` and CI is green, print
the manual Registrator trigger message:

```bash
julia --project=. scripts/registration_handoff.jl --strict
```

The script verifies the local release boundary and prints a copy-paste
Registrator comment. It does not call GitHub, Registrator, General, or any
publication endpoint.

## Manual Checklist

- Package name: `BayesianMGMFRM`
- Repository name for General: `BayesianMGMFRM.jl`
- Origin URL shape: resolves to `BayesianMGMFRM.jl` with or without a `.git`
  suffix
- Initial version: `0.1.0`
- License: MIT
- Local gate: `julia --startup-file=no scripts/pre_registration_gate.jl`
- CI gate: documentation, pre-registration gate, and Julia 1 / 1.10 tests on
  Ubuntu, macOS, and Windows pass on the registration commit.
- Trigger template: `julia --project=. scripts/registration_handoff.jl --strict`
  runs from `main` with no tracked worktree changes.
- Registration action: performed manually by the user through the Julia
  Registrator workflow.

## Manual Trigger Template

The GitHub App workflow for Registrator is to comment on the commit or branch
to be registered. For this repository, the final trigger should be posted by the
user on the green `main` registration commit:

```text
@JuliaRegistrator register

Release notes:

Initial 0.1.0 release of BayesianMGMFRM.jl. This release provides a
conservative Bayesian many-facet Rasch workflow scaffold covering
long-format data validation, design inspection, minimal MFRM/RSM/PCM
fitting, and guarded scalar GMFRM / fixed-Q confirmatory MGMFRM
experiments. Broader GMFRM/MGMFRM fitting, fitted DFF effects,
model-weight or sparse-superiority claims, manuscript claims, and
publication actions remain out of scope.
```

See the Registrator GitHub App instructions and the General / RegistryCI
guidelines before triggering the request:

- [Registrator GitHub App workflow](https://github.com/JuliaRegistries/Registrator.jl#via-the-github-app)
- [General registration README](https://github.com/JuliaRegistries/General#registering-a-package-in-general)
- [RegistryCI new-package guidelines](https://juliaregistries.github.io/RegistryCI.jl/stable/guidelines/#New-packages)

## Scope Boundary

General registration of version `0.1.0` should be treated as registration of the
current public package slice: data validation, design inspection, minimal
MFRM/RSM/PCM fitting, and guarded scalar GMFRM / fixed-Q confirmatory MGMFRM
experiments. It is not a claim of broad GMFRM/MGMFRM fitting support, DFF model
effects, model-weight superiority, sparse-design superiority, or manuscript
readiness.

After registration, update the installation instructions in the README and docs
only after the registered package is available from General.
