# Fixed-coefficient MFRM prior and identification contract

Updated 2026-09-17. This is a derivation and implementation review of the
existing independent and two-dimensional correlated MFRM targets. It does not
replace their priors or constitute statistical acceptance of either model.

## Question and consequence

Does a zero-sum constraint make raters exchangeable, and do fixed loadings
identify the ability/item locations? Neither follows from the constraint alone.
The current model assigns independent normal priors to the free coordinates,
then reconstructs the last rater and the last nonbaseline item step. This gives
the reconstructed coordinates different variances. For more than two raters,
renaming IDs so that a different rater becomes last can change the prior and
therefore the posterior, even when the likelihood is preserved exactly.

This matters to an analyst importing ratings from another program: changing an
identifier should not be mistaken for a scientifically neutral operation under
this particular prior. Sorting observation rows is different; the package sorts
facet levels by label, so row order alone does not change the reconstructed
rater. `data.rater_levels[end]` identifies that rater. An explicit exchangeable
alternative is a model change, not a repair to arithmetic or a harmless cache
rewrite. Existing fits must retain their original meaning.

## Equation, scale and parameter measure

Let `k=0,...,K-1`, `q_i` be the fixed binary Q row, and `s_ih`, `h=1,...,K-1`,
the nonbaseline steps. The leading zero in the stored K-vector is a baseline
score contribution, not an additional free threshold. Define

```math
L_{pirk}=\sum_{h=1}^{k}(q_i^\top\theta_p-b_i-r_r-s_{ih}),\qquad
P(Y_{pir}=k)=\frac{\exp L_{pirk}}{\sum_{j=0}^{K-1}\exp L_{pirj}}.
```

All locations and steps are in unit logits. Active Q coefficients and rater
consistencies equal one. The internal adapter divides the free vector by 1.7
solely to reuse the existing response kernel that multiplies by 1.7. The normal
prior is evaluated on the original unit-logit vector. This likelihood evaluation
does not transform a prior density, and adds no `log(1.7)` term. Replacing 1.7
by 1.702 in only one part would change the likelihood.

The independent target has `theta_p ~ N(0, person_sd^2 I)`, independent item
locations `b_i ~ N(0, item_sd^2)`, and the free-coordinate priors below. The
correlated target replaces only each ability pair's prior by
`N(0, person_sd^2 [1 rho; rho 1])`, conditional on the shared rho. Ability pairs
are independent conditional on rho; marginalizing the shared rho is not the
same as asserting independent pairs. All four normal SDs and LKJ eta are fixed
inputs, not estimated variance components. Only rho is estimated in this
covariance block.

The current densities are with respect to the free location/step coordinates,
and additionally Fisher z for the correlated target. `rho=tanh(z)` contributes
`log(1-rho^2)` once to the LKJ density declared in `d rho`. The ability normal's
covariance determinant is a density normalizer, not another Jacobian. Linear
reconstruction of the declared free normal variables adds no transformation
penalty. It also does not turn that prior into a symmetric full-vector prior.

## Exact induced rater and step distributions

For a zero-sum block of length n, write `m=n-1`, `C=[I_m; -1']`, and
`v ~ N(0, sigma^2 I_m)`. The implemented full vector is `a=Cv`, so

```math
\operatorname{Cov}(a)=\sigma^2 CC^\top,\quad
\operatorname{Var}(a_j)=\sigma^2\ (j<n),\quad
\operatorname{Var}(a_n)=(n-1)\sigma^2,
```

```math
\operatorname{Cov}(a_j,a_l)=0\ (j\ne l<n),\qquad
\operatorname{Cov}(a_j,a_n)=-\sigma^2\ (j<n).
```

Two free entries have contrast variance `2 sigma^2`; a free entry versus the
reconstructed entry has contrast variance `(n+2) sigma^2`. Thus equal numerical
free SDs do not mean equal prior uncertainty for all rater comparisons.

| Block | n | sigma | Consequence |
| --- | --- | --- | --- |
| Rater severity | R | `rater_sd` | Last variance `(R-1) rater_sd^2`; nonexchangeable when R>2 |
| Each item's nonbaseline steps | K-1 | `step_sd` | Last variance `(K-2) step_sd^2`; the additional leading baseline is identically zero |

At R=2, the severity vector `(v,-v)` is exchangeable, although its two entries
are dependent. At K=2, both stored step contributions are zero; at K=3, the two
nonbaseline steps are `(v,-v)`. K>3 distinguishes the final nonbaseline step's
variance. Different items' step blocks are independent under the declared
prior. Symmetry of a step prior does not authorize permutation of ordered score
categories: changing the step sequence generally changes cumulative logits.

## Relabelling, coordinate charts and an exchangeable reference

A permutation P followed by taking the first n-1 entries induces `u=T v`,
where `T=(PC)[1:n-1,:]` and `abs(det(T))=1`. Carrying the existing distribution
into that chart gives `u ~ N(0, sigma^2 T T')`. This preserves the prior measure.
Assigning independent `N(0,sigma^2)` priors anew to u generally does not.

For three raters, take full severities `(sigma,sigma,-2sigma)` and rename the
raters in reverse order, mapping observations and severities together. Every
response probability is unchanged. The free-coordinate log prior decreases
by 1.5; at zero severities its change is zero. This is a parameter-dependent
change, not an omitted normalizing constant or a backend discrepancy.
Permutations that leave the reconstructed rater fixed preserve this block's
prior. Simultaneously swapping the two ability dimensions and Q columns also
preserves the current likelihood/prior because the marginal ability scales
are equal and the bivariate covariance is symmetric.

The already implemented normalized zero-sum block reference instead has

```math
g(v;\tau)=\tfrac12\log n-(n-1)\log\tau-\tfrac{n-1}{2}\log(2\pi)
 -\frac{\|v\|^2+(\mathbf1^\top v)^2}{2\tau^2}.
```

Its full covariance is `tau^2 (I_n-11'/n)`. All marginal SDs are
`tau sqrt((n-1)/n)`; all pairwise contrast variances are `2 tau^2`. This agrees
with the [Stan sum-to-zero normal convention](https://mc-stan.org/docs/reference-manual/transforms.html#sum-to-zero-transforms).
The scale tau is a kernel SD; a desired common marginal SD s requires
`tau=s sqrt(n/(n-1))`. The correction from independent free normals is
`log(n)/2 - sum(v)^2/(2 tau^2)`, already supplied by
`_zero_sum_prior_correction`. The private fixed-coefficient reference below now
uses this correction; it is not a public fitting option.
For n>2, no single rescaling can match every marginal and contrast variance of
the asymmetric current prior. A comparison must state what is matched.

The generalized source/exchangeable targets additionally contain estimated
loadings and positive rater consistencies, with their own measures and source
rater identity. Fixed-coefficient MFRM has no sampled consistency block; its
prior must not inherit that block's lognormal tilt or its source-reproduction
claim. The normalized rater/step algebra can be reused without conflating the
complete model identities.

## Likelihood identification versus prior anchoring

For any dimension vector c, replace every ability by `theta_p+c` and every item
location by `b_i+q_i'c`, keeping raters, steps and rho unchanged. The likelihood
is invariant for both between-item and additive within-item Q. Fixed unit
loadings therefore do not remove these D location directions. Rank-deficient
Q and sparse rating designs may create additional information limitations.

The proper zero-centered priors select locations along these directions. If
`Sigma` is the ability covariance (conditional on rho), the log-prior curvature
along this scalar shift is

```math
-J\,c^\top\Sigma^{-1}c-\sum_i(q_i^\top c)^2/\mathrm{item\_sd}^2 < 0
\quad(c\ne0).
```

Here J denotes the number of persons. This is prior information. A proper posterior or narrow intervals alone do not establish
likelihood identification or recovery from ratings. Subtracting sample means
from saved ability/item draws would change their current coordinate/prior
interpretation unless performed as a declared derived summary. Hard anchors
would define another model rather than silently replace this convention.

## Code and evidence mapping

| Claim | Existing implementation / reproducible check |
| --- | --- |
| Free unit-logit measure and 1.7 likelihood adapter | `_MFRMFixedQReferenceLogDensity`, `_mfrm_fixed_q_reference_raw`, `_source_fixture_logprior` in `src/bayesian_fit.jl` |
| Sorted facet IDs and negative-sum reconstruction | `_stable_levels`, `_sum_to_zero_from_raw`, `_source_step_value` in `src/facet_workflow.jl` |
| Exact model-coordinate covariance | `_mfrm_fixed_q_model_coordinates` applied to scaled basis vectors; no simulated covariance estimate |
| Correlated ability prior and one Jacobian | `src/mfrm_correlated_2d.jl`, existing independent matrix-density checks in `test/mfrm_correlated_2d.jl` |
| Same target in CmdStan | `src/stan/mfrm_fixed_q.stan`, `src/stan/mfrm_correlated_2d.stan`, shared `mgmfrm_eta` |
| Alternative normalized block | `_zero_sum_prior_correction` in `src/mgmfrm_normalized_prior.jl`; no new MFRM dispatch |
| Covariance, chart transport, label/row changes and location freedom | [sampler-free tests](../../test/mfrm_prior_identification.jl) |
| Saved identity | Existing `fixed_q_mfrm_prior_v1`, sample records and target/cache identities retained; report wording is current interpretation only |

The numerical cases use R=2 as a symmetric control, R=3 as the smallest
label-dependent case, and R=5 to check its dimension dependence. K=2 tests
zero free steps, K=3 the symmetric two-step block, and K=4/6 the unequal
reconstructed variances. Two-dimensional pure and mixed Q cases test the
location shift; rho=0.4 checks the correlated formula away from independence.
Existing correlated-density tests cover other rho values and numerical tails.
The general covariance/location derivations do not rely on these example sizes;
the examples alone are not evidence for a broad statistical domain.

Verification outcomes are recorded in the
[owner's implementation record](normalized-prior-backend-comparison.md#fixed-coefficient-prior-and-identification-review-2026-09-17)
and its local receipt. These checks characterize the current model and backend
agreement. They do not determine a scientifically preferred prior or establish
recovery, coverage, convergence or an accepted application domain.

## Private exchangeable-rater reference

`_MFRMExchangeableRatersLogDensity` in `src/mfrm_exchangeable_raters.jl` wraps
the existing independent or correlated fixed-coefficient target. It adds the
normalized rater-block correction above to both the prior and posterior density.
It retains the current ability, item and ordered-step priors, the response
kernel, prior-anchored locations and the correlated model's single Fisher-z
Jacobian. No ability marginal scale is estimated. The correlated reference
keeps the existing conservative two-dimensional between-item design checks.

Its required `scales` record explicitly names `person_sd`, `rater_kernel_sd`,
`item_sd` and `step_sd`. Internally `MFRMPrior` validates/stores these numbers;
its rater value is the kernel SD tau used in the correction, not a promise of
independent free severities. The new target record stores a distinct schema,
the compatibility base identity, the kernel convention, actual scales, induced
common marginal/contrast SDs and unchanged step-prior policy. Reconstructing a
persisted target record verifies every field and the expected identity. This
is mathematical target persistence, not new posterior-draw or fit-cache support.
Old target identities cannot stand in for the new identity.

For example, with three raters and `rater_kernel_sd=0.4`, every rater has
marginal SD `0.4 sqrt(2/3)` (about 0.327), and every rater contrast has SD
`0.4 sqrt(2)` (about 0.566). The old `rater_sd=0.4` model instead has marginal
SDs `(0.4,0.4,0.4 sqrt(2))`; contrasts between free raters have SD 0.566, while
those involving the reconstructed rater have SD `0.4 sqrt(5)` (about 0.894).
Equal kernel scales therefore match the old free/free contrasts when R>2,
not all contrasts or marginal SDs. At R=2 the old contrast SD is `2 rater_sd`,
so that matching rule is unavailable. To match a specified contrast SD c
use `tau=c/sqrt(2)`; to match common marginal SD s use `tau=s sqrt(R/(R-1))`.
Neither rule is an automatic conversion of historical fitted draws.

CmdStan reuses the two existing fixed-coefficient sources with an explicit
`exchangeable_raters` data flag. Existing adapters send 0; only the new private
reference sends 1. The added branch supplies the same normalized correction
and checks for one common rater kernel scale. The sources and resulting build
hashes change, while the mode-0 statistical target and historical identities
remain unchanged. Both modes receive fresh full-density/gradient checks,
including both CmdStan automatic-Jacobian settings; no duplicate sampler or
response kernel was introduced.

`test/mfrm_exchangeable_raters.jl` compares against a separately constructed
multivariate normal, checks full-vector covariance, gradients and Hessians,
relabelled likelihoods/priors, unchanged nonrater derivatives and location
shifts, explicit scale matching, persisted identities and rejection of invalid
inputs. It includes binary and ordinal responses, 2/3/5 raters, independent
two/three-dimensional and fixed-Q within-item cases, and correlated 2D cases.
These checks establish this reference's mathematical behavior, not statistical
acceptance of those combinations. See the
[implementation record](normalized-prior-backend-comparison.md#fixed-coefficient-exchangeable-rater-reference-2026-09-17)
for executed checks and remaining limits.

## Private prior-predictive comparison

The exchangeable `_fixed_q_prior_draws` method transforms the existing free
rater normal draws with a Cholesky factor of `I_(R-1)-11'/R`. The kernel SD is
already present in those draws. This generates the declared free covariance
`tau^2 (I_(R-1)-11'/R)`; negative-sum reconstruction yields the full covariance
`tau^2 (I_R-11'/R)`. All nonrater coordinates and random-number consumption are
unchanged. In particular, correlated abilities are still generated conditionally
on a draw of rho from the declared LKJ distribution. Density Jacobians are not
additional simulation weights.

`_mfrm_rater_prior_comparison(spec; prior, matching, seed, ndraws=1000)` compares
the compatibility prior and exchangeable reference without fitting. Its two
explicit matching rules serve different questions:

| Rule | Question held fixed | Exchangeable kernel SD |
| --- | --- | --- |
| `:mean_contrast_variance` | Does rater symmetry change predictions at the same average pairwise contrast variance? | `tau=sqrt(2) sigma` |
| `:free_rater_marginal_sd` | What changes if every rater has the old free-rater marginal SD? | `tau=sigma sqrt(R/(R-1))` |

Here sigma is the compatibility model's `rater_sd`. Its covariance has trace
`2(R-1) sigma^2`. For any zero-sum vector, summing all pairwise contrast
variances gives `R*trace(Cov)`, so the compatibility mean contrast variance is
`4 sigma^2`. The exchangeable mean contrast variance is `2 tau^2`. Matching
these unweighted averages over all unordered pairs/raters also matches the
average marginal variance, but not every
individual rater marginal or contrast when R>2. The second rule instead
reduces average marginal/contrast variation for R>2; it therefore changes both
symmetry and overall dispersion. At R=2, both rules give `tau=sqrt(2) sigma`
and reproduce the entire compatibility distribution. There is no free/free
pair then; comparison records mark its SD as missing.

The comparison records both target identities, actual scales, the matching
criterion and seeded RNG/coupling policy. Both paths share nonrater draws and
the uniforms used for rating replication; each path remains an ordinary joint
prior simulation. Shared randomness makes differences easier to inspect and
does not remove Monte Carlo error. Observed scores are comparison data only;
changing them does not change parameter or replicated-rating draws.

The new private prior check reuses the existing response kernel, coordinate
summaries, grouped predictive summaries and `plot_prior`/`plot_predictive`.
The alternative prior's full record replaces the compatibility description;
figure captions identify the rater prior, its scale and matching rule. Existing
checks without a comparison label retain their previous fields and captions.
No new public prior selector or fitted-result/cache format is introduced.

Reproducible internal use (with an existing fixed-coefficient `spec`):

```julia
comparison = BayesianMGMFRM._mfrm_rater_prior_comparison(spec;
    prior=MFRMPrior(person_sd=0.7, rater_sd=0.4, item_sd=0.6, step_sd=0.5),
    matching=:mean_contrast_variance, seed=20260917, ndraws=2000)
using CairoMakie
save("exchangeable-raters.svg", BayesianMGMFRM.plot_prior(comparison.exchangeable; block=:rater))
save("exchangeable-ratings.svg", BayesianMGMFRM.plot_predictive(comparison.exchangeable))
predictive_check_summary(comparison.exchangeable; include_grouped=true)
```

The same call accepts `Experimental.correlated(spec; lkj_eta=3)`. Executed
checks, numerical examples and saved figures are in the
[implementation record](normalized-prior-backend-comparison.md#fixed-coefficient-rater-prior-prediction-2026-09-17).
These synthetic comparisons inspect prior implications, not model fit,
posterior performance or a scientifically preferred default.

## Private sampling and saved results

`_mfrm_exchangeable_rater_sample(target; backend=:advancedhmc, ...)` now reuses
the existing AdvancedHMC and CmdStan NUTS runners. It rebuilds mutable numerical
views from the validated design and explicit scales before sampling. The CmdStan
adapter delegates initialization coordinates to the existing independent or
correlated model, maps output by column name, and verifies pointwise likelihoods
and full normalized log posterior values against the exchangeable Julia target.
No new sampler or Stan response/target code is introduced in this slice.

The result reuses existing posterior summaries, full-coordinate reconstruction,
MCMC diagnostics and optional warmup telemetry. Correlated results continue to
distinguish Fisher-z sampling coordinates from reported rho. Fixed coefficients
and baseline steps remain fixed rather than estimated precision. A distinct
`model` value and `rater_prior` flag accompany the full prior record; the result
remains private (`public_fit=false`).

The record schema is `bayesianmgmfrm.exchangeable_rater_mfrm_samples.v1`.
It stores the independent or correlated specification, actual prior scales and
measure, target identity, canonical run and content hash. The existing generic
sample hash covers schema/prior/target/run; rebuilding and checking the target
identity separately verifies the specification, including its Q/data and LKJ
setting. The loaders check chain layout, controls, initial/retained densities,
sampler statistics, Stan log posterior values when applicable and warmup
coverage. Names, transformed coordinates, summaries and diagnostics are rebuilt
from the canonical record rather than trusted as saved display fields.

`_save_mfrm_exchangeable_rater_samples(path, result)` and
`_load_mfrm_exchangeable_rater_samples(path; expected_identity=...)` use trusted
same-environment Julia Serialization. Saving verifies the complete record before
the existing atomic publication helper runs. Failed validation or overwrite
attempts preserve the existing file. This is a separate private sample format;
the compatibility sample loaders and public fit-cache loader reject it. No
automatic conversion of historical draws or change of default is implied.

The [implementation record](normalized-prior-backend-comparison.md#exchangeable-rater-sampling-and-result-persistence-2026-09-17)
reports synthetic integrity tests and bounded live runs separately. Short runs
exercise sampling/output/replay paths and retain diagnostic warnings. They do
not establish convergence, posterior agreement between backends, recovery,
coverage or a supported application domain.

## Next bounded implementation

Connect these verified saved results to existing posterior-predictive summaries,
reports and figures privately, preserving the actual exchangeable prior and
kernel/marginal scale meanings. Prevent fallback to compatibility-prior report
text; confirm that save/reload regenerates the same numerical outputs and
diagnostic warnings without refitting. Public fitting/cache API design,
scientific default selection, ordered-step priors and target-specific
recovery/coverage remain separate decisions.
