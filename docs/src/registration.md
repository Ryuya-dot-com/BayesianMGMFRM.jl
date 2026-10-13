# Version Update Handoff

This page separates development-preview delivery from the manual handoff for
the BayesianMGMFRM.jl version `0.1.2` update in Julia General. Neither the page
nor the handoff script publishes a package or approves research claims.

## Development Preview and Successor Changes

The published 13 October preview is commit
`fe523ff8f50c6f0d1b3ba57263731e9c80a3422f` on
`development/20261013-guide`. The `development/20261013-successor` source and
`preview/20261013-successor/` manual retain the same package version while adding
opt-in mean profiles and fixing slope-comparison/report behavior. The preview
landing page identifies the exact source commit after delivery. The version number alone does not identify the source or its evidence.
Record the commit (or, before publication, the candidate's source hashes), Julia
version and complete `Project.toml`/`Manifest.toml` with the analysis.

| Successor change | Effect on an existing analysis | Migration |
| --- | --- | --- |
| `Experimental.MeanProfilePrior` | A newly selected prior target; old zero-mean fits keep their original prior. | Opt in only for the documented D1, fixed-one item/rater slopes and item-owned PCM route. This does not modify a saved posterior. |
| Restricted-slope K-fold aggregation | Fixes a metadata-branch error and retains item/rater coefficient policies; likelihood and fitting are unchanged. | Recompute aggregation from matching saved fold scores. Missing folds and warnings remain; do not replace them with full-data fits. |
| Fixed-slope report labels | Active Q entries say `fixed_one`; explanations identify fixed rater consistency. Estimates and uncertainty are unchanged. | Regenerate a report from the matching native fit and save it under a new path. Loading an old JSON report preserves its original text. |

For the report correction, use `fit_report(fit; include_prior_predictive=false,
include_posterior_predictive=false)` to avoid generating new replicated ratings.
Pass the saved analysis's reporting requests, intervals and other options
explicitly when they are needed: report defaults do not reconstruct those
choices or historical predictive sections. Preserve the original report and
record the new source version. See the [saved-report workflow](api-saved-reporting.md).

Restore native `.jls` files with their original Julia and complete dependency
environment. Pinning only this package is insufficient; do not bypass integrity
failures or assume that a newer Julia cache works on an older Julia. Portable
JSON shares already computed results, not posterior draws or a refittable model.
For rollback, return to the archived project/manifest and pinned source in a
separate project, retaining the original results. A changed prior requires its
own inference; it is not a cache migration.

Before delivering a selected successor:

- [ ] Identify the exact source/manual pair and intended destination; update
  installation instructions and the preview landing page together.
- [ ] Reconcile [model/operation scope](scope.md), NEWS, examples and the changes
  above. A published experimental interface is still experimental.
- [ ] Reuse applicable evidence by source, environment and settings, then close
  missing or invalidated checks. The current bounded 1.10.8 profile/report/cache
  checks and 1.12.5 saved-fit checks are not a current full-suite, actual
  minimum-version fitting, clean-install or all-platform pass.
- [ ] After authorized delivery, read back the identified source, verify its
  installation route and inspect the hosted manual. A successful push alone
  does not establish delivery. Keep the earlier pinned preview available.

These steps do not close scientific or independent workflow acceptance. The
existing [roadmap](../../ROADMAP.md) distinguishes those gates from preview
delivery. The release-scope summary and registration script below record the
older release boundary and available tooling; they do not inspect all later
candidate evidence, hosted content or reviewer acceptance.

## Registered Version Update

For an actual registered version update, apply the release gates below to the
selected release commit. They include new fitting and are not a no-fit preview
check. Run them when that release work and its execution scope are authorized;
do not rerun successful numerical work solely for a documentation change.

```bash
julia --startup-file=no scripts/distribution_archive_smoke.jl
julia --startup-file=no scripts/pre_registration_gate.jl --expected-version=0.1.2
```

The distribution smoke first verifies instantiate, first/warm load, the minimal
stable fit, and the manual from a Git-free, non-ignored source candidate with
optional research evidence and CmdStan/R environment hooks disabled. The full
gate then checks project metadata, General AutoMerge-facing package and origin
URL shape, clean temporary-environment import, `Pkg.test()`, the minimal
example, the guarded scalar GMFRM example, the guarded fixed-Q MGMFRM example,
Documenter with a 100 KiB rendered-page hard limit, Aqua package hygiene,
`git diff --check`, and the reader-facing wording / skipped-test scan. CI runs
the hygiene subset in a lighter mode because the matrix test and documentation
jobs cover `Pkg.test()` and the docs build separately, while the stricter
reader-facing wording scan remains part of final local release verification.
SHA-chained research archives are deliberately outside ordinary `Pkg.test()`;
they can be audited separately with
`BAYESIANMGMFRM_RESEARCH_EVIDENCE_TESTS=true` or the manually dispatched
research-evidence workflow. Their historical byte identity is not a package
installation requirement.

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
julia --project=. scripts/registration_handoff.jl --strict --expected-version=0.1.2
```

The script verifies the local release boundary and prints a copy-paste
Registrator comment. It does not call GitHub, Registrator, General, or any
publication endpoint.

## Manual Checklist

- Package name: `BayesianMGMFRM`
- Repository name for General: `BayesianMGMFRM.jl`
- Origin URL shape: resolves to `BayesianMGMFRM.jl` with or without a `.git`
  suffix
- Release version: `0.1.2`
- License: MIT
- Local gate:
  `julia --startup-file=no scripts/distribution_archive_smoke.jl`, then
  `julia --startup-file=no scripts/pre_registration_gate.jl --expected-version=0.1.2`
- CI gate: clean-distribution, documentation, and release-verification gates,
  complete ordinary package coverage through current-Julia shards and the full
  Julia 1.10 suite on Ubuntu, and current-Julia package smokes on macOS and
  Windows pass on the version-update commit.
- Trigger template:
  `julia --project=. scripts/registration_handoff.jl --strict --expected-version=0.1.2`
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

Release 0.1.2 of BayesianMGMFRM.jl. This release provides a
conservative Bayesian many-facet Rasch workflow scaffold covering
long-format data validation, design inspection, minimal MFRM/RSM/PCM
fitting. The documented scalar GMFRM and fixed-Q confirmatory MGMFRM
configurations are executable only through the experimental namespace;
broader GMFRM/MGMFRM fitting, fitted DFF effects,
model-weight or sparse-superiority claims, manuscript claims, and
publication actions remain out of scope.
```

See the Registrator GitHub App instructions and the General registry guidance
before triggering the request:

- [Registrator GitHub App workflow](https://github.com/JuliaRegistries/Registrator.jl#via-the-github-app)
- [General registration README](https://github.com/JuliaRegistries/General#registering-a-package-in-general)

## Scope Boundary

Registration of version `0.1.2` in General should be treated as an update to
the current public package slice: data validation, design inspection, minimal
MFRM/RSM/PCM fitting, and executable but provisional scalar GMFRM / fixed-Q
confirmatory MGMFRM configurations in the experimental namespace. It is not a
claim of stable or broad GMFRM/MGMFRM fitting support, DFF model
effects, model-weight superiority, sparse-design superiority, or manuscript
readiness.

After General accepts version `0.1.2`, verify that a fresh Julia environment
resolves the registered version before announcing the update.
