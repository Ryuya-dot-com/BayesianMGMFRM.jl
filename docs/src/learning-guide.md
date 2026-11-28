# Understanding Facets and Model Choices

Use this chapter when choosing a model for your own study. For a complete
first example, start with [Your First Rating Analysis](first-analysis.md).
The explanations below cover design, references, dimensions and supported
model choices; they are not prerequisites for reading that tutorial.

When several judges score a performance, a low score can reflect ability, task
difficulty or rater severity. A many-facet model describes these influences
together and estimates their differences under stated assumptions.

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
estimate their two effects. The [additive-facets workflow](additive-facets.md)
can estimate user-named scalar main effects, including more than five facets.
It does not combine arbitrary interactions, multidimensionality and time processes;
check [the support boundary](scope.md#Current-Support) for the chosen model.

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

**You do not need external anchor values to run the first analysis.** Its standard
model uses sum-to-zero facet and step constraints, with estimated population
location and person SD. Neither R1 nor I1 is fixed to zero. The difference
between R2 and R1 is calculated from their joint posterior draws. Explicit
reference coding is a separate option; a zero reference does not mean that a
rater is perfectly accurate or unbiased.

An external calibration asks a different question: *can new ratings be analyzed
while retaining a previously established rater or item value?* A **hard anchor**
holds that value fixed throughout estimation. Use it only when treating the
value as exact is appropriate for the analysis and its scale and meaning match.

| Setting | Meaning in this package |
| --- | --- |
| Standard centered specification | Sum-to-zero facets/steps with estimated population location and person spread; no individual rater or item is pinned to zero. |
| Explicit reference coding | Set the chosen reference rater/item to zero. These coordinates are not estimated. |
| Hard anchor | Fix a named rater severity or item difficulty at a supplied logit value. Other levels in that facet remain free unless explicitly constrained. |
| Starting value (`init`) | Choose where sampling begins; the free parameter can move during estimation. |
| Uncertain external calibration | Propagate a supplied calibration covariance through the documented calibration-prior route; this differs from a hard anchor. |

Some multidimensional design records use the term `prior_anchor` for an ability
prior that defines the scale. That is a distributional assumption, not a fixed
external calibration or support for the `anchors` option in that model.

### Inspect an anchor before fitting

The following code uses the standard 1D specification and performs no fitting.
The value `0.25` is hypothetical, not an externally validated calibration for
these artificial raters.

```julia
using BayesianMGMFRM
ratings = include(joinpath(pkgdir(BayesianMGMFRM), "examples", "first_analysis_ratings.jl"))
anchored_spec = mfrm_spec(ratings;
    person = :person, score = :score,
    facets = (item = :item, rater = :rater), steps = :item,
    category_levels = 0:3, prior = :default,
    fixed_calibration = (facets = (rater = Dict("R2" => 0.25),),),
)
validate_design(anchored_spec)
design_summary(anchored_spec).fixed_calibration
```

The explicit calibration fixes R2's severity. It does not also pin an arbitrary
first rater to zero. After choosing the prior and sampler controls, pass this
specification to `fit`. A changed calibration needs its own fit; the unanchored
first-analysis cache cannot supply an anchored posterior.

### What the resulting uncertainty means

A hard anchor has no estimated SE or credible interval. Reports separate fixed
coordinates from posterior estimates. Identical interval endpoints for a fixed
value do not demonstrate perfect empirical precision, and a hard anchor does
not propagate uncertainty in the external calibration.

When external estimates carry uncertainty, consider the documented
[calibration and equating modes](equating-and-populations.md#four-equating-modes),
including covariance-aware calibration priors. A hard anchor, an uncertain
external calibration and a likelihood identification constraint have different
meanings; choose from the source of information and the intended comparison.
Multiple hard anchors also fix their differences. More anchors are not
automatically better: incompatible values or calibration drift can alter the
analysis. Validation checks the design and declarations, not the truth of an
external calibration.

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

After constructing the standard specification, inspect its design and prior:

```julia
design_summary(spec)
validate_design(spec)
```

Read the category support, facet/step constraints, population assumptions and
validation warnings. This uses the existing specification without estimation.
Available operations describe implementation support, not evidence that the
model is appropriate for your ratings.

For the standard table-based constructor, keep model and estimation choices separate:

| Option or function | Meaning to check |
| --- | --- |
| `prior=:default` | Builds the standard Bayesian specification; inspect its prior summary before fitting. |
| `slope=:rater` | Selects the scale-identified GMFRM route; consult its step-owner and slope conventions. |
| `q_matrix=...` | Declares the MGMFRM item–dimension structure; it does not discover dimensions from data. |
| `fit(spec; method=:nuts)` | Uses Julia NUTS on the standard Bayesian route. |
| `prior=:none`, then `fit(spec; method=:mmle)` or `:jmle` | Selects a prior-free specification and an explicit frequentist estimator, subject to its supported identification and design. |

The older `BayesianMGMFRM.Legacy.FacetSpec` route has different selectors (`family`, `discrimination`
and `backend`). Its `backend=:julia` default is random-walk Metropolis;
`backend=:advancedhmc` selects NUTS there. This is a legacy compatibility
default, not the standard table-based workflow. See [fitting](fitting.md)
before adapting an older script. Inspect any correlation or slope-restriction
wrapper's own contract as well.

The stable fitting workflow covers one-dimensional MFRM with rating-scale or
partial-credit steps. GMFRM, multidimensional MFRM and MGMFRM have
model-specific prior, Q-matrix and backend requirements; see [available models](scope.md).
Estimated ability correlation is available through the documented two-dimensional
between-item models and the restricted three-dimensional pure-Q model
([Correlations among Three Traits](correlated-3d.md)); broader correlation
structures or four or more correlated dimensions are not supported.

The prediction and model-comparison functions described in this manual are
development interfaces described for this snapshot. Their presence
does not establish that any model is scientifically preferable. Read
[Scope and Releases](scope.md) for the exact restrictions and use documentation
matching your installed revision.

**Julia versus CmdStan is a computation choice.** MFRM versus GMFRM versus
MGMFRM is a model choice. Changing the backend should preserve the intended
probability model, priors and constraints; matching a backend name or random
seed does not establish that those ingredients match.

## Follow one complete analysis path

[Your First Rating Analysis](first-analysis.md) follows one supplied dataset
from the question through fitting, figures and saving. For the individual
function calls or your own analysis, use the [Bayesian Workflow](bayesian-workflow.md).

## [New to Julia? A Practical Guide for R, Python, and FACETS Users](@id julia-for-beginners)

You do not need prior Julia programming experience to run a many-facet analysis
in `BayesianMGMFRM.jl`. These notes explain the syntax and project setup used in
the examples. Statistical model choices still require the accompanying guides.
Install Julia first, then follow the matching source-installation block on the
[home page](installation.md).

Run `julia` in your system terminal to obtain the `julia>` prompt (the REPL).
Paste `julia` code blocks there, without the prompt, or save them in a `.jl` script.
Run `sh` blocks in the system terminal, not at `julia>`. `pwd()` prints Julia's
working directory. `Pkg.activate` selects package dependencies; it does **not**
change that working directory. Replace placeholder paths with your actual paths.

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

### 2. Essential Julia syntax

| Concept | In R / Python / FACETS | In Julia (`BayesianMGMFRM.jl`) | Why it looks this way |
| --- | --- | --- | --- |
| **Column names and option flags (`:symbol`)** | `"examinee"`, `"partial_credit"` | `:examinee`, `:partial_credit` | A leading colon creates a `Symbol`—an lightweight identifier used for table columns, facet names, and model options. |
| **Keyword arguments after `;`** | `f(data, person = "examinee", rater = "rater")` | `FacetData(ratings; person = :examinee, rater = :rater, item = :item, score = :score)` | The semicolon `;` separates positional inputs (`ratings`) from named keyword options. (Julia also accepts `,` before keyword arguments when unambiguous.) |
| **Accessing fields in results (`.` notation)** | `validation$passed` (R) / `validation.passed` (Python) | `validation.passed`, `receipt.sha256` | Functions return structured `NamedTuple`s or model structs whose fields are read with `.field_name`. Type ` propertynames(x)` or `keys(x)` to list available fields. |
| **Input rating tables** | `data.frame` / `pandas.DataFrame` / FACETS `Data=` | Any column-addressable table (`DataFrame`, `Dict`, or a `NamedTuple` of column vectors `(; examinee=[...], rater=[...], item=[...], score=[...])`) | `FacetData` reads columns by `:symbol` name (`table.col`, `table[!, :col]`, or `table[:col]`). Small examples use built-in `(; examinee=["P1", ...], ...)` column tuples so they run with zero extra dependencies. |
| **Running a script file** | `source("script.R")` | `include("script.jl")` | Evaluates the file in your active Julia session. |

### [3. Use Julia help and examples](@id Use-Julia-help-and-examples)

Julia has built-in help for functions, types and modules. From the repository
root, start an interactive session with `julia --project=.` and load the package:

```julia
using BayesianMGMFRM
using BayesianMGMFRM.GlassBox
using BayesianMGMFRM.Legacy
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
   can include seconds to minutes of compilation overhead, depending on the
   operation and environment; subsequent calls in the
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
