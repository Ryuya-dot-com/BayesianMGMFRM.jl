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
| M1-02 — open | Declare separate pilot/evaluation truth, response, holdout, and sampler seed namespaces; specify dataset sharing across anchor regimes and any common random numbers across designs | Reproduce one dataset without fitting; changes in anchor order or extra method cells must not alter its response stream. Fixed primary truth is not falsely counted as a fresh draw |
| M1-03 — open | Choose interval levels, practical tolerances, Monte Carlo precision, replications, and per-stratum decision rules for parameter and predictive targets | Justify numerical values before evaluation; distinguish MCMC error from across-dataset error and true-probability regret from heldout log loss |
| M1-04 — open | Choose the primary backend, actual prior scales, ordinary non-truth starts/jitter, chain settings, diagnostic policy, bounded cost probe, time/memory/output caps, and remediation allowance | Review the probe budget before running it; record resource evidence and keep all probes outside evaluation counts. The provisional 6,400 primary fits is not a budget authorization |
| M1-05 — open | Reuse the recovery/predictive scorer and specify planned/attempted/completed/diagnostic-valid counts, structural rejections, paired Monte Carlo error, and non-overwriting failure/remediation summaries | A bounded synthetic scoring check must include a failed fit, a fixed contrast, and paired methods; remove an unimplemented metric claim before freezing rather than treating a planning field as a scorer |
| M1-06 — open | Hand off the single protocol with exact source revision, cell roster, settings, scorer checks, unresolved questions, and claim limits | A person other than the implementer records accept/request-revision decisions. Review cannot be replaced by an implementer-authored receipt |

The next writing task is M1-01. Seed choices, numerical acceptance thresholds,
and replication budgets remain deliberately unresolved here; directory cleanup
does not select them. M2 starts only after M0 and all freeze decisions close.

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
5. **Controls and cost.** Freeze cell IDs, disjoint pilot/evaluation seeds,
   sampler settings, initialization/prior subsets, timeout and memory caps,
   and the smallest cross-implementation subset covering each claimed model
   and constraint. Cost probes contribute zero evaluation replications. An
   incompatible external anchor contract is recorded as non-overlap, not
   silently replaced by an unanchored fit.
6. **Terminal review.** Freeze the acceptance rules before fresh outcomes are
   inspected. A failed domain is narrowed or rejected; an unresolved estimate
   remains inconclusive. Any extension uses a declared new stage and seeds,
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
assertions and the 308 reference-declaration/estimand checks below pass locally
on Julia 1.10.8 and 1.12.5 (2,826 total). The command contributes
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
response RNG key. RSM and PCM truth differs, so shared uniforms would not make
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

After each milestone, record only: which uncertainty decreased, which claim
that changes, and what now blocks the next decision. Missing review or external
data should trigger a concrete handoff and work on an independent open item,
not repeated local simulations of the same question. Generalized validation,
LD1b, free correlation, soft/group anchors, and new-facet prediction keep their
own prerequisites and denominators. This roadmap revision changes planning,
not API support, completed evidence, or execution status.
