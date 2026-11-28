# Migrating from Stan and brms: Controls, Defaults, and Diagnostics

!!! note "Development manual"
    Use the [matching source and installation instructions](installation.md).
    This manual describes a development snapshot, not an accepted stable release.
    Model support and scientific acceptance remain as stated on each page.

Researchers coming from **`brms`**, **`rstan`**, **`cmdstanr`**, **`cmdstanpy`**,
**`posterior`**, **`loo`**, and **`priorsense`** already know Hamiltonian Monte
Carlo (`NUTS`) concepts such as `adapt_delta`, `max_treedepth`, `E-BFMI`,
split rank-normalized $\hat{R}$, bulk/tail effective sample size (`ESS`), and
Pareto-smoothed importance sampling (`PSIS-LOO`). This specialist reference
provides a complete parameter, default-value, diagnostic, and mathematical
crosswalk between the Stan/`brms` ecosystem and `BayesianMGMFRM.jl`.

For classical measurement software (`FACETS` and `ACER ConQuest`), see the
companion guide [Migrating from FACETS and ACER ConQuest](migration-facets-conquest.md).
To execute custom `.stan` files or import existing CmdStan `.csv` chains directly
into the reporting and plotting pipeline, see
[Custom Stan Adapter and Portable Joint-Draw Handoffs](stan-adapter.md).

## Architectural Separation: Model Specification vs. Sampler Controls vs. Qualification

Unlike `brms::brm(...)`, which bundles formula specification, priors, and MCMC
sampler controls inside one function call, `BayesianMGMFRM.jl` separates three
distinct stages so each stage can be inspected, cached, and audited independently:

1. **Model specification (`mfrm_spec`, `BayesianMGMFRM.Legacy.FacetSpec`, `joint_rating_spec`):**
   Declares only the statistical model: response family, facets, identification
   anchors or sum-to-zero constraints, predictors/random effects, and joint priors.
   Sampler tuning arguments (`target_accept` / `adapt_delta`, `max_depth` / `max_treedepth`)
   are **never** placed inside the model specification.
2. **Sampler execution (`fit`, `cached_fit`, `prepare_fit`, `StanAdapter.fit_stan`):**
   Accepts NUTS execution and adaptation controls (`chains`, `warmup`, `ndraws`,
   `seed`, `target_accept` / `adapt_delta`, `max_depth` / `max_treedepth`,
   `metric`, `step_size`, `init_jitter` / `init_radius`, `chain_execution`).
   After estimation, call `sampler_controls(fit)` to inspect the exact recorded
   settings.
3. **Diagnostics and qualification (`diagnostics`, `qualify`, `posterior_mcse`):**
   Computes post-warmup chain and parameter diagnostics (including Hamiltonian
   Energy-BFMI `e_bfmi` and max-treedepth hits `n_max_treedepth`) and evaluates
   explicit pass/fail gates via `qualify(fit; max_rhat = 1.01, min_ess = 400.0, min_bfmi = 0.30)`.

## Complete Sampler Control Crosswalk (`brms` / `rstan` / `cmdstanr` ↔ `BayesianMGMFRM.jl`)

| Concept | `brms` / `rstan` | `cmdstanr` / CmdStan CLI | `BayesianMGMFRM.jl` canonical keyword (and accepted alias) | Critical behavioral notes |
| --- | --- | --- | --- | --- |
| **Warmup transitions per chain** | `warmup = 1000` | `iter_warmup = 1000` / `num_warmup=1000` | `warmup = 1000` | Adaptation transitions per chain; excluded from retained posterior draws. |
| **Retained draws per chain** | `iter = 2000` (**total** = `warmup + retained`!) | `iter_sampling = 1000` / `num_samples=1000` | **`ndraws = 1000`** | **Important:** Like `cmdstanr` (`iter_sampling`), `ndraws` is **post-warmup retained draws per chain**, *not* `rstan`/`brms` total `iter`. `chains = 4, warmup = 1000, ndraws = 1000` retains `4,000` draws. |
| **Number of chains** | `chains = 4` | `chains = 4` | `chains = 4` | Use at least `4` chains for substantive inference (`chains = 1` on minimal `BayesianMGMFRM.Legacy.FacetSpec` is only a smoke-check default). |
| **Parallel chain execution** | `cores = 4` | `parallel_chains = 4` | `chain_execution = :threads, max_parallel_chains = 4` | Start Julia with `julia -t 4` (uses deterministic per-chain seed partitioning). |
| **NUTS engine selection** | `backend = "rstan"` or `"cmdstanr"` | CmdStan binary | **`backend = :advancedhmc`** (native Julia NUTS) or **`:cmdstan`** | On minimal 1D `BayesianMGMFRM.Legacy.FacetSpec` / `BayesianMGMFRM.Legacy.FacetDesign`, the legacy default `backend = :julia` is random-walk Metropolis; **explicitly pass `backend = :advancedhmc` or `:cmdstan` for NUTS.** Generalized `mfrm_spec` routes use NUTS automatically. |
| **Dual-averaging target acceptance ($\delta$)** | `control = list(adapt_delta = 0.95)` | `adapt_delta = 0.95` / `adapt engaged=1 delta=0.95` | **`target_accept = 0.95`** *(alias: **`adapt_delta = 0.95`**)* | Controls step-size adaptation in $(0, 1)$. Passing `adapt_delta` works across all Bayesian `fit`, `cached_fit`, and `StanAdapter.fit_stan` routes and prints an informational hint pointing to `target_accept` help. Supplying both raises `ArgumentError`. |
| **Maximum binary-tree depth ($d$)** | `control = list(max_treedepth = 12)` | `max_treedepth = 12` / `engine=nuts max_depth=12` | **`max_depth = 12`** *(alias: **`max_treedepth = 12`**)* | Caps leapfrog steps per transition at $2^{d} - 1$. Passing `max_treedepth` works as an alias across all NUTS routes and prints an informational hint pointing to `max_depth` help. Supplying both raises `ArgumentError`. |
| **Euclidean mass matrix** | `control = list(metric = "diag_e")` / `"dense_e"` | `metric = "diag_e"` / `"dense_e"` | `metric = :diagonal` or `:dense` (`:unit` where supported) | Stan 3-stage Welford variance/covariance adaptation during warmup. |
| **Initial step size ($\epsilon_0$)** | `control = list(stepsize = 0.05)` | `step_size = 0.05` | `step_size = 0.05` (or `0.03` on generalized routes) | Starting point for dual-averaging step-size adaptation. |
| **Random initialization spread** | `init = 2` (uniform in $[-2, 2]$ on unconstrained scale) | `init = 2` | `init_jitter` (`fit`) / `init_radius` (`StarAssociation`, `StanAdapter.fit_stan`) | Check the route docstring (`?fit`, `?StanAdapter.fit_stan`) for exact initialization geometry. |
| **Reproducible RNG seed** | `seed = 20261118` | `seed = 20261118` | `seed = 20261118` | Required for exact replay, `cached_fit`, and `StanAdapter.fit_stan` (`sig_figs=18` bit-exact output). |

### Alias Behavior and Interactive Help Guidance

If you write `adapt_delta` or `max_treedepth` out of habit from `brms` or Stan:

```julia
fitted = fit(spec;
    backend = :advancedhmc,
    chains = 4,
    warmup = 1000,
    ndraws = 1000,
    adapt_delta = 0.95,
    max_treedepth = 12,
    seed = 20261118,
)
```

`BayesianMGMFRM.jl` accepts both aliases, maps them to `target_accept = 0.95`
and `max_depth = 12` (producing identical draws and identical `fit_cache_key`
hashes), and emits a concise `@info` reminder pointing to `target_accept` /
`max_depth` and `?BayesianMGMFRM.fit` so scripts can standardize on the canonical
names over time. Supplying both `target_accept` and `adapt_delta` (or both
`max_depth` and `max_treedepth`) in the same call raises a deterministic
`ArgumentError`.

## Default NUTS Settings by Model Family and Their Mathematical Rationale

In `rstan`, `cmdstanr`, and `brms`, the global default is `adapt_delta = 0.80`
and `max_treedepth = 10` (Hoffman & Gelman, 2014). While `0.80` is optimal for
well-conditioned log-concave posteriors, hierarchical variance components,
random slopes, zero-one-inflated boundaries, and copula or mixture likelihoods
exhibit spatially varying curvature (Neal's funnel and boundary log-odds
compression) that routinely cause divergent transitions at `0.80` — prompting
`brms` users to rerun with `control = list(adapt_delta = 0.90)` or `0.95`.

`BayesianMGMFRM.jl` sets route-specific defaults matched to each family's
posterior geometry while keeping `max_depth = 10` ($2^{10} - 1 = 1,023$ leapfrog
steps) uniform across all NUTS routes:

| Model route / entry point | Default `target_accept` (`adapt_delta`) | Default `max_depth` (`max_treedepth`) | Default `chains`, `warmup`, `ndraws` | Geometric rationale |
| --- | --- | --- | --- | --- |
| **Minimal 1D MFRM / RSM / PCM** (`fit(BayesianMGMFRM.Legacy.FacetSpec / BayesianMGMFRM.Legacy.FacetDesign; backend = :advancedhmc \| :cmdstan \| :turing)`) | **`0.80`** | **`10`** | `chains = 1` (override to `>= 4`), `warmup = 1000`, `ndraws = 1000` | Fixed normal prior scales on an identified linear-logit manifold yield near-Gaussian posterior curvature, matching Stan's standard `0.80` optimality target. |
| **Star-factorized multi-criterion association** (`fit(joint_rating_spec(...; association = :star))`) | **`0.85`** | **`10`** | `chains = 4`, `warmup` & `ndraws` required explicitly | Combines log-normal scale priors, LKJ Cholesky factors, and event-level residual association factors; `0.85` balances step size against moderate hierarchical curvature. |
| **Generalized additive, explanatory, random-slope, bounded (`ZOIB`), count (`beta_binomial`), mixed-outcome, copula, 3D, drift, and mixture routes** (`fit(mfrm_spec(...))`, `Experimental.fit` candidates) | **`0.90`** | **`10`** | `chains`, `warmup`, `ndraws`, `seed` required explicitly (or `chains = 4` on `Concurrent`) | Hierarchical precision/scale parameters, random-slope LKJ Cholesky blocks, `ZOIB` boundary submodels, and `CriterionCollapse` mixtures induce funnel curvature; starting at `0.90` avoids routine first-pass divergences. Explicit iteration arguments prevent short pilot settings from being mistaken for substantive defaults. |
| **Custom Stan adapter** (`StanAdapter.fit_stan`) | **`0.90`** | **`10`** | `chains = 4`, `warmup = 1000`, `ndraws = 1000`, `seed` required | User-authored `.stan` measurement models typically contain hierarchical facets or non-standard priors; `0.90` matches standard hierarchical Stan practice and can be lowered (`0.80`) or raised (`0.95`–`0.99`) explicitly. |

## Diagnostics and Qualification Crosswalk (`CmdStan` / `posterior` ↔ `diagnostics` & `qualify`)

### 1. Mapping Sampler Telemetry and Convergence Metrics

Every NUTS fit records per-iteration Hamiltonian telemetry and aggregates chain
and parameter diagnostics using the modern split rank-normalized definitions of
Vehtari et al. (2021):

| Stan / CmdStan CSV / `posterior` quantity | `diagnostics(fit)` location and field | `qualify(fit)` default pass condition | Notes |
| --- | --- | --- | --- |
| `rhat` (split rank-normalized $\hat{R}$) | Parameter rows: `rank_normalized_rhat` | **`<= 1.01`** (`max_rhat = 1.01`) | Checked across all estimable raw, model-scale, and conditional-location coordinates; structurally fixed anchors are marked `:structurally_fixed` and excluded from extrema. |
| `ess_bulk`, `ess_tail` | Parameter rows: `bulk_ess`, `tail_ess` | **`>= 400.0`** (`min_ess = 400.0`) | **Both** `bulk_ess` and `tail_ess` must meet `min_ess` on every estimable parameter. |
| `divergent__` ($0/1$ per post-warmup draw) | Chain sampler rows: `n_divergences` | **`== 0`** | Any retained divergent transition fails `sampler_gate_passed` and `qualified`. Warmup divergences are recorded separately (`sampler_diagnostics(fit; phase = :warmup)` on `BayesianMGMFRM.Legacy.MFRMFit`). |
| `treedepth__` vs. `max_depth` | Chain sampler rows: `n_max_treedepth`, `mean_tree_depth`, `max_tree_depth` | **`n_max_treedepth == 0`** | Counts retained transitions where `tree_depth >= max_depth` (premature trajectory termination / U-turn not reached). When importing external CSVs via `StanAdapter.import_csv` that were sampled with `max_treedepth != 10`, pass `metadata = (max_depth = 12,)` (or `max_treedepth = 12`) so hit counting uses the run's actual cap. |
| `energy__` → **Energy-BFMI (`BFMI`)** | Chain sampler rows: **`e_bfmi`** (plus whole-fit minimum `e_bfmi` and `e_bfmi_complete`) | **`>= 0.30`** on **every** chain (`min_bfmi = 0.30`; aliases `ebfmi_min`, `bfmi_min`) | Measures momentum resampling efficiency across energy levels (see formula below). Missing or incomplete chain energy telemetry fails `qualify` rather than passing silently. |
| `accept_stat__`, `stepsize__`, `n_leapfrog__` | Chain sampler rows: `acceptance_rate`, `step_size` / `mean_step_size`, `mean_n_steps` | Informational (checked for finiteness) | Confirms dual-averaging convergence near `target_accept`. |

### 2. Understanding Energy-BFMI (`e_bfmi` and `min_bfmi = 0.30`)

For chain $c$ with retained Hamiltonian total energies $E_{c,1}, \dots, E_{c,S}$
(`energy__` in CmdStan), the empirical **Energy Bayesian Fraction of Missing
Information** (Betancourt, 2016, 2017) is:

$$\text{E-BFMI}_{c} = \frac{\sum_{t=2}^{S} (E_{c,t} - E_{c,t-1})^2}{\sum_{t=1}^{S} (E_{c,t} - \bar{E}_{c})^2}, \qquad \bar{E}_{c} = \frac{1}{S}\sum_{t=1}^{S} E_{c,t}.$$

In the Stan ecosystem, two warning conventions appear historically: `rstan::check_energy`
originally flagged $\text{E-BFMI} < 0.20$, whereas CmdStan's `diagnose` utility
and `cmdstanr` flag $\text{E-BFMI} < 0.30$ because values between $0.20$ and
$0.30$ already indicate sluggish exploration of heavy-tailed or funnel energy
marginal distributions. `BayesianMGMFRM.jl` adopts **`min_bfmi = 0.30`**
uniformly across all routes in `qualify(fit; min_bfmi = 0.30)` (with `ebfmi_min`
and `bfmi_min` accepted as aliases). If a model exhibits low `e_bfmi`, consider
non-centered vs. centered parameterization (`coordinates`) or stronger scale
priors rather than merely increasing `max_depth`.

Whole-fit `qualify(fit)` is necessary but not sufficient for reporting a
specific substantive contrast or classification cutoff: always inspect
`posterior_mcse(fit)` (mean, SD, and quantile Monte Carlo standard errors) for
the focal estimands of your study.

## Model Parameterization, `loo`, and `priorsense` Crosswalk

1. **Adjacent-category sign and anchor conventions (`brms::acat` vs. MFRM):**
   - `brms` `family = acat("logit")` parameterizes category-specific thresholds
     with linear predictors added ($\eta_n - \tau_k$), and random effects `(1 | rater)`
     are zero-mean hierarchical normal effects with estimated standard deviations.
   - Standard MFRM (`BayesianMGMFRM.Legacy.FacetSpec` and finite-panel `mfrm_spec`) subtracts rater
     severity and item difficulty ($\theta_p - \xi_r - \delta_i - \tau_k$) under
     explicit sum-to-zero or reference-level constraints (`anchors`), placing
     normal priors directly on the identified free coordinates (or hierarchical
     population priors when declared in `ExplanatoryTarget`). Because changing a
     reference anchor without transforming the prior changes the induced joint
     prior distribution, align both the likelihood gauge and the joint prior
     before expecting posterior equivalence between `brms`/Stan and `BayesianMGMFRM.jl`
     (see [Migrating from FACETS and ACER ConQuest](migration-facets-conquest.md)).
2. **Predictive model comparison (`loo` ↔ `psis_loo`, `waic`, `criteria`, `compare_models`):**
   - `psis_loo(fit)` and `waic(fit)` correspond to `loo::loo()` and `loo::waic()`,
     reporting `elpd_loo` / `elpd_waic`, effective parameter counts, and per-unit
     Pareto-$\hat{k}$ diagnostics.
   - `compare_models(["M1" => fit1, "M2" => fit2]; criterion = :psis_loo)`
     computes pairwise $\Delta\text{ELPD} \pm \text{SE}$ like `loo::loo_compare()`,
     while additionally enforcing cryptographic `observation_binding` and
     evaluation-unit (`:rating` vs. `:event` vs. `:performance` / `:profile`)
     compatibility so models evaluated on different units cannot be accidentally
     compared. When Pareto-$\hat{k} > 0.7$ occurs on clustered or persistent-effect
     models, use `loo_refit_plan` or cluster quadrature (`criteria(...; integrate = ...)`).
3. **Prior sensitivity (`priorsense` ↔ `prior_sensitivity`):**
   - `prior_sensitivity(fit, ...)` performs PSIS importance-sampling reweighting
     under alternative prior specifications (using native Julia `logprior`
     differences or declared `log_prior` / `alt_log_priors` columns in
     `StanAdapter`), flagging Pareto-$\hat{k} > 0.7$ cases as unreliable so
     high-dimensional prior shifts are refit directly rather than extrapolated.

## Side-by-Side Translation Example (`brms` → `BayesianMGMFRM.jl`)

Suppose in R (`brms` with `cmdstanr`) you run a 4-chain NUTS fit with tightened
adaptation controls:

```r
# R (brms): iter = 2000 includes 1000 warmup + 1000 post-warmup draws per chain
fit_brms <- brm(
  score ~ 1 + (1 | person) + (1 | rater) + (1 | item),
  data = ratings_df,
  family = acat("logit"),
  chains = 4, iter = 2000, warmup = 1000, cores = 4, seed = 20261118,
  control = list(adapt_delta = 0.95, max_treedepth = 12)
)
```

In `BayesianMGMFRM.jl`, specify the rating design/model first, then run `fit`
with `ndraws = 1000` (retained post-warmup draws per chain) and inspect
`diagnostics`, `qualify`, and `sampler_controls`:

```julia
using BayesianMGMFRM
using BayesianMGMFRM.GlassBox

fd = FacetData(ratings_table;
    person = :person, rater = :rater, item = :item, score = :score,
    category_levels = [0, 1, 2])
spec = mfrm_spec(fd; thresholds = :rating_scale)

# Canonical keywords (`target_accept`, `max_depth`); `adapt_delta` and `max_treedepth` also work as aliases
fit_jl = fit(spec;
    backend = :advancedhmc,
    chains = 4,
    warmup = 1000,
    ndraws = 1000,
    target_accept = 0.95,
    max_depth = 12,
    chain_execution = :threads,
    seed = 20261118,
)

sampler_controls(fit_jl)
diag = diagnostics(fit_jl)
gate = qualify(fit_jl; max_rhat = 1.01, min_ess = 400.0, min_bfmi = 0.30)
posterior_summary(fit_jl)
```

For a runnable [grouped Bayesian rating model](equating-and-populations.md), compare the shared item calibration, conditional ability distribution and joint group contrast. The [category design](design-matrix-mrcml.md) gives the measurement predictor.
