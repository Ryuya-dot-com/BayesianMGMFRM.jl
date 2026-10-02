# Bayesian Workflow

A many-facet analysis is more than a sampling call. The rating design,
identification constraints, priors, sampler behavior, predictive performance,
and reporting scope all affect what can be interpreted.

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

Create an [`mfrm_spec`](@ref) and inspect:

- [`model_equation`](@ref) for the likelihood and source contract;
- [`constraint_table`](@ref) and [`identification_declarations`](@ref) for the
  gauge and reference rules;
- optionally, [`getdesign`](@ref) for the identified parameter vector;
- [`model_manifest`](@ref) for a portable summary of data, model, and design.

For stable one-dimensional MFRM, call `fit(spec)` when no separate design
inspection is needed. Multidimensional MFRM and GMFRM/MGMFRM use
`BayesianMGMFRM.Experimental.fit(spec)`. An estimated correlation requires
`BayesianMGMFRM.Experimental.correlated(spec)` first, within the documented
two-dimensional restrictions. Specified configurations are not necessarily
fit-supported. The support table in [Scope and Releases](scope.md) governs
whether a fitting call is available.

## 3. Check Prior Implications

Choose the prior for the actual model, and pass the same prior to the prior
check and fitting call:

| Model | Prior | Prior check |
|:--|:--|:--|
| Stable one-dimensional MFRM | [`MFRMPrior`](@ref) | [`prior_predictive_check`](@ref) |
| Fixed-coefficient multidimensional MFRM, independent or correlated | `MFRMPrior`, or the explicit `BayesianMGMFRM.Experimental.ExchangeablePrior` alternative for rater severities | `BayesianMGMFRM.Experimental.prior_predictive_check` |
| Scalar GMFRM or independent fixed-Q MGMFRM | `BayesianMGMFRM.Experimental.GeneralizedPrior` | `BayesianMGMFRM.Experimental.prior_predictive_check` |
| Independent fixed-Q MGMFRM with normalized centered priors | Explicit `Experimental.NormalizedMGMFRMPrior`; all six scales and the prior family are required | `Experimental.prior_predictive_check` |
| Two-dimensional correlated MGMFRM | An explicitly supplied `BayesianMGMFRM.Experimental.GeneralizedPrior`; the specification also declares the LKJ correlation prior | `BayesianMGMFRM.Experimental.prior_predictive_check` |

Look for implausible score distributions, category use, or facet ranges before
inspecting the observed-data posterior. Generalized prior SDs apply to raw
unconstrained coordinates, including log-loadings and log-consistencies, not
directly to the positive transformed parameters. `person_sd` fixes the marginal
ability prior scale; it is not an estimated hyperparameter. The experimental
prior check exposes raw/direct draws, replicated scores, and implication
warnings. See [prior conventions](experimental.md#Workflow) before choosing
scales or comparing them across models. Posterior sensitivity requires actual
refits under defensible alternatives; repeatedly summarizing one saved fit
does not evaluate it.

## 4. Fit and Diagnose

Use the fitting entry point for the selected model above. Set an integer seed
when replay is required and record the sampler controls. Multiple chains are
required for meaningful between-chain convergence checks.

Review:

- [`sampler_diagnostics`](@ref) for chain and HMC behavior;
- [`mcmc_diagnostics`](@ref) for R-hat and ESS;
- [`parameter_block_diagnostics`](@ref) for block-level patterns;
- [`diagnostics`](@ref) for the compact combined status.

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
check. Use `sampler_diagnostics(fit_result; phase = :warmup)` to inspect
recorded AdvancedHMC or CmdStan adaptation events separately from retained
posterior diagnostics.

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

## 5. Examine Predictions and Residuals

Use [`posterior_predictive_check`](@ref),
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

When `response_id` and `testlet_id` are declared, use
[`local_dependence_summary`](@ref) for the corresponding report-only pair
summaries:

```julia
ld = local_dependence_summary(fit_result)
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
BayesianMGMFRM.plot_posterior(fit_result; block = :rater)
BayesianMGMFRM.plot_diagnostics(fit_result; block = :rater)
BayesianMGMFRM.plot_predictive(fit_result; ndraws = 200, seed = 42)
```

The first shows parameter uncertainty, the second retained-chain behavior,
and the third category proportions under conditional replications of the
fitted rows. `BayesianMGMFRM.plot_wright(fit_result)` additionally displays the
stable MFRM measures and item-step boundaries on a shared logit scale.
Generalized fits require dimension/scale interpretation and do not support a
Wright map. See [figures and export](fitting.md#Posterior-interval-figures).

## 6. Compare Models Carefully

WAIC, LOO, PSIS-LOO, and K-fold summaries require compatible observations and
an explicit prediction target. Inspect pointwise influence, Pareto-k, and
held-out diagnostics. Relative weights are not posterior model probabilities,
and a ranking is not by itself a superiority claim.

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

A report should state:

- model family, threshold regime, dimensions, and constraints;
- rating-design limitations;
- priors and sampler controls;
- convergence and predictive diagnostics;
- the prediction target for model comparison;
- unsupported features and the limits of generalization.

Experimental fixed-Q MGMFRM results must not be generalized to exploratory
multidimensional models or freely estimated correlation structures.
