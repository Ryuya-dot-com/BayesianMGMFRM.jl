# Analyze correct counts with known totals

Use this route when each response reports correct words out of
a known number of scored words. Keep both integers: 4/5 and 40/50 have the same
proportion but supply different information under a binomial model. Do not
convert rounded percentages into invented counts.

## Input and model

Each table row is one response, with `correct`, `total`, speaker, recording and
listener IDs. Counts must satisfy `0 <= correct <= total` and `total > 0`.
Missing values and fractional counts refuse. An unadministered transcription is
missing by design, not zero correct. Reconcile the denominator with the actual
scoring rule before selecting observed rows.

```julia
using BayesianMGMFRM
using BayesianMGMFRM.Legacy
using Distributions: Normal, LogNormal

spec = mfrm_spec(responses;
    person=:speaker, score=:correct, performance=:recording,
    facets=(recording_effect=:recording, listener_effect=:listener),
    observation=(family=:beta_binomial, trials=:total),
    observation_prior=(precision=LogNormal(log(8), .6),),
    population=(person=LogNormal(log(.5), .35),
        recording_effect=.3, listener_effect=LogNormal(log(.4), .35)),
    predictors=(response=(rate=Normal(0, .6),),),
    intercept=Normal(0, 1))

validate_design(spec)
prior = prior_predictive_check(spec; seed=101, ndraws=100)
```

These priors illustrate syntax; they are not universal recommendations. Each
declared owner needs a population residual SD, fixed numerically or assigned a
LogNormal prior. The mean uses the same person/facet/response predictor rules as
[explanatory ratings](explanatory-ratings.md), including unique-recording
within/between decomposition. A positive listener-facet effect lowers success
probability; call it a recognition/reproduction tendency when that describes the
task, rather than assuming it is a rater's severity. No 1.7 multiplier is applied.
`trials` is reserved as a diagnostic grouping name in this count route.

For `family=:binomial`, omit `observation_prior`. Conditional on the declared
effects, scored words are modeled as independent trials with one probability.
The beta-binomial allows an exchangeable response-specific success probability:
its beta distribution has mean `p` and precision `phi`. Its count variance is
`n*p*(1-p)*(1+(n-1)/(1+phi))`. Smaller precision means greater overdispersion;
`1/(1+phi)` describes within-response dependence, not rater reliability. Neither
model reconstructs word difficulty or word order from a total count.

With one trial, both likelihoods are exactly Bernoulli. If every row has one
trial, precision is informed only by its prior; the design report warns about
this. Between-speaker, recording and within-response variation are different
sources. One recording per speaker cannot identify two unrestricted owner
variances. This scalar route does not add random slopes or multiple outcomes.

## Fit, check and visualize

```julia
result = fit(spec; chains=4, warmup=800, ndraws=2000, seed=102,
    chain_execution=:threads, max_parallel_chains=4)
qualify(result)
report = fit_report(result;
    parameters=["coefficient[response,rate]", "precision"], include_draws=true)
ppc = predictive_check(result; seed=103, ndraws=300)
prediction = predict(result; rows=[1, 2])

using CairoMakie
BayesianMGMFRM.plot(prior; kind=:predictive)
BayesianMGMFRM.plot(report; kind=:diagnostics)
BayesianMGMFRM.plot(ppc; kind=:predictive)
BayesianMGMFRM.plot(prediction; kind=:prediction)
save_fit("count-fit.jls", result)
save_report("count-prediction.json", prediction)
BayesianMGMFRM.plot(load_report("count-prediction.json"); kind=:prediction)
```

Iteration counts are examples. Check whole-fit diagnostics and focal MCSE,
including interval endpoints; a passing numerical check is not adequate fit.
For a binomial report, omit `precision` from the requested parameter names.
PPC defaults to separate trial counts and compares zero/perfect rates, response
proportions and their variation. `groupby=:person` or a declared facet instead
inspects an owner. Equal-response and pooled word proportions differ when
denominators vary; neither weighting is automatically the research estimand.
PPC intervals are pointwise, and their endpoint MCSE is not assessed.

`predict` reports expected correct counts/proportions and zero/perfect probabilities
at the supplied trial counts. Its CrIs represent parameter uncertainty, not future
individual counts. New rows require known owners and stored owner attributes;
they must declare `total`. Changing the denominator predicts under the same
probability model; it does not establish invariance to sentence difficulty.

Use `prior_sensitivity` for declared coefficient/SD factors and beta-binomial
`precision`, keeping Jacobians unpowered. Review weight and focal-MCSE warnings.
`criteria(result; unit=:rating)` and `compare_models(...; criterion=:psis_loo)`
compare count probabilities for identical counts, denominators and known owners.
They do not score a new speaker/recording/listener or supply a population sampling
SE. Neither collapsed-category scores nor continuous densities share this measure.
Retain the receipt from `save_report(...; return_receipt=true)` and supply its
SHA-256 to reopen sensitivity/comparison reports with `load_report`.

The normalized observation models follow the
[Stan probability functions](https://mc-stan.org/docs/functions-reference/bounded_discrete_distributions.html).
Beta-binomial mean/precision also corresponds to the
[brms mu/phi parameterization](https://paulbuerkner.com/brms/reference/BetaBinomial.html).
Matching a likelihood does not establish matching owner priors, identification,
full-model coverage or posterior results across software.
