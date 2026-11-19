# Installation

Use **Julia 1.10.8 or newer** and source snapshot **`20261119-distribution-ci-freeze`**,
matching this manual. This is package **0.1.2 (unreleased)**, a development
distribution rather than a registered General release.

## Install from GitHub

In a dedicated analysis project, install and pin the matching development snapshot branch:

```julia
using Pkg
Pkg.activate("rating-analysis")
Pkg.add(url="https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl",
    rev="development/20261119-distribution-ci-freeze")
Pkg.pin("BayesianMGMFRM")
using BayesianMGMFRM
```

## Install from an extracted source archive

Alternatively, extract the matching source archive (`BayesianMGMFRM-20261119-distribution-ci-freeze`),
start Julia in the directory containing the extracted folder, and run:

```julia
using Pkg
source_dir = abspath("BayesianMGMFRM-20261119-distribution-ci-freeze")
Pkg.activate("rating-analysis")
Pkg.develop(path=source_dir)
using BayesianMGMFRM
pkgdir(BayesianMGMFRM)
```

The final line should show the extracted source folder. `rating-analysis` is
your separate analysis project; keep both folders. If the source folder is
elsewhere, replace `source_dir` with its absolute path. If Julia syntax is new,
the [Julia basics guide](learning-guide.md#julia-for-beginners) explains projects,
paths and help.

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
