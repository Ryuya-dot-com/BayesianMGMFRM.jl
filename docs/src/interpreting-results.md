# Reading Results and Comparing Models

!!! note "Unreleased documentation preview — 13 October 2026"
    This manual includes unreleased interfaces and examples. It is not the
    documentation of an installed release. Model support and scientific
    acceptance remain as stated on each page.

See the [Visualization Gallery](visualization-gallery.md) for Wright Maps,
Pathway Maps and MGMFRM response surfaces with worked reading guidance.

A completed fit produces numbers, but an analysis needs an answer supported by
those numbers. Read the output in this order: computational diagnostics,
uncertainty for the quantity of interest, predictive adequacy, and sensitivity
to defensible assumptions. Model comparison then addresses a specified question.

## Separate three kinds of uncertainty

| Quantity | What it describes | What it does not establish |
| --- | --- | --- |
| Posterior interval | Uncertainty about a parameter or contrast conditional on the model, prior and observed data. | Repeated-study coverage at every possible fixed truth. |
| Monte Carlo standard error, or MCSE | Numerical uncertainty in an estimated posterior summary due to a finite MCMC run. | Small measurement uncertainty or a correct model. |
| Simulation replication standard error | Uncertainty in an average performance measure across independently generated datasets. | Precision obtained by treating many parameters or correlated draws as independent datasets. |

For example, a wide ability interval with a small MCSE means that its posterior
summary is computed precisely but the ability remains uncertain. More adequate
MCMC draws can reduce numerical error; they do not replace more informative
ratings. A narrow interval also needs diagnostic review and checks of the model
and prior before substantive use.

R-hat compares behavior across chains, effective sample size (ESS) describes
information in dependent draws, and divergences flag problematic HMC behavior.
Inspect bulk and tail ESS, because interval endpoints can be much less precise
than a posterior mean. Passing diagnostic thresholds is useful computation
evidence, not a proof of convergence, identification, recovery or substantive
validity. The [fitting guide](fitting.md) explains the available diagnostic output.

## [Choose 90%, 95% or 99% credible intervals](@id credible-interval-levels)

A credible interval (CrI) needs both a **probability mass** and an **interval
rule**. The current summaries and plots use central, equal-tailed intervals
(ETIs): a 90% ETI runs from the 5th to the 95th posterior percentile, while a
99% ETI runs from the 0.5th to the 99.5th percentile. Neither 90% nor 95% is a
package-wide requirement; defaults differ across functions. Choose a level
appropriate to the reporting question and state it explicitly.

For an existing scalar MFRM fit, set both the main columns and interval list:

```julia
using BayesianMGMFRM

rows99 = posterior_summary(fit;
    lower = 0.005, upper = 0.995, intervals = (0.99,))

# The top-level columns and this nested entry now both describe 99% ETIs.
first(rows99).lower
first(rows99).upper
only(first(rows99).intervals)

# Several levels can be retained together; main columns still use lower/upper.
rows_all = posterior_summary(fit;
    lower = 0.005, upper = 0.995, intervals = (0.90, 0.95, 0.99))
```

`lower` and `upper` are **quantile probabilities**; `intervals` contains
**interval masses**. Supplying only `intervals = (0.99,)` adds the requested
nested interval but leaves the main `lower`/`upper` columns at their default
2.5th and 97.5th percentiles. There is no `interval = 0.99` keyword for this
summary function.

For experimental GMFRM and MGMFRM, `posterior_summary` describes raw
computational coordinates. Use the qualified model-scale summary for positive
loadings and rater consistencies:

```julia
model_rows99 = BayesianMGMFRM.direct_posterior_summary(fit;
    lower = 0.005, upper = 0.995, intervals = (0.99,))
```

Fixed-coefficient multidimensional MFRM also supports these two summary calls;
its direct summary reconstructs model coordinates. Always report the coordinate
and units of the quantity being summarized.

The plotting and response-surface interfaces instead take a single mass:

| Output | Explicit 99% request | Scope |
| --- | --- | --- |
| Parameter interval plot | `BayesianMGMFRM.plot_posterior(fit; interval = 0.99)` | Supported saved-fit types; model coordinates by default. |
| Wright Map | `BayesianMGMFRM.plot_wright(fit; interval = 0.99)` | Stable scalar MFRM. |
| Numerical response surface | `BayesianMGMFRM.item_response_surface(fit; item = "I1", rater = "R1", interval = 0.99)` | Independent fixed-Q MGMFRM; substitute actual labels. |
| Rendered response surface | `BayesianMGMFRM.plot_response_surface(fit; item = "I1", rater = "R1", interval = 0.99)` | Same surface scope; includes interval-width panels. |

Load `CairoMakie` for the plotting calls; the numerical surface needs no renderer.
Titles and figure notes remain outside images by default. In a Wright histogram,
person bars count posterior medians; they are not individual credible intervals.
The interval argument applies to the interval summaries, not to histogram bins.
Surface intervals concern each conditional probability or expected rating at
one ability grid point. They are not simultaneous bands or predictive intervals
for individual future scores.

Changing the interval level reuses the existing draws and does not require
refitting. Means and medians remain unchanged; 99% ETIs are at least as wide as
90% ETIs computed from the same draws. However, farther-tail endpoints need
adequate numerical precision. Request MCSE at the endpoints actually reported:

```julia
precision99 = posterior_mcse(fit; probabilities = (0.005, 0.5, 0.995))
```

The default coordinate for this MCSE call matches the identified scalar MFRM
or the direct generalized/multidimensional model coordinates. To match a raw
GMFRM/MGMFRM summary instead, add `parameter_space = :raw_unconstrained`.
Inspect the returned status and endpoint MCSE together with chain diagnostics;
a returned number alone does not establish tail precision. The
[Stan posterior documentation](https://mc-stan.org/posterior/reference/mcse_quantile.html)
explains quantile MCSE. Existing 90% simulation coverage results do not become
99% coverage evidence simply by changing an output setting.

## [Is a highest-density interval available?](@id highest-density-intervals)

**BayesianMGMFRM currently has no integrated HDI/HPD summary or plot option.**
An ETI is already a Bayesian credible interval; it is not an approximation to
an HDI. For a continuous unimodal posterior, an HDI selects the shortest interval
containing the requested mass. Unlike an ETI, its excluded tail probabilities
need not be equal. The two can differ substantially for skewed posteriors.

For example, a unit-rate exponential posterior has a 90% ETI approximately
``[0.0513,2.9957]`` and a 90% HDI ``[0,2.3026]``. Both contain 90% probability;
they answer different interval-selection questions. The density is highest
at zero, explaining why the HDI starts there. With separated modes, a highest-density
region can have disconnected pieces; forcing one interval can span low-density
values. HDIs also depend on parameterization: computing an HDI for a log loading
and exponentiating its endpoints need not give the HDI of the positive loading.
Choose the scientific reporting scale first.

The separate Julia package
[PosteriorStats.jl](https://julia.arviz.org/PosteriorStats/stable/api/#PosteriorStats.hdi)
provides `hdi(values; prob = 0.99)` and explicitly documented multimodal methods.
Here `values` must contain draws of **one chosen scalar parameter or draw-wise
contrast on the intended scale**, not a matrix pooling different parameters.
This is an optional external calculation, not a BayesianMGMFRM API or dependency;
it is not installed or exercised by this guide. Retain the original chain
ordering for diagnostics, label the resulting interval as an HDI, and assess
its numerical stability. The ETI endpoint MCSE call above does not by itself
supply MCSE for estimated HDI boundaries. Changing interval rules cannot repair
a poorly explored posterior.

## Interpret a contrast, not overlapping marginal intervals

Suppose the question is whether P1 has higher communication ability than P2.
For each joint posterior draw ``s``, calculate

```math
\Delta^{(s)}=\theta_{\mathrm{P1,communication}}^{(s)}
             -\theta_{\mathrm{P2,communication}}^{(s)}.
```

Summarize these differences directly. Do not subtract the endpoints of two
marginal intervals: the two abilities can be dependent in the posterior.
A hypothetical 90% posterior interval ``[0.10,0.70]`` supports a positive
difference under the fitted assumptions, but its practical importance requires
a justified ability unit and a substantive benchmark. An interval spanning zero
does not by itself establish equivalence.

For raters, a positive severity contrast means the first rater is more severe
under the model's sign convention. A consistency ratio describes relative
probability concentration; it does not label one rater more reliable or fair.
The [saved-fit contrast example](examples.md#Compare-abilities-or-raters-in-a-saved-MGMFRM-fit)
keeps joint draws, diagnostics and MCSE together without fitting again.

## Ask what a predictive check actually checks

A posterior predictive check generates replicated ratings from the fitted
model and compares relevant features with the observations. Examine category
use and patterns by rater, item and person, not only an overall average.
An aggregate match can hide a systematic mismatch in a subgroup.
Prior predictive checks perform the corresponding simulation before conditioning
on the observed scores, to inspect the implications of the chosen priors.
These operations and their different roles are explained in the
[Stan predictive-check guide](https://mc-stan.org/docs/stan-users-guide/posterior-predictive-checks.html).

Reproducing existing rating rows assesses conditional fit. It does not establish
performance on withheld ratings, new people, new items or new raters. Good
score predictions also do not demonstrate that separate loadings and abilities
are recovered correctly: different parameter combinations may predict similarly.

## Compare models against the same prediction task

First state the prediction target. Predicting an additional rating of a known
person is different from predicting a new person's work. Then use the same
observations, category meanings, split and scoring weights for competing models.
If all ratings of a response should be withheld together, keep that response
in one fold and check that the remaining training design is still connected
and contains the required facet levels.

In K-fold cross-validation, fit each model to the training portion of each fold
and evaluate its held-out ratings. A common score is the sum of log predictive
probabilities assigned to the observed held-out categories:

```math
\widehat{\mathrm{elpd}}
=\sum_{n\in\mathrm{heldout}}
\log\left[\frac{1}{S}\sum_{s=1}^{S}
P(Y_n=y_n\mid\phi^{(s)}_{\mathrm{training}})\right].
```

Higher scores mean better predictions of those outcomes under that scoring
rule. Average probabilities **before** taking their logarithm; averaging log
probabilities is a different quantity. This expression scores ratings
individually. Grouping ratings into the same fold does not turn the score into
the joint predictive density of a whole response. Equal weight per rating also
differs from equal weight per person when rating counts differ.

As a deliberately invented example, totals -120 and -116 give a difference of
4 in favor of the second model. The difference alone does not show whether the
advantage is reproducible or useful. Examine uncertainty appropriate to the
sampling/design structure, failures, diagnostic warnings and the magnitude
relevant to your decision. Do not treat overlapping training folds as independent
study replications. Predictive superiority also does not prove that the larger
model's dimensions represent the intended constructs.

WAIC and importance-sampling LOO estimate predictive quantities from fitted
draws under their own assumptions. Importance-sampling instability matters;
see the [official loo example](https://mc-stan.org/loo/articles/loo2-example.html)
for reference PSIS-LOO and its diagnostics. The package candidate's raw IS-LOO
and experimental Hill-smoothed option must not be presented as independently
validated equivalents of that reference implementation.

The current [common comparison guide](common_prediction_comparison.md) describes
saved-fit scoring, explicit refit requests and complete-fold comparison across
supported types. This unreleased candidate retains missing folds and warnings.
Opt-in delta MCSE measures numerical error, not data-sampling SE. Automatic
multi-model refitting, winners and new-level prediction remain unavailable.
Family, dimension and Q comparisons have distinct compatibility checks;
a returned table does not validate model selection.

## Use simulations to plan informative studies

Simulation studies answer different questions depending on how parameters and
data are generated:

| Question | Suitable simulation | Evidence to inspect |
| --- | --- | --- |
| Does the inference procedure reproduce the intended posterior under its own joint prior model? | Simulation-based calibration (SBC). | Rank behavior across independent prior-generated datasets, accounting for ties and MCMC dependence. |
| Can particular abilities, loadings or severity contrasts be estimated under a proposed design? | Parameter recovery at specified truths and design conditions. | Bias, RMSE, interval width/coverage, diagnostics and failure rates, with replication uncertainty. |
| How often would the proposed design meet a precision or decision requirement? | Repeated studies under explicitly justified generating scenarios. | The fraction meeting a prespecified criterion, its uncertainty and sensitivity to the scenarios. |

In SBC, draw parameters from the actual prior, generate data conditional on
them, fit the same model, and locate each generating value among posterior draws.
Across independent datasets, ranks should follow the appropriate discrete
uniform distribution when computation is calibrated. MCMC dependence and ties
need explicit treatment. A flat-looking histogram is a diagnostic, not proof
that all errors are absent or the model describes real ratings. See the
[Stan SBC guide](https://mc-stan.org/docs/stan-users-guide/simulation-based-calibration.html).

For design planning, vary features that can change the intended answer: for
example, the number of people, items per dimension, raters per response, linking
coverage, or missingness. Specify plausible generating values separately from
fitting priors, and evaluate the actual target quantity. Assessing one truth
cannot establish performance throughout a population of truths. Prior-averaged
SBC calibration does not guarantee nominal coverage at every fixed truth.

Keep failed and incomplete planned datasets in the accounting. If difficult
datasets disappear, reported precision and coverage can look better than the
procedure actually delivers. The current common recovery functions evaluate
saved fits against named truths and summarize fixed-truth replications. They
are components for this workflow, not a complete design-planning simulator or
completed SBC validation.

## Write an answer that matches the evidence

A useful report identifies the question, model family and dimensions, data and
rating design, priors and scale constraints, backend and computational controls,
diagnostic concerns, and estimates or contrasts with relevant uncertainty.
Explain what predictive checks or comparisons tested and what assumptions remain.
Retain the saved fit and environment information so that results can be revisited.

For example: “Under the specified two-dimensional model and priors, the
communication contrast was positive, with the reported posterior interval.
The interval's numerical precision was assessed separately. Prediction was
evaluated for withheld ratings of existing persons, items and raters; this
does not establish prediction for new persons.” Add the actual values and
warnings from the analysis; this is a reporting template, not an empirical finding.

Return to [Getting Started](learning-guide.md), follow the
[runnable examples](examples.md), or consult the
[Bayesian Workflow](bayesian-workflow.md) for the detailed sequence of calls.

For saved alternative loading priors in the normalized MGMFRM candidate, see
[Would a different prior change my answer?](prior-sensitivity.md) for named
contrasts, MCSE, failed variants, interval/ridge views and verified exports.

## Bias, reliability and a complete MFRM report

The reporting question should determine the statistic. “Do two raters give the
same scores?”, “Can we distinguish persons?”, and “Does a rater treat one group
differently?” are different questions. A single coefficient cannot answer all
three. The following assessment covers the current development candidate; an
available function is not evidence that every model family supports it.

### What kind of bias is being investigated?

Separate three meanings:

- **Overall severity/leniency:** a rater tends to score everyone lower/higher.
  This is a modeled facet main effect, not by itself differential bias.
- **Differential facet functioning (DFF):** severity depends on an item, group,
  response type or occasion, after accounting for the intended model. Examples
  include rater-by-item interactions and rater-by-group contrasts. An observed
  group mean difference alone is not evidence of bias.
- **Estimator bias:** repeated estimates differ systematically from known truth
  in a recovery study. This is what simulation bias summaries address; it is not
  evidence that a rater is unfair to an observed group.

`dff_report` already screens ordinary `MFRMFit` results. It returns cell counts,
expected-score residual contrasts, a local logit approximation, intervals and
optional practical-magnitude probabilities. Its scope explicitly excludes fitted
DFF effects. The approximation divides score residuals by predictive variance;
it is not a new jointly estimated interaction parameter. The existing
[FACETS procedure](https://winsteps.com/facetman/biasestimation.htm) also needs to
be distinguished: it estimates additional bias terms conditionally after fixing
the main estimates. Reproducing that conditional procedure and fitting a fully
joint Bayesian interaction model are separate validation tasks.

The default `adjustment=:assignment` removes a count-weighted additive surface
from the observed cell residuals separately in every joint draw. The reference
is the observed allocation: each rating has equal weight, so cell weights equal
observed counts, including sparse cells. These are not model likelihood weights,
inverse-variance weights, or weights for a balanced target population. Missing
cells are reported but never imputed. The score-residual surface and the local
cell-logit surface are projected separately.

For cell counts `[9 1; 1 9]`, the purely additive cell residual surface
`[0 0.2; 0 0.2]` now yields zero interaction residuals. The historical observed-
margin arithmetic gives `+0.08` for the first row and `-0.08` for the second.
This is a deterministic arithmetic check, not an empirical finding or a fitted
bias estimate. `adjustment=:observed_margins` reproduces that historical screen
with a warning. Default outputs can change even on a balanced table on the local
logit scale, because averaging and division by predictive variance do not commute.

```julia
# Existing ordinary MFRM fit; this call does not refit the model.
rows = dff_report(fit_result;
    terms = (:rater, :item), adjustment = :assignment,
    interval = 0.99, expected_score_practical_threshold = 0.2)
# The integrated report forwards the same choice:
report = fit_report(fit_result;
    include_dff = true, dff_terms = (:rater, :item),
    dff_adjustment = :assignment)
```

Read `contrast_status` alongside `n_observations`, `assignment_n_components`,
`assignment_additive_rank`, `assignment_interaction_df` and
`cell_residual_fraction`. A tree-shaped observed-cell graph has no independent
interaction contrast. A bridge cell attached to a cycle also has no support for
its own interaction, even when the whole table has positive interaction degrees
of freedom. Such cells retain their raw residuals but have NaN interaction
summaries and `:no_independent_cell_contrast`; a missing cell is `:empty_cell`.
Disconnected components can support contrasts within themselves, not contrasts
between components. `min_n` flags sparse cells rather than silently changing the
reference allocation. Rank/support tolerances and numerical zero cleanup concern
floating-point arithmetic, not statistical significance or a practical margin.

Intervals propagate the fitted base model's parameter uncertainty conditional on
the existing scores and assignment. They are not predictive intervals for another
rating study, sampling confidence intervals, or fitted DFF-parameter intervals.
Use `n_expected_score_dff_draws` and `n_logit_dff_draws` to check availability. An
undefined local logit shift in any observed cell makes that entire term's logit
projection unavailable for that draw. Partial availability remains flagged; its
finite-draw summaries must not conceal missing numerical support. Additive
projection does not remove every possible composition effect within cells or
identify a causal mechanism, and it supplies no calibrated significance test.

A defensible bias report should specify the contrast and direction, practical
margin, logit and/or score-scale effect, interval, cell support and linking,
assignment adjustment, prior/shrinkage assumptions, and the complete set of
comparisons. If many interactions are screened, marginal posterior probabilities
do not automatically provide familywise or false-discovery error control.
Unexpected residuals may reflect multidimensionality, dependence or assignment,
not a uniquely identified bias mechanism. Neither a flag nor an interval
excluding zero by itself establishes unfairness.

For a future fitted interaction API, begin with an identified MFRM interaction
model, explicit row/column constraints and partial pooling, then validate sparse
and unbalanced designs, reference contrasts, and practical decision accuracy.
Group DIF also requires separating group ability distributions from item effects;
adding every possible interaction can destroy that identification. Extend to
GMFRM/MGMFRM only with a declared response equation, dimension and reference
population. Multipliers change the relation between latent contrasts and score
changes, so a common raw-logit interpretation cannot be assumed.

### Reliability, separation and Strata

The conventional separation summary uses a declared variance of estimated facet
measures `V` and mean squared measurement SE `E`. Its positive-part convention is
`A = max(V - E, 0)`, giving

```math
G=\sqrt{A/E},\qquad R=\frac{A}{A+E},\qquad H=\frac{4G+1}{3}.
```

Here `G` is separation, `R` separation reliability, and `H` Strata. For example,
`G=2` gives `R=0.80` and `H=3`. Specify sample/population variance, error definition,
weighting and extreme-score treatment. The [FACETS summary definitions](https://winsteps.com/facetman64/table7summarystatistics.htm)
make these distinctions. Strata is an approximate resolution index; it does not
identify actual latent classes, assign persons to three groups, or establish
classification accuracy at a substantive cutoff. Its derivation uses distribution
and precision assumptions; see [Wright and Masters](https://www.rasch.org/rmt/rmt163f.htm).
A value below one should not be silently relabeled as an established class count.

**Rater separation reliability is not inter-rater agreement.** High rater
separation means severity differences are distinguishable relative to their
estimated error. Low separation can reflect similar severities *or insufficient
information*. It is not proof of equivalence. Person separation can be useful for
distinguishing people but depends on population spread, design and measurement
precision. See the [FACETS reliability explanation](https://winsteps.com/facetman64/reliability.htm).
Do not equate a GMFRM/MGMFRM consistency multiplier with any of these coefficients.

The current `separation_reliability_summary` exists for ordinary MFRM, but its
historical algorithm is a **screen requiring methodological revision**, not a
validated FACETS or EAP reliability estimator. It computes cross-person variance
within each joint posterior draw, subtracts average marginal posterior variance,
truncates at zero, and summarizes the ratios. Finite counterexamples expose why
that matters:

- Four artificial draws `[-1 -1; -1 1; 1 -1; 1 1]` give identical posterior means
  for both persons, yet reported mean reliability is `1/6`, about `0.167`.
- With a person contrast fixed at 2 in every draw, changing only a common random
  location shift changes reported reliability from about `0.993` to `0`.

These are tests of the formula, not fitted posterior samples or a universal
replacement definition. They prevent treating the result as an established
measure of rank resolution. No reporting Strata API was found, and applying
`(4G+1)/3` to this historical screen would inherit its unresolved meaning.

The candidate now provides [`BayesianMGMFRM.posterior_reliability`](@ref) for an
explicit finite-cohort target, described below. This does not make it a general
population, test–retest or generalizability coefficient. Population reliability
requires the corresponding population and response distribution.
Nuisance-parameter uncertainty must also be handled;
[Yang et al.](https://pmc.ncbi.nlm.nih.gov/articles/PMC3462470/) demonstrate why
ignoring item-calibration uncertainty can overstate score precision.

For multiple dimensions, report precision/reliability separately by declared
dimension. A composite `w'θ` requires justified weights and full covariance:
`Var(w'θ | y) = w' Cov(θ | y) w`. An average of marginal reliabilities is not a
composite reliability. Strata should be offered only for a justified scalar
measure with a validated separation definition, not as a single number for an
arbitrary multidimensional model.

### An explicit posterior reliability target

Choose the people, items or raters whose locations you want to distinguish. For
one selected dimension and normalized level weights `w_i`, let `X_i` be either
the fitted location (`target=:absolute`) or its difference from the selected
cohort's weighted mean **in the same joint draw** (`target=:centered`). With
`m_i = E(X_i | y)` and `v_i = Var(X_i | y)`, define

```math
\bar m=\sum_i w_i m_i,\qquad
B=\sum_i w_i(m_i-\bar m)^2,\qquad
W=\sum_i w_i v_i,\qquad R_{\mathrm{cohort}}=\frac{B}{B+W}.
```

This has a direct interpretation by the law of total variance. Independently
select a level `I` with probability `w_i` and a joint posterior draw. The variance
of `X_I` is exactly `B + W`: variation in posterior means plus average posterior
uncertainty. `R_cohort` is the fraction due to the first component. The EAP formula
in [TAM's official documentation](https://alexanderrobitzsch.github.io/TAM/reference/WLErel.html)
has the same ratio structure; this implementation explicitly defines its cohort,
centering and joint uncertainty rather than claiming estimator identity.

For `target=:centered`, let `C` be the posterior covariance matrix of the selected
locations and `A = I - 1w'`. The transformed covariance is `A*C*A'`. Centering
joint draws computes this transformation implicitly, including all off-diagonal
terms. Adding any draw-specific shift to every selected location leaves the
centered result unchanged. The absolute result deliberately retains that
uncertainty. Neither target is chosen automatically.

Two equal posterior means give `B=0` and `R_cohort=0` when `W>0`. If all selected
contrasts are exactly fixed in the supplied draws, centering can give `W=0` and
`R_cohort=1`; the result flags empirical zero variance and withholds delta MCSE.
A constant or stuck sampler is not proof of perfect measurement. If both
components are zero, reliability is undefined and returned as `missing`.

The eight common saved-fit types share one entry. Use the inventory to select
estimated locations in a single facet/dimension:

```julia
using BayesianMGMFRM
fit_result = load_fit_cache("my-fit.jls") # trusted local cache
catalog = BayesianMGMFRM.recovery_quantities(fit_result)
people = filter(r -> r.block == :person && !r.fixed, catalog.rows)
chosen_dimension = first(people).dimension # inspect its dimension_label first
parameters = [r.parameter for r in people if r.dimension == chosen_dimension]

absolute = BayesianMGMFRM.posterior_reliability(
    fit_result; parameters, target=:absolute,
)
relative = BayesianMGMFRM.posterior_reliability(
    fit_result; parameters, target=:centered,
)
relative.reliability
relative.between_variance
relative.within_variance
relative.mcse
relative.sampling_warning
```

By default every selected level receives equal weight, regardless of rating
count. Optional positive `weights` follow the order of `parameters`; changing
the selection or weights changes the target. Fixed anchors are rejected rather
than treated as perfectly measured members. Derived estimated constraints remain
eligible. Loadings, category steps, mixed facets and mixed dimensions are rejected.
See `examples/saved_posterior_reliability.jl` in the candidate source for the
cache-only wrapper; this file is not yet released.

The calculation uses normalized probability moments across levels and retained
draws, with no sample-variance correction. The returned ratio is one functional
of the posterior, not one value per draw from a posterior distribution of
reliability. Consequently it has no reported CrI. Its optional numerical MCSE
uses a first-order expansion, retaining the original complete chains. If
`d_i(s)=X_i(s)-m_i`, the influence is

```math
\psi(s)=\frac{W\,[2\sum_i w_i(m_i-\bar m)d_i(s)]
-B\,[\sum_i w_i(d_i(s)^2-v_i)]}{(B+W)^2}.
```

The existing autocorrelation-aware estimator applied to `psi` supplies MCSE.
It is unavailable at `B=0` or `W=0`, with insufficient chains/draws or degenerate
influence. It does not remove finite-Monte-Carlo bias, establish convergence,
or measure repeated-study uncertainty; no automatic precision cutoff is applied.
The saved source/model/prior identities and sampling warnings remain in the output.

A large ratio can reflect a wide selected cohort or informative priors, not just
better data. Do not use it alone to rank models, certify validity, plan a new
rating design or claim rater agreement. Calibration uncertainty is retained when
it is present in the saved joint draws; uncertainty omitted by fixed calibration
cannot be recovered here. Strata is intentionally not derived from this ratio.
The historical `separation_reliability_summary` now emits a migration warning;
its numerical outputs remain unchanged for reproducibility.

#### Saved simulation example

The first planned R1 block of the existing fixed-facet assessment, at loading-prior
SD 0.50, supplies 4,000 retained joint draws. Reusing that one saved fit gives:

| Selected cohort | Target | Posterior reliability | Numerical MCSE |
| --- | --- | ---: | ---: |
| 50 persons, dimension 1 | Absolute location | 0.777329 | 0.001184 |
| 50 persons, dimension 1 | Centered location | 0.794889 | 0.001053 |
| 50 persons, dimension 2 | Absolute location | 0.901848 | 0.000723 |
| 50 persons, dimension 2 | Centered location | 0.920046 | 0.000510 |
| 5 raters | Absolute severity | 0.989180 | 0.000180 |
| 5 raters | Centered severity | 0.989180 | 0.000180 |

Removing the selected persons' shared location uncertainty reduces `W`, so the
centered ratio increases. The rater results agree because these equally weighted
severities already have a sum-to-zero constraint. Their high ratio indicates
distinguishable severity differences, not high score agreement.

This is a descriptive saved-simulation example, not an empirical application,
a prior recommendation or validation of population reliability. The source study
retains all 192 planned/completed fits, including eight unqualified fits; this
single example adds zero fits and zero independent replications. The saved fit's
sampling checks passed, but numerical MCSE is not interval calibration or a
scientific acceptance decision. [Download the numerical summary and provenance](assets/posterior-reliability/summary.json).

### Agreement and practical decisions

`rater_homogeneity_summary` already provides paired severity contrasts, optional
ROPE probabilities and support information for ordinary MFRM. It explicitly
states that severity homogeneity is not observed score agreement. It also
separates fixed anchors from estimated contrasts. `rater_overlap` counts shared
units; it does not calculate an agreement percentage.

The candidate now provides [`BayesianMGMFRM.rater_agreement`](@ref) across the
eight common saved-fit types. It answers: **How often did these raters give the
same score to the same response and criterion, and how much agreement does the
fitted model expect?** It does not ask whether rater severity parameters differ.

```julia
agreement = BayesianMGMFRM.rater_agreement(fit_result;
    dataset_id="assessment-2026",
    observation_ids=rating_ids,      # unique rating IDs, in fitted-row order
    response_ids=performance_ids,   # same performance can have several ratings
    adjacent=1, interval=0.99,
    se_unit=:person)
agreement.overall.exact
agreement.rater_pairs
agreement.unmatched_observation_ids
```

Supply globally unique performance identities from the data collection records;
they may repeat across raters and criteria. If the fitted data already carry
`response_id` metadata, omit `response_ids`. Supplying conflicting identities is
an error. The API also checks person and every recorded optional context field,
including occasion/task/form, and rejects duplicate response–item–rater rows.
Matching by person and item alone can join different performances, so it is never
inferred. Unrecorded context cannot be checked; callers must verify that the IDs
represent the same performance and scoring occasion. Repeated independent scoring
rounds require distinct response/occasion identities, not silent averaging.

Each shared response–item and unordered rater pair contributes one opportunity.
Three raters on one criterion create three opportunities. Overall results weight
these opportunities equally; they do not average pair percentages equally. Each
rater's denominator counts its incident opportunities, so per-rater denominators
sum to twice the overall denominator. All fitted rater pairs appear, including
zero-overlap pairs with `missing` rates. The opportunity ledger preserves both
rating IDs, scores and response/item/person identity. Thus a selective assignment
cannot be mistaken for universal agreement: report coverage and denominators too.

Exact agreement compares original scores. `adjacent=1` includes exact agreement
and a gap of at most one ordinal category position. A tolerance covering the
entire scale always gives one and receives a visible structural flag; it is
uninformative about rater agreement. Categories are **not** recentered at each
rater's lowest observed PCM score. This can differ from the category alignment
in the [FACETS agreement report](https://winsteps.com/facetman64/table7agreementstatistics.htm).

For an opportunity involving raters A and B, each joint posterior draw supplies
category probabilities. Conditional independence gives expected exact agreement
`sum_k p_A(k) * p_B(k)`; adjacent agreement sums products for all permitted category
pairs. Average these probabilities across opportunities *within each draw*, then
summarize those aggregate draws. Shared posterior parameter dependence is retained:
if both raters have probabilities `(0.9, 0.1)` in one draw and `(0.1, 0.9)` in the
other, expected exact agreement is `0.82`, whereas multiplying their marginal
mean probabilities gives `0.50`. The latter answers a different question.

There are three distinct uncertainty statements:

- `expected_lower` and `expected_upper` are equal-tailed posterior intervals for
  the **conditional expected agreement rate** for these fitted responses and
  raters. Choose `interval=0.99` for a 99% interval. They are not predictive
  intervals for realized future agreement or frequentist CIs for the observed rate.
- `mcse` reports chain-aware numerical uncertainty in the expected-rate posterior
  mean and quantiles. Short or degenerate chains keep unavailable flags, alongside
  the fit's sampling warnings. MCSE does not establish convergence or calibration.
- Optional `se_unit=:person` estimates an observed-rate sampling SE by keeping all
  opportunities from the same person together. With `M` opportunities, `G` persons,
  overall rate `p`, and person totals `z_g = sum_j (I_gj - p)`, it computes
  `sqrt(G/(G-1) * sum_g z_g^2) / M`. This is a ratio-linearization approximation
  under independent, exchangeable person clusters, conditional on these raters
  and items. It accommodates unequal numbers of opportunities per person, but
  does not adjust arbitrary crossed dependence or sampling-design weights.
  Fewer than two persons is unavailable and zero empirical cluster variance is
  flagged. The default `se_unit=:none` makes no observed-rate SE claim.

No observed-rate CI, realized predictive interval, kappa, automatic cutoff or
reliability correction is produced. The observed-minus-expected mean difference
is descriptive, not a p-value or a chance-corrected agreement coefficient.

### Choosing an ICC

An ICC answers a different question from the proportion of exactly matching
scores. For example, two raters can rank performances identically while one
always awards a point more. Consistency can then be perfect although absolute
agreement is lower. Choose the definition from the intended use of the scores,
not from which coefficient is larger.

Use [`BayesianMGMFRM.intraclass_correlation`](@ref) for one explicit item and
complete crossed ratings: every response has one rating from the same raters.
The initial candidate computes an observed-score ANOVA point estimate, with no
fitting and no confidence/credible interval or SE. These choices are required:

| Choice | Question answered |
| --- | --- |
| `definition=:agreement` | Do scores agree, counting systematic rater offsets? |
| `definition=:consistency` | Do scores vary together after removing additive rater offsets? |
| `unit=:single` | What is the reliability of one rating? |
| `unit=:average` | What is the reliability of the mean of all K recorded raters? |
| `model=:two_way_random` | Are the raters treated as a sample from a larger rater population? |
| `model=:two_way_mixed` | Is the target this fixed rater panel? |
| `score_scale=:interval` | Can equal numerical score gaps be justified substantively? |

The fixed/random distinction changes the scope of generalization, while the
point formulas for a given definition and unit coincide. The design must justify
that interpretation; naming a random model does not establish representative
rater sampling. See the [psych author's ICC documentation](https://personality-project.org/r/psych/help/ICC.html)
for this distinction and [Liljequist et al. (2019)](https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0219854)
for the ANOVA formulation and systematic rater differences.

The [complete no-fit example](examples.md#Observed-score-ICC-without-fitting)
compares all four definition/unit combinations. The API page shows how to
supply response identities and inspect the ANOVA table.

Negative estimates are retained when the denominator is positive. A nonpositive
denominator produces an unavailable coefficient with an explicit status; constant
scores do not prove reliability. Inspect the returned ANOVA table. The
[ICC API](api-saved-reporting.md#Observed-score-intraclass-correlation) gives the
four equations and the component/denominator interpretation.

The equal-gap assumption is not automatic for ordinal rubric codes. Use the
ordinal alpha operation below when agreement under an ordinal distance is the
intended question; it is not an interchangeable estimate of the same ICC target.
No severity adjustment, trait-dimensional averaging, item pooling, arbitrary
future rater-count projection or population reliability guarantee is supplied.
The mean-score target refers to the actual K raters, not a planned replacement
panel. Interpreting it for future random panels additionally requires the declared
sampling model.

Incomplete or uneven rosters and duplicate response-item-rater cells are rejected,
without imputation or listwise deletion. Responses shared by raters must refer to
the same performance and context, as for score agreement. Multiple performances
from one person remain separate response units; `n_people` and
`repeated_person_units` disclose that dependence. A point estimate is not evidence
for independent sampling. Entirely unobserved responses cannot be recovered from
these data. One-way ICC, sparse-design mixed models and uncertainty estimation
remain outside this candidate's scope.

For a saved fit, put the same choices under `reporting.icc` with shared dataset
and rating IDs. The `intraclass_correlation` report section includes summary,
ANOVA and response-ledger tables in the public JSON/Markdown bundle. The statistic
uses ratings rather than posterior draws; computing it does not remove or repair
sampler warnings in other sections. Report the design, item, score-scale rationale,
all three ICC choices, N/K and absence of an interval alongside the value.

### Observed-score alpha

To describe chance-corrected agreement on one criterion, use
[`BayesianMGMFRM.krippendorff_alpha`](@ref). This reads `FacetData` directly;
it needs no MCMC fit. Select one item label and a measurement level explicitly:

```julia
alpha = BayesianMGMFRM.krippendorff_alpha(data;
    item="fluency", level=:ordinal, dataset_id="speaking-study",
    observation_ids=rating_ids, response_ids=response_ids)
alpha.alpha
alpha.status
alpha.marginal_counts
alpha.singleton_observation_ids
```

Use `:nominal` when categories distinguish kinds and `:ordinal` when their
declared order is meaningful. Category labels in `FacetData` are consecutive
integers; nominal analysis uses them only as codes. Ordinal analysis does not
assume equal numeric gaps. A response ID denotes one performance/occasion and
must agree with the recorded person/context. Different items are not pooled;
the meaning of the selected criterion still requires substantive justification.

For pairable units, the implementation evaluates
`alpha = 1 - observed_disagreement / expected_disagreement`. With category
counts `n_cu` in unit `u` and `m_u >= 2` ratings, coincidence entries are
`O_ck = sum_u n_cu * (n_ku - I(c=k)) / (m_u-1)`. Their margins `n_c` count
pairable ratings, with `N = sum_c n_c`. Expected coincidences are
`E_ck = n_c * (n_k - I(c=k)) / (N-1)`. Each disagreement is the sum of
coincidences times squared distances, divided by `N`. Nominal squared distance
is one for different categories and zero otherwise. Ordinal squared distance
is the squared difference between `cumsum(n_c) - n_c/2` midpoints. This differs
from squared category-code distance. See the
[author's computational reference, sections C–D](https://www.asc.upenn.edu/sites/default/files/2021-03/Computing%20Krippendorff%27s%20Alpha-Reliability.pdf).

Absent ratings are omitted rows; literal missing scores are not accepted by
`FacetData`. Singletons remain in the returned unit ledger but do not affect
either disagreement or the ordinal distances. Entirely unobserved responses
cannot be counted without an allocation roster. `:no_pairable_units` and
`:zero_expected_disagreement` both return missing alpha. Thus identical scores
everywhere do not yield an informative reliability coefficient. Negative alpha
is retained. The result includes both coincidence matrices and distances for
inspection; unlike the exact-agreement rate, it does not weight every rating
pair equally when units have different numbers of raters.

For an existing fit, add `alpha=(item="fluency", level=:ordinal,
response_ids=response_ids)` to `fit_report`'s `reporting` request, with the
shared dataset/rating IDs. Its `krippendorff_alpha` section survives public
report save/reload. Sampler warnings remain attached to the fit, while this
observed-data coefficient does not depend on its posterior draws. This is not
severity-adjusted agreement, an ICC, a posterior reliability ratio or proof of
construct validity. No SE, confidence interval, missingness correction or
automatic acceptable-value cutoff is provided; population uncertainty needs a
separately justified sampling design and resampling method.
An observed rate outside the expected-rate posterior interval is not, by itself,
a calibrated lack-of-fit test: that interval excludes realized-score variation,
and these same ratings were used to fit the model.
All original retained draws are used. Explicit prediction-cell and rater-pair
budgets reject oversized jobs before extraction; the API never silently samples
draws or drops pairs to meet those budgets.

High observed agreement beyond a model's expectation warrants investigation;
it does not uniquely diagnose copying or halo. Report uncertainty at the
response/person level when pairs share responses. ICC or weighted kappa may be
useful complementary summaries when their design, scale and agreement target
are appropriate, but cannot be substituted for facet separation. For pass/fail
or ranking decisions, report the relevant posterior decision probabilities and
conditional precision near the cutoff, not Strata alone.

#### Saved simulation example

This example reuses the same B01/R1, loading-prior SD `0.50` fit used above:
4,000 retained draws for 50 persons, five items and five raters. The recorded
generator draws one score per person–item–rater cell on one simulated occasion.
We explicitly declare each simulated person–item cell a common assessment;
that declaration would require evidence from data collection in an empirical file.
All 1,250 ratings are matched. Ten rater pairs each contribute 250 opportunities,
giving 2,500 overall opportunities; each rater participates in 1,000.

| Agreement definition | Observed rate | Model-expected mean | 95% posterior interval for expected rate |
| --- | ---: | ---: | --- |
| Exact (911 of 2,500) | 0.364400 | 0.375509 | [0.361266, 0.389984] |
| Within one category, including exact (2,003 of 2,500) | 0.801200 | 0.802674 | [0.783463, 0.820635] |

The optional observed-rate person-cluster SEs are `0.015176` and `0.012846`,
respectively. Numerical MCSEs for the two model-expected means are much smaller:
`0.000125` and `0.000164`. The distinction matters: additional MCMC draws may
reduce numerical error but do not create additional independent persons or
ratings. Expected-rate intervals represent posterior parameter uncertainty;
neither these intervals nor the observed SEs are a realized predictive interval.

This single saved simulation demonstrates the workflow, not empirical rater
quality, predictive calibration or a recommended prior. The original assessment
retains its full denominator of 192 planned/completed fits, 184 qualified;
this example adds no fit or independent replication. It was selected as the first
planned R1 block at the middle prior width, not for favorable agreement.
[Download the numerical summary, all pair rows and source provenance](assets/rater-agreement/summary.json).

### Category functioning across model families

Use `BayesianMGMFRM.category_report` to ask whether the declared categories are
used, what their transitions mean in this model, and how category probabilities
change for a specified item and rater. It reads the eight common saved-fit types
without refitting. The ownership of a step is determined by the fitted model;
the report cannot change that ownership after estimation.

| Fitted category model | Owner of centered category steps | Conditional adjacent-category crossing |
| --- | --- | --- |
| Ordinary MFRM rating scale | Shared across items and raters | Item position + rater severity + shared step |
| Ordinary MFRM PCM | Item | Item position + rater severity + item step |
| Scalar GMFRM | Rater | Item position + rater severity + rater step |
| MGMFRM and canonical fixed-Q multidimensional MFRM | Item | Item position + rater severity + item step, minus contributions of the fixed other abilities, all divided by the plotted dimension's loading |

These are the implemented families, not every possible PCM/GPCM specification.
In scalar GMFRM, the item-discrimination and rater-consistency product multiplies
the whole adjacent-category contrast. For given position/step values it changes
steepness, not the crossing. MGMFRM instead puts item loadings on abilities and
uses the literal 1.7 rater scale; fixed-Q MFRM retains its unit scale. These
conventions and centering constraints are recorded in `model_contract` and
`step_contract`. Compare models only after checking their
[category equations and identification](model-equations.md).

`usage_rows` retain every declared category overall, per item and per rater,
including unused categories. Counts use actual rating rows as the denominator;
they do not give equal weight to persons or correct an unbalanced allocation.
The `threshold_levels` field lists the step-owner groups that actually contributed
to each row. For example, a GMFRM item row can combine several raters' different
step systems. Rater differences in raw category use can reflect the abilities
and items allocated to them, so they do not alone diagnose centrality or bias.

Each row's `expected` summary describes the posterior distribution of its
**conditional expected category proportion**. Its SD and interval propagate
parameter uncertainty. They omit the additional variation from realizing a new
set of ratings. By contrast, the existing ordinary-MFRM
`category_functioning_summary` simulates replicated category proportions and
retains that predictive interpretation. The two intervals answer different
questions; observed-minus-expected is neither a p-value nor a calibrated
lack-of-fit test.

`threshold_rows` contain the centered transition parameters, excluding the dummy
reference-category zero, with posterior SD, pointwise equal-tailed intervals,
joint-draw step gaps and ordering probabilities. Posterior SD is not a
repeated-sampling SE. A reversed pair is a review prompt, not an automatic
category-collapse rule. Constant sampled ordering indicators do not establish
zero Monte Carlo error or certain ordering. Check `mcse`, `mcse_warning` and
`sampling_warning` alongside any summary.

For a two-dimensional fit, a conditional profile can be requested as follows.
Replace item/rater labels with their exact stored values. For a unidimensional
fit, omit `fixed_abilities`; for more dimensions, supply every other dimension.

```julia
categories = BayesianMGMFRM.category_report(fit_result;
    dataset_id="assessment-2026", observation_ids=rating_ids,
    interval=0.99,
    profiles=[(;id="item-1-rater-1", item="I1", rater="R1",
        dimension=1, ability_grid=range(-3, 3; length=41),
        fixed_abilities=Dict(2 => 0.0))])
categories.usage_rows
categories.threshold_rows
categories.curve_rows
categories.crossing_rows
```

`curve_rows` are plot-ready pointwise category probabilities. A profile is a
slice at the stated other abilities, not an average over them or a population
curve. A grid does not establish empirical support. To compare items or raters,
add separately named profiles; preserve their conditions in the figure caption,
outside the image. An item that does not load on the plotted dimension has a
flat curve and no unique crossing along that dimension.

`crossing_rows` calculate adjacent equal-probability ability values in each joint
posterior draw before summarizing. This preserves associations among positions,
steps and loadings; a ratio of posterior means would generally differ. With
three or more categories, equality of two adjacent probabilities need not mean
that either probability is 0.5. Centered steps, these conditional crossings and
expected-score half-points are distinct quantities.

`interval=0.99` applies a pointwise 99% equal-tailed interval to expected use,
steps, gaps, probabilities and crossings. This API does not calculate HDIs or
simultaneous bands. Results condition on the fitted model and its calibration
policy; fixed anchors omit external calibration uncertainty. All original draws,
chain layout, observation IDs, source identity and warnings are retained. Resource
limits fail explicitly rather than selecting a subset of draws. The optional `fit_report(...; reporting=(...))` integration retains these
definitions in a separate `category_report` section. Neither entry point establishes
category calibration, a new-rater guarantee or model validity.

#### Saved-draw category example

The same simulated B01–R1 assessment used above has 1,250 ratings, four declared
categories and 4,000 retained draws. The existing normalized MGMFRM fit gives:

| Category | Observed count | Observed proportion | Expected proportion, posterior mean | Pointwise 99% interval for expected proportion |
| --- | ---: | ---: | ---: | --- |
| 1 | 288 | 0.230400 | 0.231021 | [0.210600, 0.251277] |
| 2 | 327 | 0.261600 | 0.261749 | [0.234347, 0.289999] |
| 3 | 347 | 0.277600 | 0.275724 | [0.247963, 0.305068] |
| 4 | 288 | 0.230400 | 0.231506 | [0.207982, 0.255021] |

These are in-sample expectations, not an independent category-calibration check.
Similar observed and expected proportions do not establish good fit. The next
table illustrates why an item-centered step should not be labelled an ability
crossing. It selects I1 and R1, fixes the other dimension's ability at zero, then varies
the dimension on which I1 loads.

| Transition | Centered I1 step, posterior mean | I1/R1 ability crossing, posterior mean | Pointwise 99% crossing interval |
| --- | ---: | ---: | --- |
| 1 → 2 | -1.175840 | -5.827442 | [-9.383504, -3.608826] |
| 2 → 3 | 0.166463 | -3.273050 | [-5.337658, -2.007449] |
| 3 → 4 | 1.009378 | -1.676133 | [-3.141294, -0.709509] |

The downloadable report contains nine profiles: all five items with R1, plus
I1 with R2–R5. Each varies the relevant ability at −2, 0 and 2 and fixes the
other ability at zero. Crossings outside that display grid remain reported;
the grid does not truncate their intervals or imply observed support there.

The saved fit has no sampling warning in its stored diagnostic summary, and
there are no nonfinite numerical summaries. Nevertheless, `mcse_warning=true`:
all 4,000 sampled indicators for each of the ten step-order comparisons equal
one, so their mean MCSE is unavailable (`degenerate_draws`). This is not a claim
of zero error or certain ordering. Per-quantity MCSE remains in the download.
The original study denominator remains 192 planned/completed fits, 184 qualified.
Selection is the first planned R1 block at the middle prior width, not a favorable
category result; no fit or independent replication was added.
[Download the counts, steps, conditional curves, crossings and source provenance](assets/category-report/summary.json).

### Reading one integrated report

Use the [Saved-fit Reporting API](api-saved-reporting.md#One-report-with-explicit-analysis-choices)
to include category, reliability and agreement results in one `fit_report` bundle.
The integration retains each statistic's target and uncertainty definition:
expected category-use CrIs omit realization noise; a reliability estimate has
numerical MCSE but no reliability CrI or Strata; agreement separates observed
rates/optional observed-rate SE from conditional expected-rate posterior intervals.
A common report format does not make these uncertainty measures interchangeable.

Named reliability cohorts are evaluated separately. A failed cohort does not
erase successful ones; its failure makes report execution incomplete. Inspect
the named error rows in a partially failed report before correcting a request. A report
can also be execution-complete while containing MCMC warnings, unavailable MCSE,
zero-overlap pairs or unrequested analyses. Inspect both section status and
quantity-level warnings before interpreting results. JSON, tables and Markdown
retain the relevant identities and limitations, and saved-fit replay needs no
new estimation.

#### Download an integrated example

The same B01–R1 saved assessment above now has one public report bundle combining
nine category profiles, agreement on its shared simulated person–item responses,
and two reliability cohorts. Each cohort deliberately selects all 50 fitted
persons in one dimension with equal weights and `target=:centered`.

| Selected cohort | Posterior reliability | Numerical MCSE |
| --- | ---: | ---: |
| All 50 persons, dimension 1 | 0.794889 | 0.001053 |
| All 50 persons, dimension 2 | 0.920046 | 0.000510 |

These are finite-cohort functionals, not population/design reliability or Strata;
the MCSE measures numerical approximation error, not a posterior interval
or repeated-sampling SE. Category intervals in this example are
99% equal-tailed, whereas agreement intervals are 95%, matching the earlier saved
standalone examples. Both definitions remain visible in their own rows.

The report is execution-complete and reuses all 4,000 draws from 1,250 ratings.
Its category-order MCSE warning remains visible because all saved order indicators
are one; combining sections does not remove that warning. Category and agreement
results have exactly the same standalone-result hashes as the earlier examples.
No new fitting or independent simulation was performed; the originating study
still accounts for 192 completed fits, 184 qualified.

[Download the JSON, Markdown and table bundle](assets/integrated-report/report.zip)
and [its example summary and source provenance](assets/integrated-report/summary.json).
After extracting the archive, use
`load_fit_report_bundle("assessment-report"; require_complete=true)` to verify and
read it. Keep the fit cache separately if you need to recompute or change requests;
a report bundle is a result, not a saved sampler state.

### What should normally be reported?

Use the following as a question-based reporting framework. Not every exploratory
index is mandatory in every paper, and unavailable results should remain explicit.

| Reporting component | What the reader needs | Current candidate status |
| --- | --- | --- |
| Data and rating design | Persons/items/raters/responses; category counts; ratings per unit; missingness; assignment, linking and rank/identification concerns | Design validation, `rating_design_audit` and `rater_overlap` provide components. Common-response metadata are essential for repeated performances. |
| Model and scale | MFRM/GMFRM/MGMFRM, dimensions/Q, category-step ownership, constraints/anchors, priors, fixed versus estimated parameters | Specification, model metadata and reports exist; support differs by family. |
| Measures and uncertainty | Person ability, item position, rater severity, steps, and estimated loadings/consistency; units, SDs and interval mass/method | Posterior summaries and common saved-result adapters exist. Fixed values must not appear as empirical certainty. |
| Score interpretation | Raw averages versus adjusted expected scores; reference persons/items/raters and their weights | `fair_average_summary` supports ordinary MFRM on a balanced reference grid; this is not automatic population standardization. |
| Fit and unexpected ratings | Infit/outfit, observed–predicted residual patterns and support; rationale for any flag | `fit_stats` provides ordinary MFRM posterior summaries. `facets_compatibility_stats` supplies a separate approximate plug-in MnSq/ZSTD table, not FACETS JML identity. No universal cutoff or automatic deletion follows. |
| Category functioning | Use, steps, ordering uncertainty, probability curves and item/rater differences | `category_report` gives owner-aware steps, expected use and conditional curves across the common saved-fit types. Ordinary-MFRM `category_functioning_summary` retains replicated-use intervals. These targets differ; a disordered step alone does not justify merging categories. |
| Rater behavior and DFF | Overall severity, pairwise contrasts, substantive margins, cell counts, assignment and multiplicity limitations | Severity homogeneity and residual DFF screening exist for ordinary MFRM. Joint fitted DFF remains a gap. |
| Score agreement | Matched performance/criterion/occasion, exact/adjacent definition, full pair denominators, observed and model-expected rates, appropriate uncertainty | `rater_agreement` supports the common saved-fit types with explicit response IDs, joint-draw expectations and optional person-cluster observed SEs. It does not identify a dependence mechanism or provide a predictive interval. |
| Reliability and resolution | Named facet/dimension, intended population/design, uncertainty definition, individual precision; justified separation/Strata | Explicit finite-cohort `posterior_reliability` supports one dimension at a time across the common fit types. The historical separation screen warns. Population/design reliability and validated Strata remain unavailable. |
| Dependence and dimensionality | Response-level residual association, shared stimuli, repeated ratings, Q restrictions and estimated dimension correlations | Local-dependence and prediction tools exist within specific fit/metadata scopes; a residual correlation does not identify a causal mechanism. |
| Sensitivity and model comparison | Substantive prior alternatives, prior/posterior predictive checks, heldout unit and prediction target, unresolved comparisons | Saved sensitivity and comparison components exist. Predictive weights are not posterior model probabilities. |
| Computational quality and reproducibility | Chains/warmup/draws, convergence diagnostics, divergences, ESS and focal MCSE; software, seeds, saved records and exclusions | Diagnostics, MCSE, persistence and report components exist; numerical success is not measurement validity. |

The finite-cohort posterior functional now has an explicit implementation and
counterexample checks. Population/design reliability and conventional Strata
remain separate validation targets. Common-response agreement now has a scoped
implementation. Assignment-aware DFF and owner-aware category summaries now have bounded
implementations. Optional common report integration preserves explicit cohorts,
response identities and section failures;
fitted interactions and additional rater mechanisms require separate validation. Bayes factors remain a separate task
requiring validated marginal likelihoods. Existing predictive and recovery
studies continue to determine scientific support; these reporting improvements
do not replace them.


## Posterior classification and conditional ability precision

A practical question is: *Does this person's ability meet the standard, and
how uncertain is that judgment given these ratings?* This differs from asking
whether a method achieves an acceptable false-pass rate across repeated studies.
`BayesianMGMFRM.posterior_classification` addresses the first question using an
existing fit. It requires two distinct choices: the substantive ability cutoff
`c` and the probability rule `t` used to report a pass.

For person `i`, let `q_i = Pr(theta_i >= c | ratings, model, prior)`. The function
estimates `q_i` by the fraction of their saved ability draws at or above `c`.
It reports pass when `q_i >= t`, otherwise fail. Equality belongs to the
qualifying/passing side. This is an explicit reporting rule, not an automatically
recommended standard. Both `c` and `t` are required; the cutoff uses the exact
fitted coordinate system, including its identification constraints.
The [Stan guide's event-probability example](https://mc-stan.org/docs/stan-users-guide/posterior-prediction.html)
explains estimation by posterior indicator averages.

| Reported quantity | Interpretation |
| --- | --- |
| Ability mean, SD and equal-tailed interval | Conditional ability estimate and uncertainty, including calibration uncertainty represented in the saved joint draws. SD is not numerical MCSE or a repeated-sampling standard error. |
| Qualification probability | Posterior probability of ability at or above the specified cutoff. |
| Error probability for a displayed pass | `1 - q_i`, the posterior probability that this person is below the cutoff. |
| Error probability for a displayed fail | `q_i`, the posterior probability that this person is at or above the cutoff. |
| Expected false-pass / false-fail counts | Sums of the relevant individual error probabilities, each selected person counted once. |
| Probability of any error | Posterior probability that at least one displayed decision is wrong, retaining dependence among people. |

For example, if `q_i=0.92` and the required probability is `t=0.90`, the decision
is pass and its posterior error probability is `0.08`. With `t=0.95`, it is fail
and its error probability is `0.92`. The latter is possible because a strict pass
rule can prioritize avoiding false passes. The API does not infer those costs,
select the rule, or certify it as optimal. An indeterminate/review category is
not part of this binary interface.

Cohort risk must respect shared uncertainty. Consider two people with
qualification probabilities of `0.75`, both reported as pass. The expected error
count is `0.50` regardless of dependence. But if their below-cutoff events always
occur together, the probability of any error is `0.25`; if the events never occur
together, it is `0.50`. Multiplying marginal probabilities would produce a
misleading independence-based value. The implementation evaluates the decisions
against each complete joint draw and only then summarizes the cohort.

Inspect probability MCSE as well as the saved convergence diagnostics. A choice
near `t` can change with numerical noise. Constant sampled indicators retain
probabilities of zero or one but unavailable MCSE; they do not establish
certainty. A false-pass count is structurally zero if nobody was passed, and a
false-fail count is structurally zero if everybody was passed. Count/probability
MCSE conditions on the displayed decisions; it does not account for changing
those decisions in a different finite MCMC run. No automatic precision gate or
refit is applied. The [Stan reference manual](https://mc-stan.org/docs/reference-manual/analysis.html)
distinguishes posterior uncertainty from simulation error with dependent draws.

Select exact estimated person coordinates in one dimension. Another dimension
needs its own substantive scale and standard; separate marginal calls do not
define a combined, compensatory or conjunctive decision. Fixed anchors are not
uncertain people and are rejected. The API does not center the selected cohort,
link models, rank people, infer an ability-precision curve over unobserved levels,
or predict new ratings. Shared calibration uncertainty absent from the fit
cannot be restored by this report.

Finally, these posterior risks condition on the fitted model, prior and observed
data. They are not observed mistakes against known truth, population sensitivity
or specificity, repeated-study coverage, or future-design error rates. Those
claims need suitable validation data or a simulation with known truth and an
explicit target population. The current unfavorable loading-recovery finding
is not repaired by adding this reporting API; the model's scientific acceptance
remains separate.


## Posterior ranks within an explicit cohort

A rank answers a relative question: *Among these people, who is likely to have
higher ability on this dimension?* It does not answer whether someone meets an
absolute standard or whether two abilities differ enough to matter in practice.
Use the classification report for a justified absolute cutoff and inspect
ability differences when substantive magnitude matters.

`BayesianMGMFRM.posterior_ranking` requires exact person coordinates and an
explicit `direction`. With `:higher`, the largest ability is rank 1; with
`:lower`, the smallest is rank 1. Only the selected people compete for these
positions. Adding or removing a person changes the estimand; the result is not a
population percentile. A multidimensional fit can be inspected one dimension at
a time, but the API does not supply an overall multidimensional ranking.

The function ranks each complete posterior draw and summarizes the resulting
ranks. This preserves shared calibration uncertainty represented in the fit and
posterior dependence between people. Sorting each person's marginal samples
separately would destroy that dependence. It also differs from ranking posterior
means. For example, across four equally weighted joint draws, let A have abilities
`[1000, 0, 0, 0]`, B `[1, 1, 1, 1]`, and C `[2, 2, 2, 2]`. A has the largest mean
ability but is first in only one draw and last in three, giving expected rank
`2.5`. The expected ranks of B and C are `2.25` and `1.25`. This deliberately
extreme finite example shows the distinction, not a fitted model recommendation.
Posterior functions and event indicators can be averaged over draws as described
in the [Stan guide](https://mc-stan.org/docs/stan-users-guide/posterior-prediction.html).

| Output | What it means |
| --- | --- |
| Mean rank and rank SD | Expected relative position and its conditional posterior spread, using the declared tie policy. An expected rank need not be an integer. |
| Rank median and pointwise interval | Quantiles of that person's sampled midrank distribution. Empirical inverse-CDF endpoints remain on observed rank support; no interpolation invents unsupported fractional positions. |
| Mean-rank MCSE | Numerical uncertainty in the estimated expected rank, accounting for chain autocorrelation. It is not the rank SD. |
| Top-k lower / upper probabilities | Bounds on inclusion under unspecified tie-breaking at the kth position. These coincide if no sampled tie crosses that boundary. |
| Tie probability | Fraction of draws in which this person shares an ability value with someone in the cohort; the numerical equality test is exact. |

For a tied group occupying positions `a` through `b`, every member receives
midrank `(a+b)/2`. Suppose A and B tie for first while C is third, and only one
place is available. A and B each have midrank `1.5`, but their top-one inclusion
probabilities depend on the tie-breaking rule. The lower bound for each is zero
and the upper is one. The report does not silently grant each probability `0.5`
or choose by input order. If two places are available, both are included.
The API counts inclusion as certain in a draw when the tied group's last
position is at most k, and possible when its first position is at most k.
The difference between the two posterior probabilities is the probability of a
boundary-crossing tie. This range is **not a credible interval**. Near-equal
floating-point values are ordered numerically; exact ties do not implement a
practical-equivalence margin. No selection action is performed.

Marginal rank intervals need not form one consistent ordering, can overlap, and
are not simultaneous uncertainty bounds for the whole cohort. With discrete
ranks, their empirical probability mass may exceed the requested level. The
mean rank need not lie inside its equal-tailed interval. Rank-interval/quantile
MCSE is not computed; its absence is explicitly recorded. Short or constant
sampled ranks/events also have unavailable mean MCSE rather than established
certainty. Requesting `top_k` equal to cohort size is instead the structural event
that everybody is included. Read diagnostics and event MCSE before interpreting
small differences between reported probabilities.

These results are conditional on the fitted model, prior and data, for the
specified observed cohort. They do not establish known-truth ranking accuracy,
future-performance rankings or selection performance under a new design.
Ranks can be unstable even when ability differences are negligible; conversely,
a stable ordering does not establish a practically important gap. Model and prior
sensitivity, scientific acceptance, and substantive decision criteria remain
separate from successful rank reporting. No new MCMC is required to change the
reported cohort, direction, interval level or top-k query.
