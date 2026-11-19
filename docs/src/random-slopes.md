# Allow a predictor's effect to vary by listener

Use this **Experimental** extension when listeners may respond differently to
speech rate or another numeric predictor. A common rate coefficient describes
the population association; random slopes describe remaining listener variation.
A listener-experience interaction explains part of that variation if declared
separately. None of these terms is a rater discrimination parameter.

## Declare the pair in the existing population block

Start from the [bounded-score example](bounded-scores.md). Replace the listener's
population SD with an intercept/slope declaration; keep the other owners and the
common coefficient:

```julia
using Distributions: Normal, LogNormal, LKJ

population = (person=LogNormal(log(.5), .35), recording_effect=.3,
    listener_effect=(intercept=LogNormal(log(.4), .35),
        slopes=(rate_change=LogNormal(log(.6), .4),),
        correlation=LKJ(2, 2.0)))
predictors = (person=(mean_rate=Normal(0, .6),),
    response=(rate_change=Normal(0, .6),))

spec = mfrm_spec(ratings;
    person=:speaker, score=:score, performance=:recording,
    facets=(recording_effect=:recording, listener_effect=:listener),
    observation=(family=:zero_one_inflated_beta, bounds=(0., 100.)),
    observation_prior=(precision=LogNormal(log(12), .4),
        endpoint_logit=Normal(-2, .6), upper_logit=Normal(0, .7)),
    population, predictors, intercept=Normal(0, 1),
    decompose=(rate=(between=:mean_rate, within=:rate_change),))
validate_design(spec)
```

The values illustrate syntax, not universal priors. Input `rate` is constant
within each recording. Decomposition uses each speaker's unique performances,
not the number of ratings. Scalar ZOIB and scalar count (`binomial` and
`beta_binomial`) models accept one or more declared mean slopes per named owner.
Names remain user-defined; multiple owners may declare slopes, subject to design
and numerical checks. Ordinal random slopes, distributional-block slopes,
new-owner integration and joint outcomes remain separate extensions.

`correlation=0` fixes independence. With `K` slopes on an owner, `LKJ(K + 1, eta)`
estimates the residual `(K + 1) × (K + 1)` correlation matrix across the intercept
and declared slopes; larger eta concentrates more prior mass near zero. No correlation
prior is chosen silently. Intercept and slope SDs may each be fixed positive
numbers or LogNormal priors. Correlated residuals are noncentered internally;
this computation does not change the declared joint prior.

## Interpret signs, units and uncertainty

For a listener facet, the model subtracts both its intercept and its slope
contribution. With common coefficient beta and listener slope residual b1,
the listener's interior-mean response slope is **beta − b1**. For a person-owned
slope, its contribution is positive. A positive listener slope residual therefore
reduces the rate association. The estimated correlation concerns residual
intercepts/slopes after any declared owner predictors, not the sample correlation
of posterior-mean listener scores.

After fitting, use exact names from `parameter_names(result)` to combine a
facet's slope with its common coefficient, for example for integer listener ID 2:

```julia
contrast(result;
    left="coefficient[response,rate_change]",
    right="slope[listener_effect,rate_change,2]")
```

This computes beta minus b1 within each joint draw, retaining their dependence
and reporting the interval and its Monte Carlo uncertainty. Subtracting marginal
interval endpoints would not give this interval. This difference is a total
response slope for a facet; a person-owned slope instead adds to beta.

The slope refers to the interior-mean logit, not the original 0–100 mean.
Use `predict(result)` for the expected score including endpoint probabilities.
Its intervals describe uncertainty in expectations, not future individual scores.
Known-owner predictions preserve stored performance/source attributes; changing
an observed recording's rate is not a supported counterfactual operation.

Centering changes the meaning of the intercept and its covariance with slopes.
Changing units rescales slopes and their SDs. To preserve a model under either
change, transform the joint prior as well; assigning the same independent priors
again specifies a different model. An estimated random-slope variance with only
a few listeners may remain strongly prior-sensitive. Structural kernel checks
can expose aliasing but do not guarantee practical identification.
Because a LogNormal SD prior excludes zero, a positive SD credible interval is
not evidence against an intercept-only model. Use an explicitly matched model
comparison for that predictive question, retaining its diagnostics and limits.

## Use the same workflow

Call `prior_predictive_check`, `fit`, `qualify`, `fit_report`, `predictive_check`,
`predict`, `plot`, `save_fit` and `save_report` as in the bounded guide.
`parameter_names(result)` lists `slope[owner,column,ID]`, `slope_sd[owner,column]`
and `correlation[owner,column]` alongside the existing parameters. Inspect full
numerical diagnostics and focal mean/interval-endpoint MCSE; visually mixed
traces alone do not establish precision or model fit. Extreme beta draws can
round to an endpoint numerically. Predictive checks record failed replications
without clipping or replacement. If `replications_complete` is false, displayed
intervals condition on the representable replicas; they cannot establish adequacy
for the full predictive distribution. Inspect `numerical_failures` and warnings.

`logprior(result)` exposes the slope-SD and correlation factors for
`prior_sensitivity`. Power the scientific factors; conditional residuals and
Jacobians stay unchanged. LKJ(1) is uniform in correlation for this pair, so its
power scaling is exactly unchanged: a flat sensitivity curve at LKJ(1) cannot
establish robustness to alternative correlation priors. Near-one screens also
cannot establish broad prior robustness. Keep poor-weight warnings.

Known-owner rating-wise `criteria(...; unit=:rating)` retains the same observation
measure and counts each held response once. It does not evaluate a new listener,
speaker or recording. For precision/endpoint regressions alongside the mean slope, see
[distributional regressions](distributional-scores.md). Joint outcomes and
population-integrated prediction remain separate capabilities.

The covariance separation follows the [Stan hierarchical-model formulation](https://mc-stan.org/docs/stan-users-guide/regression.html#multivariate-priors-for-hierarchical-models)
and [LKJ specification](https://mc-stan.org/docs/functions-reference/correlation_matrix_distributions.html).
The analogous [brms grouping expression](https://paulbuerkner.com/brms/reference/brmsformula.html)
is `(1 + x | listener)`, after aligning signs, predictor transformations and
all priors. Similar syntax or likelihoods do not establish posterior equivalence.
