# BayesianMGMFRM.jl

`BayesianMGMFRM.jl` is an early Julia package scaffold for many-facet Rasch
measurement workflows.

The current public slice focuses on:

- long-format rating data via [`FacetData`](@ref);
- pre-fit design validation via [`validate_design`](@ref);
- minimal MFRM specification and design inspection via [`mfrm_spec`](@ref) and
  [`getdesign`](@ref);
- fit-independent reporting data via [`coverage_summary`](@ref),
  [`coverage_matrix`](@ref), [`rater_overlap`](@ref), and
  [`threshold_map_data`](@ref);
- scalar log-density validation against Julia and BridgeStan fixtures.

Bayesian fitting, generalized discrimination terms, group/DFF model terms, and
Multidimensional Generalized Many-Facet Rasch Model (MGMFRM) fitting APIs are
planned work and are not exposed yet.

```@contents
Pages = ["data-validation.md", "api.md"]
Depth = 2
```
