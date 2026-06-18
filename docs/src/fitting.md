# Minimal Bayesian Fitting

The first Bayesian fitting path targets the same minimal additive MFRM/RSM/PCM
design returned by `getdesign`. It places independent zero-centered normal
priors on the identified parameter vector and samples with a random-walk
Metropolis kernel.

```julia
using BayesianMGMFRM

ratings = (
    examinee = ["E1", "E1", "E1", "E2", "E2", "E2", "E3", "E3", "E3"],
    rater = ["R1", "R2", "R1", "R1", "R2", "R1", "R1", "R2", "R1"],
    item = ["I1", "I1", "I2", "I1", "I2", "I2", "I1", "I2", "I2"],
    score = [0, 1, 2, 1, 0, 2, 1, 2, 0],
)

data = FacetData(ratings; person = :examinee, rater = :rater, item = :item, score = :score)
spec = mfrm_spec(data; thresholds = :partial_credit)
prior = MFRMPrior(; person_sd = 1.5, rater_sd = 1.0, item_sd = 1.0, step_sd = 1.0)
fit_result = fit(spec; prior, backend = :julia, ndraws = 500, warmup = 500, step_size = 0.04)

posterior_summary(fit_result)
pointwise_loglikelihood_matrix(fit_result)
posterior_predict(fit_result; ndraws = 100)
posterior_predictive_check(fit_result; ndraws = 100)
```

This sampler is intended for small validation examples and API stabilization.
The package does not yet expose production HMC/NUTS sampling, Stan/CmdStan
sampling, convergence diagnostics, prior predictive checks, or model-comparison
helpers. The current posterior predictive check returns compact observed-vs-
replicated summaries for overall mean score, category proportions, rater-level
mean scores, and item-level mean scores. The `backend` keyword is explicit so
additional engines can be added without changing the fitted-object shape.
