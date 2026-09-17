# Fixed-Q normalized-prior backend comparison

## Protocol fixed before sampling, 2026-09-13

Question: for one declared posterior target, do Julia NUTS and CmdStan give
compatible marginal summaries and selected contrasts at a stated Monte Carlo
resolution? Run the source and exchangeable priors separately on the same
data. This tests numerical estimation under these models; it is neither
parameter recovery, source-paper replication nor evidence about an application.

Reuse `CmdStanBackendValidation.simulated_case(:mgmfrm, :dense; seed=9173001,
truth_scale=0.15)`: 6 persons, 4 items, 3 raters, 3 categories, 72 responses,
2 dimensions, Q rows `(1,0),(1,0),(0,1),(0,1)`. This existing likelihood
generator uses raw truth `0.15sin(index)`; it is not an independent check of
the model equation. Keep `1.7` and identity latent correlation. The two
normalized priors use kernel SDs `(0.7,0.4,0.6,0.3,0.35,0.5)` in person,
severity, difficulty, log-loading, log-consistency and step order. Source
mode distinguishes observed rater ID `R2`. These are specified computational
test conditions, not a scientific default or literal unit-scale source prior.

Run exactly four fits: exchangeable Julia/CmdStan with seeds 9173101/9173102,
then source Julia/CmdStan with seeds 9173201/9173202. Each has 4 chains,
1,000 warmup and 1,500 retained draws per chain, target acceptance 0.9,
maximum depth 10, diagonal metric, initial step 0.03 and zero base initial
vector with Gaussian jitter SD 0.25. Backend fits use separate RNG streams;
do not infer coupling or cross-fit covariance from equally numbered draws.
Retain the Julia master seed and CmdStan's realized chain seeds. No retries,
outcome-driven tuning or expansion of conditions in this run.

Summarize every raw and direct parameter and six declared draw-wise contrasts:
P1 minus P2 ability separately for each dimension; R2 minus R1 severity;
log of the R2/R1 consistency ratio; I1 minus I2 difficulty; and I1 minus I2
active dimension-1 loading. Inspect means, SDs and 0.1/0.5/0.9 quantiles.
Reuse the package's chain-preserving rank-normalized diagnostics and
`MCMCDiagnosticTools` MCSE for each actual statistic. Do not substitute
rank-based bulk ESS for the mean-specific MCSE. This is 64 quantities and
320 comparisons per prior, 640 across the two priors; duplicated raw/direct
quantities stay visible and are not treated as independent evidence.

Before agreement is considered, require all raw/direct/contrast quantities
to have rank-normalized split/folded R-hat <1.01 and bulk/tail ESS >=400,
zero retained divergences and depth hits, E-BFMI >=0.3 in every chain, finite
valid transformed draws, and valid pointwise likelihoods. These diagnostic
choices follow [Stan's diagnostic guidance](https://mc-stan.org/learn-stan/diagnostics-warnings.html)
and [bulk/tail ESS guidance](https://mc-stan.org/rstan/reference/Rhat.html).
Zero depth hits is an additional conservative efficiency requirement for this
trial; a hit alone does not prove bias. Diagnostic success is not proof of
convergence.

For each statistic let `delta = estimate_cmdstan - estimate_julia`,
`s = hypot(MCSE_julia, MCSE_cmdstan)`, and let `sigma` be the root-mean-square
of the two posterior SDs for that quantity. Require positive finite MCSEs,
each MCSE <=0.05 sigma, `abs(delta)/s <=4.5`, and
`(abs(delta)+4.5s)/sigma <=0.3`. The last condition prevents imprecise matching
from being called agreement. These 0.05/0.3 tolerances and the 4.5 multiplier
are **local computational choices**, not educational decision thresholds or
Stan recommendations. The 4.5 screen is deliberately conservative over 640
comparisons (a normal-approximation union bound is below 0.01); MCSEs and that
approximation are estimated, so no exact familywise guarantee is claimed.
The resolution is relative to estimated posterior spread, not a fixed-unit
equivalence margin. Higher moments, joint distribution equality and unexamined
tail probabilities remain outside the conclusion.

Preserve every failed criterion with diagnostic/precision/difference/resolution
status. A diagnostic hold suppresses the agreement conclusion even if means
look close. The overall result is `within_resolution` only when all 640 rows
meet the criteria; otherwise it remains `unresolved`, with the failing rows
reported. Do not retry until a subsequent plan explicitly addresses the cause.

The [manual runner](../../scripts/run_normalized_prior_comparison.jl) writes
the exact protocol, canonical data/design identities and source/environment
file hashes before the first sampler call. It saves every complete sample
record and re-reads it for scoring, retains per-fit diagnostics and every
comparison row, and checks source hashes again on completion. These files
use a new output directory and are never silently reused. The
[synthetic decision check](../../test/normalized_prior_comparison.jl) runs
before sampling; this experiment is not added to the ordinary test suite or
package import path. A process failure retains the protocol and already
written results; it does not constitute a completed comparison.

## Execution receipt

Completed once on Julia 1.12.5/macOS and CmdStan 2.39.0: four fits, 16 chains,
24,000 retained draws. The 52-assertion synthetic decision check passed before
the first fit. No posterior result was inspected when the protocol and
runner constants were written. The exact pre-sampling protocol identity is
`22cd48d7c35e951acce27dc1255836d663c86bd0898db8baa65c56127a1a1c01`.

All four fits meet the declared diagnostics across all 64 quantities. There
are zero retained divergences and zero depth hits in every fit.

| Prior | Backend | Maximum R-hat | Minimum bulk ESS | Minimum tail ESS | Minimum E-BFMI |
| --- | --- | ---: | ---: | ---: | ---: |
| Exchangeable | Julia | 1.00237 | 3719.5 | 3511.5 | 0.95448 |
| Exchangeable | CmdStan | 1.00169 | 3557.3 | 3834.3 | 0.88552 |
| Source | Julia | 1.00259 | 3226.3 | 3979.8 | 0.95666 |
| Source | CmdStan | 1.00174 | 3996.9 | 3939.6 | 0.98402 |

The source target meets the stated resolution for all 320 comparisons.
The exchangeable target meets it for 319 of 320, with one resolution hold.
Thus the predeclared **overall status remains `unresolved`**. No diagnostic,
missing-MCSE, individual-MCSE precision or 4.5-MCSE discrepancy screen fails;
the outstanding criterion is the error-inclusive resolution bound.

| Prior | Within resolution | Resolution holds | Maximum absolute MCSE z | Maximum difference bound / posterior SD |
| --- | ---: | ---: | ---: | ---: |
| Exchangeable | 319 | 1 | 2.67988 | 0.30478 |
| Source | 320 | 0 | 2.85655 | 0.28441 |

The held quantity is the exchangeable model's R2 consistency 90% quantile.
Julia estimates 1.05761737 (MCSE 0.00684639), while CmdStan estimates
1.04001030 (MCSE 0.00535264). Their difference is -0.01760707, with combined
MCSE 0.00869044, or 2.02603 combined MCSEs. The RMS posterior SD is
0.18607949, giving an error-inclusive bound of 0.30478412 SD against the
fixed 0.3 criterion. The difference screen passes, but the declared bound
is not established at this draw budget. A near miss remains a hold; neither
rounding to 0.3 nor loosening the cutoff is used to declare success.

Answer to the question: the tested source-prior posterior has compatible
summaries within the specified local resolution, and the exchangeable-prior
posterior retains one unresolved quantile-precision check. The result supports
this bounded estimation path, not equality of entire joint distributions,
other Q layouts/scales/data, or a general scientific-validity claim. No
automatic repeat, seed change, threshold change, new likelihood or public
prior default was introduced. The remaining hold prevents closing the
overall sampling-comparison acceptance condition.

All sample records were saved, re-read with expected target identities, and
checked for identical retained runs before scoring. The runner verified its
source hashes at completion. An independent Python check then recomputed all
640 differences, combined MCSEs and bounds from the exported summaries and
verified sample-file and source hashes, obtaining the same 639/1 decision.
This is arithmetic/integrity verification, not an independent MCMC fit or
MCSE estimator. No full-suite, minimum-Julia, other-platform, recovery or
application study ran in this slice.

Local records are retained in the git-ignored
[`results/normalized-prior-comparison/20260913-fixed-q-01/`](../../results/normalized-prior-comparison/20260913-fixed-q-01):
[protocol](../../results/normalized-prior-comparison/20260913-fixed-q-01/protocol.json),
[full comparison](../../results/normalized-prior-comparison/20260913-fixed-q-01/comparison.json),
[execution log](../../results/normalized-prior-comparison/20260913-fixed-q-01/execution.log),
four trusted Julia sample files and per-fit summaries. This note carries the
reviewable receipt; those local artifacts are not new committed fixtures.
The task-owned writable CmdStan runtime copy is removed after verification.

## Saved-result performance receipt, 2026-09-13

Question: which part of the Julia result path explains the approximately
138 seconds between a completed fitting call and the next fit? Reuse the
exchangeable AdvancedHMC record (6,000 retained draws), measure each phase
separately, and compare results before and after a minimal change. No new
posterior-comparison sampling is needed to answer this question.

The bottleneck is SHA-256 over the canonical string's `CodeUnits`, not
diagnostic computation. A stdlib-only reproduction on Julia 1.12.5 separates
canonicalization from hashing: a 3,616,806-byte synthetic payload takes
27.59 seconds to hash as `CodeUnits`, versus 0.0084 seconds after copying
to a byte vector, with identical digests. The installed SHA implementation
copies 64-byte blocks through generic array alias checks; `CodeUnits` falls
back to an object identity calculation involving its string. The observed
cost grows approximately quadratically with input size. The stdlib IO
method reads into a byte buffer and avoids that path. No dependency change
or custom SHA implementation is required.

The shared `_cache_hash` and seven sibling fit/report hash sites now use
`sha256(IOBuffer(text))`. Canonical text, SHA-256, byte-count metadata and
all validation remain unchanged. A separate UTF-8/NUL input check of
4,200,000 bytes matches the byte-vector digest and takes a median 0.0077
seconds over five warm IO calls. These isolated checks identify this local
input-path issue; they do not establish supported-version performance.

| Phase | Before, seconds | After, seconds |
| --- | ---: | ---: |
| Deserialize | 0.233 | 0.189 |
| Reconstruct and verify target identity | 1.821 | 1.523 |
| Verify payload hash | 68.720 | 0.087 |
| Validate retained run | 0.927 | 0.785 |
| Compute diagnostic tables | 2.088 | 1.789 |
| Compute comparison summaries and MCSEs | 2.140 | 1.788 |
| Atomic serialization alone | 0.311 | 0.248 |
| Save with full validation | 70.349 | 2.002 |
| Load with full validation | 74.800 | 1.926 |

Each column is one profiled run (baseline and final code), on the same local
Julia 1.12.5/macOS environment. Package startup is outside the table; individual stages retain
their JIT state, with compilation and GC times recorded separately. Save
and load each repeat hash verification, run validation and diagnostics, so
these rows must not be summed as disjoint components. Profiling uses a
10-ms interval. The table is a local before/after observation, not a repeated
end-to-end benchmark or a claim about sampling throughput. Allocation costs
remain substantial (about 3.08 GB allocated per validated save/load); removing
checks or further refactoring was unnecessary to resolve the measured delay.

The profiled record retains exact equality of its run, diagnostic tables and
64 parameter/contrast summaries against the pre-change serialized reference.
`FacetSpec` has identity equality, so the verifier reconstructs and validates
its canonical target separately rather than comparing object addresses.
The four-fit verifier then loads every original Julia/CmdStan sample record,
checks its target/content/file hashes, and exactly reproduces exported
sampler controls, sampler rows, diagnostics, parameter summaries and all
640 comparison rows. The original protocol hash still matches. The result
remains **639 within resolution and one unresolved**, and every input JSON
and serialized record remains byte-identical. This validates compatibility
of the optimization, not additional statistical evidence for agreement.

The bounded regression passes **1,658 assertions**: 65 byte-compatibility
checks, 292 normalized-prior Julia/parser/save-load checks, 1,249 fitting
boundary checks and 52 comparison decisions. Byte tests cover Unicode/NUL,
empty inputs, substring/lazy-string inputs, SHA block and stream chunk boundaries, array shape, signed
zero, nested hash metadata and every changed fit/report hash function.
Existing tests retain corruption rejection, invalid controls, chain context,
serialization errors and concurrent-publication preservation. Existing tiny
Julia fits run for operability; no new CmdStan sampling, full suite,
minimum-Julia, other-platform or application analysis runs in this slice.

The only production source changed between profiles is `src/bayesian_fit.jl`:
`e60b256da97f46a1f345c606649c42d6b633ad8bee5433be4d79add0cb470412`
to `13047bceadb06ce376aed50da5b36f37bd06d6a4990d9a79433af427ab17a4f0`.
Local artifacts remain under git-ignored
[`results/normalized-prior-profile/`](../../results/normalized-prior-profile):
before/final-after timing JSON, flat/tree profiles, serialized references, exact
profiling-script snapshots and logs. The receipt SHA-256 values are:

| Receipt | SHA-256 |
| --- | --- |
| `20260913-before/timings.json` | `f2af6aca4a7d26beea909a660230bef960c5388b726aa21403439900638f738a` |
| `20260913-after-final/timings.json` | `f0f74e753360505bd69892a1110dd63551b6b5ddb25eabb3e5cada44f4fb067c` |
| `20260913-after-final/four-fit-verification.json` | `db5bcd174d0f7b22e27b9a89030ba86951a8f229c411abb461e7ef190ae27b3a` |

Reproduce on trusted same-environment saved records, using a new output
directory/file. The profiling slice left the comparison runner and original
protocol unchanged:

```sh
julia --startup-file=no --history-file=no --compiled-modules=existing --pkgimages=existing --project=. scripts/profile_normalized_prior_results.jl results/normalized-prior-comparison/20260913-fixed-q-01 /private/tmp/normalized-profile-new results/normalized-prior-profile/20260913-before/reference.jls
julia --startup-file=no --history-file=no --compiled-modules=existing --pkgimages=existing --project=. -e 'include("scripts/profile_normalized_prior_results.jl"); NormalizedPriorResultProfile.verify_comparison("results/normalized-prior-comparison/20260913-fixed-q-01", "/private/tmp/normalized-verification-new.json")'
julia --startup-file=no --history-file=no --compiled-modules=existing --pkgimages=existing --project=. -e 'using Test, BayesianMGMFRM; include("test/cache_hash.jl"); include("test/mgmfrm_normalized_samples.jl"); include("test/fitting_boundaries.jl"); include("test/normalized_prior_comparison.jl")'
```

## Precision follow-up protocol, 2026-09-13

The separately recorded precision follow-up uses the same dataset, two
targets, 64 quantities per target and all 640 comparisons. Retain four chains,
1,000 warmup and all other sampler controls; increase retained draws from
1,500 to **6,000 per chain** (96,000 retained draws across four fits).
The new exchangeable Julia/CmdStan seeds are **9174101/9174102** and source
seeds **9174201/9174202**. Retain every diagnostic, MCSE, discrepancy and
resolution threshold above, with at most four fits and no automatic retry.

Before the first sampler call, publish a new machine-readable protocol with
the actual source hashes and a link to the initial unresolved receipt.
Use a new output directory; never rewrite the first protocol or combine
retained draws across the trials. The larger budget seeks lower MCSE; it
does not guarantee acceptance. If any row still fails a declared gate,
retain that outcome rather than tune a cutoff or selectively rerun it.
This is a precision follow-up on the same data, not independent replication
over datasets. Public prior selection, broader model claims and the Uchihara
application remain outside this handoff.

The manual runner now accepts `--precision-followup`, selecting only this
predeclared budget and seed set. Its original invocation retains the initial
controls and seeds; both trials use the same fitting, save/reload and scoring
loop. The follow-up verifies the original protocol/receipt file hashes and
matching target identities, scales and gates before publishing a new protocol.
It records the predecessor and forbids draw pooling. After each save/load it
also checks the actual sampler controls and seed against the selected plan.
The manual decision checks pass 57 assertions before any sampler call. No
production source, public API, dependency or ordinary-test budget changes.

The protocol records creation at `2026-09-13T08:31:46.741` UTC and was
published before the first fit began at `08:31:49.862` UTC,
under [`results/normalized-prior-comparison/20260913-fixed-q-precision-01/`](../../results/normalized-prior-comparison/20260913-fixed-q-precision-01).
Its canonical hash is
`ad4a98b9f58be2cd152880b1bb5ad9f81af0d63f3431bbe66cf92c55291995de`;
the protocol JSON file SHA-256 is
`0f05b5d7b2283956c8e20b29fa0589553ea37e7e7e2ae361b02c940ed6c493a2`.
The original runner is snapshotted alongside the new runner without rewriting
the first trial's artifacts. CmdStan compilation uses a task-owned writable
copy of the installed 2.39.0 runtime.

```sh
julia --startup-file=no --history-file=no --compiled-modules=existing --pkgimages=existing --project=. scripts/run_normalized_prior_comparison.jl NEW_OUTPUT_DIRECTORY --precision-followup
```

## Precision follow-up execution receipt

The single planned execution completes all four fits and **96,000 retained
draws**, without retries or adjustments. All four fits meet the frozen
retained-draw diagnostic criteria. Both prior targets pass all 320 comparisons,
so **640/640 are within the declared resolution**. Maximum individual MCSE
is 0.01850 pooled posterior SD (limit 0.05). No MCSE is unavailable, and no
precision, discrepancy or resolution hold remains in this follow-up.

| Prior / backend | Maximum R-hat | Minimum bulk ESS | Minimum tail ESS | Minimum chain E-BFMI | Fitting-call seconds |
| --- | ---: | ---: | ---: | ---: | ---: |
| Exchangeable / Julia | 1.00055 | 14466.5 | 16795.6 | 0.94618 | 169.845 |
| Exchangeable / CmdStan | 1.00081 | 14079.4 | 16522.6 | 0.94665 | 36.960 |
| Source / Julia | 1.00065 | 15685.9 | 17016.6 | 0.95058 | 170.463 |
| Source / CmdStan | 1.00042 | 15230.8 | 16285.7 | 0.97820 | 36.611 |

All chains have zero retained divergences and maximum-depth hits. Timing
surrounds the fitting call, including its JIT/compilation and initial result
validation/diagnostics; it excludes subsequent save, reload and comparison
scoring. These single executions are not pure-sampler or repeated performance
benchmarks, and they have a different draw budget from the initial trial.
Warmup is executed but its event telemetry is not retained by either adapter.

| Prior | Comparisons within resolution | Maximum absolute difference / combined MCSE | Maximum error-inclusive difference / posterior SD |
| --- | ---: | ---: | ---: |
| Exchangeable | 320 / 320 | 3.30633 | 0.14555 |
| Source | 320 / 320 | 2.29744 | 0.15226 |
| Declared limits | All rows required | 4.5 | 0.3 |

For the originally held exchangeable direct
`rater_consistency[rater=R2]` 90% quantile, the new Julia/CmdStan estimates
are 1.0429629310 / 1.0437312267. Their MCSEs are 0.0028955810 / 0.0025924990;
the difference is +0.0007682957 and combined MCSE is 0.0038865718.
The error-inclusive difference bound is **0.0993482 posterior SD**, compared
with 0.3047841 in the original trial, against the unchanged 0.3 limit.
This selected row explains the initial hold; acceptance still uses all 640
rows. The earlier unresolved result remains a separate historical receipt.
No trial pooling or outcome-driven threshold/seed/budget change is used.

Answer to the stated question: for this fixed dataset, Q, likelihood,
normalization and scale choice, the two backends produce the selected marginal
and contrast summaries within the declared Monte Carlo resolution under each
prior. This completes that bounded numerical comparison. It does not establish
equality of entire joint distributions, parameter recovery, model adequacy,
general Q/scale/data coverage or application validity. The follow-up uses the
same dataset and is not an independent replication over datasets. The screening
limits retain their previously stated approximation and multiplicity limits.

All four runs are saved and re-read with expected target identities; retained
runs, actual controls and seeds match. CmdStan's realized chain seeds and
executable hashes remain in per-fit controls. A separate stdlib-only Python
verifier recalculates every difference, pooled SD, combined MCSE, screening
bound and decision from the exported summaries, checking all 640 rows. It also
checks per-chain retained counts, planned controls/seeds, diagnostic arithmetic,
source hashes, sample-file hashes and predecessor hashes. This is independent
arithmetic and integrity verification, not an independent MCSE estimator or
MCMC implementation. The earlier complete input inventory confirms every
original JSON/JLS file is unchanged. The task-owned CmdStan runtime copy is
removed after verification. No production source change, full-suite run,
minimum-Julia run or other-platform run is part of this slice.

The local output directory linked above contains the protocol, four sample
records and summaries, two per-prior comparisons, complete comparison,
execution log, and exact runner/verifier snapshots. The verification script
is retained as `arithmetic-verifier.py`; its receipt is
`arithmetic-verification.json`. Relevant SHA-256 values are:

| Receipt | SHA-256 |
| --- | --- |
| `protocol.jls` | `304a9df45a48b201bfc115e68b413e27bef23b5ebcfd2ac2e92653e58ef1a49a` |
| `comparison.json` | `e4ab9951916f3916fbaf494556af80bedb351d00d4eb0190a7b1fbec6b048053` |
| `execution.log` | `e4166b2a9bf21a0236250772207e3ed72d1b6679d4dda2579019421728108b3b` |
| `arithmetic-verification.json` | `bdce997b88a7f77f1dc64e1d8fddfb694765868ea4f05553b5682fcdd0a4fb2d` |
| `runner-snapshot.jl` | `e16cf5da69e459d40e26fbbe72f6bac11cbaa86dc6babfb69b2f1335d777e202` |
| `arithmetic-verifier.py` | `6ddab36340fa4405f132c0ce48250051b0e7f75b290bcbee1fd41eaf3f3f6912` |

## Warmup telemetry execution receipt, 2026-09-13

Question: can the normalized-prior Julia and CmdStan paths preserve adaptation
event information without changing the posterior draws or misreporting absent
history? This initial slice added private `record_warmup` control to the
shared generalized runners, initially disabled for their existing callers and
enabled by default in `_mgmfrm_normalized_prior_sample`. The later public-fit
integration is recorded below; no new public fitting option was needed.

Julia uses AdvancedHMC's existing output-retention option, then separates the
first `warmup` iterations from posterior output. CmdStan uses `save_warmup=1`
for this path. The existing CSV parser checks the `Adaptation terminated`
boundary at exactly the expected row and requires the expected warmup and
retained counts. Warmup parameter/log-likelihood columns never enter the
retained-draw evaluator. Malformed or missing boundaries fail rather than
silently shifting posterior rows. The existing nonfinite retained-output and
Julia/Stan likelihood/prior checks remain in force.

Persisted warmup rows contain only chain, iteration, divergence, tree depth
and a nonfinite-log-density indicator. Warmup parameter vectors are not saved;
Julia temporarily receives them from AdvancedHMC while collecting telemetry.
The result exposes separate `warmup_diagnostics` rows with these meanings:

| Coverage | Expected / observed iterations | Event counts |
| --- | --- | --- |
| `recorded` | Declared warmup count / matching observed count, per chain | Observed divergences, maximum-depth hits and nonfinite log densities |
| `not_run` | 0 / 0 | 0; no warmup was requested |
| `not_recorded` | Declared positive warmup count / `missing` | `missing`; applies to legacy or explicitly nonrecording results |

These rows have `phase=:warmup` and do not enter posterior parameter tables,
R-hat/ESS, retained sampler warning flags or backend-comparison scoring.
An adaptation divergence is reported without automatically applying the
retained-draw zero-divergence rule. Nonfinite warmup log density is observable
telemetry, while a nonfinite retained log density remains an error.

New recorded samples use `bayesianmgmfrm.normalized_fixed_q_samples.v2`.
The hash covers event rows as part of the run. The reader still accepts v1
without rewriting its content or hash, and marks its positive-warmup history
unavailable. Version/telemetry mismatch, incomplete event counts, wrong
chain/iteration order and invalid event fields fail on save/load, including
deliberately rehashed malformed records. Failed save validation preserves the
existing file. This is the private trusted-Serialization format, not a change
to public fit caches or to posterior target identity.

The final normalized-prior tests pass **731 assertions**, including seven
short Julia fits and seven actual CmdStan fits: each prior with recording
off/on, a zero-warmup case, and the existing two-prior save/load checks.
Within each prior/backend pair, retained draws, log densities, chain/iteration
labels, acceptance summaries, sampler statistics and all posterior diagnostic
tables are exactly equal with recording on/off. V1 and v2 both round-trip;
their warmup coverage remains distinct. Synthetic cases add a warmup-only
divergence/depth event and nonfinite value, malformed CSV boundaries, and
an interrupt that must propagate unchanged through the parser's chain context.
The short fits are operability checks and do not assert convergence.

The existing backend, fitting-boundary, cache-containment and producer checks
pass **6,375 further assertions**. The first regression process also ran the
earlier 292 normalized-prior assertions; the distinct final count is **7,106**,
without counting those repeated checks twice. The four saved v1 precision
fits (96,000 retained draws) also reload, reproduce their exact exported
summaries and all 640 comparison decisions, and retain byte-identical input
files. No new posterior precision or recovery experiment was run.

Local validation uses Julia 1.12.5, AdvancedHMC 0.8.5 and CmdStan 2.39.0 on
macOS. No dependency, Stan model or public export changes. The task-owned
writable CmdStan runtime copy is removed after native tests. The retained
[receipt and logs](../../results/warmup-telemetry/20260913-fixed-q-01) include
source hashes and the legacy comparison verification. Receipt SHA-256:
`81a00b93234da17698935235f7b17ce7564bead67012b3ded30e35babbf528d8`;
legacy verification SHA-256:
`9e7e77d5dbf43b2b15c7b5d7e83ab08e607a9cb896f68be3e37fd0effed9f3bb`.

```sh
julia --startup-file=no --history-file=no --compiled-modules=existing --pkgimages=existing --project=. test/mgmfrm_normalized_samples.jl
CMDSTAN=WRITABLE_RUNTIME BAYESIANMGMFRM_CMDSTAN_TESTS=true julia --startup-file=no --history-file=no --compiled-modules=existing --pkgimages=existing --project=. test/mgmfrm_normalized_samples.jl
```

The broader regression also includes `test/cmdstan_backend.jl`,
`test/fitting_boundaries.jl` and the two existing `probe_cmdstan_*` scripts.
No full-suite, minimum-Julia or other-platform validation is added. Exceptions
still abort the operation without producing a complete sample record; capturing
partial warmup telemetry during interruption and actual native cancellation
remain outside this slice.

## Public fit warmup integration, 2026-09-13

Question: can an ordinary analyst retrieve warmup event counts from the fitted
object and after cache reload, without mixing them into posterior diagnosis?
The AdvancedHMC and CmdStan entry points now enable the existing recording
option for stable MFRM and experimental scalar GMFRM/fixed-Q MGMFRM. Private
candidate runners keep their previous opt-in defaults.

`sampler_diagnostics(fit; phase = :warmup)` returns the same chain-level
coverage/event summaries used by the normalized-prior slice. Its default
`:retained` output and `diagnostics(fit)` remain posterior-only. All three
fit struct layouts are unchanged. Only compact summaries are added to the
existing `sampler_controls` NamedTuple, so the v1 Julia fit-cache schema can
continue to serialize/deserialize the actual fit types. Full warmup parameter
vectors and per-iteration events are not stored in these public fit objects.
The private normalized-prior v2 format retains its own event rows unchanged.

The public summaries are included in full artifact sampler metadata and are
validated on diagnostic access, cache save and cache load. Wrong chain counts,
identities, iteration coverage or out-of-range event counts are rejected;
failed replacement preserves an existing cache. This adds semantic validation
of the optional metadata, not a new whole-fit cryptographic integrity claim.
Existing artifact hash checks remain in force.

Turing and random-walk fits still return `:not_recorded` and missing counts
for positive warmup. All backends report `:not_run` with zero counts when no
warmup was requested. Cache request identities do not change: an old
`cached_fit` result can be reused with unavailable history, and an explicit
refresh is needed to collect that history. CmdStan continues to support
manual `save_fit_cache`/`load_fit_cache`, not automatic `cached_fit`.

Three Julia caches were created before the source edits, one per family.
The updated implementation reads them under their original request keys;
all retained draws, log densities, sampler statistics, chain/iteration labels,
acceptance rates, step sizes and posterior diagnostics exactly match fresh
seeded fits. Input file bytes remain unchanged. This check passes 33 assertions.
The broader regression passes 6,838 assertions including those 33, the
existing fitting/cache/backend boundary checks, 365 normalized-prior Julia
checks, and the synthetic CmdStan producer/cache probes.

The focused `test/warmup_diagnostics.jl` covers both backends with recording
on/off for all three families, cache round trips, deliberately malformed
metadata, zero warmup, and explicit unavailable coverage for Turing/random
walk. Short fits assess output and persistence compatibility, not convergence
or statistical validity. No normalized-prior precision study is repeated and
no public prior selector is added. Dedicated warmup report presentation and
interruption-time partial telemetry remain open.

The final focused run passes **322 assertions**: 159 per NUTS backend and
four unavailable/zero-warmup checks. It executes nine short fits per NUTS
backend plus one Turing and one random-walk fit. All three families have exact
recording-on/off equality for retained output and posterior diagnostics, and
both recorded and historical-style caches round-trip. Together with the
6,838-check regression, the distinct final count is **7,160**.

The initial focused run passed its 159 Julia assertions, then stopped at the
existing CmdStan cache-reuse guard. The test harness was corrected to allocate
a fresh empty build directory for every fit, and the entire focused run
passed. The guard and production compilation policy were not weakened. Those
159 repeated assertions are not added to the final count. The task-created
initial default build was preserved under the task's temporary directory;
the owned CmdStan runtime copy was removed after completion.

Local evidence is retained under git-ignored
[results/warmup-telemetry/20260913-public-fit-01](../../results/warmup-telemetry/20260913-public-fit-01).
It includes the pre-change cache files, their producer/verification scripts,
the initial stopped log, final logs and a source/file hash receipt. Receipt
SHA-256: `ab1da13409924ca87545427f181d3cfd924ea550208af098cf808e8c645957a0`.
Validation uses Julia 1.12.5, AdvancedHMC 0.8.5 and CmdStan 2.39.0 on macOS;
there is no full-suite, minimum-version, other-platform or new statistical
acceptance claim. README and fitting help now document the phase selection,
coverage meanings, saved-result behavior and the existing fresh-build-directory
requirement for CmdStan.

```sh
julia --startup-file=no --history-file=no --compiled-modules=existing --pkgimages=existing --project=. test/warmup_diagnostics.jl
CMDSTAN=WRITABLE_RUNTIME BAYESIANMGMFRM_CMDSTAN_TESTS=true julia --startup-file=no --history-file=no --compiled-modules=existing --pkgimages=existing --project=. test/warmup_diagnostics.jl
julia --startup-file=no --history-file=no --compiled-modules=existing --pkgimages=existing --project=. results/warmup-telemetry/20260913-public-fit-01/verify_legacy.jl
```

## Warmup report presentation, 2026-09-13

Question: can an analyst report adaptation coverage and events without copying
rows out of the fitted object manually? `fit_report` now includes a separate
`warmup` section using `sampler_diagnostics(fit; phase = :warmup)`. The existing
section registry, public projection and JSON table/bundle exporters carry it
through every output form. No fitting keyword, public export or new reporting
framework is added. Markdown includes the section's interpretation and uses
explicit warmup column order, preserving its preview after JSON reload.

The section reports expected/observed iteration counts, coverage, divergences,
maximum-depth hits and nonfinite log-density counts. A computed section means
reporting succeeded; it does not certify adaptation. Missing history remains
missing (`null` in JSON, blank Markdown cells), while zero requested warmup is
`not_run` with zero counts. Events add no warmup pass/fail rule and do not enter
retained diagnostic flags or report warning rows. Malformed fit metadata uses
the existing section-error capture, `on_section_error = :throw` and
`require_complete` policies.

The final focused checks pass **211 assertions**, using deterministic reporting
inputs for all three fitted families and the two NUTS backend labels. Nonzero
synthetic warmup events confirm phase separation; both report views round-trip
through verified bundles and JSON tables, and the warmup Markdown preview is
identical before/after loading. Missing history, zero warmup and malformed
metadata are also covered. These are reporting inputs, not estimated draws,
convergence evidence or a native CmdStan check. The existing completeness test
still executes its tiny random-walk fit; no new sampling study is added.

The broader regression passes **506 assertions**: completeness 69, hash byte
compatibility 65, generalized-prior checks 351 and manual legacy checks 21.
Two pre-change full/public bundles were written before the report edits, then
loaded with normal nested hash verification; every input file stays byte-identical
and no warmup section is fabricated. New reports from three actual historical
Julia fit caches show `not_recorded` and keep their posterior diagnostics. The
distinct final count is **717**.

The initial focused check passed 174 assertions but failed twelve overly broad
whole-Markdown equality assertions. Inspection showed generic table column
order changing with NamedTuple/Dict iteration, and a different full-report hash
label after conversion to a JSON payload. The inspected public-report hash
labels remained stable. No nested export-hash check failed. The fix in this
slice is explicit column order for the new warmup table; final tests compare
that preview plus the complete serialized rows and existing hash verification.
General table order is a separate, now concrete next task. Full-report typed
hash identity and public JSON-normalized hash identity must not be conflated.

Local logs, the original bundles, producer/verification scripts and source/file
hashes are retained under git-ignored
[results/warmup-telemetry/20260913-report-01](../../results/warmup-telemetry/20260913-report-01).
Receipt SHA-256: `d1a51c55ad102ed0fa74322faed005ab43bf398c5998d0d2c0d4b8a7bf20205f`.
The focused final run uses Julia 1.12.5/macOS with `--compile=min`; the broader
regression uses default compilation and precedes the final warmup-only column
order adjustment. The focused run covers that final rendering change. No full
suite, fresh manual HTML, minimum-version or other-platform run is claimed.
README and fitting help describe the available report section and its meaning.

```sh
julia --startup-file=no --history-file=no --compiled-modules=existing --pkgimages=existing --compile=min --project=. test/warmup_report.jl
julia --startup-file=no --history-file=no --compiled-modules=existing --pkgimages=existing --project=. -e 'using Test, BayesianMGMFRM; include("test/fit_report_completeness.jl"); include("test/cache_hash.jl"); include("test/generalized_prior.jl"); include("results/warmup-telemetry/20260913-report-01/verify_legacy.jl")'
```

## Report column order, 2026-09-13

**Question:** can readers save and reload full/public reports and dossiers
without their table columns changing order? The shared `_markdown_row_fields`
previously used encounter order, so a NamedTuple and its JSON-loaded Dict
selected different columns first. The existing table export records store
rows, not a portable display schema; generalized posterior schema metadata
alone cannot order the other report tables.

The shared resolver now gives identifiers, sampler coverage, estimates and
uncertainty a fixed readable order, then sorts other fields by name. Explicit
metadata/warning column lists remain authoritative. Warmup now uses the same
resolver, including additional fields if present. The existing projection,
row lookup and table/bundle exporters are reused. No fit structure, data field,
serialized schema, hash definition, model, sampler or dependency changes.

The focused checks cover Symbol/string-keyed dictionaries, missing/null values,
heterogeneous rows, UTF-8 labels, empty and limited previews, explicit field
overrides, full/public bundles and dossier comparison/sensitivity/evidence
tables. The existing deterministic three-family/two-backend-label report test
also checks every table header after bundle reload. Manual verification reads
the two actual pre-warmup bundles and three historical Julia fit caches,
re-renders/resaves reports, verifies all table rows, and checks that input files
stay byte-identical. This is reporting and compatibility evidence; backend
labels are not native backend executions or posterior-validation evidence.

The first focused input omitted the estimation-status field used by public
projection (15 passes, one error); the input was corrected. A subsequent
overbroad whole-Markdown assertion found JSON reload displaying integral floats
such as `1.0` as `1` (26 passes, seven failures). This slice keeps the existing
numeric formatting and full typed/public JSON-normalized hash meanings. Final
checks assert column order, unchanged serialized values and verified hashes;
they do not promise byte-identical Markdown for all representations. The
generic resolver also retains the existing no-preview behavior at `max_rows=0`,
now shared by warmup instead of its previous hard-coded header.

All final checks pass **516 assertions**: focused columns/dossiers 36,
expanded warmup reports 223, completeness 69, cache/report hash bytes 65,
historical bundles 26 and reports from historical fits 97. The completeness
check retains its existing tiny random-walk fit; no new sampling study is
introduced. All commands used Julia 1.12.5/macOS and `--compile=min`. These
runs establish the bounded reporting behavior, not full-suite, fresh-HTML,
minimum-version, other-platform or performance acceptance.

Logs (including both corrected initial checks), the manual verifier, the
source diff and source/input/evidence hashes are retained in git-ignored
[results/report-presentation/20260913-columns-01](../../results/report-presentation/20260913-columns-01).
Receipt SHA-256: `74191acab47b4b97d757c1ff23c7b876de262b58f414bb3c3e6260aff16b2aaf`.
The fitting help and report/dossier docstrings describe the common order;
internal scope and next-task language remain in the roadmap and these notes.

```sh
julia --startup-file=no --history-file=no --compiled-modules=existing --pkgimages=existing --compile=min --project=. test/report_columns.jl
julia --startup-file=no --history-file=no --compiled-modules=existing --pkgimages=existing --compile=min --project=. test/warmup_report.jl
julia --startup-file=no --history-file=no --compiled-modules=existing --pkgimages=existing --compile=min --project=. -e 'using Test, BayesianMGMFRM; include("test/fit_report_completeness.jl"); include("test/cache_hash.jl"); include("results/report-presentation/20260913-columns-01/verify_legacy.jl")'
```

## Sampling failure and cache publication, 2026-09-13

**Question:** if NUTS fails after completing one chain and part of the next,
can the ordinary Julia fit/cache path publish that partial result as successful?
The source trace places `AdvancedHMC.sample` inside `_with_sampler_context` for
stable MFRM and the shared generalized sampler. Fit construction follows the
complete chain loop; `cached_fit` invokes `save_fit_cache` only after fitting
returns. CmdStan likewise runs, parses and validates each chain before returning
its combined result. Existing tests covered early NUTS faults, initialization,
invalid returned values, parser faults and atomic cache publication, but lacked
delayed generalized NUTS faults reaching the automatic cache path.

The existing `FailingRNG` test type now forwards the uniform, Boolean and
exponential draws needed to run through actual AdvancedHMC transitions before
throwing. For each of MFRM, GMFRM and fixed-Q MGMFRM, a one-chain reference
verifies the installed sampler's momentum-draw schedule and recorded warmup.
Faults occur after one complete chain, then either one warmup transition or
one retained transition in chain 2. Ordinary exceptions must preserve their
cause/backtrace and chain/stage context; constructed interrupt, out-of-memory
and stack-overflow exceptions must escape unchanged. No third chain or retry
is allowed to hide a fault.

The cache checks use a test-owned `_fit_rng(::FailingRNG, ::Integer)` method:
the production seed helper creates the MersenneTwister and replayability
metadata, then the test wrapper supplies the delayed fault. This explicit test
seam is needed because the ordinary seed argument replaces a supplied RNG.
It does not change production RNG methods or authorize reusable custom-RNG
cache keys. The real `cached_fit`/`Experimental.cached_fit` control flow runs
with both an absent destination and `refresh=true` over a valid saved fit.
The latter's original bytes and readability are checked after both an ordinary
exception and an interrupt. These test-wrapper runs never publish a result.

The CmdStan counterpart uses the existing synthetic executable/parser boundary.
Chain 1 returns an accepted synthetic row; the actual shell command for chain 2
exits with status 7. The check records command IDs 1/2, parser entry only for
chain 1, and the unchanged `CmdStanError` stage/reason plus chain-2 context.
This is command wiring, not native Stan estimation or model-agreement evidence.

The first run with `--compile=min` stopped on the existing requirement that a
rendered backtrace name `randn`: interpreted frames were shown as `top-level
scope`. The test was preserved and subsequent runs use normal compilation.
The first normal-compilation run exposed a missing `randexp` forwarding method
in the test RNG; the package correctly reported that MethodError as a sampling
failure. The test wrapper was completed without changing sampler behavior.

The final complete boundary-file run passes **1,380 assertions**: 1,249
existing checks plus 126 delayed Julia/cache checks and five added CmdStan
command checks. The added Julia slice uses three complete tiny reference fits
and 36 deliberately failed calls, not a posterior study. The existing control
flow satisfies this bounded contract; only tests and user help were changed.
The help explains that `sampling` covers the library call and cannot identify
an exact iteration or warmup/retained phase from an arbitrary exception.

Logs, source/test diffs and source/evidence hashes are retained under git-ignored
[results/sampler-failures/20260913-chain-cache-01](../../results/sampler-failures/20260913-chain-cache-01).
Receipt SHA-256: `f5a9fa2db8b30392c3ee2d57f1947588d2c26f7828bdc37e99e85d71fe9b9ca6`.
The final run uses Julia 1.12.5/macOS, AdvancedHMC 0.8.5 and normal compilation.
No full-suite, minimum-version, other-platform or performance pass is claimed.
Constructed fatal exceptions do not test live SIGINT or actual resource
exhaustion. Delayed faults cover AdvancedHMC; the existing Turing startup-fault
checks remain in the run. No native CmdStan inference/cancellation or new
statistical validation was performed.

```sh
julia --startup-file=no --history-file=no --compiled-modules=existing --pkgimages=existing --project=. test/fitting_boundaries.jl
```

## Minimum-version verification, 2026-09-13

**Question:** do the recent failure, warmup/cache and report contracts still
work with the minimum supported Julia environment, without resolving a new
dependency set to obtain a pass? Julia 1.10.8 selected the existing
`Manifest-v1.10.toml`; the preflight found its project hash current and every
dependency source installed. This environment uses AdvancedHMC 0.8.6, Turing
0.45.0 and DynamicPPL 0.41.8. The preceding Julia 1.12.5 checks used
AdvancedHMC 0.8.5, so this verifies a supported versioned dependency combination,
not the isolated effect of changing Julia alone.

The first preflight could not write Pkg's manifest-usage log in the shared
depot under the sandbox. A task-owned writable first depot fixed that setup
problem while retaining the installed depot as a read-only fallback. No
`Pkg.resolve`, `Pkg.update` or `Pkg.instantiate` was run. Julia 1.10 accepts
`yes`/`no` for compiled modules and package images, not the `existing` setting
used in the recent 1.12 commands.

With both disabled, the boundary test stopped after 986 passes and one Turing
error: DynamicPPL's generated `_has_partial_array` method could not call a
method from a newer world age. The entire boundary file then passed **1,380
assertions**, including Turing, with normal compilation and
`--compiled-modules=yes --pkgimages=yes`. Neither dependencies nor package
sources were patched. The failure with compiled modules disabled is retained
as a configuration-specific limitation; its repeated passes are not added to
the final count.

Report checks with `--compiled-modules=no --pkgimages=no --compile=min` pass
**393 assertions**: columns/dossiers 36, warmup reports 223, completeness 69
and hash bytes 65. Deterministic backend labels in these reports are not
native backend executions. A separate **26-assertion** check reads both actual
historical full/public JSON report bundles, preserves their input bytes and
tables, verifies hashes and does not fabricate warmup history. This portable
JSON check does not establish cross-version Julia `Serialization` support;
historical Julia 1.12 binary fit caches were not loaded into Julia 1.10.

The normal-compilation warmup/private-sample run was manually stopped after
about 25 minutes, after 159 AdvancedHMC assertions passed in 11m41.4s. SIGINT
did not promptly stop the owned process; SIGTERM ended it with exit code 1.
The termination stack points into LLVM while the CmdStan test dispatch was
active; this does not establish the compiler's root cause. Remaining tests
from that run have no result. The unchanged test files then pass with compiled
modules/package images enabled and `--compile=min`: public warmup/cache
`test/warmup_diagnostics.jl` **322**, and private normalized-prior sampling,
parsing and persistence `test/mgmfrm_normalized_samples.jl` **731**. These
include nine public and seven private native CmdStan 2.39.0 fits, each with a
fresh model build directory. Recording enabled/disabled preserves retained
draws and diagnostics; new records retain their warmup information after
save/load. The deliberately short fits are not convergence or recovery evidence.

The final total is **2,852 assertions**, excluding repeated passes from the
failed/interrupted attempts. All 52 recorded package-source, Stan, test and
Project/manifest files remain byte-identical. The full preflight, logs,
interruption note, portable-JSON verifier and source/input/evidence hashes are
retained under git-ignored
[results/compatibility/20260913-julia110-01](../../results/compatibility/20260913-julia110-01).
Receipt SHA-256: `755515b88672b41f5381447e64b12df344ea2b00504cce9dc6422a74fc7e32e0`.
The task-owned CmdStan copy was removed after verification; the installed
runtime's recorded key files remain unchanged. No dependencies, public names,
fit layouts or test inclusions were changed. No full-suite, other-platform,
runtime-budget, fresh-HTML, statistical or release acceptance follows.

## Cache-record compilation, 2026-09-14

**Question:** does the earlier long Julia 1.10.8 warmup/cache run reflect slow
ordinary estimation, cache work, or only its test helper? Small fresh processes
use the existing fixture, normal compilation, the unchanged versioned manifest
and the existing POSIX deadline helper. Public MFRM and experimental GMFRM
CmdStan fits take 12.57 and 12.67 seconds, including their fresh native model
builds. GMFRM cache saving and loading take 92.36 and 81.75 seconds. The test's
unchanged `replace_controls` helper takes 0.01 seconds; the delay also occurs
outside that helper. A traced CmdStan-only test reaches the GMFRM recorded-cache
load before its 240-second deadline and exits 124 without completing the testset.

Separating the saved GMFRM record's operations shows that structural validation
and the shared atomic serialization wrapper dominate. Hash stripping,
canonicalization and digest calculation alone take about 2.40 seconds combined.
The source change adds `Base.@nospecializeinfer` and `@nospecialize(record)` to
`_check_fit_cache_record` and `_save_serialized_record`; Julia 1.10 supports these
annotations. Their bodies are unchanged. Nested metadata types no longer cause
each wrapper to infer and compile separately for that record layout. No custom
serialization or new cache representation was introduced.

The matched component probe reads the same pre-change GMFRM record in separate
fresh Julia 1.10.8 processes and executes the same phases in the same order:

| Operation | Before, seconds | After, seconds |
| --- | ---: | ---: |
| Record structure validation | 75.73 | 0.04 |
| Existing payload/hash verification | 3.10 | 3.41 |
| Atomic serialization wrapper | 83.63 | 0.64 |
| Record reconstruction with the existing artifact | 2.24 | 2.22 |

Each value is one local first call including JIT, excluding initial package
load. These measurements locate the compilation cost; they are not a repeated
performance benchmark or a sampler speed claim. The before/after outputs are
byte-identical: 127,258 bytes, SHA-256
`751c7ffdb721a1257f3d6c3a86bc84431e41de1b4589d2059777ee59fe5a82fb`.
The original artifact hash also matches after record reconstruction. Priors,
sampler behavior, public names, fit layouts, validation rules, hash scope,
canonicalization, dependencies and test files remain unchanged.

Julia 1.10.8 passes the same **2,852 assertions with normal compilation**:
boundaries 1,380, public warmup/cache 322, private normalized-prior records 731,
reports/hash 393 and portable historical JSON 26. The combined run takes
627.13 seconds within a predeclared 900-second deadline and includes 16 native
CmdStan fits. Its preceding boundary checks warm some methods, so its timing
is not a controlled comparison with the earlier standalone sampler run. A
separate fresh-process run of the unchanged public warmup file also passes all
322 assertions, including nine native fits, in 147.70 seconds within its
600-second deadline. These repeated assertions are not added to the total.

Julia 1.12.5 passes **1,944 assertions in four complete files** with normal
compilation: boundaries 1,380, public warmup/cache 163, private records 365 and
columns 36. Native CmdStan sampling is disabled in this version's run. The
same process reaches its predeclared 900-second deadline during the subsequent
warmup report file, after printing all six family/backend labels; that file
has no completion result, and completeness/hash files have not started. This
remaining report execution observation is open. It does not invalidate the
completed checks, establish a compiler cause or accept normal-compilation
report runtime.

The remaining three report files pass **357 assertions** with `--compile=min`
and compiled modules/package images enabled: warmup reports 223, completeness
69 and hash compatibility 65. The complete run takes 340.67 seconds within a
600-second deadline. An initial 180-second report-only attempt was too short
relative to the preceding receipt's roughly 340-second execution; its timeout
is retained, and no assertions from that incomplete file are counted. Test
criteria and contents were preserved when correcting the deadline. The final
Julia 1.12 total is **2,301**, with the two compilation settings kept explicit.

The first public probe failed only in its timing printer because Julia 1.10's
`@timed` result lacks `compile_time`; the printer now records that field as
missing. A separate initial Julia 1.12 run with compiled modules and package
images set to `existing` encountered DynamicPPL's generated-function
`convert_model_argument` error during a tiny Turing fit. With both flags set
to `yes`, the unchanged boundary file, including Turing, passes. Neither
initial attempt contributes to the reported assertion counts; the source and
dependencies were not patched to bypass these errors.

The unchanged Project and both manifests, before/after source and exact patch,
input records, phase probes, complete and interrupted logs, commands and hashes
are retained under git-ignored
[results/compatibility/20260914-cache-compilation-01](../../results/compatibility/20260914-cache-compilation-01).
Receipt SHA-256: `d776978670976d091a2ccb5e94b5673dd0b14cd73b84ff5fc5524eb3222844c6`.
The task-owned CmdStan copy was removed after native tests completed; the
installed runtime's recorded key files are unchanged. The existing deadline
helper's 21-case self-test passed before use; it supervises an owned POSIX
process group, not independently detached descendants. Julia depots used an
installed fallback, so these were not clean-depot CI trials. No full-suite,
other-platform, runtime-budget, statistical or release acceptance follows.

## First posterior interval figures, 2026-09-14

The first fit-taking posterior interval figure is implemented as qualified
`BayesianMGMFRM.plot_posterior`, using one optional CairoMakie extension and the
existing numerical summaries and constraint transforms. The default model view
and explicit raw view retain their distinct meanings. Fixed anchors/constants
have diamond markers without sampled intervals; dimensions have separate axes.
The native Figure supports editing and PDF/SVG saving without a refit or manual
draw reshaping. Existing experimental model status and the root export set are
unchanged; no version bump or release was made.

Normal-compilation runs on Julia 1.10.8 and 1.12.5 each pass 266 numerical/selection
and 41 optional rendering/cache checks. All three families export PDF/SVG/PNG and
reload matching plot rows from saved fits. The final PDFs were rendered and
visually inspected, together with long dimension labels and fixed-anchor views.
Fixtures contain four deterministic synthetic draws and one chain; they verify
presentation and persistence, not posterior quality or either native backend.
No sampler was executed. The shared report fixture was extracted without changing
its default inputs; the full warmup report file was not rerun in this slice.

The existing public manual build succeeds; source and fresh HTML language checks
pass for 19 files and 14 pages. Four pre-existing research/release-helper
missing-docstring warnings remain. Root inference graphs are unchanged apart
from project hashes; CairoMakie 0.15.13 lives in the optional test environments.
The Julia 1.10 environment required compatible optional dependencies downloaded
to a task-owned depot after the installed-only resolution failed. Logs, commands,
manifests, source hashes and final figures are preserved in the local ignored
[receipt](../../results/posterior-plots/20260914-01/receipt.json). Initial layout
iterations are retained separately and not added to the 614 final assertions.
This closes only the first interval-figure slice, not M0 runtime, M1 scientific,
full-suite, release or unfamiliar-reader acceptance.

## Retained-chain trace/rank figures, 2026-09-14

Qualified `BayesianMGMFRM.plot_diagnostics` now returns an editable Figure with
retained-chain traces and pooled-rank histograms through the existing optional
CairoMakie extension. Shared coordinate selection/reconstruction serves both
figure operations. Trace/rank defaults to computational coordinates, preserves
chain/iteration identity and permits explicit model coordinates. Deterministic
average ranks preserve ties; normalized chain histograms share a pooled reference.
No fit, warmup reconstruction, thinning or random draw selection occurs.

Existing parameter diagnostics and whole-fit extrema/warnings are retained,
including when a named subset is displayed. Generalized fits use their stored
diagnostic thresholds and the public diagnostic-contract checks. Single chains,
fixed values, constant sampled values, missing/partial sampler statistics and
derived coordinates without stored diagnostics are labelled explicitly. Fixed
traces now use the actual retained iteration range; single-bin histograms and
figures containing only fixed values also render.

The final normal-compilation runs each pass **480 assertions** on Julia 1.10.8
and 1.12.5: 266 interval regressions, 128 trace/rank checks and 86 optional
render/cache checks. Both versions save all three families to PDF/SVG/PNG and
recover identical plotting inputs from cached fits. Final Julia 1.10 PDFs were
rasterized and visually inspected, with additional fixed/derived and single-chain
views. Synthetic fixtures include two chains of 20 deterministic draws; neither
native Julia nor CmdStan sampling was run. These are presentation and persistence
checks, not statistical or backend-equivalence evidence.

The first numerical run had one incorrect exception type for `bins = true`;
explicit positive-integer validation now returns the intended ArgumentError.
Its incomplete testset and repeated initial rendering passes are excluded from
the final total of 960. Final whole-command times are 67.37 and 221.53 seconds
within 600-second deadlines. They include local compilation and overlapping
processes, so do not constitute comparative performance benchmarks. The existing
21-case deadline self-test passed before use.

The existing manual builds in 28.14 seconds; live plotting help and the language
gate pass for 19 public files and 14 fresh HTML pages. Four existing missing
research/release-helper docstrings remain. All Projects/manifests, inference
implementation, root export contract and include lists are byte-identical to
the start of this slice. The optional environments/depot fallbacks are reused
from the interval-figure check; no dependency download or new dependency occurred.
The shared reporting fixture now optionally creates multiple chains while
preserving its prior default inputs; the full warmup-report file was not rerun.
Commands, before/after files, evidence hashes and final figures are retained in
the local ignored
[receipt](../../results/posterior-plots/20260914-trace-rank-01/receipt.json).
This does not close full-suite, CI/runtime-budget, scientific, release or
unfamiliar-reader acceptance.

## Conditional category predictive figures, 2026-09-14

Qualified `BayesianMGMFRM.plot_predictive` now uses the same optional CairoMakie
extension for stable MFRM and existing experimental GMFRM/fixed-Q MGMFRM fits.
It consumes the existing predictive check, summary and plotting rows. Observed
category proportions, replicated means and pointwise central predictive intervals
retain all declared categories, including zero-count categories. Replication
uses the original rating rows and fitted facet levels, with no new-level or
heldout-performance claim. The whole-fit MCMC diagnostic note remains visible.

Default selection visits all retained draws once. Optional `ndraws` samples
indices with replacement; explicit `draw_indices` retains order and repeats.
Replicated datasets and distinct posterior draws are counted separately. A local
MersenneTwister seeded at 1 by default leaves the global RNG untouched and replays
after fit-cache reload in the same software environment. Interval width affects
only summarization. The existing numerical API can reproduce the plotted rows
with the same selection and RNG.

A pre-edit probe confirmed that the shared categorical sampler silently mapped
NaN and all-zero probability vectors to the last category. Its common boundary
now rejects empty, nonfinite, negative or non-normalized probabilities before
drawing randomness. All four callers (stable and generalized prediction plus
local dependence replication) use this guard. The valid inverse-CDF loop is
unchanged and agrees with an independent fixed-seed sequence check. No target,
prior, Jacobian, native sampler or fit-cache type changes accompany the fix.

Final normal-compilation runs each pass **808 assertions** on Julia 1.10.8 and
1.12.5: 266 interval, 128 trace/rank, 294 predictive and 120 render/cache checks.
Figures are editable native objects and export as PDF/SVG/PNG; plotting
inputs match exactly after cache reload. Final PDFs for all three families were
rasterized and visually inspected, plus unused-category and Julia 1.12 PNGs.
Whole-command times are 60.79 and 204.63 seconds within 600-second deadlines;
these local compilation/cache-dependent times are not benchmarks. Initial core
checks are preserved separately and excluded from the final 1,616 assertions.

The final manual builds in 12.21 seconds. Live help and language checks pass
19 public source files and 14 fresh HTML pages; the four existing omitted
research/release docstrings remain. All Projects/manifests, root exports, include
lists and the shared fixture are byte-identical to the start of this slice.
The optional environments and installed depots were reused; no new dependency
or download was needed. Commands, before/after files, hashes and figures are in
the local ignored
[receipt](../../results/posterior-plots/20260914-predictive-01/receipt.json).
Synthetic parameter fixtures and simulated responses, including matching
backend-label fixtures, do not establish native-backend equivalence or statistical
validity. No native MCMC, full-suite, CI/runtime, release or unfamiliar-reader
acceptance is claimed. The ordinary inference foundation retains its priority.

## Stable MFRM Wright map, 2026-09-14

Qualified `BayesianMGMFRM.plot_wright` now returns an editable native Figure from
`wright_map_data` through the existing CairoMakie extension. Facet panels use
linked vertical logit axes, with original signs and identified origins. The
boundary panel uses item difficulty plus category step at zero rater severity,
retaining their joint posterior uncertainty. It is an adjacent-category
equal-probability boundary, not an expected-score half-point. All retained draws
are used deterministically. Facet order, category labels and optional boundaries
are preserved; the adjustable 60-position limit never silently removes rows.
Generalized fits are explicitly rejected. Fixed references/anchors and whole-fit
diagnostic warnings remain visible.

A pre-edit executable probe exposed two shared numerical-consumer defects.
`is_fixed` treated derived steps and binary steps on estimated items as fixed;
it now describes the complete position. A fixed binary boundary on a nonzero
anchored item carries that item's fixed value. Threshold `status` retains its
step-constraint meaning. The shared item-step helper also rejects nonfinite
derived values before `_finite_draw_summary` can silently discard a draw. This
serves both Wright-map and diagnostic-map consumers. Existing saved tables are
not rewritten; regenerating rows from a cached fit applies the corrections.
The likelihood, priors, Jacobians, native samplers and fit serialization remain
unchanged.

Verification covers PCM, RSM, binary responses, nonzero item/rater anchors,
binary anchors, and long labels with unused interior/extreme categories.
Independent checks compare quantiles of joint sums, adjacent-category probability
equality and facet signs. Synthetic backend-label fixtures do not supply native
backend-equivalence evidence. The first diagonal-label render clipped a long
speaker label; final vertical labels and range-relative padding address the
observed defect. Final PDFs for all six cases were rasterized and inspected.
Commands, source snapshots and figures are retained in the local ignored
[receipt](../../results/posterior-plots/20260914-wright-01/receipt.json).

Final normal-compilation runs pass **1,351 assertions per Julia 1.10.8 and
1.12.5**: 266 interval, 128 trace/rank, 294 predictive, 380 Wright-map and 283
render/cache checks. Whole-command times are 65.24 and 263.95 seconds within
600-second deadlines; these include local compilation/cache state and overlapping
processes and are not benchmarks. Initial core/rendering checks are excluded
from the final 2,702 assertions. Both versions regenerate identical plotting
inputs after fit-cache reload and export PDF/SVG/PNG. The deadline helper's
existing 21-case self-test passed before use.

The existing manual builds in 21.27 seconds; live `plot_wright`/`wright_map_data`
help and language checks pass for 19 public files and 14 fresh HTML pages. Four
existing omitted research/release docstrings remain. Projects/manifests, root
exports, include lists and the shared reporting fixture are byte-identical to
the start of this slice. Optional environments/depot fallbacks were reused,
with no new dependency or download. There was no native MCMC, full-suite,
isolated-install, CI/runtime-budget, statistical, release or unfamiliar-reader
acceptance. Julia foundation work remains primary, with CmdStan maintained.

## Short stable MFRM workflow, 2026-09-14

The existing `examples/minimal.jl` is reduced from 181 to 56 lines, reusing
`fit(spec)`, public diagnostics/summaries and fit-cache persistence. It defaults
to Julia AdvancedHMC/NUTS, retains a unique output directory, and checks exact
posterior-summary recovery after reload. `--plots` uses the existing optional
CairoMakie extension to export four PDFs and a Wright-map SVG from that reloaded
fit. `--cmdstan` selects the same stable model with a fresh build directory.
The README and fitting/examples guides document the commands and editable
figures in a later session; advanced tables/reports stay in the existing guide.
The examples page's false exclusion of GMFRM item discrimination is corrected.

Final actual-example checks pass 11 assertions without plotting on Julia
1.10.8, 13 with plotting on each of Julia 1.10.8 and 1.12.5, and 15 with CmdStan
2.39.0 and plotting on Julia 1.12.5: **52 workflow assertions**, plus one inline
summary-equality assertion per run. Each fit has two chains, 50 warmup and 50
retained draws per chain. All retain `mcmc_warning`; no statistical agreement,
convergence or recovery acceptance is inferred. Whole-command times are 22.21,
33.84, 76.63 and 75.32 seconds respectively, including compilation and overlapping
processes, so these are not benchmarks. An earlier direct Julia 1.10 run adds
one exploratory execution: five native fits occurred in this slice, four on
the final example. The initial CmdStan readiness probe found a missing old
scratch runtime; the actual fit used an APFS copy of the installed 2.39.0 tree
in a writable temporary directory, with no runtime download or installation edit.

Unknown flags and a requested but unavailable CairoMakie fail before MCMC or
output-directory creation. A separate Julia 1.12.5 process passes four checks
for loading the saved fit, editing a native axis label, exporting SVG/PDF and
preserving the cache bytes, without another fit (29.89 seconds). All twelve
final workflow PDFs and the edited replay PDF were rasterized and visually
inspected for labels, fixed references, intervals and warning captions.
The final manual build passes in 11.84 seconds. Live fit/cache help and the
existing language gates pass for 19 public sources and 14 fresh HTML pages;
four existing omitted research/release docstrings remain. The measurement
helper's 21-case self-test passed before execution.
The local ignored [receipt](../../results/workflows/20260914-minimal-01/receipt.json)
retains command logs, verification scripts, fit caches, figures and source hashes.
The package source, extension, test and script trees and Projects/manifests are
byte-identical to the start of this slice. No dependency, root export, serialized
type, fixture, CI runner or full-suite change is made. Native example operability
does not close the existing CI/runtime, release or unfamiliar-reader gates.

## Guarded GMFRM/MGMFRM workflows, 2026-09-14

The existing guarded examples now follow the stable example's data-validation,
fit, diagnostics, save/reload and optional-figure route in 60 and 67 lines
(previously 103 each). Explicit `Experimental.fit` retains generalized opt-in.
Qualified `BayesianMGMFRM.direct_posterior_summary` supplies model-scale summaries;
`posterior_summary` remains raw. GMFRM plots positive rater consistency and raw
log-consistency diagnostics. MGMFRM keeps reasoning/communication ability panels
separate and selects reasoning traces by dimension label. Both replicate category
proportions for the fitted rows. No generalized Wright map is implied.

Each run retains its own directory and `fit.jls`. Optional `--plots` writes
three PDFs and one posterior SVG from the reloaded fit; `--cmdstan` uses a fresh
build directory. Backend-specific options are passed only to CmdStan. README and
the fitting/examples guides describe these commands, model restrictions, the
raw-coordinate prior and a later-session dimension-selection/editing snippet.
The same tiny example data and existing kernels are retained; an unused task
label is removed from the scalar example. These datasets and 50-warmup,
50-retained-draw, two-chain controls are demonstrations, not scientific evidence.

Final native runs pass 35 workflow assertions without plotting on Julia 1.10.8,
46 with plotting on each of Julia 1.10.8 and 1.12.5, and 48 with CmdStan 2.39.0
and plotting on Julia 1.12.5: **175 assertions**, plus the inline model-summary
assertion in each of eight fits. All retain `mcmc_warning`. Whole-command times
are 32.89, 42.84, 172.97 and 183.49 seconds, respectively, within 600-second
deadlines. These include compilation and overlapping processes, not benchmarks.
The CmdStan run reuses the previous stable-example slice's writable APFS runtime
copy, with fresh model builds and no installation edit or download.
Two initial scalar fits stopped after sampling because the example
used an unqualified non-exported summary function; the example now uses its
existing qualified name, with no export-policy change. Those initial executions
remain separate from final checks: ten native fits occurred, retaining 1,000
draws in total. The existing measurement helper's 21-case self-test passed.

A fresh Julia 1.12.5 session passes eight checks for saved-fit recovery, named
dimension selection, native-axis editing, PDF/SVG export and unchanged cache
bytes, without another fit (75.76 seconds). All 18 workflow PDFs and both replay
PDFs were rasterized and visually inspected. Four invalid-flag/missing-renderer
invocations fail before output creation or MCMC. Live-help inspection exposed
the absent `direct_posterior_summary` docstring; a shared function docstring now
explains the model/raw distinction, returned rows and omitted derived step rows,
and the existing API reference includes it. The only package-source change is
that docstring. All executable source, extensions, tests, scripts, root exports,
Projects/manifests and serialized types retain their prior behavior/bytes.
The final manual build passes in 20.31 seconds, including package precompilation.
Live fit/summary/plot help and language checks pass for 19 public sources and
14 fresh HTML pages; the four existing omitted research/release docstrings remain.
Commands, output and source snapshots are in the local ignored
[receipt](../../results/workflows/20260914-guarded-01/receipt.json).
No statistical agreement, convergence, recovery, full-suite, isolated-install,
CI/runtime-budget, release or unfamiliar-reader acceptance follows.

## Public documentation cleanup, 2026-09-14

README (700 to 265 lines) and the public manual now lead to specification,
fitting, diagnostics, figures and saved results without research execution
instructions. Ordinary `fit(spec)` does not require separate `getdesign`.
Scalar GMFRM item discrimination and fixed-Q MGMFRM active loadings remain
explicit; the removed blanket multidimensional-fit prohibition was inaccurate.
The source/math/prior boundaries and optional CmdStan build restrictions remain.
`FacetData`, `getdesign`, `MFRMFit` and `model_family_contract` help now describe
the actual data/results rather than scaffold or milestone labels.

Existing development README/fitting notes retain maintenance commands and paired
research runners. The existing research roadmap retains the missing ConQuest
fixture detail and deferred anchor/interchange requirements. Historical fixed-Q
resource work orders already reside in the archived roadmap; current M1/M2
protocol decisions remain in ROADMAP. Retained advanced research help can name
its schema/status fields without becoming ordinary fitting instructions.

Julia 1.10.8 passes 35 assertions in 17.63 seconds: executable AST equality for
all three changed source files (excluding docs/source locations), 22 live-help
checks and ten checks executing the ordinary validation-guide snippets and
experimental Q preview without MCMC. Other source/extension/test/script/example
bytes, all Projects/manifests, exports and serialized types are unchanged.
The final Julia 1.12.5 manual build and language checks pass in 15.12 seconds,
covering 19 public sources and 14 fresh HTML pages. Ten broken fragment links
found in generated HTML were corrected to the actual Documenter heading IDs;
all 455 local fragment links resolve, with no missing local files. Removed work
orders and internal-owner navigation/search entries are absent. Four existing
omitted research/release docstrings remain; no new API omission was introduced.
Earlier passing builds (19.73 and 22.09 seconds) preceded the final content/link
review and are retained separately. The initial narrower 31-check pass is also
retained; no Julia assertion failure or native fit occurred. The timing helper's 21-case
self-test passed. Times include preparation and are not benchmarks.

The local ignored [receipt](../../results/workflows/20260914-public-docs-01/receipt.json)
retains commands, logs, source snapshots and the runnable help/link checks.
These checks do not establish independent reader acceptance, full-suite/CI,
isolated-install, release, convergence, backend equivalence or scientific validity.

## Report-bundle figures, 2026-09-14

**Question:** can an analyst export matching figures, tables and explanations
from the saved fit without reshaping draws or repeating estimation?
`save_fit_report_bundle(...; figures = (...), seed = 42)` now reuses the existing
plot data and optional CairoMakie renderer. Posterior, trace/rank and conditional
category-predictive figures support all three fitted families; Wright maps remain
stable MFRM only. Shared posterior bounds, predictive intervals, selected draw
indices and diagnostics remain explicit. Predictive figures use the report's
exact computed rows. PDF/SVG and numerical JSON files have hashes in manifest
v2; v1 figure-free bundles and report/table schemas are unchanged. Rendering
finishes before destination exports, preserving an existing bundle if a figure
selection/render fails. This is not a transaction guarantee for later I/O errors.

Synthetic saved-fit checks pass 278 assertions on each of Julia 1.10.8 and
1.12.5 (408.00 and 520.35 seconds). They cover public/full reports, scale/interval
agreement, named dimensions, chain/iteration identity, seed replay, unchanged
fit caches/global RNG, unsupported requests, and PDF/SVG/JSON tampering.
A final fresh Julia 1.10 session passes 46 checks without CairoMakie, including
all eight bundles, missing files, symlinks, downgraded manifests and live help
(22.90 seconds). The existing columns/completeness regression passes 128 checks
(93.90 seconds), including one native Julia fit with two retained draws, zero
warmup and one chain. Figure tests themselves run no MCMC. The initial Julia
1.12 attempt failed before tests because its plotting environment did not expose
JSON3 directly; using the package's existing binding fixed the test without a
package/environment change. Julia 1.10 emitted Fontconfig cache warnings but
completed all exports. Times include compilation and are not benchmarks.
The unchanged standalone plot/cache regression passes 1,351 assertions on
Julia 1.12.5 in 262.22 seconds, including native Figure edits and PDF/SVG/PNG
exports. It uses a writable temporary font cache and emits no Fontconfig errors.

All ten primary Julia 1.12 bundle PDFs were rasterized and visually inspected:
fixed values, named dimensions, distinct interval levels and unavailable
diagnostics remain legible without clipping. The manual and language checks
pass in 23.52 seconds for 19 sources and 14 fresh HTML pages; all 458 local
fragment links resolve. Four existing omitted research/release docstrings remain.
README, fitting guide, example navigation and live save/load help document the
saved-fit route and the inability of summary-only reports to recreate traces.
The local ignored [receipt](../../results/workflows/20260914-report-figures-01/receipt.json)
retains logs, source snapshots, runnable checks and output bundles.

This answers the bounded export-integration question, not reader usability,
convergence, model validity or backend equivalence. No inference kernel, prior,
serialized fit type, export list or dependency changed; no CmdStan fit, full
suite, CI, isolated install, release or statistical evaluation was run.

## Turing adaptation boundary, 2026-09-14

**Question:** does the requested `warmup` control actual Turing adaptation, and
are all returned draws after adaptation? The telemetry audit found that it did
not. The adapter used `NUTS(-1, ...)`, allowing Turing's default
`min(1000, ndraws ÷ 2)` adaptation length. `num_warmup` did not set `nadapts`.
Turing also returns an initial state before transition 1, so discarding only
`warmup` rows could retain an adapting transition.

Pre-change Julia 1.10.8 runs with six retained draws and requested warmup 0, 1
and 8 all configured three adapting transitions. A direct Turing callback
recorded actual transition indices and adaptation settings; its retained draws
exactly matched the public fit. Zero/one warmup retained three adapting rows,
all reported as `is_adapt = false`. Those original caches are preserved.

The shared Turing adapter now uses `NUTS(warmup, ...)` and discards the initial
state plus every adapting transition. `nadapts` is recorded in fit controls and
cache identity, preventing automatic reuse of old Turing results even at zero
warmup. Manual loading preserves historical draws and metadata; warmup coverage
for legacy Turing fits is unavailable rather than falsely zero. New reports
carry that distinction through JSON, tables and Markdown. The fitting guide
and live help explain re-estimation under the corrected schedule.

The final Julia 1.10.8 warmup check passes 224 assertions, including 61 Turing
checks. Julia 1.12.5 passes the same 61 Turing checks plus four unavailable/
zero-history checks; its earlier unchanged AdvancedHMC warmup checks passed 159.
Direct Turing references include the initial state and every transition, so
the tests identify the actual retained boundary independently of row labels.
They also verify identical prefixes when `ndraws` increases, fixed step size
with zero warmup, unchanged target log densities, cache keys and reload.
The existing boundary/CmdStan-contract regression passes 1,458 assertions.
These are bounded software checks using tiny native fits and injected failures;
no CmdStan model was compiled or sampled and no statistical study was launched.
The existing report checks pass 223 assertions. A separate final check passes
35 assertions on the three actual pre-change caches: manual read, corrected
key mismatch without overwrite, unavailable history in a saved public report,
and explicit refresh under the new schedule. The first cache-check attempt had
three harness errors from comparing `missing` with `==`; `isequal` fixes that
check. An earlier focused Julia 1.12 harness failed at a relative include before
sampling; its corrected run uses the same repository tests. Both failed logs
are retained separately. The manual/language build passes for 19 sources and
14 fresh HTML pages, with the same four omitted research/release docstrings.

The local ignored [receipt](../../results/workflows/20260914-turing-warmup-01/receipt.json)
retains original caches, dependency-source versions, command logs, before/after
source hashes and the cache/report checks. No likelihood, prior, model identity,
fit struct, public export or dependency changed. Turing's corrected draws may
differ at the same seed; matching the defective schedule is not required.
Positive-warmup event recording and interrupted-chain telemetry remain open.

## Turing warmup event recording, 2026-09-14

The corrected Turing path now supplies the existing compact warmup summaries
to `sampler_diagnostics`, fit caches and full/public reports. It collects the
first `warmup` transitions after discarding the initial state, validates their
event statistics and retains only the subsequent posterior draws. Turing's
statistics omit `is_adapt`; the explicit `NUTS(warmup, ...)` transition boundary
supplies that phase context. No fabricated initial-state event is counted.
Temporary transition buffering costs memory per chain; streaming is deferred
until this is a measured limit. Warmup parameter values are not stored in fits.

The private recording switch defaults off for comparison, while ordinary
`fit(...; backend = :turing)` enables it. Fit structs, v1 cache schema and the
corrected cache request identity remain unchanged. Corrected pre-recording
caches can still be reused with unavailable history; previously defective
Turing caches remain excluded by the preceding adaptation-key correction.

Julia 1.10.8 passes 305 assertions (89.58 seconds), including 159 existing
AdvancedHMC assertions. Julia 1.12.5 passes the 146 Turing/unavailable-history
checks (110.89 seconds). They compare recording on/off across two chains,
retained arrays, diagnostics and 16 subsequent RNG values; direct Turing
references check exact event counts at warmup 0, 1 and 8. Recorded counts also
survive full-cache and public-report JSON/Markdown bundle round trips, and
malformed metadata is rejected without replacing an existing cache.

Two corrected-schedule caches were created before this edit. Forty checks
(20.62 seconds) confirm unchanged input bytes and keys, automatic reuse with
honest unavailable coverage, exact new retained results and recorded-summary
reload. The existing boundary/CmdStan-contract regression passes 1,458 checks
(94.86 seconds). These use small native Julia fits and injected failures;
no native CmdStan sampling or statistical evaluation was performed. No
likelihood, prior, export, dependency or other sampler implementation changed.

The manual/language build passes in 22.72 seconds for 19 sources and 14 HTML
pages, retaining four existing omitted research/release docstrings. The first
focused Julia 1.12 driver stopped before loading tests because of a Julia
soft-scope assignment; the corrected driver executes the repository's existing
checks. The local ignored [receipt](../../results/workflows/20260914-turing-telemetry-01/receipt.json)
retains both attempts, source hashes, original/new caches and runnable checks.
Times include compilation and are not benchmarks. No full-suite, CI, independent
reader, convergence, scientific or release acceptance is claimed.

## Random-walk warmup event recording, 2026-09-14

Ordinary `backend = :julia` fits now count rejected nonfinite proposals during
burn-in with one counter per chain, using the existing warmup/cache/report
route. No warmup parameter values are buffered or saved. NUTS event fields
remain missing, including at zero warmup; the proposal count is zero for known
zero warmup and missing for unrecorded positive-warmup history. Retained
statistics, proposal scale, acceptance accounting and RNG consumption stay
unchanged. The private recording switch supplies the comparison path without
adding a public option, fit field, cache schema or dependency.

Julia 1.10.8 passes 383 warmup assertions (118.68 seconds), including the
existing AdvancedHMC/Turing checks. Julia 1.12.5 passes the 80 random-walk
assertions (97.49 seconds). Controlled overflow proposals distinguish events
by phase and chain; recording on/off preserves retained arrays, diagnostics
and 16 subsequent RNG values. Recorded/unrecorded cache round trips and
public-report JSON/Markdown bundles pass, and malformed counts/coverage
are rejected without replacing an existing cache. Forty checks on two actual
pre-edit caches (16.00 seconds) confirm unchanged keys, original bytes,
automatic reuse and fresh retained-result equality.

The broader regression passes 1,717 assertions (552.71 seconds): 1,458 existing
boundary/CmdStan-contract checks and 259 report checks, including synthetic
GMFRM/MGMFRM reports. Recounting both preceding Turing logs also gives 1,458
boundary checks; their earlier 1,558 manual totals were incorrect. The text is
corrected here and above; original logs and historical receipts are preserved.

The manual/language build passes for 19 source files and 14 HTML pages
(23.80 seconds), retaining four existing omitted research/release docstrings.
The local ignored [receipt](../../results/workflows/20260914-rw-warmup-01/receipt.json)
preserves command logs, source hashes, pre-edit/new caches and runnable checks.
Times include compilation and concurrent work, not benchmarks. No full suite,
CI, native CmdStan fit, statistical replication, independent review or release
acceptance is claimed.

## Fixed-coefficient unit-logit MFRM reference, 2026-09-14

Question: what remains to estimate when fixed-Q item loadings and rater
consistencies are one, and how does that response model relate to ordinary
MFRM? The new private `_MFRMFixedQReferenceLogDensity` uses the existing guarded
fixed-Q design and production likelihood, with those coefficient coordinates
removed. It is a numerical target, not a public fitting option or result type.

For response category `k = 0, ..., K-1`, its cumulative score is

`eta[p,i,r,k] = sum(h=1:k, dot(Q[i,:], theta[p,:]) - item[i] - rater[r] - step[i,h])`.

Category probabilities are the softmax of these scores. The reference is
confirmatory and additive: active loadings equal one, inactive loadings zero,
consistencies one, and latent-population covariance `person_sd^2 I`. Mixed Q
rows permit compensation through the sum; this does not establish exploratory,
correlated-factor, bifactor or noncompensatory support. The small verification
cases use two persons, three raters, four categories, and 2D pure/mixed or 3D
pure Q. Existing guarded design restrictions remain in force.

| Block | Reference coordinates and restriction |
| --- | --- |
| Ability | All `J * D` theta coordinates, directly in unit-logit units |
| Rater severity | `R - 1` free coordinates; the last is their negative sum |
| Item location | All `I` coordinates remain free |
| Item steps | `I * (K - 2)` free coordinates; each last step is their negative sum |
| Loadings / consistency | Fixed constants; no sampled coordinate or prior contribution |

An explicitly supplied `MFRMPrior` gives independent zero-centered normal
densities on these free coordinates, with four finite positive SDs. The prior
is proper in this chart; it is not the normalized source/exchangeable prior,
nor an assertion that free-coordinate priors are invariant to the reconstructed
rater or a change of gauge. No default production prior is selected here.

The production MGMFRM kernel retains literal 1.7. To evaluate the reference,
the adapter inserts zero log coefficients and divides the other coordinates
by 1.7. The prior is evaluated on the original reduced vector, so no Jacobian
is added to this likelihood re-expression. A separate check derives the same
prior from source coordinates: divide the four SDs by 1.7, remove the fixed
coefficient density constants, then add `-n_free * log(1.7)` for the change of
coordinates. Thus fixing coefficients alone, or substituting 1.702, would not
establish equality with the unit-logit MFRM target.

Likelihood location freedom remains: add any vector `c` to each person's
theta and add `dot(Q[i,:], c)` to each item location. The likelihood is
unchanged and the stated prior changes. Fixed slopes do not by themselves
identify these locations. The initial check attempted a single scalar PCM
using person-dimension IDs; the existing rank validator correctly rejected it.
The corrected check uses a first-item/first-rater gauge separately within each
dimension, with common rater values, and reproduces every conditional log
likelihood. It does not justify separate univariate posterior fits. The
reference intentionally keeps its prior-anchored locations; introducing hard
anchors or another chart must account for its changed prior interpretation.

Julia 1.10.8 passes 844 assertions (23.19 seconds), including 186 new reference
checks. Julia 1.12.5/CmdStan 2.39.0 passes 1,206 (74.72 seconds), including 311
existing production density/gradient assertions and 51 for the reduced Stan
reference. That test prepends the unchanged production `mgmfrm_eta` functions
to a test-only model with only the reduced `x` vector as parameters. Its 36
point/gradient evaluations cover 18, 18 and 26 coordinates under both CmdStan
Jacobian settings; density tolerance is `atol=1e-9, rtol=1e-10`, gradient
tolerance `atol=1e-8, rtol=1e-9`. Julia also checks independent equations,
exact unit coefficients, prior normalization mapping, location shifts and
invalid vector rejection. No MCMC transitions or statistical replications ran.

The local ignored [receipt](../../results/workflows/20260914-fixed-q-reference-01/receipt.json)
preserves the initial rank-deficiency failures on both Julia versions, a
subsequent test-only range-expression parse error, and the final passing runs.
It includes source hashes and the reproducible Stan reference. Every attempt
retains its original 600-second limit; times include compilation and concurrent
work. Existing public fits, caches, priors, production Stan models, exports and
dependencies are unchanged. Public workflow integration, recovery, independent
scientific review and release acceptance remain open.

## Fixed-coefficient MFRM sampling and persistence, 2026-09-14

Question: can the reduced unit-logit reference run through both existing NUTS
engines and retain its interpretation after saving and reopening? The private
adapter now reuses the AdvancedHMC and CmdStan runners, chain parser, run
validator, diagnostic/interval builders and guarded serialized-record writer.
It adds no public selector, fitting engine, dependency or plotting backend.

The reduced Stan reference is now `src/stan/mfrm_fixed_q.stan`, with `beta` as
its only sampled vector and observation-wise `log_lik` as generated output.
Both Stan models include the same package-owned `mgmfrm_eta` function. The
compiler expands that one known include into its exclusive fresh build copy;
expanding the ordinary MGMFRM file reproduces the pre-change source byte for
byte. Build-directory, executable-identity and caller-environment guards remain
in the existing compiler. The old test-only reduced model is removed.

`bayesianmgmfrm.fixed_q_mfrm_samples.v1` identifies the fixed-coefficient model
separately from ordinary fit caches and normalized-prior samples. Its prior
record declares unit logits, the free-coordinate measure and prior-anchored
locations, plus the four explicitly supplied SDs. The target identity covers
the design/data and that prior; the content hash covers the canonical sample
record. Restoring rebuilds the target and verifies each retained Julia density,
chain layout and recorded warmup history before deriving names, diagnostics
and intervals. The CmdStan adapter and reload also verify retained `lp__` with
its full normalizing constants. No generalized 1.7 rescaling is applied to
these already unit-logit draws. Reconstructed views and private interval figures
are added in the follow-up below; public fit/report integration remains open.

The new test file passes 214 assertions on Julia 1.10.8 (32.86 seconds), and
457 on Julia 1.12.5 with CmdStan 2.39.0 (70.32 seconds). Two-person examples
use 2D mixed Q with 18 free parameters and 3D pure Q with 26. Each native fit
has two chains, 10 warmup iterations and 12 retained iterations per chain.
They verify reduced names/means/interval reconstruction, unit-logit densities,
recorded and unrecorded warmup, and save/reload behavior. Synthetic CSV tests
reject correct draws with wrong `lp__` or observation likelihoods; rehashed
malformed sample tests reject changed units, priors, design labels, draws,
chain order and warmup history while preserving existing file bytes.

Regression checks pass 2,667 assertions on Julia 1.10.8 (94.37 seconds):
844 density/measure, 365 normalized-prior sampling, and 1,458 shared fitting/
CmdStan boundary checks. Julia 1.12.5/CmdStan passes 1,937 (191.20 seconds):
1,206 density/gradient and 731 normalized-prior sampling checks. These include
the existing normalized-prior v1/v2 save/reload paths and compiler guards.
Two additional 2D fits retain one sample file per backend: 60 checks cover
writing/reopening them (41.18 seconds), and a fresh Julia 1.12.5 process passes
62 reload checks (19.59 seconds) without starting MCMC. The fixture, explicit
prior, identities, reduced names and all 48 retained densities are verified
again. Across the new tests and retained artifacts, eight fixed-coefficient
fits ran: five Julia and three CmdStan, each with two short chains.

The local ignored [receipt](../../results/workflows/20260914-fixed-q-sampling-01/receipt.json)
records native commands, source and log hashes, regression results, saved
samples and a fresh-process reload. All native attempts keep their original
600-second limits. These are bounded implementation checks with short,
warning-bearing chains; no posterior agreement claim, recovery study,
statistical replications or independent acceptance follows from them.

## Fixed-coefficient MFRM reconstructed results and figures, 2026-09-14

Question: can an analyst inspect every rater and item step without manually
reconstructing MCMC draws, while keeping the fixed-coefficient model's scale
and uncertainty clear? The private sample result now adds `model_coordinates`,
`model_posterior_summary` and `diagnostics.model_parameter_rows`. Its explicit
model identity is `:mfrm_fixed_q`; the underlying generalized `FacetSpec`
continues to supply validated design information only.

The reconstruction reuses existing sum-to-zero/positive-coefficient algebra
with the retained locations and steps already in unit logits. It never calls
the 1.7 likelihood transformation to produce plotted coordinates. The last
rater and each last item step are reconstructed separately for every draw,
then summarized and diagnosed. Their intervals are not sums of marginal
intervals. Active Q loadings and rater consistencies equal one; first baseline
steps equal zero. These structurally fixed values are excluded from MCMC
quality gates and shown as diamonds without intervals. Inactive Q zeros remain
omitted. The example 2D mixed-Q and 3D pure-Q layouts contain 35 and 48 model
coordinates, versus 18 and 26 retained free coordinates.

The private `_mfrm_fixed_q_plot_data` and `_plot_mfrm_fixed_q` entry points
reuse the existing parameter/dimension selector, interval builder and
CairoMakie interval renderer. Exact parameter ordering, named dimensions,
selection limits and editable PDF/SVG figures are retained. The figure names
the fixed-coefficient MFRM and backend; location/step axes say unit logits,
while coefficient axes are dimensionless. Its diagnostic note covers the
entire model, including unselected coordinates. Plotting rebuilds from the
validated canonical record rather than trusting mutable derived views.

The sample v1 schema, target identity, retained draws, prior, densities and
samplers are unchanged. Old Julia/CmdStan samples from the preceding handoff
load with the new reconstructed summaries, and repeated plotting leaves their
bytes unchanged. Public `plot_posterior`, fit/cache dispatch and exports remain
restricted to their existing fit types. These private functions are not yet
a new supported public workflow.

The first numerical/sampling checks pass 1,821 assertions on Julia 1.10.8
(50.85 seconds) and 2,469 on Julia 1.12.5/CmdStan 2.39.0 (107.21 seconds).
Each includes 1,068 existing posterior/trace/rank/predictive/Wright-map data
checks. The new reconstruction checks use nonzero synthetic coordinates and
short two-chain 2D/3D fits, confirming direct unit values, zero sums, fixed
values, derived-parameter diagnostics, quantiles, named selection and reloads.
An initial render/reload check passes 108 assertions (76.88 seconds) and
renders both old backend samples plus existing MFRM/GMFRM/MGMFRM interval
figures. No MCMC starts in that rendering process. Review also corrected a
private warning caption that referred to an unavailable public fit method,
and preserved early rejection of invalid interval requests before deriving
coordinates and diagnostics.

Final checks pass 1,821 assertions on Julia 1.10.8 (58.20 seconds) and 1,176
on Julia 1.12.5 (113.71 seconds; 1,068 existing plot-data checks plus 108 old
sample/render checks). Subsequent presentation changes affect warning text,
early interval validation and the dimension-context guard below. Rendering starts
no MCMC, produces six private figures in PDF/SVG/PNG, and checks six existing
model/raw interval figures. All six private PDFs have one page and correct
model/backend/scale/warning text; Poppler rasters were visually inspected for
clipping, overlap and fixed-value/interval distinction. The existing sample
files retain their recorded hashes.

A final call-site review found that forwarding keyword arguments to the shared
selector could accidentally accept a `dimension_labels` override. Dimension
context is now a positional internal argument taken from the validated model;
both public fits and private samples reject that undocumented keyword. The
focused follow-up passes 1,824 assertions on Julia 1.10.8 (72.15 seconds) and
1,079 on Julia 1.12.5 (89.44 seconds), including positive named selection and
override rejection on both old backend records. This routing change preserves
the valid inputs and displayed coordinates of the inspected figures. Across
all checks and reruns, ten short fixed-coefficient fits ran: eight Julia and
two CmdStan; the render and old-record routing checks start no MCMC.

The local ignored [receipt](../../results/workflows/20260914-fixed-q-results-01/receipt.json)
retains all attempts, final checks, before/after sources, old sample hashes,
rendered figures and PDF inspection. All native commands retain their original
600-second deadlines. These are implementation and visual checks, not
convergence, recovery, posterior agreement or independent scientific review.

## Fixed-coefficient MFRM trace and rank figures, 2026-09-14

Question: can the private reference display chain mixing for its reconstructed
coordinates without manual reshaping or misleading fixed-value diagnostics?
The private `_mfrm_fixed_q_diagnostic_plot_data` and
`_plot_mfrm_fixed_q_diagnostics` now use the existing trace/rank builder and
renderer. The adapter rebuilds from the checked canonical record, selects
model coordinates using stored dimension labels, and passes actual retained
chain IDs, iteration numbers and the existing model-parameter diagnostic rows.
No sampler, rank estimator, persistence schema or public fit selector is added.

Derived-coordinate metadata marks only the last rater and each last item step.
Those traces show their own rank-normalized R-hat and bulk/tail ESS. Fixed
loadings, consistencies and baseline steps have no rank comparison or parameter
convergence gate. All retained iterations remain visible; rejected-transition
ties use the existing average-rank calculation. The rank-bin request is capped
at the retained draw count. A subset retains whole-model warnings and the
per-chain divergence, maximum-depth, E-BFMI and nonfinite-density summaries.
Warmup parameter draws are not stored and are not fabricated by this adapter.

The model and backend appear in the figure title. Location/step traces use
unit logits, and fixed coefficients use dimensionless labels. Figures remain
editable CairoMakie objects with PDF/SVG output. The existing public MFRM,
GMFRM and MGMFRM wrappers retain their labels and raw/model semantics. Internal
dimension context stays positional: callers cannot override it through an
undocumented `dimension_labels` keyword.

Focused checks pass 1,920 assertions on Julia 1.10.8 (78.62 seconds) and 2,648
on Julia 1.12.5/CmdStan 2.39.0 (160.57 seconds). Each includes 1,075 existing
public plot-data checks; their shared single-chain, constant-value, missing
telemetry and tied-rank cases remain covered. Private integration uses 2D
mixed-Q and 3D pure-Q two-chain fits, verifies draw/rank correspondence against
an independent rank-count formula, distinguishes fixed/derived values, checks
named selection and limits, rejects changed chain records, and rebuilds after
save/reload. Six short fits ran (four Julia, two CmdStan), each with 10 warmup
and 12 retained iterations per chain; they are operability checks only.

The initial rendering script used an incorrect literal consistency-parameter
name and was rejected by the existing exact-name selector after 28 passing
checks. The script now selects that name from the result's parameter metadata.
The failed log/script are retained; no library or sampler correction was
needed for that failure. The render/reload checks use old saved results from
both backends without starting MCMC or modifying those files.

The final render/reload run passes 228 assertions (79.96 seconds): 204 for
the private saved results and 24 for the existing public renderer. It produces
eight private trace/rank figures in PDF/SVG/PNG, covering derived, fixed,
mixed fixed/derived and named-dimension selections on each backend, plus six
existing public model/raw figures in SVG/PNG. All eight private PDFs have one
page and the expected model/backend, unit, warning and applicability labels.
Every Poppler raster was visually inspected; labels, legends and footers are
readable without clipping or overlap. This visual check does not assess mixing.

The local ignored [receipt](../../results/workflows/20260914-fixed-q-traces-01/receipt.json)
records the native commands, source hashes, all attempts, final rendering and
visual inspection. Every attempt keeps its original 600-second limit; timings
include compilation and concurrent work. These implementation/visual checks
do not establish convergence, posterior agreement, recovery, scientific
acceptance or a public fixed-coefficient workflow.

## Fixed-coefficient MFRM conditional predictive checks, 2026-09-14

Question: can the analyst compare observed score-category proportions with
replicated ratings from the private reference, without reshaping draws or
changing its unit-logit model? `_mfrm_fixed_q_predictive_check` validates the
canonical record and feeds its selected draws through the existing likelihood
mapping, category generator and predictive-summary assembly. The source
likelihood's 1.7 multiplier cancels the reference coordinate mapping; stored
locations and reported parameters remain in unit logits, with coefficients
fixed at one. No 1.702 substitution, prior/Jacobian change or sampler is added.

The numerical check retains replicated integer scores, the existing overall,
category and facet summaries, grouped rows, target/backend identity, selected
chain/iteration labels and full-model diagnostics. The private
`_mfrm_fixed_q_predictive_plot_data` and `_plot_mfrm_fixed_q_predictive` reuse the
public category-summary builder and renderer, with explicit fixed-coefficient
MFRM/backend/unit-logit labels. The three existing public fit methods now share
their identical check assembly; their supported fit types and output fields
remain unchanged. No public fixed-coefficient selector is introduced.

One replicated dataset is generated per selected draw. Default selection uses
all retained draws in order; `ndraws` samples with replacement and
`draw_indices` preserves explicit order and repeats. A local MersenneTwister
makes selection and category replication repeatable with the same integer
`seed` in the same environment, including after old-record reload; it leaves
the global RNG unchanged. `interval` changes only the summary. All declared
categories remain visible. Whole-model warnings survive selection, and no
warmup draw or new person/item/rater is generated.

The tests compare probabilities with an independent unit-logit adjacent-category
formula for nonzero 2D mixed-Q and 3D pure-Q parameters, and with each observed
pointwise log likelihood. Selected replicated ratings are checked against that
formula and independent seeded inverse-CDF draws. They also check proportions
and quantiles, grouped-summary compatibility, altered derived-view recovery,
corrupt canonical-record rejection, input limits and global-RNG isolation.
Short backend fits verify operation and persistence; they do not assess mixing
or statistical validity.

Focused checks pass **2,162 assertions on Julia 1.10.8** (44.24 seconds) and
**3,104 on Julia 1.12.5/CmdStan 2.39.0** (93.57 seconds). Both include 1,075
existing public plot-data assertions. Six short fixed-coefficient fits ran:
four Julia and two CmdStan, each with two chains, 10 warmup and 12 retained
iterations per chain. No statistical-evaluation replication was added.

The old-record/render run passes **164 assertions** (46.20 seconds): 152 for
both saved private backend results and 12 for the existing three public
predictive renderers. It starts no MCMC. Six private figures (all, sampled and
explicit ordered draws per backend) are saved as PDF/SVG/PNG; three public
figures are checked and saved as SVG/PNG. All six private PDF pages were
rasterized with Poppler and visually inspected. Titles, category ticks,
observed/replicated marks, interval legends, selection counts and conditional
scope/warning captions are readable without clipping or overlap.

The local ignored [receipt](../../results/workflows/20260914-fixed-q-predictive-01/receipt.json)
retains before/after source snapshots, exact commands, logs, old sample hashes,
figures and PDF inspection records. All three native runs succeeded within
their original 600-second deadlines. Old sample bytes and their v1 schema are
unchanged. This is implementation and implementer visual evidence, not
convergence, recovery, posterior agreement or independent reader acceptance.

## Fixed-coefficient MFRM result/report contract, 2026-09-14

Question: can a reader identify the fitted model and interpret its estimates,
uncertainty and warnings from one report, without rebuilding tables from draws?
The [saved-result adapter](../../src/mfrm_fixed_q_samples.jl),
[report assembly and exporters](../../src/bayesian_fit.jl), and
[figure-bundle path](../../src/posterior_plot.jl) were traced for this handoff.
This slice specifies the contract and probes existing transport; it does not
add a production report constructor or promote the reference to a public fit.

### Decision and supported core

Use one private NamedTuple report assembler in `src/mfrm_fixed_q_samples.jl`,
then reuse the existing full `bayesianmgmfrm.fit_report.v1` JSON/table/Markdown
transport. A new fit type, serializer or section registry is unnecessary for
this first slice. Existing exporters accept report payloads independently of
fit types, and their `*_rows` fallback already includes
`diagnostics.model_parameter_rows`. Structural acceptance by those exporters
is not validation of model semantics: the assembler must enforce this contract.

The report's `family` must be `:mfrm_fixed_q`, with the human label
"Fixed-coefficient multidimensional MFRM". Its storage spec's `:mgmfrm` family
selects reused design/kernel machinery; it must not label the fitted model or
supply estimated-loading prior claims. Keep `estimation_status = :private_reference`
and `metadata.model = :mfrm_fixed_q`. The first assembler returns the full
internal report only. The existing public projection maps this status to
`:unknown` and removes `report_policy`; accepting that projection is not public
support. Public status/projection semantics need their own later decision.

| Report content | Authoritative source and required meaning | Adaptation required |
| --- | --- | --- |
| Identity and run | Checked `record.schema`, `record.target_identity`, `record.content_hash`, `record.prior`, dimensions/labels/Q, `run.backend`, sampler, controls, retained count and stored diagnostic settings | Keep target identity, exact sample-content hash and report-content hash distinct. Surface model, backend, unit-logit convention and source identity in readable metadata, not only nested JSON. A report is not a fit cache or restart checkpoint. |
| `posterior` | Free-coordinate summary on unit logits; stable reduced parameter names | Label it as sampled free coordinates. Preserve this existing slot's role; do not rename unit values to generalized raw/log-positive values. |
| `direct_posterior` | Reconstructed model-coordinate summary, with `block`, named dimension, `fixed` and `derived` | Display its unit-logit locations and dimensionless fixed coefficients explicitly. Fixed point intervals mean declared constants, not estimated certainty. Last-rater/last-step intervals come from their reconstructed draws. |
| `diagnostics` | Validated free and model parameter rows, retained sampler rows and whole-model summary | Preserve both `parameter_rows` and `model_parameter_rows`; subsets do not replace the whole-model gate. Add visible warning rows. Fixed rows retain `quality_gate_applicable = false` and `structurally_fixed`; derived rows retain their own diagnostics. Existing JSON represents nonfinite diagnostic numbers as strings and missing values as null; never turn either into zero. |
| `warmup` | Rebuilt `warmup_diagnostics` from the canonical run | Preserve recorded/not-recorded/not-run coverage and separate it from retained warnings. Missing parameter histories cannot be synthesized. Reuse the warmup interpretation and table order. |
| `prior_policy`, fixed coordinates and Q | Actual fixed-Q prior record, fixed/derived coordinate metadata, and stored Q/labels | Describe independent zero-mean normals on the free unit-logit person/rater/item/step coordinates, and deterministic constants/reconstructions. The last rater and last item steps have induced dependent priors. Do not reuse the generalized estimated-log-loading/consistency policy or its source-gauge/prior claims. Report the prior-anchored locations and identity latent-population correlation restriction. |
| `posterior_predictive` | One `_mfrm_fixed_q_predictive_check` call; existing summary rows including grouped rows | Store requested selection, resolved indices, selected chain/iteration labels, RNG/seed, interval and counts. Explain conditioning on the existing rating rows/persons/items/raters and pointwise replicated-proportion intervals. Summaries and figures must use these same replications. |
| Other report sections | Capability decisions, not placeholders with numerical values | Prior predictive, calibration, WAIC/LOO, category-functioning, rater-homogeneity, DFF, MCMC-budget guidance and fit artifacts have no verified fixed-Q report adapters. An unsupported requested section gets its specific reason; a supported section deliberately disabled is `not_requested`. No fresh priors or zero-valued estimates may stand in for unavailable results. |

The assembler must revalidate the canonical record before section-error capture.
A changed hash, target, prior or run is fatal to report construction; stale or
edited derived views are rebuilt. Diagnostic thresholds come from the stored
run. Initially keep one central posterior interval shared by the free/model
summaries and interval figure, plus a separate predictive interval. The local
seed governs predictive draw selection and category replication only; parameter
summaries and diagnostic gates use every retained draw. Selection, interval and
seed must not silently redefine the target or the MCMC gate.

### Concrete display and lifecycle gaps

- `fit_report`, `fit_metadata`, `_model_manifest` and the fit-taking figure bundle
  dispatch on the three public fit types. Recasting this result as `MGMFRMFit`
  would import the wrong coefficient/prior/scale assumptions. Use a dedicated
  private assembler feeding the existing report transport.
- Generic Markdown metadata currently reads a fixed set of top-level fields.
  Nested target/backend/prior metadata alone is invisible. Section
  interpretations are printed only for warmup; a new posterior scale or
  predictive conditioning field alone is also invisible. Extend the existing
  metadata/section presentation with explicit identity, coordinate and
  conditioning explanations; display unsupported reasons. Preserve current
  reports when the additional fields are absent.
- `fit_report_health(...).complete` means no captured section errors. Missing
  sections and `unsupported` sections do not make it false; MCMC warnings do
  not make it false either. The assembler must populate its required core and
  explicit unsupported sections. Explain report-generation completeness,
  capability support and MCMC quality separately, without changing the shared
  health contract or manufacturing a new scientific pass flag.
- The report-only bundle rejects `figures`; the fit-taking bundle expects
  `.design`, `.draws`, public diagnostics and `fit_report(fit)`. After the payload
  is verified, adapt the existing staging/figure-data/export path for this
  private result. Its interval, trace/rank and predictive renderers already
  exist. Reuse the report's predictive rows instead of resampling, link figure
  data to the exported report hash, and retain preflight/staging, overwrite and
  tamper checks. A scalar Wright map is outside this multidimensional slice.

### Implementation order and acceptance

1. Add the private report assembler and the minimal readable metadata/section
   presentation. Reuse section capture, row exporters and bundle hashing; keep
   inference, canonical samples, public fit constructors and dependencies
   unchanged. Verify required identity/prior fields, fixed/derived semantics,
   both diagnostic tables, warmup coverage and predictive selection against
   Julia and CmdStan saved results. Malformed canonical inputs must fail before
   any output is written.
2. Round-trip the full report, tables and Markdown with normal nested-hash
   verification. Check that visible model/backend/scale/conditioning text and
   warnings survive reload, and that unsupported reasons are readable.
   `require_complete` must reject captured errors without relabeling sampler
   warnings or unsupported capabilities as generation failures. An export
   timestamp may change a report hash; the source sample hash remains stable.
3. Connect the three existing private figures to that checked report bundle.
   Assert exact shared posterior intervals, predictive rows and resolved draw
   indices; test destination preservation on failures and figure-byte tampering.
   Inspect the final PDFs. Public model selection, cache conversion, public
   projection and independent reader/scientific acceptance remain separate.

### Compatibility evidence and limits

A standalone probe assembled explicitly labelled internal compatibility drafts
from the old Julia and CmdStan sample records. **62 assertions pass on Julia
1.12.5** (29.77 seconds), without MCMC or a CairoMakie load. Full report and table
bundles round-trip with normal nested-hash checks, preserving prior/target/sample
identity, fixed/derived summary metadata, model diagnostic rows and predictive
indices/chain labels. Both source samples remain byte-identical. The probe also
confirms the expected Markdown omissions, `:unknown` public projection, rejected
report-only figure request, and error-before-write behavior for
`require_complete`. Its drafts intentionally lack the future production
assembler's complete metadata/policy/presentation contract.

The initial attempt passed 60 assertions and failed the two comparisons of
model diagnostic rows using `==`: fixed diagnostic entries contain `NaN`,
which is not equal to itself under that operator. Replacing that probe assertion
with `isequal` resolves the comparison; no library correction was needed.
Both attempts retain their original 600-second deadline. The first failed
script/log and drafts remain alongside the successful check.

The local ignored [receipt](../../results/workflows/20260914-fixed-q-report-contract-01/receipt.json)
contains the probe, both attempts, checked bundles, source snapshots/hashes and
document changes. Production source, inference, tests and dependencies are
unchanged in this slice. No new backend sampling, PDF check, minimum-version
run, independent-reader review or scientific validation is claimed.

## Fixed-coefficient MFRM internal reports, 2026-09-14

Question: can one saved-result report explain which model was fitted, how to
interpret its coordinates and predictions, and which analyses are available?
`_mfrm_fixed_q_report` now implements the preceding contract through existing
full-report section, health and export helpers. It returns a private
`bayesianmgmfrm.fit_report.v1` NamedTuple; it does not create a public fit type,
change the canonical sample schema, or enable a public model selector.

The report names fixed-coefficient multidimensional MFRM and its Julia or
CmdStan backend. Readable metadata includes the unit-logit convention, target
identity, source-sample schema and exact sample-content hash. Structured metadata
also retains the actual prior, sampler controls, diagnostic settings and facet
levels. The report's own export hash remains a separate identity.

Free-coordinate and reconstructed summaries use one central posterior interval
and all retained draws. Reconstructed rows retain fixed/derived flags and named
dimensions; fixed point intervals are explained as declared constants. Both
free and model-coordinate diagnostic tables remain present, with whole-model
warnings and stored gates. Warmup retains its separate coverage and the shared
interpretation. Prior/fixed-coordinate/Q/pooling tables report the actual free
unit-logit priors, deterministic coefficients, induced dependent reconstructions,
fixed hyperparameters and identity latent-population correlation restriction.
They do not import the generalized estimated-coefficient prior policy.

One predictive check supplies the report's overall/category/facet/grouped rows,
resolved draw indices, chain/iteration labels, selection policy, counts and
seed. Its explanation states the existing-rating-row conditioning and pointwise
replicated-statistic intervals. All-retained, sampled-with-replacement and
explicit ordered/repeated selections keep the same semantics as the private
predictive adapter. Prediction can be disabled; draw selection while it is
disabled is rejected. Posterior summaries and diagnostic gates never use that
predictive subset.

Ten sections explicitly remain unsupported: rating-design audit,
category-functioning, rater-homogeneity, MCMC-budget guidance, prior predictive,
calibration, WAIC, LOO, DFF and public fit artifacts. Their reasons identify
missing fixed-coefficient report adapters, not mathematical impossibility.
A disabled supported predictive section is `not_requested`. Invalid canonical
records fail before section-error capture. Computation failures use the existing
capture/throw policy, and `require_complete` rejects captured errors; unsupported
sections and MCMC warnings remain distinct from generation completeness.

The existing Markdown renderer now displays optional named-model/backend/scale/
source-identity metadata, report/section interpretations, unsupported reasons
and captured error messages. Explanations remain visible at `max_rows = 0` and
for sections without tables. Existing output without those additional fields
keeps its structure; warmup's shared explanation now precedes its table preview.
No report/table/public-projection schema, health rule or serializer changes.

```julia
report = BayesianMGMFRM._mfrm_fixed_q_report(result;
    posterior_interval = 0.9, predictive_interval = 0.8,
    seed = 42, draw_indices = [24, 1, 24, 2], require_complete = true)
save_fit_report_bundle(directory, report;
    title = "Fixed-coefficient multidimensional MFRM report", require_complete = true)
```

Here `result` is a validated same-environment fixed-Q sample result, and the
indices are an example for at least 24 retained draws. This internal report is
not a fit cache, restart checkpoint, public projection or figure bundle. The
existing `fit_report(result)` still has no method; private reports return the
full view only. Figure bundles will consume these verified report rows next.

The Julia 1.10.8 integration/regression run passes **1,843 assertions**
(431.52 seconds), including the existing public Markdown, warmup-report and
report-completeness checks. A separate Julia 1.12.5 process generates six
report bundles from the old Julia/CmdStan samples and passes **206 assertions**
(43.50 seconds). A fresh process reproduces their report content apart from
creation timestamps and passes **224 assertions** (28.20 seconds), including
18 checks loading three historical public figure bundles with normal nested
hash verification. No MCMC or renderer starts in either saved-result process.

The generated Julia ordered-selection and CmdStan sampled-selection Markdown
were inspected for readable model/backend/scale/source identity, coordinate
meaning, whole-model warnings, predictive conditioning/counts/seed and
unsupported reasons. All six report bundles have automated text and table
checks, including explanation visibility with previews disabled. Stored sampler
rows retain their historical generic `raw_unconstrained` tag; for this reference
those are free unit-logit coordinates, not rescaled generalized-model locations.

The initial Julia 1.12.5 combined regression hit its original 600-second
limit (600.08 seconds, exit 124) after its last emitted progress message from
the existing warmup-report checks. Buffered assertion summaries were not
retained, so that attempt has no credited assertion count. Its complete log
is preserved. Follow-up runs split the new fixed-Q/Markdown checks under
normal compilation from the existing warmup/completeness checks under
`--compile=min`, already used for earlier report verification. Source and
assertions stay identical; no deadline, threshold or sampling control is
relaxed. This is not a full-suite or cold-start performance acceptance claim.

Both follow-up runs pass: Julia 1.12.5 with CmdStan passes **2,888 assertions**
for the fixed-Q/Markdown checks (101.33 seconds), and the existing public
warmup/completeness regression passes **292 assertions** (488.25 seconds).
The five successful processes total **5,453 assertions**, including repeated
checks across versions and saved-result processes, not independent scientific
replications. Sampling remains limited to small implementation fixtures;
statistical acceptance and PDF review are not claimed.

The local ignored [receipt](../../results/workflows/20260914-fixed-q-report-01/receipt.json)
retains all six attempts, exact commands and deadlines, six report bundles,
old input samples, before/after source snapshots and hashes. Tested source
remained unchanged between these runs. Existing source/environment inputs,
sample bytes and historical bundle manifests retain their recorded hashes.

## Fixed-coefficient MFRM report figures, 2026-09-15

Question: can users save the private model's report and diagnostic figures
without manually reconstructing draws or independently repeating prediction?
`_save_mfrm_fixed_q_report_bundle` now supplies the existing interval, trace/rank
and predictive renderers to the shared staged bundle writer. Public fit bundles
use the same extracted writer and destination checks. No dependency, public
fit type, sampler, cache format or report/table schema is added.

The private writer rebuilds the canonical sample record before using derived
views, builds one full report, and uses its central posterior interval and
exact replicated category rows. Prediction retains the ordered/repeated or
sampled draw selection, counts, chain/iteration labels and seed. Interval and
diagnostic figures continue to use all retained draws and stored whole-model
gates. The interval inputs now also retain each coordinate's `derived` flag.
All three figures use the same existing fixed-coefficient model/backend/unit
labels as standalone plots. Diagnostic inputs omit only the redundant summary;
the caption and full-model warning remain in the numerical record.

Figure JSON records include target, source-sample schema/hash, backend and scale
alongside the exported report hash. PDF, SVG and numerical JSON are listed in
the existing v2 bundle manifest and verified by the ordinary loader without
requiring CairoMakie or a fit cache. All figures render in a temporary directory
before destination exports are written. Selection/rendering failures preserve
existing destination files, including unrelated user files; this does not add
a transactional guarantee for arbitrary I/O failure during the final copy.

```julia
selection = (block = :person, dimension = "Ability 2") # use a stored label
BayesianMGMFRM._save_mfrm_fixed_q_report_bundle(directory, result;
    figures = (posterior = selection, diagnostics = selection, predictive = (;)),
    posterior_interval = 0.9, predictive_interval = 0.8,
    draw_indices = [24, 1, 24, 2], seed = 42, require_complete = true)
report = load_fit_report_bundle(directory; require_complete = true)
```

The index example requires at least 24 retained draws. Figure-level options
select coordinates and size; intervals and prediction settings belong on the
bundle call. Existing coordinate-count limits reject oversized selections
without silently discarding coordinates. Scalar Wright maps, public projection
and fit-cache conversion remain unavailable for these private records.

Julia 1.10.8 passes **1,580 assertions** (51.96 seconds), including the existing
fixed-Q sampler/result checks, Markdown regression and renderer-absent bundle
requests. Julia 1.12.5 passes **216 assertions** (72.55 seconds) generating
four bundles from the unchanged old Julia/CmdStan samples: three figures per
backend plus a predictive-only replay. The checks compare report/figure
numbers and identities, preserve the global RNG and input bytes, detect edits
to PDF/SVG/JSON, and preserve every destination file after a later figure's
invalid selection. Invalid seeds, unsupported figures, unavailable prediction
and required-completeness failures also preserve the destination.

The first rendering attempt stopped in the scratch verification harness's
`JSON3.read` type argument (24.11 seconds, exit 1), before loading samples or
writing figures. Correcting that argument was sufficient; production source,
test assertions and the original 600-second deadlines stayed unchanged.
Both the failed script/log and successful attempt are retained.

All eight private PDFs contain one page and pass model/backend/unit/warning
text checks. Six distinct figures were rasterized and visually inspected for
labels, fixed/derived interpretation, traces/ranks, legends, predictive counts
and warnings; no clipped or overlapping text was found. The two predictive
replay PNGs are byte-identical to their inspected counterparts. These are tiny
implementation fixtures with visible MCMC warnings, not scientific results or
an independent-reader acceptance review.

The existing public report/figure regression passes **280 assertions** on
Julia 1.10.8 (392.61 seconds), including MFRM, GMFRM and MGMFRM. A fresh Julia
1.12.5 process passes **45 assertions** (22.25 seconds): 32 private report/figure
reproduction checks, 12 old/new bundle reads and one renderer-absence check.
It reproduces numerical figure inputs, the report apart from creation time,
and the typed report hash after restoring that saved time. No renderer or
sampling starts in this process.

The first fresh-process probe had four failed hash comparisons (21.65 seconds,
exit 1) because it incorrectly hashed a JSON dictionary as the original typed
artifact. Its 28 passing comparisons already reproduced the report/figure
contents. Full-report artifact hashes retain Julia type information; the JSON
export has a separate hash verified by the existing loader. The corrected
probe compares the regenerated typed report, preserving both checks rather
than changing the transport or disabling hash verification. That failed
script/log is also retained.

The four successful runs total **2,121 assertions**. The only new sampling is
the existing Julia test's two small fixed-Q fits (two chains, 10 warmup and
12 retained draws per chain); CmdStan figure checks reuse its old samples.
All six attempts, exact commands/deadlines, source snapshots/hashes, old sample
bytes, generated bundles and PDF review are retained in the local ignored
[receipt](../../results/workflows/20260915-fixed-q-report-figures-01/receipt.json).
Production source and repository tests stayed unchanged during these runs.

## Fixed-coefficient MFRM public API contract, 2026-09-15

Question: how can a user request multidimensional MFRM, identify the actual
model, and reopen its estimates and figures without learning private sampler
names? This is an implementation decision for the next slices, **not a
complete fitting workflow or a declaration of statistical acceptance**. The
canonical specification is available for inspection as recorded below. It follows the
verified private report/figure workflow above.

### User entry point and model scope

Use `mfrm_spec(data; family = :mfrm, dimensions = D, q_matrix = Q,
dimension_labels = labels)` for specification inspection. For
`D >= 2`, the first fitting route will be `BayesianMGMFRM.Experimental.fit`;
ordinary `fit(spec)` must explain the experimental route until stable support
is separately justified. Keep existing one-dimensional MFRM behavior, priors,
reference/hard-anchor rules and cache identities unchanged. Do not add another
long model-specific fit function or a second family-name alias.

The user-facing label is **Multidimensional MFRM (fixed coefficients)**.
The internal model discriminator remains `:mfrm_fixed_q`. Existing private
reports retain their `family = :mfrm_fixed_q` and sample records retain their
legacy `spec.family = :mgmfrm`; neither is silently rewritten to implement the
new selector. Public model metadata must identify the requested MFRM family,
the fixed-coefficient variant and its actual restrictions, without presenting
that storage implementation as an estimated-coefficient MGMFRM fit.

| Decision | Initial contract |
| --- | --- |
| Ability and response | A directly sampled ability vector for each person, item-specific partial-credit steps, one severity per rater and one difficulty per item. Unit logits, active Q coefficients exactly one, inactive coefficients zero, consistency exactly one. |
| Q and dimensions | `D >= 2`, explicit Boolean/0-1 Q, stored unique dimension labels and existing Q/observation-coverage validation. Preserve every current rejection and warning. Between-item and admitted within/mixed structures retain distinct labels; adding abilities is compensatory where an item uses multiple dimensions. Dense/exploratory or bifactor claims are not inferred from Q acceptance. |
| Prior and location | `MFRMPrior`, with its actual four fixed SDs applied to free unit-logit coordinates. Person prior covariance is `person_sd^2 I`; population correlation is identity and is not estimated. Locations are prior-anchored; the last rater and last nonbaseline item step are reconstructed negative sums. No extra Jacobian for that declared free-coordinate density. |
| Excluded requests | Rating-scale thresholds, anchors, fitted DFF/bias, estimated loadings/consistency, free covariance and new-facet prediction remain outside this first branch. Reject incompatible requests before sampling, CmdStan compilation or cache lookup. |
| Backend names | Default `:advancedhmc` means Julia NUTS; `:cmdstan` requests the maintained Stan implementation. Keep `:julia`'s existing scalar random-walk meaning; reject it for this new branch with the two supported choices. Backend changes must preserve the target/prior, not promise identical draws. |
| Scale | Fixed unit-logit model. The existing 1.7 bridge into the generalized likelihood is an implementation detail; neither 1.7 nor 1.702 becomes a user-selected multiplier for this branch. |

MGMFRM's existing `discrimination = :none` continues to select its generic
compatibility route with estimated Q-masked loadings and consistency. It must
never become an alias for fixed-coefficient MFRM. Likewise, the shared
`MFRMPrior` constructor does not make scalar reference constraints and
multidimensional prior anchoring interchangeable.

### Result, reporting and persistence

Use one dedicated `MultidimensionalMFRMFit` result type, defined at package root
for a stable Julia serialization identity and exposed through `Experimental`.
Users obtain it from `fit`; they do not construct it or manipulate its draws
for ordinary reporting. It owns a validated canonical fixed-Q record. Derived
summaries and diagnostics are rebuilt from that record using existing helpers;
do not store a second mutable authority or pretend it has a scalar design.
The first adapter can remain private while the public specification/cache
pieces are implemented.

Do not insert the type into `_ModelComparisonFit`: that union also activates
refitting, model comparison and other numerical analyses that have no fixed-Q
adapters. Add explicit methods only for the verified operations below. A new
all-purpose fit interface or capability registry is unnecessary.

| User operation | Required result behavior |
| --- | --- |
| `fit_metadata(result)` and display | Name the model, named dimensions/Q geometry, backend, unit scale, actual prior/location convention, identity-correlation restriction, target/source identity and experimental status. Avoid scalar reference-first or generalized raw-log-prior labels. |
| `posterior_summary(result)` | Preserve the existing sampled-coordinate meaning: free unit-logit coordinates, matching canonical names and all retained draws. |
| `BayesianMGMFRM.direct_posterior_summary(result)` | Reconstructed model coordinates, including baseline steps and reconstructed last steps/raters, named dimensions and `fixed`/`derived` flags. These are unit logits plus dimensionless fixed coefficients. |
| `diagnostics(result)` | Free and reconstructed parameter diagnostics, retained sampler rows and whole-model warning; preserve stored gates, structural fixed-value exclusions and separate warmup coverage. |
| `fit_report(result)` | Existing complete internal report plus explicit unsupported sections. Translate public central `posterior_lower`/`posterior_upper` bounds to the private interval; reject noncentral report bounds initially. Do not introduce a second public interval spelling. |
| `plot_posterior`, `plot_diagnostics`, `plot_predictive` | Qualified existing functions with dedicated methods; initial coordinate plots use `scale = :model` and existing block/dimension/parameter selectors. Predictive figures remain conditional on the observed rating rows. |
| `save_fit_report_bundle(directory, result; figures, ...)` | Existing staging and v2 figure manifest. One predictive simulation supplies tables and figures. Same interval, selected indices, warnings, backend/scale and source/report hashes. Report-only remains available with `figures = nothing`. |
| `save_fit_cache` / `load_fit_cache` | Manual save/reopen on both backends without resampling or CairoMakie. A dedicated v2 envelope for this new result records its model discriminator, canonical sample, source/target identity and matching reproducibility artifact. Reuse `_save_serialized_record`; old fit caches continue using/reading v1. |

Public report projection is a release prerequisite: it must report
`status = :experimental`, preserve the actual model/scale/prior, named dimensions,
fixed/derived meanings, diagnostics, unsupported reasons and uncertainty
interpretations, and retain its existing portable JSON hash contract. The
current generic projection can serialize the private report, but reports
`status = :unknown`; serialization alone does not close that gap.

Keep target identity, exact sample-content hash, requested-fit cache key,
typed-report hash, JSON-export hash and file hashes separate. The public
specification-to-target bridge must prove equality to the existing unit-logit
target in common free coordinates. Old private `.jls` samples keep their schema,
bytes and explicit private loader; any future import to the public v2 envelope
must validate the record and preserve its source identity, not reinterpret it
as an old `MFRMFit`/`MGMFRMFit`. No automatic in-place migration is part of this
contract. As with existing caches, Julia Serialization is for trusted records
in a compatible analysis environment, not an interchange or restart format.

Manual saved-result replay is required at first exposure. Automatic
`cached_fit`/`fit_cache_key` for the new result is deferred until its request
identity is implemented and tested; reject it explicitly meanwhile. In
particular, existing CmdStan fits still require a fresh empty compile directory
and have no automatic compiled-model or `cached_fit` reuse. Do not use a Julia
cache key for a CmdStan request.

### Proposed user workflow (not executable yet)

Here `data` is validated rating data, `Q` has one row per stored item and two
columns, and `ndraws`, `warmup` and `chains` are chosen analysis controls.

```julia
spec = mfrm_spec(data; family = :mfrm, dimensions = 2,
    thresholds = :partial_credit, q_matrix = Q,
    dimension_labels = ["Dimension A", "Dimension B"])
result = BayesianMGMFRM.Experimental.fit(spec; backend = :advancedhmc,
    prior = MFRMPrior(), ndraws, warmup, chains, seed = 42)
save_fit_cache("multidimensional.jls", result)
restored = load_fit_cache("multidimensional.jls")
selection = (block = :person, dimension = "Dimension B")
save_fit_report_bundle("multidimensional-report", restored;
    figures = (posterior = selection, diagnostics = selection, predictive = (;)),
    posterior_lower = 0.05, posterior_upper = 0.95,
    predictive_interval = 0.8, seed = 42, view = :public, require_complete = true)
```

After `using CairoMakie`, the last call should produce the reviewable report,
PDF/SVG figures and numerical inputs. For CmdStan, change the backend to
`:cmdstan` and provide a fresh empty `cmdstan_cache_dir`; the result/save/report
calls remain identical. The seed on the bundle controls predictive replication,
not the already completed sampler. Large named-dimension selections still
need explicit parameter selection or an increased display limit and figure
size; never silently omit people. The private all-coordinate diagnostic default
already exceeds the 12-coordinate limit on the retained example, which is why
the workflow selects a named dimension explicitly.

### Work order and release conditions

1. **Result adapter: implemented below.** Wrap checked canonical
   samples in the dedicated result type without changing their record schema
   or public model selection. Implement explicit metadata, free/reconstructed
   summaries and diagnostics methods. Verify both old backend records, stale
   derived-view rebuilding, malformed-record rejection, fixed/derived meanings,
   stored gates and unchanged source hashes. Leave the broad comparison union
   untouched. No new sampling or serializer is needed for this step.
2. **Canonical specification: implemented below.** Add the canonical MFRM multidimensional specification/design branch and its
   validation, constraints, prior rows, manifest/status and identity; extend
   the model contract's revalidation at the same time. Verify that the public
   request maps to the existing target, and that scalar and MGMFRM requests,
   source identities and behavior remain unchanged. A relaxed dimension guard
   by itself is not an implementation.
3. **Private fit routes: implemented below.** Connect manual v2 cache/reload,
   the matching reproducibility artifact, public report projection and the
   existing plots/bundle to that result. Test errors before numerical
   startup and preserve files on failure. Expose the experimental selector
   only once the documented example works after reload on both backends.
4. Keep statistical acceptance separate: matched-target density/gradient checks
   and short-run operability do not establish recovery, interval coverage or
   robust sampler performance. Existing statistical work and the independent
   reader walkthrough retain their own acceptance criteria before stable
   promotion or scientific claims.

The required first report includes identity, actual prior/constraints, both
posterior and diagnostic coordinate spaces, warmup and conditional prediction.
Of its ten currently unsupported sections, the **artifact** adapter is needed
for the promised cache/reproducibility path. **Rating-design** reporting is also
required for experimental exposure so users can see the validation and coverage
behind an accepted Q; it can reuse validated data/Q rows without inventing a new
analysis. Category functioning, rater homogeneity, MCMC-budget guidance, prior
predictive, calibration, WAIC, LOO and DFF can remain explicitly unsupported for
that first release. They must not silently dispatch to generalized formulas.
No automatic stable promotion follows from a complete report or a passing Q.

### Current-boundary evidence

A Julia 1.12.5 probe passes **71 assertions** (34.20 seconds), using both old
backend records without MCMC or CairoMakie. Each record has 18 sampled free
coordinates, compared with 25 in its generalized target and 35 reconstructed
model coordinates; public fit/summary/plot/cache methods do not accept the
private result. The proposed multidimensional `family = :mfrm` request and
CmdStan automatic cache request still reject. Public report projection retains
both diagnostic row sets but has status `unknown`. Named-dimension plot data
selects two person coordinates and keeps whole-model warnings. Source sample
bytes remain unchanged. This is evidence for the identified implementation
gaps, not a test of the proposed API.

The local ignored [receipt](../../results/workflows/20260915-fixed-q-public-contract-01/receipt.json)
retains the probe, output, exact command/deadline, source hashes and document
diff. Production source, tests, dependencies, public README/help and saved
artifacts remain unchanged in this contract slice.

## Fixed-coefficient MFRM result adapter, 2026-09-15

`MultidimensionalMFRMFit` is now defined at package root, unexported and without
an `Experimental` alias. Its private constructor copies and validates the
canonical fixed-Q record; the record is its only field. Each explicit metadata,
summary, diagnostic and display method rebuilds from the validated record.
Caller input and returned metadata/diagnostics cannot mutate the owned record;
direct corruption of that record is detected on subsequent reads. Stale derived
views in an input result are ignored.

`fit_metadata` identifies `family = :mfrm`, `model = :mfrm_fixed_q`,
`estimation_status = :private_reference`, unit logits, named dimensions/Q geometry,
free-coordinate priors, prior-anchored locations and identity correlation.
`posterior_summary` uses free coordinates; `direct_posterior_summary` adds model
coordinates, dimension labels and fixed/derived flags. Both reuse all existing
summary options, including noncentral quantile bounds and ROPE. `diagnostics`
returns both parameter tables, sampler rows, whole-model flags and separate
warmup coverage; defaults come from the saved record, and attempts to change
its thresholds or chain-splitting policy are rejected. Only `view = :full` is
implemented for metadata and diagnostics in this slice.

The report's existing metadata assembly is shared with the adapter. No broad
comparison-union expansion, public selector, new-result cache/artifact,
report/plot dispatch or public projection is enabled. Those requirements remain
in the contract above; the old private report/figure workflow remains usable.

The binary-response regression exposed a shared coordinate-label error: with
two categories, both item steps are structurally zero, but only the first was
marked fixed. The shared reconstruction now marks both fixed while retaining
the last step's derived flag. This excludes both from convergence gates and
propagates to existing private summaries, reports and plot data; no likelihood,
sample or prior changes are involved.

Julia 1.10.8 passes 756 deterministic assertions for two/four categories and
both backend record shapes, without sampling. The first attempt to read the old
Julia 1.12 sample files on 1.10 stopped at Serialization's newer-format check
before exercising the adapter. Those files were not converted or modified;
the deterministic checks establish native 1.10 behavior, not cross-version
Serialization compatibility or backend estimation accuracy.

On the final source, Julia 1.12.5 passes the same 756 assertions plus 439 checks
using the two saved backend records and six historical reports (1,195 total;
119.30 seconds). The saved-result outputs match the pre-fix adapter outputs;
all six reports preserve their exported values and typed hashes. Julia 1.10.8
finishes in 37.84 seconds. The binary regression first failed four assertions
and then passed after the shared fix. Each native command retained its original
600-second deadline; the timer self-test passed 21 cases. The full sampling
suite was not rerun; its existing reload tests also call the new adapter checks.

The local ignored [receipt](../../results/workflows/20260915-fixed-q-result-01/receipt.json)
retains source snapshots/diff, runnable checks, commands, outcomes (including
both failed attempts) and hashes. Old sample bytes and the previous 248 figure-
bundle artifacts remain unchanged. No MCMC, Stan compilation, figure rendering,
dependency or public README/help changes were needed.

## Fixed-coefficient MFRM canonical specification, 2026-09-15

The `family = :mfrm, dimensions >= 2` specification now accepts explicit Q and
unique dimension labels for partial-credit responses. It rejects anchors, bias
terms and non-unit discrimination. The existing Q validator supplies the same
structural and observation-coverage gates and warnings as the reference model;
accepting a Q does not establish statistical identification or recovery.
`getdesign(spec; preview = true)` returns free person-by-dimension, all-but-last
rater, item and item-step coordinates. Fixed coefficients are declarations,
not extra sampled parameters. The historical `raw_rater[...]` free-coordinate
names are retained to preserve exact alignment with private reference draws;
metadata explicitly states their unit-logit measure.

Constraints, normal-prior rows, equation, model-family contract and full/public
manifests distinguish prior-anchored person/item locations, sum-zero raters,
first-zero/sum-zero steps, fixed Q coefficients, unit consistency and identity
latent correlation. Prior density applies to the free unit-logit vector without
an additional Jacobian. The canonical spec/design revalidation uses these same
constructors. The reference density snapshots the canonical design and reuses
the established generalized-likelihood bridge; its separate canonical identity
includes the requested MFRM design and actual prior scales. Legacy targets
continue using their original storage design and identity.

The public specification status is `:specified_only`. At this inspection-only
milestone, public/experimental fitting, automatic cache requests and private
sampling of the new canonical target rejected before sampler or compiler startup.
The canonical private sampling follow-up is recorded below; public fitting and
automatic cache requests remain unavailable. The old private sampling/report
path remains available.
Row-level predictor inspection is explicitly unsupported until its own adapter
is connected; model/constraint/parameter-layout inspection is available now.

Final validation passes **1,543 assertions on Julia 1.10.8** (51.06 seconds) and
**1,983 on Julia 1.12.5** (166.19 seconds). The new 642-assertion contract check
covers two/three dimensions, two/four categories, between/mixed Q, zero/nonzero
vectors, independent density and ForwardDiff gradient calculations, matching
legacy density/CmdStan inputs, distinct canonical/prior identities, mutable-input
snapshots, stale-spec rejection and unavailable-entrypoint errors. Existing
model-family, Q-identification and result-adapter checks also pass. The saved
Julia/CmdStan records and all six historical report values/typed hashes match;
scalar MFRM, GMFRM and MGMFRM manifests/identities/contracts and the scalar
request-cache key are identical to the pre-change baseline.

The local ignored [receipt](../../results/workflows/20260915-fixed-q-spec-01/receipt.json)
retains exact source snapshots/diff, commands, outputs and deadlines. An initial
601-assertion implementation probe passed. Two subsequent runs stopped on eight
test-comparator errors each because `==` propagated `missing` in Q-validation
rows; `isequal` corrected the assertion without relaxing any validation gate.
The final checks above use the frozen final source. Each native command kept
its 600-second deadline, and the timer self-test passed 21 cases. No MCMC, Stan
compilation, figure rendering or dependency changes were performed. Existing
sample files and the previous 248 figure artifacts remain unchanged. Public
README/help pages are unchanged; the `mfrm_spec` docstring explains the new
inspection-only branch. The full sampling suite was not rerun.

## Canonical fixed-coefficient sampling record contract, 2026-09-15

The canonical private sample uses `bayesianmgmfrm.fixed_q_mfrm_samples.v2`
with the same ordered fields as v1: `schema`, `spec`, `prior`, `target_identity`,
`run`, `content_hash`. Version 2 requires a canonical multidimensional
`family = :mfrm` spec; v1 requires its legacy `family = :mgmfrm` storage spec.
Reject mismatched schema/family pairs even after rehashing. The prior record
and run validation remain unchanged, including optional warmup telemetry.
Target identity covers the canonical design and prior; content hash covers
the source sample record. No legacy conversion or additional mutable design
copy is stored in the record.

At numerical entry, validate the supplied target's design and rebuild its
private numerical views from that design and prior. The private
`_mfrm_fixed_q_fit(spec; ...)` returns `MultidimensionalMFRMFit`, defaulting to
Julia NUTS and accepting CmdStan. Reuse the private sample writer/loader for
same-environment replay and rebuild result summaries/diagnostics from the
checked record. Public fitting, fit-cache envelopes, artifact/public report
adapters and aliases remain outside this slice.

## Canonical fixed-coefficient fitting and replay, 2026-09-15

The preceding record contract is implemented. Both private sampling routes now
accept the canonical MFRM target and return the dedicated result through
`_mfrm_fixed_q_fit`. Julia NUTS remains the default. Numerical entry validates
the authoritative design and rebuilds mutable derived target views. Existing
prior/run validation, chain identity, diagnostic criteria and optional warmup
coverage remain in force. Saving the result reuses the private atomic writer;
loading checks schema/family, content hash and canonical target/prior identity
before rebuilding summaries and diagnostics. No new sampling engine, serializer
or dependency is introduced.

Julia 1.10.8 passes **2,754 assertions** (76.18 seconds): 642 specification,
1,532 synthetic result and 580 real Julia sampling/replay checks. Julia 1.12.5
passes **2,613 assertions** (145.84 seconds) for specification, synthetic results
and both historical saved backends, including all six old report values/typed
hashes. Its separate Julia/CmdStan integration passes **848 assertions** (102.12
seconds). Actual runs use two/three-dimensional Julia targets and a matched
two-dimensional CmdStan 2.39.0 target; each retains 12 draws per chain in two
chains after 10 warmup iterations. The two-dimensional example includes a
cross-loaded item and the three-dimensional example has between-item Q.
Every retained log density is recomputed, including agreement with Stan's
`lp__`; both backends preserve the same two-dimensional target identity and
prior. These short chains establish operability only, not convergence,
recovery, coverage or statistical acceptance.

Checks cover warmup recording on/off, invalid backend/init/draw controls before
numerical startup, reconstruction after stale derived views, detached caller
inputs, schema/family and identity mismatches after rehashing, and corrupted
overwrite rejection without changing existing file bytes. The existing private
report assembler accepts each v2 saved result. At this milestone, public/experimental
fitting, manual fit-cache/artifact and dedicated public report/plot dispatch were
unavailable; the manual cache/artifact follow-up is recorded below. README/help
pages were unchanged in that slice.

Fresh-process replay adds **17 assertions on Julia 1.10.8** (10.72 seconds) and
**25 on Julia 1.12.5** (16.66 seconds), reproducing exported metadata, both
posterior summaries and diagnostics exactly without sampling or CairoMakie.
The first replay probe had eight comparison failures because it compared
string-keyed exported dictionaries directly with symbol-keyed JSON3 objects.
Normalizing the JSON representation corrected the probe; no production code,
numerical tolerance or expected value changed.

The shared sampling entry also passes the unchanged legacy fixed-Q suite on
Julia 1.10.8: **1,967 assertions** (58.57 seconds), including two/three-dimensional
Julia sampling, v1 persistence, predictive/report reconstruction and synthetic
CmdStan parser checks. This explicitly exercises the old specification through
the newly validated numerical entry; no additional native CmdStan run is needed.

The local ignored [receipt](../../results/workflows/20260915-canonical-fixed-q-fit-01/receipt.json)
retains commands, source snapshots/diff, deadlines, new sample files, CmdStan
build artifacts and failed attempts. The first CmdStan attempt completed the
580 Julia checks but could not write a precompiled header inside its installed
tree. Repeating the unchanged test with `PRECOMPILED_HEADERS=false` and a fresh
compile directory passed within the existing filesystem permissions. Each
native command kept its 600-second deadline, and the timer self-test passed
21 cases. Existing private samples, previous receipts and 248 figure artifacts
remain unchanged. No full-suite run or new figure rendering was performed.

## Manual fixed-coefficient cache contract, 2026-09-15

Use `bayesianmgmfrm.fit_cache.v2` for canonical `MultidimensionalMFRMFit`
results only. Keep these ordered fields: `schema`, `object`, `model`,
`created_at`, `serialization`, `cache_key`, `target_identity`,
`source_sample_schema`, `source_sample_content_hash`, `artifact_content_hash`,
`archive_manifest`, `fit`, `artifact`. The fit's v2 sample is the only stored
model/draw authority. No second sample field or automatic import of legacy
private v1 samples is added. Manual labels may use `cache_key`; this does not
enable automatic request caching.

The full reproducibility artifact identifies the canonical design, actual
prior, unit-logit measure, source/target identity, backend/controls/RNG, stored
diagnostic gates, both coordinate summaries and optional draws/log densities/
sampler telemetry/environment. Reuse existing archive hashes, environment
metadata and atomic publication. Before saving or accepting a cache, rebuild
the model-dependent artifact from the checked sample and verify its agreement,
including archive summaries. Environment and creation time describe the saved
record and must not be regenerated during replay. V2 integrity checks cannot
be disabled with `verify_hash = false`; existing v1 inspection behavior stays
unchanged. Full artifacts and manual replay precede public projection/report
adapters and experimental fitting exposure.

### Implementation and validation

The contract above is implemented through explicit methods for the dedicated
result. `fit_artifact` and `fit_archive_manifest` default to the saved diagnostic
settings; full artifacts include actual prior/measure, source/target identity,
both coordinate summaries, diagnostics and optional draws/telemetry/environment.
Manual saving snapshots the fit, checks a supplied artifact against that sample,
and reuses the existing writer. Loading checks the model discriminator, sample,
artifact and both archive manifests before returning the result. Legacy private
sample import, automatic request caching, public fitting and public report/plot
dispatch remain unavailable. The cache-key mismatch error no longer suggests
automatic refresh, which is unavailable for this model.

Final cache-path checks pass **175 assertions on Julia 1.10.8** (136.81 seconds)
and **246 on Julia 1.12.5** (573.08 seconds). They reuse the preceding slice's
two/three-dimensional Julia samples and two-dimensional CmdStan 2.39.0 samples,
without MCMC, compilation of Stan models or CairoMakie. Lean/full artifacts,
recorded and unrecorded warmup, environment retention, nondefault stored
diagnostic settings, manual keys, mismatched/rehashed artifact rejection and
existing-file preservation are covered. All three existing v1 fit families
load and resave with unchanged artifacts; their `verify_hash = false` behavior
is retained. Original sample and v1 cache files remain byte-identical.

Julia 1.12.5 additionally passes **2,511 assertions** (318.28 seconds) for
specification boundaries, synthetic binary/four-category result/cache cases
on both backend shapes and SHA-256 compatibility. Final fresh-process replay
passes **493 assertions on Julia 1.10.8** (84.04 seconds) and **716 on Julia
1.12.5** (233.44 seconds), including the final archive convenience method and
stored-threshold regression check. File and typed artifact hashes agree;
metadata, summaries, diagnostics and artifact exports reproduce after reopening.
These are persistence/operability checks, not statistical acceptance or a
performance benchmark. The 573-second combined saved-result check is close to
the 600-second limit; single-operation latency and larger-result performance
remain unmeasured.

An initial 1,796-assertion Julia 1.10 synthetic probe passed. Both first
saved-result attempts then stopped on an environment-shape mismatch: the new
validator/probe expected a NamedTuple, while `evidence_metadata` returns a
dictionary. Matching that existing representation corrected the save path.
The v2 metadata checker also uses the existing cache validator's inference
boundary rather than specializing on each nested record layout. One initial
fresh-process JSON probe had two comparison failures because JSON3 reads an
unsigned options signature above `typemax(Int64)` as Float64. The corrected
probe compares both exports through the same JSON reader while keeping exact
file and typed artifact hash checks. No model, numerical tolerance, stored draw
or acceptance threshold was changed.

The local ignored [receipt](../../results/workflows/20260915-fixed-q-cache-01/receipt.json)
retains each source stage, commands/deadlines, successful and failed outputs,
valid caches and intentional malformed-record fixtures. Every native command
kept its 600-second limit; the timer self-test passed 21 cases. Source/tests were
frozen during each run. The only post-validation source edit removes the
obsolete refresh suggestion from an error string. Package dependencies and
README/manual pages are unchanged; artifact/cache docstrings describe v2
behavior without presenting a fitting workflow that is not yet available.
No full-suite run, new posterior sampling or figure rendering was performed.

## Canonical fixed-coefficient saved-result reports, 2026-09-15

Question: can an analyst reopen a canonical multidimensional MFRM fit and obtain
its numerical report and reader-facing exports without reconstructing MCMC draws?
`fit_report(::MultidimensionalMFRMFit)` now reuses the private report assembler
and adds the validated rating-design audit and full reproducibility artifact.
It supports the shared full/public report exports and explicit public artifact
projection. Central `posterior_lower`/`posterior_upper` bounds translate to the
existing private interval; noncentral bounds and changed diagnostic settings
are rejected. Report completeness describes captured section errors, independently
of unsupported analyses and MCMC warnings.

Public output records experimental saved-result support and unavailable fitting,
while retaining actual prior scales, unit logits, named dimensions, fixed and
reconstructed coordinates, diagnostic settings and source/target identity.
The public report uses the existing JSON-normalized hash; the public artifact
uses the artifact hash and records the full source artifact's hash. Full artifact
payloads keep their original schema and `:private_reference` status, so existing
v2 cache validation and historical records retain their meanings. The broad
fit union, numerical kernels, samplers, cache structures and plot dispatch are
unchanged.

The reusable [saved-report check](../../test/fixtures/fixed_q_report.jl) is also
called by the existing [synthetic result check](../../test/mfrm_fixed_q_result.jl).
It checks independent posterior quantiles, predictive draw order and local RNG,
fixed/derived meanings, stored diagnostic settings, actual priors, rating-design
rows, full/public hashes, cache/report-bundle replay and invalid-input/error
policies. It accepts existing fits from either backend without sampling or
loading CairoMakie.

Direct public-API smokes on Julia 1.12.5 passed for saved Julia and CmdStan
results (161.56 and 164.11 seconds): load an existing cache, build the full
report and public report/artifact, then save and reopen the public bundle.
These include first-use compilation; the Julia-result probe also enabled
compiler tracing. They are operability checks, not latency benchmarks.
The synthetic result/cache/report matrix passed 2,540 assertions on Julia
1.10.8 (464.70 seconds), covering both backend shapes, binary/multicategory
responses and legacy rejection. Saved two/three-dimensional Julia fits passed
474 assertions on 1.10.8 (421.89 seconds; assertion-module optimization was
disabled in this probe, with numerical-library defaults retained). These
checks preceded the same-output Markdown-loop correction below; the final
Markdown regression passed 75 assertions on each runtime (23.21 and 25.32
seconds), including all three notes under one heading.
On the final implementation, every saved-report assertion was also replayed
as sequential top-level calls against the saved CmdStan result on Julia 1.12.5;
all passed in 301.28 seconds, including full/public bundles, input rejection,
local RNG, cache replay and modified stored diagnostic settings. This executes
the same fixture body without a single large assertion function. The combined
Julia 1.12 drivers still reached the 600-second budget; do not report a complete
1.12 matrix or full-suite pass. Their compilation cost remains a bounded
engineering follow-up, distinct from the passing individual API paths.
The surrounding hash/column/specification/metadata checks passed 1,181
assertions; source language checks passed for 19 files. Fresh Documenter output
passed the 14-page rendered-language check (four existing omitted-maintenance
docstring warnings remain). The timer self-test passed 21 cases and 18 existing
cache/sample/receipt hashes were unchanged.

Initial test-helper comparisons confused the typed artifact hash with the
public report's JSON-normalized hash, and used `==` on rows containing
`missing`; the corrected checks use the appropriate hash and `isequal`.
Several aggregated attempts reached their 600-second limits. Read-only stack
sampling showed LLVM compilation dominating a large assertion driver;
inference-boundary and driver-compiler trials were insufficient. Replay
comparisons now check exact exported values, avoiding deeply specialized
in-memory report comparisons, and full/public payloads are selected without
packing both large reports into one tuple. Compiler tracing also identified a shared
Markdown note generator capturing the entire embedded artifact. A small loop
now collects only the three optional note values, preserving their order and
heading behavior without that capture. The 75-assertion Markdown check on both runtimes and the sequential
full-artifact report-bundle replay cover this path. This local correction
does not establish that the combined-driver compilation issue is resolved. Normal compiler defaults
are restored; numerical tolerances are unchanged.
An exploratory process-wide `--compile=min` replay changed several rebuilt
means/standard deviations at floating-point rounding precision and was rejected
by the existing exact cache validator. Standard-setting replay remains the
compatibility check; no stored result, hash check or numerical tolerance was
changed. Portability across compiler/optimization settings needs a separate
derived-summary validation policy before it can be advertised. No new MCMC,
Stan compilation, figure rendering, full-suite run or statistical acceptance
was performed.

## Canonical saved-result figures, 2026-09-15

`MultidimensionalMFRMFit` now supports the qualified `plot_posterior`,
`plot_diagnostics` and `plot_predictive` entries and fitted-object
`save_fit_report_bundle`, including full/public figure bundles. The three
plot methods reuse the private numerical/rendering path. Private and canonical
bundles share figure preparation and the existing staged writer; no renderer,
numerical kernel, result container, dependency or model-comparison dispatch
was added. The canonical guard rejects legacy sample-family records at these
entries. Fitting remains unavailable.

Named-dimension posterior/trace plots use model coordinates in unit logits.
Figures identify experimental status and the backend, retain whole-fit MCMC
warnings, and distinguish fixed coefficients from sampled/derived coordinates.
Posterior intervals match the report's central bounds; predictive figures
consume its exact replicated category rows without another simulation.
Exports preserve draw order/repeats, chains/iterations, the actual prior and
stored diagnostic settings in the report, plus source/target identity and the
exported report hash in figure inputs. Existing full artifacts and v1/v2 caches
are unchanged. Report-only calls accept the same local integer seed as the
saved-result report and require no CairoMakie; readers need no renderer either.
Figure selection/rendering failures preserve destination files. This does not
add a transaction guarantee for arbitrary failures during final file copying.

Verification uses the existing short, non-converged samples solely for output
integration. The Julia 1.10.8 synthetic result/cache/report matrix passed 2,572
assertions (471.15 seconds), including direct report-only bundle calls, legacy
rejection and renderer-absence checks. On Julia 1.12.5, saved Julia full and
CmdStan public figure bundles each passed 125 assertions (311.35 and 270.39
seconds), using the fixture body as sequential top-level calls under normal
compiler settings. These checks include standalone named-dimension plotting,
exact report/figure equality, local RNG behavior, hashes, invalid options,
destination byte preservation and predictive replay. A fresh process without
CairoMakie reopened all four exported bundles (17 assertions, including the
renderer-absence assertion) and passed the 25 existing report-only/figure-request
checks (37.61 seconds combined). Markdown column checks passed 75 assertions.
Fresh Documenter output built in 22.96 seconds and passed the source-language
19-file and rendered-language 14-page checks; the same four pre-existing
omitted-maintenance-docstring warnings remain. The standalone Julia 1.10.8 namespace
check also passed 182 assertions (44.69 seconds), including the existing
GMFRM/MGMFRM actual-fit and automatic-cache smoke paths.

Selected Julia posterior/diagnostic/predictive and CmdStan diagnostic PDFs were
rendered with Poppler and inspected. Julia posterior and CmdStan predictive
SVGs were inspected through local HTML previews; labels, intervals, fixed
markers and warning text fit. Quick Look's standalone SVG thumbnail cropped
the right edge; embedding the unchanged SVG in HTML rendered the complete
figure. This viewer check required no change to plot geometry or dependencies.
The existing private saved-sample bundle callers also passed 226 assertions
on both backends (130.98 seconds), covering the shared writer extraction.
The [local receipt](../../results/workflows/20260915-canonical-fixed-q-figures-01/receipt.json)
retains the bundles, render previews, scripts, source/output hashes and logs;
all 18 previously recorded cache/sample/receipt hashes remain unchanged.
No sampling, Stan compilation, statistical acceptance or full-suite claim was
made. The previously recorded large-driver Julia 1.12 compilation follow-up
and unfamiliar-reader acceptance remain open.

## Experimental fixed-coefficient fitting, 2026-09-15

`Experimental.fit` now accepts canonical `family = :mfrm, dimensions >= 2`
specifications and calls the existing fixed-Q sampler adapter. Julia/AdvancedHMC
and CmdStan return the same dedicated result type, also available as
`Experimental.MultidimensionalMFRMFit`; its defining root type and serialized
field layout stay unchanged. The namespace, model-family contract, ladder,
release-scope rows, README and installed help describe the restricted model.
The stored specification's compatibility status stays unchanged because it
participates in design and target identity; current availability comes from
those explicit contracts. Generalized legacy entry points retain their scope.

The generic [example](../../examples/multidimensional_mfrm.jl) runs either
backend and reaches diagnostics, manual save/reload and a public report, with
optional named-dimension posterior/trace and predictive figures. It uses the
existing result/report/figure machinery without another sampler, result class
or dependency. Active Q coefficients and rater consistency stay one, logits
have unit scale, person/item locations are prior-anchored and latent correlation
is identity. `MFRMPrior` records independent normal priors on the declared free
coordinates; warmup statistics are recorded by default. Unsupported options,
automatic request caching and stable fitting remain guarded.

New full artifacts use `mfrm_fixed_q_fit_artifact.v2` to describe experimental
fitting availability. The outer manual cache remains v2. Its reader accepts
both full-artifact versions and reconstructs v1 with its frozen metadata and
model-equation availability fields, retaining exact content and target checks.
Old files are never rewritten. Legacy private sample-family records retain
private metadata and remain rejected by canonical report/plot/artifact entries.

The [local receipt](../../results/workflows/20260915-experimental-fixed-q-01/receipt.json)
records commands, hashes and outputs. Julia 1.10.8 synthetic result/cache/report
checks passed 2,608 assertions (492.94 seconds), including both artifact versions,
malformed records and legacy sample-family rejection. The exact generic example
ran on Julia 1.12.5 with Julia/AdvancedHMC and CmdStan, including figures, cache
reload and bundle verification (144.80 and 150.42 seconds). Each uses two chains
with 50 warmup and 50 retained draws. Both report MCMC warnings, so these runs
establish operability only. Their elapsed times include compilation/rendering
and concurrent checks; they are not benchmark or backend-speed comparisons.

The final Julia 1.12.5 specification/model-family/namespace, public-language,
release-catalog and installed-help checks passed 1,085 assertions (121.29 seconds).
Julia 1.10.8 actual 2D/3D sampling/replay checks passed 590 assertions (77.30
seconds), including the new 2D public entry and existing stale-target rebuild
case. A renderer-free Julia 1.12.5 process reopened both new figure bundles and
caches (35 assertions, 77.14 seconds), checked all retained Julia/Stan densities,
identical target identities, actual priors, warmup coverage and saved diagnostic
settings. The five pre-existing canonical caches also reopened on their own
Julia minor versions (25 assertions); all 18 previously recorded input hashes
are unchanged. Fresh Documenter output built in 20.93 seconds; the 20-file
source and 14-page rendered language checks pass. The four existing omitted
maintenance-docstring warnings remain. The standalone Julia 1.10.8 namespace
check also passed 182 assertions (44.69 seconds), including the existing
GMFRM/MGMFRM actual-fit and automatic-cache smoke paths.

Selected Julia posterior and CmdStan diagnostic PDFs were rendered and inspected:
named dimensions, unit-logit axes, 90% central intervals, chain labels and
whole-fit warnings remain legible. No plotting geometry or numerical summary
semantics changed. Full-suite, independent-reader, recovery/coverage and broad
model-acceptance claims remain outside this integration check.

## Correlated fixed-coefficient density, 2026-09-15

The private `_MFRMFixedQCorrelated2DLogDensity` adds one Fisher coordinate to
the canonical unit-logit MFRM. It reuses the existing fixed-coefficient
likelihood and the numerically stabilized bivariate-normal routines from the
generalized correlation candidate, without inheriting that candidate's
raw-scale priors, estimated loadings or 1.7 model multiplier. There is no new
public fitting, saved-result or plotting dispatch.

The bounded design is exactly two named dimensions, fixed between-item Q,
at least two pure items per dimension, and observations on both dimensions
for every person. The constructor reuses the existing conservative Q/coverage
checks and takes a detached validated specification. These checks restrict the
implementation domain; they do not establish practical identification or
correlation recovery. The independent model still admits its existing Q scope.

The model/coordinate contract is:

- The likelihood keeps `a[i,d] = Q[i,d]`, unit rater consistency and unit logits.
  Person/item locations remain prior-anchored; rater severities sum to zero.
  Item steps retain the first-zero/remaining-sum-to-zero convention, including
  zero free steps for two categories.
- Each ability vector is directly parameterized as
  `theta[p] ~ Normal_2(0, person_sd^2 * R(rho))`, where
  `R(rho) = [1 rho; rho 1]`. The common marginal SD is the fixed positive
  `MFRMPrior.person_sd`; it is not estimated. Population correlation is shared
  across persons and differs from dependence among posterior draws.
- All other priors remain the canonical independent normal densities on the
  existing free coordinates, with the actual `MFRMPrior` scales. In particular,
  adding ability correlation does not change the last-reconstructed rater prior
  into an exchangeable prior.
- `rho = tanh(z)` and the prior is normalized LKJ(eta) on the one free
  correlation coordinate `d rho`. The private implementation inherits the
  existing integer-eta range 1–10,000, with default 2. This is an implementation
  restriction, not the mathematical domain of the LKJ family.

The [Stan 2.39 LKJ reference](https://mc-stan.org/docs/functions-reference/correlation_matrix_distributions.html)
gives the determinant power `eta - 1`; the
[transform reference](https://mc-stan.org/docs/reference-manual/transforms.html)
describes the tanh correlation transform and change of variables. For this
2D model, direct integration gives

```math
p(\rho)=\frac{(1-\rho^2)^{\eta-1}}{B(1/2,\eta)},\qquad -1<\rho<1,
```

and therefore, in the implemented `d beta d z` measure,

```math
\log p(z)=-\log B(1/2,\eta)+\eta\log(1-\tanh^2 z).
```

The final power is **eta**, including the manual log-Jacobian
`log(1-rho^2)` exactly once. There is no theta transformation Jacobian: the
bivariate-normal density includes its covariance determinant and is evaluated
directly at theta. The likelihood's internal division by 1.7 only evaluates
the existing response formula in unit logits; it changes neither the declared
prior measure nor the model's scale. This is a centered ability parameterization;
its sampler geometry has not yet been assessed.

At `z = 0`, the beta-coordinate density equals the independent target minus
`log B(1/2,eta)` and has the same beta gradient. The z gradient need not vanish:
it is `sum_p theta[p,1]*theta[p,2]/person_sd^2`. A rho-zero slice is thus a
baseline check, not a claim that the joint posterior is stationary there.

The target identity hashes the independent target identity together with the
new model tag, centered coordinates, covariance/scale, eta and measure/Jacobian
contract. The attached base `FacetSpec` still describes the independent model;
it must not be serialized as if it described a fitted free correlation. The
existing independent sample/cache schemas cannot store this new target. Public
`Experimental.fit` rejects the density object, and the generalized correlation
entry still rejects canonical MFRM specifications.

The private [Stan source](../../src/stan/mfrm_correlated_2d.stan) uses the same
likelihood and an independently written sum/difference form of the bivariate
normal quadratic. It computes log(1+rho) and log(1-rho) without subtracting a
rounded endpoint. Julia reuses the existing stable conditional-normal form.
Both parameter blocks are unconstrained; CmdStan's automatic-Jacobian selector
must therefore leave the manually transformed target unchanged. The file has
no generated quantities or sampling/result integration at this stage.

The two-category comparison exposed an empty-segment error in the shared Stan
step reconstruction. The shared function now directly sets steps to zero when
there are no free steps, before indexing a segment. The independent fixed-Q
Stan model's category lower bound is also corrected from three to two, matching
its Julia specification. Its multi-category response equation and priors are
unchanged. Generalized Stan model admission limits are unchanged; their shared
multi-category path receives a separate regression check.

Focused verification passed:

- Julia 1.10.8: 275 new density/contract assertions, 649 canonical fixed-Q
  specification assertions and 638 existing generalized-correlation assertions.
- Julia 1.12.5 / CmdStan 2.39.0: the 275 new assertions plus 219 backend
  assertions. The comparison covers two/four categories, eta 1/2/5, both
  automatic-Jacobian modes, five moderate-correlation points and eight
  zero/aligned-ability tail points per category/eta combination. At the checked
  points, the maximum absolute difference is `5.45697e-12` for log density
  and `5.32907e-15` for gradient coordinates.
- The existing normalized-density suite passed all 1,206 assertions on
  Julia 1.12.5 with actual CmdStan checks, including the shared generalized
  likelihood and independent fixed-Q paths.
- Five historical caches reopened in their original Julia major/minor series
  (25 assertions), and both recent independent-model examples reopened with
  their retained densities and report identities intact (35 assertions).
  The public namespace boundary passed 165 assertions; the public source
  language gate passed. All 18 historical input hashes, 84 previous receipt
  artifacts and the previous receipt itself remain unchanged.

The tail checks at z = +/-20 and +/-1,000 exercise representable zero/aligned
ability vectors. They do not guarantee finite floating-point densities or
gradients for arbitrary off-ridge vectors near a singular covariance. The
two-category independent model is checked at zero/nonzero coordinates under
both Jacobian modes. This work performs no new binary-response sampling.
An attempted Julia 1.12 read of a Julia 1.10 cache was rejected because
recomputed diagnostic/summary values differed in their final floating-point
digits. The existing same-major/minor serialization recommendation remains;
no integrity check was relaxed to admit that cross-minor read.

Verification commands, failed attempts and retained artifacts are recorded in the
[local receipt](../../results/workflows/20260915-correlated-fixed-q-density-01/receipt.json).
No MCMC, correlation recovery, covariance-model promotion, independent review
or full-suite acceptance is implied by these density/gradient checks.

## Private correlated sampling and reconstruction, 2026-09-17

The correlated fixed-coefficient target now connects to the existing
AdvancedHMC and CmdStan NUTS runners through `_mfrm_correlated_2d_sample`.
The model equation, prior, Jacobian and target identity are unchanged from the
density contract above. This is private operability work; it does not select a
supported correlation-estimation domain or provide recovery/coverage evidence.

CmdStan keeps separate `beta` and `zrho` parameter blocks. Its initial JSON
explicitly splits the Julia coordinate vector, and its CSV reader selects
columns by name before restoring the same vector order. The shared adapters
retain the old all-beta defaults for existing models. Generated quantities
provide observation-level log likelihoods. Every retained Stan draw must match
Julia's pointwise likelihood and normalized joint density before it is returned.

The new `bayesianmgmfrm.correlated_fixed_q_mfrm_samples.v1` record contains
`base_spec`, the actual MFRM prior scales and full correlation contract, target
identity, sampler record and content hash. The field is deliberately named
`base_spec`: it still represents the independent likelihood design, while the
correlation contract defines the joint ability prior. Neither that base alone
nor an independent-model sample schema can reconstruct the correlated target.
The v1 density-contract availability flags remain frozen and false for public
fitting/fit caches; the private sample record is a separate capability.

On replay, the loader rebuilds the target and verifies the prior/measure,
identity, content hash, initial and retained densities, chain/iteration layout,
sampler summaries and warmup telemetry. Names, intervals and diagnostic tables
are rebuilt from those verified samples. Saving verifies the record before
using the existing atomic persistence routine. An invalid overwrite cannot
replace a previously valid file. Serialization remains for trusted files in
the same Julia major/minor environment; this work adds no portability claim.

The reconstructed result distinguishes sampled unit-logit locations/steps,
Fisher z, dimensionless fixed coefficients and transformed population rho.
Rho is marked derived and non-fixed, with summaries and diagnostics computed
from `tanh(z)` draws; its mean is not obtained by transforming the mean z.
The existing fixed/derived rater and step meanings are retained. Warmup rows
remain separate from posterior diagnostics, with recorded/not-recorded coverage
explicit. No correlated public fit, fit-cache, report or figure entry is added.

The focused checks pass on Julia 1.10.8 (542 assertions) and Julia 1.12.5
with CmdStan 2.39.0 (964 assertions, including the density/gradient grid).
The final sampling cases use two/four categories, eta 3/5 respectively,
three persons, four pure-Q items and two raters. Each has two chains with
10 warmup and 12 retained draws per chain, seed 20260917, initial z = 0.25,
jitter 0.02, initial step size 0.03 and maximum tree depth 4. Two-category
cases omit warmup recording; four-category cases retain it. All six final
runtime/backend cases carry sampler warnings: retained maximum-depth hits
range from 4 to 19 out of 24 draws. These budgets exercise the plumbing and
do not establish convergence, posterior equivalence or correlation accuracy.

Fresh processes reopen the two Julia 1.10 records (18 assertions) and four
Julia 1.12 records (38 assertions), reproducing summaries, diagnostics,
prior/target identities and retained densities. The independent fixed-Q
Julia/CmdStan fitting checks pass 863 assertions; five historical caches
reopen in their original Julia series (25 assertions). The shared fitting
failure boundaries and experimental namespace pass 1,545 assertions, and
the public source-language gate passes. The previous density receipt and its
96 artifacts, 18 historical inputs and 84 preceding workflow artifacts retain
their recorded hashes. No full-suite or CI acceptance is claimed.

The retained initial failures are verification issues rather than waived
criteria: the sample test initially used reference equality for detached
`FacetSpec` objects, and the fresh-process driver initially compared JSON3
symbol-key objects directly with string-key dictionaries. The final checks
compare validated design identities and full saved/derived contents, using
the existing typed JSON reader. The boundary run with compiled modules and
package images set to `existing` also repeated the previously recorded
DynamicPPL/Turing generated-function error. The unchanged boundary file passes
with both flags set to `yes`; no dependency or Turing source patch was needed.

Verification commands, short-run controls, actual warnings and retained
artifacts belong to the
[local receipt](../../results/workflows/20260917-correlated-fixed-q-samples-01/receipt.json).
Numerical/backend consistency and intact replay do not establish that these
short chains estimate correlation adequately.

## Private correlated results and figures (2026-09-17)

The verified correlated sample record now has a private `_CorrelatedMFRMFit`
adapter. Existing summary, diagnostic, report and CairoMakie rendering primitives
supply named ability dimensions, draw-transformed population rho, fixed
coefficients and reconstructed rater/step coordinates. The adapter owns a
detached record and revalidates its identity, content and retained densities
before deriving a result. It does not reinterpret an independent `FacetSpec`
or become a public fit cache.

Location/step summaries use unit logits, coefficient summaries are dimensionless,
and rho has its own correlation scale and bounded plot axis. Dedicated rho
summary/diagnostic tables remain visible in the default truncated Markdown
previews. Raw z and transformed rho retain separate diagnostics. Reports distinguish the joint normal ability
prior from independent normal priors on other free coordinates and the induced
priors on sum-constrained coordinates. LKJ eta appears as a fixed **shape**, not
as a standard deviation. The rho-to-z density correction is stated exactly once;
the ability covariance determinant is a normal-density term, not another
transformation Jacobian. The existing conditional rating-prediction path uses
the retained abilities and preserves ordered/repeated draw selections; it does
not predict new persons, items or raters.

Numerical report bundles need no plotting dependency. Optional posterior,
trace/rank and predictive figures reuse the staged PDF/SVG/JSON writer and its
source/report hashes. The model/prior identity and whole-fit diagnostic warnings
remain in saved reports and figures. A complete report means no captured section
errors, not successful convergence or statistical acceptance; unsupported
analyses remain explicitly marked.

The final synthetic result checks pass 356 assertions on each of Julia 1.10.8
and 1.12.5. Saved-input replay passes 178 assertions for the two Julia 1.10
cases and 356 for the four Julia 1.12 cases, including CmdStan inputs. The two
four-category figure bundles pass 232 assertions, covering numerical payloads,
PDF/SVG/JSON hashes, repeated draw selections, failed-overwrite preservation
and tamper rejection. Fresh processes pass 28/71 result/cache assertions;
the experimental namespace and public-language policy pass 165/178 assertions.
The existing independent synthetic result/cache/report matrix passes 2,608
assertions, five historical caches reopen, and 354 historical input/artifact
hashes are unchanged. These are focused local checks, not a full-suite or CI pass.

Implementer inspection of selected PDF and SVG figures caught a clipped
posterior title; the shared renderer now wraps the title. A saved independent
fit also renders correctly with that change. SVG review uses an HTML wrapper
because Quick Look's standalone SVG thumbnail clips the viewport; the source
SVG and PDF bounds are intact. The receipt retains the initial failures:
missing no-figure routing (corrected in code), a stale-process replay after
tests changed, and test-driver mistakes in missing-value equality, JSON-reader
arguments, exported diagnostic fields and an extra namespace lookup. Final
checks use the corrected drivers; no numerical criterion was relaxed.

Verification commands, outputs and visual-review images are recorded in the
[local receipt](../../results/workflows/20260917-correlated-fixed-q-results-01/receipt.json).
This slice runs no new MCMC and adds no statistical evaluation replications.
The saved short-run inputs still carry their original sampler warnings.
Public correlated fitting, a public saved-fit contract, recovery/coverage,
posterior equivalence and an unfamiliar-reader review remain open.

## Experimental correlated MFRM API (2026-09-17)

`Experimental.correlated(spec; lkj_eta=2)` copies a canonical two-dimensional
MFRM design and identifies free population correlation explicitly. The base
`FacetSpec` retains its independent meaning. Between-item Q, two pure items per
dimension and complete person/dimension observation coverage remain required.
`Experimental.fit` uses the existing Julia/AdvancedHMC and CmdStan runners;
there is no second sampler or likelihood implementation. Unsupported designs,
initial values and controls are rejected before numerical execution.

The dedicated result type connects to the existing v2 fit-cache envelope with
model `mfrm_fixed_q_correlated_2d` and its own v1 artifact schema. Full artifact
semantics, retained densities, target identity and both archive hashes are checked
on load, including when optional hash verification is disabled. Failed overwrites
preserve the previous file. Existing independent artifact v1/v2 meanings stay
unchanged. Historical correlated target/sample v1 availability flags stay frozen
inside saved provenance; current metadata states current availability separately.

Correlated reports and report bundles default to `view=:public`; `view=:full`
retains reproducibility details. The default report includes rho, its transformed
intervals and diagnostics, named dimensions, design audit and prior/Jacobian
explanations. Sampler warnings and unsupported-analysis explanations remain.
Human display, live help and figure titles use model descriptions; language checks
reject private-result status labels. Full-provenance records retain their identities.
The existing runnable example adds `--correlated`, optionally with `--cmdstan`
and `--plots`. README, model scope and the experimental guide describe the same
bounded model.

Verification passed: 772 synthetic result/cache/public-display assertions on
each of Julia 1.10.8 and 1.12.5; 2,616 independent-model regression assertions;
86 historical replay/cache checks across the two versions; 165 namespace and
181 language-policy assertions; 355 runtime surfaces, 20 source files and 14
fresh HTML pages. Separate-process cache checks passed (12 on 1.10, 24 on 1.12).
Four bounded correlated runs (two backends, two category counts) completed;
the four-category cases exercised the new public entry and manual cache.
The first sandboxed CmdStan build failed before sampling, and was rerun in a
fresh directory with the required shared-header write permission; Julia runs
were not repeated. Two one-draw generalized fits belong to the existing runtime
language check. No statistical evaluation replication was added.

Report/figure integration passed 252 assertions. Implementer PDF/SVG inspection
confirmed visible titles, correlation axes, intervals and MCMC warnings on both
backends. The 779 retained historical artifact/input hashes are unchanged.
Initial help-fallback/test-path errors and verification-driver environment/path
errors are retained with the final passing runs. The full package suite and CI
were not run. Verification commands, outputs and visual-review images are in the
[local receipt](../../results/workflows/20260917-correlated-api-01/receipt.json).
The bounded short fits establish API/cache operability only, not convergence,
recovery, coverage or posterior equivalence. The unfamiliar-reader walkthrough
and independent scientific acceptance remain pending. No CI, merge, release or
application analysis is implied.

## Fixed-coefficient prior inspection (2026-09-17)

`Experimental.prior_predict` and `Experimental.prior_predictive_check` now accept
the canonical independent MFRM specification and `Experimental.correlated(spec)`.
They use the fitting prior's free unit-logit coordinates, reconstruct the same
rater/step constraints, and feed the existing rating kernel. No new likelihood,
sampler, dependency or posterior run is introduced. Current capability flags
are updated; frozen target/sample contracts remain unchanged.

The two-dimensional correlation draw is `rho = 2u - 1`, with
`u ~ Beta(eta, eta)`. This follows directly from the
[LKJ determinant density](https://mc-stan.org/docs/functions-reference/correlation_matrix_distributions.html#lkj-correlation-distribution)
at dimension two: `det(R) = 1-rho^2`. The installed Distributions implementation
uses the same transform; the already required Turing module reexports its Beta
distribution. Given rho, the ability pair is generated by its bivariate-normal
Cholesky transform with fixed marginal `person_sd`. Storing `atanh(rho)` changes
coordinates, not simulation weights; the existing fitted density includes its
Jacobian exactly once. Density comparisons against independently evaluated
Beta and multivariate-normal densities verify the measure, including eta 1,
2, 5 and the supported upper bound 10,000.

`check.parameter_summary` supplies model-scale means, medians and central 95%
prior intervals; `plot_prior(check)` selects abilities, correlation and other
coordinates without reshaping draws. `plot_predictive(check)` reuses prior
category-proportion summaries and also supports existing stable/generalized
prior checks. CairoMakie rendering is shared with posterior figures through an
explicit prior caption, preserving posterior defaults. Figures distinguish prior
simulation from retained MCMC draws. Current experimental support remains in
metadata/captions; final API/status wording migration is specified in the main
roadmap rather than advertised as a completed scientific promotion.

Observed scores are only a comparison; replacing them leaves prior parameters
and replicated scores unchanged with the same RNG and rating design. The checks
condition on the supplied rating rows and facet levels. Neither new-facet
prediction nor recovery/coverage is claimed. The generic example now runs prior
inspection before fitting and accepts `--prior-only`, optionally with `--plots`
and `--correlated`. README, help and the manual describe this same scope.

Initial numerical verification passed 778 predictive/constraint/summary checks
and 90 joint-prior/moment/measure checks on both Julia 1.10.8 and 1.12.5, plus
275 existing density checks per version. Namespace (165) and language-policy
(181) assertions also passed on 1.12.5. The first test attempt mutated observed
scores inside a validated specification and correctly failed the stale-design
guard; the corrected test constructs a new data/specification object. No guard
or numerical tolerance was relaxed.

The final renderer run passed 770 predictive checks (the eight missing-renderer
rejections are inapplicable with CairoMakie loaded), 90 joint-prior checks,
275 density checks, 15 existing-family prior-figure checks and 24 historical
cache/render/help checks. It read independent and correlated Julia caches and
a correlated CmdStan cache, generated 11 prior figure sets (PDF/SVG/numerical
JSON), and rendered existing posterior figures with their original MCMC captions.
The documented correlated `--prior-only --plots` example also completed without
MCMC. On Julia 1.10, the existing-family checks passed 12 assertions without a
renderer and two historical caches passed four compatibility checks. The five
saved input files retain their original bytes.

Implementer visual inspection covered ability, rho, step and category figures
in PDF and representative ability/rho SVGs. Axis units, named dimensions, fixed
steps, intervals and prior captions were visible; old posterior captions still
show their MCMC warnings. Source language checks passed for 20 files and the
fresh final manual for 14 HTML pages. The manual built with its four existing
omitted research-docstring warnings. The full package suite, CI and an independent
reader walkthrough were not run. No new MCMC or statistical evaluation
replication was added.

Two verification-driver errors are retained alongside the passing results:
the renderer environment initially lacked direct access to test dependencies
(the existing root project was added to the load path, with no dependency
installation), and the first Julia 1.10 cache driver omitted its package import.
The corrected cache-only driver passed. Commands/drivers, logs, numerical inputs,
figures, preserved-cache hashes and visual-review images are listed in the
[local receipt](../../results/workflows/20260917-prior-predictive-01/receipt.json).

## Fixed-coefficient prior report integration (2026-09-17)

Saved independent and correlated MFRM fits now accept
`include_prior_predictive=true` in `fit_report` and `save_fit_report_bundle`.
The report reconstructs the accepted model and `MFRMPrior` from the checked
record, including the correlated model's saved LKJ shape. It calls the same
prior simulator used for pre-fit checks. The section is opt-in and reports
parameter intervals, named dimensions, fixed/derived roles, rho separately,
rating summaries, prior-implication diagnostics and the local RNG control.
`prior_predictive_ndraws=100` and `prior_interval=0.95` are explicit defaults;
`predictive_interval` controls the rating summaries. No posterior fit is run.

Prior and posterior prediction start separate local RNGs from the report's
`seed`. Prior draw budgets therefore cannot consume the posterior prediction
stream or change posterior summaries/diagnostics. Invalid prior simulations
follow the existing capture/throw/require-complete policies; omitted sections
are now `not_requested` rather than `unsupported` in canonical fixed-Q fit
reports. Historical saved reports retain their original meaning and bytes.

Optional `prior` and `prior_predictive` figure keys render the already computed
parameter and rating rows. Shared parameter selection and caption/rendering
helpers also serve the standalone plots, avoiding a second simulation or a
second interpretation of intervals. Five-figure fixed-Q bundles retain the v2
envelope with an extended checked kind inventory, file-path checks and hashes.
Old bundles remain readable. Stable/generalized bundles explicitly reject the
new prior figure keys; their existing standalone prior-predictive plots remain
available. No broader figure scope is implied.

The same staged export path protects an existing report and unrelated files
when a later figure selection fails. Current experimental support stays visible;
the final API/status migration remains the roadmap's model-specific release
condition. No default prior, density, sample/cache schema or target identity
has changed.

Historical-cache checks passed 325 assertions on Julia 1.10.8, alongside
1,075 existing posterior/diagnostic/predictive/Wright plotting-data checks.
The Julia 1.12.5 renderer run passed 541 assertions using independent Julia,
correlated Julia and correlated CmdStan saved fits. It produced 15 figure sets
(PDF/SVG/numerical JSON), reloaded public/full bundles, and checked exact prior
summary/figure agreement, failure-safe overwrite, unrelated-file preservation
and tamper detection. A pre-prior figure bundle remains readable. A report-only
manual example with 1,000 prior draws produced two additional prior figures;
the fitting example was not rerun. All five saved inputs retain their bytes.

The existing prior tests passed on Julia 1.12.5: 275 density, 778 predictive,
90 joint-prior and 12 existing-family assertions. Report-only compatibility
and the stable/generalized prior-figure scope guards passed 43 assertions.
Historical replay, rendering and these prior checks used normal compilation.

The initial synthetic run had 1,264 passes and eight test-comparison errors:
`==` on missing-valued rows returned `missing`, rather than a Boolean. The
fixture was corrected to `isequal`; no implementation or tolerance was changed
for this correction. A subsequent `--compile=min` attempt was interrupted after
12m24.5s with 460 partial passes because interpreter execution was slow; its
log and stack sample are retained. The normal-compilation rerun passed 1,272
correlated and 3,092 independent synthetic-result assertions, 165 namespace
assertions and 181 language-policy assertions. A late alternative `--optimize=0`
attempt was stopped once that normal run completed; it is not counted as
verification. Both stopped attempts are retained in the receipt.

Implementer PDF/SVG inspection confirmed correlation units, prior versus
posterior intervals/draw counts and visible captions; existing MCMC warnings
remain. The fresh manual built with its four existing omitted research-docstring
warnings. Public-language checks passed for 20 source files and 14 HTML pages.
No new MCMC or statistical evaluation replication was run; the full package
suite, CI and independent reader/scientific review remain outside this handoff.
Commands, logs, preserved input hashes and visual-review artifacts are listed
in the [local receipt](../../results/workflows/20260917-prior-report-01/receipt.json).

## Fixed-coefficient prior and identification review (2026-09-17)

The [equation/code review](fixed-coefficient-prior-identification.md) derives the
current free-coordinate prior's full rater/step covariance and distinguishes
rater relabelling, row order, chart transport and a change of prior. For R>2,
renaming IDs can move the reconstructed rater and change the prior while all
rating probabilities remain equal. Independent normal priors on the new free
chart do not preserve the original full-vector distribution. The zero-sum
constraint by itself does not imply exchangeability.

The same review traces the joint ability/item location shift, the fixed ability
marginal scales and the correlated model's one Fisher-z Jacobian. It separates
the existing normalized zero-sum block reference from the generalized model's
positive consistency/source-rater prior. Public documentation and newly
computed report explanations state the current limitation. Likelihoods,
priors, target/cache identities and saved draws are unchanged.

Sampler-free checks passed 428 assertions on each Julia 1.10.8 and 1.12.5;
the existing correlated density checks passed 275 assertions on 1.12.5.
Fresh CmdStan builds passed 208 density/gradient assertions on relabelled and
location-shifted cases (3/5 raters, 2/4 categories, both ability priors and both
CmdStan Jacobian settings). No sampling was run. The checks use exact basis-image covariances, transported Gaussian densities,
matched rater relabellings, row permutations, Q/dimension swaps and location
shift derivatives. They characterize the declared prior, not its scientific
appropriateness or statistical recovery. Historical fits and clarified public
report save/reload passed 28 checks on Julia 1.10 and 42 on Julia 1.12, retaining
all five saved input files. An existing portable report remains readable with
its original explanation. The final manual built with four existing omitted
research-docstring warnings; public policy tests passed 181 assertions, and
language checks passed for 20 source files and 14 HTML pages.

The documentation driver initially inherited a custom build-root setting into
a test of the default root (180 passes, one failure); scoping that environment
setting to the build resolved it without changing test expectations. Generated
HTML inspection caught the new fragment link's case/punctuation mismatch; a
Documenter title cross-reference now resolves to the actual heading. The full
suite, CI and independent reader/scientific review were not run. Commands,
logs, density inputs/outputs and retained hashes are in the
[local receipt](../../results/workflows/20260917-prior-identification-01/receipt.json).

## Fixed-coefficient exchangeable-rater reference (2026-09-17)

The private `_MFRMExchangeableRatersLogDensity` changes only the rater prior
of the independent or correlated fixed-coefficient target. It reuses the
normalized zero-sum correction and all existing likelihood/other-prior terms.
The required scale record names `rater_kernel_sd` explicitly and records its
induced common marginal and contrast SDs. The distinct target schema/identity
can be serialized and verified independently of a posterior fit; it does not
add a public fitting selector or fit-cache format. The
[equation/code review](fixed-coefficient-prior-identification.md#private-exchangeable-rater-reference)
states the scale-matching rules and the unchanged location/step assumptions.

CmdStan uses the existing fixed-coefficient sources with an explicit rater-prior
flag, retaining flag 0 in all existing fitting adapters. Flag 1 adds the
normalized correction and checks common rater kernel scales. Fresh compilation
changes model-source/executable hashes; it does not change the compatibility
target's distribution or historical fit identity. No sampler, loading block,
consistency prior or response kernel was copied.

New sampler-free tests passed 482 assertions on each Julia 1.10.8 and 1.12.5.
They check an independently constructed Gaussian density, full covariance,
gradients/Hessians, nonrater terms, rater-ID permutations, location shifts,
scale conversion, invalid inputs and persisted target-identity separation.
The previous prior/identification checks passed 428 assertions on each version,
and existing correlated-density checks passed 275 on 1.12.5. Fresh CmdStan
2.39.0 builds passed 434 assertions: full normalized density and gradient
comparisons for both ability models and both rater priors, 2/3/5 raters, 2/4
categories, original/reversed IDs and both automatic-Jacobian settings, plus
rejection of inconsistent rater scales. These are 192 point evaluations, with
no MCMC or statistical evaluation replications.

All five historical fit files retain their bytes, target identities and draw
records: cache verification passed 10 assertions on Julia 1.10 and 15 on 1.12.
The preceding handoff's 195 evidence files retain their recorded hashes.
Public-language policy tests passed 181 assertions, and the source-language
gate passed for 20 files. No public API or help text was added for this private
reference. The CmdStan grid used two dimensions; the independent 3D and
within-item permutation cases were checked in Julia in this slice.

The full suite, CI, independent scientific/reader review and statistical
recovery/coverage were not run. Public documentation and supported API claims
are unchanged. The local receipt records compatibility checks, input hashes,
commands and raw CmdStan density outputs:
[verification receipt](../../results/workflows/20260917-exchangeable-raters-01/receipt.json).

## Next bounded work

Add a private prior-draw adapter for the exchangeable-rater reference and reuse
existing prior-predictive summaries/figures to compare rating implications.
State contrast/common-marginal scale matching, distinguish the R=2 case, and
hold ability, item and ordered-step priors fixed. Check the generated covariance
against the declared target. Mathematical correctness alone does not choose
the scientific default; public fitting/cache integration, ordered-step priors
and target-specific recovery protocols remain separate decisions. Preserve
the present prior and historical artifacts. Higher-dimensional covariance,
within-item validation, automatic request caching, hard anchors and application
predictors remain separate.

Separately, record an unfamiliar reader finding the supported model/backend, loading a fit,
choosing a named dimension, interpreting diagnostic/interval labels and saving/
reopening the documented figure bundle. Record where explanations are missing
and correct those passages. No independent reader has performed this yet;
automated checks and implementer inspection cannot close that acceptance item.

Julia remains primary and CmdStan its maintained counterpart. Interruption-time
partial telemetry is deferred until a concrete failure-diagnosis need warrants
it; failed sampling must still preserve original errors and existing caches,
and must not publish a successful partial fit. Broader sampler failure handling,
statistical validation and application work remain separate. The normalized-prior
selector remains private.
