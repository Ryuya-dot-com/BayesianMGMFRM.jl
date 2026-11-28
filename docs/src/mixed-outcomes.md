# Mixed-Outcome Speaking Models

!!! note "Mixed-outcome joint model"
    `mfrm_spec(table; outcomes = ...)` is a joint-outcome route
    for speaking and performance studies where each rating event records one or
    more ordinal, bounded (`[lo, hi]` with endpoints), or correct-count outcomes.
    Numerical qualification checks sampler behavior only; inspect paired
    within-event predictive checks, held-performance comparison, and prior
    sensitivity before substantive interpretation.

## When to use this route

Second-language speaking and performance studies often collect heterogeneous
outcomes on the same rating event—for example, a continuous slider rating on
`[0, 100]` with exact `0`/`100` endpoints (`:zero_one_inflated_beta`), an
ordinal comprehensibility scale (`:ordinal`), and transcription word-accuracy
counts (`:binomial` or `:beta_binomial`), sometimes with transcription collected
on only a subset of events (`missing`).

Use `mfrm_spec(table; outcomes = ..., person = ..., facets = ..., population = ...)`
when:

- outcomes mix `:ordinal`, `:zero_one_inflated_beta`, `:binomial`, and
  `:beta_binomial` families on the same event table;
- some rating events observe only a subset of outcomes (`missing` cells on
  unobserved channels, with at least one observed outcome per event);
- speakers, recordings, or listeners share 1D or correlated multi-factor random
  effects (`LKJ(D, eta)` or `0`) mapped to outcomes through explicit fixed or
  estimated loading matrices;
- you need distinct **known-owner** (`mode = :known_owners`) versus
  **new-owner** (`mode = :new_owners`) predictions without substituting zero
  latent effects on nonlinear links.

### Architectural boundary with other multi-outcome routes

Keep the three multi-outcome routes distinct:

1. **`mfrm_spec(...; outcomes = ...)` (this guide):** General event-table mixed
   families (`:ordinal`, `:zero_one_inflated_beta`, `:binomial`,
   `:beta_binomial`), partial-outcome `missing` masks, matrix-driven owner
   dimensions and loadings, held-performance Gauss–Hermite integration, and
   known-owner versus new-owner prediction. Outcomes are conditionally
   independent within an event given all declared owner/performance effects;
   check residual within-event dependence via `paired_cells` in
   `predictive_check`.
2. **[Concurrent Three-Outcome Study](concurrent-three-outcome.md) (`Experimental.ThreeIndicator`):**
   Dedicated model for the two-study `9/9/2` speaking protocol with an explicit
   within-event Plackett copula association parameter.
3. **[Star-Factorized Multi-Criterion Association](star-association.md) (`Experimental.StarAssociation`):**
   Complete-event ordinal/binary multi-criterion rating model with explicit
   root–branch log-odds-ratio association terms.

## Specifying outcomes, owner factors, and loadings

Declare each outcome in `outcomes` with its observation family, column mapping,
explicit priors, and optional `direction` (`:higher_is_more`, default, or
`:higher_is_less` when higher raw scores represent stronger accent or error
severity):

```julia
using BayesianMGMFRM, Distributions

outcomes = (
    accent = (
        family = :zero_one_inflated_beta,
        score = :accent_slider,
        bounds = (0.0, 100.0),
        direction = :higher_is_more,
        intercept = Normal(0.0, 1.5),
        precision = LogNormal(log(12.0), 0.5),
        endpoint_logit = Normal(-2.5, 1.0),
        upper_logit = Normal(0.0, 1.0),
    ),
    comp = (
        family = :ordinal,
        score = :comp_rating,
        categories = 1:5,
        step_sd = 1.0,
        intercept = Normal(0.0, 1.5),
    ),
    intel = (
        family = :beta_binomial,
        score = :words_correct,
        trials = :words_total,
        intercept = Normal(1.0, 1.5),
        precision = LogNormal(log(20.0), 0.5),
    ),
)
```

Every declared owner (`person` and each named facet in `facets`) requires an
explicit entry in `population`:

- **Shared 1D owner (`LogNormal(...)` or positive real SD):** One latent factor
  per owner level enters every outcome with unit loading (`+1` for `person`,
  `-1` for severity facets, multiplied by each outcome's `direction` sign).
- **1D owner with custom outcome loadings:**
  `(sd = LogNormal(...), loadings = (accent = 1.0, comp = LogNormal(0.0, 0.35), intel = LogNormal(0.0, 0.35)))`.
  When `sd` is estimated rather than fixed, at least one outcome loading must
  be fixed to a nonzero constant to anchor latent scale.
- **Multi-factor correlated owner (`dimensions`, `sds`, `correlation`, `loadings`):**

```julia
population = (
    person = (
        dimensions = (:pronunciation, :intelligibility),
        sds = (
            pronunciation = LogNormal(log(0.8), 0.35),
            intelligibility = LogNormal(log(0.8), 0.35),
        ),
        correlation = LKJ(2, 2.0),
        loadings = (
            accent = (1.0, 0.0),
            comp = (LogNormal(0.0, 0.35), 0.0),
            intel = (0.0, 1.0),
        ),
    ),
    recording = LogNormal(log(0.35), 0.35),
    listener = (
        dimensions = (:accent_sev, :comp_sev, :intel_sev),
        sds = (
            accent_sev = LogNormal(log(0.45), 0.35),
            comp_sev = LogNormal(log(0.45), 0.35),
            intel_sev = LogNormal(log(0.45), 0.35),
        ),
        correlation = LKJ(3, 2.0),
        loadings = (
            accent = (1.0, 0.0, 0.0),
            comp = (0.0, 1.0, 0.0),
            intel = (0.0, 0.0, 1.0),
        ),
    ),
)
```

`validate_design(spec)` checks per-outcome fixed-predictor column rank, scale
and sign anchoring of every factor dimension, lower-echelon rotational
restrictions when `Normal` cross-loadings are used, and the grouped Frobenius
Gram rank of owner variance/covariance kernels across observed outcome pairs
(refusing confounded hierarchies such as one-recording-per-speaker or free
correlations between dimensions whose outcomes are never co-observed).

## Joint paired predictive checks and held-performance comparison

- **`prior_predictive_check(spec; ndraws, seed)` and `predictive_check(fit; ndraws, seed)`:**
  Return both per-outcome marginal cells (`report.cells`) and within-event
  paired concordance cells (`report.paired_cells`: `pearson_r`, `spearman_rho`,
  and `centered_covariance` across co-observed outcome pairs). Plot with
  `plot(report; kind = :predictive)`.
- **`criteria(fit; unit = :performance, integrate = :recording)` and `compare_models`:**
  Integrates out the shared 1D or 2D recording/performance factor across all
  observed outcomes and raters of each withheld performance using coarse/fine
  Gauss–Hermite quadrature, retaining known speakers, known listeners, and the
  observed predictor roster. Selective held-performance refits use
  `loo_refit_plan(fit, performance_id; unit = :performance, integrate = :recording)`.
  Event-wise PSIS-LOO (`unit = :event`) is also available when all owner levels
  stay known. Plot with `plot(comparison; kind = :comparison)`.
- **`logprior(fit; components = :factors)` and `prior_sensitivity(fit; powers, estimands)`:**
  Perturbs top-level SD, `LKJ` correlation, free-loading, coefficient, and
  family observation priors without refitting. Mixed-outcome row estimands use
  `(row = 1, outcome = :accent, metric = :expected_score)` or
  `(row = 1, outcome = :comp, category = 5)`.

## Known-owner versus new-owner prediction

On nonlinear logit, ZOIB, and count links, plugging zero into an unobserved
random effect does **not** yield the marginal population expectation. `predict`
therefore separates two explicit contracts:

1. **Known owners (`predict(fit; data, rows, mode = :known_owners)` — default):**
   Conditions on the posterior draws of stored training owners. Any unseen
   owner ID in `data` raises an error rather than substituting zero.
2. **New owners (`predict(fit; data, rows, mode = :new_owners, new_owners = (:person, :recording), seed = 101)`):**
   Integrates over fresh latent owner vectors drawn from the fitted population
   SDs and `LKJ` Cholesky correlation factors at every retained posterior draw,
   while keeping any remaining owners (such as an existing listener panel) at
   their stored posterior draws. Predicting for a new `:person` when a
   `performance` facet is modeled requires including that performance facet in
   `new_owners` as well. Pass `include_predictive = true` to retain single-event
   replicated outcome intervals alongside conditional-expectation credible
   intervals. Scalar `BoundedTarget` and `CountTarget` fits also accept
   `mode = :new_owners` for new iid population owners.
