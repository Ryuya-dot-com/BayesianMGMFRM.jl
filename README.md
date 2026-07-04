# BayesianMGMFRM.jl

[![CI](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/workflows/CI.yml)

`BayesianMGMFRM.jl` is a conservative Julia package for Bayesian many-facet
Rasch measurement workflows. It is designed for rating data where people,
raters, items, categories, and optional grouping variables all matter, and where
model checks are as important as posterior summaries.

The current public release focuses on a reliable first workflow:

- normalize long-format rating data into stable facet indexes;
- validate connectedness, sparse cells, skipped categories, and design rank
  before fitting;
- inspect many-facet Rasch design matrices, constraints, thresholds, and model
  manifests;
- fit minimal MFRM/RSM/PCM models with Bayesian samplers;
- summarize diagnostics, posterior measures, predictive checks, calibration,
  WAIC/LOO inputs, rater diagnostics, DFF screening rows, and report bundles;
- explore narrow guarded GMFRM/MGMFRM experiments without broadening public
  claims beyond their validation evidence.

The package is intentionally explicit about scope. Minimal MFRM/RSM/PCM fitting
is the fit-supported surface. Scalar rater-consistency GMFRM, configured through
the compatibility keyword `discrimination = :rater`, and fixed-Q confirmatory
MGMFRM with `dimensions >= 2` are available only through guarded experimental
paths. Broader generalized discrimination, exploratory MGMFRM, free latent
correlations, modeled DFF effects, sparse-superiority claims, and public
model-weight claims remain out of scope.

## Installation

Until the package is registered in Julia General, install it directly from
GitHub:

```julia
using Pkg
Pkg.add(url = "https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl")
```

After General registration, use:

```julia
using Pkg
Pkg.add("BayesianMGMFRM")
```

The package currently supports Julia `1.10.8` and later Julia 1.x releases.

## First Run

This tiny example keeps sampler settings deliberately small so the whole
workflow is quick to inspect. Increase `ndraws`, `warmup`, and `chains` for
real analysis.

```julia
using BayesianMGMFRM
using Random

ratings = (
    examinee = ["E1", "E1", "E1", "E1", "E2", "E2", "E2", "E2"],
    rater = ["R1", "R2", "R1", "R2", "R1", "R2", "R1", "R2"],
    item = ["I1", "I1", "I2", "I2", "I1", "I1", "I2", "I2"],
    group = ["A", "A", "B", "B", "B", "B", "A", "A"],
    score = [0, 1, 2, 0, 1, 2, 0, 2],
)

data = FacetData(ratings;
    person = :examinee,
    rater = :rater,
    item = :item,
    score = :score,
    group = :group,
)

validation = validate_design(data; bias = [(:rater, :group)])
spec = mfrm_spec(data; thresholds = :partial_credit, validation_report = validation)
design = getdesign(spec)

println(validation)
println(design)
println(design.parameter_names)

prior = MFRMPrior()
fit_result = fit(spec;
    prior,
    backend = :julia,
    ndraws = 8,
    warmup = 8,
    chains = 2,
    step_size = 0.1,
    seed = 20260621,
)

posterior_summary(fit_result)
diagnostics(fit_result)

ppc = posterior_predictive_check(fit_result;
    ndraws = 8,
    rng = MersenneTwister(20260622),
)
predictive_check_summary(ppc)

report = fit_report(fit_result;
    include_prior_predictive = true,
    prior_predictive_ndraws = 8,
    rng = MersenneTwister(20260623),
    artifact_include_environment = false,
)
fit_report_sections(report)
```

For a fuller script with cache exports, diagnostic tables, calibration, WAIC,
and report-bundle examples, see [`examples/minimal.jl`](examples/minimal.jl).

## What You Get

`BayesianMGMFRM.jl` is organized around the workflow a measurement reviewer
usually wants to see.

**Data and design**

- `FacetData` turns long-format ratings into deterministic person, rater, item,
  category, and optional metadata indexes.
- `validate_design` checks category support, connectedness, singleton levels,
  sparse DFF cells, and design rank before a sampler is started.
- `mfrm_spec`, `getdesign`, `constraint_table`, `model_manifest`,
  `design_row_table`, `linear_predictor_table`, and `threshold_map_data` make
  the design contract inspectable.
- `coverage_summary`, `coverage_matrix`, `rater_overlap`,
  `anchor_linking_summary`, and `rating_design_audit` help review whether the
  data can support the intended comparison.

**Bayesian fitting**

- `fit` supports minimal MFRM/RSM/PCM models with `backend = :julia`,
  `backend = :advancedhmc`, or `backend = :turing`.
- `cached_fit`, `fit_cache_key`, `save_fit_cache`, and `load_fit_cache` provide
  same-environment recomputation control.
- `MFRMPrior`, `MFRMLogDensity`, `initial_params`, `loglikelihood`,
  `logprior`, and `logposterior` expose the likelihood/prior target for review
  and external sampler experiments.

**Diagnostics and reporting**

- `fit_metadata`, `sampler_diagnostics`, `mcmc_diagnostics`,
  `parameter_block_diagnostics`, and `diagnostics` summarize sampler and chain
  quality.
- `posterior_summary`, `fair_average_summary`,
  `separation_reliability_summary`, `rater_diagnostics`, `residual_summary`,
  `fit_stats`, and `wright_map_data` produce report-ready measurement rows.
- `prior_predictive_check`, `posterior_predictive_check`,
  `predictive_check_summary`, `calibration_table`, `waic_diagnostics`,
  `loo_diagnostics`, `psis_loo`, `kfold`, and `compare_models` support the
  Bayesian workflow around the fitted object.
- `fit_artifact`, `fit_report`, `save_fit_report`, `save_fit_report_tables`,
  `save_fit_report_markdown`, `save_fit_report_bundle`, and
  `fit_report_dossier` create hash-checked artifacts for local review.
- `evidence_artifact_schema_policy` records the required provenance fields for
  schema versioning, content hashes, package/git/environment hashes, seed and
  sampler controls, cache provenance, blocked claims, and raw-data status.

**Validation and reproducibility**

- `simulate_responses`, `simulation_grid`, `parameter_recovery`, and
  `parameter_recovery_summary` support small recovery studies.
- `stan_validation_row` and `stan_validation_summary` expose committed
  Julia/BridgeStan scalar fixture checks.
- `release_scope_summary` records the current public surface, guarded
  experimental surfaces, blocked claims, and release-readiness guardrails.
- `related_software_capability_matrix` positions Facets, TAM, mirt, sirt,
  immer, brms/Stan workflows, and this package without making replacement or
  superiority claims.
- `release_gate_check` checks that README, roadmap, docs, and manifest status
  rows agree before a release is cut.

## Model Support

| Surface | Status | Entry point | Notes |
| --- | --- | --- | --- |
| Minimal MFRM/RSM/PCM | `supported` | `mfrm_spec`, `getdesign`, `fit` | Main public workflow for current analyses. |
| Scalar rater-consistency GMFRM | `experimental_public` | `mfrm_spec(...; family = :gmfrm, discrimination = :rater)`, then `fit(spec; experimental = true)` | Narrow guarded source-aligned candidate; `discrimination = :rater` is the compatibility keyword for the positive rater-consistency multiplier. |
| Fixed-Q confirmatory MGMFRM | `experimental_public` | `mfrm_spec(...; family = :mgmfrm, dimensions = D, q_matrix = Q)`, then `fit(spec; experimental = true)` | Guarded fixed Q-mask candidate for `D >= 2`; identity latent correlation only. |
| Broader GMFRM/MGMFRM, DFF model effects, exploratory Q-matrices | `blocked` | Manifest and preview inspection only where available | Not a public fit API until identification, diagnostics, validation, and reporting contracts are stronger. |

The guarded MGMFRM example is runnable at
[`examples/guarded_mgmfrm.jl`](examples/guarded_mgmfrm.jl).

## Reading Path

- Start with [`examples/minimal.jl`](examples/minimal.jl) if you want a runnable
  end-to-end example.
- Read [`docs/src/data-validation.md`](docs/src/data-validation.md) when you
  are preparing a rating dataset.
- Read [`docs/src/fitting.md`](docs/src/fitting.md) for sampler choices,
  guarded generalized caveats, and reporting helpers.
- Read [`docs/src/model-equations.md`](docs/src/model-equations.md) for the
  source-traced likelihood contracts.
- Read [`docs/src/roadmap.md`](docs/src/roadmap.md) for the conservative scope
  boundary and future MGMFRM promotion gates.
- Read [`docs/src/registration.md`](docs/src/registration.md) for the manual
  Julia General handoff boundary.

## Development Checks

For ordinary local verification:

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
julia --project=docs docs/make.jl
```

Before requesting Julia General registration, run the stricter local gate:

```bash
julia --startup-file=no scripts/pre_registration_gate.jl
```

The gate checks temporary-environment import, package tests, examples,
documentation rendering, Aqua package hygiene, project metadata, whitespace,
public wording, and skipped-test scans. CI runs the hygiene subset in a lighter
mode because package tests and docs are separate jobs, and the stricter public
wording scan remains a manual pre-registration check.

The repository also includes a manual handoff helper:

```bash
julia --project=. scripts/registration_handoff.jl --strict
```

It verifies the release boundary and prints the Registrator comment. It does not
call GitHub, Registrator, General, or any publication endpoint.

## Manifest and Cache Policy

Package `Manifest.toml` files are intentionally ignored for Julia General
registration. The package gate develops the repository in fresh temporary
environments so local manifests do not affect registration checks.

Serialized fit caches from `cached_fit` are for same-environment recomputation
avoidance. For durable review, keep the `model_manifest`, `fit_artifact`,
exported summaries, report bundles, source data, and exact code version with
the analysis.

## Citation

If you use `BayesianMGMFRM.jl`, please cite the package metadata in
[`CITATION.cff`](CITATION.cff):

```text
Ryuya Komuro. BayesianMGMFRM.jl: Bayesian many-facet Rasch measurement in
Julia, version 0.1.0. https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl
```

## License

MIT License. See [`LICENSE`](LICENSE).
