# Frequentist 1D JMLE and MMLE

When you want fast point calibration, classical FACETS/ConQuest/mfrmr/mfrmpy
tables, or a direct frequentist baseline alongside a Bayesian posterior on the
exact same rating specification, pass `method = :jmle` or `method = :mmle` to
`fit`.

Non-Bayesian estimation is intentionally scoped to **one-dimensional unit-slope
Rating Scale (`RSM`) and Partial Credit (`PCM`) models** across both standard
three-facet `FacetSpec` (`person`, `rater`, `item`) and general user-named
multi-facet `mfrm_spec` designs. Multidimensional, free-slope (`GPCM`),
predictor-regression, and random-interaction models remain Bayesian routes.

## Quick start: 3-facet and general multi-facet specifications

For a three-facet table (`person`, `rater`, `item`), reuse `FacetData` and
`mfrm_spec` directly:

```julia
using BayesianMGMFRM

data = FacetData(ratings; person=:person, rater=:rater, item=:item,
    score=:score, category_levels=0:4)
spec = mfrm_spec(data; thresholds=:rating_scale) # or :partial_credit

fit_jmle = fit(spec; method=:jmle)
fit_mmle = fit(spec; method=:mmle, quad_points=31, population_sd=1.0)
```

For a general $F$-facet table (for example `Person × Rater × Task × Criterion`),
`mfrm_spec` can be called **without** `prior_sd` when only frequentist estimation
is needed, or **with** `prior_sd` when you want to run both frequentist and
Bayesian fits on the identical specification object:

```julia
spec_4f = mfrm_spec(writing;
    person=:Person,
    facets=(Rater=:Rater, Task=:Task, Criterion=:Criterion),
    score=:Score,
    steps=:global,          # or steps=:Criterion for PCM
    category_levels=0:5,
)

jml_rsm = fit(spec_4f; method=:jmle)
mml_rsm = fit(spec_4f; method=:mmle, quad_points=31, population_sd=1.0)
```

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
     to zero, matching the default gauge of `BayesianMGMFRM`'s `FacetDesign`.
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
freedom and Wilson–Hilferty cube-root `ZSTD` (`df >= 1` safeguard and optional
`zstd_cap = 9.0`), alongside homogeneous-variance `infit_zstd_engine` and
`outfit_zstd_engine` columns and both composite (`ptmea`) and person-only
(`ptmea_person`) point-measure correlations.

## Inspecting, comparing, saving, and plotting

```julia
qualify(mml_rsm)                        # gradient, positive-definite Hessian & boundary check
rep = fit_report(mml_rsm)               # portable summary, facet/step/person tables, reliability
contrast(mml_rsm; facet=:Rater, left="R1", right="R4")

# Compare RSM vs. PCM under MMLE (AIC / BIC / likelihood-ratio summary):
spec_pcm = mfrm_spec(writing; person=:Person,
    facets=(Rater=:Rater, Task=:Task, Criterion=:Criterion),
    score=:Score, steps=:Criterion, category_levels=0:5)
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
