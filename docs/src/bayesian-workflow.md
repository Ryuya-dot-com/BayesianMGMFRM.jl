# Bayesian Workflow

!!! note "Development manual"
    Use the [matching source and installation instructions](installation.md).
    This manual describes a development snapshot, not an accepted stable release.
    Model support and scientific acceptance remain as stated on each page.

For the first example and its figures, use [Your First Rating Analysis](first-analysis.md).
This guide explains individual API operations and decisions for adapting an
analysis to your own study. You need not run it after completing the tutorial.

## [Follow one analysis through the APIs](@id connected-analysis)

Keep one question in view: **is R2 more severe than R1 after accounting for the
people and tasks they rated?** The [first analysis](first-analysis.md) implements
this workflow. The steps below expose its connections; use the saved fit if you
have already run `FirstMFRMAnalysis.main()`.

| Step | Operation | Decision before continuing |
| --- | --- | --- |
| Prepare and inspect | Rating table → `mfrm_spec(...; prior = :default)` → `validate_design` and `design_summary` | Are categories, identifiers, assignment and the model appropriate? Resolve errors and retain warnings. |
| Estimate and preserve | `fit(spec; controls...)` → `save_fit` and portable handoff export | Did estimation return and persist? A completed progress bar does not establish convergence. |
| Read uncertainty | `qualify`, `diagnostics`, `contrast` and its `mcse` fields | Do the whole-fit diagnostics and focal numerical precision support interpretation? |
| Assess assumptions | `predictive_check`, `criteria`, and separately justified prior/model comparisons | Are the assumptions adequate for the intended conclusion? |
| Reopen | `load_fit` in the producing environment, or a portable handoff/report reader | Do you need retained draws or only already computed results? |

The standard specification estimates population location and person spread,
with isometric sum-to-zero facets and steps. No individual rater or item is
fixed at zero. The shared verbs retain model-specific operation boundaries;
see the [operation support table](scope.md#common-operation-support).

### Prepare and inspect without estimating

```julia
using BayesianMGMFRM
include(joinpath(pkgdir(BayesianMGMFRM), "examples", "first_analysis.jl"))
prepared = FirstMFRMAnalysis.inputs()
prepared.validation
prepared.design_summary.prior_summary
```

`prepared` contains the 72 fixed artificial `ratings`, the standard `spec`,
validation, design summary and explicit NUTS `controls`. This step neither fits
nor generates ratings. The teaching settings are not sample-size or prior
recommendations. Adapt the input using the [CSV workflow](data-validation.md#import-csv).

### Fit once and preserve the result

**This block runs four chains.** If you have a matching saved fit, use the
reopening block below instead.

```julia
out = mktempdir(mkpath("results/connected-analysis"); cleanup = false)
fitted = fit(prepared.spec; prepared.controls...)
cache_path = joinpath(out, "fit.jls")
save_fit(cache_path, fitted)
H = BayesianMGMFRM.PortableHandoff
H.save_handoff(joinpath(out, "handoff.json"), H.export_handoff(fitted))
```

The new directory preserves earlier attempts. Save before optional reports or
figures so a reporting failure can be repaired from completed draws. Native
caches require the producing source, Julia version and dependency environment;
the verified JSON handoff supports exchange across environments.

### Turn the same fit into an answer

```julia
answer = FirstMFRMAnalysis.result(fitted, prepared)
answer.contrast
answer.numerically_qualified
answer.interpretation
```

The helper checks the data/model/prior identity, combines whole-fit diagnostics
with the R2−R1 mean and interval-endpoint MCSE limits, and withholds interpretation
when those conditions fail. It also computes seeded posterior predictive checks
and fit-statistic reference distributions; these generate outcomes without
refitting. Its 90% interval and computational limits belong to this example.
An interval containing zero does not establish equivalence, and a precise
contrast does not establish model fit.

### Reopen without another fit

```julia
restored = load_fit(cache_path)
reopened_answer = FirstMFRMAnalysis.result(restored, prepared)

# Rebuild the example's reports in a new directory from the matching cache:
reopened_analysis = FirstMFRMAnalysis.main(["--saved-fit", cache_path])
```

In a later session, load the same example definitions and use the original
native-cache environment. A mismatched dataset, prior or reference-coded fit
is rejected. Both `first_analysis.jl` and `first_analysis_v02.jl` use this same
standard implementation. The earlier reference-coded example is under
`examples/legacy/first_analysis.jl` for historical reproduction only.

### [Know which operations do more work](@id workflow-operation-costs)

| Operation on an existing analysis | New posterior fit? | What happens |
| --- | --- | --- |
| Summaries, diagnostics, MCSE, interval/chain figures | No | Reuse retained draws; calculations can still be expensive. They do not remove existing warnings. |
| `predictive_check` or `plot(...; kind = :predictive)` | No | Generate replicated outcomes unless explicitly consuming saved predictions. Record the seed, draw count and prediction target; consider the size of requested arrays. |
| Different priors, anchors, slopes, dimensions or an estimated effect | Yes, for a new posterior analysis | A changed model/specification cannot be attached to the old fitted object. A label or plot change is not a sensitivity analysis. |
| Portable saved-report reader | No | Read computed values and warnings; it cannot recompute intervals, generate predictions or migrate a native cache. |

When numerical checks fail, keep the fit and identify the affected quantity or
stage. When predictive fit is poor, limit the substantive claim or justify a
model change. When reporting alone fails, repair that stage and reopen the
saved fit. These are different decisions; none calls for silently repeating
the same fit until a preferred result appears. The remaining sections explain
each decision and link to the corresponding function help.

For rater decisions, use the [evidence-to-conclusion guide](interpreting-results.md#rater-decision-evidence)
to distinguish a fitted group/item contrast, residual screen, predictive
discrepancy, prior sensitivity and fairness claim. It also separates the
available drift workflow from research-only halo classification.

## 1. Validate the Rating Design

Create [`FacetData`](@ref) from long-format ratings and run
[`validate_design`](@ref). Review:

- person, rater, item, and category coverage;
- disconnected or weakly linked rating blocks;
- skipped or sparse categories;
- repeated ratings and optional time or order fields;
- anchors and optional grouping variables;
- the distinction between planned and accidental missingness.

[`coverage_summary`](@ref), [`coverage_matrix`](@ref),
[`rater_overlap`](@ref), [`anchor_linking_summary`](@ref), and
[`rating_design_check`](@ref) provide additional review rows. These checks do
not make non-random rater assignment ignorable. The current optional
`occasion` column is categorical metadata; it does not by itself encode exact
within-rater order, timestamps, active duration, or randomized presentation.
Likewise, declared parameter anchors and rater-linking summaries are not the
same as controlled benchmark responses deliberately distributed across a
rating sequence. Time-varying severity, fatigue, or learning claims therefore
require a separate process-data and temporal-identification design.

If ratings share an answer, prompt, or item cluster, record `response_id` and
`testlet_id` separately and run [`testlet_design_check`](@ref). The check keeps
ordinary rating-graph connectivity separate from person-by-testlet,
rater-by-response, rater-by-task, and fixed-Q dimension support. Passing it
establishes only conservative structural eligibility for a candidate that is
not currently fit-supported, not the presence or interpretation of a clustered
effect. Custom thresholds are explicitly marked unvalidated.

## 2. Inspect the Model Before Fitting

State the estimand first: for example, an ability difference within a named
dimension, a rater-severity contrast, or predicted category proportions for a
specified rating design. This determines which model assumptions, summaries,
and precision checks matter. Use the [model comparison](scope.md#What-Changes-When-You-Choose-MGMFRM)
to distinguish fixed coefficients from estimated loadings and fixed from
estimated ability correlation.

Build a standard specification with `mfrm_spec(ratings; ..., prior = :default)`.
Inspect `design_summary(spec)` for its facets, category support, constraints and
prior summary, and `validate_design(spec)` for identification and design warnings.
For mathematical details, use `BayesianMGMFRM.GlassBox.contract(spec)` and the
[model equations](model-equations.md).

Standard 1D MFRM, scalar GMFRM (`slope = :rater` or `:item`) and scale-identified
MGMFRM (`q_matrix = ...`) use `fit(spec; chains = 4, warmup = 1000,
ndraws = 1000, seed = 42)`. The specification already carries its Bayesian prior;
do not attach a legacy `BayesianMGMFRM.Legacy.MFRMPrior` at fitting time. For JMLE/MMLE, construct the
appropriate prior-free 1D specification with `prior = :none` and select `method`
explicitly. Available methods depend on the specification's identification
constraints; the [support table](scope.md) and [frequentist guide](frequentist-mfrm.md)
describe the combinations.

## 3. Check Prior Implications

Inspect the prior on the actual specification before fitting:

```julia
design_summary(prepared.spec).prior_summary
prior_check = prior_predictive_check(prepared.spec; ndraws = 100, seed = 42)
```

The prior check generates parameters and ratings; it does not fit a posterior.
Look for implausible score distributions, category use and facet ranges. The
standard 1D prior estimates both population location and person spread. A
custom fixed `person_sd` has a different meaning from a prior on an estimated
population SD.

| Specification | Prior selection |
| --- | --- |
| Standard unanchored 1D MFRM | `prior = :default`; inspect the population and isometric facet/step prior summary. |
| Customized additive/population model | Explicit `prior_sd`, population and intercept settings as documented in [additive facets](additive-facets.md) and [equating](equating-and-populations.md). |
| Scale-identified GMFRM/MGMFRM | `prior = :default` or an explicit `Experimental.ScaleIdentifiedMGMFRMPrior`; keep loading identification separate from the estimated ability spread. |
| Historical reference-coded fits | Use the matching legacy model and prior; do not transfer its coordinate SDs unchanged to a centered model. |

Prior widths on free coordinates, centered facet levels, pairwise contrasts and
positive transformed parameters are different quantities. See the
[free and constrained prior densities](model-equations.md#Density-on-free-and-constrained-coordinates)
and each model guide before transferring numeric widths between routes.
Posterior sensitivity requires defensible alternative priors.
[Importance reweighting](prior-sensitivity.md) is available for specified changes
when its weight and precision diagnostics are adequate; unsupported changes or
unreliable weights require separate fits. Repeating an unchanged summary is not
a sensitivity analysis.

## 4. Fit and Diagnose

Use the fitting entry point for the selected model above. Set an integer seed
when replay is required and record the sampler controls. Multiple chains are
required for meaningful between-chain convergence checks.

For the standard example, inspect `diagnostics(fitted)` and `qualify(fitted)`.
The diagnostic report separates raw/model coordinates, retained sampler
telemetry and warmup. Legacy fits additionally provide
[`sampler_diagnostics`](@ref), [`mcmc_diagnostics`](@ref) and
[`parameter_block_diagnostics`](@ref); these helpers have their own type support.
In the standalone recipes below, `fit_result` denotes the completed fit.

The primary convergence fields are rank-normalized split R-hat, bulk ESS, and
tail ESS. The historical `rhat` and `ess` fields remain available for
compatibility. Use the rank-normalized fields for convergence review; at least
two independent chains and enough finite, nondegenerate draws are required.

For guarded GMFRM/MGMFRM fits, inspect both raw unconstrained and direct
constrained parameter rows: the gate fails if either applicable surface fails.
A constrained coordinate fixed by a transform with zero raw dimension stays in
the output with `diagnostic_status = :structurally_fixed`,
`flag = :structurally_fixed`, and `quality_gate_applicable = false`. It is not
used in extrema or failure counts. This exception does not apply to a
reconstructed constrained coordinate that varies with free raw coordinates;
that coordinate remains gated. The versioned diagnostic contract is part of
generalized cache identity, so a cache written under the older provisional
contract cannot silently supply a modern diagnostic status.

The sampler summary also reports E-BFMI availability for every expected
chain. An unavailable energy diagnostic is missing evidence, not a passing
check. For standard MRCML, use `diagnostics(fit_result).warmup` to inspect
adaptation separately from retained diagnostics. Legacy fits expose
`sampler_diagnostics(legacy_fit; phase = :warmup)` for their recorded
AdvancedHMC or CmdStan adaptation events.

A completed run is not automatically a trustworthy run. Divergences,
tree-depth saturation, low ESS, unstable R-hat, non-finite evaluations, or
constraint failures require investigation.

After that convergence review, use [`posterior_mcse`](@ref) to quantify the
simulation error of reported means, standard deviations, and quantiles:

```julia
mcse_rows = posterior_mcse(fit_result;
    probabilities = (0.025, 0.5, 0.975),
)
```

For GMFRM/MGMFRM, [`BayesianMGMFRM.direct_posterior_summary`](@ref) and the default
`posterior_mcse` summarize transformed model parameters. `posterior_summary`
instead summarizes their raw coordinates, so match parameter names and scales
before comparing intervals and MCSE. A credible interval describes parameter
uncertainty conditional on the model and data; MCSE describes numerical
uncertainty in an estimated posterior summary. A small MCSE does not imply a
narrow credible interval, correct model assumptions, or accurate measurement.

For fixed-coefficient multidimensional MFRM, this call also supports correlated
abilities and either rater prior, including reloaded fits from either backend.
It reports reconstructed parameters and rho on their model scales by default;
see [multidimensional precision summaries](experimental.md#Fitting-and-saved-results)
for coordinate selection and fixed/short-chain statuses.

For a derived estimand, compute one value per posterior draw while preserving
the contiguous chain blocks, place the values in matrix columns, and call the
matrix method with `chains` and `parameter_names`. The function deliberately
does not turn MCSE into a universal pass/fail threshold. Required precision
depends on the reported estimand and substantive decision; MCSE also cannot
repair or certify non-converged chains.
The [saved-fit contrast example](examples.md#Compare-abilities-or-raters-in-a-saved-MGMFRM-fit)
implements this calculation for within-dimension ability differences, rater
severity differences and log-consistency ratios, including optional practical
ranges and the simulation error of their posterior probabilities.

For independent fixed-Q MGMFRM, optionally inspect
`diagnostics(fit_result; include_location = true)` for common ability/item
location movement. Its location rows supplement the original diagnostic
assessment and are not automatically included in the ordinary report. The
[saved-fit walkthrough](examples.md#Review-a-saved-MGMFRM-fit-without-fitting)
shows these checks, intervals and MCSE together without sampling again.

### Qualification and focal precision

Inspect the default whole-fit screen, or declare explicit diagnostic reference levels:

```julia
gate = qualify(fit_result; max_rhat=1.01, min_ess=400.0, min_bfmi=0.3)
```

Interpret the returned flag within its stated scope:

| Result | Meaning of a passing gate | Precision still to assess |
| --- | --- | --- |
| Common fit or supported NamedTuple | `qualified`: whole-fit parameter diagnostics and complete sampler telemetry, under requested thresholds. `focal_precision_qualification=:not_assessed`. | MCSE of the means, interval endpoints, contrasts, decisions and probabilities used in the analysis. |
| Star | `result.numerically_qualified`: raw/transformed diagnostics, complete sampler telemetry and the named `result.focal_parameters` pass. The focal quantities are finite-entity root/branch correlations, with mean and 95% interval-endpoint MCSE limits. | Other population correlations, residual-association parameters, contrasts, ranks, event probabilities and any different interval endpoints. |

For Star, `rhat_max`, `ess_min`, and `ebfmi_min` remain aliases of the common
controls; supplying both spellings for one control is an error. Its
`check_transformed=false` option returns a partial diagnostic report:
`transformed_assessed=false`, `transformed_passed=missing`, and both whole-fit
and overall qualification are false. Missing, duplicate or misordered retained
sampler records cannot pass the telemetry gate. This avoids interpreting an
unperformed check as successful. Previously stored warnings remain attached even
if a user chooses looser thresholds for a new diagnostic report.

The thresholds are numerical criteria, not a scientific adequacy test or a
universal precision recommendation. Assess MCSE in the estimand's own units and
at the endpoints you report. The [posterior quantile-MCSE documentation](https://mc-stan.org/posterior/reference/mcse_quantile.html)
explains why quantile uncertainty is a separate calculation and can be unavailable
for constant or nonfinite chains. A constant estimated event indicator does not
establish a zero probability. Preserve unavailable precision and model-fit or
prior-sensitivity warnings.

## 5. Examine Predictions and Residuals

For the standard MRCML fit, use `predictive_check(fitted; ndraws = 1000, seed = 42)`
and `diagnostics(fitted; kind = :fit_statistics, by = :rater, seed = 43)`.
These propagate retained draws; the latter separates posterior-integrated and
plug-in MNSQ. For supported local pair comparisons, see
[residual correlations](interpreting-results.md) and the operation support table.

Legacy diagnostic routes use [`posterior_predictive_check`](@ref),
[`predictive_check_summary`](@ref), and [`calibration_table`](@ref) to compare
observed and replicated outcomes. [`predictive_residuals`](@ref),
[`predictive_standardized_residuals`](@ref), [`residual_summary`](@ref),
[`fit_stats`](@ref), and
[`rater_diagnostics`](@ref) help locate misfit.

The generalized posterior predictions replicate the existing rating rows using
the fitted persons, items, and raters. Agreement checks conditional model fit;
it does not measure held-out accuracy or prediction for a new person, item, or
rater. A category-proportion plot also cannot establish parameter recovery or
interval coverage. Those questions need their own design and evidence.

`predictive_standardized_residuals` reports draw-specific Pearson residuals
and explicitly excludes rows with negligible predictive variance. Non-finite
predictions are errors, not low-variance exclusions. This is a low-level input,
not a test of local independence. The provisional
[`local_dependence_contract`](@ref) separates single-rating item pairs,
within-rater item pairs, and rater pairs; fixes draw-specific support,
duplicate rejection, weighting, paired predictive tails, and multiplicity
scopes; stratifies estimation by testlet; and forbids implicit rater
aggregation or cross-rater cross-item pairing. Its decision labels remain
disabled until known-truth calibration.

For the legacy route with `response_id` and `testlet_id` declared, use
[`local_dependence_summary`](@ref) for the corresponding report-only pair
summaries:

```julia
ld = local_dependence_summary(legacy_fit)
```

The function selects distinct posterior draws, generates one conditional
replicated dataset from each selected draw, and applies the same matching and
validity rules to observed and replicated standardized residuals. It keeps
single-rater item pairs, within-rater item pairs, and rater pairs on the same
response and criterion separate. Criterion-split scoring is not silently
relabelled as single-rater Q3, and applicability is evaluated separately in
each testlet so one criterion-split stratum does not suppress another valid
single-rating stratum. Sparse or undefined pairs with at least one common unit
remain structured pair rows with missing evidence values;
zero-overlap combinations remain visible in family counts and testlet support
graphs. Family-wide and testlet-specific support statuses are reported
separately. Before large work or allocations, the API counts candidate-pair
rows, shared-unit links, positive-pair-by-draw cells,
pair/common-unit-by-draw cells, and draw-by-observation-by-category cells.
Posterior predictive tail fractions, BH-adjusted values, and the all-family
maximum statistic are calibration-pending references; none is a decision label
or evidence for a specific mechanism.

These local-dependence summaries are uncalibrated diagnostic references. They
provide no decision threshold or mechanism classification and do not make
clustered effects available for fitting. The separate research helpers are
documented in the [Validation and Evidence API](api-validation-evidence.md);
running a simulation study is not a prerequisite for an ordinary analysis.

Observation-row LOO does not validate
prediction for a wholly unseen response whose shared effect was informed by
other rows from that response.

DFF rows are screening information unless the fitted model explicitly supports
the corresponding identified effect. Statistical differences should be
reported separately from practical magnitude and substantive interpretation.

For figures without assembling draw matrices, load CairoMakie and use:

```julia
using CairoMakie
parameters = [r.parameter for r in posterior_summary(fitted).rows
    if startswith(r.parameter, "rater[")]
BayesianMGMFRM.plot(fitted; kind = :posterior, parameters)
BayesianMGMFRM.plot(fitted; kind = :diagnostics, parameters)
BayesianMGMFRM.plot(fitted; kind = :predictive, ndraws = 200, seed = 42)
```

The first shows parameter uncertainty, the second retained-chain behavior,
and the third category counts and group means under conditional replications
of the fitted rows. Wright maps remain a separate legacy MFRM operation
(`BayesianMGMFRM.plot_wright(legacy_fit)`); the standard example does not offer
that plot. See [figures and export](fitting.md#Posterior-interval-figures).

## 6. Compare Models Carefully

Use `compare_models` for the supported comparison routes.
For a CriterionCollapse fit, `compare_models(result)` compares the all-ordinary
and at-least-one-collapse submodels under their induced priors. This is model
evidence rather than WAIC/LOO; pair it with the [joint count check](criterion-collapse.md#Joint-prediction-and-model-comparison) to assess the selected category pattern. State the prediction
unit and baseline before reading a difference. Paired ELPD differences require
the same observed outcomes; see the [loo comparison documentation](https://mc-stan.org/loo/reference/loo_compare.html).
A matching row count alone does not establish compatibility.

For the eight common MFRM/GMFRM/MGMFRM result types, use named pairs and an
explicit comparison axis:

```julia
comparison = compare_models("reference" => reference_fit, "alternative" => alternative_fit;
    comparison_axis=:model, dataset_id="ratings-v1", observation_ids=rating_ids,
    criterion=:waic, baseline="reference", se_unit=:none)
comparison.rows                # input order; each difference is model minus reference
comparison.criterion_target    # one rating omitted, fixed specification
comparison.uncertainty         # uncomputed MCSE/SE remain explicit
```

`rating_ids` supplies one unique string per original rating. If fit row orders
differ, use a dictionary from the same model names to each fit's ID vector.
Use `comparison_axis=:dimensions` when D/Q may differ, or `:q_matrix` for Q
changes at fixed D. These operations reuse `compare_predictions`; its data,
category, conditioning and draw-layout checks remain. They use all retained
draws. Model identity, prior/scale information and warnings remain in each row;
a comparison axis does not isolate a causal effect of that choice.

For Star fits, the model already retains event IDs:

```julia
comparison = compare_models("association" => association_fit,
                            "no_residual_association" => no_residual_fit)
comparison.primary_name
comparison.baseline_name
comparison.waic_diff.elpd_diff
comparison.psis_loo_diff.interpretation_scope
```

This route accepts exactly two Star results and returns primary minus baseline,
without choosing a winner. It aligns events by ID and checks actual entity/rater
labels, scores, criterion IDs, category supports and scoring directions. Priors,
root choice and dependence terms can differ. In the `include_phi=false` alternative,
only residual association is removed; entity/rater correlations remain estimated.
Do not reuse event IDs for different
measurements. Current in-memory Star `criteria(fit)` results can also be compared
with `compare_models(primary_criteria, baseline_criteria; names=("a", "b"))`.
Older reports lacking observed-event bindings remain readable but cannot establish
this comparison contract. Portable JSON remains a computed report, not an
in-memory criteria object. Preserve it and its original producing environment;
this is not a native-cache migration facility or a request to refit.

| Route | Prediction unit / calculation | Difference and uncertainty |
| --- | --- | --- |
| Common fits, explicit `comparison_axis` | One original rating; `:waic`, `:raw_loo`, `:psis_loo` (Zhang–Stephens GPD smoothing with chain relative efficiency), or the separate historical `:hill_smoothed_loo`. | Model minus declared baseline, original order. Default difference SE is unavailable; `:observation` or `:person` adds the documented approximate SE. Neither is MCMC MCSE or general crossed-cluster adjustment. |
| Two Star fits or current Star criteria records | One complete multi-criterion event, conditional on existing entity/rater effects; joint-event WAIC and the Star GPD-smoothed PSIS implementation. | Primary minus baseline, both criteria reported. Existing entity + rater - observation variance approximation, floored at observation variance; repeated entity/rater pairs lack an intersection-cluster adjustment. Inspect sampling, Pareto-k and clipping warnings. This is not a guarantee of calibrated uncertainty. |
| Legacy common-fit call without `comparison_axis` | Existing MFRM/GMFRM/MGMFRM ranking interface; `:psis_loo` now selects standard PSIS and requires all retained draws. Historical stored Hill scores are unchanged. | Sorted relative to the best model, with normalized Akaike-style weights. These are not posterior model probabilities. Kept for compatibility; use the explicit-axis route above for observation-bound comparison. |

`criteria` availability does not imply that every model combination has a public
comparison route. Correlated3D criteria, JointRatings and OrdinalAssociation
reports do not make a rating row interchangeable with a joint event. Refitted
K-fold also has a distinct prediction target. Keep those contracts separate.

The common `event_probabilities` entry likewise preserves model-specific meaning:

| Model | Meaning and returned object |
| --- | --- |
| Common fits | Category probabilities conditional on fitted effects, as a draws × rating rows × categories array. No intervals, MCSE or diagnostic envelope are added by this call. |
| Correlated 3D | Category probabilities for `observation` or `rows` of the fitted design, with intervals, MCSE and diagnostics. |
| Star / OrdinalAssociation | Joint probabilities for an existing `rating_event_id`, with intervals, MCSE and source warnings/diagnostics. Star includes marginal and conditional summaries; a full Cartesian table is opt-in. |
| JointRatings | Future criterion-row marginal probabilities with intervals, MCSE and integration-error information. `response_effect=:existing` retains the response, while `:new` integrates a new shared response effect for known person/task/rater levels. Marginal products do not provide the shared-response joint probability. |

Without draw-selection controls, common-fit probability arrays preserve the
original joint draw order. `ndraws` resamples with replacement; `draw_indices`
preserves the requested order and duplicates. A resampled or reordered array
must not be passed to chain-based MCSE calculations as if it retained the original
chains. Use all original draws, maintain chain/iteration alignment, and calculate
MCSE for each named probability being interpreted. Returned probability intervals
measure posterior uncertainty in probabilities, not intervals for future scores.

These probability summaries are not replicated outcomes. `predictive_check`
generates outcomes where supported, so it is a distinct operation. Inspect
pointwise influence, Pareto-k and numerical warnings before interpreting any
comparison; a ranking alone is not a superiority claim.

Sensitivity work should cover defensible prior choices and any threshold,
anchor, dimensionality, or Q-matrix decisions that could change the
interpretation.

## 7. Report the Boundary

[`posterior_summary`](@ref), [`fair_average_summary`](@ref),
[`separation_reliability_summary`](@ref), [`wright_map_data`](@ref), and other
reporting helpers return table-oriented results where the chosen model supports
them. In particular, the stable MFRM Wright map is unavailable for generalized
fits. Use model-scale summaries for the named dimension instead.
[`fit_report`](@ref) assembles the requested machine-oriented sections.
Use `fit_report(fit; view = :public)`
or [`fit_report_public`](@ref) for a reader-facing structured projection, and
[`fit_report_markdown`](@ref) for a Markdown preview.

The top-level `status` describes model exposure (`:supported` or
`:experimental`); it does not certify that every requested report section was
computed. [`fit_report_health`](@ref) derives report-generation health from the
section statuses. A captured `status = :error` section sets
`report_status = :incomplete`, while `:not_requested` and `:unsupported` do not.
Use `require_complete = true` on `fit_report`, report exporters, or
`fit_report_dossier` when a failed requested section should stop export. Use
`on_section_error = :throw` when the first failing section should abort
immediately.

Report completeness and diagnostic quality are separate: a complete report can
preserve MCMC warnings or unsupported sections. Read the diagnostic assessment
and the status of each section needed for the claim. For positive loadings or
consistencies, a posterior probability above zero reflects the imposed positive
support and is not evidence of an effect. Define meaningful comparisons before
interpreting these rows. In MGMFRM, consistency one is the model's product-one
reference, not a calibrated reliability threshold.

Save the fit with `save_fit_cache` and reload it with `load_fit_cache` to
regenerate tables and figures in the same environment without sampling again.
Keep source data, analysis code, and environment/version information alongside
portable reports; the serialized cache alone is not a durable analysis archive.
Recorded-fit caches retain exact integrity hashes while allowing tiny roundoff
differences in recomputed means and SDs. This neither changes the saved values
nor establishes cross-version compatibility.

A report should state:

- model family, threshold regime, dimensions, and constraints;
- rating-design limitations;
- priors and sampler controls;
- convergence and predictive diagnostics;
- the prediction target for model comparison;
- unsupported features and the limits of generalization.

Fixed-Q MGMFRM results must not be generalized to exploratory
multidimensional models or freely estimated correlation structures.

For an ordinary scalar MFRM, the [expected-score and information guide](score-information.md)
connects an explicit item/rater assessment design to conditional curves and
saved report tables. Its information is distinct from posterior precision.
