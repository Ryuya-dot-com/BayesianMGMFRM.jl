# BayesianMGMFRM for R

Fit Bayesian and frequentist many-facet Rasch (MFRM), generalized many-facet Rasch (GMFRM), and scale-identified multidimensional generalized many-facet Rasch (MGMFRM) models from R data frames via `BayesianMGMFRM.jl`.

## Common-plan Fair Average

For additive MFRM, shared-event MRCML and scale-identified GMFRM/MGMFRM fits, evaluate all people under the same known
facet levels using `diagnostics_mgmfrm(fit, "fair_average", reference_plan=plan)`.
The plan has one column per fitted facet role and optional positive `Weight`.
The result includes joint-posterior expected scores, credible intervals,
MCSE and local R-hat/ESS, together with the original whole-fit qualification.
`threshold` reports an expected-score exceedance probability; a `comparisons`
data frame (`left`, `right`, `margin`) requests paired person differences.
Use `plot(report)` to compare observed and adjusted scores. RDS and portable
R handoffs retain the basis and joint draws for new plans without Julia.
Cells must share a category score scale. Shared-event models require an explicit
`shared_effects="zero"` or `"marginal_new"`; omit shared-event IDs from the plan.
The latter integrates new Gaussian events with a two-order quadrature check.
MGMFRM preserves item loadings, all ability dimensions and rater consistency.
JMLE returns delta-method Wald intervals from the joint person/calibration
covariance, with no posterior probabilities. MMLE averages over the conditional
empirical-Bayes ability distribution while holding calibration and population
parameters fixed; its intervals omit their estimation uncertainty. Both methods
retain their scoring basis in RDS/JSON for new plans without Julia.
Structured facet-by-facet, focal/doubly centered group DFF and facet-by-step
interactions require `interaction_effects="fitted"` or `"zero"`. The latter zeros
interaction terms only when reporting; it retains ability estimates from the
original fitted model. Population-roster group membership is held for each person
and recorded in `held_contexts`, not added to the reference plan. Shared-event
conditioning is chosen separately. LLTM/custom designs and arbitrary combinations
of shared and generalized models remain outside this operation. Interaction fits
use version 2 scoring metadata; update the wrapper before restoring them. Intervals describe expectations, not future ratings.

For FACETS-style marginal Fair-M / Fair-Z on additive 1D MFRM fits (Bayesian or frequentist),
pass `facet` without `reference_plan`: `diagnostics_mgmfrm(fit, "fair_average", facet = "rater", baseline = "sample_mean")`
(or `baseline = "zero_origin"`, supplying `step_group` under mixed-category rubrics).
Cell-level residual/DFF tables (`diagnostics_mgmfrm(fit, "pair_bias", pair = c("rater", "item"))`),
cutoff decision risk (`diagnostics_mgmfrm(fit, "classification", cutoff = 0.0, pass_probability = 0.8)`),
and tie-aware cohort rank summaries (`diagnostics_mgmfrm(fit, "ranking", direction = "higher", top_k = 3L)`)
also run offline from saved `mgmfrm_r_fit` objects and portable handoffs.

## Quick Start

Install Julia 1.10.8 or newer. Download and extract the
[R wrapper snapshot](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/archive/refs/tags/snapshot-v0.2-20261128-r3.tar.gz).
From its root directory, install the R package and connect to Julia:

```r
install.packages(c("JuliaConnectoR", "posterior", "jsonlite", "digest"))  # once
install.packages("interfaces/R/BayesianMGMFRM", repos = NULL, type = "source")

library(BayesianMGMFRM)
setup_mgmfrm()

ratings <- read.csv(system.file("extdata", "ratings.csv", package = "BayesianMGMFRM"))
fit <- fit_mgmfrm(ratings, 0:3)

print(fit)
summary(fit)
contrast_mgmfrm(fit, facet = "rater", a = "R2", b = "R1")
diagnostics_mgmfrm(fit, type = "fit_statistics", facet = "rater")
diagnostics_mgmfrm(fit, type = "reliability")
```

The R wrapper is version `0.2.0`. Its default setup installs the Julia
`0.2.0-DEV` engine at commit `850721b6546da993152e31c6755f289b5bdef592`.
After fitting, `fit$metadata$bridge_source` records this SHA and
`fit$metadata$package_version` records the Julia package version.

## Key Capabilities (`v0.2.0`)

- **Isometric Default 1D MFRM (`identification = "isometric"`)**: Uses label-permutation-invariant orthonormal Helmert zero-sum bases on measurement facets and category thresholds (marginal prior SD 1.0) while absorbing cohort location and ability spread into `population_mean` (`Normal(0, 2.5)`) and `residual_sd[person]` (`HalfNormal(1.0)`). Inspect the stored prior summary with `print(fit)` or `diagnostics_mgmfrm(fit, "prior")`. Pass `identification = "reference"` only for legacy backward comparisons.
- **Arbitrary Facets, Thresholds, and Multi-Group Designs**: Declare custom measurement facets with `facets = c(item = "item", rater = "rater", task = "task")`, choose rating scale vs. partial credit thresholds via `steps = "global"` or `steps = "item"` (or `"rater"`), pass a named list of consecutive integer scales in `category_levels` (e.g., `list(Content = 0:3, Delivery = 0:5)` under `steps = "item"`) for mixed-category rubrics, supply `fixed_calibration = list(facets = ..., groups = ...)` (`identification = "isometric_fixed_calibration"`) for hard facet locations or unweighted subset-mean/sum constraints (kept distinct from person-population `group = "cohort"`), and pass optional `response_id` / `assessment_id` columns for event-dependence auditing (when omitted, event membership is reported as unknown).
- **Orthogonal Estimation Engines (`method`)**: The default `"nuts"` (Bayesian No-U-Turn Sampler) is the sole estimator for `"gmfrm"` and `"mgmfrm"` models; for 1D `model = "mfrm"`, `"mmle"` (marginal maximum likelihood) and `"jmle"` (joint maximum likelihood) are explicit frequentist alternatives whose constrained-subspace covariance matrix (`vcov(fit)`) propagates off-diagonal zero-sum covariances into `contrast_mgmfrm()`.
- **Generalized and Multidimensional Extensions (`model`)**: Fit `model = "gmfrm"` with explicit `slope = "rater"`, `"item"`, or `"both"` for scale-identified isometric GMFRM across `steps = "global"`, `"item"`, or `"rater"` (leaving `slope = NULL` retains the legacy `steps = "rater"` kernel), or fit `model = "mgmfrm"` with a binary item-by-dimension matrix `Q` (supporting `rownames(Q)` item alignment and `colnames(Q)` dimension labels), `steps = "global"`, `"item"`, or `"rater"`, `scale_identification = "geometric_mean_one"` (default) or `"anchor_item"`, `correlation = "independent"` or `"lkj"`, `logit_scale = 1.0` or `1.7`, `rater_slope_scope = "entire_linear_predictor"` or `"ability_only"`, and `aggregation = "additive"` or `"softmin"`.
- **Offline Persistence and Verified Portable Handoffs**: Every `mgmfrm_r_fit` object embeds posterior summaries, covariances, Bayesian posterior-integrated vs. plug-in fit statistics, and reliability summaries so `print()`, `summary()`, `coef()`, `vcov()`, `diagnostics_mgmfrm()`, and `contrast_mgmfrm()` work after `saveRDS()` / `readRDS()` without an active Julia session. Use `receipt <- handoff_mgmfrm(fit, path, return_receipt = TRUE)` and `read_handoff_mgmfrm(path, expected_sha256 = receipt$sha256)` to verify file SHA-256, embedded `payload_sha256`, array dimensions, and complete `(iteration, chain)` coverage before summarizing. Earlier `r_portable_fit.v2` files without `payload_sha256` still enforce strict dimension, length, finiteness, and covariance-symmetry checks.

## Local Julia Source Setup

By default, `setup_mgmfrm()` installs the pinned repository commit. To run against the local Julia package tree accompanying this wrapper, start a fresh R session at the repository root and call:

```r
setup_mgmfrm(
  project = file.path(tools::R_user_dir("BayesianMGMFRM", "cache"), "local-v02"),
  source_dir = "."
)
```

Inspect `diagnostics_mgmfrm(fit, "qualification")` and `diagnostics_mgmfrm(fit, "sampler")` before interpreting substantive parameter contrasts.

<a id="shared-personrater-or-persontestlet-effects-experimental"></a>

### Shared person/rater or person/testlet effects

```r
# Each pair ID is shared across criteria, and unique across people and raters.
ratings$event <- as.character(interaction(ratings$person, ratings$rater, drop = TRUE))
shared <- fit_mgmfrm(ratings, category_levels = 0:4,
  facets = c(item = "item", rater = "rater", event = "event"), steps = "global",
  assessment_id = "event", random_effects = "event",
  random_sd_prior = "half_normal", random_sd_scale = 1,
  chains = 4L, warmup = 1000L, draws = 1000L)
summary(shared)
saveRDS(shared, "shared.rds")
handoff_mgmfrm(shared, "shared.json")
```

For a person/testlet effect, construct person/testlet pair IDs instead. These
are zero-mean Gaussian shared effects, with HalfNormal or Half-t (4 degrees of
freedom) SD priors. Without groups, person residual SD uses `ability_sd_prior` and the free
intercept has a Normal(0, 2.5) prior. With groups, `group_sd_prior` controls
the group ability scales. The model requires replicated event IDs
and distinguishable covariance components. Person draws are deviations; add
the joint `population_mean` draws for absolute ability in an ungrouped model.
This route uses isometric MFRM with NUTS and can combine group effects, DFF on
finite facets, and fixed calibration of finite facets. Infit/Outfit, Q3 and
reliability tables are populated; residual checks condition on fitted shared
effects. A shared facet cannot also own thresholds or fixed DFF/anchor terms.
Grouped models report person locations including the population mean. Original
ID dictionaries and offline R/JSON handoff remain available.

A continuous SD prior gives `Pr(SD > 0) = 1` even without an effect. Use credible
upper bounds or probabilities relative to a stated meaningful magnitude, with
MCSE, rather than treating positivity as evidence of halo.

### Gaussian G-theory with ML or REML

```r
gt <- fit_mgmfrm(scores, model = "gtheory", method = "reml",
  person = "Person", score = c("Content", "Organization"),
  facets = c(rater = "Rater", task = "Task"),
  counts = list(rater = 1:6, task = c(1L, 2L)), weights = c(.6, .4))
summary(gt)
plot(gt, type = "variance")
plot(gt, type = "covariance")
plot(gt, type = "dstudy", metric = "Phi")
saveRDS(gt, "gtheory.rds")
```

One score column fits univariate G-theory. `nesting = c(rater = "task")`
declares local rater IDs within tasks. JML/MML for ordinal Rasch models are
separate estimators. ML/REML integrates Gaussian random effects exactly and
profiles score means. Scores must be numeric and complete within each observed
person/facet cell; omitted cells must be noninformative for this likelihood.

`coef(gt)` and `vcov(gt)` concern covariance-component estimates and their
approximate sampling covariance. `diagnostics_mgmfrm(gt, "reliability")` returns
the stored D-study scenarios. Plots use saved results and work after `readRDS()`
without Julia. Confidence intervals are pointwise delta approximations, are not
clipped, and are unavailable at covariance boundaries. They are not Bayesian
credible intervals or threshold probabilities.

Change the design or composite weights after saving, without re-estimation:

```r
diagnostics_mgmfrm(gt, "reliability",
  counts = list(rater = 2:8, task = 1:3), weights = c(.8, .2))
plot(gt, type = "dstudy", metric = "G",
  counts = list(rater = 2:8, task = 1:3), weights = c(.8, .2))
```

For complete person × one-facet Gaussian designs, set `interval_method="exact"`
in the diagnostic or D-study plot call to use F intervals for G and chi-square
intervals for relative SEM. Weights must be prespecified. These intervals use
stored mean squares and can remain available at covariance boundaries. Empty
confidence sets remain empty and are reported explicitly. Exact Phi/absolute
SEM intervals and exact intervals for incomplete or two-facet designs are not
provided by this option.

Complete balanced one/two-facet crossed or nested analyses can instead use
`interval_method="mean_square_region"` for G, Phi and both SEM metrics:

```r
plot(gt, type="dstudy", metric="Phi",
  counts=list(rater=1:6, task=1:3), interval_method="mean_square_region")
```

The same option works in `diagnostics_mgmfrm(gt, "reliability", ...)`. Under
independent normal effects, region projections protect future plans and metrics
jointly for each prespecified score/composite, with coverage at least the stated
level. This is not joint coverage across scores or data-selected weights.
Intervals may be wide. Empty regions remain unavailable; incomplete designs or
older reports without ANOVA summaries require a different applicable method.
