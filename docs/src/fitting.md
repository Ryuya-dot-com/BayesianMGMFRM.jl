# Bayesian Fitting

`BayesianMGMFRM.jl` fits identified MFRM/RSM/PCM designs and exposes two narrow
generalized configurations behind explicit experimental opt-in. Validate data
before sampling; inspect the compiled design when reviewing identification or
model structure. The [minimal example](examples.md#Minimal-MFRM-Workflow) runs
the ordinary fit, diagnostics, figures and save/reload sequence.

## Supported MFRM/RSM/PCM Fit

```julia
using BayesianMGMFRM

ratings = (
    examinee = ["E1", "E1", "E1", "E1", "E2", "E2", "E2", "E2"],
    rater = ["R1", "R2", "R1", "R2", "R1", "R2", "R1", "R2"],
    item = ["I1", "I1", "I2", "I2", "I1", "I1", "I2", "I2"],
    score = [0, 1, 2, 0, 1, 2, 0, 2],
)

data = FacetData(ratings;
    person = :examinee,
    rater = :rater,
    item = :item,
    score = :score,
    category_levels = 0:2,
)
validation = validate_design(data)
validation.passed || error(validation)

spec = mfrm_spec(data;
    thresholds = :partial_credit,
    validation_report = validation,
)

fit_result = fit(spec;
    backend = :advancedhmc,
    ndraws = 500,
    warmup = 500,
    chains = 4,
    seed = 20260718,
)
```

The rating-scale and partial-credit threshold regimes share the same workflow.
`fit(spec)` constructs the design internally; use `getdesign(spec)` when you
want to inspect it separately.
Declaring `category_levels` preserves the form's intended threshold count when
an endpoint is absent from the realized sample. Inspect
`ordinal_response_pattern_audit(data).category_scale` and validation warnings
before fitting; do not reduce the scale merely to remove an empty category.
Inspect [`constraint_table`](@ref), [`identification_declarations`](@ref), and
[`model_manifest`](@ref) when reviewing the parameterization.

## Posterior interval figures

Install the optional renderer once with `Pkg.add("CairoMakie")`. It is not
required for fitting, summaries, or saved reports. With the fit above:

```julia
using CairoMakie

figure = BayesianMGMFRM.plot_posterior(fit_result; block = :rater, interval = 0.95)
display(figure)
content(figure[2, 1]).xlabel = "Rater severity"
save("rater-posterior.pdf", figure)
save("rater-posterior.svg", figure)
```

The returned Figure can be edited using CairoMakie. Points are posterior
medians; bars are central credible intervals, not predictive intervals or
Monte Carlo error bars. Fixed identification values are labelled and shown as
diamonds without intervals. External anchor uncertainty is not propagated.
The diagnostic note concerns the whole fit, including parameters outside the
selection; an interval figure does not establish convergence.

Use `block = :person`, `:rater`, `:item`, or `:thresholds` for MFRM, or choose
exact names with `parameters = ["rater[R2]", "rater[R1]"]`. Names must match
your data. Explicit names set the order within each axis. Blocks have separate
axes; model-scale figures include fixed reference values and the derived last
threshold. `scale = :raw` instead shows the coordinates in `posterior_summary`
and does not change that function's defaults. A selection above 60 coordinates
asks you to narrow it or set `max_parameters` explicitly; no rows are silently
dropped. Use `size = (900, 600)` to set the figure dimensions.

Figures can be regenerated from an existing fit cache without rerunning MCMC:

```julia
save_fit_cache("analysis-fit.jls", fit_result)
reloaded = load_fit_cache("analysis-fit.jls")
figure = BayesianMGMFRM.plot_posterior(reloaded; block = :rater)
```

The same qualified function accepts the existing experimental generalized fit
types. Their model coordinates use transformed draws; `scale = :raw` is an
explicit computational view. MGMFRM accepts a dimension index or declared
label, for example `dimension = 2`, and keeps dimensions on separate axes.
Plotting does not expand the supported model configurations.
The [guarded examples](examples.md#Saved-Generalized-Fits-and-Figures) demonstrate
model-scale intervals, raw-coordinate diagnostics and named-dimension selection
from saved GMFRM/MGMFRM fits, with either Julia or CmdStan estimation.

## Chain diagnostic figures

Use the same optional renderer to inspect retained draws without reshaping them:

```julia
chains = BayesianMGMFRM.plot_diagnostics(fit_result; block = :rater)
display(chains)
save("rater-chains.pdf", chains)
save("rater-chains.svg", chains)
```

Each selected coordinate has a trace and a rank histogram. Chain colors and
line styles agree across panels. The trace retains the stored chain and
iteration identities; plotting does not thin, subsample, or refit. The default
`scale = :raw` helps inspect computational coordinates. Use `scale = :model`
for transformed parameters. `block`, `dimension`, and exact `parameters` names
work as in the interval figure. The default limit is 12 selected coordinates;
choose a subset or explicitly increase `max_parameters`.

Ranks are pooled across chains for each coordinate, with average ranks for
ties. Each chain's bin fractions sum to one. The gray line is the pooled
histogram, so ties remain visible instead of being randomly separated. Set
`bins = 10` to change the bin count (capped at total retained draws). Compare
chain distributions alongside the trace and numerical diagnostics; similar
rank histograms alone do not establish convergence. Single-chain, fixed-value,
and constant-draw rank comparisons are explicitly unavailable or inapplicable.
The [bayesplot explanation of trace and rank plots](https://mc-stan.org/bayesplot/reference/MCMC-traces.html)
provides further context for interpreting these views.

Parameter captions use existing rank-normalized R-hat and bulk/tail ESS rows.
Derived constraint coordinates without such rows are labelled unavailable.
The footer retains whole-fit warnings and extrema even when only one parameter
is shown, plus per-chain reported divergence counts, maximum-depth hits and
E-BFMI. Missing or incomplete sampler statistics remain unavailable; these
panels do not create missing telemetry. Experimental fits use their recorded
diagnostic settings and the same compatibility checks as `diagnostics`.

Warmup parameter draws are not stored and are excluded from these plots. Use
`sampler_diagnostics(fit_result; phase = :warmup)` for separate adaptation
summaries. A fit reloaded with `load_fit_cache` works with the same plotting
call; the editable Figure and PDF/SVG workflow are unchanged.

## Posterior predictive figures

Check whether the fitted model reproduces overall category use:

```julia
predictive = BayesianMGMFRM.plot_predictive(fit_result; ndraws = 200, seed = 42)
display(predictive)
save("category-predictive.pdf", predictive)
save("category-predictive.svg", predictive)
```

Black diamonds show observed category proportions. Blue circles show the mean
proportion across replicated datasets; bars show 90% pointwise central predictive
intervals by default. Set `interval = 0.95` to change their width. Categories
with no observed ratings remain visible. The replication preserves the original
rating rows and uses posterior draws of their fitted persons, items and raters;
it does not generate new facet levels or refit the model.

An observed proportion outside its bar identifies a discrepancy to investigate.
These bars describe replicated category proportions, rather than parameter
uncertainty or Monte Carlo error. They are pointwise intervals, not a simultaneous
band or an overall model-acceptance rule. Overall category use can conceal
differences between raters or items. Inspect the fit's diagnostics and relevant
facet summaries alongside this check. See the
[Stan guide to posterior predictive checks](https://mc-stan.org/docs/stan-users-guide/posterior-predictive-checks.html)
for the distinction between replicated data and parameter draws.

With no selection option, the figure uses every retained draw once, in stored
order. `ndraws = 200` samples 200 draw indices with replacement from the retained
draws. Alternatively, pass `draw_indices = [1, 4, 10]` for exact ordered indices;
repeated indices generate new responses from the same parameter draw. Supply
only one selection option. The caption distinguishes replicated datasets from
the number of distinct posterior draws used. Generating more replications does
not add posterior draws. For large fits, `ndraws` bounds the number of replicated
datasets held in memory.

Each call uses a local `MersenneTwister` with `seed = 1` by default and leaves the
global RNG unchanged. Reuse the same fit, seed and selection options in the same
Julia/package environment to replay the result. Changing only `interval` or
Figure labels does not change the simulated scores. For matching numerical rows:

```julia
using Random
check = posterior_predictive_check(fit_result; ndraws = 200, rng = MersenneTwister(42))
rows = predictive_check_summary(check; interval = 0.9)
```

The figure displays the category-proportion rows from this summary. The same
plotting call accepts `load_fit_cache("analysis-fit.jls")`; retain the seed and
selection arguments with your analysis code. The returned native Figure can be
edited and saved without simulating again. Whole-fit MCMC warnings remain in its
caption. Stable MFRM and the existing experimental GMFRM/MGMFRM fits retain their
respective support limits; this conditional check does not establish performance
for new persons, items or raters.

## Wright map

For a stable MFRM rating-scale or partial-credit fit, compare persons, raters,
items and category boundaries on one logit scale:

```julia
wright = BayesianMGMFRM.plot_wright(fit_result; interval = 0.95)
display(wright)
save("wright-map.pdf", wright)
save("wright-map.svg", wright)
```

Each panel uses the same linked vertical axis. Higher person ability increases
adjacent-category log odds; higher rater severity or item difficulty decreases
them. The `+` and `-` panel headings identify those effects; plotted severity
and difficulty retain their original signs. The figure uses the fit's identified
coordinates without recentering. Horizontal positions identify levels in their
original order; horizontal spacing has no measurement interpretation.

Circles are posterior medians and bars are central credible intervals. Diamonds
mark fixed references or hard anchors, with no interval; external anchor
uncertainty is not propagated. The whole-fit diagnostic note remains visible.
A visually plausible map does not establish convergence or model adequacy.

The boundary panel shows **item difficulty plus category step**, summed within
each draw before computing intervals. This preserves joint item/step uncertainty.
At zero rater severity, a person at that position has equal probabilities for
the two adjacent categories shown in the label. Those probabilities need not
each be 50% when other categories exist. These are neither expected-score
half-points nor predictive intervals. For another rater, add that rater's
severity to the boundary, propagating its uncertainty in any numerical analysis.
Zero severity remains the figure's reference even when all raters have nonzero
estimates or anchors. The [Facets Wright-map documentation](https://www.winsteps.com/facetman64/table6_0.htm)
illustrates the facet-orientation convention; its expected-score scale column
has a different interpretation from this boundary panel.

`facets = (:person, :item)` chooses panels and their order. Set
`include_thresholds = false` to omit boundaries; otherwise boundaries for every
item are included independently of facet selection. All declared category
transitions remain present, even when a category has no observed scores.
More than 60 positions raises an error. Narrow the facet selection, omit
boundaries, or explicitly increase `max_levels` and adjust `size = (1600, 900)`.
No levels are silently dropped. GMFRM and MGMFRM fits are explicitly unsupported.

The map uses all retained draws without random selection or refitting. The same
call accepts `load_fit_cache("analysis-fit.jls")`; the returned Figure is editable.
`wright_map_data(fit_result; interval = 0.95)` supplies matching numerical rows.
In threshold rows, `status` describes the step constraint while `is_fixed` and
`fixed_value` describe the full item-step position. A derived step is uncertain;
even a fixed binary step has an uncertain position when its item is estimated.

## Fixed coordinates and anchors

For a stable MFRM fit with exact item or rater hard anchors, inspect the public
report directly:

```julia
report = fit_report(fit_result; view = :public)
report.fixed_coordinates.rows
report.fixed_coordinates.warning_rows
```

The rows include both default reference coordinates and declared hard anchors.
Every row states that the coordinate is unsampled, prior-free, and not a
posterior estimate. A hard-anchor fit contributes two baseline warnings to the
structured report and to the prominent `Warnings` block in
`fit_report_markdown(report)`: one marks fixed coordinates as constants, and
the other states that `MFRMPrior` remains zero-centered on free identified
coordinates. Thus changing an anchor value can change prior and posterior
predictions even when a likelihood-equivalent reparameterization exists. The
fixed-value warning also states that uncertainty from an externally estimated
anchor is not propagated into this fit.
When two or more anchors occur in the same facet, a third warning states that
within-facet contrasts have been fixed and require contamination or drift
sensitivity; one rater plus one item anchor does not trigger that warning.
Posterior-summary rows continue to contain only estimated coordinates.

The same stable MFRM report includes practitioner-facing category and rater
sections by default:

```julia
report = fit_report(
    fit_result;
    view = :public,
    category_functioning_min_count = 5,
    rater_severity_rope = nothing,
)
report.category_functioning.usage_rows
report.category_functioning.threshold_rows
report.rater_homogeneity.contrast_rows
```

Category flags are review prompts, not an automatic category-collapse,
recoding, or refitting rule; any flagged rows contribute one aggregate warning.
No universal severity ROPE is assumed for rater contrasts. The default
`rater_overlap_unit = :person_item` is a proxy rather than proof that two raters
scored the identical response when repeated occasions exist; use
`:response_id` or `:response_item` with declared response identifiers when
common-response linking is the intended claim. Each contrast labels its rater
coordinates as `reference_zero`, `hard_anchor`, or `estimated`. A contrast
between two fixed coordinates is an exact constant rather than a posterior
estimate: `n_uncertainty_draws` is zero, the interval is not applicable, and
its interval probability and quantile-probability fields are missing;
sign/ROPE probabilities are deterministic. With one fixed coordinate,
posterior uncertainty comes only from the estimated coordinate. Set
`include_category_functioning = false` or
`include_rater_homogeneity = false` to disable either section independently.
For a one-rater fit, the rater section is still computed but contains zero
contrast rows and reports `not_applicable_single_rater`; an empty comparison is
not evidence of rater homogeneity. Generalized fits do not request these
stable-only sections by default, and an explicit request returns `unsupported`.
Public JSON, table, and bundle exports preserve the zero-row contrast table.
Markdown keeps the section summary but omits empty table previews by default;
use `fit_report_markdown(report; include_empty = true)` when an explicit
zero-row table marker is required.

With `thresholds = :partial_credit`, a declared but unobserved endpoint remains
in category usage rows as `observed_flag = :skipped`, while item-specific step
rows continue to cover the complete declared scale. This is a review prompt,
not authorization to narrow the scale or collapse the category.

## Backends and Sampler Controls

[`fit`](@ref) supports:

- `backend = :julia` for a simple random-walk Metropolis implementation;
- `backend = :advancedhmc` for direct AdvancedHMC/NUTS sampling;
- `backend = :turing` for the package target wrapped in Turing/NUTS;
- `backend = :cmdstan` for stable MFRM/RSM/PCM and both guarded generalized
  configurations through an external CmdStan installation. Use
  `BayesianMGMFRM.Experimental.fit` for GMFRM/MGMFRM.

Run `cmdstan_backend_check()` to inspect CmdStan, `stanc`, `make`, and C++
compiler availability without compiling a model. The first fit for a supported
family compiles its package-owned Stan model into a temporary machine-local
cache. It uses the same Julia raw/identified parameter order and prior scales, imports the
standard CmdStan sampler columns, and checks generated pointwise log likelihoods
against Julia at every retained draw. `target_accept` maps to CmdStan's
`adapt delta`; thinning remains one. CmdStan failures raise `CmdStanError`
instead of being converted to a missing result.

Supply a new empty `cmdstan_cache_dir` for each CmdStan fit. Compiled-model
reuse is currently disabled pending verified build evidence; a populated
directory is preserved and rejected, as is a symlink root. The default
directory cannot be reused after a build attempt leaves files. A fresh model
directory does not isolate CmdStan's shared build products or verify build provenance.

`MAKE` selects one executable name or path, not a shell command with arguments.
Compilation requires `MAKEFILES`, `MAKEFLAGS`, and `GNUMAKEFLAGS` to be unset
or exactly empty; even whitespace or parallel-build flags are rejected. The
readiness check does not enforce this compile-time policy. See
[`cmdstan_backend_check`](@ref) for discovery and toolchain details.

For both guarded generalized families, every retained raw draw is transformed
through the Julia identification map before the common fit, diagnostics, and
prediction interfaces are built. Unwrapped MGMFRM specifications remain fixed-Q
with identity correlation. The [explicit correlated MGMFRM](experimental.md#correlated-mgmfrm-explicit-fitting-and-saved-results)
uses a separate result type and currently supports summaries, diagnostics, MCSE
and manual caches, plus prior and conditional existing-row posterior prediction.
Reader-facing reports, tables and optional CairoMakie figures retain the saved
prior, model identity and sampling warnings.
`cached_fit` and parallel chain execution are not
yet connected to CmdStan. CmdStan remains optional for package
installation, and no backend is declared faster or more accurate without a
same-target analysis.

Use short runs only to verify wiring. For substantive work, choose the number
of chains, warmup, retained draws, target acceptance, tree depth, metric, and
initialization strategy before examining the results. Record a seed when exact
replay is part of the analysis plan.

The [runnable examples](examples.md) show stable and guarded fits with
`--cmdstan`, including saved-fit reload and optional figures.

Sampler success is necessary but not sufficient. Review:

- [`sampler_diagnostics`](@ref) for acceptance and HMC warnings;
- [`mcmc_diagnostics`](@ref) for parameter-level R-hat and ESS;
- [`posterior_mcse`](@ref) for on-demand mean, SD, and quantile simulation
  error after convergence review;
- [`parameter_block_diagnostics`](@ref) for block-level summaries;
- [`diagnostics`](@ref) for the compact overall status;
- prior and posterior predictive checks, calibration, and sensitivity results.

Very short chains commonly produce unreliable R-hat and ESS values even when
the example completes without an exception.

Inspect warmup separately from the retained posterior draws:

```julia
sampler_diagnostics(fit_result)                  # retained draws (default)
sampler_diagnostics(fit_result; phase = :warmup) # warmup events by chain
```

New AdvancedHMC, Turing and CmdStan fits record warmup iteration counts,
divergences, maximum-tree-depth hits and nonfinite log densities. Generalized
GMFRM/MGMFRM fits support AdvancedHMC and CmdStan. Random-walk fits record
`n_nonfinite_proposals` during burn-in, with no proposal-scale adaptation.
Their divergence, tree-depth and nonfinite-log-density fields are `missing`
because those NUTS statistics do not apply. The rows distinguish
`coverage = :recorded`, `:not_run` when `warmup = 0`, and `:not_recorded` for
fits without recorded history. Unavailable counts are `missing`.
Warmup events do not contribute to posterior summaries, R-hat/ESS or retained
sampler warning flags, and have no automatic pass/fail rule.

Turing adapts for exactly `warmup` transitions per chain, independently of
`ndraws`; `warmup = 0` disables adaptation. The initial state and every adapting
transition are excluded from posterior draws. Older Turing fits without
`sampler_controls.nadapts` used an automatic adaptation length tied to `ndraws`
and could include adapting transitions. Their warmup history is reported as
`:not_recorded`, even if zero warmup was requested. Re-estimate those fits for
analysis under the corrected schedule. Turing cache request keys distinguish
the corrected controls; `cached_fit(...; refresh = true)` replaces an older
cache through a new fit. Manual loading preserves historical draws and metadata.

`save_fit_cache` preserves these compact summaries and `load_fit_cache` restores
them; warmup parameter draws are not saved. Existing caches remain readable.
Turing temporarily buffers warmup transitions to produce the counts, then
keeps only the chain summaries. Recording preserves the corrected adaptation
schedule, retained draws and RNG stream. A corrected Turing cache created before
recording was added remains reusable with unavailable history; refresh it only
if that history is needed.
`cached_fit` can reuse an older cache with unavailable warmup history; request
`refresh = true` to collect it in a new fit. CmdStan fits can be saved/loaded
explicitly, but automatic `cached_fit` remains limited to its supported Julia
backends.

For random-walk fits, `sampler_diagnostics(fit)` reports
`n_nonfinite_proposals`: proposals with non-finite parameters or log density
are rejected while retaining the last valid state. The count covers retained
iterations and is distinct from NUTS divergences. It is `missing` for older
fits without this telemetry and for other samplers. Such proposals trigger a
sampler warning in `diagnostics(fit)`. Use `phase = :warmup` to see the separate
burn-in count. Warmup-only rejections do not trigger retained-draw warnings.
Random walk stores only one warmup counter per chain; recording preserves
retained draws and the RNG stream.

Failures during chain initialization, sampling and retained-output
validation identify the backend, chain and phase. Unexpected exceptions retain
their original cause and backtrace; initialization and output validation errors
keep their `ArgumentError` type with context added to the message. CmdStan
per-chain command and parser failures preserve the existing
`CmdStanError.stage` and `.reason` categories. A failed chain aborts the fit;
completed chains are not returned as a successful partial fit.
The `sampling` stage covers the library sampling call, including warmup and
retained transitions; an exception does not by itself identify the exact
iteration or whether adaptation had finished. If fitting fails inside
`cached_fit`, no new result is saved. With `refresh = true`, the previous cache
remains available unchanged.

The package's gradient, sampler and CmdStan adapters rethrow Julia
`InterruptException`, `OutOfMemoryError` and `StackOverflowError` as received.
`fit_report` also propagates these exceptions with the default section-error
capture policy.

On POSIX systems, each CmdStan build or sampling command runs in its own
process group. The adapter terminates remaining group members and waits for
its direct child on completion or interruption. This includes compiler and
wrapper descendants that stay in the group. On other systems, cleanup covers
the direct child only.

Julia's SIGINT policy is preserved. Capturable interrupts propagate as
`InterruptException`; default script SIGINT exits and explicit `exit()` calls
use an exit hook to clean up active commands. To catch SIGINT yourself in a
script, call `Base.exit_on_sigint(false)` before fitting. No completed command
is kept in the exit-cleanup registry.

Processes that create another session or process group escape this cleanup.
Forced Julia termination that bypasses exit hooks, such as SIGKILL, also
bypasses cleanup.

[`fit_metadata`](@ref) and [`diagnostics`](@ref) retain their complete existing
payload with the default `view = :full`. For a reader-facing structured result,
request `view = :public`. The public form identifies its schema, model family,
and stability level in a compact portable payload. Experimental fit metadata
reports the fitted configuration as `estimation_status = :experimental`.
Public generalized diagnostics retain raw-space, constrained-space, and
combined convergence metrics, parameter names, and scientific warning counts,
while omitting initialization identity hashes and repository artifact paths.
The public form is intended for tables and reports, while the full form remains
available when the complete fitting record is required.

## Experimental Generalized Fitting

Generalized fitting is deliberately outside this stable fitting surface. Use
the [Experimental Generalized Models](experimental.md) page for the scalar
item-discrimination × rater-consistency GMFRM and fixed-Q confirmatory MGMFRM
contracts, examples,
and migration guidance.

Both configurations require `thresholds = :partial_credit`.
Both configurations require no anchors and no fitted DFF terms. Scalar GMFRM
uses `discrimination = :rater`; fixed-Q MGMFRM uses the compatibility selector
`discrimination = :none`. Use
`BayesianMGMFRM.Experimental.GeneralizedPrior` to vary the independent normal
scales on raw unconstrained coordinates. Direct-scale generalized priors remain
unsupported. Run `BayesianMGMFRM.Experimental.prior_predictive_check` before
fitting to inspect score, category-use, and facet-range implications.
The legacy
`fit(spec; experimental = true)` form remains source-compatible, but
`BayesianMGMFRM.Experimental.fit` is the canonical entry point for new work.

## Predictive Checks and Model Comparison

Use [`prior_predictive_check`](@ref) before interpreting a fit and
[`posterior_predictive_check`](@ref) afterward. [`calibration_table`](@ref)
provides expected-score and category-probability calibration rows.

WAIC, LOO, PSIS-LOO, and K-fold summaries require a clearly stated prediction
target and compatible observations across compared models. Treat Pareto-k and
held-out diagnostics as part of the result. A numerical ranking alone is not a
scientific superiority claim.

## Reports and Reproducibility

[`fit_report`](@ref) collects metadata, diagnostics, design checks, posterior
summaries, predictive results, calibration, stable-MFRM category/rater
practitioner rows, and optional comparison rows.
It also includes a separate `warmup` table with chain-level adaptation counts
and recording status. Retrieve it with `fit_report_rows(report, :warmup)`;
public reports, Markdown, JSON tables and report bundles include it
automatically. The Markdown explanation distinguishes observed counts, no
requested warmup, and unavailable history. Missing counts remain JSON `null`
and blank Markdown cells. A `computed` warmup section means reporting
succeeded; it does not apply a warmup quality threshold or change retained
sampler warnings. Older reports without this section remain readable as saved.
The complete version-1 payload retains its fields for machine compatibility.
Use `fit_report(fit; view = :public)` or [`fit_report_public`](@ref) for a
portable report shared with readers. [`fit_report_markdown`](@ref) applies the
same projection. It preserves user-supplied person, rater, item, parameter,
category, and dimension labels, and its JSON-normalized content hash remains
stable after a save/load round trip.
Markdown tables use a common column order before and after reload: identifiers,
sampler coverage, estimates and uncertainty first, then other columns by name.
Report dossiers use the same order. JSON table fields and values are unchanged;
JSON object key order is not a display-order contract.
Report dossiers saved by v0.1.0 remain readable; loading converts them to the
same portable form before rendering or resaving.

Use [`fit_artifact`](@ref) for a hash-checked fit artifact and [`cached_fit`](@ref)
when cache identity is explicitly part of the workflow. The compatibility
default `view = :full` is the complete reproduction archive and can contain
repository- and environment-specific metadata; use
`fit_artifact(fit; view = :public)` when
sharing a reader-facing artifact. The same distinction applies to
[`model_manifest`](@ref) and [`fit_reproduction_manifest`](@ref): retain the
full view for a private reproduction record and request `view = :public` for a
portable public projection. A cache hit should be accepted only when model,
data, prior, initialization, backend, and sampler controls match the requested
fit.

[`sensitivity_comparison_summary`](@ref) also accepts `view = :public` for
compact reader-facing sensitivity results.

## Reports with figures

Load a saved fit and select the figures to include in the existing bundle:

```julia
using BayesianMGMFRM, CairoMakie
restored = load_fit_cache("analysis-fit.jls")
save_fit_report_bundle("analysis-report", restored;
    view = :public,
    require_complete = true,
    figures = (
        posterior = (block = :rater,),
        diagnostics = (block = :rater,),
        predictive = (;),
        wright = (;),
    ),
    ndraws = 200,
    seed = 42,
)
```

This example selects a stable MFRM fit. It writes the ordinary JSON report and
tables, plus `figures/posterior.pdf`, `.svg`, `.json` and corresponding files
for the other selected figures. `fit_report.md` embeds the SVGs, explains the
uncertainty and diagnostics, and links to PDFs and numerical inputs. Each PDF
contains one figure; this does not create a combined PDF manuscript.

Each figure entry accepts its usual selection and `size` options. Choose the
shared `posterior_lower`/`posterior_upper` central bounds (default 0.025/0.975),
`predictive_interval` (0.9), and `ndraws` or `draw_indices` on the bundle call.
Posterior and Wright figures use those posterior bounds. Predictive figures use
the exact category-summary rows already computed for the report, including
unobserved declared categories. Their intervals describe replicated category
proportions rather than uncertainty about a parameter. The local `seed`
(default 1) controls predictive simulation; use it instead of `rng` keywords
for a figure bundle. Rendering does not run MCMC or draw another predictive
sample. Diagnostic settings match the standalone plots; contradictory report
threshold overrides are rejected.

For GMFRM or MGMFRM, omit `wright`. An MGMFRM selection can be
`posterior = (block = :person, dimension = "communication")`, using the fit's
actual dimension label; the diagnostic entry accepts the same selection.
Generalized posterior figures default to model coordinates and diagnostics to
raw coordinates. The plotted subset and whole-fit warning remain visible.

Read or verify the output without CairoMakie:

```julia
report = load_fit_report_bundle("analysis-report"; require_complete = true)
manifest = load_fit_report_bundle("analysis-report"; return_manifest = true)
```

Figure bundles use manifest v2 and verify PDF, SVG and numerical-input hashes.
The JSON report/table formats and figure-free v1 bundles remain unchanged.
Older package readers reject v2. Numerical-input JSON includes the selected
coordinates and, for diagnostic figures, their retained values and chain/
iteration IDs. Keep this in mind when sharing row-level or person-labelled
outputs. Only files listed in the manifest are verified.

Keep the saved fit and analysis settings to regenerate a bundle in another
session. A summary-only JSON report cannot recreate traces; passing one with
`figures` gives an error directing you to the saved fit. To edit a native
Figure, use the existing `plot_*` functions on that fit, then save the edited
figure separately. See [figure editing](fitting.md#Posterior-interval-figures).

## FACETS-Compatible Descriptive Rows

[`facets_report`](@ref) and [`facets_compatibility_stats`](@ref) return a
separately labelled posterior-mean plugin summary for supported MFRM/RSM/PCM
fits. The rows use unit weights, Wright--Masters fourth-moment degrees of
freedom, and a capped Wilson--Hilferty transformation. They are approximate,
do not propagate full posterior uncertainty, and do not claim numerical
equivalence with FACETS. Generalized fits are rejected.

## Interpretation Boundary

- Diagnose rating-design support before interpreting facet differences.
- Separate statistical uncertainty from practical magnitude.
- Treat DFF output as screening unless a fitted, identified effect model is
  explicitly supported.
- Do not generalize fixed-Q results to exploratory multidimensional models.
- Report sampler warnings, prediction targets, prior choices, and unsupported
  model features alongside substantive results.
