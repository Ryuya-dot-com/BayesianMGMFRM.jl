# Examples

The repository keeps runnable examples compact. These scripts are learning and
verification examples rather than substantive analyses; they exercise the public surfaces
described in the [Bayesian Fitting](fitting.md) page.

## Minimal MFRM Workflow

[`examples/minimal.jl`](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/blob/main/examples/minimal.jl)
runs the fit-supported MFRM/RSM/PCM path. It covers:

- long-format data construction with [`FacetData`](@ref);
- pre-fit validation via [`validate_design`](@ref);
- specification and design inspection via [`mfrm_spec`](@ref) and
  [`getdesign`](@ref);
- prior predictive checks, cached fitting, fit artifacts, fit reports, and
  diagnostics;
- posterior summaries, WAIC rows, calibration rows, and posterior predictive
  summaries.

Use this script to learn the ordinary supported fitting workflow.

## Guarded Scalar GMFRM Workflow

[`examples/guarded_gmfrm.jl`](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/blob/main/examples/guarded_gmfrm.jl)
runs the guarded scalar rater-consistency GMFRM path. It covers:

- a compact one-dimensional example with partial-credit thresholds and
  `discrimination = :rater`;
- preview design and constraint inspection before fitting;
- opt-in fitting through `BayesianMGMFRM.Experimental.fit(spec)`;
- guarded [`GMFRMFit`](@ref) metadata, fit artifacts, fit reports, sampler
  diagnostics, posterior summaries, WAIC rows, and posterior predictive
  summaries.

Use this script to learn the narrow experimental scalar GMFRM entrypoint. It
does not support item discrimination, multidimensional ability, rating-scale
generalized kernels, fitted DFF terms, or broad generalized-model claims.

## Guarded Fixed-Q MGMFRM Workflow

[`examples/guarded_mgmfrm.jl`](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/blob/main/examples/guarded_mgmfrm.jl)
runs the guarded fixed-Q confirmatory MGMFRM path. It covers:

- a compact two-dimensional example of the `family = :mgmfrm` guarded path,
  using a fixed item-by-dimension `q_matrix`;
- preview design and constraint inspection before fitting;
- opt-in fitting through `BayesianMGMFRM.Experimental.fit(spec)`;
- guarded [`MGMFRMFit`](@ref) metadata, fit artifacts, fit reports, sampler
  diagnostics, posterior summaries, WAIC rows, and posterior predictive
  summaries.

Use this script to learn the narrow experimental MGMFRM entrypoint. It
does not support exploratory loadings, free latent correlations, model-weight
claims, or sparse-superiority claims.
