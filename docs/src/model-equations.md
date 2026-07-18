# Model Equations

`BayesianMGMFRM.jl` keeps model-equation metadata separate from fitting
availability. The [`model_equation`](@ref) contract records the intended family,
category kernel, primary-source references, required parameter blocks,
identification restrictions, implementation gaps, and whether a specification is
fit-ready.

The current public fitting surface is the minimal MFRM/RSM/PCM slice plus
guarded experimental generalized candidates: the scalar rater-consistency
GMFRM path and the fixed-Q confirmatory MGMFRM path with `dimensions >= 2`.
Broader GMFRM/MGMFRM specifications expose source-aligned manifests and preview
compiler rows for review, while broad generalized fitting remains guarded or
under development as described in [Scope and Releases](scope.md).

## Source Map

- Partial-credit lineage: Masters (1982), DOI
  [`10.1007/BF02296272`](https://doi.org/10.1007/BF02296272).
- Rating-scale lineage: Andrich (1978), DOI
  [`10.1007/BF02293814`](https://doi.org/10.1007/BF02293814).
- Generalized MFRM target: Uto and Ueno (2020), DOI
  [`10.1007/s41237-020-00115-7`](https://doi.org/10.1007/s41237-020-00115-7).
- Multidimensional generalized MFRM target: Uto (2021), DOI
  [`10.1007/s41237-021-00144-w`](https://doi.org/10.1007/s41237-021-00144-w).

See [API](api.md) for the rendered [`model_equation`](@ref) docstring.
