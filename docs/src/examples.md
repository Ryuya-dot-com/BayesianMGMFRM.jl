# Examples

!!! note "Unreleased documentation preview — 13 October 2026"
    This manual includes unreleased interfaces and examples. It is not the
    documentation of an installed release. Model support and scientific
    acceptance remain as stated on each page.

Install the [matching development preview](index.md#Install-this-development-preview)
first. Repository-relative commands below assume that your working directory is
the source checkout. After `Pkg.add`, locate a shipped example instead with
`include(joinpath(pkgdir(BayesianMGMFRM), "examples", "observed_icc.jl"))`
after `using BayesianMGMFRM`; substitute the desired example filename. An
example that accepts your own cache/output paths still needs those arguments.

## Ordinary binary IRT without raters

**Question: how difficult are items I02 and I03 relative to I01?** The ordinary
Rasch/1PL example uses fixed artificial responses from 24 people to three items,
with scores 0/1. It supplies no rater column and generates no new responses.
Three items give limited information about each person's ability; this small
example demonstrates the analysis steps, not a recommended test length or a
parameter-recovery study.

```julia
using BayesianMGMFRM
include(joinpath(pkgdir(BayesianMGMFRM), "examples", "first_irt_analysis.jl"))
prepared = FirstIRTAnalysis.inputs()  # Inspect input and settings; no fit.
prepared.spec
analysis = FirstIRTAnalysis.main()    # Fit once and save.
```

The input operation is `FacetData(responses; person=:person, item=:item,
score=:score, rater=nothing, category_levels=0:1)`. The existing `mfrm_spec` and
`fit` APIs then use `P(correct) = logistic(ability - difficulty)`, with unit
discrimination, no guessing parameter, and I01 fixed at difficulty zero.
I01 is a reference convention, not an externally calibrated item. The prior
is independent Normal(0, 1.5) for the 24 abilities and Normal(0, 1) for the two
free difficulties. There are no free rater or step parameters. Changing the
reference while simply reusing these independent priors can change the model.
This is Bayesian joint estimation, not conditional maximum likelihood.

Four chains each use 1,000 warmup and 4,000 retained draws. The script saves a
native `fit.jls` before calculating its `answer.json`. It reports 95% intervals
and Monte Carlo errors for P001's ability and the two free difficulties.
Positive difficulty means harder than I01; an interval crossing zero leaves
that direction unresolved. The numerical check requires the whole-fit diagnostic
gate (R-hat at most 1.01 and bulk/tail ESS at least 400, with sampler checks),
mean MCSE at most 0.01 and each focal interval-endpoint MCSE at most 0.03 logit.
These are example computational tolerances, not scientific effect thresholds.
Keep warnings and unqualified results; successful computation alone does not
establish model fit, prior suitability or interval calibration.
The qualification shown by this example concerns its three focal quantities.
In the local reference run they all pass, while eight other person intervals
miss the same endpoint tolerance. Inspect `posterior_mcse(fitted)` for every
parameter; passing focal checks does not qualify every ability interval.

Reopen a trusted saved fit in the same source/dependency environment:

```julia
cache = joinpath(analysis.directory, "fit.jls")
fitted = load_fit_cache(cache)
posterior_summary(fitted)
posterior_mcse(fitted)
review = FirstIRTAnalysis.main(["--saved-fit", cache])  # No refitting.
```

For your own data, preserve the explicit `rater=nothing` choice, use
`validate_design` and `mfrm_spec`, select priors and sampler settings, then call
`fit(spec; ...)`. The ordinary [score and information functions](score-information.md)
also apply to this unit-slope model. Existing reference tables use one fixed-zero
`no_rater` level internally; it does not represent an observed judge. This entry
does not provide free-discrimination, guessing or multidimensional IRT.

## First MFRM analysis

**Question: is R2 more severe than R1 after accounting for the people and tasks
they rated?** Follow this example before exploring the other model families.
It uses 72 supplied artificial ratings from 12 people, four items and three
raters, on categories 0–3. The ratings are fixed: running the example does not
generate a new dataset. This is a teaching example, not a study of real raters.
To run the same analysis one operation at a time, follow the
[connected API walkthrough](bayesian-workflow.md#connected-analysis). Choose that
route or the complete script below; there is no need to fit both.

### Run the analysis

After installing this checkout as described on the home page, run in Julia:

```julia
using BayesianMGMFRM
include(joinpath(pkgdir(BayesianMGMFRM), "examples", "first_analysis.jl"))
analysis = FirstMFRMAnalysis.main()
```

Including the file only defines the example's functions. The last line performs
the fit and saves the result. From the source checkout, the equivalent command is
`julia --project=. examples/first_analysis.jl`.

The example checks the data and fits a one-dimensional partial-credit MFRM.
Each item has its own category steps. R1 defines zero rater severity, so
`rater[R2]` is the R2−R1 contrast: positive means R2 is more severe, negative
means R2 is less severe. Scores and logits are different units; a difference of
0.180 logit does not mean 0.180 score points.

R1's zero is a reference convention, not a claim that R1 is unbiased or an
external calibration. See [references and anchors](learning-guide.md#references-and-anchors)
before replacing it with a fixed calibration value.

Four Julia NUTS chains each use 1,000 warmup and 1,000 retained draws. The
zero-centered normal prior scales are 1.5 for person coordinates and 1.0 for
free rater, item and step coordinates. These are explicit settings for this
artificial example, not universal defaults to copy into an applied study.
The [model explanation](rating-model-theory.md) describes the probability model
and constraints; [prior implications](bayesian-workflow.md#3.-Check-Prior-Implications)
explains what to examine when choosing a prior for your own data.

### Read the answer

The reference calculation gives the following excerpt, rounded to three decimals:

```text
Is R2 more severe than R1?
Artificial ratings: 72; people: 12; items: 4; raters: 3.
Positive values mean that R2 is more severe than R1, after accounting for persons and items.
Numerical checks: passed
Posterior mean: 0.18 logit; 90% interval: [-0.511, 0.889].
```

The estimate leans toward greater severity for R2, but the interval includes
both negative and positive differences. **These ratings do not clearly establish
the direction of the difference under this model and prior.** They also do not
show that R1 and R2 are equivalent. A useful analysis can reach an uncertain
answer; successful computation does not guarantee a clear empirical distinction.

The 90% central interval contains 90% of the computed posterior distribution.
It describes uncertainty about the contrast conditional on the data and model.
MCSE describes a different uncertainty: the numerical error from using finitely
many posterior draws. In the reference result the mean MCSE is about 0.0069
logit and the two endpoint MCSEs are about 0.0171 and 0.0156. Small MCSE does not
make the interval narrower or establish repeated-sampling coverage.

Before producing a substantive interpretation, the example requires the global
diagnostic checks to pass, mean MCSE at most 0.01 and both endpoint MCSEs at most
0.02 logit. These numerical tolerances resolve this displayed example; they are
not a minimum scientifically important difference. If checks fail, the answer
says to withhold interpretation and preserves the fit for diagnosis. It does
not silently rerun the fit or substitute a more favorable result.

The complete answer also prints the actual MCSEs and these illustrative limits,
R-hat/ESS, and each chain's sampler diagnostics. It separates retained-draw
divergences, maximum-depth hits, nonfinite log densities and E-BFMI from warmup
events. Warmup records show recorded/expected iterations and whether history is
available; unavailable counts are not zeros. Warmup events do not enter the
retained-draw pass/fail rule. They remain visible even when that rule passes.
Passing numerical checks does not establish model adequacy or interval calibration.
`answer.json` preserves the full diagnostic summary and both sets of sampler
rows, alongside the exact MCSE values, limits and their illustrative purpose.

### Save and reopen without refitting

The returned `analysis.directory` is a new folder under `results/first_analysis/`:

| File | Use |
| --- | --- |
| `answer.txt` | Read the question, estimates, interpretation, MCSE limits and separate retained/warmup diagnostics. |
| `answer.json` | Reuse the computed answer, prior settings, numerical criteria and complete diagnostic summary/sampler rows in other software. |
| `fit.jls` | Recompute summaries or make figures from the saved posterior in the original environment. |

The script reloads the fit and compares its answer with the original before
finishing. In the same Julia session, inspect it yourself:

```julia
read(joinpath(analysis.directory, "answer.txt"), String)
restored = load_fit_cache(joinpath(analysis.directory, "fit.jls"))
FirstMFRMAnalysis.result(restored)
```

To regenerate the answer from that cache, without new MCMC, call:

```julia
reopened = FirstMFRMAnalysis.main([
    "--saved-fit", joinpath(analysis.directory, "fit.jls")])
```

This writes a new output folder and rejects a cache from different ratings,
model or prior. In a later session, retain the original analysis project and
Julia/dependency environment and supply the saved path; see
[reopening saved results](api-saved-reporting.md#saved-result-reproduction).
JSON and text can be read without restoring a Julia fit. For optional figures,
use the [plotting instructions](fitting.md#Posterior-interval-figures) with
`restored`; figures need no refitting.

The example saves `fit.jls` and prints its absolute path **before** computing
the answer. If summarizing or writing the answer fails after that message, keep
the cache and the error details. After resolving the reporting problem in the
matching environment, use `FirstMFRMAnalysis.main(["--saved-fit", "the printed path"])
to write the answer into a new folder without sampling again. A fitting or
cache-writing failure before that message has no such saved-fit guarantee.
This checkpoint preserves completed draws; it does not resume an interrupted sampler.

### Move to your own question

First decide which contrast matters and what its units mean. Then check your
rating allocation, category use, model assumptions and prior implications.
Use the [analysis workflow](bayesian-workflow.md) for that sequence. Moving to
GMFRM, several dimensions or dependent ratings changes the model; it is not a
required extra step in this one-dimensional example.

## Observed-score ICC without fitting

The candidate's `examples/observed_icc.jl` compares four questions on the same
three performances and two raters. Rater 2 always gives one point more.

```julia
include("examples/observed_icc.jl")
result = observed_icc_example()
[(r.definition, r.unit, r.icc) for r in result.results]
# (:agreement, :single,  2/3)
# (:agreement, :average, 0.8)
# (:consistency, :single,  1.0)
# (:consistency, :average, 1.0)
```

The perfect consistency coefficient reflects the identical ordering and spacing
once the additive rater offset is removed. It does not mean the raw scores agree.
The average coefficient concerns the mean of these two ratings. The example
explicitly assumes equal score gaps and treats the raters as a fixed panel.
See [Choosing an ICC](interpreting-results.md#Choosing-an-ICC) for the design,
scale and uncertainty limits. This example performs no model fitting.

## Observed-score alpha without fitting

The candidate's `examples/observed_alpha.jl` contains a complete small example:

```julia
include("examples/observed_alpha.jl")
result = observed_alpha_example()
result.ordinal.alpha
result.ordinal.observed_disagreement
result.ordinal.expected_disagreement
result.ordinal.singleton_observation_ids
```

The two coefficients use the same ratings but different declared measurement
levels. Choose a level from the meaning of the categories, not whichever value
is larger. See [Observed-score alpha](interpreting-results.md#Observed-score-alpha)
for the definition, exclusions and report integration.

The repository keeps runnable examples compact. These scripts are learning and
verification examples rather than substantive analyses; they exercise the public surfaces
described in the [Bayesian Fitting](fitting.md) page.

## Inspect Data Without Fitting

Start with `examples/inspect_ratings.jl` to learn the input and model workflow
without running MCMC or creating files. From a repository checkout with its
dependencies installed:

```sh
julia --project=. examples/inspect_ratings.jl
```

The script constructs eight artificial ratings from two persons, two items and
two raters on categories 0–2. It prints those counts, the complete category
order, validation errors or warnings, and the equation for a one-dimensional
partial-credit MFRM. A passing design check permits the next specification step;
it does not make this tiny dataset adequate for inference.

In an interactive session, `?FacetData` shows a complete input example,
`?validate_design` explains how to read its report, and `?mfrm_spec` explains
the model choice. `?fit` gives a short fitting introduction; `??fit` includes
the full controls. The [Julia help walkthrough](learning-guide.md#Use-Julia-help-and-examples)
explains the prompts and how these examples differ from R's `example()`.

## Minimal MFRM Workflow

[`examples/minimal.jl`](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/blob/main/examples/minimal.jl)
runs a short partial-credit MFRM sampler demonstration. For the complete first
teaching analysis and its interpreted result, use [First MFRM analysis](#First-MFRM-analysis).
From the repository root, after
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
content(figure[1, 1]).xlabel = "Rater severity (logits)"
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

### Start with the bundled MGMFRM data

**Question: what does a person's rating profile tell us about two separate
abilities?** The bundled `examples/normalized_mgmfrm_ratings.jl` contains 1,000
fixed artificial ratings from 50 people, five items and five raters. Categories
are ordered 1–4. Two items measure the first dimension and three measure the
second. Each item has an estimated positive loading on its assigned dimension;
the other loading is fixed at zero. The dimension names `dim=1` and `dim=2`
are deliberately generic because these are simulated teaching data, not a test
with validated substantive constructs.

First inspect the inputs without estimating a model or creating output files.
This is the default when no mode is supplied:

```sh
julia --project=. examples/normalized_mgmfrm.jl
```

Use `--help` to list the modes; `--inspect-example` explicitly selects the same
inspection. Both inspection and help finish without sampling or writing results.

| Mode | What happens |
| --- | --- |
| No arguments or `--inspect-example` | Read the fixed data and explain Q, dimension support, priors and proposed fit settings. |
| `--help` or `-h` | Print the available commands. |
| `--fit-example` | Run the four-chain teaching fit and save/report its results. |
| `--saved-fit PATH` | Read a trusted fit in its original environment and write a new report without fitting. |
| `--demo` | Run a tiny demonstration with random draws and chains too short for inference. |

`--figures` can accompany `--fit-example`, `--saved-fit` or `--demo` when
CairoMakie is installed. It cannot accompany help or input inspection.

This prints the category order, item-to-dimension assignment, all six explicit
prior scales and the proposed sampling settings. The table is incomplete:
250 of the 1,250 person/item/rater combinations are unobserved. They must stay
absent; do not fill them with zero or a category value. This example retains all
known persons, items and raters. It does not establish performance for arbitrary
sparse or disconnected designs.

The model uses item-specific partial-credit steps, centered rater severities
and positive rater consistencies whose product is one. Person dimensions have
independent unit-SD priors; their population correlation is fixed at zero.
The [explicit normalized prior](experimental.md) defines the scale of the
remaining effects. Its supplied values reproduce this example, not a default
choice for a new study; inspect the [scientific scope](scope.md#current-scientific-evidence)
before interpreting numerical qualification as calibration.

To estimate this fixed example, use the explicit fitting command:

```sh
julia --project=. examples/normalized_mgmfrm.jl --fit-example
```

It runs four Julia NUTS chains, each with 1,000 warmup and 1,000 retained draws,
using seed `20261008110001`, then writes the answer and saved results described
below. It does not generate a new dataset or predictive replications. These
inputs, prior and controls match an existing completed four-chain analysis;
changing the data, prior, environment or controls requires checking the new
diagnostics and MCSE. A fixed iteration count is not an accuracy guarantee.

In Julia, inspect or adapt the complete specification before fitting:

```julia
using BayesianMGMFRM
include(joinpath(pkgdir(BayesianMGMFRM), "examples", "normalized_mgmfrm.jl"))
prepared = NormalizedMGMFRMExample.example_inputs()  # no fitting
prepared.spec.q_matrix
prepared.prior
prepared.controls
# Execute only when you intend to run MCMC:
# fitted = BayesianMGMFRM.Experimental.fit(prepared.spec;
#     prior=prepared.prior, prepared.controls...)
```

Inspection also reports how many people have structural support for every
ability direction and names those with missing dimensions. With your own data,
start with [CSV import and your own specification](data-validation.md#import-csv).
`example_inputs()` always reads the bundled data. Build Q by item label and
inspect person-level support before fitting; the
[worked incomplete-assignment check](data-validation.md#person-dimension-support)
shows why overall data validation can pass while one ability remains unmeasured.

The fixed ratings are shipped with the source; the previous posterior is not.
Use your printed `fit.jls` path with `--saved-fit` for later reporting. The
explicit `--demo` command below uses different, tiny data
and deliberately short chains; it is not this teaching analysis.

If the program prints `Saved fit before reporting:` and a later export fails,
keep that cache and fix the reported problem. In the original environment, use
`--saved-fit "the printed path/fit.jls"` to create a new output folder. Do not
rerun `--fit-example` to recover a report. Preserve the failed output folder
until the new bundle has been verified; a partly written report is not a
verified bundle. See [export recovery](api-saved-reporting.md#If-reopening-fails).

### Read an existing MGMFRM analysis

**Question: what abilities does the fitted model estimate in each dimension?**
Use your trusted normalized MGMFRM cache in the original Julia/dependency
environment. This route reads the original model, data, prior and all retained
chains; it performs no new fitting, prior simulation or predictive random draws.

```julia
using BayesianMGMFRM
include(joinpath(pkgdir(BayesianMGMFRM), "examples", "normalized_mgmfrm.jl"))
analysis = NormalizedMGMFRMExample.main(["--saved-fit", "path/to/fit.jls"])
read(joinpath(analysis.directory, "answer.txt"), String)
```

From a source checkout, the equivalent command is
`julia --project=. examples/normalized_mgmfrm.jl --saved-fit path/to/fit.jls`.
The cache must be a `NormalizedMGMFRMFit` produced by the documented fit/save
route; it is not a raw research sample file or a portable JSON report. See
[saved-result reproduction](api-saved-reporting.md#saved-result-reproduction)
for selecting the matching environment.

The answer prints the observed sample sizes, retained draws, whole-fit numerical
status and the first person's estimate and 95% central interval in each named
dimension. The two values describe different abilities; they are not an overall
ranking or evidence that one trait is intrinsically higher. Their scale comes
from the saved model and prior. This model fixes latent correlations at zero;
correlating the printed person estimates is not estimation of that population
correlation.

The new output folder contains `answer.txt`, a verified `fit.jls` copy and
`report/` with readable Markdown, portable JSON and parameter tables. The report
includes all people, the actual prior, and mean/interval-endpoint MCSE. A narrow
interval and small MCSE answer different questions. Numerical warnings remain
visible and the answer says to withhold interpretation when the whole-fit
diagnostics fail. Passing diagnostics still requires judging numerical precision
against the reported quantity and does not establish calibration or model adequacy.
No WAIC/LOO comparison or new observation IDs are invented for the saved analysis.

The saved route has also been exercised on a completed four-chain MGMFRM with
1,000 retained draws per chain, using an existing simulated validation dataset:
1,000 training ratings from 50 people, five items and five raters. The incomplete
allocation retains known facet levels. That validation cache is not bundled with
the package; supply your own trusted fit in the command above.
This checks the existing-sample reporting route; it is not a new fit or evidence
for extreme sparsity. The [scientific scope](scope.md#current-scientific-evidence),
including prior sensitivity and undercoverage, still applies.

### Short interface demonstration

The bundled source file `examples/normalized_mgmfrm.jl`
is a self-contained two-dimensional, fixed-Q example with estimated positive
loadings and identity latent correlation. The following commands run a short
interface demonstration, including prior/predictive random generation; they do
not produce an analysis suitable for substantive interpretation:

```sh
julia --project=. examples/normalized_mgmfrm.jl --demo
# With CairoMakie installed in the analysis environment:
julia --project=. examples/normalized_mgmfrm.jl --demo --figures
```

It specifies all six normalized exchangeable-prior scales, inspects prior rating
implications, and fits with the explicit location coordinates. Two chains with
10 warmup and 12 retained draws demonstrate the interface; their warnings remain
visible and these settings are insufficient for inference. The script prints
model-scale summaries and Monte Carlo errors, saves to a new directory under
`results/normalized_mgmfrm/`, and checks metadata, summaries and diagnostics after
reloading `fit.jls`.

The optional person and loading-diagnostic figures use the reloaded fit and the
first named dimension and are saved under `figures/`. The `--figures` option can
also accompany `--saved-fit`; it requires CairoMakie in that analysis environment.
The report reader verifies the exported bundle;
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
content(figure[1, 1]).xlabel = "Communication ability"
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
analysis environment that reads the cache, with CairoMakie available.
The script also saves a diagnostic supplement. Find the
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

### Compare persons or raters in a saved scalar MFRM fit

For an ordinary one-dimensional `MFRMFit`, use the same named
[`BayesianMGMFRM.posterior_contrast`](@ref) operation for person or rater
differences. It supports RSM and item-owned PCM. With the first-analysis
example's trusted cache in its original environment:

```julia
using BayesianMGMFRM, Serialization
restored = load_fit_cache("analysis-fit.jls")
BayesianMGMFRM.recovery_quantities(restored).rows # exact names and units
ability = BayesianMGMFRM.posterior_contrast(restored;
    left="person[P1]", right="person[P2]", interval=0.95)
severity = BayesianMGMFRM.posterior_contrast(restored;
    left="rater[R2]", right="rater[R1]", interval=0.95)
ability.summary
severity.summary.precision
severity.whole_fit_diagnostics
serialize("scalar-contrasts.jls", (; ability, severity))
saved = deserialize("scalar-contrasts.jls") # trusted file, same environment
```

Each difference is calculated within the original joint draw, including the
reference rater's fixed zero. Scalar MFRM differences use unit logits; do not
apply the MGMFRM multiplier of 1.7. Positive severity means the left rater is
more severe under this model, not less fair. A reference or hard-anchored rater can be
one side of the comparison; two fixed coordinates are rejected because neither
is estimated. External anchor uncertainty is excluded.

Keep the native fit, the saved answers and their environment together. Inspect
the whole-fit warning, contrast diagnostics and interval-endpoint MCSE before
interpreting a result; a probability above zero is not an automatic practical
decision. This scalar method provides differences, not consistency ratios,
cross-model contrasts or fixed-Q multidimensional MFRM contrasts.

### Compare abilities or raters in a saved MGMFRM fit

Use a joint posterior contrast to ask whether two fitted persons differ within
one dimension, or whether two raters differ in severity or consistency.
Subtract the two values **at each retained draw**: subtracting marginal
interval endpoints or independently shuffling the columns loses their posterior
dependence. For example, the variance of a difference includes minus twice the
covariance, even when the population ability prior has identity correlation.

The qualified [`BayesianMGMFRM.posterior_contrast`](@ref) function accepts
independent fixed-Q `MGMFRMFit` and `Experimental.NormalizedMGMFRMFit` caches.
It uses the fitted model coordinates with all original chains and draws;
no renderer or additional diagnostic dependency is needed:

```julia
using BayesianMGMFRM
restored = load_fit_cache("analysis-fit.jls")
BayesianMGMFRM.recovery_quantities(restored).rows # exact names and units
answer = BayesianMGMFRM.posterior_contrast(restored;
    left="person[P1,communication]", right="person[P2,communication]",
    interval=0.95)
answer.summary
answer.whole_fit_diagnostics
```

Replace the exact names with those listed for your fit. For the normalized
teaching example, the first dimension is named `dim=1`, so use
`person[P1,dim=1]` and `person[P2,dim=1]`. Positive differences mean higher
ability for P1 under the saved model and prior. The interval describes that
joint difference; a positive mean alone does not resolve its direction.
Inspect the whole-fit diagnostics, the contrast diagnostics and endpoint MCSE.

[`saved_mgmfrm_contrasts.jl`](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/blob/main/examples/saved_mgmfrm_contrasts.jl)
provides a label-based wrapper over the same function for these two fit types.
From the repository root:

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
The wrapper remains example code; `posterior_contrast` is the qualified package
entry point. Correlated MGMFRM and other fit families are outside this method.
Within a slope-restricted normalized fit, abilities and severities remain
available; a comparison of two consistencies fixed at one is rejected because
it is not an estimated contrast. No new fitting support follows from this summary.

Save the calculated answer alongside the fit and its original environment.
This example creates a new directory and refuses an existing one:

```julia
using Serialization
mkdir("contrast-results")
serialize("contrast-results/ability.jls", answer)
reopened = deserialize("contrast-results/ability.jls")
@assert isequal(reopened, answer)
```

Load only trusted serialization files. This retains the computed answer and
its source/coordinate metadata; it does not archive the fit or provide portable
posterior draws. Reopen the native fit in its
[recorded environment](api-saved-reporting.md#saved-result-reproduction) to
calculate a different contrast. Existing caches are not changed by this operation.

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

## Common saved-fit prediction preview

The isolated common-API candidate also provides a
[saved comparison, diagnostics and reporting workflow](common_prediction_comparison.md).
That guide distinguishes the candidate package APIs from the standalone preview
below, lists supported result types and explains their warning/uncertainty limits.

The repository example `examples/common_prediction_observations.jl` reads a fit
cache through the **opt-in prototype** common adapter. It works with eight
result types: `MFRMFit`, `GMFRMFit`, `MGMFRMFit`, `NormalizedMGMFRMFit`,
`CorrelatedMGMFRMFit`, `MultidimensionalMFRMFit`, `CorrelatedMFRMFit` and
`ExchangeableMFRMFit` (experimental types use the `Experimental` namespace).
This adapter is not yet included or exported by the package;
use a repository checkout. Its availability does not establish scientific
acceptance of those models.

```sh
julia --project=. examples/common_prediction_observations.jl --help
julia --project=. examples/common_prediction_observations.jl \
  results/my-analysis/fit.jls study-A/ratings-v1 results/my-analysis/observation-ids.txt
```

Replace the paths and dataset version with your saved analysis. The cache must
come from `save_fit_cache`, rather than a private `samples.jls` record. The ID
file contains one unique, nonblank observation ID per line, **in the original
fit row order**. Preserve IDs at data ingestion and carry them through filtering
or reordering with the ratings; repeated person/item/rater combinations need
distinct observation IDs. The adapter checks uniqueness, counts and bindings,
but cannot discover whether a user supplied the wrong real-world ID-to-row map.
Keep the ID file and dataset version alongside the fit cache.

The example writes no files and runs no sampler. It prints category order,
array dimensions, model scale, WAIC/raw IS-LOO scores, sampling warnings and
problem observation IDs. One retained draw illustrates the probability-array
axes; it is not a posterior mean or a precision assessment. Criteria use **all**
original draws and chains, without creating the full category probability cube.
Warnings remain visible even when a numerical score is returned.

For use in a Julia session, run from the repository root:

```julia
using BayesianMGMFRM
include("scripts/prediction_observation_adapter.jl")
using .PredictionObservationAdapter

restored = load_fit_cache("results/my-analysis/fit.jls")
ids = readlines("results/my-analysis/observation-ids.txt")
evaluation = prediction_criteria(restored;
    dataset_id="study-A/ratings-v1", observation_ids=ids,
    criteria=(:waic, :raw_loo))
evaluation.sampling_warning
evaluation.criterion_warnings
evaluation.problem_observation_ids
evaluation.uncertainty

# Inspect the current prototype's arguments and output contract.
@doc prediction_observations
@doc prediction_criteria
```

The extraction target is the original training rows and existing facet levels;
criterion aggregation gives equal weight to rating rows. This differs from the
foundation study's heldout, globally person/dimension-weighted scoring. The
raw IS-LOO target omits one rating with fixed specification/level maps. Neither
operation predicts a new person/rater or performs grouped K-fold refits. Returned
pointwise score SE is not MCMC MCSE, a cluster-adjusted SE or an independent-study
replication SE. `:hill_smoothed_loo` remains the separate historical approximation.
The package's common `criteria(..., criteria=(:psis_loo,))` route now supplies
standard PSIS with chain relative efficiency; see the
[comparison guide](common_prediction_comparison.md) for diagnostics and limits.
This older prototype example performs no model ranking.

The normalized-prior walkthrough above provides the earlier fit → diagnostics →
save/reload → report/figure sequence. Its short run and prior values demonstrate
syntax; they do not prescribe adequate draws or an accepted scientific prior.

## Reliability from a Saved Fit

The candidate's `examples/saved_posterior_reliability.jl` reads an existing cache
and calls `BayesianMGMFRM.posterior_reliability`. It performs no fitting. Select
estimated location names with `BayesianMGMFRM.recovery_quantities`, then declare
whether absolute locations or deviations from the selected cohort's mean are
the target. For multiple dimensions, make a separate call for each dimension.

```julia
include("examples/saved_posterior_reliability.jl")
# Replace these with exact names from your fit's inventory.
result = saved_posterior_reliability("my-fit.jls";
    parameters=["person[1]", "person[2]"], target=:centered,
)
result.reliability
result.mcse
result.sampling_warning
```

This is a finite-cohort posterior summary, with numerical MCSE where available.
It is not a reliability CrI, inter-rater agreement, Strata or an assurance about
a new rating design. Read the [target and derivation](interpreting-results.md#An-explicit-posterior-reliability-target)
before interpreting it. Save the selected names, weights and target with the fit
so that another session can reproduce the same result.

## Common-response score agreement from a saved fit

Use this when several raters scored the same performance and criterion. Retain
the actual response IDs from data collection; a person can produce more than
one performance on the same item. The example works with the same eight saved-fit
types as the common prediction interface, including multidimensional models.

```julia
include("examples/saved_rater_agreement.jl")

result = saved_rater_agreement("my-fit.jls";
    dataset_id="assessment-2026", observation_ids=rating_ids,
    response_ids=performance_ids, adjacent=1, interval=0.99,
    se_unit=:person)
result.overall.exact.observed_rate
result.overall.exact.expected_mean
result.overall.exact.expected_lower, result.overall.exact.expected_upper
result.overall.exact.observed_se
result.overall.exact.mcse
result.rater_pairs
```

The observed percentage, conditional model-expected rate, observed-rate cluster
SE and numerical MCSE answer different questions. See the
[matching rules, denominators and uncertainty explanation](interpreting-results.md#Agreement-and-practical-decisions).
Zero-overlap pairs remain in the table. The function neither diagnoses copying
or halo nor infers agreement on new performances. No new fit is performed.

## Category use and conditional curves from a saved fit

The qualified common report retains shared, item-owned or rater-owned steps as
specified by the saved model. It does not change the threshold facet. For a
one-dimensional fit, the saved-cache example can be called as follows:

```julia
include("examples/saved_category_report.jl")

categories = saved_category_report("my-fit.jls";
    dataset_id="assessment-2026", observation_ids=rating_ids,
    interval=0.99,
    profiles=[(;id="selected-item-rater", item="I1", rater="R1",
        dimension=1, ability_grid=range(-3, 3; length=41))])
categories.step_contract
categories.usage_rows
categories.threshold_rows
categories.curve_rows
categories.crossing_rows
categories.sampling_warning, categories.mcse_warning
```

Use the exact stored item and rater labels. Multidimensional fits require
`fixed_abilities=Dict(2 => 0.0, ...)` for every dimension other than the plotted
one. All retained draws contribute. The intervals are pointwise equal-tailed
posterior intervals; the expected category proportion has no new-rating
realization noise. Read the [ownership, crossings and uncertainty explanation](interpreting-results.md#Category-functioning-across-model-families)
before interpreting these rows. This standalone example performs no fitting. The integrated example below
adds explicitly requested sections to `fit_report`.

## Integrated saved-fit report

For a comparison of several models, the
[combined saved workflow](common_prediction_comparison.md#Connect-comparison,-diagnostics-and-persistence)
uses all eight common fit types, diagnostics, parameter MCSE and explicit
per-model reporting choices in one save/reload path.

`examples/saved_integrated_report.jl` loads a trusted cache and writes a public
JSON/Markdown/table bundle. Declare persistent rating IDs, actual shared-response
IDs and a deliberate reliability cohort before calling it:

```julia
include("examples/saved_integrated_report.jl")

restored = saved_integrated_report("my-fit.jls", "assessment-report";
    reporting=(;
        dataset_id="assessment-2026", observation_ids=rating_ids,
        category=(;interval=0.99),
        agreement=(;response_ids=performance_ids, interval=0.99),
        reliability=[(;id="Ability A", parameters=person_names_A, target=:centered)]),
    include_posterior_predictive=false, include_artifact=false,
    include_waic=false, include_loo=false)
restored["category_report"]["usage_rows"]
restored["posterior_reliability"]["rows"]
restored["rater_agreement"]["rows"]
```

Replace these input vectors with the actual study identities and exact estimated
coordinate names; another ability dimension requires its own named cohort. The
example requires execution-complete sections when saving, while preserving MCMC
and numerical warnings. It does not require that the underlying scientific claims
have been accepted. See the [request and failure semantics](api-saved-reporting.md#One-report-with-explicit-analysis-choices).

## Matched one- and multidimensional MGMFRM

`examples/matched_dimension_refit_plans.jl` prepares the one-dimensional
restriction and a between-item MGMFRM with common rating identities, splits,
item-owned steps, loading count and prior settings. It performs no fitting.
Follow the [worked comparison workflow](common_prediction_comparison.md#Matched-dimensionality-comparison)
to fit training folds, retain diagnostics/failures and compare saved held-out
predictions. This example does not equate scalar GMFRM with the one-dimensional
MGMFRM restriction or validate dimensionality selection.

## Numerical precision of saved K-fold comparisons

`examples/saved_kfold_comparison.jl` accepts `mcse=:delta` and separate
`independent_fold_rng` / `independent_model_rng` declarations. It reads existing
fits and reports first-order numerical error where estimable, preserving
short-chain and diagnostic warnings. Follow the [numerical-error example](common_prediction_comparison.md#Numerical-error-of-the-K-fold-comparison)
for formulas, field meanings and the distinction from data-sampling SE.


## Classification from a saved fit

Inspect the coordinate catalogue before selecting the people and ability
dimension relevant to the study. Keep the cutoff on this fitted scale:

```julia
fit = load_fit_cache("my-fit.jls")
BayesianMGMFRM.recovery_quantities(fit).rows

# Supply exact selected names and justified study rules, not example defaults.
decisions = BayesianMGMFRM.posterior_classification(fit;
    parameters=person_names_A, cutoff=study_cutoff,
    pass_probability=study_probability_rule, interval=0.99)
decisions.rows                       # Ability SD/99% ETI, probability, decision, risk
decisions.cohort                     # Expected error counts and any-error probability

report = fit_report(fit; view=:public,
    reporting=(;classification=(;parameters=person_names_A, cutoff=study_cutoff,
        pass_probability=study_probability_rule, interval=0.99)),
    include_posterior_predictive=false, include_artifact=false,
    include_waic=false, include_loo=false, require_complete=true)
save_fit_report_bundle("classification-report", report; require_complete=true)
restored = load_fit_report_bundle("classification-report"; require_complete=true)
restored["posterior_classification"]["rows"]
```

These calls reuse all original retained draws. The qualified API supports the
eight common fit types. Read the [rule, dependence and uncertainty explanation](interpreting-results.md#Posterior-classification-and-conditional-ability-precision).
Ranking, multidimensional composite rules and repeated-study error calibration
are separate tasks; a complete saved report does not imply scientific acceptance.


## Ranking uncertainty from a saved fit

Use exact estimated person coordinates from one ability dimension. Select the
cohort and rank direction deliberately; a top-k query is optional:

```julia
fit = load_fit_cache("my-fit.jls")
BayesianMGMFRM.recovery_quantities(fit).rows

ranks = BayesianMGMFRM.posterior_ranking(fit;
    parameters=person_names_A, direction=:higher, top_k=3, interval=0.99)
ranks.rows[1].rank                       # Mean, SD, median, discrete 99% interval, MCSE
ranks.rows[1].top_k_probability.lower    # Posterior mean and numerical MCSE
ranks.rows[1].top_k_probability.upper

report = fit_report(fit; view=:public,
    reporting=(;ranking=(;parameters=person_names_A, direction=:higher,
        top_k=3, interval=0.99)), include_posterior_predictive=false,
    include_artifact=false, include_waic=false, include_loo=false,
    require_complete=true)
save_fit_report_bundle("rank-report", report; require_complete=true)
restored = load_fit_report_bundle("rank-report"; require_complete=true)
restored["posterior_ranking"]["rows"]
```

The selected cohort must have at least three people for this `top_k=3` example;
the API itself permits cohorts of two or more. Omit `top_k` for rank summaries
without an inclusion query. Use `direction=:lower` when smaller values should
come first. A top-k boundary tie produces probability bounds, not an arbitrary
winner. Read the [cohort, tie and uncertainty explanation](interpreting-results.md#Posterior-ranks-within-an-explicit-cohort).
Both ranking and classification may be requested in the same report; their
person lists and substantive purposes need not be identical.


## Matched item-slope workflow

For a comparison that starts with the same heldout split and preserves missing
folds, follow [fixed versus free item slopes](common_prediction_comparison.md#Matched-fixed-versus-free-item-slopes).
That preparation and saved-scoring example performs no new estimation.

`examples/matched_slope_workflow.jl`
provides `matched_slope_workflow(spec; prior, output_dir, ndraws, warmup, chains, seed)`.
It requires an explicit one-dimensional MGMFRM specification and normalized
exchangeable prior. The function fits fixed-one and estimated-positive item
slopes with unit rater consistency, saves separate caches and reopens both.
All numerical controls are supplied by the caller. It prints the retained
sampling flags and returns the fits and paths; it does not select a model.
Use a new output directory. If one fit fails, any earlier saved fit remains.

Read [matched fixed and estimated item slopes](experimental.md#Matched-fixed-and-estimated-item-slopes)
for the equation, inactive prior inputs, free-coordinate order and common
heldout comparison workflow. This is an unreleased candidate example; obtain
it from the same candidate checkout as the package.

## Mean-profile prior example

`examples/mean_profile_prior.jl` provides `mean_profile_example()`, which returns
an artificial three-category specification, fixed-slope model and explicitly
scaled prior. It performs no fitting and uses named item IDs. Load it from the
installed package's examples directory as described above, then inspect the
[mean-profile contract](experimental.md#Fixed-location-and-step-mean-profiles).
Use the [successor installation](index.md#Install-this-development-preview);
the earlier 13 October preview does not contain this example.

```julia
include(joinpath(pkgdir(BayesianMGMFRM), "examples", "mean_profile_prior.jl"))
setup = mean_profile_example()
contract = BayesianMGMFRM.Experimental.surface_contract(setup.model; prior=setup.prior)
# Choose sampling controls for your analysis; these are deliberately not inferred.
# fit = BayesianMGMFRM.Experimental.fit(setup.model; prior=setup.prior,
#     ndraws=..., warmup=..., chains=..., seed=...)
# save_fit_cache("profile-fit.jls", fit)
# reopened = load_fit_cache("profile-fit.jls")
```

Use an explicit existing-level split with `prediction_refit_plan` before fitting
training subsets. A saved fit for a different mean profile is rejected when
scoring a heldout request. Saving/reopening retains numerical warnings; a short
workflow check is not evidence of convergence or model-selection performance.

### Check a mean-profile contrast in the intended units

After fitting, ask whether rater B is more severe than A. A positive B−A
difference means B assigns lower scores at otherwise equal conditions.
Load your saved `profile-fit.jls` in its original Julia/dependency environment.
The following recipe only reads retained draws; it does not fit again.

The `units=:unit_logit` argument used when preparing the prior specifies the
input means. It does **not** change the units returned by `posterior_contrast`.
For this independent D1 model with both coefficients fixed at one, multiply
the model-coordinate severity difference, interval and MCSE by the likelihood
constant 1.7 to express them in unit logits. This conversion is not a general
rule for free coefficients or the ordinary scalar MFRM, which already uses
unit logits.

```julia
using BayesianMGMFRM
restored = load_fit_cache("profile-fit.jls")
restored isa BayesianMGMFRM.Experimental.NormalizedMGMFRMFit ||
    error("Use the normalized fixed-one mean-profile fit for this example.")
meta = fit_metadata(restored)
(meta.dimensions == 1 && meta.loading_policy === :fixed_one &&
    meta.rater_consistency === :fixed_one) ||
    error("This scale conversion requires the D1 fixed-one model.")
contrast = BayesianMGMFRM.posterior_contrast(restored;
    left="rater[B]", right="rater[A]", interval=0.95)
s = contrast.summary
p = s.precision
d = s.contrast_diagnostics
scale = meta.likelihood_scale
unit_logit = (; mean=scale*s.mean, lower=scale*s.lower, upper=scale*s.upper,
    mean_mcse=scale*p.mean_mcse,
    endpoint_mcse=(scale*first(p.quantiles).mcse, scale*last(p.quantiles).mcse))

# Illustrative limits, chosen before fitting; specify suitable limits for your study.
limits = (; mean_mcse=0.01, endpoint_mcse=0.02) # both in unit logits
valid = x -> x isa Real && !(x isa Bool) && isfinite(x) && x >= 0
checks = (;
    whole_fit=contrast.whole_fit_diagnostics.passed,
    contrast_diagnostics=d.status === :available &&
        all(valid, (d.rank_normalized_rhat, d.bulk_ess, d.tail_ess)) &&
        d.rank_normalized_rhat <= 1.01 && d.bulk_ess >= 400 && d.tail_ess >= 400,
    mean_mcse=p.mcse_status === :available && valid(unit_logit.mean_mcse) &&
        unit_logit.mean_mcse <= limits.mean_mcse,
    endpoint_mcse=p.mcse_status === :available && all(valid, unit_logit.endpoint_mcse) &&
        all(x -> x <= limits.endpoint_mcse, unit_logit.endpoint_mcse))
result = (; unit_logit, limits, checks, numerically_qualified=all(values(checks)),
    warmup=diagnostics(restored).warmup_rows)
result
```

One recorded run of the bundled 24-rating artificial example used four chains,
each with 1,000 warmup and 1,000 retained draws. Its B−A summaries were:

| Quantity | Model coordinates | Unit logits |
| --- | ---: | ---: |
| Posterior mean | 0.00337 | 0.00573 |
| 95% equal-tailed interval | [−0.57811, 0.59519] | [−0.98278, 1.01183] |
| Mean MCSE | 0.00368 | 0.00625 |
| Lower-endpoint MCSE | 0.01986 | 0.03376 |
| Upper-endpoint MCSE | 0.01340 | 0.02278 |

Whole-fit and contrast R-hat/ESS checks passed, but both endpoint MCSEs exceeded
the declared 0.02 **unit-logit** limit. Comparing the model-coordinate MCSEs
directly with 0.02 would give the wrong decision. Equivalently, compare those
MCSEs with `0.02 / 1.7` in model coordinates: both checks still fail. The limits
are illustrative numerical tolerances, not package defaults or practical
equivalence margins.

The saved interval spans zero, but the requested endpoint precision was not
attained. Retain that interval with its numerical limitation; this example
does not establish a severity direction, rater equivalence or inadequate data
collection. MCSE describes finite-chain computation, whereas the posterior
interval describes uncertainty conditional on the data, model and prior.
There were no retained divergences; all 17 warmup divergences remain in the
record. This example was not extended to obtain a passing result. It supplies
no high-category prior recommendation or repeated-study calibration evidence.
Different recorded environments and controls need their own results; these
numbers are an illustration, not an exact-output promise for every new run.

## Review saved temporal severity

`examples/fit_rater_drift.jl` also defines a fitting function for caller-supplied
rows, model options and explicit inference settings. It retains native chains
and a portable report. Including the example does not start inference;
see [Rater Drift](rater-drift.md#Fit-and-retain-the-chains) for the full operation
and original-environment restoration.

`examples/review_saved_rater_drift.jl` accepts an existing RW1 computed JSON
report, its separately retained SHA-256, a new output path and an optional judge
ID. It prints reference-relative changes, MCSE and whole-report warnings, then
saves a portable copy. It never samples or loads native posterior chains.
See [Rater Drift](rater-drift.md) for input conventions, figures and interpretation.

`examples/compare_saved_rater_drift.jl` compares matched static/RW1 computed
reports using their separately retained SHA-256 receipts. It preserves both
source reports, location/trajectory numerical warnings and the static
structural-zero interpretation. No sampling or model selection is performed.

## Read a saved three-outcome report

For input inspection first, use `examples/three_indicator_input.jl` and the
[labelled-input recipe](data-validation.md#three-outcome-input). The bundled
165-event synthetic input illustrates the format and block-reset history;
it does not establish adequate sample size or model validity.

For an existing accentedness/comprehension/transcription report, follow
[the saved-results recipe](api-saved-reporting.md#three-outcome-saved-reports).
The package-only `examples/saved_three_indicator_report.jl` reads the named
panel and contrasts, preserves numerical/comparison warnings and optionally
saves a portable copy. Supply the original JSON files and their separately
retained SHA-256 receipts. This example does not fit the three-outcome model.


## Prepare a three-outcome fit

[`three_indicator_fit.jl`](fitting.md#three-outcome-fitting) prepares the bundled
artificial input with an explicit reference prior, settings and named focal
quantities. It does not start inference on inclusion or preparation. Call
`Experimental.ThreeIndicator.fit` explicitly to fit and preserve native results;
follow the fitting guide for diagnostics, warnings and restoration limits.

## Observed-group rater effects

`examples/rater_group_effects.jl` fits one saved simulated allocation or reviews
a saved fit. It prints within-group gaps and their between-group change
separately, and writes `assessment.json` with explicit numerical limits, failures
and unavailable precision. Follow [group effects](rater-group-effects.md) for the model, prior,
contrast and limitations. The example is not evidence of population fairness.

The [three-trait guide](correlated-3d.md) shows explicit generation and fitting. `examples/correlated_3d_saved.jl` reopens a trusted saved fit in its original environment without generating or fitting.
