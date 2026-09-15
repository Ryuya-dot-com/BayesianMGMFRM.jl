# Experimental Generalized Models

`BayesianMGMFRM.Experimental` contains generalized models that are executable
only in the limited configurations documented below. They are not part of the
stable MFRM fitting contract, and their availability does not imply broader
GMFRM or MGMFRM support.

## Boundary

The namespace currently admits only two surfaces:

- one-dimensional source-aligned scalar GMFRM with positive item/task
  discrimination multiplied by positive rater consistency and rater-specific
  partial-credit steps;
- fixed-Q confirmatory MGMFRM with at least two dimensions, partial-credit
  steps, and fixed identity latent correlation.

Both reject anchors and fitted DFF terms. Broader discrimination, rating-scale
generalized kernels, exploratory or rotated loadings, and free latent
correlations remain outside the fitting boundary.

The compatibility selector `discrimination = :none` on MGMFRM means that no
broader generic discrimination family is selected. The experimental kernel still
estimates positive item-by-dimension discriminations at the active cells of
the fixed Q-matrix.

Likewise, the GMFRM compatibility selector `discrimination = :rater` does not
mean that item/task discrimination is absent. Its source-aligned kernel uses
the effective multiplier `item_discrimination[i] * rater_consistency[r]`.
Each rater has one step vector that is shared across items and persons on the
direct parameter scale. With `K` categories, the first step is fixed to zero,
`K - 2` steps per rater are free, and the final step is reconstructed so the
remaining steps sum to zero. The effective response-scale spacing also depends
on the item-by-rater discrimination product.

Inspect the executable contract before building an experimental workflow:

```julia
using BayesianMGMFRM
using Random

contract = BayesianMGMFRM.Experimental.surface_contract()
contract.families.mgmfrm
contract.families.gmfrm
contract.candidate_surfaces.mgmfrm_free_latent_correlation_2d
```

## Dimension aggregation and item structure

Keep author terminology, response algebra, and item structure separate.
[Uto (2021), Section 5](https://doi.org/10.1007/s41237-021-00144-w) calls the
model non-compensatory, but Equations 5--6 and Appendix 1 use an additive
weighted ability sum. The cited
[Yao and Schwarz (2006) publisher abstract](https://doi.org/10.1177/0146621605284537)
explicitly describes its multidimensional partial-credit model as compensatory.
This is a terminology discrepancy, not a reason to replace the published
likelihood with a probability product.

Our algebraic reading of Equation 6, with categories indexed from 1, is

```math
u_{ij}=\sum_{d=1}^{D}a_{id}\theta_{jd},\qquad
\eta_{ijrk}=1.7\alpha_r\left[(k-1)(u_{ij}-\beta_i-\beta_r)
 -\sum_{m=2}^{k}d_{im}\right],\qquad
P_{ijrk}=\frac{e^{\eta_{ijrk}}}{\sum_{h=1}^{K}e^{\eta_{ijrh}}}.
```

The empty step sum is zero, so the first logit is zero. For a fixed item with
two positive loadings, replacing abilities by
`(theta_1 + t, theta_2 - a_i1/a_i2 * t)` leaves `u_ij` and the entire category
probability vector unchanged. For example, loadings `(2, 1)` make abilities
`(0, 2)` and `(1, 0)` indistinguishable on that item. Thus the conditional
response equation has compensatory tradeoffs. Other items with different
loadings, the ability prior, and the full posterior need not be unchanged.
This result is not evidence of global nonidentification or practical validity.

In the visually checked Appendix 1 Stan code (printed page 451), also checked
against the [published Stan implementation](https://github.com/AI-Behaviormetrics/Multidimensional-GMFRM/blob/master/mult_gmfrm_uto.stan):

| Operation | Index/role |
| --- | --- |
| `dot_product` of item discrimination and person ability | Multiply each loading by its ability, then **sum over dimensions** |
| `1.7 * trans_alpha_r` | Scalar rater multiplier on the category logits |
| `cumulative_sum` of steps and category scores `0:(K-1)` | Accumulate **category steps**, not dimensions |
| Reciprocal of `prod(alpha_r)` | Reconstruct the first **rater** consistency so the full product is one; an identification constraint |
| `categorical_logit` | Softmax normalization over **response categories** |

The package Stan kernel uses an explicit loading-sum loop and reconstructs the
last rater's log-consistency as the negative sum of the free log-consistencies.
It has the same response algebra under the Q restriction, not a demonstrated
match of the complete source prior. A product of unnormalized exponentials
(`exp(sum(z)) = prod(exp(z))`) or likelihoods across observations is not a
product of dimension-specific success probabilities. For the latter distinction,
[Bolt and Lall (2003), Equations 1--2](https://doi.org/10.1177/0146621603258350)
contrast a compensatory logistic weighted sum with a non-compensatory product
of component success probabilities; that binary comparison is not an
implemented alternative ordinal kernel here.

Within/between instead describes which dimensions an item measures
([ACER ConQuest manual, Section 2.8.3](https://conquestmanual.acer.org/s2-00.html#within-item-and-between-item-multidimensionality)).
The source Appendix estimates a positive discrimination for every item-dimension
cell, without a Q mask: for `D > 1`, it is **within-item**. A small positive
loading is not a structural zero. In this package, one active cell per Q row
gives **between-item** structure; rows with multiple active cells are
**within-item**. The contract calls a combination of pure and cross-loaded
rows **mixed**; this is a finer subdivision of what the cited manual calls
within-item at test level. These labels do not establish non-compensation or
identify the model by themselves.

The contract's `source_classification` preserves the author's wording;
`algebraic_aggregation` records the weighted sum. Its unresolved
`operational_compensation_status` is not evidence against the conditional
identity above or a certification of a practical decision rule.

## Workflow

Specifications continue to use the common domain-language constructor. Design
preview, fitting, and cached fitting then cross the explicit namespace boundary:

```julia
spec = mfrm_spec(data;
    family = :mgmfrm,
    dimensions = 2,
    thresholds = :partial_credit,
    discrimination = :none,
    q_matrix = Bool[1 0; 0 1],
)

design = BayesianMGMFRM.Experimental.preview(spec)

fit_result = BayesianMGMFRM.Experimental.fit(spec;
    backend = :advancedhmc,
    ndraws = 500,
    warmup = 500,
    chains = 4,
    seed = 20260722,
)
```

The guarded fit accepts a typed sensitivity prior. Its scales are standard
deviations of independent zero-centered normal priors on the raw unconstrained
coordinates; they are not priors on the transformed direct parameters:

```julia
unit_raw_prior = BayesianMGMFRM.Experimental.GeneralizedPrior(;
    person_sd = 1.0,
    rater_sd = 1.0,
    item_sd = 1.0,
    log_discrimination_sd = 1.0,
    log_consistency_sd = 1.0,
    step_sd = 1.0,
)

prior_check = BayesianMGMFRM.Experimental.prior_predictive_check(spec;
    prior = unit_raw_prior,
    ndraws = 500,
    rng = Random.MersenneTwister(20260813),
)

sensitivity_fit = BayesianMGMFRM.Experimental.fit(spec;
    prior = unit_raw_prior,
    backend = :advancedhmc,
    ndraws = 500,
    warmup = 500,
    chains = 4,
    seed = 20260814,
)
```

The same resolved scale values enter experimental fit-cache keys. Direct-scale
generalized priors remain unsupported because they would require a separately
specified transform and change-of-variables policy. The prior-predictive result
contains raw and constrained direct parameter draws, replicated scores, and
implication diagnostics. Use it before fitting, then use actual refits—not only
importance reweighting—to assess posterior sensitivity.

For MGMFRM, the ability-scale row in `diagnostics` and `fit_report` records
the actual `person_sd` in `row.prior.sd`; `fit_artifact` also exposes it as
`ability_prior.sd`. SD 1 retains the `:standard_normal_by_dimension` label;
other scales use `:normal_by_dimension`. These describe independent
`Normal(0, person_sd)` priors conditional on fixed hyperparameters, not
posterior uncertainty or proof of identification. Fixed identity correlation
does not imply unit covariance when `person_sd != 1`. Fit artifacts and report
Q sections mark their embedded design/source-reference prior and gauge metadata
with `design_prior_scope = :source_reference_not_resolved_fit_prior`.
The design manifest itself is unchanged, preserving existing fit-cache keys.
Pointwise/scale checks without a prior report the scale as missing.

For these generalized fits, the posterior density is defined with respect to
the free raw coordinates. Exponentiating a sampled log-loading or
log-consistency, or reconstructing a constrained coordinate, adds no Jacobian
term to that target. Both Julia and the package's Stan models use this
convention; Stan samples an unconstrained `beta` vector. The fit's
`log_posterior` therefore remains a raw-coordinate density even when you inspect
`direct_draws`. Summaries and plots of transformed draws need no density
adjustment. Expressing a density in different coordinates does: for a free
positive coordinate `a = exp(z)`, `log p_a(a) = log p_z(log(a)) - log(a)`.
This distinction follows the
[Stan change-of-variables rule](https://mc-stan.org/docs/stan-users-guide/reparameterization.html#changes-of-variables).

To inspect intervals without arranging draw matrices yourself, load CairoMakie
and call `BayesianMGMFRM.plot_posterior(fit_result; block = :person)`.
The interval figure defaults to model coordinates; `scale = :raw` selects
computational coordinates. For MGMFRM, select a dimension by its index or declared
label with `dimension = 2`. Dimensions have separate axes and retain their labels.
Use `BayesianMGMFRM.plot_diagnostics(fit_result; block = :person)` for retained
chain traces and rank histograms, defaulting to computational coordinates and
using the fit's recorded diagnostic settings.

`BayesianMGMFRM.plot_predictive(fit_result; ndraws = 200, seed = 42)` compares
category proportions for the original rating rows with conditional posterior
replications. It does not introduce new persons, items or raters.
Generalized plots are marked experimental. The [plotting guide](fitting.md#Posterior-interval-figures)
also covers editing, PDF/SVG output, and cache reload.
`BayesianMGMFRM.plot_wright` supports stable MFRM only and rejects generalized
fits; generalized loadings and scales need their own interpretation.

Equal raw scales do not imply exchangeable constrained priors. For MGMFRM,
the last sorted rater severity is the negative sum of the other `R - 1`
coordinates. With raw variance `s²`, its variance is `(R - 1)s²`, whereas each
free severity has variance `s²`. The same asymmetry holds for log-consistency;
the final reconstructed item step also has a different induced variance when
there are more than three categories. Consequently, renaming raters so that a
different rater occupies the reconstructed position can change the posterior
target even when ratings and matched likelihoods are unchanged. This matters
especially when the data weakly constrain a rater; it is not a data-exclusion
rule or evidence that a particular rater is unreliable.

Setting every raw scale to one is a sensitivity setting, not replication of
the complete prior in [Uto (2021), Appendix 1](https://doi.org/10.1007/s41237-021-00144-w).
For example, that code applies the severity normal density to the full
constrained rater vector, including its reconstructed coordinate; the current
package applies it only to the free coordinates. Matching the response equation
or the two package backends therefore does not establish source-posterior
equivalence. An exchangeable alternative needs an explicit prior/scale decision
and validation before it replaces this experimental policy.

If sampler counts are omitted, both guarded families currently use 100 warm-up
iterations and retain 100 draws per chain across two chains. Thus warm-up is
50% of the 200 iterations per chain and is discarded before the returned draw
matrix is constructed. This is a computational default, not analysis guidance.
The explicit 500 warm-up plus 500 retained draws in the example is also only an
example; choose and report a larger budget when diagnostics or the inferential
target require it. The stable MFRM `fit` entry point has a separate default of
1,000 warm-up plus 1,000 retained draws per chain.

Both guarded configurations accept either `backend = :advancedhmc` or
`backend = :cmdstan`. Each CmdStan route uses a package-owned Stan model,
samples the same raw-coordinate prior, applies the Julia identification
transform, and checks Stan's generated pointwise log likelihood against Julia
at every retained draw. The MGMFRM route remains fixed-Q and
identity-correlation only. Experimental `cached_fit` remains AdvancedHMC-only.
CmdStan is an optional external runtime; inspect it with
`cmdstan_backend_check()` before requesting that backend.

The older `fit(spec; experimental = true)` form remains available during the
migration, but new code should not depend on it. Passing `experimental` inside
the namespace is rejected because the namespace itself is the opt-in.

## Two-dimensional correlation density

The experimental namespace also provides a density for an exactly
two-dimensional simple-structure Q design with at least two
pure items per dimension and observations on both dimensions for every person.
It appends one raw coordinate `zρ` to the existing parameter vector and sets
`ρ = tanh(zρ)`. Person abilities receive a bivariate normal prior with fixed
marginal scale and correlation `ρ`; `ρ` receives a normalized two-dimensional
LKJ prior including the `tanh` Jacobian. Existing response likelihood terms and
all earlier raw coordinates remain unchanged.

```julia
correlation_spec = mfrm_spec(data;
    family = :mgmfrm,
    dimensions = 2,
    thresholds = :partial_credit,
    discrimination = :none,
    q_matrix = Bool[1 0; 0 1; 1 0; 0 1],
)

candidate = BayesianMGMFRM.Experimental.
    free_latent_correlation_2d_candidate(correlation_spec; lkj_eta = 2)

raw = BayesianMGMFRM.initial_params(candidate; zrho = 0.0)
state = BayesianMGMFRM.Experimental.
    free_latent_correlation_2d_state(candidate, raw)
diagnostics = BayesianMGMFRM.Experimental.
    free_latent_correlation_2d_diagnostics(
        correlation_spec,
        raw;
        finite_difference_coords = (1, 2, length(raw)),
    )
```

This exactly two-dimensional implementation accepts positive integer `lkj_eta` values.
Its name deliberately retains `2d`: independently transforming pairwise
correlations would not ensure a positive-definite matrix in higher dimensions,
where an LKJ-Cholesky parameterization is required. The candidate has no public
MCMC fit entry point, fit type, or cache key. Its public diagnostics evaluate
the density and selected gradient coordinates only; they do not assess sampler
convergence or response-level recovery.

## Stability and evidence limits

Experimental types, arguments, parameterizations, and report details may
change in a minor release. A successful run demonstrates only that exact
configuration. It does not establish broader source-equation coverage,
identification robustness, known-truth recovery, predictive validity,
sensitivity robustness, external-software agreement, construct validity, or
real-data validation.

Targeted Float64 tests exercise the stable-residual switch and extreme
subnormal inputs, but they do not establish numerical stability for every
dataset or sampler trajectory. At the smallest representable scales, gradient
contributions may round to zero; users should treat this as a documented
numerical limit rather than validation evidence.

Artifact digests support transport and reproducibility checks, but a matching
digest does not by itself establish scientific equivalence, execution
authenticity, or external validation.

```@docs
BayesianMGMFRM.Experimental
BayesianMGMFRM.Experimental.GMFRMFit
BayesianMGMFRM.Experimental.MGMFRMFit
BayesianMGMFRM.Experimental.GeneralizedPrior
BayesianMGMFRM.Experimental.surface_contract
BayesianMGMFRM.Experimental.free_latent_correlation_2d_contract
BayesianMGMFRM.Experimental.preview
BayesianMGMFRM.Experimental.prior_predict
BayesianMGMFRM.Experimental.prior_predictive_check
BayesianMGMFRM.Experimental.free_latent_correlation_2d_candidate
BayesianMGMFRM.Experimental.free_latent_correlation_2d_state
BayesianMGMFRM.Experimental.free_latent_correlation_2d_diagnostics
BayesianMGMFRM.Experimental.fit
BayesianMGMFRM.Experimental.fit_cache_key
BayesianMGMFRM.Experimental.cached_fit
```
