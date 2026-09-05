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

## Next decision

Stop broad log collection for this window. The next useful comparison should
hold the current source, resolved environment, CPU/target, and threads fixed,
and explicitly distinguish effective package-cache reuse from timed-block
compilation. Choose that bounded comparison before modifying cache settings or
compilation structure; do not infer the effect from cross-runner job totals.
No profiler framework, dependency pin, sampler change, timeout increase, cache
deletion, rerun/dispatch, or fresh fit/evaluation was introduced by this review.
The historical timing windows and the M1 independent-review gate remain intact.
