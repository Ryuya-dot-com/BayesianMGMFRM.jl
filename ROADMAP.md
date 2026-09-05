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
| M0 — Package baseline | Implementation, placement/load review, and all 12 lane baselines recorded; runtime acceptance remains open | Maintainer: explain or remediate the `fitting_core` rolling-median increase of 23.4%; preserve the reviewed 0.1.x boundaries |
| M1 — Anchor-study protocol | Draft: anchor, response-replay, and scoring primitives checked; full roster, adapters, and decision rules unfrozen | Analyst: finish the decision table in the [study draft](docs/internal/mfrm-anchor-study.md#freeze-decisions); independent reviewer checks equations, cells, scoring, thresholds, and resource limits |
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
| 2. M0-CI — Compilation-heavy fits; runner CPU heterogeneity observed | Separate ordinary observations by CPU/target and version/threads; three CPU/target pairs currently have one observation each, not a hardware-matched median | Explain or remediate 17m41s -> 21m49s before acceptance; preserve the 30-minute ceiling and all assertions. Instrumented observations do not silently replace the original timing window |
| 3. M0-BOUNDARY — Placement/load review complete | [123 fixtures classified](docs/internal/fixture-boundary.md); [35 source includes and seven ordinary script includes reviewed](docs/internal/code-load-boundary.md). Retain the declared 0.1.x compatibility surface and archival records | Isolated definition loads passed on Julia 1.10.8 and 1.12.5 without research trees. No relocation, regeneration, dependency removal, or lazy loader. Reopen for changed dependencies/consumers or measured budget pressure |
| 4. M1-FREEZE — Resolve the study draft | Finite sensitivity cells, seed policy, estimands/thresholds, sampler/resource budget, all-attempt scorer, and reviewer handoff | No fresh evaluation while any freeze decision is open; no new generic controller or evidence framework without a demonstrated gap |

M0-DOC is a bounded documentation/layout change, not completion of all M0.
Physical relocation of research fixtures, large source-file decomposition,
and optional-dependency changes are separate tasks and are not bundled into it.
M0-BOUNDARY accepts the current compatibility-line placement, not minimum
startup cost or scientific validation. The next unfinished engineering decision
is the runtime attribution in order 2; do not restart the closed inventories.

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
- `9a4d180`: [CI 33955509722](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33955509722)
  passed all 12 ordinary jobs; two manual research jobs were skipped. The full
  Julia 1.10.8 job passed the same 90 testsets / 17,557 assertions in 31m28s.
  The updated medians below expose a runtime investigation, not a test failure.
- `04daa4d`, `a13399c`, and `27fb7d7`: [CI 33958936886](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33958936886),
  [CI 33960125413](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33960125413),
  and [CI 33961918446](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33961918446)
  each passed all 12 ordinary jobs; both manual research jobs were skipped.
  Their Julia 1.10.8 full jobs passed 90 testsets / 17,557 assertions in
  33m15s, 30m57s, and 22m24s, respectively. These are engineering observations,
  not fresh anchor-study replications or acceptance of a later revision.
- `46f8d92` added 951 MCMC-free assertions. Its focused file passed four
  testsets / 3,777 assertions on Julia 1.10.8 and 1.12.5, and a deliberately
  malformed paired control was detected. [CI 33963553257](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33963553257)
  passed all 12 ordinary jobs: `fitting_reports` passed 25 / 7,453 and the
  full Julia 1.10.8 job passed 91 / 18,508 in 30m14s. Both manual research
  jobs were skipped. This verifies that revision, not subsequent changes.
- `5f58701` added the [response-sharing draft](docs/internal/mfrm-anchor-study.md#m1-data-sharing-and-rng-ownership-draft)
  and 131 smoke assertions. The focused file passed five testsets / 3,908
  assertions on Julia 1.10.8 and 1.12.5. [CI 33964790537](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33964790537)
  passed all 12 ordinary jobs: `fitting_reports` passed 26 / 7,584 and the
  full Julia 1.10.8 job passed 92 / 18,639 in 30m54s. Both manual research
  jobs were skipped. These results do not accept a subsequent source revision.
- `8cd32ff` extended the [scoring draft](docs/internal/mfrm-anchor-study.md#m1-scoring-applicability-and-denominator-draft)
  with 50 assertions for applicability, primary-attempt denominators, and
  paired finite-subset comparisons. All six focused testsets / 3,958 assertions
  pass locally on Julia 1.10.8 and 1.12.5; two memory-only mistakes are detected.
  [CI 33965531472](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33965531472)
  passed all 12 ordinary jobs; the full Julia 1.10.8 job passed 93 / 18,689
  in 20m00s. Both manual research jobs were skipped.
- `8f9be52`'s [predictive-boundary check](docs/internal/mfrm-anchor-study.md#predictive-scoring-boundaries-checked)
  fixes a shared KL overflow for positive subnormal probabilities and adds
  16 scorer / 28 M1 assertions. Locally, all 56 scorer and 3,986 anchor checks
  pass on Julia 1.10.8 and 1.12.5; the old KL formula fails three regressions.
  Category alignment, event weights, mean-before-log, and a finite-log heldout
  route were checked. [CI 33966444116](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33966444116)
  passed all 12 ordinary jobs: `fitting_reports` passed 28 / 7,662,
  `generalized` 19 / 2,461, and the full Julia 1.10.8 job 94 / 18,733 in
  26m06s. Both manual research jobs were skipped.
- `49871e3`'s [all-category log integration](docs/internal/mfrm-anchor-study.md#all-category-log-input-and-integration)
  adds explicit log input to the existing scorer, retaining its default input
  and result schema. All 4,202 anchor and 103 scorer checks passed on both local
  Julia versions; two memory-only numerical mistakes were detected.
  [CI 33968517600](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33968517600)
  passed all 12 ordinary jobs: `fitting_reports` 29 / 7,878, `generalized`
  20 / 2,508, and the full Julia 1.10.8 job 96 / 18,996 in 26m00s. Both
  manual research jobs were skipped. This does not certify later changes.
- The current [independent log-truth check](docs/internal/mfrm-anchor-study.md#independent-log-truth-boundaries)
  extends the existing standalone primitive and feeds its logs into the
  24-scenario scoring check. No probability-kernel copy or export is added.
  The 277 new assertions bring the anchor file to 4,479; together with 103
  scorer and 2,168 unchanged LD assertions, 6,750 pass on Julia 1.10.8 and
  1.12.5. All 22 legacy LD raw outputs match the preceding revision within
  each environment; three memory-only numerical mistakes are detected.
  Candidate CI is required: expected totals are 30 / 8,155 in `fitting_reports`
  and 97 / 19,273 in the full suite. Other shards gain no assertions.
  Labelled truth persistence, the full attempt adapter, thresholds, and review
  remain open. No sampler, dependency, fixture, or evaluation replication is
  added; changed-workload timing medians do not close M0.
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

The following are complete successful jobs from attempt 1 of
[`33952439772`](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33952439772)
(`bd22c01`),
[`33953993916`](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33953993916)
(`fa7ffc9`), and
[`33955509722`](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33955509722)
(`9a4d180`), in that order. The review window ends at `9a4d180`; later
completions do not retroactively enter it. Current-Julia rows use Julia 1.12.7; the full-suite row
uses Julia 1.10.8. All logs agree on Ubuntu 24.04, runner image
`20260831.293.1`, and provisioner `20260828.587`. Testset names and per-set
assertion counts match exactly within every row. Only the root roadmap,
internal fixture inventory, and fixture README changed across these revisions;
workflow, package/test code, dependency declarations, examples, and published
manual sources did not change.

These are workload/image-matched operational windows, not hardware-matched
benchmarks: CPU models were not logged in those jobs. The later instrumentation
below demonstrates why an unchanged runner-image label is insufficient.

| Lane | Testsets / assertions | Three whole-job times | Median | Change from initial median |
| --- | --- | --- | --- | --- |
| `core` | 11 / 2,899 | 20m46s, 22m30s, 17m05s | 20m46s | 0.0% |
| `fitting_core` | 2 / 2,755 | 15m41s, 22m15s, 21m49s | 21m49s | +23.4% — investigate |
| `local_dependence_core` | 32 / 2,904 | 23m35s, 23m29s, 23m36s | 23m35s | 0.0% |
| `local_dependence_integrity` | 2 / 52 | 13m57s, 12m05s, 11m19s | 12m05s | -31.9% |
| `generalized` | 19 / 2,445 | 11m19s, 8m26s, 13m26s | 11m19s | -12.9% |
| `fitting_reports` | 24 / 6,502 | 20m37s, 21m08s, 20m18s | 20m37s | -1.7% |
| Full suite, Julia 1.10.8 | 90 / 17,557 | 30m17s, 29m56s, 31m28s | 30m17s | +1.2% |

Initial medians are retained in the
[roadmap at `0881fd4`](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/blob/0881fd4276d5e960152a627b378145f8a63b43ee/ROADMAP.md#comparable-ci-timings).
The windows overlap: percentage changes are monitoring triggers, not independent
estimates of an optimization or regression. Setup/cache variation is included;
queue time is excluded. No timing here measures sampler speed.

The `fitting_core` trigger is localized but **not explained**. All three jobs
restored their lane cache. Their test-command steps took 15m04s, 21m44s, and
21m10s; the 2,641-assertion fitting testset itself took 9m51.3s, 14m59.6s, and
14m29.8s. Thus job setup alone cannot explain the increase. The later
[`0881fd4` fit job](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33956618271/job/101280994109)
passed the same 2,755 assertions in 22m01s; its fitting testset took 14m42.6s.
This is follow-up evidence, not a replacement of the fixed window above.

Across all six fit jobs from `9668383` through `0881fd4`, the 187 logged
versioned package entries match, the PR target commit is `6e8291c`, and
`runtests.jl`, package sources, and the workflow are unchanged. Slow fitting
testsets (14m29.8s--14m59.6s) already occur at `9668383`, before the document
reorganization; the two faster observations are 9m23.5s and 9m51.3s. The gap
between the group announcement and the inferred testset start is about
378--381s in the slower jobs versus 273--292s in the faster ones. This gap is
not a pure import or compilation timer. Identical logged versions do not prove
identical binaries, hardware, or scheduling; cache restoration does not prove
zero compilation. Existing logs cannot attribute the two timing ranges.

The existing fitting block now uses Julia's `@time ... @eval begin ... end`
to include compilation of the large expression, while preserving both original
testset trees, seeds, draw counts, and assertions. Its CPU target and Julia/BLAS
thread counts are logged without changing them. Only the Linux `fitting_core`
command adds `lscpu`, `free --mebi`, and
[`/usr/bin/time -v`](https://www.gnu.org/software/time/manual/time.html)
around the unchanged `Pkg.test()` call. Treat CPU time, RSS, GC, and compilation
as command/block diagnostics, not sampler-only performance or a system-wide
memory bound. The extra evaluation boundary makes this an instrumented series:
do not claim a speedup by mixing it with uninstrumented timings. Accept an
explanation only when these observations support it; retain the trigger if
they do not. No dependency, sampler, threshold, or timeout changes are bundled
with this measurement.

Local verification on Julia 1.12.5/macOS passed both fitting testsets unchanged
(2,641 + 114 assertions). The timed block took 677.526s: 78.16% compilation,
1.26% GC, and 32.437 GiB cumulatively allocated, **not peak resident memory**.
The testset summaries alone were 9m07.8s and 4.4s and omit part of the enclosing
block cost. One 1-second native sample during that run found compilation frames
in all 72 observed main-thread stacks; sampling perturbed this diagnostic run.
This supports investigating compilation locally, not attributing the historical
CI increase or pooling local and Linux timings. All 11 inline testset expression
trees match before/after instrumentation; selection checks passed 45/45 on
Julia 1.10.8 and 1.12.5. The minimum-version timing/failure smoke and the four
stubbed Bash routing/exit-status cases passed. Native Linux resource reporting
was subsequently verified by the first instrumented CI observation below.

Three ordinary instrumented fit jobs passed the same 2,755 assertions. They use
Julia 1.12.7, the same Ubuntu image/provisioner, four exposed logical CPUs, one
Julia thread, and two BLAS threads, but **different CPU models and targets**.

| Revision / fit job | CPU model / Julia target | Whole job | `Pkg.test()` command | Timed block | Compilation | Reported max RSS |
| --- | --- | --- | --- | --- | --- | --- |
| [`04daa4d`](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33958936886/job/101287242614) | AMD EPYC 7763 / `znver3` | 22m36s | 1,317.54s | 1,121.871s | 80.45% | 2,555,816 KiB |
| [`a13399c`](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33960125413/job/101290451261) | AMD EPYC 9V74 / `znver4` | 17m42s | 1,026.77s | 895.140s | 83.45% | 2,671,352 KiB |
| [`27fb7d7`](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33961918446/job/101295159486) | Intel Xeon 6973P-C / `graniterapids` | 13m04s | 748.13s | 621.888s | 76.70% | 2,589,148 KiB |

The 180 extracted unique logged package/version entries match; all three PR merges
target `6e8291c`. Only the root roadmap and study draft changed between heads.
All restored their lane cache, but from different predecessor runs: cache
restoration does not establish identical effective precompilation. The first
two blocks report 679.74 million allocations / 31.977 GiB cumulative allocation;
the third reports 680.05 million / 31.992 GiB. These are not peak memory. GC
is 0.84% / 0.99% / 1.89%. Command user/system CPU times are 1,315.19/2.67s,
1,024.56/2.52s, and 745.73/2.29s; 99--100% CPU means about one CPU's capacity
on average, not saturation of all four. Reported max RSS is not simultaneous
process-tree memory; major page faults are zero and startup memory snapshots
are not run-long traces. Testset summaries exclude part of the enclosing
compilation-inclusive block cost. These successful runs precede the later
951-assertion M1 addition and do not verify that candidate.

The current observations are compilation-heavy and demonstrate runner
heterogeneity. They do **not** isolate the CPU's causal contribution, establish
a documentation-induced speedup, or identify the CPU of any older job. Those
older logs cannot support retrospective hardware stratification. Keep M0 open;
separate subsequent ordinary observations by CPU/target, version, and threads
before forming a comparable window or choosing a measured compilation remedy.
There is only one observation per CPU/target, not a three-run matched median.
Do not pool these observations into the original median, add research
execution, or inflate the timeout to close the trigger.

The remaining lanes use the same three runs, except macOS uses `fa7ffc9`,
`9a4d180`, and the completed macOS job of
[`33956618271`](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33956618271)
(`0881fd4`; attempt 1). That run's other jobs were still in progress at review;
this observation does not transfer a green result to its whole candidate.

| Lane | Matched check | Three whole-job times | Baseline median |
| --- | --- | --- | --- |
| macOS smoke | Same portable-package script, Julia 1.12.7 | 1m09s, 1m08s, 0m55s | 1m08s |
| Windows smoke | Same portable-package script, Julia 1.12.7 | 2m00s, 2m01s, 2m05s | 2m01s |
| Documentation | 19 public sources / 14 rendered HTML files | 3m26s, 3m59s, 0m58s | 3m26s |
| Experimental boundary | 2 testsets / 1,123 assertions, Julia 1.10.8 | 6m36s, 3m02s, 2m35s | 3m02s |
| Release hygiene | Same gate; Aqua 7 testsets / 10 assertions; 351 runtime-language surfaces | 18m29s, 18m20s, 13m13s | 18m20s |

Ubuntu versions match the first table; docs/hygiene use Julia 1.12.7,
Documenter 1.19.0, and Aqua 0.8.16 where applicable. Windows uses
`windows-2025-vs2026` image `20260824.214.3`, provisioner `20260819.586`.
The accepted macOS observations use `macos-26-arm64` image `20260728.0273.1`,
provisioner `20260707.563`; exclude `bd22c01`'s 1m05s because its image and
provisioner differ. Platform and experimental fits remain bounded engineering
smokes, not new scientific evaluation.

### Distribution phases and budget interpretation

The hygiene jobs above ran the same
[`distribution_archive_smoke.jl`](scripts/distribution_archive_smoke.jl).
Seconds below follow `bd22c01`, `fa7ffc9`, `9a4d180`; all observations passed.

| Phase | Three times (seconds) | Median (seconds) | Budget (seconds) |
| --- | --- | --- | --- |
| Assemble and inspect | 0.171, 0.143, 0.136 | 0.143 | 30 |
| Instantiate | 5.205, 4.657, 4.670 | 4.670 | 600 |
| First load | 15.419, 14.709, 12.174 | 14.709 | 300 |
| Warm load | 2.798, 2.580, 2.297 | 2.580 | 120 |
| Minimal fit | 33.062, 31.839, 26.043 | 31.839 | 300 |
| Manual build | 25.059, 22.853, 19.489 | 22.853 | 600 |

These are operational baselines across documented internal-text changes, not
a byte-fixed archive benchmark. Candidate inventories were 427 / 428 / 428
files and 27,959,685 / 27,970,739 / 27,976,891 bytes; compressed Git archives
were 3,176,414 / 3,180,291 / 3,182,326 bytes, all below 4 MiB. The assembly and
privacy scan therefore process slightly different text. Other commands and
published build inputs are unchanged. Each candidate is Git-free and excludes
ignored local outputs, but uses the runner's existing depot: neither
instantiate nor first load is a cold-depot measurement. The separately
[classified research records](docs/internal/fixture-boundary.md) remain shipped;
passing this smoke alone does not prove their removal or non-use. The separate
fixture review establishes which ordinary checks consume them and how.

Phase budgets are **post-completion elapsed-time checks**, not process-killing
timeouts. The hard cancellation boundary is the 30-minute hygiene CI job;
standalone local use has no equivalent outer deadline. Preserve this distinction
when interpreting the older archived wording. Existing job ceilings remain
35 minutes for core/experimental, 30 for the other current-Julia shards/hygiene,
20 for platforms/docs, and 75 for the minimum-version full suite. Every current-
Julia shard observation above meets the 30-minute T2 target; the full suite is
a separate T3 job, not a 30-minute shard. A target exceeded three consecutive
times requires splitting or reclassification. Baseline collection is complete;
the >20% fitting trigger still prevents runtime P0 acceptance.

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
250 KiB fixture-review threshold, phase elapsed-time gates, and CI job timeouts.
A size or timing exception needs a stated user benefit; do not inflate limits silently.
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
