# BayesianMGMFRM.jl — Internal Roadmap

Current decisions reviewed 2026-10-11; the 2026-09-21 assessment of checkout
`9cf42fc` and subsequent dated evidence remain below. The current
position is **working implementations with substantial numerical checks, before
target-specific statistical acceptance**. The near-term finish is a declared
MGMFRM domain that completes the Julia workflow, matching CmdStan checks,
statistical validation and independent/user review. The broader model catalogue
remains the long-term direction; neither completion of the fixed-coefficient
MFRM reference nor an application alone completes that objective. See the
[progress assessment and decision sequence](#decision-handoff-and-progress-accounting).
The [completion milestones](#completion-milestones) define the current finish,
its evidence and dependencies. They supersede historical M0–M3 scheduling below;
those records retain their evidence and any separate release holds.

## Current decisions

**2026-10-11 MS2 closed; the Julia baseline is retained.** The
[final closeout and implementation/N decision](results/workflows/20261011-foundation-efficiency-01/closeout.json)
and [full comparison summary](results/workflows/20261011-foundation-efficiency-01/summary-002.json)
account for **all 32 planned attempts: 31 completed and numerically qualified,
one external storage interruption**. Fifteen of the sixteen planned backend
pairs are complete. No candidate is adopted: complete posterior precision and
uncontaminated cost evidence are not established. This closes the finite
comparison, not scientific acceptance or the full foundation.

The original [launch record](results/workflows/20261011-foundation-efficiency-launch.json)
binds plan SHA256 `3b98dacdb8ed40166ea026f661576bc60eb198465209bb8874302af836234f87`
and 1,980 source/evidence files. Its worker/controller checks (106 saved-draw
checks and eight controller tests), all-eight-target native mathematics and
original design receipts remain valid; no successful sampler or suite was
repeated. The declared 32 attempts used four chains with 1,000 warmup and 1,000
retained iterations, serial fits/chains/threads, the original coordinates and
controls, an 8 GiB RSS limit, a 5 GiB disk reserve and no elapsed-time cutoff.

**Storage interruption and continuation.** Session 001 reached 28 completed
fits; the disk guard stopped attempt 29 (`B002-R0-050-F2`, Julia, repetition 2)
when free space fell below 5 GiB. Cleanup left no observed live workers. After
the user freed space, measured availability was 11.25 GiB, exceeding the 5.85 GiB
projection (the 5 GiB reserve plus twice the observed maximum output sizes for
the remaining fits). Session 002 executed only never-started attempts 30–32.
Attempt 29 was retained as interrupted; no seed, sample count, case or outcome
was replaced. All 32 terminal records were then moved, without overwriting,
from local staging to the [result directory](results/workflows/20261011-foundation-efficiency-01/archive.json).
Both session logs, resource traces and partial-attempt identities are preserved.
The incomplete pair retains all 1,172 unavailable comparisons in the denominator.

**Final precision result.** All **17,520 evaluated posterior difference screens**
and **60/60 prediction comparisons** pass. Nevertheless, **0/15 completed pairs**
meet every posterior precision requirement. Passing a difference screen means
that a difference was not detected at the declared multiplier; it does not by
itself establish adequate agreement precision. Across the 15 pairs:

| Statistic | All posterior screens pass / 4,380 | MCSE screen pass / 4,380 | Resolution screen pass / 4,380 |
| --- | ---: | ---: | ---: |
| Mean | 4,374 | 4,380 | 4,374 |
| SD | 4,346 | 4,364 | 4,346 |
| 5% quantile | 1,784 | 3,117 | 1,810 |
| 95% quantile | 1,931 | 3,176 | 1,947 |

Thus 12,435/17,520 posterior summaries pass all screens; 5,085 remain unresolved.
The shortfall mainly concerns interval endpoints but includes six mean rows:
the I4 loading in `B002-R1-050-F5/R1` and I2 loading in `B003-R0-100-F3/R2`, each
represented by a raw log loading, its duplicate named log loading and a positive
loading. The declared 292-row roster includes duplicates and is not a count of
independent estimands. The original 18,752-comparison multiplier (4.6949758485),
per-backend MCSE limit of 0.05 posterior SD, and combined difference-plus-error
bound of 0.3 posterior SD remain unchanged. Tail MCSE shortfalls occur on both
backends; this result does not identify a Stan-specific discrepancy or prove
full distributional equality. Earlier `pair-preview-001` through `005` receipts
remain in the result directory as dated intermediate evidence.

**Cost interpretation.** Twenty-eight of 31 completed fits triggered the frozen
external-workload rule, and every completed pair has a cost flag. The balanced
first-repetition Stan/Julia geometric elapsed and CPU ratios are approximately
0.207 and 0.206, descriptively; second-repetition aggregate ratios are unavailable
because of the interrupted pair. Neither supports speed-based adoption. All
original costs are retained, including attempt 28's 2,452.28 elapsed versus
338.91 CPU seconds; the specific cause of that discrepancy is unestablished.
Julia `time_ns` fit intervals and Python `monotonic` controller intervals are
separate recorded clocks, so summed fit elapsed times need not match session
intervals and must not be added to them. Session CPU totals include interrupted
work and controller/startup costs; the interrupted attempt's own total is
unavailable, not zero. Peak observed worker-tree RSS was 3,865,903,104 bytes.
The reused native build-plus-preflight cost remains 35.69 seconds, not a
separately measured pure compilation cost.

The [closeout validator](scripts/mgmfrm_foundation_efficiency_closeout.py)
checked the complete denominator, final cleanup, source/result references,
all 518 retained source/environment identities, and independently recalculated
17,520 posterior screen decisions from the saved summaries. It reused the
controller's complete output/source integrity checks and the passing MS1
closeout. This is an implementer's arithmetic/integrity check, not MS6 independent
scientific review. No posterior fits were generated by the closeout.

**MS3 N is now selected: 32 fresh independent paired blocks / 960 planned fits.**
The same closeout binds the retained AdvancedHMC implementation, Julia 1.12.5,
ForwardDiff Chunk 12, coordinate/control/environment identities, and the validated
pilot continuation summary. The unchanged six-mean/seven-contrast rule gives
128 / 32 / 32 blocks for replication-SE targets 0.005 / 0.01 / 0.02 nat;
0.01 selects 32. Pilot or benchmark blocks do not enter the fresh denominator.
This is point-estimate planning, not guaranteed precision or a calibration claim.
The subsequent main preparation and launch below consume the validated pilot
continuation and this decision. The old `select-main`/`prepare-main` path still
reads the pilot root's interrupted summary and must not be used for this run;
its historical sources and receipts are preserved.

**2026-10-11 MS3 plan frozen and main execution started.** The
[preparation record](results/workflows/20261011-foundation-prediction-main-01/preparation.json)
and [launch record](results/workflows/20261011-foundation-prediction-main-01/launch.json)
bind plan SHA256 `dba97753c0319c8355937ef6c03a72ff2c72560bac0667218389e83a2b04eb3e`,
526 source/environment files, **32 fresh paired R0/R1 blocks, 64 input data sets
and 960 training targets**. All input/target/heldout identities, complete five-fold
partitions and training-facet support were checked before sampling. The existing
Julia binding code also checks Python-generated probabilities against its own
formula. Person, response, split and MCMC seed namespaces are disjoint from the
recovery assessment, prediction pilot and MS2; no old block adds main-study credit.
The original prospective main seed namespace (20261008090000) is retained.

The new [main controller](scripts/mgmfrm_foundation_prediction_main.py) and
[worker entry point](scripts/run_mgmfrm_foundation_prediction_main.jl) reuse the
frozen generator, actual Julia `attempt` implementation, diagnostics, scoring,
panel aggregation and six-mean/seven-contrast summaries. They add the validated
handoff, continuation inventory and monitored scheduling. All original controls,
qualification rules, metric definitions, MCSE/stability screens, missing-panel
rules and numerical thresholds remain unchanged. This is the independent-2D,
fixed-Q normalized-C prediction study, not cross-family model selection or SBC.

[Execution checks](results/workflows/20261011-main-execution-check-01/verification.json)
passed nine Python tests and 21 Julia checks, with zero MCMC fits. They cover
rejection of stale/unclosed/changed handoffs, seed namespaces, complete/failed/
unstarted separation, saved-draw recovery holds, storage admission, controlled
supervisor transitions, exact Julia runtime identity and finite worker assignment.
The Julia check took 27.29 seconds including startup and peaked at 1,189,675,008
bytes observed RSS. A replay of one saved R0/R1 pilot pair under Python 3.14.3
reproduced Python 3.10.2's truth, observations, IDs and generating probabilities
exactly after the original JSON serialization convention. This replay contributes
zero independent blocks. Existing sampler/diagnostic/resource checks were reused;
these focused checks are not a full package suite or independent scientific review.

Main preparation then generated and checked every prospective target in 96.06
seconds, with 1,547,042,816 bytes peak observed descendant RSS and zero posterior
fits. The separate run command started the real controller, supervisor and first
Julia worker; its runtime/environment receipt matches the retained baseline.
The [first actual main-fit check](results/workflows/20261011-foundation-prediction-main-01/runs/001/first-fit-check.json)
now verifies `B001-R0-025-F1`: all four chains completed 2,000 transitions, saved
samples were reloaded and checked, original geometry/primary-score gates passed,
and all four globally weighted heldout scores were independently reconstructed
from the saved probabilities. This check added no fit. Both real worker runtime
identities match the retained baseline. One completed fold is not a complete
five-fold panel or a block-level precision result. The main study is **running,
not completed or statistically accepted**.

The original admission threshold is at least 12 GiB free space for an 8 GiB
output budget; measured launch space exceeded it. Execution retains 8 GiB total
worker-tree RSS, an 8 GiB study-output limit, a 5 GiB disk reserve, Julia/BLAS one
thread, and no elapsed-time cutoff. One worker starts first. A second is permitted
only after the first new fit completes, observed first-worker RSS is at most
3,500 MiB, and available memory is at least 5 GiB; otherwise the two fixed block
assignments run serially. The recorded first-fit decision permitted two workers:
first-worker peak RSS was 2,736,668,672 bytes and available memory 9,159,376,896
bytes. Worker 1 continued to `B001-R0-025-F2`; worker 2 started `B002-R0-025-F1`.
The supervisor polls disk space every second, and the
existing guard owns/cleans up descendant processes, including separate groups.
Polling cannot reserve host storage against sudden external consumption.

Only never-started IDs are eligible for continuation. An interrupted unsaved fit
is retained with unknown attempt costs, not retried. Completed saved stages remain
untouched; saved draws or a non-sampling error require integrity-checked recovery
or investigation before continuation. Recovery can reuse the existing saved-draw
review path without new sampling; it is not silently treated as a completed fit.
All original records and per-session guards/logs are append-only. Preserve this
source snapshot during the run and keep API work in isolated candidates.

The current commands are `python3 -B scripts/mgmfrm_foundation_prediction_main.py
check results/workflows/20261011-foundation-prediction-main-01` for prelaunch or
continuation-eligibility checks; a running or unresolved started fit is deliberately
rejected by that command. Use the same command with `run` only for an eligible continuation.
A controller lock rejects concurrent launches. Per-session results live under
`runs/NNN`; an uncompleted cohort remains MS3 work, irrespective of partial scores.

### Model choice, design simulation and higher-dimensional correlation

**2026-10-11 user-directed review and mathematical prototype.** Choosing MFRM,
GMFRM or MGMFRM, choosing dimensionality, and planning rating collection are
user tasks in their own right. MS2 compares implementations of one target;
the current six-condition foundation prediction study compares generating
conditions/prior widths within its declared 2D model. Neither completes the
cross-family or dimensionality-selection task. The following work refines the
MS5 user workflow and starts the requested correlation mathematics without
changing any frozen study or making a new simulation campaign mandatory.

**Priority review, following the user's 2026-10-11 clarification.** Judge work
by whether it removes a barrier to a defensible end-to-end user analysis, its
dependencies and reuse, the remaining uncertainty, and its full verification
cost. Completing more functions/tests or extending dimensionality is not itself
the objective. MS2 is now closed with the baseline retained, and the fixed MS3 main is running.
Preserve its roster and implementation, account for failures and achieved precision,
and do not add optimization or reruns to obtain a pass; preserve the MS3/MS4 sequence. Alongside that sequence, prioritize the common model/prediction,
diagnostic and comparison contracts needed by both model choice and design
simulation. Build the design runner on those shared capabilities rather than
duplicating model-specific pipelines. Keep LKJ work bounded to its declared
mathematical/native-check step before scheduling a higher-dimensional fit
campaign; that extension is not a prerequisite for completing already-supported
user workflows. Reassess this ordering when evidence or dependencies change,
including validity defects that affect the supported core. Record consequential
changes here with their reason; do not add a competing roadmap or new studies
merely because a local subproblem is technically interesting.

**Model comparison is partially implemented, not a finished selection workflow.**
The [existing comparison](src/bayesian_fit.jl) accepts `MFRMFit`, `GMFRMFit` and
`MGMFRMFit`, returns WAIC/LOO scores and paired pointwise ELPD-difference SEs, and
requires identical data/order/categories/dimensions/Q. Explicit
`sensitivity_comparison(...; axis=:dimensions)` already permits dimensionality
and Q changes while retaining the observation contract. These are real
computational paths; different dimensions do not inherently prevent predictive
comparison. The ordinary comparison guard is not a mathematical prohibition.
`relative_weight` is a normalized exponential ELPD weight, not posterior model
probability or stacking. The Hill-based `psis_loo` is not reference-validated
PSIS, and its importance ESS does not account for MCMC autocorrelation.

Model family, dimensionality and covariance are separate axes. A fixed-coefficient
multidimensional MFRM is already representable; MGMFRM is not the only way to
introduce multiple abilities. Present the fixed versus estimated item/rater
coefficients, D/Q and covariance explicitly in the user-facing candidate roster.
The [eight-type adapter inventory](docs/internal/prediction-contract-four-facet-design.md#8-ms5のapi対応表と統合順序2026-10-09)
already provides shared observed-row predictions and criterion calculation;
normalized/correlated/fixed-coefficient result types remain outside the released
comparison/refit dispatch. The isolated comparison candidate below now connects
their saved predictions, but does not add common refitting. General heldout refitting, cluster-appropriate SEs,
new-level integration and a model-selection operating-characteristic study
are not established by those adapter checks. MS5 should deliver a declared
candidate set varying fixed/estimated coefficients, D/Q and supported
correlation structure, with one observation/category/split/weight/prediction
contract, warning propagation and explicit unresolved comparisons. Preserve
current callers; do not merely remove dimensionality/Q guards or extend a union.
Use existing exact/K-fold machinery for supported known-level targets and
validate reference PSIS separately. The prediction unit must match the intended
use: an omitted rating at known levels and an entirely new person/rater/task
are different targets ([loo FAQ](https://mc-stan.org/loo/articles/online-only/faq.html)).
Predictive rank alone neither validates a construct nor establishes interval
calibration. Across-dimensional ability vectors require named common estimands,
not component-wise comparisons of differently defined coordinates.

**2026-10-11 isolated common-comparison API candidate verified.** The
[candidate snapshot and receipt](results/workflows/20261011-common-comparison-candidate-01/verification.json)
connect the existing eight-type prediction adapter to qualified package APIs
`BayesianMGMFRM.prediction_observations`, `observation_alignment`,
`prediction_criteria` and `compare_predictions`. The adapter's numerical body
is unchanged apart from its module alias and versioned schema names. Only the
candidate package entry point gains includes; the active source tree, original
exports, legacy comparison semantics, dependencies and fit-cache formats remain
unchanged. The snapshot and [reviewable patch](results/workflows/20261011-common-comparison-candidate-01/candidate.patch)
are archived separately while MS2 uses its frozen source.

The comparison requires an explicit model/dimensions/Q axis, checks the same
training outcomes/categories/conditioning and persistent rating IDs, aligns
permuted rows, and uses every original retained draw and chain. It retains input
order, a named baseline, model/prior/scale/correlation metadata, sampling and
criterion warnings, and affected observation IDs. Different draw counts and
dimensions are supported under the declared contract. It returns ELPD differences
without selecting a winner or generating model probabilities. Difference SE is
missing by default; optional rating/person-unit SE explicitly assumes exchangeable
units. Person aggregation is not a general crossed-rater/item correction, and
neither SE is MCMC MCSE or independent-replication uncertainty. The Hill smoother
remains explicitly non-reference-validated; no new PSIS claim is made.

[All 113 focused checks passed](results/workflows/20261011-common-comparison-candidate-01/check-01/verification.toml):
analytic scores and paired SEs, all eight concrete fit types including both
exchangeable variants, D1/D2/D3 and Q comparisons, legacy behavior, mismatched
data/draw rejection, warning propagation, and MFRM/GMFRM/normalized/correlated
save/reload. The [saved-fit example](results/workflows/20261011-common-comparison-candidate-01/candidate/examples/saved_model_comparison.jl)
reproduces comparisons using qualified public calls without private helpers or
manual draw reshaping. The [Japanese guide](results/workflows/20261011-common-comparison-candidate-01/candidate/docs/src/common_prediction_comparison.md)
and docstrings state settings, output meaning, assumptions, unsupported targets
and prototype-schema migration. Validation took 157.69 seconds including startup,
with 1,344,897,024 bytes peak observed descendant RSS and **zero new posterior
fits**. It overlapped MS2 attempt 16 and is not isolated cost evidence. All 518
MS2-bound source/environment file hashes remained unchanged, and archive hashes
were checked after relocation; successful numerical tests were not repeated.

This completes the saved-prediction comparison slice, **not MS5 as a whole**.
Common refit/K-fold dispatch, end-to-end fit/diagnostic/MCSE/figure integration,
reference PSIS validation and final scientific scope/review remain open. The
candidate is not merged or released. Design simulation can reuse this comparison
contract, but no SBC/recovery or model-selection operating-characteristic study
is implied by these synthetic API checks. With MS2 now closed, the priority is
MS3 execution/accounting and the usable common workflow, before a separate design or
higher-dimensional fit campaign.

**2026-10-11 recorded MGMFRM report integration verified.** Review of the actual
workflow evidence found that normalized fitting, diagnostics/MCSE, caching and
figures already have the bounded public walkthrough and 3,835 selected checks
per historical Julia version in foundation §§15–16. Do not describe those
operations as unimplemented or rerun their samplers to verify the new comparison
consumer. The concrete gap was that recorded normalized/correlated MGMFRM reports
still marked WAIC/LOO unsupported even though the isolated common API could compute
them. The [new candidate](results/workflows/20261011-common-report-candidate-01/verification.json)
extends the previous snapshot at that boundary; it remains isolated and unreleased.

`fit_report` and `save_fit_report_bundle` for those two result types now accept
explicit `include_waic` / `include_loo` requests with persistent dataset/rating IDs.
Unrequested sections are `not_requested`; old saved `unsupported` sections remain
readable. The LOO report is raw importance sampling, not validated PSIS. Criteria
use all original draws independently of a posterior-prediction/plot subset.
Public JSON, Markdown, tables and reopened bundles retain score and MCMC warnings,
rating IDs, interpretation and uncertainty limits. User-provided IDs survive the
prose filter unchanged. Warning-only `problem_rows` tables expose flagged ratings
that would otherwise fall outside the first rows of a Markdown preview; complete
tables remain in JSON. A failing LOO section does not discard a valid WAIC section,
and `require_complete` still rejects an incomplete report. Parameter MCSE and the
native pointwise SE of a score remain explicitly different quantities.

[133 integration checks passed](results/workflows/20261011-common-report-candidate-01/check-01/output/verification.toml),
including two result types, all-draw versus selected-prediction behavior, public
projection, warning/ID preservation, cache/report round trips, section failures,
legacy behavior and replay of the previously saved 24-draw normalized walkthrough.
Its original cache hash, diagnostics and parameter-MCSE results remain unchanged.
After adding only the warning-only tables, [36 focused checks](results/workflows/20261011-common-report-candidate-01/check-02/output/verification.toml)
confirmed persistence and equality of all earlier criterion fields and parameter
diagnostics; the 133 successful checks and earlier 113 comparison checks were not
rerun. Runtime including startup was 186.09 and 89.14 seconds respectively; peak
observed descendant RSS was 1,591,672,832 and 1,413,857,280 bytes. **Zero new MCMC
fits** were run. This is combined evidence from defined stages, not one full-suite
execution. The checks overlapped MS2 attempts 20/21, so they are not isolated cost
benchmarks. All 518 MS2-bound source/environment hashes remain unchanged.

The [saved-fit report example](results/workflows/20261011-common-report-candidate-01/candidate/examples/saved_mgmfrm_report.jl),
[updated from-data walkthrough](results/workflows/20261011-common-report-candidate-01/candidate/examples/normalized_mgmfrm.jl)
and [guide](results/workflows/20261011-common-report-candidate-01/candidate/docs/src/common_prediction_comparison.md)
describe the same arguments and warnings. The from-data fit/figure stages reuse
their existing evidence; only the affected saved-result/report path was executed
here. The subsequent candidate below adds fixed-coefficient MFRM report integration.
Common refit/K-fold, reference PSIS, final scope, ordinary-test integration and
independent review remain open.
This closes another user-facing connection without claiming MS5 or model-selection
validation complete, or launching an unrelated simulation campaign.

**2026-10-11 fixed-coefficient MFRM report integration verified.** The
[isolated candidate and verification](results/workflows/20261011-fixed-mfrm-report-candidate-01/verification.json)
extends the recorded-report candidate to canonical `MultidimensionalMFRMFit`,
`Experimental.CorrelatedMFRMFit` and `Experimental.ExchangeableMFRMFit`, including
both independent and correlated exchangeable-rater variants. They use the same
explicit WAIC/raw-LOO flags and dataset/rating IDs, existing common calculation,
warning tables, public JSON/Markdown and saved-bundle example. The small
[patch](results/workflows/20261011-fixed-mfrm-report-candidate-01/candidate.patch)
uses the existing type-specific data accessor instead of assuming every record
stores its specification in the same field. Fixed coefficients, unit-logit scale,
Q, population correlation, priors and native diagnostics remain distinct and intact.

Validation combines **192 passed assertions** for four canonical D2 variants
with **84 subsequent checks** for independent D3, invalid requests, single-criterion
requests, short-draw section failures, both recorded MGMFRM types and two historical
24-draw Julia/CmdStan exchangeable-correlated records. Saving/reloading preserves
IDs, scores, warnings, priors and diagnostic summaries; original fits/files and
parameter MCSE are unchanged. These are interface and persistence checks, not new
posterior draws, independent statistical replications or D3 free-correlation evidence.

The first test stopped on an incorrect assumption that public reports accept old
fixed-Q v1 records. The pre-existing canonical-format guard remains unchanged:
legacy records support common saved-row criteria/comparison, but public reports
reject them. The [guide](results/workflows/20261011-fixed-mfrm-report-candidate-01/candidate/docs/src/common_prediction_comparison.md),
docstring and test now state/check that boundary. A short-draw synthetic fixture's
split-chain flag was also made consistent with its chain/draw counts; the default
2-by-20 inputs of the 192 passed checks are unchanged. Only a docstring changed in
runtime sources between stages, so those passed cases were not rerun. Both original
test inputs and the first error log are preserved. This is staged evidence, not a
single clean full-suite execution.

Checks took 255.50 and 208.60 seconds including startup, with peak observed RSS
1,479,933,952 and 1,897,463,808 bytes, and **zero new MCMC fits**. They ran single-threaded
at low priority alongside MS3 and are not isolated cost benchmarks. All **526**
MS3-bound source/environment identities and 306 parent source/evidence identities
remained unchanged. The same
[public saved-fit example](results/workflows/20261011-fixed-mfrm-report-candidate-01/candidate/examples/saved_mgmfrm_report.jl)
now covers the five recorded/fixed result types; legacy scalar reports retain their
existing arguments. Fixed-MFRM parameter MCSE remains available through
`posterior_mcse(fit)` rather than a newly added report table. Rendering and fitting
reuse existing evidence. Common refit/K-fold, reference PSIS, design-planning
simulation, ordinary-test registration and MS4/MS6 decisions remain open; this
candidate is not merged, released or complete MS5 acceptance.

**2026-10-11 ordinary-test and saved-workflow integration verified.** The
[isolated workflow candidate](results/workflows/20261011-common-workflow-candidate-01/verification.json)
adds the comparison/report tests to the existing `fitting_reports` group, without
new CI jobs or required historical research files. Separate test modules prevent
fixture-name collisions. The [public saved-fit workflow](results/workflows/20261011-common-workflow-candidate-01/candidate/examples/saved_prediction_workflow.jl)
connects comparison, diagnostics, parameter MCSE and public report save/reload.
It requires a new output directory and prepares all reports before writing;
unsupported inputs leave no partial report. It is not an atomic multi-model
rollback for external I/O failures. Both WAIC and raw IS-LOO reports are required
regardless of the selected comparison criterion.

The ordinary entry passed **525 assertions** (113 comparison, 146 recorded-report,
266 fixed-coefficient-report). A missing `end` in the newly added workflow test
then prevented that test from parsing. Its corrected, previously unexecuted
portion passed **29 assertions plus 13 in a fresh Julia process**. The comparison,
diagnostics, parameter MCSE, report scores/warnings and original cache hashes
agree across sessions for normalized and correlated MGMFRM. Another **61 checks**
cover parsing, existing shard selection, loaded help and documentation connections.
The **628 passes are combined staged evidence**, not a single clean full-suite
execution; the original error/input and both logs remain archived. Passed groups
were not repeated after the syntax correction.

The [guide](results/workflows/20261011-common-workflow-candidate-01/candidate/docs/src/common_prediction_comparison.md)
is linked from documentation navigation and examples. Module help now correctly
describes existing correlated fitting/manual caches; candidate NEWS distinguishes
implementation availability from scientific acceptance. Runtime implementation
bodies are unchanged from the parent; only the initial module docstring changed
in `src`. All **526** MS3-bound files and **418** parent source/evidence identities
remain intact. The two checks took 559.24 and 218.54 seconds including startup,
with peak observed descendant RSS 1,859,665,920 and 3,404,152,832 bytes, and **zero
new posterior fits**. They overlapped MS3 and are not isolated cost measurements.

Ordinary-test registration and this saved-result connection are now checked.
Full `Pkg.test`, the complete report shard/CI timing, document-site build,
minimum-version/platform verification and independent user/scientific review
remain open. This candidate is unmerged and unreleased; it does not close MS5,
common refit/K-fold, reference PSIS, or model-selection/design-calibration claims.
The priority remains MS3 accounting and the remaining common workflow boundaries,
using existing fit/figure evidence before any new statistical campaign.

**2026-10-11 existing refit-plan integrity repaired before widening dispatch.**
Review of the next common-refit boundary reproduced three defects without new
sampling: the generic K-fold/LOO execution preflight accepted an observation in
both training and heldout sets; K-fold could attach a different row order to the
computed heldout scores; rebuilding a training specification discarded custom
dimension names. These affect the validity or interpretation of an existing
workflow, so repairing them takes priority over adding more result types.
The [latest isolated candidate and verification](results/workflows/20261011-refit-plan-candidate-01/verification.json)
extends the tested workflow snapshot without changing the active study.

The [patch](results/workflows/20261011-refit-plan-candidate-01/candidate.patch)
checks all folds before the first fit: training is the full heldout complement,
K-fold covers every outcome exactly once, LOO holds out unique individual rows,
declared groups stay together, and scoring indices/order, fold labels and counts
match the actual rows. Valid subset/empty LOO and normal generated v1 plans remain
supported. Training specs now retain dimension names and the existing item-label
Q mapping. The checks are shared by single-model and comparison refits; public
exports, cache formats and numerical sampling/likelihood bodies are unchanged.

**86 focused assertions passed**, including an invalid late fold rejected through
the public refit/comparison paths before sampler-control validation, serialization
and valid-plan compatibility, retained metadata-only grouping behavior, unknown
fitted-level rejection, source immutability, and three finite-point density checks
under changed dimension labels. The test is registered in `fitting_core`; help,
the fitting guide and candidate NEWS describe the same boundary. Reproduction
and verification took 18.83 and 35.29 seconds including startup, with peak observed
RSS 1,023,737,856 and 1,513,865,216 bytes, and **zero new posterior fits**. All 526
main-bound source/environment files and 871 parent source/evidence files remain
unchanged. The parent's 628 successful workflow checks were not repeated.

This finding does **not** justify rerunning MS3. Its separate
[foundation path](scripts/mgmfrm_foundation_prediction.jl) already checks disjoint
complete partitions and once-only heldout coverage, and binds scoring to the
actual heldout native IDs/categories and training target. Its saved preparation
and execution evidence remain intact. General `kfold_plan_diagnostics` remains
a level-availability audit, not a complete partition or source-identity certificate;
generic plan row indices are positional. Shared model-specific refit factories,
source/observation bindings and heldout scoring integration remain MS5 work.
Full package/CI/docs verification, common refit support for the additional result
types and independent review remain open; this candidate is unmerged/unreleased.

**2026-10-11 common K-fold requests and saved-fold scoring verified.** The
[latest isolated candidate](results/workflows/20261011-heldout-scoring-candidate-01/verification.json)
extends the refit-plan snapshot with qualified `prediction_refit_plan` and
`prediction_fold_observations`. A model/specification, explicit prior, persistent
rating IDs and a checked K-fold plan produce source-bound training requests;
their `model` and `prior` can be passed to the existing stable/experimental fit
entry points. A full-data fit is neither needed nor used for initialization.
The scorer accepts the matching saved training fit, validates its native target
and record, and scores heldout rows with the existing native likelihood kernel.
Data/split identities are separate from model/prior identities, so a common
source and split remain comparable across model families or dimensions.

The [patch](results/workflows/20261011-heldout-scoring-candidate-01/candidate.patch)
and [public guide/example](results/workflows/20261011-heldout-scoring-candidate-01/candidate/docs/src/common_prediction_comparison.md)
cover all eight concrete result types, including both exchangeable MFRM covariance
variants, both normalized MGMFRM prior modes and independent fixed-MFRM D3.
All retained draws/chains and sampling warnings are preserved. Wrong training
data, priors, LKJ settings, edited requests and corrupted saved records are
rejected. Heldout results have a separate schema and cannot be passed to
training-row WAIC/LOO. No new correlation transform or numerical likelihood is
introduced; the existing adapter's prediction loop is shared with this path.

**531 focused assertions passed in stages:** 317 final common-refit checks,
86 existing partition checks, 113 existing comparison checks and 15 metadata/
category checks. These include native numerical agreement, changed heldout
outcomes with unchanged training predictions, serialized requests, and fit-cache
replay through the public example. The final 317-check run took 270.62 seconds
including startup, with peak observed RSS 1,741,406,208 bytes; **zero new posterior
fits** were run. This is not one clean full-suite execution: early test fixture
errors, a rejected counterexample, and the later metadata-fixture error are
preserved and explained in the receipt. Successful 199-check regression sections
were reused; only the failed metadata section was repeated.

**Correction of the level-order hypothesis.** Ordinary `FacetData(table)` sorts
levels; merely reversing rows did not reproduce the suspected change of reference
rater. That broad suspicion was withdrawn. A valid explicitly reordered source
encoding does differ from the table constructor's order: for a three-rater finite
example, the old reconstruction preserves likelihood but changes log prior by
-0.3 nat at the same physical severities. The shared training-data helper now
preserves source order among observed fitted levels, restoring likelihood/prior
agreement while retaining optional metadata and category declarations. Missing
fitted levels remain absent and unsupported. This bounded case does not establish
a defect in ordinary sorted inputs or authorize rerunning a frozen study.

All 526 MS3-bound files and 735 parent source/evidence files remain unchanged.
MS3 continues on its original, explicitly exchangeable normalized-prior target
and saved target/draw/scoring bindings; candidate identities are not substituted
into that evidence. At this receipt, 46/960 attempts are completed, 42 are
primarily qualified and four fail numerical qualification; no execution failure
file is recorded. These are interim execution counts, not prediction conclusions.

At this preparation/scoring checkpoint, automatic multi-model refit execution,
complete-fold aggregation/comparison and its common uncertainty/reporting contract
remained MS5 work; the subsequent checkpoint below closes the descriptive
aggregation/comparison and new-schema fresh-process replay portions. No new SBC/recovery/calibration,
new-level integration, reference PSIS or D>=3 correlation-fitting claim follows.
Full suite/docs/environment verification, fresh-process replay specifically of
the new fold-request schema, MS4 acceptance and MS6 independent review remain
open. The candidate is unmerged and unreleased.

**2026-10-11 complete-roster K-fold comparison and fresh-process replay verified.**
The [new isolated candidate](results/workflows/20261011-kfold-comparison-candidate-01/verification.json)
adds qualified `prediction_kfold` and `compare_kfold_predictions` on top of the
saved-fold scoring path. The [public example and guide](results/workflows/20261011-kfold-comparison-candidate-01/candidate/docs/src/common_prediction_comparison.md)
connect saved training fits to scoring, complete-fold aggregation and declared
model/dimension/Q comparisons. This checkpoint is extended by the recovery
evaluation candidate below; parent snapshots and MS3 sources remain immutable. The [incremental patch](results/workflows/20261011-kfold-comparison-candidate-01/candidate.patch)
is unmerged and unreleased.

Aggregation checks the original full roster and source/split/target bindings.
Unknown, duplicate or edited fold results are rejected. Missing results and
explicit execution failures remain separate fold states with failure reasons;
any absent fold leaves the full ELPD missing. If any named candidate is incomplete,
every model contrast remains missing, while completed model totals remain visible.
Numerically warned folds/models retain all their scores and diagnostics and mark
the complete comparison as a warning. No successful-only roster, automatic rank,
winner or model weight is substituted for the declared comparison.

Each score is the existing native log-mean-exp over all retained training-posterior
draws for one heldout rating. Rating scores are added even for grouped holdouts;
this is not the joint predictive density of a group. Persistent rating IDs align
row-order differences; the split identity canonicalizes fold-label order. Model
metadata retain D, item-to-Q mapping, family, prior and covariance. Differences
are model minus the named baseline. Standard errors, MCMC MCSE and independent-
replication uncertainty are explicitly not computed: folds are not treated as
independent replications and the native naive pointwise SE is not forwarded.

**285 assertions passed in stages:** 229 complete-path/native-agreement and
missing/failure/identity/arithmetic checks, 13 model-axis/grouping checks, 36
fresh-process public-workflow checks and seven syntax checks. The 11 deterministic
configurations cover all eight concrete fit types and the prior/covariance/D3
variants from the previous checkpoint. Separate-process replay checks all 11
saved configurations and a MFRM/GMFRM/MGMFRM comparison through the public example.
These are synthetic saved-draw checks, with **zero new posterior fits**. They do
not establish comparative predictive performance or qualified posterior sampling.

The first test attempt stopped before assertions because a new fixture omitted
required column-name keywords. Correcting that fixture produced the 229-pass
stage. Its runtime source remains applicable by hash, apart from a later docstring
cross-reference; added checks ran separately, rather than repeating successful
work. The final additional-check and replay source maps match the candidate.
The main 229-pass run took 290.17 seconds including startup, with peak observed
RSS 1,756,250,112 bytes; fresh-process replay took 176.87 seconds. Both overlap
MS3 and are not performance benchmarks. All 761 parent source/evidence files and
526 MS3-bound files were verified unchanged.

Prepared-plan and scored-fold records move to content-bound v2 in this unreleased
candidate. Old unsealed candidate records must be reprepared/rescored using their
matching existing fit caches; no new MCMC is needed. Individual fold-request v1
and fit-cache formats remain unchanged. Hashes detect accidental changes, not
trusted execution history or the absence of heldout-driven tuning.

At verification, MS3 has 58/960 completed attempts: 54 primarily qualified,
four numerically unqualified and no execution-failure file. Its fixed roster,
implementation and reporting rules are unchanged. MS5 remains open for full
suite/docs/environment checks and the remaining supported end-to-end operations;
automatic multi-model refit execution and inferential K-fold uncertainty are not
established. MS4 scope decisions and MS6 independent/unfamiliar-user review also
remain open. The common aggregation/failure contract can now be reused by design
simulation; it does not replace independent simulation replications or authorize
a new campaign. Higher-dimensional correlation fitting remains a separate task.

**2026-10-11 common named recovery evaluation verified.** The
[single-dataset candidate](results/workflows/20261011-recovery-evaluation-candidate-01/verification.json)
extends the K-fold candidate with qualified `recovery_quantities` and
`recovery_evaluation`. Its [guide and saved-fit example](results/workflows/20261011-recovery-evaluation-candidate-01/candidate/docs/src/common_prediction_comparison.md)
connect all eight concrete fit types to named model-coordinate truths, native
recovery arithmetic and existing within-fit MCSE. This removes a shared evaluation
gap before a design runner is assembled; it does not introduce a second fitting
pipeline or a simulation campaign. The [incremental patch](results/workflows/20261011-recovery-evaluation-candidate-01/candidate.patch)
is unmerged and unreleased.

Truth keys select focal quantities in their native scale and identification.
The evaluator retains all draws/chains, diagnostics, model/prior/source bindings
and unavailable MCSE. Fixed-MFRM coordinates stay in unit logits; rho is transformed
per draw and joint ability draws are not correlated twice. Structural constants
have missing coverage and a separate fixed-value/truth agreement flag, preventing
point constraints from being counted as calibrated estimates. No centering or
cross-model latent alignment is inferred. Fixed-Q v1 recovery is explicitly
unsupported; existing vector-truth recovery APIs and cache formats are unchanged.

**1,342 distinct assertions passed in stages:** 1,147 unaffected fit/inventory
checks reused from the first run, 165 affected-case/constraint/input checks,
23 fresh-process replay/source-binding checks and seven syntax checks. The 11
deterministic configurations include both normalized-prior modes, both
exchangeable-MFRM covariance modes and independent fixed-MFRM D3. These are
software checks, with **zero new posterior fits or formal simulation/SBC
replications**. All 773 parent source/evidence files and 526 MS3-bound files
remain unchanged. The final additional-check/replay source applicability is
recorded by hash; this is not one clean package-wide test run.

The first run passed 1,304 assertions and failed two tests that wrongly applied
MGMFRM's zero-sum severity constraint to GMFRM. Native source and saved-draw
inspection confirmed that GMFRM centers item difficulties, while its rater
severities are free. That review also found and fixed a new inventory metadata
omission: GMFRM item discrimination is dimensionless. Only the affected GMFRM
case and changed constraint/input sections were rerun. No existing model equation,
prior or sampler was changed. The saved-fit replay then reproduced all final
expectations and matched the common prediction API's source binding.

This evaluates **one dataset**, not repeated-data bias, replicated coverage,
SBC calibration or design assurance. Parameter rows, chains and folds are not
independent simulation replications. Generating-truth verification and independence
remain explicitly unverified; no coverage-decision error bound or precision
threshold is applied. The next design-planning layer must retain the planned
independent-dataset roster, failed/unresolved attempts and replication uncertainty,
and reuse these recovery and prediction consumers. Full suite/docs/environment
checks, MS4 scope decisions and MS6 independent/unfamiliar-user review remain open.
At verification MS3 had 69/960 completed attempts: 64 primarily qualified, five
numerically unqualified and no execution-failure file; its frozen plan is unchanged.

**2026-10-11 fixed-truth recovery replication aggregation verified.** The
[replication candidate](results/workflows/20261011-recovery-replications-candidate-01/verification.json)
extends that evaluator with qualified `recovery_replications` and a
[saved-evaluation workflow](results/workflows/20261011-recovery-replications-candidate-01/candidate/examples/saved_recovery_replications.jl).
This closes the next shared design-planning gap: each named quantity is summarized
across its declared dataset roster, without treating persons, parameters, chains
or folds as independent replications. It consumes existing evaluations and adds
no generator, fitter, study or replacement attempt. The candidate remains unmerged
and unreleased; the [guide](results/workflows/20261011-recovery-replications-candidate-01/candidate/docs/src/common_prediction_comparison.md#固定した真値でのデータセット間の回復集計)
and NEWS describe the same limits.

The complete ledger retains missing datasets, declared failure reasons, missing
focal quantities, fixed constants and original evaluation/diagnostic/MCSE records.
Each quantity has both warning-inclusive and without-warning summaries. The latter
is conditional descriptive performance, **not** adequate-MCSE qualification.
Structural constants receive no recovery summary or coverage credit. Changed
analysis model/prior/scale/interval contracts and varying focal truths are rejected;
separate design conditions require separate scenario summaries. A matching focal
truth and contract do not certify common rating assignments, all generating truths,
seed rules, prospective selection or a shared data-generating process.

Replication SE uses sample SD / sqrt(n) only with a declared independence basis
and at least two retained datasets. The RMSE SE is a first-order delta approximation;
zero MSE leaves it unavailable, and empirical zero variance is explicitly flagged.
Detected reuse of native sample records or matching target/evaluated-draw evidence
suppresses SE. Undetected duplicates remain possible; different IDs/hashes do not
prove independence. Within-fit MCSE remains visible but is not combined with or
removed from these SEs. Unresolved coverage outcomes have bounds
`[covered/N, (covered+N-n)/N]`, not confidence intervals or a finite-MCMC
coverage-decision guarantee. Full-planned continuous performance stays unavailable
when required outcomes are missing.

**166 focused assertions passed:** 80 arithmetic/accounting/rejection checks,
55 interoperability checks on the eleven existing native evaluation configurations
(eight concrete fit types), 25 fresh-process replay checks and six recursive Julia
syntax checks. A hand-calculated three-dataset example checks all six performance
metrics and their SEs; adding 20 unrelated parameter rows changes neither the focal
denominator nor SE. Empty/singleton, warning, failure, missing-quantity, fixed-value,
zero-variance, duplicate-evidence and incompatible-input cases are covered.
The main check took 26.56 seconds including precompilation, with peak observed RSS
1,020,821,504 bytes; replay took 14.71 seconds. These overlap MS3, not benchmarks.
All 799 parent source/evidence files and 526 MS3-bound files are unchanged.
Native extraction, model mathematics, sampling and cache formats were not changed;
their existing checks were reused, not rerun or recounted as new evidence.

This contributes **zero new fits or formal simulation/SBC replications**. A design
runner, variable-truth assurance, paired design/model comparisons, SBC, precision
thresholds and design recommendations remain open. Full suite/docs/environment
verification, MS4 scope and MS6 independent/unfamiliar-user review are still needed.
At this checkpoint MS3 has 73/960 completed attempts: 68 primarily qualified,
five numerically unqualified and no execution-failure file; its frozen roster and
rules remain unchanged.

**2026-10-11 common API documentation integration verified.** The
[current isolated candidate](results/workflows/20261011-common-api-docs-candidate-01/verification.json)
connects the prediction/recovery guide and eleven qualified APIs to the rendered
reference, corrects the stale claim that common K-fold aggregation is unavailable,
and moves test-running instructions to the existing internal owner. Public-page
registration was missing from the existing content gate; that omission and its
false detection of Julia's `@__FILE__` macro are fixed, with private-identifier
rejection retained. No model, sampler, saved format, common API implementation,
example, or runtime dependency file changed. Their numerical evidence is reused.

Final validation passes **194 policy assertions**, the 36-file source policy,
all **17 rendered pages**, and **566 local fragment links**, with no missing local
destinations. All eleven new API bindings render. The experimental-model guide
exceeded the unchanged 100 KiB page limit, so its 25 API docstrings now have a
separate reference; its mathematical explanations and all 25 old API anchors are
retained. Two stale heading links are repaired. Maintainer pages remain outside
navigation/search, and all 17 public pages occur in the search index.

The first docs run hit the 3 GiB RSS guard during parallel precompilation.
Serial precompilation resolved that resource issue without increasing limits;
its completed work was reused after the HTML-size correction. Final build and
policy checks took 12.56 and 16.63 seconds, respectively, while MS3 was running;
these are not performance benchmarks. Earlier failed checks and their corrections
are retained in the receipt. Four pre-existing omitted management docstrings and
a 521.41 KiB search-index warning (500 KiB advisory threshold) remain explicit.

This is a **local documentation check**, using Julia 1.12.5 / Documenter 1.17.0
in a separately recorded docs environment, not remote publication or current-CI
equivalence. The candidate is unmerged/unreleased. Full package/environment
verification, MS4 scientific scope and MS6 independent/unfamiliar-user review
remain open. All 780 parent source/evidence files and 526 frozen MS3 files are
unchanged; no new posterior fit or formal simulation was run. MS3 has 79/960
completed attempts at this checkpoint: 74 primarily qualified, five numerically
unqualified and no execution-failure file.

**2026-10-11 common API ordinary integration started; one stale test contract repaired.**
The [isolated integration run](results/workflows/20261011-common-api-integration-01/snapshot.json)
first verified all 878 files in the documentation candidate and its evidence,
plus all 526 frozen MS3 files. The historical 2026-10-02 ordinary-suite successes
predate the common APIs and used Julia 1.12.6/1.10.8; they are not presented as
a current candidate-wide pass. The affected `fitting_reports` shard is running
on the unchanged 740-file copy. `fitting_core` is queued only after that job
passes and at least 8 GiB memory is available. Both retain single-threaded,
serial-precompile execution, low priority and no elapsed-time cutoff; their
separate RSS limits reflect the historical observed peaks. No new scientific
cohort or replacement fit is scheduled. Ordinary tests may generate small
synthetic fits, which receive no scientific replication credit.

Review of the other affected test consumers found one old fixed-Q MFRM report
fixture still requiring WAIC/LOO to be `unsupported`. The candidate implementation
and help consistently specify `not_requested` when neither criterion is selected.
Only that test fixture was corrected in the separate
[repaired candidate](results/workflows/20261011-common-api-integration-01/candidate-repaired/test/fixtures/fixed_q_report.jl);
the running copy and all production/docs/dependency files remain unchanged.
The five still-unsupported sections retain their reason checks, and both full
and public default reports are checked for the two unrequested criteria.

The [focused receipt](results/workflows/20261011-common-api-integration-01/fixed-report-verification.json)
records **3,604 passing assertions** across the existing eight synthetic saved-format
cases: 2/4 categories, AdvancedHMC/CmdStan record labels, canonical MFRM and legacy
MGMFRM-labelled fixed-Q records. Result, cache, report, prior-report and bundle
checks passed without executing either backend. This run took 707.28 seconds
including startup/precompilation, with 1,719,894,016 bytes peak observed RSS;
it overlaps MS3 and ordinary tests and is not a performance benchmark.
The corrected fixture belongs to `generalized`; this focused pass does not
close that entire shard or the package suite. The report/core jobs use the
unchanged copy and do not include the corrected fixture.

The ordinary test environment is archived separately: Julia 1.12.5,
`Pkg.test(allow_reresolve=false)` offline, unchanged existing runtime package
versions/tree identities, and cached test additions ReverseDiff 1.17.3 and
StaticArrays 1.9.23. Minimum-version, other-platform, hosted-CI and publication
checks remain open. All parent/MS3 identities were rechecked after the focused
run. MS3 has **86/960** completed attempts at this checkpoint: 81 primarily
qualified, five numerically unqualified and no execution-failure file.

**2026-10-11 actual public refit-to-comparison workflow verified.** The
[isolated candidate and receipt](results/workflows/20261011-common-refit-workflow-01/verification.json)
add a [synthetic executable example](results/workflows/20261011-common-refit-workflow-01/candidate-connected/examples/synthetic_kfold_workflow.jl)
and an opt-in integration check. Earlier common-refit checks used synthetic saved
draws; this follow-up supplies **16 actual AdvancedHMC fits, two folds for each
of the eight concrete result types**: scalar MFRM/GMFRM, raw/normalized/correlated
MGMFRM, and independent/correlated/exchangeable fixed-Q multidimensional MFRM.
Every model uses the same 96 fixed synthetic ratings, 8 people / 4 items /
3 raters / 3 categories, and response-grouped split with 48 training and 48
heldout ratings. All ratings of each person-item response remain together.
Both training designs are connected, and each person retains one item per
dimension. The example explicitly specifies priors; these are demonstration
settings, not adopted defaults or a generating model.

**255 assertions pass** through public preparation, actual fitting, cache
save/reload, diagnostics and parameter MCSE, heldout scoring and comparison.
An independent stable log-mean-exp calculation reproduces ELPD and baseline
differences. Real fits from the wrong training fold are rejected. A fresh Julia
process passes **251 saved-result checks**, reproducing the comparison without
sampling or changing any saved input bytes. These are overlapping replay checks,
not additional independent replications. Short-chain warnings remain visible;
no winner, inferential comparison SE or scientific acceptance is returned.

The fixed operability budget is two chains, ten warmup and eight retained draws
per chain, with maximum tree depth three. This deliberately short run supplies
no posterior-precision, recovery, calibration, model-ranking or SBC evidence.
The successful guarded execution took 559.78 seconds including startup,
compilation and fresh-process replay (188.7 seconds in the replay testset),
with 2,559,885,312 bytes peak observed descendant RSS. It overlaps MS3 and the
ordinary report shard and is not a cost benchmark. Two earlier example errors
were rejected before any sampling: an unsupported row-vector table format,
then a split retaining all levels but disconnecting the training design. Their
sources/logs remain intact; only the example's input representation and rating
allocation changed. No validation rule or threshold was relaxed and no
successful fit was repeated.

All **740 existing candidate files**, including the corrected fixed-Q report
fixture and all implementation/docs/dependency files, remain byte-identical to
the prior repaired candidate. Only the example and opt-in test are added. All
**526 MS3-bound files** are unchanged. Existing mathematical/backend and rendered
documentation evidence is reused. This closes the eight-type actual-fit
connection check, not the ordinary suite, a general resumable refit executor,
inferential K-fold uncertainty, design runner, release or independent review.
At this checkpoint the report shard remains running (25 completed testsets /
25,440 assertions passed), with the core shard still queued. MS3 has **99/960**
completed attempts: 94 primarily qualified, five numerically unqualified and
no execution-failure file. Common integration and MS3/MS4 remain the priorities.

**2026-10-12 remaining ordinary integration queued (JST).** The
[finite continuation plan](results/workflows/20261012-common-api-integration-continuation-01/plan.json)
adds only the four not-yet-run ordinary shards, in this order: `generalized`,
`core`, `local_dependence_core`, `local_dependence_integrity`. It waits for
passing terminal receipts from both the already-running `fitting_reports` and
the previously queued `fitting_core`; those jobs are not repeated. The
[launch](results/workflows/20261012-common-api-integration-continuation-01/launch.json)
is confirmed waiting, not a claim that the four shards have started or passed.

The historical ordinary success used Julia 1.12.6/1.10.8 and predates changes in
five shared production files plus seven new common-API files. Dependency files
are unchanged, but that is insufficient for a current Julia 1.12.5 suite claim.
The continuation uses the verified 742-file actual-refit candidate. Relative to
the running 740-file copy, the only modified existing file is the fixed-Q report
fixture, whose sole direct consumer is the generalized shard; the two added
example/opt-in-test files are not invoked by the ordinary runner. All production,
dependency and ordinary-entrypoint bytes match the running candidate, allowing
its report/core results to be combined with these four shards after completion.
Keep the distinct snapshot and environment provenance in the final receipt.

[Eleven admission/identity checks pass](results/workflows/20261012-common-api-integration-continuation-01/preflight.json):
incomplete/writing receipts remain pending, failed exits/resource stops/live
survivors block continuation, and changed bound files are rejected. All 742
candidate files, 52 parent evidence files and 526 MS3 files were verified.
Each remaining shard has a 4 GiB observed-RSS limit, based on historical peaks
of 1.89–2.72 GiB, a 512 MiB log-output limit, one Julia/BLAS thread, serial
precompilation, low process priority and no elapsed-time cutoff. Admission
requires at least 8 GiB available memory and 5 GiB free disk. Shards run serially;
a failed shard leaves later shards unstarted. Offline `Pkg.test` disallows
re-resolution; optional research/native smoke flags remain disabled.

No runtime source or test expectations changed in this continuation. The prior
16-fit workflow, native Stan mathematics and rendered documentation are reused,
not rerun. Ordinary tests may create small synthetic fits but contribute no
scientific study/SBC replications. Current-version full-suite acceptance awaits
all six terminal results; minimum-version, other-platform, hosted-CI, publication
and independent review remain separate. MS3 has **103/960** completed attempts
at this checkpoint: 98 primarily qualified, five numerically unqualified, and
no execution-failure file. Its frozen roster and controls remain unchanged.

**2026-10-12 English beginner learning path (JST).** At the user's request,
the [isolated documentation candidate](results/workflows/20261012-beginner-guide-candidate-01/verification.json)
adds three linked pages: [Getting Started](results/workflows/20261012-beginner-guide-candidate-01/candidate/docs/src/learning-guide.md),
[How Rating Models Work](results/workflows/20261012-beginner-guide-candidate-01/candidate/docs/src/rating-model-theory.md),
and [Reading Results and Comparing Models](results/workflows/20261012-beginner-guide-candidate-01/candidate/docs/src/interpreting-results.md).
All new guides are English, following the user's explicit language preference.
The existing manual home, navigation, README and release notes now lead to this
question-first path. It explains rating rows and linking, distinct model axes,
Q versus fixed coefficients, step ownership and scale differences, priors and
identification, interval/MCSE/replication uncertainty, known-level prediction,
and the different purposes of SBC, recovery and design assurance. It does not
promote experimental models or claim an implemented general design runner.

The candidate passes **197 policy assertions**, source checks on **40 public
files**, rendered-content checks on **20 HTML pages**, and **613 local fragment
links**. All 11 common API anchors and 25 prior experimental anchors remain.
The worked probability calculation executes during document generation; an
independent closed-form calculation verifies all nine table values. Every page
remains below the unchanged 100 KiB limit. The first combined command finished
HTML generation but then failed one policy test because its custom build-path
environment variable conflicted with a default-path assertion. Only that policy
stage was rerun with the appropriate environment; generated HTML and successful
numerical evidence were retained. Four pre-existing omitted management docstrings
and the 553.4 KiB search-index advisory remain. Browser file-URL navigation was
blocked by the browser policy, so visual layout/math and interactive search are
not claimed as checked. Unfamiliar-reader acceptance remains open.

All **742 parent source files, 52 parent evidence files and 526 MS3-bound files**
remain unchanged. The new 745-file copy changes documentation and its coverage
checks only; runtime, examples and dependency files retain their existing evidence.
No posterior fitting, formal simulation or SBC replication was added. The
candidate remains unmerged and unpublished. This supplies the beginner entry
requested within MS5; it does not close MS4 scientific or MS6 independent acceptance.

**2026-10-12 ordinary integration checkpoint (JST).** The existing
[`fitting_reports` receipt](results/workflows/20261011-common-api-integration-01/fitting_reports/guard-receipt.json)
now passes: **62 testsets / 92,902 assertions**, exit zero, 4,238.12 seconds,
peak observed descendant RSS 3,756,294,144 bytes. The subsequent
[`fitting_core` job](results/workflows/20261011-common-api-integration-01/fitting_core/guard-receipt.json)
fails in `test/refit_metadata.jl`: an occasion-grouped plan is reused with data
that omit the occasion metadata, and the new partition validation rejects that
missing grouping facet. This is a test/contract compatibility issue to resolve
in a new isolated candidate, not a resource interruption or evidence that the
report shard failed. The four-shard continuation stopped before launching any
of its shards, as required by its prerequisite rule. Do not restart successful
reports or relax grouping validation merely to make the old test pass; determine
the intended comparison and verify the affected behavior before resuming the
unfinished integration work. At this checkpoint MS3 has **108/960** completed
attempts, 103 primarily qualified, five numerically unqualified and no
execution-failure file. Its plan and sampling controls are unchanged.

**2026-10-12 Julia help and first-example review (JST).** The user explicitly
authorized browser inspection and asked whether Julia offers understandable
help/examples comparable to R. The browser tool again rejected the rendered
guide's `file://` URL under its URL policy; authorization did not remove that
tool restriction. No alternate browser surface or workaround was attempted.
Visual layout/math and search interaction remain unverified.

The [new isolated help candidate](results/workflows/20261012-julia-help-candidate-01/verification.json)
reads seven actual Julia help entries and improves the module overview,
`FacetData`, `validate_design`, `mfrm_spec` and `fit`. Entry help now explains
purpose, inputs, returned fields, runnable examples and interpretation. Long
details remain accessible through Julia's standard `??` extended help. The
stable `fit` default is explicitly identified as random-walk `backend=:julia`,
with `:advancedhmc` selecting Julia NUTS and counts applying per chain. No
backend/default/namespace change was made. The English
[help walkthrough](results/workflows/20261012-julia-help-candidate-01/candidate-readable/docs/src/learning-guide.md#use-julia-help-and-examples)
maps R help/example expectations to Julia REPL help, `@doc`, doctests and
package example scripts. The new
[first example](results/workflows/20261012-julia-help-candidate-01/candidate-readable/examples/inspect_ratings.jl)
prints eight-row input counts, a real sparse-category warning, the selected
model and equation, with no fitting or analysis-file writes. Its final output
selects the equation instead of dumping the full technical metadata tuple.

Actual REPL help and example checks pass **30 focused assertions**, with
**seven subsequent output checks** for the final display change. Two initial
literal-string checks failed only on terminal line wrapping; whitespace-aware
checks passed without changing help or repeating successful AST/help checks.
Three parsed-source comparisons confirm that changes in the source files are
docstrings only. The successful Documenter build executes the new self-contained
`FacetData` doctest; **197 policy assertions**, 20 rendered pages and **623 local
fragment links** pass. The last snapshot changes only example printing, so the
unchanged help/docs build is reused with the output-specific check. Four existing
omitted management docstrings and the 563.25 KiB search-index advisory remain.

The final **746-file** candidate is `candidate-readable`, as explicitly recorded
in its verification receipt. All 745 parent source files, 70 parent evidence
files and 526 MS3-bound files remain unchanged. Existing sampling checks retain
their prior scope; no new fit or scientific/SBC replication was run. The
candidate is unmerged/unreleased, other reference help is not wholly rewritten,
and implementer readability review does not substitute for unfamiliar-reader
acceptance. The separate occasion-plan integration failure remains unresolved;
its stopped continuation was not restarted for this documentation request.
MS3 now has **112/960** completed attempts: 107 primarily qualified, five
numerically unqualified and no execution-failure file, with unchanged controls.

**2026-10-12 GitHub browser route checked (JST).** At the user's suggestion,
the repository's HTTPS page opened successfully and its screenshot was inspected.
The GitHub Pages address was also accessible to the browser, but returned the
standard site-not-found page; the authenticated repository API confirms
`has_pages=false`. The public `main` documentation lacks the three new beginner
pages. Its CI builds documentation but does not deploy it. GitHub's Markdown
viewer is not a substitute for the generated Documenter site's math, search and
navigation. The existing 20-page HTML build can supply a dedicated Pages preview
without repeating Julia builds or fits. Publishing that preview requires a new
public upload and Pages configuration; neither has been performed. The latest
candidate's visual acceptance therefore remains open.

**2026-10-12 approved Pages preview and visualization gallery (JST).** The user
approved publication and requested Wright Maps, Pathway Maps and 3D MGMFRM
illustrations. The [English documentation preview](https://ryuya-dot-com.github.io/BayesianMGMFRM.jl/)
is now public on the separate `gh-pages` branch, commit `726e64c`, with the
[visualization gallery](https://ryuya-dot-com.github.io/BayesianMGMFRM.jl/preview/20261012/visualization-gallery/)
linked from the beginner path. Every manual page identifies the unreleased
preview. GitHub's [Pages deployment](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/38154128252)
passed; all 45 served files match the local publication hashes. `main` is unchanged.

The [756-file isolated candidate and verification](results/workflows/20261012-visual-guide-pages-01/verification.json)
add the gallery, static PNG/SVG figures and a downloadable CairoMakie Pathway
example. Wright/Pathway figures share 80 deterministic artificial display draws;
they are explicitly not fitted posterior evidence. The Pathway example uses
posterior infit mean squares with marginal intervals, distinguished from
standardized-infit versions of the Bond-and-Fox display. The 3D figure reuses
16,000 saved joint draws from a simulated-data fit and displays two abilities
plus category probability, not three latent dimensions or a newly supported
correlation model. Its archived image and rendering-source hashes match.

Five figure-data assertions and 197 documentation-policy assertions pass.
The 21-page manual has 652 checked local fragment links plus checked image/script
targets. Chrome review confirms the three figures, SVG enlargement, typeset
equations, search-to-section navigation and gallery reflow at 390-pixel width.
The [receipt](results/workflows/20261012-visual-guide-pages-01/verification.json)
retains the resource-limited precompilation, corrected execution mode, deployment
metadata checks and certificate-store fallback. No model was refitted. All 746
parent sources, 101 parent evidence files and 526 MS3-bound sources are unchanged.
Four existing missing-docstring warnings and the search-size advisory remain;
live search works. This closes the previous browser-verification obstacle for
the inspected preview pages, not unfamiliar-reader, full-suite or scientific
acceptance. The ordinary occasion-plan failure and its stopped continuation
remain separate unfinished work.

**2026-10-12 visualization review: publication layout and dimensional meaning
(JST).** The user's four questions were checked against the actual
[published-preview source](results/workflows/20261012-visual-guide-pages-01/candidate/ext/BayesianMGMFRMCairoMakieExt.jl),
its numerical consumers, the [APA figure guidance](https://apastyle.apa.org/style-grammar-guidelines/tables-figures/figures)
and the [FACETS ruler controls](https://www.winsteps.com/facetman64/vertical.htm).
This is a source/literature/estimand review and an implementation decision,
not a completed rendering change. The public preview still contains the original
images and example-only Pathway renderer. Existing scientific milestones and
the frozen MS3 run retain their priority and scope.

The five CairoMakie renderer families (posterior, diagnostics, predictive,
Wright and response surface), including prior views routed through them, embed
overall titles and explanatory notes in their figures. The Pathway example does
likewise. There is no common publication-presentation option. APA permits figure
notes; their existence is not a violation. Its figure structure separates the
number/title, image and note, with keys inside the image. Therefore put figure
numbers/titles and explanatory notes in the surrounding guide/report, retaining
axis labels, units, panel identifiers and necessary keys in the image. Provide
the same separation through the plotting/report workflow, not manual image
cropping. Preserve diagnostic warnings, conditioning and provenance in the
accompanying text/metadata. Assess font sizes at final physical output size,
legibility, accessible encodings and exports before claiming APA suitability;
current display font constants and editable SVG/PDF alone do not establish it.
Preserve existing Figure returns and document any default/compatibility change.

**Wright display.** FACETS `Vertical=1*,2N,2A` explicitly combines a person
frequency distribution with item numbers/labels; `C` instead gives counts.
Adopt that familiar arrangement as an additional overview: horizontal person
histogram bars along the vertical measurement axis, beside item/rater locations
and optional boundaries. Retain the existing interval view for individual
uncertainty. Count each selected person once using a declared summary (initially
the posterior median); state bin edges/counts, show the complete selected roster,
and distinguish this shrunken estimate distribution from a population density or
a histogram of pooled MCMC draws. A histogram does not convey individual
posterior uncertainty. Selection/size limits must count displayed individual
marks appropriately rather than rejecting a large cohort solely because its
histogram aggregates more than 60 people. Do not silently omit levels.
The [FACETS scale column](https://www.winsteps.com/facetman64/table6_0.htm)
uses expected-score half-points, whereas our existing optional boundary panel
uses adjacent-category equality. Retain that explicit distinction; a familiar
layout does not imply identical estimation, scoring or threshold definitions.

**One entry point per plot, with model-specific meaning.** Keep `plot_wright`
for both one- and multidimensional fits as support is implemented; default to
named-dimension 2D panels, not one pooled ability or mandatory 3D. The current
implementation still accepts only stable unidimensional MFRM. Pure-Q,
unit-coefficient multidimensional MFRM is the first natural extension. A
correlation between abilities does not merge their constructs or rulers.
For the implemented MGMFRM equation, an adjacent-category boundary on dimension
`d`, conditional on the other abilities and a rater, is

`theta_d = (b_i + s_r + step_ik - sum(a_ij * theta_j, j != d)) / a_id`.

This requires `a_id > 0`, explicit reference conditions, and draw-wise
transformation of the joint samples before intervals are computed. For a pure-Q
item the other-dimension sum is zero; even then raw `b_i` is not the ability
boundary when the loading differs from one. A severity change corresponds to
`delta_s / a_id`, so unequal loadings preclude a single item-independent rater
ruler in ability units. Preserve severity in a separately labelled native-unit
panel or show explicitly item-conditional effects. A mixed-Q boundary is a
line/plane/hyperplane, not a unique item point; any per-dimension slice must
state the fixed abilities. An inactive dimension has no isolated boundary.
The scalar GMFRM is a separate case: its discrimination multiplies the entire
bracket, so its equality location is `b_i + s_r + step_rk`, with rater-owned
steps. Its common ability-coordinate interpretation is possible in principle,
but unit-logit slopes and numerical equivalence to MFRM do not follow. Neither
generalized case is currently implemented by `plot_wright`.

Use 3D only for an explicitly requested geometric question, with projections
and uncertainty interpretation. A three-ability person scatterplot is different
from the current two-ability-plus-probability response surface. Neither replaces
readable per-dimension Wright panels or establishes higher-D fitting acceptance.

**Pathway API.** Promote a qualified `BayesianMGMFRM.plot_pathway` using the
existing `diagnostic_map_data` and optional CairoMakie extension; do not require
users to include an example file. Start with stable MFRM, facets and an explicit
infit/outfit mean-square metric, editable Figure output and matching external
notes. The [Pathway teaching source](https://www.rasch.org/rmt/rmt222a.htm)
combines location, fit and precision; the Bayesian marginal-interval display
must name its own quantities. Reuse shared axis/layout logic with Wright where
appropriate, preserving fixed-anchor markers, counts, numerical flags,
whole-fit diagnostics, missing-data failures and saved-fit reproducibility.
The present example does not expose those contracts: it fixes infit, marks
anchors like estimated points, and gives a generic diagnostic reminder instead
of carrying the fit's actual warning status. Simply renaming it is insufficient.
Horizontal/vertical marginal intervals are not a joint credible region; 1 is
a mean-square reference, not an automatic acceptance rule. Existing
`facets_compatibility_stats` supplies a separate approximate posterior-mean
plugin ZSTD, without propagated posterior uncertainty or FACETS JML equivalence;
do not silently substitute that statistic or apply its cutoffs to mean squares.

Retain the same future Pathway entry point for multidimensional models. Define
the response subset and fit estimand first: a person's pooled infit cannot be
copied into multiple panels and called dimension-specific fit. Pure-Q subsets
can support explicitly conditional per-dimension residual summaries; mixed-Q
responses do not have a unique dimension attribution. The present posterior
`fit_stats`/`diagnostic_map_data` fit-taking methods are stable-MFRM-only, so
multi-model support needs numerical consumers as well as plotting dispatch.
Until those definitions/checks exist, reject unsupported requests clearly.

**Implementation order within MS5:** (1) common external-title/note publication
output and gallery correction; (2) FACETS-style histogram Wright overview;
(3) the stable Pathway API and report/cache integration; (4) pure-Q fixed-unit
dimensional panels; (5) justified generalized/conditional views. Optional 3D
latent geometry comes after those user tasks. Check selected counts/bin edges,
interval/anchor semantics, dimensional labels, unsupported-input rejection,
save/reload and actual publication rendering at each affected step. These are
prospective acceptance checks, not newly passed tests. Reuse existing fits and
valid tests; neither new MCMC nor a broad simulation campaign is needed merely
to change presentation.

Five independent elementary formula assertions passed during this review,
with no package test or fit rerun. For example, `a=(2, 0.5)`, `b=0.6`, `s=0.2`,
`step=-0.4`, fixed `theta_2=-0.4` and `c=1.3` give the conditional boundary
`theta_1=0.3` and adjacent log odds approximately zero; plotting the unscaled
`b+s+step=0.4` instead gives log odds `0.442`. With steps `(-0.4,0.4)`, the
boundary probabilities are approximately `(0.460686,0.460686,0.078627)`:
adjacent equality does not imply marginal probability 0.5. This finite
arithmetic check supports the mapping decision, not calibration or backend
validation. All 756 preview-source and 526 MS3-bound hashes remain unchanged.

**2026-10-12 external figure text implemented and preview published.** Following
the user's explicit instruction, titles and explanatory notes are external by
default in the [isolated publication candidate](results/workflows/20261012-figure-publication-candidate-01/candidate)
([verification](results/workflows/20261012-figure-publication-candidate-01/verification.json)).
`annotation_io = stdout` prints the full text while returning the same editable
CairoMakie `Figure`; a writable stream saves it, and `annotation_io = nothing`
selects the previous embedded layout. Axis labels, units, panel headings and
keys remain in the image. For single-panel figures, the main panel now starts
at `[1, 1]`; examples and help document this migration. The option reaches
posterior, prior, diagnostic, predictive, Wright and response-surface renderers,
including fixed-Q and correlated-result adapters. All three report callbacks
retain titles and complete notes outside the image, alongside their numerical
input JSON and existing report/cache validation. The Pathway example follows
the same default but remains an example, not the prospective formal API.

Validation reuses deterministic fixtures and the existing saved MGMFRM fit:
eight result types/nine model cases, embedded/external text equivalence,
diagnostic status, unchanged plot-mark counts, invalid streams, default output,
cache replay and all three report callbacks. The first run passed 292/317;
22 failed expectations incorrectly assumed short fixtures could always compute
MCMC diagnostics, while three exposed an introduced response-title overwrite.
Focused rechecks passed all 22 corrected diagnostic-status expectations plus
an actual-warning case; the renderer now keeps panel titles separate from the
overall item/rater title, with all nine focused response checks passing.
These give 324 passing drawing/report assertions across stages, **not one clean
full-suite run**. Failed logs and pre-correction sources are retained. All 11
gallery checks, four help-only AST comparisons, 197 example/language checks and
the Documenter build passed. All 21 HTML pages and 655 local fragment links
were checked; the four previously omitted management docstrings and search-size
advisory remain. No posterior fit or statistical replication was rerun.

The [public gallery](https://ryuya-dot-com.github.io/BayesianMGMFRM.jl/preview/20261012/visualization-gallery/)
now places figure numbers, italic titles and notes outside all three images,
with PDF, SVG and full-text-note downloads. One static `gh-pages` push,
`b08c133fe2aec0c90913fdb1b1dc20ef2811d4e7`, deployed successfully in
[Pages run 38156745273](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/38156745273).
All 48 served preview files match the built hashes. Live Chrome review checked
the three figures, separate HTML title/note blocks, the new usage section,
loaded images and no page overflow at a 390-pixel viewport. Browser navigation
to the downloadable text file was blocked by its client; HTTPS retrieval and
hash checks independently verified all three text files and the PDF/SVG assets.
All 756 parent candidate files, 100 parent evidence files and 526 MS3-bound
sources remain unchanged; remote `main` is still `f3fdd658a4c6224f783a3ddf4652c736da06621d`.
The source change remains an unreleased isolated candidate. This completes the
first visualization slice, not automatic APA certification, the histogram
Wright overview, the formal Pathway API, multidimensional Wright/Pathway support
or scientific/release acceptance. The staged priorities above remain in force.

**2026-10-12 histogram Wright overview implemented and published.** The second
visualization slice is complete in the [isolated histogram candidate](results/workflows/20261012-wright-histogram-candidate-01/candidate)
([verification](results/workflows/20261012-wright-histogram-candidate-01/verification.json)).
`plot_wright(...; person_display = :histogram)` counts each person's posterior
median once in horizontal bars on the shared vertical logit axis. The default
remains `:intervals` for individual uncertainty. Integer or explicit finite
bin edges are supported; edges must cover every person. Bins are left closed,
with the last upper edge included. Auto bins use a declared square-root rule
capped at 20, with a ±0.5-logit span for identical medians. The note distinguishes
this distribution of estimates from a population density, pooled posterior
draws and uncertainty in persons or counts; unequal bin widths still encode
counts in bar length, not density. No fitting support is added beyond stable
unidimensional MFRM/RSM/PCM.

The 60-position default now counts individual marks only, so a histogram may
include a larger cohort without silently dropping persons. Item/rater/boundary
limits, original coordinates, credible intervals and fixed-anchor semantics
remain. Report options route through the same numerical preparation; their
figure JSON preserves exact edges/counts and the complete labelled person rows,
including individual intervals. External-title/note defaults remain in force.

The focused run passed 66 numerical and 44 renderer/report assertions. These
cover tied values and final edges, empty/invalid/uncovered bins, unequal-width
bar geometry, all-person accounting, facet order, the individual-position limit,
RSM/PCM with binary/polytomous categories and hard anchors, unchanged default
rows, unsupported generalized fits, random-state preservation, cache replay and
report save/reload. One additional missing-mode rejection and ten gallery
checks passed during rendering. The first attempt stopped before assertions
because the artificial fixture used `logdensities` instead of the existing
`log_posterior` field; its failed log/source are retained, and the fixture was
corrected. No fitting code was changed or MCMC rerun. The 197 documentation
checks and Documenter build passed; all 21 HTML pages and 658 local fragment
links passed after restoring the preview's `siteinfo.js` packaging file. That
packaging step is now included in the build entry point; no successful numerical
checks or document build were repeated. Existing management-docstring omissions
and the search-size advisory remain.

The [gallery's Figure 2](https://ryuya-dot-com.github.io/BayesianMGMFRM.jl/preview/20261012/visualization-gallery/)
uses 80 artificial persons, four items, three raters and 40 deterministic draws,
explicitly not fitted posterior evidence. Its 12 bins over −3 to 3 logits sum
to 80. The prior three figures were retained byte-for-byte. One `gh-pages`
commit, `129182cfdec932f5c3cc0f72b3a446388ff5064a`, deployed successfully in
[Pages run 38158213729](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/38158213729).
All 53 served files match their built hashes; Chrome review confirmed the new
figure, external notes/download links and the published histogram guide.
All 763 parent sources, 109 parent evidence files and 526 MS3-bound files remain
unchanged. Remote `main` remains `f3fdd658a4c6224f783a3ddf4652c736da06621d`;
source integration/release, the unrelated ordinary-suite failure, scientific
acceptance and independent review remain open. This is affected-scope evidence,
not a full-suite or new statistical-validation claim. Next within the existing
visualization order is the stable formal Pathway API with its diagnostic,
anchor, report and cache contracts; multidimensional maps remain subsequent work.

**2026-10-12 item/rater response-surface variants published.** The user's
request to extend Figure 4 is complete in the [isolated gallery candidate](results/workflows/20261012-surface-variants-candidate-01/candidate)
([verification](results/workflows/20261012-surface-variants-candidate-01/verification.json)).
This is a bounded guide/example addition before the next formal Pathway API
slice, not a change to the scientific milestone order. All package `src/` and
`ext/` files, dependencies and prior gallery assets are unchanged. No model
was fitted or statistical replication added.

Figure 5 compares all five items at R1; Figure 6 compares all five raters at I1.
Both reuse all 16,000 joint draws from the same saved experimental fit to
simulated ratings used in Figure 4. Category 4, a 21 × 21 grid from −2 to 2,
viewing angle and probability/color range 0–1 are shared; the common I1/R1
panel is evaluated once and reused. Active Q dimensions are labelled: I1/I2
use the first ability and I3/I4/I5 the second. The original Figure 4 retains
all categories and interval-width heatmaps byte-for-byte. The comparison
images show means only; downloadable JSON retains 90% pointwise intervals,
exact grid/roster/draw indices and source identity. A downloadable CairoMakie
example uses the existing numerical function, returns editable figures and
keeps explanatory notes external by default. The guide distinguishes item
difficulty, loadings, steps and Q; rater severity and consistency; probability
saturation versus an excluded Q dimension; and marginal intervals versus a
within-joint-draw contrast. These images do not establish bias or rater quality.

Validation passed 55 example assertions initially, with four color-range
expectations corrected from tuple equality to the renderer's vector values
and all four rechecked. The saved-fit gallery passed 139 assertions, including
full-roster/draw accounting, fixed references, Q flatness, active-direction
monotonicity, probability/interval bounds, numerical-to-image equality and
JSON round-trip checks. Visual review found clipped decorations; only layout
was revised, using the saved surface summaries without repeating probability
calculations. The first JSON replay stopped before assertions because its axes
needed restoration to concrete Float64 arrays; the corrected replay passed
52 layout/export assertions. Failed logs and pre-correction sources are
retained. These are staged, partly overlapping checks, not a clean full-suite
run. Documenter and 197 documentation checks passed; all 21 pages and 659 local
fragment links passed. Existing management-docstring omissions and the search
size advisory remain.

One `gh-pages` commit, `8a0d9240d343b9547cdc1d20e1084f6311144e34`, deployed
successfully in [Pages run 38186603589](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/38186603589).
All 64 served files match the build. Native Safari review checked both new
figures, their external titles/notes and download links; Chrome subsequently
displayed the item board correctly after an initially blank load. The browser
provider was unavailable, so native app controls supplied the visual review;
no new mobile-viewport test was performed. All 771 parent sources, 103 parent
evidence files and 526 MS3-bound files remain unchanged, as does remote `main`
at `f3fdd658a4c6224f783a3ddf4652c736da06621d`. Source integration/release,
scientific acceptance, independent review and the unrelated ordinary-suite
failure remain open.

**2026-10-12 model-structure and credible-interval guide published.** The
[user-directed explanation audit](results/workflows/20261012-model-interval-guide-candidate-01/verification.json)
adds four English guide updates in an isolated documentation candidate. Existing
advanced source discussions already separated Uto's non-compensatory terminology
from the additive response equation; the beginner theory now gives the concrete
weighted-sum tradeoff and distinguishes it from a binary conjunctive example.
Within-item, between-item, mixed Q, and population correlation are explained as
separate choices, including current fitting restrictions and gallery Q flatness.

The results guide now shows 99% ETIs with both `lower`/`upper` quantile columns
and `intervals` masses, model versus raw coordinates, plotting/surface `interval`,
and matching 0.005/0.995 quantile MCSE. It explains that saved draws can be reused
without refitting and that a new output level does not supply new coverage
validation. HDI/HPD is not an integrated package option; the guide explains its
difference from ETI, skewness, disconnected regions and scale dependence. It
links the separately available PosteriorStats function without installing it,
adding a dependency, or claiming package integration or HDI endpoint MCSE.

The affected examples passed 32 assertions initially; one test incorrectly
expected the surface level in its external note. The existing correct colorbar
label passed a focused replacement assertion; no library correction was needed.
Both logs and test sources are retained. Documenter and 197 documentation policy
assertions passed; 21 pages and 671 local fragment links passed. All 64 publicly
served files match the validated build. Safari visually confirmed the added
code, formulas, Q table and HDI explanation. Existing documentation omissions
and the search-size advisory remain; no new mobile or unfamiliar-reader review
is claimed. This is staged documentation/API-use evidence, not a full-suite or
statistical-validation run.

One `gh-pages` commit, `5fd91fd934cf84a41e7b7659308b05af725c1034`, deployed
successfully in [Pages run 38187964003](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/38187964003).
All 784 parent source files, 115 parent evidence files and 526 MS3-bound files
remain unchanged. Library runtime, dependencies and gallery assets are unchanged;
remote main remains `f3fdd658a4c6224f783a3ddf4652c736da06621d`. The user explicitly
chose to continue estimation; both MS3 workers were observed running, with no
pause/stop signals sent. This bounded guide addition changes neither the
scientific milestone order nor the pending formal Pathway API priority.

**2026-10-12 formal Pathway API implemented in the isolated candidate.**
The [Pathway candidate](results/workflows/20261012-pathway-api-candidate-01/verification.json)
adds qualified `BayesianMGMFRM.plot_pathway` for stable unidimensional MFRM
RSM/PCM. It reuses `diagnostic_map_data`, supports facet order, infit/outfit,
central intervals including 99%, minimum counts and explicit display limits.
Fixed locations retain horizontal fit uncertainty; counts, numerical flags,
whole-fit diagnostics and all retained draws are preserved. Missing/nonfinite
summaries fail explicitly. No recentering, fit-statistic cutoff, joint-region
interpretation or generalized/dimensional attribution is introduced. External
titles/notes remain the default. Report bundles add Pathway PDF/SVG, numerical
JSON and matching notes; cache replay and failed-export preservation are checked.
Multidimensional/generalized requests are explicitly rejected in plotting and
all affected report dispatches. No likelihood, prior, sampler or dependency changed.

The first scoped run retained 239 passing numerical assertions and 298 existing
report-figure assertions; eight new test expectations were incorrect (hard
anchors replace references; Makie stores converted marker paths). Corrected
anchor/render/cache checks and binary-label cases pass 60 assertions. Final
label-layer/gallery checks pass 11. A helper omitted a fixture module alias;
a later combined rendering/build helper shadowed the exported `fit` binding.
Their failures and corrections are retained, distinct from package regressions.
Only affected stages were resumed. The final manual passes 197 policy checks,
21 HTML pages and 676 local fragment-link checks; four existing management-help
omissions and the 612.07 KiB search-size advisory remain. This is staged evidence
on Julia 1.12.5, not a fresh full-suite or platform acceptance run.

The updated [English gallery](https://ryuya-dot-com.github.io/BayesianMGMFRM.jl/preview/20261012/visualization-gallery/?v=c0c7d0f#Pathway-Map:-connect-location-with-response-patterns)
uses the formal API and the same artificial inputs for Figure 3. No new fitting
or scientific replication was needed. Browser review found a cached old image
beside updated text; content-hash asset filenames now bind the figure, note,
numerical inputs and example to the updated page. Documenter rejected the
initial query-string approach, so only the failed documentation stage was rebuilt.
The final [Pages run 38191833826](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/38191833826)
for `c0c7d0f4e01d3554fd01fb469381bef1c76e123b` succeeds and all 71 served files
match the local build. Chrome desktop review confirms the updated count labels,
fixed markers, external notes and direct API example; no new mobile or
unfamiliar-reader acceptance is claimed. This is an unreleased documentation preview; main stays
`f3fdd658a4c6224f783a3ddf4652c736da06621d`. Parent sources/evidence and the
526 MS3-bound files remain unchanged.

Separately, the existing remaining fitting_core continuation passes 6,032
assertions across 26 testsets. The four following groups continue serially;
consult the live queue rather than treating this as full integration completion.
The Pathway slice does not close MS5 or MS3/MS4. Preserve scientific priority
and resolve common-workflow failures before extending visualization scope.

**Design simulation should reuse the existing pieces.** `simulation_grid`
creates planning rows, not fits; `simulate_responses` generates one data set;
`parameter_recovery` scores estimates against truth. Its block-level summary
currently pools parameter rows, not independent replications, and must not be
read as a precision-backed calibration decision. The isolated `recovery_evaluation`
above now provides common named, single-dataset evaluation across eight fit types;
`recovery_replications` adds per-quantity fixed-focal-truth dataset aggregation,
with declared-independence SE, full-roster accounting and explicit verification limits.
It does not pool parameter rows. The project SBC/recovery
scripts add rigorous but target-specific execution and accounting. There is
not yet an integrated public design-planning runner.

The next design API should accept explicit candidate rating assignments (people,
items, raters, categories and overlap), generating truths or distributions,
analysis model/prior, focal estimands, decision loss or precision targets, and
independent replication/seed rules. Keep three modes distinguishable:

| Mode | Question and required output |
| --- | --- |
| Joint-prior SBC | Does the inference procedure recover the declared prior-to-posterior calibration? Use the same generative/fitting prior, rank/ECDF checks and MCMC uncertainty; retain failed and unresolved replications. This is not a sample-size adequacy claim. |
| Fixed/scenario-truth recovery | At scientifically plausible truths, how do candidate assignments affect bias, RMSE, interval width/coverage, correlation recovery and failures? Retain per-estimand repeated-data summaries and replication uncertainty; do not count persons or chains as independent simulated studies. |
| Design assurance / model choice | Under an explicit design distribution and loss/precision criterion, how often does a design achieve its goal, and how stable are model comparisons? Couple model comparisons on the same simulated data; report uncertainty, costs and indeterminate outcomes, not an automatic best-model guarantee. |

SBC uses joint prior draws, whereas deliberately mismatched scenario truths
answer robustness/design questions ([Stan SBC guide](https://mc-stan.org/docs/stan-users-guide/simulation-based-calibration.html)).
Distinguish sampling MCSE within a fit from simulation uncertainty across
independent data sets. Reject unsupported combinations before starting a
batch; preserve all planned failures and separate them from conditional
successful-fit performance. Reuse saved source/input/result identities and
the existing finite-plan/continuation machinery. Independent generator checks
remain necessary when the fitted and generating kernels share code. Function
names and a scientific design are not frozen by this review; no new large
study, cutoff or replication count has been selected.

**The requested LKJ–Cholesky start is implemented as an isolated kernel.**
The [Julia candidate](scripts/mgmfrm_lkj_cholesky_candidate.jl) and
[Stan reference](scripts/stan/mgmfrm_lkj_cholesky_candidate.stan) use D(D−1)/2
unconstrained canonical partial correlations, row-wise as in Stan, to construct
a lower-triangular L and R=LL'. For fixed eta>0,
`log p(L) = constant + sum((D-i+2eta-2)*log(L[i,i]), i=2:D)`;
the Julia raw kernel adds the q→strict-lower-L log Jacobian. With row coordinate
`z[i,j]=tanh(q[i,j])`, the combined coefficient of `log(1-z[i,j]^2)` is
`eta+(D-j-1)/2`. For D=2 this reduces to the existing tanh/LKJ kernel, up to
the q-independent normalizer. The same derived kernel gives marginal
`p(rho[1,2]) proportional to (1-rho[1,2]^2)^(eta+(D-2)/2-1)`;
thus keeping eta fixed across D does not keep the marginal correlation prior
fixed. Prior-predictive inspection must accompany any chosen shape policy.
Independent pairwise tanh correlations would
not guarantee positive definiteness. At D≥3, eta=1 is not constant density
in L coordinates ([Stan LKJ reference](https://mc-stan.org/docs/functions-reference/correlation_matrix_distributions.html),
[transform reference](https://mc-stan.org/docs/reference-manual/transforms.html#cholesky-factors-of-correlation-matrices)).

[508 checks](results/workflows/20261011-lkj-cholesky-math-01/verification.json)
pass on 48 dimension/shape/point combinations: D=2,3,4,6 and eta=.5,1,2,2.5.
They include a closed-form 3D example, a non-positive-definite pairwise
counterexample, inverse/positive-definiteness checks, independently differentiated
Jacobian, transported correlation-density kernel, analytic/AD/central-difference
gradients, and preservation of marginal ability scales under `theta=diag(sd)*L*z`.
Maximum errors are 2.22e-16 (log Jacobian), 1.78e-15 (density transport),
4.44e-16 (analytic/AD gradient), and 2.51e-10 (central differences). The Julia
check took 4.79 seconds with 0.424 GiB peak observed process RSS, and zero fits.
CmdStan 2.39.0 `stanc` passes syntax/type translation in 0.11 seconds. Its
pedantic no-prior warning is retained: L has an explicit LKJ prior with the
shape supplied as data. That initial receipt did not include a native build
or density/gradient execution; the follow-up below now supplies that evidence.

**2026-10-11 native LKJ–Cholesky follow-up completed.** The opt-in
[native check](test/mgmfrm_lkj_cholesky_native.jl) compiles the unchanged Stan
reference and passes **1,124 assertions** on Julia 1.12.5 / CmdStan 2.39.0.
The [receipt](results/workflows/20261011-lkj-cholesky-native-01/verification.json)
covers **80 distinct finite points**: D=2,3,4,5,6, eta=.5,1,2,2.5, and four
coordinate vectors per condition, including coordinates up to magnitude 2.5.
Each point is evaluated with both constrained-L and unconstrained-q input,
with the native Jacobian both enabled and disabled (320 density/gradient
evaluations, not independent statistical replications). Native reverse-mode
gradients match Julia ForwardDiff, the difference of the two modes matches
the Jacobian and its gradient, and the constrained-input path checks the
inverse transformation and coordinate order. Generated quantities check
R=LL' and the **full**, normalized Cholesky density.

The independent normalizer uses partial-correlation beta factors:
`alpha_j = eta + (D-j-1)/2` and
`C(D,eta) = -sum((D-j)*log(Beta(1/2,alpha_j)), j=1:D-1)`.
Before the tanh transform each factor is proportional to
`(1-z^2)^(alpha_j-1)`; its Jacobian adds one exponent in q coordinates.
Thus the normalized q density is the original kernel plus C. CmdStan's
`log_prob` service drops q-independent constants, so that output alone does
not validate normalization. The separate full `lkj_corr_cholesky_lpdf`
generated quantity agrees with the beta-product expression, including the
exact D=2/eta=1 and D=3/eta=1 constants. Invalid D/eta native requests are rejected.
See the [Stan LKJ API](https://mc-stan.org/docs/functions-reference/correlation_matrix_distributions.html)
and [density/gradient command](https://mc-stan.org/docs/cmdstan-guide/log_prob_config.html);
the web manual displays 2.40, while this check binds local 2.39.0 sources.

Maximum absolute errors are 4.43e-12 (kernel), 9.05e-12 (gradient), 6.59e-13
(Jacobian or its gradient), 1.10e-11 (constrained/raw input agreement),
4.12e-12 (normalization), and 3.33e-16 (R). The predeclared native tolerance
was 1e-8, with a 1e-10 matrix tolerance. Total elapsed time was 25.34 seconds,
including a 6.87-second native build, and peak observed descendant RSS was
1,611,956,224 bytes. This overlaps MS3 and ordinary API tests; it is not a
backend performance comparison. The 508 earlier mathematical checks were
reused, not repeated. All 526 frozen MS3 files and both 740-file API snapshots
remain unchanged. Only the new opt-in test, its evidence and this roadmap
were added/updated; there are zero new posterior fits or formal replications.

This kernel omits the fixed-D/eta normalizing constant and is not an eta-estimation,
model-evidence, prior-generator or MGMFRM fitting API. The normalizer above is
a test oracle, not a change to that kernel; eta derivatives and extreme-boundary
behavior were not validated. The next correlation-extension step is an explicitly
identified fixed-Q 3D rating-model candidate, after the common API's current
integration work. Preserve fixed marginal scales,
positive loading/sign and dimension-label conventions, cross-dimension data
overlap, and the declared prior measure; general covariance alone does not solve
loading/rotation identification. Centered/noncentered person coordinates need
their own density/likelihood and saved-output checks. Do not reuse the independent
foundation location transform without a new correlated-target derivation.
Recovery/SBC, prior sensitivity, prediction and failure evaluation follow that
implementation; broader cross-loadings and arbitrary D are not already accepted.

Only new standalone source/test files and this roadmap changed. All 518 frozen
MS2 source/environment file hashes were checked unchanged. The brief no-MCMC
check overlapped attempt 8 and has its own UTC timestamps/cost receipt; it is not
part of the benchmark cost or independent validation denominator. Production
exports, dependencies and running samplers were not changed. MS1→MS2→MS3→MS4
remains the current scientific sequence; the user-facing comparison/design
work belongs to the shared workflow, and the correlation prototype is a
separate, explicitly limited model-extension preparation.

**2026-10-11 continuation: MS1 closed; MS2 native mathematics checked, execution
integration still in progress.**
The [pilot closeout receipt](results/workflows/20261006-foundation-prediction-pilot-01/continuations/20261009-01/closeout.json)
now validates all 240 terminal attempts, 239 completed fits, the one retained
external storage interruption, 228 numerically eligible fits and 37/48 eligible
panels. Both historical guards completed; the current host check found no pilot
workers. The updated closeout validator passes ten focused tests. It permits
only a consistent repository-prefix relocation, with frozen source/input/output
hashes checked. Recomputed named aggregates permit relative roundoff of 1e-12
or absolute roundoff of 1e-14; all other values/types, fit rows, eligibility,
hashes and planning decisions remain exact. The receipt records all 225 changed
float values (maximum absolute difference 7.192e-13) and both Python environments.
Original summaries and receipts were not rewritten. The unchanged planning rule
gives 128/32/32 blocks at SE targets 0.005/0.01/0.02 nat; main N is still not
formally selected and no main launch is enabled. Closeout SHA256 is
`da7c5248e792ace3410edaa856afaecdd7a789d729382666484f6b0d45efadb1`.

After MS1 closure, the opt-in [Stan location model](scripts/stan/mgmfrm_foundation_location.stan)
and [data/build bridge](scripts/mgmfrm_foundation_location_stan.jl) implement q →
raw beta, preserving the original normalized-C prior and likelihood. The bridge
requires the closed pilot and unchanged eight-case design. The candidate restricts
its native input domain to the declared 50-person/5-item/5-rater/4-category,
independent 2D pure-Q, 1,000-training-row model. It does not extend package defaults.
[431 checks](test/mgmfrm_foundation_location_stan.jl) pass on Julia 1.12.5 /
CmdStan 2.39.0 for all eight prospective comparison targets, including both
historical numerical failures. Five points per target comprise zero, two fixed
vectors and the first/last retained raw draws from the saved fit. Native q
densities/gradients agree with Julia and the separately compiled unchanged raw
Stan reference; both Jacobian modes agree. Forty fixed-parameter evaluations
also verify q initialization, native raw-beta output, inverse transformation and
all observed pointwise log likelihoods. Six malformed native inputs are rejected.
Maximum discrepancies are 5.457e-12 (density), 1.001e-11 (Julia gradient),
1.819e-12 (raw-Stan gradient transported to q), 3.997e-15 (raw output) and
5.685e-14 (pointwise log likelihood).

The [native preflight receipt](results/workflows/20261011-location-stan-preflight-01/check/verification.json)
and [resource receipt](results/workflows/20261011-location-stan-preflight-01/guard-receipt.json)
bind sources, evidence, saved draws and executable identity. The run took
35.69 seconds, with 2.15 GiB peak observed descendant RSS and no elapsed-time cap.
These are deterministic fixed-parameter evaluations, **zero posterior fits and
zero independent statistical replications**. The 40 points are preliminary native
checks, not the complete preflight required by foundation §26. The initial
description of them as the completed MS2 native preflight was too broad.

The subsequent [259-point-per-target check](test/mgmfrm_foundation_efficiency_preflight.jl)
now passes **10,423/10,423 assertions** on all eight targets, reusing both native
executables without rebuilding or sampling. It checks zero, ±0.1sin(i), and every
±0.1 coordinate point; zero and the positive sine point also use independent
central differences with step 1e-5. Maximum errors are 9.095e-13 for the
zero-referenced density difference, 3.919e-13 for the scaled Julia/native gradient,
9.459e-14 for the scaled transported raw/native gradient, 8.709e-15 for the
log absolute Jacobian, and 1.683e-7 for the scaled central-difference gradient
(required limits 1e-8 for gradients and 1e-5 for central differences).
The [mathematical receipt](results/workflows/20261011-efficiency-math-preflight-01/check/verification.json)
and [resource receipt](results/workflows/20261011-efficiency-math-preflight-01/guard-receipt.json)
record completion in 31.72 seconds with 1.31 GiB peak observed descendant RSS.
These finite-point checks do not constitute a general mathematical proof.

The [comparison adapter](scripts/mgmfrm_foundation_efficiency_adapter.jl) now
passes [82 no-MCMC integration checks](test/mgmfrm_foundation_efficiency_adapter.jl).
Heldout-only response changes leave the training target/native data unchanged;
training-response changes, overlapping splits, changed bindings and wrong stored
coordinates are rejected. Initial raw jitter and native master+1:4 chain seeds
replay exactly; the Julia gradient target retains ForwardDiff Chunk{12}.
Native CSV ingestion checks q-to-raw values, the warmup boundary, every retained
pointwise likelihood and the posterior density constant. Synthetic native
telemetry applied to one existing pilot record tests save/reload and the shared
diagnostic/scoring path; the original qualification and all four scores/MCSEs
are recovered. This is a record-adapter test, **not a native HMC run or posterior
agreement result**. All 292 block-labelled quantities retain their own mean,
SD and 5%/95% quantile MCSEs, including repeated quantities across blocks.

The [adapter receipt](results/workflows/20261011-efficiency-adapter-preflight-01/check/verification.json)
and [resource receipt](results/workflows/20261011-efficiency-adapter-preflight-01/guard-receipt.json)
record 51.30 seconds and 2.20 GiB peak observed descendant RSS. A separate CPU
workload verifies Darwin's completed-descendant accounting: 0.68961 seconds of
native child CPU is included once in 0.72486 seconds of completed-child CPU;
exclusive Julia CPU is added separately. The [command wrapper](scripts/mgmfrm_efficiency_command.py)
retains individual exit-time CPU, failed exits and launch errors and passes two
focused tests. Its per-chain wait4 values are a breakdown, not added again to
the cumulative child CPU.

The [pure comparison evaluator](scripts/mgmfrm_foundation_efficiency_compare.py)
passes seven [decision tests](test/mgmfrm_foundation_efficiency_compare.py), with
the [check receipt](results/workflows/20261011-efficiency-comparison-check-01/verification.json)
binding its code and preceding checks. The tests distinguish difference,
statistic-specific MCSE and resolution, preserve the 18,752-comparison denominator,
reject changed targets/rosters/global weights, retain failed-attempt costs, and
require both repetitions and the declared stress cases. Diagnostic/resource
warnings never become agreement passes. These are synthetic decision fixtures,
not evidence that the candidate meets the adoption rule.

At that checkpoint, the serial controller, common timing, resource/overlap
monitoring and execution plan still needed integration. The later launch above
supersedes that execution status. Native target agreement does not close MS2's
precision/cost/adoption decision or alter previous calibration failures.

**2026-10-11 user direction: examine the mathematics, use Stan as an independent
computational reference, then check the Julia implementation.** The working
sequence is equations/estimands/identification and prior measures → deterministic
native Stan density/gradient checks → Julia coordinate and gradient equivalence
→ same-target sampling/precision/cost → statistical claims and the public workflow.
Stan agreement is evidence about implementation, not a proof of identification,
appropriate priors, calibrated intervals or sufficient MCMC precision. Reuse the
existing derivations and completed assessments; do not restart them or add the
future model extensions to the current foundation scope. The deterministic
check below uses unchanged production Stan code and no sampling. It can proceed
before MS1 closure; construction and fitting of the new MS2 Stan candidate still
follow MS1. The scientific sequence MS1 → MS2 → MS3 → MS4 is unchanged.

**2026-10-11 native reference check completed.** The opt-in
[Stan/Julia coordinate check](test/mgmfrm_stan_location_chainrule.jl) passes
**240/240 assertions** on Julia 1.12.5 / CmdStan 2.39.0. It reconstructs the frozen
pilot's B001, fold 1 training targets for R0/R1 × loading-prior SD 0.25/0.5/1.0,
checks their exact target identities, and evaluates three deterministic vectors
per target: 18 target–vector cases, each with 1,000 training observations and
128 free parameters. An explicit normalized zero-sum Gaussian density, direct
ordinal likelihood, dense Householder map and analytic derivative provide
separate reference calculations. The checks restore the known constant omitted
by Stan's proportional normal density, compare both native Jacobian modes,
transport the native raw gradient into Julia's sampling coordinates, and compare
every observed pointwise log likelihood. Maximum absolute discrepancies are
2.706e-11 for the joint log density, 7.276e-12 for raw/transformed gradients,
2.843e-14 for pointwise log likelihood and 8.709e-15 for the transformation's
log absolute determinant. Nonzero examples also reject incorrectly assigning
the original independent priors to the new item offsets.

The [verification receipt](results/workflows/20261011-stan-foundation-check-03/check/verification.json),
[test log](results/workflows/20261011-stan-foundation-check-03/command.log) and
[resource receipt](results/workflows/20261011-stan-foundation-check-03/guard-receipt.json)
retain identities, versions, errors and controls. The successful run took
36.78 seconds with 2.15 GiB peak observed descendant RSS and no elapsed-time cap.
Two preceding guard attempts are retained: the first could not observe processes
inside the sandbox and launched nothing; the second stopped when a descendant
created a separate process group. The successful run used the existing explicit
descendant-group option with identity/RSS monitoring retained. Neither earlier
attempt is a mathematical test failure. Production sources and saved fits remain
unchanged. This adds zero posterior fits and zero statistical replications; it
does not implement or validate the future transformed-coordinate Stan sampler,
complete the eight-target MS2 preflight, or establish speed, mixing or calibration.
The complete-crossing identification derivation also remains distinct from a
general identification theorem for the pilot's heldout training designs.

**2026-10-04 user direction: prioritize mathematical foundations and the analysis
contract before OS-specific tests and distribution policy.** Existing derivations,
numerical checks and saved fits are the starting evidence. The immediate work is
to connect assumptions and identification to the quantities being estimated,
their prior dependence, computational precision and the claims an evaluation
could support. Distribution readiness is a later milestone, not the next research
dependency. Do not equate passing tests with statistical acceptance.
The normalized coordinate route and the four-fit loading-prior comparison remain
experimental. The six-fit R0/R1 rehearsal retains four numerical passes and two
R-hat failures, with zero evaluation credit. Independent review and scientific
prior/domain choices remain open; all three calibration margins remain in scope.
The [current assessment](#current-assessment-and-next-exits) and its next exits
own the work order; scheduling language in dated records is historical.
The [2026-09-30 strategic review](docs/internal/strategic-review-2026-09-30.md)
keeps integration, independent usability review and scientific acceptance as distinct exits.
The [2026-09-27 review](docs/internal/strategic-review-2026-09-27.md) retains the earlier evidence and decisions.

**2026-10-09 user direction:** finish the frozen prediction pilot, then compare
its target/results with a more efficient implementation before launching the
fresh main assessment. Prefer the faster implementation only after target,
diagnostic and precision checks pass. The [comparison handoff, foundation §26](docs/internal/mgmfrm-foundation-scale-acceptance.md)
defines this new stage; no candidate fitting starts during the pilot.

**2026-10-09 user correction: empirical fitting follows model API finalization.**
Chopin, Uchihara and EVA are downstream applications. Preserve the completed
input audits as requirements and future fixtures; do not advance their empirical
fits, application-specific prior selection or analysis reports while the model
API is unsettled. Develop and validate the selected foundation on synthetic data.
Generic issues exposed by an application, such as reference-dependent priors,
belong in that mathematical/API work with controlled examples.

API finalization means a documented, versioned contract for the selected model
scope: likelihood, constraints and prior measures; data/facet/category roles;
fit and result types; diagnostic/MCSE and prediction semantics; and save/reload
compatibility. The supported synthetic workflow must pass relevant numerical,
statistical and integration checks with its limitations recorded. Existing
application adapters do not establish this exit. Finalization does not require
all future model extensions or OS/distribution completion, and each application
must fit within the finalized supported scope. Keep pilot closure → matched
efficiency comparison → adopted implementation → fresh main as the immediate
scientific sequence; integrate and finalize the shared API before applications.

**2026-10-09 application checkpoint:** the
[updated portfolio](docs/internal/application-portfolio.md) separates the Chopin
input audit, the synthetic Uchihara A0 workflow and the unstarted empirical
reanalyses. Chopin's [first-stage input and unidimensional specification](docs/internal/chopin-stage1-analysis.md)
now preserve 84 performance names, 17 judge columns, 1,395 raw ratings, 33 recusals
and PDF positions. An independent coordinate extraction agrees on names and all
raw/corrected cells; 19 Julia checks preserve 25 categories and the existing
123-parameter target. No empirical fit has started. Preserve this input checkpoint
until API finalization. Reference-judge dependence and asymmetric derived
last-step variance are generic prior issues for controlled foundation checks;
Chopin-specific prior selection and focal precision declarations follow the API
exit. The default free-coordinate prior is only an engineering candidate. This
example does not need the full multidimensional/shared-effect extension.
Uchihara's existing A0 already has correlated speaker/recording effects, sparse
paired ratings and limited new-recording integration. Reuse that implementation:
its saved 16-draw engineering runs still have no qualified focal quantities.
The new complete-crossing, scalar shared-task prototype is a different target,
requires at least four criteria and does not replace A0 or fit the actual
two-criterion data. Reuse synthetic A0 only when it resolves a declared foundation
or API question; a standalone application report is not the next deliverable.
Real-data population/source/missingness reconciliation remains a later application
task. Track
application progress by reproducible answers and their uncertainty; more model
code and passing checks alone add no application acceptance. The current pilot,
matched efficiency comparison and fresh main retain priority. Completed input
work is retained; further application work waits for the relevant API exit.
Neither application becomes a prerequisite for foundation completion, and EVA
remains a later candidate. Historical time-limit proposals do
not override the user's current no-elapsed-time-limit direction.

**2026-10-09 analysis integration and next model extension:** adopt the
[shared prediction contract and four-facet design](docs/internal/prediction-contract-four-facet-design.md)
as the implementation handoff. Common observation identities, category log
probabilities, pointwise likelihoods, prediction conditioning and model/scale
metadata should cover correlated and normalized MGMFRM as well as the legacy
and fixed-coefficient multidimensional fit types.
Implement extraction/alignment before connecting each analysis, preserving
explicit comparison axes and training/heldout bindings. Separately distinguish
person, physical task, rater and criterion in the first model extension.
Thirteen exact-rank examples and five lightweight tests check its fixed-coefficient
location design, including the failure of a single criterion zero-sum in the
multidimensional case. These are design checks, not new model fitting or
statistical acceptance. Pilot closure, matched efficiency comparison and the
fresh current-domain assessment retain their order; neither the full four-facet
extension nor every report feature is a prerequisite for that assessment.
The [opt-in extraction prototype](scripts/prediction_observation_adapter.jl)
now supports eight fit types, including independent/correlated fixed-coefficient
MFRM and its exchangeable-rater variants, without changing frozen package sources.
The fixed-coefficient output retains unit-logit semantics even when a legacy
record or internal calculation uses an MGMFRM reference. The common criterion
consumer requires all retained chains/draws and explicitly distinguishes WAIC,
raw importance-sampling LOO and the repository's Hill-tail smoother. It keeps
sampling/criterion warnings and affected observation IDs. Native pointwise SE
and importance ESS are not cluster-adjusted SE or autocorrelation-adjusted MCMC
precision; reference PSIS agreement is not established. The initial 560-check
extraction validation remains dated evidence in §6 of the handoff; its extension
passes 1,087 focused checks, including the prior checks and read-only saved-pilot
replay, as recorded in §7. No new posterior fit or replication was added. Package/report
integration, reference PSIS validation, calibration and category-functioning
consumers remain separate next steps. The prototype uses original training rows
and existing levels; it adds no common-fold refitting or new-level prediction.

**2026-10-09 shared effects, learned rater scales and new-level prediction:**
the [implementation handoff](docs/internal/shared-effects-hierarchy-prediction.md)
extends the four-facet design with one person–task/testlet shared effect first,
then supported rater–response and rater–criterion blocks. Fixed-scale priors
already shrink effects; estimating their scales learns the strength of pooling.
Seven exact covariance-design cases distinguish crossed support from aliases,
including the limits of full covariance rank without repeated indicators.
Nine scale cases check normalized zero-sum densities, log-scale Jacobians and
centered/noncentered agreement. Six lightweight tests also cover joint versus
marginal scoring and the population assumptions missing from simply appending a
new rater to a finite zero-sum panel. These are mathematical oracles, not new
fitted mechanisms or ordinal-identification evidence. Preserve one draw of each
shared effect within its prediction group, label fixed-prior versus learned
population prediction, and match holdout and score units. Reuse the existing LD
support/residual machinery; its broader-fit entry point, sampler/report integration,
population prediction and prospective statistical validation remain to be built.
The ongoing pilot and the current-domain main assessment do not acquire these
extensions as prerequisites.

The [opt-in shared-task density core](scripts/four_facet_shared_target.jl) now
implements the first new likelihood and normalized prior: 2D pure-Q four-facet
partial credit, separate physical task/criterion effects and a noncentered
person–task effect with an explicit half-normal scale prior. The initial scope is
complete crossing, one distinct response per person–task, consistent category
direction and at least two criteria per dimension. Task/rater and within-dimension
criterion means are zero; centered criterion steps use orthonormal coordinates.
The input spec supplies data/Q, while this new target owns its constraints and
priors. Its 77 focused checks cover density/AD, conditional prediction, facet
relabeling, input ownership and target-record reconstruction; maximum observed
gradient discrepancy is 1.54e-9 and native zero-effect likelihood discrepancy
4.44e-16. These checks are separate from posterior inference. The subsequent
[opt-in Stan target](scripts/stan/four_facet_shared_task.stan) and
[data/build bridge](scripts/four_facet_shared_stan.jl) now pass 227 focused checks:
four crossed designs, 2–5 categories and 28 declared parameter vectors, including
unequal Q groups, zero shared values, extreme logits and log-scale underflow.
Complete normalized densities, both Jacobian modes, gradients, pointwise likelihoods
and all-category probabilities agree; the maximum density and gradient differences
are 2.80e-9 and 1.07e-14. Seven malformed native inputs are rejected. This uses
CmdStan log_prob/generated quantities without sampling, separate from the frozen
pilot's future efficiency comparison. The subsequent
[opt-in Julia workflow](scripts/four_facet_shared_workflow.jl) now adds joint prior
draws, conditional replicated ratings, a maintained AdvancedHMC sampler connection,
validated sample records, model/raw diagnostics and original-row posterior mean
category probabilities. One declared 144-row/35-parameter engineering fit uses
four chains of 500 warmup + 500 retained draws: retained divergences 0, maximum
rank-normalized R-hat 1.0051, minimum bulk/tail ESS 616/714; 15 warmup divergences
remain recorded. The positive shared SD has no directional evidence against zero
by construction, so the report suppresses that misleading probability. Prior
prediction compares explicit half-normal scales 0.35, 0.7 and 1.4 with Monte Carlo
precision; it selects no scientific prior. Initial validation passes 65 checks;
the report refinement passes 66 checks on the saved fit, without another MCMC run.
The handoff's §§7–9 record the evidence. Public fit/report integration, a matched
Stan posterior run, prediction MCSE, new levels and residual diagnostics remain
open. Next declare independent recovery/prior-sensitivity/failure experiments
with precision targets; this one fit adds no statistical acceptance or pilot
replication. Pilot closure, same-target efficiency comparison and fresh main
retain priority.

- **Scope:** the user-selected 2D fixed-Q foundation. Candidate C is an explicit
  normalized exchangeable prior for computational comparison, not an adopted
  scientific prior or a new default. Preserve the distinct raw/source targets.
- **Evidence:** the completed 32-block fixed-facet assessment has 192 finished
  fits, 184 numerical passes and eight retained loading R-hat failures, with
  paired recovery/prior-sensitivity summaries, replication MCSE and condition-wise
  failure intervals. Narrow SD 0.25 is computationally easier but shows strong
  R1/I1 undercoverage (1/32 confirmed, none unresolved). Earlier two-panel C
  checks, the four-fit sensitivity comparison and their warnings remain dated
  evidence below. No calibration, heldout-prediction or supported-domain
  acceptance is claimed. The same-data raw and shorter-window failures remain;
  the raw cohort stays 4 completed / 1 failed / 269 unstarted out of 274.
  The cohorts are not pooled, and computation-only replays add no replication.
- **Criteria:** retain comparisons at ±2.5, ±5 and ±7.5 percentage points. The
  all-150-quantity positive-acceptance claim remains open; do not drop difficult
  quantities after observing results or make this claim a prerequisite for
  every experimental workflow improvement.
- **Work order:** mathematical and estimand assumptions → prior interpretation →
  posterior-computation precision → claim-specific statistical assessment →
  delivery and extensions. Reuse completed proofs and checks; add work only for a
  named missing argument or an unresolved analytical question. A numerical defect
  that invalidates an analysis remains urgent. OS fixtures, distribution gates,
  presentation polish and further general optimization are deferred unless they
  prevent this research work. Independent scientific review informs acceptance;
  an unassigned reviewer does not prevent derivation or saved-result analysis.
- **Ordinary-test runtime (user decision, 2026-10-02):** no per-run or batch
  elapsed-time cutoff. Monitor progress and resources until completion; elapsed
  time is a measurement, not a pass/fail or cancellation criterion. Use
  `wall_seconds=None` and `batch_deadline=None` with the resource guard. Earlier
  time-limited receipts remain historical evidence. Scientific replication and
  sampling conditions remain separate from this ordinary-test policy.
  The [runtime policy and guard verification](results/workflows/20261002-test-runtime-policy-01/policy.json)
  record the controller change and 26 passing checks. The subsequent
  [ordinary integration run](results/workflows/20261002-integration-01/verification.json)
  completes all six current-version groups and the minimum-version all run.

### Current assessment and next exits

**Strategic review, 2026-10-06.** The first prospective descriptive study and the
selected computational comparison are complete. The project can now describe
condition-specific recovery, prior sensitivity and numerical failures with
replication uncertainty. Scientific acceptance of a useful MGMFRM domain remains
open. Count completion against each declared study or claim; 192/192 finished
fits is not a percentage of overall scientific readiness.

| Question | Evidence reached | Remaining boundary |
| --- | --- | --- |
| Mathematical target and interpretation | The [identification and estimand derivation](docs/internal/mgmfrm-estimands-identification.md), normalized prior, location transform and density/gradient checks cover the declared complete-crossed pure-Q setting under their stated assumptions | Centered abilities retain scale dependence. Posterior propriety does not establish mixing or coverage. Sparse training designs, mixed Q and free latent correlation do not inherit the dense identification result; independent scientific review remains open |
| Recovery, prior sensitivity and numerical failures | The [completed assessment, foundation record §20](docs/internal/mgmfrm-foundation-scale-acceptance.md) accounts for 32 independent paired blocks, 192 completed fits, 184 numerical passes and eight retained loading R-hat failures | Continuous summaries condition on qualification; variants share datasets. Even 0/32 failures has a pointwise exact 95% upper limit of 10.89%, so low failure probability is not established |
| Prior adequacy and calibration | Under R1 / loading-prior SD 0.25, all 32 fits qualify numerically, yet I1's nominal 90% interval covers the fixed truth in only 1/32 cases, with no unresolved classifications | This is a substantive limitation of this prior/condition, not a reason to choose another prior after observing its RMSE. N=32 cannot establish any of the three calibration margins under the retained exact-interval rule. Fixed-facet coverage and joint-prior SBC remain distinct claims |
| Heldout prediction | The binding/replay checks pass 543/660 assertions and panel/planning arithmetic passes nine tests. The [eight-block, 240-fit pilot, §§24–25](docs/internal/mgmfrm-foundation-scale-acceptance.md) stopped after 115 completed fits when host storage filled. Saved draws restore one further fit without sampling: the recovery checkpoint has 116 completed fits, one recorded external interruption, 123 unstarted fits and 19 qualified panels. Four numerical failures remain in three panels; the external interruption makes a fourth panel ineligible. Eight continuation tests and byte-identical replay of a completed fit pass. Only the 123 unstarted IDs resume, under the original frozen conditions | Neither the pilot nor the main C heldout assessment is complete. The 90-fit comparison results in §24 remain historical snapshots; small-sample variances and paired-difference precision are unresolved. Keep external interruptions distinct from numerical failures, retain planned denominators and never renormalize partial folds. Main N is unselected: use the fully validated continuation summary after every planned fit is terminal, not the preserved interruption-time summary. The target remains five-fold prediction of known people/items/raters after 1,000 training ratings; prior ranking/equivalence, new levels and performance after fitting all 1,250 ratings are not established |
| Computational efficiency | Fitting accounts for 96.20% of summed attempt durations in the completed 192-fit assessment. The [four-fit comparison, §22](docs/internal/mgmfrm-foundation-scale-acceptance.md) preserves all saved numerical results, with measured time reductions of 26.24% and 2.12%. The current pilot also records per-fit CPU, compilation and GC time | The earlier ≥5% improvement on each target was not met; retain Chunk 12 throughout the pilot. After pilot closure, the newly requested comparison in §26 first considers Stan with the same target/coordinates, against freshly timed Julia baselines. Validate density/gradients, posterior summaries and heldout scores before comparing cost at the required precision. The old small-model Stan timing advantage is motivation, not a speed claim for this target |
| Delivery and independent review | Local ordinary integration and the experimental fit/save/report workflow are complete | Hosted CI/OS/distribution, unfamiliar-reader review and independent scientific acceptance remain separate later exits; test counts do not substitute for them |

The main remaining uncertainty is which scientific interpretations and predictive
claims the declared prior/domain supports. The earlier four-fit comparison is
closed; its adoption rule and results are not rewritten. The user's new
post-pilot comparison addresses the cost of the forthcoming main assessment,
with its own prospectively frozen cases, numerical agreement margins and speed
decision. It adds no independent scientific replications. Record process CPU
and elapsed time from the start, retaining failed attempts and uncertainty.
No elapsed-time cap is introduced.

### Completion milestones

**2026-10-09 completion contract.** The first finish is a reviewed, reusable
MGMFRM foundation with an explicit supported domain and a finalized model API.
The present evaluation domain is normalized C, two independent dimensions,
fixed pure Q, 50 people / 5 items / 5 raters / 4 categories, with R0/R1 and three
loading-prior widths. The prediction claim concerns known facet levels after
1,000 training ratings. Other domains need their own evidence; these dimensions
and counts are evaluation conditions, not universal package input limits.
Preserve existing MFRM/GMFRM behavior and declare which result types and functions
are included in the API candidate. Applications, all future model combinations
and OS/distribution completion are separate later finishes.

Use three distinct judgments. **Study closed** means every planned outcome,
failure and unresolved quantity has been accounted for. **Claim supported**
requires its declared evidence and precision criteria; a closed study can reject
or leave a claim unresolved. **Foundation complete** requires the accepted scope,
verified common workflow and independent review in MS6. A negative finding does
not authorize silently reducing the objective or calling an unrun study complete.

The 32-block / 192-fit recovery assessment, its eight numerical failures, the
earlier Chunk comparison and the training/heldout binding audit are completed
inputs to these milestones. Reuse them; no automatic repeat or successful-only
replacement is scheduled.

| Milestone / responsible role | Dependency and current state | Required artifact and completion condition | Consequence of a negative or unresolved result |
| --- | --- | --- | --- |
| **MS1 — Prediction pilot closure** / analyst | **Closed 2026-10-11.** The validated final continuation retains 239 completed fits, one external storage interruption, 228 numerically qualified fits and 11 numerical failures; 37/48 five-fold panels are eligible. Relocation and aggregate roundoff are documented in the v2 closeout receipt; original records and decisions remain intact | [Passing closeout receipt](results/workflows/20261006-foundation-prediction-pilot-01/continuations/20261009-01/closeout.json): all 240 attempts terminal, all 48 panels accounted for, no live pilot workers observed, source/input/output hashes intact. Failure classes, precision and known/unknown costs are preserved | Closure is accounting, not scientific acceptance. All 13 planning groups have at least three eligible blocks; MS2 closure selects N=32 at SE 0.01 nat; the separate MS3 plan is frozen and execution is running, with scientific conclusions still open |
| **MS2 — Efficiency and implementation decision** / numerical analyst, maintainer | **Closed 2026-10-11.** The [closeout](results/workflows/20261011-foundation-efficiency-01/closeout.json) accounts for 31 qualified completed fits and one retained storage interruption, all 32 attempts terminal. Fifteen completed pairs have unresolved full posterior precision and cost flags. Stan is not adopted; the exact Julia baseline and main N=32 are fixed | Before candidate sampling, freeze case IDs, seeds, repeated/interleaved timing, complete quantity roster, numerical agreement tolerances and minimum useful speed improvement. Then archive same-target density/gradient checks, posterior/prediction agreement at adequate MCSE, qualified ESS per CPU/elapsed second, memory and every failed attempt. Finish with an adoption decision and the exact implementation/source/control identity for MS3 | Faster implementation is adopted only when target, precision and cost conditions all pass. Rejection or inconclusive benefit closes the comparison with the baseline retained; faster execution is not required to finish MS2. A target mismatch never counts as an optimization |
| **MS3 — Fresh main prediction assessment** / analyst | **Running 2026-10-11.** MS1/MS2 are closed; the [frozen main and launch](results/workflows/20261011-foundation-prediction-main-01/launch.json) bind N=32 fresh paired blocks (960 fits), the retained Julia implementation, validated continuation summary, all new inputs/seeds, resources and reporting rules. Preparation and execution-entry checks passed; the first actual main fit completed, passed its diagnostics and had all four saved scores verified. Two workers are now running under the measured resource rule | Freeze a new main plan using the unchanged pilot-based N rule below, new data/seed blocks, implementation hashes and all primary quantities. Complete and account for every planned attempt; publish all six condition means, seven paired contrasts, secondary scores, replication SE, MCMC MCSE, eligibility and failures with reproducible summaries | Precision shortfalls or weak differences produce an inconclusive assessment, not an extension until favorable. An unselected N or unrun cohort keeps MS3 open. If a different design is needed, record a separate prospective decision and retain the original result/status |
| **MS4 — Supported-domain decision** / analyst, maintainer; independent review in MS6 | Draft evidence mapping can proceed now; final candidate decision follows MS3. Scientific prior/domain adoption is open | One claim-by-condition table links formulas, scale/constraints/normalized priors, numerical evidence, recovery/sensitivity/failures and heldout results. For each claim record supported, narrowed, rejected or inconclusive, with rationale and permitted interpretation. Explicitly decide prior defaults versus opt-in research choices and the supported API/model/prediction roster; carry exclusions into documentation and runtime behavior | The R1 / SD 0.25 I1 undercoverage cannot be hidden by good diagnostics or prediction. Missing calibration or new-level evidence stays unsupported. A completed decision table may narrow the scope, but no defensible supported core means MS6 cannot declare foundation completion |
| **MS5 — Common API candidate verified** / maintainer | The [eight-type operation inventory](docs/internal/prediction-contract-four-facet-design.md#8-ms5のapi対応表と統合順序2026-10-09) guides isolated integration. The [comparison candidate](results/workflows/20261011-common-comparison-candidate-01/verification.json) passes 113 checks; the [recorded MGMFRM report extension](results/workflows/20261011-common-report-candidate-01/verification.json) passes 133 checks plus 36 focused checks after a display addition. The [fixed-coefficient MFRM report extension](results/workflows/20261011-fixed-mfrm-report-candidate-01/verification.json) adds 192+84 staged checks, retaining the explicit legacy-format report refusal. The [ordinary-test/saved-workflow candidate](results/workflows/20261011-common-workflow-candidate-01/verification.json) adds registration in the existing report shard and fresh-process reproduction of comparison, diagnostics, MCSE and reports, with 628 staged passes and no new fits. Runtime implementation is unchanged apart from module help; guide/navigation/NEWS are connected. A [subsequent refit-plan candidate](results/workflows/20261011-refit-plan-candidate-01/verification.json) closes reproduced leakage/scoring-label preflight gaps and preserves training dimension labels, with 86 focused passes and no new sampling. The [common heldout-scoring candidate](results/workflows/20261011-heldout-scoring-candidate-01/verification.json) now prepares explicit-prior, source-bound K-fold training requests and scores matching saved training fits across eight types, with 317+214 staged assertions and no new sampling. The [K-fold comparison candidate](results/workflows/20261011-kfold-comparison-candidate-01/verification.json) adds complete-roster aggregation/comparison, missing/failure and diagnostic-warning retention, and fresh-process replay, with 285 staged assertions and no new sampling. The [common recovery-evaluation candidate](results/workflows/20261011-recovery-evaluation-candidate-01/verification.json) adds named native-scale truths, fixed-value/coverage separation, MCSE and fresh-process replay across eight types, with 1,342 distinct staged assertions and no new fits or formal simulation replications. The [fixed-truth replication extension](results/workflows/20261011-recovery-replications-candidate-01/verification.json) adds complete-dataset-roster accounting and per-quantity replication SE, retaining missing/failed/warned outcomes, with 166 focused passes and zero new fits or formal replications. The [documentation integration](results/workflows/20261011-common-api-docs-candidate-01/verification.json) verifies the local manual with 194 policy assertions, 17 rendered pages and 566 local fragment links, preserving model explanations and old API anchors. The [English beginner learning path](results/workflows/20261012-beginner-guide-candidate-01/verification.json) adds three chapters with a worked probability example; 197 policy assertions, 20 HTML pages and 613 local fragment links pass, while browser visual and unfamiliar-reader review remain open. The [Julia help extension](results/workflows/20261012-julia-help-candidate-01/verification.json) adds actual brief/extended REPL help checks, a self-contained doctest and a no-fit first example; the updated manual has 623 checked local fragment links. The subsequently approved [Pages preview and visualization gallery](results/workflows/20261012-visual-guide-pages-01/verification.json) now pass representative Chrome visual/search checks, including 390-pixel gallery reflow; unfamiliar-reader acceptance remains open. [Ordinary report integration](results/workflows/20261011-common-api-integration-01/fitting_reports/guard-receipt.json) passes 92,902 assertions across 62 testsets. The occasion-metadata test mismatch is corrected with 47 passing checks, preserving the grouping guard. The [remaining fitting_core continuation](results/workflows/20261012-refit-metadata-integration-01/fitting_core_remaining-02/guard-receipt.json) passes 6,032 assertions across 26 testsets. Reuse its previously passed prelude/report evidence; these staged results are not a single fresh full-suite run. The [remaining ordinary shards](results/workflows/20261012-refit-metadata-integration-01/queue.json) continue serially, starting with generalized; full integration remains open. A [test-only fixed-Q report correction](results/workflows/20261011-common-api-integration-01/fixed-report-verification.json) passes 3,604 existing saved-result checks; it is not the whole generalized shard. The [actual-refit workflow](results/workflows/20261011-common-refit-workflow-01/verification.json) adds 16 short AdvancedHMC fits across eight result types, 255 passing integration assertions and 251 overlapping fresh-process replay checks; it changes only an example and its opt-in test and contributes no scientific replications. Full suite/remaining environment checks, automatic multi-model refit execution, inferential K-fold uncertainty, the design runner and independent review remain open. Final scientific recommendations and acceptance depend on MS4's supported roster | Versioned API/compatibility specification plus a synthetic public-workflow example: data/specification → fit → diagnostics and MCSE → supported prediction/comparison and figures → save/reload → reproduce results. Verify observation/category/draw/conditioning alignment, native numerical agreement, relevant legacy behavior, saved-record compatibility, unsupported-input rejection and consistent help/report warnings on the candidate commit | A supported operation requiring private helpers, manual draw reshaping or dataset-specific glue keeps MS5 open. Unverified PSIS, category consumers or new levels cannot be advertised through the common API; explicitly retain their unsupported/experimental status. Changes affecting an evaluated target reopen the affected evidence, not every unrelated test |
| **MS6 — Independent review and API finalization** / independent scientific reviewer, unfamiliar user, maintainer | Requires MS4's defensible scope and MS5's tested candidate. Reviewers are currently unassigned; assignment and review preparation must not be left implicit | Independent scientific review assesses target/interpretation/evidence; an unfamiliar user reproduces the selected public workflow and explains its limitations. Record feedback and its disposition. Close blocking issues, freeze the API version, supported scope, compatibility policy and documentation with the accepted candidate commit. This is the first foundation completion point | An implementer's self-check does not satisfy independent review. Reviewer unavailability, unresolved validity defects or workflow blockers keep MS6 open. A rejected review can finish a review activity, but cannot mark the foundation complete. OS-specific distribution work remains a separate release milestone |

#### Dependencies, precision and finite decisions

The execution dependency is **MS1 → MS2 → MS3 → MS4**, followed by **MS4 + MS5
→ MS6**. MS5 design work and MS4 evidence preparation may proceed alongside the
statistical sequence. Do not serialize independent documentation work behind
long fits, or start candidate fits during the frozen pilot. An implementation
change after a study freeze needs a separate identity and a reasoned equivalence
check or fresh affected evaluation before its results can support the new API.
While any frozen study is running, make API changes in an isolated candidate
snapshot; never mutate that study's running source snapshot.

**Settings, help and examples start before MS4.** Document current keyword
semantics, inputs/outputs, unsupported cases and warning interpretation now;
exercise saved-fit examples without additional sampling. After MS1, update
public docstrings, the guide and synthetic end-to-end examples together with
the isolated API implementation. MS4 supplies evidence-based scope and any
scientific prior recommendations; MS5 checks code/help/example consistency and
MS6 checks unfamiliar-user reproducibility. This separates starting the work
from accepting its final claims. See the [documentation handoff](docs/internal/prediction-contract-four-facet-design.md#9-設定ヘルプ具体例の整備時期),
[current settings/help](docs/src/experimental.md#settings-and-help) and
[saved-fit example](examples/common_prediction_observations.jl).

MS3 keeps the existing rule from foundation §24: for all six primary means and
seven paired contrasts compare replication-SE targets 0.005 / 0.01 / 0.02 nat;
use the maximum planned N at **0.01 nat**, at least **32 independent paired
blocks**, rounded up to an even number. Each planning group needs at least three
eligible pilot blocks. Keep the baseline pilot's variance/eligibility provenance
when adopting a faster implementation. Neither pilot blocks nor benchmark refits
enter the fresh main denominator. Actual achieved precision and failure rates,
not the planning calculation alone, determine what the main study establishes.

Retain the existing numerical screens, including R-hat ≤ 1.01, bulk/tail ESS ≥
400 and the full parameter/prediction MCSE and stability criteria in §24. These
are numerical qualification conditions, not guarantees of scientific accuracy.
Separately keep all three **90% interval calibration margins: ±2.5, ±5 and ±7.5
percentage points**. Fixed-facet coverage and joint-prior SBC remain different
claims. A positive calibration claim needs its own frozen estimands, independent
replications, interval/simultaneity rule, classification uncertainty and precision
design; neither the 32-block recovery study nor the prediction main supplies it
automatically. In MS4 either provide the matching evidence or explicitly exclude
that claim. A calibration study becomes a dependency only for a claim retained
in the supported scope, not an unannounced expansion of the prediction main.

No elapsed-time caps are introduced. Stop a planned study when its declared
roster and accounting are complete, even with unfavorable or inconclusive
results. A documented integrity/resource interruption retains its failed or
pending status. No seed replacement, outcome-driven retries or precision-driven
extension of an already frozen cohort; any further investigation gets a separate
question and prospective plan. New priors are not adopted simply because they
mix faster or improve a chosen recovery statistic.

#### Current claim-to-evidence register (MS4 preparation)

**2026-10-09 review draft, not an MS4 acceptance.** Keep the existing C1–C6
questions from [foundation §12](docs/internal/mgmfrm-foundation-scale-acceptance.md)
and the original raw-model ledger. This register updates candidate C with the
completed assessment; it does not overwrite dated receipts or transfer evidence
between priors. The foundation document is also hash-bound to the MS2 design,
so current decisions live here without changing that bound document.

| Claim / decision | Evidence now available | Conclusion currently permitted | Evidence or decision still required |
| --- | --- | --- | --- |
| **C1 — Target, constraints and coordinates** | [Equation and invariance derivation](docs/internal/mgmfrm-estimands-identification.md); normalized-prior, location-coordinate and canonical-record checks in foundation §§1–11, training-only binding in §23, and the 2026-10-11 raw-reference/actual native-q preflights above | Computational support within the checked model/coordinate domain. The eight-target native q implementation agrees at 40 checked points; this does not establish sampling precision. Proper priors anchor origin/scale but do not establish likelihood identification or scientific appropriateness. The complete-crossing/pure-Q derivation is not a theorem for every training split or sparse design | Independent review of declared estimands and scope; MS2 has preserved target/coordinate identities but has not established complete posterior comparison precision |
| **C2 — Numerical estimation and cost** | [Completed 192-fit assessment](results/workflows/20261004-foundation-fixed-facet-assessment-01/summary.json): 184 qualified, 8 retained diagnostic failures; foundation §20. Chunk comparison §22 retained Chunk 12 after only one of two targets met its speed threshold | Report the measured qualification/failure frequencies and costs under the declared controls. Numerical success is not calibrated coverage; no universal convergence or new Stan speed claim | MS1/MS2 terminal accounting and the baseline-retention decision are now closed; carry their unresolved precision and cost limitations into MS3/MS4. Do not count 192 fits as 192 independent panels or pool different budget/backend failure rates |
| **C3a — Joint-prior calibration** | Earlier candidate-C joint-prior panels, full quantity roster, numerical classification work and the three margin calculations in foundation §§2, 9–12 | Positive joint-prior calibration at ±2.5/5/7.5 percentage points remains unestablished. The 32-block fixed-facet recovery study and heldout prediction do not supply this evidence | A separate prospective calibration design and justified classification/precision assumptions if this claim is retained. Otherwise explicitly exclude it from the accepted scope; a large conditional N calculation is not authorization to launch it |
| **C3b — Fixed-facet recovery and interval coverage** | 32 independent paired blocks, six conditions and seven matched contrasts in foundation §20; bias/RMSE, replication MCSE, eligibility and unresolved coverage retained | Descriptive recovery and uncertainty for the tested R0/R1 conditions, conditional on numerical eligibility where stated. R1/SD 0.25 I1 (truth 0.35) has coverage confirmed in only 1/32, unresolved 0, despite 32/32 qualified fits: strong observed undercoverage, not a satisfactory general 90% coverage claim | Decide which recovery claims and conditions can be supported. Preserve pointwise versus simultaneous and fixed-facet versus joint-prior distinctions; no finite unconditional RMSE bounds have been established for numerical failures |
| **C4 — Unused-rating prediction at known levels** | Training-only target/heldout binding verified; the frozen 8-block/240-fit pilot is formally closed under foundation §§23–25 and the v2 closeout receipt | The scoring path is checked; pilot results remain exploratory. Main-study predictive means, paired differences and their precision are not yet established. Existing-row WAIC/LOO is a different target | Unchanged planning rule, the recorded MS2 implementation/N decision, and fresh MS3 blocks. Report all six means/seven contrasts with panel eligibility, replication SE and MCMC MCSE; R0→R1 NLL changes also reflect different generating-distribution entropy |
| **C5 — Prior sensitivity and recommendations** | Three loading-prior widths on the same 32 blocks; eligibility intersections for matched comparisons. R1 I1 coverage: SD 0.25 gives 1 confirmed / 0 unresolved; SD 0.5 gives 20 / 3; SD 1.0 gives 26 / 3, each out of 32 | Prior dependence is observable. The wider-prior descriptive coverage ranges are 62.5–71.875% and 81.25–90.625%; neither is itself a precision-backed calibration acceptance. No width becomes a recommended default because it mixes faster, has the lowest RMSE or wins a predictive comparison | MS4's explicit research-option/default decision with a stated use and joint recovery/precision/prediction rationale. A new prior prompted by these results needs a separate prospective plan |
| **C6 — Consistent use and reproducibility** | [Eight-type adapter inventory](docs/internal/prediction-contract-four-facet-design.md), existing native fit/figure workflows and adapter/example evidence; **2026-10-11 update:** the [isolated common workflow](results/workflows/20261011-common-workflow-candidate-01/verification.json) connects comparison/report checks to the ordinary test shard, corrects help and reproduces saved comparison/diagnostics/MCSE/reports in a fresh Julia process, with 628 staged passes. The [refit-plan follow-up](results/workflows/20261011-refit-plan-candidate-01/verification.json) adds 86 passing checks of pre-sampling partition/score-label integrity and training-spec preservation. The [heldout-scoring follow-up](results/workflows/20261011-heldout-scoring-candidate-01/verification.json) adds common source-bound requests, native-target matching and heldout scores, with 531 staged checks; later K-fold comparison and named recovery/replication candidates add saved-result aggregation. The [current documentation candidate](results/workflows/20261011-common-api-docs-candidate-01/verification.json) verifies the local rendered guide/reference. The [actual-refit follow-up](results/workflows/20261011-common-refit-workflow-01/verification.json) connects 16 short public fits across eight types to saved diagnostics/MCSE and heldout comparison, with 255 assertions and 251 overlapping fresh-process replay checks; a general refit executor and inferential K-fold uncertainty remain open | Implementation and persistence evidence for the tested candidate paths. Earlier saved-only checks add no MCMC; the separately declared short fits establish operability only. Candidate integration and a second process are not a release, scientific acceptance or unfamiliar-user review. No new-level prediction or reference-PSIS validation is implied | Remaining MS5 refit/compatibility integration, full-suite/environment verification and MS4 scope, then [MS6's independent review](docs/internal/prediction-contract-four-facet-design.md#10-ms6のレビュー資料と実施手順). Reviewer assignment remains open; OS/distribution completion remains a later milestone |

For C2/C3b/C5, keep the six assessment denominators visible: R0 at SD
0.25/0.5/1.0 has **32/29/30 qualified out of 32**; R1 has **32/31/30 out of 32**.
Even 0 observed numerical failures in a condition has a pointwise 95% binomial
upper bound of about **10.89%**, not a demonstrated zero failure probability.
Recovery summary SHA256 remains
`5070da90e6ab60e41c081447724ea9c39af4dd5686f3ffa47aad37be7d72e308`.
Coverage classifications use the existing local numerical screens; they do not
provide an all-quantity classification-error guarantee. Do not replace a
quantile-boundary unresolved case with a successful-looking point estimate.

Each final MS4 row must add its exact condition/estimand, evidence hashes and
candidate implementation, supported/narrowed/rejected/inconclusive verdict,
reason, permitted wording, exclusions and corresponding API/help behavior.
A draft conclusion above is not independent sign-off. Correlation, mixed/sparse Q,
learned rater scales, shared effects and unknown-level integration retain separate
requirements; computational support for those prototypes does not inherit the
present fixed-Q independent-dimension scientific evidence.

#### Main-result reporting contract prepared before MS3

The final report must retain all six condition rows and all seven paired-contrast
rows, including unresolved ones. For each metric record planned independent
blocks; eligible blocks and IDs (the intersection for a contrast); missingness
by external interruption, fit failure, diagnostic or panel-precision failure;
the estimate/direction/unit; replication SE; within-MCMC error and its ratio;
and the target/source identity. Mark unavailable values as unavailable, not zero.
Keep the four metric definitions and global person/dimension weights from
foundation §24. Partial folds cannot be renormalized into a complete panel.
Observed estimates conditional on eligibility are not unconditional performance
over failed panels, and the unbounded primary loss has no invented finite missing-data bounds.

This prepares the reporting structure only. Main N and baseline retention are now
fixed by MS2; scientific practical margins and study acceptance remain unset;
no new columns become new gates, no pilot scores determine a preferred primary metric, and no main fit is
launched by preparing this register. Reuse completed evidence rather than rerun
the 192-fit study or unrelated test suites.

#### Milestones after the foundation

| Workstream | Entry | Its own completion condition |
| --- | --- | --- |
| Empirical applications: Chopin, Uchihara, EVA | MS6 and the application's required model/prediction features within the finalized supported scope | Verify source/population/score/missingness correspondence, prospectively specify prior/sensitivity/focal precision, then fit and report through that API. Save reproducible estimates, diagnostics, uncertainty and predictive checks, including unresolved results. Prepared inputs and a successful fit alone do not complete an application; empirical reanalysis does not retroactively validate the foundation |
| Distribution/release | Mathematical/analysis foundations and MS6 complete | On the selected release candidate, satisfy the declared platform/CI, installation, compatibility and documentation checks, resolve applicable historical release holds, and record the version/artifacts. This is separate from API finalization and is not a prerequisite for local empirical applications |
| Further model domains | A named reusable requirement and a declared scope for the next version | Reuse [four-facet](docs/internal/prediction-contract-four-facet-design.md) and [shared-effect/hierarchy](docs/internal/shared-effects-hierarchy-prediction.md) work. Each extension closes its equation/identification/prior, backend, synthetic statistical and API/workflow checks before application. Correlation, sparse/mixed Q, learned rater scales and new-level integration do not inherit acceptance from the present independent fixed-Q assessment |

The broad model catalogue is a sequence of versioned scopes, not a requirement
to finish every combination before MS6. Existing extension prototypes remain
evidence; add work now only if it closes a named MS1–MS6 gap. Shared effects,
learned rater scales, halo and new-level prediction retain their separate
validation requirements and are not added to the current main denominator.

#### Progress reporting and the next actions

Each milestone report records its work status, evidence commit/receipt, verdict,
remaining blocker, responsible role and next allowed action. Show attempted,
terminal, numerically qualified and statistically resolved counts separately;
do not turn a fit count or a number of passed tests into an overall completion
percentage. Update this table and the existing linked evidence documents rather
than creating another competing roadmap.

MS1 and MS2 are now closed; the MS3 baseline/N decision and MS5
comparison/report candidates are available. Main execution is running; completion,
statistical conclusions and full API acceptance remain open.
The current C1–C6 register and main-report schema are prepared above; MS6's
review tasks and evidence handoff are specified in the API contract. Reviewer
assignment, final candidate material and independent decisions remain open;
the native candidate was constructed and checked after MS1 closure. These are
bounded preparation tasks with explicit outputs, not authorization to launch
application fits, repeat completed suites or build unrelated extensions.
Preserve the closed MS2 comparison, its storage interruption and unresolved
precision/cost findings. Complete MS3 under its recorded Julia baseline, N=32 and fixed plan, with the
validated pilot continuation as its planning source. Do not use the old root
summary, replace the comparison, or add draws to seek a pass. On interruption,
retain all existing outcomes and complete integrity/resource checks before an
append-only continuation; never restart the cohort from the beginning.
A numerical study needs its
question, roster, seed/controls, metrics,
precision/decision rules and source identity filled in before launch; a document
still containing those open decisions is a handoff, not a completed protocol.

The separately frozen prediction pilot completed its append-only storage
continuation in §25, with a 5 GiB free-space reserve and no elapsed-time cap.
The final [continuation summary](results/workflows/20261006-foundation-prediction-pilot-01/continuations/20261009-01/summary.json)
accounts for every attempt; its run guard reports completion with exit code 0.
The completed recovery assessment and its source hashes remain unchanged.
The [closeout validator](scripts/mgmfrm_foundation_prediction_closeout.py) is
verified with ten lightweight tests: it requires terminal continuation receipts,
recomputes the final summary, preserves unknown costs and leaves main launch
disabled. The 2026-10-11 inspection found and resolved two portability blockers: original-machine
absolute paths in guard receipts, and exact equality against a summary generated
with a different Python/NumPy/SciPy environment. Recalculation retains all fit
rows, statuses and hashes; 225 aggregate floating-point values differ by at most
7.192e-13. No refit was performed. The v2 receipt verifies the original identities
under one repository-prefix relocation and applies a narrow comparison only to
named aggregates, preserving exact discrete/status/hash and planning-decision
checks. Original receipts and the target were not changed.
The pilot-based N calculation is informational and main N remains unselected.
Section 26 also maps the
Stan target/coordinate/parser/scoring changes and the need to measure child-process
CPU. The transformed-coordinate native model is now built and checked, alongside
the unchanged production reference, as recorded above. No posterior sampling
has started for the new candidate.
The [efficiency design binder](scripts/mgmfrm_foundation_efficiency_design.py)
passes six lightweight tests and binds 27 input/design evidence files. Its local
receipt is `results/workflows/20261009-foundation-efficiency-design-01/design.json`
(SHA256 `8e75087186f18eb389a7374011db7f0777aa396ecee424b62734aa9ab2ec8cab`).
It retains the original global person/dimension score weights, lists 292 quantity
rows and 18,752 planned summary/score comparisons, and requires 20% lower elapsed
cost in both counterbalanced rounds plus no slower individual pair. These are
prospective computational choices, not measured acceleration or scientific
equivalence. The actual comparison runner, scoring/CPU verification and executable
protocol freeze remain prerequisites; the native preflight passes but the design
receipt still cannot launch fits.
Current decisions live here; dated receipts below preserve how they were reached
instead of creating additional active work queues. Scientific acceptance and
the subsequent main assessment remain open.

### Historical handoff evidence

These rows preserve earlier milestones and their then-open decisions. References
to an unselected N, a six-fit next step or hosted CI as next work are superseded
by the current assessment above and the completed records below.

| Historical milestone / responsible role | Concrete deliverable | Exit and boundary at that milestone |
| --- | --- | --- |
| Completed engineering handoff — Maintainer | The existing normalized location transform now connects to explicit experimental fitting, diagnostics, canonical saved records and a documented example; the research adapter delegates to the same implementation | Density/Jacobian/gradient and bounded public fit/save/reload/report checks pass. CmdStan rejects this coordinate option; raw remains its supported route. No default change, automatic request cache, scientific promotion or new independent calibration dataset. See [the implementation receipt](docs/internal/mgmfrm-foundation-scale-acceptance.md) |
| Completed evidence review — Analyst | Candidate C now has a C1–C6 claim/evidence table, a saved-draw absolute-versus-centered ability review and all three calibration-margin comparisons in the [foundation document](docs/internal/mgmfrm-foundation-scale-acceptance.md) | Two joint-prior datasets remain two datasets. The initial saved-draw review added no fits; its additional diagnostic/MCSE assessment is now recorded with C5 below. These exploratory error summaries do not establish fixed-facet recovery, calibration or heldout prediction |
| Completed — Analyst: bounded exploratory C5 comparison | Four of four frozen attempts completed at log-loading SD 0.25 / 1.0 on the same two C panels, reusing the 0.5 baselines. All original 150-quantity diagnostics and extra 111-quantity precision screens pass. Paired differences/MCSE, all prediction warnings and independent arithmetic checks are in the [foundation record §13](docs/internal/mgmfrm-foundation-scale-acceptance.md) | 70.22 serial minutes, observed peak RSS 3.26 GiB; zero retries, redraws or extensions. Paired prediction comparisons retain 28 / 33 / 0 / 0 unresolved rows out of 5,000 each. This closes the bounded exploratory comparison, not general prior robustness, new independent-data evidence or formal M2 acceptance |
| Completed design — Analyst; scientific review pending | The [fixed-facet design](docs/internal/mgmfrm-foundation-fixed-facet-design.md) retains C as a reference and proposes paired R0/R1 with loading SD 0.25 / 0.5 / 1.0. It states fixed truths, estimands, within-fit versus between-panel MCSE, failure denominators and 8 / 32 / 128-block cost/precision comparisons. Four disposable engineering panels verify the existing DGP; no new posterior fit or evaluation panel | R1 is an explicit weak-loading stress condition, especially for SD 0.25. No scientific prior, evaluation N or calibration margin is adopted. Independent review remains pending; existing 150-quantity claims and all three calibration margins remain |
| Completed execution — Maintainer/analyst: bounded fixed-facet rehearsal | Fixed-facet inputs connect to explicit normalized targets and saved reviews; input/target checks pass 79 assertions. All six attempts completed in 81.92 serial minutes, with observed peak RSS 2.88 GiB; four pass the 150-quantity and extra 111-quantity screens | R0 / SD 0.5 and R1 / SD 1.0 retain R-hat failures. Zero retries, redraws or extensions; zero common qualified blocks across all six conditions out of one planned block. See the [execution and verification record](docs/internal/mgmfrm-foundation-fixed-facet-design.md). This engineering pair has no evaluation credit |
| Review packet complete; independent decisions pending — Analyst and scientific reviewer | The [fixed-facet decision packet §10](docs/internal/mgmfrm-foundation-fixed-facet-design.md) proposes descriptive C3b/C5 plus finite-budget C2, retains R0/R1 and all three priors, specifies denominator/failure handling, and compares N = 8 / 32 / 128 with observed costs. Exact integer missing-coverage arithmetic passes 284 checks | This is an analyst proposal, not independent acceptance. Review purpose, stress scope, finite sampling policy, precision target and N/resource budget before a separate launch. All three margins remain; no adopted N, new fit or evaluation credit. Do not treat the descriptive bounds as confidence intervals or use 2/6 as a general failure probability |
| Integration candidate and walkthrough available; local integration complete, reader review pending — Maintainer and independent readers | The [self-contained normalized-prior example](examples/normalized_mgmfrm.jl) connects fit, diagnostics/MCSE, figures, save/reload and report verification. The same selected API tests pass 3,835 assertions on each of Julia 1.10.8 and 1.12.6; the walkthrough retains warnings and passes 13 saved-output checks | See [foundation record §§15–16](docs/internal/mgmfrm-foundation-scale-acceptance.md) for documentation and completed ordinary generalized results. Selected minimum-version checks do not establish a full minimum-version suite or hosted CI matrix pass. Unfamiliar-reader and scientific review remain unassigned; the small demonstration adds no evaluation credit |
| Completed ordinary generalized verification — Maintainer, 2026-09-28 | The original saved-sample checks pass 547 assertions standalone; the unchanged integration candidate completes ordinary `Pkg.test` on Julia 1.12.6: 129 test sets / 46,442 assertions pass, with no failures or broken/skipped checks | 85 min 38 s, observed peak owned-process RSS 2.72 GiB. No source, assertion, dependency or default changes were needed. This resolves the previous 45-minute incomplete run; buffered output did not identify the active test. See [foundation record §16](docs/internal/mgmfrm-foundation-scale-acceptance.md) and [verified result](results/workflows/20260928-saved-test-integration-01/verification.json). Whole-package/minimum-version completion is recorded in the next row; hosted CI for the new candidate and independent review remain separate |
| Local ordinary integration complete — Maintainer, 2026-10-02 | The repaired Julia 1.12.6 report shard completes 56 test sets / 92,315 passing assertions. Combined with five previously completed groups, all six ordinary groups are complete. Julia 1.10.8 all completes 256 test sets / 150,618 passing assertions. Both new runs have zero failures, errors or broken checks and no elapsed-time cutoff | See [foundation record §18](docs/internal/mgmfrm-foundation-scale-acceptance.md) and [verification](results/workflows/20261002-integration-01/verification.json). Pkg.test success and identified process termination confirm completion after the outer controllers disappeared during conversation interruption; their exit codes and continuous peak-RSS receipts remain unavailable. Earlier failures/time limits remain. Next confirm hosted CI and obtain independent reader/scientific review; local ordinary success alone does not close those gates |
| Conditional — Analyst: assess remaining classification precision | If a retained claim needs it, compare conditional CDFs and raw indicators on the two saved transformed fits, preserving all 150 quantities | One bounded comparison; zero additional posterior fits. Report MCSE, cost, failures and any benefit or lack of benefit. The 36 location-invariant quantities and nuisance-chain error remain; no automatic reference-method or sampling escalation |
| Later — Analyst/maintainer | Follow the existing model-extension sequence after the relevant foundation evidence | Validate one declared combination at a time. Existing correlation implementations need acceptance work; application completion and an all-options architecture are not prerequisites |

Do not restart the remaining 269 raw attempts, the long same-data backend pair,
the historical performance investigation, or a general Q/random-effects
implementation merely to keep work moving. Their original evidence and release
conditions remain; a named claim or observed blocker must justify reopening them.
The strong global calibration claim can remain unresolved while experimental
operability improves. Stable-public promotion still requires the
[release conditions](#package-release-conditions), including the retained M0 hold.

## Execution priorities after local integration

**2026-10-04 authorization update.** The user authorized additional estimation
through statistical validation, prioritizing recovery, prior sensitivity and
estimation failures with precision, on measured local resources and with no wall
cutoff. The [prospective fixed-facet protocol §11](docs/internal/mgmfrm-foundation-fixed-facet-design.md)
now fixes 32 independent paired blocks / 192 attempts, all three loading-prior
widths, existing draw counts and numerical screens, failure denominators and
paired replication MCSE. Complete the focused input/scoring checks and freeze
the plan before fitting. Reuse Julia worker processes; admit a second worker
only under the documented measured memory rule. This authorization permits
execution without an additional independent prelaunch approval; independent
scientific review remains unassigned and no scientific acceptance is claimed.
The mathematical mapping and saved-six-fit assessment below are addressed in
the linked identification/protocol additions. Earlier proposed work order and
unselected N options remain historical context, not a new permission barrier.

**First interim interpretation, 2026-10-04.** A fixed snapshot of five completed
R0 fits supports an initial paired recovery/sensitivity analysis and an actual
phase-cost decomposition; see [foundation record §19](docs/internal/mgmfrm-foundation-scale-acceptance.md).
All five pass the declared numerical screens, but only two paired blocks are
available for SD 0.5 versus 0.25. The centered-D1 RMSE difference is −0.006095
(replication MCSE 0.005069); no prior is selected. Repeated-worker scoring accounts
for about 3.5–3.8% of attempt wall time, directing any later optimization toward
the fitting work and effective sampling. Continue the unchanged 192-attempt plan.
Even with no unresolved cases, N=32 cannot put a pointwise 95% exact-binomial
coverage interval wholly inside any of the three chosen margins; this is a
descriptive first study, not a calibration acceptance design. Next-stage prediction
retains C4's known-level heldout-rating target and training-only five-fold fitting;
joint-prior SBC remains a separate claim. The controller observation gap is
recorded, supervision is restored, and no fit was restarted.

**Final assessment and efficiency decision, 2026-10-06.** All 192 planned fits
finished on October 5 at about 09:49 JST: 184 numerical passes, eight retained
loading R-hat failures, no sampler exceptions or unstarted attempts, and no
retries, replacement seeds or extensions. The [foundation record §20](docs/internal/mgmfrm-foundation-scale-acceptance.md)
closes this descriptive recovery/prior-sensitivity/finite-procedure study with
six condition summaries, seven paired contrasts, replication MCSE and pointwise
failure intervals. Shared blocks are not 192 independent replications.
Narrow SD 0.25 was computationally easier but R1/I1 coverage was only 1/32
with no unresolved classifications; speed does not choose the scientific prior.
Calibration acceptance at the three margins, joint-prior SBC, heldout prediction
and independent scientific review remain open. Do not extend this completed
study in response to its outcomes.

All-attempt costs locate 96.20% in fitting and 3.78% in scoring; median fit time
was 759 seconds and observed two-worker elapsed time was about 21 h 45 min.
The monitor gap prevents a full-period peak-RSS or original-controller exit-code
claim. A saved-state density/gradient probe passes 100 checks. A single paired
ForwardDiff Chunk 12 versus 16 comparison passes 56 checks, preserving the
gradient exactly at all 12 points, with median gradient time reductions of
13.47% and 27.49% on the two saved targets and 6.50% fewer allocated bytes.
These are warmed microbenchmarks on a shared host, not whole-fit speedups.
The default and frozen study sources remain unchanged; no whole suite was rerun.

This assessment led to the same-target computational comparison recorded below.
That comparison is now complete; its closure and the current next-exit table
supersede the earlier plan to launch it. The mathematical mapping and 32-block
study are completed evidence, not a queue to repeat.

**Whole-fit chunk comparison launched, 2026-10-06.** The [pre-result rules in
foundation record §21](docs/internal/mgmfrm-foundation-scale-acceptance.md)
fix four serial fits on the same two profiled targets, in Chunk 12→16 / 16→12
order. The isolated research adapter passes 54 density/gradient/validation checks
and delegates fitting/scoring to the existing runner. Inputs, seeds, 4-chain
1000+1000 schedules and all diagnostics stay fixed; no product defaults change.
Direct adoption from this small engineering comparison requires identical saved
numerical results/precision and at least 5% lower whole-fit time on both targets.
Otherwise retain baseline or report inconclusive, without extending this batch.
Any original diagnostic failure stays a failure; independent evaluation credit
is zero. One worker, 8 GiB RSS / 2 GiB output limits and no elapsed-time cutoff.

**Prediction handoff clarified while the comparison runs.** The current study's
recovery RMSE variance does not determine the replication variance of heldout
negative log predictive density. For C4, first bind each training-only normalized
target and preserve facet IDs/support; reuse the existing log-domain scoring,
within-draw covariance and fold/panel aggregation helpers. The old raw-target
`check_fit` binding cannot be applied unchanged to normalized C. Then obtain
claim-specific pilot variance under a separate fixed design before selecting a
precision-driven replication count. Five overlapping folds remain one panel,
and a missing/unqualified fold leaves that panel unresolved. No CV fit has been
launched during this cost comparison.

**Whole-fit comparison closed, 2026-10-06.** All four planned attempts completed
with exit code 0 in 88 min 17 s; observed peak RSS was 2.49 GiB. Both chunk
settings reproduced byte-identical samples and identical diagnostics/MCSE on
both saved targets, including the original R1 loading R-hat failure. The
[final comparison, foundation record §22](docs/internal/mgmfrm-foundation-scale-acceptance.md)
records full-fit time reductions of 26.24% for B01-R0-050 and 2.12% for B24-R1-050.
The fixed requirement of at least 5% on **each** target was not met: retain the
baseline setting 12 and leave general adoption of 16 unestablished. No default,
prior or scientific acceptance changed; zero retries/extensions or new independent
replications. Do not turn an average of the two cases into a replacement rule.
Shared-host variation and first-use compilation remain measurement limitations;
a future cost study should declare per-fit process CPU timing as well as elapsed
time. The density/gradient and complete saved-result equivalence evidence is reusable.

**Current concrete exit:** execute and assess all 240 fits in the frozen
[eight-block prediction pilot, §24](docs/internal/mgmfrm-foundation-scale-acceptance.md).
Its plan hash is `f64b476f7232bee2dd82f7a9c1d378ef173a75a7308d68f9412c556279d28428`.
The earlier binding/diagnostic checks add no independent evaluation panels.
Predictive-score variance and qualification fractions determine the fresh main
assessment's N under the already fixed rule; pilot outcomes do not change its
numerical thresholds or permit extra pilot blocks.
The earlier chunk experiment remains closed. The 2026-10-09 user direction adds
the separately designed same-target efficiency comparison in §26 after pilot
completion and before main fitting. Mathematical/analytical work retains
priority over OS and distribution.

The [current next-exit table](#current-assessment-and-next-exits) replaces the
October 4 queue: its mathematical mapping, saved-fit review, protocol selection
and descriptive assessment have completed records. The reusable completion and
review rules below still apply. Update their existing documents and helpers
rather than creating another framework. Mathematical validity, computational
accuracy, statistical evidence and delivery readiness retain separate exits.

### Work products and completion decisions

The immediate domain is the existing complete-crossed 50-person / 5-item /
5-rater, four-category, pure-Q, two-dimensional MGMFRM with identity latent
correlation. Candidate C and its three loading-prior widths retain their stated
computational roles. Existing proofs may cover a wider mathematical domain;
empirical acceptance cannot inherit that wider scope without evidence.

| Work / existing home | Method and concrete output | Complete when / consequence of an unmet condition |
| --- | --- | --- |
| Mathematical argument — [identification](docs/internal/mgmfrm-estimands-identification.md), [prior measures](docs/internal/mgmfrm-prior-choice.md) | For the declared response distribution, record support, constraints, free coordinates, normalized prior measure and transformations. Attach existing derivations/counterexamples and their exact assumptions; supply only a missing argument needed by a selected claim | Every mathematical assertion used by that claim has an argument under its stated assumptions; density/Jacobian and relevant derivative checks agree. Record excluded cases. A required unresolved assertion holds the dependent claim open; naming the gap does not complete the mathematical foundation |
| Interpretation — [foundation claims](docs/internal/mgmfrm-foundation-scale-acceptance.md), [fixed-facet design](docs/internal/mgmfrm-foundation-fixed-facet-design.md) | Map absolute and centered ability, loading/log-ratio, severity/consistency, item position and prediction to their origin/unit, conditioning population and evaluation quantity. Reuse completed prior-predictive and sensitivity evidence | Every focal row has a formula, unit, prior dependence, permitted interpretation and applicable evidence. All original 150 quantities remain traceable. Centering is not called scale invariance; one favorable fit does not choose a scientific prior |
| Numerical assessment — fixed-facet design §8 and foundation record §20 | Reuse the completed rehearsal and 192-fit assessment, including diagnostics, focal MCSE, sampler warnings and eligibility; the eight assessment failures and saved scale/ratio analysis remain recorded | Every attempt and relevant quantity is accounted for, and observed facts are separated from mechanism hypotheses. The assessment can end with unresolved causes; a fit is usable for the declared comparison only if its original global and focal rules pass. Otherwise retain it as ineligible, and state the next discriminating check or why no further run is justified |
| Efficiency assessment — the profile receipts below | Attribute the cost of the selected analysis to startup/JIT, density/gradient evaluation, transitions and postprocessing. If an actionable cost is found, compare one target-preserving change with the baseline under the same accuracy conditions | Record a measured benefit, no benefit or inconclusive result with correctness checks, spread, allocations and memory. Keep the baseline when benefit is unsupported. The exit is an adequate method for the declared analysis or an explicit unresolved cost/precision problem, not proof of the fastest possible implementation |
| Statistical design — fixed-facet design §§10–11 and C4 handoff | The N=32 descriptive protocol is complete. Reuse its question/generator/estimand/method/precision/failure structure for the separate C4 pilot and assessment; retain calibration-margin comparisons for their own claim | All fields that determine execution/scoring have explicit choices and rationale, including numerical and between-panel precision. Unset N, scientific tolerance or unresolved execution conditions keep that new study in design. Do not reopen the completed cohort or add another packet in place of resolving decisions |
| Statistical assessment — foundation C2–C5 evidence | After the separate execution decision, evaluate the selected protocol and report every planned attempt, uncertainty, paired comparison and claim result | The assessment is complete when the planned outcomes and unresolved results are accounted for. A scientific claim is accepted only when its predeclared criteria and independent scientific review pass. A negative or inconclusive assessment is a valid completed study, not positive acceptance |

The first foundation milestone is a defensible **named set of claims** for this
domain: mathematical validity, interpretable estimands, adequate numerical
precision and statistical evidence for each claim actually made. Retain C3a
joint-prior calibration and C4 heldout prediction as open if they have not been
evaluated; do not describe the entire foundation as statistically validated in
that case. A narrower descriptive result may finish independently. Required
criteria cannot be removed after observing failures to manufacture that result.
Scientific prior adoption and package release are further, separate decisions.

### Mathematical appropriateness from several perspectives

| Perspective | Question and way to check it | Evidence that would not settle the question |
| --- | --- | --- |
| Probability model and measure | Do the response probabilities, zero-sum/product constraints and proper prior define the intended joint law? Reuse the normalizers, support argument and change-of-variable derivations; check needed moments for reported means/variances | A finite log density at a few points, or a sampler that returns draws |
| Identification and information | Which quantities are invariant to the pure-Q location/positive-scale transformations? Use the conditional-model derivation and degenerate counterexamples; keep structural identification separate from finite-data precision and marginal-model claims | A connected design, a nonsingular posterior Hessian or proper priors alone |
| Prior and measurement meaning | Which origin/unit and rater symmetry are being assumed? Translate kernel scales into marginal/contrast distributions and connect the existing sensitivity results to the estimands | Equal numeric SD arguments across raw/source/exchangeable priors, or selecting the smallest observed RMSE |
| Numerical realization | Does code compute that law and its derivatives in the relevant range? Reuse independent equations, invariant transformations and known-answer checks; target weak loadings, extreme predictors or near-boundary values only where they bear on the selected analysis | Self-comparison through the same helper, or backend agreement when both share the same mistaken definition |
| Error and interpretation | Separate posterior uncertainty, finite-chain error, numerical integration/rounding error and between-panel error. Verify the uncertainty calculation for the actual mean, quantile, probability or paired contrast being reported | Treating posterior SD as MCSE, an empirical diagnostic threshold as a finite-sample guarantee, or a conditional CDF as an exact marginal posterior CDF |
| Design and scientific scope | State what is fixed/generated, conditional independence, the role of weak-loading R1 and the prediction population. Evaluate recovery, prior sensitivity, calibration and heldout prediction as different questions | Treating in-sample probability reconstruction as heldout prediction, repeated fits as independent datasets or a valid model equation as evidence of real-data adequacy |

Label each conclusion as a derivation under assumptions, a deterministic numerical
check, an observation from specified fits, a hypothesis or an unresolved question.
These are evidence descriptions, not interchangeable levels of proof. Analyst
self-review can resolve algebra and implementation issues; it does not fill the
independent scientific-review role.

### Numerical precision and efficiency decisions

Retain the rehearsal's existing numerical screens: rank-normalized R-hat ≤ 1.01,
bulk/tail ESS ≥ 400, and for the additional focal quantities mean MCSE / posterior
SD ≤ 0.05 and 90% interval-end MCSE / interval width ≤ 0.05, together with the
existing sampler/global checks. These are screening rules for that protocol,
not universal tolerances or a proof of convergence. A future scientific accuracy
requirement must also be expressed in the reported quantity's units; no unchosen
scientific tolerance is silently filled by these ratios. Finite-chain diagnostics
and function-specific MCSE have distinct roles; see the official
[Stan posterior-analysis reference](https://mc-stan.org/docs/reference-manual/analysis.html).

The rehearsal's two failures remain in its six-fit denominator. In the completed
192-fit assessment, eight fits retain loading R-hat failures (maximum 1.01757),
with zero divergences or tree-depth hits. Saved loading/ability-scale associations
and passing within-dimension loading-ratio diagnostics suggest a common-scale
mixing issue; they do not establish its cause or reverse the original failures.
The saved-result inspection is complete. Reopen a coordinate comparison only if
this uncertainty obstructs a named subsequent analysis.

| Measured cost or uncertainty | First action, reusing existing tools | Adoption / stopping rule |
| --- | --- | --- |
| Startup, compilation or repeated setup | Separate process/import/JIT cost from warm calls; reuse the existing profile recipes and source/environment records | Change setup only if it obstructs the selected analysis. Report first-use and warm costs separately; keep compilation out of a claimed sampling speedup |
| Density/gradient kernel and allocations | Profile the representative target and count calls, active Q entries, observations and draws. Inspect repeated validation, intermediates and type instability before considering parallelism or another library | Preserve target/gradient and invalid-input behavior. Compare warm repetitions and actual end-to-end impact; a faster minor phase alone does not justify a broad rewrite |
| Transition cost or poor effective sampling | Use retained step counts, adaptation and chain diagnostics to distinguish expensive transitions from poor mixing. Consider a mathematically equivalent parameterization only when the evidence points there | Verify transformed density/Jacobian first, then compare focal precision and diagnostics. Do not change priors or drop difficult quantities to claim a speed gain |
| Postprocessing or classification precision | Reuse the completed batch-preparation optimization and saved draws. Consider conditional integration only for a named remaining error/cost problem | Account for integration cost and remaining nuisance-chain error. Preserve the unchanged 36 location-invariant quantities and original indicators; no automatic all-150 reference project |
| Repeated numerical/reference work | Start with existing independent equations and exact location references; use fixed-state Julia/CmdStan comparisons when a cross-implementation question remains | A backend mismatch is investigated before additional fits. A fresh backend fit is justified only by a question that deterministic or saved-result checks cannot answer; neither backend is presumed ground truth |
| Parallelism, storage or approximate inference | Reuse available chain controls only after profiling shows an opportunity; retain independent RNG streams, thread counts and memory measurements | Compare elapsed time, total compute and peak memory. Approximate inference needs its own error assessment; thinning or reduced precision is not a default speed fix |

For deterministic comparisons, hold input, target, dependency versions, hardware
and threads fixed; record first use plus repeated warm medians and spread, and
interleave before/after measurements where practical. Require exact equality when
arithmetic is unchanged, otherwise a declared absolute/relative tolerance checked
against an independent reference. For sampler changes, trajectories need not be
identical: require the same posterior target and assess summaries within their
Monte Carlo uncertainty. Fix the comparison conditions and desired benefit before
looking at candidate timing; if variation obscures it, report inconclusive rather
than repeatedly measuring until a favorable number appears.

Sampling comparisons report focal bulk/tail ESS per second, MCSE and total cost
at comparable precision, with the full diagnostic roster and failures retained.
Report retained-sampling cost separately from total analysis cost, including
warmup, compilation, failures and postprocessing; no ranking based only on a
selected successful chain or iterations per second. The documented kernel and
geometry options follow [Julia's profiling/allocation guidance](https://docs.julialang.org/en/v1/manual/performance-tips/)
and [Stan's efficiency guidance](https://mc-stan.org/docs/stan-users-guide/efficiency-tuning.html);
their usefulness here remains a measurement question. The completed 8.56× saved
diagnostic improvement does not estimate a sampling or whole-study speedup.

### Statistical precision, handoff and the next concrete work

Use the existing [fixed-facet protocol](docs/internal/mgmfrm-foundation-fixed-facet-design.md)
and its aims/generator/estimands/methods/performance organization, consistent with
[Morris, White and Crowther's simulation-study guidance](https://arxiv.org/abs/1712.03198).
Before choosing N for a new study, identify the primary performance quantity and
its needed between-panel precision. N = 8 / 32 / 128 were the descriptive-study
comparisons; N=32 was selected and completed. A predictive N needs predictive
variance. Continue comparing ±2.5 / 5 / 7.5 percentage-point calibration margins
for the separate calibration claim.
A margin is not an MCSE target. For a panel-level average use independent panels,
and for a paired contrast form the within-pair difference first; do not count
persons, draws, folds or prior variants as independent panels. Unresolved/failed
attempts retain the planned denominator and conditional summaries retain their
eligibility labels. Large N cannot repair a wrong estimand, biased computation
or a persistent unresolved fraction.

The C4 binding audit is complete; the fixed prediction pilot and precision-driven
heldout assessment remain in the [current table](#current-assessment-and-next-exits).
The new normalized-C adapter reuses log-domain scoring and covariance-aware MCSE;
the old raw `check_fit` remains distinct. Five overlapping folds remain one
panel; an incomplete or ineligible fold leaves the panel unresolved. A reporting
resolution proposal is not an adopted scientific effect margin. Check the
actual achieved precision against the frozen execution/scoring choices, without
making an all-quantity calibration guarantee a prerequisite for this narrower
predictive question.

No elapsed-time cutoff is introduced by this roadmap. Work ends at the stated
deliverable or predeclared sampling design; elapsed cost is measured. Do not
extend draws, replace failed seeds, relax thresholds or broaden the model roster
after seeing results. Changed mathematical/numerical code receives the smallest
relevant check under the [change-to-check table](test/README.md); prose changes
receive link/consistency and whitespace checks. Full local suites, OS fixes,
distribution policy and further report/UI work remain outside this work sequence.
Formal evaluation retains the [research execution conditions](#research-execution-prerequisites).

**Engineering status retained, checked 2026-10-04.** For PR head `cd46dfe`,
[CI run 36980844893](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/36980844893)
has 14 successful jobs, one failed release-hygiene job and two intentionally skipped
optional research jobs. Ordinary minimum-version/all and current-version groups
pass. The remaining failure is the static skipped-test scan rejecting the Windows
branch's `@test_skip` in `test/cmdstan_adaptation_record.jl`; the prior optional
plotting import failure is resolved. This is deferred distribution work, not a
failed mathematical assertion or an all-green CI result. [PR #101](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/pull/101)
remains draft and unmerged; no gate, test or workflow is changed by this reprioritization.

**Performance evidence and its limits.** The historical
[fitting-core runtime review](docs/internal/fitting-core-runtime-review.md)
reports 76.70–83.45% compilation in its measured enclosing block. That is neither
the sampling fraction nor a decomposition of the October 2 full suite. The
[saved-result profile](docs/internal/normalized-prior-backend-comparison.md)
already found a non-sampling bottleneck: on the same saved 6,000-draw record,
payload hashing changed from 68.720 to 0.087 seconds and validated loading from
74.800 to 1.926 seconds after the prior fix. These are individual local profiles,
not a repeated benchmark or a new speedup delivered by this review.

Bayesian HMC repeatedly evaluates log density and gradients; difficult geometry
can require more work per useful draw. Compilation and report/serialization work
are additional costs, so “Bayesian” alone does not explain elapsed time. Assess
sampling by diagnostic-qualified effective samples per second and focal Monte
Carlo error, rather than iterations per second. Preallocation, compiled-code
reuse and chain parallelism are candidates only after phase measurements; preserve
RNG streams and avoid BLAS/thread oversubscription if parallelism is introduced.
Approximate inference changes the accuracy contract and is a separate decision.
See the official [Julia performance guidance](https://docs.julialang.org/en/v1/manual/performance-tips/),
[Stan sampling description](https://mc-stan.org/docs/reference-manual/mcmc.html)
and [ESS/MCSE definitions](https://mc-stan.org/docs/reference-manual/analysis.html#effective-sample-size).

**Portable integration summary.** Commit `4443efa` records the accumulated
foundation implementation. Before staging, all 638 execution-input hashes matched
the completed local candidate. Staging exposed generated SVG trailing spaces and
one extra final newline in `test/posterior_mcse_draws.jl`; cleanup preserves all
SVG XML tokens/coordinates and all Julia non-terminal-newline bytes. The subsequent
policy change touches this roadmap, `test/README.md` and the CI archive-size check,
not product code or sampler settings. The completed local results remain:

| Runtime / coverage | Passing assertions | Fail / error / broken |
| --- | ---: | --- |
| Julia 1.12.6, six ordinary groups combined | 150,627 | 0 / 0 / 0 |
| Julia 1.12.6, report group within that total | 92,315 | 0 / 0 / 0 |
| Julia 1.10.8, ordinary `all` | 150,618 | 0 / 0 / 0 |

The two new runs completed despite loss of their outer controllers; their logs
contain `Pkg.test` success and the identified processes ended, but the outer exit
codes and continuous peak-RSS receipts are unavailable. See the retained
[foundation evidence §18](docs/internal/mgmfrm-foundation-scale-acceptance.md).
Raw logs, fit caches and hash receipts under `results/` remain ignored local
artifacts; links to them are local evidence references, not downloadable GitHub
attachments. The summary here travels with the source; it is not an independent
reproduction. New-head hosted CI and independent scientific review remain separate.

**Publication checks.** GitHub confirms that
[PR #100](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/pull/100) was merged
on September 22 and its [CI run 35709866645](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/35709866645)
completed successfully, including the minimum-version all job. That validates
`91210a5`, not the new candidate. Freshly fetched `origin/main` is `f3fdd65` with
the same tree as that old branch head. A push to the old, now-closed PR branch
would not trigger this workflow's main/master-push or open-PR events.
The initial GitHub CLI/transport checks rejected the stored token. Following the
user's explicit authorization and browser authentication on October 2, Git
authentication was configured and `4443efa` / `0c90531` were successfully pushed
to `work/mgmfrm-foundation-integration`. A new draft PR carries the follow-up;
the old PR remains merged. Main currently has neither classic branch protection
nor applicable branch rules (read-only API checks); this does not waive review or
the candidate's CI. No merge or release is implied.

The committed candidate's compressed Git archive is 4,529,311 bytes (4.32 MiB),
versus 4,090,006 bytes for fetched main. This exceeds the repository's 4 MiB growth
guard; it is not a GitHub file-size limit. The guard is explicitly revised to
5 MiB for the normalized-fit, response-surface and deterministic-validation source,
tests and documentation. Results, caches and current-machine paths remain absent
from the candidate. The 250 KiB fixture-review rule remains; future increases
still need a stated user benefit. Do not hide required files from archives or
delete evidence to satisfy the old number. Hosted CI routing remains unchanged:
[workflow-level path skipping can leave required checks pending](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow).

Validation for this policy-only follow-up: parsed YAML comparison confirms that
only the archive threshold and its shell comments changed; workflow triggers,
matrices and test commands are identical. The public-language gate passes all
25 files, current roadmap/test-guide link targets exist, and whitespace checks
pass. The 638-input comparison identifies only CI, the test guide and the
newline-only MCSE test cleanup as execution-input deltas. No full suite or new
scientific fit was rerun for these changes.

**Saved-result cost measurement, completed 2026-10-02.** The existing profiler
had one stale private validator name; it now calls `_check_generalized_sample_run`,
the same validator used by the maintained loader. Product code is unchanged.
The corrected profiler completed one first-use run and three same-process warm
repetitions on the existing normalized exchangeable AdvancedHMC 6,000-draw record.
All four verify unchanged input/source hashes, exact save/reload results and,
for the three repetitions, equality with the first run's reconstructed values.
No posterior fit or full test suite was launched.

| Phase | First call (s) | Warm median, 3 repetitions (s) | Warm cumulative allocation (MiB) |
| --- | ---: | ---: | ---: |
| Deserialize | 0.250 | 0.0046 | 3.7 |
| Target identity | 1.995 | 0.0061 | 3.2 |
| Payload hash | 0.132 | 0.0497 | 123.0 |
| Validate retained run | 0.614 | 0.0716 | 43.3 |
| Reconstruct diagnostics | 3.995 | 1.988 | 1,920.5 |
| Comparison summaries | 2.593 | 0.261 | 526.1 |
| Serialization alone | 0.761 | 0.0085 | 1.6 |
| Save with validation | 2.384 | 2.135 | 2,095.0 |
| Load with validation | 2.069 | 2.173 | 2,097.2 |

Environment: Apple M1 Max, macOS 27.0.1, Julia 1.12.6, one Julia/BLAS thread,
the existing project/manifest and retained compiled caches. The earlier failed
profiler attempt spent 278.47 seconds in imports/includes with dependency
precompilation; the corrected attempt reused those caches and took 4.14 seconds
for setup. These observations are not a controlled cold/warm speedup estimate.
The completed guarded process took 63.41 seconds with a sampled peak owned RSS of
1.81 GiB, zero exit code and no elapsed-time cutoff. Allocations in the table
are cumulative bytes, not peak memory. The profiler explicitly runs GC before
stages and repeats validation inside save/load; its outer duration is not one
ordinary user operation, and the stages are not an additive application timeline.

The warm stack profile points to repeated design/Q validation and parameter
blueprint construction inside `_mgmfrm_guarded_local_fit_direct_draw_values`:
each draw enters both the constrained-parameter conversion and the pointwise
likelihood's checked design path. This motivated preparing target-owned design
information once per call while retaining boundary checks and per-draw
constraint/density validation; the completed comparison follows below.
Density/gradient, warmup/retained sampling and rendering costs remain separate
work under priority 3, and the historical M0 hold remains open.

Local reproducible recipe, per-stage timings, stack profiles and verification:
`results/workflows/20261002-saved-result-cost-02/`. Failed preparation and the
stale-profiler attempt remain in `20261002-saved-result-cost-01`; they are not
successful measurements. These ignored artifacts are local evidence, while the
table and scope above travel with the source.

**Saved-result improvement, verified 2026-10-02.** The batch converter now builds
the existing validated parameter blueprint and Q loading indices once per call.
Each draw still receives parameter-length and constraint checks; standalone and
heldout likelihood entry points retain design validation. Preparation is rebuilt
on each call so a mutated owned design cannot reuse stale validation. No density,
gradient, sampling, cache-format or default change is intended.

The same saved 6,000-draw input, Julia 1.12.6, dependency manifest, hardware,
one Julia/BLAS thread and profiling script were used before and after. Each side
has three warm repetitions in its own process with retained compiled caches;
the host is uncontrolled. Source hashes differ only in `src/bayesian_fit.jl` and
`src/facet_workflow.jl`. All four new runs, including first use, exactly match the
prechange diagnostic tables, parameter summaries and retained draws, and verify
unchanged input hashes and save/reload equality.

| Phase | Before warm median (s) | After warm median (s), range | Local speed ratio | Cumulative allocation before → after (MiB) |
| --- | ---: | --- | ---: | ---: |
| Reconstruct diagnostics | 1.988 | 0.232, 0.227–0.243 | 8.56× | 1,920.5 → 250.1 |
| Save with validation | 2.135 | 0.384, 0.379–0.402 | 5.56× | 2,095.0 → 423.7 |
| Load with validation | 2.173 | 0.378, 0.372–0.390 | 5.74× | 2,097.2 → 425.9 |

Diagnostic allocation falls 87.0%; comparison-summary time remains approximately
0.261 s. Cumulative allocation is not peak memory. The complete instrumented
process takes 44.73 s with sampled peak owned RSS 1.67 GiB; forced GC, repeated
operations and first-use compilation prevent treating it as one user operation.
This is a local postprocessing comparison, not a general or sampling speedup.

Focused checks pass eight test sets / 6,315 assertions with zero failures,
errors or broken checks, including 330 new batch boundary/equation assertions,
the existing density/derivative checks, heldout-Q guards and synthetic saved-result
workflows. They complete in 892.29 s with sampled peak RSS 1.60 GiB, without an
elapsed-time cutoff. An isolated test environment supplies the existing test-only
extras; root dependencies are unchanged. No full local suite or posterior fit is
rerun. Recipes, hashes, timings and receipts remain locally under
`results/workflows/20261002-draw-preparation-01/`; the table above is the portable
summary. New-head hosted CI remains separate from these checks.

The first PR CI run also exposed an example-entry defect: invoking the saved-review
example with no arguments loaded optional CairoMakie before showing usage.
Commit `77d8a6b` moves no-argument/`--help` handling before imports. Six checks in
an empty package environment, 181 existing public-language checks and the 25-file
wording gate pass; the help entry also works on Julia 1.10.8 without packages.
Actual saved-fit review still requires the documented plotting environment.
The distribution gate and optional-dependency policy are retained. Inspect the
revised PR head's CI before considering integration complete; independent reader
review and scientific acceptance remain outstanding.

<details>
<summary>Dated progress history — evidence retained; use Current decisions for the work order</summary>

**Archived update, 2026-09-27 JST:** The [saved-window precision comparison](docs/internal/mgmfrm-foundation-scale-acceptance.md)
recomputes all 150 quantities plus two exact pivots on four windows of each
of the three saved fits. Both transformed full fits retain their pass; every
short window fails the necessary focal diagnostics. There are no opposite
resolved classifications, yet two ungated short-window D1 coverage risks are
0.517%/0.744% against the exact normal pivot. Agreement is therefore not an
error-rate audit, and short-window results do not replace the original gates.
All 5,472 quantiles, 21,888 rank boundaries and 192 analytic risk components
are checked. A named all-150 conditional-CDF design now separates 112 normal,
36 location-invariant and two product quantities; implementation is next,
initially using saved draws with zero new posterior fits. Nuisance-chain error
remains, so this is not an exact marginal reference or certified e/u bound.
The three requested margins and original raw cohort remain unchanged.

**Previous update, 2026-09-27 JST:** The [replication-budget comparison](docs/internal/mgmfrm-foundation-scale-acceptance.md)
keeps all three requested margins (2.5/5/7.5 percentage points) and all 150
quantities. Fifteen conditional e/u scenarios are inverted by an exhaustive
integer scan, preserving nonmonotone binomial thresholds. With unverified
u <= 1% and e <= 0.1%, separately checked rounded counts of 35,000/4,200/1,600
give joint nominal acceptance lower bounds >= 80%. At the unchanged pilot
budget their serial-time references are 412.3/49.5/18.8 days, excluding review;
these are not launch plans or minimum actual sample requirements. Current
4,000-draw evidence does not establish the assumed 1% unresolved bound.
Three tests and 36 independent binomial-tail sums pass. No margin is adopted,
no new fit is launched, and the original raw cohort remains 4/1/269. The next
bounded task is a full-roster reference/precision design to assess the e/u
assumptions before choosing replication volume and an overall error budget.

**Previous update, 2026-09-26 JST:** The [full-roster review and independent replication](docs/internal/mgmfrm-foundation-scale-acceptance.md)
retain the original 150 quantities. Reusing the coordinate pair preserves the
raw failure and transformed pass under the expanded diagnostics. One new,
independently generated candidate-C dataset also passes with transformed
coordinates at the same four-chain, 1,000 warmup + 1,000 retained budget:
maximum focal R-hat 1.00737, minimum bulk ESS 771.43, minimum quantile ESS
1,102.54, and zero retained divergences/depth hits. Actual k=2 classifications
leave 5 median and 9 coverage events unresolved among the dependent 150 quantities.
Exact conditional unresolved probabilities for the two location pivots remain
about 3%; all-quantity error bounds and statistical acceptance remain open.
No raw fit was added for the new dataset, so it does not replicate the earlier
raw-versus-transformed effect estimate. One new fit, no retries/extensions,
no public-default change, and the original raw cohort remains 4/1/269.

**Previous update, 2026-09-26 JST:** The [fixed-budget coordinate comparison](docs/internal/mgmfrm-foundation-scale-acceptance.md)
completed two AdvancedHMC fits on the same candidate-C dataset, each with four
chains and 1,000 warmup plus 1,000 retained draws per chain. Raw coordinates fail
the declared gate; transformed coordinates pass. D1/D2 location-pivot bulk ESS
rises from 328/231 to 8,813/7,945 with nearly unchanged retained leapfrog counts
(124,896/124,016). Negative lag-one correlation accompanies ESS estimates above
the 4,000 retained draws; classifier effective counts remain capped at
4,000. Conditional k=2 unresolved probabilities improve to about 3–4%, not 1%.
Ninety-four saved-record checks and independent reconstruction of all 16,000
pivot values/eight risk rows pass; 69 source/environment hashes stay unchanged.
This supports the transformed research route on one previously inspected
dataset, not general calibration acceptance. Next assess all 150 quantities
and replication on independent data. No default/public-API change, draw
extension or original raw-cohort change was made.

**Previous update, 2026-09-26 JST:** A [normalized location-coordinate research adapter](docs/internal/mgmfrm-foundation-scale-acceptance.md)
reuses the existing unit-Jacobian map while evaluating the complete normalized
prior. It preserves raw-space initialization/jitter, canonical stored draws,
target identity and manual saved-result consumers. Mathematical checks pass
352 assertions, four tiny operability fits pass 172 checks, and 32 principal
checks on the actual 128-coordinate foundation target confirm density, gradient
and conditional Hessian agreement. The previous input and samples are unchanged.
This is an AdvancedHMC research path, not a public fit option or evidence of
improved mixing. Next design a fixed-budget raw/transformed comparison within
AdvancedHMC; comparing only to the previous CmdStan run would confound backend
and coordinate effects. Original cohort and scientific acceptance remain open.

**Previous update, 2026-09-26 JST:** The [foundation location-oracle evaluation](docs/internal/mgmfrm-foundation-scale-acceptance.md)
now connects two exact standard-normal posterior pivots to conditional
classification-error and unresolved probabilities. One independently generated
candidate-C dataset was fitted with CmdStan, four chains and 1,000 warmup plus
1,000 retained draws per chain. Retained divergences/depth hits are zero, but
the declared diagnostic gate fails (D2 location-pivot R-hat 1.01879, bulk ESS
228.12); formal classifications remain unresolved. Ungated probability masses
are explicitly descriptive, not bounds for all 150 quantities or future data.
Eleven density/response checks, three new Python tests and seven rank-band
regressions pass; independent arithmetic reproduces all 8,000 pivot values and
four risk rows. The pre-MCMC sandbox compilation failure is retained separately.
No sampling extension or original-cohort change occurred. Next verify a
prior-preserving location coordinate map for the normalized target before
designing another sampling comparison.

**Previous update, 2026-09-26 JST:** The user-selected 2D fixed-Q foundation now has a
[scale and acceptance worksheet](docs/internal/mgmfrm-foundation-scale-acceptance.md).
Existing exchangeable case C supplies an explicit six-scale computational
comparison candidate, with marginal, pairwise and whole-block prior widths.
Conditional positive acceptance retains all 150 quantities: at ±5 percentage
points, 274 datasets have an empty median acceptance region even with no
classification errors or unresolved outcomes. The 45-setting design grid
separates this obstruction from conservative joint-power lower bounds and the
unverified finite-MCMC assumptions. No scientific tolerance/default is adopted
and no sampler runs are added; the raw cohort remains 4/1/269. Next assess the
candidate's numerical classification precision before commissioning a new cohort.

**Previous update, 2026-09-26 JST:** The [normalized-prior public connection](docs/internal/mgmfrm-prior-choice.md)
adds explicit `Experimental.NormalizedMGMFRMPrior` and `NormalizedMGMFRMFit`.
One distribution, six declared scales and the source-rater identity now connect
prior prediction, maintained Julia/CmdStan targets, summaries/MCSE, diagnostics,
existing-row prediction, manual fit caches and report/figure bundles. Existing
raw results, fixed-coefficient `ExchangeablePrior`, private v1/v2 sample formats
and target identities keep their meanings. Correlated MGMFRM, non-raw sampling
coordinates and automatic request caching remain outside this adapter.
Sampler-free checks cover 2,238 existing prior assertions, 37 API/boundary
assertions and 1,004 saved-result/report assertions; 1,870 shared correlated/API
regressions also pass on Julia 1.12.6. Four tiny Julia/CmdStan fits pass 28
operability checks while retaining sampler warnings. Five rendered figure
kinds pass 40 checks; local HTML is built with Git links disabled because local
Git reads stalled. No remote CI, minimum-version run or scientific acceptance
is claimed. Scientific widths, claim-specific precision and statistical
acceptance remain separate decisions; the original raw cohort remains 4/1/269.

**Previous update, 2026-09-24 JST:** The [prior contract connection](docs/internal/mgmfrm-prior-choice.md)
now gives the private normalized MGMFRM target direct Gaussian prior generation,
existing prediction summaries/figure data, and the same derived prior metadata
after loading either existing sample-record version. Actual kernel, marginal
and contrast scales, source log-consistency means, rater identity and the
estimated-loading scope come from the canonical prior record. Its serialization
and identity definitions remain unchanged. Deterministic generator/density,
independent response-equation and serialization checks pass 2,238 assertions;
351 raw-prior and 967 prior-measure regression checks also pass, without fits.
This completes the internal connection, not public normalized-prior fit/report
integration or scientific scale selection. Public `ExchangeablePrior` remains
fixed-coefficient MFRM-only, and the original raw cohort remains 4/1/269.

**Previous update, 2026-09-24 JST:** The [prior-response review](docs/internal/mgmfrm-prior-responses.md)
connects contrast widths to category predictions through deterministic examples
and six joint-prior conditions, with 4,096 paired parameter panels per condition
and no posterior fits. Matching average variance changes the interpretation of
raw/exchangeable comparisons. Shrinking step variance reduces highly concentrated
cells while increasing endpoint mass in the declared comparison; neither metric
alone chooses a scientific prior. A score-reflection calculation exposes the
raw step prior's directional asymmetry, with normalized-reference regression
checks at K=2,3,4,6. Independent Python/Julia predictions, densities and generator
covariances agree; 155 study checks and 967 prior-measure checks pass. No default,
scientific SD, public-prior scope or original 4/1/269 cohort changes. Next make
the MGMFRM prior's distribution, scale convention and model scope consistent
across explicit specification, prediction, persistence and reporting; selecting
scientific widths and statistical acceptance remain separate decisions.

**Previous update, 2026-09-24 JST:** The [prior-choice review](docs/internal/mgmfrm-prior-choice.md)
separates raw, normalized exchangeable and normalized source distributions,
their exact moments, available APIs and scale-matching conventions. When rater
IDs have no prior scientific distinction, exchangeability is the preferred
structure for the next scientific candidate; no SDs or new default are adopted.
The source reference has a nonzero log-consistency mean for its distinguished
rater, not merely a different normalizer. The public `ExchangeablePrior` remains
fixed-coefficient MFRM-only. A reproduced empty-step failure in the private
normalized Julia density is repaired for K=2; the MGMFRM Stan K>=3 boundary is
unchanged. Prior-measure checks pass 951 assertions without fits. The original
raw cohort remains 4/1/269. Next relate interpretable prior-contrast widths to
response predictions before deciding a scientific scale or public integration.

**Previous update, 2026-09-24 JST:** The [estimand and identification review](docs/internal/mgmfrm-estimands-identification.md)
derives the conditional response model's equivalence class for complete crossed,
pure-Q designs with ability variation in each dimension. It distinguishes
scale-dependent ability differences, origin-dependent item-location differences,
and invariant comparisons. Proper-posterior existence is established separately
for the declared proper raw prior and valid finite category observations.
Deterministic probability reconstruction and counterexamples connect the algebra
to the implementation without new fits. Sparse/mixed-Q identification, statistical
acceptance and prior choice remain separate questions. The next priority is the
scientific role of the existing priors and units; the 4/1/269 cohort is unchanged.

**Previous update, 2026-09-24 JST:** A [claim-based scope review](results/workflows/20260924-core-sbc-scope-review-01/report.md)
compares continuing the remaining 269 attempts with fresh, narrower studies.
Preserving all facet roles, location checks and named-person sentinels gives
54 quantities and a conditional detection design of 242 datasets. Adding the
26 original scientific contrasts gives 80 quantities and 253 datasets, saving
only 16 new fits relative to the existing remaining roster. Neither candidate
is adopted; all original evidence and the 4/1/269 status remain unchanged.

The review also separates global positive acceptance via intersection–union
tests from departure detection and simultaneous interval reporting. Global
false acceptance need not use Bonferroni over every required component, but
joint power and finite-MCMC classification accuracy still need a design. Under
the current conservative count procedure, a hypothetical ±5-point acceptance
margin cannot support uniform 80% power over the allowed u=0.05, e=0.001
mechanisms, regardless of dataset count. This is a conditional counterexample,
not a universal impossibility result or an adopted margin. The priority is to
connect computational precision/reference evidence to the intended claims,
rather than substitute a smaller roster solely to save runtime. No new fits,
scientific acceptance or changes to the frozen execution plan were made.

**Previous update, 2026-09-24 JST:** [Decision preparation](docs/internal/mgmfrm-core-sbc-decision.md)
now separates complete execution, conditional SBC departure screens, and positive
statistical acceptance. A read-only reviewer recomputes the existing primary
summary, checks all 274 ledger entries, separates reasons for unresolved outcomes,
and reports conditional simultaneous probability envelopes. Complete non-rejection
never becomes acceptance; the original plan, runtime, criteria and cohort remain
unchanged at **4 completed, 1 failed, 269 unstarted**.

The e=0.001 classification-error assumption supports Type-I error control and
the new envelopes; u=0.05 is needed for the reference power, not for conservative
missing-outcome accounting. Neither bound is verified for MGMFRM. Even hypothetical
fully resolved nominal counts at n=274 give simultaneous conditional probability
intervals of about [0.385, 0.615] for the median event and [0.816, 0.957] for 90%
coverage. These illustrate precision, not newly chosen acceptance tolerances.
The [review supplement and checks](results/workflows/20260924-core-sbc-decision-prep-01/report.md)
also explain what an independent reference would need to establish the error
bound. No new fit or data generation was performed. Broad C1–C6 acceptance and
independent scientific review remain separate unfinished work.

**Previous update, 2026-09-24 JST:** The [resumed independent-data batch](docs/internal/mgmfrm-first-acceptance.md#51-依存補完後の独立データ3件を完了する)
completed joint-003 through joint-005 with the original seeds, orthogonal
coordinates, four chains, 1,000 warmup and 4,000 retained iterations per chain.
A prospectively recorded runtime supplement adds the missing include while
preserving all original 71 source files. All three fits pass the declared
diagnostics; their maximum R-hat is 1.002131, minimum bulk ESS is 3,706, and
minimum quantile ESS is 5,238. Retained divergences and depth-limit hits are zero.

The full ledger now contains **4 completed, 1 failed, 269 unstarted** out of
274 slots. Joint-002 remains failed and was not retried. Despite sufficient
quantile ESS, the new three datasets retain 6/450 unresolved median and 9/450
unresolved coverage classifications under the primary rank bands. These are
dependent quantity counts, not independent calibration trials or validated
unresolved-rate bounds. The k=4 descriptive sensitivity is also retained.

Julia replays all three archived caches, checking 6,144,000 raw values; Python
reconstructs 1,408,000 derived values and 576,000 conditional residual values
across all four completed datasets. The [report, figures and verification](results/workflows/20260924-core-sbc-batch-02/report.md)
preserve the prior failure and every planned slot. This batch ends at its three
declared fits. Calibration acceptance, the classification-error assumptions,
the earlier raw/coordinate questions and 83 inconclusive comparisons remain open.

**Previous update, 2026-09-24 JST:** The [independent-data batch](docs/internal/mgmfrm-first-acceptance.md#50-独立データ再開時の凍結環境不備を検出し修正する)
stopped at joint-002 before sampling: the frozen runtime omitted a Julia helper
included by the evaluation module. Package import and all recorded hashes had
passed, exposing the gap between matching listed files and a runnable snapshot.
One new dataset was generated; no new sampler or fit completed. The full ledger
now retains **1 completed, 1 failed, 272 unstarted** out of 274 slots. Joint-003
through joint-005 remain unstarted under the declared batch stop rule.

Future launches now bind and copy the missing dependency, and load the saved
Python/Julia worker before claiming an ID or generating data. Nine orchestration
checks and actual complete/incomplete snapshot import checks pass. A separate
copy of the original 71 files plus the missing helper also imports successfully;
the original frozen runtime, launch, joint-001 and failed attempt remain intact.
The [report and verification](results/workflows/20260924-core-sbc-batch-01/report.md)
record this engineering repair, not a scientific continuation or calibration
result. Resuming the remaining IDs requires a prospectively recorded runtime
supplement; joint-002 is retained as failed. Statistical acceptance, the
classification-error assumptions and earlier diagnostic questions remain open.

**Previous update, 2026-09-24 JST:** The [saved-chain localization review](docs/internal/mgmfrm-first-acceptance.md#49-保存済みチェーンでraw警告の位置を絞る)
locates the raw seed 9432404 warning mainly in D2 common-location scale mixing.
The person mean's folded R-hat is 1.016253, while the item-I4 offset has R-hat
0.999923 and the maximum over 50 centered D2 person quantities is 1.005154.
Chain 2 has standardized-residual mean 0.0088 but SD 0.8488, with a second-moment
deficit in both fixed halves. Other chains also vary between halves; no chain
or retained prefix is removed and no original fit is requalified.

Across all eight fits, orthogonal coordinates have smaller common-location
MCSE but larger item-offset MCSE. This is an estimand-specific tradeoff, not
uniform efficiency superiority or proof of a sampler defect. The existing
independent-data cohort remains orthogonal, four chains, 1,000 warmup and
**4,000 retained iterations per chain**, distinct from the shorter coordinate
comparison. Its precision and classification-error assumptions still require
validation. Python independently reconstructs 4,320,000 derived values and
3,240 R-hat components; four diagnostic figures and the [decision report](results/workflows/20260924-raw-mixing-review-01/report.md)
preserve every saved chain. No new fit, dataset, sampler/default change or
cohort continuation was performed. The raw arm/coordinate contrast, 1/274
cohort status, 83 inconclusive comparisons and statistical acceptance remain open.

**Previous update, 2026-09-24 JST:** The [fixed-data coordinate comparison](docs/internal/mgmfrm-first-acceptance.md#48-同じデータと推定長で計算座標とseedを比較する)
completed all eight declared scientific fits: four fresh seeds per raw/orthogonal
coordinate path, holding the target, AdvancedHMC version, four chains and
1,000 warmup/1,000 retained iterations per chain fixed. All four orthogonal fits
qualified; their D2 standardized second-moment mean was 1.006436 with the
predeclared approximate reference band [0.910980, 1.101892]. This detected no
persistent deficit and does not establish equivalence or calibration.

One raw fit failed the declared diagnostics, including primary-moment
rank-normalized R-hat 1.016848. The raw arm and coordinate contrast therefore
remain unresolved, retaining all four raw fits rather than pooling a qualified
subset. Their descriptive estimates of the second moment and raw-minus-orthogonal
difference are 1.001399 and -0.005038. All retained chains have zero recorded
numerical errors and depth-limit hits; those facts do not cancel the R-hat
warning. Python independently reconstructs 288,000 conditional residual values
from 32,000 raw draws (maximum difference 1.42e-14) and checks 64,000 transition
rows. The [report, figures and verification](results/workflows/20260924-coordinate-comparison-01/report.md)
preserve every planned fit, its adaptation record and the pre-run protocol.
All 77 bound source files and the historical fits remain unchanged. These are
eight new fits of one existing dataset, not eight new SBC replications; the
1/274 cohort status, 83 inconclusive comparisons and statistical acceptance
remain unchanged. This comparison ends at its declared eight fits.

**Previous update, 2026-09-24 JST:** [Saved adaptation review](docs/internal/mgmfrm-first-acceptance.md#47-保存した適応記録をfitと照合して読む)
checks complete records against their fit caches and native files, then reports
whole warmup, the final specified fraction, and retained telemetry separately.
Both backends share the review entry point, while missing CmdStan metric history
remains unavailable. No new fit or transition is needed. The existing short
CmdStan engineering record has zero divergences in its final 40 warmup iterations
per chain but reaches its configured depth limit in all 40; the report does not
turn record integrity into a convergence or calibration verdict. Historical
source hashes remain provenance, not a requirement to match today's checkout.
The original cohort and scientific acceptance remain unchanged.

The [actual AdvancedHMC integration follow-up](docs/internal/mgmfrm-first-acceptance.md#実advancedhmc出力による接続検証)
now closes the previous synthetic-only review gap. The existing 18 paired
conditions per Julia environment run through recording, cache reload and review,
preserving ordinary/recorded draws, diagnostics and subsequent RNG values.
Julia 1.10.8/AdvancedHMC 0.8.6 and Julia 1.12.5/AdvancedHMC 0.8.5 each pass
9,469 assertions. All 36 saved records are retained; Python independently checks
72 chains, 8,256 transition rows, window summaries and initial coordinate maps.
This is 72 small engineering fits, not new scientific replications or a
cross-version trajectory-equivalence claim. Recorder, reviewer and sampler
sources remain unchanged. The maintained regression now covers the actual
AdvancedHMC path; no further recording feature is needed to close this gap.

**Previous update, 2026-09-24 JST:** [CmdStan adaptation provenance](docs/internal/mgmfrm-first-acceptance.md#46-cmdstanの適応記録を同じ保存経路へ接続する)
extends the opt-in recorder to independent fixed-Q MGMFRM on raw CmdStan
coordinates. Native CSV, data/init JSON and adapted metric JSON are preserved
alongside the ordinary cache, with actual chain starts/seeds, commands,
executable and file hashes. Rounded CSV metric comments are not treated as
full-precision matrices; the helper requests the official metric JSON output.
Dense matrices retain their original entries and report tiny numerical
asymmetry rather than being silently symmetrized.

Warmup metric history and energy errors remain unavailable on CmdStan and are
explicitly missing. Native CSV preserves warmup parameter states, unlike the
AdvancedHMC recorder. These are backend-specific observation boundaries, not
matched posterior evidence. The native check uses isolated CmdStan 2.39.0,
six paired sampler conditions and one ordinary/recorded public-fit pair on
short synthetic data. Parser/failure checks run on Julia 1.10.8 and 1.12.5;
AdvancedHMC recording and existing backend regressions remain protected.
The final native run passes 174 sampler and 14 public-fit checks; the parser
and failure tests pass 75 + 9 checks in both Julia environments. Python
independently matches all 1,712 recorded rows in 14 chains to the native CSVs
and verifies metric/init/CSV/cache hashes. Only `src/cmdstan_fit.jl` changed
among this turn's 71 bound runtime files; the original frozen 71 files and
three historical fits/exports remain intact. See the [engineering record](results/workflows/20260924-cmdstan-adaptation-01/)
for attempts, native artifacts and final verification. No scientific refit,
cohort alteration, hosted CI or full fit-suite run is implied. The original
variance concern, 83 inconclusive comparisons, 1/274 cohort status and
statistical acceptance remain open.

**Preceding update, 2026-09-24 JST:** [Opt-in adaptation recording](docs/internal/mgmfrm-first-acceptance.md#45-今後のadvancedhmc-fitへ適応記録を接続する)
now saves a separate JSON record alongside an ordinary fit cache for independent
fixed-Q MGMFRM/AdvancedHMC. It records actual jittered chain starts, coordinate
order, all warmup/retained sampler rows, copied inverse mass matrices when they
change, the retained kernel and input/source provenance. Each row distinguishes
the metric used by its transition from the metric after adaptation. Existing
fit types, cache schemas and default recording behavior are preserved.

Julia 1.10.8 and 1.12.5 each pass 18 paired synthetic-fit conditions (two
coordinate systems, three metrics, warmup 0/120/200), with exact draw, density,
statistics, diagnostic and subsequent RNG equality. Recording checks total
9,108 assertions per environment; existing observer/density regressions and
shard selection also pass. An initial test assumption about mass adaptation at
120 iterations was corrected from the installed adaptor schedule, retaining
that case and adding 200 iterations to exercise actual metric updates. Failed
attempts and the amendment are preserved in the [engineering record](results/workflows/20260924-adaptation-record-01/).
The test is registered in the ordinary fitting group, not the fit-free job;
hosted CI and the full fit suite were not run.

The helper is opt-in research tooling, not an exported API, an exact restart
facility or a recovery of missing historical records. CmdStan recording remains
outside this implementation. Only `src/bayesian_fit.jl` changed among the 71
previously bound runtime files; the original frozen 71 files, three prior-002
fits and their exports remain unchanged. No scientific refit or cohort change
was made. The original variance concern, 83 inconclusive comparisons, 1/274
cohort status and statistical acceptance remain open.

**Preceding update, 2026-09-24 JST:** [Saved sampler-record audit](docs/internal/mgmfrm-first-acceptance.md#44-保存済みの適応探索記録で判別できる範囲を確定する)
reproduces the existing per-chain summaries from all 24,000 retained rows
in the three prior-002 fits. All 12 chains have constant retained step sizes,
zero retained divergences/depth-limit hits and no exactly repeated adjacent
full raw states. These facts do not resolve the original D2 variance deficit.
The original AdvancedHMC retained step sizes are 0.15974–0.20133; the stored
control value 0.03 is the requested initial value, not the adapted result.

The audit identifies a concrete evidence gap: warmup survives only as chain
totals, with no iteration history, warmup states or adapted inverse mass matrix.
CmdStan energy-error fields are missing, not zero. The [record](results/workflows/20260924-sampler-records-01/analysis.json)
preserves all exported statistics and their availability, retains the first
CmdStan follow-up's diagnostic warnings, and makes no new hypothesis tests.
Public fitting documentation now distinguishes summary coverage from full
adaptation history and notes that refreshing a cache does not add unsupported
history. The next implementation priority is explicit adaptation provenance
for future comparisons; no logging mechanism, new fit, sampler change or
frozen-cohort alteration is included in this audit. Scientific acceptance,
the cause of prior-002, 83 inconclusive comparisons and 1/274 status remain open.

**Preceding update, 2026-09-24 JST:** [All-coordinate gradients and coupled curvature](docs/internal/mgmfrm-first-acceptance.md#43-保存標本の全勾配と非線形座標変換の結合曲率を照合する)
extend the saved prior-002 checks beyond its two mean coordinates. At six
fixed saved states, all 128 raw and orthogonal-coordinate sampler gradients
agree with the existing independent Python analytic score; maximum differences
are `7.82e-14` and `9.59e-14`. Directional curvature includes the second
derivative of the loading-dependent item translation, even though the map's
Jacobian determinant has absolute value one. Independent finite differences
at all three declared step sizes agree to `1.89e-9`; deliberately omitted
Jacobian/curvature terms and incorrect independent offset priors are detected.

The new cache-free regression has 66 assertions on each of Julia 1.10.8 and
1.12.5, including mixed-Q and three-dimensional examples, and is registered
in existing CI and generalized tests. Saved-state checks add 60 assertions
per environment; these repeat the same six states, not independent posterior
or calibration replications. The [record](results/workflows/20260924-coupled-geometry-01/verification.json)
retains full gradients, Jacobians and directional results. Inference code,
existing fit and both 71-file runtime sets are preserved. No new fit, random
transition, dataset, full suite or GitHub update is added. The original
variance concern and scientific acceptance remain open; this finite-point
consistency evidence does not validate adaptive, full-dimensional exploration.

**Preceding update, 2026-09-24 JST:** [Independent one-transition NUTS probes](docs/internal/mgmfrm-first-acceptance.md#42-既知分布からの独立1遷移でnutsの停止と状態選択を点検する)
extend the previous deterministic checks to full momentum refreshment,
tree building, generalized stopping and multinomial selection in the actual
AdvancedHMC kernel. The prospectively fixed 36-cell experiment completed
88,488 independent exact-normal-start transitions on fixed-nuisance Gaussian
conditionals, without model fitting or adaptation. No cell rejected the
declared D2 second-moment null after Bonferroni correction; observed moments
ranged from 0.93427 to 1.07748. This is non-detection in a limited local test,
not equivalence, an acceptable-bias bound or posterior calibration.

Separate paired bridges (72 analytic plus 72 actual embedded-density
transitions) agreed to `2.01e-14`, with matching step counts and tree depths.
No primary transition reported a numerical error or reached maximum depth.
All initial/output states and sampler statistics are retained, and independent
Python arithmetic verifies the conditional parameters and reported quantities.
The 27-assertion cache-free mechanics check passed on Julia 1.10.8 and 1.12.5
and is registered in CI; the larger statistical experiment is not a CI gate.
The [analysis record](results/workflows/20260924-location-nuts-01/verification.json)
preserves the original fit, 71 current runtime files and 71 frozen copies.
Full-dimensional coupled motion, adaptation, the prior-002 cause, 83
inconclusive comparisons and 1/274 cohort status remain unresolved. No GitHub
update or full fitting suite is claimed.

**Preceding update, 2026-09-24 JST:** [Fixed-nuisance Gaussian location dynamics](docs/internal/mgmfrm-first-acceptance.md#41-既知の位置条件付き分布で計算座標と決定的な積分処理を照合する)
now connect the analytic location conditional to the actual model density,
existing orthogonal transform and installed AdvancedHMC leapfrog integrator.
Mean, orthogonal and analysis-only whitened coordinates are checked against
closed-form Gaussian updates, with matched momentum/metric transformations
and deliberately incorrect controls. The cache-free check has 676 assertions
on each of Julia 1.10.8 and 1.12.5 and is wired into the existing fit-free CI
job and ordinary generalized group. Saved prior-002 snapshots are separate
finite probes; they are not posterior replicas or a replay of the full NUTS
trajectory. The [record](results/workflows/20260924-location-dynamics-01/verification.json)
binds versions, independent Python arithmetic and input/runtime preservation.

No new fit, RNG-driven transition, adaptation, NUTS tree or state selection
is executed. Reversibility/volume alone can pass a wrong force, and invariance
alone can pass a frozen state; these limitations are explicit test controls.
The follow-up design separates independent one-transition stationarity probes
from full-fit seed, coordinate and engine comparisons. Its 36-cell power
reference is conditional, unadopted and not a launch instruction. The original
prior-002 cause, 83 inconclusive comparisons, 1/274 cohort status and scientific
acceptance remain open. Current inference sources and the original frozen
runtime are preserved; no full suite or GitHub-hosted run is claimed.

**Preceding update, 2026-09-24 JST:** [Conditional 3D item response surfaces](docs/src/fitting.md#3d-item-response-surfaces-for-mgmfrm)
are implemented for saved independent fixed-Q MGMFRM fits.
`BayesianMGMFRM.item_response_surface` returns the posterior mean and pointwise
central intervals of all category probabilities by default, with explicit
selection of one category or expected rating.
`BayesianMGMFRM.plot_response_surface` adds an editable CairoMakie 3D mean
view with numbered ability axes, category-colored wireframes and a legend,
plus category-specific interval-width heatmaps on a shared scale. Category
colors remain consistent across all/single-category views for the same scale.
Item/rater labels, two ability axes,
explicit fixed values for all remaining dimensions and the whole-fit warning
are retained. All retained joint draws are evaluated by default; no fitting,
random selection, population marginalization or parameter-mean substitution
occurs. Curvature is not evidence of an ability interaction; pointwise
intervals are not future-rating intervals or simultaneous bands. Pure-Q items
remain flat along excluded dimensions. This does not extend supported models
or add a report-bundle section.

All 1,594 fit-free postprocessing checks pass locally on Julia 1.10.8 and
1.12.5, including 371 numerical surface checks against the actual model
kernel and a separate three-category formula. The ordinary test entry point
and fit-free CI group both include the new checks. A further 67 renderer
checks and 10 checks on the existing 16,000-draw fit pass; PNG/SVG outputs
use numbered abilities and category legends. No new fit or calibration
evidence is added. See the [task record](results/workflows/20260924-response-surface-01/verification.json)
for rendering, saved-fit replay and documentation verification; GitHub-hosted
CI and the full fitting suite have not been run.

**Frozen-cohort execution:** Adding the new source include changes
`src/BayesianMGMFRM.jl`; the current working tree is now a different package
version from the 71-file frozen SBC runtime. The old setting/hashes were not
resealed. All 71 original files are preserved in the verified
[frozen runtime copy](results/workflows/20260924-response-surface-01/frozen-runtime-verification.json)
at `results/workflows/20260924-response-surface-01/frozen-runtime`.
Its controller validates the original cohort and reproduces the entire
274-slot collection exactly (one completed, 273 unstarted). To continue that
cohort, use that copy's `scripts/mgmfrm_core_sbc_cohort.py` with the original
cohort directory, rather than the changed working-tree controller context.
This is a source/context/collection check, not a new Julia fit or a change to
the cohort target, budget, prior-002 concern or independent-review status.

**Preceding update, 2026-09-23 JST:** The fit-free [prior-002 distribution review](docs/internal/mgmfrm-first-acceptance.md#40-prior-002の不足が分布のどこにあるかを保存標本から切り分ける)
localizes the original D2 conditional second-moment deficit without resolving
its cause. Fixed normal-reference bins show the largest deficits at absolute
standardized residuals 1.5–2.5. Capping the squared residual at four retains a
gap of -0.08198; omitting any one chain or fixed 250-draw block does not remove
the negative full-moment gap. Independently computed lag-window MCSEs
0.02586–0.02812 remain close to the historical 0.02789. These are exploratory
saved-draw sensitivities, not calibrated tests or transition-bias attribution.
All four equal-length windows of the existing longer CmdStan fit are retained;
none has the original deficit's magnitude, but backend, coordinates and RNG
are confounded. The warning-bearing first follow-up remains unqualified.

Name-based reconstruction checks all 312,000 conditional values across the
three existing fits; 132 summaries and 42 MCSE estimates pass separate
arithmetic checks, including a convolution formulation of the lag-window
variance. The [verification record](results/workflows/20260923-prior002-distribution-01/verification.json)
preserves all 21 input artifacts and 71 frozen runtime hashes. No new fit,
scientific acceptance, full-suite run or GitHub update occurred. Finite-sample
fluctuation, unobserved slow mixing and transition bias remain unresolved;
further tests of the same finite traces alone cannot identify the cause.

**Preceding update, 2026-09-23 JST:** [Postprocessing checks](test/README.md)
now have a single fit-free Julia entry point, `test/postprocessing.jl`, and an
Ubuntu CI job for Julia 1.10.8 and current stable Julia. The entry point reuses
the existing matrix MCSE and numerical figure-data checks. The matrix tests
were moved verbatim; the actual-fit MCSE tests remain intact in the ordinary
suite. The contrast checks now also reuse the deterministic reporting fixture
to verify both named ability dimensions, the reconstructed last rater, warning
preservation, invalid selectors/chain ordering and temporary-cache reload.
No historical posterior cache, study result, renderer or external backend is
needed. These synthetic inputs are not posterior or backend-validation evidence.
All 1,223 checks pass locally on macOS with Julia 1.10.8 and 1.12.5. Both
versions also pass from a 602-file source copy without `results/` or historical
fit caches: 1.10.8 uses the tracked version-specific manifest; 1.12.5 uses an
environment instantiated offline in the copy without importing the working-tree
`Manifest.toml`. The [verification record](results/workflows/20260923-postprocessing-ci-01/verification.json)
records the environments and confirms all 71 frozen runtime sources unchanged.
Test selection passes 45 checks, CI YAML parses, and the source-language gate
passes 24 files. No new fit, calibration evidence, full-suite execution or
GitHub-hosted run was added; independent review remains open.

**Preceding update, 2026-09-23 JST:** The [saved-draw contrast example](examples/saved_mgmfrm_contrasts.jl)
now computes within-dimension ability differences, rater-severity differences
and log-consistency ratios for independent fixed-Q MGMFRM. It preserves joint
draw pairing and chain order, reports central intervals, summary/event MCSE and
contrast R-hat/ESS, and retains the original whole-fit assessment. Optional ROPE
bounds belong to the declared contrast scale; no practical-equivalence or rater
reliability decision is imposed. Constant event indicators keep unavailable
MCSE rather than treating observed fractions zero/one as certainty.

All 41 fit-free synthetic checks pass, including posterior covariance,
direction reversal, autocorrelated indicators and separated chains; this check
is also wired into `fitting_reports`. Replaying the existing 16,000-draw
AdvancedHMC fit and 4,000-draw warning-bearing CmdStan fit passes 56 checks.
All three contrasts retain `mcmc_warning` on the latter. NumPy reconstructs
the six sets of moments, intervals and event counts from every paired saved
draw. This is arithmetic/workflow validation, not new calibration or a
first-class generalized homogeneity API. No sampler, prior or runtime source
change, new fit, full test suite, independent review or GitHub update occurred.
The [verification record](results/workflows/20260923-saved-contrasts-01/verification.json)
confirms both cache hashes and all 71 frozen runtime sources unchanged. The
manual builds with four existing omitted-docstring warnings; language checks
pass for 24 source surfaces and 14 HTML pages. All 108 local fragment links
from the two edited manual pages resolve, including four repaired older links.

**Preceding update, 2026-09-23 JST:** The public manual now connects the analysis
question to [what MGMFRM estimates and fixes](docs/src/scope.md#what-changes-when-you-choose-mgmfrm)
and the [model-specific prior and fitting routes](docs/src/bayesian-workflow.md).
The entry pages distinguish fixed Q from fixed loadings, consistency from
reliability, prior-anchored locations from likelihood identification, and raw
from model-scale summaries. The workflow separates credible intervals from
MCSE, existing-row prediction from held-out evidence, and report completeness
from diagnostic quality; it also explains why positive support makes a
probability above zero uninformative as evidence of an effect.
These are interpretation and routing corrections grounded in the existing
implementation, not new fitting capabilities or statistical validation.
The manual builds with the four existing omitted-docstring warnings; language
checks pass for 23 source surfaces and 14 HTML pages. All 257 local fragment
links from the four changed pages resolve after correcting two old links.
The [verification record](results/workflows/20260923-model-interpretation-01/verification.json)
also confirms all 71 frozen runtime hashes unchanged. No new fit, full test
suite, independent review or GitHub update was performed.

**Preceding update, 2026-09-23 JST:** The [saved-MGMFRM walkthrough](examples/review_saved_mgmfrm.jl)
now connects public cache loading, model/backend and dimension selection,
whole-fit/location diagnostics, warmup history, 90% intervals, MCSE and report
figures without fitting. The [reader instructions](docs/src/examples.md#review-a-saved-mgmfrm-fit-without-fitting)
explain uncertainty and same-row prediction. Location diagnostics and MCSE are
an explicit supplement; they are not automatically part of the ordinary report.

Replay used three existing independent fixed-Q caches: two AdvancedHMC fits and
the warning-bearing CmdStan follow-up. The 16,000-draw fit was also replayed in
a separate Julia process: all 130 summary/MCSE rows and the numerical inputs for
all three figures reproduce exactly. The CmdStan fit keeps `mcmc_warning` in its
whole-fit/location assessments and all figure captions despite a complete report.
The R0 cache initially selected for the warning check is the improved, qualified
fit; that result is retained separately and is not counted as warning evidence.
The [verification record](results/workflows/20260923-saved-mgmfrm-walkthrough-01/verification.json)
checks interval/MCSE/figure agreement, complete retained chains, prediction
settings and unchanged frozen runtime sources. Six representative PDFs were
rendered and visually inspected. The manual builds, with the existing four
omitted-docstring warnings, and language gates pass for 23 source surfaces and
14 HTML pages. No new fit, calibration replication, full CI run or GitHub update
was performed. Independent reader and scientific review remain open.

**Preceding update, 2026-09-23 JST:** [Fit-free Python regression checks](test/README.md)
now have an ordinary CI job and declared NumPy/SciPy dependencies. Runner and
cohort tests construct synthetic settings instead of reading a local study
manifest. Nine standalone test files cover arithmetic, classification,
conditional integration, full-roster failure accounting, export binding and
lossless storage; separate entry points avoid test/script module-name collisions.
All 43 tests pass from a source copy without `results/` or the local
`Manifest.toml`, in a fresh Python 3.14.3 environment on macOS with NumPy 2.4.2
and SciPy 1.17.1. The exact CI test command was run locally, YAML syntax and
Python dependencies checked, and all 71 frozen cohort runtime source hashes
remain unchanged. No new fit or scientific replication was added. GitHub-hosted
Ubuntu execution and the full Julia suite have not been rerun for this change.
At that step, the next fit-free foundation task was a saved-result workflow walkthrough,
including diagnostic warnings, uncertainty, reload and figure/report output;
this does not replace calibration or independent scientific review.

**Preceding update, 2026-09-23 JST:** [Byte-exact cache storage and serial cohort batches](docs/internal/mgmfrm-first-acceptance.md#39-元のcacheを完全復元できる圧縮保存と共通予定表の分割実行)
now preserve the existing worker and all original cache bytes. Standard-library
XZ/LZMA2 with a 256 MiB dictionary reduces the observed cache from 549.84 MB to
156.30 MB (71.57%); decompression matches its original SHA256. The restored
16,000-draw fit reproduces all 2.4 million quantity values, 144,000 conditional
residuals, diagnostics and precision results in 12 Julia checks. Four Python
tests cover corruption, original-copy preservation, unresolved slots, serial
execution, duplicate attempts and failure handling. The entire 274-ID summary
equals the previous summary, including the conditional error-rate screen.

The shared cohort imports the completed `joint-001` without adding a replication.
Only explicitly named unstarted IDs run, with an OS lock and per-ID claims.
After each successful driver, the controller verifies an exact archive before
removing its own uncompressed copy. Collection restores one cache at a time;
corrupt evidence, failures, incomplete attempts and absent IDs remain in the
full denominator. The old workflow and cache are retained. No new data or
fits were started: one of 274 slots is complete, and calibration remains open.

The single-cache reference is now about 42.83 GB for archives plus 5.58 GB for
quantity/residual exports, or 48.40 GB for the whole roster; it is not a size
bound. Free space increased during this work to about 339.95 GB; the user
subsequently explained that Dropbox files had been made online-only. The
earlier capacity shortage is not treated as current.
Only a verified 550 MB working copy was removed by this implementation. The
next execution can use explicit batches in the shared cohort, preserving the
unchanged model, seeds, controls, full roster and all attempts.

**Preceding update, 2026-09-23 JST:** The [first prospective SBC execution](docs/internal/mgmfrm-first-acceptance.md#38-実行設定から新規fit保存再読込み全予定表の集計をつなぐ)
now completes generation, a fresh AdvancedHMC fit, validated save/reload,
all 150 quantities and collection over the complete 274-ID roster. Only
`joint-001` was selected before generation; its four chains retain 16,000 draws.
The fixed diagnostic criteria pass: maximum rank R-hat 1.00128, minimum bulk ESS
3,559, minimum tail ESS 6,057, and no retained divergences or depth hits.
The 24 warmup divergences are retained separately. Nine conditional moment
means are within 0.80 MCSE of zero on this one fit; the old prior-002 concern
remains unresolved.

Python reconstruction checks 352,000 derived values and 144,000 conditional
residuals, plus all 450 quantiles and 900 boundary values. Focused runner tests
pass, including 1,088 Julia assertions on a historical saved fit. The primary
median/coverage classifications leave 1/2 of the 150 quantities unresolved on
this dataset; these quantities are dependent, not 150 new replications.
All 273 unstarted slots remain unresolved in each quantity's planned denominator.
The earlier eight datasets are not pooled with this cohort. This is a completed
execution path and one qualified fit, not calibration or protocol acceptance.

Measured driver time is 26.88 minutes, child-process peak RSS about 6.61 GiB,
and the fit cache is 524.37 MiB. A single-slot linear reference gives about
122.8 hours and 150.7 GB of caches for 274 slots, without a timing guarantee or
imposed cap. The measured destination had about 61.7 GB free. Continuing the
roster needs a concrete storage arrangement and split execution that preserve
IDs, settings and every attempt. No automatic full-roster launch, model/sampler
change, old-artifact deletion, full-CI run or new GitHub update occurred.

**Preceding update, 2026-09-23 JST:** The [prospective SBC setting](docs/internal/mgmfrm-first-acceptance.md#37-判定誤りを含む感度設計と保持数を結合した実行設定)
binds 274 independent dataset IDs, 150 quantities, 600 one-sided screens and
four chains with 4,000 retained draws each. The reference count now accounts
for unresolved probability at most 5% AND unconditional resolved-error
probability at most 0.1%, shifting both null thresholds and alternative power.
It gives 81.08%/81.37% lower power in the two normal controls under those
assumptions; neither bound is established for MGMFRM. Thus 274 is a concrete
conditional sensitivity setting, not certified MGMFRM power or acceptance.

The checker binds source hashes, controls, named quantities, seeds and rank-band
construction while keeping failed/absent attempts in the whole roster. The
Julia evaluation adapter now binds the declared retained length instead of a
4,000-draw constant; existing calls retain their previous settings. Old saved
4,000/16,000-draw fits provide a software replay, not new sampling. Focused
Python tests and 2,810 independent Decimal power checks pass. Cost references
from old fits are about 97 or 155 hours under two simple extrapolations, not a
timing guarantee or an imposed timeout. Next connect this setting to a worker
that completes generation, a fresh fit, saved-result checks and all-150-quantity
collection, and measure the selected longer AdvancedHMC setting. No new data
or fits, automatic large-batch launch, protocol promotion or default change.

**Preceding update, 2026-09-23 JST:** The [rank-boundary implementation and comparison](docs/internal/mgmfrm-first-acceptance.md#36-順位に基づく境界判定を実装し既存sbc集計へ接続する)
adds explicit order-statistic bands enlarged using quantile ESS. On the same
frozen controls, paired normal/exp-normal classifications agree within numeric
precision: at 16,000 draws both give 4.127% unresolved and 0.02063% resolved-wrong
90% coverage decisions. Treating correlated draws as iid substantially increases
errors, so rank ordering alone is insufficient. The candidate preserves the
exact iid marginal band but claims no finite-MCMC or familywise guarantee.

The existing full-roster SBC summary now accepts `classification_method="rank_band"`
explicitly; its default remains `value_mcse`. Missing IDs, rejected fits and all
150 quantities remain accounted for. Replaying the old eight MGMFRM fits gives
52 median and 36 coverage unresolved decisions; retaining prior-002's open
concern as unresolved gives 198 and 184. These are separate retrospective
artifacts, not changed old results or calibration acceptance. All 21 focused
Python test methods pass, 840,000 interval-mass comparisons agree within
2.22e-16, and the old classifier's 168,000 probabilities are unchanged.
Next bind method, band width, qualification, full attempt accounting, retained
samples and replication into one prospective joint-prior execution setting.
No new independent synthetic ensembles or actual MGMFRM fits were added.

**Preceding update, 2026-09-23 JST:** The [finite-MCMC classification controls](docs/internal/mgmfrm-first-acceptance.md#35-有限mcmcの確定判定を正解が分かる分布で検証する)
complete 1,000 chain ensembles for each of seven known-distribution scenarios,
with three fixed prefixes and the existing classifier. Exact reference-CDF
integration separates resolved errors from unresolved outcomes. At 4,000 iid
normal draws, the 2-MCSE rule gives 0.01754% wrong 90%-coverage decisions and
2.858% unresolved outcomes; neither rate establishes general error control.
Common wrong-target and missing-mode controls pass limited R-hat/ESS checks
while retaining large classification errors. More draws do not repair them.

The paired normal/lognormal control also exposes coordinate dependence:
quantile ESS agrees exactly, but the relative endpoint-MCSE rule leaves 4.03%
versus 52.14% coverage decisions unresolved at 16,000 draws. Next compare a
probability/rank-based boundary candidate on these known-answer controls,
retaining outcome errors and unresolved cases, before selecting actual
MGMFRM precision and replication budgets. No existing rule or old result was
changed. A floating-point representative-point bug in the new integration
helper was caught by separate interval arithmetic, repaired, and regression
tested. The final 630,000 mass comparisons agree within 1.67e-16. New helper
and existing SBC tests pass; no actual MGMFRM data or fits were added.

**Preceding update, 2026-09-23 JST:** The [quantile-precision and replication review](docs/internal/mgmfrm-first-acceptance.md#34-分位点の精度と独立データ反復数を一緒に設計する)
adds truth-blind quantile ESS and posterior boundary-mass diagnostics, using the
existing MCSE implementation. Fixed windows of the old eight fits show that
4,000 retained draws give mean boundary-mass proxies around 3.3%, with median
proxies up to 7% for loadings. Good whole-draw R-hat does not establish this
separate precision requirement. Projections to larger draw counts assume
stationary mixing and are not future unresolved-rate bounds.

A new power helper permits outcome-dependent unresolved status with a bounded
per-dataset probability and independent datasets, without a deterministic cap
on the realized count. Under the same two normal controls and correct resolved
classifications, unresolved-rate bounds of 0%, 2.5%, 5% and 10% give first
reference counts of 142, 189, 262 and 907 for both one-direction power bounds
at least 80%. The preceding 255 assumes a different, deterministic count cap.
These remain reference designs, not adopted MGMFRM cohorts. Next check the
finite-MCMC classification error itself against known posterior answers and
combine that evidence with precision and cost before fixing the actual roster.
All attempts must remain in the denominator. No new fits or datasets were added;
joint-prior calibration, prior-002's concern and independent acceptance remain
open. Focused helper tests and saved-draw/probability arithmetic checks pass.

**Preceding update, 2026-09-23 JST:** The [SBC sensitivity review](docs/internal/mgmfrm-first-acceptance.md#33-juliaの校正検証へ戻り検査自体の感度を確かめる)
connects the existing full-draw interval reviews to median and 90% coverage
screens, retaining all 150 quantities and a separately declared dataset roster.
Absent attempts, failed fits and ambiguous quantile decisions stay unresolved
on the full denominator. Analytic normal-model controls distinguish posterior
location error, deficient spread and ignoring the data; parameter-only coverage
misses the last error, while the observed-likelihood quantity detects it.

With 600 one-sided tests and all outcomes resolved, 142 is the first replication
count giving at least 80% power for both the declared 0.5-posterior-SD mean shift
and 30% posterior-SD deficit in the normal controls. This is not universal
MGMFRM power or a selected actual cohort size. With seven unresolved cases out
of 142, mean-shift power is 49.3% under independent fixed missing positions;
allowing outcome-dependent selection gives a worst-case lower bound of 34.1%.
If at most floor(5% of n) outcomes are unresolved per quantity, 255 is the first
reference count with both lower bounds above 80%, conditional on correct
resolved classifications. Neither count guarantees finite-MCMC calibration.
Precision and missing outcomes therefore belong in the design. Seven helper tests, separate probability
integration/counting and 3,600 saved-draw quantile comparisons pass. The replay
of the old eight panels is retrospective, not new calibration evidence; their
original denominator and unresolved concerns remain. Julia 1.12.5 passes all
134,678 ordinary assertions with `-O0`; the generalized shard also passes
30,947 assertions with default optimization. The latter count overlaps the
full suite. A stale metadata/refit expectation was repaired with acceptance
and rejection checks; its 31 assertions pass separately and in the full run.
Inactive test blocks now avoid unnecessary macro expansion. Full CI and new
GitHub publication remain separate; no new calibration fits were added.

**Preceding update, 2026-09-23 JST:** The [fresh 37-panel R1 coverage screen](docs/internal/mgmfrm-first-acceptance.md#32-新しい37パネルで負荷量区間の大きな過少被覆を点検する)
completes all 37 fits and 592,000 retained draws with the original explicit prior.
Every fit meets the numerical criteria, but the prospectively specified primary
screen detects I2 loading undercoverage. Its raw 90% interval covers in 26/37
panels (70.27%). Counting all three endpoint-sensitive cases as covered still
gives at most 27/37; the conservative Bonferroni-adjusted one-sided p-value is
0.01373 across the five loadings. The old eight panels are excluded. I1, which
stood out in the exploratory cohort, covers in 33/37 new panels. The new result
limits the original conditional-coverage claim without identifying a coding
error or selecting a different prior.

The sample size was fixed before generation to give 82.4% per-parameter power
at true coverage .70 with family alpha .05; power is only 9.2% at .85 and assumes
resolved outcomes. No flag is not fine-calibration acceptance. Secondary D1
centered-person coverage averages 85.57% (descriptive t36 band 83.90–87.23%),
using 37 panel means rather than 1,850 independent-person trials. The new helper
retains unresolved outcomes in the full denominator and exact interval envelopes.
Six unit-test methods, a 37-failure scorer fixture, 263 input/target checks,
20 binding/density checks per fit and separate arithmetic verification pass.
All attempts, data and source snapshots are preserved; no retries or extensions.
Joint-prior SBC remains a separate question with its original denominator eight.
Scientific acceptance, prior selection, the full package CI and new GitHub
publication remain uncompleted.

**Preceding sensitivity study, 2026-09-23 JST:** The [loading-prior sensitivity follow-up](docs/internal/mgmfrm-first-acceptance.md#31-同じ8パネルで負荷量事前への依存を調べる)
completes eight additional fits on all eight existing R1 panels, with no new
datasets, retry or draw extension. All meet the unchanged numerical criteria.
Broadening the common log-loading prior SD from 0.5 to 1 changes centered D1
person RMSE only slightly: 0.51535 to 0.51203, paired difference -0.00332,
between-panel MCSE 0.00236, descriptive t7 band [-0.00890, 0.00226]. I1/I2
upward errors decrease, person intervals widen, and D1 90% coverage rises from
85.75% to 89.00%. I2 loading coverage nevertheless falls from 7/8 to 6/8.
The result demonstrates prior dependence, not uniform improvement or adoption
of the broader prior. All five loading priors change; D2 is not an untreated
control, and there are no R0 refits to identify an interaction.

This follow-up was chosen after inspecting the same panels. Its descriptive
bands do not account for that selection; subsequent calibration needs separate
new panels and declared precision. The explicit-prior prediction helper passes
60 checks on Julia 1.12.5 and 1.10.8. Prior predictions, 273 saved-draw quantities,
conditional moments and paired summaries have separate arithmetic checks.
Zero observed between-panel variance no longer produces a zero-width t band.
Original artifacts and unresolved claims remain preserved. No default prior,
scientific-acceptance flag, full CI or new GitHub publication changes.

**Preceding recovery cohort, 2026-09-23 JST:** The [paired R0/R1 recovery cohort](docs/internal/mgmfrm-first-acceptance.md#30-r0r1の人物回復を8組の反復で調べる)
completes eight independent pairs and 16 fits, all meeting the declared numerical
criteria. Weakening D1 loadings raises mean centered-person panel RMSE from
0.31256 to 0.51535: paired difference 0.20279, replication MCSE 0.01477 and an
approximate descriptive t7 interval [0.16787, 0.23770]. D2 changes are small.
D1 90% person coverage is 87.25%/85.75%; the two D1 loadings average 75% in both
conditions, with substantial replication uncertainty. This is a measured
fixed-condition contrast, not calibration acceptance. The loadings move farther
from the fixed prior's center as they weaken, so the contrast does not isolate
information loss from prior dependence. Focus next on that dependence and
replicated interval coverage. Primary-difference MCMC MCSE is only 0.000265;
more draws for the same fits do not address the dominant between-panel variation.
Fourteen pre-MCMC build-path failures are preserved and explicitly repaired using
individual empty build directories. No completed fit or generated panel is
replaced. The 273-quantity helper, all-attempt summaries, Python reconstruction,
figure and source archive are complete. The final helper's 28 checks pass on
Julia 1.12.5 and 1.10.8; ordinary CI and new GitHub publication remain unperformed.

The [prior-002 follow-up](docs/internal/mgmfrm-first-acceptance.md#29-prior-002の位置分散を別backendと精度追試で照合する)
preserves the original location-moment gap and adds two same-data CmdStan fits.
The first, with 4,000 retained draws, misses the fixed R-hat criterion. A
separately declared precision follow-up with 16,000 draws passes all fit and
conditional-moment diagnostics. Its primary E[z²−1] estimate is 0.000901 with
MCSE 0.028055; the approximate reference band includes zero and excludes the
old point estimate −0.110720. Saved-draw and conditionally integrated person-mean
SDs are 0.125766 and 0.125681. The downward departure is not detected again in
this qualified follow-up. The original cause remains unidentified: backend,
coordinates and random seed change together. Targeted checks of the original
transform, actual gradient wrapper, Hessian and saved density pass at 25 points.
No original draws, warning, prior, default or calibration denominator is changed.
The subsequent paired recovery cohort retains these limitations.

The [analytic location review](docs/internal/mgmfrm-first-acceptance.md#28-絶対位置の条件付き分布を解析し標本の整合性も確かめる)
derives the exact normal conditional for the finite-panel person mean under the
current independent normal raw priors. Applied to the eight saved datasets,
E[V] accounts for 98.15–99.96% of the conditional-integration estimate of its
posterior variance. This is uncertainty along a likelihood-invariant location
direction, not a causal attribution of information to the prior. More ratings
do not directly remove it at fixed centered persons, relative items and loadings.
Absolute location, relative recovery and prediction now have separate claims.

The review also detects an unresolved computational concern: prior-002, D2 has
E[z²−1] estimated as −0.11072 (MCSE 0.02789), despite ordinary diagnostics passing.
Paired second-moment differences and a separate batch-mean MCSE sensitivity
check retain a roughly four-MCSE gap. The case was selected after inspecting
the results; this is not a calibrated rejection or proof of sampler bias.
The subsequent follow-up above narrows the computational concern without
identifying its cause. Section 28 added no fits; Section 29 adds two fits and no
datasets. There are now eleven fits for the same eight calibration datasets.

The [tail-case follow-up](docs/internal/mgmfrm-first-acceptance.md#27-ゼロ件だった裾を別backendと条件付き積分で照合する)
adds one same-data CmdStan fit for the I3 relative location identified in the
eight-dataset interval review. All expanded diagnostics pass. The selected mean
and four interval endpoints agree under the numerical comparison rule fixed
before the new fit. Both backends have zero retained draws below the generating
truth; conditional integration of item difficulty estimates a small positive
probability, 0.03050% and 0.02676%. Relative MCSE is still 20.3% and 17.7%, with
about 70% of each estimate supplied by its largest 1% of conditional values.
This narrows a computational concern without establishing precise tail mass or
repeated-dataset calibration. The original eight fits and their denominator are
unchanged; the follow-up adds no independent calibration dataset.

The [saved-draw interval review](docs/internal/mgmfrm-first-acceptance.md#26-保存した全標本で区間位置数値精度を直接点検する)
checks 150 quantities at 90% and 95% using the original 32,000 draws. Even with
endpoint MCSE at most 3.10% of width, fixed-half comparisons change 28 coverage
decisions. Both this sensitivity and the original zero-count event are retained.

Finite-panel person-mean posterior SDs average 0.137/0.134, close to their prior
SD of 0.141. Better sampling coordinates have not established strong data-only
identification of absolute location. Separate absolute and relative quantities,
prior dependence, numerical precision and repeated-dataset calibration. An
analytic control also shows that 225 replications can have poor power against
roughly two-percentage-point undercoverage; MCSE and detection power are distinct.
The earlier four-draw ranks and prior-only negative control remain unchanged.

This builds on the [prior-preserving coordinate comparison](docs/internal/mgmfrm-first-acceptance.md#22-共同事前を保つ位置座標で混合を比較する),
[public fit/cache integration](docs/internal/mgmfrm-first-acceptance.md#23-位置座標を公開fitと自動cacheへ接続する)
and [one-panel R0 heldout evaluation](docs/internal/mgmfrm-first-acceptance.md#24-標準条件r0の未使用評定を5分割で予測する).
Both R0/R1 coordinate fits and all five R0 heldout refits qualify. The original
R0 warning, 83 inconclusive backend statistics, existing defaults, joint prior
and canonical saved coordinates remain intact. Initial fixed-condition recovery
is now measured; interval acceptance, repeated-dataset prediction, posterior prior-sensitivity and
independent scientific review remain open. The [application portfolio](docs/internal/application-portfolio.md)
keeps Uchihara, EVA and Chopin as secondary uses. Following the user's current
priority, empirical analysis and dataset-specific adapters are deferred while
the core model's supported inferential scope is established. The common refit
metadata repair is complete; it is not statistical acceptance.

Earlier evidence and preparation through 2026-09-21 are recorded below; their
historical next-step statements are superseded by the current update and active
work queue.

The subsequent [critical self-review](docs/internal/strategic-review-2026-09-21.md)
finds that recent application engineering has outpaced resolution of the core
acceptance claim. The [first core acceptance candidate](docs/internal/mgmfrm-first-acceptance.md)
now specifies one identity-correlation, two-dimensional MGMFRM with the existing
raw `implementation_reference` prior, 50 persons, 5 items, 5 raters and 4
categories. Its six claim-to-evidence rows separate equations, computation,
calibration, conditional prediction, prior sensitivity and the user workflow.
The independent stdlib DGP and finite pilot invocation are now implemented.
Four generated conditions pass 154 Julia checks; Python verifies generation,
comparison/failure decisions and owned-process resource stops. The original
[maximum-two-fit computation pilot](results/workflows/20260921-core-generator-01/pilot-01/contract.json)
retains its qualified Julia result and CmdStan pre-MCMC Make-setting failure.
A separately bounded [CmdStan follow-up](results/workflows/20260921-core-cmdstan-followup-01/pilot/contract.json)
now passes whole-fit diagnostics and all 67 primary precision decisions, reusing
the original Julia fit. Both backends retain 4,000 draws. Of 303 statistics from
the primary quantities, 220 meet the numerical allowance, 83 remain inconclusive
and none meet the discrepancy rule; all 10 ability-contrast statistics meet the
allowance. Per-fit precision does not guarantee the stricter simultaneous
comparison: retained Julia MCSE alone exceeds the comparison allowance for
three item means. The subsequent
[precision/resource design](docs/internal/mgmfrm-first-acceptance.md#9-比較精度と長い結果の処理を具体化する)
proposes 40,000 retained draws per backend, conditional on unchanged ESS per draw,
with adjusted MCSE consuming at most half the allowance for all 313 statistics.
The 151-minute whole-workflow linear reference is not a runtime prediction.
Batched focal prediction now reproduces all saved summaries/MCSE and handles
40,000 repeated rows in a sampler-free capacity check. Default full-fit caches
preserve the fitted data and diagnostics while omitting artifact duplication,
but reduce stored bytes by only 5.9%; a tenfold storage reference still exceeds
the existing 2 GiB shared limit. No new MCMC or resource-limit increase follows.
The [subsequent strategic/local reassessment](docs/internal/strategic-review-2026-09-21.md#再点検の結論)
defers that long pair. The subsequent
[current-candidate conformance check](docs/internal/mgmfrm-first-acceptance.md#10-現候補への数値検証の対応と不足分の照合)
maps the existing evidence and fills the 128-coordinate gap: independent analytic
Python gradients, Julia and current native Stan agree at seven observed-data
points and two unused-category points; 35,000 unaveraged Stan log probabilities
also agree. No MCMC is involved. The
[scientific design proposal](docs/internal/mgmfrm-first-acceptance.md#11-科学的評価の具体案レビュー用未凍結)
specifies two recovery conditions with fresh N(0,I) persons, 138 proposed SBC
quantities, ID-sensitive predictive losses and fixed-ID CV/prior/backend subsets.
The 100/225-replicate options require 444/819 fits and remain unselected.
The subsequent [evaluation preparation](docs/internal/mgmfrm-first-acceptance.md#12-人物生成id付き評価sbc順位案の準備)
implements R0/R1 person generation, ID-aligned row scores, 138 quantities and
fixed terminal selection from four chains. Existing tie and missing-rank logic
is reused. A finite PCM negative control exposes the 100-replicate screen's
limited sensitivity; it is not MGMFRM power evidence. Single-observed-category
fits remain rejected by the package boundary. The [fit/attempt binding](docs/internal/mgmfrm-first-acceptance.md#13-保存fit診断予定idと評価処理を結合する)
now verifies full cache hashes and training targets, recomputes diagnostics, and
connects 59 primary plus 100 person recovery rows to all planned IDs. Fold
assembly rejects full-data leakage and incomplete folds. Actual joint-prior
SBC/fold fits are still absent; their complete-ledger checks use explicit
arithmetic fixtures. CV-loss MCSE, paired-condition/person summaries, prior
prediction, fresh seeds, independent review and resource bounds remain open. Pilot-scaled costs are references, not forecasts or bounds. The deterministic pilot panel has SDs about 0.107 and empirical
cross-dimension correlation 0.547; it is not a draw from the declared N(0,I)
population. A finite counterexample also shows that all 69 focal quantities can
miss a P3/P4 ability-ID swap despite changed row probabilities. Neither finding
invalidates the preserved pilot; both limit its claims. The 83 inconclusive
statistics remain inconclusive. A future long pair needs an explicit claim
reason, executable fixed-length contract and justified resources; it is not a
prerequisite for designing the other evaluations. Do not repeat CmdStan alone,
change margins after results or sample until passing.
The [follow-up verification](results/workflows/20260921-core-cmdstan-followup-01/verification.json)
and [comparison figure](results/workflows/20260921-core-cmdstan-followup-01/comparison-precision.png)
separate this partial numerical agreement from recovery/SBC/CV and scientific
acceptance, which remain uncompleted.
Application-specific step-prior selection and an A0 pilot are not prerequisites.
The review also corrects the description of A0's fixed person SD: with unit loadings/logits it is a population restriction,
not merely scale identification. Marginal prediction scores alone cannot
validate recording dependence. No target, prior value or saved sample changes;
this is implementer self-review, not independent scientific acceptance.

The earlier fixed-coefficient cost evidence remains the 2026-09-18
[bounded likelihood replay](docs/internal/fixed-coefficient-validation-protocol.md#bounded-likelihood-replay-2026-09-18)
at `73895e7` (recorded in `5cc7ad8`). Observed one-chain fit times fell from
102.02 to 77.60 seconds with diagonal metric and from 784.50 to 586.38 seconds
with dense metric, preserving saved bytes and transition work. These are
single-condition cost observations, not statistical evaluation or a general
speed guarantee; cumulative allocation increased. The 2026-09-21 follow-through
adds fixed-coefficient `posterior_mcse(fit)` support and the generalized
correlation target's [numerical Julia/Stan counterpart](docs/internal/normalized-prior-backend-comparison.md#generalized-2d-correlation-numerical-target-2026-09-21).
It adds no recovery/SBC replications or new
backend-comparison pilot. See the [completed precision handoff](#decision-handoff-and-progress-accounting).

The active model-workflow handoff now connects correlated MGMFRM prior and
conditional posterior prediction, reports, exported tables and figures with
replay from saved results. The core candidate packet above now links the proposed
claim to its validation design. Independent DGP and qualified Julia/CmdStan
pilots are now verified; full numerical agreement, the final replication
budget and independent review remain open. The application
packet below informs this work but does not complete it.
The [application-informed acceptance packet](docs/internal/applied-mgmfrm-acceptance.md)
now starts from interpretable speaker profiles, criterion-specific rater
contrasts and predictive consequences. A read-only reinspection of the local
Uchihara workbook identifies sparse word coverage and repeated-recording
dependence that the application model must address. This informs the scientific
design without replacing the Julia foundation objective or selecting a new default.
The user's subsequent 2026-09-21 clarification authorizes synthetic data for
this application example. The [paired-rating generator](examples/synthetic_paired_ratings.jl)
now creates artificial IDs, assignments and responses, with separate known
truth for person and recording correlation. It does not read the workbook.
The application path can therefore proceed without empirical reconciliation.
The [A0 reference implementation](docs/internal/paired-rating-reference.md) now
matches the generating equation, with explicit priors, noncentered effects,
normalized Julia/Stan densities, analytic/autodiff gradient checks and bounded
engineering samples on both backends. Saved records reproduce intervals,
MCSE and warnings. The private application workflow now also samples the full
joint prior and predicts existing or unknown recordings, preserving shared
bivariate recording effects, recorded sampling warnings and a separate numerical
integration MCSE. A saved-draw focal precision report now adds draw-level
marginal probabilities, MCMC MCSE and explicit numerical decisions; see the
[focal precision and resource checks](docs/internal/paired-rating-precision.md).
Scientific prior/identification review and a frozen pilot contract remain. All retained draws
in the short check hit its depth-4 cap and parameter diagnostics report
insufficient draws; this is not a recovery/SBC evaluation or accepted inference.
The [initial prior check](docs/internal/paired-rating-reference.md)
places about 61--62% of ratings at the two category endpoints on average,
versus 23--32% in the synthetic example. The subsequent
[fixed mechanism comparison](docs/internal/paired-rating-prior-review.md)
separates nuisance scale, step spread and step order on the same 256 prior draws.
Halving nuisance SD reduces endpoint probability by about 8 percentage points;
sorting the same step values reduces it by about 21--22 points and gives all
nine categories a unique modal interval, versus about 3.6--3.8 on average under
the original prior. These are response-mechanism findings, not a selected prior
or proof of application suitability. The next scientific decision is what role
the middle rating categories should have. The independent engineering
deliverable is now verified: 4,354 focal quantities per saved result preserve
all short-run warnings, with none qualifying; the resource guard passed 18
bounded Python tests after a documented macOS zombie-group cleanup repair.
The default sandbox refuses process observation and correctly prevents launch.
For the secondary application, the remaining decisions concern the scientific
prior and bounded pilot contract, including compilation, shared budgets and a
permitted monitoring environment; they do not displace the primary deliverable.
No new sampler run or automatic prior/default change follows from these checks.
The bounded early-dense-adaptation observation
remains a separate cost investigation with a stopping rule, not a prerequisite
for this model-workflow work.
Fresh recovery/SBC evaluation, diagnostic-qualified C2 backend agreement,
independent review and the unfamiliar-reader walkthrough remain open.
Julia remains primary, CmdStan remains its maintained counterpart, and
Uchihara (2022) remains a secondary application. The final migration away from
development-status API names remains a model-specific release requirement;
compatibility defaults and historical results retain their meanings.
This is the **single current work order**, not a public feature catalogue or a
completion percentage. Start with the decision below;
do not reconstruct priorities from historical checkboxes. The
[ordered deliverables](#immediate-work-and-stop-conditions) are the work queue;
the source reviews below are their evidence, not additional milestones.

</details>

## Active Decision Roadmap

The [current decisions](#current-decisions) control scheduling. The contracts and
dated evidence below retain their scope; historical next-step wording is not a
second execution queue.

**Primary objective: establish a mathematically correct, reliable and reusable
Julia foundation for Bayesian MGMFRM, preserving the existing MFRM/GMFRM
behavior and making supported models usable from fitting through diagnostics,
visualization and saved results. Maintain CmdStan estimation of the same models
as a continuing computational check. Uchihara (2022) is a secondary application
that exercises this foundation.**

The user's 2026-09-11 clarification supersedes the prior case-first
sequence. Establish the Julia model and numerical contracts -> strengthen the
existing estimation/result path with CmdStan checks -> validate the declared
domain and user workflow -> apply the supported foundation to concrete studies.
The [ordered deliverables](#immediate-work-and-stop-conditions) control this work.
Completion of the Uchihara analysis, its data reconciliation or its specialized
extensions is not a prerequisite or the definition of completion for the Julia
foundation. Applications can reveal a reusable defect or requirement, but their
data layout and desired findings must not determine core defaults or architecture.

The user's 2026-09-15 scope clarification sets the long-term direction:
compensatory and non-compensatory response models, between-item and within-item
structures, estimated latent correlations, Q identification and structure
estimation, and configurable random effects. Treat these as distinct model
choices, with validated combinations added incrementally. The
[extension sequence](#long-term-extension-sequence) specifies their deliverables
and evidence requirements; it is not a claim that those options are available
today or that every combination belongs in the next release.
The subsequent Uchihara workflow discussion sharpens the reusable
[specification and prediction contract](#shared-specification-and-prediction-contract).
Implement each relevant part with its model extension; the application and a
complete future specification language are not prerequisites for the
[implementation handoffs](#next-implementation-handoffs).

The user's 2026-09-07 clarification corrects the previous work order's emphasis
on the MFRM anchor study. MFRM is a reusable foundation and comparison branch,
not the project's final deliverable. Completing its entire anchor panel is not
a blanket prerequisite for MGMFRM development. The existing fixed-Q MGMFRM
implementation is the starting point, not a permanent restriction to independent
dimensions or one dataset's two-trait structure. Prioritize model correctness
and the reusable fixed-coefficient/correlated-dimension extensions on their own
measurement and validation merits. The source and exchangeable-prior scientific
models retain their distinct research roles and identities; no complete model
catalogue or full source-reproduction study is a prerequisite for fixing the core.

The research-first sequencing decision defers M0's historical runtime
attribution and controlled benchmarking; it does not accept M0 or waive the
release criterion. Those performance tasks are no longer prerequisites for
M2. Fresh evaluation still requires a target-specific independently reviewed M1 and the
[research execution prerequisites](#research-execution-prerequisites).
The independent and two-dimensional correlated fixed-coefficient workflows
now connect through the experimental API, including fitting, manual caches,
diagnostics and figures. Free correlation is requested explicitly with
`Experimental.correlated(spec)`; it is limited to between-item Q and does not
alter the ordinary independent specification. Reports default to a public view
for correlated results, while scientific warnings and prior/coordinate meanings
remain visible. The [implementation record](docs/internal/normalized-prior-backend-comparison.md#experimental-correlated-mfrm-api-2026-09-17)
separates operability from statistical acceptance. Prior-predictive inspection
now connects to optional saved-fit reports and figures. The
[prior/identification review](docs/internal/fixed-coefficient-prior-identification.md)
characterizes the current model's rater-label dependence. A distinct private
exchangeable-rater reference now passes normalized density, derivative,
relabelling and Julia/CmdStan checks. A private prior-predictive comparison
records explicit scale matching and reuses existing figures. Private sampling,
diagnostics and save/reload retain the distinct prior identity, now carried into
posterior prediction, reports and figures. The explicit opt-in
`Experimental.ExchangeablePrior(rater_kernel_sd=...)` now connects those paths
to public experimental fitting and manual fit caches, with a distinct result
type and artifact identity. This does not choose a scientific default.
Recovery, coverage, prior sensitivity and diagnostic-qualified backend comparison require their
reviewed protocol; the generalized correlation candidate keeps its own identity.
LD1b execution, soft/group anchors, and new-facet prediction remain separate
programs unless a reviewed core-model requirement makes them necessary.

The user's 2026-09-11 UX review adds a product completion requirement:
ordinary users must be able to fit, diagnose, interpret, visualize, and save
results without manually reshaping MCMC draws or learning research-management
APIs. README, public manuals and help must explain current behavior consistently
without requiring knowledge of development stages or study-execution approvals.
The [UX delivery contract](#user-workflow-api-naming-and-visualization), including
[documentation/help acceptance](#public-documentation-and-help-acceptance),
joins the existing work queue. Its acceptance criteria remain distinct from
the dated implementation checks below and from independent scientific review.

The following M0–M3 rows retain the earlier stage definitions and dated status.
Use [MS1–MS6](#completion-milestones) for current completion decisions and work
order. Historical release holds remain applicable to the later release branch;
they do not reorder the current mathematical, statistical and API milestones.

| Milestone | Status | Responsible role and concrete exit |
| --- | --- | --- |
| M0 — Package baseline | Implementation, placement/load review, and all 12 lane baselines recorded; runtime acceptance open, further performance work deferred | Maintainer: retain the unexplained 23.4% trigger and release hold; revisit after research progress or evidence of an actual execution blocker. Correctness, integrity, and resource-safety defects are not deferred |
| M1 — Julia model, implementation and validation contract | Experimental fixed-Q, fixed-coefficient and explicit 2D correlated workflows have numerical checks and saved-result consumers. Explicit normalized source/exchangeable priors now connect to the public independent MGMFRM workflow; candidate C remains a computational scale choice. The normalized location transform now connects to explicit experimental AdvancedHMC fitting, sharing implementation with the research adapter | Analyst/maintainer: preserve the checked target, saved-coordinate and cache contracts; retain identification limits and obtain independent review of the target-specific scientific prior and protocol. Application preparation is not a dependency |
| M2 — Core estimation evidence | The raw target has eight joint-prior fits, paired recovery evidence and a 37-panel fixed-condition screen with I2 undercoverage; its later 274-ID cohort remains 4 completed / 1 failed / 269 unstarted. Separate normalized candidate C has two independent datasets with diagnostic-qualified transformed fits. Neither record establishes broad calibration acceptance | Analyst: prepare claim-specific recovery/calibration, prior-sensitivity and prediction decisions, comparing all three margins. Keep target identities, failure denominators and diagnostic-qualified backend comparisons separate; run only a justified bounded roster. The application and computational diagnostic passes do not close M2 |
| M3 — Usable package and supported-domain review | Public result/report/figure and save/reload paths have dated checks. Normalized transformed fitting now has public experimental fit/save/reload/report integration checks. Current integration verification, unfamiliar-reader and scientific review, and final API migration remain pending | Maintainer and independent reviewer: verify the complete selected workflow on a reviewable candidate, reproduce its numerical/scientific claims and decide supported/narrowed/rejected/inconclusive scope. Historical checks are not current CI; application reports are secondary outputs |

Roles above do not imply that a person has accepted an assignment. In
particular, an independent reviewer is not yet assigned. Implementation by
the same author or another local receipt cannot satisfy that review.

### Core-model boundaries and next deliverable

Reuse the existing [model-family contract](src/model_family_contract.jl),
[experimental surface contract](src/experimental.jl),
[validation protocol](src/mgmfrm_validation_protocol.jl), and
[research design detail](docs/src/mgmfrm-research-roadmap.md). They already
separate the implemented branch from broader source-model targets. The two
scientific models need explicit identities and prior targets, not two copied
fitting engines, another roadmap, or a new generic model registry.

| Core concern | Current implementation and next decision |
| --- | --- |
| Multidimensional generalized likelihood | The experimental fit has at least two ability dimensions, fixed-Q positive item-dimension discriminations, rater severity and positive consistency, and item-owned partial-credit steps. Review the existing Julia/Stan equation, transforms, priors, and parameter/report mappings together; MFRM or scalar GMFRM checks do not validate this joint model |
| Fixed-coefficient multidimensional MFRM | Canonical specifications connect through `Experimental.fit` to Julia/CmdStan, dedicated results, manual v2 caches and full/public reports with named-dimension figures. Small 2D/3D fits and numerical checks establish operability, not recovery or coverage. A generic fit-to-report example exercises both backends. The separate 2D correlated-ability model now has an explicit experimental specification, both fitting routes, manual caches and public reports/figures; statistical validation remains pending. Unit logits, fixed loadings/consistencies and the prior-anchored location convention remain explicit; this branch does not select the generalized source/exchangeable prior |
| Identification and intended scope | The unwrapped generalized fit fixes latent correlation to identity; both fixed-coefficient MFRM and estimated-loading MGMFRM can explicitly estimate 2D between-item correlation, with different prior/scale contracts and workflow coverage. They reject anchors and fitted DFF; the fitted facets are person, item, and rater. Establish the implemented domain and the contracts for fixed-coefficient and correlated-dimension extensions independently of any application. Fixed within-item/mixed Q structures remain warning-bearing; criterion-specific raters, recording effects, arbitrary facets and generalized anchors require separate scope decisions |
| Bayesian practical decisions | Assess dimension-specific ability, discrimination, severity/consistency, category steps, and predictive uncertainty according to the user's intended use. Revisit the existing draft's secondary-only person-ability priority for individual decisions. Distinguish posterior uncertainty, prior sensitivity, model adequacy, and practical loss; neither a converged fit nor a finite interval alone establishes practical acceptability |
| Stress and scientific evidence | Reuse the existing Q/design validation and [response-pattern stress plan](src/mgmfrm_response_stress.jl), including all-minimum raters. Separate well-specified recovery from deterministic response contamination; an all-1 pattern does not itself identify its cause or justify automatic exclusion/downweighting. Evaluate joint severity/consistency uncertainty and predictions under sparse overlap and Q misspecification, not only warning detection |

The initial source-equation-to-implementation gap review is recorded below,
using existing sampler-free contract/identification tests before changing
fitting code. Any change must address an observed gap in a named
model block or user decision. The existing narrow fixed-Q/identity-correlation
branch is a reusable numerical baseline; the first substantive validation target
must follow the accepted package model and intended domain, with its restrictions
explicit. The Uchihara design does not define that domain. The
generalized free-correlation density/gradient candidate and historical pilots
are useful assets. They are distinct from the connected fixed-coefficient
correlation API and do not establish a promoted generalized correlation API or
fresh independent evaluation. This review does not change model code, protocol
constants, scientific acceptance, or execution permissions.

### First Julia core verification slice

The 2026-09-11 implementation passes traced the existing fixed-Q target,
corrected a numerical constraint failure, and hardened input conversion and
cache publication without changing the statistical model.

| Block | Implementation trace and finding |
| --- | --- |
| Raw prior and measure | `_SourceFixturePrior`, `_source_fixture_prior_sd` and `_source_fixture_logprior` in [bayesian_fit.jl](src/bayesian_fit.jl) apply independent normal priors to the free raw coordinates. Positive transforms add no Jacobian for this declared target; source/exchangeable prior decisions remain separate |
| Response equation and transforms | `_mgmfrm_source_constrained_params_from_unconstrained` and `_mgmfrm_source_linear_predictors!` in [facet_workflow.jl](src/facet_workflow.jl) reconstruct constrained parameters and use the additive ability score, item steps and `1.7` rater multiplier. The [Stan model](src/stan/mgmfrm.stan) and its [data adapter](src/cmdstan_fit.jl) retain the same raw layout and prior SD mapping |
| Product-one constraint — corrected | Finite factors `exp.([400, 400, -400, -400, 0])` have product approximately one, but ordinary intermediate multiplication overflowed and caused rejection. The shared positive-product calculation now uses log space in both validation and diagnostic rows, covering GMFRM item discriminations and MGMFRM rater consistencies. Product-scale tolerance stays `1e-8`; invalid factors and non-unit products remain failures |
| Prior and initial-value inputs — corrected | `MFRMPrior` and `_SourceFixturePrior` (also used by `Experimental.GeneralizedPrior`) now validate the stored `Float64` scales. Finite positive `BigFloat` inputs that convert to infinity or zero are rejected. Scalar `initial_params` methods likewise reject conversion overflow, including the research-only correlation coordinate; vector initializers already checked after conversion |
| Sampler controls and initialization — corrected | `_check_fit_controls` and `_check_nuts_controls` now share converted numeric bounds across fitting and cache-key creation. This covers stable Julia/Turing, GMFRM/MGMFRM AdvancedHMC, the research-only correlation sampler, and both CmdStan adapters. CmdStan retains its fixed divergence threshold, and stable MFRM rejects a non-finite initial log posterior before runtime discovery/compilation |
| Sampling and results — focused integration checked | `_run_generalized_candidate_advancedhmc` uses the target/gradient adapter; `_mgmfrm_guarded_local_fit_diagnostic_surface` reconstructs direct draws and constraint summaries; `_mgmfrm_fit_from_sampler_diagnostics` stores the common result. Tiny Julia fits check retained chain/iteration labels, sampler-stat alignment, recomputed log densities, and raw/direct summary names and means. Malformed chain labels/iterations are rejected by the existing layout check; this is not a full sampler-failure or statistical acceptance study |
| Rejected transitions and retained-output boundary — corrected | Random-walk proposals with non-finite coordinates or log density are rejected and counted separately from NUTS divergences. `_store_sampler_draw!` checks parameter count and converted finite draws/log densities before Julia NUTS output can become a fit result, identifying the chain and retained iteration on failure. The shared path covers stable AdvancedHMC/Turing, GMFRM/MGMFRM AdvancedHMC and the research-only correlation sampler; valid states retained after divergent transitions remain admissible |
| Cache publication — corrected | Shared `save_fit_cache` serializes and closes a same-directory temporary file before publishing it. Serialization/replacement failures preserve an existing result; exclusive publication also preserves a competing destination. `cached_fit` now passes `refresh` through as the overwrite policy. `load_fit_cache` retains the existing schema, key and artifact-hash checks; the artifact hash does not certify every field of the fitted object |

The [regression test](test/generalized_prior.jl) checks overflow/underflow orderings
against high-precision multiplication, finite gradients, expected probabilities,
diagnostic values and rejection of invalid inputs. On Julia 1.12.5,
`test/generalized_prior.jl` and `test/generalized_guard_contract.jl` passed all
409 assertions, including 108 new regression assertions. The existing
GMFRM/MGMFRM Stan-reference checks passed 44 assertions using the retained
fixtures and test helper; their source files and reference values were unchanged.
These are deterministic
implementation checks, not new CmdStan execution, posterior comparisons or
recovery evidence. No new prior, model option or default was adopted.
The follow-up [input and cache regression tests](test/fitting_boundaries.jl)
passed 256 assertions on Julia 1.12.5/macOS: 232 prior/initial-value checks and
24 publication/reload checks. Fault injection reproduced corruption of an
existing cache before the fix; the corrected path preserves its exact bytes,
rejects competing destinations, cleans temporary files, and replaces symbolic
links without changing their targets. These tests use deterministic fit objects,
not estimated posterior draws. The existing 409 generalized assertions and
44 retained Stan-reference assertions also passed after the input correction.
The existing `cached_fit` create/reuse/key-mismatch/refresh integration checks
passed eight assertions using two tiny random-walk fits (two chains, three
retained draws and two warmup iterations per chain per fit). This checks the
ordinary artifact/save/load connection, not posterior accuracy or convergence.
Native rename is used to avoid Julia 1.10's copy/remove fallback; minimum-version
runtime verification remains with the existing Julia 1.10.8 CI job and was not
run locally. This does not establish crash/power-loss durability.

The 2026-09-12 pass reproduced accepted `step_size` inputs becoming infinity
or zero, returning stationary random-walk draws with acceptance rates of zero
or one. These requests now fail at the numeric input boundary. The same fix
covers target acceptances rounding to zero/one, energy thresholds overflowing
or underflowing, and jitter overflowing; tiny negative jitter remains invalid
even when it rounds to negative zero. Valid equivalent numeric types retain
the same cache keys. The explicit-chain-initialization policy in the research
candidate still requires the original jitter input to be exactly zero.

The [boundary tests](test/fitting_boundaries.jl) add 700 control/initialization
assertions and 82 integration assertions on Julia 1.12.5/macOS. The final
passing integration uses five tiny fits: stable MFRM with random walk,
AdvancedHMC and Turing, plus GMFRM/MGMFRM with AdvancedHMC, each with two chains,
four retained draws and two warmup iterations per chain. This tests software
connections and metadata, not posterior accuracy, convergence or recovery.
The existing CmdStan contract/CSV checks (78 assertions), generalized guards
(58), and retained Stan density/gradient references (44) also pass; no new
CmdStan fit was launched. Full-suite, minimum-version and other-platform runs
remain unperformed for this change.

The next 2026-09-12 pass reproduced a finite, very large random-walk step
producing non-finite proposals while every sampler row claimed no numerical
error. The corrected rows retain the last valid state, mark the event and
expose `n_nonfinite_proposals` through `sampler_diagnostics` and `diagnostics`.
This is a retained-iteration count, not warmup coverage or a diagnosis of the
cause. NUTS divergence counts are unchanged. Older random-walk fits without
this telemetry report `missing`; cache reload does not invent historical data.
One acceptance uniform is still consumed per iteration, including rejection.

The focused [transition tests](test/fitting_boundaries.jl) pass 59 assertions:
24 for overflow rejection, ordinary rejection, warning priority, random
stream consumption, incomplete telemetry and current/legacy cache reload; 35 for valid divergent
states, malformed parameter counts, non-finite output and chain/draw context.
The latter inject invalid retained values into the shared output writer;
they do not demonstrate that AdvancedHMC or Turing emitted such values.
The existing tiny integration tests exercise the writer through actual Julia
sampling. No model, prior or default sampler setting changed.

The following 2026-09-12 pass reproduced explicit `InterruptException`s being
converted to `ArgumentError` during gradient initialization, to `CmdStanError`
during JSON output, and to a captured report-section error. The fitting and
CmdStan adapters now share the existing stress-runner policy: interruption,
out-of-memory and stack-overflow exceptions are rethrown unchanged. The report
capture path follows the same policy; ordinary section errors remain capturable.

Unexpected exceptions from random walk, AdvancedHMC and Turing sampling now
carry backend, chain and sampling-phase context with a `CapturedException`
retaining the original exception and backtrace. The shared AdvancedHMC path
covers stable and generalized fits and the research correlation sampler uses
the same wrapper. CmdStan initialization-file, command and parser errors gain
chain/phase context; existing `CmdStanError.stage` and `.reason` stay intact.
Existing CmdStan typed errors still store a diagnostic string rather than a
structured original cause. Preflight input errors retain their existing types.
No failed chain is retried or returned as a successful partial fit.

The runnable fault checks are in [fitting boundaries](test/fitting_boundaries.jl).
They inject exceptions through target evaluation, JSON serialization, finite
checks and real Julia sampler RNG calls. The random-walk case fails on chain 2
after a complete first chain. The CmdStan case uses a synthetic shell executable
and fails the parser on chain 2; it does not compile or sample a Stan model.
Constructed exception objects do not test actual memory exhaustion, live Ctrl-C
delivery, subprocess termination/reaping or cancellation of a process tree.

On Julia 1.12.5/macOS, all 76 new fault assertions pass. The 1,097 existing
boundary and tiny-fit assertions, CmdStan contract/CSV checks (78), generalized
guards (58), and retained Stan density/gradient references (44) also pass in
targeted runs. These are software checks, not posterior validation. The full
suite, minimum supported Julia version and other platforms were not run.
The existing isolated CmdStan cache probe (4,617 assertions) and synthetic
producer/control probe (431) also pass. The latter's imports were updated for
the shared control checks and fatal-exception policy; both probes avoid native
CmdStan execution.

The next pass extends the same context wrapper to chain initialization and
retained-output validation in stable Julia, guarded generalized, research
correlation and CmdStan paths. Initialization/output `ArgumentError`s retain
their type with context added; unexpected failures retain a captured cause.
CmdStan output dimensions and row counts must match exactly before assignment,
so broadcasting cannot conceal malformed output. Finite output is checked
after conversion into the retained Float64 arrays.

A real SIGINT sent to Julia while its owned command waited reproduced an
orphaned direct child with both terminal and captured output. The command
adapter now retains the process handle, enables interruption during the wait,
and kills/reaps the direct child before rethrowing. It preserves stdin and
the existing output-routing behavior explicitly when starting asynchronously,
following Julia's [process API](https://docs.julialang.org/en/v1/base/base/#Base.run)
and [signal handling API](https://docs.julialang.org/en/v1/base/c/#Base.disable_sigint).
The standalone [command lifecycle check](test/cmdstan_cancellation.py) runs
with `python3 test/cmdstan_cancellation.py`; it uses unchanged package helper
bodies, temporary shell commands and real POSIX signals, without loading the
full package or running CmdStan. It checks successful and failed commands,
stdin/output routing, and interruption with a child that ignores INT and TERM.
The probe explicitly uses `Base.exit_on_sigint(false)`, matching capturable
REPL interruptions. The package does not change Julia's global signal policy;
immediate script termination bypasses this exception-based cleanup.

On Julia 1.12.5/macOS, the 76 additional boundary assertions and all six live
command cases pass. The combined targeted Julia run passes 6,477 assertions,
including the existing tiny native fits, generalized guards, retained Stan
references and both isolated CmdStan probes. Invalid native output is injected
at the shared validation wrapper; these checks do not imply that Turing or
AdvancedHMC emitted malformed draws. No actual CmdStan fit, full-suite run,
minimum-version run or other-platform validation was performed.

The 2026-09-13 pass extends command ownership to a fresh POSIX process group,
using the same scope as the existing [command observer](scripts/measure_command.py).
The Julia adapter uses [detached commands](https://docs.julialang.org/en/v1/base/base/#Base.detach)
and the existing libuv runtime's [signal API](https://docs.libuv.org/en/v1.x/process.html#c.uv_kill).
Remaining group members are terminated after command completion as well as
interruption, including a wrapper's workers when the wrapper exits first.
Special group IDs and Julia's own group are rejected before signalling.
This uses no process-name search or new runtime dependency.

A lazily registered, single Julia exit hook cleans active commands at default
script SIGINT exits and explicit `exit()` calls. The registry is locked and
retains only active commands; completed commands are removed. Julia's global
SIGINT policy is unchanged: capturable interrupts still propagate, while
uncapturable script SIGINT still terminates Julia. Cleanup failures are reported;
an exception during the command wait and a subsequent cleanup exception are
retained together instead of discarding the original failure.

The expanded [lifecycle check](test/cmdstan_cancellation.py) tests the original
six command cases and twelve process-group cases: captured SIGINT sent to Julia
or its terminal group, default script SIGINT, explicit exit, two active groups,
and a leader exiting with status 0 or 7 before its worker. It verifies group
identity, preservation of an unrelated group, descendant exit via an owned
FIFO reaching EOF, and rejection of unsafe group IDs. FIFO EOF is not a claim
that Julia can reap non-child descendants. These are synthetic processes, not
native CmdStan build or estimation evidence.

On Julia 1.12.5/macOS, all eighteen live command cases and the group-ID guards
pass. The existing targeted Julia testsets pass 6,477 assertions; a final check
also confirms that the package's active-command registry is empty. The combined
error formatter is checked separately so a cleanup failure is visible alongside
the original error. No actual CmdStan fit or full-suite run was performed.

The remaining boundary is explicit: descendants that call `setsid`/`setpgid`
can escape the owned group; SIGKILL or other termination bypassing Julia exit
hooks cannot run cleanup. Windows retains direct-child cleanup. Runtime
discovery still uses its separate command path. Minimum-version, other-platform,
PID/group-reuse races, repeated-signal stress and actual CmdStan cancellation
remain unvalidated. These remain explicit acceptance limits.

The subsequent [blockwise measure check](#current-fixed-q-mgmfrm-executable-blockwise-measure)
now connects the current Julia target to production CmdStan densities and
gradients. The [normalized prior reference](#normalized-source-and-exchangeable-prior-reference)
specifies source/exchangeable blocks, now integrated into
[complete private Julia/Stan densities](#complete-fixed-q-normalized-prior-targets).
The [private sampling and saved-result slice](#normalized-prior-sampling-and-saved-results)
now exercises both backends. The subsequent
[fixed-Q posterior comparison](docs/internal/normalized-prior-backend-comparison.md)
initially meets diagnostics in all four fits but retains one of 640 comparison
rows on its predeclared precision criterion. The separately frozen larger-budget
follow-up passes all 640 rows, closing that bounded same-target precision check.
The subsequent normalized-prior slice records warmup events on both routes
without changing retained draws. The next integration exposes chain summaries
through ordinary fit diagnostics and cache save/load. A separate warmup report
section now reaches structured/public/Markdown/table/bundle outputs. Shared
Markdown column order now survives report/dossier JSON reload. Broader sampling
acceptance, full sampler-failure handling and other presentation limits remain open.
These corrections do not close M1.

#### Turing adaptation boundary, 2026-09-14

Auditing the missing Turing warmup telemetry exposed a control defect first:
`NUTS(-1, ...)` let Turing choose adaptation length from `ndraws`, while
`num_warmup` did not override that length. The initial state also occupied one
discarded row, so the previous discard count could retain adapting transitions.
With six retained draws, requests for 0, 1 and 8 warmup iterations all used
three adaptation transitions. The zero/one cases retained three adapting rows
while reporting `is_adapt = false`.

The adapter now sets `NUTS(warmup, ...)` and excludes the initial state plus
all `warmup` transitions. Fit metadata and cache request identity include the
explicit `nadapts` count, including zero. Old Turing caches remain manually
readable but cannot be automatically reused for the corrected request. Their
unrecorded warmup history stays unavailable even for a zero-warmup request.
Re-estimation is needed to use the corrected schedule; seed equality with the
old defective schedule is not an acceptance condition. Likelihoods, priors,
AdvancedHMC and CmdStan sampling paths are unchanged. The [existing owner](docs/internal/normalized-prior-backend-comparison.md#turing-adaptation-boundary-2026-09-14)
records the reproduction and focused checks. The subsequent recording slice
below preserves this corrected schedule; neither establishes convergence.

#### Turing warmup event recording, 2026-09-14

Ordinary Turing fits now record chain-level warmup iteration coverage,
divergences, maximum-depth hits and nonfinite log densities through the existing
summary/cache/report path. Initial states and adapting draws remain excluded
from posterior output. The adapter temporarily buffers warmup transitions per
chain; only compact summaries enter the fit and cache.

Julia 1.10.8 passes 305 warmup assertions; Julia 1.12.5 passes the 146 Turing/
unavailable-history assertions. Recording on/off preserves retained arrays,
diagnostics and the subsequent RNG stream. Direct Turing references verify the
event counts at warmup 0, 1 and 8. Another 40 checks verify two actual corrected
pre-recording caches: unchanged keys/bytes, ordinary reuse, exact fresh draw
equality and recorded-summary reload. The existing 1,458 boundary/CmdStan
contract checks pass. Details and limits are in the [existing owner](docs/internal/normalized-prior-backend-comparison.md#turing-warmup-event-recording-2026-09-14).
Fit structs, cache schema, likelihoods, priors and other samplers are unchanged.
Random-walk recording is covered by the following slice; interrupted-chain
telemetry remains separate.

#### Random-walk warmup event recording, 2026-09-14

Ordinary `backend = :julia` fits now retain one nonfinite-proposal counter per
chain during burn-in. The existing warmup diagnostic, cache and report paths
expose these counts separately from retained iterations. NUTS event fields are
missing because they do not apply. There is no proposal-scale adaptation or
warmup draw buffer. Older positive-warmup histories remain unavailable;
known zero warmup reports zero proposal events and inapplicable NUTS fields.

Julia 1.10.8 passes 383 warmup checks; Julia 1.12.5 passes the 80 random-walk
checks. Controlled nonfinite proposals verify phase/chain separation, while
recording on/off preserves retained results and subsequent RNG values. Forty
checks on two actual pre-edit caches verify unchanged keys/bytes, reuse and
fresh retained-result equality. Another 1,717 boundary/CmdStan-contract and
report checks pass. See the [existing owner](docs/internal/normalized-prior-backend-comparison.md#random-walk-warmup-event-recording-2026-09-14)
for persistence/report checks and limits. These are implementation checks,
not statistical validation or independent review.

#### Fixed-coefficient unit-logit MFRM reference, 2026-09-14

The private `_MFRMFixedQReferenceLogDensity` removes all active log-loadings
and free log-consistencies from the parameter vector. Active Q loadings and
all rater consistencies are exactly one. Abilities, item locations, free rater
severities and free item steps use unit-logit coordinates. Dividing only those
locations/steps by 1.7 permits reuse of the unchanged production MGMFRM kernel;
the reference prior is explicitly defined on the reduced unit-logit vector.
No positive-transform Jacobian or prior for a fixed coefficient is added.

Julia 1.10.8 passes 844 density/measure checks. Julia 1.12.5 and CmdStan 2.39.0
pass 1,206, including 51 checks of the reduced Stan reference. The 2D pure/mixed
and 3D pure examples have 18, 18 and 26 free coordinates, versus 24, 25 and 34
in their generalized targets. Independent equations, unit-scale prior mapping,
gradients and per-dimension scalar PCM likelihoods agree. These are numerical
checks without sampling, recovery, convergence or scientific acceptance.

Fixed coefficients do not remove the location invariance
`theta[p, :] += c; item[i] += dot(Q[i, :], c)`. Proper free-coordinate normal
priors anchor these directions in this reference. One scalar PCM over
person-dimension IDs retains unfixed locations and is rejected by the existing
design validator; dimension-specific scalar comparisons verify conditional
likelihoods only, retaining the shared rater effects. Neither independent
univariate posteriors nor prior invariance under gauge changes is established.
The [existing owner](docs/internal/normalized-prior-backend-comparison.md#fixed-coefficient-unit-logit-mfrm-reference-2026-09-14)
records the equation, prior/measure, native checks and remaining fit boundary.

#### Fixed-coefficient MFRM sampling and persistence, 2026-09-14

The private unit-logit reference now uses the existing AdvancedHMC and CmdStan
NUTS runners. Retained draws, parameter diagnostics and posterior intervals keep
the reduced names and units; fixed coefficients do not appear as sampled
parameters. A separate sample schema records the actual prior, coordinate
measure, prior-anchored location convention and design identity. Loading verifies
the canonical record and recomputes retained Julia densities; CmdStan output and
saved records also verify `lp__`, including the normalizing constants.

Julia 1.10.8 passes 214 new sampling/persistence assertions. Julia 1.12.5 with
CmdStan 2.39.0 passes 457. These cover 2D mixed-Q and 3D pure-Q short fits,
warmup recording, reduced summaries, reloads, model/scale mismatches and
preservation of existing files after rejected writes. The shared Stan response
function expands to the exact pre-change MGMFRM source. The [existing owner](docs/internal/normalized-prior-backend-comparison.md#fixed-coefficient-mfrm-sampling-and-persistence-2026-09-14)
records regression checks and a separate-process saved-result check.

This closes private sampler/persistence wiring, not a public model selector,
convergence, recovery or independent scientific acceptance. The follow-up below
adds reconstructed results and interval figures. Public exposure still needs
coherent model, prior and result semantics.

#### Fixed-coefficient MFRM reconstructed results and figures, 2026-09-14

The private result now reconstructs every rater severity and item step from
each retained draw in unit logits. Existing constraint algebra, posterior
summary and MCMC diagnostic builders supply full-coordinate summaries, with
fixed coefficients/baseline steps excluded from convergence gates. The last
rater and last item steps remain uncertain derived quantities. The canonical
sample record and v1 schema are unchanged; loading rebuilds these views.

The private interval-figure adapter reuses the ordinary parameter/dimension
selection, interval calculation and CairoMakie renderer. Model/backend labels,
unit-logit location/step axes and dimensionless fixed-coefficient axes are
explicit. Figures retain whole-model warnings when a subset is selected.
Older Julia/CmdStan sample files can supply these figures without refitting.
The [existing owner](docs/internal/normalized-prior-backend-comparison.md#fixed-coefficient-mfrm-reconstructed-results-and-figures-2026-09-14)
records tests, saved-file compatibility, PDF/SVG inspection and limits.

This completes private reconstructed summaries and interval figures. The
follow-up below adds retained trace/rank panels. Public model selection,
report integration, predictive figures and statistical validation remain open.

#### Fixed-coefficient MFRM trace and rank figures, 2026-09-14

The private diagnostic-figure adapter now reuses the existing trace/rank data
builder and CairoMakie renderer. Every retained iteration remains attached to
its original chain. Last-rater and last-item-step coordinates are explicitly
marked as derived and show their own R-hat and bulk/tail ESS. Fixed coefficients
and baseline steps show a fixed line and an inapplicability message instead
of a rank comparison. Whole-model warnings and per-chain sampler diagnostics
remain visible when selecting a subset or a named dimension.

Julia 1.10.8 passes 1,920 focused assertions, and Julia 1.12.5/CmdStan 2.39.0
passes 2,648, including existing public plot-data regressions. Old backend
sample files supply the new figures without refitting or changing the sample
schema. Model/backend labels and unit-logit versus dimensionless axes stay
explicit; unstored warmup parameter draws are not reconstructed. The [existing owner](docs/internal/normalized-prior-backend-comparison.md#fixed-coefficient-mfrm-trace-and-rank-figures-2026-09-14)
records rendering checks, output inspection and their limits.

The conditional category predictive follow-up below reuses the same saved
results. Public model/result/report integration and statistical validation
remain separate handoffs.

#### Fixed-coefficient MFRM conditional predictive checks, 2026-09-14

The private reference now produces replicated ratings and category-proportion
figures from canonical saved results. It reuses the existing category generator,
check summaries and CairoMakie renderer. The likelihood-coordinate mapping
preserves unit logits; active Q loadings and consistency remain fixed at one.
Independent 2D mixed-Q and 3D pure-Q formulas check probabilities and their
agreement with pointwise log likelihoods.

All retained draws, sampled indices with replacement, and explicit ordered
indices (including repeats) are supported with a local seeded RNG. Selected
chain IDs and iteration numbers remain attached, and the whole-model diagnostic
warning survives draw selection. All declared categories stay visible, including
zero observed counts. Figure intervals summarize replicated proportions for
existing rating rows, persons, items and raters. They are pointwise intervals;
this same-data check does not establish convergence or new-facet performance.

The [existing owner](docs/internal/normalized-prior-backend-comparison.md#fixed-coefficient-mfrm-conditional-predictive-checks-2026-09-14)
records Julia/CmdStan checks, old-result regeneration and visual evidence.
The result/report contract below now specifies the handoff. Its production
assembler and public model selection remain separate implementation steps.

#### Fixed-coefficient MFRM result/report contract, 2026-09-14

The private result/report handoff is specified against the existing code in
[its owner](docs/internal/normalized-prior-backend-comparison.md#fixed-coefficient-mfrm-resultreport-contract-2026-09-14).
Reuse the full report payload and JSON/table/Markdown exporters through a
private assembler. Its model label is fixed-coefficient multidimensional MFRM,
with unit logits, exact prior/target/sample identity, free and reconstructed
summaries, both diagnostic tables, separate warmup coverage and conditional
predictive rows. The reused `:mgmfrm` storage spec must not imply estimated
coefficients or generalized raw-coordinate priors.

The compatibility probe identifies presentation gaps: nested model identity
and non-warmup section explanations are not rendered automatically; the public
projection gives the private status `unknown`; a report-only bundle cannot add
figures. Existing `complete` means no captured section errors, independently of
MCMC quality and unsupported capabilities. The owner defines the required core,
unsupported reasons and acceptance checks. A 62-assertion Julia 1.12.5 probe round-trips report/table drafts from both
old backend samples with nested-hash checks and no MCMC. No production report
constructor, public selector or new sampling study is added by this
specification slice.

The private assembler and presentation follow-up below implements this first
handoff. Staged figure-bundle integration follows the verified report rows.

#### Fixed-coefficient MFRM internal reports, 2026-09-14

`_mfrm_fixed_q_report` now assembles full internal reports from canonical saved
results using the existing section and export helpers. It preserves the actual
unit-logit model/prior/target/sample identity, free and reconstructed summaries,
both diagnostic tables, fixed/derived applicability, warmup coverage and one
conditional predictive check with its selection/seed. It names ten unsupported
sections with specific reasons. Canonical corruption remains fatal before error
capture; report-generation completeness is separate from support and MCMC quality.

Markdown now shows the optional identity fields, coordinate/conditioning
explanations, unsupported reasons and captured errors even with table previews
disabled. The [existing owner](docs/internal/normalized-prior-backend-comparison.md#fixed-coefficient-mfrm-internal-reports-2026-09-14)
records checks and saved-result round trips. Public model selection, cache
conversion and public projection remain separate. The following figure-bundle
slice connects the three existing private figures to these report rows.

#### Fixed-coefficient MFRM report figures, 2026-09-15

`_save_mfrm_fixed_q_report_bundle` connects saved Julia/CmdStan samples to the
existing staged report/figure writer. Posterior intervals use the report's
central interval; prediction uses its exact category rows and resolved draw
selection. Whole-model diagnostics, fixed/derived coordinates, named dimensions,
backend and unit-logit labels remain present. Figure JSON includes target and
source-sample identity alongside the report hash. Existing bundle schema v2,
PDF/SVG/JSON exports and loader checks are reused.

The [owner](docs/internal/normalized-prior-backend-comparison.md#fixed-coefficient-mfrm-report-figures-2026-09-15)
records saved-result replay, destination-preservation checks and PDF review.
The public model/result contract below now specifies the next implementation
steps. Numerical implementation checks do not close statistical acceptance or
the independent-reader walkthrough.

#### Fixed-coefficient MFRM public API contract, 2026-09-15

The [owner](docs/internal/normalized-prior-backend-comparison.md#fixed-coefficient-mfrm-public-api-contract-2026-09-15)
specifies the proposed `family = :mfrm, dimensions >= 2, q_matrix = Q` request,
initially through `Experimental.fit`. It preserves scalar MFRM and estimated-
coefficient MGMFRM behavior. A dedicated result type will reuse common summary,
diagnostic, plot and report calls without admitting unsupported numerical
analyses through the broad fit union. Julia NUTS (`:advancedhmc`) remains the
default for the new branch, with CmdStan as the maintained alternative;
`:julia` keeps its existing scalar random-walk meaning.

The contract separates manual save/reopen from automatic request caching,
specifies source/target/report identity and a new-result cache envelope, and
traces a named-dimension report/figure workflow. Artifact and rating-design
adapters are required for experimental exposure; the other eight unsupported
report analyses may remain explicit limitations. A 71-assertion probe verifies
the current boundary using old samples without fitting or rendering; the
proposed selector and result type are not implemented by this specification.

The dedicated result adapter and canonical specification/identity are implemented
below. The complete experimental fit/cache/report workflow remains required
before exposing fitting. Statistical acceptance remains separate.

#### Fixed-coefficient MFRM result adapter, 2026-09-15

The private root type `MultidimensionalMFRMFit` owns a detached canonical sample
record and revalidates it on every read. Explicit `fit_metadata`,
`posterior_summary`, `direct_posterior_summary` and `diagnostics` methods preserve
unit logits, named dimensions, actual prior/target/source identity, fixed/derived
coordinates, stored diagnostic criteria and separate warmup coverage. Display
names the model and backend. Shared metadata assembly preserves existing private
reports. The [owner](docs/internal/normalized-prior-backend-comparison.md#fixed-coefficient-mfrm-result-adapter-2026-09-15)
records validation and the remaining exposure requirements.

The type remains unexported without an `Experimental` alias. Its report/plot,
cache/artifact and comparison methods are not activated by this adapter. The
canonical specification/design/identity follow-up is recorded below.

#### Fixed-coefficient MFRM canonical specification, 2026-09-15

`mfrm_spec(data; family = :mfrm, dimensions = D, q_matrix = Q,
dimension_labels = labels)` now represents the fixed-coefficient model for
`D >= 2`. `getdesign(spec; preview = true)` compiles its free unit-logit
coordinates; constraints, prior rows, model-family contract and full/public
manifests identify fixed coefficients, prior-anchored locations and identity
correlation. The existing Q/coverage gates and warnings are retained. Its
canonical target identity is distinct from the legacy storage-spec identity;
the reference density and CmdStan input use the same unit-logit target.

Public fitting and automatic cache requests reject this branch before numerical startup.
Row-level predictor inspection also remains unavailable with an explicit
explanation. The [owner](docs/internal/normalized-prior-backend-comparison.md#fixed-coefficient-mfrm-canonical-specification-2026-09-15)
records the checks and remaining workflow requirements. The private sampling
connection is implemented below; cache/report exposure remains subsequent work.

#### Canonical fixed-coefficient MFRM fitting and replay, 2026-09-15

The private `_mfrm_fixed_q_fit(spec; ...)` now connects the canonical
multidimensional MFRM specification to Julia NUTS by default and to CmdStan
when requested, returning `MultidimensionalMFRMFit`. Its v2 sample record stores
the MFRM spec, actual prior and canonical target identity. The existing private
writer/loader preserves that record and rebuilds metadata, free/reconstructed
summaries and diagnostics. Schema/family mismatches reject even after rehashing;
old v1 records retain their original family, identity and bytes. Numerical entry
revalidates the authoritative design and rebuilds derived target views.

Small two/three-dimensional Julia fits and a matched two-dimensional CmdStan
fit pass on the tested runtimes; both backends' target/prior and retained
log-density checks agree. This verifies operability, not convergence, recovery
or interval coverage. Public fitting and result report/plot dispatch remain
unavailable; manual cache/artifact support is recorded below. The [owner](docs/internal/normalized-prior-backend-comparison.md#canonical-fixed-coefficient-fitting-and-replay-2026-09-15)
records the runs, compatibility evidence and remaining exposure conditions.

#### Fixed-coefficient MFRM manual cache and artifact, 2026-09-15

Canonical `MultidimensionalMFRMFit` results now use `save_fit_cache` /
`load_fit_cache` with a dedicated v2 envelope and `fit_artifact(view = :full)`.
The existing atomic writer, artifact hashes and environment metadata are reused.
The fit's sample record remains the sole model/draw authority; loading rebuilds
and checks the artifact's model, prior, controls, source/target identity,
summaries, diagnostics and archive summaries. Saved environment metadata and
diagnostic settings survive replay. V2 integrity checks remain mandatory when
`verify_hash = false`; existing v1 cache behavior is preserved.

Legacy private samples retain their loader and cannot be silently imported into
the new cache. Automatic request caching, public fitting and result report/plot
dispatch remain unavailable. The [owner](docs/internal/normalized-prior-backend-comparison.md#manual-fixed-coefficient-cache-contract-2026-09-15)
records the contract and validation. The numerical reporting connection is
recorded below; no additional sampler or saved-result type is introduced.

#### Fixed-coefficient MFRM saved-result reports, 2026-09-15

Canonical results now support `fit_report`, `fit_report_public` and
`fit_artifact(view = :public)`. The dedicated adapter reuses the private report
assembler, adds validated rating-design rows and the existing full artifact,
and preserves actual priors, unit logits, named dimensions, fixed/derived
coordinates, stored diagnostic settings and source/target identity. Public
output was labelled experimental while fitting was unavailable at that step. Central
posterior bounds use the existing interval semantics; unsupported analyses and
captured errors remain distinct from MCMC warnings. Full v1 artifacts and
v1/v2 fit-cache meanings are unchanged. See the
[owner's verification](docs/internal/normalized-prior-backend-comparison.md#canonical-fixed-coefficient-saved-result-reports-2026-09-15).
The subsequent [figure handoff](docs/internal/normalized-prior-backend-comparison.md#canonical-saved-result-figures-2026-09-15)
connects posterior, trace/rank and conditional predictive figures and staged
full/public bundles. The [experimental fitting handoff](docs/internal/normalized-prior-backend-comparison.md#experimental-fixed-coefficient-fitting-2026-09-15)
subsequently connects the API and generic example. Individual
saved-result checks pass; the combined Julia 1.12 assertion drivers still exceed
the 600-second budget. Track that compilation cost separately and do not claim
a complete 1.12 matrix or full-suite pass.

### Model axes and staged scope decisions

The user's seven-point model review on 2026-09-11 and extension review on
2026-09-15 refine M1 and the long-term scope. Specify the following axes
separately for each proposed model, using the existing
[family contract](src/model_family_contract.jl), [equations](docs/src/model-equations.md)
and [experimental scope](docs/src/experimental.md). These are distinct decisions,
with support established per declared combination. Source reproduction and the
exchangeable-rater-prior model retain their parallel scientific roles; the
current raw-prior implementation remains a separately identified baseline.

| Axis | Current evidence | Required specification and completion condition |
| --- | --- | --- |
| Logistic scale constant | MGMFRM executes `1.7` in Julia and Stan; `1.702` is reference metadata. Stable MFRM and the implemented 2020 scalar GMFRM use unit scaling | Name the multiplier `c` separately from dimension count `D`. Retain literal `1.7` for source reproduction. Any alternative needs an explicit likelihood/parameter/prior mapping and versioned identity; changing the constant alone is not a precision fix or exact normal-ogive conversion |
| Coordinate measure and Jacobians | Current generalized priors are normal densities on raw coordinates; deterministic positive transforms require no extra Jacobian for that target | Complete the blockwise measure/transform specification below. Distinguish Stan's automatic parameter-constraint transforms from manual changes of variables and from transformations of already sampled variables. Check density differences and gradients in common coordinates, including constrained-vector reconstruction; backend agreement alone does not establish source-prior fidelity |
| Explicit ability vector and multidimensional MFRM | MGMFRM estimates every person's `theta[p,d]`. `family = :mfrm, dimensions >= 2` supports fixed-Q specification/design inspection, Julia/CmdStan fitting and manual v2 cache/artifact replay; experimental fitting now connects through `Experimental.fit`. MGMFRM `discrimination = :none` still estimates active loadings and rater consistency. Fixed-Q MFRM has a dedicated result adapter, reconstructed summaries and report/figure bundles with `a[i,d] = Q[i,d]`, unit consistency, unit logits and explicit free-coordinate priors | The experimental fit-to-report path and a generic two-backend example are connected. Retain the prior-anchored location convention and identity-correlation ability prior as restrictions; hard anchors or another prior require a separately specified target. Operability does not establish statistical acceptance |
| Confirmatory versus exploratory | Current Q zero locations are fixed and active positive loadings are estimated. An all-active Q is rejected by the duplicate-column gate | First retain named confirmatory dimensions for the matched comparison. Full source loading reproduction needs its own identification/alignment treatment. Exploratory discovery additionally needs admissible rotations, signs/permutations and interpretation checks; a dense Q or estimated nonzero loadings alone does not supply that workflow |
| Between-item versus within-item | One active Q entry per item gives between-item structure; multiple active entries give within-item structure. Admitted within/mixed designs are warning-bearing; the narrow evaluation candidate is between-item | Declare the tested Q geometry and person/item/rater coverage. Select within-item checks for named loading-direction or cross-loading questions; pure-item evidence cannot close them. Q acceptance and structural rank do not establish joint identification or recovery |
| Compensatory versus non-compensatory | The weighted ability sum permits conditional compensation on cross-loaded items; no nonadditive ordinal kernel is implemented | Describe the response equation separately from the source author's label and the user's decision rule. Retain additive algebra and exact tradeoff checks for reproduction. A non-compensatory response alternative needs its own probability equation and claim; do not infer it from between-item structure, category accumulation or rater product constraints |
| Correlated factors versus bifactor | Unwrapped generalized fits fix latent correlation to identity, with covariance `person_sd^2 I`. Explicit between-item correlated MGMFRM fitting and manual caches now complement its retained density-only candidate; prior/conditional posterior prediction and report/figure adapters are connected; statistical validation remains pending. The separate fixed-coefficient 2D density has an explicit prior/transform contract and Julia/CmdStan numerical checks; its explicit experimental fit/cache/report/figure workflow is connected for between-item Q, with statistical validation pending. Bifactor-shaped Q can be admitted as a warning-bearing within-item design | Specify covariance restrictions separately from loading roles. Correlated factors need a reviewed correlation prior/transform and both fitting routes. Bifactor needs explicit general/specific roles, orthogonality or declared deviations, identification, score interpretation and recovery evidence. Neither identity covariance nor Q acceptance certifies bifactor support; posterior dependence is not the latent-population correlation |
| Q identification versus Q estimation | Current validation checks the supplied Q structure and coverage; MGMFRM estimates positive active loadings while structural zeros stay fixed. No ordinary route estimates Q itself | Distinguish identification of a fixed-Q model, estimation of its continuous loadings, and inference over zero/nonzero structure. Start with prespecified candidate structures and a fixed dimension count, then partially unknown Q and exploratory loading structures. Define scale, labels, signs/rotations and observational equivalence; structural checks alone do not establish identification. Preserve structural uncertainty in ability and predictive summaries |
| Configurable random effects | The current fitting families have prescribed person/item/rater blocks and priors. Additional cluster identifiers and residual summaries do not fit cluster effects or estimate arbitrary variance components | Add declared grouping factors, random intercepts, nested/crossed structures, then justified random slopes and covariance blocks. Specify fixed predictors, grouping units, pooling/hyperpriors, replication requirements and existing/new-level prediction. Start with reusable blocks rather than a universal formula parser; expose only implemented combinations and diagnose confounded effects |

The sampler-free 2026-09-11 inspection used nine items, three disjoint groups
of three, and Q columns for one general plus three specific factors. Each item
loaded on the general factor and its group's specific factor. Q validation
passed with structural rank four, but returned
`guarded_generic_fixed_q_review_required` and cross-loading/no-pure-item
warnings. The preview retained eight ability coordinates for two persons.
This establishes representation and guard behavior only; no posterior fit,
Stan compilation, bifactor identification or scientific validation was performed.

**Completed foundation evidence:** prior-predictive inspection for independent
and correlated fixed-coefficient MFRM now uses the declared joint priors and
existing response kernel. Parameter summaries, `plot_prior(check)` and
`plot_predictive(check)` provide ability/correlation and rating implications
before fitting. Verification is recorded in the
[owner's evidence](docs/internal/normalized-prior-backend-comparison.md#fixed-coefficient-prior-inspection-2026-09-17).
Optional saved-fit report sections and figures now reuse that prior simulation
with an explicit local RNG and draw budget; their
[verification record](docs/internal/normalized-prior-backend-comparison.md#fixed-coefficient-prior-report-integration-2026-09-17)
distinguishes this implementation handoff from scientific acceptance.
The [prior/identification review](docs/internal/fixed-coefficient-prior-identification.md)
now traces the current free-coordinate measure, unequal reconstructed variances,
rater-label dependence and likelihood location freedom with sampler-free checks.
This characterizes a limitation; it does not accept arbitrary label dependence
as the final scientific default or close M1.
The private exchangeable-rater reference is implemented for independent and
correlated fixed-coefficient MFRM. It reuses the normalized zero-sum correction,
response likelihood and existing ability/correlation terms. Explicit kernel,
common marginal and contrast scales, unchanged item/step priors and a distinct
persistable mathematical target identity are recorded in the
[implementation evidence](docs/internal/normalized-prior-backend-comparison.md#fixed-coefficient-exchangeable-rater-reference-2026-09-17).
The reference-only implementation initially left public prior selection
unchanged. The later explicit opt-in API below now supplies that selector;
the compatibility default has not migrated.
The private prior-draw adapter and comparison now match either mean pairwise
contrast variance or the compatibility free-rater marginal SD. They retain
nonrater draws, share predictive uniforms, handle the R=2 equality case and
label existing parameter/predictive figures with actual prior/matching meanings.
The [implementation record](docs/internal/normalized-prior-backend-comparison.md#fixed-coefficient-rater-prior-prediction-2026-09-17)
separates mathematical/backend checks and synthetic prior implications from
statistical acceptance.
The private sample adapter now reuses Julia/CmdStan NUTS, coordinate
reconstruction and diagnostics. A distinct record verifies its specification,
prior, identity, draw densities and chain/warmup layout before save/reload;
compatibility/public fit-cache loaders reject this new format. Bounded live
runs and integrity checks are recorded in the
[result-persistence evidence](docs/internal/normalized-prior-backend-comparison.md#exchangeable-rater-sampling-and-result-persistence-2026-09-17).
These short runs establish operability and retain MCMC warnings.
The private reporting path now reuses posterior-predictive summaries and the
staged report/figure writer. Actual exchangeable kernel/marginal/contrast scales
and diagnostic warnings accompany regenerated outputs; incompatible records
are rejected before reporting. The
[reporting evidence](docs/internal/normalized-prior-backend-comparison.md#exchangeable-rater-prediction-and-reporting-2026-09-17)
separates output verification from statistical acceptance.
The opt-in `Experimental.ExchangeablePrior(rater_kernel_sd=...)` now connects
both public experimental fitting routes to `Experimental.ExchangeableMFRMFit`,
manual caches and the existing report/figure workflow. The selected kernel,
marginal and contrast scales survive save/reload; old defaults and records are
unchanged. See the [API evidence](docs/internal/normalized-prior-backend-comparison.md#explicit-exchangeable-prior-api-2026-09-17).
The [validation protocol draft](docs/internal/fixed-coefficient-validation-protocol.md)
now connects those questions to explicit estimands, five primary/four secondary
fit cells, matched rater-contrast variance, separate SBC, and diagnostic-qualified
backend comparisons. Its complete and balanced-thin designs have only the two
location null directions; disconnected and missing-dimension controls add more.
This deterministic evidence is not posterior recovery. Allocations, margins and
sampler/resource rules remain proposals awaiting target-specific review.
The [Julia preparation](docs/internal/fixed-coefficient-validation-protocol.md#sampler-free-julia-preparation)
now implements independent response generation, truth/category/target alignment,
per-draw estimands, chain-aware MCSE and failed-attempt denominators on synthetic
inputs. New checks pass on both Julia versions; synthetic CmdStan-labelled
records exercise result wiring, not live backend agreement.
The [SBC preparation](docs/internal/fixed-coefficient-validation-protocol.md#sampler-free-sbc-preparation)
now adds separate joint-prior generation, 12/13 bound test quantities, exact-tie
randomization and full-denominator CDF envelopes. Prior moment checks and an
enumerated prior-only negative control are preparation evidence, not MCMC SBC.
The [diagnostic/comparison preparation](docs/internal/fixed-coefficient-validation-protocol.md#sampler-free-diagnostic-and-comparison-preparation)
now applies supplied criteria and numerical margins, retaining failed/inconclusive
pairs and a fixed comparison family. The [SBC attempt binding](docs/internal/fixed-coefficient-validation-protocol.md#sampler-free-sbc-attempt-binding)
now retains planned IDs, generating targets, selected draw identities and
failure/dependence declarations in rank summaries. The subsequent
[C2 computation pilot and follow-ups](docs/internal/fixed-coefficient-validation-protocol.md#one-condition-computation-pilot-2026-09-17)
now provide actual execution, diagnostic and cost evidence, including retained
failures. The [current implementation handoffs](#next-implementation-handoffs)
replace the former pilot-preparation task. Study criteria remain proposals;
there is no new fit grid, controller or default change. Ordered-step priors and
scientific default selection remain separate decisions. Higher-dimensional
covariance, within-item validation, automatic request caching and hard anchors
are not supplied by the C2 evidence.
The warmup recording slices above are verified. Interruption-time histories
remain unavailable; adding them is deferred until a concrete failure-diagnosis
need warrants it, while existing error and cache-preservation guarantees remain.
The [figure/report integration](#report-bundle-figure-integration-2026-09-14)
and [public documentation cleanup](#public-documentation-cleanup-2026-09-14)
are verified. An unfamiliar-reader walkthrough remains pending independently;
automated checks do not establish reader usability or block Julia core work.
The [cache-compilation follow-up](docs/internal/normalized-prior-backend-comparison.md#cache-record-compilation-2026-09-14)
isolates excessive specialization in two private persistence helpers and
preserves the serialized bytes. This closes that bounded diagnostic task;
broader M0 performance work retains its separate acceptance conditions.
The [precision follow-up](docs/internal/normalized-prior-backend-comparison.md#precision-follow-up-execution-receipt)
now passes all 640 comparisons and all four diagnostic gates with 6,000 draws
per chain (96,000 retained draws total), under unchanged criteria and new
predeclared seeds. The initially held R2 consistency quantile has an
error-inclusive difference bound of 0.09935 posterior SD in the follow-up,
below 0.3. Preserve the first trial's separate 639/1 unresolved receipt;
no cutoff changed and no draws were pooled. The preceding hash improvement
also preserves existing records while removing the measured save/load delay.

The private normalized-prior sampler now records warmup telemetry by default
on Julia and CmdStan. Its version-2 sample records preserve chain/iteration,
divergence, depth and nonfinite-log-density events; version-1 records remain
readable with explicit unavailable coverage. Matched short fits verify exact
retained-draw and diagnostic equality with recording enabled/disabled under
both priors and backends. The earlier 96,000-draw comparison also reloads and
reproduces all 640 decisions unchanged.

Ordinary AdvancedHMC, Turing and CmdStan fits now record compact
chain-level warmup summaries. `sampler_diagnostics(fit; phase = :warmup)`
selects them, while its retained default and posterior convergence diagnostics
stay unchanged. All three fit structs and the v1 cache schema retain their
layouts; summaries travel in the existing sampler metadata. New caches retain
the summaries and old caches report unavailable coverage. Generalized fits
retain AdvancedHMC/CmdStan support. Random walk still has no positive-warmup
telemetry in this interface.

`fit_report` now includes these summaries automatically in a separate `warmup`
section. The section has explanatory text, no adaptation pass/fail cutoff, and
no effect on retained diagnostic flags. Its Markdown columns are fixed across
in-memory and JSON-loaded reports. Existing report readers/exporters carry the
new section; older reports without it retain their saved contents and hashes.

The shared Markdown resolver now orders identifiers, sampler coverage,
estimates and uncertainty consistently and sorts remaining columns by name.
This covers full/public reports and dossier tables without a renderer per
section or a serialized schema migration. Existing row values, public-language
filtering and hash meanings are preserved. Column stability does not promise
identical whole-Markdown bytes: JSON reload can render `1.0` as `1`, and full
typed artifact hashes differ from JSON-normalized public-report identity.
See the [bounded handoff](docs/internal/normalized-prior-backend-comparison.md#next-bounded-work).
The subsequent failure audit confirms that mid-chain AdvancedHMC exceptions
do not return or cache partial fits for all three families, and failed refreshes
preserve existing cache bytes. The same existing control flow is retained;
131 added fault assertions cover the delayed Julia/cache cases and CmdStan's
second-chain command failure. `sampling` remains the reported stage when the
library exception cannot identify a warmup/retained iteration.
Julia remains primary, with CmdStan as its same-target counterpart. Public
prior selection, existing `GeneralizedPrior` caches, broader statistical claims
and the application remain unchanged. Retain the
[other failure boundaries](#first-julia-core-verification-slice); no Uchihara
preprocessing or new statistical validation roster is required for this handoff.

#### Long-term extension sequence

The near-term completion target remains a reliable Julia workflow for a
declared model/design domain, with matching CmdStan evidence. The long-term
target expands that domain along the axes above. These extensions do not all
have to finish before the current foundation can be accepted. Follow this
implementation sequence; specification of independent later branches can
proceed when it resolves a concrete model question. Non-compensatory models
and Q structure inference are separately prioritized branches; neither requires
the other to be implemented first. Fixed-Q identification and candidate
comparison can advance with the current additive model. This is an order of
implementation focus: scientific completion of every earlier model is not a
blanket prerequisite for later code/specification work. Each extension needs
its relevant contract; domain promotion still needs its own evidence.

| Order and purpose | Bounded deliverable | Evidence and user-facing completion condition |
| --- | --- | --- |
| 1. Accept the implemented foundation for a declared domain | Experimental fixed-coefficient fitting, prior inspection, manual persistence, reports and named-dimension figures are connected on both backends. Complete the remaining model/protocol decisions, diagnostic-qualified comparisons, statistical evidence and reader review; do not reimplement the completed workflow | Same model, prior, diagnostic settings, selected dimensions and intervals survive Julia/CmdStan save/reload and report/figure export. Complete target-specific validation and reader review for the advertised scope; short fits establish operability only |
| 2. Correlated dimensions and within-item validation — distinguish related abilities and cross-loaded items | Follow the [concrete model handoff](#next-implementation-handoffs): first the existing 2D between-item generalized correlation candidate and its explicit prior/identification contract; separately examine a declared mixed fixed-Q geometry with covariance held at identity. After those separate checks, specify 2D correlation/cross-loading combinations and higher-dimensional positive-definite covariance as distinct extensions. Bifactor roles and constraints require a distinct specification; two dimensions are an initial slice, not the permanent API limit | Recover ability, loading and population-correlation uncertainty under selected correlation, Q and coverage conditions; assess prior sensitivity and confusion between cross-loadings and correlations. Deliver correlation intervals/figures and named loading/ability summaries. Bifactor additionally requires general/specific score interpretation and its own recovery evidence |
| 3. Configurable random effects — represent dependence at the actual grouping units | Begin with one justified extra grouping block and an estimated variance/hyperprior, e.g. task or recording. Extend the same design representation to nested/crossed intercepts, then predictor-specific random slopes and selected covariance blocks. Distinguish a modeled effect from an identifier retained only for reporting | Use replication/overlap conditions that can separate the effects; test weak/near-zero variance, omitted effects, shrinkage and confounding with abilities or facet severity. Deliver effect/variance/covariance summaries and plots. Define conditional existing-level and integrated new-level prediction separately; expose each only when implemented and checked |
| 4. Non-compensatory response models — test a different ability-to-response mechanism | Select one scientifically justified ordinal response equation first; define category probabilities, thresholds, rater effects, scale/prior measures and its unidimensional behavior. Preserve the additive model as an explicit alternative with a distinct target identity | Verify normalized valid probabilities, intended monotonicity and the stated compensation behavior. Use known-truth fits under both generating mechanisms to assess ability/decision calibration and predictive discrimination. Report dimension-conditioned response surfaces; an operational pass rule or author label does not define the response kernel |
| 5. Q structure inference — quantify uncertainty about what each item measures | First improve fixed-Q identification explanations and compare a bounded, prespecified set of candidate Q matrices at a fixed dimension count. Next allow selected unknown cells with declared structural priors, then exploratory loading/rotation policies. Selection of dimension count is a separate decision | Check distinguishable/equivalent structures, weak cross-loadings, incorrect Q and sparse coverage; assess structure recovery and ability/interval calibration with alignment appropriate to the model. Report candidate support or cell-inclusion probabilities only for the implemented inferential method, plus loading/structure figures and sensitivity to Q. Conditional-on-Q results must remain labelled; selecting one Q does not account for structural uncertainty |

For Q inference, estimating continuous loadings under fixed zeros is not
estimating the zero pattern. Stan cannot directly sample discrete parameters;
its [latent-discrete guidance](https://mc-stan.org/docs/stan-users-guide/latent-discrete.html)
describes marginalization where feasible. Choose a bounded candidate comparison
or a tractable marginalization before promising a shared unknown-Q posterior.
Record the structural prior, computational limit and uncertainty calculation.
A continuous relaxation has its own target and cannot silently replace a binary
Q model. Julia may use a different algorithm, but the maintained CmdStan
comparison must address the same declared model and inferential quantity.

Flexible random effects means supported blocks can be combined with explicit
meaning and usable syntax. It does not imply every grouping, slope and covariance
combination is identifiable. Explain grouping levels, fixed versus varying
coefficients, scale constraints and insufficient replication before fitting.
Record which facet or ability scales remain fixed for identification when
other variances are estimated;
report unresolved confounding rather than treating sampler convergence as proof
of separation. Reuse existing facet/design structures where they suffice, and
introduce a compact public specification only with the first working block.
Criterion-specific raters, recording effects and phonetic predictors can motivate
a reusable block, but no application-specific schema or arbitrary formula
language is required in advance.

For each extension, the completion evidence must connect the user's question
to the chosen data/design conditions, the quantities checked and the answer:

- State the response equation, dimensions/Q, covariance/effect structure,
  identification constraints, scale constants and priors/Jacobians. Record
  supported combinations in the existing model/surface contract; a change to
  the statistical target has an explicit identity.
- Check Julia probabilities, densities and gradients against independent
  equations and the matched CmdStan implementation. Compare diagnostic-qualified
  posterior/predictive results with Monte Carlo uncertainty; neither matching
  backends nor more local test assertions establishes statistical validity.
- Use a reviewed, bounded known-truth design selected for the claimed mechanism:
  recovery, interval coverage, failures, misspecification and prior sensitivity.
  Retain failed attempts and state whether evidence supports, narrows or leaves
  the intended domain unresolved. Require fresh interaction checks when combining
  independently validated blocks; avoid an automatic full Cartesian experiment.
- Complete fit -> diagnose -> interpret -> visualize -> save/reload using the
  existing result/report/figure path. Include model-specific uncertainty plots,
  declared prediction targets, reproducibility metadata and compatible saved
  records. Check clear README/help/examples with an unfamiliar reader; users
  should not reshape MCMC draws or interpret internal development stages.

Julia remains primary throughout. Each promoted extension retains the
two-backend requirement; an unavailable CmdStan counterpart remains an explicit
incomplete item, not a reason to substitute another model. This sequence does
not launch research runs, select numerical defaults or relax existing release
conditions. Uchihara and external-software comparisons exercise the relevant
supported slice; they do not define completion of the foundation or every
extension.

#### Shared specification and prediction contract

Extend `FacetData`, `mfrm_spec`, the existing model/surface contracts and saved
results only as the first relevant model block is implemented. These requirements
define observable API behavior, not a new generic registry or a promise of
particular keyword names. A workflow sketch using a future `spec` is not a
currently executable example: preserve the documented `fit` versus
`Experimental.fit` boundary until that family is deliberately exposed.

| Concern | Required behavior | Smallest meaningful verification |
| --- | --- | --- |
| Observation and grouping units | Distinguish the response event, criterion, physical item, person, rater and optional response/recording group. Preserve a physical item's identity when measurement items are item × criterion. Declare outcome-specific uniqueness keys, category direction and missingness/inclusion rules | Pure row permutations and consistent level relabelling preserve aligned probabilities under explicit parameter/prior/reference mappings. Joining recording-level features cannot multiply observations; accidental duplicates are rejected under the declared event key. Repeated events remain representable with explicit IDs; missing outcomes are not replaced by the lowest category |
| Effects and covariance | Specify which coefficients are fixed, estimated, shared across criteria or varying by group; record pooling, variance priors, scale constraints and the level of each covariance. Separate person-population correlation from shared-response dependence and posterior draw correlations | Check a minimal crossed/nested example and a deliberately confounded design. Verify known invalid structures fail before sampling; report unresolved identification limits. Fixed loadings/consistency are removed from sampled coordinates; a zero prior SD does not substitute for a fixed coefficient |
| Predictors and transformations | Record each predictor's grouping level, coding, units, centering/scaling, missing-data treatment and criterion-specific effects. Retain transformations in the fitted specification and cache. Word/item-level predictors require a separately identified hierarchical effect or explicit constraint | Reproduce fitted predictions after reload and on transformed new rows. Detect redundant predictor/effect columns. During heldout evaluation, estimate transformations and any imputation from training data only. Explain whether person traits are total or conditional on the included predictors |
| Comparison and prediction | Name the outcome, evaluation population, heldout unit and information available at prediction time. Separate predictions conditional on estimated existing levels from predictions integrating effects for new levels. Record which model block changes and which settings/data stay matched | Keep all criteria and raters for one heldout recording in the same split. Integrate its unknown effect when predicting a new recording; observed heldout ratings may be used only for a separately declared prediction task. Compare models on the same eligible observations with explicit scale/prior mappings and Monte Carlo uncertainty |
| Saved results, capability and errors | The specification, backend, summaries, reports and plots must agree on fitted effects, dimensions, transformations, prediction target and experimental status. Use the existing artifact/report identities and compatible readers | Reload and regenerate the same named summaries/figures on both backends. Unimplemented covariance, effect, predictor or prediction requests fail explicitly; do not silently use independent dimensions, ignore columns or omit uncertainty. Extend automatic cache keys only when that model's automatic caching is implemented |

Use synthetic examples with generic person/item/rater/group names for these
checks. The Uchihara data shape is a later application of the same contract.
For a composition such as correlated traits plus recording effects, test their
separation jointly before advertising the combination; passing each block's
isolated tests is insufficient. Retain the existing practical-acceptance and
independent-review requirements without making every future combination a
prerequisite for an ordinary implementation correction.

### Julia and CmdStan continuity and comparison

The user's 2026-09-11 decision is to retain both Julia and CmdStan estimation
as a continuing means of checking computational results. Julia is the primary
implementation and user-facing foundation; this priority does not retire or
indefinitely postpone the matching CmdStan route. AdvancedHMC is the
Julia comparison route for the current generalized models. CmdStan remains
optional for ordinary Julia installation and use. Carry each newly supported
core MGMFRM model through both routes; an implementation available on only one
route remains explicitly partial until the matching route is verified.

The two scientific models (source reproduction and exchangeable-rater prior)
and the two execution routes are separate choices. First resolve the
[blockwise specification](#blockwise-specification-and-comparison-contract),
then compare Julia and CmdStan within each accepted model and shared structural
scope. Backend switching must preserve the declared likelihood, prior measure,
identification constraints and model/scale interpretation in reports and artifacts.
Record the backend and sampler configuration in execution/cache identity,
separately from the model identity.

Reuse the existing target tests and paired-validation scripts in two stages:

1. At matched parameter points, compare log-density differences, Jacobians,
   gradients and response probabilities in a common coordinate measure, with
   declared numerical tolerances. Shared helpers or fixtures can share errors;
   retain source-equation and independently derived checks as well.
2. In a scoped, authorized fitting comparison, use the same data and accepted
   model, assess each route's chain diagnostics, and compare declared posterior and
   predictive summaries with Monte Carlo uncertainty. Independent runs need
   not produce identical draws. Select representative conditions and retain
   failures; do not automatically double the entire evaluation roster.

Both routes must feed the same user-facing diagnostics, figures and saved
reports. Keep differences in installation, cache reuse and chain execution
visible in public backend help. Agreement strengthens implementation evidence;
it does not establish model adequacy, source reproduction or independent
scientific review. ConQuest/TAM comparisons remain a separate exercise in
matching supported response models, scales and estimands across estimators.

Core backend verification must use controlled numerical and synthetic cases
without depending on the Uchihara workbook or an empirical conclusion. Complete
model-equation, category/sign, prior-predictive and common-coordinate checks
before interpreting posterior agreement. Keep observation and prediction units
explicit in likelihood/report output and verify save/reload and figure output
from both routes. When the Uchihara application is undertaken, apply the same
checks to its named empirical comparisons and distinguish rating-level likelihoods
from heldout-recording predictions. The current CmdStan path does not reuse compiled-model caches
and does not wire `cached_fit` or parallel chain execution into the fit path;
document the current requirements and resolve a measured execution blocker
with the smallest existing-path change. A new general cache/scheduler framework
or the historical M0 benchmark investigation is not a prerequisite.

### ConQuest and TAM comparison scope

External measurement-software comparison and same-model backend verification
answer different questions. Retain three separate evidence levels: matching
response equations/parameter meanings; numerical implementation agreement;
and recovery, calibration or practical validity under a declared design.

| Comparison / responsible role | Current evidence | Next deliverable and claim limit |
| --- | --- | --- |
| ConQuest — analyst/maintainer | The [bridge](docs/src/mgmfrm-research-roadmap.md#migration-evidence-and-deferred-contracts-retained-2026-09-14) has version-specific execution records and source-gauge semantic reconstruction for ConQuest 5.47.5, three-category unanchored MFRM RSM/PCM. Destination-gauge alignment and numerical comparison remain unavailable | Finish one unanchored common-model path: map category/step meanings, signs and identification constraints, check probability-preserving translation, assess external convergence, then compare declared estimands. Keep unsupported versions, anchors and broader models explicit; a returned bundle is not direct posterior agreement |
| TAM — analyst with independent review | The [retained comparison](test/fixtures/mgmfrm_tam_direct_agreement_multireplication.json) contains ten selected unidimensional MFRM/PCM jobs, five each at 40 and 100 persons; the primary 100-person comparison gate passed. Despite the `mgmfrm_tam_*` prefix, GMFRM/MGMFRM were not evaluated | Resolve the [review packet's](test/fixtures/mgmfrm_tam_direct_agreement_post_execution_review_packet.json) outstanding independent review/re-execution and pre-execution packet lineage discrepancy without rewriting frozen evidence. Describe the tested family plainly. A future multidimensional comparison first needs a common fixed-loading/scoring model and explicit estimator/scale mapping; historical MFRM results cannot transfer to it |

For these comparisons, distinguish the external marginal maximum-likelihood
estimand from this package's joint Bayesian target, including prior and
uncertainty interpretation. Do not require identical estimates, equate standard
errors with credible intervals, or call interval inclusion coverage. General
ConQuest/TAM multidimensional capability is not proof that the exact proposed
MGMFRM is available there. This supporting work does not replace core model
specification or block unrelated MGMFRM implementation.

### Core equation and prior review

Read [Uto (2021)](https://doi.org/10.1007/s41237-021-00144-w), Sections 5--6.5
and the Appendix 1 code on printed page 451 (PDF page 27), using indexed text,
publisher-rendered equations and the rendered local PDF. This is a focused
equation/implementation review, not a new full-paper empirical replication.
The compensation/structure follow-up also reads the [published Stan code](https://github.com/AI-Behaviormetrics/Multidimensional-GMFRM/blob/master/mult_gmfrm_uto.stan)
and the Bolt and Lall (2003) equations from Zotero (item `Y2GABZ6D`);
the Uto PDF is Zotero item `38TX837G`. The initial Yao and Schwarz abstract
check is now supplemented by the [full-text review below](#yao-and-schwarz-full-text-review-and-adoption-limits).

| Finding | Evidence and consequence |
| --- | --- |
| Response equation agrees within the fixed-Q restriction | `_mgmfrm_source_linear_predictors!` and `src/stan/mgmfrm.stan` use the weighted ability sum, subtract item difficulty, rater severity and item steps, and multiply by `1.7 * rater_consistency`. The zero first logit removes a category-common term and preserves probabilities. This does not validate unrestricted loadings, free correlations or practical recovery |
| Source terminology conflicts with conditional algebra | Uto calls the model non-compensatory; [Yao and Schwarz (2006)](https://doi.org/10.1177/0146621605284537), p. 470, explicitly treats compensatory models, and Equation 4 plus the p. 491 dot-product note establish additive ability aggregation. Uto Equation 6 and Appendix 1 admit exact ability tradeoffs at fixed item parameters. The [focused operation/structure review](docs/src/experimental.md#dimension-aggregation-and-item-structure) separates the dimension dot product, category-step sums and rater product-one constraint. Preserve author terminology as attribution, not a model-behavior claim; do not silently substitute a nonadditive kernel |
| Source within-item structure is not the narrow between-item candidate | Appendix 1 estimates positive loadings in every item-dimension cell without a Q mask. For more than one dimension this is within-item, irrespective of how small some loadings are. The package's pure-Q branch is a restriction; its mixed/within fixed-Q branches remain warning-bearing. Compensation and item structure are separate axes, and source-like unrestricted loading identification remains open |
| Prior equivalence is not established by matching scales | Appendix 1 applies the severity normal density to the complete constrained vector; `_source_fixture_logprior` penalizes only the free coordinates. The [existing prior-asymmetry analysis](docs/internal/archive/roadmap-2026-09-05.md#fixed-q-identification-priors-and-nested-comparison-program) remains applicable, not a newly discovered mathematical issue. The manual calls its all-one setting `unit_raw_prior`, not a reproduction of the source prior. The [decision draft below](#m1-prior-measure-and-identification-decision-draft) also derives the source consistency prior's nonzero log-coordinate mean after the positive-to-log change of measure; source fidelity and exchangeability are different targets |
| Rater relabeling changes the implemented posterior target | The new deterministic block in [generalized_prior.jl](test/generalized_prior.jl) swaps R1/R3 on the same 24 ratings, including an all-1 rater. In separate severity and log-consistency cases it maps `(s,s,-2s)` to `(-2s,s,s)`: matched pointwise likelihoods agree, but the raw log-prior and unnormalized log-posterior each change by `-1.5`. At the zero vector the difference is zero, so it is not an additive normalizing constant. The coordinate permutation has unit absolute Jacobian. This is a density counterexample, not a measured posterior-mean or decision shift |
| Actual ability-prior scale reporting corrected | The no-fit `GeneralizedPrior(person_sd = 2)` counterexample exposed a hard-coded standard-normal claim. The [reporting correction](#actual-prior-reporting-correction) now resolves actual SD across shared consumers and leaves absent-prior checks unrecorded. This repairs metadata, not the numerical prior or scientific identification |
| Rater-report integration is incomplete | `rater_diagnostics` has MFRM/GMFRM methods but no `MGMFRMFit` method. MGMFRM direct posterior and residual infrastructure already exists; the missing convenience report is not absence of severity/consistency estimation. Reuse it after the prior/scale interpretation is explicit, without importing MFRM-only infit/outfit or automatic rater rejection |

**Next decision slice:** with actual-prior reporting corrected below, review
the [prior-measure and identification draft](#m1-prior-measure-and-identification-decision-draft), distinguishing a
constrained normal kernel scale from a desired
direct marginal SD. [Stan's transform reference](https://mc-stan.org/docs/reference-manual/transforms.html)
describes orthonormal zero-sum coordinates and the marginal-variance adjustment;
it is an alternative to evaluate, not a new dependency or an adopted model.
Any numerical replacement requires explicit prior/scale semantics, matching
Julia/Stan targets, cache compatibility and sensitivity checks. Do not silently
change defaults, rescale old draws, rewrite historical fixtures, or treat this
relabeling test as proof of scientific acceptability.

For the all-1 scenario, a low consistency multiplier at fixed finite remaining
parameters flattens category probabilities; it does not specifically encode
always selecting the minimum category. This follows from the implemented
softmax equation. Severity, consistency, item/person assignment, Q support and
prior influence must be examined jointly; no fitted reliability state or
automatic exclusion rule was added.

Verification on 2026-09-07: the existing generalized-prior file passes 73
prior-contract plus 14 relabeling-characterization assertions on Julia 1.12.5
and 1.10.8 (final quiet logs `xrYCu4` and `HIeIUZ`). The existing structural-Q
and model-family files pass 46 + 75 assertions on Julia 1.12.5; the same no-fit
check records the scale-report mismatch and missing MGMFRM rater method
(`ofTmV5`). These are implementation checks, including existing prior-predictive
test draws, not posterior fits, practical validation, or new CI results.
Package source, Stan kernels, priors/defaults, locks and historical evidence
remain unchanged by this review.

The compensation/structure follow-up passes all 75 existing model-family
assertions plus 14 new deterministic assertions on both Julia 1.10.8 and 1.12.5
(quiet logs `a9PDjS` and `M1eVOP`). These check the full three-category vector
for two raters and three ability tradeoffs, a nonzero step and nonunit rater
multiplier, pure-item negative controls, and a finite high-ability example.
The Stan comparison is a source-code review, not a new Stan execution or
cross-backend sampling result. Only this roadmap, the existing experimental
manual and the existing model-family test file change in this follow-up;
the actual-prior reporting correction was the next implementation slice and
is recorded separately below.

### Actual-prior reporting correction

The shared ability-prior metadata now uses the target/fit's `person_sd`.
SD 1 retains the existing standard-normal label; other SDs report a normal
prior with the numeric SD, zero mean, independent dimensions and fixed-prior-
hyperparameter conditioning. Without a supplied prior, scale and pass status
are missing rather than certified. This is not posterior covariance or an
identification proof. Stored sampler diagnostics, target pointwise checks,
full/public diagnostics, artifacts and reports use the same resolver; readers
do not trust stale stored scale rows over `fit.prior`. The research generator's
shared-row call and preview fields were updated, but it was not executed.

Design/source-reference prior and gauge declarations remain unchanged because
the design manifest participates in existing cache keys. Artifacts and report
Q sections label those declarations separately from the resolved fit prior.
The validation protocol's three current regimes all specify `person_sd = 1`,
so its standard-normal reference scale is not a nondefault-fit report. Its
`source_aligned` regime name still does **not** establish full source-prior
equivalence; reconcile that terminology with the next M1 prior decision.

Verification: [generalized_prior.jl](test/generalized_prior.jl) passes 144
assertions on each of Julia 1.12.5 (`uhzelZ`) and 1.10.8 (`BAiuzI`): 87 existing
plus 57 sampler-free reporting assertions, covering SD 0.5/1/2, unknown/stale
metadata, both reader views and artifact hashes. The new checks use fixed
numeric matrices, not posterior sampling; existing prior-predictive checks
remain. The numerical target, prior defaults, cache implementation, design
manifest and historical fixtures are unchanged. No MCMC, Stan execution,
fixture regeneration or CI was performed, and M0/M1 acceptance remains open.
On Julia 1.12.5, fixed-Q and model-family tests also pass 46 + 89 assertions;
the updated generator parses without execution and the changed manual passes
its language check (`tG1FT4`). An additional public-language check found
pre-existing README wording at
lines 321, 323, 331 and 337; README is unchanged by this correction, so that
repository-wide gate is not claimed as passing.

### Yao and Schwarz full-text review and adoption limits

[Yao and Schwarz (2006)](https://doi.org/10.1177/0146621605284537), pp. 469--492,
was read in full, including the appendix, from Zotero item `58X8E8BK`
(PDF attachment `KJDEPPHP`). Key equations were checked in rendered pages;
the indexed-text response stopped before the end, so the remaining pages were
read from the PDF. This is a source review plus local algebra checks, not
BMIRT reproduction, Stan execution, new package regression coverage, or
independent scientific acceptance. The consequences below are our analysis;
they do not assert that every source statement has been validated.

| Topic and source location | Finding and required M1 treatment |
| --- | --- |
| Aggregation and likelihood, Equations 4, 7, 9; p. 491 note | The dot product sums loading-by-ability products. The category-indicator product selects the observed category, and the person/item products form the joint likelihood. None is a product of dimension-specific success probabilities. Keep source attribution, conditional compensation, within/between structure, and practical decision rules separate in the existing contracts/reports; an unresolved operational label must not hide the proven conditional tradeoff |
| Structure and source mapping, pp. 471, 480, 490 | The demonstrated exploratory model does not impose simple structure; it is not validation of the package's pure-Q branch. Map Yao's category logits to Uto's rater multiplier, item difficulty and centered steps, including the explicit `1.7` scale. Yao allows item-specific category counts and has no rater facet in this kernel. Matching this conditional response family is not full-model, prior, mixed-format, or software equivalence; BMIRT/Metropolis--Hastings is not Stan |
| Conditional information, Equations 24, 48--50 | With other parameters fixed, `I_j = Var(Y_j \| theta) a_j a_j'` has rank at most one. For MGMFRM, the corresponding item/rater contribution is `(1.7 alpha_r)^2 Var(Y_ir \| theta, phi) a_i a_i'`, where `phi` fixes item/rater/step parameters. Repeated ratings in the same loading direction can add precision but not new ability directions. Assess loading directions, weak dimensions, and the summed information spectrum over the declared ability region; conditional full rank is not proof of joint item/rater/ability identification |
| Information versus uncertainty, Equations 49--55 | For unit direction `u`, distinguish `u' I u` from `1 / (u' inv(I) u)`. The latter requires a nonsingular matrix and is a local covariance-based approximation with nuisance item/rater parameters fixed, not the joint Bayesian posterior covariance. Name the estimand, conditioning, ability units and uncertainty source. Do not hide singularity with a prior or numerical ridge and report it as likelihood information |
| Identification and priors, pp. 472, 480 | Fixed population covariance does not generally remove likelihood rotation ambiguity. For identity covariance, jointly rotating abilities and loadings preserves their dot products and the ability-normal kernel; small rotations can preserve positive loadings. Loading priors need not be rotation-invariant, so do not infer full-posterior invariance. Review rotation, admissible sign/permutation changes, Q restrictions, transformed-prior measures and report alignment together. Interpret Equation 75's prior scale on the log scale; source-looking scale values do not establish source-posterior equivalence |
| Boundary raters and diverse user decisions | The variance in the information formula is model-implied, not the observed within-rater sample variance. An all-1 rater is not automatically zero-information, unreliable, or removable. Evaluate joint severity/consistency uncertainty, overlap, prior sensitivity and posterior predictions. Separate dimension-specific ability, declared composite scores and joint threshold-event probabilities according to use; a compensatory response kernel does not force a compensatory operational decision rule |
| Source corrections and optional statistics, Equations 47, 61, 65 | Equation 47's intermediate sum omits a minus sign; its final Hessian and Equation 48 agree with re-derivation. The 3PL claim in Equation 61 does not generally hold with positive guessing. Equation 65 supplies a stationary-point condition, not a sufficient global-maximum check. Retain these as review findings, not copied formulas. New 3PL or MID implementations are deferred unless a selected user-facing quantity requires them |
| Model comparison, pp. 480--481 and Appendix Equations 78--82 | The application fixes candidate correlations and counts examinee parameters in its fit-statistic calculation. Do not inherit its AIC parameter count, ordinary chi-square reference, trace-based convergence assessment or iteration budget as package acceptance rules. Predeclare conditional versus integrated prediction, heldout units and target population, check applicable regularity/diagnostics, and assess predictive performance separately from ability/decision calibration |

The full-text review's deterministic examples are reproducible mathematical
checks, not fitted results: for `I = [2 1; 1 2]` and `u = [1, 0]`, the two
information quantities are 2 and 1.5. With 3PL slope 1, location 0 and guessing
0.2, information is `0.1666667` at location 0 and `0.1703856` at its maximizer
near 0.267142, contradicting Equation 61's general claim. With ordinal slope
1 and adjacent thresholds `(-4, 4)`, logits `(0, theta + 4, 2theta)` give
information about 0.0353368 at the stationary point 0 but 0.2503353 at 4;
the center is a local minimum. These examples do not invalidate the correctly
derived M-2PPC response kernel or justify adding a 3PL branch to MGMFRM.

**Proposed stress extension, not an executable roster:** use a small set of
contrasting loading geometries (separated, nearly parallel, weak, and
rank-deficient), distinguish pure/within/mixed Q support, and examine dense
versus sparse overlap and regular versus boundary response patterns. Reuse
the existing [Q-design program](docs/src/mgmfrm-research-roadmap.md#v012-fixed-q-dimensionality-and-q-validation-expansion)
and [response-stress primitives](src/mgmfrm_response_stress.jl); the latter
currently generates a two-dimensional pure-Q design, not these new within-item
cells. Do not silently expand it into a full Cartesian experiment. Select cells
by the failure mechanism and decision they test, retaining rank-deficient
negative controls and separate misspecification/contamination outcomes.

Before M2, fix the needed model restrictions and estimands, make the relevant
algebra checks executable in existing focused tests, then specify per-cell
recovery/coverage, joint-posterior uncertainty, prediction/calibration,
practical loss and failure denominators. Eigenvalue/conditioning summaries
depend on the declared scale; no universal practical cutoff, replication count
or resource budget is adopted here. Review and size the selected cells before
authorizing any fresh evaluation. This planning refinement changes only this
roadmap and leaves the previous test receipts and all execution gates intact.

### M1 prior-measure and identification decision draft

**User-selected research priority on 2026-09-07: treat literal source
reproduction and an exchangeable-rater-prior model as parallel, distinct
scientific models.** Neither is merely a sensitivity setting subordinate to
the other. This selects their research roles, not a new implementation,
default prior, fitting scope or experiment authorization. Retain the current
raw-coordinate prior as the compatibility baseline; it is not silently renamed
as either model. Do not reinterpret `GeneralizedPrior` scales or relabel old draws.

The latest 2026-09-11 clarification prioritizes the Julia core prior/measure
contract independently of the Uchihara application. This section supplies the
derivations for the distinct source/exchangeable models and compatibility checks.
Completing unrestricted Uto reproduction is not a prerequisite for a bounded
core correction. Using a source-derived prior in an adapted application model
remains a restricted comparison, not literal source reproduction. Numerical
prior choices still need explicit specification.

For a prior-only comparison, match the likelihood, Q restrictions, response
scale, data and prediction/decision targets, while retaining each model's
explicit prior measure. Comparing unrestricted source loadings with pure-Q
exchangeable loadings would confound prior and structure. A source-prior model
under a fixed-Q restriction must be labeled a restricted reference, not full
Uto reproduction. Full source reproduction retains its separate loading-scope
and identification requirements; the current guarded API does not supply it.
Scale matching is itself a scientific choice: shared numeric SDs need not
match marginal or contrast uncertainty. Report remaining differences explicitly.

The source check revisited Zotero Uto item `38TX837G`, rendered Appendix 1 on
printed p. 451 (PDF page 27), and the
[author's Stan file](https://github.com/AI-Behaviormetrics/Multidimensional-GMFRM/blob/master/mult_gmfrm_uto.stan).
The PDF declares positive free consistencies and reconstructs the **first**
rater's consistency by the reciprocal product. It applies lognormal densities
to the complete consistency vector. The repository copy omits the positive
declaration bounds; this review does not certify equivalent initialization or
execution. Our derivation below uses the PDF's positive-coordinate measure,
including its change to free log coordinates, not a new Stan run.

Let `n >= 2`, `P = I - 11'/n`, and `C = [I_(n-1); -1']`. Here `s_raw` denotes
the current free-coordinate SD, `tau` a normal/lognormal kernel SD, and `s` a
desired common constrained marginal SD. These are different definitions, not
interchangeable argument names; severity and log-consistency scales are separate.

| Prior option | Induced rater distribution and scientific consequence | Proposed treatment |
| --- | --- | --- |
| Current raw-coordinate baseline | Severity and log-consistency have zero mean and covariance `s_raw^2 C C'`; free marginal variances are `s_raw^2`, the last is `(n-1)s_raw^2`. For `n > 2`, arbitrary rater renaming is not prior-invariant | Compatibility baseline, separate from the two selected scientific models; preserve the relabeling counterexample |
| Literal source measure | Full-vector severity normal kernel gives covariance `tau^2 P`. Source log-consistency has that same covariance but mean `tau^2 (1/n * 1 - e_1)`, where `e_1` marks the reconstructed first rater | Parallel reproduction track; equal log marginal variances do not make this nonzero-mean prior exchangeable. Distinguish full reproduction from a Q-restricted reference |
| Exchangeable zero-sum proposal | For severity and log-consistency separately, `v = s sqrt(n/(n-1)) H z`, with `z ~ N(0,I)`, `H'H = I` and `H'1 = 0`, gives zero mean and covariance `s^2 n/(n-1) P` | Parallel scientific model for raters whose IDs carry no declared prior information; an alternative kernel-SD convention uses `tau H z`. The construction and scale convention still need acceptance before implementation |

The zero-sum covariance and marginal-SD adjustment agree with
[Stan's sum-to-zero transform reference](https://mc-stan.org/docs/reference-manual/transforms.html#sum-to-zero-transforms).
The basis is a coordinate choice, not an additional rater effect. Exchangeable
does not mean independent: pairwise correlations are `-1/(n-1)` under this
constraint. If a future scale is estimated rather than fixed, normalization
must account for `n-1` free dimensions; blindly summing `n` normal log densities
adds an erroneous scale-dependent factor. No hierarchical scale is added here.

Kernel SD keeps pairwise contrast variance at `2 tau^2`; a fixed common
marginal SD gives contrast variance `2 s^2 n/(n-1)`. With different numbers of
raters, stable marginal uncertainty and stable contrast uncertainty are
different goals. Select the convention for the intended decisions, not just
by matching existing numeric scale arguments.

The source-consistency mean is **our change-of-measure derivation**, not a
claim made by Uto. The printed code fixes `tau = 1`; other positive `tau` values
here are an algebraic generalization. Write `z = log(alpha_2:n)` and
`ell = (-sum(z), z)`. The product-one constraint cancels the sum of the
lognormal `-log(alpha)` terms, but the density in free log coordinates uses
the inverse-map Jacobian `abs(det(d alpha_free / d z)) = exp(sum(z))`, as in
[Stan's change-of-variables rule](https://mc-stan.org/docs/stan-users-guide/reparameterization.html#changes-of-variables).
Thus, up to a constant for fixed `tau`,

```math
\log p(z) = -\frac{z^\top(I_{n-1}+11^\top)z}{2\tau^2}+1^\top z+\mathrm{const}_{\tau},
\quad E[z]=\frac{\tau^2}{n}1,
\quad \operatorname{Cov}(z)=\tau^2\left(I-\frac{11^\top}{n}\right).
```

For three raters and `tau = 1`, the full log-consistency means are
`(-2/3, 1/3, 1/3)`, not all zero. For `ell = (-0.8,0.4,0.4)`, reversing rater
labels preserves the quadratic penalty but changes the log-coordinate density
by `-1.2`; the corresponding free-log permutation has unit absolute Jacobian.
This is a prior-density result, not a fitted rater bias or a practical-error
estimate. In particular, it supplies no rule for excluding an all-1 rater.
The standalone source item-loading lognormal does not have this product-one
coupling. Source centered-step normals also differ from the package's free-step
prior, but ordered category positions must not automatically inherit a rater-
exchangeability requirement; settle the blocks separately.

For identification, the retained Yao--Schwarz full text (Zotero `58X8E8BK`,
pp. 472 and 480) motivates separating response invariances from prior
restrictions. The existing fixed-Q test now checks a concrete two-dimensional
example: a small joint orthogonal rotation preserves all ability-loading dot
products, positivity of dense loadings and the identity-normal ability kernel,
but not the independent direct-loading lognormal prior. That rotation violates
a pure-item Q mask. Moreover, the source-style all-active Q has full structural
rank but is **currently rejected** by the duplicate-column gate; warning-bearing
mixed/within fixed-Q support is not unrestricted source-model fitting.
None of these checks proves global or joint identification of an admitted Q.

Before accepting a numerical change: specify the intended Q/correlation scope
and each prior's base measure, scale, centering and admissible label changes;
separately check likelihood and prior/posterior transformations, including
Jacobians. Then require matching Julia/Stan density and gradient checks,
prior-predictive checks, versioned cache/report compatibility, and separately
authorized refit sensitivity for boundary raters and the selected practical
decisions. Preserve named dimensions when reporting ability/composite/joint-
event targets; do not silently rotate estimates to improve recovery. The
exchangeable construction removes this rater-label artifact, not all likelihood
ambiguity, weak information or dependence on substantive prior assumptions.

Verification on 2026-09-07: the existing generalized-prior and fixed-Q files
pass 299 assertions on each of Julia 1.12.5 (`oOGogT`) and 1.10.8 (`a9EWN6`).
These comprise 190 existing assertions and 109 new checks: 99 zero-sum/measure
checks over 2/3/5 raters and SD 0.5/1/2, plus 10 rotation/Q/prior checks.
One density-difference comparison cancels to zero and uses absolute tolerance
`1e-12` for floating-point roundoff; this is not a scientific acceptance margin.
The source-density check compares the lognormal-plus-Jacobian expression with
a completed-square Gaussian kernel, not with a newly executed Stan target.
No dependency was added. Only this roadmap and the two existing test files
change; package source, defaults, caches, fixtures and previous evidence stay
unchanged. No posterior fit, CI, library write or reviewer contact occurred.
Both model specifications, independent review and M1 acceptance remain open.

### Blockwise specification and comparison contract

**Reusable specification: resolve the applicable blocks for each selected model.**
The immediate target is the Julia core contract; the two columns below retain
the distinct source/exchangeable prior targets. Resolve a bounded model slice
without requiring both full research programs or an application study. Use the
source-prior derivation above and existing contracts; record
the chosen value, measure, source revision and unresolved restriction for each
block before proposing a numerical patch. Keep the legacy raw-coordinate model
separately identifiable for compatibility checks, not as a substitute for either
selected scientific model.

| Block | Literal source reproduction | Exchangeable-rater-prior model / comparison control |
| --- | --- | --- |
| Response kernel and categories | Reproduce the additive dimension score, category-step accumulation, rater multiplier and `1.7` convention; bind the printed positive-coordinate declarations to the source revision | Hold these fixed for a prior-only contrast. Declare category labels and step indexing; compensation is a property of this conditional equation, not of the subsequent decision rule |
| Ability distribution | Record source zero mean, unit SD and independent dimensions, together with the loading-scale convention | Specify actual ability SD and covariance restrictions. Hold them fixed in the initial prior-only comparison; a free-correlation model is a separate structural change, not an incidental part of rater exchangeability |
| Loading geometry and dimension identity | Full source reproduction needs its all-positive loading scope and an explicit identification/alignment treatment; the current duplicate-column gate blocks that surface | A matched fixed-Q comparison can be an earlier restricted study, provided both models use the same Q and loading prior. Declare named dimensions, admissible transformations and recovery targets; unrestricted source reproduction remains a separate unresolved deliverable |
| Rater severity | Full-vector zero-sum normal kernel, including the reconstructed coordinate | Select kernel-SD or marginal-SD semantics. Under kernel-SD matching this block can have the same distribution in both models; do not change it merely to make the tracks look different |
| Rater consistency | Positive free-coordinate measure with reciprocal-product reconstruction; retain its derived nonzero log-coordinate mean and distinguished source rater | Specify the centered exchangeable zero-sum log prior and its own scale convention. Record full log means, covariance and contrast variance, transformation Jacobians and the treatment of the distinguished source rater in comparisons |
| Item difficulty and category steps | Record the direct item prior and full centered-step kernel, free dimension and source category convention | Match these blocks when isolating the rater-prior effect. Do not silently keep a legacy free-step prior and call the comparison source-matched. Ordered category labels do not by themselves impose monotone step thresholds or justify exchangeability of category positions |
| Coordinate measure and Jacobians | For every block record free coordinates, base measure, constrained reconstruction, prior density and log-Jacobian, naming what Stan supplies automatically and what must be explicit | Match Julia/Stan in common coordinates. For `a = exp(z)`, a declared density on `a` contributes `log p_a(exp(z)) + z`; a prior directly on `z` needs no extra term. Treat sum-zero/product-one constraints in their free dimension, distinguish constant terms from parameter-dependent terms, and retain scale-dependent normalization if a scale becomes estimated. Avoid missing or double-counted adjustments |
| Persistence and reports | Preserve source identity, restrictions and actual fitted priors, including any deliberate departure from the printed code | Reuse existing target/artifact/report and cache mechanisms, adding only the identity needed to prevent cross-model reuse. Test old-artifact interpretation and unknown-prior handling; no relabeling of old draws, changed defaults or frozen-fixture rewrites |

A prior-comparison proposal should name **one shared structural scope and
one prior contrast**, not cross every prior with every possible geometry.
A Q-restricted source-prior reference versus the exchangeable model can isolate
the declared rater-prior difference; it is not full Uto replication. If the
accepted prior contrast also changes other blocks or scale conventions, report
it as a multi-block comparison and isolate those effects only where a named
claim requires it. Numeric equality of SD arguments is not distributional
matching, and a coordinate reparameterization with its correct Jacobian is not
automatically a different scientific model.

Before protocol freeze, reconcile the existing
[Stage-A protocol](src/mgmfrm_validation_protocol.jl) with this specification.
Its `implementation_reference`, `source_aligned` and `strong_regularizing`
regimes are settings of the current raw-coordinate prior, not implementations
of the selected two-model program. Its pure-Q/identity-correlation primary scope
and secondary-only person-ability target also need explicit disposition.
Update the relevant existing contract/protocol only after that decision; retain
old protocol identities and evidence rather than retroactively reinterpreting
them. No protocol constants or branch guards change in this roadmap edit.

#### Current fixed-Q MGMFRM: executable blockwise measure

The 2026-09-13 slice records the **existing raw-coordinate baseline**, using
the production Julia target and [Stan model](src/stan/mgmfrm.stan). Let `J`,
`I`, `R`, `K`, `D` denote persons, items, raters, categories and dimensions,
and `L` the number of active Q cells. The common parameter vector concatenates
the following blocks in this order. Each raw coordinate has an independent
`Normal(0, s_block)` prior with respect to ordinary Lebesgue measure on the
listed free coordinates. The SDs are fixed hyperparameters.

| Block / raw count | Reconstruction and scale meaning | Julia / production Stan mapping |
| --- | --- | --- |
| Ability / `J*D` | `theta[p,d]` directly; `person_sd` is the dimension marginal SD, covariance `person_sd^2 I` | `:person`; first `J*D` entries of `beta`, person-major then dimension |
| Severity / `R-1` | Free `b[1:R-1]`, last `b[R] = -sum(b_free)`; `rater_sd` is the free-coordinate SD, not a common full-rater SD | `:rater_free`; `rater_offset = J*D` |
| Difficulty / `I` | Direct item difficulties; `item_sd` is their independent SD | `:item`; `item_offset = J*D+R-1` |
| Loadings / `L` | `a[i,d] = exp(z[i,d])` at active Q cells, zero elsewhere; `log_discrimination_sd` is the log SD | `:log_item_dimension_discrimination`; item-major active Q order after difficulty |
| Consistency / `R-1` | Free `ell`, `ell[R] = -sum(ell_free)`, `alpha = exp(ell)`; `log_consistency_sd` is the free log SD | `:log_rater_consistency_free`; after active loadings |
| Steps / `I*(K-2)` | Per item `d[i,1]=0`, free positions `2:K-1`, `d[i,K]=-sum(d_free)`; `step_sd` is the free-step SD, without ordering | `:item_steps`; item-major free steps at the end of `beta` |

The Julia path is `_mgmfrm_unconstrained_blueprint` ->
`_mgmfrm_source_constrained_params_from_unconstrained` -> category logits,
with `_source_fixture_logprior` supplying the normalized raw density.
`_cmdstan_mgmfrm_data` sends this same raw order and per-coordinate SD vector;
Stan declares only `vector[P] beta`, where
`P=J*D+2*(R-1)+I+L+I*(K-2)`. Its `mgmfrm_eta` reconstructs the constrained
effects inside the likelihood, and `beta ~ normal(0, prior_sd)` supplies the
raw prior. The reconstructed severity, log-consistency and final steps receive
no additional independent prior penalties.

**Jacobian contract.** The target is `log L(beta) + sum(log Normal(beta_j;0,s_j))`
in `d beta`. The additional log-Jacobian is zero in every current block.
Stan has no bounded sampled parameter to transform automatically; switching
its `jacobian` flag should leave both density and gradient unchanged. These
statements do not mean the reconstruction derivatives vanish: the last
severity has derivative `-1` with respect to every free severity, and the
last consistency has derivative `-alpha[R]` with respect to every free log
consistency. They enter likelihood gradients through the chain rule.

For a density expressed instead in free positive loading/consistency
coordinates, the inverse-chart log-Jacobian is `-sum(z_free)`; pulling it
back to the existing log chart adds `+sum(z_free)`. Do not replace this sum
with the zero sum of the **full** product-one log vector. The full constrained
vector has redundant coordinates and no ordinary full-dimensional density.
For a zero-sum linear embedding `[v; -sum(v)]`, the volume factor relative to
orthonormal surface coordinates is the constant `sqrt(n)`, not an extra
parameter-dependent prior penalty. This baseline is defined in the free
chart, so no such constant is added to its normalized free normal density.
The source full-vector kernels and the exchangeable proposal above remain
different prior specifications, not corrections implied by this contract.

The runnable check is [mgmfrm_density_measure.jl](test/mgmfrm_density_measure.jl),
included in the generalized test group. It uses a separately written
category-score equation, explicit block counts, six distinct SDs, and
between-item/mixed Q layouts with three raters and four categories. Its eight
points per layout cover zero, a joint nonzero point and each isolated block.
It checks reconstruction derivatives, pointwise likelihoods, normalized priors,
analytic prior gradients, a finite-difference total-gradient reference and the
positive-coordinate change of measure. The opt-in production comparison uses
[CmdStan's standard `log_prob` command](https://mc-stan.org/docs/cmdstan-guide/log_prob_config.html),
compiles the current package Stan source once, and checks both Jacobian flags.
It compares densities after accounting for the known fixed normalizing constant,
density differences and all raw gradient coordinates. No MCMC is required:

```sh
BAYESIANMGMFRM_CMDSTAN_TESTS=true julia --project=. test/mgmfrm_density_measure.jl
```

**Local evidence, 2026-09-13:** Julia 1.12.5/macOS and CmdStan 2.39.0 pass
126 independent-equation/measure assertions and 50 production-Stan assertions.
There are 16 distinct matched points (24 or 25 raw coordinates), evaluated
under both Jacobian flags: 32 Stan density/gradient evaluations. Maximum
absolute error is `1.4211e-14` for normalized log density and `7.1055e-15`
for a gradient coordinate. Both flag settings produce identical output.
Declared tolerances are `atol=1e-9, rtol=1e-10` for densities/differences and
coordinatewise `atol=1e-8, rtol=1e-9` for gradients. The first build failed
because the sandbox disallowed a precompiled-header write in the installed
CmdStan tree; a task-owned copy in writable temporary storage completed the
comparison without altering the installation. No target source, numerical
default, historical fixture or sampler was changed.
The compiled package `src/stan/mgmfrm.stan` SHA-256 was
`2e8f9ebc6b53c5644dbaf4245557bf55a74465a465a6e9935563e05ea3793a25`.
The 351 existing generalized-prior assertions and 44 retained Stan-reference
assertions also pass: 571 numerical/regression assertions in this slice.
This was not a full-suite run.

README links into internal build-review notes were removed while retaining
the actual user-visible build constraints. Public generalized-model help now
explains why `log_posterior` remains a raw-coordinate density when examining
`direct_draws`, and why plotting transformed draws requires no Jacobian.
The source-language gate passes all 19 public files; rendered-HTML and human
usability review were not repeated.

This verifies the tested current raw-prior slice. It does not cover GMFRM/MFRM
production density gradients, free correlation, new source/exchangeable priors,
all accepted Q layouts, other platforms or the minimum Julia version. Existing
historical bridge fixtures remain separately identified reference evidence.
No MCMC, convergence, statistical recovery or source-posterior equivalence
claim follows from this comparison.

#### Normalized source and exchangeable prior reference

The next 2026-09-13 slice specifies normalized **block reference densities**;
it does not add a fitting selector, change `GeneralizedPrior`, or adopt new
defaults. The derivations extend the fixed-scale source reading above.
The [author's Stan file](https://github.com/AI-Behaviormetrics/Multidimensional-GMFRM/blob/master/mult_gmfrm_uto.stan)
was reread for block indexing: severity and consistency reconstruct the first
rater; `category_est` contains `K-1` centered steps, with `K-2` free values and
the last derived. Its normal density is on those `K-1` values, not the
leading zero appended before cumulative summation. The positive consistency
domain follows the previously visually checked printed Appendix, not the
unbounded declarations in that repository copy. Only the unit kernel SD is
literal source specification; other SDs below are our mathematical extension.

For a full zero-sum vector of length `n`, let `m=n-1`, `C=[I_m; -1']`,
`A=C'C=I_m+11'`, and `v` the package's last-reconstructed free coordinates.
All formulas in this section are densities in `d v`. The centered normalized
log density with **kernel SD** `tau>0` is

```math
g_0(v;\tau)=\tfrac12\log n-m\log\tau-\tfrac m2\log(2\pi)
 -\frac{v^\top A v}{2\tau^2},\qquad
\Sigma_v=\tau^2\left(I_m-\frac{11^\top}{n}\right).
```

This is a proper `m`-dimensional Gaussian; `det(A)=n`. Reconstructing the
full vector gives covariance `tau^2 (I_n-11'/n)`. Use `n=R` for severity and
centered log-consistency, and **`n=K-1` for each item's centered steps**.
For source consistency, retain the identity `r_star` of the source's
distinguished rater when changing coordinate charts. Its normalized free-log
density is

```math
g_{r_*}(v;\tau)=g_0(v;\tau)-(Cv)_{r_*}
 -\frac{\tau^2(n-1)}{2n},\qquad
E[Cv]=\tau^2\left(\frac1n1-e_{r_*}\right).
```

The covariance equals that of `g_0`; the mean does not. For the source's
first-rater identity in the package chart, the linear term is **`-v[1]`**.
The familiar `+sum(v)` term is correct only when the distinguished rater is
the reconstructed coordinate. Thus a change from first- to last-reconstructed
coordinates must not silently move the scientifically distinguished rater.
If `u=(Cv)[2:n]` denotes the source's free log coordinates, `u=T v` with
`T=C[2:n,:]` and `abs(det(T))=1`. Densities agree under this map, and
gradients transform by `T'`. For three raters the common-chart log means are
`(-2tau^2/3, tau^2/3)`, with the last reconstructed mean `tau^2/3`.
These are prior moments, not estimated rater effects.

The explicit gradients and scale scores are

```math
\nabla_v g_0=-Av/\tau^2,\qquad
\nabla_v g_{r_*}=-Av/\tau^2-C^\top e_{r_*},\qquad
\nabla_v^2 g=-A/\tau^2,
```

```math
\partial_\tau g_0=-m/\tau+(v^\top Av)/\tau^3,\qquad
\partial_\tau g_{r_*}=\partial_\tau g_0-\tau(n-1)/n.
```

Scale derivatives here verify normalization; they do not introduce an
estimated scale or hyperprior. If a future hierarchical extension is selected,
its conditional prior must retain these scale-dependent terms. Merely adding
a hyperprior to the printed fixed-scale kernel would generally define a
different scale distribution.

| Expression before normalization | Integral over the specified free measure | Required correction to its log density |
| --- | --- | --- |
| Product of `n` centered normal densities on `Cv`, integrated in `d v` | `Z0 = 1 / (sqrt(2pi*n) * tau)` | `-log(Z0)`; omitting it gives one excess `-log(tau)` |
| Source product of `n` lognormal densities on the product-one vector, integrated in its `n-1` free **positive** coordinates | `Zsource = Z0 * exp(tau^2*(n-1)/(2n))` | `-log(Zsource)`; in the source's free-log chart also add the change-of-variables term `sum(u)` |

The source severity block and a centered exchangeable severity block therefore
coincide under kernel-SD matching. A comparison intended to isolate the
consistency prior can hold the source-centered step block fixed in both
models. For a common constrained marginal SD `s`, use
`tau=s*sqrt(n/(n-1))`; contrast variance is `2tau^2`. This agrees with
[Stan's sum-to-zero scale convention](https://mc-stan.org/docs/reference-manual/transforms.html#sum-to-zero-transforms).
Equal numeric raw-coordinate SDs in the legacy model are not this matching.
For steps, symmetric normal penalties do not authorize permuting ordered
response labels or imply ordered thresholds.

**Implementation identity handoff.** Preserve the current raw-prior cache
record and `GeneralizedPrior` meaning. Any new complete target must distinguish
the raw-coordinate baseline, a Q-restricted source-prior reference, and the
exchangeable-rater model. Record the block distributions, explicit scale
convention/values, and the distinguished source **rater ID**, not just its
current sorted index. Coordinate-chart and backend identity remain separate
from that scientific identity. Source/exchangeable severity need no artificial
difference; loading, ability, difficulty and step choices must be matched and
recorded for a consistency-only comparison. A source-like prior under fixed Q
is still not unrestricted source reproduction. No new cache schema is adopted
until an executable target consumes it.

The runnable [Julia reference checks](test/mgmfrm_prior_measure.jl) compare
the closed forms with an independently evaluated multivariate-normal formula,
analytic gradients/Hessians, scale scores, chart changes and relabeling with
and without moving the distinguished rater. Stdlib quadrature independently
checks unit mass and zero integrated scale score in one and two free
dimensions. The [Stan prior reference](test/stan/mgmfrm_prior_measure.stan)
uses positive sampled consistencies and the source first-rater reconstruction,
full-vector `normal_lpdf`/`lognormal_lpdf` calls, and explicit normalizers.
Stan's automatic positive-parameter Jacobian is compared with the common-chart
Julia density; disabling it is a negative control with a known density and
gradient shift. The exchangeable reference explicitly converts its centered
log-coordinate density into a positive-coordinate density before Stan's
automatic transform, as required by the
[change-of-variables rule](https://mc-stan.org/docs/stan-users-guide/reparameterization.html#changes-of-variables).
No likelihood or MCMC is present in that new reference model.

```sh
julia --project=. test/mgmfrm_prior_measure.jl
BAYESIANMGMFRM_CMDSTAN_TESTS=true julia --project=. test/mgmfrm_prior_measure.jl
```

**Local evidence, 2026-09-13:** Julia 1.12.5/macOS passes 666
normalization/formula/derivative/chart assertions and 24 quadrature assertions.
The algebra covers `n=2/3/5` and kernel SD `0.5/1/2`; numerical integration
covers one and two free dimensions on `[-12tau,12tau]` per coordinate with
96-point Gauss-Legendre quadrature. Unit-mass and integrated-scale-score
tolerances are absolute `1e-9`. This finite-domain check is numerical evidence
alongside the Gaussian derivation, not a general-purpose integration guarantee.

CmdStan 2.39.0 passes 180 assertions across `(R,K)=(2,4),(3,3),(5,6)`, three
base scales, both prior choices, two parameter points and both Jacobian flags:
72 density/gradient evaluations. Severity, consistency and step kernel SDs are
respectively `tau`, `0.8tau`, and `1.3tau` to detect block-scale interchange.
Explicit `lpdf` calls retain normalizing constants under `log_prob`'s
`propto=true`, so the test compares absolute densities as well as gradients
after mapping to the common chart. Maximum absolute differences are
`2.6646e-15` in log density and `2.4425e-15` in gradient coordinates;
tolerances are `atol=rtol=1e-10` for density and coordinatewise
`atol=1e-9, rtol=1e-10` for gradients. The new Stan reference SHA-256 is
`fb880b171721eb39c19b76918cbd80598f8e8f879428b3eca8175b9bb2d7f0aa`.
It was compiled in a task-owned writable copy of CmdStan, subsequently removed.

The 126 existing raw-measure checks also pass, giving 996 assertions in this
slice. The initial test attempted to differentiate the package's fixed-Float64
normal SD argument; those two kernel-scale checks now use finite differences,
preserving the production helper's fixed-scale contract. Production priors,
likelihoods, caches and historical fixtures were not changed. Neither a full
suite nor MCMC was run; other platforms and the minimum Julia version were
not tested. These block references alone do not implement either new prior in
the fitting paths or establish statistical validity. The following slice
integrates the complete densities, retaining the sampling boundary.

#### Complete fixed-Q normalized prior targets

The next 2026-09-13 slice implements
[`_MGMFRMNormalizedPriorLogDensity`](src/mgmfrm_normalized_prior.jl), an
unexported complete Julia density. It consumes the existing validated fixed-Q
MGMFRM specification, requires all six scales explicitly, and accepts either
`:source` with an explicit observed `source_rater` ID or `:exchangeable` with
no distinguished rater. The base target supplies the same snapshot, coordinate
layout, `1.7` likelihood and fixed identity correlation. Ability, difficulty
and log-loading priors remain independent normals. Severity, log-consistency
and each item's steps use the normalized centered kernels above; source
log-consistency additionally retains its distinguished-rater linear term and
scale-dependent normalizer. Source SDs other than one and fixed-Q loading
restrictions remain declared adaptations, not unrestricted source reproduction.

The implementation reuses `_source_fixture_logprior` and adds, for each
centered block with `m` free entries, the exact log-density correction
`log(m+1)/2 - (sum(v)/tau)^2/2`. This avoids subtracting two potentially
infinite prior densities. It exposes ordinary `LogDensityProblems` density
and dimension methods, `initial_params`, and `logprior` for this private type.
No copied likelihood, new dependency or runtime work on package import is
introduced.

`_mgmfrm_normalized_prior_record` records the versioned prior schema,
source/exchangeable choice, scale convention, coordinate measure, six actual
scales and source-rater **ID**. `_mgmfrm_normalized_prior_identity` combines
that record with the existing canonical design identity. The in-memory
record constructor requires an expected identity and rejects unknown fields,
schemas/measures, missing IDs, invalid scales, changed priors and mismatched
designs. It reads no file and reuses no fit cache. Changing a caller's data
after construction cannot alter the target's validated snapshot. These checks
are compatibility checks, not authentication of external artifacts.

The [production MGMFRM Stan program](src/stan/mgmfrm.stan) now contains the
same three explicit prior branches. The ordinary adapter supplies
`prior_model=0, source_rater=0`, retaining the legacy raw-coordinate target.
The private normalized adapter supplies mode 1 (source) or 2 (exchangeable)
and the resolved source index. All branches reuse `mgmfrm_eta` and its
generated pointwise likelihood. The normalized branches require positive,
common SDs within each centered block and reject inconsistent prior/reference
selectors and non-finite source normalizers. Stan still samples unconstrained
`beta`, so its automatic Jacobian flag adds nothing in this parameterization.
The earlier positive-coordinate Stan prior reference remains an independent
change-of-measure check.

**Compatibility boundary:** the production Stan source/hash and its data
schema changed; older manually retained production-Stan JSON inputs require
the two explicit raw-mode fields or regeneration through the adapter. Existing
Julia prior defaults and cache meanings are unchanged. No historical fixture
was regenerated. A fresh compile is required under the existing no-reuse
build policy. Neither the ordinary `Experimental.fit` prior argument nor its
cache route accepts these new private targets/records. At this density-only
slice there was no saved-result or MCMC route; the subsequent private
integration is described below. There is still no public selector or full
source-model claim.

The extended [density test](test/mgmfrm_density_measure.jl) checks complete
priors against an independent multivariate-normal formula, complete gradients,
record reconstruction/rejection, source-ID snapshot behavior and relabeling
of the actual ratings. Source consistency is exercised with first, middle
and last distinguished raters; exchangeable and unit-SD source controls
share the same likelihood. Production Stan comparisons include both pure and
mixed Q, zero/joint/isolated-block points and both Jacobian flags. Invalid Stan
data exercise its selector, block-scale and source-normalizer rejection paths.
**Local evidence, 2026-09-13:** Julia 1.12.5/macOS and CmdStan 2.39.0 pass
126 retained raw-target assertions, 532 new complete-target/identity assertions
and 311 production-Stan assertions. The Stan check evaluates 192
density/gradient rows: two Q layouts, one raw and five normalized settings,
eight parameter points, and both Jacobian flags. Five normalized settings are
exchangeable, source with each of three rater IDs, and a unit-SD source
reference. Maximum absolute differences are `1.4211e-14` in normalized log
density and `7.1055e-15` in gradient coordinates. It retains the earlier
`atol=1e-9, rtol=1e-10` density/difference tolerances and coordinatewise
`atol=1e-8, rtol=1e-9` gradient tolerances. Eleven malformed Stan payloads are
rejected. The compiled source SHA-256 is
`d53f4aff0026e0b30f494595abd48b6bdf71a8b83acf8c5dc0cb2a0e0a57d018`.

The existing 690 prior-reference, 78 backend-contract, 4,617 synthetic
cache-containment and 431 synthetic producer/control assertions also pass:
969 density/identity/input assertions plus 5,816 related regression assertions.
Actual compilation/log-probability evaluation used a task-owned CmdStan copy;
the cache and producer probes remain synthetic evidence. No MCMC or full-suite
run occurred. The complete-target examples cover three raters, four categories
and two dimensions; other sizes have block-reference evidence, not a new
complete-target evaluation. Minimum Julia, other platforms, saved fits,
sampler/result parity, recovery and scientific validity remain unverified for
the new priors. The temporary CmdStan copy was removed after verification.

#### Normalized-prior sampling and saved results

The subsequent 2026-09-13 slice connects both normalized targets to actual
NUTS execution in [`mgmfrm_normalized_prior.jl`](src/mgmfrm_normalized_prior.jl).
`_mgmfrm_normalized_prior_sample(target; backend=:advancedhmc, ...)` uses
the existing Julia sampling loop; `backend=:cmdstan` uses the existing
compile/chain/CSV route and the same production MGMFRM program. Shared runners
now accept the private wrapper through its dimension, density and raw-vector
validation methods. Existing generalized callers retain their defaults and
concrete public result types. No sampler loop, dependency or public fitting
selector was added.

The normalized CmdStan parser retains the generated `log_lik` comparison,
evaluates each draw under the normalized Julia target, and checks `lp__`
after restoring the independent-normal constants omitted by Stan. This last
check detects a wrong prior branch even when pointwise likelihoods agree.
Stan's original `lp__` remains in sampler statistics. Shared adapters preserve
chain/phase error context.

The private result contains `record`, raw/direct parameter names,
`public_fit=false`, and `diagnostics`. Its
`bayesianmgmfrm.normalized_fixed_q_samples.v1` record retains the specification,
normalized-prior record, target identity and complete sampler run: raw draws,
normalized log densities, chain/iteration IDs, seed and effective controls,
backend, initial state, sampler telemetry and chain summaries. The prior
record carries actual scales and the original typed source-rater ID. These
posteriors are never represented as a legacy `MGMFRMFit` or raw-coordinate
`GeneralizedPrior` fit.

`_save_mgmfrm_normalized_prior_samples(path, result)` and
`_load_mgmfrm_normalized_prior_samples(path; expected_identity=...)` use
Julia's existing `Serialization` dependency for trusted records in the same
analysis environment. The saved payload contains the primitive record;
direct parameters, pointwise likelihoods and diagnostics are rebuilt on load.
Loading requires the caller's expected target identity, validates the schema,
prior and canonical data/design, and verifies a content hash covering the run
and prior metadata. It also checks dimensions, finite values, chain order,
effective backend controls, initial and retained normalized densities,
sampler-stat correspondence and chain summaries. Deliberately rehashing
inconsistent records does not bypass these semantic checks. The specification
is covered by canonical design identity, not generic object display. This is
compatibility/corruption detection, not authentication or a safe reader for
untrusted serialized objects; cross-version archival portability is untested.

Saving validates before publication. The existing fit-cache temporary-file,
hardlink and native-rename implementation is extracted into
`_save_serialized_record` and shared by both callers. Failed writes preserve
existing files, and overwrite is refused by default. Ordinary `load_fit_cache`
rejects this distinct schema. Derived diagnostics are not duplicated in the
file or substituted for the underlying draws.

The [runnable test](test/mgmfrm_normalized_samples.jl) uses 24 ratings,
two persons, four items, three raters, four categories and two dimensions.
Exchangeable priors use a pure Q and integer rater IDs; source priors use a
mixed Q and a distinguished middle rater with a Symbol ID. Each backend uses
2 chains, 10 warmup and 12 retained draws per chain, seed 9173, jitter 0.02,
initial step 0.03 and maximum depth 4. The six kernel SDs are
`(0.7,0.4,0.6,0.3,0.35,0.5)` in the existing six-block order. These are
operability inputs, not a chosen scientific prior. Tests check every retained
normalized density and pointwise likelihood, direct constraints, typed-ID and
full-run round trips, rebuilt diagnostics, schema/identity/content and semantic
rejection, and preservation of existing files on rejected save. A separate
synthetic CSV check preserves correct draws/likelihoods while changing `lp__`
to verify prior-mismatch rejection.

**Local evidence, 2026-09-13:** Julia 1.12.5/macOS and CmdStan 2.39.0 pass
608 assertions: 18 input/public-boundary, 6 synthetic parser, 268 Julia
sample/save/load and 316 actual CmdStan sample/save/load checks. Four fits
retain 96 draws in total. The deliberately short fits retain diagnostic
warnings; successful run/save/load establishes operability, not convergence,
posterior agreement, parameter recovery or application validity. The first
run's eight failures were incorrect exception-type expectations in the test;
the shared validator correctly kept `ArgumentError` with chain/phase context.
Those expectations were corrected before the final run.

Related regression checks pass 7,723 assertions: 658 complete-density/identity,
690 prior-reference, 78 backend-contract, 1,249 fitting-boundary, 4,617
synthetic cache-containment and 431 synthetic producer/control checks.
Total: **8,331 assertions** in the final bounded checks. The regression includes
legacy short fits and serialization failure/race preservation; the cache and
producer probes remain synthetic. Fixed Q, `1.7`, identity latent correlation
and declared scale adaptations are unchanged; the production Stan source
hash remains `d53f4aff0026e0b30f494595abd48b6bdf71a8b83acf8c5dc0cb2a0e0a57d018`.
The generalized shard now executes two short Julia fits; actual CmdStan
sampling requires `BAYESIANMGMFRM_CMDSTAN_TESTS=true`. No work occurs on package
import. There was no full-suite, minimum-Julia, other-platform or new
distribution/runtime-budget assessment. The task-owned CmdStan copy is
removed after verification; no application data or historical fixture changed.

#### Fixed-Q posterior comparison receipt

The next 2026-09-13 slice completes the single predeclared experiment in
[`normalized-prior-backend-comparison.md`](docs/internal/normalized-prior-backend-comparison.md).
Its [manual runner](scripts/run_normalized_prior_comparison.jl) reuses the
existing dense synthetic-data generator, private normalized sampler/results,
rank-normalized diagnostics, statistic-specific MCSE and serialization helpers.
It adds no production dependency, export, likelihood or ordinary-test MCMC
budget. The [manual synthetic decision test](test/normalized_prior_comparison.jl)
passes 52 assertions before execution. Source and exchangeable priors are
compared independently on the same pure-Q, 72-response, two-dimensional case,
using four chains per backend and 1,500 retained draws per chain: four fits
and 24,000 retained draws in total.

All four fits meet the frozen diagnostic criteria. Across raw/direct
parameters and six draw-wise contrasts, maximum R-hat is 1.00259, minimum
bulk ESS is 3226.3 and minimum tail ESS is 3511.5; all chains have E-BFMI above
0.8855, with zero retained divergences or depth hits. Of 640 mean/SD/quantile
comparisons, 639 satisfy both the 4.5-combined-MCSE screen and the 0.3-posterior-SD
error-inclusive resolution requirement. The source target passes all 320
rows; the exchangeable target retains one resolution hold. Its R2 consistency
90% quantile differs by -0.01761 (CmdStan minus Julia), with combined MCSE
0.00869. The resulting bound is 0.30478 SD, so the overall decision remains
**unresolved** despite passing diagnostics and no discrepancy-screen failures.
Thresholds, seeds and draw budgets were not changed after inspecting results.

All four sample records are saved and re-read before scoring. Source and
file hashes remain consistent; independent Python arithmetic reproduces all
640 comparison decisions. Full local records remain under git-ignored
`results/normalized-prior-comparison/20260913-fixed-q-01/`; the internal note
contains the durable human-readable receipt. Evidence is local to Julia
1.12.5/macOS, CmdStan 2.39.0 and this fixed model/data/scale choice. It is not
full-distribution equality, general backend equivalence, recovery, minimum-
version/other-platform acceptance or application evidence. Warmup-event and
other remaining failure boundaries are unchanged. The task-owned CmdStan copy
is removed after verification. The subsequent performance work below does
not discard or change this unresolved run.

#### Saved-result hash cost and compatibility receipt

The subsequent 2026-09-13 slice profiles one retained 6,000-draw Julia record
without fitting. SHA-256 over canonical `CodeUnits` takes 68.72 seconds;
run validation and diagnostic tables take 0.93 and 2.09 seconds. A separate
stdlib-only reproduction isolates the input-format cost. The shared cache
hash and seven fit/report hash sites now use `sha256(IOBuffer(text))` over
the same bytes. No canonicalization, target identity, density, draw, chain,
diagnostic or atomic-publication check is removed or altered.

The final repeat profile records 0.087 seconds for hashing, 2.00 for validated
save and 1.93 for validated load, versus 68.72/70.35/74.80 previously.
These are one local before/after pair, including JIT and profiler overhead;
they are not portable performance guarantees or new sampler benchmarks.
The in-memory draws, diagnostic tables and all 64 parameter/contrast
summaries match the pre-change serialized reference exactly. Re-reading
all four Julia/CmdStan records also reproduces the original hashes,
diagnostics, summaries and 640 comparison rows exactly: still 639 accepted
and one unresolved. Input files remain byte-identical.

The bounded regression passes **1,658 assertions**: 65 cache/report byte
compatibility, 292 normalized-prior Julia/parser/save-load, 1,249 fitting
boundary and 52 comparison-decision checks. These include Unicode, SHA
block/stream boundaries, corruption rejection and serialization failure/race
preservation. Only existing tiny Julia operability fits run; there is no new
CmdStan or posterior-comparison MCMC, full suite, minimum-Julia or other-platform
validation. The manual [profiler and saved-result verifier](scripts/profile_normalized_prior_results.jl)
add no package load work or public API. Timings, reproduction commands and
local artifact hashes are in the [comparison note](docs/internal/normalized-prior-backend-comparison.md#saved-result-performance-receipt-2026-09-13).

#### Fixed-Q precision follow-up receipt

The next 2026-09-13 slice executes the predeclared 6,000-draw-per-chain
follow-up: four fits, four chains each and **96,000 retained draws**. The
existing manual runner gains one explicit `--precision-followup` switch,
reusing the original fitting/scoring loop and preserving its initial default.
The new protocol records verified hashes of the initial receipt and unchanged
model/data/scale/gate identities before the first sampler call. The manual
decision test passes 57 assertions; no production source or public API changes.

**All 640 comparisons satisfy the unchanged criteria**, 320 per prior, and
all four fits pass retained-draw diagnostics. Across all quantities, maximum
R-hat is 1.00081, minimum bulk ESS is 14079.4 and minimum tail ESS is 16285.7.
Every chain has E-BFMI above 0.9461, with zero retained divergences or depth
hits. Maximum absolute discrepancy is 3.30633 combined MCSEs (limit 4.5);
maximum error-inclusive difference is 0.15226 posterior SD (limit 0.3).
The formerly held exchangeable R2 consistency 90% quantile has estimates
1.04296/1.04373 for Julia/CmdStan, combined MCSE 0.003887 and bound 0.09935 SD.
No extra fit, seed change, cutoff change or draw pooling follows the outcomes.

Each result is saved, re-read, validated against its target and checked for
identical retained runs and actual planned controls/seeds. A separate Python
arithmetic/file check reproduces all 640 decisions and verifies the frozen
protocol, source hashes and sample bytes. The original trial's JSON/JLS files
remain byte-identical and its unresolved receipt is retained. Local records
and exact runner/verifier snapshots are under git-ignored
`results/normalized-prior-comparison/20260913-fixed-q-precision-01/`;
the [execution note](docs/internal/normalized-prior-backend-comparison.md#precision-follow-up-execution-receipt)
contains the durable receipt. The task-owned CmdStan 2.39.0 runtime copy is
removed after completion.

This closes the selected same-target marginal/contrast precision check on
Julia 1.12.5/macOS and CmdStan 2.39.0. It does not establish whole-joint
equivalence, recovery/calibration, other Q/data/scales, source-paper reproduction
or application validity. No full-suite, minimum-Julia or other-platform run
is added. M1 remains open; the warmup slice below follows this comparison,
without promoting the private prior selector.

#### Normalized-prior warmup telemetry and saved-result compatibility

The following 2026-09-13 slice adds opt-in recording to the shared generalized
AdvancedHMC and CmdStan runners. The private normalized-prior sampler enables
it by default. Existing public callers retain their current behavior; the
likelihood, prior, sampling controls and public exports do not change.
Julia retains the library's warmup output long enough to extract compact event
rows, then indexes retained draws after warmup. CmdStan writes warmup rows and
the parser verifies the adaptation boundary and both row counts before using
only retained rows for posterior evaluation. Recorded events cover divergence,
maximum depth and nonfinite log density, with chain and warmup iteration.

Separate `warmup_diagnostics` rows distinguish `recorded`, `not_run` and
`not_recorded`, including expected/observed counts. They add no warmup R-hat,
ESS or pass/fail rule. Missing historical telemetry is never inferred to be
zero. Private sample schema v2 requires and hashes warmup event rows; v1
remains readable and keeps its original hash. Semantic checks reject incomplete
coverage, wrong chain/iteration layouts, invalid event fields and schema/data
mismatches even after a record is deliberately rehashed. Failed saves preserve
the existing file. No new public cache schema is introduced.

Final bounded checks cover **7,106 assertions**: 731 normalized-prior checks
including actual Julia/CmdStan fits, plus 6,375 existing backend, fitting-boundary
and synthetic cache/producer checks. The initial 292 normalized-prior assertions
were also run before the expanded 731; they are not counted twice here.
Seven short fits per backend cover both priors with recording on/off and one
zero-warmup case. Retained draws, log densities, chain/iteration labels, sampler
statistics and posterior diagnostic tables match exactly within each backend.
Synthetic checks exercise warmup-only divergences/nonfinite values, CSV phase
boundary errors, retained-only density evaluation and fatal interruption
propagation. These are operability checks, not convergence evidence.

The four historical precision-trial files (96,000 draws) reload successfully
and reproduce every original summary and all 640 decisions. Input bytes and
content identities remain unchanged. The receipt and logs are retained under
`results/warmup-telemetry/20260913-fixed-q-01/`; the
[internal note](docs/internal/normalized-prior-backend-comparison.md#warmup-telemetry-execution-receipt-2026-09-13)
records reproduction commands and scope. Validation is local to Julia 1.12.5,
AdvancedHMC 0.8.5 and CmdStan 2.39.0 on macOS. The owned CmdStan runtime copy
is removed. No full suite, minimum-version/other-platform run, new precision
study or native cancellation experiment is added. The following slice connects
public fit diagnostics and caches; report presentation and interruption-time
partial telemetry remain open.

#### Public fit warmup diagnostics and cache compatibility

The following 2026-09-13 slice enables warmup collection on ordinary
AdvancedHMC and CmdStan `fit`/`Experimental.fit` for MFRM, scalar GMFRM and
fixed-Q MGMFRM. `sampler_diagnostics(fit; phase = :warmup)` retrieves compact
chain summaries; its retained default and posterior diagnostics remain
unchanged. No fit struct layout, public export, dependency, prior, production
Stan model or cache request identity changes. The existing sampler metadata
carries the summaries through v1 fit-cache save/load and full fit artifacts.
Turing, random walk and older positive-warmup fits return unavailable coverage;
zero warmup is recorded as not run. Cache save/load reject malformed summary
metadata and failed saves preserve an existing destination.

The focused check passes **322 assertions**, including nine short fits per
NUTS backend and one each for Turing and random walk. It verifies exact
recording-on/off retained draws, sampler statistics and posterior diagnostic
outputs in all three families, zero-warmup behavior, both cache coverage states
and malformed metadata rejection. The broader regression passes **6,838**
assertions, including 33 checks that three actual pre-change Julia caches
remain byte-identical, load under their original keys, and match fresh retained
output/diagnostics. The distinct final count is **7,160**; short fits assess
operability and compatibility, not convergence or recovery.

The initial focused run stopped at the existing CmdStan cache-reuse guard
after its 159 Julia checks passed. The test harness now gives every fit a new
empty build directory; the complete rerun passed without changing that guard.
README and fitting help describe phase selection, coverage, cache refresh and
CmdStan's existing build-directory requirement. The
[internal receipt](docs/internal/normalized-prior-backend-comparison.md#public-fit-warmup-integration-2026-09-13)
records local artifacts, reproduction and limits. This does not close M1,
full-suite/CI runtime acceptance, minimum-version or other-platform validation.
The report slice below supplies dedicated presentation; interruption-time
partial telemetry and unsupported-backend recording remain separate work.

#### Warmup report presentation and legacy output compatibility

The following 2026-09-13 slice adds `warmup` to the existing fit-report section
and public-projection registries. The section uses the existing diagnostic API
and captured-error policy. Structured/public reports, Markdown, JSON tables
and bundles now carry chain coverage and event counts automatically. An
explanation distinguishes observed history, no requested warmup and unavailable
counts; `computed` records reporting success, not adaptation quality. Fixed
warmup column order preserves that table's appearance after JSON reload.
Retained convergence diagnostics and warning aggregation are unchanged.

The focused deterministic report checks pass **211 assertions** across MFRM,
GMFRM and fixed-Q MGMFRM with AdvancedHMC/CmdStan backend labels. They verify
nonzero adaptation events without added retained warnings, all output forms,
missing/zero distinctions, captured invalid metadata and strict error modes.
These labels do not constitute native backend execution. The existing
completeness/hash/prior checks and manual legacy checks pass **506 assertions**;
the distinct final count is **717**. Two actual pre-change full/public bundles
retain their file bytes and load with their original hashes. New reports from
three historical Julia fit caches correctly show unavailable warmup history.

An initial whole-Markdown equality assertion exposed pre-existing generic
column-order and full-report hash-representation differences. The final check
verifies the new warmup preview and all serialized rows; the following slice
addresses general report column stability. The
[internal receipt](docs/internal/normalized-prior-backend-comparison.md#warmup-report-presentation-2026-09-13)
records commands, local files and the stopped check. No new sampler validation,
CmdStan compilation, prior/model change or M1 acceptance follows from this
reporting slice. Full-suite, fresh-HTML and other-platform validation remain
separate.

#### Shared report and dossier column order

The following 2026-09-13 slice fixes the shared Markdown field resolver.
Identifiers, sampler coverage, estimates and uncertainty have a common readable
order; other fields sort by name. Full/public reports and dossiers now retain
that order after JSON reload. Warmup uses the same mechanism. Existing explicit
metadata/warning columns, public filtering, serialized rows and hash definitions
are preserved; older saved Markdown files are not rewritten.

The final checks pass **516 assertions**: column/dossier checks 36, expanded
three-family/two-backend-label warmup reports 223, report completeness 69,
hash byte compatibility 65, and manual historical-report/fit checks 123.
The latter read two actual old bundles and three historical Julia fit caches,
verify table values and hashes, and preserve all input file bytes. These are
reporting checks; no native CmdStan execution or new posterior validation is
claimed. JSON numeric spelling and full typed hash labels still need not match
whole-Markdown bytes across representations. The
[receipt](docs/internal/normalized-prior-backend-comparison.md#report-column-order-2026-09-13)
records the focused test corrections and reproduction commands. Julia 1.12.5
with `--compile=min` was used; full-suite, fresh-HTML and other-platform checks
remain open. The next task returns to the Julia sampling failure boundary.

#### Sampling-call failures and automatic cache preservation

The following 2026-09-13 audit confirms the existing sampling/result/cache
control flow with **131 additional assertions**. AdvancedHMC completes a first
chain and then fails after one warmup or one retained transition in chain 2,
for MFRM, GMFRM and fixed-Q MGMFRM. Ordinary errors retain the cause/backtrace
and chain/stage; constructed interruption, out-of-memory and stack-overflow
exceptions propagate unchanged. Automatic cache creation and refresh are tested
through a test-owned seeded RNG wrapper; a failure writes no new cache and
preserves an existing valid cache's exact bytes. A synthetic CmdStan command
exits on chain 2 after chain 1's output is accepted; no third command or parser
call for the failed chain occurs, and its stage/reason contract is retained.

The complete fitting-boundary file passes **1,380 assertions** on Julia
1.12.5/macOS with normal compilation (1,249 existing plus 131 added). No sampler
or cache implementation change was required. The public fitting help and
`cached_fit` docstring now explain cache preservation and the limit of the
`sampling` phase label. The
[receipt](docs/internal/normalized-prior-backend-comparison.md#sampling-failure-and-cache-publication-2026-09-13)
records test seams, initial harness corrections and source/evidence hashes.
Constructed exceptions do not test live SIGINT, actual resource exhaustion or
native CmdStan cancellation; the delayed tests use AdvancedHMC, with the older
Turing startup-fault checks retained. No new posterior-validation claim, M1
acceptance or full-suite/minimum-version/other-platform pass follows.

#### Minimum Julia version: recent contract verification

The 2026-09-13 check uses Julia 1.10.8 and the existing versioned manifest,
including AdvancedHMC 0.8.6. **2,852 assertions pass**: fitting boundaries 1,380,
reports/hash compatibility 393, historical JSON reports 26, public warmup/cache
322 and private normalized-prior records 731. The last two include 16 native
CmdStan short fits with `--compiled-modules=yes --pkgimages=yes --compile=min`.
Recording enabled/disabled preserves retained draws and diagnostics; fresh
records retain warmup metadata through save/load. Historical cross-version
reads cover portable JSON reports, not Julia binary fit caches.

Normal compilation passes the complete boundary file, including Turing. The
larger normal-compilation sampler run was manually stopped after about 25
minutes, after the AdvancedHMC portion passed; its CmdStan portion has no
completion result. The termination stack points into LLVM, without identifying
the root cause. Disabling compiled modules separately exposes a Turing world-age
error. Both attempts remain in the
[receipt](docs/internal/normalized-prior-backend-comparison.md#minimum-version-verification-2026-09-13)
and their repeated passes are excluded from the final count. Package sources,
tests, Project and both manifests remain unchanged. This verifies bounded
functional contracts under the recorded flags, not full-suite, runtime-budget,
other-platform, statistical or release acceptance. The compilation observation
was investigated in the follow-up below.

The 2026-09-14 follow-up isolates excessive specialization on nested cache
record types in `_check_fit_cache_record` and `_save_serialized_record`. Their
bodies remain unchanged; only compiler annotations limit specialization and
inference on the record argument. In fresh Julia 1.10.8 processes using the
same saved GMFRM record, structure checking falls from 75.73 to 0.04 seconds
and atomic serialization from 83.63 to 0.64 seconds. The 127,258 serialized
bytes are identical. These are local first-call measurements including JIT,
not sampler speed or CI runtime acceptance. Julia 1.10.8 passes the same 2,852
assertions with normal compilation; a fresh standalone warmup/cache run also
passes all 322 assertions in 147.70 seconds. See the
[follow-up receipt](docs/internal/normalized-prior-backend-comparison.md#cache-record-compilation-2026-09-14)
for normal-compilation regression results and retained incomplete attempts.
The separate Julia 1.12.5 report run reaches its 900-second limit after the
first four files pass 1,944 assertions. Its remaining 357 report assertions
pass with `--compile=min`; normal-compilation report runtime remains open.
This does not reopen the whole M0 matrix before the first figure.

### Practical acceptance and mechanism-selected stress

The user prioritizes **conditions under which use is practically acceptable**,
for diverse users and with Bayesian uncertainty available. Propose a small
set of decision profiles, not one universal cutoff or a compulsory feature
bundle. For each selected profile specify the target population, estimand,
conditioning, action/loss, tolerance and acceptable uncertainty before looking
at evaluation results.

The 2026-09-21 [application-informed packet](docs/internal/applied-mgmfrm-acceptance.md)
concretizes the first use as descriptive multidimensional assessment, with
rater monitoring and generalized-model benefit as distinct questions. It links
each estimand to a design contrast, information unit, prediction task and
reportable conclusion. The current application evidence includes two words
observed for only one speaker and substantial differences in words per speaker;
many ratings therefore do not automatically justify item-specific loading
estimation or comparisons of unadjusted person means. No practical cutoff,
new fit or scientific acceptance is implied. The packet's application-specific
model A0 is a review candidate; it does not supersede the existing core targets.

Select profiles by the reusable package claim, not the available Uchihara data.
That application can later exercise trait/rater interpretation and prediction;
it does not itself justify pass/fail, rater-sanction or general proficiency
claims. The profiles below are options for a bounded validation design, not a
compulsory cross-product of features and conditions.

- **Individual assessment:** named dimension abilities, a declared weighted
  composite, or a joint event such as all required dimensions exceeding their
  cutoffs. Obtain joint events from joint posterior draws, not products of
  marginal probabilities; an additive response model does not require a
  compensatory pass rule. Include an indeterminate/review outcome when posterior
  uncertainty or model sensitivity exceeds the profile's accepted limit.
- **Rater and item monitoring:** posterior severity/consistency contrasts,
  category behavior and predictive consequences, conditional on assignment and
  prior choice. An all-1 rater is a diagnostic scenario, not a predeclared
  unreliable class; distinguish sparse information from predictive misfit and
  do not automatically delete, downweight or sanction the rater.
- **Prediction:** declare heldout units among supported persons/items/raters,
  predictive event weights and decision loss; compare integrated predictions,
  calibration and uncertainty. New-facet prediction remains out of scope unless
  its population model and implementation are separately selected.

Keep convergence/Monte Carlo diagnostics, likelihood information, posterior
uncertainty and practical loss as separate report fields. A finite posterior
under a proper prior must not conceal singular likelihood information. A
practical conclusion belongs to a model, profile and tested domain; disagreement
between the two models is an outcome to quantify, not permission to select the
more favorable answer after evaluation.

Select the smallest cell set that distinguishes these mechanisms; retain an
explicit expected rejection or inconclusive outcome for negative controls:

- **Prior/label effects:** matched data and geometry, informative versus sparse
  ratings, rater-ID permutations and selected rater counts. Declare how source
  distinguished-rater status moves under a permutation. Check exchangeable
  invariance separately from the expected source/legacy label sensitivity;
  these counterexamples do not yet measure posterior decision shifts.
- **Geometry and assignment:** separated, near-parallel, weak and rank-deficient
  loadings; pure versus selected within/mixed Q; sufficient, sparse and
  disconnected overlap. Separate rank/identification checks from practical
  precision and distinguish wrong-Q fits from well-specified recovery.
- **Boundary responses:** all-minimum raters, all-maximum persons and unused
  categories, reusing the [existing stress generator](src/mgmfrm_response_stress.jl)
  where supported. Distinguish model-generated extremes from deterministic
  contamination. Do not request simultaneous all-minimum/all-maximum patterns
  at a shared observation; the existing combined case uses nonoverlapping
  targets. New geometry cells need their own checked generator mapping.
- **Calibration versus robustness:** under each model, prior-generated
  calibration and fixed-truth recovery answer different questions. Use common
  declared truths/data for comparative performance, and separate contamination
  or misspecification outcomes; neither a shared generator/fit kernel nor a
  favorable own-prior result is independent validation.

For each retained cell, give its mechanism, decision profile, expected outcome,
generator/fit mismatch and applicable metrics. Size independent datasets by
the required Monte Carlo precision for recovery, coverage, loss and failure
rates; chains and multiple fits on one dataset are not new replications.
Report planned, started, completed and diagnostically usable attempts and the
applicable denominator for every metric. Paired model contrasts need the same
response data and their joint usable subset plus missing/failure counts; a
successful-only contrast cannot certify the full planned domain. Pilot tuning
and its data stay outside fresh evaluation. No cell count, seed roster,
scientific margin or experiment budget is adopted by this proposal.

### User workflow, API naming, and visualization

#### Final API and development-status wording

The user's 2026-09-17 clarification makes `Experimental` a transitional
development boundary, not the intended permanent analyst workflow. In the
final supported release, ordinary model selection, fitting, prior inspection,
plots and reports must use model names and explicit supported options rather
than requiring a development-status namespace. Existing names such as `fit`,
`prior_predictive_check`, `plot_prior`, `plot_predictive` and `fit_report` should
remain the short workflow. Decide the final model constructor and correlation
selector alongside their statistical contract; prospective signatures are not
executable documentation until implemented.

Promotion is a model-specific change, with four linked acceptance checks:

1. Accept the model's equation, scale, prior measure/Jacobians, identification
   and supported domain, with the required Julia/CmdStan evidence and the
   existing release conditions below. Removing a word does not satisfy them.
2. Expose the accepted model through the ordinary API and update examples,
   README, live help, rendered navigation/search, displays, errors, plot titles
   and report defaults together. Final figure/report headings describe the
   model and quantities; relevant limitations, units and diagnostic warnings
   remain visible. Retain status/provenance fields for reproducibility where
   needed, without making development work orders part of user interpretation.
3. Preserve `Experimental` calls as documented compatibility aliases for an
   explicitly recorded transition period. Deprecations must name the replacement
   and any real semantic difference. Do not change existing `FacetSpec` meanings,
   serialized defining-type identities or historical payload hashes merely to
   shorten a name. Verify old source calls and saved results on supported Julia
   versions, and give materially different models different identities.
4. Add release-scope checks for both source/help and freshly rendered/runtime
   output of promoted models, including the ordinary prior-to-fit-to-report
   walkthrough. A blanket ban on the token `Experimental` would also reject
   necessary compatibility documentation and unpromoted models; scope checks to
   the actual final user surfaces and preserve user-supplied labels.

Today the namespace and experimental support metadata remain truthful. The
new prior plots use quantity/model headings and state current support in the
caption. Final promotion will remove that status caption together with the
corresponding API migration. This is part of package handoff, independent of
completion or publication of the Uchihara application.

**Status: fit-taking posterior interval, trace/rank, category predictive and
stable MFRM Wright-map figures implemented; the stable MFRM and both guarded
generalized examples now run through save/reload and optional figures.
Public-content corrections and posterior figure/report integration are verified
below. Fixed-coefficient prior inspection and direct figures are implemented;
their saved-fit report integration is implemented. The unfamiliar-reader walkthrough remains open.**
The acceptance unit is a user's completed analysis task, not the number of
exports, plotting-data helpers, report sections, or generated files. Keep
scientific validity and usability as separate requirements: neither a polished
figure nor a complete numerical report satisfies both.

#### Current UX baseline

| Observed surface | Consequence and reuse boundary |
| --- | --- |
| The [root API contract](src/root_api_contract.jl) lists 137 stable, five compatibility and 44 research bindings | Classification exists, but the 186-name root surface does not reveal a short ordinary workflow. Keep useful names such as `fit`, `validate_design`, `posterior_summary` and `fit_report`; reducing name length alone is not the objective |
| `mfrm_spec(...; family = :mgmfrm)` and the MGMFRM selector `discrimination = :none` | The latter still fits Q-masked discriminations. Resolve terminology and model selection together; an apparently simple name must describe the actual model |
| `fit(spec)` already delegates to `fit(getdesign(spec))`; [the minimal example](examples/minimal.jl) is now 56 lines, down from 181 | The default Julia NUTS route prints diagnostics and summaries, saves/reloads the fit, and optionally exports four figures. Design inspection and manual cache keys are optional; advanced reporting uses the existing manual |
| Generalized `posterior_summary` uses raw coordinates; qualified `BayesianMGMFRM.direct_posterior_summary` uses transformed parameters; `fit_report` includes direct summaries by default | Both guarded examples now print model-scale summaries and generate model-scale intervals plus raw-coordinate diagnostics from the saved fit. MGMFRM preserves named dimension selection. Existing draws and serialized objects retain their meanings |
| `wright_map_data` and `diagnostic_map_data` serve stable MFRM; calibration, predictive-check and recovery helpers return plotting rows | Category-proportion and stable MFRM Wright-map rows now feed finished figures; the remaining rows are reusable inputs. Do not advertise a generalized Wright map or MGMFRM rater report on the strength of stable-only methods |
| [Report bundles](src/bayesian_fit.jl) contain JSON, JSON tables and Markdown; qualified `BayesianMGMFRM.plot_posterior(fit)`, `BayesianMGMFRM.plot_diagnostics(fit)`, `BayesianMGMFRM.plot_predictive(fit)` and `BayesianMGMFRM.plot_wright(fit)` return editable figures | The optional CairoMakie extension consumes existing fit draws, summaries and transforms; the Wright map is stable MFRM only. Posterior figure/report integration is verified below. Prior inspection has direct `plot_prior(check)` and `plot_predictive(check)` figures and optional saved-fit report integration |

The initial API/visualization inspection did not rerun package tests or fit
models. Later figure checks and native example runs are recorded below; they
do not establish that the current uncommitted tree passes CI. The longer
[archived UX proposals](docs/internal/archive/roadmap-2026-09-05.md#integrated-summary-warnings-persistence-and-visualization)
remain background: extra save/load aliases, HDIs and every diagnostic plot are
not prerequisites for the first delivery below.

#### Delivery order and dependencies

| Slice / responsible role | Concrete deliverable | Completion evidence and dependency |
| --- | --- | --- |
| Public content and ordinary workflow — maintainer, with analyst input | The [README/manual/help correction](#public-documentation-cleanup-2026-09-14) and short data -> specification -> fit -> diagnostics/summary -> figures -> save/reload route are implemented; retain their factual consistency as model support expands. Record proposed spellings, old-to-new mappings, version/stability policy and affected callers only for actual API changes | Source, live-help and fresh-HTML checks now pass; unfamiliar-reader acceptance remains pending. The introductory path needs no custom printing helpers, private names, manual cache keys or compulsory design inspection. A user can identify the fitted family, restrictions and warning status. Preserve experimental boundaries and old calls; proposed figure operations stay out of runnable public examples until implemented |
| Draw and interpretation mapping — analyst/maintainer | Reuse fit draws, chain IDs, iterations, parameter layouts, direct transforms and existing report summaries behind the selected user operations. Allow selection by named parameter, facet/block and dimension, with explicit computational versus model scale | Stable MFRM and computational diagnostics can proceed without full M1 freeze. A generalized interpretation view needs the accepted model/scale slice, not completion of M2. Verify reconstruction of constrained coordinates, label/chain alignment, actual prior metadata and unchanged old-artifact interpretation; never silently change the existing raw-summary default |
| Standard figures — maintainer | Posterior intervals, trace/rank diagnostics, category predictive figures and the stable MFRM Wright map are implemented for their documented scope. Extend those editable figures to each new model's named quantities, using the existing backend and numerical consumers; add further calibration views for a specified user task | First exercise existing stable fits and explicit generalized cases with known scale metadata; new scientific-model figures follow their verified implementation. Check every advertised family/plot combination. A stable-only plot remains explicitly unavailable for unsupported generalized fits. Plotting must not trigger a refit or require research artifacts |
| Integrated report and user walkthrough — maintainer, analyst and a reader unfamiliar with the implementation | Selected figures, captions and numerical tables are integrated into reports/bundles. Use the existing stable, guarded and fixed-coefficient examples for the reader walkthrough; carry the same analysis settings through new-model consumers | From a documented setup, the reader can fit, inspect a warning, select a rater/dimension, save/reload the fit through the existing cache/persistence route, and regenerate an editable figure and report without handling draw matrices. Record task outcomes and remaining friction. This is usability evidence, not independent scientific review |

**Immediate UX work:** report/figure integration is implemented. Prepare and
record the unfamiliar-reader walkthrough on the existing supported workflow,
then correct observed friction. For each new model slice, extend that same
workflow and verify its scale, warnings and save/reload behavior. Preserve the
existing qualified figure names and compatibility bindings; final API promotion
follows the model-specific migration requirements above.

Select `BayesianMGMFRM.plot_predictive` in place of the earlier proposed
abbreviation `plot_ppc`; no alias is added. It joins
`BayesianMGMFRM.plot_posterior`, `BayesianMGMFRM.plot_diagnostics` and now
`BayesianMGMFRM.plot_wright` as a qualified optional entry point.
Prefer clear, consistent names to cryptic abbreviations. Resolve the
`mfrm_spec`/discrimination mismatch against the accepted model specification.
Keep existing 0.1.x bindings and serialized type identities; a change to the
frozen export set needs an explicit version/migration decision and matching
API-contract tests, not an unnoticed extra export. Research helpers can leave
the introductory documentation now; moving/removing their bindings belongs to
that compatibility decision.

The first renderer review evaluated optional CairoMakie against installation,
headless operation, figure editing and PDF/SVG export needs. Its
[official backend documentation](https://docs.makie.org/stable/explanations/backends/cairomakie.html)
supports vector output, and [Julia package extensions](https://pkgdocs.julialang.org/v1/creating-packages/#Conditional-loading-of-code-in-packages-(Extensions))
allow plotting code to load only with its dependencies. The implementation
decision below selects this renderer. Retain backend-independent rows for custom work;
do not require users to assemble those rows to obtain standard figures. Avoid
multiple initial backends, a custom graphics engine, or a separate dashboard.

**First interval-figure implementation decision, 2026-09-14:** select CairoMakie
0.15 as a weak dependency and Julia package extension. The installed 0.15.13
renderer is the initial verification target. Add the qualified, opt-in
`BayesianMGMFRM.plot_posterior(fit; ...)` entry point for the next additive
0.1.x release; retain the exact root export set, existing names and serialized
type identities. No release/tag is made by this implementation. Stable MFRM
and the existing experimental GMFRM/fixed-Q MGMFRM fits keep their respective
support status. Default the figure to model coordinates, allow explicit raw
coordinates, and retain the existing numerical summary defaults unchanged.
Reuse the existing posterior summaries and constraint transforms, separate
blocks/dimensions into axes, label fixed coordinates as constants, and return
the native editable Figure. Use CairoMakie's own display/save functions;
do not add a figure wrapper, custom serializer or required plotting dependency.
Ordinary tests cover numerical/selection contracts without CairoMakie; a
separate optional test exercises the extension, editing, PDF/SVG export and
fit-cache reload on Julia 1.10.8 and 1.12.5.

#### First interval-figure verification, 2026-09-14

`BayesianMGMFRM.plot_posterior` now supports stable MFRM and existing experimental
GMFRM/fixed-Q MGMFRM fits, including block/parameter/dimension selection, model
and raw coordinates, fixed anchors and derived threshold constraints. Each of
Julia 1.10.8 and 1.12.5 passes **266 numerical/selection checks plus 41 optional
render/cache checks** with normal compilation. These are deterministic synthetic
draw fixtures, not new sampler runs or statistical validation. The final PDF
exports for all three families were rendered and visually inspected; row order,
spacing, fixed markers, long dimension labels and editable native output were
also checked. Earlier iterative passes are excluded from the final 614 total.

The public guide/help and README now describe the implemented operation. The
existing manual build succeeds, and the language gate passes 19 public source
files and 14 freshly generated HTML pages. Four existing missing-docstring
warnings for research/release helpers remain; the new plotting help is included.
These checks do not close the broader semantic cleanup or unfamiliar-reader
walkthrough. The optional test environments retain CairoMakie 0.15.13; root
inference dependency graphs and exports are unchanged. Project hashes were
updated for the optional dependency declaration. Commands, logs, environment
manifests and final figures are retained in the local ignored
[verification receipt](results/posterior-plots/20260914-01/receipt.json).
No full-suite, CI runtime-budget, new scientific-model or release acceptance
follows. The subsequent trace/rank implementation is recorded below.

#### Trace/rank figure implementation, 2026-09-14

Retain the same CairoMakie extension and additive qualified-entry-point policy
for `BayesianMGMFRM.plot_diagnostics`. No export, dependency, version, sampler or
serialized type change accompanies it. Shared coordinate reconstruction and
selection now serve interval and diagnostic figures; the interval summarizer
still uses the existing numerical consumer. Trace/rank defaults to raw
computational coordinates, with model coordinates selectable. The default
12-coordinate limit rejects an oversized selection rather than hiding rows.

Preserve every retained chain/iteration using the existing fit-layout check.
Use deterministic pooled average ranks for ties, chain-normalized bin counts
and a pooled reference that retains ties. Existing parameter R-hat/bulk/tail ESS
and whole-fit diagnostics supply the captions; generalized fits retain their
recorded thresholds and diagnostic-contract checks. Fixed and constant values,
single chains, absent/partial sampler statistics and derived coordinates without
stored diagnostics are explicit, not successful checks. Warmup draws are not
reconstructed; pairs/divergence overlays and energy plots remain separate work.
The existing [bayesplot rank-plot guidance](https://mc-stan.org/bayesplot/reference/MCMC-traces.html)
informs interpretation, not an additional package dependency or a new diagnostic
acceptance rule. The subsequent conditional predictive figure is recorded below.

Final normal-compilation checks pass **480 assertions per Julia 1.10.8 and
1.12.5**: 266 interval regressions, 128 trace/rank data checks and 86 optional
render/cache checks. The final PDFs for all three families were rasterized and
visually inspected; fixed/derived and single-chain views were also inspected.
Checks use deterministic synthetic draws, including two chains of 20 draws;
there was no sampler execution or backend-equivalence experiment. Initial
iterations are excluded from the final 960 assertions. Fresh live help,
19 public source files and 14 generated HTML pages pass the existing language
checks; the manual retains the four previously recorded missing-docstring
warnings. Projects, manifests, root exports and include boundaries are unchanged
in this slice. The local ignored
[receipt](results/posterior-plots/20260914-trace-rank-01/receipt.json) retains
commands, source hashes, logs and final figures. Full-suite, runtime-budget,
scientific and unfamiliar-reader acceptance remain open.

#### Category predictive figure implementation, 2026-09-14

`BayesianMGMFRM.plot_predictive` reuses `posterior_predictive_check`,
`predictive_check_summary` and `predictive_check_plot_data` through the same
optional renderer. It compares observed category proportions with replicated
means and pointwise central predictive intervals (90% by default), retaining
every declared category. Replications condition on the original rating rows
and fitted persons, items and raters. Whole-fit diagnostic warnings remain
visible; this aggregate same-data check is not new-facet validation.

By default use every retained draw once; `ndraws` samples indices with replacement
and `draw_indices` preserves explicit order and duplicates. A local seeded
MersenneTwister (default seed 1) supports exact replay after cache reload in the
same software environment. The caption distinguishes replications from distinct
posterior draws. Changing interval width does not change the replicated scores.
The shared categorical sampler now rejects invalid probability vectors before
consuming randomness: previously NaN or all-zero probabilities silently selected
the last category. The guard serves stable/generalized prediction and local
dependence replication; valid probability sampling retains its original sequence.

Final scoped checks pass **808 assertions per Julia 1.10.8 and 1.12.5**: 266
interval, 128 trace/rank, 294 predictive and 120 rendering/cache checks. Final
PDFs for all three supported fit families were rasterized and visually inspected,
including a separate zero-count-category view. Live help, 19 public sources and
14 fresh HTML pages pass the language checks; the four existing omitted research
docstrings remain. The local ignored
[receipt](results/posterior-plots/20260914-predictive-01/receipt.json) preserves
commands, final figures and hashes. Projects/manifests, exports, include lists
and fixtures are unchanged. These use synthetic parameter draws with simulated
responses, not native Julia/CmdStan MCMC or statistical validation. No full-suite,
CI/runtime, release or unfamiliar-reader acceptance follows. The subsequent
stable MFRM Wright map is recorded below; broader predictive displays and report
integration retain their own scope and evidence requirements.

#### Wright-map implementation decision, 2026-09-14

Select qualified `BayesianMGMFRM.plot_wright` in the same CairoMakie extension,
with no new export, dependency or serialized type. Reuse `wright_map_data` for
stable MFRM rating-scale/partial-credit fits only. Place facet levels and item-step
boundaries on linked vertical logit axes, retaining posterior intervals and
explicit fixed references/anchors. Preserve facet order and use a visible
60-position limit, adjustable by the caller; never silently drop levels.
Threshold boundaries mean item difficulty plus step at zero rater severity,
not expected-score half-points. Retain the item's and step's joint uncertainty.
Correct fixed-position metadata and reject derived overflow in the shared
numerical helper so custom plotting and diagnostic-map callers receive the same
correction. Verification remains distinct from native backend or scientific
validation. No generalized Wright-map support is inferred.

Final normal-compilation runs pass **1,351 assertions per Julia 1.10.8 and
1.12.5**: 266 interval, 128 trace/rank, 294 predictive, 380 Wright-map and 283
render/cache checks. Six stable cases cover RSM/PCM, binary data, nonzero anchors,
and long labels with unused categories. Tests verify joint item-step quantiles,
adjacent-category equality, facet signs, structural fixed values, overflow
rejection and exact plotting-input recovery after cache reload. Final PDFs were
rasterized and inspected; vertical labels correct the initially observed clipping.
Fresh live help and language checks pass 19 public sources and 14 generated
HTML pages, with the four existing omitted research docstrings unchanged.
Commands, source hashes and figures are in the local ignored
[receipt](results/posterior-plots/20260914-wright-01/receipt.json).
These are synthetic presentation/consumer checks, not native Julia/CmdStan MCMC
or statistical validation. Projects/manifests, exports, include lists and the
shared fixture are unchanged. Full-suite, CI/runtime, release and reader
acceptance remain open. The subsequent short ordinary workflow is recorded below.

#### Short stable MFRM workflow, 2026-09-14

`examples/minimal.jl` now uses 56 lines for ratings, validation, `fit(spec)`,
diagnostics, compact posterior summaries and checked fit save/reload. The default
is Julia AdvancedHMC/NUTS. Optional `--plots` loads CairoMakie before sampling
and writes interval, trace/rank, category predictive and Wright-map PDFs plus a
Wright-map SVG from the reloaded fit. Each run retains its own output directory;
`--cmdstan` uses the same specification and a fresh empty build directory.
README and the existing fitting/examples guides explain setup and later-session
figure editing. The examples guide also corrects its scalar GMFRM claim: the
implemented kernel estimates positive item discrimination and rater consistency.
No public API rename, helper, dependency or fitting-kernel change is needed.

Four final native runs pass **52 workflow assertions**: 11 for Julia 1.10.8
without plotting, 13 with plotting on each of Julia 1.10.8 and 1.12.5, and 15
for CmdStan 2.39.0 with plotting on Julia 1.12.5. Each also executes the example's
summary-equality assertion. Every run uses two chains with 50 warmup and 50
retained draws per chain and retains its diagnostic warning; these are execution
checks, not convergence or backend posterior-agreement evidence. A separate
fresh-session cache/figure check is recorded with the verification details in
the [backend note](docs/internal/normalized-prior-backend-comparison.md#short-stable-mfrm-workflow-2026-09-14).
No MCMC draw reshaping is required. Source, extension, test and script files,
Projects/manifests, exports and include lists are unchanged in this slice.

The guarded-example and public-cleanup follow-ups are recorded below.
Report-bundle figures, unfamiliar-reader acceptance, M0 runtime work and M1
scientific validation remain open. Julia remains primary; CmdStan remains maintained.

#### Guarded GMFRM/MGMFRM workflows, 2026-09-14

The existing GMFRM and MGMFRM examples are reduced from 103 lines each to 60
and 67 lines. They validate data, retain explicit `Experimental.fit` opt-in,
print diagnostics and qualified `BayesianMGMFRM.direct_posterior_summary`, and
check model-scale summary recovery after saving/reloading. `--plots` exports
three PDFs plus a posterior SVG from the saved fit; `--cmdstan` selects the
companion backend with a fresh build directory. GMFRM displays positive rater
consistency intervals and raw log-consistency traces. MGMFRM displays separately
named abilities and selects a dimension by label for diagnostics. Prediction
uses the same fitted rating rows. Wright maps remain stable MFRM only.

README and the fitting/examples guides now describe the actual 50-warmup,
50-retained-draw, two-chain controls, raw/model-scale distinction, outputs and
later-session editing. The two-item MGMFRM dataset remains an API demonstration,
not identification or substantive multidimensional evidence. Final Julia/CmdStan
workflow checks pass 175 assertions, with eight further fresh-session figure
checks. Verification and its limits are recorded in the [backend note](docs/internal/normalized-prior-backend-comparison.md#guarded-gmfrmmgmfrm-workflows-2026-09-14).
Live-help inspection exposed a missing model-scale-summary docstring; that help
and its existing API-reference entry are now supplied. No export, source kernel,
prior, dependency or serialized type changes are needed.
The public-content follow-up below precedes report-bundle figure integration
and the unfamiliar-reader walkthrough; none closes M0 or M1 by itself.

#### Public documentation cleanup, 2026-09-14

README is reduced from 700 to 265 lines. Public data/workflow/model/fitting and
migration pages now separate ordinary analysis from research execution plans,
resource probes, CI details and deferred anchor implementations. Existing
research owners retain missing commands and deferred contracts; historical
fixed-Q resource instructions remain in the existing archived roadmap, while
current M1/M2 decisions remain above. Research API schemas and compatibility
bindings retain their meanings. Stable and guarded support, raw/model scales,
`1.7`/`1.702`, Jacobians, priors, exact anchors and CmdStan restrictions remain
explicit. Live help replaces scaffold/Stage-0 descriptions with object behavior.

Julia 1.10.8 passes 35 checks: three parsed-code comparisons excluding docs and
source locations, 22 live-help checks and ten ordinary-data/preview checks.
Every other source, extension, script, test and runnable example is byte-identical
to this slice's starting tree, as are Projects/manifests, root exports and
serialized definitions. No MCMC, package installation or external fit ran.
The final Julia 1.12.5 manual build and language checks pass in 15.12 seconds:
19 public sources and 14 fresh HTML pages. Inspection found ten broken HTML
fragment links; corrected Documenter heading IDs now pass all 455 local
fragment links with no missing local files. Internal owner pages are absent
from generated navigation/search. Four pre-existing omitted research/release
docstrings remain outside the published manual. Details and preserved checks
are in the [existing workflow owner](docs/internal/normalized-prior-backend-comparison.md#public-documentation-cleanup-2026-09-14).
This closes the bounded editorial/runtime-help correction, not independent
reader, full-suite/CI, release, model-validity or scientific-review acceptance.

#### Report-bundle figure integration, 2026-09-14

`save_fit_report_bundle` now accepts optional posterior, trace/rank, conditional
category-predictive and stable-MFRM Wright figures from a saved fit. Existing
numerical and CairoMakie helpers supply the figures and captions; predictive
figures consume the report's exact summary rows and selected draws. PDF/SVG
and numerical-input JSON exports share the report's interval/diagnostic settings.
Figure bundles use manifest v2 with file hashes; ordinary v1 bundles and report/
table schemas remain compatible. Readers require neither CairoMakie nor a fit.
Summary-only figure requests and unsupported selections fail explicitly.

Julia 1.10.8 and 1.12.5 each pass 278 bundle checks across the three families.
The final no-renderer pass covers 46 checks, including both versions' exports,
missing files, symlinks and downgraded manifests. The existing report regression
passes 128 checks; its single two-draw Julia fit is distinct from the synthetic
draws used by every figure test. The existing standalone plot/cache regression
passes 1,351 checks on Julia 1.12. All ten primary Julia 1.12 bundle PDFs were
visually inspected. Manual/language checks pass for 19 sources and 14 fresh
HTML pages; all 458 local fragment links resolve. Details, attempt history and
remaining limits are in the [existing workflow owner](docs/internal/normalized-prior-backend-comparison.md#report-bundle-figures-2026-09-14).
No inference kernel, dependency or public export changes were needed. This
closes the bounded integration task; independent reader acceptance remains open.

#### Public documentation and help acceptance

**Initial observation on 2026-09-11, before corrections.** The short-workflow
changes and the dated cleanup above now cover the observed content defects;
unfamiliar-reader acceptance remains open. The following records the initial
findings and the acceptance criteria retained for future edits. The existing
[source-language check](scripts/public_language_gate.jl) examined 19 public
files and returned four language violations, all README links into the
supporting anchor-study document (lines 321, 323, 331 and 337 at inspection).
Navigation and workflow checks returned zero violations. The 14 saved public
HTML pages passed the rendered-language check, but those files were generated
on 2026-09-05 and visibly retain development-stage wording. They are neither
a fresh build of the edited source nor evidence of reader usability. Live
Julia help was read for `FacetData`, `MFRMFit`, `getdesign`, `fit`, `MGMFRMFit`
and `mgmfrm_validation_protocol`; the first four retain `scaffold` wording.
No fit or full package test was run for this inspection.

| Surface / existing owner file | Required treatment | Reader-visible completion condition |
| --- | --- | --- |
| [README](README.md) | Keep purpose, actual model support, installation, a short current analysis, essential limitations and manual links. Move the approximately 180-line study/resource discussion following Quick Start to its existing research owner, merging only missing information. Reduce the detailed CI/resource/quiet-wrapper instructions to a brief contributor route | An ordinary analysis does not require Stage 1--3, cell rosters, resource-review receipts or permission to execute the package's validation study. Clearly distinguish released from development-only behavior; all runnable examples use available APIs for the stated revision |
| [Fitting](docs/src/fitting.md) and CmdStan help | Keep actionable backend requirements in the public guide: current cache-directory behavior, rejected Make environment settings, readiness versus compilation, and errors. Replace the four README links to internal proposals with a self-contained public explanation and an appropriate public-manual link | Removing the internal links does not conceal cache-reuse restrictions or change backend behavior. A user can resolve a supported configuration error without reading the anchor-study methods draft |
| [Data validation](docs/src/data-validation.md), [Bayesian workflow](docs/src/bayesian-workflow.md), [scope](docs/src/scope.md) and [home](docs/src/index.md) | Explain the user's input, action, output and interpretation. Move `Primary work order`, LD1a/LD1b0/LD1b1 progress, study freeze decisions and execution sequencing out of ordinary analysis instructions; retain applicable diagnostic and evidence limitations in plain language | Readers can distinguish an available diagnostic from a fitted effect and from an unvalidated decision rule, without learning internal milestone names or mistaking research-execution blocks for a ban on ordinary fitting |
| Public help in [facet_workflow.jl](src/facet_workflow.jl) and [bayesian_fit.jl](src/bayesian_fit.jl) | Replace development-era descriptions such as `v0.1 design scaffold` with the supported data/model/result behavior. Lead with purpose, then inputs/defaults, return values/scale, a short example and relevant limits. Keep actual argument names and important raw/direct distinctions | `?FacetData`, `?getdesign`, `?fit`, `?MFRMFit` and generalized result help agree with the manual and implementation. No implementation detail is removed when needed to interpret a returned field, but the reader need not infer maturity from historical scaffolding language |
| [GMFRM example documentation](docs/src/examples.md) versus [experimental model description](docs/src/experimental.md) | Resolve the statement that scalar GMFRM does not support item discrimination: its current kernel uses positive item discrimination times rater consistency. State the restricted fitted structure, distinguish the compatibility selector from the actual parameters, and retain the partial-credit/no-anchor/no-DFF restrictions | README, example, help, model-family contract and equations describe the same fitted structure. Correct existing prose without claiming unrestricted discrimination or complete source-prior reproduction; verified changes for the two future scientific models get their own explicit descriptions |
| [Model equations](docs/src/model-equations.md), [experimental scope](docs/src/experimental.md), [fitting](docs/src/fitting.md) and [migration guide](docs/src/migration-facets-conquest.md) | Present the actual model choices using the model axes above: explicit abilities, fixed/estimated slopes, Q structure, aggregation, latent covariance and fitted effect blocks. Explain literal `1.7` versus reference `1.702`, and raw versus direct prior measures. Separate Julia/CmdStan backend selection from ConQuest/TAM migration/comparison | Users can identify what their chosen model estimates without interpreting `discrimination = :none` as fixed unit loadings, assuming free correlations, or treating a bifactor-shaped Q as validated bifactor support. Describe available behavior and limits, keeping proposed extensions and internal acceptance work in their research owner |
| [API reference](docs/src/api.md) and [research-helper reference](docs/src/api-validation-evidence.md) | Lead ordinary users to stable workflow operations. Keep retained research helpers clearly labeled in their advanced reference/help; remove instructions to future developers such as how to expand the root namespace | Source compatibility and stable/compatibility API documentation coverage are preserved. Research-return schemas may still document their actual status fields; they do not become ordinary analysis prerequisites or mature model claims |

Use existing research/protocol notes as destinations for developer material;
do not paste every removed paragraph into this roadmap or create a parallel
manual. Preserve genuinely missing methodological rationale and links once.
The existing placement review already keeps repository-only pages out of the
public build; the repair is primarily within published pages and docstrings.
Check generated navigation and search entries after edits so removed content
does not survive in stale output.

Acceptance requires both factual consistency and an understandable sequence:
what the user wants to know -> the operation and why -> its output -> the
interpretation and next action. For a few representative documented tasks,
compare actual model family, discrimination/loadings, thresholds, prior scale,
raw/direct summaries, fixed coordinates, prediction target and support status
across the existing implementation, help and guide. Reuse existing model tests
and contracts; no second capability registry or prose-to-source hash ledger.
Explicitly retain experimental/unsupported status, unknown or insufficient
evidence, and real operational limitations. Do not turn editorial cleanup into
a stronger scientific claim or change inference to match stale documentation.

Verification retained for documentation edits (source/help/HTML completed
above; the reader check remains pending):

1. Run the existing source-language/navigation checks and inspect each affected
   section semantically. Close the four observed README findings and the
   documented content contradictions; four removed links alone are insufficient.
2. Read live help from the edited package and make a fresh manual build with
   the existing [build entrypoint](docs/build.jl). Scan the resulting HTML with
   the rendered-language check; inspect navigation/search and the relevant API
   pages, rather than relying on Markdown or a September 5 build alone.
3. Check runnable examples against their stated revision using existing bounded
   example checks when execution is needed. Keep snippet parsing, actual
   execution and scientific validation distinct; do not execute copied research
   probes to validate documentation. Public plot examples wait for callable plots.
4. In the existing unfamiliar-reader walkthrough, require users to find the
   relevant function, understand its return scale and warning, and reach the
   next analysis step without internal notes. If no reader has performed it,
   record it as pending rather than treating an automated scan as a substitute.

Retain the existing language checks as regression tools. Add a narrow rule
only for a demonstrated recurrent leak with a meaningful check; do not weaken
them to pass the current links or add a blanket blacklist of `experimental`,
`validation`, `internal consistency`, or research API status fields. An allowed
word can still form a misplaced work order, and an accurate restriction is
still necessary user guidance. Record source, live-help, rendered-content and
reader-review outcomes separately against the edited revision.

#### Figure and report acceptance

- **Diagnostic meaning:** preserve chain and iteration identity for traces and
  rank views; show R-hat, bulk/tail ESS and available sampler warnings from the
  existing diagnostics. Insufficient chains/draws or absent backend statistics
  are unavailable, not successful diagnostics. A bounded overview identifies
  its displayed subset and allows named selection; it must not hide problems
  elsewhere. Add pairs/divergence or energy views when the needed statistics
  are present and a diagnostic task requires them. Report-construction health
  is not convergence or model adequacy.
- **Parameter meaning:** default interpretive figures to the declared model
  scale, with computational scale explicitly selectable. Show facet IDs,
  dimension names, constraints and fixed anchors; fixed values are not sampled
  intervals. Distinguish posterior dependence from fixed latent-population
  correlation. Preserve named ability dimensions rather than collapsing them
  into a single score; any composite or joint threshold event needs its declared
  weights/rule and joint-draw uncertainty. General/specific-factor labels and
  summaries apply only to an explicitly supported factor structure.
  Multidimensional abilities, loadings and thresholds cannot be
  placed on a common Wright-map axis without a justified mapping. Reference
  lines and practical margins must match the estimand, not a universal zero.
- **Uncertainty and prediction:** reuse declared interval levels and methods;
  label posterior credible intervals separately from predictive intervals and
  MCMC error. Do not introduce HDIs or change existing interval defaults in the
  first plotting slice. State the observed/replicated statistic and conditioning;
  same-data predictive checks and calibration are not heldout validation or
  new-person/item/rater prediction. Unobserved declared categories remain visible.
- **Reproducible output:** figures, captions and tables agree on model/prior
  identity, selected parameters, scales, interval policy and diagnostic status.
  Use the same checked summaries or selected draws; retain RNG/selection settings
  for stochastic predictive displays so saving/reloading does not silently
  regenerate different checks. Rendering consumes those results and starts no
  MCMC. Preserve existing JSON readers and bundle compatibility through explicit
  optional entries/schema handling; summary-only saved reports cannot recreate
  traces, so request the saved fit with a clear message instead of fabricating draws.
- **Readable, editable output:** inspect PDF/SVG exports for clipping, crowded
  labels, font sizes and readable grayscale/color-vision-safe encodings; do not
  communicate warnings by color alone. Expose labels, order, dimensions and
  interval controls through the returned figure or small documented options.
  Captions identify the estimand and uncertainty without exposing internal
  provenance tokens or implying a model/claim has passed independent review.

Verification should use a small deterministic fit/draw example exercising
chain separation, transformed and fixed coordinates, unavailable diagnostics,
and equality with existing summary rows, followed by visual inspection of the
exported figures and the saved/reloaded workflow. Test one supported combination
per advertised family and explicit unsupported cases; reuse existing numerical
tests rather than duplicate inference. Keep ordinary loading usable without the
optional backend; exercise rendering in a bounded optional-dependency check and
measure its added load/export cost without relaxing existing runtime gates.
Use separately bounded pilot data only if a real fit is needed for integration;
these checks add zero evaluation replications and do not replace M1/M3 review.

## Immediate work and stop conditions

**Current order, 2026-09-27:** Follow [Current decisions](#current-decisions):
the normalized coordinate route now connects to the explicit experimental API;
the [foundation evidence](docs/internal/mgmfrm-foundation-scale-acceptance.md) now
separates claim-specific decisions. The four-fit loading-prior sensitivity comparison
is complete, including added-quantity MCSE and independent saved-value arithmetic checks.
The [fixed-facet design](docs/internal/mgmfrm-foundation-fixed-facet-design.md) now
specifies paired R0/R1, scale rationale, estimands and precision/cost options. Its
bounded rehearsal has completed all six fits, with four numerically qualified and
two retaining R-hat failures. The single engineering pair adds no evaluation credit;
zero blocks qualify jointly across all six conditions. The analyst's [decision packet
in §10](docs/internal/mgmfrm-foundation-fixed-facet-design.md) now makes the claim,
finite sampling/failure policy and precision/cost alternatives reviewable. Independent
review, N and the formal launch remain pending. This planning task is closed; prepare
the existing experimental API's integration candidate and relevant checks alongside
scientific review, without adding another planning prerequisite or posterior batch.
The existing two-panel comparisons and saved ability review remain exploratory.
Workflow review proceeds alongside this work. Conditional-CDF refinement is a
bounded optional aid, not a universal prerequisite. The
[first raw candidate](docs/internal/mgmfrm-first-acceptance.md) remains a distinct
historical target with unresolved findings, not the automatic next cohort.
The numbered [implementation handoffs](#next-implementation-handoffs) retain
their identifiers and evidence; their dated chronology does not set priority.

**Previous order, 2026-09-24:** Establish mathematical interpretation before
adding long-running fits. The [estimand review](docs/internal/mgmfrm-estimands-identification.md)
now gives the pure-Q conditional equivalence argument, interpretation table and
proper-posterior existence proof. The [prior-choice review](docs/internal/mgmfrm-prior-choice.md)
now connects raw/source/exchangeable structures to comparisons and units.
The [prior-response review](docs/internal/mgmfrm-prior-responses.md) now checks
the category implications of illustrative contrast widths, distinguishing
label symmetry, score reflection, endpoint mass and concentration. The internal
normalized route now connects the same prior record to generation, prediction
and restored-sample explanations. The 2026-09-26 public connection now provides an explicit MGMFRM prior/result
boundary and compatible report/cache dispatch, without extending the
fixed-coefficient `ExchangeablePrior` or adopting scientific scales. Claim-specific precision and acceptance requirements remain separate work.
Preserve the original data, frozen
runtime, evaluation quantities and unresolved results. Completing the remaining
269 attempts is neither a prerequisite for these derivations nor a proof of
the broader foundation. The preceding execution sequence below is historical.

**Previous order, 2026-09-23:** Sections 22–26 complete location-coordinate
integration, one R0 heldout evaluation, eight joint-prior fits and saved-draw
interval checks. Section 27 now checks the selected tail case with one same-data
CmdStan fit and conditional integration. Its five focal summaries agree and its
small positive tail probabilities are compatible at current MCSE; precise tail
mass remains open. Preserve the original cohort, its zero-count observation and
its eight-dataset denominator. Diagnostics, numerical agreement, information from
data and repeated-dataset calibration remain separate forms of evidence.

Section 28 now defines the distinct claims for absolute location, relative
recovery and prediction, with a closed-form conditional under the declared priors.
It also finds a roughly four-MCSE second-moment gap for prior-002 D2, which
ordinary diagnostics miss. Section 29 preserves that result, a first CmdStan
fit with a diagnostic warning, and a longer qualified follow-up that does not
detect the same departure. Its source remains unidentified; this local result
is not a global calibration claim or permission to repair the old draws.
Sections 30–32 now complete the first paired fixed-condition recovery, paired
prior-sensitivity follow-up and fresh 37-panel coverage screen. The latter finds
I2 loading undercoverage under the declared fixed R1 condition; this limits the
interval-performance claim without identifying a computational error. Preserve
the data, priors, all attempts and the separate joint-prior denominator eight.

Section 33 returns to calibration with full-draw median/coverage screens and
analytic correct/error controls. The next core deliverable is an actual
joint-prior replication and numerical-precision design informed by those controls:
keep all 150 quantities, including the observed likelihood; specify the deviations
to detect, resolved-classification assumptions, per-quantity unresolved outcomes
and dependence treatment before generating new panels. The normal-reference
counts 142 and 255 are sensitivity results, not an adopted MGMFRM roster or
finite-MCMC guarantees. Aggregate unresolved rates from the old eight cannot
justify a per-quantity 5% condition. Continue to distinguish sampler computation,
joint-prior calibration and fixed-condition performance; a further fixed-condition
mechanism contrast needs its own question. Repeated-dataset prediction follows.
The targeted tail comparison is complete for its local question; it is not a
calibration replication. Rank-based tests still need an explicit dependence
design. Keep failure accounting and independent review explicit. Application
readiness and execution-management machinery do not replace these outcomes;
the old unreviewed 12-fit proposal is not a prerequisite for targeted progress.

The [application inspection](docs/internal/application-portfolio.md) adds
Uchihara, EVA and Chopin as complementary uses, with separate questions and
input provenance. Grouped refits now permit heldout-only metadata IDs for the
currently supported likelihoods, while still rejecting unseen fitted
person/rater/item levels. Grouped splitting and joint predictive scoring are
explicitly distinguished. This reusable repair does not launch empirical fits
or supersede recovery/SBC and repeated-dataset evaluation. Dataset-specific
adapters, heterogeneous scales, selection models and new latent dimensions are
not prerequisites for the initial core candidate.

The supporting preparation below is complete: finite density, gradient and ID
conformance for the exact candidate is checked (candidate packet, section 10). Sections 11–12 now specify the scientific proposal and
implement person-population generation, ID-sensitive scoring and SBC quantity/
draw selection. Section 13 now binds complete cache bytes, training targets, recomputed
diagnostics and primary IDs, with named recovery rows and complete-fold assembly.
Section 14 now connects first-order CV-loss MCSE with joint row covariance and
recovery summaries paired by R0/R1 ID or aggregated within person dimensions.
These are arithmetic preparation, not statistical evidence or an adopted CV
precision gate. Section 15 now checks 2,048 joint-prior datasets for each of the
three declared raw priors. Mean endpoint mass is similar (about 73–74%), while
high-concentration rows differ (37.5%, 41.9%, 21.1%); retain actual prior-sensitivity
refits and rater/step position labels, without selecting a prior from this review.
Section 16 now adds exact observed chain-mean curvature remainders, diagnostics
for each loss influence, and descriptive dataset-level and paired R0/R1 CV
summaries with the full failed/missing roster. A prospective .01-nat reporting
resolution gives a proposed first-order MCSE budget of .005/3 nat, with an
additional MCSE/replication-error screen of .1. Neither screen is adopted;
observed curvature is not a bias bound and actual CV refits remain zero.
Section 17 retains single-category rejection as the current fitting-interface
boundary, without treating it as posterior impropriety under the declared proper
prior. Preflight now preserves a distinct rejected slot for datasets and folds.
Four-draw SBC is explicitly exploratory error detection: an exact continuous
counterexample has uniform ranks but 87.99% coverage for nominal 90% intervals.
Fixed missing ranks also sharply reduce detection in the separate finite PCM
negative control; neither the 100- nor 225-replication alternative is selected.
Section 18 now adds fixed 250/500/1000-draw prefixes and early/late-half loss
sensitivity, preserving all 4000 draws and withholding a bias guarantee. A bounded,
immutable preflight roster retains rejected, interrupted, incomplete and unstarted
jobs; ordinary and single-category dataset/fold records survive save/reload into
the original denominators. This is sampler-free preparation, not a formal fit
runner. Section 19 now provides a [12-fit R0/R1 execution rehearsal proposal](docs/internal/mgmfrm-core-rehearsal-plan.md):
one matched dataset pair, two complete-data fits and ten heldout refits, fixed
IDs/seeds, and proposed serial caps of eight hours and four GiB. Inputs and all
12 training targets are bound, and fitting/scoring worker entry points are connected;
new sampling under that proposal remains zero. This one pair cannot estimate replication error,
coverage or general condition effects. Section 20 now connects the serial batch
controller with shared time/storage caps and immutable all-slot ledgers. Owned
Python workers verify warnings, resource stops, interrupted or missing records;
native Julia collection retains failed/missing/precision-unresolved denominators
without sampling. Explicit post-stop collection has a separate 300-second budget
and cannot refit. Actual twelve-fit execution remains untested. Before running
that particular rehearsal, record its independent review and execution decision
in a new frozen contract. It is not a prerequisite for the targeted engineering
work above; do not add infrastructure as a substitute. The 444/819-fit alternatives remain
unselected. Preserve the
central pilot as computational evidence. The 40,000-draw pair is deferred unless
closing its full numerical-comparison claim becomes necessary. Its 83 unresolved
statistics are neither waived nor a blanket block on this design work. Saved-result
user-workflow preparation and integration-scope review proceed alongside it;
actual independent/user review remains a separate requirement.

The fixed-coefficient independent/correlated and explicit exchangeable-prior workflows are connected
on Julia and CmdStan, including prior inspection, fitting, diagnostics, figures
and saved results. This is operational and numerical evidence; model-specific
scientific acceptance is still open.

The [C2 pilot](docs/internal/fixed-coefficient-validation-protocol.md#one-condition-computation-pilot-2026-09-17)
retains execution failures and 30 inconclusive original backend comparisons.
A separately authorized dense Julia follow-up passed the pilot and additional
location thresholds on that one panel; it does not retroactively qualify the
preserved CmdStan fit. The [cost/replay evidence](docs/internal/fixed-coefficient-validation-protocol.md#bounded-likelihood-replay-2026-09-18)
shows an unchanged trajectory at lower observed cost. Most remaining dense
work is in early/middle warmup, with its metric-conditioning mechanism unmeasured.

The remaining bounded geometry observation stays a supporting cost inquiry.
Resume it for a demonstrated blocker to the core candidate or a later release
requirement; no faster adaptation is required before the candidate work. If
resumed, record a mechanism finding or an unresolved result within its existing
limits, then decide whether a separate algorithm comparison is warranted.
Review preparation and supported-workflow UX can proceed alongside these implementation handoffs. Neither reviewer recruitment,
Uchihara readiness nor completion of every MFRM validation cell blocks them.

The numbered rows are bounded handoffs, not a requirement to finish every
specification before making a routine correction. Work on an accepted model
slice can proceed without waiting for unrelated extensions or an empirical
study. CmdStan checks accompany that slice; fresh statistical evaluation still
needs its reviewed protocol and resource/launch decision. Public documentation
corrections and supported-scope plots run alongside the numerical work. Their
priority follows the Julia user workflow, not the readiness of a paper dataset.

| Task / owner role | Next deliverable | Verification and stop condition |
| --- | --- | --- |
| 1. Remaining Julia cost investigation — analyst/maintainer; supporting, deferred | If needed for a demonstrated blocker or release review, complete the [metric-observation handoff](#next-implementation-handoffs) using the existing observer; relate updated metric conditioning to subsequent transition work. Keep the completed [likelihood replay](docs/internal/fixed-coefficient-validation-protocol.md#bounded-likelihood-replay-2026-09-18) as the arithmetic-preservation baseline | Exit: exact trajectory/RNG preservation and a recorded mechanism finding or unresolved result. Any schedule comparison is a separate declared decision. Keep the joint prior, coordinates/Jacobian, criteria and all attempts; no automatic budget extension, new default or full-chain rerun. Do not block the already active row 2 model-workflow handoff |
| 2. M1 Julia model-to-code contract and estimation path — analyst/maintainer; bounded connection implemented | The [normalized location adapter](scripts/mgmfrm_normalized_location.jl) now delegates to the package implementation used by explicit experimental fitting for the selected independent fixed-Q target. Preserve the explicit normalized prior identity, canonical raw records, diagnostics and report/cache consumers. Earlier correlated-model connections, raw-coordinate comparisons and numerical receipts remain in their dated records | Exit: target/gradient and initialization checks, coordinate-aware cache identity, compatibility with old records, an end-to-end fit/save/reload/report check and one user example. Reject unsupported combinations explicitly. Do not infer scientific prior adoption, matched CmdStan acceptance or broader model support from this engineering connection |
| 3. CmdStan continuity — analyst/maintainer; accompanies each model slice | First common-coordinate probabilities, density differences and gradients, then a bounded matched-target posterior/predictive comparison with declared MCSE margins. Maintain independent backend execution and the same report/figure meaning | Exit: both routes represent the same likelihood, prior measure, constraints and scale. A posterior agreement claim requires each fit to qualify; the original C2 pair remains inconclusive. Missing counterpart support stays partial. Numerical agreement is implementation evidence, not model adequacy |
| 4. M2 core statistical validation — analyst; current order in Current decisions | Retain the raw evidence in [first acceptance](docs/internal/mgmfrm-first-acceptance.md): one descriptive R0 five-fold evaluation, eight joint-prior fits, paired recovery, 37 fixed-condition panels and the later 4/1/269 cohort. Keep the I2 undercoverage finding, prior-002 D2 concern and 83 inconclusive backend comparisons. The distinct [normalized foundation](docs/internal/mgmfrm-foundation-scale-acceptance.md) now has two independent candidate-C datasets, transformed-fit diagnostics and three-margin conditional budget comparisons. Consolidate what each claim can and cannot establish; the all-150 positive-acceptance claim remains open | Exit: reviewed target/scope, scientific margins or descriptive-only conclusions, replication/MCSE rationale, dependence policy, failure accounting and an executable bounded budget. Do not automatically continue the 269 raw attempts, launch thousands of candidate-C fits, or require full conditional-CDF error certification before every workflow improvement. Archived preparations and storage estimates are not current execution orders |
| 5. Julia user workflow and public documentation — maintainer with analyst input; alongside rows 1--4 | The fixed-coefficient fit-taking MCSE adapter is implemented with direct/raw coordinates and saved-record validation; see the verification below. Next record an unfamiliar reader identifying model/backend, inspecting warnings and precision, selecting a dimension and regenerating figures after reload. Extend consumers with each model slice and prepare naming/call-site migration for accepted models | Exit: demonstrated precision values and reload semantics remain covered. Supported-scope source/help/fresh-HTML and runtime output agree. The actual reader walkthrough and final ordinary API migration remain required, with compatibility aliases and unchanged old-result interpretation; model limits and diagnostic warnings remain visible |
| 6. M3 supported-domain and package handoff — maintainer and independent reviewer | Reproduce selected model/numerical claims and the documented workflow in a separate environment at the recorded revision; make claim-level supported/narrowed/rejected/inconclusive decisions | Exit: usable Julia behavior, matching CmdStan evidence and independent scientific acceptance are reported separately. Public promotion retains its M0 gate and integration/release authority. Completion or publication of an application paper is not an exit condition |
| Long-term model extensions — analyst/maintainer; sequenced after the relevant foundation slice | Follow the [single extension sequence](#long-term-extension-sequence): correlated dimensions/within-item validation, configurable random effects, a specified non-compensatory ordinal kernel, and staged Q structure inference. Fixed-Q comparison and identification work can precede full structure learning | Promote one declared combination at a time with model-specific evidence, both backends and a complete user workflow. Independent block validation does not certify their composition. These are long-term deliverables, not newly available options or an automatic batch of implementation/research jobs |
| Synthetic pronunciation example — analyst; secondary application, A0 reference engineering path implemented | The [A0 reference](docs/internal/paired-rating-reference.md) connects generation, fitting, saved results and known/new recording prediction. The [prior review](docs/internal/paired-rating-prior-review.md) now separates scale and step order, derives category-mode implications and specifies focal quantities, numerical precision and stopping proposals. The [focal precision consumer and cost guard](docs/internal/paired-rating-precision.md) are now verified on saved fits and bounded Python jobs. Next decide the scientific step-prior assumption and freeze the complete pilot contract, including compilation, shared limits and a permitted monitoring environment. Real Uchihara reanalysis remains optional future work | No prior or model is selected by closeness to the synthetic observations. Sorted/zero steps are mechanism contrasts without a fitted target. Existing samples retain their warnings. All 4,354 focal quantities remain MCSE-unavailable on each short saved fit. The verified polling guard is not hard OS containment. Scientific review and the frozen execution contract remain prerequisites for the bounded estimation pilot. Generation, numerical checks, statistical evaluation and empirical conclusions remain separate; application completion never defines Julia acceptance |
| ConQuest/TAM comparison — analyst/maintainer; supporting track | Complete the bounded [external-software handoffs](#conquest-and-tam-comparison-scope): ConQuest destination-scale mapping and estimator-aware comparison; TAM evidence reconciliation and independent-review handoff | Exit: scope, versions, parameter/uncertainty meanings and comparison decisions are explicit. Multidimensional comparisons wait for a matched model specification; historical MFRM evidence is not renamed MGMFRM validation. This is not a prerequisite for unrelated core implementation or a substitute for Julia/CmdStan verification |
| MFRM anchor sub-study — analyst; supporting track | Retain its [six freeze decisions](docs/internal/mfrm-anchor-study.md#freeze-decisions), 266-cell draft, resource proposal and reusable response/scoring checks; advance a piece when it addresses a core dependency or a separately selected anchor claim | All six decisions remain open. The 400/100 allocation is not automatically adequate for practical acceptance; the historical 20-assertion ordinal audit is not recovery evidence. Completing this panel does not certify generalized anchoring, and the full panel is not the next automatic launch |
| M0 observer integration — maintainer; local verification, candidate CI, and implementer review passed; unmerged | Use the [candidate CI and integration review](docs/internal/fitting-core-runtime-review.md#candidate-ci-and-integration-review) for the merge-approval handoff; no further fit is queued | At `5c4bff2`, all 12 ordinary CI jobs passed, including 21 guard cases on each of Linux/macOS; both manual research jobs were skipped. Verification C retains all 2,755 passing assertions and child/guard exit 0. PR #100 stays draft with auto-merge disabled; integration needs explicit approval. These checks repair local measurement, not the historical +23.4% acceptance trigger |
| M0 runtime acceptance — maintainer; open, deferred | Retain the [prospective acceptance proposal](#prospective-runtime-acceptance-proposal) and [minimal control changes](#minimal-control-change-proposal) as inactive options, not the next implementation task | No new measurement or criterion adoption. Resume for an actual study execution/cost blocker or a later release review; a new fast run still does not explain the historical trigger |

Completed work stays out of the active queue. **M0-DOC** closed at `bd22c01`:
both archived bodies were preserved with rebased links; 34 local links/fragments,
the Git-free install/load/example/manual smoke, and all 12 ordinary candidate-CI
jobs passed. That historical placement result does not close the newly observed
public-content defects; their bounded correction belongs to row 5 above.
**M0-BOUNDARY** retains the [123-fixture classification](docs/internal/fixture-boundary.md)
and [35 source / seven ordinary-script include review](docs/internal/code-load-boundary.md);
isolated loads passed on Julia 1.10.8 and 1.12.5 without research trees.
Reopen only for changed boundaries/consumers or measured budget pressure, not
to accumulate more completed checks. Relocation, large source decomposition
and new generic controllers remain out of scope. The UX backend proposal may
revisit optional dependencies and API migration for a concrete user workflow;
this roadmap refinement itself changes neither the load nor export boundary.
The single additional **verification C** is complete and is not a cache
experiment. Cold A remains a consumed attempt with observer exit 1; B never
ran. C neither resets nor completes that pair, and no further fit is queued.

### Next implementation handoffs

The fixed-coefficient fit/report/figure/persistence handoff is complete; its
[implementation record](docs/internal/normalized-prior-backend-comparison.md#explicit-exchangeable-prior-api-2026-09-17)
retains the evidence. The following are the implementation details for work-queue
rows 1--2, not an additional registry. Complete one bounded output, update its
status here, and move on. Numerical checks, operability and scientific promotion
have distinct exits.

**1. Observe dense adaptation without changing it.** The question is whether
poorly conditioned adapted geometry coincides with the expensive C2 warmup
windows, rather than assuming that short windows are the cause. Reuse the
private sampling observer and the [owned probe recipe](scripts/profile_fixed_coefficient_sampling.jl).
At the installed library's five update boundaries (100, 150, 250, 450, 950),
record finite/symmetric/positive-definite status, extreme eigenvalues and the
condition number of the adapted inverse-mass matrix. Preserve matrix meaning
and update timing: the callback's matrix is post-update, while its transition
statistics describe the just-completed trajectory. Compare it with subsequent
work and step sizes; copy only what the calculation needs and never mutate or
retain mutable sampler state. Attribute observation overhead separately.

First verify event timing, unchanged draws/statistics and unchanged RNG on small
fixtures under supported Julia versions. The resource proposal for an actual
C2 observation is at most one call per metric, in sequential fresh processes,
with the existing one-chain/1,000-warmup/100-draw controls, 1,200-second deadline
per process and observed 8 GiB RSS/5 GiB output stops. Freeze the recipe,
environment, inputs, seeds and attempt limits before execution; this roadmap
edit launches none. A timeout or missing metric is retained as an unresolved
observation. Stop after the declared observations and record whether the
conditioning/work association is present, absent or unresolved. Association
alone is not causation. If warranted, specify one separate adaptation contrast
with matched total warmup and diagnostics before running it; no automatic
schedule sweep, criterion relaxation, new default or four-chain rerun follows.

**2. Generalized correlation: engineering path complete; prepare acceptance.**
The 2D, fixed-Q, between-item MGMFRM with estimated positive active loadings
and rater consistency now connects numerical checks, maintained fitting,
prediction and saved-result reports/figures. It remains separate from the
fixed-coefficient MFRM correlation API. The completed equation-to-code review
below uses the [candidate](src/mgmfrm_free_correlation_candidate.jl),
[model contract](src/model_family_contract.jl) and
[blockwise measures](#blockwise-specification-and-comparison-contract).
The [first acceptance packet](docs/internal/mgmfrm-first-acceptance.md) selects
the identity-correlation branch for initial qualification. This correlated
implementation retains its own later acceptance question and evidence; carry
its explicit target, loading/ability scale and joint prior into that review. The candidate's raw-coordinate prior,
normalized source reference and exchangeable-rater model must not be treated as synonyms or silently chosen
as a new scientific default. Keep literal 1.7 for the corresponding likelihood;
1.702 metadata and fixed-coefficient unit-logit adapters have their existing
meanings. Account for every transform/Jacobian exactly once in common coordinates.

Retain the candidate's pure-item and per-person dimension-coverage restrictions
until a separately justified model replaces them. Distinguish likelihood
identification, prior anchoring and population correlation from posterior draw
correlation. Inventory which target, sampler, failure handling, result/cache,
prior-predictive, diagnostic and figure consumers already work; implement only
the missing connections in those paths. Exit the implementation slice with
independent equation and Julia/CmdStan density/gradient checks, affected boundary
checks, bounded fitting and named-quantity save/reload/report/figure agreement.
Use explicit model/prior identities; preserve existing saved types and targets.
A statistically qualified posterior comparison and domain acceptance remain
separate requirements. Declare target-specific fit controls, attempt counts and
resource stops; the fixed-coefficient C2 timing is not a cost estimate for
estimated loadings. Neither this slice nor its contract waits for the full
fixed-coefficient validation grid or an Uchihara analysis.

**Code trace for handoff 2, 2026-09-21.** The existing candidate is a
concrete raw-coordinate model, not an unspecified choice of correlation prior.
This trace characterizes that target; it does not adopt it as the scientific
default or declare the source/exchangeable variants equivalent.

For the admitted pure-Q item i, its adjacent-category logit is
`1.7 * gamma_r * (a_i,d(i) * theta_p,d(i) - b_i - r_r - s_i,h)`.
Active loadings are positive; rater consistencies are positive with product
one; severities sum to zero; the stored baseline step is zero and the remaining
steps sum to zero. Given rho, ability pairs have covariance
`person_sd^2 * [1 rho; rho 1]`. The remaining free coordinates keep the base
independent normal priors, including log-loadings and free log-consistencies.
Their positive transformations add no Jacobian to this raw-coordinate target.
The current candidate admits integer eta from 1 through 10,000; a broader eta
domain needs its own normalizer and input checks. The rho prior is LKJ(eta) in
`d rho`; with `rho=tanh(z)`, its normalized density
in `d z` is `eta * log(1-rho^2) - log(B(1/2,eta))`. Each person's bivariate
normal separately contributes its covariance normalizer. At z=0 the full target
reduces to the independent raw-prior target minus the LKJ normalizing constant;
this is a useful numerical reduction, not a source-prior fidelity claim.

Positive loadings and named pure-Q dimensions restrict orientation, but the
conditional likelihood still admits positive dimension rescaling
`theta_p,d -> c_d*theta_p,d`, `a_i,d -> a_i,d/c_d`, and location shifts
`theta_p,d -> theta_p,d+h_d`, `b_i -> b_i+a_i,d*h_d` for pure items.
These transformations change the declared priors. Explain the role of the
population model and priors in setting scales/locations; neither a finite
posterior nor successful sampling proves rating-only identification. Preserve
pure-item/coverage restrictions and test sparse overlap before extending Q.

| Path inspected | Reusable implementation | Concrete missing connection / check |
| --- | --- | --- |
| Equation, density and derivatives | Existing likelihood/prior functions plus `_mgmfrm_correlated_2d_contract` and its target identity; independent-equation and native derivative checks | Carry the implemented identity into the eventual specification/results; keep normalized source/exchangeable variants separate and retain the numerical regression cases |
| Julia sampling | `_mgmfrm_correlated_2d_sample` now uses the maintained sampler/observer/error path, snapshots the canonical target and retains warmup coverage; the old research loop remains separate | Bounded engineering tests cover the path, observer invariance and explicit failure context. A statistically qualified sampling comparison still needs its declared controls, budget and attempt stops |
| CmdStan | `src/stan/mgmfrm_correlated_2d.stan` now reuses the response kernel and corrected shared correlation function; private family/data/initial/named-output adapters and numerical checks are implemented | The maintained private sampling/result path now runs a bounded native engineering check, including normalized posterior validation and reload. The explicit experimental entry also uses this maintained route. Predictive/report/figure consumers now replay saved fits; a statistically qualified posterior comparison still needs its own design and budget; substituting the fixed-coefficient model still changes the target |
| Fit, prior and persistence | `Experimental.correlated(spec)` now returns a dedicated MGMFRM specification; fitting requires explicit `GeneralizedPrior`. A dedicated result and manual fit-cache schema preserve the validated sample identity, eta and z/rho | Public summaries, MCSE, diagnostics, metadata and full artifacts are connected. Existing independent `MGMFRMFit` and its v1 cache remain unchanged; scientific target selection is not implied by the new entry |
| User outputs | Public raw/direct summaries, MCSE, parameter/block diagnostics, warmup and whole-result warnings now rebuild from the explicit result after save/reload; a runnable example and operation limits accompany it | Joint-prior simulation and conditional existing-row posterior probabilities/checks are connected, with raw z/model rho and prior identity preserved. Reports, exported tables and dimension-labelled figures are connected. Preserve their interval/seed and warning semantics in the acceptance review; this workflow is not scientific acceptance |

The [numerical target and transport handoff](docs/internal/normalized-prior-backend-comparison.md#generalized-2d-correlation-numerical-target-2026-09-21)
is complete: 120 declared points were compared through native density/gradient
evaluation and 104 through standalone generated quantities. Extreme-tail
testing found and corrected a shared Stan derivative-underflow defect; the
record distinguishes the subnormal CSV limitation from model arithmetic.
The [maintained sampler and private sample-record handoff](docs/internal/normalized-prior-backend-comparison.md#generalized-2d-correlation-maintained-sample-records-2026-09-21)
now connects both backends, warmup, diagnostics, private summaries/MCSE and
validated save/reload. The [explicit experimental specification/result interface](docs/internal/normalized-prior-backend-comparison.md#explicit-correlated-mgmfrm-interface-2026-09-21)
now requires a declared generalized prior and connects public summaries, MCSE,
diagnostics, full artifacts and manual fit caches. The [prediction handoff](docs/internal/normalized-prior-backend-comparison.md#correlated-mgmfrm-prior-and-posterior-prediction-2026-09-21)
adds normalized LKJ/joint-ability prior simulation, conditional existing-row
posterior probabilities and score checks, and replay of previously saved Julia
and CmdStan fits. It neither integrates new facet levels nor turns same-data
agreement into predictive validation. The [report/figure handoff](docs/internal/normalized-prior-backend-comparison.md#correlated-mgmfrm-reports-and-figures-2026-09-21)
now connects public/full reports, portable tables, five figure kinds and replay.
The implementation preserves model-coordinate intervals/MCSE, raw z/model rho,
saved prior scales, conditional prediction and whole-fit warnings. It also fixes
signed-zero and large-integer corruption in the shared JSON reader without
changing the existing hash or fit-cache formats. Optional CairoMakie figures
use the report's intervals, selected draws and local RNG policy; the generic
example saves and reloads a complete warning-bearing report.

The current workflow gap is closed for the declared experimental operations.
The next **acceptance handoff** has three concrete outputs:

1. **A reviewable claim and operation matrix.** Use the existing protocol owner
   to distinguish identity-correlation MGMFRM's proposed first acceptance domain
   from this explicitly selected correlated raw-prior model. Record the target,
   population/likelihood/prior meaning, primary estimands, admitted designs and
   unsupported extrapolations. The live operation matrix is
   `Experimental.surface_contract(model)`; stored fit metadata remains the
   historical capability baseline so old artifacts retain their identity.
   The [application-informed packet](docs/internal/applied-mgmfrm-acceptance.md)
   supplies the intended user decisions, an explicit application-model proposal,
   mechanism-specific validation contrasts and the gaps in current support.
   The user has accepted a synthetic application example: the implemented
   paired-rating generator supplies observed views and separately stored truth
   without reading empirical data. The [A0 reference](docs/internal/paired-rating-reference.md)
   adds a matching normalized target, short Julia/Stan engineering fits and
   saved-result consumers. Qualified inference and target-specific scientific
   acceptance remain open; no ordinary package API or defaults change.
2. **The smallest defensible validation design.** For each question, state its
   design contrast, truth or reference, statistic and meaningful margin (or
   explicitly descriptive interpretation). Separate joint-prior SBC, fixed-truth
   recovery, prior sensitivity, application adequacy and backend agreement.
   Specify independent generation, all-attempt accounting, precision targets,
   target-specific cost observations, total budget and stopping rules before
   launching fresh evaluation. Reuse the existing protocol rather than another
   generic controller or automatically expanding the reference-model grid.
3. **Independent review and a reader task.** Prepare a concrete packet for a
   named reviewer, with accept/revise/inconclusive decisions tied to the exact
   target and code revision. The reviewer remains unassigned. Separately have
   an unfamiliar reader follow the example to choose a prior, identify the
   warning, interpret rho versus predictive intervals, and reopen the bundle.
   Record observed errors and revisions; implementer replay is not that review.

These outputs precede fresh recovery/SBC and a qualified posterior comparison.
Scientific M1/M2, reader acceptance, final API migration and release acceptance
remain open; the completed engineering path does not waive any of them.

Bounded posterior comparison follows with target-specific cost/attempt limits. This
order does not require another generic engine, a new research controller,
completion of the C2 evaluation grid, or an application fit. Scientific target
selection and independent domain acceptance remain distinct decisions.

**3. Isolate loading geometry before combining extensions.** The next geometry
question concerns one declared 2D mixed fixed-Q design with pure items and
cross-loaded items, holding latent covariance at identity. Assess fixed
coefficients and estimated positive loadings as distinct targets; do not change
both loading policy and covariance in one contrast. Check design/null directions,
scale/orientation, sparse overlap and which ability/item/loading contrasts are
interpretable. A fixed-coefficient logit-matrix rank check alone cannot establish
joint identification of abilities and estimated loadings. The current Q admission
warnings are not evidence of recovery. Specify model-appropriate diagnostics;
the existing between-item finite-panel location display must not be relabelled as a within-item diagnostic.

A new correlated-within-item target needs its own identification and interaction
checks; deleting the between-item guard is not that implementation. Higher-
dimensional covariance is a separate extension, not a prerequisite for the 2D
combination. It needs a positive-definite parameterization, explicit prior
measure/Jacobian and matching CmdStan target. Bifactor additionally needs
named general/specific roles, covariance restrictions and score interpretation.
The [extension sequence](#long-term-extension-sequence) retains these as staged
combinations, followed by reusable random effects and the separately justified
non-compensatory and Q-inference branches. No universal formula/parser or all-model
capability expansion is required to complete these bounded slices.

### Decision handoff and progress accounting

**Assessment updated 2026-09-27; historical baseline at `9cf42fc`, 2026-09-21.**
Use [Current decisions](#current-decisions) for scheduling. The implementation is substantially
beyond a prototype, but the current core targets have not completed the chain
from reviewed scientific specification to fresh evaluation and independently
accepted scope. Measure progress by that chain for each model, not by file,
test, fit or documentation counts. No defensible weighted percentage or calendar
completion date follows from the present evidence. Long-term extensions and the
first accepted MGMFRM domain have different completion boundaries.

| Model/workstream | Evidence actually reached | Next unresolved outcome |
| --- | --- | --- |
| Stable one-dimensional MFRM | Supported fitting, design/anchor checks, diagnostics, persistence and figures in the existing contract | Preserve compatibility and verify the eventual integration candidate; this supporting branch does not complete MGMFRM |
| Scalar GMFRM | Experimental item-discrimination times rater-consistency fitting, both backends and saved-result examples; historical research records remain available | Preserve its distinct unit-scale equation, rater-owned steps and restricted prior/scope. Its existing checks do not transfer to multidimensional MGMFRM |
| Fixed-Q MGMFRM with identity latent correlation | Experimental Julia/CmdStan workflows and explicit normalized priors; distinct raw and normalized comparison records. Candidate C has two independent datasets with qualified transformed fits; four same-data prior-sensitivity fits and their MCSE comparisons are now recorded | The transformed route now connects to the public experimental API. Fixed-facet input/result binding and the six-fit R0/R1 engineering rehearsal are complete; four fits pass and two retain numerical failures. The one pair adds no evaluation credit. Scientific prior/domain selection, claim-specific acceptance and independent review remain open. The raw cohort remains 4/1/269; it is not running or pooled with C. Earlier normalized backend checks do not certify this candidate across designs |
| Fixed-coefficient independent/correlated MFRM | Both backends and explicit exchangeable-prior workflows are connected. A dense Julia C2 follow-up passes its one-panel diagnostic screen | Original C2 backend comparison retains 30 inconclusive statistics; diagnostic-qualified parity, reviewed recovery/SBC and prior sensitivity remain open. This reference cannot validate estimated loadings/consistencies |
| Generalized 2D between-item correlation | Explicit specification/prior, maintained Julia/CmdStan fitting, numerical target checks, summaries/MCSE, diagnostics, prediction and cache/report/figure replay are connected; the old research sampler remains separate | Review this target’s prior/domain and estimands, freeze a bounded validation design, then evaluate it. Short warning-bearing fits and implementer figure review do not establish scientific or reader acceptance |
| Within-item/mixed fixed Q | Some identity-covariance designs are executable with warnings | Establish joint identification and recovery for a declared geometry. Admission/rank checks and between-item evidence do not certify cross-loadings or their combination with free correlation |
| Random effects, non-compensatory kernels and Q inference | Design/evidence plans and reusable diagnostics; no corresponding general fitting support | Implement and validate the bounded combinations in the existing extension sequence; no all-options requirement for the first accepted domain |

The strongest existing assets are the reusable fit/result/report path, explicit
model/prior measures, known-answer and cross-backend checks, and retained failed
attempts. The limiting uncertainty is now which scientific claims those assets
can support on fresh data. Preserve the distinction between a simulation that
tests posterior computation under its joint prior and one that measures recovery
under specified facet truths. Neither replaces an application adequacy check.
The existing [MGMFRM validation protocol](src/mgmfrm_validation_protocol.jl)
and [analysis contract](src/mgmfrm_validation_analysis_contract.jl) own the
[first review candidate](docs/internal/mgmfrm-first-acceptance.md). They retain
their broader Stage-A draft scope and execution blocks. The fixed-coefficient
protocol remains a separate supporting study; no new protocol engine is needed.

**Precision handoff completed, 2026-09-21.** This review found that the public
workflow's `posterior_mcse(fit_result)` call lacked methods for the three
fixed-coefficient result types. The adapter in
[mfrm_fixed_q_samples.jl](src/mfrm_fixed_q_samples.jl) now reuses validated
saved records, model-coordinate reconstruction and the existing MCSE helper.
It supports independent/correlated models, both rater priors and both backend
record formats. Default rows include reconstructed severities/steps, fixed
coefficients, dimension labels and rho; raw rows retain Fisher z. Fixed values
have zero MCSE, insufficient chains/draws remain unavailable, and malformed
chain/iteration records are rejected. MCSE remains a computation-precision
estimate requiring separate convergence review. No sampler, model prior, cache
schema, dependency, export or scientific default changed. The help, public
manual, example and validation protocol now describe this scope; custom
contrasts continue to use per-draw matrix input.

The raw target's Section 30 contains eight paired recovery panels; Sections
31–32 add prior sensitivity and 37 fixed-condition panels with an I2 undercoverage
finding. These results do not transfer to normalized candidate C, whose two
independent datasets currently provide computation evidence. Follow the
claim-specific evidence gaps without automatically increasing the same-fit draw
count. Preserve the prior-only comparison as a post-design interpretive benchmark
and the startup/metadata correction history.

The following **decision sequence** records the earlier scientific handoff in
more detail. Read it under [Current decisions](#current-decisions), not as a
second queue or an instruction to launch an unrestricted simulation grid:

1. **First candidate specified for review, 2026-09-21.** The
   [candidate packet](docs/internal/mgmfrm-first-acceptance.md) fixes an additive,
   pure fixed-Q, two-dimensional identity-correlation MGMFRM with the existing
   raw prior and one dense 50-person/5-item/5-rater/4-category design. It declares
   estimands, 90% primary intervals, existing-level prediction and excluded
   claims, including rater-label invariance. This is a concrete review candidate,
   not a scientific default or completed evaluation. Source reproduction,
   exchangeable priors and correlated dimensions retain separate claims.
2. **Both bounded backend fits qualify; comparison precision remains open.** The core
   candidate now has fixed-raw/joint-prior generation, known-answer checks and
   diagnostic/precision-qualified Julia and CmdStan results. The separately
   bounded CmdStan follow-up retains the initial pre-MCMC launch failure and
   reuses the original Julia result after compatibility checks. Primary-quantity
   comparisons yield 220 within allowance, 83 inconclusive and zero discrepancies.
   All point differences are inside the allowance, but MCSE prevents complete
   agreement. The new all-statistic precision design proposes an equal fixed
   40,000-draw pair if ESS per draw is unchanged; weaker efficiency requires more.
   Batched prediction and nonduplicated full-fit caching are verified. The
   strategic/local reassessment now defers the long pair and resource work;
   current 4,000-draw controls and limits are unchanged. Existing numerical
   evidence is now mapped, with current-target analytic-gradient and native
   Stan checks at 7+2 point/data pairs and all-category likelihood probes.
   These are finite numerical checks, not posterior or calibration evidence.
   Proceed to the scientific proposal below while retaining the 83 inconclusive
   results. Reopen the long pair only for an
   explicit full-comparison claim with a prospective feasible contract.
   Retained Julia MCSE alone limits three item means, so repeating only CmdStan
   cannot resolve them. No automatic extension or threshold change follows.
   Statistical acceptance and the full-comparison claim remain unresolved.
   Keep the metric observation deferred unless it addresses a
   demonstrated blocker; faster adaptation is not a prerequisite. Complete common-coordinate
   Julia/Stan checks and affected fit/cache/report/figure consumers; preserve the completed MCSE
   behavior as these models extend. A real correctness or execution blocker takes precedence;
   broad source decomposition and new controllers need a demonstrated need.
3. **Obtain a target-specific, executable scientific decision.** In the owning
   protocol, connect each question to a design contrast, estimand, score,
   scientifically meaningful margin or explicitly descriptive claim, and
   replication MCSE. Separate N(0,I) person-population generation from fixed-panel
   recovery and deliberate population mismatch; the central sinusoidal truth is
   not representative of the first. Define ID-sensitive predictive quantities,
   SBC test quantities (including a data-dependent likelihood quantity), rank-draw
   dependence handling and missing-category inputs before sampling. Keep the
   full fitted draws, explicit prior sensitivity and all-attempt failure accounting.
   Descriptive predictive accuracy does not automatically claim superiority to
   another model; add a common-split comparator only for that additional claim. Assign the reviewer and record accept/request-revision outcomes
   against the target/revision. The candidate packet now has explicit R0/R1 facet
   truths, fresh N(0,I) persons, 138 proposed SBC quantities and fixed-ID subsets.
   Its 100/225-replicate options imply 444/819 total fits and remain unselected.
   Section 12 now implements generation and low-level ID scoring/quantity selection,
   reuses ties and missing-slot bands, and quantifies a finite negative control.
   Its 100-replicate band detects that toy prior-only error only about 49% of the
   time; the 225-replicate result is not MGMFRM power evidence. Section 13 now supplies fit/diagnostic/ID binding, parameter recovery rows and
   complete-fold assembly. Complete CV-loss MCSE and paired R0/R1/person aggregation;
   settle the single-category boundary, prior prediction, seeds, code revision and
   resources before freezing an execution profile. The hand-built rank/fold tests
   do not replace actual joint-prior or heldout-fit verification.
   Reviewer recruitment does not block this independent implementation work.
   The fixed-coefficient proposal's 5,780 calls and 46.24 million retained draws are planning counts,
   not evidence or a minimum scope. Use measured target-specific pilot costs
   to choose a feasible roster before evaluation; do not extrapolate one C2
   timing to estimated loadings or outcome-tune the evaluation budget.
4. **Run the reviewed evidence and answer its questions.** After research
   readiness and the launch decision, execute only the frozen roster. Keep
   pilots separate from evaluation, unsuccessful primary IDs in denominators,
   and diagnostic/MCSE failures as failures or inconclusive evidence. Report
   recovery, calibration and predictive risk with their simulation uncertainty;
   require both backends to qualify for posterior-agreement claims. A failed
   claim leads to a scoped repair, narrowed support or an unresolved conclusion,
   not automatic retries or changed thresholds.
5. **Complete independent/user acceptance and package delivery.** Reproduce
   selected claims in a separate environment and have an unfamiliar reader
   follow the documented fit-to-interpretation-to-saved-report workflow. Make
   model-level supported/narrowed/rejected/inconclusive decisions. Then verify
   API migration/old-result compatibility, the selected integration revision,
   ordinary CI/distribution checks and the retained M0 release condition.
   Historical candidate CI does not certify this checkout; local branch refs
   also do not establish current remote integration. Apply the accepted slice
   to studies and extend the domain through the existing long-term sequence.

The independent reviewer, scientific margins, full execution budget and launch
remain unassigned/unaccepted where the owning documents say so. These are
specific inputs to the scientific acceptance steps, not reasons to ask the user
to choose the already established Julia-first priority again. The MFRM anchor
study's six decisions stay on its supporting track. Uchihara, ConQuest/TAM and
historical M0 attribution do not become general prerequisites for core work.
M0's release hold remains; its observer correction and historical candidate CI
remain recorded in the [runtime review](docs/internal/fitting-core-runtime-review.md).

At the end of each bounded handoff, update these four points in the owning
work item: the question answered; the evidence and remaining uncertainty; the
claim or user action that is now enabled; and the next unresolved dependency.
Stop or redirect work that only adds more receipts without changing a decision,
removing a demonstrated defect or supplying necessary scientific evidence.
Ordinary fixed-coefficient precision inspection is enabled, and the first
MGMFRM candidate and claim matrix are now concrete. Its evaluation and
scientific acceptance, and generalized correlation integration, remain open.
The [candidate preflight](results/workflows/20260921-core-acceptance-01/verification.json)
records the original equation/prior and fold-support checks without sampling.
The subsequent independent DGP, qualified Julia/CmdStan pilots and retained
initial CmdStan launch failure are documented in the same
[candidate packet](docs/internal/mgmfrm-first-acceptance.md), with
[follow-up verification](results/workflows/20260921-core-cmdstan-followup-01/verification.json).
The 83 inconclusive primary-quantity statistics leave full agreement unresolved. Completion of a
finite computation pilot does not close scientific acceptance; no percentage
increase follows from test counts.

**Verification of this assessment.** Reviewed the repository inventory, active
and supporting plans, model/API/Stan paths, examples, CI definitions and selected
local execution records. At this checkout, 792 sampler-free assertions passed
across model-family/compensation, fixed-coefficient prior/identification and 2D
correlated-density checks on Julia 1.12.5. Initial ordinary loading could not
write a sandboxed precompile lock; rerunning with `--compiled-modules=existing`
passed with ordinary optimization and no CmdStan execution. All 212 artifact
entries in the C2 primary, extended dense and likelihood-replay receipts match
their SHA-256 values. Recalculation from the exported estimates/MCSE/pooled SD
reproduced all 640 normalized-prior comparison decisions; it did not recompute
MCSE from draws or rerun inference. This was a strategic review with focused
checks, not a line-by-line audit, full suite, fresh CI, independent scientific
review, reader walkthrough or new recovery/SBC evidence.

**Verification of the precision implementation.** On Julia 1.10.8 and 1.12.5,
the targeted checks passed 4,379 assertions per version: 3,210 for the new
fixed-coefficient fit dispatch, 1,113 existing prior/reconstruction/backend-
format checks and 56 existing matrix/scalar-MFRM MCSE checks. The 11 synthetic
configurations cover both priors, correlation policies and backend formats,
plus binary steps and a 3D mixed-Q case. Numerical comparisons use per-draw
reconstructed raters/rho, mean/SD/quantile MCSE, fixed/unavailable statuses,
invalid chain layouts, RNG preservation and cache replay. These are engineering
fixtures, not known-truth statistical evaluation; the existing scalar dispatch
test runs only its tiny MFRM sampler check. No new CmdStan fit was run.

The fresh manual built on the installed docs environment; the public language
gate passed all 20 source files and 14 generated HTML files. The build retained
four existing missing-docstring warnings for research helpers, with no new
document-build error. Julia 1.12.5 used `--compiled-modules=existing`; Julia
1.10.8 and the docs build used writable temporary depots where needed. This
was not a clean dependency-install test, full package suite or fresh CI run.
Same-version save/reload passes on both Julia versions. A separate attempt to
load an existing Julia 1.12-format pilot cache on 1.10.8 stopped in Julia's
deserializer before the fit/MCSE methods; cache portability to older Julia
versions is not established by this implementation.

On Julia 1.12.5, replay of the actual C2 Julia and CmdStan pilot caches and
the extended dense Julia cache passed: each produced 153 model-coordinate
rows, rho mean/SD/quantile MCSE matched an explicit per-draw tanh calculation,
and all three source-file hashes stayed unchanged. This checks old-result
consumption, not renewed diagnostic qualification or backend agreement. The
[local verification record](results/workflows/20260921-fixed-q-mcse-01/verification.json)
retains commands, source hashes, successful checks and corrected preliminary
test/depot attempts. The first test failures concerned the test fixture's array
shape and object-equality comparison; neither was a production MCSE discrepancy.

### Research execution prerequisites

Core validation has its own model/design roster and does not depend on a
particular empirical dataset. If an application such as Uchihara is scheduled,
retain its separate input derivation, inclusion rules, estimands, diagnostics,
backend comparisons and resource plan. Development probes and empirical fits
remain outside counts of fresh simulation replications. Core implementation
checks can proceed without waiting for application planning or the independent
review that governs scientific acceptance.

Before fresh M2 evaluation, retain one reviewed source/environment revision
and independently accepted target-specific decisions on model/identification,
cells/estimands, RNG/data allocation, scoring/thresholds, sampler settings,
failure handling, and budgets. The MGMFRM protocol's execution and independent
scientific-review blockers remain open; the anchor sub-study separately
requires all six of its accepted M1 decisions.
For MGMFRM, that acceptance must also resolve the selected loading geometry,
dimension alignment, conditional-information versus posterior-uncertainty
semantics, and source-statistic adoption limits above. Literature-derived
formulas and negative-control examples are inputs to review, not substitutes
for a target-specific validation result.
Verify the actual generation-to-fit-to-score path on that revision, including
truth and category alignment, saved response/source/attempt binding, no
replacement of failed primary attempts, and functioning time/resource stops.
Use the [source/environment requirements](docs/internal/mfrm-anchor-study.md#source-and-execution-environment-declaration-requirements)
to distinguish predeclared inputs, actual producer observations, and later
scoring metadata; collecting optional metadata is not environment acceptance.
Unresolved correctness or data-loss risks block execution; a green historical
CI or the deferred performance proposal cannot substitute for these checks.

M2 preparation and synthetic checks can proceed now. A small cost/pipeline
probe requires an explicit attempt/resource budget and separate pilot data;
it cannot enter evaluation counts. Full evaluation needs a separate launch
decision after readiness is recorded. Software/RNG provenance remains required,
but identical hosted CPU/cache states are not a blanket condition for scientific
recovery evaluation; any timing comparison needs its own comparable conditions.
This removes the former blanket M0-to-M2 dependency, not the M0 release hold,
independent review, or research safety checks.

### Secondary applications: Uchihara, EVA and Chopin

The user's 2026-09-23 clarification makes all three datasets application
examples of the MGMFRM foundation, not its defining objectives. The
[application portfolio and inspection](docs/internal/application-portfolio.md)
records 136,943 filtered EVA image-rater events and the four stages of the
official Chopin score table. EVA adds sparse multi-attribute ratings and
different response scales; Chopin adds raw versus corrected scores, recusal
and selection, with no published criterion-level dimensions in the inspected
table. None of these observations establish a new model's identification or
scientific validity. Core validation retains its own known-truth designs;
application fits and software integration checks do not count as evaluation
replications. The detailed Uchihara plan below remains historical application
evidence, with equal subordinate status.

#### Uchihara 2022 secondary application

This is a retained application plan, subordinate to the Julia foundation work.
The user's 2026-09-21 clarification permits synthetic data for the current
example. The active application deliverable is therefore the
[synthetic paired-rating example](examples/synthetic_paired_ratings.jl), with
12 artificial persons, 37 artificial words, 19 artificial raters and two
nine-category criteria. It generates its own assignment and missingness
positions and saves true parameters and conditional probabilities separately
from observed ratings. It neither reads nor relabels empirical observations.
The following empirical inspection and reanalysis plan are retained for a
possible later real-data application; their unresolved data reconciliation
does not block synthetic development. A matching A0 reference now completes
short engineering fits; scientifically interpretable estimation and uncertainty
remain unestablished. See the [reference contract](docs/internal/paired-rating-reference.md).

Its questions and inspected data inform possible requirements and later examples;
they do not set the package milestones, core defaults or next implementation task.
Schedule its data preparation and extensions when the needed foundation is ready
or a bounded piece directly checks a reusable package behavior. Its completion
is tracked separately from package acceptance.

The substantive problem is whether a word pronunciation can be relatively easy
to understand while still sounding strongly accented, and which properties of
the pronunciation help explain that distinction. Researchers and teachers need
to know what each measure tells them before treating an accent score as a
proxy for understanding. The final report must introduce this problem before
model terminology and follow question -> design and its rationale -> result ->
answer. An observational reanalysis can assess associations and measurement
under this task; it cannot establish a causal teaching effect or general spoken
language proficiency.

The source is Uchihara, T. (2022), *Is it possible to measure word-level
comprehensibility and accentedness as independent constructs of pronunciation
knowledge?*, Research Methods in Applied Linguistics, 1(2), 100011
([article](https://doi.org/10.1016/j.rmal.2022.100011);
[public data](https://osf.io/nc7yp/)). The 2026-09-11 review read the methods,
results and discussion from the Zotero copy and inspected `Raw Data (Speech
Measures).xlsx`, sheet `Speech Measures`, `A1:N5834`. This is an inspection
baseline, not a cleaned analysis dataset or a reproduced model fit.

The 2026-09-21 [read-only reinspection](docs/internal/applied-mgmfrm-acceptance.md#2-今回確認したデータと設計上の帰結)
reproduces the counts below from the local workbook copy and retains its checksum.
It additionally finds 19--33 observed words per speaker, only three words
observed for all 12 speakers, two words observed for only one speaker, and 282
recordings with all three specified phonetic annotations present. Processing
times are also stored for all 55 recordings with intelligibility zero; storage
does not establish outcome eligibility. The local input was not altered, and
no cleaned view or fit was produced. Identity with the current OSF download
and complete reconciliation to the paper's analysis populations remain open.

| Observed unit | Inspected data and implication for the analysis |
| --- | --- |
| Speaker, word and recording | 12 speakers, 37 words and 307 observed speaker–word recordings from the immediate post-test. Of 444 possible speaker–word cells, 137 have no selected production. Preserve the recalled-word selection; do not code absent productions as the worst rating or assume random missingness |
| Ordinal ratings | 19 listeners per recording: 5,833 unique speaker–word–rater rows, 5,833 accentedness and 5,827 comprehensibility ratings on 1–9 scales. Higher original scores mean stronger accent or greater difficulty. Preserve the original columns and document any reversal, latent-score direction and plot labels |
| Intelligibility and processing time | A separate two-listener dictation task; the paper defines intelligibility as both listeners correct and analyzes latency conditional on joint correctness. The workbook supplies one intelligibility value and one time per recording, repeated across the 19 rating rows, without separate listener responses. Analyze these once per recording; do not create 19 independent trials or infer the two individual responses |
| Explanatory features | Segmental accuracy, stress accuracy, vowel-duration ratio and the column named articulation rate are recording-level predictors; syllable count is word-level. Some are human annotations. The paper's rate definition is duration per syllable, so its direction must not be described as syllables per second. Extra `FacetData` columns currently do not make these fitted predictors |

**Application handoff when scheduled: a reproducible data/measurement contract.** Retain the source
URL, retrieved-file checksum, sheet/range, original IDs and a derivation from
immutable input into rating-level and recording-level analysis views. Verify
joins and report sample flow by speaker, word, recording, rater and criterion.
Resolve the six missing comprehensibility ratings; missing vowel ratios for
24 recordings, segmental accuracy for three and stress accuracy for five; zero
values in the rate column; processing-time units, aggregation and eligibility;
and the paper's reported analysis counts versus the workbook. Explain each
exclusion or unresolved discrepancy instead of forcing agreement. Preserve
partially observed rating pairs when the specified model permits them; use
analysis-specific inclusion rules rather than a universal complete-case filter.
Document the 0/1/2 segmental coding and the published stress recoding before
choosing categorical or ordered covariate effects. An unavailable detail narrows
the affected analysis, not every independent implementation task. No additional
data request or contact with the authors is authorized by this plan.

| Research question | Analysis and why it addresses the question | Required evidence and limit |
| --- | --- | --- |
| How do comprehensibility and accentedness relate after accounting for word and rater differences? | Fit named, correlated speaker dimensions to the paired ordinal criteria, with word effects and dependence among ratings of the same recording. Contrast a declared common-dimension reference with the two-dimension model where identifiable | Report speaker profiles, population-correlation uncertainty, predictive adequacy and prior sensitivity. The paper's pooled rating correlation is not the speaker-population correlation; 12 speakers remain 12 speaker-level units despite thousands of ratings. A wide posterior or prior dependence limits claims of distinctness or independence |
| Do raters treat the two criteria differently, and does generalized scoring help? | Allow criterion-specific severity; compare fixed loading/unit-consistency multidimensional MFRM with explicitly selected MGMFRM loading and consistency blocks under matched scales, thresholds and dependence structure | Report rater contrasts, uncertainty and predictive/recovery consequences. Free one block at a time if attributing its benefit; a joint change supports only a combined comparison. More parameters or a better in-sample fit is not itself an improvement |
| Which phonetic properties relate differently to the criteria? | Add declared recording-level predictors and a separately identified word-level syllable effect; estimate criterion contrasts jointly | Report comparable predicted-category effects and uncertainty, plus coefficient contrasts only on declared comparable scales. A significant effect for one criterion and a nonsignificant effect for the other does not establish a difference. Explain total versus feature-adjusted speaker traits; annotation overlap with intelligibility and observational confounding limit interpretation |
| What do the two rating constructs tell us about successful recognition and processing time? | Relate recording-level latent predictions to the published joint-correctness event and eligible latency, propagating rating-model uncertainty. Evaluate heldout recordings where feasible, keeping all their criteria/raters in the same split and fitting outcome relationships on training data | Report associations and predictive uncertainty for these aggregate outcomes and the conditional latency population. Do not duplicate the outcome across listeners, plug in uncertain scores as error-free, or claim that a separate two-listener panel supplies a third 19-rater ordinal dimension. Holdout design must state the prediction target and implement integration for the heldout recording effect; generalization to new speakers, words or raters needs separate support |

The original paper already used mixed models with speaker, word and listener
effects. Reproduce the relevant published summaries and analysis populations
as a reference, recording any unavailable specification; the contribution is
the joint ordinal measurement model, explicit uncertainty and new contrasts,
not the first recognition of three crossed facets. The already inspected
published results make this a theory-directed reanalysis, not a new independent
confirmatory sample. Keep known-truth simulation evidence separate from its
empirical findings.

The minimum model proposal for this application is a **confirmatory, two-trait
correlated ordinal model**. Define a measurement item as word × criterion for a pure-Q
mapping while retaining the shared physical-word and recording IDs. Each
response measures its named criterion; two criteria on one word do not require
within-item cross-loadings. Specify the adjacent-category equation, category
steps (including shared versus item-specific structure), score direction,
location/scale constraints and the placement of the rater multiplier before
implementation. A fixed-loading, unit-consistency MFRM reference and the selected
generalized extensions must agree conditionally when the extra coefficients
are fixed under the same scaling; zero prior SD is not a fixed-parameter API.

#### Application sequence and reusable dependencies

Explicit experimental independent/correlated fixed-coefficient fits and the
correlated estimated-loading MGMFRM now have Julia/CmdStan, prediction, manual
caches and report/figure workflows. Application-specific recording effects,
criterion-specific rater constraints, a justified step-sharing policy and fitted
predictors still need their contracts and extensions. The [application packet](docs/internal/applied-mgmfrm-acceptance.md#3-応用モデルの最小候補と実装の境界)
proposes a fixed-coefficient A0 with separate speaker/recording covariance,
criterion-specific rater severity and criterion-shared steps before a named
generalized comparison. This changes neither current defaults nor the primary
package acceptance target. Reuse existing likelihood/transforms where the
accepted equation matches; an explicit population correlation alone, composite
rater IDs or metadata-only predictor columns do not provide the missing effects.

| Analysis output | Reusable capability or application prerequisite | Comparison and reporting condition |
| --- | --- | --- |
| Analysis-ready views and sample flow | The retained data/measurement contract; outcome-specific event keys, physical IDs, score directions and inclusion rules. Keep ordinal ratings in a criterion-labelled long view and outcomes/features in a unique recording view | Reconcile the inspected counts and exclusions without multiplying outcomes through joins. Preserve missing productions and partially observed rating pairs. The aggregate read-only inspection is complete; analysis-ready views and eligibility decisions remain. This application preparation proceeds separately from core acceptance and does not authorize an empirical fit |
| Unadjusted joint measurement — primary application model | Public fixed-coefficient workflow plus correlated traits, identified word/criterion effects, criterion-specific rater severity and a justified shared-recording structure. Keep fixed loadings/unit consistency and fixed pure-Q as the reference | Fit the two-criterion ordinal ratings without requiring complete phonetic covariates. Compare a separately specified common-dimension reference where identifiable, using matched observations, score directions and nuisance structure. Report speaker profiles, population-correlation uncertainty, recording dependence, prior sensitivity and predictive adequacy |
| Generalized scoring — named comparison | Explicitly selectable loading and rater-consistency blocks with the same dependence structure and a declared likelihood/parameter/prior scale mapping | Add one block at a time when attributing its effect, or label a joint change as a combined comparison. Unit-logit MFRM and the literal `1.7` MGMFRM baseline are not automatically a nested prior-matched comparison. Keep the same eligible observations, thresholds and intended prediction target |
| Phonetic associations — adjusted model | Predictor coding/transformations and criterion-specific coefficients; an identified hierarchical word effect for syllable count and a declared treatment of missing annotations | Distinguish adjusted from total speaker traits. Compare adjusted/unadjusted models on matched eligible observations or under an explicit missing-data model, and retain the full-rating unadjusted analysis separately. Report predicted-category contrasts and uncertainty; changing the analysis population must not be attributed solely to phonetic adjustment |
| Recognition and eligible latency — secondary outcomes | One published joint-correctness event and eligible latency per recording; a specified outcome model that propagates rating uncertainty and declares whether feedback is allowed | Choose a predictive task, available inputs and grouped heldout split before fitting. Train transformations, measurement/outcome relationships and any structural selection inside that split as required by the task. Integrate unknown heldout effects, retain both stages' provenance and compare the same computational target in Julia/CmdStan. No duplicated outcome trials or reconstructed individual dictation responses |
| Reproducible answers and figures | Saved primary/comparison fits, diagnostic-qualified backend comparisons, application-specific validation and the existing report/figure bundle | Reopen in a separate environment and reproduce named contrasts, uncertainty and plots within stated tolerances. Explain each question's answer and limits. Broader Q learning, within-item, bifactor and non-compensatory models enter only for an explicit additional measurement question; their completion is not required for this application |

Resolve the allocation of shared variation before fitting the primary model:
retain the physical rater as well as criterion IDs, and define whether recording
effects are shared scalars or criterion-specific vectors. Keep speaker-population
correlation separate from recording-level covariance. Specify an identified
word/criterion hierarchy rather than adding a redundant free word effect to
unrestricted word × criterion difficulties. A word-level syllable predictor
must use that hierarchy or another explicit identifying constraint. Choose the
smallest justified dependence structure and assess its restrictions; do not add
unrestricted covariance matrices at every level by default.

The common-dimension reference needs its own equation and identification; do not
implement it by sending a perfect correlation into a nonsingular covariance
sampler. Report whether the data distinguish the proposed models under their
priors, rather than treating one fit statistic as proof of construct independence.
Thousands of rating rows do not increase the number of speaker-level units
beyond 12. Application validation must separate uncertainty about speaker
correlation from recording-level associations; a larger-speaker comparison
answers a small-sample question rather than changing the empirical population.

The first secondary-outcome implementation can propagate the rating posterior
into a recording-level model with an explicitly specified no-feedback target.
It must propagate model/parameter uncertainty rather than use posterior means
as error-free predictors, and preserve the linkage between its saved stages.
A fully joint binary/ordinal/continuous likelihood is a later alternative with
different feedback semantics. Listener-specific dictation modeling additionally
requires individual responses absent from the inspected workbook. Neither is
a prerequisite for Julia core acceptance or the unadjusted ordinal analysis.
Exact secondary likelihoods, missing-data choices and API signatures remain to
be selected with their model contracts; this table does not implement them.

When validating this application, target its 12-speaker/37-word/19-rater design and its
observed sparse speaker–word coverage. Use a small set of known-truth conditions
that tests trait correlation, fixed versus generalized scoring, recording
dependence, criterion-specific raters and feature contrasts. Include prior
predictive checks, recovery/calibration with failure denominators, and selected
prior/missingness/dependence sensitivities; a larger-speaker comparison is useful
only if it answers an explicit small-sample limitation. Predeclare the needed
precision and resource envelope instead of inheriting the old full panel.
Numerical backend agreement checks implementation; these simulations assess
estimation under assumptions; observed-data checks assess adequacy for the case.

**Application-specific acceptance:** the public-data recipe, selected equations/priors,
Julia and CmdStan executions, diagnostics, posterior comparisons, targeted
validation, sensitivity results, figures and report form one reproducible path.
Both backends must estimate the primary empirical model and named fitted
comparisons supporting the conclusions, with adequate diagnostics and declared
Monte Carlo tolerances; a Julia result plus an untested Stan translation is
incomplete. Retain model/environment identity, attempts and limitations through
the existing artifact/report paths. A separate environment must reproduce the
declared claims and figures within their stated tolerances.

Required figures cover the observed design/missingness; paired speaker profiles
and latent-correlation uncertainty; criterion-specific rater effects and any
estimated loadings/consistency; phonetic effect contrasts; posterior predictive
ratings and recording-level intelligibility/latency results; and chain diagnostics
for both backends. Report population correlation separately from correlations
among posterior draws or recording scores. Users must obtain and export these
from saved fits without manually reshaping draws. Use the existing
[figure/report acceptance](#figure-and-report-acceptance), including editable
plots, publication exports and uncertainty labels. The report must answer each
question in words, distinguish the original result from the reanalysis and
simulation, and state the narrow task/population to which the evidence applies.
Stable-public promotion of every package feature is a separate release decision.

### M0 runtime acceptance handoff

**Implementer assessment: insufficient evidence to accept M0 under the current
runtime criterion; maintainer disposition pending.** The retained
[historical comparison](#comparable-ci-timings) is arithmetically valid:
1,061s -> 1,309s, an increase of 248s (23.4%). Its two three-job windows share
`bd22c01`, so they contain five distinct jobs, not six independent observations.
The percentage is a monitoring trigger, not an identified causal effect.

Across those five revisions and the `0881fd4` follow-up, `src/`,
`test/runtests.jl`, the workflow, and `Project.toml` are byte-identical.
This does not identify the old CPU, effective cache, native binaries, or host
load, nor show that the package meets the runtime acceptance criterion.
The [16-job review](docs/internal/fitting-core-runtime-review.md#findings-and-limits)
characterizes later costs; the observer repair addresses the local measurement
failure. Neither establishes the cause of the historical increase.

The retained-evidence review is complete, not the acceptance gate. Drafting the
proposal below was authorized; changing the criterion or running it was not.
The maintainer may retain the current hold, reopening attribution for evidence
that addresses the historical trigger, or review the explicit policy change
below. M1/M2 preparation takes priority; fresh evaluation follows the research
prerequisites above instead of waiting for this historical attribution.

### Prospective runtime acceptance proposal

**Deferred draft only; the existing M0 release criterion still applies.** Proposed scope: accept
current, cohort-specific engineering operability while retaining the historical
+23.4% alert as **unexplained, with explicitly accepted residual uncertainty**.
This replaces the requirement to explain/remediate that alert for M0 acceptance;
it is not an explanation, a performance improvement, or a scientific finding.
A named maintainer must approve that tradeoff and its rationale before adoption.
Rejecting the change leaves M0 on hold without more automatic measurements.

| Decision | Proposed rule, inactive until approved |
| --- | --- |
| Workload and revision | Use only the existing Linux `fitting_core` job: the unchanged 2,641 + 114 assertions, seeds, draws, and compilation-inclusive test block. Proposed reference is `5c4bff2`; freeze the full checkout SHA before execution. A different candidate needs review, not a silent substitution. All 12 ordinary CI jobs must also pass for the exact candidate being accepted |
| Comparison cohort | Predeclare and verify the actual CPU model/Julia target, exposed CPU and memory class, OS image/provisioner, exact Julia build, effective dependency graph/native binaries, thread and compilation flags, and workflow/action versions. Match these within a batch and across compared batches. `ubuntu-latest` and Julia `1` labels alone are insufficient. Changed workload or unmatched environments require an explicit new-baseline decision, not pooling or CPU-normalizing old timings |
| Cache inputs | Before execution, choose one identifiable initial cache lineage/key/version for every attempt, or an explicit no-restored-cache regime for all. Retain restored provenance and emitted precompile work. A rebuild despite matching inputs remains an outcome, not an exclusion or permission to warm and retry. Unknown/mismatched inputs make the comparison inconclusive |
| Primary outcome | Preserve whole-job elapsed seconds, including setup/cleanup and excluding queueing. Retain command elapsed, compilation-inclusive block time, and both test and observer outcomes as diagnostics; do not replace the primary metric with a faster nested timer. Local macOS C and cold A are not Linux baseline observations |
| Initial baseline | Schedule exactly three attempts at one approved revision/cohort. All three must be comparable, successful, and within the existing 30-minute job limit; retain their individual times and freeze their median as the prospective reference. An incomplete batch cannot become a successful-only median. No relative speed or non-regression conclusion is available from this initial batch |
| Subsequent monitoring | Require the same comparability, success, and deadline checks for a separately authorized, non-overlapping three-attempt candidate batch. Using unrounded medians, `median(candidate) / median(reference) > 1.20` requires explanation/remediation and blocks runtime acceptance even when each job is under 30 minutes. Never slide the reference to absorb a slowdown. A ratio at or below 1.20 satisfies only this operational warning rule, not statistical equivalence or a causal/no-regression guarantee |

**Budget proposal:** at most three `fitting_core` job attempts for the initial
baseline, each retaining its existing 30-minute CI timeout, plus at most 15
minutes of no-fit preparation. These are job limits, not a guaranteed total
wall-clock bound or three individual model fits. Stop on failure, timeout,
cancellation, observer error, or missing/mismatched comparison inputs; retain
every started attempt and do not replace it. No fitting warm-up, full-matrix
rerun, `workflow_dispatch`, replacement host provisioning, or cold/warm-pair
restart is included. If the existing job cannot be isolated and its cohort/cache
inputs verified within this scope, stop as inconclusive instead of building a
new runner. A later comparator batch needs its own approval and attempt budget.

The three-attempt median, 20% warning, and 30-minute ceiling retain the existing
operational policy choices; they are not a power calculation or a confidence
bound. Hosted jobs use fresh runner environments ([GitHub runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners));
cache-key matches concern restored files ([cache reference](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching)),
while Julia timings can include compilation ([Julia performance guidance](https://docs.julialang.org/en/v1/manual/performance-tips/)).
These sources motivate recording conditions, not the numerical acceptance rules.

**Execution feasibility, read-only review on 2026-09-06: not ready under the
unchanged CI.** [Candidate job 101415767832](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/34006928912/job/101415767832)
and its resolved action sources establish the following limits, not another run:

- **Job isolation is available in principle.** GitHub supports rerunning one
  job and its dependent jobs; the existing workflow has no `needs` dependencies.
  The verified fitting-job `databaseId` is `101415767832`. No rerun was executed.
  The cancellation API is run-scoped, so a future stop procedure must first
  ensure no other work is active in that run ([GitHub workflow-run API](https://docs.github.com/en/rest/actions/workflow-runs#re-run-a-job-from-a-workflow-run)).
- **Runtime inputs are observed, not fixed.** The job used AMD EPYC 9V74,
  Julia target `znver4`, Julia 1.12.7, and image `20260831.293.1`;
  `ubuntu-latest`, Julia `1`, and major-version action tags do not freeze them.
  Only `Manifest-v1.10.toml` is tracked; it does not lock Julia 1.12's environment
  ([Pkg manifest selection](https://pkgdocs.julialang.org/v1/toml-files/#Different-Manifests-for-Different-Julia-versions)).
  The current `Pkg.test()` path does not enforce a frozen root/test dependency
  graph or native-binary identity before fitting. Same source SHA is insufficient.
- **Initial cache inputs advance.** The [exact cache action used](https://github.com/julia-actions/cache/blob/d10a6fd8f31b12404a54613ebad242900567f2b9/action.yml)
  puts `run_id`/`run_attempt` in the save key, restores by a shared prefix,
  updates restored registries, and defaults to deleting older PR caches.
  This job restored the `34004236027` attempt-1 cache and saved a new
  `34006928912` attempt-1 cache; deletion of three older caches failed.
  An unchanged rerun therefore does not enforce the same starting cache.
  Do not delete caches or broaden permissions to manufacture comparability.

These are gaps against the stricter draft, not failures of ordinary CI or the
local observer repair. No rerun, cache mutation, or workflow change was made by
this review. Defining controls beyond the existing-job scope requires a separate
scoped proposal; do not spend the three attempts hoping their inputs match.

Before any execution approval, name the maintainer, final SHA, available Linux
cohort, exact environment/cache inputs, and a job-only launch/stop procedure.
Those execution inputs remain unresolved. If the proposal is adopted and its
baseline plus all other M0 checks pass, the maintainer may explicitly accept M0
with the historical exception recorded; this is never automatic or independent
scientific acceptance. Neither approval to draft, policy adoption, nor a green
baseline authorizes a merge or changes M1. M2 follows the separate research
execution prerequisites; this performance proposal is not its launch authority.

### Minimal control-change proposal

**Deferred design, not implemented or execution-ready; no longer the next
task.** If this performance investigation is explicitly resumed, the minimal
candidate is one no-restored-cache path with rejection of mismatched inputs.
Its first implementation would be a bounded Linux **no-fit preflight**; reuse the
[existing native-environment checks](docs/internal/fitting-core-runtime-review.md#preflight-result-and-execution-gate)
and POSIX guard. Do not build a runner, cache service, or benchmark controller.
The controls below describe the eventual comparison, not permission to launch it.

| Boundary | Minimum proposed control and remaining limit |
| --- | --- |
| Host and runtime | Predeclare one CPU/target, exposed CPU/memory class, exact image/provisioner, Julia build, and resolved action SHAs. Check the host before expensive preparation, then actual Julia/Pkg, native libraries, threads, and flags before fitting. Missing or different inputs stop the batch; do not learn the accepted cohort from whichever attempt finishes. An explicit Ubuntu release label still does not select an exact CPU or image build |
| Root and native test environments | Prepare and retain Linux-specific root and effective test Project/Manifest files, preferences, package/artifact identities, and actual loaded BLAS identity. Use `Pkg.test(; allow_reresolve=false)` plus equality checks in its native merged test context and the root context used by the plan subprocess. The option alone does not freeze test-only dependencies. Re-audit the one-off private hook for the exact Julia 1.12.7/Pkg build and payload; the macOS 1.12.5 locks, native binaries, and hook are not a portable Linux implementation |
| Starting state | For every eventual job, start a fresh task-owned depot with no restored third-party packages/artifacts/compiled caches or user-depot fallback; retain the pinned Julia bundle's own resources. Bypass the cache action entirely, including save/delete hooks, rather than deleting existing caches. Replace the build action's implicit preparation with explicit locked setup; freeze any required registry input and verify installed artifacts. Keep preparation/download/build/precompile work inside whole-job elapsed time, then use Pkg offline mode for the fit. This is a cold-depot operability condition, not a cold OS page cache or an ordinary warm-cache CI estimate |
| Preflight and measurement | Reuse the guard and version/payload-checked native no-fit path in a separate disposable depot; never transfer its compiled cache into a measured attempt. Check the real test and plan children, not only a parent probe. Retain the two unchanged fitting testsets and compilation-inclusive block. One attempt remains one whole CI job, including setup and cleanup; three fits inside one job or local command times cannot substitute |

[Pkg's test API](https://pkgdocs.julialang.org/v1/api/#Pkg.test) and
[Julia depot semantics](https://docs.julialang.org/en/v1/manual/environment-variables/#JULIA_DEPOT_PATH)
support these mechanisms, not their Linux verification. Pkg offline mode is not
a network sandbox. Guard/check overhead remains part of the chosen measurement
boundary; do not suppress compilation or move setup outside the primary timer
to fit the 30-minute ceiling.

The first implementation slice would contain only the task-local Linux preflight
and its frozen input files; package/test sources and ordinary CI stay unchanged.
Within the proposed 15-minute no-fit preparation cap, require a valid native
launch, rejection of changed graph/payload/flags, untouched cache-flags probe
output, and unchanged source/locks. Stop on failure; no fit or replacement
attempt follows. Exact Linux inputs and an available execution context still
need to be supplied and reviewed; none was provisioned or captured in this edit.

Only after that feasibility check may a separate CI-wiring decision be made.
Keep ordinary current-Julia compatibility coverage: silently pinning its
`fitting_core` lane would narrow that coverage. Any controlled CI path needs a
reviewed checkout/workflow SHA, isolated launch/stop route, and explicit approval
of publication and every resulting CI run; `5c4bff2`'s green result does not
validate those changes. Count all started baseline jobs, including pre-fit
rejections, and launch sequentially so a failure stops further attempts.

**Residual limit:** fail-closed checks prevent mismatched comparisons; they do
not guarantee three matching hosted jobs or fixed host load. If the declared
cohort is unavailable, retain an incomplete batch without host-shopping,
replacement runs, relaxed controls, or a larger timeout. A guaranteed fixed
execution environment would be a separate infrastructure decision, not this
minimal implementation. M0 and the historical +23.4% exception remain open.

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
- `bc36adc`'s [independent log-truth check](docs/internal/mfrm-anchor-study.md#independent-log-truth-boundaries)
  extends the existing standalone primitive and feeds its logs into the
  24-scenario scoring check. No probability-kernel copy or export is added.
  The 277 new assertions bring the anchor file to 4,479; together with 103
  scorer and 2,168 unchanged LD assertions, 6,750 pass on Julia 1.10.8 and
  1.12.5. All 22 legacy LD raw outputs match the preceding revision within
  each environment; three memory-only numerical mistakes are detected.
  [CI 33970171857](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33970171857)
  passed all 12 ordinary jobs: `fitting_reports` at 30 / 8,155 and the full
  Julia 1.10.8 job at 97 / 19,273 in 30m10s. Both manual research jobs were
  skipped. Its CI does not certify subsequent revisions or close M0.
- `fe80126`'s [labelled JSON/scoring check](docs/internal/mfrm-anchor-study.md#labelled-json-roundtrip-and-scoring-boundary)
  reuses the existing JSON conversion and array scorer, adding one private
  label-alignment helper. All 4,531 anchor and 103 scorer assertions pass on
  Julia 1.10.8 and 1.12.5. The 52 new checks preserve tiny finite values,
  structural zero/infinite loss, missing records, and primary-attempt counts
  through temporary-file roundtrips; two memory-only mistakes are detected.
  [CI 33971936154](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33971936154)
  passed all 12 ordinary jobs: `fitting_reports` 31 / 8,207 and the full
  Julia 1.10.8 suite 98 / 19,325 in 20m13s. Both manual research jobs were skipped.
  Durable truth/RNG storage, full dataset/attempt binding, the persistent ledger,
  thresholds, and review remain open. No export, dependency, retained fixture,
  sampler, or evaluation replication is added; runtime acceptance stays open.
- [PR #97](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/pull/97) merged
  the verified `fe80126` head into `main` as `e8bc648` on 2026-09-06 JST,
  preserving individual source commits. This is engineering integration only:
  no release/tag/registration, research dispatch, or M0/M1 acceptance was made.
  Its [main CI 33973332148](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33973332148)
  passed all 12 ordinary jobs; the full Julia 1.10.8 suite passed 98 / 19,325
  in 33m36s. Both manual research jobs were skipped.
- `2f4f431`'s [attempt-identity/native-replay check](docs/internal/mfrm-anchor-study.md#attempt-identity-join-and-native-replay)
  adds 76 identity assertions and four native-save/replay assertions, reusing
  existing code and stdlib Serialization. The 4,611 anchor and 103 scorer
  assertions pass locally on Julia 1.10.8 and 1.12.5.
  [CI 33973824420](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33973824420)
  passed all 12 ordinary jobs: `fitting_reports` 32 / 8,287 and the full
  Julia 1.10.8 suite 99 / 19,405 in 33m11s. Both manual research jobs were skipped.
  [PR #98](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/pull/98) merged as
  `4b2c5a4` on 2026-09-06 JST; this does not certify the following revision.
  Payload/source binding, labelled durable archives, crash-safe publication,
  a persistent all-attempt ledger, and all scientific freeze decisions remain open.
- The [response-byte binding check](docs/internal/mfrm-anchor-study.md#byte-bound-labelled-response-restoration)
  reuses SHA, JSON3's typed reader, the event-label check, and `FacetData`.
  It adds 95 boundary assertions plus 64 labelled-table checks on the existing
  16 smoke blocks. All 4,770 anchor and 103 scorer assertions pass on Julia
  1.10.8 and 1.12.5; SHA-bypass and decimal-rounding mutations are detected.
  [CI 33975779252](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33975779252)
  at `ac31b41` passed all 12 ordinary jobs: `fitting_reports` 33 / 8,446 and
  the full Julia 1.10.8 suite 100 / 19,564 in 31m46s. Both manual research
  jobs were skipped. Trusted reference retention, data/state/source/attempt
  binding, durable publication, the persistent ledger, and scientific review
  remain open. No fresh fit/evaluation or new dependency/export is added.
- [PR #99](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/pull/99) merged
  verified `ac31b41` into `main` as `ad57606` on 2026-09-06 JST; their complete
  Git trees match. [Main CI 33997276971](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/33997276971)
  passed all 12 ordinary jobs: `fitting_reports` 33 / 8,446 and the full
  Julia 1.10.8 suite 100 / 19,564 in 30m50s. Both manual research jobs were
  skipped. Integration does not close M0/M1 or authorize a release/evaluation.
- The runtime-review and no-fit preflight documentation at `b19eeec` passed all
  12 ordinary jobs in
  [CI 34001839651](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/runs/34001839651):
  `fitting_reports` 33 / 8,446 and the full Julia 1.10.8 suite 100 / 19,564
  in 31m16s. Both manual research jobs were skipped. This does not certify the
  subsequent cold-A report, enlarge the fixed timing window, or close M0.
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

These initial observations are compilation-heavy and demonstrate runner
heterogeneity. They do **not** isolate the CPU's causal contribution, establish
a documentation-induced speedup, or identify the CPU of any older job. Those
older logs cannot support retrospective hardware stratification. Keep M0 open;
separate subsequent ordinary observations by CPU/target, version, and threads
before forming a comparable window or choosing a measured compilation remedy.
In that initial window there is only one observation per CPU/target, not a
three-run matched median. The [16-job follow-up through `ad57606`](docs/internal/fitting-core-runtime-review.md)
now finds four source/version/CPU-matched observations (median 22m12s),
precompilation despite cache restoration, and a resolved JSON version change.
It localizes one later job-time change outside the fitting block, without
attributing the original trigger or claiming a sampler improvement.
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

Stable-public MGMFRM promotion waits for every condition below and the
target-specific M0–M3 domain decision. Core development and sampler-free
validation need not wait for completion of the entire MFRM anchor study.
A checked engineering item is not scientific validation.

Checked items below retain their dated baseline meaning, not a claim that the
2026-09-27 checkout has passed fresh full CI or minimum-version verification.
The current integration candidate must supply the checks relevant to its changes.

These conditions govern the primary Julia package deliverable, including its
continuing CmdStan verification. The [Uchihara application](#uchihara-2022-secondary-application)
is not an additional release gate, and its success does not waive any condition.
Historical M0 runtime attribution remains a release hold while further benchmarking
stays deferred under the existing decision. Actual correctness, data integrity,
load/runtime and resource-safety blockers in the core workflow take priority;
the priority correction does not automatically restart the old benchmark program.

- [x] A Git-free source candidate installs, loads, runs the stable example, and
  builds the manual without ignored artifacts, private paths, CmdStan, or R.
- [x] Stable MFRM supports declared categories and actual individual rater/item
  hard anchors through fitting, fixed-coordinate reports, and persistence;
  the finite M0 behavior review passed candidate CI.
- [x] Root exports are frozen and classified; stable exports are documented;
  experimental and research entry points remain visibly separated.
- [ ] Apply the [final API migration](#final-api-and-development-status-wording)
  to each accepted model: ordinary calls and final report/figure headings no
  longer require `Experimental`; compatibility aliases, old saved results,
  model meanings and necessary limits remain intact. This is not satisfied by
  removing a status string from the current development build.
- [ ] Each advertised model has an accepted [model-axis specification](#model-axes-and-staged-scope-decisions)
  and evidence for its declared domain. A fixed-Q or bifactor-shaped design,
  direct ability coordinates, or a correlation candidate does not imply
  support for every multidimensional MFRM/MGMFRM or factor structure.
- [ ] Complete the [content acceptance checks](#public-documentation-and-help-acceptance):
  README/manual/live-help/fresh-HTML consistency is verified on 2026-09-14;
  the independent unfamiliar-reader walkthrough remains pending.
  Ordinary user tasks do not depend on internal work orders; the four observed
  source-language findings and GMFRM explanation contradiction are resolved.
  Historical navigation/API-coverage checks do not satisfy this condition.
- [ ] The advertised MGMFRM workflow reaches standard diagnostic/result figures
  and a saved report without manual draw reshaping; scale/interval agreement,
  compatibility and the [UX walkthrough](#figure-and-report-acceptance) pass.
  Bounded saved-fit figure/report integration is verified on 2026-09-14;
  the unfamiliar-reader walkthrough remains pending.
- [ ] The advertised core MGMFRM models remain estimable through both
  Julia/AdvancedHMC and CmdStan, with the [cross-backend checks](#julia-and-cmdstan-continuity-and-comparison)
  complete for the declared scope. Record numerical target checks separately
  from diagnostic-qualified posterior comparisons and scientific validation;
  a single successful fit or one available backend does not close this item.
- [x] Release checks protect behavior, schema, performance, portability, and
  privacy rather than unrelated prose or transitive source digests.
- [ ] Runtime P0 acceptance resolves the retained >20% fitting trigger.
  Research-result isolation, whole-lane evidence, and three-run baseline
  collection are recorded above; they do not substitute for that decision.
- [x] The historical 0.1.x package/research placement and load boundary was reviewed:
  retained fixtures have a shipped purpose or an explicit archival role, and
  research records are not numerical prerequisites for ordinary tests. Retained
  ordinary numerical/behavioral references are identified separately; shared
  research definitions still have parsing/load cost and are not promoted APIs.
- [ ] Confirm current decision/document navigation on the integration candidate.
  The 2026-09-27 review separates the current work order from accumulated history;
  this correction does not itself establish unfamiliar-reader acceptance.

The compressed Git archive growth guard is 5 MiB following the explicit October 2
source-growth review above; retain the documented 250 KiB fixture-review threshold.
Ordinary tests have no custom elapsed-time cutoff under the October 2 user decision.
Earlier timing gates are historical; separately declared scientific sampling
conditions remain unchanged. Future size exceptions need a stated user benefit.
The four documented research-only missing-docstring warnings stay classified
under the existing Documenter policy; stable API completeness is checked
separately.

## Directory map and change boundaries

| Location | Role and rule |
| --- | --- |
| `Project.toml`, `src/` | Package dependencies and implementation; no source/API refactor in this organization pass |
| `examples/`, `README.md`, `docs/src/` | User workflows and manual sources; `docs/make.jl` explicitly selects published pages |
| `ROADMAP.md` | Current priorities, owners, exit decisions, and a compact evidence baseline |
| [`docs/internal/mfrm-anchor-study.md`](docs/internal/mfrm-anchor-study.md) | Supporting MFRM anchor methods draft; the only place to edit that sub-study's six freeze decisions, not the MGMFRM model contract |
| [`fixture-boundary.md`](docs/internal/fixture-boundary.md), [`code-load-boundary.md`](docs/internal/code-load-boundary.md) | Finite 0.1.x placement decisions and their verification limits; revisit only when the recorded boundary changes |
| [`fitting-core-runtime-review.md`](docs/internal/fitting-core-runtime-review.md) | Fixed-window M0 timing observations and comparison limits; acceptance and next work remain in this roadmap |
| [`docs/internal/archive/`](docs/internal/archive/) | Preserved roadmap snapshots and deferred rationale; outside the manual source tree and not an execution authority |
| `docs/src/development-*.md`, `docs/src/mgmfrm-research-roadmap.md` | Existing non-published ledgers and MGMFRM design/evidence detail to reuse in the active core review; older version schedules and execution decisions do not override this work order |
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

The [narrow fixed-Q program](docs/internal/archive/roadmap-2026-09-05.md#downstream-fixed-q-program)
is now an implementation/evidence input to the active MGMFRM core review, not
deferred wholesale until the MFRM anchor-domain decision. Its protocol, recovery,
external-review and promotion gates remain unsatisfied by this priority change.
Fixed-coefficient multidimensional MFRM now has canonical experimental fitting,
manual cache/full-artifact replay and report/figure workflows, including an explicit two-dimensional between-item correlated model. Higher-dimensional correlations, validated within-item structures, configurable
random effects, non-compensatory kernels and Q structure inference follow the
[long-term sequence](#long-term-extension-sequence). They are intended extensions
with separate identification and validation work, not indefinitely excluded
features or current support claims. Existing guards remain until the relevant
implementation and evidence are complete. Bifactor roles/score interpretation
require their own contract even when a Q pattern can be represented.

Criterion-specific raters, shared recording effects and phonetic predictors may
exercise the reusable effect design; the Uchihara-specific combination and mixed
outcomes remain a separate application scope. Full Uto reproduction, generalized
anchors, dynamic raters, broader testlet mechanisms and causal fairness claims
retain their distinct research decisions. Uchihara, ConQuest/TAM and the full
MFRM anchor panel are supporting work; none defines completion or blocks an
otherwise independent Julia foundation task.

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
