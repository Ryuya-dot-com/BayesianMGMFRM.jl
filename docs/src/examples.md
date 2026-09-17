# Examples

The repository keeps runnable examples compact. These scripts are learning and
verification examples rather than substantive analyses; they exercise the public surfaces
described in the [Bayesian Fitting](fitting.md) page.

## Minimal MFRM Workflow

[`examples/minimal.jl`](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/blob/main/examples/minimal.jl)
runs a stable partial-credit MFRM analysis. From the repository root, after
installing the project's dependencies:

```sh
julia --project=. examples/minimal.jl
```

The script validates the ratings, constructs a specification and calls
`fit(spec; backend = :advancedhmc)` for Julia NUTS. It prints the diagnostic flag,
maximum R-hat, minimum bulk/tail ESS and posterior medians with 95% central
credible intervals. It then saves the fit, reloads it and checks that posterior
summaries are identical. Design inspection and manual cache keys are not required.

The two chains each use only 50 warmup and 50 retained draws. This is a short
workflow demonstration, not a substantive analysis. Inspect any reported
warnings with `diagnostics(fit_result)` when working interactively. A completed
script or successful save/reload does not establish convergence or model validity.

For figures, install CairoMakie in the active Julia environment (for example,
`using Pkg; Pkg.add("CairoMakie")`), then run:

```sh
julia --project=. examples/minimal.jl --plots
```

This mode loads CairoMakie before fitting and generates all figures from the
reloaded fit. The default command does not load a plotting backend. Every run
prints a new output directory under `results/minimal/`, retained after Julia
exits. It contains:

| File | Contents |
| --- | --- |
| `fit.jls` | The fit, retained draws, model/data information and diagnostics |
| `rater-posterior.pdf` | Rater medians and credible intervals, including the fixed reference |
| `rater-chains.pdf` | Retained traces and rank histograms with diagnostic notes |
| `category-predictive.pdf` | Observed versus replicated category proportions, using seed 42 |
| `wright-map.pdf`, `wright-map.svg` | Stable MFRM facet measures and category boundaries on a shared scale |

With the default Julia backend, only `fit.jls` is written without `--plots`.
In a later session, use the printed cache path to regenerate and edit a figure
without running the script or MCMC again:

```julia
using BayesianMGMFRM, CairoMakie
restored = load_fit_cache("results/minimal/<printed-directory>/fit.jls")
figure = BayesianMGMFRM.plot_posterior(restored; block = :rater)
content(figure[2, 1]).xlabel = "Rater severity (logits)"
save("rater-posterior-edited.svg", figure)
```

Replace `<printed-directory>` with the actual directory name. The
[plotting guide](fitting.md#Posterior-interval-figures) explains selection and
intervals; the [reports guide](fitting.md#Reports-and-Reproducibility) covers
the separate report, table and bundle APIs. To export selected figures
with the same report, use the [figure bundle workflow](fitting.md#Reports-with-figures).

With CmdStan configured, add `--cmdstan` (it can be combined with `--plots`):

```sh
julia --project=. examples/minimal.jl --cmdstan --plots
```

The same specification and workflow use `backend = :cmdstan`. Each CmdStan run
gets a new `cmdstan-build/` directory alongside its saved fit; compiled-model
reuse is not attempted. See [backend setup](fitting.md#Backends-and-Sampler-Controls)
for runtime discovery and build requirements. Shared seeds do not imply identical
draws across backends.

## Fixed-coefficient multidimensional MFRM

[`examples/multidimensional_mfrm.jl`](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/blob/main/examples/multidimensional_mfrm.jl)
fits two named dimensions through `BayesianMGMFRM.Experimental.fit` and saves
the fit and a report. Use either backend, optionally adding figures with CairoMakie:

```sh
julia --project=. examples/multidimensional_mfrm.jl
julia --project=. examples/multidimensional_mfrm.jl --cmdstan --plots
julia --project=. examples/multidimensional_mfrm.jl --correlated --plots
julia --project=. examples/multidimensional_mfrm.jl --correlated --prior-only --plots
```

Its fixed Q assigns items 1–2 to reasoning and items 3–4 to communication.
Active coefficients and rater consistency are one; person/item locations use
zero-centered priors, rater severities sum to zero, and latent correlation is
identity. `MFRMPrior` sets standard deviations on free unit-logit coordinates.
The [experimental guide](experimental.md#fixed-coefficient-multidimensional-mfrm)
explains the model and limits. Add `--correlated` to estimate population rho
with an LKJ(2) prior on either backend; its figures show rho and its chains.
Ability-pair marginal standard deviations remain fixed prior inputs.

Before fitting, the script prints prior parameter and rating summaries. Add
`--prior-only` to stop there. `--plots` also saves ability-prior and rating-prior
figures, plus a correlation-prior figure when `--correlated` is selected.

Each fitting run prints a new directory under `results/multidimensional_mfrm/` containing
`fit.jls` and `report/`. The script reloads the fit, checks its metadata and
summaries, and reopens the report bundle, including prior parameter and rating
summaries regenerated from the saved model. `--plots` adds prior figures and reasoning posterior
and chain figures plus category predictive figures in PDF/SVG and their JSON
inputs. Posterior figures use the reloaded fit; users need not reshape MCMC draws.
The posterior intervals are central 90% intervals in unit logits. Fixed
coefficients and derived coordinates are labelled; whole-fit diagnostic warnings
remain visible. Report-only mode and subsequent bundle verification need no renderer.

The 50 warmup and 50 retained draws per chain are solely a workflow demonstration.
A completed report does not establish convergence or scientific validity. To
select another dimension later, load `fit.jls` and follow the
[saved-fit report example](api-fitting-artifacts.md#experimental-saved-multidimensional-mfrm-reports).
Automatic request caching is unavailable for this model; manual save/reload is supported.

## Guarded Scalar GMFRM Workflow

[`examples/guarded_gmfrm.jl`](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/blob/main/examples/guarded_gmfrm.jl)
fits the experimental scalar GMFRM through
`BayesianMGMFRM.Experimental.fit(spec)`:

```sh
julia --project=. examples/guarded_gmfrm.jl
```

Its `discrimination = :rater` configuration estimates positive item
discrimination and rater consistency, with rater-specific partial-credit
steps. The script validates the ratings, prints model-scale posterior summaries
and MCMC diagnostics, then saves and reloads the fit. It does not fit additional
task effects, multidimensional ability, rating-scale generalized kernels or
DFF terms. See the [experimental model guide](experimental.md) for the response
equation, identification and raw-coordinate prior.

## Guarded Fixed-Q MGMFRM Workflow

[`examples/guarded_mgmfrm.jl`](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/blob/main/examples/guarded_mgmfrm.jl)
uses the same experimental entrypoint for two named ability dimensions:

```sh
julia --project=. examples/guarded_mgmfrm.jl
```

Q rows follow `data.item_levels`; its columns follow the declared dimension
labels. The script prints both orders and the matrix before fitting:

| Item | reasoning | communication |
| --- | --- | --- |
| I1 | 1 | 0 |
| I2 | 0 | 1 |

This is a confirmatory between-item example. Active positive item-by-dimension
loadings and rater consistency are estimated even though the compatibility
selector is `discrimination = :none`. Latent correlation is fixed to identity;
item-specific partial-credit steps are used. The two-item toy dataset illustrates
the API and is insufficient for substantive multidimensional conclusions.
Exploratory loadings, free latent correlations, validated bifactor support and
model-weight claims are outside this fitting route. The
[experimental model guide](experimental.md) explains these restrictions.

## Saved Generalized Fits and Figures

Both guarded scripts default to Julia AdvancedHMC/NUTS with two chains, each
using 50 warmup and 50 retained draws. These are short workflow demonstrations;
inspect the printed R-hat, ESS and diagnostic warnings before interpretation.
They use the default generalized prior on raw computational coordinates.
`BayesianMGMFRM.direct_posterior_summary(fit_result)` describes transformed model parameters;
`posterior_summary(fit_result)` retains its raw-coordinate meaning.

The scripts check that model-scale summaries survive save/reload. Each run
prints a retained directory under `results/guarded_gmfrm/` or
`results/guarded_mgmfrm/`. Without plotting, the default Julia run writes only
`fit.jls`. After installing CairoMakie as described above, add `--plots`:

```sh
julia --project=. examples/guarded_gmfrm.jl --plots
julia --project=. examples/guarded_mgmfrm.jl --plots
```

Figures are generated from the reloaded fit, without reshaping draw matrices:

| Script | Model-scale intervals | Raw-coordinate trace/rank diagnostics | Predictive check |
| --- | --- | --- | --- |
| GMFRM | `rater-consistency.pdf`, `.svg` | `rater-chains.pdf` | `category-predictive.pdf` |
| MGMFRM | `ability-posterior.pdf`, `.svg`, with separate named dimensions | `reasoning-chains.pdf`, selecting the reasoning dimension | `category-predictive.pdf` |

The predictive figures compare observed and replicated category proportions
for the same fitted rating rows, using seed 42. Interval bars and predictive
bars describe different uncertainties; none of these figures establishes
convergence. Wright maps are available only for stable MFRM.

To change the dimension shown in a later session, replace the placeholder with
the printed MGMFRM output directory and load the fit in the same Julia analysis
environment:

```julia
using BayesianMGMFRM, CairoMakie
restored = load_fit_cache("results/guarded_mgmfrm/<printed-directory>/fit.jls")
figure = BayesianMGMFRM.plot_posterior(restored; scale = :model,
    block = :person, dimension = "communication")
content(figure[2, 1]).xlabel = "Communication ability"
save("communication-posterior.pdf", figure)
save("communication-posterior.svg", figure)
```

This does not rerun MCMC. For a saved GMFRM fit, select
`block = :rater_consistency` and omit `dimension`.
See the [plotting guide](fitting.md#Posterior-interval-figures) for other selections
and the [reports guide](fitting.md#Reports-and-Reproducibility) for tables and bundles.

Both scripts also accept `--cmdstan`, with or without `--plots`, using the same
specification and a fresh `cmdstan-build/` directory alongside the fit. For example:

```sh
julia --project=. examples/guarded_mgmfrm.jl --cmdstan --plots
```

Configure the runtime using the [backend setup guide](fitting.md#Backends-and-Sampler-Controls).
A shared seed does not imply identical draws across backends. Switching backends
preserves the experimental model restrictions.
