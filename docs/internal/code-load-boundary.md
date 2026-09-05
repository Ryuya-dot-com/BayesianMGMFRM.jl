# Code-load boundary review

Reviewed 2026-09-05 against `9a4d180`. The [active roadmap](../../ROADMAP.md)
owns priority; the [fixture review](fixture-boundary.md) separately classifies
all retained data. This review accepts the existing **0.1.x placement and
default execution boundary**, not a claim of minimal load cost or physical
separation of every research definition.

## Package definitions and retained purpose

[The module entry](../../src/BayesianMGMFRM.jl) includes 35 Julia files,
2,562,717 source bytes, with no nested repository includes in those files.
Including the entry itself gives 36 Julia sources. Three `src/stan/*.stan`
files support the optional CmdStan backend; they are not Julia includes.
No source file defines a package `__init__` hook or includes `scripts/`,
`test/`, or a research artifact at module top level.

The disjoint groups below cover all 35 includes at the reviewed revision.
Patterns identify current membership, not a classification rule for new code.

| Files | Count | Why they remain |
| --- | --- | --- |
| `cmdstan_backend`, `evidence_metadata`, `facet_workflow`, `ordinal_response_patterns`, `model_family_contract`, `model_contract`, `testlet_design_audit`, `bayesian_fit`, `cmdstan_fit`, `anchor_refit_plan`, `facets_conquest_bridge`, `practitioner_diagnostics`, `local_dependence`, `root_api_contract` | 14 | Stable behavior, compatibility aliases, shared model/fit/report implementation, and export policy. Some large files mix stable and research helpers; removing them by topic would remove shipped behavior |
| All `mgmfrm_validation_*.jl`, plus `mgmfrm_response_stress{,_fit}.jl` | 10 | Existing root research APIs for protocol, scoring, design and resource contracts; ordinary tests exercise their bounded behavior, not publication-grade recovery |
| `local_dependence_{known_truth_dgp,simulation,calibration,calibration_pilot}.jl` | 4 | Standalone generator and retained LD planning/scoring APIs; these definitions do not execute LD1b on import |
| `scalar_validation_logp.jl` | 1 | Analytic-gradient and frozen Stan comparison target; keep this numerical cross-check available to the ordinary fitting tests |
| All `mgmfrm_free_correlation_*.jl`, plus `experimental.jl` | 6 | Existing qualified `Experimental` diagnostic/research wrappers call these definitions. Study planning/scoring and recovery code are not orphaned merely because they are unexported |

The first row's names omit `.jl`. The existing
[root API contract](../../src/root_api_contract.jl) classifies **137 stable,
five compatibility, and 44 research bindings**. Keep that exact 186-binding
set and the qualified `Experimental` surface; loading a definition does not
promote its stability. Do not introduce lazy loading, remove compatibility
bindings, or split the two large shared source files for directory cosmetics.

All seven non-stdlib dependencies in [Project.toml](../../Project.toml) are
used by the shipped fit, gradient, diagnostic, or JSON/report implementation.
For example, Turing still implements the stable Turing backend. CmdStan/R and
licensed external executables are not required to load Julia-only definitions.
No dependency removal or extension migration follows from this inventory.

## Ordinary test runner: includes versus execution

The ordinary runner's direct script includes and their transitive closure are
**seven distinct files**, with the following consumers:

| Script(s) | Consumer and execution boundary |
| --- | --- |
| `local_json.jl`, `scientific_payload_digest.jl`, `public_language_gate.jl` | Shared JSON/digest and reader-facing output checks; the digest module includes the same JSON helper in its own namespace. Loading the language module does not run its CLI |
| `run_cmdstan_backend_validation.jl`, `run_cmdstan_recovery_pilot.jl` | [Core contract tests](../../test/cmdstan_validation_contract.jl) exercise controls, small generated cases, aggregation, and invalid inputs. Both CLIs have `PROGRAM_FILE` guards; including them does not run paired fits |
| `run_mgmfrm_publication_grade_refit_job.jl`, `generate_mgmfrm_full_heldout_mcmc_refit_fold1_pilot.jl` | [Diagnostic contract tests](../../test/rank_normalized_diagnostics.jl#L517) call the runner's metric selector on synthetic rows. The runner includes fold helpers; both entry points guard `main`, so this test does not read the committed pilot plan or execute a publication-grade refit |

This is an **include** inventory, not a claim that ordinary tests never run a
script or sampler. In particular:

- `fitting_core` explicitly runs `generate_validation_plan.jl` in a subprocess
  with `--preset smoke` and a temporary output. That CLI activates its project
  and calls `main()` unconditionally. Keep it a subprocess; do not treat it as
  another safe include. It generates a plan, not fits or research results.
- Ordinary fit integration and generalized resource tests deliberately use
  bounded synthetic fits. The three `BAYESIANMGMFRM_CMDSTAN_*` execution flags,
  free-correlation sampler/recovery flags, and experimental-fit smoke flag
  are distinct opt-ins. The separate experimental CI lane enables its bounded
  smokes; `RESEARCH_EVIDENCE_TESTS=false` does not mean all MCMC is disabled.
- The common helpers in `test/runtests.jl` are still parsed/defined before
  shard dispatch. The 90 optional fixture selectors prevent research-result
  checks, not that parsing cost. The JSON privacy lint still reads top-level
  fixture text, as recorded in the fixture review.
- LD artifact/harness tests, publication-grade fixture policy checks, free-
  correlation study execution tests, and reproduction archives remain behind
  `RUN_RESEARCH_EVIDENCE_TESTS` and the `all` group contract. Source/hash checks
  in ordinary tests are not independent research replication.

## Verification, decision, and stop condition

A temporary probe copied only `src/` into one tree and only the seven scripts
into another. On **Julia 1.10.8 and 1.12.5**, direct source evaluation passed
nine assertions and script loading passed seven: include paths matched the
reviewed sets, the 186 root bindings/classifications were preserved, and no
files were added or changed in either isolated tree. Both runs used
`--depwarn=error`; the probe inspected newly defined bindings in the latest
world. Neither tree contained fixtures, results, artifacts, or Git metadata.

This uses the already-resolved dependency environment and direct `include`,
not a fresh install, cached `using` latency benchmark, OS-level file-access
trace, or proof about every explicitly invoked function. The existing
[Git-free distribution smoke](../../scripts/distribution_archive_smoke.jl)
continues to cover install/load/example/manual behavior separately. No new
scientific evaluation, external execution, fixture regeneration, source edit,
dependency change, or file relocation was performed for this review.

Accept the current placement for the declared compatibility line together
with the fixture retain decisions. This closes the bounded M0 placement/load
review; it does not close runtime acceptance or establish an independently
reviewed scientific domain. Reopen it for a changed load dependency, an
unguarded execution/result dependency, an API migration, or measured budget
pressure. **Next: finish the remaining CI/distribution runtime assessment**;
profile a demonstrated hot path before extracting shared helpers or adding
another loading layer.
