# Fitting-core runtime review

Reviewed 2026-09-06, through `ad57606`. The [active roadmap](../../ROADMAP.md)
owns acceptance and priority. This is a bounded review of existing ordinary
CI logs, not a new benchmark, sampler-speed claim, or anchor-study evaluation.

## Window and comparison conditions

The table contains every ordinary `fitting_core` job in attempt 1 of CI runs
from the first instrumented revision `04daa4d` through the post-merge
`ad57606`, inclusive: 16 jobs, all successful, each with the same two
testsets and 2,641 + 114 = 2,755 assertions. Selection is by this fixed window,
not by duration. Later jobs do not retroactively enter it. For each PR job,
the checkout commit printed by the log was checked against the GitHub Git
commit API: its complete tree equals the table's head tree. Push jobs
checked out the named head directly.

All 16 use Julia 1.12.7, Ubuntu 24.04 image `20260831.293.1`, provisioner
`20260828.587`, four exposed logical CPUs, one Julia thread, and two BLAS
threads. CPU abbreviations below map to the logged model / Julia target:

- 7763: AMD EPYC 7763 / `znver3`.
- 9V74: AMD EPYC 9V74 / `znver4`.
- 6973P: Intel Xeon 6973P-C / `graniterapids`.
- 8370C: Intel Xeon Platinum 8370C / `icelake-server`.

[The workflow](../../.github/workflows/CI.yml), [Project.toml](../../Project.toml),
and [test/runtests.jl](../../test/runtests.jl) are byte-identical throughout.
The two changed test includes execute in other shards, not `fitting_core`.
However, two package files loaded by the module changed:
`src/mgmfrm_validation_scoring.jl` and
`src/local_dependence_known_truth_dgp.jl`. Identical test counts alone therefore
do not establish identical load/compilation work. Source groups in the table
are exact `src/` Git-tree groups:

| Group | Tree prefix | Revisions |
| --- | --- | --- |
| A | `d45578c` | `04daa4d`, `a13399c`, `27fb7d7`, `46f8d92`, `5f58701`, `8cd32ff` |
| B | `6d80183` | `8f9be52` |
| C | `48fcb4e` | `49871e3` |
| D | `742d2c2` | `bc36adc` |
| E | `2df67ad` | `fe80126`, `e8bc648` |
| F | `5495718` | `2f4f431`, `4b2c5a4` |
| G | `2b12e06` | `633551d`, `ac31b41`, `ad57606` |

The first 15 jobs have identical sets of 180 unique logged package/version
entries. At `ad57606`, the only set difference is `JSON 1.7.1 -> 1.8.0`
(UUID prefix `682c06a0`, **not JSON3**). The declaration file did not change.
Exclude that job from a version-matched aggregate; identical Git trees do
not imply an identical resolved environment. Logged versions also do not
prove identical native binaries or cache contents.

## Observations

Whole-job time excludes queueing but includes setup and cleanup. Command time
is the existing `/usr/bin/time -v` elapsed time around `Pkg.test()`; block time
is the existing `@time ... @eval` compilation-plus-execution measurement.
Precompile is the emitted dependency count / seconds before the block, inside
that command. “Not reported” is **not zero compilation**. Cache is the restored
key's producer run ID, always attempt 1, or an explicit cache miss.

| Head / source group | CPU | Whole job | Command (s) | Block (s) | Precompile count / s | Restored cache run |
| --- | --- | --- | --- | --- | --- | --- |
| [`04daa4d`](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33958936886/job/101287242614) / A | 7763 | 22m36s | 1317.54 | 1121.871 | not reported | 33957494879 |
| [`a13399c`](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33960125413/job/101290451261) / A | 9V74 | 17m42s | 1026.77 | 895.140 | not reported | 33958936886 |
| [`27fb7d7`](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33961918446/job/101295159486) / A | 6973P | 13m04s | 748.13 | 621.888 | not reported | 33960125413 |
| [`46f8d92`](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33963553257/job/101299544810) / A | 7763 | 21m55s | 1277.16 | 1080.518 | not reported | 33961918446 |
| [`5f58701`](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33964790537/job/101302899016) / A | 7763 | 22m29s | 1315.47 | 1118.525 | not reported | 33963553257 |
| [`8cd32ff`](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33965531472/job/101304867061) / A | 7763 | 21m52s | 1279.49 | 1082.455 | not reported | 33963553257 |
| [`8f9be52`](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33966444116/job/101307303933) / B | 7763 | 22m09s | 1290.93 | 1083.987 | 1 / 12 | 33964790537 |
| [`49871e3`](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33968517600/job/101312785443) / C | 6973P | 13m27s | 774.22 | 633.369 | 1 / 9 | 33966444116 |
| [`bc36adc`](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33970171857/job/101317153534) / D | 6973P | 13m28s | 774.02 | 637.584 | 1 / 9 | 33968517600 |
| [`fe80126`](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33971936154/job/101321871511) / E | 7763 | 22m52s | 1333.19 | 1120.697 | 1 / 12 | 33970171857 |
| [`e8bc648`](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33973332148/job/101325604311) / E | 6973P | 15m51s | 924.49 | 633.980 | 254 / 160 | miss |
| [`2f4f431`](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33973824420/job/101326917236) / F | 8370C | 20m02s | 1170.78 | 806.311 | 254 / 200 | miss |
| [`633551d`](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33975571567/job/101331544991) / G | 7763 | 25m53s | 1523.89 | 1102.309 | 254 / 223 | 33973332148 |
| [`4b2c5a4`](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33975699340/job/101331884995) / F | 7763 | 26m56s | 1582.55 | 1149.555 | 254 / 234 | 33973332148 |
| [`ac31b41`](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33975779252/job/101332093187) / G | 8370C | 20m59s | 1223.61 | 848.169 | 254 / 209 | 33973332148 |
| [`ad57606`](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33997276971/job/101389886698) / G | 7763 | 23m23s | 1375.14 | 1109.183 | 17 / 68 | 33975699340 |

Compilation is 76.70--83.45% of the enclosing block in these logs. This is
separate from the earlier package-precompile summaries, not sampler-only
execution, nor proof that restoring a package cache removes block compilation.

## Findings and limits

1. **A small hardware/source/version-matched reference now exists.** All four
   group-A / 7763 jobs (`04daa4d`, `46f8d92`, `5f58701`, `8cd32ff`)
   have whole-job times of 21m52s--22m36s, median **22m12s**, and block times
   of 1,080.518--1,121.871s, median **1,100.490s**. This is a descriptive
   four-job reference, not a fixed-host/cache benchmark or a before/after
   effect. Cache producers differ; group-A 9V74 and 6973P still have only
   one observation each. Do not pool all 16 into a single runtime median.

2. **Cache restoration is not effective precompile reuse.** `e8bc648` and
   `2f4f431` explicitly missed their caches. `633551d`, `4b2c5a4`, and
   `ac31b41` restored the same cache from the 6973P run `33973332148`,
   yet each precompiled 254 dependencies on 7763 or 8370C. Conversely, earlier
   cross-CPU restorations have no emitted precompile summary: a CPU change
   does not itself prove a rebuild.
   [GitHub's branch/PR cache isolation](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching#restrictions-for-accessing-a-cache)
   means a PR cache cannot automatically warm its base branch or another PR.
   [Julia's package-image documentation](https://docs.julialang.org/en/v1/devdocs/pkgimg/)
   describes heterogeneous-target caches and selection requirements for flags.
   These are relevant mechanisms, **not measured causes** of any particular
   cache miss or invalidation here; the logs do not record rejection reasons.

3. **One job-time change is localized outside the fitting block.** Group-G /
   7763 jobs `633551d -> ad57606` fall from 25m53s to 23m23s (150s), while
   the block increases by 6.874s. Command-minus-block decreases from 421.581s
   to 265.957s (155.624s); reported precompile time decreases from 223s to
   68s (155s). The bookkeeping locates almost all the reduction outside the
   block. That residual also contains other command work, and precompile
   summaries are rounded: this is not an exact additive profiler.
   Cache lineage and JSON version both differ, so it is neither a controlled
   cache treatment nor evidence of a JSON effect or sampler optimization.

4. **M0 runtime acceptance remains open.** The original uninstrumented
   17m41s -> 21m49s (+23.4%) trigger retains its original window. Its CPU
   identities cannot be recovered from those logs. This review establishes
   compilation-heavy work, runner heterogeneity, and variable preparation
   costs; it does not causally explain that historical increase. All 16
   observed jobs meet the existing 30-minute ceiling, but passing that ceiling
   alone does not close the trigger.

## Controlled comparison protocol

The diagnostic specifies **one ordered cold/warm pair**, not another pooled CI
window. Cold A ran; an observer failure stopped the pair before B (receipt below).
The macOS / Homebrew Julia 1.12.5 / Apple M4 Max host is explicitly separate
from Linux / Julia 1.12.7 CI.
The question is whether effective package-cache reuse changes preparation
cost while the compilation-inclusive test block remains expensive.

| Control | Fixed choice and verification |
| --- | --- |
| Source and workload | One temporary, Git-free copy of `ad57606`; identical package, test, script, and fixture bytes for both attempts. Preserve both fitting testsets, all 2,755 assertions, seeds, and draws. Only local diagnostic environment files may be added |
| Resolved environment | Prepare once, outside measurement; retain the root and effective test Project/Manifest files, preferences, exact Julia build, and package identities/versions/tree hashes. Include test-only ReverseDiff and its dependencies. Require `Pkg.test(; allow_reresolve=false)` and check the effective graph in each attempt, not only the root file |
| Process settings | Fresh Julia process each time; one default thread, zero interactive threads, one GC thread, two effective BLAS threads in the test and plan children, and `JULIA_NUM_PRECOMPILE_TASKS=2`. On this OpenMP host, set both `OPENBLAS_NUM_THREADS=2` and `OMP_NUM_THREADS=2`. Record the actual BLAS binary, native CPU target, and all subprocess flags; keep them fixed, including bounds checking |
| Depot isolation | A task-owned depot and restricted load path; no fallback to the user's compiled caches or global environment. Keep bundled Julia resources identical. Prepare packages/artifacts/registry data before measurement; do not update or download during the pair |
| Cold A | Start with no third-party compiled package cache in the task depot. This is not a cold OS page cache or a Julia build without bundled caches |
| Warm B | At the same source/depot paths, restore the prepared non-compiled baseline and reuse only the compiled cache produced by successful A. Do not reuse A's Julia process, draws, or fit-result files. A continuing precompile/rebuild in B is a result to retain, not a reason to silently retry |
| Resource bound | At most two measured commands, each with a 30-minute process-tree deadline; preparation capped at 15 minutes. Verify cancellation before starting. These diagnostic bounds do not change any ordinary CI timeout |

The standard [Pkg test API](https://pkgdocs.julialang.org/v1/api/#Pkg.test)
uses a separate test environment and a fresh process with bounds checking.
The Pkg source shipped with Julia 1.12.5 also resolves the merged test environment
when `allow_reresolve=false`; that option disallows its fallback re-resolution,
but cannot by itself freeze versions absent from the input manifests. Inspect the complete
test graph before accepting the pair. The existing plan subprocess additionally
activates the copied package root in
[generate_validation_plan.jl](../../scripts/generate_validation_plan.jl), so
locking only the test environment would miss that second resolution context.

Use [Julia's depot/load-path controls](https://docs.julialang.org/en/v1/manual/environment-variables/#JULIA_DEPOT_PATH)
with care: a task depot followed by `:` retains bundled resources but excludes
the default user depot; prepending the user depot as a fallback would also
expose its compiled caches. Inspect the expanded paths. Do not run
[distribution_archive_smoke.jl](../../scripts/distribution_archive_smoke.jl)
as the comparison controller: it performs additional fits/builds, inherits an
existing depot, and checks phase budgets only after completion. Its elapsed-time
checks are not the required hard deadline.

### Preflight result and execution gate

The initial MCMC-free local probe passed **12 checks** for isolated depot/load paths,
explicit Julia/BLAS thread settings, the existing `fitting_core` selector, and
rejection of invalid/research-enabled shard combinations. TOML inspection found
ReverseDiff absent from both the local Julia 1.12.5 root manifest and the tracked
Julia 1.10.8 manifest. Neither file was changed.

The native-path follow-up on **2026-09-06 JST** completed successfully in
**664.443 seconds (11m04s)**, within the 15-minute preparation cap. It used an
isolated copy of `ad57606`, Homebrew Julia 1.12.5 / bundled Pkg 1.12.1, offline
task-owned package/artifact/registry copies, and no user-depot fallback.

| No-fit check | Observed result |
| --- | --- |
| Complete environment | Root graph: 178 entries; native merged test graph: 180, including ReverseDiff 1.17.0. Saved the native test Project/Manifest, added the latter only to the temporary copy's `test/Manifest.toml`, and replayed `Pkg.test(; allow_reresolve=false)` with exact graph/project equality |
| Actual test child | Fresh native `Pkg.test()` child loaded the package and test dependencies: Julia default/interactive 1/0, GC 1, BLAS 2; effective graph and shard selector matched |
| Actual plan child | The existing plan script ran with `--help`, after a startup check of its root activation: the same effective thread counts, isolated depot, and root graph; no plan generation or fit |
| Cancellation | Stdlib deadline self-check covered success, nonzero exit, and timeout of a parent/child pair that ignored SIGTERM. Both stopped. The preparation Julia, native test child, observed precompiler, and plan child shared the owned process group |
| Integrity and scope | All tracked copied source bytes and the prepared root manifest were unchanged. The startup hook exited before the original `test/runtests.jl`; no fitting testset or scientific evaluation ran |

The one-off environment capture uses the audited private `test_fn` hook in
**Pkg 1.12.1**, guarded by exact Julia/Pkg version assertions; it is not a public
package API or a portable new runner. Deadline handling uses Python stdlib
[`start_new_session` / timeout waiting](https://docs.python.org/3/library/subprocess.html)
and [`os.killpg`](https://docs.python.org/3/library/os.html#os.killpg), including
group cleanup on exit. Its ceiling is an owned POSIX process group, not arbitrary
daemonizing descendants; the observed Julia path remained in that group.

The earlier negative BLAS probe (`OPENBLAS_NUM_THREADS=2` alone yielded 14)
now has a local explanation: the loaded ILP64 OpenBLAS **0.3.32** binary reports
parallel mode **2 (OpenMP)**. This build uses `OMP_NUM_THREADS`, as documented by
[OpenBLAS](https://www.openmathlib.org/OpenBLAS/docs/runtime_variables/).
Both variables set to two produced BLAS 2 in the actual children without a
parent-only setter. Keep the OpenMP setting fixed too: it can affect other
OpenMP code. The manifest labels OpenBLAS_jll **0.3.29+0**, so record the loaded
binary as well as the dependency graph. This does not explain the historical
CI regression or invalidate its thread logs.

**The no-fit preflight passed; its success was not a pass of the 2,755 assertions.**
It used `JULIA_PKG_PRECOMPILE_AUTO=0` only to suppress Pkg's automatic preparation
pass; import-time compilation still occurred. A later used `1`, with the no-fit
exit hook removed. Retain the earlier failures separately from the measured
attempt below; preflight cache contents are not eligible as cold input.

### Cold A result and observer stop

On **2026-09-06 JST**, cold A ran once against the same `ad57606` source and
frozen root/test environments. The preflight cache was moved aside, not deleted;
the initial task depot had no compiled cache. Source bytes matched a fresh Git
archive plus the two diagnostic manifests. Non-compiled source/depot snapshots
were retained for B, but **restoration and B were not executed**.

The initial depot `diff` emitted directory-loop warnings for macOS framework
symlinks despite returning zero. A checksum-based `rsync` **dry run**, comparing
links rather than following them, found no content/link/entry differences.
The 664.443s environment preflight, 56.311s snapshot step, and 59.042s link-aware
check total **779.796s**, within the 900s preparation allowance; these are
executed preparation-command times, not elapsed time between conversation turns.
No preparation job or measured attempt was silently restarted.

| Cold A observation | Retained result |
| --- | --- |
| Native tests | `minimal Bayesian MFRM fitting`: 2,641 / 2,641; `scalar validation analytic gradient`: 114 / 114; all 2,755 passed |
| Command elapsed | `/usr/bin/time`: 1,505.55s; deadline wrapper: 1,505.555s, no timeout; approximately 25m06s |
| Existing compilation-inclusive block | 888.559782s; reported compilation 80.69%, GC 1.76%; 32.421 GiB allocated, not resident memory |
| Command minus block | 616.990218s; includes other command work, not a sampler-only measurement |
| Emitted precompile summaries | 26 dependencies / 92s and 292 / 364s; rounded summaries, not counts of unique packages or a complete additive profiler |
| Integrity and controls | Native test graph matched all 180 frozen entries; source and both manifests remained byte-identical after tests. Actual test command retained bounds checking, Julia threads 1/0 and GC 1; the test log reported BLAS 2 |
| Overall command outcome | Julia tests and final integrity checks succeeded, then `time -l` failed: `sysctl kern.clockrate: Operation not permitted`; outer exit **1**, no surviving owned-group process |
| Warm B / inference | Not run. No cache-reuse effect, speedup, or complete pair is available |

The 24-dependency "different versions currently loaded" warning is retained.
The local Julia precompiler increments that warning count for an already-loaded
module that it recompiles; the text alone is not evidence of dependency-version
drift. All 178 shared root/test package UUIDs, versions, and source hashes match;
the extra test entries are ReverseDiff and StaticArrays. A direct dictionary
comparison was too strict because the manifests encode local paths and weak
dependencies differently; path/UUID-aware checks confirmed their equivalence.
Each environment also matched its own frozen representation exactly during A.

The observer failure reproduced without fitting: sandboxed `time -l true`
returned 1, ordinary `time true` returned 0, and `time -l true` with approved
unsandboxed read access returned 0. Thus the failure belongs to the local
resource observer, not the model tests. The complete `time -l` resource report
is unavailable; later probes do not fill it in retroactively. The existing
warm-launch guard requires a successful **outer command**, so B stayed closed.
Do not relabel A as an entirely successful measurement or rerun it automatically.

Next, review using the existing deadline elapsed time and plain `time` instead
of `-l`; require an exact launch-context no-fit observer check before any further
measurement. Another fit needs a reviewed attempt-budget decision, not a reset
of this pair. No package, sampler, test, dependency declaration, or CI change is
indicated by this permission failure. The temporary raw A log is retained with
SHA-256 `fa92aac05ce66064f8b885119fa6a72bd28ac7345987f4d4f16f965ab030fbc8`.

### Observer correction and verification scope

The subsequent request to investigate and repair the measurement failure
authorizes local implementation and regression verification, not a reset of
the failed pair or closure of the historical runtime trigger. Cold A and the
unexecuted B remain unchanged. The correction is the small POSIX
[measurement guard](../../scripts/measure_command.py), reusing the temporary
deadline's monotonic clock and owned-process-group cleanup. Invoke it directly
around the command, without `time -l` or another resource-reporting wrapper.

The failure reproduces without Julia: in the same sandbox, `time -l true`
returns 1 and `time -l sh -c 'exit 7'` also returns 1; plain `time` preserves
0 and 7 respectively. Apple's [published time implementation](https://github.com/apple-oss-distributions/shell_cmds/blob/main/time/time.c)
waits for the child, prints elapsed/CPU time, then calls `getstathz()` for `-l`.
Its denied `kern.clockrate` query calls `err(1, ...)` before returning the
child's status. This matches the observed error; it does not establish the
exact source revision of the installed macOS binary. The missing exact-wrapper
permission preflight allowed this observer failure to surface only after A.

Required local measurements are now monotonic elapsed seconds, the direct
child's raw return code, and the guard's outcome/exit code. A completed command
with child exit 124 is distinguishable from a guard timeout; launch, cleanup,
and cancellation failures cannot become successful tests. Elapsed includes
launch, wait, and cleanup, not just fitting; no maximum RSS or resource-counter
report is claimed. [Python's monotonic clock](https://docs.python.org/3/library/time.html#time.monotonic)
does not depend on wall-clock adjustments. The guard preserves argv, inherited
environment, stdout/stderr, and the 1,800-second upper bound; it adds no package
dependency, cache policy, sampler change, or automatic retry.

Before a fit, run `python3 scripts/measure_command.py --self-test` in the same
permission context, then run the native no-fit launch with that guard. The
self-test covers actual subprocess outcomes, invalid bounds, launch failures,
SIGINT/SIGTERM/SIGHUP cancellation, timeouts, and parent/child cleanup, including
a child left by a normally exiting parent. Controlled workers keep an inherited
pipe open until exit, so EOF checks cleanup without requiring sandbox-sensitive
`ps`. The same check is
wired into the existing Linux hygiene and macOS smoke jobs; it is not a Windows
runner or a dependency of Julia package loading. Containment remains an owned
POSIX group: deliberately detached descendants and a guard killed by SIGKILL
or another unhandled fatal signal require OS-level supervision, not an assertion
of full tree safety.

Verification C is limited to **one additional ordinary fitting command**,
with the existing 30-minute deadline and all 2,755 assertions unchanged, after
the no-fit gate passes. It uses the retained isolated `ad57606` source and
frozen root/test environments; these package/test bytes also match the current
worktree. Retained caches may be reused and warmed by preflight. C is therefore
an integration check of the repaired observer, **not warm B**, a fresh cold/warm
pair, a controlled cache effect, or a scientific evaluation. No baseline restore,
retry, shared-depot change, CI timeout increase, or external publication is
part of this verification. Retain failure and stop if C does not pass.

The first corrected-guard native preflight failed in **22.647311s**, before any
fit, and correctly retained child/outer exit 1. The old unconditional `--load`
no-fit hook was also applied to Pkg's auto-precompile cache-flags probe when
`JULIA_PKG_PRECOMPILE_AUTO=1`; its diagnostic text reached a stdout channel that
Pkg parses as an integer. The earlier preflight had used auto-precompile 0.
This is a preflight-hook defect, not a model failure or an observer-status
regression. The corrected one-off hook is guarded by the exact Julia/Pkg build
and native test payload: it leaves cache-flags/compile workers untouched, exits
only before the intended test payload, and rejects unexpected commands. The
second native preflight passed in **23.509134s**, with auto-precompile still 1,
the native test and plan children in the owned group, effective graph/thread
checks passed, and all copied source/manifest bytes unchanged. Neither preflight
ran fitting assertions. Both outcomes are retained; together they used 46.156445s
of the 900s no-fit preparation allowance. The guard's standalone self-test now
also injects a cleanup-observer failure, retaining child exit 7 separately from
observer exit 125.

The unchanged baseline revision `a916346` has now completed
[CI 34004236027](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/34004236027):
all 12 ordinary jobs succeeded and both manual research jobs were skipped.
That baseline result does not validate this guard or its new CI steps;
candidate CI and review remain required before integration.

### Verification C result

On **2026-09-06 JST**, C ran once under the new guard, without sandbox escalation
or an external timer. The launch was `python3 scripts/measure_command.py 1800 --
/bin/bash <task>/launch.sh --verify`; the task-local launcher retained the
environment controls above and invoked the unchanged original `measure.jl`.
The guard reported **1,237.862374s (20m38s)**, `status=completed`, `child_exit=0`,
and `exit=0`. The native testsets passed **2,641 + 114 = 2,755 assertions**.
Final source/manifest checks passed, and a separate directory comparison matched
the retained pre-A source baseline. An approved read-only post-run process check
found no remaining member of C's owned group; that inspection is not a required
permission of the guard itself.

The compilation-inclusive block was **1,033.745311s**, with reported compilation
77.13%, GC 1.12%, and 32.421 GiB cumulatively allocated, not maximum RSS.
No package-precompile summary was emitted; this is not zero compilation.
These observations establish a successful end-to-end measurement, not a speedup,
a completed cold/warm pair, or an explanation of the historical CI trigger.
The 21-case guard self-test passed with local Python **3.9.6 and 3.14.3**;
the native preflight also preserved the cache-flags reply and rejected an
unexpected payload before execution. No package dependency or scientific
test assertion was changed. There is no further fit queued for this repair.

The temporary `verification-C.log` has SHA-256
`ab2439a860c67c4b7fef6e0ed4ab6dc39c9213a1d1a4d0f2f1a11b93d5f98cb9`;
the executed guard has SHA-256
`e7418fa37b665c6eb9c361e9f83fc2c16e2608fccb71f82fabbc778ae78d6ae4`.
Both earlier preflight outcomes and the cold A receipt remain retained.

### Interpretation and stop rule

Record command elapsed time, block time/compilation/GC, emitted precompile
count/time, resource diagnostics, and both testset results for every attempt.
Compare command-minus-block separately from block time. An absent precompile
summary is not zero JIT compilation. A version/source/thread mismatch, timeout,
or test failure makes the pair incomplete: retain it and stop, with no automatic
retry or replacement observation. Never reinterpret a timeout as a completed
30-minute measurement.

A then B has order/page-cache/host-load confounding and only one observation
per condition. It can locate work and expose failed cache reuse; it cannot
estimate a causal speedup, establish a median, identify an optimal cache policy,
explain the older CPU identities, or close M0. If verified reuse reduces only
preparation, the next engineering target is the separately timed compilation
block; if reuse fails, inspect that failure before proposing a cache change.
Either result needs review before further repetitions or implementation.
Through cold A, no profiler framework, package/CI change, cache deletion, manual
dispatch, or scientific evaluation was introduced. The correction above adds
only the local guard and its no-fit CI checks, not a change to the measured Linux
fitting command. The fixed 16-job window and the M1 independent-review gate
remain intact; neither the observer stop nor its repair closes M0 or authorizes
another cold/warm pair.
