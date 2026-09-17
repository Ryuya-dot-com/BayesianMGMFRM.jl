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

### Normalized-prior density and sampling addendum, 2026-09-13

The package entry now also includes `mgmfrm_normalized_prior.jl`: 36 direct
Julia includes, or 37 sources with the entry itself. This adds a private,
explicitly configured fixed-Q density and its prior-record/data adapters;
there is no new export, dependency, file read, subprocess or MCMC on import.
The same three production Stan files remain. `mgmfrm.stan` gains explicit
prior branches while its ordinary adapter continues to select the legacy
raw prior. The subsequent private integration reuses the existing Julia NUTS,
CmdStan chain, diagnostic and atomic serialization helpers, without changing
the include count or public exports. Explicit save/load calls use trusted
same-environment serialized records with a separate schema; no file is read
or written by import. The generalized shard now also includes
`test/mgmfrm_normalized_samples.jl`, which executes two short Julia fits and
temporary save/load checks. Its actual CmdStan fits, like the earlier density
compilation, require the existing CmdStan test flag. The preceding claim of
sampler-free added tests applies only to the density slice. This is not a
fresh isolated-load or distribution/runtime-budget receipt; see the
[active roadmap](../../ROADMAP.md#normalized-prior-sampling-and-saved-results)
for the measured verification scope and remaining sampling acceptance.

The later manual [`run_normalized_prior_comparison.jl`](../../scripts/run_normalized_prior_comparison.jl)
includes the existing backend-validation script solely to reuse its fixed-data
generator. Its `PROGRAM_FILE` guard prevents the four-fit experiment from
running on include. The separate
[`normalized_prior_comparison.jl`](../../test/normalized_prior_comparison.jl)
decision test is manual and is not added to `test/runtests.jl`. Package include
counts, exports and the ordinary script closure are unchanged. The declared
experiment, local execution receipt and remaining precision/runtime limits
are recorded in the [comparison note](normalized-prior-backend-comparison.md);
they are not a new CI or distribution runtime acceptance receipt.

The subsequent saved-result profiling slice changes only SHA-256 input
handling in existing fit/cache/report functions. It adds no package include,
export or dependency. The manual
[`profile_normalized_prior_results.jl`](../../scripts/profile_normalized_prior_results.jl)
reuses the comparison definitions without fitting on include; explicit calls
read trusted saved records and write to new profile/verification locations.
The fitting-reports shard adds [`test/cache_hash.jl`](../../test/cache_hash.jl),
which checks byte compatibility without sampling or reading research files.
The 1,658-assertion manual regression and local before/after timing receipt
are documented in the comparison note; package-load and CI/distribution
runtime acceptance remain separate work.

The following precision trial adds one explicit `--precision-followup` option
to the same manual comparison runner. The initial invocation retains its
original controls/seeds, and both fixed plans reuse the existing loop. Its
predecessor-file verification runs only when the follow-up is explicitly
requested; no research artifact is read on include. The manual decision test
now passes 57 assertions. The four larger fits and independent arithmetic
verification are recorded in the [comparison note](normalized-prior-backend-comparison.md#precision-follow-up-execution-receipt),
without changing production sources, package includes, public exports,
dependencies or ordinary test execution.

The subsequent normalized-prior warmup slice adds compact event collection,
phase summaries and CSV phase-boundary validation inside existing source files.
In that initial slice, only the private normalized-prior sampler enabled
recording by default; ordinary fit callers retained the previous policy. No package include, public
export or dependency is added. Private samples gain schema v2, while v1
remains readable with unavailable historical warmup coverage. The existing
generalized-shard `test/mgmfrm_normalized_samples.jl` now runs seven short Julia
fits instead of two, plus synthetic coverage/CSV checks. Seven matching native
CmdStan fits require the existing explicit CmdStan test flag. The larger saved
comparison is read only by a manual verification call, not ordinary tests.
The [warmup receipt](normalized-prior-backend-comparison.md#warmup-telemetry-execution-receipt-2026-09-13)
records 7,106 final assertions and historical-result compatibility; this is
not a new package-load, CI runtime-budget or distribution acceptance receipt.

The following public warmup integration enables recording in the existing
AdvancedHMC and CmdStan `fit`/`Experimental.fit` routes. It reuses the same
collectors and CSV parser, retains all fit struct layouts and stores only
chain summaries in the existing `sampler_controls` metadata. The public
`sampler_diagnostics` function gains `phase = :warmup`; its retained default
and convergence surfaces are unchanged. Cache save/load validate the optional
summary metadata without changing the v1 cache schema or rewriting old files.
No package include, public export, dependency or production Stan file is added.

The `fitting_core` shard additionally includes `test/warmup_diagnostics.jl`:
nine short AdvancedHMC fits across the three fitted families and one fit each
for Turing and random walk. Nine CmdStan counterparts require the existing
explicit native-test flag. The saved pre-change cache comparison is a manual
local check; ordinary tests do not read that receipt or research results.
The [public-fit receipt](normalized-prior-backend-comparison.md#public-fit-warmup-integration-2026-09-13)
records 322 focused plus 6,838 regression assertions. Its initial native setup
failure and corrected fresh-directory rerun are retained separately; this is
not an ordinary full-shard runtime or CI acceptance run.

The subsequent warmup report slice only extends the existing report section,
projection and Markdown paths. `test/warmup_report.jl` joins the `fitting_reports`
shard and uses deterministic report inputs, with no MCMC, subprocess, CmdStan
build or research-file read. The manual legacy check reads local pre-change
report bundles and earlier saved fits only when explicitly run. No package
include, public export or dependency changes. The
[report receipt](normalized-prior-backend-comparison.md#warmup-report-presentation-2026-09-13)
records 211 focused and 506 regression assertions; it does not close CI runtime
or package-load acceptance.

The subsequent column-order fix changes only the shared Markdown resolver and
removes warmup's separate column list. `test/report_columns.jl` joins the existing
`fitting_reports` shard; it uses small report/dossier payloads and temporary
exports without sampling or reading research artifacts. The expanded warmup
report checks also compare all table headers. Manual historical-bundle/fit
reads remain outside the ordinary runner. The
[column-order receipt](normalized-prior-backend-comparison.md#report-column-order-2026-09-13)
records 516 assertions on Julia 1.12.5 with `--compile=min`; this does not
establish CI runtime or package-load acceptance. No package include, public
export or dependency changes.

The subsequent sampling-failure audit extends only the existing
`test/fitting_boundaries.jl` inclusion. The test-owned RNG drives real tiny
AdvancedHMC transitions and injects delayed faults; its seeded test dispatch
exercises automatic cache creation/refresh without changing production RNG
methods. The existing synthetic CmdStan executable also fails during chain 2.
The [receipt](normalized-prior-backend-comparison.md#sampling-failure-and-cache-publication-2026-09-13)
records 1,380 assertions with normal compilation on Julia 1.12.5. The only
package-source edit is a cache docstring clarification. No include, public
export, dependency, sampler or cache-execution change; no CI runtime or load
acceptance claim.

The subsequent minimum-version slice reruns existing test files on Julia
1.10.8 with its unchanged versioned manifest. The
[receipt](normalized-prior-backend-comparison.md#minimum-version-verification-2026-09-13)
records 2,852 final assertions, including 16 native CmdStan short fits with
`--compile=min` and compiled modules enabled. Normal compilation passes the
boundary file; the larger sampler run was manually stopped after about 25
minutes while in LLVM and remains an unresolved execution observation. This
does not establish its cause or accept CI runtime/load budgets. The follow-up
below separates ordinary fitting from the combined test harness. No package include,
public export, dependency, production source or ordinary test execution changes.

The [2026-09-14 follow-up](normalized-prior-backend-comparison.md#cache-record-compilation-2026-09-14)
localizes excessive specialization on nested record types to two private cache
helpers in `bayesian_fit.jl`. Compiler annotations suppress specialization and
inference on their record arguments; both function bodies, serialized bytes,
hash rules and validation conditions are unchanged. The existing tests run with
normal compilation on Julia 1.10.8; the Julia 1.12.5 run completes its first four
files but reaches the 900-second limit in warmup reports. The remaining report
checks pass separately with `--compile=min`. No include, export,
dependency, fit layout or test inclusion changes; this bounded correction does
not close M0 CI runtime/load acceptance.

### Previously reviewed runner

At the reviewed `9a4d180` revision, the ordinary runner's direct script includes
and their transitive closure were **seven distinct files**, with the following
consumers. The anchor-recording addendum below records the later bounded addition.

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

## Fixed-coefficient validation preparation addendum

On 2026-09-17, the ordinary `generalized` shard also includes
[mfrm_validation_preparation.jl](../../test/mfrm_validation_preparation.jl), which
manually loads one new script module,
[mfrm_validation_preparation.jl](../../scripts/mfrm_validation_preparation.jl).
The module defines a small fixed-facet generator and known-truth scoring helpers;
importing it performs no data generation, fitting, file publication or research
evaluation. It imports the package and standard libraries, with no other script
includes. Its tests reuse the existing exchangeable synthetic-record helper.
There is no package include/export, dependency, serialized fit type or public
API change. The historical include counts below remain dated observations.

## Anchor recording test addendum

On 2026-09-07, `fitting_reports` also includes
[mfrm_anchor_attempt_record.jl](../../test/mfrm_anchor_attempt_record.jl).
That test loads the new `scripts/mfrm_anchor_attempt_record.jl` module, which
includes `scripts/local_dependence_pilot_attempt_archive.jl` and its existing
`scripts/local_json.jl` dependency. This adds **two distinct scripts**, bringing
the current ordinary include closure to **nine**, without adding a package
include or export. No LD1 job/batch runner or research fixture is loaded by this
path. The script now imports the package for its concrete, input-bound minimal
fit call; the underlying LD1 archive module remains separately loadable. Its
real calls reject before sampling; successful-return tests use
synthetic results. Other checks cover temporary-file publication/recovery and
interruption of owned stdlib-only child processes, not an executing fit observer.

The publication/observation step passed 25,537 scoped assertions per version;
input binding then passed 25,631, and returned-fit/scoring links passed 25,691.
With pre-entry source/environment checks, the recording file passes 374
assertions (93 publication/recovery + 52 observation + 99 input binding + 55
result/scoring links + 75 source/environment) on Julia 1.10.8 and 1.12.5.
The checks reuse the existing record readers, fit hash, read-only scorer,
source-roster/digest primitives, and native Project/Manifest resolution;
no additional include boundary or package-source change was introduced. The
input transport v2 omits the redundant legacy UInt64 design signature to avoid
JSON round-trip rounding, retaining the canonical SHA and labelled payload.
The combined scoped regression passed 25,766 assertions across 29 testsets per version,
rechecked 186 root exports, and verified the single `fitting_reports` inclusion
by parsing, not executing, the full runner. Historical seven-script isolated-load
receipts below are not fresh isolation checks of the added paths. This addition
does not close M0's runtime hold or authorize CI.

The later manual [CmdStan cache probe](../../scripts/probe_cmdstan_cache_identity.jl)
is not included by the ordinary runner. It evaluates eight selected helpers in
an isolated module with a fixed source lookup, command/JSON traps and a no-draw
RNG. It never loads the package or runs a sampler/compiler. It now checks cache
containment, invocation/environment rejection and output handoff with 4,617
assertions per Julia 1.10.8/1.12.5; the earlier 68-check characterization,
488-check containment, 704-check invocation and 4,110-check environment receipts are
historical. None changes the nine-script ordinary closure or constitutes a
package-load check. Cumulative production changes cover shared program discovery,
compilation/output validation and both sampling consumers/fit-control routes,
plus the discovery docstring; there are no new package imports or exports.

The separate manual [synthetic output-wiring check](../../scripts/probe_cmdstan_output_wiring.jl)
does load the installed project/package for real types and deterministic helpers.
It selects four unchanged adapter definitions into its own module and replaces
only local runtime/cache/command/sampler boundaries, leaving package methods and
the stdlib-only probe unchanged. It passed 431 assertions per Julia 1.10.8/1.12.5,
with four direct producer returns, four fixed-result routes and twenty injected
compile failures; ten source/project/probe hashes and the caller environment
were preserved. No native build, posterior draw or synthetic-result publication
occurred. This manual package-dependent check is not an isolated distribution
load, an ordinary-runner addition, a public generalized-fit integration or a
rerun of the 4,617-check probe; the nine-script ordinary closure is unchanged.

## Optional posterior-figure addendum, 2026-09-14

The package now includes [posterior_plot.jl](../../src/posterior_plot.jl) after
the existing fit implementation. Its numerical/selection helpers reuse fit
summaries and constraint transforms; no graphics dependency loads on this path.
CairoMakie 0.15 is a weak dependency whose
[extension](../../ext/BayesianMGMFRMCairoMakieExt.jl) supplies the native editable
Figure when the user loads CairoMakie. The qualified optional entry point adds
no root export, serialized type or script include.

`fitting_core` now includes [posterior_plot.jl](../../test/posterior_plot.jl),
which loads a small deterministic reporting fixture shared with the existing
warmup report check. It loads no research artifacts or samplers. The separate
[rendering check](../../test/posterior_plot_render.jl) needs an optional CairoMakie
environment and is not part of the ordinary test runner. Each of Julia 1.10.8
and 1.12.5 passes 266 numerical/selection and 41 render/cache assertions with
normal compilation. The root inference dependency graphs are preserved; only
their project hashes reflect the weak-dependency declaration. These checks do
not rerun the historical isolated-tree review or accept CI/distribution runtime.
See the local ignored [receipt](../../results/posterior-plots/20260914-01/receipt.json).

The subsequent trace/rank slice adds `BayesianMGMFRM.plot_diagnostics` inside
the same source file and extension, with shared draw-coordinate selection.
It expands the same test files and optionally supplies multiple synthetic chains
through the existing fixture. No package/script include, root export, Project or
manifest changes occur. The final scoped checks pass 266 interval, 128 trace/rank
and 86 optional rendering/cache assertions per Julia 1.10.8 and 1.12.5, all with
normal compilation. See the local ignored
[trace/rank receipt](../../results/posterior-plots/20260914-trace-rank-01/receipt.json).
These remain synthetic checks, with no native sampler or isolated-install trial;
the existing CI/distribution runtime acceptance conditions remain open.

The category predictive slice adds `BayesianMGMFRM.plot_predictive` in the same
source file and extension, reusing existing predictive checks and summaries.
The shared `_sample_category_index` in `bayesian_fit.jl` now rejects invalid
probabilities instead of silently selecting the final category. Existing test
files cover valid-sequence preservation, selection/replay and all three fit
families; the fixture and include lists are unchanged. Final checks pass 266
interval, 128 trace/rank, 294 predictive and 120 optional rendering/cache
assertions per Julia 1.10.8 and 1.12.5. No root export, dependency, Project,
manifest or serialized type changes occur. See the local ignored
[predictive receipt](../../results/posterior-plots/20260914-predictive-01/receipt.json).
Replicated responses use synthetic parameter draws; no native MCMC, isolated
install, full-suite or runtime acceptance is claimed.

The stable MFRM Wright-map slice adds qualified `BayesianMGMFRM.plot_wright`
inside the same source file and extension, and extends the same two test files.
It adds no package/script include, root export, dependency or serialized type;
the shared reporting fixture is unchanged. In `bayesian_fit.jl`, threshold-row
fixed metadata now refers to the full item-step position, and the shared position
helper rejects derived overflow before numerical summarization. Both ordinary
Wright-map rows and diagnostic-map rows use that correction. Scope and evidence
are recorded in the local ignored
[Wright-map receipt](../../results/posterior-plots/20260914-wright-01/receipt.json).
These changes do not rerun isolated-install or CI/runtime acceptance.

The short stable MFRM example now integrates existing fitting, diagnostics,
cache reload and optional figures without changing any package source,
extension, test or script file, Project/manifest, export or include list.
CairoMakie loads only for the example's `--plots` flag; `--cmdstan` uses a fresh
build directory. Actual native Julia/CmdStan example checks are recorded in the
[workflow receipt](../../results/workflows/20260914-minimal-01/receipt.json).
They do not rerun isolated-install or CI/runtime acceptance.

The two guarded examples now use the same optional-figure/save-reload route,
with qualified model-scale summaries and named MGMFRM dimensions. Their
`--cmdstan` options stay in the existing backend; no wrapper or include is added.
The [guarded workflow receipt](../../results/workflows/20260914-guarded-01/receipt.json)
records this examples/documentation slice. The sole package-source edit adds
the missing `direct_posterior_summary` docstring, also listed in the existing
API reference. Executable source, extension/test/script trees, Projects/manifests,
exports and serialized types are unchanged.

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
