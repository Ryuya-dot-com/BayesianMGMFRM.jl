# BayesianMGMFRM.jl

BayesianMGMFRM.jl is a Julia package for Bayesian many-facet Rasch
models, generalized MFRM, and multidimensional GMFRM workflows.

The package is under active development. The current release keeps a scalar
MGMFRM analytic log-density validation target and reproducibility metadata
utilities stable while the public data/spec API is being built.

## Installation

Until the package is registered:

```julia
using Pkg
Pkg.add(url = "https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl")
```

After General registration:

```julia
using Pkg
Pkg.add("BayesianMGMFRM")
```

## Minimal Example

```julia
using BayesianMGMFRM

meta = evidence_metadata(; include_packages = false)
meta["software"]["julia"]["version"]
```

See [`examples/minimal.jl`](examples/minimal.jl) for the same minimal example as
a script.

## Development Status

The planned public API will use domain-oriented names such as `fit`, `audit`,
`simulate`, `posterior_summary`, `FacetData`, `FacetSpec`, and `FacetDesign`
rather than repeatedly prefixing function names with the package name.

Current registration checklist:

- Package name: `BayesianMGMFRM`
- Repository name for General: `BayesianMGMFRM.jl`
- License: MIT
- Initial version: `0.1.0`
- Tests: `Pkg.test()` passes locally
- Load check: `import BayesianMGMFRM` passes locally

## License

MIT License. See [`LICENSE`](LICENSE).
