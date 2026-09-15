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

| ID / status | Decision and required output | Owner, needed input, and closure evidence |
| --- | --- | --- |
| M1-01 — open, finite factor subsets and exclusions drafted | Review the candidate cells and exclusions for anchors, links, information/categories, priors/starts, and response/link misfit; freeze the retained roster, estimands, and pairing | Analyst, with maintainer-supplied claim scope: every required factor maps to an accepted cell or explicit reviewed exclusion. Fixed contrasts are N/A for interval coverage; composite design changes are labelled |
| M1-02 — open, native replay and response-byte binding checked | Declare pilot/evaluation and component RNG lineage, state ownership, data sharing, and any cross-design common random numbers; freeze the actual root/state roster | Analyst, using the M1-01 roster and M1-03/04 allocation/settings: synthetic replay and labelled response restoration are checked; durable data/state/source binding, actual allocation, and review remain required |
| M1-03 — open, pointwise precision and claim limits proposed | Choose interval levels, practical tolerances, Monte Carlo precision, replications, and per-stratum decision rules for parameter and predictive targets | Review the precision proposal below; practical tolerances and continuous-loss SD references still need justification. Distinguish MCMC error from across-dataset error, and descriptive pointwise results from simultaneous acceptance |
| M1-04 — open, sampler/resource options proposed | Choose the primary backend, actual prior scales, ordinary non-truth starts/jitter, chain settings, diagnostic policy, bounded cost probe, time/memory/output caps, and remediation allowance | Review the prior-predictive audit and provisional sampler settings below; maintainer supplies a resource envelope before any cost probe. Whole-panel fit/data counts are arithmetic, not budget approval or measured cost |
| M1-05 — open, complete candidate scoring roster checked without fitting | Reuse the recovery/predictive scorer; the denominator/applicability draft below specifies failures, paired Monte Carlo error, and non-overwriting remediation | Analyst, using M1-01--04: bound fit/data/source checks, explicit evaluation panels, category totals, HMC/contrast screens, recovery applicability/failure summaries, contrast-error pairs/quartets, and descriptive predictive pairing cover all 266 candidate cells with synthetic objects; see the verification record below. The predictive pairer reuses primary and secondary reports without parameter-target duplication. Curvature-aware precision, accepted diagnostic/precision policy, complete source/environment/RNG and lifecycle provenance, a persistent all-attempt ledger, and final decision rules remain required; an unimplemented metric needs implementation or an explicit scope decision |
| M1-06 — open | Hand off the single protocol with exact source revision, cell roster, settings, scorer checks, unresolved questions, and claim limits | Maintainer obtains a willing independent reviewer; terminal review needs review-ready M1-01--05 proposals and checks. A person other than the implementer records accept/request-revision decisions. Nomination, availability, and implementer-authored receipts are not acceptance |

M1-01 now has finite factor subsets and explicit proposed exclusions below,
totalling 266 candidate fit cells. This is not an accepted whole-study roster.
All finite candidate subsets now have checked in-memory scoring integration.
Encoding every candidate cell is not a complete generation/RNG/execution pipeline.
Whole-roster descriptive predictive pairing is connected; curvature-aware
precision, complete source/environment/RNG and lifecycle provenance, seed
choices, numerical acceptance thresholds, and replication budgets remain open.
M2 preparation can proceed now; fresh evaluation requires all independently
accepted freeze decisions and the roadmap's
[research execution prerequisites](../../ROADMAP.md#research-execution-prerequisites),
not completion of the deferred M0 performance investigation.

### Preparation order and handoff

These are drafting dependencies, not new execution permissions. All six
decisions remain open; owner roles above are unassigned until a person accepts.

1. **Prioritize M1-01 and reviewer assignment.** Review the anchor,
   [nested-link](#m1-candidate-nested-link-subset),
   [information/category subset](#m1-candidate-information-and-category-support-subset),
   [prior/start](#m1-candidate-prior-and-start-subset), and
   [response/link-misfit](#m1-candidate-response-and-link-misfit-subset)
   candidates and exclusions together. Each row names
   its question, control, estimand/applicability, data pairing, and source or
   stress-test rationale. Reuse the 16 primary and 114 anchor-sensitivity candidates;
   do not treat them as a complete roster or add combinations without a question.
   The maintainer supplies the intended claims and seeks reviewer agreement on
   scope and availability; this document sends no invitation or assigns a person.
2. **Resolve M1-03 and M1-04 together.** Propose justified tolerances/precision
   and fixed sampler/prior/start settings using the
   [precision/execution proposal](#m1-0304-precision-and-execution-decision-proposal), then reconcile replication counts
   with a reviewed cost-probe and total resource envelope. The existing
   [allocation alternatives](#m1-allocation-and-budget-decision-draft) remain
   alternatives, not a selected budget. M0's regression-shard time is not a
   per-fit study cost. If precision and cost conflict, return a scope/allocation
   decision; do not silently relax tolerances, omit strata, or start a probe.
3. **Finalize M1-02/05 bindings, then request M1-06 review.** Tie the actual
   allocation and RNG roster to the retained attempts, truth, responses, source,
   and scorer decisions. Resolve each required binding or scorer gap with the
   existing primitives and focused checks. The handoff is this single protocol
   plus evidence links and one source revision, with an accept/request-revision
   disposition for each decision; do not create another controller or ledger
   format merely to track drafting. Changing the roster or settings reopens
   affected downstream decisions before terminal acceptance.

Reviewer availability and a resource envelope are external inputs, not work
that more local tests can complete. Until they exist, record the specific
missing input here and continue independent M1/M2 preparation and synthetic
checks. Fresh M2 evaluation requires independently accepted M1 and research
execution readiness; M0's unresolved historical timing increase is no longer
a blanket prerequisite. This sequencing decision does not select any candidate
cell, threshold, seed, replication count, or scientific claim for execution.

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
3. **Scoring readiness.** Reuse the existing probability/recovery scorers, not
   the historical pilot's inline KL formula, and check their truth/gauge
   contracts against the independent generator. The broader design-robustness
   scorer's predictive and decision gates are still unimplemented. Either implement the smallest
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
sh scripts/quiet_command.sh julia --startup-file=no --project=. test/mfrm_anchor_generator_crosscheck.jl
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
The additional 951 finite-candidate, 199 serial-response replay, 50 denominator,
28 predictive-boundary, 216 all-category log, 277 independent-log-truth,
52 labelled-roundtrip, 76 attempt-identity, and 95 response-byte-binding checks
bring the focused file to twelve testsets / 4,770 assertions, passing locally
on Julia 1.10.8 and 1.12.5.
The command contributes **zero evaluation replications**.
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
respectively, with no errors. The then-current file passed all 3,908 assertions
on Julia 1.10.8 and 1.12.5. This checks primitives and the stated construction,
not a production executor, stage reservation, sampler streams, or posterior
calibration. On-disk replay is now checked separately below. It uses test seed
17 only; no fit or evaluation replication is run. M1-02 stays open for the
remaining boundaries and review.

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

## M1 candidate nested-link subset

**Review candidate only; no new responses or fits.** Separate common-response
links from fixed parameter anchors. Reuse the primary 40-person truth, four
raters/items, `0:3` categories, RSM/PCM steps, and B/R/I/RI regimes. The following
two-group topology is a new candidate, not a replay of the old pilot's
single-primary-rater, 10%-of-person-item design.

For every odd-numbered person, R1/R2 score all four items; for every even-numbered
person, R3/R4 do so. These 320 base events remain in every topology. Each selected
common person is additionally scored by the other two raters on every item.
With L common persons, this yields L distinct people, 4L all-rater common
person-item units, and `320 + 8L` ratings. Do not conflate those three counts.

| Topology suffix | Common person indices | L / common person-item units | Ratings / ratings per rater and per item |
| --- | --- | --- | --- |
| N-C4 | 19, 20, 21, 22 | 4 / 16 | 352 / 88 |
| N-C8 | 17 through 24 | 8 / 32 | 384 / 96 |
| N-E4 | 1, 2, 39, 40 | 4 / 16 | 352 / 88 |
| N-E8 | 1, 2, 3, 4, 37, 38, 39, 40 | 8 / 32 | 384 / 96 |

C selects a central ability band; E selects both ends. Every set is balanced
between the two home groups and symmetric about person location 1.35. At the
same L, overall burden, per-rater/per-item exposure, and mean link location
match; the link's ability spread and person-specific extra ratings differ.
This removes the old pilot's rater-load/item-mix imbalance, not every design
confound. C4-to-C8 also changes the link range; increasing L changes information
and workload. Neither contrast establishes an isolated universal link-count
effect, a mean-location effect, or an optimal anchor percentage.

A fit-cell ID is `<RSM|PCM>-<N-C4|N-C8|N-E4|N-E8>-<B|R|I|RI>`:
eight new data cells and **32 additional fit cells**. Within a data cell and
replication, reuse training and heldout data for all four anchor regimes.
For comparisons across these topologies, score predictions on the common
320 base-event set with equal event weights; draw heldout responses on that
same set, separately from training. Do not compare each topology's different
full training-event distribution as if the forecast situations were identical.
Use the existing primary parameter contrasts. Allocate response blocks
separately across topology cells: equal replication indices are not paired
datasets, and nested event sets do not imply shared response draws. New blocks
require the reviewed M1-02 stage allocation; none is allocated by this draft.

Retain **N-Z0**, with no common people, as a no-fit identification boundary,
not eight additional recovery fits. For the additive predictor
`theta_p - rho_r - beta_i`, holding steps fixed and deleting fixed anchor
columns, its B and I matrices have ranks 45/46 and 44/45. Shifting every even
person and R3/R4 by the same amount leaves responses unchanged; in particular,
the cross-group `R3 - R2` contrast is not likelihood-identified. R and RI fix
R4 as well as R1 and remove that null direction: ranks 45/45 and 44/44.
Thus absent response links do not imply the same identification result under
every anchor regime; proper priors are not evidence of likelihood identification.
The later no-fit target-adapter check now confirms that the package's existing
reference-location validation rejects N-Z0 under **all four** regimes, including
the mathematically anchor-rescued R/RI cases. This is a current implementation
boundary, not evidence against the rank calculation. The adapter does not
bypass or change that validation; N-Z0 remains outside the recovery roster.

A one-off stdlib exact-rational check verified all 20 topology/anchor combinations:
unique events, exposure/count formulas, nested C/E sets, and the predictor
ranks above. All four positive-link topologies have full column rank in this
predictor block. This is not a full polytomous-model identification proof,
package compilation check, posterior recovery result, or independent review.
Extend the existing generator/scorer checks before freezing these cells.

[Wind and Jones (2018)](https://doi.org/10.1177/0013164417703733)
(Zotero `F3CVK9EA`; library metadata/abstract rechecked) motivates examining
link size, latent location, and fit. It does not prescribe these 4/8-person
sets or validate their Bayesian recovery. Equal forecast situations for score
comparisons follow [Gneiting and Raftery (2007)](https://doi.org/10.1198/016214506000001437)
as discussed in the existing scoring section. The labels, counts, balancing,
and rank deductions here are package-specific design choices and algebra.

The existing 130-cell anchor panel is unchanged; the anchor-plus-link subtotal
is 162 fit cells, not a complete study or approved budget.
The 17,800/32,800/52,000 alternatives below still cover only the original 130.
Do not silently assign the new 32 cells their replication counts.

| Remaining factor | Disposition for the next M1-01 draft, not an approved exclusion |
| --- | --- |
| Information and category support | Review the finite subset below; its sparse 20/40-person comparison does not cover larger populations, dense/nested information interactions, or forced structural-zero categories |
| Prior and initialization | Review the prior/start subset below and couple its candidate scales and non-truth jitter to M1-03/04 precision/cost; truth starts remain excluded from primary evaluation |
| Response/link misfit | Review the signed quadratic-tilt subset below, including link-local misfit. Other link counts/locations and crosses with the 57 anchor-error regimes remain excluded candidates, not supported claims |

## M1 candidate information and category-support subset

**Review candidate only; no evaluation responses, fits, or allocation.** Use
the primary connected-sparse design and its original labelled truth, not a new
20-point ability grid. Retain persons with indices `1:4, 9:12, 19:22, 29:32,
37:40` and their original rotating rater pairs. This S20 set contains P10/P30,
five people from each residue modulo four, and symmetric ability locations
about 1.35. Keep the original labels: P30 is not the 30th row of a 20-person fit.
All four items and raters remain present. S20 has 160 events and 40 ratings
per rater/item; the existing S40 sparse cell has 320 and 80, respectively.
S40 here denotes the existing `RSM-S`/`PCM-S` cells, not new cell IDs.
Each retained person still has eight ratings. Thus the comparison changes
sample composition, shared-facet information, and nuisance-parameter count,
not an isolated doubling of information for the person contrast.

For information comparisons, retain `R3 - R2`, `I3 - I2`, and `P30 - P10`
with the same true values. Score predictions on S20's common 160 event tuples
with equal weights; obtain S40's comparator by restricting its already-defined
predictions/heldout table to those labels. This does not change S40's primary
320-event score or require another control fit. Generate S20 responses in
separate, reviewed blocks, not by reusing S40's training outcomes; equal
replication IDs do not make the cross-size comparison paired.

Apply the following five profiles to S20 for both families and B/R/I/RI.
Rater/item truths, exact anchor inputs, and declared `0:3` scale stay fixed.
For PCM, add the indicated step change to each item's own full step vector;
RSM applies it to the shared vector. All steps remain finite and sum to zero.

| Profile / suffix | Change from primary truth | Purpose and interpretation |
| --- | --- | --- |
| S20 | None | Smaller-information comparator to the existing S40; 8 new fit cells |
| S20-L | Subtract 4 logits from every person location | Rare upper endpoint (category 3); also changes location relative to the unchanged person prior |
| S20-H | Add 4 logits to every person location | Rare lower endpoint (category 0); the same prior-coordinate qualification applies |
| S20-G1 | Add `(8, -8, 0)` to full steps | Rare interior category 1; changes step truth relative to the unchanged step prior |
| S20-G2 | Add `(0, 8, -8)` to full steps | Rare interior category 2; does not represent a removed category |

The 4/8-logit perturbations are synthetic stress choices, not literature-derived
cutoffs or recommended priors. With category index k starting at zero,
`log(w_k) = k*eta - sum(step[1:k])`; G1/G2 subtract 8 only from the targeted
category's unnormalized log weight. Normalization changes every probability.
No ordered-step constraint is added: the package's current step map is
sum-to-zero, and disordered steps are not a change to the declared score labels.
These are finite, fitted-family truths with potentially strong prior influence,
not the separate rater-response misspecification mechanism. Within each profile,
anchor methods share the same training/heldout records. Across profiles, use
separate response blocks and do not interpret raw heldout-loss differences as
an isolated anchor effect when truth and outcome entropy differ.

For each category k, the fixed-truth independent-response DGP gives
`E[N_k] = sum_n p[n,k]` and `Pr(N_k=0) = exp(sum_n log1p(-p[n,k]))`.
The eight stressed family/profile combinations have expected targeted-category
counts 0.0163--0.0345 and zero-count probabilities 0.9660--0.9838 over 160 ratings.
These are rounded deterministic design calculations, not Monte Carlo results
or a requirement that every generated dataset omit the category. Retain every
dataset without redrawing, dropping categories, inserting dummy ratings, or
conditioning the primary roster on observed occupancy.

Record occupancy by category, item/category, and rater/category before fitting;
report zero-category strata descriptively alongside the full planned denominator.
Post-generation strata are not new unconditional calibration experiments.
Retain all-category log-probability scoring and report true versus predicted
category totals, so an aggregate log score alone does not stand in for rare-
category behavior. These point summaries do not establish threshold-interval
calibration, which is not a retained claim of this subset. Source inspection
finds `unused_interior_category` and `unobserved_declared_endpoint` warnings,
but `single_observed_category` is an error in `validate_design`. Such a
realization remains a planned case with pre-fit rejection and zero fit entries,
not a replacement draw or successful fit; other validation issues still apply.

Reuse of the standalone generator verified 12 deterministic family/design
combinations (S40 plus the five S20 profiles): 2,240 probability vectors matched
a separate 256-bit category-equation oracle within `1e-13`; probabilities were
positive and normalized, counts/targets matched, and G1/G2 changed only the
intended unnormalized weight. The initial one-off check stopped on a Julia
variable-scope error; its corrected check passed without any random draws.
That equation-only checkpoint did not include package compilation/scoring or
posterior recovery. The later [information/category integration](#information-and-category-support-integration)
below adds synthetic package checks, not fresh recovery evidence.

[Linacre (2003)](https://www.rasch.org/rmt/rmt172e.htm) distinguishes incidental
from structural zeroes; [Wilson (1991)](https://www.rasch.org/rmt/rmt51b.htm)
warns that down-coding a sample's unused categories changes the response
framework. Their proposed estimation remedies are not adopted here.
[Wind (2023)](https://doi.org/10.1177/00131644221116292)
(Zotero `TZSBP6N4`, metadata/abstract checked) motivates examining threshold
ordering/precision, but its PCM/GPCM study does not validate this MFRM design
or supply these perturbations. No new threshold-detection performance claim
is inferred from that abstract.

IDs are `<RSM|PCM>-<S20|S20-L|S20-H|S20-G1|S20-G2>-<B|R|I|RI>`:
10 new data cells and **40 new fit cells**, including the eight S20 controls.
The subtotal is `130 + 32 + 40 = 202`, before the prior/start and misfit
increments below and cross-backend decisions. The allocation alternatives below
still cover only the original 130; do not silently expand their budgets.
Dense/nested size interactions, larger populations, item-only empty-category
mechanisms, forced structural zeroes, and all-constant adversarial tables are
outside this increment. The existing deterministic boundary checks are not
fresh recovery evidence for these omitted domains. All six M1 decisions remain
open; integrate the new cells with the existing generator/scorer checks before
freeze review, including the prior/start and response/link-misfit scope below.

## M1 candidate prior and start subset

**Review candidate only; no fit, budget, or default-setting adoption.** Reuse
`MFRMPrior` and the current fit initialization helpers in `src/bayesian_fit.jl`.
Define `P(c) = MFRMPrior(person_sd=1.5c, rater_sd=c, item_sd=c, step_sd=c)`
for `c in {0.5, 1, 2}`. These are narrower/reference/wider zero-centered priors,
not intrinsically strong/weak information on every predictive quantity.
The scale grid already exists in the anchor conformance tests. Propose
`init=nothing, init_jitter=0.02` as the ordinary reference and jitter `0.5` as
one dispersed-start alternative, conditional on accepting an applicable backend
and adequate warmup. Both are non-truth starts; retaining the old pilot's small
jitter does not retain its truth/projection-centered initialization.

| Subset | Existing controls, reused without new responses | New fit cells and comparison |
| --- | --- | --- |
| Prior | RSM-S/PCM-S, each with B/R/I/RI and C-R(+0.8)/C-I(+0.8), at P(1) and reference start | 12 controls x P(0.5)/P(2) = **24**; within an anchor regime compare prior sensitivity; at each c compare C-R with R and C-I with I for same-constraint gauge sensitivity |
| Start | RSM-S/PCM-S with B/R/I/RI at P(1), reference start | 8 x jitter 0.5 = **8**; compare computational reliability and target summaries for the same posterior, not different statistical models |

Use existing data/anchor IDs with explicit prior/start method fields; do not
duplicate the P(1)/reference-start controls. Pair on the same saved training and
heldout records and the same prespecified replication subset. Give planned
start alternatives their own method identities and primary dispositions, not
success-selected retries. Changing c changes the target posterior; changing
jitter does not. Report the existing contrast/predictive losses and failure
denominators, retaining finite-MCMC uncertainty when interpreting start differences.
Use the same frozen sampler settings across these comparisons. This candidate
does not prove the reference start or either prior adequate.

The prior applies only to free coordinates: anchors have no density term.
For an event, its prior predictor has mean minus the fixed rater/item values
and variance `c^2 * (2.25 + 1[rater free] + 1[item free])`. For each four-category
step block, `(s1,s2,s3)=(z1,z2,-z1-z2)` with independent `zj ~ N(0,c^2)`;
the full-step covariance is `c^2 * [1 0 -1; 0 1 -1; -1 -1 2]`.
Thus this prior is not exchangeable across full steps. RSM shares the block
across items whereas PCM has independent item blocks. Before M1-04 acceptance,
use the existing prior-predictive facilities to inspect category proportions
and extreme forecasts under each retained anchored coordinate system. These
analytic moments are not that completed predictive check. Do not translate
prior centers implicitly or drop normalizing constants when comparing dimensions.
The bounded [prior-predictive audit](#prior-predictive-audit-before-choosing-scales)
below now supplies an initial forecast profile; substantive adequacy review is
still required before accepting a prior.

`_fit_initial_params(..., nothing)` returns the free-coordinate zero vector;
`_advancedhmc_initial` adds independent Normal(0, jitter^2) increments per chain.
AdvancedHMC/Turing consume the fit RNG for both starts and sampling; CmdStan
allocates chain seeds before drawing starts. Equal fit seeds do not establish
matched chain starts across backends or dimensions. The random-walk `:julia`
route does not forward `init_jitter` and records zero jitter: it cannot implement
this comparison as written. AdvancedHMC is a candidate, not an adopted primary
backend. A different choice requires an explicit compatible start design.
The two jitter levels bound the number of conditions, not the Gaussian support;
0.5 is not guaranteed to be overdispersed relative to the posterior. No clipping,
truth-based relocation, or repeated jitter draws until success is proposed.

[Gelman et al. (2020), Sections 2.4 and 3.1](https://arxiv.org/html/2011.01808v1)
(HTML sections read) distinguish prior-predictive implications from finite-run
initialization/adaptation problems. Zotero `LAA54HWF`, Gabry et al. (2019),
DOI `10.1111/rssa.12378`, was checked at metadata/abstract level for the broader
workflow context. Neither source validates these package-specific values.

Excluded from this increment, pending scope review: block-specific scale grids,
alternative prior families/centers, negative or joint gauge-shift-by-prior
interactions, prior/start crosses with information/category/link/misfit cells,
and all-backend start comparisons. The positive single-facet shifts are targeted
checks, not evidence for those omitted combinations. This adds **32 fit cells
and zero data-generating cells** to the 202-cell subtotal.

## M1 candidate response and link-misfit subset

**Synthetic robustness candidate, not another fitted family or nominal recovery
gate.** Retain original labels, truth, steps, and B/R/I/RI anchors. Reuse the
quadratic-category tilt equation in the old pilot's `condition_probabilities`,
but not its fitting-kernel-derived base probabilities, truth starts, or arithmetic
response seeds. The standalone recurrence supplies independent base p; for
`k in 0:3`, define `q[n,k] ∝ p[n,k] * exp(lambda[n]*(k-1.5)^2)`.
Use log weights and stable normalization in the eventual generator. Two signed
coefficients, `a = -0.35, +0.35`, retain the pilot's magnitude and add its
centrality counterpart; they are synthetic choices, not literature thresholds.

| Data-cell suffix | Nonzero lambda[n] = a | Fitted-family control / affected counts |
| --- | --- | --- |
| S-X(a) | Every R4 event in the original connected sparse design | Existing S, a=0; 80 affected and 240 unaffected events |
| N-C4-X(a) | R4 events only for the four common persons P19--P22 | Existing N-C4, a=0; 16 affected and 336 unaffected events, including 72 other R4 ratings |

For both families and both signs, fit B/R/I/RI: **8 new data-generating cells
and 32 fit cells**. At a=0 the existing controls are aliases, not new fits.
Within each data cell methods share training/heldout records; across a or
topology use separate response blocks, with no cross-DGP pairing assumed.
The two rows differ in topology, affected count, and ability composition: their
comparison does not isolate link placement or misfit strength. No additional
matched-dose control is claimed. Link-local misfit means a response-distribution
change on observed linking events, not broken identifiers or missing links.

For an affected event, the change to adjacent-category log odds is
`a*(2k-4)`, k=1,2,3, hence `(-2a,0,2a)`. A severity shift contributes a constant
over k instead. Comparing R4 against an unaffected rater on the same person/item
cancels person/item/step terms, so neither shared RSM nor item-specific PCM steps
can absorb this rater-specific difference. Such co-rated events exist in both
proposed designs. If every rater were tilted alike it could instead be a step
change; that is not this design. For a binary scale the centered quadratic is
constant and generates no misfit, so the present four-category condition matters.

Positive a multiplies the odds of an endpoint versus either interior category
by `exp(2a)` (about 2.014 for +0.35, 0.497 for -0.35). It need not preserve the
mean score at an asymmetric base distribution. Conditional responses remain
independent: this is not a local-dependence experiment. Fixed anchors still name
the baseline severity/difficulty components; they do not fit the extra response
mechanism. Report component-contrast distortion descriptively, not coverage of
a supposed true parameter of the misspecified fitted model or an uncomputed
pseudo-true projection. For predictive KL and heldout log loss, truth is **q**,
not the unperturbed p. Keep affected/unaffected and endpoint/interior summaries;
weight their stratum means by 80/240 or 16/336 for an all-event mean.
These are full training-event counts. In the existing `nested/base-320`
evaluation view, N-C4-X has **eight affected and 312 unaffected events**, not
16/336; direct enumeration checks both counts. The misfit integration below
uses predictive weights from its declared evaluation events, while
retaining the separate 352-event training exposure audit.

[Eckes and Jin (2021)](https://www.psychologie-aktuell.com/journale/psychological-test-and-assessment-modeling/currently-available/inhaltlesen/psychological-test-and-assessment-modeling-2021-1.html),
Zotero `FM7GEW7Y` (metadata/abstract checked; year/venue checked on the publisher's
listing), motivates distinguishing severity from centrality in four-category
writing assessments. Its Bayesian facets model is not claimed to be this
quadratic tilt; no equation-level equivalence or replication of its findings is
inferred from the abstract. Other magnitudes, affected raters, link counts/
locations, category/anchor-error interactions, and fitted model extensions remain
proposed exclusions requiring review, not established robustness domains.

The existing no-fit conformance file now checks the 12 prior-coordinate designs,
actual zero/jitter helper behavior, and induced step covariance. It also compares
4,032 deterministic probability vectors (two families x two designs x three
coefficients, including zero) against a separate 256-bit category-equation oracle,
with positivity, normalization, tilt odds, exposure counts, and a binary null
boundary. This tests equations/helpers, not an implemented misfit adapter,
durable attempt binding, or posterior recovery. No evaluation responses or fits
are generated by these checks; test seed 17 is only a helper replay fixture.
At that checkpoint the new testset passed all 16,247 assertions; the full focused
file passed 21,017 on Julia 1.12.5 with existing compiled modules, without a
Julia 1.10 or CI rerun. Later local verification is recorded below; these earlier
counts are historical checks.

The combined candidate count is **202 + 24 + 8 + 32 = 266 fit cells**.
The original 17,800/32,800/52,000 allocation alternatives are unchanged and still
exclude these additions. Stop adding combinations without a retained question:
next reconcile the proposed scope with M1-03/04 precision, sampler adequacy,
prior-predictive review, and an explicit resource envelope; complete the existing
generator/scorer and data/attempt bindings alongside this work. All six M1
decisions remain open and no fresh M2 evaluation is authorized.

## M1 scoring applicability and denominator draft

This is a bounded scoring design and check, not an implemented all-attempt
executor or an acceptance rule. [Morris et al. (2019)](https://doi.org/10.1002/sim.8086),
Section 5.1 and Table 6, pp. 2085--2086 (Zotero `PKQMUBH7`, previously retrieved
indexed full text rechecked), treat missing estimates as a performance outcome
and warn against assuming they are missing completely at random. This motivates
the separation below; the exact status scheme is package-specific.

Start with the planned dataset-by-method roster, not the set of files that
happened to finish. Within one phase/data cell, keep one primary disposition
per planned dataset/method, plus additional attempts under distinct attempt
IDs. Preserve the dataset/heldout IDs, settings, and failure reason; reject
duplicate attempt keys, unplanned IDs, and mismatched data or target definitions
before aggregation. Missing output is unresolved, never silently successful.

| Quantity | Counting rule |
| --- | --- |
| Planned | Every prespecified primary dataset/method, including unstarted, running, generation-failed, and unexpectedly structurally rejected cases |
| Fit entered | The fit call was actually entered; generation/preflight rejection does not count as a sampler attempt |
| Completed | A fit result was returned; timeout/exception is not completion, and completion does not imply valid diagnostics |
| Diagnostic-valid | Completed fits passing the frozen full diagnostic policy; missing diagnostics cannot pass |
| Metric-valid | Diagnostic-valid fits with an applicable, correctly aligned and valid target summary; this can differ by metric |
| Additional attempts | Report separately by original dataset/method and reason; they do not enlarge independent N or replace the primary disposition |

Report nested counts `metric-valid <= diagnostic-valid <= completed <=
fit-entered <= planned` for the **primary** attempt. Additional attempts have
their own workload denominator. Count statuses/reasons alongside these totals,
including pending work; do not equate every unresolved case with an observed
fit failure. If a sequential fallback strategy is later evaluated as a method,
freeze its full rule and report both initial-method and strategy performance.
Do not select whichever attempt happens to have the best recovery or prediction.

Applicability is structural and predeclared per cell/target. Both endpoints
fixed means interval coverage is N/A; one free endpoint remains an estimated
contrast. Zero empirical draw SD does **not** establish that a contrast is
fixed. Incompatible-anchor and response-misspecification cells retain
distortion/failure targets, not a nominal-coverage gate for excluded truth.
Known unsupported negative controls belong to a separate expected-rejection
panel. Unexpected rejection in a planned applicable cell remains in its
denominator. N/A targets are not unresolved coverage trials and must not be
sent to a positive-N binary summary with artificial zero-width intervals.

For one applicable target at fixed truth, let N be planned datasets, m be
primary metric-valid datasets, and c be covered intervals. Report all three:
conditional coverage `c/m` (missing if m=0), the joint operational rate
`c/N` (valid **and** covered), and extreme binary-completion scenarios
`[c/N, (c + N - m)/N]`. The joint rate is not nominal coverage. The last range
is neither a confidence interval nor evidence that a nonexistent interval has
a defined latent coverage outcome. It shows sensitivity to assigning unresolved
binary outcomes as all false/all true; it cannot establish calibrated recovery
when failures make the target unavailable. Report Monte Carlo uncertainty
separately. Fixed targets have no such range.

Reuse `_parameter_recovery_rows` for draw-wise contrasts and
`parameter_recovery_summary` on eligible rows. The latter's `n_parameters` is
the number of supplied rows, **not** the planned independent dataset count;
its `flag` comparing coverage to nominal is not the study acceptance gate.
Within one fixed target/method, errors `e = posterior_mean - truth` give
`bias = mean(e)`, `MSE = mean(e^2)`, and `RMSE = sqrt(MSE)` over m valid datasets.
Use `sd(e)/sqrt(m)` and `sd(e^2)/sqrt(m)` for bias/MSE MCSE, with corrected sample
SD and m>=2; otherwise MCSE is unavailable, not zero. These are across-dataset
errors, not posterior SDs or within-chain MCMC errors. Report empirical SD of
point estimates and root-mean posterior variance on the same subset if retained.
Do not count several contrasts from one dataset as independent observations.

The existing `_free_correlation_study_binary_summary` can supply the binary
counts/rates/extreme scenarios without importing its study protocol or gates.
Its Wilson records are labelled 95%; the smoke uses the corresponding normal
quantile, not a new selected coverage level or acceptance threshold. The
free-correlation scorer's bounded correlation-error machinery does **not**
transfer to unbounded MFRM contrasts or log losses. Without a justified bounded
metric/support assumption there is no finite worst-case upper bound for missing
log loss or squared contrast error; report unresolved/conditional status rather
than imputing zero or borrowing a correlation bound.

For paired differences or four-method interactions, join on the same
dataset **and heldout** IDs within the predeclared comparison subset. Form each
dataset-level difference first, then `mean(d)` and `sd(d)/sqrt(m)` on the common
finite, diagnostic-valid subset (m>=2 for MCSE). Never subtract separately
filtered marginal means, or use independent-method variances for shared data.
Report the common subset size and each method's missing/nonfinite/invalid counts.
An infinite log loss is a meaningful extended-real outcome when predicted mass
at the observed category is truly zero, not an ordinary missing finite loss.
A supplied Float64 probability array alone cannot distinguish structural zero
from underflow; retain that numerical qualification. Preserve the array score
and flag the all-planned comparison as unresolved or extended-real as
appropriate; a finite-subset MCSE must not hide it. Reject NaN/invalid probability
rows. Do not silently clip probabilities or cap losses.

For the declared point-predictive targets, use posterior-mean category
probabilities before the logarithm, not mean draw-wise log probabilities.
For KL regret, sum `p*(log(p)-log(q))` only where truth p>0; q=0 there gives
infinity, while p=0 contributes zero. The difference of logs avoids overflow
of the mathematically equivalent ratio. Heldout loss uses `-log(q[y])` on the
stored heldout responses, never the training scores. Keep event weights and
the 20/60/60/180 strata declared above.

The focused file now checks 50 assertions with hand-constructed draws/outcomes:
an eight-dataset plan has 6 fit entries, 5 completions, 4 diagnostic-valid fits,
3 scored intervals and 2 covered intervals. Thus conditional coverage is 2/3,
joint valid-and-covered rate is 2/8, and the extreme-completion range is
[2/8, 7/8]. A successful second attempt stays outside the primary summary.
Actual anchor designs check estimated, partially estimated, and fixed contrasts,
including a structurally estimated contrast with constant synthetic draws.
A four-method loss example retains two complete finite quartets with interaction
mean -1.5 and MCSE 0.5, while explicitly retaining one missing and one infinite
loss outside that subset. Memory-only mutations admitting retry rows to the
primary summary or inferring applicability from draw SD trigger 15 and 2
assertion failures, respectively, with no errors. That revision passed
3,958 assertions on Julia 1.10.8 and 1.12.5. These checks establish
arithmetic/applicability, not the full roster adapter or diagnostic policy.

### Predictive scoring boundaries checked

[Gneiting and Raftery (2007)](https://doi.org/10.1198/016214506000001437),
Section 3.1, Example 3, p. 363 (Zotero `B7CHD4RK`, indexed text checked),
connect the categorical logarithmic score with KL divergence. Their score is
maximized; this study minimizes negative log score and uses truth-to-prediction
KL. Section 2.3, p. 362, requires the same forecast situations for direct score
comparisons. These support the scoring definitions and paired event set, not
an anchor-calibration threshold.

Reuse `mgmfrm_predictive_recovery_score` for validated probability arrays;
its historical name does not make this array calculation model-specific.
One-hot **heldout** outcomes as its truth input give `KL(onehot(y) || q) =
-log(q[y])`; only this log-score field is the heldout loss. Its other fields
against realized outcomes are not known-truth probability recovery. Match
outcomes to declared `FacetData.category_levels`, not `score + 1`, and jointly
reorder labels and probability columns. Validate each draw before averaging;
an invalid draw is not repaired by a valid average. No clipping or implicit
renormalization is introduced.

The shared KL calculation now uses a difference of logs. For p=(0.5,0.5) and
q=(smallest positive Float64,1), the old ratio overflowed and returned infinity;
the corrected result matches a 256-bit oracle at about 371.52688878013066.
The existing scorer test adds 16 checks for this case, zero terms, invalid
truth/prediction rows, empty draws, and invalid draws with a valid mean.
Before the fix, three assertions failed without errors; after it, all 56 pass.

The 28 new M1 checks cover mean-before-log, category alignment/permutation,
unknown outcomes, zero support, and event-weighted versus equal-stratum means
(3.25 versus 2.5 in the synthetic example). A finite-parameter MFRM example
also produces underflowed zero probabilities but finite heldout log probabilities
(-3000 and -3003 across two draws). Existing `pointwise_loglikelihood` on the
heldout design and `_logmeanexp` recover the finite mixture loss without
clipping; the training responses instead score zero in this example.
`_logmeanexp` currently rejects nonfinite inputs, including structural -Inf.
That revision checked a finite-log heldout route, with 3,986 anchor checks
plus 56 scorer checks passing on both Julia versions. The implementation below
now extends the existing array scorer without changing those default inputs.

### All-category log input and integration

`mgmfrm_predictive_recovery_score(...; log_probabilities = true)` takes
**both** truth and prediction as normalized natural-log probabilities. This is
an optional argument on the existing research scorer, not a new export or model
family. The default probability input and result schema are unchanged. Input
rows must have finite nonpositive logs or -Inf, with total mass within the
declared probability tolerance; NaN, positive logs, `-Inf`-only rows, empty
draws, and invalid individual draws are rejected. Raw logits are not accepted.

The scorer reuses the shifted `_logsumexp` calculation for draw mixtures;
[Blanchard, Higham, and Higham (2021)](https://doi.org/10.1093/imanum/draa038),
Eq. 1.3 and its subsequent analysis, provide the numerical reference.
The mixture retains every draw in its denominator, including zero-mass draws;
a category with no mass in any draw stays -Inf. This extension does not alter
the shared `_logsumexp` or finite-only `_logmeanexp` contracts.

For a finite log-truth value `a` and log prediction `b`, the KL term uses
`sign(a-b)*exp(a + log(abs(a-b)))`, with an explicit zero-difference case.
This package-specific implementation avoids prematurely underflowing
`exp(a)` when the complete term is still representable. Structural truth zero
contributes zero; finite log truth with predicted -Inf still gives infinity,
even if exponentiating that truth would round to zero. An online mean preserves
both huge finite regrets and equal subnormal regrets without summing to infinity
or dividing every tiny term to zero. These are floating-point safeguards, not
exact-arithmetic or calibrated-recovery guarantees. Other probability and
expected-score metrics still use Float64 probabilities.

The 47 new scorer assertions cover ordinary/log agreement, support and input
boundaries, a 256-bit oracle for the approximately `3.67e-40` KL contribution
whose truth probability underflows, huge finite means, and subnormal means.
Memory-only mutations replacing the stable product by `exp(a)*(a-b)` or
dropping zero-mass draws from the denominator trigger two and one assertion
failures, respectively, without errors. The provisional divide-before-sum
implementation also failed the subnormal-mean check and was replaced.

The existing `linear_predictor_values` already returns all-category log
probabilities with observation/category/facet metadata. A bounded integration
check reorders those records, joins on row/category labels, and feeds their
logs directly to the scorer. It checks 24 scenarios: RSM/PCM, four combinations
of no/rater/item/joint declarations (the anchored facets are fully fixed in
this small panel), and moderate/negative-extreme/positive-extreme shifts.
Each has two synthetic parameter vectors, not fitted posterior draws.
All 216 assertions pass, including agreement with a separate 256-bit category
equation oracle where the probability-array route reports infinity.

That revision passed 4,202 anchor checks plus 103 scorer checks on Julia 1.10.8
and 1.12.5. The 24-scenario check now receives truth logs directly from the
standalone primitive below, without taking logs of rounded probabilities.
Reuse of the metadata-rich predictor inspection output is sufficient for this
check; measure its cost before any lean producer is justified. No fitted
posterior or evaluation responses are generated.

### Independent log-truth boundaries

The existing `_ld1_pcm_probabilities(...; log_probabilities = true)` now
returns normalized natural-log probabilities directly from its standalone
category recurrence. Its default probability calculation is unchanged.
[Blanchard et al. (2021)](https://doi.org/10.1093/imanum/draa038), Section 4,
Eq. 4.1 and Algorithm 4.1, motivate shifting by a maximum and using `log1p`
on the remaining exponential sum. Exclude exactly one maximum, including when
several categories tie. Subtract this small log normalizer from the shifted
weights, rather than taking logs after exponentiation. This preserves finite
log support even where the corresponding Float64 probability is zero, and
tiny negative log probabilities where the ordinary probability rounds to one.
Nonfinite locations or overflowed cumulative/shifted log weights are rejected
in log mode, not represented as structural zeros or silently clipped.

The 277 added checks cover 42 location/step combinations against a separate
512-bit category-equation oracle, normalization, adjacent log odds, tied modes,
non-centered steps, and invalid/overflow inputs. The empty-step case checks
only the primitive's existing one-category boundary, not a supported fitted
model. A stdlib-only child process verifies the log path's isolation. Generated
binary truth/prediction logs at locations -800/-1e308 give a finite positive
KL of approximately `3.67e-40`, matching the high-precision oracle; both ordinary
probability vectors round to `[1, 0]` and would incorrectly suggest zero regret.
Replacing a finite prediction log with structural -Inf instead gives infinity.
Memory-only mutations using `log(1 + tail)`, excluding every tied mode, or
taking logs after exponentiation trigger 12, 10, and 46 failures with no errors.

All 4,479 anchor, 103 scorer, and 2,168 existing LD checks pass on Julia 1.10.8
and 1.12.5. A separate memory-only comparison against `49871e3` confirms exact
equality of all raw outputs for the existing 22 LD smoke scenarios within each
environment, not cross-version bitwise portability. LD output schemas, response
RNG allocation, resource accounting, historical fixtures, and their recorded
source digests are unchanged; the raw LD table still stores ordinary probabilities.
That revision closed the independent log-probability primitive, not truth/state
persistence or the full attempt adapter. The next check addresses only the
labelled JSON/scoring boundary below; no freeze decision is closed.

### Labelled JSON roundtrip and scoring boundary

The private `_mfrm_anchor_log_probability_matrix` aligns one truth/draw record
set to declared event and category order, then reuses the normalized-log row
validator. It joins on exact string `(person, rater, item)` labels and integer
category labels, never a record's row number or inferred/sorted label order.
Every declared event/category must occur exactly once. Missing, duplicate,
unknown, non-normalized, or invalid-valued records are rejected. This panel
requires one event per facet tuple; repeated occasions need explicit event
identities before this adapter can be extended, not silent pooling.

Reuse `_write_json_record` and its existing `_json_export_value` conversion:
matrices have explicit nested rows, finite Float64 values stay numeric, and
nonfinite values use strings while missing values use JSON null. The adapter
decodes only `"-Inf"` in the numeric log-probability field; literal facet labels
such as `"-Inf"` and `"null"` are untouched. Other numeric strings, booleans, and
finite values that would overflow to -Inf are rejected. The legacy script
`write_json`/`write_canonical_json` behavior is unchanged; those writers alone
flatten matrices and collapse nonfinite numbers to null, so do not send these
raw scoring records through them. No shared writer or historical artifact is
migrated by this check.

The 52 new assertions use temporary files, asymmetric log-truth rows, Unicode
labels, negative/nonconsecutive categories, reversed records/events/categories,
and malformed inputs. Stored prediction records feed the existing scorer after
reload, retaining a tiny positive KL, an infinite loss, and a missing prediction
as different outcomes. A synthetic eight-case plan retains an absent result and
a successful retry: six primary fit entries, five completions, three scoreable
cases, and only two finite losses. At `fe80126` this verified the illustrated
join/count arithmetic; the identity checks below now replace its inline join.
Neither check validates diagnostic decisions or prediction/source binding.
The existing 24-scenario RSM/PCM integration also uses the new label adapter.
All 4,531 anchor and 103 scorer assertions pass on Julia 1.10.8 and 1.12.5.
Memory-only event-order and numeric-string coercion mistakes trigger three and
one assertion failures, respectively, without errors.

This is a checked representation/scoring path, not a frozen archive schema,
untrusted-JSON importer, or crash-safe create-new publisher. Source/environment
binding, labelled training/heldout tables with RNG checkpoints, stage reservation,
and the persistent all-attempt ledger remain required. The identity rejection
and bounded native replay checks below do not close those storage requirements.
Do not serialize RNG objects through the JSON fallback that
stringifies unknown types. All six freeze decisions, diagnostic policy,
thresholds, and independent review remain open. No new repository file, dependency, export,
MCMC run, retained fixture, or evaluation replication is added.

### Attempt identity join and native replay

The private `_mfrm_anchor_primary_attempts` validates exact nonempty string
`(dataset_id, heldout_id, method)` keys against the declared plan, rejects
duplicate plan keys, and checks every attempt's positive non-Boolean integer
number and unique full key. A retry requires a retained primary record, but
input order is irrelevant. Only attempt 1 is returned, in plan order, with
`nothing` for absent planned cases; the input keeps every retry unchanged.
No delimiter concatenation, success filtering, or retry replacement is used.
The existing eight-case JSON/scoring check now consumes this join. The 76
identity assertions also cover shared datasets across methods, reordered
records/plans, missing or malformed keys, unplanned records, orphan retries,
and duplicates with changed payloads. This checks identifiers, not whether
payloads actually contain the declared data, valid diagnostics, or authorized
settings. Separate phases need separately bound plans; the final roster and
its source/data fingerprints are still unfrozen.

The response smoke uses stdlib `serialize`/`deserialize` on its own fresh
temporary file, saving the Julia version, RNG engine, and all 16 existing
blocks with their states, uniforms, event keys, probabilities, and scores.
Reloaded blocks equal the originals and replay in reverse order in a fresh
stdlib-only process; the existing row/subset checks also use the reloaded
blocks. Four additional assertions bring that testset to 135. This is native
same-environment replay, not a portable labelled-data archive or a no-overwrite,
crash-safe publisher. [Julia's Serialization documentation](https://docs.julialang.org/en/v1/stdlib/Serialization/)
warns that compatibility can depend on type definitions/platform and that
deserialization does not validate malformed bytes. Only trusted self-produced
files are read here; no untrusted import or cross-version guarantee is added.

All 4,611 anchor and 103 scorer assertions pass on Julia 1.10.8 and 1.12.5.
Memory-only mutations that remove duplicate rejection or replace the primary
with a retry each trigger three assertion failures and no errors.
There is no new writer, controller, export, dependency, retained artifact,
fit, or evaluation replication. Durable labelled truth/data plus state and
source/environment binding, crash-safe stage reservation/publication, and
the persistent all-attempt ledger remain required before execution. M1-02,
M1-05, and all other freeze decisions remain open.

### Byte-bound labelled response restoration

The private `_mfrm_anchor_response_data(bytes, reference)` accepts a separately
trusted `(dataset_id, role, sha256)` reference and checks the SHA-256 of the
exact bytes it parses. The digest is lowercase 64-hex; role is `train` or
`heldout`. The JSON record contains only `dataset_id`, `role`, `category_levels`,
and `rows`; each row contains only string `person/rater/item` labels and an
integer `score`. IDs/roles must match, rows must be nonempty with unique facet
tuples, and the declared scale must be increasing consecutive integers. The
existing `FacetData` then checks scores against that scale and preserves row
order and unobserved declared categories. The existing log adapter shares the
same label check; its broader nonconsecutive category labels are unchanged.

JSON3's untyped path can round decimal tokens to integers, including a value
such as `1.0000000000000000001`. After required-field checks, its existing typed
reader decodes scores/categories directly as `Int`. Decimal/exponent tokens,
numeric strings, booleans, overflow, and out-of-scale scores are rejected;
representable integer tokens above Float64's exact range are retained. No
custom parser or change to general `FacetData`/JSON export behavior is added.

The 95 boundary checks cover wrong bytes, changed rows/scores/scales, role
swaps, malformed references/records, and numeric edge cases. All 16 existing
response blocks also pass through temporary labelled JSON files and back to
`FacetData`, adding 64 checks for labels, scores, and declared categories.
All 4,770 anchor and 103 scorer assertions pass on Julia 1.10.8 and 1.12.5;
memory-only SHA-bypass and untyped-decoding mutations trigger four and five
assertion failures, respectively, with no test errors.

This is byte identity relative to a trusted reference, not authentication,
semantic hashing, an untrusted-JSON importer, or proof that a fit consumed
those bytes. Whitespace/reordering changes require a new reference. Tests
create their references locally; a frozen plan must retain them independently
and bind truth, native state, source/environment, and every attempt to the
same data. Durable create-new publication, the persistent all-attempt ledger,
and all freeze decisions remain open. No dependency, export, retained fixture,
fit, or evaluation replication is added.

## M1-03/04 precision and execution decision proposal

**For review, not a frozen protocol or permission to run a probe.** The 266
candidate cells remain unchanged. Separate scientific tolerances, across-dataset
simulation precision, and within-fit MCMC precision; none substitutes for the
others. Practical bias/interval-width/probability/log-loss tolerances still need
the intended use and reviewer justification. In particular, the synthetic
0.2/0.8-logit anchor perturbations do not define acceptable estimation errors.

### Practical-acceptance decision brief

**User-specified aim, 2026-09-07 JST:** determine practically acceptable
conditions, not merely describe differences. The user also asked that resource
planning use current machine availability. These clarify the aim and planning
inputs; they do not adopt tolerances, a backend, an allocation or execution.
The user further requested support for diverse users and explicit use of Bayesian
uncertainty, with an all-score-1 rater as a concrete example. No universal target,
practical margin or decision loss is thereby selected. All six M1 decisions remain open.

| Decision | Recommendation for review | Still needed before acceptance |
| --- | --- | --- |
| Domain and targets | Judge explicitly retained RSM/PCM cells, using the existing estimated contrasts and predictive targets; retain the full 266-cell candidate roster while deciding which claims each cell supports | Intended use and priority among person, rater, item and prediction targets. A finite checked grid cannot establish a continuous safe-anchor region or a general real-world guarantee; fixed contrasts stay N/A and incompatible truths retain distortion/failure targets |
| Practical tolerances | Specify acceptable bias/error, predictive loss and operational failure separately, with uncertainty-based accept/reject/inconclusive decisions | Substantive margins, units, direction and coverage/width tradeoffs for each applicable target. Neither anchor perturbation sizes, nominal 90% intervals nor diagnostic thresholds supply these margins. A nonsignificant difference is not practical equivalence |
| Backend, prior and starts | Review the existing AdvancedHMC/ForwardDiff proposal first, preserving P(1), non-truth starts and declared prior/start alternatives | Adequacy under the selected configurations and exact source/environment identity. The route implements the proposed jitter; this is not a speed ranking or approval of the 1,000/1,000-draw settings. CmdStan remains conditional on an explicit comparison/primary-role decision |
| Replications and scope of assurance | Recalculate allocation from the accepted margins and error control; keep the existing 400/100 and uniform-400 totals as resource references only | Across-dataset loss/error SD references, missing-outcome policy and the family of claims. The 400/100 allocation was descriptive for sensitivity cells and is not automatically adequate for their practical acceptance |
| Execution readiness | Start with the bounded rehearsal proposal in the resource section, only after its launcher/recording/resource checks and separate approval | Retained pilot inputs/RNG, all-attempt accounting, enforceable time/memory/output stops and a reviewed launch. The quiet wrapper only controls displayed output; it is not a timeout or memory guard |

For a proposed performance measure, let A be its substantively justified
acceptable set and C its reviewed uncertainty set across simulated datasets.
Propose **accept if C is contained in A; reject if C and A are disjoint;
otherwise inconclusive**. For an upper-limited loss with margin t and interval
[L,U], this becomes U <= t, L > t, or inconclusive, respectively. C is not an
individual fit's posterior interval, and its construction/level is not selected
here. Missing diagnostics, inadequate MCMC precision, or unresolved failure
sensitivity cannot produce an acceptance. Unbounded missing log loss or squared
error has no finite worst-case completion bound without additional assumptions.
Apply the existing applicability/denominator rules before any such decision;
conditional valid-fit accuracy alone does not establish operational acceptability.

If simultaneous confidence bounds are chosen, predeclare the complete family
of asserted cell/target endpoints and error allocation. The existing M=16/266
zero-failure examples each count one binary endpoint per cell, not every
contrast, predictive target and diagnostic claim together. They are not a ready
whole-study acceptance rule. Predictive-score curvature and within-fit MCSE
remain unresolved where documented below; an unavailable precision check is
not a zero-error result.

Zotero `PKQMUBH7` metadata/abstract and indexed full-text Sections 5.1--5.3
were rechecked: failures must be examined and simulation repetitions chosen
for performance-measure precision. These principles support the separation
above, not our numerical margins or allocation.
[Morris, White and Crowther (2019)](https://doi.org/10.1002/sim.8086).
The [Stan diagnostic guidance](https://mc-stan.org/learn-stan/diagnostics-warnings.html)
was also rechecked; convergence/ESS screens do not replace precision for the
quantity of practical interest. No new fit or package-wide test ran for this brief.

#### Bayesian decisions for diverse users and constant-score raters

Keep one inferential core and distinguish user decisions, rather than inventing
a universal good/bad-rater cutoff or separate fitting engines. The following
uses are review directions, not implemented automated decisions:

| User need | Bayesian information to use | Boundary |
| --- | --- | --- |
| Rater training and quality monitoring | Observed category use/assignment overlap, severity-contrast posterior intervals, residual/fit summaries and prior sensitivity | A constant response pattern prompts inspection, not automatic exclusion, a claim of misconduct or an estimated probability that a rater is unreliable |
| Individual assessment or consequential decisions | Joint posterior draws for declared ability contrasts or a substantively calibrated cutoff, reporting threshold-crossing probabilities and expected decision loss | Cutoff, scale linkage and asymmetric error costs require the actual use case. An anchored coordinate has no estimated uncertainty; it cannot stand in for a confidently measured ability or rater effect |
| Research and model/design development | Recovery and failure denominators across datasets, within-fit MCSE, posterior predictive checks and anchor/prior sensitivity | Posterior concentration is not empirical calibration; a model reproducing a mean does not establish appropriate rating variation or a valid decision rule |

**Current all-score-1 behavior, inspected in source:**

- With at least two ratings, a one-category rater is reported by
  [`ordinal_response_pattern_audit`](../../src/ordinal_response_patterns.jl)
  and receives `:constant_rater_score_pattern` at warning severity in
  `validate_design`. Its observations are neither dropped nor reweighted.
  Other errors such as disconnectedness or rank deficiency can still prevent fitting.
- If the entire dataset uses only one observed category, the current validator
  returns the error `:single_observed_category`, even with a larger explicitly
  declared scale; canonical fit validation refuses that input. This is the
  package's support boundary, not a theorem that proper Bayesian priors cannot
  define a posterior for constant data.
- Declare the intended `category_levels`: score 1 is a floor on a 1:5 scale but
  an interior category on 0:3. The audit distinguishes these cases; the literal
  label 1 is not intrinsically an extreme score.
- The stable MFRM likelihood uses person minus rater minus item location and
  shared/item steps. It has no estimated rater-consistency or contamination
  weight. [`rater_diagnostics`](../../src/bayesian_fit.jl) retains category use,
  severity intervals and residual/infit/outfit summaries; generalized consistency
  is marked missing for MFRM. The guarded GMFRM has a separate consistency
  parameter, but its existence does not resolve severity/consistency confounding
  or justify automatic promotion for this study.
- Free identified MFRM coordinates have proper independent Normal priors with
  supplied scales, not learned hierarchical shrinkage. Mathematically, their
  bounded positive ordinal likelihood and proper prior give a proper posterior
  with finite moments; that does not establish data-driven identification,
  low prior sensitivity, good MCMC or correct model specification. A reference
  or hard-anchored rater is fixed, not estimated: its zero-width interval is a
  constraint, not evidence of reliable rating.

A constant rater may have seen a narrow performance range, used an extreme or
interior category, or behaved incompatibly with the model. Shared person/item
ratings, their observed range and the declared assignment design are needed to
interpret it. Zotero `WWBMEUVU` metadata/abstract supports sensitivity to the
rating design and rater-effect type; `IAMFRCSX` describes models with different
rater/task parameters. Neither abstract establishes an all-score-1 exclusion
rule or this package's recovery performance.
[Wind and Jones (2019)](https://doi.org/10.1111/jedm.12201),
[Uto and Ueno (2018)](https://doi.org/10.1016/j.heliyon.2018.e00622).

For a later targeted predictive check, a useful proposed statistic is the
largest within-rater category proportion: it is 1 for a constant rater. Compare
it with posterior-replicated ratings on the same assigned events, together
with severity/prior/assignment diagnostics. The current compact predictive
summary has rater means, not an integrated constant-pattern decision statistic;
do not present this proposal as an implemented check. Conditional posterior
probabilities of a declared contrast exceeding a practical margin are similarly
different from probabilities about an unmodeled unreliable-rater state. Any
threshold-crossing probability needs its own Monte Carlo precision assessment.

The unchanged `test/ordinal_response_patterns.jl` passed **20 assertions on
Julia 1.12.5** in this review (`quiet-command.08nrpu`); its explicit all-score-1
rater fixture and global-constant rejection exercise audit behavior without
fitting or RNG draws. Julia 1.10 and posterior recovery were not rerun. This
does not add a constant-rater recovery panel to the 266 candidate cells or
authorize dropping such realized datasets. Next scope the missing constant-rater
decision evidence within M1-01/03/05 before changing the study roster or claiming
practical acceptability.

### Pointwise precision and limits of claims

Propose 90% equal-tailed intervals for the existing estimated contrasts and
pointwise MCSE targets of 1.5 percentage points for coverage near 90%, and
2.5 points for an unknown binary failure rate. These are analyst-proposed
reporting-precision targets, not acceptable coverage deficits or adopted failure
ceilings. The existing replication helper yields the following references for
independent, fully observed datasets; conditional valid subsets use their actual
smaller denominators, without replacement sampling.

| Independent datasets | Coverage MCSE at 90% (percentage points) | Worst-case binary MCSE (percentage points) |
| --- | --- | --- |
| 100 | 3.00 | 5.00 |
| 400 | 1.50 | 2.50 |
| 900 | 1.00 | 1.67 |
| 2,500 | 0.60 | 1.00 |

At 400, both proposed pointwise precision targets hold algebraically, not
empirically for every outcome or jointly for all cells. Fixed-truth coverage of
a Bayesian credible interval is not guaranteed to equal its nominal level;
this is an operating-characteristic study, not prior-averaged simulation-based
calibration. Retain the existing applicability/failure envelopes. Without
accepted practical tolerances, report descriptive estimates and uncertainty,
not automatic allow/reject decisions or equivalence inferred from a nonsignificant
comparison. Continuous bias and paired-loss precision still require an external
or separately authorized pilot SD reference; the Bernoulli table cannot supply it.
[Morris et al. (2019)](https://onlinelibrary.wiley.com/doi/full/10.1002/sim.8086)
motivates performance-specific Monte Carlo error reporting; Zotero `PKQMUBH7`
metadata/abstract was refreshed, and the earlier full-text evidence remains
linked in the allocation draft below. The proposed numerical targets are ours.

Zero observed failures also needs a claim scope. At N=400 per cell, the exact
one-sided 95% marginal upper bound is 0.746%; a Bonferroni simultaneous bound
`1 - (0.05/M)^(1/N)` is 1.432% for M=16 primary cells and 2.122% for all M=266
cells. The union bound does not require independence between methods sharing
data; each marginal calculation still needs independent datasets and fully
observed Bernoulli statuses. To put this zero-failure upper bound below 1%
requires N=299, 574, or 854, respectively. These are illustrations, not an
adopted 1% gate or permission to sample until zero failures is obtained. A
pointwise statement must not be promoted to whole-package simultaneous assurance.

### Prior-predictive audit before choosing scales

The existing prior-draw and supplied-draw prediction paths were reused through
the small `mfrm_anchor_prior_profile` helper in the focused test. The audit uses
256 independent parameter draws for each of 36 configurations: both families,
B/R/I/RI/C-R(+0.8)/C-I(+0.8), and c=0.5/1/2 on the same 320 sparse event tuples.
Each call starts `MersenneTwister(17)`; scales within one design therefore share
standard-normal innovations. This prior-only coupling does not alter the study's
response RNG plan. The placeholder scores are not fitted or used to condition
these draws. No training/heldout outcomes, MCMC chains, or evaluation replications
are generated. It is a prior audit, not a new data-generating recovery condition.

For each parameter draw, average the conditional endpoint probability p0+p3
and the indicator `maximum(p) > 0.95` over events; then summarize over draws.
The latter is a descriptive near-deterministic-forecast marker, not acceptance
at a newly selected 95% cutoff. Ranges below span the 12 family/anchor settings
at each c, not confidence intervals or uncertainty envelopes.

| Prior multiplier c | Mean endpoint mass, range | Mean fraction of near-deterministic forecasts, range |
| --- | --- | --- |
| 0.5 | 60.0--68.7% | 0.58--6.71% |
| 1.0 | 68.1--73.0% | 14.78--21.29% |
| 2.0 | 73.9--76.6% | 42.15--44.83% |

MCSE is `sd(draw-level summary)/sqrt(256)`, not an SE over 81,920 independent
ratings: events share prior-drawn facet/step coordinates. Across all configurations,
the largest MCSE was 1.36 points for endpoint mass and 1.38 for the forecast
fraction. This bounded audit illustrates more concentrated conditional forecasts
under wider parameter priors; it does not show which prior is appropriate.
The prior mean expected score also shifts with anchor coordinates; for example,
RSM P(1) gives R 1.309 (MCSE 0.020) versus C-R(+0.8) 1.128 (0.020).
These are separate prior systems, not likelihood-gauge invariance tests.
The prior-predictive rationale follows the already-read
[Bayesian workflow, Section 2.4](https://arxiv.org/html/2011.01808v1).
Reviewer assessment against intended rating behavior remains open; do not tune
the priors to favorable future recovery outcomes or require stress truths to be
typical under the prior. The test retains four-draw replay/range checks per
configuration; 256 is the recorded audit size, not a universal precision rule.

### Provisional sampler and diagnostic handoff

For a later, separately budgeted adequacy/cost probe, propose the existing
AdvancedHMC path: four chains, 1,000 warmup and 1,000 retained draws **per chain**,
initial step size 0.03, target acceptance 0.9, maximum depth 10, diagonal metric,
ForwardDiff, and `init=nothing` with jitter 0.02 (0.5 only in the declared start
subset). Retain P(1) except for declared prior alternatives. These are finite
starting settings for review, not evidence of convergence, a chosen runtime cap,
or inherited approval from the 200/200-draw truth-start pilot. Keep adaptation
and chain order in provenance; four chains do not create four datasets.

| Check | Candidate policy and existing path |
| --- | --- |
| Convergence/computation | `diagnostics(...; rhat_threshold=1.01, ess_threshold=400, split_chains=true)` plus finite available metrics; use rank-normalized R-hat, bulk/tail ESS, and all retained chains; no dropping inconvenient chains |
| HMC warnings | Require zero post-warmup divergences/nonfinite log densities and complete all-chain E-BFMI with minimum at least 0.3; record depth hits separately. Requiring the package's `passed` also conservatively excludes depth hits; that is a policy choice, not proof that a depth hit biases inference |
| Estimand precision | Reuse `posterior_mcse` on chain-blocked derived-contrast draws with probabilities `(0.05,0.95)`; mean/endpoint MCSE must be available. Propose a budget of at most one tenth of the respective scientifically accepted tolerance; actual tolerances and this budget still need review |

[Stan's diagnostic guidance](https://mc-stan.org/learn-stan/diagnostics-warnings.html)
supports multiple chains, stringent R-hat/ESS review, checking divergences/BFMI,
and distinguishing tree-depth efficiency warnings from validity concerns. These
screens do not guarantee accuracy or justify our 1,000/1,000 iteration counts.
Package `summary.passed` alone is not an all-chain E-BFMI or estimand-MCSE gate.
Missing diagnostics cannot pass. The base `diagnostics`, all-chain HMC screen,
and derived-contrast diagnostics/MCSE are now recomputed inside the
[attempt-bound scorer](#attempt-bound-fit-object-scoring), using explicit
caller-supplied policy inputs. Their no-fit checks do not adopt the proposed
thresholds or settle cell-specific applicability and scientific precision.
No backend behavior or default is changed here.

Do not substitute rank-based bulk ESS into `posterior_sd/sqrt(ESS)` as the exact
mean MCSE. Likewise the retained KL uses the **posterior mean probability**:
`KL(q, mean_s p_s)` is not `mean_s KL(q,p_s)`. A mean-MCSE call on draw-wise KL
therefore checks the wrong functional. Before predictive-precision acceptance,
verify a chain-aware calculation for the actual nonlinear plug-in score (and
preserve cross-event covariance), or explicitly leave that precision claim
unresolved. Finite-MCMC mean/quantile helpers do not by themselves close it.

### Predictive-score linearization and binding checks

The private `_mfrm_anchor_log_score_delta_mcse` in
`src/mgmfrm_validation_scoring.jl` now supplies a **first-order review candidate**,
not a public API, convergence decision, or accepted precision criterion. It
reuses the validated log-probability scorer, draw averaging, and `posterior_mcse`.
For S chain-blocked draws, R equally weighted events, fixed truth q, and
`m[n,k] = mean_s p[s,n,k]`, the target and linearized sequence are

```
F(m) = sum_nk q[n,k] * (log(q[n,k]) - log(m[n,k])) / R
g[s] = -sum_nk q[n,k] * (p[s,n,k] / m[n,k] - 1) / R
```

Under a suitable joint Markov-chain CLT and a nondegenerate first derivative,
the mean-MCSE of g estimates the first-order MCSE of F(m). Aggregate events and
categories **within each draw before** estimating temporal variance, retaining
their shared-parameter covariance. Do not flatten events into extra draws or
sum event MCSEs as if independent. Contiguous equal-sized chains must retain
their true order and identity. One-hot q gives heldout log loss conditional on
the saved outcomes; this does not include across-dataset or new-outcome uncertainty.
[Stan's posterior-prediction equations](https://mc-stan.org/docs/stan-users-guide/posterior-prediction.html#computing-the-posterior-predictive-distribution)
support averaging probabilities before taking logs. The Jacobian covariance
formula and its degeneracy limitation follow
[Strimmer's multivariate delta-method notes, Section 3.2](https://strimmerlab.github.io/publications/lecture-notes/MATH38161/03-transformations.html#delta-method)
(relevant HTML section read); the KL gradient and implementation here are our
derivation and checks, not an MFRM validation result from those sources.

Terms use `expm1(log(p_s)-log(m))` and signed log-domain multiplication by q;
this avoids directly forming q/m and retains representable tiny contributions.
Structural truth zeros are skipped; zero predicted support with positive truth
keeps an infinite score and unavailable MCSE. Insufficient chains/draws or
unusable **mean** MCSE stays unavailable. The aggregate `posterior_mcse` row
can be unavailable solely because its unrelated SD-MCSE is missing; the
linearization consumes only its finite positive mean-MCSE. A balanced two-point
fixture exposed this distinction on Julia 1.10.8 (mean-MCSE about 6.98e-5,
SD-MCSE missing); the original whole-row gate discarded the usable target.
The general `posterior_mcse` contract is unchanged. Numerical cancellation of g (including
q=m) returns `first_order_degenerate`, **not MCSE=0**. The 64-epsilon check is
only a numerical guard; it does not detect every scientifically important
near-degenerate case. The Hessian has diagonal entries `q[n,k]/(R*m[n,k]^2)`;
curvature and finite-sample bias can matter even with a nonzero first-order MCSE.
Every result therefore retains `curvature_review_required`, convergence review,
and no precision/validation permission. Near-perfect prediction needs separate
second-order or otherwise justified error assessment before a precision claim.

Synthetic checks compare g with independent central differences of the actual
score, verify event duplication/unequal-count weighting and whole-chain/category
reordering, and keep finite one-hot log loss below ordinary probability
underflow. They also cover q=m and cross-event cancellation away from q=m:
a zero linear term does not make the nonlinear score constant. These tests
check implementation/algebra, not repeated-run calibration of the MCSE estimator.
Do not use arbitrary same-index draws from different fits as paired MCMC draws;
cross-method Monte Carlo covariance requires its own declared sampler coupling,
separate from the study's shared-data pairing.

#### Exact curvature stress check

The added no-fit oracle sums the count distribution of four independent,
stationary two-state chains. Each draw's forecast is either (0.3, 0.7) or
(0.7, 0.3); the chain switches state with probability f. The 18 cases cross
40/160 draws per chain, f=0.1/0.5/0.9 (lag-one correlation 0.8/0/-0.8), and
truth q=(0.5+d, 0.5-d) with d=0/0.001/0.2. Independent chain boundaries reset
to stationary probabilities. The count recurrence is checked against all 256
paths for two four-draw chains, the IID binomial distribution, symmetry, and
the finite-chain autocovariance sum. No fits or new study cells are involved.

Let e be the first category's pooled forecast mean minus 0.5. Then

```
F(0.5+e) - F(0.5) = -(0.5+d)*log1p(2e) - (0.5-d)*log1p(-2e)
                    = -4*d*e + 2*e^2 + remainder
v = E[e^2]; u = E[e^4]                  # exact count-distribution moments
first-order SD = 4*abs(d)*sqrt(v)
quadratic bias = 2*v
quadratic SD = sqrt(16*d^2*v + 4*(u-v^2))
```

Symmetry makes the linear/quadratic covariance zero in this fixture. These
are finite-sum results (Float64 arithmetic), not estimated MCSEs from a sampled
trajectory. For 40 draws per chain (160 total), natural-log score units are:

| Lag-one correlation | d | Exact bias | Exact centered SD | First-order SD at true mean | Quadratic SD |
| --- | --- | --- | --- | --- | --- |
| 0 | 0 | 0.00050075 | 0.00070700 | 0 | 0.00070489 |
| 0 | 0.001 | 0.00050075 | 0.00070983 | 0.000063246 | 0.00070773 |
| 0 | 0.2 | 0.00050075 | 0.012681 | 0.012649 | 0.012669 |
| 0.8 | 0.001 | 0.0040467 | 0.0055606 | 0.00017889 | 0.0054387 |
| -0.8 | 0.001 | 0.000061739 | 0.000090974 | 0.000022222 | 0.000090941 |

Even with exact input variance, the first-order SD is about 11.2 times smaller
than the exact SD in the near-stationary IID case, and about 31.1 times smaller
with positive autocorrelation. This is an approximation failure, not a measured
bias of the package's temporal-variance estimator. At d=0 in the IID case,
quadrupling the draws reduces both bias and SD by approximately four, not two;
the limiting scale is second-order. Bias is reported separately: centered SD
does not include it, and is not the root-mean-square error about F(0.5).
[STAT 205B, Theorem 3.2](https://bookdown.org/jkang37/stat205b-notes/lecture03.html)
states the second-order delta limit (relevant theorem read). The KL formulas
and finite-state oracle above are our derivation, not that source's example.
The library's [Morris, White and Crowther (2019)](https://onlinelibrary.wiley.com/doi/10.1002/sim.8086)
(Zotero `PKQMUBH7`, metadata/abstract rechecked) supports separating estimands
and performance measures; it is not a source for these KL formulas.

Crucially, q equal to the **population** forecast mean need not equal the
**sample** mean. Separate shuffled, fixed-count fixtures give an available
`first_order_candidate` both near the population stationary point and at it
with a slightly unbalanced sample. Both must keep curvature/convergence review
and no precision permission. The numerical cancellation guard cannot be a
near-degeneracy gate. The quadratic approximation improves all 18 toy cases,
but uses known count moments: this does not validate a replacement posterior
MCSE, normal confidence interval, or a generic chi-square calibration. Do not
substitute a scalar ESS for the joint covariance or assume batch-level KL has
the bias/variance of the full-mean KL. A usable curvature-aware assessment
remains open; adding a universal second-order estimator or threshold is deferred.

#### Paired predictive-loss contract and error decomposition

This is a checked mathematical proposal, **not an accepted precision gate**.
The descriptive consumer below now implements the point-loss portion.
Reuse each primary report's `truth_score.estimate`
or `heldout_score.estimate`, never a parameter-recovery eligibility flag. A
misspecified model can have a meaningful predictive loss against q while its
parameter recovery is inapplicable. Keep the two score kinds separate, preserve
the declared event weights, and compare only the same dataset/heldout, response
bytes, q, sources, and evaluation panel. Apply the existing primary-only join;
retries must not replace failed primaries. The recovery pairer's shared-reference
checks are the pattern to reuse, not permission to treat its target/precision
screen as a predictive screen.

For a declared balanced pair or B/R/I/RI interaction with weights w, form the
difference **within each independent data replication**, then average:

```
d_hat[i] = sum_j w[j] * L_hat[i,j]
mean_difference = mean_i d_hat[i]
across_replication_SE = sd_i(d_hat[i]) / sqrt(n)   # n >= 2
```

This retains the same-data cross-method covariance, equivalently
`w' * sample_covariance(L_hat) * w / n` for the squared SE. It is not the sum of
marginal method variances. Lower loss is better; reversing all weights reverses
the mean but not its SE. For shared q and identical events/weights, q's entropy
cancels in a balanced contrast, so KL-regret and q-cross-entropy differences
agree. This does not equate q-expected loss with realized heldout loss or justify
comparisons across DGPs/panels. These are applications of the covariance rule in
[Strimmer, Sections 3.1--3.2](https://strimmerlab.github.io/publications/lecture-notes/MATH38161/03-transformations.html#delta-method)
(relevant sections reread), not a new statistical procedure.

Distinguish data variation, finite-sampler variance, and nonlinear bias. Let D
include the saved training/evaluation outcomes and truth, let `d(D)` use exact
posterior predictive means, and define the conditional finite-MC bias/variance
`b(D) = E_MC[d_hat | D] - d(D)` and `v(D) = Var_MC(d_hat | D)`. Here b includes
any sampler bias, not only curvature. With finite second moments, expanding
the conditional squared deviations gives

```
Var_D,MC(d_hat) = Var_D(d(D) + b(D)) + E_D[v(D)]
E_MC[(d_hat - d(D))^2 | D] = v(D) + b(D)^2
```

Consequently the across-replication SE of independent finite-MC results already
includes sampler variation: do **not** add `sum_i v(D_i)/n^2` to its square a
second time. Nor does that SE measure or remove `E_D[b(D)]`. Independent draws
across data replications and the declared common-subset selection rule are
assumptions, not facts supplied by an ID or seed label. With diagnostic/precision
exclusions, label the summary conditional on that common subset and retain all
planned denominators and reasons. Applying the decomposition after selection
also requires conditioning its expectations/variances on joint eligibility;
selection can change both the target and covariance. With n=0 the mean is
unavailable; with n<2 the SE is unavailable. Infinite losses and `Inf-Inf` remain explicit unresolved
comparisons; no clipping, zero replacement, or finite failure envelope for an
unbounded signed log-loss difference is justified here.

For **fixed D**, first-order propagation instead needs the covariance matrix of
the methods' MC errors. Only under declared conditional sampler independence
does the candidate variance reduce to `sum_j w[j]^2 * mcse[j]^2`; different draw
counts are allowed. Shared data does not establish this independence or a joint
sampler coupling. Arbitrary same-index influence subtraction changes if one
fit's whole chains are reordered, even though each marginal loss and MCSE stays
unchanged. Without a justified coupling/independence declaration, leave the
combined within-fit MCSE unavailable. Even under independence, marginal
first-order degeneracy/unavailability must not become zero; curvature and
convergence review remain required. Method-specific nonlinear biases generally
do not cancel in a pair or interaction. The formulas above are our derivation.
[Morris, White and Crowther (2019), Sections 3.4 and 5.1--5.2, Table 6](https://doi.org/10.1002/sim.8086)
supports distinguishing performance targets, simulation uncertainty, and
nonconvergence; Zotero item `PKQMUBH7` was found and those indexed full-text
sections reread. That paper does not supply this predictive MCSE or accept our
failure/precision policy.

The runnable check is nested in `M1 predictive-score curvature oracle (no fits)`
in `test/mfrm_anchor_generator_crosscheck.jl`, reusing its count recurrence and
the existing scorer. For each of three toy data contexts, four conditionally
independent methods have two stationary chains, 2/4/2/4 draws per chain and
switching probabilities 0.1/0.5/0.9/0.5. All **2,025 joint count outcomes** are
summed, separately for q-expected and one-hot heldout loss. Four oriented pairs
and the interaction check entropy cancellation, exact conditional variance,
bias/MSE decomposition, total variance, and across-data covariance. A separate
160-draw fixture checks the whole-chain-reordering counterexample and retained
review flags. These add **269 assertions**, not study cells, sampled fits, or
MCSE calibration evidence. Tiny draw counts belong only to the finite oracle;
they are not a proposed study allocation.

The earlier mathematical-proposal verification on Julia **1.10.8 and 1.12.5** passed **24,691 assertions per
version** across 20 top-level testsets: 24,588 anchor checks plus 103 existing
predictive/decision checks. This scoped run used Julia's `include(mapexpr, path)`
to omit only the unchanged `M1/M2 complete candidate roster and paired controls
(no fits)` testset; the exact single omission was asserted and printed. All
other anchor testsets ran, including the expanded 360-assertion curvature oracle
and the bound-report/recovery consumers. The earlier 266-cell full-roster
69,128-assertion receipts remain historical, **not a fresh full-suite pass for
this edit**. Both scoped runs preserved all 186 exports; the quiet wrapper's
six checks, three protected historical bodies, six open M1 decisions, runtime
hold, 59 local links / 31 targets, and `git diff --check` also passed. Only the
test and study/roadmap documents changed in this increment; no production code,
dependency, precision gate, real fit, benchmark, or CI dispatch was added.

#### Descriptive paired predictive report consumer

The private `_mfrm_anchor_paired_predictive(groups; comparison, score)` consumes
the existing reports without fitting or recomputing predictions. Each method
group supplies only `plan`, `attempts`, and separately retained `attempt_hashes`;
extra recovery-group fields are not used. Select `score = :truth_score` or
`:heldout_score` explicitly. Two/four distinct methods have the existing balanced
+1/-1 comparison weights; their planned dataset **and** heldout rosters must match.

Recovery and predictive consumers now share `_mfrm_anchor_checked_primary` for
the existing plan, attempt/digest, reason, and primary-reference checks. Both
pairers share the comparison and response/truth/source/panel checks. This is
extraction of existing integrity guards, not another ledger or schema framework.
The predictive consumer also checks matching equal-event report scopes and the
selected score's numeric fields. As before, retained hashes bind trusted caller
content, not producer honesty or complete source/RNG/execution provenance; this
is not an untrusted report importer or a replay of the original bytes/fit.

Each planned primary retains its reported disposition, failure reason, point
loss, score status, reported marginal MCSE, and HMC/global diagnostic indicators.
A missing reference prevents inclusion even if the point loss is finite. Missing
attempts and nonfinite losses remain explicit. Retries are integrity-checked and
counted but never substitute for a primary. Shared-data mismatches reject even
on scored rows that are unbound or have nonfinite losses.

`n_common_finite` counts only identities with bound finite losses from every
compared method and a finite weighted difference. Their mean and corrected
sample-SD/sqrt(n) are reported as `mean_difference` and `across_replication_se`;
zero/singleton subsets retain unavailable mean/SE as specified above. A finite
input overflow in the difference or aggregate is flagged `nonfinite_comparison`,
not accepted silently. Method counts preserve planned, reported/scored-primary,
point-available, additional-attempt, and unavailable-reason totals. Raw rows and
the input plans/digests remain in the output for audit.

This selection is explicitly `bound_finite_primary`, **not diagnostic or
precision eligibility**. Diagnostic warnings, missing/degenerate first-order
MCSE, misspecification, unresolved parameter recovery, or an absent coordinate
cell declaration do not erase a finite predictive point loss. Coordinate truth
declarations, where present, must still match across paired reports. The result
keeps `diagnostic_selection_applied = false`, `precision_status = :unresolved`,
`combined_within_fit_mcse = missing`, curvature/convergence review, unavailable
lifecycle counts, and `validation_claim_allowed = false`. No sampler independence,
coupling, practical tolerance, or precision acceptance is defaulted.

The synthetic bound-report checks reuse the existing B/R/I/RI fixtures for both
score kinds, four-way arithmetic, sign/order invariance, retry exclusion,
zero/singleton subsets, retained diagnostic warnings, nonfinite arithmetic, and
hash/reference/roster/score-field mutations. Parameter recovery's two-eligible
example has four descriptive finite predictive pairs: the names deliberately
prevent confusing these different subsets. This consumer-only checkpoint did
not cover whole-candidate predictive integration and is not evidence of
predictive performance.
The initial mutation check failed inside the test helper because a concretely
typed report vector could not retain a `missing` MCSE; the helper now preserves
variant field types with the existing `NamedTuple` vector pattern. That fixture
error was corrected without changing the consumer's precision rules.

At the consumer-only checkpoint, Julia **1.10.8 and 1.12.5** passed **24,824 assertions per version**
across 20 top-level testsets (24,721 anchor + 103 predictive/decision), including
1,407 bound-report consumer assertions. This increment adds 133 checks. All
anchor testsets except the existing 266-cell roster ran; the exact single
omission was asserted and printed. This covers the extracted guards and both
consumers, but is **not a full-roster rerun or CI certificate**. All 186 exports,
the quiet wrapper's six cases, three protected historical bodies, six open M1
decisions, runtime hold, 59 local links / 31 targets, and whitespace checks were
preserved. No inference kernel, dependency, scientific fit, evaluation seed,
cost probe, benchmark, or CI dispatch changed or ran.

#### Whole-roster predictive pairing and secondary views

The existing no-fit candidate test now routes its saved primary reports through
`_mfrm_anchor_paired_predictive`. No prediction or fit is rerun for aggregation,
and no production source, dependency, or public API changes in this increment.
The 1,710 recovery comparison-target cases represent **342 distinct method
comparisons**; predictive aggregation runs once per comparison/score kind, not
once per parameter target. The check verifies **684 primary summaries** covering
every one of the 266 candidate methods for both truth and heldout loss.

The already-scored secondary reports are also reused: eight S40 common-person
views yield 20 comparison/score summaries, and 64 affected/unaffected misfit
views yield 160, for **180 secondary summaries** and **864 in total**. They are
not new cells, datasets, or fits. Each view replaces only the scored report and
its retained reference/content digests in a separate in-memory comparison input;
the original method/dataset/heldout/attempt identities and other planned
dispositions stay intact. Full and subset reports must not be mixed inside one
comparison merely because their attempt IDs agree.

Each summary is checked against the signed sum of its selected reports' point
losses. This tests the join/arithmetic, not an independent accuracy proof for
every posterior forecast; the earlier generator and per-event scoring oracles
remain separate. There is one finite synthetic data replication per comparison,
so across-replication SE remains unavailable, never zero. Missing primaries,
information-profile structural rejections, and misfit/start-profile failures
retain the same planned denominators and reasons in every view. Fixed or
distortion-only parameter targets do not suppress finite predictive loss.

For each misfit pair/interaction, the affected and unaffected loss differences
reconstruct the full-panel difference using their event counts, including the
nested 8/312 and sparse 80/240 partitions. No MCSEs are averaged or added in this
identity. Negative controls reject mixed full/subset evidence and cross-profile
link, information, and misfit comparisons. Input hashes are checked before and
after aggregation; uniqueness and method coverage counters prevent duplicate
parameter-level counting or silently omitted candidate methods. Profile progress
lines go only to the quiet wrapper's retained log, not the success display.

On **2026-09-07 JST**, the full local **Julia 1.10.8 and 1.12.5** runs each
passed **87,324 assertions** across 21 top-level testsets: 87,221 anchor + 103 existing
predictive/decision scorer assertions, including **62,500** in the complete
candidate-roster testset. The roster increment adds **17,794** assertions and
verifies all **864** summaries, **266** methods, **30**
data blocks, and **1,710** recovery comparison-target cases without omitting the
heavy roster. Both versions' testset counts match, and the exact **186** public
bindings are preserved. These are local no-fit regressions, not a full-package
CI certificate or evidence of posterior performance.

The quiet wrapper's six cases, three protected historical bodies, six open M1
decisions, runtime release hold, 59 local links / 31 targets, and whitespace
checks passed or remained preserved. No production source, dependency, public
API, scientific fit, evaluation seed, cost probe, benchmark, or CI dispatch
changed or ran in this increment.

This completes a connection in the synthetic scoring test, not generation-to-fit
execution, posterior performance assessment, or an accepted precision policy.
The following increment checks source/environment binding using the existing
`_evidence_file_sha256` and `_evidence_manifest_path` helpers in
`src/evidence_metadata.jl` and the retained `docs/internal/code-load-boundary.md`
inventory. At that checkpoint the scorer verified every supplied `source_files`
entry, but did not require a complete source roster or a Julia-appropriate Manifest;
the candidate fixture's eight-file map is not complete execution provenance.
Choose the smallest no-fit missing/changed-file and environment-binding check,
not another inventory framework. The separate free-correlation study already
binds environment, sources, generation, and samples, but its fixed source roster,
seed plan, and execution schema are specific to that deferred program and must
not be adopted as anchor-study decisions.

Saved response bytes and fit/report hashes also do not establish the actual
root/state allocation, fit-entered/completed evidence, or reviewed sampler
settings required by M1-02/04. Keep these gaps explicit; do not create a new
ledger/executor or silently allocate evaluation seeds. Curvature-aware precision
and independent policy review remain open; all six M1 decisions stay open and
fresh M2 evaluation remains zero.

#### Native Manifest resolution and source-coverage boundary

The source/environment review found a concrete error in the shared metadata
helper before adding a coverage gate. In constructed environments, both Julia
1.10.8 and 1.12.5 reproduced three mismatches: the old helper selected an
unsupported major-only `Manifest-v1.toml`, ignored `JuliaManifest.toml`, or
ignored an explicit project `manifest` path. A valid SHA-256 of the wrong file
is not evidence of the resolved environment. Julia's
[code-loading rules](https://docs.julialang.org/en/v1/manual/code-loading/#Project-environments)
describe the alternative and major/minor-specific filenames; the installed
loaders were also read directly for exact precedence and project resolution.

`_evidence_manifest_path` now takes the actual project file and delegates to
`Base.project_file_manifest_path`, instead of guessing filenames from a directory
and a supplied version. Its one production caller, `_evidence_project_hashes`,
passes the active project. The existing optional-probe handling records malformed
project resolution as unavailable at `manifest_resolve`, without leaking raw
errors or turning optional metadata collection into a fitting failure. Public
metadata keys and default path redaction are unchanged. No new dependency,
execution schema, source collector, or export is introduced.

The existing metadata tests cover all 32 project-name/manifest-presence
combinations on these runtimes, unsupported-name decoys, relative/absolute
explicit paths, changed/missing files, working-directory invariance, malformed
projects, and version-dependent workspace resolution. Temporary active-project
changes are restored in `finally`. A single existing synthetic anchor report
also retains the resolved Project/Manifest digests through `source_files`;
altered retained digests are rejected without changing either point loss or
granting a validation claim.

On **2026-09-07 JST**, scoped regression passed **25,235 assertions per version**
on Julia **1.10.8 and 1.12.5**, with identical counts across 22 top-level testsets:
24,731 anchor, 103 predictive/decision scorer, and 401 metadata assertions. The
increment adds 380 Manifest checks and ten bound-report checks; the other 21
metadata checks already existed. The two adjusted legacy Manifest assertions
in `test/runtests.jl` also passed separately without executing that fitting
runner. Both scoped runs asserted and printed the single omission of the
unchanged heavy 266-cell roster; its preceding 87,324-assertion full receipt
above is historical, not a rerun on this revision. All 186 public bindings,
the quiet wrapper's six cases, three protected historical bodies, six open M1
decisions, runtime hold, 59 local links / 31 targets, and whitespace checks
passed or remained preserved.

This fixes which file is recorded, not whether its dependencies were actually
loaded or its environment is scientifically accepted. A Manifest's
[`julia_version` records its creation version](https://pkgdocs.julialang.org/v1/toml-files/#Manifest.toml-entries);
equality with the current runtime is not a new acceptance rule here. The current
static source inventory still has 35 direct module includes plus its entry
(36 Julia files), with three optional Stan files. The scorer checks each supplied
file, but at this checkpoint did not reject omission of a required source; the
following increment adds a caller-retained declaration and coverage check.
Actual RNG allocation, fit-entry/completion evidence, settings, and independent
review remain open.
No new scientific fit, evaluation seed, cost probe, benchmark, or CI dispatch is
authorized. The constructed mismatch does not explain M0's historical +23.4%
trigger or close its release hold; all six M1 decisions remain open and M2 stays
at zero fresh evaluation replications.

#### Declared required-source coverage

The private scoring reference now accepts optional `required_source_paths`,
retained separately from the supplied `source_files` digest map. A declaration
must be a nonempty tuple/vector of unique, lexically normalized absolute paths;
every declared path must occur in the map. All supplied files, including extras,
still undergo the existing SHA-256 check. Missing/`nothing` declarations remain
descriptive-only with `source_coverage.status=:undeclared`; successful declared
coverage is `:declared_roster_covered`, never scientific or execution acceptance.
The existing review-required and no-validation-claim flags stay unchanged.

Both paired consumers reuse the same declaration check and compare canonical
path sets, so reordered declarations agree but differing sets or a declared /
undeclared mismatch reject. The original reference remains unmodified and hash-bound;
recomputing a report hash after dropping its roster does not satisfy the
separately retained planned reference digest. A caller must retain that plan
and roster independently: deriving the roster from the submitted map would
reintroduce the original omission problem.

One existing synthetic fixture retains the current 36 Julia sources, three
optional Stan sources, resolved Project/Manifest, and its own test file. It
removes each of those 42 digest entries in turn, exercises malformed and absent
declarations, checks extra-file digests, paired-scope mismatches (including
excluded rows), reference binding, and input immutability. This conservative
test snapshot is not an approved generation-to-fit execution roster, a record
of loaded dependencies, or an RNG/lifecycle receipt. No new collector, ledger,
dependency, export, sampler, or evaluation is introduced.

On **2026-09-07 JST**, scoped regression passed **25,317 assertions per version**
on Julia **1.10.8 and 1.12.5**, with matching 22-testset receipts: 24,813 anchor,
103 predictive/decision scorer, and 401 metadata assertions. The increment adds
82 checks; the attempt-bound testset now has 1,499. Both runs explicitly skipped
the heavy 266-cell roster, so the earlier 87,324-assertion full receipt remains
historical. All 186 public bindings, the quiet wrapper's six cases, protected
historical bodies, open decision/hold checks, local links, and whitespace checks
passed or remained preserved. No scientific fit, cost probe, benchmark, or CI ran.

The following review checks the candidate execution path and the actual RNG
allocation and fit-entry/completion evidence required by M1-02/04 against existing metadata.
Do not substitute another local receipt for independent policy review or
silently adopt the test snapshot as the production declaration. M0's +23.4%
runtime hold, all six open M1 decisions, and zero fresh M2 replications remain.

#### RNG ownership and lifecycle evidence boundary

The source review traces minimal MFRM `fit` through `_fit_rng`, initialization,
all four backends, `fit_metadata`, and the anchor scoring/primary consumers.
These existing pieces establish different facts; none supplies a durable
invocation history by itself.

| Existing boundary | What is available | What must not be inferred |
| --- | --- | --- |
| Response replay smoke in `test/mfrm_anchor_generator_crosscheck.jl` | Saved test-only block states and labelled data; replay uses copies | A production stage reservation, accepted root/state allocation, or independent sampler streams |
| `_fit_rng` in [bayesian_fit.jl](../../src/bayesian_fit.jl) | Explicit `seed` creates a local `MersenneTwister`; no seed returns the supplied object with `seed=missing, replayable=false` | Unseeded metadata does not identify its state. Passing the live response allocator to fitting would let fitting advance it |
| Backend controls and `MFRMFit` | Seed/algorithm/replay policy and sampler settings; CmdStan also records derived chain seeds | The input `init` vector, each jittered start, and entry/completion events are not stored in `MFRMFit`. `replayable=true` alone is not complete execution replay |
| Fit hash and primary summaries in [mgmfrm_validation_scoring.jl](../../src/mgmfrm_validation_scoring.jl) | Recorded RNG controls are hash-bound; original primaries and retries remain distinct | A constructed object can be scored without any fit call. `status=:scored` is not invocation evidence; `lifecycle_counts_available=false` remains correct |

AdvancedHMC/Turing share one fit RNG between jitter and successive chains;
CmdStan allocates chain seeds before jitter, as documented in the RNG draft.
The new helper-only check verifies owned versus borrowed RNGs, unchanged
response checkpoints under explicit seeding, equal unseeded metadata despite
different states, and non-mutating rejection of invalid seed inputs. One
existing fabricated fit additionally verifies that changing only recorded seed,
algorithm, replay policy, or chain-seed metadata invalidates its retained fit
hash. The fabricated report still grants no validation claim. These checks do
not run a sampler or establish cross-version trajectories or independence.

The historical [anchor pilot](../../scripts/run_mfrm_anchor_recovery_pilot.jl)
returns a row only after fitting and scoring, uses truth-derived initial values,
and uses its old seed arithmetic; it is not the new all-attempt execution path.
The [LD1 attempt archive](../../scripts/local_dependence_pilot_attempt_archive.jl)
exposes create-new publication and attempt seals, but binds LD1-specific plan
and execution fields. Do not copy those schemas or add a generic executor now.

On **2026-09-07 JST**, scoped regression passed **25,345 assertions per version**
on Julia **1.10.8 and 1.12.5**, with matching 23-testset receipts: 24,841 anchor,
103 predictive/decision scorer, and 401 metadata assertions. The 28 additions
are 17 ownership checks and 11 fit-binding checks; the attempt-bound testset
now has 1,510. Both runs explicitly skipped the heavy 266-cell roster; the
earlier 87,324-assertion full receipt is historical, not a rerun. All 186 public
bindings, six quiet-wrapper cases, protected historical bodies, six open M1
decisions, runtime hold, local links, and whitespace checks passed or remained
preserved. No production source, dependency, sampler, or public API changed in
this increment, and no scientific fit, cost probe, benchmark, or CI ran.

The following **recording contract review**, not another synthetic roster, will
locate observations for actual fit entry, successful return, scoring, and durable
publication, and keep interruption between those boundaries explicitly unknown.
A pre-call intent is not proof of entry; failure to save a returned fit is not
proof that fitting failed. Retain planned inputs, including initialization and
RNG ownership, before execution; do not reconstruct them from posterior output.
Any implementation/probe follows the reviewed contract and explicit resource
authorization. No seed allocation, lifecycle counts, M1 acceptance, or M2
evaluation is created by this review; M0's historical runtime hold stays open.

#### Minimal attempt recording contract proposal

**Review candidate, not an implemented schema or an accepted M1 decision.**
Keep lifecycle facts separate from the scoring disposition and from successful
file publication. Reuse the existing planned `(dataset_id, heldout_id, method)`
and positive attempt number, bound to the phase/plan reference; do not introduce
another ID registry. Before invocation, retain the actual labelled inputs,
truth/source/environment references, backend/prior/settings, ordered initial
vector (or explicit default-zero policy), and owned sampler seed/RNG state.
The scoring reference's fit digest is available only after return; it cannot
replace this pre-call input record. Bind the later fit/scoring reference back
to the separately retained input declaration without rewriting that declaration.
The current `reference_sha256` checks a scoring reference; its existence alone
does not prove that the inputs were committed before fitting.

The observation points are **intent, actual public `fit` body entry, successful
return, scoring, and publication validation**. Intent precedes argument
evaluation/dispatch and cannot prove entry. Entry must be observed inside the
declared callable boundary, before its input checks; it does not mean that the
sampler started. Observe return before hashing/scoring/publishing so failures
in those later operations cannot be mistaken for a fitting exception. An
audited return observation also entails entry, but must not fabricate a missing
entry record. The immediate return observation does not require an output hash;
attach that digest only after successful hashing, bound to the same attempt.
Bind every observation to its attempt, producer/source revision,
stage, and relevant input/output digests; wall-clock timestamps alone are not
identity or causal evidence. The [minimal bridge](#minimal-fit-observation-bridge)
now supplies entry/return hooks, not an audited scientific declaration schema.

The following table describes **confirmed facts after recovery**, not new
status symbols accepted by `_mfrm_anchor_checked_primary`. `?` means unknown;
it is neither a zero count nor an observed failure.

| Retained observation / interruption window | Fit entered | Fit returned | Required disposition |
| --- | --- | --- | --- |
| Preflight rejection confirmed before any invocation | No | No | Preserve the planned primary and rejection reason |
| Intent is the last record; subsequent execution is unobserved | ? | ? | Do not infer `not_started`, `running`, or `fit_failed` from silence |
| Entry confirmed; no return or call exception confirmed | Yes | ? | Keep completion unknown, including a lost return record |
| Actual call exception confirmed after entry, with no successful return | Yes | No | Distinguish input validation from sampler failure by stage; neither is completion |
| Return confirmed; scoring throws | Yes | Yes | Preserve completion and the scoring failure separately |
| Return/scoring confirmed; publication throws or acknowledgement is lost | Yes | Yes | Reconcile saved bytes; do not demote the fit or automatically refit |
| Fit/report file exists without a bound invocation observation | ? | ? | A constructed object or digest alone cannot establish execution |
| An additional attempt succeeds after primary failure/interruption | Unchanged for primary | Unchanged for primary | Retain both attempts; no replacement or enlargement of independent N |

Report confirmed and unknown counts separately for the planned primary roster;
the confirmed count is a lower bound, not an exact total while unknowns remain.
Valid later observations entail earlier causal facts, preserving
`metric-valid <= diagnostic-valid <= returned <= entered <= planned`; conflicting
records require integrity review, not silent repair. Successful return does not
imply acceptable diagnostics or applicable metrics. Missing publication may
leave a result unusable for scoring without proving that fitting failed.
Current consumers keep `lifecycle_counts_available=false`; do not force these
new observation distinctions into their existing coarse status vocabulary.

The existing LD1 publisher was inspected and its unchanged
[publication tests](../../test/local_dependence_pilot_attempt_archive.jl) reused.
Its three explicit fault windows show why an exception is insufficient:
before the hard link there is only a staging file; after linking but before
unlinking there are two aliases and ordinary validation rejects; after unlinking
but before final validation a single-link target can already contain the exact
expected bytes. Existing reconciliation removes only the verified staging alias
for the expected same-inode, same-byte two-link case. Extra aliases or different
expected bytes reject without cleanup. Recovery must not overwrite a target,
delete ambiguous evidence, or restart the fit merely because publication threw.

The publisher uses same-volume hard-link creation, `flush`/close, and read-back
validation, with no explicit file/directory durability-sync step. These are
local visibility/reconciliation checks, **not verified power-loss durability,
cloud synchronization, or hostile concurrent-writer protection**. The tests use
fresh temporary directories, not this repository's Dropbox archive location.
The archive location, supported interruption model, and required durability
must be decided before adopting a storage mechanism or promising recovery.

On **2026-09-07 JST**, the unchanged publication/fault/reconciliation testset
passed **47 assertions on each of Julia 1.10.8 and 1.12.5**, with two default-pool
Julia threads. Only that existing testset and its nested fault-window checks ran;
other LD1 archive tests, the package/anchor regression, and all fit runners were
excluded. An initial Julia 1.10 launch rejected the interactive-thread-zero
option before tests; both successful runs used `--threads=2`. The preceding
25,345-assertion anchor/metadata/scorer receipt remains historical, not a rerun.
No source/test code, dependency, public API, evaluation seed, fit, cost probe,
benchmark, CI dispatch, observer, or ledger was changed, allocated, or launched.

**Remaining decision:** maintainer and analyst review the pre-call declaration
and its binding to actual inputs for M1-02/04/05. The authorized local adapter
and entry point are described below; they do not copy the LD1 plan/seal schema,
approve a resource budget, close any of the six M1 decisions, start M2, or resolve
M0's +23.4% runtime hold.

#### Local record publication recovery adapter

The user authorized the minimum process-interruption implementation, excluding
power loss and cloud synchronization. Its first implemented part is
[mfrm_anchor_attempt_record.jl](../../scripts/mfrm_anchor_attempt_record.jl).
Its publication/recovery functions never fit or execute an attempt roster. `publish_record` aliases
the existing publisher; `recover_record` takes the same caller-retained expected
artifact, archive/staging paths, and semantic validator. It reuses the existing
JSON/hash checks and exact staging-alias reconciliation without copying the LD1
plan or seal schemas. The validator must throw on semantic rejection.

Recovery requires one stopped writer and normalized absolute paths in a trusted
local archive. An absent target returns `:not_published` without creating a
directory, publishing staging bytes, or rerunning work. An exact, valid
single-link target returns `:published` without replacement. With exactly two
links, only the verified same-inode/same-byte staging alias may be removed;
staging must not contain the target itself. Different bytes, invalid references,
semantic rejection, symlinks, escaped paths, or extra/ambiguous aliases fail
closed and preserve evidence. Repeating successful recovery is read-only.
Orphan and partial staging files remain for review, not automatic deletion.

These statuses concern publication only: both returned outcomes explicitly keep
`lifecycle_counts_available=false` and `validation_claim_allowed=false`. The
adapter does not verify the completeness or actual execution of an input/event
declaration. The bridge below adds observations, while audited pre-call-to-result
binding remains unfinished; a saved object alone supplies neither.
No archive is created in Dropbox and no scientific input/seed roster is adopted.

The new standalone test uses opaque test records, existing publication faults,
conflict/non-mutation checks, and four owned child processes killed with SIGKILL
at partial-write, complete-staging, linked, and unlinked primitive states. Those
children construct the publisher's file states; they do not run a sampler or
constitute end-to-end interruption testing of a fit observer. The test is wired
once into `fitting_reports`; its script-include boundary addition is recorded in
the [load review](code-load-boundary.md#anchor-recording-test-addendum).

At the publication-only step on **2026-09-07 JST**, **140 assertions per version**
passed on Julia **1.10.8 and 1.12.5**: 93 new adapter/interrupted-producer checks and 47 unchanged
publication checks. The final runs also parsed `test/runtests.jl` and verified
the single new include in its existing `fitting_reports` blocks, without running
that fitting suite. The temporary routing checker initially assumed there was
only one such block; correcting that checker did not change implementation code.
Neither the full anchor/metadata regression nor CI was rerun, and no actual fit,
evaluation seed, cost probe, or benchmark ran. The prior 25,345 scoped and 87,324
full-roster receipts remain historical. All six M1 decisions, zero fresh M2
replications, and M0's +23.4% runtime hold remain unchanged.

#### Minimal fit observation bridge

The minimal `fit(::FacetDesign)` body now has an opt-in private `_on_enter`
callback before its input checks. The default is `nothing`; inference kernels,
defaults, exports, and dependencies are unchanged. The `FacetSpec` overload
delegates to that same boundary after design construction; argument evaluation,
keyword type errors, and failed dispatch can precede entry. Cached/generalized
fitting is not an observation route for this bridge.

The script's `observe_fit(invoke; record_event)` runs one trusted synchronous
closure, which must directly call `fit(...; _on_enter = on_enter)` and return its
result unchanged without intercepting errors. It records `:fit_entered` inside the
public body and `:fit_returned` outside the successful call, before hashing or
scoring. Call exceptions propagate unchanged. Recording failures instead carry
`FitObservationError(stage, cause, returned_fit)` with the captured cause and,
after return, the original result. A recorder exception can still leave a valid
published event: reconcile it using the existing adapter, never automatically
refit. No global/task-local observer or exception-to-scoring-status mapping is
introduced. Missing entry and duplicate entry reject; the trusted closure and
its scientific input binding are not dynamically audited by this helper.

The generic bridge requires the caller to retain the input declaration and
bind both events to it. Its opaque-record tests alone do not prove that declared
inputs equal actual arguments. The specialized [input binding](#declared-fit-input-binding)
below now performs that comparison for an owned minimal-fit call; linkage to the
later scoring reference remains unfinished. Recovery still supplies no lifecycle
counts or validation permission.

On **2026-09-07 JST**, both Julia **1.10.8 and 1.12.5**, with two default-pool
threads, passed **25,537 assertions across 26 testsets**: 25,345 existing scoped
anchor/metadata/scorer checks, 93 publication/recovery checks, 52 new observation
checks, and 47 existing LD1 publication checks. The 186 root exports and exact
single inclusion in `fitting_reports` were verified; its full runner was parsed,
not executed. The targeted recording file also passed its 145 checks separately
on both versions, and the quiet-command wrapper passed all six cases.

Real public-fit entry is exercised only with pre-sampling rejection, including
all four backend labels and the design/spec routes; dispatch/type failures
produce no entry. Successful return and subsequent recording failure use
synthetic call results, not successful MCMC. The heavy 266-cell roster was
explicitly skipped; its prior 87,324-assertion receipt remains historical.
Successful sampler execution, end-to-end observer SIGKILL, benchmarks, and CI
were not run. All six M1 decisions, zero fresh M2 replications, and M0's
historical +23.4% runtime hold remain unchanged.

#### Declared fit input binding

`fit_input_record(design; options)` reuses canonical design validation, the
labelled design payload/identity, prior recording, and initial-vector checks.
It records every one of the 18 minimal-fit options explicitly, including
inactive options, progress, and requested CmdStan paths; it adopts no sampler
defaults or numerical policy. All real controls are normalized to the Float64
values passed by this adapter. Default-zero and supplied initialization remain
distinct policies even when their ordered vectors match. Initialization must
normalize to a one-dimensional vector: matrices reject instead of losing shape
in JSON and appearing identical to different call arguments. Matching a declaration
does not establish that its settings are valid or scientifically adequate.

For an explicit non-Boolean integer seed, the existing seed-selection helper
creates an owned MersenneTwister; the otherwise ignored supplied RNG state is
not falsely bound. Without a seed, only MersenneTwister is currently supported:
the caller's state is copied without drawing from it, and the declaration
retains its serialized bytes and digest. Julia version, architecture, and word
size are bound, but serialization is not a portable or independently reproduced
replay guarantee. Production code never deserializes an archive. Unseeded
TaskLocalRNG and other RNG types reject until their ownership/replay contracts
are checked. The ordinary `fit` RNG semantics remain unchanged.

`observe_declared_fit` snapshots the actual call inputs, compares their native
JSON representation against `expected.fit_input`, validates the caller's outer
declaration, and requires an exact already-published single-link file within the
trusted local boundary. Preflight is read-only: missing files, mismatches,
symlinks, unreconciled hard links, or semantic rejection cannot invoke fit. The
adapter then directly calls public minimal fit once with private snapshots,
using the existing observation bridge. Both event callbacks receive the same
verified declaration content hash and file digest, not mutable call inputs.
Call exceptions and recording failures retain their separate semantics.

The script now imports the package to make this concrete call; the pure archive
primitives remain in the existing LD1 module. No package include, dependency,
export, inference kernel, or new execution framework was added. The caller's
semantic validator still owns attempt/phase/plan, truth, source/environment, and
resolved toolchain checks; requested CmdStan paths are not an executable digest.
This input subrecord is not a frozen complete scientific schema, restart guard,
all-attempt ledger, or execution authorization. The subsequent returned-fit
link below connects this boundary to the existing scorer.

On **2026-09-07 JST**, both Julia **1.10.8 and 1.12.5**, with two default-pool
threads, passed **25,631 assertions across 27 testsets**: 25,345 existing scoped
anchor/metadata/scorer checks, 93 publication/recovery checks, 52 observation
checks, **94 new input-binding checks**, and 47 existing LD1 publication checks.
The recording file contributes 239 checks, including the final matrix-shape
guard. The 186 root exports and single `fitting_reports` inclusion were verified;
the full ordinary runner was parsed, not executed. The quiet-command wrapper
also passed all six cases.
An initially unchanged threshold fixture was corrected to a genuinely different
regime; each changed-design fixture now checks that its input record differs.
Tests cover all 18 option perturbations, labelled response/model/anchor changes,
private snapshot ownership, same-process RNG-state replay, and fail-closed
publication preflight. Real calls stop at `ndraws = 0`, or at AdvancedHMC's invalid
`target_accept` guard after design/initialization checks and before target/draw
allocation or sampling. The latter checks isolation from caller array mutation.
Successful return remains synthetic-only. The heavy 266-cell roster was
explicitly skipped, retaining its historical 87,324-assertion receipt. No
scientific sampling, evaluation seed, benchmark, or CI was run. All six M1
decisions and M0's +23.4% hold remain open; fresh M2 replications remain zero.

#### Returned fit and scoring record links

`observe_linked_fit` reuses the declared-input bridge for one direct public
minimal-fit call. Before entry, the outer declaration must bind the scoring
reference's dataset/heldout/method IDs, positive attempt number, and complete
`scoring_plan_sha256` using the existing `_cache_hash`. That reference must not
already contain the derived `fit_sha256` or `fit_provenance` fields. The
caller's semantic validator still decides whether the declared scientific
inputs and environment are acceptable; this transport adopts no such policy.

The trusted recorder publishes `fit_event_record(stage, binding)` with
CREATE_NEW and returns its normalized absolute path. The bridge verifies the
exact single-link file for each entry/return observation. Only after the real
call returns and its return observation is verified does the bridge hash the
actual returned fit and create `(fit, reference, link)`. The result link binds
the complete final reference and all three input/entry/return file paths,
content hashes, and byte digests. Publish and separately retain that link with
the existing publisher; no publication or retry is implicit. A post-return
hashing failure retains the actual fit in `FitObservationError(:fit_linked, ...)`.

`score_linked_fit` is read-only: it snapshots its arguments, verifies the
separately retained result link, then checks all three pinned files, their
stages/input bindings, and the original scoring-plan hash before calling the
unchanged attempt-bound scorer. Missing, altered, symlinked, or unreconciled
multi-link evidence rejects without repair. A scoring error does not rewrite
a return observation or turn it into a fit failure. Publication recovery is
still an explicit stopped-writer operation, not a re-fit.

The new input transport is `bayesianmgmfrm.anchor_fit_input.v2`. A three-category
case exposed loss of the redundant `design_identity.data_signature::UInt64`
when untyped JSON3 decoding rounded a value above signed-64-bit range through
Float64. The transport now omits only that legacy field, retaining the full
labelled design payload and canonical SHA-256 identity. The public identity API
and shared LD1 JSON implementation are unchanged. Old v1 input declarations
reject before entry; they are never silently migrated or overwritten.

Link/event artifacts use the existing archive hash, which excludes only its
root `content_hash`. Final-reference and retained attempt digests use
`_cache_hash`, which also covers nested `content_hash` fields. The generic
score-report `artifact_content_hash` alone does not cover those nested fields;
the existing separately retained reference/attempt checks remain required.

This is a local integrity chain, not independent execution attestation or a
complete study ledger. Constructed events and synthetic fit objects do not
prove that fitting occurred. Complete source/environment/resolved-toolchain
provenance and scientific acceptance remain caller-owned, open requirements.
No new include, export, dependency, executor, restart guard, lifecycle count,
power-loss/cloud-sync guarantee, or concurrent-writer protocol is introduced.

On **2026-09-07 JST**, both Julia **1.10.8 and 1.12.5**, with two default-pool
threads, passed **25,691 assertions across 28 testsets**: 25,345 existing scoped
anchor/metadata/scorer checks, 93 publication/recovery checks, 52 observation
checks, 99 input-binding checks, **55 returned-fit/scoring-link checks**, and 47
existing LD1 publication checks. The recording file contributes 299 checks.
The 186 root exports and single `fitting_reports` inclusion were verified;
the full ordinary runner was parsed, not executed. All six quiet-wrapper cases
also passed. The initial JSON round-trip failure was corrected at the input
transport, and a report comparison containing `missing` was corrected to use
`isequal`; both versions then passed the complete scoped run.

Real wrapper calls stop at pre-sampling guards; successful fits/events in the
link/scoring tests are explicitly synthetic. Checks cover entry-record failure,
changed fit/reference/file contents, missing files, wrong stages or input
bindings, unresolved hard links, explicit publication recovery, nested hash
tampering, and preservation of retained records after a scoring failure.
No scientific fit, evaluation seed allocation, benchmark, CI, or fresh
independent reproduction was run. The heavy 266-cell roster was explicitly
skipped; its 87,324-assertion receipt remains historical. M0's +23.4% hold and
all six M1 decisions remain open; fresh M2 replications remain zero. Next,
specify the outstanding source/environment/resolved-toolchain requirements
within the caller's declaration and M1 review, as reviewed below.

#### Source and execution environment declaration requirements

**Review proposal for M1-02/04/05, not complete environment verification or M1 acceptance.**
Reuse the existing outer input declaration, `source_files` / independently
retained `required_source_paths`, and `semantic_validator`; no new collector,
registry, execution schema, or production source roster is frozen here. The
42-file synthetic fixture is not the generation-to-fit-to-score source closure.

The source review distinguishes collection from verification. In
[evidence_metadata.jl](../../src/evidence_metadata.jl), `collection.status`
reports caught optional-probe failures, not completeness against study needs.
An absent Manifest can produce a `nothing` digest without a collection issue;
conversely, unavailable R discovery need not block a Julia-only study. The
default package list contains direct dependencies, not all transitive packages
or an inventory of loaded code. Git commit and short-status hashes do not bind
dirty file contents. A `fit_artifact` collects environment metadata when it is
created, not when its supplied fit was computed; the anchor score report's
Julia version likewise describes scoring. Neither can reconstruct the fit's
producer environment after the fact.

| Requirement | Retain before the call | Observation / verification boundary |
| --- | --- | --- |
| Source closure | Independently reviewed required paths and exact file digests for generation/truth, model/fit, scoring, recorder/archive helpers, and the actual launcher/validator; retain dirty or path-developed source bytes as well as any Git revision | Reuse declared-source coverage and digest primitives before entry, not only the existing scorer's later check. Hashing files on disk does not prove those methods were loaded; a reviewed launch from retained inputs and unchanged source during the call is still required |
| Effective Julia environment | Actual active Project and runtime-resolved Manifest identities, their retained bytes/digests, and the intended Julia/package environment | Reuse `_evidence_project_hashes` / `_evidence_manifest_path`; require the declared paths and digests, rejecting absence or fallback to a different file. Do not guess a Manifest name or require its creation-version field to equal the running Julia version |
| Dependencies and native code | Transitive package identities, path-dependency contents, effective preferences, and the backend-relevant artifacts/native libraries | `Pkg.dependencies()` metadata describes resolution, not loaded or immutable code. The current direct-package list and BLAS configuration string are insufficient alone; the retained environment and actual loaded libraries need a reviewed evidence route |
| Runtime and launch | Exact Julia build/executable and system-image identity, OS/architecture, effective startup/compilation flags, load/depot paths, Julia thread pools and BLAS threads | The input v2 subrecord already binds Julia version/architecture/word size, but not this whole scope. Match the declared effective settings in the producer process; requested environment variables alone are not the observed settings |
| Backend/toolchain | Chosen backend/AD route; for CmdStan, resolved root and discovery source, Stan source, build configuration including `make/local` when present, actual build tools/options, and the model executable identity | The bound `cmdstan_path` / cache-directory request is not a resolved executable digest. Compilation may occur inside fit after entry, so an output binary cannot always be predeclared: bind reviewed build inputs first and retain the selected binary/build provenance before sampling. This observation route is not implemented |
| Scope, applicability, and privacy | Explicit required versus optional versus not-applicable requirements with reasons, tied to the attempt/phase and backend | Missing required evidence rejects readiness; optional discovery failure stays descriptive. CmdStan/R cannot be silently required for a Julia-only path or marked not-applicable when used. Keep necessary private paths in the trusted archive; do not dump the entire environment or publish machine-local paths |

These are semantic requirements, not new field names or status symbols. Match
only the declared identity/configuration fields, not volatile timestamps or an
entire `evidence_metadata()` dictionary. Hardware/resource observations remain
context unless the scientific protocol requires them; this is not a blanket
same-CPU/cache rule or a revival of M0's deferred timing experiment.

The [CmdStan runtime check](../../src/cmdstan_backend.jl) verifies installation
pieces and executes `stanc --version`; it does not attest a model binary.
At that review, the [compilation helper](../../src/cmdstan_fit.jl) reused a cache
entry when copied Stan bytes match and the executable exists with a sufficient
mtime. It did not compare compiler/build-option identities or an executable
digest. Different toolchains could therefore remain eligible for the same cache
entry. This was a source-inspected integrity gap, not an observed sampling error.
Before using CmdStan for this study, resolve and test that binary-selection
boundary; neither `runtime_ready`, a version label, nor a user-supplied cache
path closed it. The later containment and output-handoff changes below remove
that reuse branch and bind observed executable bytes; they do not establish
the build producer's identity. No `cmdstan_backend_check`, compilation, or cache modification
was run in this review; metadata collection only performed path discovery.
No package backend was disabled or selected as the primary method.

The minimum integration sequence is:

1. Retain the reviewed requirements and build/source/environment inputs before
   entry. At the existing semantic callback, compare the current producer's
   required identities and reject missing/mismatched evidence without fitting,
   automatic environment repair, package installation, or publication retry.
2. Observe any identity resolved only inside execution, before it is used.
   Input snapshots do not freeze global environment variables, loaded methods,
   or files; prevent changes through the reviewed execution setup. A later
   matching file hash cannot detect a change-and-restore interval.
3. Keep the bound producer observations with the returned-fit link. Scoring
   verifies retained producer evidence and records its own consumer environment
   separately; a scoring host is not proof of the original fitting host. A
   mismatch discovered after return must preserve the return observation and
   be handled as an integrity/scoring rejection, not retroactive fit failure.

On **2026-09-07 JST**, the unchanged metadata tests passed **401 assertions
across two testsets on each of Julia 1.10.8 and 1.12.5** (21 optional-collection
and 380 Manifest-binding checks); all 186 root exports were also checked.
Only these existing tests ran, not the earlier 25,691-check scoped suite or
the heavy candidate roster. That requirements-only review changed this document
and ROADMAP; no runtime/test code, collector, or dependency changed. No fit, evaluation
seed allocation, cost probe, benchmark, CI, or independent reproduction ran.
The requirements review is complete; execution-environment verification is not.
The following bounded check implements the file/resolution part at the existing
semantic boundary. Loaded-code/native-toolchain provenance,
all six M1 decisions, and M0's +23.4% hold remain open; fresh M2 replications
remain zero.

#### Pre-entry source and Project/Manifest check

`check_source_environment(declaration, reference)` in the existing
[recording script](../../scripts/mfrm_anchor_attempt_record.jl) is an opt-in,
read-only semantic check. Compose it into `observe_linked_fit`'s or
`observe_declared_fit`'s `semantic_validator`, alongside the caller's existing
phase/truth/scientific-scope checks. Existing callers are not silently opted in;
the transport alone does not prove that this validator was used.

The pre-call scoring reference adds `project_environment`, containing exactly
`active_project` and `manifest` absolute paths. Both must occur in the separately
declared, nonempty `required_source_paths` and the `source_files` digest map.
Their expected digests come from that same map, not a second environment hash
record. The existing `scoring_plan_sha256` binds the whole reference, including
these paths and its roster; the checker first verifies that binding.

The checker reuses `_mfrm_anchor_required_sources`, `_evidence_file_sha256`, and
`_evidence_project_hashes`. It verifies every supplied source entry, including
extras, requires normalized absolute paths and lowercase 64-hex digests, then
compares the active Project and runtime-resolved Manifest paths **and** hashes
with the retained reference. Equal bytes at a different environment path are
not an identity match. Missing files, malformed resolution, and fallback to a
different Manifest reject before entry without publication, repair, or package
installation. The checker returns `nothing`, not a readiness/acceptance flag.
It does not invoke the full optional metadata collector or R/Git/CmdStan probes.

This adds no package source, export, dependency, or include edge. It neither
validates a dependency lock nor selects the complete scientific source roster.
The file readers retain their existing semantics; this is not a new symlink,
concurrent-writer, or loaded-code attestation protocol. Stable trusted files and
a reviewed launch remain necessary: a successful synchronous check cannot
freeze global state, detect change-and-restore between reads, or prove which
methods/native binaries were used. Re-scoring on another host must preserve the
producer evidence rather than treating the consumer's current environment as
the producer's. The CmdStan binary/cache gap above remains open.

On **2026-09-07 JST**, Julia **1.10.8 and 1.12.5** each passed **25,766
assertions across 29 testsets**, with two default-pool threads: 25,345 existing
scoped anchor/metadata/scorer checks, 93 publication/recovery, 52 observation,
99 input-binding, 55 returned-fit/scoring-link, **75 new source/environment**,
and 47 existing LD1 publication checks. The recording file contributes 374
checks. Both runs preserved all 186 root exports and verified the single
`fitting_reports` inclusion by parsing, not executing, the full ordinary runner.
All six quiet-wrapper cases also passed. The first targeted run found one
test expectation that incorrectly required `ArgumentError` from the existing
JSON field-set validator; its `ErrorException` remains propagated unchanged,
and the test now accepts the existing validation types while checking no entry.

New checks cover self-consistently published invalid declarations, missing
required paths/map entries, malformed digests/paths, changed or missing source
and environment files, same-byte alternate environments/Manifests, and native
resolution failure despite a matching Project digest. The valid concrete call
still stops at `ndraws = 0`; no sampler starts. Tests preserve input/event bytes
and the caller's RNG, restore their temporary active-project changes in `finally`,
and use only owned fixture files rather than modifying the working environment.
The heavy 266-cell roster was explicitly skipped; its 87,324-assertion receipt
remains historical. No scientific fit, evaluation seed allocation, cost probe,
benchmark, CI, or independent reproduction ran. The guarded probe below
investigates the CmdStan cache-identity gap without building or running cached
executables. All six M1 decisions and M0's +23.4%
hold remain open; fresh M2 replications remain zero.

#### CmdStan executable cache identity probe

The manual [cache-identity probe](../../scripts/probe_cmdstan_cache_identity.jl)
originally reproduced the gap without loading the BayesianMGMFRM package or
launching any external tool/model. That characterization is historical; the
same script now checks the containment described below. It loads the
declaration-only backend file and selects four unmodified helper bodies from
`cmdstan_fit.jl` in an isolated module.
Its two explicit seams are a fixed repository Stan-source lookup and an
`_cmdstan_run` replacement that always throws before launch. Runtime-check
objects and tool/model files are fixtures, not working CmdStan installations.
The original check was a cache-predicate characterization, not a public-fit
integration test, toolchain-readiness proof, or OS sandbox; re-audit changed
source before reuse.

| Perturbation in owned fixtures | Pre-containment result for each of MFRM / GMFRM / MGMFRM |
| --- | --- |
| Different retained CmdStan root, same explicit cache directory | The previous model path is returned; equal version labels also map to the same default cache root (that shared default is never written by the probe) |
| Changed CXX or MAKE selection, or STAN_THREADS setting | The previous model path is returned without reaching the command trap |
| Changed `make/local` setting, stanc bytes, or compiler bytes at the same path | The previous model path is returned without reaching the command trap |
| Non-executable model fixture, then empty replacement with a different digest | Both are returned as cache hits while the copied-source and mtime conditions hold |
| Changed copied Stan source, or missing model file | Each reaches the build-command trap; no compiler or model is executed |

The cause was the shared early-return predicate: matching **copied** source bytes
and a model-file mtime do not bind that model's bytes to its build inputs. The
minimal fitter and generalized diagnostic routes both use
`_cmdstan_compile_model`; fixing only an anchor caller would leave sibling
callers exposed. These fixtures demonstrate a decision/identity gap, not that
any retained scientific posterior was computed with an incorrect executable.

The [containment implementation](#cmdstan-shared-cache-containment-proposal)
below removes that reuse branch. It does not supply the build-input/binary
evidence required to restore reuse. Complete loaded-library and scientific
provenance remain separate requirements, not promises of a cache key.

On **2026-09-07 JST**, the final pre-containment probe passed
**68 characterization assertions on each of Julia 1.10.8 and 1.12.5**,
including six trapped build requests and
unchanged SHA-256 digests of both inspected Julia files and all three Stan
sources. Output explicitly says **REPRODUCED, NOT FIXED**. Only owned temporary
fixtures were changed; no existing CmdStan installation or cache was modified.
The quiet wrapper's six cases also passed. The probe is manual-only and absent
from the ordinary test runner/include closure. The prior 25,766-check regression
and 186-export receipt remain historical, not rerun or enlarged by these 68
checks. That earlier increment left production source, dependencies, and the
public API unchanged.
No sampler, evaluation seed allocation, benchmark, CI, or independent
reproduction ran in this increment.
At that point the cache defect remained unfixed; it is now contained by refusing
reuse, not by validating cached binaries. All six M1 decisions and M0's +23.4%
hold remain open; fresh M2 replications remain zero.

#### CmdStan shared-cache containment proposal

**Containment implemented; verified reuse and study execution readiness remain open.**
The first correction rejects existing cache contents; it does not attempt to
establish a verified build fingerprint. Existing helpers do
not supply the missing evidence: `external_bridge_result_receipt` explicitly
treats the executable digest as operator-supplied, while `save_fit_cache` /
`load_fit_cache` bind fitted objects, not native build inputs. This change reuses
the existing `CmdStanError` and filesystem operations; it adds no receipt
schema or dependency.

The initial containment source change was confined to `_cmdstan_compile_model`, shared by all
three families and both fitter routes. The copied-source/mtime reuse branch
is removed. After resolving `build_root` but **before** `mkpath`, source copying,
or `_cmdstan_run`, the helper rejects a symlink root (including a dangling link),
an existing non-directory root, or any nonempty directory. It uses
`CmdStanError(:model_compile, :cache_unverified, ...)` and explains that callers
must retain the old directory and explicitly select a new empty
`cmdstan_cache_dir`. It inspects directory entries without following their
contents; even an unrelated or hidden entry prevents treating the root as a
fresh build.
It does not infer ownership from a family filename or silently choose another
root. Joining the native `splitpath` components removes trailing separators
before the link check: plain links, `link/`, and `link/.` must all be rejected.

An absent root or a real empty directory may reach the existing compilation
path; the source copy now uses `force = false`. The implementation tests trap
the build command before launch. There is no automatic cache migration,
overwrite, cleanup, rebuild-on-rejection, or retry. A failed/interrupted build
leaves its files in place; a later call rejects that occupied directory too.
**Compatibility cost:** the shared default directory stops being reusable,
including after a successful first build. Repeated authorized fits would need
explicit fresh directories until verified reuse exists. This is deliberate
temporary containment, not a completed replacement cache or an approved
increase in study compilation cost.

The existing manual probe was converted to guarded rejection checks, retaining
the historical 68-check receipt as characterization. It uses the same isolated
source lookup and always-throwing command trap, owned POSIX fixtures, and all
three families. Checked cases are:

| Fixture / perturbation | Observed result with the guard |
| --- | --- |
| Matching source and apparently executable, nonempty model | `:cache_unverified`; no build request, return path, or byte change |
| Changed root, MAKE/CXX selection or bytes, stanc, `make/local`, or STAN_THREADS | Same rejection; these cases no longer depend on detecting every changed input |
| Missing/changed copied source, missing/empty/non-executable model, or partial generated output | Same rejection while any entry remains; retain all remaining bytes and names |
| Unrelated/hidden entry, regular-file root, live or dangling symlink root | Same rejection, without touching any link target or other entry |
| Absent root or actual empty directory | Exact source copy with no overwrite; one `:model_compile` request reaches the trap, never a compiler or model |
| Repeated call after the trapped request leaves its source copy | Reject the occupied directory without another request or repair |

The checks compare error stage/reason and guidance, build-request counts,
directory entries, file bytes/modes/mtimes, and link targets before and after each
rejection, and unchanged repository source hashes during each run. They also
verify each fresh-root request's exact command arguments and working directory.
Successful cache reuse is intentionally **not** a positive test. The trap validates the helper
boundary only: public callers already run `cmdstan_backend_check` (including
`stanc --version`) before this helper, and initialize their fit/RNG context
earlier. Do not claim rejection before all external execution or public-fit
entry, and do not call those public routes in this no-execution check.

Restoring reuse requires the separate
[build-input and evidence contract](#cmdstan-effective-build-inputs-and-reuse-evidence-review)
below. A fresh model directory is not an isolated toolchain, and the current
post-build `isfile` check is not executable authenticity or scientific provenance.

This containment assumes a trusted local directory and stable ancestors/files
during a call. It does not add a concurrent-writer protocol, protect against
replacement after verification, or attest loaded dynamic libraries. On
**2026-09-07 JST**, the initial implementation passed **488 guarded assertions on each
of Julia 1.10.8 and 1.12.5**. Each run trapped six fresh-root build requests and
reported **CONTAINED, REUSE DISABLED**; both Julia sources and all three Stan
sources retained their start-of-run hashes. Its `cmdstan_fit.jl` digest was
`87a31cd7fef61c6a2037ecb40b0a2e8f9bcc4f66ef1dfa9c86eb113164e8f4e5`;
the old 68-check receipt is not a check of this revision. The quiet wrapper's
six cases also passed. No existing installation/cache was changed, no external
tool/model was launched, and no package regression, evaluation seed allocation,
benchmark, CI, or independent reproduction ran. The 25,766-check / 29-testset,
186-export, and full-roster receipts remain historical. The script remains
manual-only; package dependencies, exports, and ordinary includes are unchanged.
This 488-check receipt predates the later
[invocation correction](#cmdstan-explicit-make-invocation); it is not fresh
evidence for the changed helpers. No publisher, build, model run, or cache migration is queued.
All six M1 decisions and M0's +23.4% hold remain
open; fresh M2 replications remain zero.

#### CmdStan effective build inputs and reuse evidence review

**Source/documentation review, 2026-09-07 JST; reuse remains disabled.**
This review compared the pre-invocation-correction Julia call path with the official CmdStan
guide (displaying version 2.39) and tagged **v2.39.0** build rules, not a moving
development branch. It neither identifies the local installation as that
version nor adopts it for the study. The three package Stan sources are
unchanged; no installed Makefile, compiler, stanc, or model was executed.
The guide describes translation followed by C++ compilation/linking, not a
single-source binary identity. [Official compilation guide](https://mc-stan.org/docs/cmdstan-guide/compiling_stan_programs.html).

| Boundary | Source-backed finding and consequence for this package |
| --- | --- |
| Make invocation, before the correction below | `_cmdstan_configured_program` kept only the first whitespace-delimited word, so `MAKE="make -n"` lost `-n` in `_cmdstan_compile_model`; this was a local source deduction, not an executed example. The helper invoked Make without `-f`, while readiness only checked `root/makefile`. GNU Make can select `GNUmakefile` first. The checked filename therefore need not have been the selected entrypoint. [GNU Makefile selection](https://www.gnu.org/software/make/manual/html_node/Makefile-Arguments.html) |
| Effective compiler/configuration | The CXX readiness check discovers one word, but the build inherits the environment and reads `make/local`; CmdStan can also choose a platform default. Environment, Makefile assignments, and inherited Make options interact. A discovery path or raw CXX value is not the effective compiler command. `MAKEFILES` adds pre-read files; `MAKEFLAGS`/`GNUMAKEFLAGS` also affect behavior. [Tagged Makefile](https://raw.githubusercontent.com/stan-dev/cmdstan/v2.39.0/makefile), [GNU environment and Make inputs](https://www.gnu.org/software/make/manual/make.html#Environment) |
| Shared build inputs | The model link depends on `CMDSTAN_MAIN_O`, SUNDIALS/MPI/TBB targets, and the configured precompiled header. Default main-object/PCH locations are outside the fresh model directory; dependency files also participate. **Inference:** the directory guard does not prevent reuse or rebuilding of shared installation products. Their producer/input identity must also be accounted for. [Tagged model rules](https://raw.githubusercontent.com/stan-dev/cmdstan/v2.39.0/make/program) |
| Actual stanc bytes | Rules can build stanc from a local source tree, copy a release binary, or download a binary, with `STANC3_VERSION` defaulting to `nightly` in the rule file. Discovery-time `stanc --version` is not a binding to the bytes later used. These are possible rule paths, not observed actions on this machine. [Tagged stanc rules](https://raw.githubusercontent.com/stan-dev/cmdstan/v2.39.0/make/stanc) |
| Producer-to-consumer evidence | `_cmdstan_run` returns `nothing` on success and does not retain its temporary log; `_cmdstan_compile_model` returns a path after `isfile`. `_cmdstan_sample_chains` consumes that string without a retained build receipt or expected-binary digest. Existing fitted-object caches and operator-supplied external-bridge digests do not fill this gap. [Local adapter](../../src/cmdstan_fit.jl), [external receipt limits](../../src/facets_conquest_bridge.jl) |

Keep raw configuration and its effective meaning distinct. In the tagged
Makefile, `ifdef STAN_THREADS` selects the `_threads` suffix for a nonempty
value; the literal `false` is not a Boolean off switch in that conditional.
Consequently, the earlier `false` to `true` fixture perturbation demonstrates
changed setting bytes, **not** a verified off-to-on thread transition. An
eventual profile must preserve unset/empty/nonempty distinctions and review
each option's actual rule; it must not Boolean-normalize arbitrary values.
[CmdStan flag branches](https://raw.githubusercontent.com/stan-dev/cmdstan/v2.39.0/makefile),
[GNU conditional semantics](https://www.gnu.org/software/make/manual/make.html#Conditional-Syntax).

**No-execution boundary:** `make -n` is not a sandbox: recursive recipes and
included-Makefile updates can still execute. Shell expansions run during
evaluation; the tagged CmdStan Makefile includes immediate compiler-version
queries. Thus `make -n`, `make -q`, and `make compile_info` are not used as
read-only inspection shortcuts here. The official clean/rebuild suggestions
are not authorization to alter existing installations or caches.
[GNU dry-run exceptions](https://www.gnu.org/software/make/manual/html_node/Instead-of-Execution.html),
[GNU shell expansion](https://www.gnu.org/software/make/manual/html_node/Shell-Function.html),
[CmdStan evaluation-time probes](https://raw.githubusercontent.com/stan-dev/cmdstan/v2.39.0/makefile).

The engineering proposal is to support one explicitly reviewed build profile
before designing a reusable-cache publisher, with three required bindings:

1. **Requested inputs to effective build inputs:** bind the family, actual Stan
   bytes, reviewed CmdStan/toolchain revision and paths, explicit Makefile and
   command arguments, effective compiler/wrapper/stanc bytes and arguments,
   and the declared closure of included settings, source/header/SDK files,
   shared objects/PCH, and link inputs. Shared generated products require their
   own trusted producer binding, not only a digest of whatever is present.
   Unknown overrides, external inputs, or unaccounted generated products must
   refuse reuse. Do not implement a general Make interpreter or dump all of ENV;
   only reviewed build-relevant values belong in retained metadata.
2. **Observed build to retained output:** after separately authorized execution
   in an owned build workspace, retain completion evidence and bind the actual
   input snapshot and generated source to the expected executable bytes. Seal
   only a newly produced target; missing/malformed/mismatched evidence and
   interruptions remain untrusted. Do not adopt legacy binaries, overwrite old
   evidence, auto-clean, download, or rebuild to repair an identity mismatch.
3. **Retained output to fit attempt:** check the requested input/profile and
   expected binary digest before allocating chain seeds, bind that receipt to
   the actual fit, and recheck at the command-use boundary. This is a proposed
   consumer change at the time of this review; the later output-handoff change
   implements the observed-output checks, not a build-input receipt. A trusted local receipt does not
   authenticate a hostile producer, prove loaded-library identity, eliminate
   replacement races, or establish statistical correctness.

The current SHA-256 and JSON primitives suffice for byte binding; optional
metadata probes that return `nothing` must not be accepted as verified evidence.
No new schema, collector, publisher, dependency, or execution profile is adopted
in this increment. The complete native dependency closure is still unreviewed.

The review selected the bounded invocation correction implemented below,
separately from CXX discovery and inherited Make settings. The review itself
changed documentation only; its 488-check-per-Julia containment receipt then
still bound the unchanged source and was not rerun. Neither were the package
regressions or historical export/full-roster checks. No build, MCMC,
evaluation seed allocation, benchmark, CI, or independent review ran. All six
M1 decisions and M0's +23.4% hold remain open; fresh M2 replications remain zero.

#### CmdStan explicit Make invocation

**Implemented, 2026-09-07 JST; inherited configuration and verified reuse remain open.**
The existing `_cmdstan_configured_program` now treats a nonblank MAKE value as
one complete executable name/path. It does not split, unquote, or interpret a
shell command. If that exact selection cannot be resolved, it returns `nothing`
without falling back to another program. Unset/blank values keep the existing
default search. Thus ordinary option-bearing strings such as `make -n` no
longer silently select `make`; an actual executable path containing spaces is
preserved as one command argument. CXX's first-program readiness probe is
unchanged and does not attest Make's effective compiler command.

The shared compile helper reports `:model_compile` / `:make_unavailable` with
single-executable guidance before creating or changing the cache. Its command
arguments are now `[resolved_make, "-f", "makefile", model_stem]`, with the
CmdStan root as working directory. This makes the primary Makefile explicit
even when `GNUmakefile` is present; it does not hash or attest its contents,
suppress `MAKEFILES`/inherited options, isolate shared build products, or make
dry-run flags safe. Public readiness checks still execute `stanc --version`
before checking MAKE, so this is not a claim of no external execution from
the public check/fit route.

The existing manual probe passed **704 combined assertions on each of Julia
1.10.8 and 1.12.5**, including prior containment cases. New cases cover default
and PATH lookup, exact paths with spaces, seven unresolved option-like/quoted/
missing MAKE selections without fallback, unchanged CXX first-word discovery,
and pre-write rejection for occupied and absent cache paths in all three
families. Every rejection preserves owned fixture entries, bytes, file modes/
mtimes, and link targets. Nine valid requests (three per family) reached the
always-throwing command trap; their complete argument vectors and working
directories matched expectations, and both competing Makefile fixtures stayed
unchanged. No Make program was run to test precedence or path portability.
This remains an isolated helper test, not public-fit integration or validation
of a working GNU Make installation.

Both runs retained all five watched source hashes during execution. The new
`cmdstan_backend.jl` digest is
`c02e0388948c2d1c2fe23a4a0d248597c5488e32acd3a0983270f57fbb7a0374`;
`cmdstan_fit.jl` is
`0f50a6a4bc7ffc686a9381b22bcd259bbb270755f17b072d352c1117b1f2052a`.
The three Stan sources are unchanged. The quiet wrapper's six cases also
passed. The 488-check, 68-check, package/export, and full-roster receipts remain
historical, not additional tests of this revision. No new dependency, export,
ordinary include edge, or collector was added. No existing installation/cache
was changed; no compiler, stanc, model, evaluation seed, benchmark, CI, or
independent reproduction was executed or allocated.

The subsequent inherited-environment guard below adds a separate restriction;
the 704-check invocation receipt above is now historical. Reuse remains disabled.

#### CmdStan inherited Make environment policy proposal

**Implemented, 2026-09-07 JST; verified reuse remains disabled.**
The proposal heading is retained for existing links.
GNU Make reads `MAKEFILES` as additional Makefiles before the primary file.
`MAKEFLAGS` carries options and command-line variable assignments;
`GNUMAKEFLAGS` is parsed before it. Consequently, explicit `-f makefile`
does not remove these inherited inputs. This is documentation/source review,
not an observation of the local Make executable.
[GNU additional Makefiles](https://www.gnu.org/software/make/manual/make.html#MAKEFILES-Variable),
[GNU inherited options](https://www.gnu.org/s/make/manual/html_node/Options_002fRecursion.html).

One guard in the existing `_cmdstan_compile_model` serves all three families.
After the existing source/root checks, but before MAKE discovery,
cache inspection, directory creation, source copying, or the command request,
it inspects `MAKEFILES`, `MAKEFLAGS`, `GNUMAKEFLAGS` in that fixed order:

| Raw value of each variable | Implemented action |
| --- | --- |
| Unset or exactly empty | Permit this guard; preserve the distinction and value, without rewriting ENV or the child command environment |
| Any nonempty value, including whitespace only | Stop with `CmdStanError(:model_compile, :unsupported_make_environment, detail)`; report the first offending variable name and the unset/empty requirement, never its value |

The guard performs no stripping, shell/Make expansion, option parsing, file
lookup, or retry. It does not clear flags and proceed, alter the caller's
environment, copy settings to `make/local`, or suggest cleaning a cache.
The caller must explicitly choose a compatible launch environment for a later
authorized attempt. Existing source/root failures keep their precedence;
this new error precedes invalid MAKE and occupied-cache errors when combined.

This deliberately also rejects benign logging flags, `-j` and inherited
jobserver settings. GNU Make propagates parallelism through `MAKEFLAGS`, so
launching Julia from a parent Make recipe with nonempty flags will be outside
this initial policy. Supporting that workflow requires an actual reviewed
resource/jobserver requirement; do not silently discard its coordination.
[GNU parallel option propagation](https://www.gnu.org/s/make/manual/html_node/Options_002fRecursion.html).
Whitespace rejection is a simple supported-input boundary, not a claim that
whitespace itself changes GNU Make behavior.

All other environment values remain unchanged, including MAKE, CXX, PATH,
STAN_THREADS and SDK/library settings. That is **preservation, not approval**
of their effective meanings. Unset and empty can remain distinguishable to
Makefile logic. Makefile assignments/includes, wrappers, other variables
(including MAKEOVERRIDES/MFLAGS), and shared installation products remain
outside this guard; it is not a hermetic build profile or a resource limit.
The public readiness check remains a tool-availability check and can report
ready before this compile guard rejects a build. It still executes
`stanc --version` first; this guard does not move the public
no-execution or RNG boundary. Concurrent ENV/path changes remain unsupported.

The existing isolated manual probe passed **4,110 combined assertions on each
of Julia 1.10.8 and 1.12.5**, on the first run of this revision. It temporarily
controls these variables with `withenv` and verifies restoration. Cases cover
all eight unset/empty combinations, each variable alone, and all seven nonempty
subsets with deterministic error precedence. Inert values include ASCII and
nonbreaking whitespace, existing/missing/listed MAKEFILES paths, compact `n`,
`-q`, `-t`, `-e`, `-j2`, jobserver-shaped and logging flags, a variable assignment,
and an unknown option. No Make parser is invoked.

For each family, unsupported settings reject absent, empty, occupied and symlink
cache roots without changing fixture entries/bytes/modes/mtimes/link targets or
making a command request. Diagnostics match the name-only contract and exclude
a distinctive raw-value marker. Combined cases retain source/root failure
precedence and reject settings before invalid MAKE/occupied-cache failures.
All prior invocation/containment cases remain. **33 requests per run**, including
24 unset/empty-combination requests, reached the always-throwing trap. They
retained exact argv/working directory, no child-environment override, and the
selected environment values at the trap; the caller's selected values were
restored afterward. This proves the isolated helper contract, not behavior of
a real Make child, public-fit integration, OS sandboxing or concurrent safety.

Both runs retained all five watched source hashes. `cmdstan_backend.jl` is now
`737bcfc779f394b80185607bf6ff0b2e32e1cd036b75ed53671103a591ee8be2`;
`cmdstan_fit.jl` is
`5301b6d263d3ef3c568d6396c68e2fd7ee2fe9f1f1bac20074feeffaafb24846`.
The three Stan sources are unchanged. The quiet wrapper's six cases passed.
The 704/488/68-check, package/export and full-roster receipts remain historical,
not additional checks of this revision. The production increment is one guard
plus a readiness docstring clarification; no helper, dependency, export or
ordinary include was added. Public compatibility documentation was updated.
Only owned temporary fixtures were changed during testing; no existing
installation/cache, persistent environment, Make/compiler/stanc/model, evaluation
seed, benchmark, CI or independent reproduction was changed, executed or allocated.

The subsequent output-handoff change below makes this 4,110-check receipt historical.
Reuse stays disabled; all six M1 decisions and M0's +23.4% hold remain open;
fresh M2 replications remain zero.

#### CmdStan compile-to-sampler output handoff proposal

**Implemented, 2026-09-07 JST; build provenance and verified reuse remain open.**
The proposal heading is retained for existing links. Before this change,
the shared compile helper returned an executable path after only
`isfile`, following `_cmdstan_run` returning `nothing` on success. That check
does not exclude empty files, non-executable files or symlinks to files.
Both `_fit_cmdstan` and `_cmdstan_generalized_candidate_run` passed that string
to `_cmdstan_sample_chains`; its first operation drew chain seeds, before
draw-array allocation and JSON/initialization writes. Each chain then built
a command and launched it without checking an expected digest. Both routes'
controls retained a CmdStan version, but no model executable digest.
These are deductions from the [adapter source](../../src/cmdstan_fit.jl),
not an observed build or sampling failure. The historical 4,110-check probe
always threw at the compile command boundary, so it could not establish
post-build acceptance or sampler-entry behavior.

The implemented binding is an **in-memory `(path, sha256)` named tuple**
returned by `_cmdstan_compile_model`, not a persisted receipt or cache schema.
One private strict `_cmdstan_executable_sha256` helper in `cmdstan_fit.jl`
serves these points:

| Boundary | Implemented change |
| --- | --- |
| After a successful compile command | Validate the exact absolute output path and return its path/digest pair; do not discover an alternative program or adopt an occupied cache |
| Start of `_cmdstan_sample_chains` | Require the producer's `expected_sha256` keyword, without a default that hashes the current file as its own expectation; validate and compare before `_cmdstan_chain_seeds`, arrays, JSON or initialization |
| `_cmdstan_sample_command`, for each chain | Require the same expected digest and repeat the check before constructing the command; the existing caller immediately passes that command to `_cmdstan_run` |
| Both fit routes and their controls | Pass the compile pair's path and digest through both consumers; retain `cmdstan_executable_sha256` in controls as an observed output digest, without exposing an absolute path or asserting verified build provenance |

The strict helper rejects relative paths, symlink leaves, non-regular or
empty files, and files lacking executable permission before reading contents.
It uses `Sys.isexecutable` on the exact path, not PATH lookup or guessed mode-bit
rules. Installed Julia 1.10.8 implements that permission query; installed
1.12.5 retains it as an alias to `Base.isexecutable`. Permission checks do not
prove a valid executable format or guarantee a later launch will succeed;
`_cmdstan_run`'s launch/process error handling remains unchanged.
[Julia permission-check limits](https://docs.julialang.org/en/v1/base/io-network/#Base.isexecutable).
The helper streams the digest with `open` and `sha256(io)` using the already
imported SHA stdlib. The bridge uses the same pattern, without coupling the
CmdStan adapter to its unrelated manifest validators. `_evidence_file_sha256` is unsuitable as
a strict verifier because it can return `nothing` after an optional-probe failure.
[Julia SHA stream interface](https://docs.julialang.org/en/v1/stdlib/SHA/).

The helper keeps `:executable_missing` for absent output and uses `:executable_invalid` for
structural/permission rejection and `:executable_changed` for a digest mismatch,
including an empty/malformed expected string. Stages are `:model_compile` at the
producer and `:sampling` at consumers. Typed failures are preserved and actual
file-access exceptions use the existing failure mapper. Both consumers require
an `AbstractString` expectation; omitting the keyword raises `UndefKeywordError`
before their bodies run. Neither consumer defaults to a current-file digest,
overwrites the expected value, retries, cleans, or rebuilds.
No separate digest-format parser is needed: comparison with a freshly computed
SHA-256 hex string fails closed for malformed expected strings.

**Scope:** the initial digest observes whatever a successful command left at
that path; it does not prove source-to-binary correspondence, a trustworthy
compiler, shared-product provenance, loaded libraries, or model correctness.
Repeated reads narrow the unchecked interval but do not eliminate replacement
races, including same-bytes replacements or changes after command construction.
Trusted stable local paths and no concurrent writers remain assumptions.
Earlier public readiness still executes `stanc --version`; `_fit_rng` and
initial validation happen before this handoff. Thus early rejection
is specifically before *chain-seed draws*, not before fit entry, RNG construction
or every external command. A later-chain rejection also cannot undo earlier
chain draws/execution; retain the failed attempt rather than retrying it.

The extended isolated probe passed **4,617 combined assertions on each of Julia
1.10.8 and 1.12.5**, on its first run. It retains all existing containment and
invocation cases and the always-throwing command trap: 33 compile requests per
run, zero sampling requests. New cases use three family-labelled inert files,
not model binaries. Both digest-helper stages cover valid spaced paths, missing,
directory, empty, non-executable, file/dangling symlink and relative/empty paths.
Consumers reject wrong, empty, malformed, uppercase and padded expectations.
Changing file bytes without changing their length after a matching entry check
is rejected at the command boundary as well as on a later entry check.

An unmodified sampler/chain-seed path reaches a synthetic RNG that throws on
its first request: three matching entries stop there, with no seed produced.
All invalid entries leave its request count zero. JSON, initialization and
parse traps remain untouched. Twelve actual command vectors (warmup off/on and
progress off/on for each fixture) match expected arguments and are never run.
The literal seed in those vectors is test input, not an evaluation allocation.
Rejection checks preserve owned fixture entries/bytes/modes/mtimes/link targets;
all five watched source hashes and the selected caller environment are retained.
The quiet wrapper's six cases also passed.

`cmdstan_fit.jl` now has SHA-256
`7b1b0f8f42ebb3d3e319955d8c13a2d6944fcb89a8ec7532ae6ade8fd087ae26`.
The backend and three Stan source digests are unchanged. Production changes in
this increment are one helper and five existing compile/consumer/fit functions;
the native command runner is unchanged. In that increment, the producer return and both
consumer/control assignments were reviewed from source, **not exercised through
a successful compile or complete fit**. This is not a public integration,
file-access-error-injection, executable-format, Windows, or build-provenance
acceptance check. No package regression, export count or full-roster test was
rerun; earlier receipts remain historical. No new dependency/export/ordinary
include, existing installation/cache change, native execution, scientific draw,
benchmark, CI, migration or independent acceptance occurred.

The separate synthetic-wiring check below now exercises those assignments with
substituted completion and fixed rows, not an actual build or posterior fit;
the existing always-throwing probe is not a successful-build simulator.
Reuse remains disabled; all six M1 decisions and M0's +23.4% hold stay open;
fresh M2 replications remain zero.

#### CmdStan synthetic producer and fit-control wiring check proposal

**Implemented and checked, 2026-09-07 JST; synthetic wiring only.**
The heading is retained for existing links. The separate manual
[output-wiring script](../../scripts/probe_cmdstan_output_wiring.jl) implements
the contract below in a fresh Julia process. The existing
`probe_cmdstan_cache_identity.jl` remains byte-identical.
This new check loads the installed project/package for its real types and
deterministic helpers; it is not another stdlib-only probe. Do not install,
resolve or precompile dependencies to make it run, and do not include either
CmdStan test file wholesale: `test/cmdstan_backend.jl` performs real discovery
and `test/cmdstan_sampling.jl` performs real fits.

Reuse the nine-row fixture definition and model configurations from the
[backend tests](../../test/cmdstan_backend.jl): MFRM/PCM, MFRM/RSM, scalar GMFRM
and fixed-Q identity-correlation MGMFRM. Use package types, payload builders,
initial-value validation and summary helpers; do not build imitation fit or
target classes. Existing synthetic-fit tests demonstrate constructor use, but
their random rows are not needed here: use a fixed two-row, one-chain response
from the sampler substitute, with compatible dimensions and statistic fields.
Those rows and literal chain labels are test data, never posterior draws or
evaluation seed allocations.

In a separate module, evaluate only the unchanged source definitions of
`_cmdstan_compile_model`, `_cmdstan_compile_mfrm`, `_fit_cmdstan` and
`_cmdstan_generalized_candidate_run`, with an exact selected-name assertion.
The MFRM compile alias is a short-form method definition, not a `function` block;
the selector must account for that existing syntax. Import actual package
types/pure helpers explicitly, but **do not import or redefine the package's
methods at the substituted names**. Local definitions must not alter the real
package or the existing probe. Keep exactly these observable substitutions:

| Local boundary | Test-only behavior and fail-closed limit |
| --- | --- |
| `cmdstan_backend_check` | Return the declared owned fixture root and a visibly synthetic version; record the requested arguments, without discovery or `stanc --version` |
| `_cmdstan_cache_root` | Require the exact active test-owned cache argument before calling the real normalizer; reject missing/different arguments so a caller regression cannot write to the shared default cache |
| `_cmdstan_run` | Recognize only the exact expected compile argv, directory and environment policy; create only the predetermined absent inert output in the owned cache, or inject the declared failure. All other requests, including sampling, hard-fail without launching a process; never derive an unchecked write target from argv |
| `_cmdstan_sample_chains` | Record the received path, required expected digest and controls; compare them with the independently retained fixture expectation, then return fixed labelled rows. Never invoke callbacks, JSON/CSV I/O, chain-seed generation or a real sampler |

Keep a no-draw RNG that throws if used, passed with `seed = nothing`. Return
fixtures must carry all fields consumed by the real callers/summary helpers;
do not replace those helpers simply to make incomplete fixtures pass. This
boundary permits the actual local `_fit_cmdstan` body to construct an actual
package `MFRMFit`. For generalized models, stop at the actual local
`_cmdstan_generalized_candidate_run` result/controls; do not claim that public
`Experimental.fit` or the final GMFRMFit/MGMFRMFit conversion was exercised.

Required assertions: a direct compile call returns the exact path/digest pair;
each supported route forwards that digest unchanged to the sampler substitute
and its returned controls (and MFRM `fit_metadata`). Verify payload dimensions,
fixed-result shapes, one compile/one sampler-substitute call and no RNG request.
The retained expectation comes from the known fixture bytes, not from whatever
file the consumer later finds. Inject command failure and missing, empty,
non-executable or symlink output; the actual compile helper must reject before
any sampler-substitute call or returned fit. Repeated occupied-cache calls must
not rerun the substitute or overwrite retained bytes. Unknown command/cache
requests must throw, not merely record a failed assertion and continue writing.

No synthetic object may be published, serialized, cached, scored, registered
as an attempt, or counted as research evidence. In particular, the production
callers still set `execution = :cmdstan_cli`; that field inside a test object
does not make the substituted run a real CLI execution. Label the independent
test log as synthetic wiring only, retain source/test hashes, verify caller
environment restoration and owned-file preservation, and run through the quiet
wrapper on Julia 1.10.8 and 1.12.5. Report its count separately from the existing
4,617-check probe and any package/full-roster receipts. The module isolation is
not an OS sandbox, and an inert executable-permission file is not a native model.

The new check passed **431 assertions on each of Julia 1.10.8 and 1.12.5**,
on its first run after inspecting the four substitution boundaries. Per run:
four direct producer returns, four routed fixed results, and twenty injected
compile failures (five per configuration). All 28 occupied-cache retries refused
reuse without another compile/sampler-substitute call or retained-file change.
Unknown cache/command requests also failed closed. The selected eight package
function method tables, caller Make environment, owned toolchain fixture and
ten watched source/project/probe digests were preserved; RNG requests were zero.
The two MFRM results used the actual package constructor and `fit_metadata`;
the two generalized results stopped at internal run/controls as specified.

The quiet-wrapper logs are `quiet-command.M7XTpF` (Julia 1.10.8) and
`quiet-command.cBIKIv` (Julia 1.12.5), retained in the local temporary-log directory,
not published as study artifacts. Each records ten file hashes. The new script's
SHA-256 is `4243065f86522b54418dfbe49203876870f668919bf63b132c15224ecc670433`.
Both logs were rechecked against current files. The older 4,617-check logs and
their five source digests also still match; that probe was **not rerun**.

This increment adds only the manual script and updates this note, the roadmap
and the load-boundary note. Production code, dependencies, exports, ordinary
runner and existing probes are unchanged. No package/full-roster regression,
real native build, posterior sampling or independent acceptance is claimed.
The following decision note reviews the remaining supported-build-profile choices against the existing
[input/evidence review](#cmdstan-effective-build-inputs-and-reuse-evidence-review),
separating this checked output binding from the still-unverified producer and
shared-product provenance. Do not add a publisher or another simulator before
those choices are resolved. No build-profile adoption, actual build, sampling,
cost probe, benchmark, CI, publisher, migration or reviewer contact is queued.
Build provenance/reuse, all six M1 decisions and M0's +23.4% hold remain open;
fresh M2 replications remain zero.

#### CmdStan build-profile choices and applicability

**Decision preparation, 2026-09-07 JST; no profile selected or execution authorized.**
This closes the bounded follow-up to the synthetic wiring check, not native
build acceptance. The first decision is **whether CmdStan is in the accepted
study route at all**. The [M1-03/04 proposal](#provisional-sampler-and-diagnostic-handoff)
currently proposes AdvancedHMC, without selecting it. CmdStan-specific build
evidence is required if CmdStan is used, not a blanket prerequisite for a
Julia-only evaluation. Such an evaluation still needs its own reviewed Julia,
dependency/native-library, source, RNG, resource and all-attempt evidence.
Deferring CmdStan for the study would not waive its separate
[stable-promotion requirement](../../src/cmdstan_backend.jl).

The current evidence supports a narrower claim: the compile helper refuses
occupied caches and returns the output path and observed SHA-256; consumers
check that digest before chain seeds and command construction. The manual
4,617-check probe covers those guards and the separate 431-check probe covers
synthetic producer/control wiring. Neither establishes a successful native
build, source-to-binary provenance or a reproducible rebuild. Source inspection
also shows that `fit_metadata` retains those controls and the existing
`_mfrm_anchor_fit_hash` includes full metadata; hashing a declared digest does
not independently verify its producer. No additional fit-link test ran here.

Re-read the official **tagged v2.39.0** rules as a reference, not a selection of
the installed or future study version. They include compiler-setting files and
query the compiler during Make evaluation; the model link uses shared main,
library and optional precompiled-header products. **Inference:** a fresh model
output directory alone does not isolate or establish the origin of those inputs.
[Entry Makefile](https://raw.githubusercontent.com/stan-dev/cmdstan/v2.39.0/makefile),
[model/link rules](https://raw.githubusercontent.com/stan-dev/cmdstan/v2.39.0/make/program).
The stanc rule has local-build, release-copy and download branches; its default
download version is `nightly`. A version string or a pre-existing `bin/stanc`
alone does not select and attest the branch used by a later build.
[stanc rules](https://raw.githubusercontent.com/stan-dev/cmdstan/v2.39.0/make/stanc).
The complete transitive build/SDK/library closure remains unreviewed. Do not use
Make, including its dry-run/query targets, as a read-only inspection shortcut.

Use the existing M1-04/06 decision process, not another registry. The following
are proposals/questions for the analyst and maintainer; all remain unaccepted.

| Choice requiring disposition | Smallest proposed scope if CmdStan is needed | Missing input / stop condition |
| --- | --- | --- |
| Scientific role | Primary or explicitly scoped cross-backend comparison for the existing MFRM/RSM/PCM study; do not expand to generalized models merely because wiring fixtures cover them | Analyst and reviewer justify the role, matched target and comparison cells under M1-01/04. Do not silently switch the proposed AdvancedHMC backend or add comparison fits |
| Platform and tools | One named OS/architecture, CmdStan revision with retained submodule/source bytes, one resolved Make/C++ toolchain and SDK, and independently identified stanc bytes | Maintainer supplies the intended environment and trusted source of each input. v2.39.0 is only the reviewed example; PATH discovery and a version label are not sufficient identities |
| Effective configuration | One reviewed settings file/argv/environment contract; initially exclude custom compiler wrappers, user headers, MPI/OpenCL and within-chain threading unless scientifically needed | Record exact absent/empty/value semantics and effective compiler/link/stanc settings. Keep the existing three-variable Make guard; do not parse arbitrary Make or silently clear the caller environment. Optional-feature exclusions are proposals, not current adapter enforcement |
| Shared products and workspace | A task-owned full build workspace from reviewed inputs, with new generated shared products or separately trusted producer evidence; a fresh model directory is only one part | Maintainer must approve the workspace and provisioning/build actions. Copying an old installation copies unknown generated products too; disabling PCH does not remove the main object or libraries. No existing installation/cache may be cleaned or adopted to fill a gap |
| Producer observation and lifetime | Retain the approved input snapshot, actual compile argv/directory/settings, completion/log evidence, generated source and observed output digest, then bind that evidence before sampling | The current `_cmdstan_run` deletes its temporary success log and returns no producer receipt. An outer quiet wrapper cannot recover that discarded log. A post-fit hash cannot reconstruct it. Review this shared compile boundary only after the profile is accepted; no new callback/schema/publisher is implemented here |
| Reuse and execution budget | Keep model-cache reuse disabled for an initial authorized check; retain each attempt and its build cost separately from sampling cost | Maintainer supplies attempt/time/memory/output limits and approves build/provisioning separately from sampling. A compile check is not evaluation. Develop verified reuse only if the selected study requires it and measured authorized cost warrants it; never adopt an occupied cache or retry to replace a failure |

Input traceability, observed-output continuity, independently reproduced behavior
and bit-for-bit reproducible builds are different claims. This note does not
adopt the latter as a universal requirement for statistical recovery, nor claim
that hashes authenticate an untrusted producer, freeze loaded libraries, or
eliminate concurrent replacement. Stable trusted local paths remain the current
guard's assumption; a workspace name is not an OS sandbox.

**Disposition:** return to M1-04's backend/claim/resource choice before further
CmdStan infrastructure work. If CmdStan is not selected, mark only its specific
requirements not applicable with reasons; do not mark the other environment
requirements complete. If selected, resolve the table against the actual chosen
revision, obtain the required approval and then scope the smallest shared-boundary
change/check. No backend, version, budget, reviewer or execution date is assigned.

Only this document and ROADMAP change in this increment. The 431- and 4,617-check
logs remain source-matched and were not rerun; no package load, native discovery,
provisioning, build, sampling, benchmark, CI, publisher or reviewer contact ran.
All six M1 decisions and M0's +23.4% hold remain open; fresh M2 replications stay zero.

#### Attempt-bound fit-object scoring

The private `_mfrm_anchor_score_attempt(fit, training_bytes, heldout_bytes,
truth_records; reference)` connects the existing primitives to an `MFRMFit`;
it never calls a fitter, samples posterior rows, writes files, or replaces an
attempt. The separately retained reference supplies dataset/heldout/method IDs,
a positive attempt number, response-byte references, fit/truth digests, an
absolute source-file-to-SHA-256 map, explicit `split_chains`, `rhat_threshold`,
`ess_threshold`, and `min_e_bfmi` settings, an explicit contrast-request vector,
and `cell` (a declaration as specified below, or explicit `nothing`). No
diagnostic threshold is defaulted or frozen.
The optional required-source declaration follows the
[declared-source contract](#declared-required-source-coverage); a missing
declaration cannot claim coverage.

The consumer snapshots its in-memory inputs, verifies the referenced files and
digests, and restores the exact response bytes. It recompiles the restored
training data under the fit's family/anchor contract and compares canonical
`design_identity` values, rather than trusting a stored data signature alone.
Heldout rows may be reordered and must retain the declared category scale.
Without an explicit evaluation-panel declaration, they still must cover exactly
the training events. The [evaluation-panel extension](#explicit-evaluation-panels-and-nested-link-integration)
below permits an explicitly bound subset, not new events or role/ID swaps.
The existing labelled adapter validates each full original-design prediction,
then selects/reorders events by their labels; independent truth must match the
heldout panel exactly. This preserves finite log scores below ordinary
probability underflow. Predictive outputs remain equal-event
truth KL and observed heldout log loss, not the complete stratum analysis.

`_mfrm_anchor_fit_hash` hashes explicit full metadata, ordered parameter draws,
log densities, chain IDs/iterations, and sampler statistics. Existing metadata
validation checks the current canonical design and contiguous chain layout;
the helper also rejects empty or wrong-width draws. Prior scales, controls,
anchors, and parameter order are therefore bound, not just dimensions or the
fit's abbreviated display. Fit/truth digests use the existing `_cache_hash`
without dropping metadata field names. The returned report uses
`artifact_content_hash`, whose recursively excluded `content_hash` and
`archive_manifest` names must not be trusted through that hash alone. Nested
provenance content hashes require the separately retained full-reference and
attempt digests described above. Its Julia
version, reference (including contrast labels and limits), diagnostics, point
scores, and review flags are all bound.

The HMC screen requires a recognized NUTS backend and one statistics row per
retained draw, in the exact chain/iteration order and without warmup rows.
Finite energy summaries alone cannot establish that correspondence: the existing
diagnostic helper can summarize a gapped sequence. Missing rows/chains,
duplicates, reordering, unknown chains, and warmup contamination therefore
yield `:incomplete_trajectory`; malformed field types are integrity errors.
Missing/nonfinite/constant chain energy or unavailable depth information cannot
pass. With complete coverage, the screen uses the minimum E-BFMI across **all**
chains and the same-object diagnostic summary, including rank-normalized R-hat,
bulk/tail ESS, nonfinite log densities, divergences, and the conservative depth
warning policy above. A non-HMC object gets `:not_applicable_backend`, not an
invented HMC pass. These checks verify supplied statistics, not sampler provenance.

Each contrast request supplies a unique name, `person`/`rater`/`item` block,
positive and negative level labels, two increasing quantile probabilities,
and separate mean/endpoint MCSE limits. Limits must be positive finite numbers
or explicit `nothing`; no scientific tolerance is filled in. Labelled coordinate
lookup respects hard anchors and reference coordinates, while every person
coordinate remains estimated. Subtracting coordinates **within each ordered
draw** preserves their covariance. Existing rank-normalized diagnostics and
`posterior_mcse` then operate on that paired series. Mean and both endpoint MCSEs
are the requested targets; unavailable SD-MCSE alone is not a veto. Quantile
endpoints are reported as requested, without assuming a central interval.

Two fixed endpoints produce `:not_applicable_fixed` and no posterior MCSE,
not fabricated zero uncertainty. An accidentally constant estimated contrast
remains estimated and cannot pass. Other contrasts distinguish diagnostic
warnings, unavailable MCSE, missing precision limits, exceeded limits, and
`:screen_passed` against the supplied limits (equality is allowed). The last
status is a mechanical screen only, **not** an accepted tolerance or recovery
claim. An explicit empty roster is allowed but does not establish coverage.
The cell adapter below checks the requested labels against the supplied roster
and truth declaration; it does not infer a roster, approve its scientific
applicability, or turn raw recovery candidates into failure/paired summaries.

Diagnostics and both first-order MCSE candidates are recomputed from the same
snapshotted object; callers cannot supply a pre-passed diagnostic result.
`status=:scored` describes scoring, **not** fit-entered, diagnostic-valid, or
scientifically accepted status. A diagnostic warning does not erase an available
point score. `precision_status=:unresolved`, diagnostic/source-coverage review,
and `validation_claim_allowed=false` remain explicit. The primary-attempt join
keeps the original result even when a scored retry is present. Integrity errors
raise before a usable report is returned; the future execution ledger must
retain that original attempt/error, never drop it from planned denominators.

The synthetic checks use the actual fit type without any fit call, crossing
RSM/PCM and no/rater/item/joint/fully-fixed declarations. They compare predictions and
recomputed diagnostics; reject changed data, prior/draws, chain order, truth,
source references, and malformed policy; preserve diagnostic-invalid points;
and check reordered heldout/truth labels, underflow, policy-sensitive hashes,
own-byte serialization, and non-overwriting retries. Fabricated HMC rows exercise
complete and incomplete coverage, one low-E-BFMI chain, unavailable energies,
warmup, divergence, depth and nonfinite-density warnings. The three recognized
backend labels exercise the consumer contract only, not backend parity.
Contrast checks cover orientation, fixed/partially-estimated/fully-estimated
pairs, strongly correlated free/free rater and item coordinates, shifted chains,
accidental constants, asymmetric endpoints, limit boundaries, and malformed
requests. Source digests cover six actual repository files, not the earlier
toy source text. They are locally constructed test references, not independent
approval.

File equality does not establish that an earlier fit was produced by those
files or that every loaded dependency is covered. Full source/environment/RNG
provenance and producer-to-consumer execution still need verification on the
reviewed roster. Accepted diagnostic/contrast precision policy, scientific
truth/applicability review, curvature-aware predictive precision, durable publication,
and the full attempt ledger remain open. No new public API, executor, dependency,
fit, cost probe, or evaluation replication is added; all six M1 decisions remain
open. The initial load-order error was corrected with call-time type guards,
without changing package includes or moving the fitting core. Old candidate CI
does not cover these private helpers or later local tests.

Before the actual-anchor roster extension below, no-fit runs on
**Julia 1.10.8 and 1.12.5** each passed 25,231 anchor checks
(1,235 fit-object, including 71 retained-primary and 67 paired summary checks, 2,676 cell-target,
16 free/free covariance, and 91 curvature
checks included) plus 103 predictive/decision scorer checks:
**25,334 assertions per version**.
Both preserved the exact 186 exported API bindings. Historical comparison
bodies stayed byte-identical to HEAD, all six freeze decisions stayed open,
the runtime release hold remained unchecked, and 43 local link occurrences
(18 distinct paths) resolved. These runs used `sh scripts/quiet_command.sh`:
one success line, or the final 80 log lines on failure, with the original exit
code and complete private temporary log retained. The separate
`python3 test/quiet_command.py` check passed six cases covering quiet success,
argument preservation, stdout/stderr capture, failure-tail length, absent commands,
child signal exit, and empty invocation. It adds no test selection, retries,
deadline mechanism, or changes to the historical runtime observer.
The previous fit-binding check's targeted in-memory bypass of the fit-digest
comparison, retaining its shape/chain validation, produced 24 expected test
failures and zero errors; it was not repeated for this extension. No source file
was changed by that mutation check. The earlier Julia 1.10 failure exposed the
mean-versus-SD MCSE gate described above and remains fixed in these final runs.
No CI dispatch, fresh fit, or sampler calibration is claimed.

#### Cell-bound contrast targets and recovery candidates

`_mfrm_anchor_cell_targets` prepares a supplied cell declaration before contrast
recovery is scored. It binds a nonempty cell ID, the actual canonical design ID,
and the retained log-truth digest to complete labelled person/rater/item truth
records and a target roster. Every target declares its name, facet, oriented
endpoints, and primary/secondary role. Requested contrasts must match the whole
roster exactly by name and endpoints; order may differ. Unknown/duplicate labels,
omitted or substituted targets, invalid values, and mismatched references reject.
Truth records and returned target rows keep labels as values, not dictionary
keys that `artifact_content_hash` could mistake for `content_hash` or
`archive_manifest` metadata. No arbitrary-label hash exclusion is introduced.

For each rater/item facet, compare every fixed coordinate (including implicit
references) with its labelled truth. The offsets must agree with the first fixed
offset within the explicitly supplied nonnegative `anchor_atol`. This checks a
common additive gauge shift, not unchanged priors or posterior invariance. It is
conditional on the minimal additive model and its existing validation boundary;
component-specific gauges and generalized models are not handled. Both-fixed
targets are identified from the design before looking at any draws and remain
N/A for posterior coverage. Common-shift, endpoint/interior, and fully fixed
cases therefore cannot silently substitute a secondary target for the primary.

Model status (`declared_correct`, `misspecified`, or `unresolved`) and likelihood
identification (`declared_identified`, `unidentified`, or `unresolved`) are
explicit **declarations**, not independently verified conclusions. Supplied
parameter truth and log truth are linked by the retained declaration; the
adapter does not independently reconstruct the full generating model from
facet truth alone. Model misspecification, declared nonidentification, or
incompatible common-shift offsets produce distortion-only rows. Unresolved
declarations or absent `cell` produce no recovery row. Per-target point errors
remain descriptive when coordinate truth is available, including fixed targets.
All scientific declaration review remains required.

For a declared compatible estimated target, reuse `_parameter_recovery_rows`
on the same paired draws as the contrast MCSE. Its current central-interval
contract is used only for complementary requested quantiles (up to eight
Float64 epsilons of arithmetic rounding); an asymmetric interval is retained
for MCSE but marked `unsupported_recovery_interval`, never silently changed.
These are `candidate_available` recovery rows, with diagnostic selection **not**
applied. Their `covered`/`flag` fields do not establish metric validity. The
retained-primary adapter below now applies the supplied diagnostic/precision
screen and cell/target bindings before calling existing recovery/binary summaries.
It keeps unavailable outcomes in planned denominators and fixed N/A targets out
of coverage trials. Cross-method paired aggregation remains separate work.

The no-fit checks cover 29 synthetic anchor declarations per family (58 across
RSM/PCM): baseline, endpoint/interior, single and fully fixed boundaries, and
crossed common/differential shifts. The roster includes the three drafted
primary contrasts plus both placement secondaries for the check; this does
not add them universally to the unfrozen study roster. End-to-end checks use
the existing independent log-truth fixture and fit-object consumer. Further
checks retain mismatched/unresolved declarations, asymmetric intervals,
special label names, and N-Z0 rejection. An initial negative test accidentally
converted a Boolean truth value to Float64; the fixture now preserves its type.
An initial attempt to construct N-Z0 exposed the pre-existing spec rejection;
the test now asserts that boundary, without weakening validation or duplicating
its rank check. No fits, full-roster acceptance, or independent review occurred.

#### Retained-primary recovery summaries

The private `_mfrm_anchor_recovery_summary(plan, attempts; cell, request,
diagnostic_policy, attempt_hashes)` is a read-only consumer for **one cell,
one method, and one labelled target**. It reuses `_mfrm_anchor_primary_attempts`,
`parameter_recovery_summary`, and the existing binary count/Wilson-envelope
helper. It neither runs fits nor creates an execution ledger. Each planned row
supplies dataset/heldout/method IDs and a separately retained primary scoring
reference digest, or explicit `nothing` if that binding is not yet available.
Missing bindings do not remove the dataset from the plan. One dataset cannot
be counted twice through different heldout IDs in the same summary.

The separate `attempt_hashes` map keys all supplied attempts by dataset,
heldout, method, and attempt number and contains `_cache_hash` of the full
record, including metadata fields normally excluded by `artifact_content_hash`.
Missing/extra digests, duplicate or unplanned attempts, orphan retries, altered
contents, and inconsistent report/reference IDs reject. Scored records also
must satisfy their existing artifact hash. This is content binding to the
caller's retained references, not independent authorization or proof of execution.
Retry content/identity is checked and counted, but it never replaces the
primary record or contributes to its recovery denominator.

For a scored primary, check the complete retained reference hash, prepared cell,
diagnostic policy, and the selected request/target (including role, oriented
endpoints, truth, interval, and MCSE limits). Check the recovery row's own
target/truth/interval identifiers too. Only compatible estimated targets with
complete passing HMC and contrast diagnostics, available in-limit mean and
endpoint MCSE, and finite recovery quantities enter `n_screen_eligible`.
The actual MCSE values are checked even if the supplied row says `screen_passed`.
This count is descriptive eligibility under supplied declarations, **not** an
independently accepted metric-valid count. All review/claim restrictions remain.

Each planned primary retains its reported disposition, selection reason, and
available point error/recovery row, including diagnostic/precision failures.
Absent records stay `not_recorded`; retained pending, generation/structural,
fit-failure, and scoring-failure dispositions keep their supplied reason.
The result reports planned, reported-primary, scored-primary, eligible, and
additional-attempt counts. It explicitly does **not** infer fit-entered or
fit-completed counts from `status=scored`; lifecycle provenance is still required.

Conditional bias/RMSE/interval coverage reuse the existing recovery summary.
Across-dataset bias/MSE MCSE uses corrected sample SD divided by sqrt(m), with
MCSE missing for m<2. Binary coverage reports c/m, c/N, and the unresolved
completion range; its descriptive Wilson intervals are 95%, not a selected
study acceptance threshold or simultaneous guarantee. Empty eligible subsets
do not get zero bias or zero MCSE. Fixed N/A, distortion-only, and unresolved
cell definitions receive no nominal-coverage denominator/envelope. Nonfinite
recovery stays unresolved; nonfinite aggregate arithmetic is explicitly flagged.
There is no borrowed finite upper bound for missing unbounded squared errors.

The no-fit integration generates scored reports from synthetic fit objects and
saved response bytes, using eight planned datasets: five scored primaries,
three eligible rows, two covered intervals, one reported fit failure, one
reported structural rejection, and one absent primary. A scored retry is kept
separate. Checks recover conditional coverage 2/3, joint coverage 2/8, and the
completion range [2/8, 7/8], plus bias/MSE MCSE; input order does not affect the
result. Mutation checks recompute report digests while changing planned
references, cell/target/interval fields, or status/MCSE consistency, to test
semantic guards as well as hash checks. Singleton/empty subsets, missing
bindings, duplicate dataset counts, and N/A definitions are also checked.
These are synthetic arithmetic/integration checks, not eight fresh evaluations.
The paired adapter below now joins these original reports before taking
differences; single-method summaries alone are not permission to subtract
filtered marginal means.

#### Same-data paired recovery

The private `_mfrm_anchor_paired_recovery(groups; comparison)` consumes two or
four original recovery groups. Each group supplies the existing `plan`,
`attempts`, prepared `cell`, `request`, `diagnostic_policy`, and separately
retained `attempt_hashes`. The explicit comparison is a tuple of distinct
`(method, weight)` records with balanced +1/-1 weights: a directed pair or
four-method interaction. It does not infer the comparison from observed results
or infer anchor semantics from a method's name. The existing recovery consumer
revalidates each group, including retained primary-reference hashes and retries.

All methods must retain exactly the same planned dataset **and heldout** roster,
or the call rejects instead of silently intersecting different plans. The
oriented target, true contrast, target role, interval, precision limits, and
diagnostic policy must match. Cell IDs, design hashes, and fit hashes may differ
across methods. Every available scored primary, even one failing a screen, must
match the other methods' full training/heldout byte references, independent
log-truth digest, labelled coordinate-truth declaration, source-file map, and
any declared required-source roster. This checks supplied references and
declared coverage, not the roster's execution completeness, RNG lineage, the
correctness of method labels, or independent generating-model approval.

For each shared planned dataset, form the signed sum of contrast errors and,
separately, squared errors only when **all** methods are screen-eligible. The
mean squared-error difference is not the square of the mean-error difference
and is not an RMSE difference. Both metrics use the same finite subset; corrected
sample SD divided by sqrt(m) gives each across-dataset MCSE. MCSE is missing for
m<2, and empty subsets receive no zero estimate. Available nonfinite arithmetic
is retained and flags the comparison rather than being silently dropped or
capped. The output reports planned, jointly screened, and common finite counts,
each method's unavailable reasons/counts, eligible rows outside the common
subset, and all original primary dispositions/point errors. A successful retry
cannot enter the comparison. Fixed N/A, distortion-only, or unresolved-cell
groups make the comparison inapplicable, not a nominal recovery comparison.

Synthetic scored objects check all four directed B/R/I/RI pair labels and the
RI-R-I+B interaction, without fitting or claiming those objects implement four
real anchor regimes. The pair has five planned datasets, two common eligible
datasets with differences 2 and 4, mean 3, and MCSE 1; subtracting marginal means
would give a different answer because each method has an extra eligible dataset.
The quartet retains the same two common datasets. Tests also exercise input
order, retries, singleton/empty subsets, applicability, different cell IDs,
unmatched plans/heldout IDs, and rehashed reference mutations on both eligible
and diagnostic-failed rows.

The actual-anchor integration below extends this arithmetic check to the 130
primary/anchor-sensitivity cells. Predictive-loss pairing remains unimplemented:
these contrast screens do not solve predictive curvature/precision or justify
treating infinite log loss as ordinary missing data. All outputs remain
conditional descriptive preparation with no lifecycle counts or validation
claim permission.

#### Actual-anchor roster integration

Reuse the existing finite M1 anchor roster and shared five-target declaration,
not a second execution roster. The no-fit matrix contains the 16 primary cells
(four B/R/I/RI regimes on dense/sparse RSM/PCM data) and 114 sparse sensitivity
cells (57 regimes for each family). Dense sensitivity cells are not added.
Each actual package design has 40 persons, four raters, four items, and four
categories, with the declared 640/320-event panel. These are **130 synthetic
fit objects, not 130 fitted datasets or evaluation replications**.

Each data cell retains one deterministic training table and a distinct,
reversed-order heldout table, shared unchanged by all its anchor methods.
Independent recurrence-based log truth, labelled coordinate truth, actual
design/fit hashes, source-file references, and all five contrast requests feed
the existing completed-object consumer. Response bytes and scored records are
retained in memory here; this is not a durable archive or execution ledger.
Synthetic 4-by-40 draw rows have centred
noise and explicit nonzero coordinate errors; their fabricated NUTS statistics
exercise the diagnostic path without a sampler call. These objects, test-only
precision limits, and reused noise do not establish posterior correctness,
independent chains, independent dataset replications, or scientific calibration.

An independent label/fixed-level lookup computes each of the 650 target errors
and applicability classes before reading the scorer's result. Endpoint and
interior placements check that a fixed primary 3-2 contrast receives no interval
recovery, while the declared secondary 2-1 contrast remains partially estimated.
Fully fixed facets retain N/A instead of perfect coverage. Common shifts keep
contrast recovery applicable, without asserting prior/posterior invariance.
Differential errors make estimated targets distortion-only; their available
point errors remain visible even though nominal recovery is unavailable.

The matrix passes original scored reports and separately retained digests into
the paired adapter for 172 method comparisons, each checked against all five
targets: **860 comparison/target cases**. This covers the four directed primary
pairs and RI-R-I+B interaction, each sensitivity's clean comparator, the S
regimes' additional B comparison, and all 16 crossed-error quartets per sparse
family using their same-constraint D-RI single-perturbation controls. Testing
secondary targets across this matrix is an applicability stress check, not a
promotion to primary study claims or a replacement after observing failures.

Each comparison retains a second, absent primary in its planned denominator.
Applicable comparisons therefore have N=2 and one common scored dataset;
their bias/MSE differences match the independent coordinate-error calculation,
and their across-dataset MCSE remains missing. Fixed/distortion-only comparisons
have no nominal recovery estimate or manufactured coverage denominator, but
still retain the scored point errors and per-method applicability. The preceding
two-dataset arithmetic test remains the check of non-missing paired MCSE.

This covers the primary/anchor-sensitivity portion, **not all 266 candidates**.
At that checkpoint, 136 link, information/category, prior/start, and response/link-
misfit cells still needed the corresponding saved-data/scoring integration.
The evaluation-panel extension below now covers the 32 nested-link cells:
their predictive target is the common 320-event base panel, a strict subset of
their 352/384 training events. This requires a bound evaluation-panel contract,
not a silent intersection or scores on each topology's different training
distribution. Preserve N-Z0 structural rejections and never bypass the current
specification rank guard.
Do not relax same-data pairing: separately generated topology datasets remain
unpaired even when their evaluation event labels coincide. Predictive precision,
RNG/lifecycle provenance, practical tolerances, budgets, and independent review
remain open. That anchor-only increment changed tests and documentation, not
the package implementation, exports, dependencies, executor, or runtime observer.

Before the link extension, both local **Julia 1.10.8 and 1.12.5** runs passed **39,973 anchor assertions**
(including 15,693 in the actual-roster/control testset) plus 103 existing
predictive/decision scorer assertions: **40,076 per version**. Both preserved
the exact 186 exported API bindings. The quiet wrapper's six checks also passed;
successful full logs were retained without flooding terminal output. The three
historical bodies, six open M1 decisions, runtime release hold, and 43 local
link occurrences were preserved/checked. These are local synthetic tests, not
new CI evidence, posterior recovery, reviewer acceptance, or fresh evaluations.

#### Explicit evaluation panels and nested-link integration

The existing attempt consumer accepts an optional `reference.evaluation_panel`:

```julia
(panel_id = "nested/base-320", weighting = :equal_event, events = base_events)
```

Here `base_events` is a complete, nonempty labelled event vector, not a selector inferred
from observed scores. Each event has only `person`, `rater`, and `item` fields.
Events must be unique, occur in the restored training data, and match the
heldout event set exactly. Only equal-event weighting is supported; category
scales must match. Empty/malformed declarations, duplicates, new events,
unknown/empty labels, extra outcome/weight fields, or incomplete/extra heldout
events reject. If the declaration is absent or explicit `nothing`, the original
full-training-event requirement remains. An explicit full panel produces the
same scores as that legacy path. Event-order permutations do not alter scores,
but do change the separately retained reference and report digest.

No new predictor or heldout model is compiled. For each original posterior draw,
reuse `linear_predictor_values` on the **training design**, validate its entire
labelled log-probability table, and select rows by event labels in heldout order.
Thus invalid predictions outside the selected subset are not silently hidden,
and the fit's parameter order, chain layout, and all draws remain intact.
Independent log truth must itself cover exactly the evaluation events/categories;
an over-complete truth table is rejected rather than silently filtered.
The report's `evaluation_scope` records whether a panel was declared, its ID,
equal weighting, and training/evaluation event counts. The existing retained
reference hash binds the full declaration alongside data/truth/source digests;
there is no second authorization mechanism or claim of preregistration by hash.

The paired recovery adapter additionally requires matching full evaluation
declarations. A shared panel ID or the same event labels do not establish shared
data: training/heldout IDs and bytes, truth, source references, and the planned
denominator still must match. Rehashing an altered declaration in one method
does not make it comparable to another. Separate topology datasets remain
unpaired, including in synthetic checks where event labels and score patterns
coincide. This extension does not implement paired predictive-loss precision.

The existing no-fit roster test now also constructs the **32 positive-link
cells**: both families, N-C4/N-C8/N-E4/N-E8, and B/R/I/RI. Within each data cell,
methods share deterministic response bytes; each topology has distinct dataset
references. Training has 352 or 384 events and heldout has only the common 320
base events, in reversed order. That heldout graph by itself is the N-Z0
boundary: attempting to compile it still rejects under all four anchor regimes.
Prediction from the connected training fit does not require compiling it, and
the production specification rank guard is unchanged.

For all 32 synthetic objects, a separate recurrence-based oracle reconstructs
each base-event/category probability from labelled draw coordinates and the
actual fixed anchors. KL uses mean probabilities before the logarithm; observed
heldout loss uses the stored base-panel scores. Both are averaged over **320**
events and checked against the consumer. The existing primary pair/quartet
checks add 200 comparison/target cases across these eight data cells. The
combined integration matrix at this checkpoint was **162 cells / 1,060 comparison-target cases**, not
162 fits or 1,060 evaluation replications. Explicit-panel negative tests cover
legacy fallback, subsets, permutations, malformed/extra declarations, scale/
truth mismatches, and rehashed incompatible pairing references.

All draws/statistics are fabricated and all new response/report records are
held in memory. Predictive curvature and precision flags remain unresolved;
these checks do not calibrate an estimator or close any M1 decision. At this
checkpoint **104 candidate cells** still needed integration; the subsequent
40-cell information/category increment is recorded below. RNG/lifecycle
provenance, budgets, independent review, and
fresh evaluation remain separate open gates. No exports, dependencies, fitter,
execution ledger, or M0 runtime observer are added or changed here.

Both local **Julia 1.10.8 and 1.12.5** runs passed **44,085 anchor assertions**
(including 19,766 in the combined anchor/link roster testset) plus 103 existing
predictive/decision scorer assertions: **44,188 per version**. Both preserved
the exact 186 exported API bindings, and the quiet wrapper's six checks passed.
The three historical bodies, six open M1 decisions, runtime release hold, and
43 local link occurrences were preserved/checked. These runs are local synthetic
integration evidence only: no CI dispatch, fresh fit, evaluation replication,
scientific threshold adoption, or independent review is claimed.

#### Information and category-support integration

Reuse the same actual-roster testset and completed-object consumer for all
**40 information/category cells**: RSM/PCM, S20/S20-L/S20-H/S20-G1/S20-G2, and
B/R/I/RI. This checkpoint brought the synthetic matrix to **202 candidate cells / 1,310
comparison-target cases** (250 additional pairs/quartets by target), not fits
or fresh evaluation replications. At that point the 64 prior/start and response/link-misfit
candidates still needed corresponding integration. Local verification results
for this increment are recorded below.

The twenty retained people keep their original labels and forty-person truth
grid, including P10/P30; each has eight ratings, and each rater/item has forty.
L/H shift only person truth by minus/plus four. G1/G2 perturb each full RSM/PCM
step vector as declared above, retaining finite sum-to-zero steps and the same
four-category scale. Fabricated parameter draws and trajectory statistics feed
the existing diagnostics, labelled contrasts, and predictive scorer. None is
a posterior sample from an actual fit or evidence of practical prior adequacy.

The response scaffolding deliberately includes endpoint/interior-empty tables
for the four stressed profiles. These are constructed boundary fixtures, **not
DGP samples redrawn or filtered until the target category disappears**. Existing
`validate_design` and `ordinal_response_pattern_audit` retain all declared
categories and inspect overall, item/category, and rater/category occupancy.
Overall support does not imply support in every stratum: the baseline fixture's
additional item-wise gaps are retained, not filled or treated as new study cells.
The ordinary unused-category warnings do not become fit prohibition. A separate
all-zero boundary fixture for each family/profile is rejected before compiling
all four anchor specifications. Each method's synthetic summary retains one
scored case, one `structurally_rejected` case with the response digest/reason,
and one unrecorded case: three planned, one eligible, no replacement or retry.
This exercises existing dispositions; it does not create an all-constant study
cell, execute a fit, or establish persistent lifecycle provenance.

The private consumer now includes `category_totals`, in declared category order:
observed heldout count, fixed-truth expected count, and posterior-mean-prediction
expected count. All use the **evaluation events**, not the training-event
denominator. Missing observed categories remain in the output with zero observed
counts and positive expected counts for these finite stress truths/draws.
These are descriptive Float64 point totals; very small masses may underflow,
and no category/threshold interval, MCSE tolerance, or acceptance claim is added.
Log-score calculations retain the existing log-probability path. A separate
category-recurrence oracle reconstructs all synthetic draws on the selected
events, checks KL after probability averaging, checks heldout loss using actual
stored labels/scores, and checks all four expected/observed category totals.

The eight existing S40 B/R/I/RI objects additionally supply a **secondary
160-event view**, with panel ID `information/common-160`, by restricting their
heldout rows and independent truth records to S20 labels. The original 320-event
reports and input bytes remain unchanged; fit digest, dataset/heldout/method/
attempt identities, and contrast scores are retained. Subset bytes/truth and
the explicit panel have their own bound scoring reference. These eight views
are not eight new cells, datasets, fits, or primary attempts: the primary-attempt
join rejects combining both views as duplicate attempts. A future persistent
artifact owner must preserve this distinction and link the subset view to its
retained full input; this test is not that artifact pipeline.

S20 has separately constructed response records, not S40's training outcomes.
Within each family/profile all anchor methods share bytes and evaluation
declarations. Across sizes/profiles, identities remain different and attempted
same-data pairing rejects. A shared panel ID/event roster does not establish
paired sampling or make raw cross-profile loss differences isolated anchor
effects. The consumer's strict full-panel fallback, same-data reference checks,
N-Z0 rank guard, unresolved predictive precision/curvature, and all six open M1
decisions remain unchanged. No dependency, public export, fitting algorithm,
execution ledger, or runtime observer is introduced by this increment.

The following increment connects the **32 prior/start cells** using existing
same-data controls and native prior/start helpers. The 32 response/link-misfit
cells follow. Budgets, source/RNG/lifecycle provenance, independent freeze review,
and fresh evaluation remain separate open work.

The initial Julia 1.10.8 run exposed eight incorrect test expectations equating
overall and item-wise category support; the other 29,560 assertions in that
roster testset passed. The still-running Julia 1.12.5 check of that superseded
test was deliberately interrupted, with its log retained. The correction compares
each stratum with counts from its actual labelled input rows; it does not alter
the response fixture, model validation, category scale, or scoring algorithm.
The corrected **Julia 1.10.8 and 1.12.5** runs each passed **53,967 anchor
assertions** (29,648 in the combined actual-roster testset) plus 103 existing
predictive/decision scorer assertions: **54,070 per version**, with the exact
186 exported API bindings preserved. The quiet wrapper's six checks also passed.
The three historical bodies, six open M1 decisions, and runtime release hold
remain preserved; 59 local file-link occurrences resolve to 31 distinct targets.
These are local synthetic checks, not CI, posterior validation, independent
protocol acceptance, or authorization to generate fresh evaluation data. No
fresh fit, evaluation replication, cost probe, benchmark, or CI dispatch ran.

#### Prior and start integration

Reuse the actual-roster testset and completed-object consumer for the **24 prior
and eight start methods**, without changing production code or sampler defaults.
At this checkpoint the synthetic matrix covered **234 candidate cells / 1,510 comparison-target
cases**. The additional 200 cases are 40 same-data pairs across five targets:
prior alternatives against P(1), shifted versus clean coordinates at P(0.5)/P(2),
and jitter 0.5 against 0.02. Existing P(1) gauge comparisons and all controls are
reused once, not re-counted. The 32 response/link-misfit candidates were outside
that increment; their integration is recorded below.

Each variant keeps its existing data/anchor cell ID, saved training/heldout
bytes, labelled truth, and category scale, with a distinct prior/start method ID.
Both families' six existing controls and sixteen variants give **44 configured
objects** checked against the declared `MFRMPrior` fields and `init_jitter`.
The existing fit hash already includes those native metadata: changing only a
prior or jitter while retaining the original fit reference is rejected. This
binds recorded settings; it does not prove that a real sampler used particular
start vectors or RNG states. Durable source/RNG/attempt provenance remains open.

An independent Normal-density calculation checks the actual prior on free
coordinates, including its scale-dependent normalizing constants; hard anchors
add no density terms. Prior variants preserve likelihood and probability truth
but change the posterior target. For matching shifted/clean geometries the log
prior difference scales as `1/c^2`, while probability truth remains invariant.
Start variants preserve the same prior/posterior target. Native initialization
helpers start at zero, not truth, then reproduce four jittered starts with test
seed 17; jitter 0.5 gives 25 times the increment at 0.02 under that helper replay.
The base vector stays unchanged and all initial log posteriors are finite.
This is not an evaluation seed allocation, a cross-backend guarantee, or evidence
that either start scale is adequate for sampling.

The independent category-recurrence oracle checks all 320 heldout events, four
categories, and 160 fabricated draws for each new method: probability averaging
before KL, actual saved heldout scores, and observed/truth/predicted category
totals. The original eight secondary S40 views are unchanged; variants do not
create additional subset views or overwrite primary reports. Synthetic draw
offsets exercise paired contrast-error arithmetic, not an inferred effect of
prior or jitter on genuine posterior draws. Predictive curvature/precision
remains unresolved; the later whole-roster increment above adds descriptive
predictive-loss summaries.

Each start method also has one deliberately fabricated `fit_failed` primary
disposition on its second planned case. Its summary retains two planned cases,
one scored primary, one failed primary, and no additional attempt; paired
comparisons retain only the common eligible case and have unavailable MCSE.
Distinct start methods can coexist as primary attempts on the same data;
relabeling an isolated alternative as the control's attempt 2 does not supply
the missing control primary. No fit was run to manufacture these failures,
and this in-memory check is not a persistent execution ledger.

Both local **Julia 1.10.8 and 1.12.5** runs passed **59,332 anchor assertions**
(35,013 in the combined actual-roster testset) plus 103 existing predictive/
decision scorer assertions: **59,435 per version**. Both preserved the exact
186 exported API bindings. The quiet wrapper's six checks passed; the three
historical bodies, six open M1 decisions, and runtime release hold remain
preserved. All 59 local file-link occurrences resolve to 31 distinct targets.
At that checkpoint the nested-misfit exposure enumeration above was a separate
no-fit arithmetic check, not integration of the remaining 32 cells. These were local synthetic
checks: no fresh fit, evaluation replication, cost probe, benchmark, CI dispatch,
scientific setting adoption, or independent acceptance is claimed.

#### Response and link-misfit integration

The existing actual-roster testset now checks the remaining **32 misfit cells**:
RSM/PCM, S-X/N-C4-X, both coefficients minus/plus 0.35, and B/R/I/RI. This brings
the finite matrix to **266 candidate cells, 30 candidate data-block IDs, and
1,710 comparison-target cases**. Eight new data blocks have distinct
training/heldout IDs; coefficient-zero controls are reused, not added again.
No production scorer, fitting kernel, default, dependency, or public export is
changed. Local verification of this increment is recorded below.

The independent category recurrence supplies base log p. The test applies the
quadratic tilt using a maximum-shifted log normalizer and checks all training
events against a separate 256-bit category-equation oracle: finite positive
probabilities, normalization, unchanged unaffected events, adjacent-category
odds changes, and endpoint/interior odds ratios. The retained predictive truth
is **q**, not p. Supplying unperturbed truth with the original q reference is
rejected. This binds the supplied truth records, not the authority or scientific
correctness of a caller's declaration; the independent oracle is a separate check.

Responses remain deterministic labelled scoring scaffolds, not random samples
from q; parameter draws and NUTS statistics are fabricated. These records do not
constitute fresh evaluation replications, a production misfit generator, fitted
pseudo-true parameters, or evidence of sampler recovery. Within each data block,
anchor methods share the same saved training/heldout records and q. Cross-DGP
pairing with the corresponding coefficient-zero control or another misfit block
is rejected, even when fabricated score patterns coincide. No common-random-
numbers allocation is inferred from those patterns or a shared event panel.

Every primary predictive report uses 320 events. The S-X split is 80 affected /
240 unaffected. N-C4-X retains its separate 16/336 exposure audit over 352 training
events, but its `nested/base-320` evaluation split is **8/312**. Reusing explicit
evaluation panels yields **64 secondary views** for the 32 methods, not new fits,
cells, datasets, or primary attempts. Each view keeps the original attempt and
fit digest, with separately bound subset response/truth records and panel ID.
Primary input/report hashes and contrast results remain unchanged; joining a
primary and its view as two primary attempts is rejected. The eight earlier
S40 information views remain unchanged.

An independent recurrence checks all 160 fabricated draws and four categories
on each full/subset view. Its KL uses probability averaging before scoring
against q; heldout loss uses the actual saved category labels. Affected/unaffected
point scores reassemble to the primary score with **evaluation-event weights**.
Observed, truth-expected, and prediction-expected category totals also reassemble,
including endpoint (0,3) and interior (1,2) bands without changing the scale.
These identities do not justify averaging subset MCSEs or adopting a predictive
precision threshold; curvature-aware precision remains unresolved. Descriptive
pairing is checked in the later whole-roster increment above.

Compatible baseline anchors do not make the response model correctly specified.
All component contrasts retain descriptive point errors and `distortion_only`
status, with no recovery rows or nominal-coverage summaries. The additional
200 paired-recovery cases are deliberately **inapplicable comparisons**, not
200 recovery estimates. Each method retains one scored primary and one fabricated
`fit_failed` primary: two planned/reported, zero recovery-eligible, no additional
attempt or replacement. The failure is a test input, not an executed fit, and
the in-memory summary is not a persistent all-attempt ledger.

At the response/link-misfit checkpoint, both local **Julia 1.10.8 and 1.12.5**
runs passed **69,025 anchor assertions**
(44,706 in the complete candidate-roster testset) plus 103 existing predictive/
decision scorer assertions: **69,128 per version**. Both preserved the exact
186 exported API bindings, and the quiet wrapper's six checks passed. The three
historical bodies, six open M1 decisions, and runtime release hold remain
preserved; all 59 local file-link occurrences resolve to 31 distinct targets.
These are local synthetic checks, not CI, posterior recovery evidence, or
independent protocol acceptance. No fresh fit, evaluation replication, cost
probe, or benchmark ran. All six M1 decisions remain open.

The [paired predictive-loss contract](#paired-predictive-loss-contract-and-error-decomposition)
specifies and checks the arithmetic and Monte Carlo/curvature limits; its
descriptive report consumer now connects primary and secondary reports across
the whole candidate roster, as recorded above. Do not infer
scientific settings, an execution budget, independent review, or pipeline
readiness from completion of the finite cell roster. No fresh fit, evaluation,
cost probe, benchmark, or CI dispatch is authorized by this increment.

### Whole-candidate resource arithmetic, not a selected allocation

The old A/B/C alternatives below remain confined to their original 130 cells.
Two whole-266-cell references make the size of the pending choice explicit:

| Illustrative allocation | Planned fits | Distinct training datasets, each with its own heldout block |
| --- | --- | --- |
| 400 per primary cell, 100 per other cell | 31,400 | 4,200: 4 primary data cells x 400, plus 26 new data cells x 100 |
| 400 for every candidate fit cell | 106,400 | 12,000: 30 data cells x 400 |

There are 26 new data cells (8 link + 10 information/category + 8 misfit);
anchor/prior/start comparisons reuse data and controls. The first allocation
does not give sensitivity cells the proposed primary precision. Both exclude
cross-backend checks, probes, remediation, and setup; neither is authorized.
At 4,000 retained draws, 54 maximum free coordinates, and Float64 storage, the
raw parameter-draw numeric contents alone have conservative upper bounds of 54.3 GB
or 183.9 GB, respectively (decimal units). Diagnostics, data, logs, serialization,
and predictions add to these bounds; retaining every draw's full event-category
probabilities is not included. These are arithmetic, not measured outputs.

#### Current resource snapshot and bounded rehearsal proposal

Read-only inspection on **2026-09-07 JST** found 60,386,044 available 1,024-byte
blocks: **61.835 GB / 57.589 GiB**. The checkout and `/private/tmp` report the
same Data filesystem; their free space is not two independent budgets. The
machine reports **36 GiB physical memory, 14 logical CPUs**, and about
**20.897 GiB currently used swap**. Swap usage alone does not establish current
memory pressure or available RAM. These are transient host observations, not
reserved resources, Dropbox quota, a concurrency recommendation or a cost probe.

The 31,400-fit raw-draw upper-bound budget is 54.259 GB, leaving only 7.576 GB
of that disk snapshot before all other retained outputs, temporary writes and
system use. The 106,400-fit upper-bound budget is 183.859 GB. These conservative
budgets are not measured sizes or lower bounds proving an actual run's size;
they nevertheless do not demonstrate safe whole-panel storage capacity here.
Do not launch either full allocation or delete/compress retained evidence to
make it fit. Review a smaller claim/allocation or an explicitly approved storage
destination after actual bounded output measurements; do not count cloud sync
or another path on this filesystem as additional local capacity.

**Analyst-proposed rehearsal ceilings, not adopted or enforced:** at most one
fit process at a time; 4 GiB aggregate worker/child resident-memory ceiling;
2 GiB total rehearsal output including temporary files and logs; retain at
least 30 GiB local disk headroom; 15 minutes per complete attempt and 2 hours
for the whole rehearsal including setup/scoring. At most eight primary pilot
attempts and zero automatic retries. Time/RSS ceilings are conservative review
choices, not requirements inferred from free disk or measured sampler costs.
Recheck host availability before any launch; inability to enforce or observe
a required limit prevents launch. Exceeding a limit stops execution and retains
the attempt as failed/unresolved according to observed evidence, never as a
successful or replaceable primary result.

A candidate eight-attempt roster is RSM/PCM x dense/sparse x B/RI, with one
separate pilot dataset per family/design shared by B and RI. Keep the existing
four-chain, 1,000-warmup/1,000-retained-per-chain proposal, P(1) and non-truth
reference start for setting-matched rehearsal. No dataset, seed or attempt ID
has been allocated. This small roster checks selected primary execution paths;
it does not cover all 266 cells, certify worst-case cost or establish recovery,
and its eight attempts may not all finish within the total cap. Pilot outputs
never enter evaluation denominators. Full-study time, output, memory and
additional-attempt budgets remain unselected.

The maintainer must choose scope and total time/memory/output/concurrency caps
before a setting-matched cost probe can be specified and launched. Probe cases
must cover the retained computational stress questions with finite attempt caps;
their separate pilot outcomes never replace evaluation datasets. If resource
limits cannot support the chosen precision, narrow claims or revise allocation
before freeze. No fitting or cost probe ran for this proposal. Local work has
connected diagnostic/contrast screens, declared cell targets, retained-primary
recovery/failure summaries, and same-data contrast-error pairing across the finite
candidate roster. The paired predictive-loss arithmetic/error decomposition and
whole-roster descriptive report connection are now in place; the next bounded
step checks source/environment coverage and separates retained hashes from
actual RNG allocation and lifecycle evidence. Preserve unresolved precision
without choosing practical tolerances or inventing reviewer/budget approval.

The earlier prior-proposal no-fit run passed 21,154 assertions on Julia 1.12.5 (29 precision/
derived-MCSE checks and the expanded prior-profile checks included); the separate
36-configuration audit completed. For current verification, use the latest
integration record above; those earlier checkpoints do not certify CI or later increments.
All six freeze decisions remain open.

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
