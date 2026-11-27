# Installation

Use **Julia 1.10.8 or newer** with the matching **`0.2.0-DEV (unreleased)`**
source tree that accompanies this manual. This is a local development
distribution rather than a registered General release.

## Install from the matching `0.2.0-DEV` source tree

In a dedicated analysis project, develop the local or extracted `0.2.0-DEV`
source folder (`BayesianMGMFRM.jl`, containing `Project.toml` with
`version = "0.2.0-DEV"`):

```julia
using Pkg
source_dir = abspath("path/to/BayesianMGMFRM.jl")  # matching 0.2.0-DEV tree
Pkg.activate("rating-analysis")
Pkg.develop(path=source_dir)
using BayesianMGMFRM
pkgdir(BayesianMGMFRM)
```

The final line should print your `0.2.0-DEV` source folder, and
`isfile(joinpath(pkgdir(BayesianMGMFRM), "examples", "first_analysis_v02.jl"))`
should return `true`. `rating-analysis` is your separate analysis project; keep
both folders. If Julia syntax is new, the
[Julia basics guide](learning-guide.md#julia-for-beginners) explains projects,
paths and help.

!!! note "Do not use the older `0.1.2` GitHub snapshot for this manual"
    The previously published GitHub snapshot branch
    (`development/20261119-distribution-ci-freeze`, package `0.1.2`) predates
    `0.2.0-DEV`, does not include `examples/first_analysis_v02.jl`, and does not
    use the `0.2.0-DEV` isometric `prior = :default` specification. Install from
    the matching `0.2.0-DEV` source tree above (or, once a `0.2.0-DEV` branch or
    tag is published, pin that exact matching revision with `Pkg.add(url=...,
    rev=...)` and `Pkg.pin("BayesianMGMFRM")`).

**Continue to [Your First Rating Analysis](first-analysis.md).** Its supplied
figures can also be read without installing or running Julia.

## Return to the same project

In a later session, start Julia from the same directory and run:

```julia
using Pkg
Pkg.activate("rating-analysis")
using BayesianMGMFRM
```

Keep the source archive/checksum, extracted source, and the analysis project's
`Project.toml` and `Manifest.toml`. A developed package path is mutable; the
manifest alone does not preserve the source. Historical native fits need their
original complete environment: see [saved-result reproduction](api-saved-reporting.md#saved-result-reproduction).

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
