# Frequentist 1D JMLE and MMLE

When you want fast point calibration, classical FACETS/ConQuest/mfrmr/mfrmpy
tables, or a direct frequentist baseline alongside a Bayesian posterior on the
exact same rating specification, pass `method = :jmle` or `method = :mmle` to
`fit`.

Non-Bayesian estimation is intentionally scoped to **one-dimensional unit-slope
Rating Scale (`RSM`) and Partial Credit (`PCM`) models** across both standard
three-facet `BayesianMGMFRM.Legacy.FacetSpec` (`person`, `rater`, `item`) and general user-named
multi-facet `mfrm_spec` designs. Multidimensional, free-slope (`GPCM`),
predictor-regression, and random-interaction models remain Bayesian routes.

## Quick start: 3-facet and general multi-facet specifications

For a three-facet table (`person`, `rater`, `item`), reuse `FacetData` and
`mfrm_spec` directly:

```julia
using BayesianMGMFRM
using BayesianMGMFRM.GlassBox
using BayesianMGMFRM.Legacy

data = FacetData(ratings; person=:person, rater=:rater, item=:item,
    score=:score, category_levels=0:4)
spec = mfrm_spec(data; thresholds=:rating_scale) # or :partial_credit

fit_jmle = fit(spec; method=:jmle)
fit_mmle = fit(spec; method=:mmle, quad_points=31, population_sd=1.0)
```

For a general $F$-facet table (for example `Person × Rater × Task × Criterion`),
pass `prior = :none` to `mfrm_spec` when only frequentist estimation is needed,
or supply `prior_sd` when you want to run both frequentist and Bayesian fits on
the identical specification object:

```julia
spec_4f = mfrm_spec(writing;
    person=:Person,
    facets=(Rater=:Rater, Task=:Task, Criterion=:Criterion),
    score=:Score,
    steps=:global,          # or steps=:Criterion for PCM
    category_levels=0:5,
    prior=:none,
)

jml_rsm = fit(spec_4f; method=:jmle)
mml_rsm = fit(spec_4f; method=:mmle, quad_points=31, population_sd=1.0)
```

## Transfer recording locations and category steps to a second panel

To estimate a second panel's mean on an earlier calibration scale, match each
recording by ID and each adjacent-category step by its **upper score label**.
Positive recording and step values lower the probability of a higher score.
The following three-category example treats the input values as known.

```julia
wave2 = (listener=repeat(1:3, inner=2), recording=repeat(["a","b"], 3),
         rating=[1,2,2,2,3,2])
calibration = (facets=(recording=Dict("a"=>0.4, "b"=>1.1),),
               steps=(owner=:global, values=Dict(:global=>Dict(2=>-0.3, 3=>0.3))))
setup = (person=:listener, facets=(recording=:recording,), score=:rating,
         category_levels=1:3, steps=:global, fixed_calibration=calibration)
spec = mfrm_spec(wave2; setup..., prior=:none)
result = fit(spec; method=:mmle, estimate_mean=true, population_sd=1.0)
s = design_summary(result)
(s.population_mean, s.population_mean_se, s.fixed_calibration.uncertainty)
```

A positive mean places the second panel above the original zero-mean panel on
the declared unit-logit scale. Here the conditional standard error treats both
the recording locations and the common steps as fixed. Changing the reference
SD or transferring estimates with sampling uncertainty changes the question.
The alternating pattern of recordings in this example is incidental. Input
row and dictionary order can change without changing the identified anchors.

Use `steps=(owner=:recording, values=Dict("a"=>Dict(2=>-0.3, 3=>0.3)))`
inside the calibration to fix recording-specific PCM steps when the specification
uses `steps=:recording`. Each owner's steps sum to zero across its declared
categories. When all but one are fixed, the last one is determined by that
constraint. An anchored facet keeps absolute locations; any remaining free
levels on it use individual location coordinates. Other unanchored ordinary
facets retain their sum-zero coding. For an existing scalar `BayesianMGMFRM.Legacy.FacetSpec`, use
`mfrm_spec(existing_spec; fixed_calibration=calibration, prior=:none)` with its own facet
names, such as `:item` and `:rater`.

For a Bayesian population-mean contrast, use the same setup and supply an
intercept prior on the linked scale. For unit-normal listener deviations and
a Normal(0,1) prior on the shared panel mean, use

```julia
using Distributions: Normal
bayes = mfrm_spec(wave2; setup..., prior_sd=(person=1.0, facets=(recording=0.0,), step=0.0),
                  intercept=Normal(0,1))
draws = fit(bayes; method=:nuts, chains=4, warmup=400, ndraws=800, seed=4361)
posterior_summary(draws; parameters=["population_mean"])
```

The zero SDs identify fully fixed structural blocks. For a partially anchored
facet the declared SD applies to independent free absolute locations. A
partially fixed centered step block of length H retains the original
H/(H−1) variance multiplier on orthonormal contrasts of the remaining steps.
Numerical intervals from either route condition on the supplied values.
A shared shift of the anchors would also shift the recovered panel mean.

### Link panels through a subset mean

Suppose recordings `"a"` and `"b"` have preliminary locations 0.4 and 1.1
logits. If their **equal-weight mean** of 0.75 is a defensible reference,
allow their individual locations to change in the receiving panel.

```julia
subset = (groups=[(block=:recording, levels=["a","b"], mean=0.75)],
          steps=calibration.steps)
linked = mfrm_spec(wave2; setup..., fixed_calibration=subset, prior=:none)
group_fit = fit(linked; method=:mmle, estimate_mean=true, population_sd=1.0)
group_result = design_summary(group_fit)
(group_result.population_mean, group_result.population_mean_se,
 group_result.fixed_calibration.dimensions, facet_summary(group_fit))
```

The two estimated locations must average 0.75. Each member has a standard
error, and their covariance makes the variance of their fixed mean zero.
Use the observed-information `se` for original-scale locations. The separate
diagonal `conditional_se` depends on the free-coordinate coding. The panel SE
conditions on the declared mean and fixed steps. If every reference recording
has moved by the same amount, these data cannot distinguish that shift from
a panel location difference. With different recordings in the reference,
compare the resulting panel estimates on their explicitly declared scales.

Use `sum=1.5` for the equivalent total in this example. Groups can overlap
on a facet, and fixed individual locations can be supplied alongside groups.
Consistent redundant equations count once toward the rank. The design
summary gives the independent constraint count and remaining facet degrees
of freedom. Each level has equal weight regardless of its observation count.

For a Bayesian fit set `prior_sd=(person=1., facets=(recording=1.,), step=0.)`
and `intercept=Normal(0,1)` on the same specification. On a grouped facet
the prior is an isotropic Gaussian restricted to the declared equations.
Its center is the feasible vector with smallest Euclidean norm. The facet SD
scales a unit-length contrast in the free subspace. For this pair the SD of
the difference between locations is √2 times the specified SD. Unconstrained
recordings have prior mean zero. A LogNormal hyperprior places uncertainty on
the contrast SD. Compare plausible prior scales, especially for sparsely rated
recordings.

### Carry preliminary calibration uncertainty into the panel comparison

Suppose the recording and step estimates above came from an independent sample.
Supply their covariance in the order of the **source** coordinates. The receiving
model matches recording IDs and the upper scores of adjacent steps. A
three-category rating scale has two centered steps and one free step.

```julia
coordinates1 = [(block=:recording, level="b", estimate=1.1),
                (block=:steps, owner=:global, level=:global, upper_category=2, estimate=-0.3),
                (block=:recording, level="a", estimate=0.4)]
transfer = (coordinates=coordinates1, covariance=[0.12 -0.01 0.03; -0.01 0.05 0.02; 0.03 0.02 0.08])
linked = (person=:listener, facets=(recording=:recording,), score=:rating,
          category_levels=1:3, calibration=transfer)
res = fit(mfrm_spec(wave2; linked..., prior=:none); method=:mmle, estimate_mean=true, population_sd=1.0)
summary2 = design_summary(res)
(summary2.population_mean, summary2.calibration.conditional_se, summary2.population_mean_se)
```

The last value includes preliminary sampling uncertainty by the delta method.
The panel mean itself is the ordinary plug-in estimate. Other reported MMLE
SEs condition on the preliminary estimates. When the receiving information is
unqualified, the propagated SE is missing. Both panels must use the same scale,
rating direction, step convention and invariant linking parameters. A common
displacement of the anchors is confounded with the panel difference.

For a qualified preliminary MRCML MMLE fit, `anchor_linking_summary(first_fit;
coordinates=mapping)` extracts the joint estimates and covariance directly.
Each mapping row supplies `parameter` (the exact name in the preliminary
fit), the receiving `block` and `level`, and, for a step, `owner` and
`upper_category`. For example, a source parameter named `"Cat1"` may map to
`(parameter="Cat1", block=:steps, owner=:global, level=:global, upper_category=2)`.
Select independent coordinates. Within each step owner, omit at least one
transition so the centered constraint can determine the remaining step mean.
Preserve the source scale or transform its means and covariance together.

For Bayesian transfer, supply a Gaussian approximation to the **preliminary
posterior**, then use only the receiving observations. For the small example,
`mfrm_spec(wave2; linked..., prior_sd=(person=1.0, facets=(recording=0.0,), step=0.0),
intercept=Normal(0,1))` uses the external covariance for the transferred
coordinates and a separate prior on the receiving panel mean. The zero SDs
indicate that these blocks have no additional free contrasts. The named
`population_mean` is the panel contrast, and the person coordinates are
deviations about that mean. Receiving data can update the transferred
coordinates under the joint model. An MLE and its inverse information alone
approximate a likelihood. Incorporate the intended calibration prior once
when comparing with a concurrent Bayesian analysis. This Gaussian approximation
can give a different answer from fitting the original two likelihoods jointly.

### Compare an individual to a common cutoff

For the Bayesian receiving-panel fit `draws` above, choose the location to
which the cutoff applies. Here zero represents the reference panel's population
mean. The chosen 0.95 probability is an illustrative decision rule.

```julia
linked_people = classification(draws; location=:linked, cutoff=0.0,
                               pass_probability=0.95, interval=0.95)
[(r.parameter, r.lower, r.upper, r.qualifying_probability,
  r.qualifying_mcse.value) for r in linked_people.rows]
```

Each interval and probability uses the person's deviation plus the receiving
panel mean in the same draw. The default `location=:parameter` uses the
deviation alone and answers a question about the receiving population's mean.
For a within-panel ordering, `ranking(draws; direction=:higher, top_k=2)`
gives the same ranks on either scale because the shift is shared. Different
recording calibrations can change individual contrasts. A fixed calibration
conditions on the supplied values. An uncertain calibration propagates its
joint posterior variation. A sampled probability of zero or one with missing
MCSE calls for reporting the event count. Interpret the direction from the
rating scale and the role of the person in the design.

### Fix one rater-by-task interaction cell

Suppose an external calibration puts judge A's additional severity on task 1
at 0.6 logits after accounting for judge and task main effects. To use this
value, declare the interaction and identify the cell by both facet names and
their original level IDs. The example has three judges and three tasks.

```julia
using BayesianMGMFRM.Legacy: fit_report
crossed = (person=repeat(1:12, inner=9),
           judge=repeat(repeat(["A","B","C"], inner=3), 12),
           task=repeat(1:3, 36),
           rating=[mod(p + j, 3) for p in 1:12 for j in 1:9])
cell_anchor = (levels=(judge="A", task=1), value=0.6)
cell_spec = mfrm_spec(crossed; person=:person, score=:rating,
    facets=(judge=:judge, task=:task), steps=:global, category_levels=0:2,
    interactions=((:judge,:task),), fixed_calibration=(cells=[cell_anchor],),
    prior=:none)
cell_fit = fit(cell_spec; method=:mmle, population_sd=1.0)
effects = filter(r -> startswith(r.parameter, "interaction["),
                 fit_report(cell_fit).facet_measures)
[(r.parameter, r.estimate, r.se, r.fixed) for r in effects]
```

Positive additional severity lowers each adjacent-category logit by 0.6 at
that cell. The interaction sums to zero across each row and column. The two
remaining entries in judge A's row therefore sum to −0.6, as do the two
remaining entries in task 1's column. Both entries in either pair can still
vary. One independent anchor reduces the four free interaction contrasts to
three. See `design_summary(cell_fit).fixed_calibration.interaction_dimensions`
for the rank and remaining degrees of freedom. Standard errors condition on
the supplied value. Cells determined by the margins also appear as fixed.
Several distinct cells can be supplied, provided their values agree with the
margins. A zero-sum interaction alone supplies no origin for a panel mean.

For a Bayesian fit, supply an interaction SD in
`prior_sd.interactions`, e.g. `(judge_task=0.9,)`, alongside the usual person,
facet and step priors. It defines the cell SD on the original doubly centered
grid. At a given scale the Gaussian prior on the remaining contrasts is the
one obtained by conditioning on the declared cell values. Its center shifts
and its remaining cell variances can differ. A LogNormal prior applies to the
scale of this restricted model; fixed values do not supply a likelihood for
that scale. Set the interaction SD to zero when the constraints determine all
cells. The same cell syntax works with `method=:jmle` and with scalar
`mfrm_spec(existing_facet_spec; interactions=..., fixed_calibration=..., prior=:none)`.
Cell declarations currently target facet-by-facet residuals.

### Read a two-wave linking report

Use the observed rows from the first wave and the fitted receiving model. The
first table must contain only the scored observations used in the preliminary
analysis. Set `person` and `level` to its column names and `block` to the
receiving facet role. Match the origin, unit and score direction of the preliminary
locations to the fitted scale. An ID match alone cannot verify this. The example
uses the two-recording group fit above.

```julia
wave1 = (listener=["P1","P1","P2","P2"], recording=["a","b","a","b"])
source_locations = Dict("a"=>0.4, "b"=>1.1)
link = anchor_linking_summary(wave1, group_fit; block=:recording,
                              person=:listener, reference=source_locations)
(link.connectivity.shared_levels, link.connectivity.combined_components,
 only(link.groups).member_free_df, link.panel)
[(r.level, r.preliminary_n, r.receiving_n, r.role, r.displacement)
 for r in link.common_parameters]
```

Here both recordings connect the waves. Their fixed mean leaves one free
contrast. Each row gives the receiving location and, where estimable, the
receiving minus preliminary change. In this difficulty coding, a positive
recording change lowers the expected score at the same listener location.
The tables retain first-only and receiving-only levels in `connectivity.rows`.
Components describe the person-by-facet observation graph. Equal person IDs
in different waves remain separate. Shared IDs alone cannot establish
invariance or the identification of a larger model.

Read the displacement interval with its reference. For a free level or a
member of a fixed-mean group it conditions on the supplied preliminary point
and uses the receiving fit's observed-information SE or posterior quantiles.
The Bayesian rows also give mean and endpoint Monte Carlo errors. An omitted
preliminary value leaves the change missing. A fixed location supplies no
separately estimable change. A Gaussian calibration updates a common location
in the Bayesian fit; this update alone cannot identify a between-wave change.
Inspect `qualified`, `warnings`, and `panel_conditional_se` when comparing
models. JMLE has no estimated population mean. A common shift of the reference
set is inseparable from a panel change without an independent reference.

The report identifies the fitted step owner. For each owner level, `centered_step_df` gives the degrees of freedom after
centering; `conditional_free_df` gives the number remaining with the
transferred coordinates held fixed. `transferred_df` counts the independent
external coordinates. The same report can be saved and reopened with its
checksum using `receipt=save_report(path, link; return_receipt=true)` and
`load_report(path; expected_sha256=receipt.sha256)`.

## Alignment with FACETS, ConQuest, `mfrmr`, and `mfrmpy`

All conventions are explicit so results match across packages when the same
estimator and constraints are selected:

1. **Additive logit orientation:** By default, person ability enters with `+1`
   and every non-person facet enters with `-1` (difficulty / severity):
   ```math
   \log\frac{P(Y_n = k)}{P(Y_n = k - 1)} = \theta_{p(n)} - \sum_{f=1}^{F} \beta_{f, j_f(n)} - \tau_{g(n), k}.
   ```
   Pass `positive_facets = [:Rater]` if a facet uses easiness/leniency orientation.
2. **Identification gauge (`centering` and `noncenter_facet`):**
   - `centering = :sum_to_zero` (default) constrains free levels of each centered
     facet to sum to zero ($\sum_\ell \beta_{f, \ell} = 0$) and step thresholds
     within each step owner to sum to zero ($\sum_s \tau_{g, s} = 0$), matching
     `mfrmr`, `mfrmpy`, `FACETS`, and `ConQuest` (`lconstraints=items`).
   - `centering = :reference_first` fixes the first level of each centered facet
     to zero, matching the default gauge of `BayesianMGMFRM`'s `BayesianMGMFRM.Legacy.FacetDesign`.
   - In `JMLE`, `noncenter_facet = :person` (default) leaves interior person
     abilities unconstrained while centering non-person facets. Individual hard
     anchors (`anchors = (rater = Dict("R1" => 0.0), ...)`) fix the anchored
     levels directly.
3. **MMLE population distribution (`population_sd`, `estimate_sd`, `estimate_mean`):**
   - `estimate_sd = false, estimate_mean = false` (default, `population_sd = 1.0`):
     integrates $\theta_p \sim \mathcal{N}(0, \sigma_0^2)$ over Golub–Welsch
     Gauss–Hermite quadrature (`quadrature = :gauss_hermite`, `quad_points = 31`
     default, or `quadrature = :rectangular`), matching fixed-SD MML in `mfrmr`
     and `mfrmpy`.
   - `estimate_sd = true, estimate_mean = false`: estimates $\theta_p \sim \mathcal{N}(0, \sigma^2)$
     jointly with sum-to-zero non-person facets, matching `ConQuest`
     `set lconstraints=items; estimate ! method=gauss`.
   - `estimate_sd = true, estimate_mean = true`: estimates both mean and SD
     $\theta_p \sim \mathcal{N}(\mu, \sigma^2)$ with sum-to-zero non-person facets,
     matching `mfrmr` `population_formula = ~ 1`.
4. **Extreme-score persons in JMLE (`extreme_adjustment`):**
   - `extreme_adjustment = 0.0` (default): exact unadjusted JMLE. Persons with
     all-minimum or all-maximum scores have no finite unpenalized MLE ($\mp\infty$),
     contribute zero gradient at the limit, and are reported with `finite_mle = false`
     and `estimate = missing` alongside finite Warm `WLE` scores (`wle`, `wle_se`).
   - `extreme_adjustment = 0.3`: applies the FACETS `EXTRIM = 0.3` score adjustment
     to extreme person totals.

## Standard errors, person scores, and fit statistics

Frequentist uncertainty quantities are **not** Bayesian posterior credible
intervals or MCMC Monte Carlo standard errors. Reports keep three uncertainty
quantities distinct:

- **`se` (`:constrained_observed_information`):** Exact delta-method standard
  error from the inverse observed Fisher information on the identified free
  coordinates (`J * inv(H_free) * J'`), computed via exact block Schur
  complement in unadjusted `JMLE` and exact marginal-log-likelihood Hessian in `MMLE`.
- **`conditional_se` (`ModelSE` in `JMLE`):** FACETS-style diagonal conditional approximation
  `1 / sqrt(sum(w_r * Var(Y_r | eta_hat_r)))`, holding all other parameters fixed.
- **`model_se` & `real_se` (`RealSE`):** `model_se` equals `se` in `MMLE` and
  `conditional_se` in `JMLE` (matching `mfrmr` and `mfrmpy`), with misfit-inflated
  `real_se = model_se * sqrt(max(1.0, infit))`.

Person scores (`facet_summary(fit; facet = :person)` or `fit_report(fit).person_scores`)
provide:
- In `MMLE`: `eap`, `eap_sd` (quadrature posterior SD conditional on point
  calibration; calibration uncertainty is not propagated), `eap_q05`/`eap_q50`/`eap_q95`,
  Warm's bias-reduced `wle` and `wle_se`, and fixed-calibration `mle` / `mle_se`.
- In `JMLE`: joint `estimate`, joint Hessian `se`, `conditional_se`, and fixed-calibration
  `wle` / `wle_se`.

Fit diagnostics (`fit_stats(fit)`, `facets_report(fit)`) report `Infit` and `Outfit`
mean squares together with Wright & Masters (1982, Eq. 4.27) FACETS degrees of
freedom and Wilson–Hilferty cube-root `ZSTD` (`WHEXACT = Yes` by default via
`whexact = true`, evaluated for all `df > 0` with optional `zstd_cap = 9.0`),
alongside homogeneous-variance `infit_zstd_engine` and `outfit_zstd_engine`
columns and both composite (`ptmea`) and person-only (`ptmea_person`)
point-measure correlations.

## Inspecting, comparing, saving, and plotting

```julia
using BayesianMGMFRM.Legacy: fit_report
qualify(mml_rsm)                        # gradient, positive-definite Hessian & boundary check
rep = fit_report(mml_rsm)               # portable summary, facet/step/person tables, reliability
contrast(mml_rsm; facet=:Rater, left="R1", right="R4")

# Compare RSM vs. PCM under MMLE (AIC / BIC / likelihood-ratio summary):
spec_pcm = mfrm_spec(writing; person=:Person,
    facets=(Rater=:Rater, Task=:Task, Criterion=:Criterion),
    score=:Score, steps=:Criterion, category_levels=0:5, prior=:none)
mml_pcm = fit(spec_pcm; method=:mmle, quad_points=31)
cmp = compare_models("RSM" => mml_rsm, "PCM" => mml_pcm; criterion=:aic)

save_fit("mml-rsm.jls", mml_rsm)
save_report("mml-rsm.json", rep)

using CairoMakie
BayesianMGMFRM.plot(mml_rsm; kind=:posterior)  # point estimates + 95% asymptotic Wald CIs
BayesianMGMFRM.plot(mml_rsm; kind=:wright)     # multi-facet Wright map
BayesianMGMFRM.plot(mml_rsm; kind=:pathway)    # Infit MNSQ vs. logit Pathway map
BayesianMGMFRM.plot(cmp; kind=:comparison)     # MMLE ΔAIC / ΔBIC comparison
```

Bayesian-only MCMC operations (`posterior_summary`, `posterior_mcse`, `waic`,
`psis_loo`, `prior_sensitivity`) and `JMLE` `AIC`/`BIC` comparisons (invalid under
Neyman–Scott incidental person parameters) are deterministically refused with
guidance to the appropriate frequentist or Bayesian verb.


## Can the two groups be compared on this rating scale?

For a scalar MRCML specification, give each modeled person one row in a roster.
Choose a reference group and, if needed, numeric covariates. The reference
population mean is zero at covariate zero. The fixed category scoring
coefficients set the unit. The group coefficient compares means at the same
values of all covariates.

```julia
ratings = (id=[1,1,2,2,3,3,4,4], item=repeat(["A","B"],4),
           score=[1,0,0,1,1,1,0,0])
spec = mfrm_spec(ratings; person=:id, score=:score, facets=(item=:item,),
    steps=:global, category_levels=0:1,
    fixed_calibration=(facets=(item=Dict("A"=>0.0),),), prior=:none)
roster = (id=[1,2,3,4], study=["first","first","second","second"],
          practice=[0.0,1.0,0.0,1.0])
check = BayesianMGMFRM.MRCML.population_design(spec, roster;
    person=:id, group=:study, reference="first", covariates=(:practice,))
check.mean_terms  # both the second-group contrast and practice slope are estimable
```

If every person in the second group is rated by a panel with its own free
severity shift, increasing the second-group mean and that shift equally leaves
every rating probability unchanged. The affected mean gets
`identifiable=false`. Adding a duplicate group indicator as a covariate
also flags both affected coefficients. A full rank establishes separation of
the declared location terms in the observed design. Group SD precision,
measurement invariance and the adequacy of a shared anchor require other evidence.

### Estimate the adjusted group difference and group SDs

For your own four-category ratings, supply a long table `ratings` with
`id`, `item` and `score`, and a `roster` with `id`, `study` and `practice`.
In this example both groups see item `I1`, fixed at −0.8 logits. The study
labels include `"first"`. Estimating a separate person SD in each group
requires replication beyond the four-person design illustration above.

```julia
population = (roster=roster, person=:id, group=:study, reference="first",
              covariates=(:practice,))
measurement = (person=:id, score=:score, facets=(item=:item,), steps=:global,
               category_levels=0:3, fixed_calibration=(facets=(item=Dict("I1"=>-0.8),),))
grouped = mfrm_spec(ratings; measurement..., population, prior=:none)
m = fit(grouped; method=:mmle, quad_points=81)
qualify(m)
design_summary(m).population.coefficients  # adjusted mean contrast and common slope, with SEs
design_summary(m).population.groups        # SD and delta-method SE for each named group
```

With the same item and step constraints in both groups, a positive contrast
means higher expected ability at equal practice. Check covariate overlap before
interpreting that comparison. Each person contributes one marginal likelihood
across all of their ratings. Standard errors include joint estimation of the
free measurement and population coefficients. The SEs above condition on the specified value of item `I1`.

If the anchors came from an independent sample, transfer their estimates and
joint covariance on the same logit scale. For example, suppose a preliminary
MMLE fit `first_fit` names the item difficulties `"I1"` and `"I3"` and the
first centered step `"step-1"`. Use the actual parameter names from your
preliminary fit. Here the receiving data use the same four categories.

```julia
mapping = [(parameter="I1", block=:item, level="I1"),
           (parameter="I3", block=:item, level="I3"),
           (parameter="step-1", block=:steps, owner=:global, level=:global, upper_category=1)]
transfer = anchor_linking_summary(first_fit; coordinates=mapping)
linked_groups = mfrm_spec(ratings; person=:id, score=:score, facets=(item=:item,),
    steps=:global, category_levels=0:3, population, calibration=transfer, prior=:none)
m_linked = fit(linked_groups; method=:mmle, quad_points=81)
design_summary(m_linked).calibration.contrasts
item_values = Dict(c.level => c.estimate for c in transfer.coordinates if c.block == :item)
link = anchor_linking_summary(preliminary_ratings, m_linked;
    block=:item, person=:id, reference=item_values, interval=0.95)
link.panel.contrasts
```

For each group versus the named reference, `conditional` gives the Wald
interval with anchors fixed. `summary` gives the interval after adding the
first-order contribution of their joint sampling covariance. The point estimate
is identical. Read the contrast at the same covariate values in both groups.
The calculation allows all free receiving coefficients and group SDs to vary
with the anchors. SEs reported for covariate slopes and group SDs, and plug-in
plausible values, still condition on the supplied calibration. If the receiving
information fails qualification, the propagated SE is missing. Independence
requires disjoint sampling units across the calibration and receiving stages.
The intervals assume stable linking parameters. A systematic change in the
meaning or severity of an anchor requires a separate analysis.

For a Bayesian analysis, declare independent Normal priors for the mean
coefficients and LogNormal priors for the group SDs. Pass the resulting target
to the ordinary sampler. The numerical settings below illustrate invocation.
Use the diagnostics and Monte Carlo errors to judge the retained draws.

```julia
using BayesianMGMFRM.GlassBox: parameter_names
using Distributions: Normal, LogNormal
target = mfrm_spec(ratings; measurement...,
    prior_sd=(facets=(item=1.,),step=0.75),
    population=merge(population,(coefficient_prior=Normal(0,1.1),sd_prior=LogNormal(0,0.5))))
b = fit(target; method=:nuts, chains=4, warmup=500, ndraws=1000, seed=21721)
qualify(b)
terms = filter(n -> startswith(n,"population"), parameter_names(target;scale=:model))
posterior_summary(b;parameters=terms)
posterior_mcse(b;parameters=terms)
save_fit("grouped.jls", b)
b_saved = load_fit("grouped.jls")
```

The group means and SDs describe a single latent dimension. The native fit
retains the roster and joint draws. For an independent Stan comparison use the
target-specific pair `BayesianMGMFRM.MRCML.stan_code(target)` and `stan_data(target)`.

The Bayesian sampler uses a standardized ability for every person by default
(`person_coordinates=:noncentered`). To sample physical abilities for everyone,
add `person_coordinates=:centered` to the population declaration. To choose
individually, supply a dictionary keyed by every original person ID, with either
symbol as its value. For example, an existing dictionary `by_id` can be passed
as `population=merge(population, priors, (person_coordinates=by_id,))`, where
`priors` holds the two population priors above.

To use observed design information, specify `person_coordinates=(information_cutoff=8.0,)`.
The sampler centers a person when the sum of the within-rating variances of the
category scoring weights, multiplied by the squared prior median group SD, reaches
the chosen cutoff. The calculation uses physical ability zero and the measurement
parameters at their zero raw prior coordinates. It uses the assigned ratings and
their category supports, independently of the scores received. Inspect
`design_summary(target).population.person_chart` in `.population.people` order.
Eight is an optional setting studied on specific rating designs. Estimated
calibration, group SDs and category use can change sampling efficiency. Check the
whole fit and the Monte Carlo error for the group or person estimate of interest.
The fit saves the assignment. Reopen it with a version supporting grouped person
coordinates. Use model-scale summaries or joint plausible values to report abilities.

### Use plausible values for a population comparison

To compare two groups at the same practice level, start from the grouped fits above.
The MMLE route samples a person's ability given their own ratings, group and
covariates on the fitted quadrature grid. The measurement coefficients, regression
coefficients and group SDs have one fitted value each. The Bayesian route
carries all of these quantities and the persons together in each retained draw.

```julia
H = BayesianMGMFRM.PortableHandoff
plugin = plausible_values(m; n_imputations=100, seed=7321)
joint = plausible_values(b_saved)
contrast(plugin; group="second", reference="first")
contrast(joint; group="second", reference="first")
first(H.pv_rows(joint))  # imputation, chain, iteration, person, group, theta
receipt = save_report("group-pvs.json", joint; return_receipt=true)
restored = load_report("group-pvs.json"; expected_sha256=receipt.sha256)
contrast(restored; group="second", reference="first")
```

Use the actual group labels from your roster. For MMLE, each imputation supplies
one complete-data group contrast from an unweighted regression with separate
group intercepts and common covariate slopes. The within-imputation variance
uses the independent-person HC2 sandwich. The result gives the mean contrast,
mean within-imputation variance, between-imputation variance, their Rubin
total and a large-complete-sample interval. Increase the number of imputations
if the reported imputation Monte Carlo error matters at your reporting precision.
This interval conditions on the fitted calibration and population parameters.
Its repeated-sample coverage depends on the design and imputation model.

The joint result uses the mean and equal-tailed credible interval of the
population coefficient difference at shared covariate values. Check
`qualify(b_saved)` and the source diagnostics before interpreting it. Group SDs
are available in the fit summary above. In the bundle, `record.parameter_names`
identifies the model-scale columns, including group SDs. Their values are in
`record.calibration` for plug-in PVs and in each `record.draws[i].parameters`
for joint PVs. Tidy person rows identify each imputation and retain original
person/group labels. Store the SHA-256 receipt separately for verification.

The [linked group example](equating-and-populations.md) explains the adjusted mean and the distinction between joint and plug-in plausible values. For explicit TAM arrays see [category design matrices](design-matrix-mrcml.md).
