# BayesianMGMFRM.jl — Internal Roadmap

Reviewed 2026-09-05. This is the **single current work order**, not a public
feature catalogue or a completion percentage. Start with the decision below;
do not reconstruct priorities from historical checkboxes.

## Active Decision Roadmap

**M0: close the package baseline -> M1: freeze the anchor study -> M2: evaluate
with fresh data -> M3: independently review the supported domain.**

M1 drafting and external-source inventory may proceed during M0. Fresh
evaluation waits for M0 and independently reviewed M1. Generalized-model
expansion, LD1b execution, free correlations, soft/group anchors, and new-facet
prediction remain separate, deferred programs.

| Milestone | Status | Responsible role and concrete exit |
| --- | --- | --- |
| M0 — Package baseline | Implementation and placement/load-boundary review complete; final runtime acceptance remains open | Maintainer: finish comparable CI/distribution runtime assessment; preserve the reviewed 0.1.x boundaries |
| M1 — Anchor-study protocol | Draft: 16 primary candidate cells and comparable estimands specified | Analyst: finish the decision table in the [study draft](docs/internal/mfrm-anchor-study.md#freeze-decisions); independent reviewer checks equations, cells, scoring, thresholds, and resource limits |
| M2 — Fresh evaluation | Not started; zero evaluation replications | Analyst: execute the reviewed roster, retain every attempt, and report per-cell recovery/calibration with Monte Carlo uncertainty and failure denominators |
| M3 — External review and domain decision | Matching-source inventory only; independent review outstanding | Maintainer and independent reviewer: separate-environment matched reproduction and claim-level allow, narrow, reject, or inconclusive decisions |

Roles above do not imply that a person has accepted an assignment. In
particular, an independent reviewer is not yet assigned. Implementation by
the same author or another local receipt cannot satisfy that review.

## Immediate work and stop conditions

Work on the highest unfinished decision, not the largest collection of scripts.

| Order / task | Next deliverable | Verification and stop condition |
| --- | --- | --- |
| 1. M0-DOC — Complete at `bd22c01` | Short root roadmap, one active anchor-study draft, archived old roadmaps, and the directory map below | Both archived bodies preserved with rebased links; 34 local links/fragments, the Git-free install/load/example/manual smoke, and all 12 ordinary candidate-CI jobs passed |
| 2. M0-CI — Six shard and minimum-version full-suite medians established; other lanes open | Complete the remaining CI/distribution runtime assessment without mixing changed workloads | Preserve timeouts and tests; investigate >20% median growth. A changed lane/workload or an isolated rerun cannot silently fill the denominator |
| 3. M0-BOUNDARY — Placement/load review complete | [123 fixtures classified](docs/internal/fixture-boundary.md); [35 source includes and seven ordinary script includes reviewed](docs/internal/code-load-boundary.md). Retain the declared 0.1.x compatibility surface and archival records | Isolated definition loads passed on Julia 1.10.8 and 1.12.5 without research trees. No relocation, regeneration, dependency removal, or lazy loader. Reopen for changed dependencies/consumers or measured budget pressure |
| 4. M1-FREEZE — Resolve the study draft | Finite sensitivity cells, seed policy, estimands/thresholds, sampler/resource budget, all-attempt scorer, and reviewer handoff | No fresh evaluation while any freeze decision is open; no new generic controller or evidence framework without a demonstrated gap |

M0-DOC is a bounded documentation/layout change, not completion of all M0.
Physical relocation of research fixtures, large source-file decomposition,
and optional-dependency changes are separate tasks and are not bundled into it.
M0-BOUNDARY accepts the current compatibility-line placement, not minimum
startup cost or scientific validation. The next unfinished engineering decision
is the runtime assessment in order 2; do not restart the closed inventories.

## Evidence baseline and claim limits

- `101b791`: [CI 33946739309](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33946739309)
  passed all 12 ordinary jobs. The full minimum-version suite and six current-
  Julia shards matched at 87 testsets / 14,731 assertions.
- `9668383`: [CI 33949682122](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33949682122)
  passed all 12 ordinary jobs. The six current-Julia shards passed 89 testsets /
  17,249 assertions; the Julia 1.10.8 full job passed in 30m48s. The two manual
  research jobs were skipped. This is not a three-run runtime median.
- `ed4185f`: 308 reference-declaration/estimand checks were added. The focused
  generator file passed 2,826 assertions locally on Julia 1.10.8 and 1.12.5.
  [CI 33951073887](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33951073887)
  subsequently passed all 12 ordinary jobs; both manual research jobs were
  skipped. The Julia 1.10.8 full job took 21m47s. Do not transfer this green
  result to a later documentation edit, or treat three changed-workload runs
  as an already-reviewed comparable runtime baseline.
- `bd22c01`: the document/layout reorganization passed all 12 ordinary jobs in
  [CI 33952439772](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33952439772);
  both manual research jobs were skipped. The full Julia 1.10.8 job took
  30m17s. The fixture inventory and median assessment are later documentation
  changes, not additional scientific evaluation.
- `fa7ffc9`: [CI 33953993916](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33953993916)
  passed all 12 ordinary jobs; two manual research jobs were skipped. The full
  Julia 1.10.8 job passed 90 testsets / 17,557 assertions in 29m56s. This closes
  the missing test-lane median observations below, not all runtime conditions
  or the later complete-fixture classification's candidate CI.
- The earlier anchor pilot completed 80 fits but only two independent datasets
  per cell, with PCM-only truth, favorable initialization, and a shared
  generation/fitting kernel. None of its fits enters the new evaluation count.
- Exact anchor checks cover fixed versus estimated coordinates, incompatible
  anchor contrasts, intended categories, reports, and persistence. They establish
  implementation behavior, not repeated recovery or uncertainty calibration.
- Narrow local TAM and version-specific ConQuest evidence remain useful but do
  not establish independent reproduction, broad product parity, or transfer to
  GMFRM/MGMFRM.

The finite implementation review and earlier timings are preserved in the
[baseline record](docs/internal/archive/roadmap-2026-09-05.md#immediate-milestones).
Its older “pending” observations are historical; the status above governs.
Track scientific readiness separately from engineering readiness. No count of
tests, generated files, or historical checkboxes is a project-completion score.

### Comparable CI timings

The following are complete successful jobs from attempt 1 of runs
`33949682122` (`9668383`), `33951073887` (`ed4185f`), and
[`33952439772`](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33952439772)
(`bd22c01`), in that order for the first five rows. The last two rows instead
use `ed4185f`, `bd22c01`, and
[`33953993916`](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33953993916)
(`fa7ffc9`). Current-Julia rows use Julia 1.12.7; the full-suite row uses
Julia 1.10.8. All logs agree on Ubuntu 24.04, runner image `20260831.293.1`,
and provisioner `20260828.587`. Within each accepted row,
testset names and per-set assertion counts match exactly. The reports row
excludes `9668383` (23 testsets / 6,194 assertions; 24m54s), before the 308-check
anchor addition; the other source changes are documentation only.

| Lane | Testsets / assertions | Three whole-job times | Baseline median |
| --- | --- | --- | --- |
| `core` | 11 / 2,899 | 22m05s, 20m32s, 20m46s | 20m46s |
| `fitting_core` | 2 / 2,755 | 21m53s, 17m41s, 15m41s | 17m41s |
| `local_dependence_core` | 32 / 2,904 | 24m25s, 22m46s, 23m35s | 23m35s |
| `local_dependence_integrity` | 2 / 52 | 17m45s, 17m59s, 13m57s | 17m45s |
| `generalized` | 19 / 2,445 | 13m24s, 13m00s, 11m19s | 13m00s |
| `fitting_reports` | 24 / 6,502 | 20m59s, 20m37s, 21m08s | 20m59s |
| Full suite, Julia 1.10.8 | 90 / 17,557 | 21m47s, 30m17s, 29m56s | 29m56s |

These are an initial lane baseline, not sampler-speed measurements or a
completed >20% regression comparison. Setup/cache variation is included; queue
time is excluded. The full suite includes the changed reports workload, so
`9668383` is also excluded from that row. Remaining lanes are macOS/Windows
smoke, documentation, experimental-boundary smoke, and release hygiene; assess
the distribution smoke's individual phases separately. Their comparable
medians and the sustained runtime target remain open, so this table does not
close the runtime P0 condition.

## Package release conditions

Generalized expansion waits for every condition below, followed by the
M0–M3 domain decision. A checked engineering item is not scientific validation.

- [x] A Git-free source candidate installs, loads, runs the stable example, and
  builds the manual without ignored artifacts, private paths, CmdStan, or R.
- [x] Stable MFRM supports declared categories and actual individual rater/item
  hard anchors through fitting, fixed-coordinate reports, and persistence;
  the finite M0 behavior review passed candidate CI.
- [x] Root exports are frozen and classified; stable exports are documented;
  experimental and research entry points remain visibly separated.
- [x] Release checks protect behavior, schema, performance, portability, and
  privacy rather than unrelated prose or transitive source digests.
- [ ] Ordinary research-result isolation and enforced runtime budgets have
  comparable whole-lane evidence and three-run medians.
- [x] The current 0.1.x package/research placement and load boundary is reviewed:
  active documents are short,
  retained fixtures have a shipped purpose or an explicit archival role, and
  research records are not numerical prerequisites for ordinary tests. Retained
  ordinary numerical/behavioral references are identified separately; shared
  research definitions still have parsing/load cost and are not promoted APIs.

Keep the existing 4 MiB compressed Git archive growth guard, the documented
250 KiB fixture-review threshold, and per-phase/per-job timeouts. A size or
timing exception needs a stated user benefit; do not inflate limits silently.
The four documented research-only missing-docstring warnings stay classified
under the existing Documenter policy; stable API completeness is checked
separately.

## Directory map and change boundaries

| Location | Role and rule |
| --- | --- |
| `Project.toml`, `src/` | Package dependencies and implementation; no source/API refactor in this organization pass |
| `examples/`, `README.md`, `docs/src/` | User workflows and manual sources; `docs/make.jl` explicitly selects published pages |
| `ROADMAP.md` | Current priorities, owners, exit decisions, and a compact evidence baseline |
| [`docs/internal/mfrm-anchor-study.md`](docs/internal/mfrm-anchor-study.md) | Active M1 methods draft; the only place to edit its cell/estimand/seed/threshold decisions |
| [`fixture-boundary.md`](docs/internal/fixture-boundary.md), [`code-load-boundary.md`](docs/internal/code-load-boundary.md) | Finite 0.1.x placement decisions and their verification limits; revisit only when the recorded boundary changes |
| [`docs/internal/archive/`](docs/internal/archive/) | Preserved roadmap snapshots and deferred rationale; outside the manual source tree and not an execution authority |
| `docs/src/development-*.md`, `docs/src/mgmfrm-research-roadmap.md` | Existing non-published ledgers and deferred research detail; not competing work orders |
| `test/`, [`test/fixtures/`](test/fixtures/README.md) | Behavioral regressions and numerical references; ordinary versus opt-in behavior is documented in the fixture guide |
| `scripts/` | Existing release, diagnostic, and research commands; names do not authorize execution, and pinned paths are retained |
| `artifacts/`, `results/`, `test/fixtures/local/` | Ignored local outputs where present; neither delete nor publish them during directory cleanup |
| `Manifest.toml`, `docs/Manifest.toml`, `docs/build/` | Ignored local environments/build output; keep the tracked `Manifest-v1.10.toml` reproducibility reference |

Commands and inline source paths in internal documents are relative to the
repository root; Markdown links are relative to their containing file.
The old [manual roadmap path](docs/src/roadmap.md) is retained as a pointer.
The [root snapshot](docs/internal/archive/roadmap-2026-09-05.md) and
[manual snapshot](docs/internal/archive/manual-roadmap-2026-09-05.md) preserve
their pre-organization content and source commit. Frozen research bundles may
refer to the old paths/bytes: inspect their recorded revision; do not rewrite
old evidence digests just to match the new documentation.

## Deferred work and decision discipline

Resume the [narrow fixed-Q program](docs/internal/archive/roadmap-2026-09-05.md#downstream-fixed-q-program)
only after the current domain decision. Its protocol, recovery, external review,
and promotion gates remain separate. Generic MGMFRM, exploratory loadings, free
correlations, dynamic raters, testlet mechanisms, and causal fairness claims
are not hidden requirements for finishing the declared stable MFRM slice.

Retain the [claim-to-evidence boundaries](docs/internal/archive/roadmap-2026-09-05.md#claim-to-evidence-ledger)
and [engineering sustainability constraints](docs/internal/archive/roadmap-2026-09-05.md#engineering-sustainability-gate).
A proposed change must name a shipped behavior, a demonstrated correctness
risk, or a predeclared scientific claim. Prefer an existing helper and a focused
check; do not add exports, dependencies, large fixtures, or source-hash chains
for one-off research convenience.

When a milestone changes, replace its status and record only the uncertainty
reduced, the affected claim, and the next blocking decision. Git records routine
edits; do not create another dated snapshot for each status update. Missing
external input triggers a concrete reviewer/data handoff, not endless local
simulation. No merge, release, broad claim, or independent review is implied
by this roadmap or by green CI.
