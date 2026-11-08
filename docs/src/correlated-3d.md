# Correlations among three declared traits

Use `BayesianMGMFRM.Experimental.Correlated3D` when item content specifies three
traits and the question concerns their population correlations. This opt-in
workflow estimates item discriminations and rater consistencies, reports named
marginal and partial correlations, and preserves joint posterior draws.
It is Experimental. A successful fit does not establish construct validity,
adequate fit, calibrated uncertainty or the need for three dimensions.

## Model and input

Supply a `FacetSpec` with exactly three named dimensions and a fixed pure Q
matrix: one active dimension per item, at least two items per dimension, every
person observed in every dimension, at least two raters and at least three
declared categories. The first domain uses item-owned partial-credit steps;
cross-loadings, shared response/occasion effects and new-level prediction are
outside this route. The existing two-dimensional wrappers are separate APIs.

For item i assigned to dimension d, adjacent logits are
`1.7 * c[r] * (a[i]*theta[p,d] - b[i] - s[r] - tau[i,k])`.
Item loadings are positive, rater severities sum to zero, log consistencies sum
to zero, and each item's steps sum to zero. Steps are not forced to be ordered.
Person abilities have a zero population mean and fixed marginal SDs of one,
with a jointly positive-definite correlation matrix. Realized person means
and variances are not constrained to equal their population values.

All prior scales and the LKJ shape are explicit. Rater/step widths are the
normalized zero-sum Gaussian **kernel** SDs, not independent marginal SDs.
LKJ shape has a dimension-dependent effect; three separate bivariate priors
would not represent the same joint correlation prior. See the
[Stan LKJ documentation](https://mc-stan.org/docs/functions-reference/correlation_matrix_distributions.html)
and [constraint transforms](https://mc-stan.org/docs/reference-manual/transforms.html).

## A complete small example

These sizes and priors illustrate the operation; they are not a recommended
sample size or scientifically adopted default. Placeholder categories define
the mask. `generate` explicitly replaces them with one prior-generated dataset.

```julia
using BayesianMGMFRM
C = BayesianMGMFRM.Experimental.Correlated3D
cells = [(p, i, r) for p in 1:3 for i in 1:6 for r in 1:3]
table = (person=first.(cells), item=getindex.(cells, 2), rater=last.(cells),
         score=[mod(p+i+r, 4) for (p,i,r) in cells])
data = FacetData(table; person=:person, item=:item, rater=:rater,
                 score=:score, category_levels=0:3)
Q = [j == cld(i,2) for i in 1:6, j in 1:3]
spec = mfrm_spec(data; family=:mgmfrm, dimensions=3,
    thresholds=:partial_credit, q_matrix=Q,
    dimension_labels=["Trait 1", "Trait 2", "Trait 3"])
scales = (person_sd=1.0, rater_sd=0.5, item_sd=0.7,
    log_discrimination_sd=0.3, log_consistency_sd=0.4, step_sd=0.6)
template = C.model(spec; scales, lkj_eta=2.5)
generated = C.generate(template; seed=1234)
target = C.model(generated.spec; scales, lkj_eta=2.5)
result = C.fit(target; ndraws=2000, warmup=1000, chains=4,
               seed=5678, target_accept=.95, max_depth=12)
save_fit("three-trait-fit.jls", result)
summary = posterior_summary(result)
summary.result.posterior
summary.result.mcse
summary.result.diagnostics
```

For observed data, construct `spec` from those observations and call `model`
and `fit` directly. Do not call `generate` to fill missing responses. Generation
holds the declared mask and category support fixed, even if some categories
are absent in the one generated dataset. Its truth and provenance are retained.
Seeded generation is repeatable in the recorded environment, not promised to
be byte-identical across Julia/dependency versions.

## Reading the results

`report` includes all named person/item/rater/step effects, three population
marginal correlations and three rowwise Cholesky partial correlations. The
partial correlation between traits 3 and 2 conditions on trait 1; it is not
their marginal correlation. Population covariance equals correlation because
the marginal SDs are fixed at one. `population_covariance` maps all nine matrix
entries to their summary parameter or a fixed diagonal value; it does not
estimate population SDs. These quantities are not correlations of fitted person
point estimates. A parameter selection retains all-coordinate diagnostics.

Intervals are equal-tailed posterior intervals, with mean and endpoint MCSEs.
Inspect the raw, transformed and sampler diagnostics, including warmup and
retained divergences. Small MCSE does not remedy model misfit or a poor prior.
The centered sampler uses ForwardDiff; no relative-speed or universal
sampling-reliability claim is made. Saturated floating-point correlation
proposals are rejected, never clipped. Diagnostics are not auto-qualified.

```julia
probabilities = C.probabilities(result; observation=1)
probabilities.result.categories
probabilities.result.posterior
restored = load_fit("three-trait-fit.jls")
save_report("three-trait-summary.json", posterior_summary(restored))
```

These probabilities condition on fitted effects at the specified original
row. Their intervals describe parameter uncertainty, not the distribution of
a new categorical observation or performance for a new person/rater. Joint
draw pairing is retained for downstream calculations; marginal interval
endpoints do not constitute one jointly valid correlation matrix.

Native loading is for trusted files in the producing source, Julia version,
platform and Project/Manifest environment. Loading validates all retained
densities and model-effect hashes and performs no fitting or random generation.
Reports are portable JSON summaries, not replayable fits. Saving preserves
existing files; use a new path deliberately. There is no automatic `file=`
request cache or automatic refit when restoration fails.

## API

```@docs
BayesianMGMFRM.Experimental.Correlated3D.contract
BayesianMGMFRM.Experimental.Correlated3D.model
BayesianMGMFRM.Experimental.Correlated3D.generate
BayesianMGMFRM.Experimental.Correlated3D.fit
BayesianMGMFRM.Experimental.Correlated3D.report
BayesianMGMFRM.Experimental.Correlated3D.probabilities
BayesianMGMFRM.Experimental.Correlated3D.save_result
BayesianMGMFRM.Experimental.Correlated3D.load_result
BayesianMGMFRM.Experimental.Correlated3D.save_report
```
