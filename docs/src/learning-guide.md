# Getting Started with Many-Facet Measurement

!!! note "Unreleased documentation preview — 13 October 2026"
    This manual includes unreleased interfaces and examples. It is not the
    documentation of an installed release. Model support and scientific
    acceptance remain as stated on each page.

See the [Visualization Gallery](visualization-gallery.md) for Wright Maps,
Pathway Maps and MGMFRM response surfaces with worked reading guidance.

When several raters score people's work, a low score can have several explanations:
the performance was weaker, the task was harder, or the rater was more severe.
Many-facet models describe these influences together. They estimate differences
and their uncertainty under explicit assumptions about the ratings and their design.

This guide is for readers who can interpret a table of scores but are new to
many-facet models or Bayesian analysis. Start here to choose a question and
understand the data. Continue to [How Rating Models Work](rating-model-theory.md)
for a worked probability calculation, then [Reading Results and Comparing
Models](interpreting-results.md) for interpretation. Julia is needed for running
the examples, but not for reading the explanations.

Before running an analysis, check the [available model and prior routes](scope.md#Current-Support)
and [what their current evidence permits](scope.md#current-scientific-evidence).
An implemented function and a scientifically supported conclusion are separate
milestones; the guide identifies both.

## Start with a concrete question

Suppose students give short presentations, several tasks elicit their work, and
raters score each response from 0 to 2. Higher categories represent better
performance. You might ask:

- How do two students differ after accounting for which tasks and raters they encountered?
- How much more severe is one rater than another, on the model's rating scale?
- Do reasoning and communication need separate ability estimates?
- Does allowing different item sensitivities improve predictions of held-out ratings?

These are different questions. A model that predicts scores well need not
estimate every individual parameter precisely. Decide which quantities will
answer your question before choosing a model or comparing fit statistics.

Here, **person** identifies whose performance is assessed, **item** identifies
the task or scored component, and **rater** identifies who assigns the score.
These influences are called *facets*. What counts as an item depends on the
study: a task–criterion combination may be an item, but that coding alone does
not model dependence between scores on the same response.

## Understand one row of data

Use one row per observed rating. For example:

| Person | Item | Rater | Score | Response |
| --- | --- | --- | ---: | --- |
| P1 | I1 | R1 | 1 | P1-I1 |
| P1 | I1 | R2 | 2 | P1-I1 |
| P1 | I2 | R1 | 0 | P1-I2 |
| P2 | I1 | R2 | 1 | P2-I1 |

The first two rows describe two ratings of the same response. They are not two
independent performances. A response identifier helps preserve that relationship
when checking the data or splitting them for prediction. It does not, by itself,
add a response effect to the fitted model. The table is only an illustration of
row meaning, not an adequate analysis dataset.

Categories are ordered outcomes. Coding them 0, 1 and 2 does not assume equal
distances on an underlying ability scale. Declare the complete intended category
order, including a category that happens not to occur in a small sample.
An unobserved rating is missing information; it must not be entered as score zero.

The design also matters. If one group of people is rated only by R1 and another
only by R2, with no linking observations or justified anchors, severity and
group differences may not be separable from the ratings. More MCMC draws cannot
create that missing link. Connectedness is necessary in many designs but does
not guarantee useful precision or remove bias from selective rater assignment.
See [Data Validation](data-validation.md) for coverage, linking and missingness checks.

## Choose assumptions before choosing a model name

Three choices are easy to confuse: the number of abilities, whether item/rater
multipliers are estimated, and whether ability dimensions are correlated.
They are separate modeling decisions.

| Question | Relevant model choice | What the choice adds |
| --- | --- | --- |
| Is one ability sufficient for the intended interpretation? | One-dimensional MFRM | Ability, item difficulty, rater severity and category steps, with fixed slopes. |
| Should items differ in sensitivity and raters in the concentration of their category probabilities? | Scalar GMFRM | Positive item discrimination and rater consistency, within its one-dimensional response equation. |
| Are distinct abilities needed with fixed item–dimension coefficients? | Multidimensional MFRM | A specified mapping from items to dimensions; active coefficients remain one. |
| Are distinct abilities and varying active loadings needed? | MGMFRM | A specified zero/nonzero loading pattern, estimated positive active loadings and rater consistency. |
| Should the population association between dimensions be estimated? | An explicitly correlated model | Correlation is an additional assumption and parameter, not an automatic consequence of using several dimensions. |

MFRM stands for *many-facet Rasch model*, GMFRM for *generalized many-facet
Rasch model*, and MGMFRM for *multidimensional generalized many-facet Rasch
model*. A more flexible model requires more information and stronger attention
to priors and identification. The table is a way to formulate alternatives,
not a rule that the most flexible model should win.

The implemented families also differ in who owns the category steps and in
their scale conventions. In particular, the scalar GMFRM uses rater-specific
steps, whereas MGMFRM uses item-specific steps. Comparing these configurations
does not isolate the effect of dimensionality alone. The
[theory guide](rating-model-theory.md) explains these differences explicitly.

For a multidimensional model, the **Q matrix** declares which dimensions enter
each item. For example, two reasoning items and two communication items give:

| Item | Reasoning | Communication |
| --- | ---: | ---: |
| I1 | 1 | 0 |
| I2 | 1 | 0 |
| I3 | 0 | 1 |
| I4 | 0 | 1 |

Zero excludes a dimension. In MGMFRM, one permits a loading to be estimated;
it does not fix that loading to one. Each row here uses one dimension, called
a *between-item* structure. Several ones in a row allow several abilities to
enter that item's predictor. Choose and justify Q from the intended measurement
structure; the current interface does not discover an unknown Q automatically.

Several active dimensions within one item are called *within-item*
multidimensionality. This structure is distinct from a compensatory or
non-compensatory response rule, and from correlation between abilities. See the
[worked explanation](rating-model-theory.md#Compensatory-and-non-compensatory-response-rules)
before interpreting these labels.

## Check what this package can currently fit

The stable fitting workflow covers one-dimensional MFRM with rating-scale or
partial-credit steps. GMFRM, multidimensional MFRM and MGMFRM are experimental.
Estimated ability correlation is available only through the documented,
restricted two-dimensional between-item models. A three-dimensional model
with independent abilities and a model estimating three-dimensional correlations
are different capabilities; the latter is not a supported fitting route.

The common prediction/comparison APIs described in this development manual are
an isolated, unreleased candidate. Their presence does not establish that any
model is scientifically preferable. Read [Scope and Releases](scope.md) for
the exact restrictions and use documentation matching your installed revision.

**Julia versus CmdStan is a computation choice.** MFRM versus GMFRM versus
MGMFRM is a model choice. Changing the backend should preserve the intended
probability model, priors and constraints; matching a backend name or random
seed does not establish that those ingredients match.

## Follow one complete analysis path

1. **State the quantity of interest.** For example, the ability difference
   between P1 and P2 in communication, with a scientifically meaningful scale.
2. **Validate the ratings and their design.** Inspect category use, facet
   coverage, links, missingness and shared responses.
3. **Specify the model and priors.** Check what each parameter means, how the
   origin and units are defined, and what simulated ratings from the prior look like.
4. **Fit and inspect computation.** Use multiple chains and review diagnostics
   and Monte Carlo error for the quantities you intend to report.
5. **Examine the substantive answer.** Read uncertainty intervals, predictive
   checks and sensitivity results. Use held-out predictions when the question
   concerns predictive performance.
6. **Save and reproduce the result.** Save the fitted object, model specification,
   data provenance and analysis environment; regenerate summaries and figures
   from the saved fit.

To try data checking and model specification first, without sampling or writing
files, use the [Inspect Data Without Fitting](examples.md#Inspect-Data-Without-Fitting)
example. For the subsequent fitting example, use a project checkout with its
dependencies installed and run this command from the repository root:

```sh
julia --project=. examples/minimal.jl
```

This uses artificial data and only 50 warmup plus 50 retained draws per chain.
It demonstrates data validation, fitting, diagnostics and save/reload. Those
settings are not a sample-size or MCMC recommendation, and warnings should be
read rather than treated as successful inference. The
[example walkthrough](examples.md#Minimal-MFRM-Workflow) explains its output
files and optional plots. The [Bayesian Workflow](bayesian-workflow.md) gives
the fuller analysis sequence, including prior checks and sensitivity analysis.

## Use Julia help and examples

Julia has built-in help for functions, types and modules. From the repository
root, start an interactive session with `julia --project=.` and load the package:

```julia
using BayesianMGMFRM
```

At the beginning of the Julia prompt, press `?`. The prompt becomes `help?>`;
type `FacetData` and press Enter. Its example constructs a complete small
dataset, checks it and creates a model specification without fitting.
Press Backspace at an empty help prompt to return to `julia>`.

| If you use R | In Julia |
| --- | --- |
| `?function_name` | Type `?FacetData`, `?mfrm_spec` or `?fit` at the Julia prompt. |
| Package-level help | Type `?BayesianMGMFRM` for this package's starting workflow. |
| Search help by a word | In help mode, enter a quoted word such as `"severity"`; this searches loaded documentation. |
| A longer details section | Type `??fit` from the Julia prompt to include its extended help. |
| `example(function_name)` | There is no standard one-to-one command. Read/copy the documented example or run an example script supplied by the package. |

The `?` shortcut is REPL syntax; do not paste `?fit` into a `.jl` script.
Use `@doc fit` to retrieve its documentation in ordinary Julia code or a notebook.
This retrieves help, including its full detail; it does not execute examples.
See the official [Julia help-mode guide](https://docs.julialang.org/en/v1/stdlib/REPL/#Help-mode)
and [documentation guide](https://docs.julialang.org/en/v1/manual/documentation/).

The manual's API pages render the package's docstrings. The short REPL help and
the web reference therefore share their source; the introductory chapters add
the conceptual explanation and reading order. Blocks marked as *doctests* are
examples whose displayed results can be checked during documentation builds.
Merely opening help does not run those checks.

For an executable first example in this development checkout, run:

```sh
julia --project=. examples/inspect_ratings.jl
```

Or, in a Julia session that has loaded this same package revision:

```julia
include(joinpath(pkgdir(BayesianMGMFRM), "examples", "inspect_ratings.jl"))
```

Both forms print the rating counts, category order, validation issues and model
equation. They run no MCMC and write no files. `include` executes a script; other
examples such as `minimal.jl` do fit models and save results, so read their
description before running them. New development examples may be absent from
an older installed release.

You can also [download the no-fit example](assets/visual-guide/inspect_ratings.jl)
from this preview and run `include("inspect_ratings.jl")` in a Julia session
with BayesianMGMFRM loaded.

One important default is easy to miss: `fit(spec)` currently selects
`backend = :julia`, meaning random-walk Metropolis. The minimal fitting example
explicitly chooses `backend = :advancedhmc` for Julia NUTS. A backend called
“Julia” is not itself a sampler algorithm, and the default `chains = 1` is not
sufficient for between-chain convergence checks.

## Check your understanding

If two people received the same average score but faced different raters,
their adjusted ability estimates need not be equal. If a model reports finite
intervals despite a weak design, inspect how the priors identify and regularize
the parameters. If a richer model predicts better, ask whether the improvement
answers your intended prediction question and whether its ability estimates
are interpretable and precise enough for the proposed use.

Continue with [How Rating Models Work](rating-model-theory.md), or go directly
to [Reading Results and Comparing Models](interpreting-results.md) if you are
already comfortable with probability models.
