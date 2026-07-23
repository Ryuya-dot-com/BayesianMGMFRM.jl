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
[`rating_design_audit`](@ref) provide additional review rows. These checks do
not make non-random rater assignment ignorable. The current optional
`occasion` column is categorical metadata; it does not by itself encode exact
within-rater order, timestamps, active duration, or randomized presentation.
Likewise, declared parameter anchors and rater-linking summaries are not the
same as controlled benchmark responses deliberately distributed across a
rating sequence. Time-varying severity, fatigue, or learning claims therefore
require a separate process-data and temporal-identification design.

If ratings share an answer, prompt, or item cluster, record `response_id` and
`testlet_id` separately and run [`testlet_design_audit`](@ref). The audit keeps
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

The experimental generalized configurations use their documented built-in
raw-coordinate priors. Custom generalized prior objects are not supported.

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
separately. Before large work or allocations, the API checks explicit audit-
pair rows, audit/shared-unit links, positive-pair-by-draw cells,
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
semantic event-keyed uniforms, sequence positions, and structural-audit
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
`local_dependence_calibration_pilot_preflight`. The contract fixes 30
replications for each of the 22 scenarios (`30 × 22 = 660`): 540 eligible fits,
and 120 planned structural rejections. For each eligible scenario, the study-
local operational candidates require at least 27 completed jobs, at most three
categorized failures, and no missing outcome. Retry outcomes are appended and
cannot overwrite the original failure. The planned sampler uses four
AdvancedHMC/NUTS chains with 500 warmup and 500 retained draws per chain, and
the diagnostic uses 250 distinct posterior-predictive draws. These are study-
specific execution settings, not package defaults.

The MCMC-free `local_dependence_pilot_protocol_preflight.json` artifact records
that package sampler diagnostics now provide the required rank-normalized
R-hat and bulk/tail ESS, so the pilot execution protocol is authorized. The
authorization pins the exact `rank_normalized_rhat_bulk_tail_ess_v1` dependency
and operation-order record, primary fields, tail probability, minimum chain and
draw requirements, complete-chain E-BFMI coverage, and the SHA-256 digest of
`src/bayesian_fit.jl`.
Candidate quality bounds are rank-normalized R-hat at most 1.01, bulk and tail
ESS of at least 400, no divergences or maximum-depth hits, and E-BFMI of at
least 0.3. After the pilot, either 50 or 100 evaluation replications must be
selected and frozen before a separately seeded evaluation; the evaluation may
not be extended partway through. The preflight runs no fit or MCMC, the pilot
has not been run, and no repeated-calibration evidence, pairwise power,
diagnostic decision, or mechanism interpretation is available.

The MCMC-free `local_dependence_pilot_batch_execution_harness.json` dry run
checks orchestration for the 660 planned rows: 540 eligible fitting jobs and
120 planned pre-fit rejections. The controller and generator sources are
identified, while a complete execution plan also requires the future
single-job executor SHA-256. Role-specific evidence envelopes are bound to each
job result. Every evidence role identifies one source artifact by bytes and
SHA-256 and records its exact upstream evidence
hashes. The frozen `pilot_contract` and ordered 660 job rows must reproduce
their canonical SHA-256 values. The exact evidence chain for
`pre_fit_rejected` is `generated_data` -> `structural_rejection_audit` ->
`calibration_row`, where the final member follows the existing public
calibration-row contract. Simulation evidence validates response data, table
columns, probability cells, truth and row-truth arrays, and data/score/design
signatures. Fit evidence uses the structured
`local_dependence_pilot_fit_artifact_export.v1` JSON wrapper containing retained
draws, log posterior values, and sampler statistics. Its package-native content
hash must be verified by the future pinned canonical executor before JSON
projection; the batch runner separately recomputes the canonical JSON payload
hash and verifies the exact file SHA-256. The JSON projection cannot soundly
reconstruct the native typed hash. Data, design, fit-artifact, retained-draw,
chain, and iteration
provenance must match across fit, sampler, local-dependence, and calibration
members. The custom `local_dependence_pilot_summary_bundle.v1` directly records
the draw-selection and posterior-predictive seeds; the runner compares both
with its evidence payload, the frozen job, and the calibration execution seeds.
Draw selection uses the frozen `sha256_seeded_rank_without_replacement_v1`
algorithm, and the runner recomputes its ordered draw indices from the frozen
seed. The posterior-predictive seed is source-bound, but seed-to-result replay
verification remains pending the canonical single-job executor and bounded
smoke review.
For `diagnostic_failed`, `sampler_quality_gate` requires a failed
sampler gate, whereas `local_dependence_summary` requires that sampler gate to
have passed. Resource counts and fixed sampler controls are checked, and the
R-hat, bulk/tail ESS, divergence, depth, and complete-chain E-BFMI gates are
evaluated individually. Symbolic links, hard links, and unmanifested files are
rejected.

The aggregate state is bound to the ordered primary-result and evidence
digests. Primary outcomes are nonoverwritable, and remediation remains
separately visible. Resume first
rescans the complete attempt archive as the source of truth, then verifies and
compares the derived checkpoint, and skips only verified terminal primary
records; it does not resume a sampler chain. The generated dry run reports
attempt-archive integrity as not assessed. Snapshot and inventory rechecks are
static consistency checks, not an atomic completed-attempt seal. The canonical
single-job executor, bounded smoke review, completed-attempt seal, and append-
only recovery or retirement path for interrupted attempts remain required
before execution. No response data are generated, no model is fitted, and no
MCMC is
run; pilot results, calibration or power estimates, diagnostic decisions, and
mechanism interpretations remain unavailable.

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

A report should state:

- model family, threshold regime, dimensions, and constraints;
- rating-design limitations;
- priors and sampler controls;
- convergence and predictive diagnostics;
- the prediction target for model comparison;
- unsupported features and the limits of generalization.

Experimental fixed-Q MGMFRM results must not be generalized to exploratory
multidimensional models or freely estimated correlation structures.
