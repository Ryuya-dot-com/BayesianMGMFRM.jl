# Fixed-coefficient MFRM validation protocol

Draft, 2026-09-17. Owner: analyst/maintainer. Independent M1 review and
execution acceptance are **open**. Numbers below are concrete review proposals,
not adopted scientific criteria, package defaults or permission to run a grid.
This preparation generated no responses and ran no fits, SBC or recovery
replications. The [roadmap](../../ROADMAP.md#research-execution-prerequisites)
governs execution; this document owns this target's proposed design.

## Question and scope

An analyst comparing two named abilities and four raters needs to know whether
uncertainty reflects the available ratings, whether arbitrary rater IDs affect
comparisons, and whether Julia and CmdStan implement the same posterior.
A completed fit or agreement between backends cannot answer all three questions.
This study separates those questions so that a numerical defect, weak rating
design and consequential prior choice lead to different conclusions.

The primary target is fixed-coefficient, two-dimensional, between-item MFRM
with `Experimental.ExchangeablePrior`. Independent and correlated fits share
the response model; the latter estimates one population correlation. The
existing `MFRMPrior` is a secondary compatibility/prior comparison. This panel
does not validate estimated loadings, within-item Q, Q estimation, bifactor or
non-compensatory models, new random effects, new-facet prediction, hard anchors
or all category counts. Uchihara data are not required to prepare or run it.

| Question | Comparison and reason | Answer to report |
| --- | --- | --- |
| Which contrasts can the rating design identify? | Rank/nullspace of adjacent logits, including disconnected and missing-dimension controls | Which estimands survive every likelihood null direction; distinguish structural ambiguity from low precision |
| Does a selected prior change the answer? | Match mean rater-contrast variance across priors; change item-prior scale separately on the same data | Changes in contrasts, predictions and prior-anchored locations, with their Monte Carlo uncertainty; no automatic preferred prior |
| Does renaming raters change their posterior comparisons? | Cyclic ID permutation with all observations and outputs mapped back | Exchangeable target invariance versus a genuine legacy-prior change |
| How much is learned from this design? | Zero/nonzero correlation, more persons, and fewer ratings with connectivity retained | Bias, coverage, interval width and predictive error for declared estimands, including unsuccessful attempts |
| Is posterior computation calibrated under its own model? | Separate joint-prior SBC, including data-dependent test quantities | Resolved deviations or limited sensitivity; not fixed-truth coverage or prior suitability |
| Do maintained backends agree at sufficient precision? | Exact same data/target, independent sampling and statistic-specific MCSE | Agreement within declared numerical tolerance, discrepancy, or inconclusive precision |

The separation of aims, data generation, estimands, methods and performance
measures follows [Morris, White and Crowther](https://doi.org/10.1002/sim.8086).
Each result must answer its row's question; more fitted models or plots do not
constitute acceptance of a wider domain.

## Target and estimands

The [prior/identification contract](fixed-coefficient-prior-identification.md)
owns the equations and measures. Categories are 0:3. Adjacent logits are
`q_i' theta_p - b_i - r_r - s_ih`, with active coefficients and consistencies
fixed at one. All locations are unit logits; the internal 1.7 adapter cancels
in the likelihood and contributes no prior Jacobian. Each stored step vector
is `(0, u_i1, u_i2, -u_i1-u_i2)`; raters sum to zero. The correlated target
uses `rho=tanh(z)`, with its Jacobian once. Normal scales and LKJ eta are fixed,
not additional variance estimands.

For any two-vector c, `theta_p -> theta_p+c` and `b_i -> b_i+q_i'c` preserve
the likelihood. Proper priors select these locations; fixed loadings do not
identify them from ratings. As declared derived summaries, compute per draw
`theta*_p=theta_p-mean_p(theta_p)` and `b*_i=b_i-q_i'mean_p(theta_p)`.
Apply the same transformation to truth. Keep stored raw draws unchanged.
Between-person contrasts within a dimension, same-Q item contrasts, rater contrasts, steps
and response probabilities are invariant to these shifts. Cross-Q raw item
differences generally are not. Invariance to these two shifts is insufficient
if the design has additional null directions.

The primary scalar roster, fixed before seeing simulated outcomes, is:

| Estimand | Interpretation |
| --- | --- |
| `r_4-r_1`, `r_2-r_1` | Contrasts involving and excluding the reconstructed legacy rater |
| `b_4-b_1`, `b_8-b_5` | Within-dimension item comparisons with identical Q rows |
| `theta_11-theta_21`, `theta_12-theta_22` | Named person comparisons on each dimension |
| `s_1,1`, `s_8,3` | A free and a reconstructed nonbaseline step |
| `rho` (correlated fits only) | Population ability correlation, not the realized persons' sample correlation |
| Mean `Pr(Y >= 2)` over observed design cells | Expected higher-category rating on these known facets |

There are ten scalars for correlated fits and nine for independent fits.
The fixed zero correlation has no estimated interval and is not scored for
coverage. All person/item/rater/step summaries and centered coordinates are
secondary. Raw absolute ability/item locations describe prior anchoring only;
their recovery must not be presented as likelihood identification. For rho
coverage, redraw the persons for every replication; resampling ratings with
one fixed ability matrix answers a different, conditional question.

## Recovery data and fit roster

Use D=2, I=8, R=4 and K=4. Items 1:4 have Q row `(1,0)` and items 5:8 have
`(0,1)`. IDs preserve these declared mappings regardless of lexical ordering.
Within each replication draw persons independently from a bivariate normal
with zero means, unit marginal SDs and the cell's true rho. Do not recenter
these generating abilities. Hold the following facet truths fixed:

- `b = (-1,-1/3,1/3,1, -1,-1/3,1/3,1)`.
- `r = (-0.6,-0.2,0.2,0.6)`.
- Item i has stored steps `(0,-a_i,0,a_i)`, `a_i=0.35+0.05(i-1)`.

Generate ratings conditionally independently using a separate stable softmax
of the cumulative adjacent logits. This is conditional fixed-facet recovery
with random persons, **not** joint-prior calibration. Keep empty or rare
observed categories as outcomes; never redraw until a convenient data pattern
appears. If a fit's category/data validation rejects a dataset, retain the
attempt and cause. A future unsupported missingness mechanism needs its own
design; the thin condition here is deterministic and ignorable by construction.

All primary fits use `ExchangeablePrior(person_sd=1, item_sd=1, step_sd=0.5,
rater_kernel_sd=0.5)`; correlated fits use LKJ eta=2.

| Fit cell | True rho | Persons | Observations | Fitted covariance | Reason |
| --- | --- | --- | --- | --- | --- |
| C0 | 0 | 48 | 1,536, complete | Independent | Baseline with correctly fixed zero correlation |
| C1 | 0 | 48 | Exactly C0's data | Correlated | Cost/uncertainty of estimating an unnecessary correlation |
| C2 | 0.6 | 48 | 1,536, complete | Correlated | Recovery away from independence |
| C3 | 0.6 | 144 | 4,608, complete | Correlated | Information about population correlation from more persons |
| C4 | 0.6 | 48 | 768, balanced thin | Correlated | Less rating information with the same structural identification |

For each replication, generate the 144-person rho=0.6 design once. C2 uses
its first 48 persons and ratings; C4 uses C2's prescribed subset. For one-based
person p and item i, retain zero-based raters `(p+i-2) mod 4` and its cyclic
successor. Each person-item pair has two raters; each person has four ratings
per rater, and each item has 24 ratings per rater. The rho=0 family has a
separate generating stream. Replications are independent; paired conditions
within a replication are deliberately dependent. More persons do not give a
given person more ratings, so C3 need not greatly improve individual ability
precision. C1 versus C2 changes the generating correlation, not just a fit option.

Add four secondary Julia fit cells on these same data: legacy `MFRMPrior` on
C2 and C4, and exchangeable C4 with item SD 0.5 and 2. All other settings stay
fixed. Nine fit cells are proposed, not a Cartesian sweep of all factors.
Changing item SD alters both location anchoring and shrinkage of identifiable
contrasts; this sensitivity comparison does not isolate only the location gauge.

### Matched rater priors and label comparison

Let tau be the exchangeable kernel SD and sigma the legacy free-coordinate
SD. Exchangeable pairwise contrast variance is `2 tau^2`; the legacy mean
over all unordered pairs is `4 sigma^2`. Match this mean with
`sigma=tau/sqrt(2)`, retaining the same person/item/step priors. For R=4 and
tau=0.5, the exchangeable marginal SD is 0.433013 and every contrast SD is
0.707107. Legacy sigma=0.353553 gives free/free contrast SD 0.5 and
free/last contrast SD 0.866025. Equal means do not make these priors equivalent.
No scalar matches every contrast for R>2; R=2 supplies an exact matched control
in the existing mathematical checks. This comparison does not change defaults.

On the first 20 preassigned dataset IDs of C2 and C4, refit both rater priors
after a cyclic relabelling that changes the reconstructed last physical rater
(80 extra Julia calls). Map truth and posterior estimands back before comparison.
For the exchangeable target the posterior should be unchanged, up to MC error;
for the legacy target it can change because the prior changed. A small legacy
change on one dataset does not establish invariance. Data/target identifiers
may legitimately change under relabelling; equality of hashes is not the test.

## Sampler-free identification and scoring checks

Construct the adjacent-logit matrix A in the free ability, item, rater and step
coordinates. It excludes rho: rho enters the hierarchical ability distribution,
not conditional rating logits. The following deterministic SVD audit is complete;
it is not an evaluation of posterior recovery or hierarchical information.

| Design | Free logit coordinates | Rank | Nullity |
| --- | --- | --- | --- |
| 48 persons, complete | 123 | 121 | 2 |
| 144 persons, complete | 315 | 313 | 2 |
| 48 persons, balanced thin | 123 | 121 | 2 |
| Two disconnected components | 123 | 118 | 5 |
| Person 1 has no dimension-2 ratings | 123 | 120 | 3 |

The disconnected control assigns persons 1:24, items {1,2,5,6} and raters
{1,2} to one component and the remainder to the other. Each person still has
both dimensions. Merely checking dimension coverage therefore misses this
defect. The missing-dimension control removes person 1's dimension-2 ratings;
the correlated model's existing coverage guard is expected to reject it.
Neither negative design is a recovery cell. Test each linear estimand against
the *whole* nullspace before labelling it likelihood-estimable; a prior can
still supply information for a non-estimable contrast.

The [local arithmetic record](../../results/workflows/20260917-fixed-coefficient-protocol-01/design-audit.json)
contains ranks, tolerances/singular-value separation, exact zero logit change
under c=(0.5,-0.5), thin-design balance, prior-variance matching and allocation
arithmetic. It contains no simulated responses or fits. The rank calculation
does not exercise the package's input guards, response generator or scorer.
Existing [identification tests](../../test/mfrm_prior_identification.jl) and
[correlated-density tests](../../test/mfrm_correlated_2d.jl) provide reusable
checks; the next implementation must connect these facts to generated data.

Before any live pilot, independently calculate probabilities and per-draw
estimands on tiny known inputs; reject shifted category/truth IDs and wrong
target records. Inject missing/nonfinite draws, failed diagnostics, absent
MCSE, exceptions and interrupted-attempt records into the scorer. Check that
it retains denominators and never emits a successful partial result. These
are finite implementation checks, not additional research conditions.

## Scores, failures and decision rules

For each primary scalar, report posterior-mean bias, RMSE, central 95% interval
coverage and interval width. Also show posterior SD and statistic-specific MCMC
MCSE so that sampling precision is not confused with posterior uncertainty.
Diagnostic qualification alone does not establish sufficient precision for a
scientific margin. If MCMC error could change that decision, retain an
inconclusive precision finding rather than crediting the recovery result.
For errors e across n usable replications, bias MCSE is `sd(e)/sqrt(n)`;
RMSE is `sqrt(mean(e^2))`, with delta-method MCSE
`sd(e^2)/(2*RMSE*sqrt(n))` when RMSE>0 and n>=2. Use binomial intervals for
coverage and `sd(score)/sqrt(n)` for average widths/regrets. Degenerate or
insufficient replication counts retain an explicit unavailable precision flag;
do not present the delta approximation as exact or a zero RMSE as certainty.
For secondary groups, first compute each replication's group score, then its
between-replication uncertainty. Multiple persons or steps in one dataset do
not increase the number of independent simulation replications.

For prediction, average category probabilities over posterior draws, not at
posterior-mean parameters. Against known generating probabilities, calculate
mean Brier regret `sum_k (pi_hat_k-pi_true_k)^2` and logarithmic-score regret
`sum_k pi_true_k log(pi_true_k/pi_hat_k)` over the observed design cells.
These are expected new-rating risks on the same persons/items/raters, not
held-out observations or unseen-facet generalization. Use stable log-space
probabilities; never silently clip a failed calculation. Summaries of realized
ratings alone cannot substitute for these known-truth prediction scores.

Every planned dataset has a primary attempt, including generation rejection,
fit error, timeout, nonfinite output, failed diagnostics and unavailable MCSE.
Store separate cause flags as well as a declared qualification status. Do not
replace failed IDs. Show all-attempt failure rates and usable-subset estimates
together. Paired differences use the jointly usable datasets, with their count
and missing-pair causes; the relevant MCSE is the SD of paired differences
divided by the square root of that count.

If C intervals cover among S qualified attempts and U=N-S are unresolved,
all-attempt coverage is bounded by `[C/N,(C+U)/N]`. Add binomial uncertainty
(for example Wilson lower bound at C and upper bound at C+U) rather than
reporting only C/S. Continuous bias/RMSE cannot in general be bounded this way:
missing errors are unbounded. Usable-subset results cannot certify all-attempt
performance. Report every interval's denominator and whether it is pointwise.

The proposed recovery allocation is 400 independent replications per dataset
family. Coverage MCSE at probability 0.95 is 0.01090; worst-case binary MCSE
is 0.025. This supports descriptive precision, not a claim of 0.005 precision:
at probability 0.95 that would require 1,900 replications. Bias/RMSE precision
depends on their observed replication variability. Report MCSE and Monte Carlo
intervals using the replication as the unit; no outcome-driven extra batches.

Scientific error margins are **not yet adopted**. Independent review must
choose the intended use and tolerable error for each primary claim, or retain
descriptive/inconclusive conclusions. Once a margin is fixed prospectively,
classify its Monte Carlo interval as wholly inside (supported in this cell),
wholly outside (contradicted), or overlapping (inconclusive); incorporate the
failure bounds above. Nominal Bayesian coverage under fixed facet truths is
not guaranteed to equal 95%. A deviation may indicate prior shrinkage rather
than a coding error. No application ranking or decision threshold is inferred
from these synthetic truths.

## Joint-prior calibration is a separate experiment

Propose 500 datasets for each of four targets: independent/correlated crossed
with exchangeable/legacy rater prior, at the 48-person complete geometry and
the same fit priors as above. Draw **every stochastic parameter** from that
target's prior. For exchangeable raters, use `tau*(z-mean(z))` from R iid
standard normals; for legacy raters draw R-1 independent normals then take the
negative sum. Draw item/free-step normals and reconstruct steps. In the
correlated case, `rho=2B-1`, `B~Beta(eta,eta)`, then draw abilities conditional
on rho; in the independent case use independent normals. Do not fix rho at
0.6, recenter abilities, or reject inconvenient prior draws.

Independent response generation is required: reusing the fitted likelihood as
the sole generator can hide a shared bug. The public prior-predictive path can
cross-check moments and schema, not serve as the only reference. SBC tests
computation under the selected model; it does not show that the model or prior
is appropriate for an application. See [Talts et al.](https://arxiv.org/abs/1804.06788)
and the [Stan SBC guide](https://mc-stan.org/docs/stan-users-guide/simulation-based-calibration.html).

Use the primary scalar roster plus raw `theta_11`, raw `b_1` and the joint
response log likelihood on that dataset (13 quantities for correlated fits,
12 for independent fits). The data-dependent quantities matter: parameter-only
ranks can miss a procedure that simply returns the prior. Randomize ties
within their rank interval and exclude fixed coordinates. This choice follows
[Modrak et al.](https://doi.org/10.1214/23-BA1404); it is not proof of sensitivity
to every possible error. A prior-only negative control should exercise the
scorer's limitations as well as its detection ability.

The candidate rank policy takes 31 evenly spaced draws per chain from four
chains (iterations 64,128,...,1984), L=124. Thinning alone does not establish
independence: inspect dependence and effective sample size of the actual test
quantities in separate pilot work; unresolved dependence makes rank assessment
inconclusive. Freeze the selection policy before evaluation. Do not treat all
8,000 autocorrelated draws as independent uniform-rank trials.

For iid posterior draws the expected rank CDF at k is `(k+1)/(L+1)`.
As a conservative screen, compare it with the empirical CDF using a DKW band
with Bonferroni adjustment over the T predeclared quantities:
`epsilon=sqrt(log(2*T/0.05)/(2*N))`. For N=500, T=13 this is 0.07908.
This family is within one target; it is not a global four-target error guarantee.
Independent datasets and valid posterior-rank draws are assumptions. Missing
ranks give a full-N CDF envelope by placing each missing rank below/above each
threshold; widen it by epsilon. Departure is resolved only where even that
envelope excludes the reference CDF. No detected departure is limited evidence,
not proof of correct computation, especially at this coarse sensitivity.

## Sampler qualification and backend comparison

Proposed per-call settings: four chains, 1,000 warmup and 2,000 retained draws
per chain, target acceptance 0.9, maximum tree depth 10. Use supported finite
initialization with independently seeded jitter, never the generating truth.
The exact initializer and backend option mapping must be recorded before the
pilot. These are study proposals, not changes to package sampling defaults.

Check free coordinates and nonconstant derived/focal quantities. The candidate
qualification rule is finite output, rank/folded split R-hat <1.01, bulk and
tail ESS >=400, no divergences, and each chain's E-BFMI >=0.3. A tree-depth hit
is recorded separately as an efficiency concern and conservatively prevents
primary qualification pending review; it is not by itself evidence of biased
draws. These choices build on [Stan's diagnostic guidance](https://mc-stan.org/learn-stan/diagnostics-warnings.html);
meeting them does not prove convergence. Check precision of each requested
statistic: an adequate mean ESS does not ensure accurate 2.5% quantiles.

Reuse the matrix form of `posterior_mcse`: verify saved chain/iteration IDs,
form equal-length contiguous chain blocks of per-draw estimands, and supply
`chains=4` and column names. The method takes a chain count, not an ID vector.
There is currently no
fit-taking overload for these fixed-Q result types; adding a claim that
`posterior_mcse(fit)` already works would be incorrect. Quantile comparisons
need quantile MCSE, not the mean's MCSE; the
[posterior reference](https://mc-stan.org/posterior/reference/mcse_quantile.html)
describes the distinction. Unavailable precision stays unavailable.

CmdStan receives the exact same data and priors for the first 20 preassigned
IDs of C0, C1, C2, C4 and legacy C4 (100 calls). Use independent backend sampler
streams; equal integer seeds do not mean equal random streams. Check common
coordinate density/gradient/probability parity first using existing tests, and
record the compiled target identity. Neither backend is assumed to be truth.

Compare posterior means and 2.5%/97.5% quantiles for the primary scalar roster.
For each statistic let delta be Julia minus CmdStan and
`s=sqrt(MCSE_J^2+MCSE_C^2)`. Use an approximate normal interval with
`z=Phi^-1(1-0.05/(2M))`, M=27 or 30 comparisons within that fit pair.
This adjustment is within a pair, not across all datasets. Proposed numerical
tolerance is 0.1 times pooled posterior SD, defined as
`sqrt((SD_J^2+SD_C^2)/2)`, capped at 0.02 for rho and 0.01
for the probability summary. These are computational equivalence margins,
not practical accuracy requirements, and need review before adoption.

- `abs(delta)+z*s <= tolerance`: precision-resolved agreement for that statistic.
- `abs(delta)-z*s > tolerance`: resolved discrepancy requiring investigation.
- Otherwise, or if either fit/MCSE is unqualified: inconclusive.

A nonfixed quantity with zero/nonfinite posterior SD is not an automatic pass.
Aggregate all three outcomes with denominators; failure to detect a difference
is not equivalence. Apply the same statistic-specific reasoning to exchangeable
label invariance. Treat legacy relabelling as prior sensitivity, not an expected
equivalence. No automatic rescue fit or pooling of differently tuned runs is
proposed; any later remediation remains a separate secondary attempt and cannot
erase the primary failure.

## Allocation, provenance and execution boundaries

| Proposed allocation | Calls |
| --- | --- |
| Recovery: nine Julia fit cells x 400 replications | 3,600 |
| SBC: four targets x 500 datasets, Julia | 2,000 |
| Relabelled Julia fits | 80 |
| Matched CmdStan subset | 100 |
| Total evaluation calls | 5,780 |

Each call contains four chains, not four replications. This proposal entails
46,240,000 retained posterior draws; it is a planning count, **not an accepted
runtime/storage budget or queued job**. Cost is unmeasured. If infeasible,
narrow the question/roster or accept lower declared precision *before* freezing
evaluation; do not silently shorten failing cells or launch this allocation.

A separately proposed cost/pipeline pilot has at most eight calls: C0/C2/C3/C4
on each backend using pilot-only dataset ID 1. Candidate stops are 30 minutes
per call, four hours total serial wall time including compilation, 8 GiB per
process tree and 5 GiB total output. These caps and their enforcement must be
reviewed and implemented before any pilot. A cost cap can prevent completion;
it is not a forecast. SBC dependence checks may require a later separately
bounded pilot; these eight recovery calls do not validate the SBC rank policy.
No pilot calls are counted as evaluation. No pilot was launched in this preparation.

Freeze the source/environment revision, dataset/cell roster, actual RNG
algorithms and seed-root table before evaluation. Use logical keys for phase,
case, replication, component, backend and chain; avoid process-dependent hash
seeding. Paired cells read preserved truth/response bytes; retain both physical
facet IDs and model indices. Store target/prior identity, generation versus
sampling RNG provenance, input hashes, attempt settings, result/exception,
diagnostic qualification, score and MCSE availability. Capture measured
producer resources separately from later scoring metadata. The existing
[environment contract](mfrm-anchor-study.md#source-and-execution-environment-declaration-requirements)
applies, without inheriting the anchor study's 266-cell roster or claiming its
six review decisions are closed.

## Next implementation and review handoff

The next bounded change is a sampler-free Julia generation/scoring preparation:
independent response probabilities and truth reconstruction, declared estimands,
chain-aware MCSE binding, and failure/denominator checks on tiny synthetic
records. Reuse existing fit types, diagnostics, matrix MCSE, result persistence
and report figures. Do not add a sampling engine, generic controller, new public
API or full-grid script. A reproducible data generator is not independently
validated merely because it produces plausible-looking ratings.

Independent review must resolve target/identification interpretation, scientific
margins or descriptive-only claims, allocation precision, SBC dependence policy,
sampler/initializer mapping, and resource/failure stops before fresh evaluation.
Prepare code and reviewable evidence while those decisions are open. Report
mathematical checks, operability, reviewed design, statistical evidence and
scientific acceptance separately. Neither this protocol nor prior short API
fits close M1/M2, choose a default prior, or qualify an application analysis.
