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
spec_rsm = mfrm_spec(data; thresholds = :rating_scale)
prior = MFRMPrior(; person_sd = 1.5, rater_sd = 1.0, item_sd = 1.0, step_sd = 1.0)
prior_predict(spec; prior, ndraws = 100)
prior_ppc = prior_predictive_check(spec; prior, ndraws = 100)
predictive_check_summary(prior_ppc)
fit_result = fit(spec; prior, backend = :julia, ndraws = 500, warmup = 500, step_size = 0.04)
fit_result_rsm = fit(spec_rsm; prior, backend = :julia, ndraws = 500, warmup = 500, step_size = 0.04)

posterior_summary(fit_result)
pointwise_loglikelihood_matrix(fit_result)
waic(fit_result)
compare_models(:partial_credit => fit_result, :rating_scale => fit_result_rsm)
predictive_probabilities(fit_result)
expected_scores(fit_result)
predictive_variances(fit_result)
predictive_residuals(fit_result)
fit_stats(fit_result; by = :rater)
posterior_predict(fit_result; ndraws = 100)
ppc = posterior_predictive_check(fit_result; ndraws = 100)
predictive_check_summary(ppc)
```

This sampler is intended for small validation examples and API stabilization.
The package does not yet expose production HMC/NUTS sampling, Stan/CmdStan
sampling, convergence diagnostics, PSIS-LOO, or richer model-comparison
workflows. The current prior and posterior predictive checks return compact
observed-vs-replicated summaries for overall mean score, category proportions,
rater-level mean scores, and item-level mean scores; `predictive_check_summary`
turns those checks into rows with replicated intervals and tail probabilities.
`waic` computes WAIC from posterior pointwise log-likelihood draws, and
`compare_models` ranks fitted models by WAIC-derived expected log predictive
density. Observation-level predictive probabilities, expected scores,
variances, and residuals are exposed as the substrate for calibration,
infit/outfit, and further model-comparison helpers. `fit_stats` currently
returns posterior summaries of infit and outfit mean-square statistics by facet
level. The `backend` keyword is explicit so additional engines can be added
without changing the fitted-object shape.
