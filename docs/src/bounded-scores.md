# Analyze bounded scores with endpoints

Use this route for a single bounded rating such as a 0–100
comprehensibility slider. It retains exact endpoint observations. It is a
zero-one-inflated beta (ZOIB) model with explanatory population effects, not
an ordinal PCM or a guarantee of Rasch measurement properties. For correct words
out of a known total, use the [count model](count-scores.md) instead.

## What the table must contain

Each row is one rating. Supply the score, speaker, listener and recording IDs,
plus the predictors you intend to use. A recording must belong to one speaker.
Repeated listener ratings of that recording share its recording effect. Scores
must be nonmissing and inside the declared bounds; decide how missing responses
arose before selecting observed rows. Keep the original data and scoring rules.

In this example, `ratings` has columns `speaker`, `recording`, `listener`,
`score`, `rate` and `experience`. Experience must be constant within listener;
use a session/response-owned predictor when it changes across sessions.

```julia
using BayesianMGMFRM
using BayesianMGMFRM.Legacy
using Distributions: Normal, LogNormal

spec = mfrm_spec(ratings;
    person=:speaker, score=:score, performance=:recording,
    facets=(recording_effect=:recording, assessor=:listener),
    observation=(family=:zero_one_inflated_beta, bounds=(0.0, 100.0)),
    observation_prior=(precision=LogNormal(log(12), .4),
        endpoint_logit=Normal(-2, .7), upper_logit=Normal(.3, .8)),
    population=(person=LogNormal(log(.5), .35),
        recording_effect=.3, assessor=LogNormal(log(.4), .35)),
    decompose=(rate=(between=:mean_rate, within=:rate_change),),
    predictors=(person=(mean_rate=Normal(0, .6),),
        assessor=(experience=Normal(0, .5),),
        response=(rate_change=Normal(0, .6),)),
    intercept=Normal(0, 1))

validate_design(spec)
prior = prior_predictive_check(spec; seed=1001, ndraws=100)
```

The priors are illustrative, not universal recommendations. `population` declares
every owner: a number fixes its residual SD; a `LogNormal` estimates it.
Residuals have zero population mean, not an imposed zero sample mean.
Mean rate weights unique recordings equally; `rate_change` is each recording's
deviation. One recording per speaker cannot identify two unrestricted population
variances. Finite sum-zero effects are not in this bounded route.

## Fit, inspect and save

```julia
result = fit(spec; chains=4, warmup=800, ndraws=2000, seed=1002,
    chain_execution=:threads, max_parallel_chains=4)
qualify(result)
parameters = ["coefficient[response,rate_change]", "precision",
              "endpoint_logit", "upper_logit"]
report = fit_report(result; parameters, include_draws=true)
ppc = predictive_check(result; seed=1003, ndraws=300)
prediction = predict(result; rows=[1, 2])

using CairoMakie
BayesianMGMFRM.plot(prior; kind=:predictive)
BayesianMGMFRM.plot(report; kind=:diagnostics)
BayesianMGMFRM.plot(ppc; kind=:predictive)
BayesianMGMFRM.plot(prediction; kind=:prediction)
save_fit("bounded-fit.jls", result)
save_report("bounded-prediction.json", prediction)
BayesianMGMFRM.plot(load_report("bounded-prediction.json"); kind=:prediction)
```

Counts are examples, not guaranteed sufficient sampling. Inspect whole-fit
diagnostics and focal MCSE, including interval endpoints. Prior and posterior
predictive displays are explicitly labeled. PPC compares endpoint rates, overall
mean/SD and interior-only mean/SD; interior summaries retain the number of defined
replicas. These summaries do not exhaust predictive adequacy. Use `groupby` with
a declared owner to look beyond pooled agreement. Save/reopen plots does not refit.

## Read the quantities correctly

`precision` is the beta concentration, not rater reliability. `endpoint_logit`
controls the chance of either endpoint; `upper_logit` controls the upper endpoint
conditional on reaching an endpoint. These three parameters are constant in this example.
If these probabilities are `z` and `h` and the interior mean is `mu`, the total
normalized expectation is `(1-z)*mu + z*h`. `predict` reports the total and
interior means in original score units, plus both endpoint probabilities.
Its intervals describe parameter uncertainty, not future individual scores.

Person/response coefficients increase the interior mean; positive facet
coefficients decrease it, following the severity convention. Interpret coefficients
per supplied predictor unit. No 1.7 multiplier is used. Integer slider interiors
are treated as a continuous approximation; no jitter or endpoint squeezing occurs.
Continuous log densities include the bounds' unit transformation. They must not be
compared directly with categorical log probabilities from collapsed scores.

For selected prior-factor sensitivity, use the existing `prior_sensitivity`
operation; factor IDs include `precision`, `endpoint_logit`, `upper_logit`,
coefficients and residual-SD priors. A prediction estimand can be
`"total" => (row=1, metric=:expected_score)`. Review weight diagnostics and MCSE;
failed reweighting does not establish robustness.

`criteria(result; unit=:rating)` and `compare_models("a"=>a, "b"=>b;
criterion=:psis_loo)` compare the same rating rows, bounds and measure with known
owners. The score is not new-speaker/listener/performance prediction. Population
sampling SE, automatic ranking and automatic refitting are not supplied.
Saved reports retain failures and can be plotted with `kind=:comparison`.
Use `receipt = save_report(path, report; return_receipt=true)` and retain
`receipt.sha256`; reopen comparison/sensitivity reports with
`load_report(path; expected_sha256=receipt.sha256)`.
The scalar model does not combine multiple outcomes.

For one declared correlated intercept/rate-slope pair per owner, see
[random slopes](random-slopes.md). For condition-dependent precision and endpoint use, see
[distributional regressions](distributional-scores.md). Joint outcomes remain separate.

Predictive reports retain numerical failures if interior beta draws round to an
endpoint. Incomplete bands describe only representable replicas, not the full
predictive distribution. No clipping or replacement draw is used.
