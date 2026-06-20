# Examples

The repository keeps runnable examples small enough for local API checks and
the pre-registration gate. These scripts are not publication-grade analyses;
they are compact workflow smoke tests that exercise the public surfaces
described in the [Bayesian Fitting](fitting.md) page.

## Minimal MFRM Workflow

[`examples/minimal.jl`](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/blob/main/examples/minimal.jl)
runs the fit-supported MFRM/RSM/PCM path. It covers:

- long-format data construction with [`FacetData`](@ref);
- pre-fit validation via [`validate_design`](@ref);
- specification and design inspection via [`mfrm_spec`](@ref) and
  [`getdesign`](@ref);
- prior predictive checks, cached fitting, fit artifacts, and diagnostics;
- posterior summaries, WAIC rows, calibration rows, and posterior predictive
  summaries.

Use this script when checking the ordinary public fitting workflow.

## Guarded Fixed-Q MGMFRM Workflow

[`examples/guarded_mgmfrm.jl`](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/blob/main/examples/guarded_mgmfrm.jl)
runs the guarded fixed-Q confirmatory MGMFRM path. It covers:

- a two-dimensional `family = :mgmfrm` spec with a fixed item-by-dimension
  `q_matrix`;
- preview design and constraint inspection before fitting;
- opt-in fitting through `fit(spec; experimental = true)`;
- guarded [`MGMFRMFit`](@ref) metadata, fit artifacts, sampler diagnostics,
  posterior summaries, WAIC rows, and posterior predictive summaries.

Use this script when checking the narrow experimental MGMFRM entrypoint. It
does not support exploratory loadings, free latent correlations, dimensions
beyond two, model-weight claims, or sparse-superiority claims.
