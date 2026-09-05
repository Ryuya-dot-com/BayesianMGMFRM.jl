# MFRM anchor study — internal review draft

Status: **not frozen; no fresh evaluation authorized**. The
[active roadmap](../../ROADMAP.md#active-decision-roadmap) owns priority and
milestone status. This file owns the M1 design and scoring decisions; archived
copies are historical. Moved from the root roadmap on 2026-09-05 without
changing the candidate truth, 16 primary cells, estimands, or execution count.

Commands and inline repository paths below are run from the repository root.

## Freeze decisions

The existing primary panel is specified below; it is not a complete execution
roster. Close each decision explicitly rather than adding another planning
script. The analyst prepares scientific choices, the maintainer checks the
execution budget, and an independent reviewer must accept the equations,
design, scorer, and thresholds. No reviewer is currently assigned.

| ID / status | Decision and required output | Review or runnable check before closure |
| --- | --- | --- |
| M1-01 — open | Enumerate the finite sensitivity cells and controls, including anchor placement/count aliases, shifts, crossed contamination signs/magnitudes, priors, nested links, category support, and information levels; name the estimand and pairing for each | Every required factor below maps to a cell or an explicit reviewed exclusion. Fixed contrasts are N/A for interval coverage; composite design changes are labelled |
| M1-02 — open, sharing/replay draft below | Declare pilot/evaluation and component RNG lineage, state ownership, data sharing, and any cross-design common random numbers; freeze the actual root/state roster | Reproduce one dataset without fitting; method order/addition cannot alter responses. Check non-overlapping allocation, not just distinct seed labels; fixed primary truth is not a fresh draw |
| M1-03 — open | Choose interval levels, practical tolerances, Monte Carlo precision, replications, and per-stratum decision rules for parameter and predictive targets | Justify numerical values before evaluation; distinguish MCMC error from across-dataset error and true-probability regret from heldout log loss |
| M1-04 — open | Choose the primary backend, actual prior scales, ordinary non-truth starts/jitter, chain settings, diagnostic policy, bounded cost probe, time/memory/output caps, and remediation allowance | Review the probe budget before running it; record resource evidence and keep all probes outside evaluation counts. The provisional 6,400 primary fits is not a budget authorization |
| M1-05 — open | Reuse the recovery/predictive scorer and specify planned/attempted/completed/diagnostic-valid counts, structural rejections, paired Monte Carlo error, and non-overwriting failure/remediation summaries | A bounded synthetic scoring check must include a failed fit, a fixed contrast, and paired methods; remove an unimplemented metric claim before freezing rather than treating a planning field as a scorer |
| M1-06 — open | Hand off the single protocol with exact source revision, cell roster, settings, scorer checks, unresolved questions, and claim limits | A person other than the implementer records accept/request-revision decisions. Review cannot be replaced by an implementer-authored receipt |

M1-01 now has the finite anchor-placement/error candidate subset below; nested
links, information/category support, prior/start subsets, and response-model
misspecification still need cell assignments or reviewed exclusions. Seed
choices, numerical acceptance thresholds, and replication budgets remain open.
M2 starts only after M0 and all freeze decisions close.

## M1 design and analysis decisions

Use the existing [mathematical and literature crosswalk](../../docs/src/migration-facets-conquest.md#implemented-stage-individual-hard-anchors-for-the-minimal-model)
and [exact anchor tests](../../test/hard_anchor_fit.jl). For each selected design
factor, record the source equation/page and DOI or existing Zotero key, and
whether it is direct model evidence, an analogy from another IRT model, or a
package-specific stress hypothesis. Reading a paper does not close a recovery
criterion. The following is a required coverage map, **not a frozen full
Cartesian grid**; M1 must enumerate primary cells and targeted sensitivity
subsets with the contrast each cell identifies.

| Factor | Required contrast or boundary | Confounding control / interpretation |
| --- | --- | --- |
| Response model | RSM and PCM; fitted-family truth and the existing extremity-response misspecification. | Independently code response probabilities from equations without calling package simulation, predictor, probability, or likelihood helpers. Verify hand-computed fixtures and normalization before fitting. A mismatch is fixed before M2. |
| Anchor count and facet | No declared anchors (default references), rater-only, item-only, and joint anchors; 1 versus 2 per affected facet, plus a fully fixed boundary. | Vary facet counts separately. The existing five joint regimes cannot identify separate rater and item contributions. Unsupported soft, threshold, and group-mean anchors stay rejection/inspection controls. |
| Anchor placement and error | Endpoints versus interior; clean values, common shifts within a facet, and differential contamination with both signs and more than one magnitude. | Separate prior-coordinate sensitivity from constrained contrast error; cross rater/item contamination signs on a targeted subset to expose cancellation. Leave-one-out flags incompatibility, not the guilty source. |
| Rating design and linking | Dense, connected sparse, and nested links varying absolute common-target count and score range; disconnected negative controls. | Record rater/item exposure and rating-event burden. Hold these fixed for a claimed placement effect, or label the contrast composite. Parameter anchors and common-response links have separate denominators. |
| Information and category support | Small versus larger information levels; unused endpoints/interior categories and boundary response patterns on a declared subset. | Keep scale declarations fixed and record affected strata; changes in population size, item count, and rater exposure must not masquerade as one isolated factor. |
| Prior and initialization | Actual weak/reference/strong prior refits; ordinary non-truth initial values and a bounded dispersed-start sensitivity subset. | Record prior predictive implications in the declared coordinates. Truth-initialized runs may diagnose computation but cannot replace ordinary-initialization evaluation. |
| Anchor source and prediction | Exact known anchors versus perturbed fixed inputs; independent heldout responses at existing persons/items/raters. | Hard-anchor intervals are conditional on supplied values. Source-estimation uncertainty and new-facet prediction need separate models and are outside this study's calibration claim. |

Before M2, the single M1 protocol must resolve all of the following:

1. **Estimands and criteria.** Primary targets are identified, estimated facet
   contrasts and true category probabilities/expected scores; prespecify bias,
   RMSE, interval coverage/width, posterior versus empirical uncertainty, and
   log-score regret. Fix interval levels and numeric tolerances per target and
   stratum, with a practical or source-based justification. Exact constants
   have no interval-coverage gate. Across gauges, use comparable contrasts and
   predictions and explicitly retain the prior-coordinate qualification.
   Recovery/nominal-coverage acceptance applies to correctly specified,
   compatible-anchor cells. For incompatible fixed contrasts or response-model
   misspecification, score probability/decision distortion and warning behavior;
   do not require recovery of a truth excluded by the fitted constraints. Any
   pseudo-true parameter target needs its own definition before execution.
2. **Precision and denominator.** Select independent dataset replications per
   primary cell from stated Monte Carlo precision targets for coverage, failure
   rates, and bias; reuse the existing replication-precision calculation where
   applicable. More chains/draws or anchor fits on one dataset do not increase
   this replication count. Paired comparisons retain dataset-level pairing;
   Monte Carlo error across datasets is separate from within-fit MCMC error.
3. **Scoring readiness.** Reuse the pilot probability/log-score calculations and
   existing recovery scorer after checking their truth/gauge contracts against
   the independent generator. The broader design-robustness scorer's predictive
   and decision gates are still unimplemented. Either implement the smallest
   analysis needed for a declared primary metric or remove that claim before
   freezing the study; do not count planning fields as a working scorer.
4. **Failure and decision policy.** Specify per-chain/block diagnostics,
   resource failures, structural rejections, and remediation before execution.
   Preserve the planned denominator and original attempts; numeric recovery
   among valid fits is labelled conditional and accompanied by failure-rate
   and predeclared failure-sensitivity summaries. Assess criteria per stress
   stratum; pooled success must not hide a failed domain. Any ranking or
   classification claim needs its own practical threshold and scored rule.
5. **Controls and cost.** Freeze cell IDs, non-overlapping pilot/evaluation
   response allocations and separate recorded sampler seeds,
   sampler settings, initialization/prior subsets, timeout and memory caps,
   and the smallest cross-implementation subset covering each claimed model
   and constraint. Cost probes contribute zero evaluation replications. An
   incompatible external anchor contract is recorded as non-overlap, not
   silently replaced by an unanchored fit.
6. **Terminal review.** Freeze the acceptance rules before fresh outcomes are
   inspected. A failed domain is narrowed or rejected; an unresolved estimate
   remains inconclusive. Any extension uses a declared new stage and RNG allocation,
   preserving the original results instead of increasing the sample until it
   passes. Independent equation/threshold review remains required; another
   implementer-authored receipt cannot satisfy it.

## M1 preparation: reuse and check the independent generator

The existing `src/local_dependence_known_truth_dgp.jl` already supplies a
standalone adjacent-category probability recurrence and inverse-CDF sampler.
Reuse those primitives; do not copy another probability kernel or adopt the
LD study's design, seeds, mechanisms, or scientific claims. RSM passes one
shared full step vector; PCM passes an item-specific full vector. The MFRM
adapter must explicitly construct its sum-to-zero steps and identified facet
coordinates from labelled truth, without reading them back through the fitting
kernel. The generating recurrence itself does not impose this gauge.

[Wind and Jones (2018)](https://doi.org/10.1177/0013164417703733), p. 686,
Eq. 1 (Zotero item `F3CVK9EA`), gives the RSM adjacent-category log odds
`theta - severity - difficulty - step`. [Linacre (2000)](https://www.rasch.org/rmt/rmt143k.htm)
distinguishes shared RSM from item-specific PCM step structures. These support
the equation and step ownership, not an optimal anchor count or a recovery
threshold. The existing anchor literature crosswalk retains the distinction
between parameter anchors and common-response links.

Run the bounded, MCMC-free conformance check with:

```bash
julia --startup-file=no --project=. test/mfrm_anchor_generator_crosscheck.jl
```

It checks hand-computed probabilities, binary and extreme-location limits,
half-open inverse-CDF bins including zero-probability categories, and loading
the generator in a separate stdlib-only process. A label-based adapter then
checks 768 compatible configurations: two model families, 2/3/5 categories,
dense/reversed-row connected-sparse designs, and all 8-by-8 masks of three
rater and three item anchors. Category labels include negative and one-based
scales. Another 96 configurations cross two differential-error magnitudes
with both signs in each facet; their probabilities match the constrained
oracle but differ from the original truth. Tolerance `1e-12` is a numerical
conformance limit, not a statistical acceptance threshold. The check is also
included in the ordinary `fitting_reports` shard. The initial 2,518 conformance
assertions and the 308 reference-declaration/estimand checks below are retained.
The additional 951 finite-candidate checks and 131 serial-response replay
checks described below bring the focused file to five testsets / 3,908
assertions, passing locally on Julia 1.10.8 and 1.12.5. The command contributes
**zero evaluation replications**.
It establishes implementation separation from the fitting kernel, not
independent authorship, independent review, or posterior calibration. The old
80-fit pilot remains unchanged and still used the shared fitting kernel.

Replication planning reuses `mgmfrm_validation_replication_precision`, despite
its historical generalized-model name. Its Bernoulli calculation is not a
model-specific validation claim. [Morris, White, and Crowther (2019)](https://doi.org/10.1002/sim.8086),
Sections 5.1--5.3, especially Eq. 1 on p. 2089 (Zotero item `PKQMUBH7`),
supports checking failed estimates and selecting replications using Monte
Carlo precision. For a **candidate**, not yet adopted, 90% interval:

| Independent datasets per cell | Coverage MCSE at 90% | Worst-case binary-rate MCSE |
| --- | --- | --- |
| 100 | 3.00 percentage points | 5.00 percentage points |
| 400 | 1.50 percentage points | 2.50 percentage points |
| 1,000 | 0.95 percentage points | 1.58 percentage points |

These are standard errors, not confidence-interval half-widths. Anchor refits
on the same dataset and multiple facet contrasts do not multiply this dataset
count. For pooled contrasts use dataset-level summaries or clustered Monte
Carlo uncertainty, not a falsely enlarged Bernoulli denominator. Nominal
frequentist coverage at fixed truth is an operating target to examine, not an
identity guaranteed by a Bayesian credible interval. Bias precision still
needs a justified error-SD reference, and diagnostic-invalid fits need the
predeclared failure sensitivity. Neither a replication count nor a complete
evaluation grid is frozen by this calculation.

## M1 candidate primary panel and comparison contract

The following is a **review draft, not an execution authorization or a frozen
study**. It reduces duplicated fitting without removing the required anchor
declaration cases. All numbers in this panel are package-specific synthetic
design choices, not recommended operational anchor counts. The distinction
between estimands, methods, and performance measures follows
[Morris et al. (2019), Sections 3.3--3.5](https://doi.org/10.1002/sim.8086)
(Zotero item `PKQMUBH7`); the target-equivalence deduction below is specific to
this package's reference constraints and priors, not a result asserted by that
paper.

Use 40 persons (`P01`--`P40`), four raters (`R1`--`R4`), four items
(`I1`--`I4`), and the declared category scale `0:3`. Keep the labelled truth
fixed across data replications: person locations are
`range(-1.2, 1.2; length = 40) .+ 1.35`, rater severities are
`(0, 0.5, 1.0, 1.5)`, and item difficulties are `(0, 0.4, 0.8, 1.2)`.
This preserves the pilot's location range and rater/item values, translated
into the default R1/I1 reference coordinates, while increasing the fixed person
grid from 20 to 40. It is not a prior draw or a random-facet population.
The candidate RSM full step vector is `(-0.6, 0, 0.6)`; PCM uses, by item,
`(-0.6, 0, 0.6)`, `(-0.4, 0.1, 0.3)`, `(-0.8, 0.3, 0.5)`, and
`(-0.2, -0.1, 0.3)`. Each sums to zero. Unlike the pilot's repeated item-step
vector, the PCM primary truth is not a shared-step RSM special case.

| Regime | Declared exact anchors | Scientific comparison |
| --- | --- | --- |
| B | None; R1 and I1 retain their default zero references | Baseline identified model |
| R | R1 = 0, R4 = 1.5 | Add one known rater contrast |
| I | I1 = 0, I4 = 1.2 | Add one known item contrast |
| RI | Union of R and I | Add both contrasts and assess their interaction |

At these coordinates, declaring R1 = 0 alone, I1 = 0 alone, or both does not
change B's free coordinates, likelihood, or prior density. Likewise, adding
I1 = 0 to R or R1 = 0 to I leaves its sampling target unchanged. Thus the nine
0/1/2-anchor-count combinations have **four distinct posterior targets** in
this restricted panel. `test/mfrm_anchor_generator_crosscheck.jl` checks all
five aliases on the 40-person dense/sparse RSM/PCM designs at three parameter
vectors and three prior-scale settings, and checks rating counts, balanced
rater exposure, and which contrasts remain estimated.
Keep report/provenance/cache distinctions; equal
sampling targets do not mean equal metadata. Shifted values, a different
reference level, interior anchors, and different priors are **not** covered by
this reduction and must remain sensitivity cases.

| Data cell | Observed training events | Candidate fit-cell IDs |
| --- | --- | --- |
| RSM-D | All 40 x 4 x 4 person/rater/item events: 640 ratings | RSM-D-B, RSM-D-R, RSM-D-I, RSM-D-RI |
| RSM-S | For person p, raters `mod1(p,4)` and `mod1(p+1,4)` score every item: 320 ratings | RSM-S-B, RSM-S-R, RSM-S-I, RSM-S-RI |
| PCM-D | Same dense event design, item-specific step truth | PCM-D-B, PCM-D-R, PCM-D-I, PCM-D-RI |
| PCM-S | Same connected-sparse event design, item-specific step truth | PCM-S-B, PCM-S-R, PCM-S-I, PCM-S-RI |

Generate responses with the standalone recurrence, and use identical training
data for B/R/I/RI within each data cell and replication. Independent heldout
responses use the same observed facet tuples and fixed truth. Pair data by
replication for method comparisons; no anchor-regime identifier enters the
response allocation. RSM and PCM truth differs, so shared uniforms would not make
their scores identical. Dense versus sparse changes rating burden and exposure;
do not advertise it as an isolated topology effect or compare their raw
predictive losses as if they used the same event-weighting distribution.

Primary parameter targets are `R3 - R2`, `I3 - I2`, and `P30 - P10`.
All remain estimated under B/R/I/RI. Score bias, RMSE, interval coverage/width,
and posterior-versus-empirical uncertainty separately for each target; do not
pool the three as independent replications. Prediction targets are the true
category probabilities and expected scores on each data cell's declared event
set, with equal event weights. Keep true-probability KL regret distinct from
finite-sample heldout log loss. Rater comparisons are R minus B and RI minus I;
item comparisons are I minus B and RI minus R. Evaluate an interaction, if
retained, as RI minus R minus I plus B on a predeclared dataset-level error or
loss, with paired Monte Carlo error, not by assuming independent fits.

Moving a two-anchor set from endpoints `{1,4}` to interior levels `{2,3}`
fixes the primary contrast `3 - 2` itself. Label its posterior coverage not
applicable, never perfectly covered. Placement sensitivity retains common
prediction/person targets and prespecifies `R2 - R1` or `I2 - I1` as the
affected facet's secondary contrast: exactly one endpoint is estimated under
either placement. Mark this as partially estimated, and do not substitute it
for a failed primary metric after observing results. Only a requirement that
**both** contrast endpoints remain free under both disjoint anchor sets would
need a larger design (at least six levels for two free endpoints). Fully fixed
facet controls have no estimated within-facet contrasts. Contaminated fixed
contrasts and extremity-response truth remain distortion/warning tests rather
than recovery of excluded truth.

All these are conditional hard-anchor comparisons under the declared priors:
changing the fixed coordinates also changes which parameters receive priors.
The placement comparison is not a claim about anchor location alone under an
unchanged joint prior on all facet coordinates.

The candidate 400 independent datasets per data cell would require
`4 x 400 = 1,600` generated training datasets and `16 x 400 = 6,400` primary
fits, not 14,400 fits for the nine declarations. These are planned costs, not
executed evidence; sensitivity, cross-backend, failed-attempt, and remediation
costs are additional. Replication counts remain provisional until a bounded
cost probe and the precision/threshold review. Ordinary starts must use
`init = nothing` (the package's zero vector) with a declared non-truth jitter;
the pilot's truth/projection initialization does not transfer. Next resolve
the finite sensitivity-cell/seed table, sampler and resource settings, and
scorer/decision thresholds before requesting the independent freeze review.

## M1 data sharing and RNG ownership draft

This is the preferred **review candidate**, not a frozen seed roster or a new
execution command. Reuse the standalone probability recurrence/inverse CDF,
but do not adopt either the old pilot's arithmetic seed offsets or LD1's
event-keyed reseeding as a proven independent-stream construction.
[Morris et al. (2019)](https://doi.org/10.1002/sim.8086), Sections 4.1--4.1.1,
pp. 2081--2084 (Zotero `PKQMUBH7`, indexed full text checked), recommend saving
RNG states and warn that arbitrarily different seeds can start overlapping
streams. Their example of saving successive one-draw states is not a valid
way to allocate multi-draw replications. Distinct IDs, distinct seeds, and a
collision-free finite key check do not establish statistical independence.

Prefer **serial response generation before fitting**, with one explicitly
owned `MersenneTwister` advanced across complete, non-overlapping blocks. Save
the start and end state of every block; replay uses a copy of its start state,
not the live allocator. The allocation unit is `(stage, data_cell, replication,
role)`, where role is training or heldout. Within a stage, order replication
IDs first, then `RSM-D, RSM-S, PCM-D, PCM-S`, then training/heldout. Within each
block use the lexicographic labelled event order `(person, rater, item)` from
the primary panel, one scalar `rand(rng)` per event. Never use method/anchor
IDs, worker numbers, task schedules, discovered level order, or outcome-based
sorting to allocate response randomness. Retain these labelled tables before
the fitting layer recodes levels. Selecting/reordering rows reads the stored
event map; it must not consume a new response stream. Disjoint draw positions
prevent accidental reuse; this is not a proof of statistical independence or
a validation of the PRNG's statistical quality.

| Randomness/data owner | Sharing and separation contract |
| --- | --- |
| Fixed truth and event design | Store their version and labelled values; truth/design RNG is N/A in the primary panel. Random truth or random designs need their own reviewed allocation, not a hidden extra draw |
| Training responses | One stored dataset per stage/data-cell/replication, reused by all B/R/I/RI, sensitivity, prior/start, and backend comparisons that retain that DGP. Anchor contamination changes fitted inputs, not generating truth or responses |
| Heldout responses | A separate block on the same observed facet tuples and truth, shared by the same methods. Never feed heldout outcomes to fitting, initialization, diagnostics-based remediation, or subset selection; this is not new-facet prediction |
| Across RSM/PCM or dense/sparse | No intentional common random numbers in this primary candidate: allocate separate blocks. A sparse response table is not a subset of the dense response table. Equal replication numbers alone do not make a cross-design paired comparison |
| Sampler and initialization | Separate from response allocation. Identify each fit by dataset ID, canonical method, backend, prior/start setting, and attempt ID; reuse one control fit across comparisons. Record the actual replay seed/settings, not its loop position |

Training and heldout scores can coincide by chance; require different allocated
draw positions, not forced score inequality. Never redraw to fill missing score
categories or rescue a failed fit; retain the declared `0:3` scale and the
original planned denominator. Paired losses/quartets join by the
same stored dataset and heldout IDs, not merely matching seed integers. If the
100-of-400 sensitivity allocation is selected, use the prespecified first 100
replication IDs of each relevant sparse cell and those IDs' already fitted
clean controls. This outcome-independent prefix needs no subset-selection RNG;
it is a candidate rule, not authorization of allocation A or B. All four cells
of an interaction must use the same complete-case subset and report failures.

Keep smoke, pilot/cost-probe, evaluation, and later amendments distinguishable
in IDs and records. For the new response lineage, fix phase draw allocations
before any phase is generated and place later phases after the reserved end
state of the earlier allocation, even if some pilot blocks are unused. Do not
reset the root at each phase or let an early-stopped pilot choose evaluation's
starting position. Evaluation blocks remain ungenerated until authorization.
Actual root seed, all phase/block sizes, persistence format, and any additional
DGP allocations remain M1-02/04 decisions; no numeric evaluation seed is minted
here. Adding a method cannot change these blocks. Adding a data-generating
cell requires an appended, reviewed allocation, never insertion that moves
existing blocks. The old 80-fit pilot stays outside the new lineage and counts.
Do not parallelize response allocation without a reviewed non-overlapping
stream mechanism; distributing already generated datasets for fits is separate.

The current `fit(seed=...)` owns a local `MersenneTwister`, with a seed that
must fit `Int`. AdvancedHMC/Turing consume that fit RNG for initial jitter and
successive chains; there is no separately exposed per-chain/jitter seed option.
CmdStan derives and records additional chain seeds. Do not promise unchanged
later chains after changing earlier chain work, or the same trajectories from
equal seeds across backends/dimensions. Freeze the actual attempt-seed roster
and backend behavior with M1-04, audit duplicates against other roles, and
retain all original attempts. Exact replay keeps the original settings/seed;
authorized remediation gets a new attempt ID and seed on the **same data**,
not a replacement dataset or an extra independent replication. Unique sampler
seeds are bookkeeping, not a proof of independent substreams. No sampler change
or sampler-independence claim is made by the response smoke below.

[Julia's Random documentation](https://docs.julialang.org/en/v1/stdlib/Random/#Reproducibility)
notes that seeded sequences may change across releases and recommends saving
random data for exact reproduction. Retain generated labelled training/heldout
tables with category declarations, fixed truth, RNG engine/root/block states,
source revision, exact Julia version, and dependency manifest. Saved state is
an environment-bound replay aid, not a portable substitute for the data.
Test invariance within each supported environment; do not pin arbitrary score
bytes across Julia releases or substitute a checksum for the saved tables.

The existing focused test now adds a bounded two-replication **smoke only**:
16 training/heldout blocks across the four data cells, 7,680 scalar uniforms,
131 assertions. It checks contiguous allocation against a single serial draw
sequence, block replay in reverse request order, valid scores, and event-keyed
row reversal/subsetting. Memory-only mutations that alias the start checkpoint
or reverse uniform-to-event attachment trigger 47 and 16 assertion failures,
respectively, with no errors. The unmodified file passes all 3,908 assertions
on Julia 1.10.8 and 1.12.5. This checks primitives and the stated construction,
not a production executor, on-disk replay, stage reservation, sampler streams,
or posterior calibration. It uses test seed 17 only; no fit or evaluation
replication is run. M1-02 stays open for those unchecked boundaries and review.

## M1 candidate anchor-placement and error subset

This is a **finite review candidate, not a frozen roster**. Apply the following
57 additional anchor regimes to each of `RSM-S` and `PCM-S`, using that cell's
unchanged truth, observed events, and paired training/holdout datasets. Do not
regenerate responses when anchor inputs change. Dense sensitivity interactions
and differential errors on interior anchors are not covered by this subset.
Clean B/R/I/RI comparators already exist in the primary panel and are not
counted again.

Let `U = {-0.8, -0.2, +0.2, +0.8}` logits. These synthetic magnitudes reuse the
existing deterministic contamination check's 0.2/0.8 levels; they are neither
practical cutoffs nor values recommended by the literature. A cell ID is its
data-cell prefix plus the regime and signed values, for example
`PCM-S-D-RI-u+0.2-v-0.8`. Exact values without a shift refer to the labelled
primary truth. An unaffected facet retains its default zero reference unless
the row explicitly retains its clean two-anchor set.

| Regime suffix | Fixed inputs / finite values | Cells per data cell | Paired comparison and target |
| --- | --- | --- | --- |
| `S-R`, `S-I`, `S-RI` | One non-reference anchor: R4, I4, or both at truth | 3 | Compare with B for reference/prior-coordinate sensitivity, and with R/I/RI for the added known contrast; retain primary contrasts and predictions |
| `P-R`, `P-I`, `P-RI` | Replace the affected endpoint pair by its interior pair R2/R3, I2/I3, or both, at truth | 3 | Compare with R/I/RI; use predictions/person contrast and the predeclared partially estimated `2 - 1` facet contrast, not coverage of fixed `3 - 2` |
| `F-R`, `F-I`, `F-RI` | Fix all four levels of the affected facet(s) at truth | 3 | Compare with R/I/RI as a known-facet boundary; fixed within-facet contrasts have no interval-coverage score |
| `C-R(u)`, `C-I(v)` | Add u to both R anchors, or v to both I anchors; u or v in U | 4 + 4 | Compare with clean R or I; common-shift likelihood gauge with unchanged declared priors |
| `C-RI(u,v)` | Shift both R anchors by u and both I anchors by v; u,v in U with `abs(u) = abs(v)` | 8 | Compare with clean RI; same/opposite signs, including zero net person-location shift |
| `D-R(u)`, `D-I(v)` | Keep anchor 1 at truth; perturb only anchor 4 by u or v in U | 4 + 4 | Compare with clean R or I; incompatible within-facet contrast, score distortion/warnings |
| `D-RI(u,0)`, `D-RI(0,v)` | Keep both endpoint anchor sets; perturb only R4 or I4, with the nonzero value in U | 4 + 4 | Same-constraint single-perturbation controls for the crossed error interaction |
| `D-RI(u,v)` | Keep R1/I1 at truth; perturb R4 by u and I4 by v for all `(u,v)` in `U x U` | 16 | Compare with clean RI; use the same-constraint controls to distinguish the two perturbations |

Reuse each `D-RI(u,0)` and `D-RI(0,v)` control across the crossed cells with that
nonzero value. They retain **both** clean two-anchor sets except for the named
perturbation; they are not D-R/D-I, which leave the other facet unanchored.
On a predeclared dataset-level loss, the
interaction is `L(u,v) - L(u,0) - L(0,v) + L(0,0)`, with paired Monte Carlo
error. The table totals **57 regimes per data cell**, or **114 additional fit
cells** across the two families. The controls are required if this interaction
is retained; do not infer it from fits with different clean anchor constraints.

The distinction between C and D follows the adjacent-category predictor
`eta = theta_p - rho_r - beta_i`. For C, translating every rater coordinate
by u, every item coordinate by v, and every person coordinate by `u + v`
preserves the likelihood (take the unaffected facet's shift as zero). The
package's zero-centered free-coordinate priors do not undergo that translation.
Even when `u + v = 0`, free facet priors can change; this is not a posterior
invariance claim. Score contrasts/predictions, not unaligned absolute person
locations. S and P likewise change which coordinates receive those priors.

For D-RI, at the original free coordinates before refitting, the imposed
predictor change is `-u * 1[r = R4] - v * 1[i = I4]`. Equal opposite errors
cancel only on the R4/I4 intersection, not on R4/other-item or other-rater/I4
events; both event types occur in the sparse design. Unequal magnitudes test
partial cancellation as well. This algebra is a generator/projection check,
not a claim that a refitted posterior must retain the same local distortion.
For D-RI and its paired controls, keep these three event strata and the
unaffected stratum separate in predictive summaries: their event counts are
20/60/60/180, summing to the same 320-event primary total. Do not average the
four stratum means equally and call that the equal-event-weight total. Do not
require nominal recovery of a truth excluded by an incompatible fixed contrast.

[Kopf et al. (2015)](https://doi.org/10.1177/0013164414529792), pp. 36--37
(Zotero `4CEIQCQX`), vary DIF proportion and balanced/unbalanced direction in a
dichotomous Rasch simulation with a **constant 0.4** DIF magnitude. This is an
analogy motivating directional contamination controls, not evidence for our
two magnitudes, cross-facet design, or a Bayesian polytomous recovery threshold.
[Wind and Jones (2018)](https://doi.org/10.1177/0013164417703733), pp. 683--686
(Zotero `F3CVK9EA`), vary common-response linking-set size (3/6/8), location,
and fit. Those are observed linking persons, not fixed parameter anchors.
Their study motivates the still-open link-size/location/misfit subset, not
using 3/6/8 as a parameter-anchor prescription. These source-method sections
were checked in indexed Zotero full text; neither source supplies this roster.

The arithmetic is `16 + 114 = 130` distinct candidate fit cells, not 130 new
data-generating cells. Extending the provisional 400 replications to all of
them would mean **52,000 fits**, before the other sensitivity factors,
cross-backend checks, failures, or remediation. That is a cost warning, not an
approved replication allocation. The alternatives below separate scenario
coverage from Monte Carlo precision; M1-03/04 must justify the chosen allocation
and its claim limits before any execution.
The existing generator-check file now explicitly enumerates all 57 sensitivity
regimes and four clean sparse comparators per family (114 + 8 configurations).
Its 951 added assertions check unique IDs/constraint sets, free parameter names
and block sizes, independent-oracle probabilities and pointwise likelihoods,
common-shift prior non-invariance at these vectors, and the four event strata.
They include all asymmetric error pairs and verify that joint-error controls
retain the same fixed sets/free-coordinate priors; D-R/D-I are not substitutes.
A memory-only mutation dropping the item anchors from `D-RI-u+0.2-v0` produced
20 assertion failures and no errors, confirming that this mistake is detected;
the then-current file passed all 3,777 assertions on both local Julia versions.
The 1e-12/1e-4 checks test numerical agreement/non-equality, not statistical or
practical acceptance. Scores are deterministic scaffolding, not fresh responses.
This verifies the candidate constraints and projection algebra, **not** an
evaluation executor, RNG policy, interval/failure scorer, posterior calibration,
or independent review. No new controller, fixture, or fit is introduced.
All six freeze decisions remain open, including the other factor subsets.

## M1 allocation and budget decision draft

Prioritize the 16 primary cells for the main recovery/calibration questions.
The 114 sensitivity candidates comprise **50 compatible cells** (S/P/F/C:
`2 x (9 + 16)`) and **64 incompatible-contrast cells** (D:
`2 x (8 + 8 + 16)`). Compatible cells retain conditional recovery targets
where estimated; fixed contrasts remain N/A. D cells assess distortion and
failures, not recovery of an excluded truth. This division sets analysis
priorities; it does not make the third group optional or authorize deleting
unfavorable results. No scenario is removed by the following alternatives.

| Review alternative | Replications per primary / compatible / D fit cell | Planned fits | Precision/claim consequence |
| --- | --- | --- | --- |
| A — lower-cost descriptive sensitivity | 400 / 100 / 100 | 17,800 | Retains all 130 cells; sensitivity estimates have lower precision and do not inherit primary calibration or rare-failure claims |
| B — retain compatible-cell precision | 400 / 400 / 100 | 32,800 | Compatible-cell precision matches the primary allocation; D loss/failure precision still needs its own justification |
| C — uniform reference | 400 / 400 / 400 | 52,000 | Uniform replication count, not uniformly sufficient precision for every metric |

Review A first if descriptive sensitivity results are sufficient; otherwise
review B/C or explicitly narrow the intended domain before freezing. None is
selected here. These totals exclude the still-open linking, information,
category, prior/start, and response-misspecification subsets, cross-backend
checks, probes, and additional attempts. They are not whole-study budgets.
Keep the same 1,600 primary training datasets: a 100-replication sensitivity
uses a fixed, outcome-independent subset of 100 of its sparse data cell's 400
replication IDs. Pair every comparison/control on that same subset, including
clean methods already fitted for the primary panel. Do not compare its 100
losses against a clean mean over all 400 or count shared controls twice.
Select IDs before generating outcomes; the candidate first-100 rule and
remaining RNG gates are in the [sharing draft](#m1-data-sharing-and-rng-ownership-draft).

[Morris et al. (2019)](https://doi.org/10.1002/sim.8086), Sections 5.1--5.3,
Table 6 and p. 2089 Eq. 1 (Zotero `PKQMUBH7`), motivate choosing repetitions
from performance-measure precision and treating missing fits explicitly.
Those indexed full-text sections were checked; they do not recommend this
400/100 split. Reusing `mgmfrm_validation_replication_precision` confirms that
the candidate 90% coverage MCSE is 3.0 versus 1.5 percentage points at 100
versus 400 independent complete outcomes; worst-case binary-rate MCSE is 5.0
versus 2.5 points. These are marginal per-cell references, not simultaneous
guarantees across targets/cells, nor tolerances for accepting the model.

Rare failures need a separate precision check. With zero failures in N
independent, fully observed Bernoulli attempts at a fixed, nonadaptive N,
solving `(1 - p)^N = 0.05` gives the exact one-sided 95% upper bound
`p = 1 - 0.05^(1/N)`: **2.95% at N=100**, versus **0.746% at N=400**.
Thus zero of 100 does not establish a below-1% failure rate by this criterion.
This is an illustrative mathematical bound, not adoption of a 1% acceptance
threshold. Unattempted or unclassified outcomes cannot be counted as successes.

Continuous loss precision cannot be obtained from that binary calculation.
For each replication form the paired loss difference d, or the four-cell
interaction d defined above; its mean has estimated MCSE `sd(d) / sqrt(m)`
over m complete finite pairs/quartets (m >= 2; otherwise unavailable).
Do not sum independent-method variances: the shared-data covariances matter.
When fits are missing/diagnostic-invalid, label this estimate conditional on
that common valid subset and report its size against the planned denominator;
M1-05's failure-sensitivity policy remains required. A predeclared SD reference
from an authorized pilot or external evidence is needed to plan precision for
these losses. No such reference is supplied by a CI test duration or by the
Bernoulli helper, and this draft does not authorize pilot execution or increasing
replications after inspecting evaluation results.

Before accepting any allocation, M1-04 must fix sampler/prior/start settings
and a separately reviewed cost-probe cap. Bound total serial attempt-hours by
`sum((N_j + A_j) * t_cap_j) / 3600`, plus shared setup/probe allowances: N_j
counts planned fits, A_j caps additional attempts, and t_cap_j covers the whole
attempt, including all chains, warmup, diagnostics, and per-attempt startup.
Also bound concurrent aggregate memory and retained output, not just one
process's RSS. None of these caps or a concurrency level is selected yet.
The engineering fit shard includes extensive compilation and many test fits;
its job time is not an estimate of the study's per-fit cost. Use measured,
setting-matched probe costs and retain failures/additional attempts in the
budget instead of silently replacing them.

After each milestone, record only: which uncertainty decreased, which claim
that changes, and what now blocks the next decision. Missing review or external
data should trigger a concrete handoff and work on an independent open item,
not repeated local simulations of the same question. Generalized validation,
LD1b, free correlation, soft/group anchors, and new-facet prediction keep their
own prerequisites and denominators. This roadmap revision changes planning,
not API support, completed evidence, or execution status.
