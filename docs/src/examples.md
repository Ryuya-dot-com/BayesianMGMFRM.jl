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

## Synthetic paired-criterion ratings

[`examples/synthetic_paired_ratings.jl`](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/blob/main/examples/synthetic_paired_ratings.jl)
generates one pronunciation example with artificial persons, words, raters and
responses. Run it from the repository root:

```sh
julia --project=. examples/synthetic_paired_ratings.jl
```

The example has 12 persons, 37 words, 19 raters and two criteria: ease of
understanding and weak accent. Both scores range from 0 to 8, with higher scores
indicating more of the named property. The design includes repeated ratings of
the same recording, unequal word coverage, two sparsely covered words and a
small amount of missingness in the first criterion. No empirical file is read.
These counts and generating constants illustrate a design, rather than a
recommended sample size or estimates from real speakers.

The printed output directory contains `ratings.json` (observed long-form
ratings), `recordings.json` (all possible person–word cells and their assignment),
`truth.json` (generating effects, correlations, complete assigned ratings and
category probabilities), and `manifest.json` (seeds, equation, counts and file
checksums). Missing first-criterion scores leave the second criterion intact;
absent recordings are not assigned score zero. An optional argument selects a
new output directory; existing directories are not overwritten.

Person correlation is 0.6 and residual recording correlation is 0.25. Recording
effects are shared across raters, rater severity varies by criterion, and steps
are shared across words within each criterion. These are generating conditions,
not fitting priors. The realized correlation among 12 persons will differ from
the population correlation. The script draws no posterior samples: the current
MGMFRM fitting interface does not represent this complete recording/criterion
structure. Use the example to inspect known truth and data handling; it does not
establish parameter recovery or conclusions about real speakers.

## Fixed-coefficient multidimensional MFRM

[`examples/multidimensional_mfrm.jl`](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/blob/main/examples/multidimensional_mfrm.jl)
fits two named dimensions through `BayesianMGMFRM.Experimental.fit` and saves
the fit and a report. Use either backend, optionally adding figures with CairoMakie:

```sh
julia --project=. examples/multidimensional_mfrm.jl
julia --project=. examples/multidimensional_mfrm.jl --cmdstan --plots
julia --project=. examples/multidimensional_mfrm.jl --correlated --plots
julia --project=. examples/multidimensional_mfrm.jl --correlated --prior-only --plots
julia --project=. examples/multidimensional_mfrm.jl --exchangeable --correlated --plots
```

Its fixed Q assigns items 1–2 to reasoning and items 3–4 to communication.
Active coefficients and rater consistency are one; person/item locations use
zero-centered priors, rater severities sum to zero, and latent correlation is
identity. `MFRMPrior` sets standard deviations on free unit-logit coordinates.
The [experimental guide](experimental.md#Fixed-coefficient-multidimensional-MFRM)
explains the model and limits. Add `--correlated` to estimate population rho
with an LKJ(2) prior on either backend; its figures show rho and its chains.
Ability-pair marginal standard deviations remain fixed prior inputs.
Add `--exchangeable` to use an exchangeable zero-sum rater prior with kernel
SD 0.4 for either model/backend. This selects
[`Experimental.ExchangeablePrior`](experimental.md#Exchangeable-rater-prior)
for both the prior check and the fit; the default remains `MFRMPrior`.

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
[saved-fit report example](api-fitting-artifacts.md#Experimental-saved-multidimensional-MFRM-reports).
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

## Explicit normalized-prior MGMFRM workflow

[`examples/normalized_mgmfrm.jl`](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/blob/main/examples/normalized_mgmfrm.jl)
is a self-contained two-dimensional, fixed-Q example with estimated positive
loadings and identity latent correlation:

```sh
julia --project=. examples/normalized_mgmfrm.jl
# With CairoMakie installed in the analysis environment:
julia --project=. examples/normalized_mgmfrm.jl --figures
```

It specifies all six normalized exchangeable-prior scales, inspects prior rating
implications, and fits with the explicit location coordinates. Two chains with
10 warmup and 12 retained draws demonstrate the interface; their warnings remain
visible and these settings are insufficient for inference. The script prints
model-scale summaries and Monte Carlo errors, saves to a new directory under
`results/normalized_mgmfrm/`, and checks metadata, summaries and diagnostics after
reloading `fit.jls`.

The optional person and loading-diagnostic figures use the reloaded fit and the
named `reasoning` dimension. The report reader verifies the exported bundle;
report completeness does not mean MCMC diagnostics passed. This workflow uses
AdvancedHMC. See the [explicit prior contract](experimental.md) for the separate
raw-coordinate CmdStan route and the meaning of the illustrative scales.

## Correlated MGMFRM Workflow

[`examples/correlated_mgmfrm.jl`](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/blob/main/examples/correlated_mgmfrm.jl)
constructs a two-dimensional pure-Q panel, explicitly chooses `GeneralizedPrior`,
simulates prior rating implications, fits the population correlation with
estimated loadings/consistency, and prints diagnostics, rho precision and a
conditional posterior-predictive comparison. It verifies the same MCSE,
category probabilities and seeded score replications after save/reload, then
saves and reopens a reader-facing report with tables.

```sh
julia --project=. examples/correlated_mgmfrm.jl
```

Add `--cmdstan` to use the matching backend. The example uses only 10 warmup and
12 retained iterations in each of two chains; the resulting warnings must not
be interpreted as inferential acceptance. Each run prints a new directory under
`results/correlated_mgmfrm/` containing `fit.jls` and a `report/` bundle.
Add `--figures` in an environment containing CairoMakie to include loading,
rho-diagnostic, prior and predictive PDF/SVG figures with their numerical inputs.
The result is `Experimental.CorrelatedMGMFRMFit`. Prediction concerns the existing
rating design; agreement does not establish performance for new persons, items
or raters. See the
[model and prior explanation](experimental.md#Correlated-MGMFRM:-explicit-fitting-and-saved-results).

## Saved Generalized Fits and Figures

This section applies to scalar GMFRM and independent fixed-Q `MGMFRMFit` results.

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

### Review a saved MGMFRM fit without fitting

[`review_saved_mgmfrm.jl`](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/blob/main/examples/review_saved_mgmfrm.jl)
starts from an existing independent fixed-Q MGMFRM cache. Use the same Julia
analysis environment that reads the cache, with CairoMakie and JSON3 available.
JSON3 writes the diagnostic supplement. Find the
stored dimension labels with `fit_metadata(load_fit_cache("analysis-fit.jls");
view = :public).dimension_labels`, then pass one of those labels:

Running the script without arguments or with `--help` prints usage without
loading a cache or requiring the plotting packages.

```sh
julia --project=. examples/review_saved_mgmfrm.jl \
  analysis-fit.jls results/saved_mgmfrm_review communication
```

Replace `communication` with the actual label and choose a new output directory
for each review. Missing or incompatible caches produce an error; this example
does not call `fit`, `cached_fit`, or refresh a cache. The correlated MGMFRM
result type has its own [saved-result workflow](experimental.md#Correlated-MGMFRM:-explicit-fitting-and-saved-results).

Read the output in this order:

1. `README.md` shows the whole-fit and finite-panel location diagnostic status.
   Inspect both, including the separate warmup history in `review.json`.
   Good location-difference diagnostics do not clear whole-fit warnings.
2. `report/fit_report.md` contains model-scale 90% credible intervals and a
   posterior figure for all fitted persons in the selected dimension. The
   diagnostic figure shows the active loadings in that dimension, with all
   retained chains and the whole-fit warning. PDF, SVG and numerical inputs
   are saved under `report/figures/`.
3. `review.json` retains all model-scale posterior summaries and their mean,
   SD, median and interval-endpoint Monte Carlo errors. Match rows by
   `parameter`; credible intervals describe posterior uncertainty, while MCSE
   describes error in its numerical calculation. Unavailable MCSE remains
   unavailable, and this example applies no precision acceptance threshold.
4. The predictive figure compares category proportions on the existing rating
   rows with 200 posterior replications, using seed 42 and 90% predictive
   intervals. This does not assess held-out ratings or new persons, items or
   raters. Calibration, WAIC and LOO are not requested in this walkthrough.

Parameter summaries and MCSE use every retained draw. Prediction alone
resamples 200 joint draws. The supplement is necessary because the ordinary
independent-MGMFRM report does not automatically include location diagnostics
or MCSE. It also records the input cache SHA256 and the analysis settings.
The example verifies that the cache bytes are unchanged and reopens the report
bundle to verify its manifest-listed files. `README.md` and `review.json` sit
outside that bundle's verification scope.

To regenerate the same numerical figure inputs, rerun with the same cache,
dimension, script and Julia environment, writing to a new directory. Report
completeness means that the requested sections were produced; diagnostic
warnings remain visible, and a complete report is not scientific acceptance.

### Compare abilities or raters in a saved MGMFRM fit

Use a joint posterior contrast to ask whether two fitted persons differ within
one dimension, or whether two raters differ in severity or consistency.
Subtract the two values **at each retained draw**: subtracting marginal
interval endpoints or independently shuffling the columns loses their posterior
dependence. For example, the variance of a difference includes minus twice the
covariance, even when the population ability prior has identity correlation.

[`saved_mgmfrm_contrasts.jl`](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/blob/main/examples/saved_mgmfrm_contrasts.jl)
provides an includable example for independent fixed-Q MGMFRM caches from either
backend. It uses Statistics and the package's existing MCMCDiagnosticTools
dependency; no renderer is needed. From the repository root:

```julia
include("examples/saved_mgmfrm_contrasts.jl")
restored = load_fit_cache("analysis-fit.jls")
ability = saved_mgmfrm_contrast(restored; kind = :ability,
    left = "P1", right = "P2", dimension = "communication")
severity = saved_mgmfrm_contrast(restored; kind = :severity,
    left = "R1", right = "R2")
consistency = saved_mgmfrm_contrast(restored; kind = :log_consistency_ratio,
    left = "R1", right = "R2", rope = (-log(1.25), log(1.25)))
ability.summary
consistency.summary.event_rows
```

Replace the person/rater labels and dimension with those in your saved data.
The example rejects unknown levels, a missing ability dimension, a dimension
selector on rater parameters, self-comparisons, and altered chain ordering.
It keeps all retained draws and the original fit's diagnostic assessment.
These helpers are example code, not additional package fitting APIs.

Positive contrasts mean that the left person has higher ability, the left
rater is more severe, or the left rater has larger consistency. The consistency
contrast is `log(left) - log(right)`: zero means equal multipliers. Its
`ratio_interval` exponentiates the log-scale median and interval endpoints;
this is not a posterior mean ratio, and its MCSE remains on the log scale.
Unrepresentable ratio endpoints are marked unavailable.

Ability-difference magnitudes use the saved model's ability unit. A common
origin shift cancels, but positive rescaling multiplies the difference and
any nonzero ROPE bounds; the sign is invariant. Item-location differences
require additional care when loadings differ: even their sign can depend on
the ability origin. See [Estimands, origins and units](@ref "Estimands, origins and units")
before interpreting contrasts across models or prior settings. Invariance of
a contrast does not make its posterior independent of the chosen prior.

`summary` contains a central 90% credible interval by default, mean/SD and
quantile MCSE, and rank-normalized split R-hat plus bulk/tail ESS for the
contrast itself. Inspect those diagnostics as well as `whole_fit_diagnostics`;
one contrast cannot clear warnings elsewhere. Short or constant sequences keep
unavailable diagnostics and precision. No new acceptance threshold is applied.

An optional two-bound `rope` specifies a practically negligible range on the
**contrast's scale**. The illustrative consistency bounds above correspond to
ratios from 0.8 to 1.25; they are not a recommended tolerance. Justify bounds
before inspecting the posterior, or omit them. Event rows report the posterior
fraction above zero and, if requested, below/inside/above the ROPE, with MCSE
computed from the ordered indicator draws. All-zero or all-one indicators retain
unavailable MCSE: an observed fraction of zero or one is not proof of exact
posterior certainty. No equivalence decision, multiplicity adjustment, or rater
reliability classification is made. A contrast still depends on the fitted
model, prior and rating design; it does not establish agreement on future scores.
