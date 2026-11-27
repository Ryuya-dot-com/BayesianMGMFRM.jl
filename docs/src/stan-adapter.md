# Custom Stan Adapter and Portable Joint-Draw Handoffs

!!! note "Development manual"
    Use the [matching source and installation instructions](installation.md).
    This manual describes a development snapshot, not an accepted stable release.
    Model support and scientific acceptance remain as stated on each page.

Researchers who author custom Stan programs (`.stan`) or already hold CmdStan
output chains (`.csv`) can feed their posterior draws directly into the
post-estimation diagnostics, contrasts, cohort summaries, predictive model
comparison, prior-sensitivity reweighting, visualization, and reproducible
persistence tools of `BayesianMGMFRM.jl` through **`BayesianMGMFRM.StanAdapter`**. For a side-by-side mapping of
Stan/`brms` sampler controls (`adapt_delta` ↔ `target_accept`,
`max_treedepth` ↔ `max_depth`), route-specific defaults, and `E-BFMI`
qualification thresholds, see
[Migrating from Stan and brms](migration-stan-brms.md).

Alongside source-bound native caches (`save_fit` / `load_fit`),
**`BayesianMGMFRM.PortableHandoff`** freezes a versioned, SHA-256-sealed JSON
joint-draw interchange (`"bayesianmgmfrm.portable_joint_draws_handoff.v1"`) that
transports exact IEEE-754 `Float64` `chain × iteration × parameter` draws,
NUTS sampler telemetry, optional pointwise `log_lik` and `log_prior` evaluations,
and producer provenance across processes and Julia versions without requiring
native `Serialization` compatibility.

## Design Boundaries (Explicit Roles, Zero Guessing)

`StanAdapter` enforces strict methodological transparency:

1. **No arbitrary `.stan` syntax parser:** Stan compiles and runs the `.stan`
   program natively via CmdStan (`StanAdapter.fit_stan`), or `StanAdapter.import_csv`
   reads existing CmdStan `.csv` chain files directly.
2. **No implicit variable-name guessing:** Every parameter block (`person`,
   `rater`, `item`, `thresholds`, or user-named blocks), fixed anchor, optional
   pointwise `log_lik` block (with explicit `unit = :rating | :event | :performance | :performance_rater`
   and observation IDs), and optional joint `log_prior` column must be declared
   explicitly in `roles`.
3. **Bit-level provenance and reproducibility:** Every `StanAdapter.Fit` records
   SHA-256 digests of the `.stan` source, input data JSON, compiled executable,
   and per-chain `.csv` outputs, plus CmdStan/Julia/package versions and integer
   seed.

## Fitting a Custom `.stan` Program (`StanAdapter.fit_stan`)

Suppose `custom_rsm.stan` defines person abilities `theta[1..P]`, free rater
severities `rater_free[1..R-1]` (or reconstructed `rater[1..R]` in
`generated quantities`), item difficulties `item[1..I]`, step thresholds
`step[1..K-1]`, plus `log_lik[1..N]` and `log_prior` in `generated quantities`:

```julia
using BayesianMGMFRM, CairoMakie
const SA = BayesianMGMFRM.StanAdapter

roles = (
    parameters = (
        person = ["theta.$p" for p in 1:P],
        rater = ["rater.$r" for r in 1:R],
        item = ["item.$i" for i in 1:I],
        thresholds = ["step.$k" for k in 1:(K - 1)],
    ),
    fixed = (
        rater = ["rater.1" => 0.0],
    ),
    log_lik = (
        columns = ["log_lik.$n" for n in 1:N],
        unit = :rating,
        dataset_id = "writing_panel",
        observation_ids = ["obs_$n" for n in 1:N],
    ),
    log_prior = "log_prior",
    alt_log_priors = (
        wide_prior = "log_prior_wide",
    ),
)

stan_fit = SA.fit_stan(
    "custom_rsm.stan",
    stan_data_dict;
    roles = roles,
    chains = 4,
    warmup = 500,
    ndraws = 500,
    seed = 20261118,
)
```

If CmdStan `.csv` chain files were already generated externally (via CmdStan,
`cmdstanr`, or `cmdstanpy`), import them directly without re-running MCMC:

```julia
stan_fit = SA.import_csv(
    ["chain_1.csv", "chain_2.csv", "chain_3.csv", "chain_4.csv"];
    roles = roles,
)
```

## Unified Layer-1 Post-Estimation Analysis

Once wrapped as `StanAdapter.Fit`, the standard Layer-1 verbs dispatch directly:

- **Convergence and NUTS telemetry:** `diagnostics(stan_fit)` and
  `qualify(stan_fit; max_rhat = 1.01, min_ess = 400.0, min_bfmi = 0.30)` evaluate
  split rank-normalized $\hat{R}$, bulk/tail ESS, divergences, max-treedepth hits,
  and chain E-BFMI (`accept_stat__`, `stepsize__`, `treedepth__`,
  `n_leapfrog__`, `divergent__`, `energy__`).
- **Summaries, contrasts, and cohort decisions:**
  - `posterior_summary(stan_fit; interval = 0.95)` and `posterior_mcse(stan_fit)`
  - `facet_summary(stan_fit; facet = :rater)`
  - `contrast(stan_fit; left = "rater.2", right = "rater.3", rope = (-0.2, 0.2))`
  - `ranking(stan_fit; facet = :person, top_k = 3)`
  - `reliability(stan_fit; facet = :person, target = :centered)`
  - `classification(stan_fit; cutoff = 0.0, pass_probability = 0.80)`
- **Predictive criteria and model comparison (when `roles.log_lik` is declared):**
  - `waic(stan_fit)` (for conditionally independent `:rating` or `:event` units),
    `psis_loo(stan_fit)`, and `criteria(stan_fit)`
  - `compare_models(["RSM" => rsm_stan_fit, "PCM" => pcm_stan_fit]; criterion = :psis_loo)`,
    which verifies identical `unit` and `observation_binding` hashes before
    computing $\Delta\text{ELPD} \pm \text{SE}$.
- **PSIS prior-sensitivity reweighting (when `roles.log_prior` is declared):**
  - `prior_sensitivity(stan_fit, :wide_prior)` (using a column declared in
    `roles.alt_log_priors`, an explicit vector `"wide" => alt_lp_vec`, or a
    draw function) applies Pareto-smoothed importance sampling (`PSIS`) to
    estimate shifted posterior means and credible intervals and flags high
    Pareto-$\hat{k}$ values (`> 0.7`) that require direct refitting.
- **Figures (`BayesianMGMFRM.plot`):**
  - `BayesianMGMFRM.plot(stan_fit; kind = :posterior)`
  - `BayesianMGMFRM.plot(stan_fit; kind = :diagnostics, parameters = ["rater.2", "item.2"])`
  - `BayesianMGMFRM.plot(stan_fit; kind = :wright)`
  - `BayesianMGMFRM.plot(cmp_rep; kind = :comparison)`
  - `BayesianMGMFRM.plot(sens_rep; kind = :prior_sensitivity)`

Generative operations that require evaluating a Julia likelihood on new data
(`coordinates`, `logdensity_and_gradient`, `stan_data`, `predictive_check`,
`event_probabilities`, `category_summary`) raise a deterministic `ArgumentError`
explaining that `StanAdapter.Fit` wraps external draws without parsing `.stan`
likelihood code.

## Portable Joint-Draw Handoff (`PortableHandoff`)

Native `.jls` files (`save_fit` / `load_fit`) bind to the exact producing Julia
and package versions. When archiving draws across Julia upgrades or sharing
exact `chain × iteration × parameter` matrices across machines, export a
versioned portable joint-draw handoff:

```julia
const PH = BayesianMGMFRM.PortableHandoff

handoff = PH.export_handoff(fit; scale = :model, include_log_lik = true, include_log_prior = true)
receipt = save_report("analysis_handoff.json", handoff; return_receipt = true)

# In a separate process or newer Julia version:
restored = load_report("analysis_handoff.json"; expected_sha256 = receipt.sha256)
qualify(restored)
posterior_summary(restored)
contrast(restored; left = "rater[2]", right = "rater[3]")
```

`load_report` requires the separately retained `expected_sha256` file receipt
and independently recomputes the embedded canonical `handoff_hash` over all
draws, chain/iteration indices, NUTS sampler telemetry, fixed parameters,
`log_lik`, and `log_prior` arrays, guaranteeing bit-exact (`0.0` ULP) IEEE-754
`Float64` restoration and refusing any mutated payload.

## Frozen `model × operation` Contract Matrix

Use `BayesianMGMFRM.ModelOperationMatrix.audit()` to inspect the machine-readable
table (`schema = "bayesianmgmfrm.model_operation_matrix.v1"`) listing all 21
model and interchange routes, their support tier, prediction unit, PSIS
estimator, and Layer-1 / Layer-2 operation availability.
