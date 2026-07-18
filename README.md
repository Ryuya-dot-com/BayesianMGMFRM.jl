# BayesianMGMFRM.jl

[![CI](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/workflows/CI.yml)

`BayesianMGMFRM.jl` provides conservative Bayesian workflows for many-facet
Rasch measurement in Julia. It validates long-format rating designs, constructs
identified MFRM/RSM/PCM models, fits them with Bayesian samplers, and produces
diagnostic and reporting tables.

The package deliberately distinguishes supported models from experimental
ones. A successful experimental fit is evidence about that exact configuration;
it is not evidence for broader GMFRM or MGMFRM support.

## Installation

Install the registered release from Julia General:

```julia
using Pkg
Pkg.add("BayesianMGMFRM")
```

To test unreleased development code, install an explicit Git revision:

```julia
using Pkg
Pkg.add(url = "https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl", rev = "main")
```

Pin a commit or tag instead of `main` for reproducible analyses.

## Model Support

| Model surface | Status | Entry point |
|:--|:--|:--|
| MFRM with rating-scale or partial-credit steps | Supported | `mfrm_spec`, `getdesign`, `fit` |
| Scalar rater-consistency GMFRM | Experimental | `fit(spec; experimental = true)` |
| Fixed-Q confirmatory MGMFRM | Experimental | `fit(spec; experimental = true)` |
| Broader discrimination structures | Not supported | Specification review only where documented |
| Exploratory multidimensional loadings or free latent correlations | Not supported | No fitting API |
| Fitted DFF effects | Not supported | Screening and design diagnostics only |

The experimental GMFRM configuration is one-dimensional, uses partial-credit
steps and rater consistency, and does not accept anchors or fitted DFF terms.
The experimental MGMFRM configuration requires at least two dimensions, a
fixed confirmatory Q-matrix, partial-credit steps, identity latent correlation,
no anchors, and no fitted DFF terms.

## Quick Start

```julia
using BayesianMGMFRM

ratings = (
    examinee = ["E1", "E1", "E1", "E1", "E2", "E2", "E2", "E2"],
    rater = ["R1", "R2", "R1", "R2", "R1", "R2", "R1", "R2"],
    item = ["I1", "I1", "I2", "I2", "I1", "I1", "I2", "I2"],
    score = [0, 1, 2, 0, 1, 2, 0, 2],
)

data = FacetData(ratings;
    person = :examinee,
    rater = :rater,
    item = :item,
    score = :score,
)

validation = validate_design(data)
validation.passed || error(validation)

spec = mfrm_spec(data; thresholds = :partial_credit,
    validation_report = validation)
design = getdesign(spec)

fit_result = fit(design;
    backend = :advancedhmc,
    ndraws = 500,
    warmup = 500,
    chains = 4,
    seed = 20260718,
)

diagnostics(fit_result)
posterior_summary(fit_result)
```

Small sampler settings are useful for smoke tests only. Substantive analyses
should predeclare sampler controls, inspect convergence and HMC diagnostics,
and repeat important conclusions under defensible prior and model choices.

## Main Workflow

1. Create `FacetData` from long-format ratings.
2. Run `validate_design` and inspect coverage, connectedness, category use,
   anchors, and optional grouping fields.
3. Create an `mfrm_spec` and inspect `getdesign`, `constraint_table`, and
   `model_manifest` before fitting.
4. Fit the supported model with `fit` or use `cached_fit` when the cache
   identity is part of the reproducibility plan.
5. Review `sampler_diagnostics`, `mcmc_diagnostics`,
   `parameter_block_diagnostics`, posterior predictive checks, calibration,
   and sensitivity results.
6. Export `fit_report(fit; view = :public)` for a portable reader-facing
   structured report, or use a human-readable Markdown summary.

Useful reporting functions include:

- `posterior_summary`, `fair_average_summary`, and
  `separation_reliability_summary`;
- `rater_diagnostics`, `residual_summary`, `fit_stats`, and `wright_map_data`;
- `prior_predictive_check`, `posterior_predictive_check`, and
  `calibration_table`;
- `waic`, `loo`, `psis_loo`, and K-fold helpers with an explicitly stated
  prediction target;
- `fit_report`, `fit_report_public`, `fit_report_markdown`, and report-bundle
  exporters. The full version-1 report remains available for compatibility;
  use the public view for material shared with report readers.

`facets_report` (also available as `facets_compatibility_stats`) returns an
explicitly approximate, unit-weighted posterior-mean plugin table for supported
MFRM/RSM/PCM fits. It does not claim numerical equivalence with FACETS and is
not available for generalized fits.

## Experimental Fixed-Q MGMFRM

```julia
q_matrix = Bool[1 0; 0 1]

mgmfrm_spec = mfrm_spec(data;
    family = :mgmfrm,
    dimensions = 2,
    thresholds = :partial_credit,
    discrimination = :none,
    q_matrix,
    anchors = [],
)

mgmfrm_fit = fit(mgmfrm_spec;
    experimental = true,
    backend = :advancedhmc,
    ndraws = 500,
    warmup = 500,
    chains = 4,
    seed = 20260718,
)
```

This path is confirmatory: the Q-matrix is fixed, dimension labels and gauge
choices must be interpreted explicitly, and exploratory loading claims are out
of scope.

## Documentation

- [Data validation](docs/src/data-validation.md)
- [Model equations](docs/src/model-equations.md)
- [Bayesian workflow](docs/src/bayesian-workflow.md)
- [Bayesian fitting](docs/src/fitting.md)
- [Examples](docs/src/examples.md)
- [Scope and releases](docs/src/scope.md)
- [API overview](docs/src/api.md)
- [Release notes](NEWS.md)

Runnable examples are available in
[`examples/minimal.jl`](examples/minimal.jl),
[`examples/guarded_gmfrm.jl`](examples/guarded_gmfrm.jl), and
[`examples/guarded_mgmfrm.jl`](examples/guarded_mgmfrm.jl).

## Development

For ordinary repository verification:

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
julia --project=docs docs/make.jl
```

The test matrix runs package tests on Julia 1.10.8 and the latest Julia 1.x
release across Ubuntu, macOS, and Windows. Separate jobs build the documentation
and verify examples and release-facing language.

## Citation

If you use the package in research, cite the software version and the primary
measurement-model sources appropriate to your analysis. DOI-traced model
sources are listed in the [model-equation documentation](docs/src/model-equations.md).

## License

MIT License. See [LICENSE](LICENSE).
