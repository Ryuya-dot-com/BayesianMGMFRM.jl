# Explain dispersion and endpoint use

Use this scalar ZOIB extension when a condition or listener
attribute may change rating variability or endpoint use, in addition to the
interior mean. Start with the [bounded-score guide](bounded-scores.md). Keep
its mean model and replace `observation_prior` with blocks such as:

```julia
observation_prior = (
    precision=(intercept=LogNormal(log(12), .35),
        predictors=(response=(condition=Normal(0, .7),),),
        population=(assessor=LogNormal(log(.2), .35),)),
    endpoint_logit=(intercept=Normal(-1, .6),
        predictors=(response=(condition=Normal(0, .7),),),
        population=(assessor=.15,)),
    upper_logit=(intercept=Normal(0, .6),
        predictors=(response=(condition=Normal(0, .7),),),
        population=(assessor=.15,)))
```

Pass this value to the same `mfrm_spec` call. `assessor` must be a facet name
already declared in that call; it is not a built-in role. Add a numeric
`condition` column to the input. The values illustrate syntax, not recommended
priors. A scalar prior entry still declares a constant parameter. A structured
entry requires `intercept`; `predictors` and `population` are optional.

## What each block means

| Block | Link | Positive coefficient means |
| --- | --- | --- |
| `precision` | log beta concentration | Less interior variability at a fixed interior mean |
| `endpoint_logit` | logit probability of either endpoint | More endpoint observations |
| `upper_logit` | logit probability of the upper endpoint, conditional on an endpoint | More upper rather than lower endpoints |

Every coefficient and random intercept in these blocks **adds** on its link
scale, including listener-owned terms. Mean-model facet severity still subtracts
from the interior-mean predictor. Do not transfer that sign convention here.
`upper_logit` does not directly model the unconditional upper-endpoint probability:
if endpoint probability is z and conditional upper probability is h, the latter
probability is z*h. Interior beta variance on the normalized scale is
mu*(1-mu)/(precision+1). Higher precision need not reduce the whole mixture's SD.

Use `person`, `response`, or any declared facet for predictor ownership. Attributes
owned by a person or facet must be constant within that owner; session-varying
attributes belong at the appropriate response/session level. Response predictors
can use the existing `(prior=Normal(...), by=:facet_name)` declaration. Population
intercepts may be declared for a person or named facet, with a fixed positive SD
or a LogNormal SD prior. Owner counts are not capped at five facets.

Blocks have separate, independent Gaussian random intercepts. Reusing an owner
name does not share a residual across blocks. Cross-block correlations, slopes
within these blocks, multiple mean slopes per owner, and joint outcomes are not
provided here. The declared [mean intercept/slope pair](random-slopes.md) can
coexist with these distributional intercepts.

## Check information before interpreting coefficients

Run `validate_design(spec)` before fitting. Full-design aliases are rejected.
Reports also show contributing rows and fixed-design ranks: precision uses
interior observations; the conditional-upper block uses endpoint observations;
the endpoint block uses all observations. Missing conditional directions trigger
warnings while proper priors keep the target defined. Full rank is not proof
of adequate information: rare endpoints or few owners may leave large uncertainty
and strong prior sensitivity. A positive SD interval under a LogNormal prior
does not test whether a variance is zero.

Fit and inspect the usual prior/PPC, convergence and trace reports. PPC should
look at variability and endpoint use across the predictor of interest, as well
as pooled summaries; a mean-only check can miss these differences. Preserve
failed predictive replicas rather than squeezing endpoints or replacing draws.

```julia
report = predict(result; rows=[1, 2], metrics=(
    :precision, :endpoint_probability,
    :upper_given_endpoint_probability, :score_sd))
BayesianMGMFRM.plot(report; kind=:prediction)
save_report("distribution-parameters.json", report)
```

These intervals describe posterior uncertainty in **conditional distribution
parameters**. `score_sd` includes interior and endpoint mixture variation in the
original score units; `interior_sd` excludes endpoint observations. Neither is an
interval for a future individual score. Default `predict` metrics remain total
mean, interior mean, and unconditional lower/upper probabilities. Predictions
condition on known owners and preserve their stored attributes.

Use `parameter_names(result)` for coefficient and SD names, for example
`coefficient[precision,response,condition]` and `residual_sd[precision,assessor]`.
The same names select scientific factors in `prior_sensitivity`; prediction
estimands accept the metrics above. The precision intercept prior is on positive
concentration, with its transformation Jacobian retained; coefficient priors
are on the stated links. Reweighting a scientific prior does not power coordinate
Jacobians. Review weight reliability and MCSE before drawing sensitivity conclusions.

`criteria(result; unit=:rating)` can compare this model with constant blocks on
the same observed ratings, bounds and measure. This is known-owner predictive
scoring, not prediction for an unseen listener or a general superiority claim.
Save/reopen uses the existing fit/report operations.

The observation mixture and distributional regression match the corresponding
[brms family definition](https://paulbuerkner.com/brms/articles/brms_families.html)
and [distributional-regression framework](https://paulbuerkner.com/brms/articles/brms_distreg.html).
Posterior equivalence additionally requires matching predictors, signs, all
priors and identification. A paper's more extensive correlated model is not
reproduced by this reduced declaration alone.
