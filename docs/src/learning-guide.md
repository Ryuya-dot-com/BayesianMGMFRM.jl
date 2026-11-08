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

## [Facets, levels and dimensions are different](@id facets-levels-dimensions)

Five raters are five **levels** of the rater facet. Five facets are five kinds
of influence: for example, person, task, rater, scoring criterion and occasion.
Five ability **dimensions** instead describe five latent traits of each person.
Increasing one of these counts does not automatically increase the others.

Consider a student who performs a task on two occasions. Several raters score
each performance for accuracy and fluency. Decide what each role means before
choosing columns or a model:

| Role | Possible model meaning | What must be decided |
| --- | --- | --- |
| Person | Ability to be measured | One trait or several; stable ability or change over time |
| Physical task | Difficulty of the eliciting task | Shared across criteria or criterion-specific |
| Rater | Severity, and possibly consistency | Which effects the chosen model estimates |
| Criterion | Scoring dimension, location and/or category steps | Which role it has in Q and which thresholds it owns |
| Occasion | A systematic shift between measurement occasions | Common shift, individual growth or rater drift are different models |
| Response ID | The performance shared by several ratings | An observation/dependence identifier; not automatically another estimated effect |

The public rating workflow uses `person`, `item` and `rater` as model roles.
Metadata such as `task` or `occasion` preserve information but do **not** add
task difficulty, change over time or shared-response dependence to the likelihood.
Likewise, joining task and criterion labels into an item ID does not separately
estimate their two effects. A general fitted five-facet composition is not yet
available through the public API; see [the support boundary](scope.md#Current-Support).

Why does assignment matter? If task A occurs only at the first occasion and
task B only at the second, a score difference can be attributed to task or
occasion. Even many ratings may not separate them. Shared tasks across occasions
can help, under a model that makes the required stability assumptions. A proper
prior can regularize this ambiguity; that is different from the ratings
identifying the effects. Inspect the intended training split as well as the
complete dataset. More sampling cannot replace missing design information.

For a small simulation, first name the effects, scale, threshold owner and
constraints, then check whether the allocation separates them. Only after a
generator and matching fitter exist should you evaluate bias, interval coverage,
failure rates and cost. A few successful fits do not establish recovery or SBC.
The package's current [recovery operations](scope.md#common-operation-support)
evaluate supplied fits and truths; they are not an automatic five-facet
simulation or study-planning service.

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

For a multidimensional analysis, also check which dimensions were actually rated
for each person. A connected overall design can still leave one person's second
ability unmeasured. The [worked dimension-support check](data-validation.md#person-dimension-support)
shows how to find that person and keep the Q rows aligned with item names before
running MCMC.

The design also matters. If one group of people is rated only by R1 and another
only by R2, the ratings may not separate severity from group differences. Shared
tasks and overlapping assignments must provide enough information to separate
the effects. More MCMC draws cannot create that information. The current fitter
requires connectedness and the design-rank checks to pass even with anchors;
anchors do not bypass these checks. Passing them does not guarantee useful
precision or remove bias from selective rater assignment.
See [Data Validation](data-validation.md) for coverage, linking and missingness checks.

## [Choose a reference or fix an external calibration](@id references-and-anchors)

**You do not need external anchor values to run the first analysis.** In that
example, R1 is set to zero so that R2's severity means the difference from R1.
Zero is a reference point, not evidence that R1 is perfectly accurate or unbiased.
The one-dimensional MFRM also sets the first item to zero and centers the category
steps. Check the actual reference labels in `model_manifest(getdesign(spec))`.

An external calibration asks a different question: *can new ratings be analyzed
while retaining a previously established rater or item value?* A **hard anchor**
holds that value fixed throughout estimation. Use it only when treating the
value as exact is appropriate for the analysis and its scale and meaning match.

| Setting | Meaning in this package |
| --- | --- |
| Default reference | Choose zero for the first rater and first item. These coordinates are not estimated. |
| Hard anchor | Fix a named rater severity or item difficulty at a supplied logit value. It replaces the default reference in that facet. |
| Starting value (`init`) | Choose where sampling begins; the free parameter can move during estimation. |
| Soft anchor | Express external calibration uncertainty through an informative prior. This is not implemented by the current anchor-fitting route. |

Some multidimensional design records use the term `prior_anchor` for an ability
prior that defines the scale. That is a distributional assumption, not a fixed
external calibration or support for the `anchors` option in that model.

### Inspect an anchor before fitting

The following code uses the supplied first-analysis data and performs no fitting.
The value `0.25` is hypothetical; it is not an estimate or an externally validated
calibration for these artificial raters.

```julia
using BayesianMGMFRM
include(joinpath(pkgdir(BayesianMGMFRM), "examples", "first_analysis.jl"))
data = FirstMFRMAnalysis.inputs().data

anchored_spec = mfrm_spec(data;
    thresholds = :partial_credit,
    anchors = [(block = :rater, level = "R2", value = 0.25, type = :hard)],
)
plan = anchor_refit_plan(anchored_spec; require_provenance = false)
plan.numerical_fit_supported   # true: this declaration has a fitting route
anchored_design = getdesign(anchored_spec)
model_manifest(anchored_design; view = :public).design.fixed_coordinates
# R2: 0.25, hard_anchor; I1: 0.0, reference_zero; neither is sampled.
anchored_design.parameter_names
# Includes rater[R1] and rater[R3], but not rater[R2].
```

R1 is now free: declaring R2's anchor does **not** also keep R1 fixed at zero.
To anchor an item instead, use `block = :item` and its actual level label.
The same declaration syntax is supported with `thresholds = :rating_scale`. In partial-credit
models, fixing item difficulty fixes only the item's location; it does not fix
that item's category-step pattern. Item difficulty alone is therefore not a
complete imported calibration of a PCM item.

[`anchor_refit_plan`](@ref) checks the declaration; it does not fit the model
or establish that the calibration is valid. Its optional provenance checks
inspect recorded source fields, not the original source bytes. See the
[external-calibration contract](migration-facets-conquest.md#Anchor-constrained-refitting-policy)
for scale/sign conversion and source records. After choosing the prior and
sampling settings, the existing [`fit`](@ref) function accepts `anchored_spec`;
an anchored specification needs its own fit. The first-analysis cache and its
R2−R1 interpretation cannot be reused for a changed specification.

### What the resulting uncertainty means

An anchored value has no estimated SE or credible interval. Reports separate
fixed coordinates from posterior estimates; an interval with identical endpoints
in a data table denotes a fixed value, not perfect empirical precision. Uncertainty
in an external calibration is not propagated to the other estimates. Read the
[fixed-coordinate report](fitting.md#Fixed-coordinates-and-anchors) alongside the
posterior summaries.

One anchor in a facet chooses that facet's origin at the likelihood level.
Two anchors in the **same** facet also fix their difference: fixing R1 at zero
and R2 at 0.25 imposes a severity difference of 0.25 rather than estimating it.
More anchors are not automatically better. Calibration drift or incompatible
anchor values can alter the analysis; assess that assumption against the study's
purpose and external evidence. The zero-centered priors on free coordinates
are not shifted automatically when the reference changes, so a change of origin
that preserves likelihoods need not preserve the posterior.

The fitted anchor route is limited to **one-dimensional MFRM**, with rating-scale
or partial-credit steps and individual rater/item hard anchors. It does not fit
person, category-threshold, group-mean or soft anchors, or anchors in GMFRM and
multidimensional MFRM/MGMFRM. A displayed declaration or a successful
[`anchor_linking_summary`](@ref) is not evidence that such a model can be fitted.
For the supported route, unknown or duplicate targets and invalid fixed values
are rejected before fitting. Anchors also cannot be used to bypass disconnected
data or insufficient design rank in this implementation.

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

To connect that declaration to data and fitting, use the
[bundled MGMFRM example](examples.md#Start-with-the-bundled-MGMFRM-data).
Its inspection command shows the actual item assignment, incomplete rating
table, prior and four-chain settings without starting estimation. Its fitting
command uses those same inputs and saves dimension-specific estimates.

Several active dimensions within one item are called *within-item*
multidimensionality. This structure is distinct from a compensatory or
non-compensatory response rule, and from correlation between abilities. See the
[worked explanation](rating-model-theory.md#Compensatory-and-non-compensatory-response-rules)
before interpreting these labels.

## Check what this package can currently fit

After constructing a specification, enter `spec` at the Julia prompt. In a
script or notebook, the following prints the same explanation:

```julia
show(stdout, MIME"text/plain"(), spec)
println()
```

Read the slope line, the owner of the category steps and the fitting entry.
The display also keeps design/Q warning counts and any validation-only terms
visible. It uses the existing specification; it does not estimate parameters
or select priors. An available fitting entry describes implementation support,
not evidence that the model is appropriate for your ratings.

Some existing option names need care:

| Option or function | Meaning to check |
| --- | --- |
| `mfrm_spec(...; family=:mgmfrm)` | The `family` option chooses the model; the constructor retains its original name. |
| MGMFRM `discrimination=:none` | Positive loadings at active Q cells and rater consistency are still estimated. This compatibility selector does not request unit slopes. |
| GMFRM `discrimination=:rater` | The model estimates both item discrimination and rater consistency. |
| `bias=[(:rater, :item)]` | Requests cell/design checks. It does not fit rater-item interactions; those use the separate [joint-interaction workflow](@ref "Jointly fitted rater-by-item effects (experimental)"). |
| `backend=:julia` | Random-walk Metropolis. Request Julia NUTS with `backend=:advancedhmc`; stable bare `fit(spec)` currently uses one random-walk chain. |

The specification display concerns the base `FacetSpec`. If you subsequently
apply a correlation or slope-restriction wrapper, inspect that wrapper's
documented contract; the original specification does not describe those changes.

The stable fitting workflow covers one-dimensional MFRM with rating-scale or
partial-credit steps. GMFRM, multidimensional MFRM and MGMFRM are experimental.
Estimated ability correlation is available through the documented two-dimensional
between-item models and the restricted three-dimensional pure-Q model
([Correlations among Three Traits](correlated-3d.md)); broader correlation
structures or four or more correlated dimensions are not supported.

The prediction and model-comparison functions described in this manual are
development interfaces not yet included in a registered release. Their presence
does not establish that any model is scientifically preferable. Read
[Scope and Releases](scope.md) for the exact restrictions and use documentation
matching your installed revision.

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
example. Then follow the [first MFRM analysis](examples.md#First-MFRM-analysis),
which answers one question using 72 supplied artificial ratings. With this
checkout's dependencies installed, run from its root:

```sh
julia --project=. examples/first_analysis.jl
```

The worked result has an estimated R2−R1 severity difference of about 0.180
logit and a 90% interval from −0.511 to 0.889. Positive values mean greater
severity for R2. The interval spans both directions, so these ratings do not
clearly establish which rater is more severe. That is an answer with uncertainty,
not a software failure or proof that the raters are equivalent.

The example checks computation before giving that interpretation, saves a
plain-English answer and the fitted model, and reloads them. Its four chains
and explicit priors reproduce the documented teaching setup; the walkthrough
explains their meaning and how to inspect the saved result without refitting.
The [Bayesian Workflow](bayesian-workflow.md) covers the additional checks needed
for your own study, including prior implications and sensitivity.

## [New to Julia? A 5-Minute Guide for R, Python, and FACETS Users](@id julia-for-beginners)

You do not need prior Julia programming experience to run a many-facet analysis
in `BayesianMGMFRM.jl`. The four short notes below cover everything required to
read the examples, adapt them to your own rating data, and avoid first-time
pitfalls.

### 1. Project environments and starting Julia (`--project`)

Julia manages package versions per project folder using two text files—`Project.toml`
(direct dependencies) and `Manifest.toml` (exact locked versions, similar to R's
`renv.lock` or Python's `uv.lock`). Keeping one folder per study ensures that
your analysis remains reproducible across sessions:

```julia
using Pkg
Pkg.activate("my-rating-study")                     # Create or switch to an isolated project folder
Pkg.develop(path="path/to/BayesianMGMFRM.jl")       # Link this local package checkout
```

From a terminal, start Julia with `--project=.` inside that folder (or pass the
folder path as `--project=my-rating-study`) so the same environment is active
whether you work interactively or run a script:

```sh
julia --project=my-rating-study my_analysis.jl
```

### 2. Essential Julia syntax in 60 seconds

| Concept | In R / Python / FACETS | In Julia (`BayesianMGMFRM.jl`) | Why it looks this way |
| --- | --- | --- | --- |
| **Column names and option flags (`:symbol`)** | `"examinee"`, `"partial_credit"` | `:examinee`, `:partial_credit` | A leading colon creates a `Symbol`—an lightweight identifier used for table columns, facet names, and model options. |
| **Keyword arguments after `;`** | `f(data, person = "examinee", rater = "rater")` | `FacetData(ratings; person = :examinee, rater = :rater, item = :item, score = :score)` | The semicolon `;` separates positional inputs (`ratings`) from named keyword options. (Julia also accepts `,` before keyword arguments when unambiguous.) |
| **Accessing fields in results (`.` notation)** | `validation$passed` (R) / `validation.passed` (Python) | `validation.passed`, `receipt.sha256` | Functions return structured `NamedTuple`s or model structs whose fields are read with `.field_name`. Type ` propertynames(x)` or `keys(x)` to list available fields. |
| **Input rating tables** | `data.frame` / `pandas.DataFrame` / FACETS `Data=` | Any column-addressable table (`DataFrame`, `Dict`, or a `NamedTuple` of column vectors `(; examinee=[...], rater=[...], item=[...], score=[...])`) | `FacetData` reads columns by `:symbol` name (`table.col`, `table[!, :col]`, or `table[:col]`). Small examples use built-in `(; examinee=["P1", ...], ...)` column tuples so they run with zero extra dependencies. |
| **Running a script file** | `source("script.R")` | `include("script.jl")` | Evaluates the file in your active Julia session. |

### [Use Julia help and examples](@id Use-Julia-help-and-examples)

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

### 4. Three common pitfalls for first-time Julia users

1. **First-call compilation time ("time-to-first-fit"):**
   Julia compiles functions to machine code the first time they are called in a
   new session. The first call to `fit` or `BayesianMGMFRM.plot` therefore
   includes several seconds of compilation overhead; subsequent calls in the
   same session run at compiled speed.
2. **Always specify `backend = :advancedhmc` and `chains = 4` for substantive fits:**
   Calling bare `fit(spec)` without keywords selects `backend = :julia`
   (a single-chain random-walk Metropolis sampler intended only for lightweight
   interface checks). For real Bayesian inference and between-chain convergence
   diagnostics, pass explicit NUTS controls:
   `fit(spec; backend = :advancedhmc, chains = 4, warmup = 500, ndraws = 500, seed = 20260718)`.
3. **Load `CairoMakie` before calling `BayesianMGMFRM.plot`:**
   Plotting is packaged as an optional extension so core estimation stays fast
   to load. Install `CairoMakie` once in your project (`Pkg.add("CairoMakie")`)
   and run `using CairoMakie` before calling `BayesianMGMFRM.plot(fit_result; kind = :wright)`.

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
