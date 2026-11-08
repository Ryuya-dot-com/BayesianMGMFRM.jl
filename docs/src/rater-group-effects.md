# Group differences in rater severity

Does a judge rate one group more severely than another, after allowing the groups
to differ in ability? `Experimental.RaterGroupEffects` fits **relative severity
within an explicitly defined rater panel**. For example, compare the gap between
judges R1 and R2 for groups B and A. This is a uniform severity effect on adjacent
category logits, not a different use of middle categories or an ability-dependent
slope. The route is Experimental.

## Choose the question before fitting

The existing [DFF screening](interpreting-results.md) uses residual information
from a baseline scalar MFRM. It does not jointly estimate the new effects.
Here, ability, item difficulty, rater severity, item steps and rater-by-group
severity are estimated together. Ordinary `mfrm_spec(...; bias=...)` terms
remain validation-only; the new route has separate results and reporting.

A shared penalty applied by **every** rater to one group is indistinguishable
from that group's lower ability in these data. Centering chooses a panel
reference; it does not prove the panel is unbiased. Adding the same group-specific
constant to both abilities and all rater severities leaves response probabilities
unchanged. An absolute group-bias claim requires external identifying information
and substantive justification beyond this model.

Group-specific rater functioning and overall fit are different questions;
Engelhard's [DRF example](https://www.rasch.org/rmt/rmt213f.htm) illustrates why
apparently ordinary overall fit can conceal group differences. Severity and
centrality are separate effects in
[Jin and Eckes (2022)](https://doi.org/10.1177/00131644211043207).
This implementation covers uniform severity only; it is not their dual-effect
model or a replication of their validation study.

## Input, fit and read a contrast

Use one row per observed rating and declare the full consecutive category
support, including unobserved categories. Preserve IDs when
[reading CSV](data-validation.md). `group` is an observed person attribute: it
cannot change across a person's rows. Do not label missing ratings as zero.

```julia
using BayesianMGMFRM
RG = BayesianMGMFRM.Experimental.RaterGroupEffects
# ratings has columns person, item, rater, group and score.
data = FacetData(ratings; person=:person, item=:item, rater=:rater,
    group=:group, score=:score, category_levels=0:2)
# Illustrative logit scales, not scientifically recommended defaults.
prior = RG.Prior(person_sd=0.9, group_mean_sd=1.4, item_sd=0.7,
    rater_sd=0.6, step_sd=0.8,
    interaction_logmean=log(0.5), interaction_logsd=0.6)
target = RG.model(data; prior)
RG.design(target)
result = RG.fit(target; ndraws=2000, warmup=1000, chains=4,
    seed=73, target_accept=0.95, max_depth=12, progress=true)
save_fit("group-effects.jls", result)
report = posterior_summary(result; reference_group="A", practical_threshold=0.3)
comparison = RG.contrast(result; left="R1", right="R2", group="B",
    reference_group="A", practical_threshold=0.3)
comparison.difference_in_differences
categories = RG.category_report(result)
save_report("group-effects.json", report)
save_report("group-categories.json", categories)
restored = load_fit("group-effects.jls")
```

The runnable `examples/rater_group_effects.jl` uses one saved simulated dataset
and supports `--saved-fit PATH`; it does not regenerate data when reviewing a
fit. Labels must match the input's values and types.

The default executes chains serially. To use bounded parallel chains, start
Julia with multiple threads and pass `chain_execution=:threads` and
`max_parallel_chains=2`. Separate per-chain random streams are stable across
worker caps in the checked reference environment; serial and threaded streams
need not be identical. Analytic gradients avoid differentiation through an
observation-by-category probability matrix. Extra workers require extra memory;
no proportional speedup or all-model claim follows.

`difference_in_differences` is

```math
(\rho_a+\gamma_{aB}-\rho_b-\gamma_{bB})
 -(\rho_a+\gamma_{aA}-\rho_b-\gamma_{bA}).
```

A positive value means R1 is relatively more severe compared with R2 for B
than for A. `at_group` and `at_reference_group` retain the two component gaps;
`report.changes` compares each rater across groups. Effects use joint posterior
draws, not differences of separately computed interval bounds. The practical
threshold is an analyst-chosen logit difference. An interval containing zero
is not proof of equivalence; posterior probabilities are not multiplicity-adjusted
bias declarations. Examine all diagnostic warnings, focal mean and interval-endpoint
MCSE and event-probability MCSE. A constant sampled event can have unavailable
MCSE, not known zero probability error.

Native files require trusted input, the producing source and its environment.
The JSON file is a computed report, not a portable posterior sample format.
Hashes, target/prior, row order, chain and iteration identities are checked on
native restoration. Existing files are not overwritten.

## Separate the scientific question from numerical precision

A positive **change in the rater gap** does not imply a positive gap within
every group. One saved execution of the bundled simulated example gave:

| Quantity | Mean [95% interval], logits | Question |
| --- | --- | --- |
| R1 minus R2 at B | 0.357 [-0.404, 1.141] | Is R1 more severe than R2 within B? |
| R1 minus R2 at A | -0.978 [-1.758, -0.239] | Is R1 more severe than R2 within A? |
| Change in gap, B minus A | 1.336 [0.278, 2.508] | Does their relative severity change between groups? |

The change interval excludes zero while the B interval includes it. These
answer different questions, so there is no contradiction. This illustrative
fit passed whole-fit diagnostics but missed its predeclared upper-endpoint
MCSE limit: 0.02075 versus 0.02. The table therefore is not presented as a
fully qualified numerical result or a finding about real group fairness.

The runnable example now prints these three quantities separately and saves
`assessment.json` alongside its fit and reports. The assessment retains the
contrast labels, evaluated-draw and sample identities, explicit limits and a
`pass`, `fail` or `unavailable` status for each numerical check. It separates:

- Whole-fit raw/model/sampler diagnostics, including divergences.
- Focal rank-normalized R-hat and bulk/tail ESS.
- MCSE for the focal mean, both interval endpoints and each event probability.

`numerical_checks_passed` requires all these checks. A whole-fit pass alone
cannot make it true, and unavailable precision never counts as a pass. The
teaching example uses mean MCSE 0.01, endpoint MCSE 0.02 and event MCSE 0.005;
these are computational accuracy limits for this example, not package-wide
scientific defaults. Choose needed accuracy before inspecting a result. The
practical effect threshold 0.3 logits is a different, substantive choice.
A numerical pass still does not assess model adequacy, prior sensitivity,
multiplicity, equivalence or fairness.

Posterior uncertainty and Monte Carlo uncertainty also differ. In the saved
illustration, the change had posterior SD 0.567 and mean MCSE 0.0061. More
accurate computation of its mean would not remove the broad posterior interval.
A small mean MCSE does not guarantee accurate tail endpoints or establish
agreement with a generating value.

For a fit with a divergent transition, retain the warning even when its
R-hat/ESS and retained-point density look ordinary. The retained point need not
be the trajectory point where integration failed. Inspect available trajectory
metadata; it cannot reconstruct an unrecorded proposal or establish the cause
of difficult geometry. Do not delete flagged draws to obtain a clean report or
mix warmup into the posterior. Resolve the sampling problem before trusting the
sample; a longer retained chain by itself addresses Monte Carlo precision, not
integration accuracy. See the [Stan diagnostic guidance](https://mc-stan.org/learn-stan/diagnostics-warnings.html)
for the distinction between divergences, convergence summaries and focal MCSE.

## Compare observed and expected category use

Converged chains do not show that the model describes the observed ratings.
`RG.category_report(result)` compares observed category proportions and mean
scores with their conditional posterior expectations, overall and separately
for each rater/group and item/group cell. It uses every original rating and
retained draw, preserving the declared category support.

```julia
categories = RG.category_report(restored; interval=0.95)
# These are rows for the labels used in the input; other labels remain intact.
rater_b = filter(row -> row.facet == :rater_group &&
    row.level == "R1" && row.group == "B", categories.category_rows)
item_b = filter(row -> row.facet == :item_group &&
    row.level == "i1" && row.group == "B", categories.score_rows)
[(row.category, row.observed_proportion, row.expected.mean,
    row.expected.lower, row.expected.upper) for row in rater_b]
categories.sampling_warning
```

For an observed cell ``C`` and retained draw ``s``, the reported expectation is

```math
\bar p_{Ck}^{(s)}=\frac{1}{|C|}\sum_{n\in C}P(Y_n=k\mid\psi^{(s)}),\qquad
\bar m_C^{(s)}=\sum_{k\in\mathcal K}k\bar p_{Ck}^{(s)}.
```

The score calculation uses the declared scores, including a nonzero minimum.
Expected-score intervals are computed from joint draws, not from sums of
separately calculated category interval bounds. Each `expected` summary carries
mean and endpoint MCSE. `precision_threshold_applied=false` means that the
function has not chosen scientific or numerical acceptance limits for you.
Constant sampled quantities can have unavailable MCSE; they are not declared
precisely known. Whole-fit diagnostics and their warnings remain in the report.

`observed_minus_expected` is observed proportion or mean score minus the
posterior mean expectation. It is descriptive. The expected-value interval
describes parameter uncertainty; it is **not** a replicated-score/count interval,
a p-value or a simultaneous model-fit test. An observed proportion outside it
does not by itself establish misfit. Fitting and reviewing the same observations
can also conceal inadequacy. Examine the magnitude and pattern, the cell size,
model assumptions and a justified predictive or alternative-model check before
making a substantive decision.

Cells can contain different people or items. Their raw expected means are not
adjusted rater contrasts; use `RG.contrast` for the specified rater-gap question.
Item/group discrepancies can prompt an item-invariance review but do not identify
item DIF as the cause. Similarly, differences in category use do not by themselves
establish centrality or unfairness.

An observed cell retains categories with zero observations and their nonzero
model probabilities. A cell with no ratings instead has `status=:unobserved_cell`,
`expected=nothing` and unavailable observed proportions/means: there is no
observed assignment over which to average. It is not filled with artificial
zero scores. This report does not predict unobserved assignments or new levels.

The example saves these rows in `categories.json`, including when invoked with
`--saved-fit`. Computation uses a cell-level accumulation array, avoiding a
draws-by-observations-by-categories tensor. `max_prediction_cells` bounds its
Float64 accumulation/logit workspace: ``S K[1+(R+I)G]+K``. The default is
20,000,000 cells; exceeding the budget raises an error rather than silently
subsampling. Restored samples, coordinate transforms, summaries and diagnostic
memory are outside this workspace limit. No simulated responses are generated.

## [Check a selected category count against its predictive distribution](@id group-category-predictive-check)

Use this operation for a different question from an expected-value interval:
**how often would the fitted model produce a count at least as low or as high
as the observed count for this rater, group and category?** Choose a discrepancy
for the scientific question, preferably before inspecting the fitted results.

```julia
# Reuse a saved RaterGroupEffects result; no inference or outcome generation.
check = RG.category_predictive_check(result;
    rater="R2", group="A", category=1)
check.observed_count
check.expected_count.mean
check.lower_tail.mean       # P(N_rep <= N_observed | ratings)
check.lower_tail.mean_mcse
check.upper_tail.mean       # P(N_rep >= N_observed | ratings)
check.observed_mass.mean    # P(N_rep == N_observed | ratings)
check.diagnostics.qualified # Whole fit; also inspect each summary's diagnostics
check.sampling_warning
check.mcse_warning
save_report("selected-category-check.json", check)
```

The example writes this R2/A/category-1 check to `predictive.json` in fit and
saved-fit modes. That cell was selected after noticing a descriptive gap in
the example: it is an exploratory follow-up, not a confirmatory test. Selecting
many cells and reporting only the smallest probabilities adds selection bias;
these marginal tails provide no multiplicity control. Retain the full set of
checks you chose, their reasons and all warnings.

At joint draw ``s``, each selected indicator ``I(Y_j^{rep}=k)`` has its own
conditional probability ``p_j^{(s)}``. This model makes those indicators
conditionally independent, so their sum follows a Poisson-binomial distribution.
Its probability coefficients obey the positive recurrence

```math
f_j(c)=(1-p_j)f_{j-1}(c)+p_j f_{j-1}(c-1),\qquad f_0(0)=1.
```

The code updates coefficients in descending count order using one array.
It sums each inclusive tail directly and then averages over the retained
joint draws. It does not replace the heterogeneous probabilities by their
average or use a single binomial distribution. Posterior dependence is preserved
by integrating each joint draw before averaging. The count method is exact
conditional integration up to floating-point error; averaging over MCMC draws
still has numerical error. The distribution and computational alternatives are
discussed by [Hong (2013)](https://doi.org/10.1016/j.csda.2012.10.006);
this implementation uses the recurrence, not Hong's Fourier algorithm.

Read `mean_mcse`, `mcse_status` and `diagnostics` for each reported quantity
alongside the whole-fit diagnostics. No precision threshold is silently selected.
A constant sampled function has unavailable MCSE rather than established
certainty; tiny probabilities can underflow in floating point. A support-fixed
inclusive tail is different: `P(N_rep >= 0)=1` and `P(N_rep <= n)=1` are labelled
structurally fixed with zero numerical error. The two inclusive tails sum to
one **plus** the probability of the observed count. They are not complements,
and neither a two-sided test nor a rejection threshold is supplied. No intervals
for conditional tail probabilities or predictive count quantiles are reported.

The check follows the posterior predictive approach of
[Gelman, Meng and Stern (1996)](https://www3.stat.sinica.edu.tw/statistica/j6n4/j6n41/j6n41.htm).
As explained in the [Stan guide](https://mc-stan.org/docs/stan-users-guide/posterior-predictive-checks.html),
predictive tail probabilities are not generally calibrated frequentist p-values.
A small tail identifies a feature to investigate, not centrality, item DIF or
unfairness as its cause. A large tail does not prove model adequacy.

All original rows in the selected cell and all retained draws are used. The
prediction repeats the existing people, items, rater and group allocation;
it does not predict new levels or add shared-response/halo-class dependence.
The positive recurrence takes ``O(Sn^2)`` work and ``4S+n+1+K`` Float64 work
cells. Coordinate reconstruction, restored draws, validation and diagnostics
are additional costs. `max_count_updates=50_000_000` bounds the recurrence's
``S n(n+3)/2`` coefficient updates. Exceeding that budget raises an error;
raise it explicitly for a justified larger check, rather than silently thinning
draws. No response simulations or new posterior fits occur.

## Model, prior and identification

For category indices ``k=1,\ldots,K-1``, after shifting the declared minimum
score to index zero,

```math
\log\frac{P(Y_{pri}=k)}{P(Y_{pri}=k-1)}
 =\theta_p-b_i-\rho_r-\gamma_{r,g(p)}-s_{ik}.
```

All coefficients are one. Items and their steps are invariant across groups.
Item difficulty, rater severity and each item's steps sum to zero; the
interaction sums to zero across both raters and groups. The reference weights
facet levels equally, not according to their observed rating counts. Changing
the panel or group roster changes that reference and prior.

Let ``H_n`` be an orthonormal zero-sum Helmert basis. For group ``g`` with
``n_g`` observed people,

```math
\theta_g=\mu_g\mathbf{1}+
 \frac{\sigma_p}{\sqrt{1-1/n_g}}H_{n_g}z_g,
\qquad \mu_g=\sigma_\mu u_g.
```

Thus ``\mu_g`` is exactly the mean ability of the observed finite cohort,
not a separately inferred superpopulation mean. Group means have independent
normal priors, so groups are not forced to share an ability mean. Within-group
residuals have marginal variance ``\sigma_p^2`` and negative covariance from
the sum constraint. Fixing that variance is an explicit restriction; this route
does not estimate different group variances.

```math
b=\sigma_b H_I z_b,\quad \rho=\sigma_r H_R z_r,\quad
s_i=\sigma_s H_{K-1}z_{s_i},\quad
\Gamma=\frac{\tau}{\sqrt{(1-1/R)(1-1/G)}}H_R Z H_G^\mathsf{T},
\quad \log\tau\sim N(m_\tau,s_\tau^2).
```

All entries of ``u,z,Z`` are independent standard normal coordinates. In
particular, conditional on ``\tau``, each interaction cell has variance
``\tau^2``; its constrained neighbors are correlated. The sampled target is
normalized with respect to these white coordinates and ``\log\tau``. Its prior
contains the normal constants, including ``-\log s_\tau``; no extra Jacobian is
added for a generative coordinate map. A density specified instead with respect
to model-coordinate measure must transport its prior and Jacobian consistently.
Equal SD values under different identifying constraints need not give the same
joint prior. Binary data have fixed zero item-step deviations.

The first route requires at least two groups, raters and items, two distinct
people per group, and every rater-by-group cell observed. It additionally checks
the location-design rank after eliminating person intercepts: item contrasts
and group-specific rater contrasts must be estimable. This conditional design
check catches allocations that counts alone miss. It does not establish adequate
category information, posterior precision, or validity of invariant items.
Incomplete individual assignments and unequal cell counts are permitted when
these requirements hold; disconnected or confounded allocations are rejected.
The rank calculation stores a square matrix in the number of item and
group-specific rater contrasts, not the number of people.

## What remains outside this route

The implementation does not fit group-varying items or steps, centrality,
free slopes, latent groups, multiple dimensions, covariates, time processes,
anchors or combinations with other experimental effects. Item DIF, omitted
dependence and assignment related to unmodeled performance can invalidate a
severity interpretation even with good MCMC diagnostics. Assess the design,
residual fit, plausible alternative explanations and prior sensitivity before
substantive use. The small simulated execution examples establish a checked
operation, not general false-positive rates, power, recovery or fairness.
