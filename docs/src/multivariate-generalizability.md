# Univariate and multivariate generalizability theory

Use multivariate G-theory when the question concerns the reliability of several
numeric scores, their weighted composite, and the number of raters or tasks needed
for a future assessment. The model partitions **both variances and covariances**
by source and carries uncertainty into a D study. One score column specifies
univariate G-theory. Choose explicit ML/REML estimation or Bayesian NUTS.

For a person × rater × task design, the score vector is

```math
\mathbf y_{prt}=\boldsymbol\mu+\mathbf p_p+\mathbf r_r+\mathbf t_t+
\mathbf{pr}_{pr}+\mathbf{pt}_{pt}+\mathbf{rt}_{rt}+\boldsymbol\epsilon_{prt}.
```

Each effect has its own multivariate normal distribution and covariance matrix.
The residual includes the highest interaction and measurement error; one score
vector per cell cannot separate those two sources. For one random facet, the
components are person, facet, and their interaction/residual. For a nested design,
use `nesting=(rater=:task,)`: components are person, task, rater within task,
person × task, and person × rater within task/residual. Child IDs can repeat across
parents because their joint identities are retained.

These covariance structures follow the common-design formulations in
[Jiang and Skorupski (2018), especially Equations 8–9](https://doi.org/10.3758/s13428-017-0986-3).
Their BUGS tutorial uses Wishart-based covariance priors. This implementation
instead explicitly separates marginal SDs from LKJ correlations, as described in
the [Stan multivariate hierarchical prior guide](https://mc-stan.org/docs/stan-users-guide/regression.html#multivariate-priors-for-hierarchical-models).
It therefore implements the same covariance decomposition with a different,
user-declared prior specification, rather than reproducing the original posterior.

## ML and REML

```julia
using BayesianMGMFRM
const GT = BayesianMGMFRM.Generalizability
spec = GT.model(scores; person=:Person,
    facets=(rater=:Rater, task=:Task),
    scores=(:Content, :Organization), prior=:none)
fit_gt = fit(spec; method=:reml)   # :ml also available
GT.component_summary(fit_gt)
diagnostics(fit_gt)
d_study = reliability(fit_gt; counts=(rater=3, task=2), weights=[0.6, 0.4])
```

Use `scores=(:Content,)` for a single score and `nesting=(rater=:task,)`
for raters nested within tasks. These are Gaussian score models; ordinal
Rasch `:jmle` and `:mmle` are separate estimators. ML/REML requires
`prior=:none`; it never discards a supplied prior implicitly.

Random effects are integrated analytically. ML profiles one unrestricted mean
per score; REML additionally accounts for estimating those means, using the
restricted Gaussian likelihood. The parameterization permits positive
semidefinite random-effect covariance matrices and requires positive definite
residual covariance. The likelihood follows
[Bates et al. (2015), Section 3.4](https://doi.org/10.18637/jss.v067.i01).
Numerical stationarity checks include both factor gradients and covariance
boundary conditions; they do not certify a global optimum or adequate sample size.

`GT.component_summary()` and `reliability()` report point estimates, standard
errors and pointwise asymptotic confidence intervals from observed information
and the delta method. Intervals are withheld when a covariance component is
on a boundary, optimization checks fail or information is unsuitable. They
are not clipped to the parameter bounds. Finite-sample coverage is not
established; a narrow interval is not evidence of model adequacy. ML/REML
reports do not contain posterior probabilities, R-hat, ESS or MCMC diagnostics.
The current implementation uses dense Gaussian covariance algebra; memory and
factorization costs grow with the total number of observed scalar scores.

### Finite-sample intervals for a complete one-facet design

For a separate table `rater_scores` with one row per person/rater cell:

```julia
one_facet = GT.model(rater_scores; person=:Person, facets=(rater=:Rater,),
    scores=(:Content, :Organization), prior=:none)
fit_one = fit(one_facet; method=:reml)
d = reliability(fit_one; counts=(rater=4,), weights=[0.6, 0.4],
    interval_method=:exact)
```

This option requires a **complete person × one random facet** allocation with
at least two levels of each. Under the independent Gaussian random-effects
model, it uses the F pivot for G and the chi-square pivot for relative SEM.
Weights must be specified independently of the observed scores. Multivariate
mean-square matrices retain cross-score covariance, so the same calculation
applies to each score or a prespecified weighted composite. The usual
consistency-ICC F interval is documented in the
[Stata ICC manual, Methods and formulas, pp. 20–22](https://www.stata.com/manuals/ricc.pdf).
Changing the future replication count is a monotone transformation of that
variance-ratio interval.

ML/REML point estimates are retained; these exact intervals come from the raw
Gaussian mean squares, not the fitted covariance Hessian. They can remain
available when a fitted covariance component is on a boundary. The F confidence
set is intersected with the nonnegative person-variance model; if that
intersection is empty, bounds remain missing with `status=:empty_confidence_set`.
It is not replaced by a zero-width interval at zero. These are pointwise
confidence sets, not posterior probabilities or simultaneous bands.

This option does not supply intervals for Phi, absolute SEM or the other
variance summaries (`status=:not_supported_by_exact`); it never silently falls
back to delta intervals. Incomplete or two-facet designs are rejected. New
ML/REML reports store the necessary mean squares. Older reports without them
retain delta calculations but cannot supply exact intervals without their
original complete score data.

### Joint uncertainty across future designs

For a complete balanced one- or two-facet design, including raters nested
within tasks, `interval_method=:mean_square_region` supplies intervals for
G, Phi, both SEM metrics and the two variance summaries:

```julia
region_d = reliability(fit_gt; counts=(rater=4, task=2), weights=[0.6, 0.4],
    interval_method=:mean_square_region)
using CairoMakie
BayesianMGMFRM.plot(fit_gt; kind=:dstudy, metric=:Phi,
    counts=(rater=1:6, task=1:3), weights=[0.6, 0.4],
    interval_method=:mean_square_region)
```

The source must contain every person/facet cell, with equal child counts per
parent in a nested design. Independent normal random effects give independent
chi-square pivots for the ANOVA mean squares. The implementation forms their
simultaneous region, intersects it with nonnegative variance components, and
projects it onto the requested coefficients and error variances. The SEM
intervals are square roots of the error-variance limits. These are extensions
of the same [chi-square variance pivot](https://www.itl.nist.gov/div898/handbook/eda/section3/eda358.htm)
used in the one-facet calculation.

Under those assumptions, the projections have **at least the requested
coverage jointly across future counts and metrics for one fixed score or
prespecified composite**. This does not provide joint coverage across the
different scores or data-selected weights. Intervals can be substantially wider
than pointwise or asymptotic intervals; more planned raters do not add information
to the original G-study data. They are not posterior probabilities, profile
likelihood intervals or distribution-robust intervals.

ML/REML points and numerical warnings are retained. A covariance boundary does
not prevent the mean-square calculation. Empty regions, degenerate mean squares
and unresolved numerical ranges retain explicit statuses and missing bounds.
Incomplete designs and older reports lacking the ANOVA summaries are rejected
for this method. No automatic method substitution occurs. New fits save the
small mean-square matrices and degrees of freedom, so subsequent calculations
and plots do not fit another model or draw random samples.

## Bayesian estimation


Supply a wide table with one row per person/facet cell and one numeric column per
criterion. All declared criteria must be observed in every supplied row. Entire
missing cells are allowed when the covariance components remain distinguishable;
duplicate cells and aliased covariance components are rejected. There are one or
two random measurement facets. Criteria are the fixed vector of outcomes, not
another randomly sampled facet.

```julia
using BayesianMGMFRM
using Distributions: Normal, truncated, LKJ
const GT = BayesianMGMFRM.Generalizability

spec = GT.model(scores;
    person=:Person, facets=(rater=:Rater, task=:Task),
    scores=(:Content, :Organization),
    prior=(mean=Normal(0, 5),
           sd=truncated(Normal(0, 2), 0, Inf),
           correlation=LKJ(2, 2)))
validate_design(spec)
fit_gt = fit(spec; chains=4, warmup=1000, ndraws=1000, seed=42)
posterior_summary(fit_gt)
posterior_mcse(fit_gt)
diagnostics(fit_gt)
qualify(fit_gt)
predictive_check(fit_gt; seed=43)
```

For a single score, supply `correlation=nothing` instead of an LKJ prior.
Choose mean and SD prior scales in the actual score units; the numbers above are
illustrative. The covariance prior is
`Σ = Diagonal(sd) * R * Diagonal(sd)`, with independent HalfNormal SDs and an LKJ
correlation matrix for each component. Effects use noncentered standard normal
coordinates; no sample-centering constraint changes their population distribution.
`prior_draw(spec; seed=...)` and `simulate(spec, draw; seed=...)` generate a complete
score table on the declared allocation.

The Gaussian observation model treats the scores as numeric measurements. For
coarse ordinal categories, floor/ceiling concentrations or strongly non-Gaussian
scores, inspect replicated means, variances and cross-score covariances and
consider an ordinal MGMFRM analysis. Passing a structural screen does not establish
adequate information or model fit. R-hat 1.01, bulk/tail ESS 400, energy and sampler
warnings remain computational reference criteria; required MCSE depends on the
quantity and decision.

## Bayesian D-study coefficients and probabilities

```julia
d_study = reliability(fit_gt;
    counts=(rater=3, task=2), weights=[0.6, 0.4],
    threshold=0.80, interval=0.95)
```

For each criterion and the composite, the result includes posterior means and
credible intervals for relative G, absolute Φ, relative/absolute SEM, universe
variance and absolute error variance. It also gives `P(G ≥ 0.80 | data)` and
`P(Φ ≥ 0.80 | data)`, with chain-aware MCSE. Constant sampled indicators have
unresolved probability precision; an empirical proportion of zero or one is not
reported as a precisely established probability. Whole-fit diagnostic warnings
remain attached to every D-study result.

For a crossed design with counts `n_r` and `n_t`,

```math
\Sigma_\delta=\Sigma_{pr}/n_r+\Sigma_{pt}/n_t+\Sigma_e/(n_r n_t),\qquad
\Sigma_\Delta=\Sigma_\delta+\Sigma_r/n_r+\Sigma_t/n_t+\Sigma_{rt}/(n_r n_t).
```

For each posterior draw and weight vector `w`,

```math
G=\frac{w^\mathsf T\Sigma_p w}{w^\mathsf T(\Sigma_p+\Sigma_\delta)w},\qquad
\Phi=\frac{w^\mathsf T\Sigma_p w}{w^\mathsf T(\Sigma_p+\Sigma_\Delta)w}.
```

Counts always describe a future complete balanced allocation of new random facet
levels. A nested child count is **per parent**, so child and residual contributions
are divided by the parent count times the child count. Counts are required explicitly,
even for an unbalanced G study. Weights keep their supplied scale: doubling them
preserves G/Φ and doubles SEM. Omitting weights uses the equal-score mean.
These are population design coefficients, distinct from the finite-cohort
reliability of posterior person estimates in an ordinal model.

## Interpret covariance alongside criterion discrimination

A person covariance describes stable relationships among criteria. Rater covariance
reflects criterion tendencies shared by a rater; person × rater covariance describes
a rater's person-specific tendencies recurring across tasks. The residual covariance
captures remaining dependence within a complete person/rater/task cell. Positive
covariance in any one component does not by itself establish psychological halo.
With only one facet, person × rater and measurement residual covariance are combined.

Criterion discrimination in MGMFRM acts on the latent measurement scale. Multivariate
G-theory instead decomposes numeric score covariance; unequal discrimination can
change the signal/error pattern, but is not separately identified by adding free
loadings to an unrestricted person covariance. Use the models to answer complementary
questions: MGMFRM for criterion loadings and ordinal response behavior, G-theory for
where score covariance occurs and how replication affects reliability. Raw score
correlations and latent correlations are not interchangeable, and neither a large
correlation nor improved model fit alone establishes a causal halo mechanism.

## Save joint results

```julia
save_fit("gtheory.jls", fit_gt)  # trusted cache for the same source/environment
receipt = save_report("gtheory.json", fit_gt; return_receipt=true)
report = load_report(receipt.path; expected_sha256=receipt.sha256)
new_plan = reliability(report; counts=(rater=4, task=2), weights=[0.6, 0.4])
```

The Bayesian portable report retains joint covariance draws, criterion/component
identities, chain and iteration IDs, priors, diagnostic warnings and producer hashes.
The ML/REML report retains covariance estimates, the joint information-based
uncertainty when available, balanced ANOVA mean squares when applicable,
identities, optimization diagnostics and producer hashes.
Reopening either report or changing D-study counts does not rerun estimation.
Keep the SHA-256 receipt separately.
The R wrapper supports Gaussian ML/REML through
`fit_mgmfrm(data, model="gtheory", method="reml", score=c("Content", "Organization"),
facets=c(rater="Rater", task="Task"), counts=list(rater=1:6, task=c(1L,2L)))`.
One score name requests a univariate analysis. `plot(result, type="variance")`,
`type="covariance"` and `type="dstudy"` draw stored estimates and confidence
intervals without Julia. `vcov(result)` is the approximate sampling covariance
of the component estimates. Preserve the complete R object with `saveRDS()`.
Bayesian G-theory is specified through Julia.

After fitting the corresponding one-facet model in R, new designs can be
calculated from its saved object without Julia:

```r
gt_one <- fit_mgmfrm(rater_scores, model="gtheory", method="reml",
                    person="Person", score=c("Content", "Organization"),
                    facets=c(rater="Rater"))
saveRDS(gt_one, "one-facet.rds")
# In a later R session, these operations do not start Julia.
gt_one <- readRDS("one-facet.rds")
d <- diagnostics_mgmfrm(gt_one, "reliability", counts=list(rater=1:8),
                       weights=c(0.6, 0.4), interval_method="exact")
plot(gt_one, type="dstudy", metric="G", counts=list(rater=1:8),
     weights=c(0.6, 0.4), interval_method="exact")
```

Use `interval_method="delta"` for the existing approximation, including
two-facet plans. Nested child counts remain per parent. The covariance and
optimization record are preserved when counts, weights or the confidence level
change. A design grid need not have been supplied at fit time.

For a saved complete balanced two-facet analysis, use:

```r
diagnostics_mgmfrm(gt, "reliability",
  counts=list(rater=1:6, task=1:3), weights=c(0.6, 0.4),
  interval_method="mean_square_region")
plot(gt, type="dstudy", metric="Phi",
  counts=list(rater=1:6, task=1:3), weights=c(0.6, 0.4),
  interval_method="mean_square_region")
```

R uses the same region definition offline and reuses each fixed-score region
across the displayed plans. Figure labels identify the statistical interval
method; the numerical fit qualification remains visible when it needs review.

## Visualize saved results

```julia
using CairoMakie
fig = BayesianMGMFRM.plot(fit_gt; kind=:variance)
save("gstudy-variance.svg", fig)
BayesianMGMFRM.plot(fit_gt; kind=:covariance)
BayesianMGMFRM.plot(fit_gt; kind=:dstudy,
    counts=(rater=1:6, task=[1,2]), score="composite", metric=:Phi,
    weights=[0.6, 0.4])
```

The same plots accept SHA-verified saved reports. Components retain signed
covariances. D-study curves show each declared allocation and pointwise
intervals, with no new fitting or random sampling. Figure captions distinguish
confidence intervals from credible intervals and retain numerical qualification.
By default the full caption is written to `annotation_io=stdout`; use an IO
stream to save it alongside the image, or `annotation_io=nothing` to embed it.
The organization follows mfrmr's component and D-study views; statistical
intervals and warnings refer to the estimator used here.
For a complete one-facet ML/REML fit, `kind=:dstudy, metric=:G` or
`:relative_sem` also accepts `interval_method=:exact`. Empty confidence sets
are identified in the caption and omitted from the interval bars.

```@docs
BayesianMGMFRM.Generalizability.model
BayesianMGMFRM.Generalizability.report
```
