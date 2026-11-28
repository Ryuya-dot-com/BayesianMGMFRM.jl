# Installation

## Install the development snapshot

Use Julia 1.10.8 or newer. This manual uses Julia package version
`0.2.0-DEV` at commit `134418dd459267ab4c834cf9ff8f49d71aea9ec5`. Install it in a
dedicated analysis project:

```julia
using Pkg
Pkg.activate("rating-analysis")
Pkg.add(url="https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl",
        rev="134418dd459267ab4c834cf9ff8f49d71aea9ec5")
using BayesianMGMFRM
pkgversion(BayesianMGMFRM)  # v"0.2.0-DEV"
```

Keep the analysis project's `Project.toml` and `Manifest.toml` to reproduce
the dependency versions. Analyses made with the original public solver
snapshot can use `rev="0cea3251a8ef739378c188270a15085aab0777ff"` instead.

## Install from a local source tree

To work on a checkout or an extracted snapshot, use its package directory
in a separate project:

```julia
using Pkg
Pkg.activate("rating-local")
Pkg.develop(path=abspath("path/to/BayesianMGMFRM.jl"))
using BayesianMGMFRM
pkgdir(BayesianMGMFRM)  # local source directory
```

Keep the local source and its Git revision or archive checksum alongside
the analysis environment. For an introduction to Julia projects, see the
[Julia basics guide](learning-guide.md#julia-for-beginners).

**Continue to [Your First Rating Analysis](first-analysis.md).** Its supplied
figures can also be read without installing or running Julia.

## Return to the same project

In a later session, start Julia from the same directory and run:

```julia
using Pkg
Pkg.activate("rating-analysis")
using BayesianMGMFRM
```

For a local source installation, activate `rating-local` instead.
Historical native fits require the original complete environment. See
[saved-result reproduction](api-saved-reporting.md#saved-result-reproduction).

## Optional plotting and other backends

The supplied figures need no plotting package. To draw new figures from your
own supported fit, run `Pkg.add("CairoMakie")` in your analysis project, then
`using CairoMakie`. The [figure recipe](examples.md#first-analysis-own-figures)
shows how to create the tutorial's selection from your own fit.
Turing is optional; install it only when choosing that
[fitting backend](fitting.md#Backends-and-Sampler-Controls).

The declared Julia minimum is not evidence of every platform/operation
combination. See the [recorded compatibility scope](api-saved-reporting.md#What-the-development-version-has-actually-verified)
when selecting an environment for an existing fit.
