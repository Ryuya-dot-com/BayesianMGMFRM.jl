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

Create an [`mfrm_spec`](@ref) and inspect:

- [`model_equation`](@ref) for the likelihood and source contract;
- [`constraint_table`](@ref) and [`identification_declarations`](@ref) for the
  gauge and reference rules;
- [`getdesign`](@ref) for the identified parameter vector;
- [`model_manifest`](@ref) for a portable summary of data, model, and design.

Specified configurations are not necessarily fit-supported. The support table
in [Scope and Releases](scope.md) governs whether a fitting call is available.

## 3. Check Prior Implications

Choose [`MFRMPrior`](@ref) scales that match the analysis context and run
[`prior_predictive_check`](@ref). Look for implausible score distributions,
category use, or facet ranges before inspecting the observed-data posterior.

The experimental generalized configurations default to their documented
raw-coordinate priors. Use
`BayesianMGMFRM.Experimental.GeneralizedPrior` for typed scale sensitivity and
actual refits. Its values apply to raw unconstrained coordinates, not directly
to transformed parameters. A generalized prior-predictive operation remains a
separate roadmap item.

## 4. Fit and Diagnose

Use [`fit`](@ref) for supported models. Set an integer seed when replay is
required and record the sampler controls. Multiple chains are required for
meaningful between-chain convergence checks.

Review:

- [`sampler_diagnostics`](@ref) for chain and HMC behavior;
- [`mcmc_diagnostics`](@ref) for R-hat and ESS;
- [`parameter_block_diagnostics`](@ref) for block-level patterns;
- [`diagnostics`](@ref) for the compact combined status.

The primary convergence fields are rank-normalized split R-hat, bulk ESS, and
tail ESS. The historical `rhat` and `ess` fields remain available for schema
compatibility but do not define the modern quality gate. For odd split chains,
bulk metrics remove the center draw before ranking, folded R-hat first folds
around the untrimmed pooled median, and tail ESS first fixes the untrimmed
pooled tail quantiles. ESS uses all available valid split-chain lags rather
than a fixed 250-lag truncation. These choices match Stan/posterior semantics.
At least two original independent chains and enough finite, nondegenerate draws
are required.

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

The sampler summary retains the minimum finite available `e_bfmi` for
compatibility and reports `n_e_bfmi_expected`, `n_e_bfmi_available`,
`n_e_bfmi_unavailable`, and `e_bfmi_complete`. Any missing or non-finite energy
value within a chain makes that chain unavailable. The publication gate applies
the E-BFMI threshold only when every expected chain is available. Version-1
result, diagnostic, and heldout wrappers are unchanged: only rows whose
`diagnostic_contract` is
`rank_normalized_rhat_bulk_tail_ess_v1` are modern. The general `flag` aliases
the modern `rank_normalized_flag`; `classical_compatibility_flag` remains a
legacy comparison field.

A completed run is not automatically a trustworthy run. Divergences,
tree-depth saturation, low ESS, unstable R-hat, non-finite evaluations, or
constraint failures require investigation.

## 5. Examine Predictions and Residuals

Use [`posterior_predictive_check`](@ref),
[`predictive_check_summary`](@ref), and [`calibration_table`](@ref) to compare
observed and replicated outcomes. [`predictive_residuals`](@ref),
[`predictive_standardized_residuals`](@ref), [`residual_summary`](@ref),
[`fit_stats`](@ref), and
[`rater_diagnostics`](@ref) help locate misfit.

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
ld = local_dependence_summary(fit)
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

For method development and reproducible design stress tests, LD1a provides an
independent known-truth generator:

```julia
plan = local_dependence_simulation_grid()
known_truth = simulate_local_dependence(first(plan))
```

The 22 scenarios exercise null and boundary behavior, study-local positive
magnitudes, sparse and rejected designs, competing halo/rater-by-task/
multidimensional mechanisms, randomized drift, ability-confounded no-drift
order, ability-informed rater assignment, and a testlet-plus-sequence mixture.
The ordinal sampling kernel is
separate from the fitted likelihood, and each bundle records complete truth,
semantic event-keyed uniforms, sequence positions, and structural-check
results. The
ability-confounded scenario is an order/case-mix negative control; it is not a
substitute for a study that distributes controlled benchmark responses across
early, middle, and late rating windows.

Generator completion is not diagnostic calibration. Until repeated LD1b
replications estimate false declarations, power, multiplicity behavior, and
mechanism confusion, `local_dependence_summary` continues to provide neither a
decision nor a mechanism label, and its report-only references must not be
converted into user-defined universal cutoffs.

LD1b0 provides a protocol-validation and aggregation layer through
`local_dependence_calibration_contract`, `local_dependence_calibration_row`,
and `local_dependence_calibration_summary`. It records expected structural
rejections, generation or fitting failures, unsupported diagnostics, and
completed replications separately. Complete-null simulations supply candidate
Type-I and dataset-level FWER references. Competing-mechanism simulations are
reported as detection signatures, not mechanism classifications. Because the
current generator has no versioned pair-level null/non-null oracle, alternative
pair declaration fractions are not labelled pairwise power or FDR. The LD1b0
surface does not itself run a pilot or evaluation study and does not modify the
decision-disabled observed-data diagnostic.

LD1b1 adds `local_dependence_calibration_pilot_contract` and
`local_dependence_calibration_pilot_check`. They freeze a 30-replication
pilot plan for each of the 22 scenarios and validate its study-specific sampler
and diagnostic requirements. The frozen MFRM gradient route is `ForwardDiff`,
and authorization checks that route together with the AdvancedHMC/NUTS and
diagnostic capabilities. The check runs no fit or MCMC; the pilot and
evaluation remain unrun. Consequently, these layers provide no
repeated-calibration, power, diagnostic-decision, or mechanism-identification
evidence, and they do not make clustered effects available for fitting.

Observation-row LOO does not validate
prediction for a wholly unseen response whose shared effect was informed by
other rows from that response.

DFF rows are screening information unless the fitted model explicitly supports
the corresponding identified effect. Statistical differences should be
reported separately from practical magnitude and substantive interpretation.

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
reporting helpers return table-oriented results. [`fit_report`](@ref) combines
the complete machine-oriented sections. Use `fit_report(fit; view = :public)`
or [`fit_report_public`](@ref) for a reader-facing structured projection, and
[`fit_report_markdown`](@ref) for a Markdown preview.

The top-level `status` describes model exposure (`:supported` or
`:experimental`); it does not certify that every requested report section was
computed. [`fit_report_health`](@ref) derives report-generation health from the
section statuses. A captured `status = :error` section sets
`report_status = :incomplete`, while `:not_requested` and `:unsupported` do not.
Use `require_complete = true` on `fit_report`, report exporters, or
`fit_report_dossier` for evidence and release jobs that must fail closed. Use
`on_section_error = :throw` when the first failing section should abort
immediately.

A report should state:

- model family, threshold regime, dimensions, and constraints;
- rating-design limitations;
- priors and sampler controls;
- convergence and predictive diagnostics;
- the prediction target for model comparison;
- unsupported features and the limits of generalization.

Experimental fixed-Q MGMFRM results must not be generalized to exploratory
multidimensional models or freely estimated correlation structures.
