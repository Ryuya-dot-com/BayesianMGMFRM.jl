# Long-Format Data and Pre-Fit Validation

`BayesianMGMFRM.jl` starts from long-format rating data: one row per rating
event. The data and validation layer is intentionally sampler-free. Its purpose
is to make common weak or non-estimable many-facet design patterns visible
before a sampler is called.

```julia
using BayesianMGMFRM

ratings = (
    examinee = ["E1", "E1", "E1", "E1", "E2", "E2", "E2", "E2"],
    rater = ["R1", "R2", "R1", "R2", "R1", "R2", "R1", "R2"],
    item = ["I1", "I1", "I2", "I2", "I1", "I1", "I2", "I2"],
    group = ["A", "A", "B", "B", "B", "B", "A", "A"],
    score = [0, 1, 2, 0, 1, 2, 0, 2],
)

data = FacetData(ratings;
    person = :examinee,
    rater = :rater,
    item = :item,
    score = :score,
    group = :group,
)

validation = validate_design(data; bias = [(:rater, :group)])
spec = mfrm_spec(data; thresholds = :partial_credit, validation_report = validation)
design = getdesign(spec)
```

`FacetData` records deterministic integer indexes and stable label maps for
persons, raters, items, the contiguous integer score range from the minimum to
maximum observed score, and optional metadata roles.
`validate_design` returns a `ValidationReport` with machine-readable
`ValidationIssue.code` values and human-readable messages. Current checks cover:

- observed and skipped score categories;
- all-minimum/all-maximum person patterns and constant-score raters with at
  least two ratings;
- singleton person, rater, item, and optional metadata levels;
- connectedness of the person-rater-item graph;
- rank of the current reference-constrained minimal location design;
- item/category support warnings for weakly informed partial-credit thresholds;
- empty, sparse, and potentially confounded DFF cells for requested `bias`
  terms.

## Ordinal Response-Pattern Stress

Use [`ordinal_response_pattern_audit`](@ref) before fitting when category use
or boundary responses are part of the design risk:

```julia
audit = ordinal_response_pattern_audit(data)
audit.status
audit.category_scale.unobserved_interior_categories
audit.flags.extreme_person_levels
audit.flags.constant_rater_levels
```

If a five-category dataset contains scores 1, 2, 4, and 5, `FacetData` retains
the contiguous `1:5` range and the audit reports category 3 as an unobserved
interior category. This is not a missing response row and is not automatically
a fit error; its adjacent step transitions can be weakly separated and belong
in prior-sensitivity and category-use checks. Literal missing score values are
different: the current `missing_policy = :error` rejects them during data
construction.

A person rated 5 on every observed response supplies one-sided information
about ability, and dimension-specific Q coverage must also be inspected. A
rater assigning 1 on every observed response can weakly
separate severity from the generalized rater-consistency parameter, depending
on assignment overlap. Both patterns produce pre-fit warnings when the level
has at least two ratings, but neither is converted into an infinite parameter
or an automatic scientific failure. Proper priors keep finite posteriors; the
levels must be reported separately and refitted under predeclared prior
regimes. If the entire dataset contains only one score category, the ordered-
response likelihood is not estimable and `validate_design` returns an error.

The ordinary `FacetData` constructor infers the scale from the observed
minimum through maximum. It can detect skipped interior categories, but not an
intended endpoint outside that realized range. Preserve such endpoint intent
in source-data provenance until a declared-category-scale constructor is
available; do not infer endpoint use from this audit.

For the fixed-Q MGMFRM validation program, the same cases can now be generated
and checked across dense and connected-sparse layouts without running MCMC:

```julia
stress_plan = mgmfrm_response_stress_plan()
stress_preflight = mgmfrm_response_stress_preflight(stress_plan)

stress_preflight.summary
stress_preflight.rows
```

The default plan has nine attempts: four separate patterns under a fully
crossed layout and five under the connected systematic-link layout. The exact
combination of an all-maximum person and all-minimum rater is not generated in
the fully crossed design because their shared cells would require both scores
simultaneously. In the sparse combined case, the target person and target rater
have no common observation.

Each attempt terminates as `:preflight_passed`, `:pre_fit_rejected`, or
`:generation_failed`, and the returned denominator must equal the planned
attempt count. A generation exception is retained as an exception object plus
its type, message, phase, and elapsed time; it is not converted to `nothing`.
Non-baseline patterns are declared deterministic interventions after a model-
generated response draw, so their retained probabilities are pre-intervention
references for robustness stress—not well-specified recovery truth. The
preflight does not fit a model, apply the convergence gate, or provide recovery
evidence.

A separate, explicitly resource-bounded function checks that generation,
pre-fit validation, fitting, and output-integrity diagnostics are connected:

```julia
one_case = mgmfrm_response_stress_plan(
    design_strata = (:connected_sparse_systematic_link,),
    response_patterns = (:regular_all_categories,),
)
fit_smoke = mgmfrm_response_stress_fit_attempts(one_case)

fit_smoke.summary
fit_smoke.rows
```

By default, `maximum_attempts = 1`; expanding the plan across more source
cases, backends, or prior regimes requires an explicit larger bound before any
generation or fitting starts. Each admitted attempt terminates as
`:generation_failed`, `:pre_fit_rejected`, `:fit_failed`,
`:diagnostic_failed`, or `:completed`. Exceptions retain their object, concrete
type, message, and phase, and a successful fit is retained when only its
diagnostic phase fails.

The executable `:wiring_smoke` profile uses one chain with four warmup and four
retained draws. Its integrity checks cover finite draws, log densities,
pointwise log likelihoods, predictive probabilities and expected scores,
probability normalization, and direct-parameter constraints. Sampler flags are
recorded but not adjudicated. Consequently, completion establishes only
operability of this path: convergence, recovery, coverage, backend agreement,
prior sensitivity, and scientific decisions remain explicitly unassessed.
`profile = :analysis` is rejected before execution until the Stage-A analysis
contract and independently reviewed thresholds are frozen.

Use the non-executing contract to inspect that boundary directly:

```julia
execution_design = mgmfrm_validation_execution_design_contract()
analysis_contract = mgmfrm_validation_analysis_contract()
primary_grid_candidates = mgmfrm_validation_primary_grid_candidates()
primary_candidate = simulate_mgmfrm_validation_primary_candidate(
    first(primary_grid_candidates.cells),
)
# Explicit and heavier: materializes all 16 candidate datasets.
primary_grid_preflight = mgmfrm_validation_primary_grid_preflight(
    primary_grid_candidates,
)
primary_resource_plan = mgmfrm_validation_primary_resource_plan()
primary_resource_probe = mgmfrm_validation_resource_probe(
    first(primary_resource_plan.rows),
)

execution_design.heldout
execution_design.retry
execution_design.sensitivity
analysis_contract.status
analysis_contract.fixed_components
analysis_contract.open_decisions
analysis_contract.next_work_order
```

Thirteen structural, computational, and execution-design components are now
recorded as fixed in the Stage-A draft. The primary predictive target is a
seeded five-fold observation split conditional on person, item, and rater
levels retained in every training fold; `kfold_plan_diagnostics(...;
facets = :all)` must pass before refitting. This does not estimate prediction
for unseen persons, items, or raters. Primary results cannot be overwritten by
remediation, and the 24 sensitivity role-cells cover prior/response, Q
boundary/misspecification, unidimensional MFRM comparison, and paired CmdStan
roles without treating their count as a fit workload.

The fixed-Q stress generator accepts odd item totals. It assigns pure items to
the two dimensions with a count difference of one, so the source-anchored 5-
and 15-item candidates do not require a false equal-count identification rule.

The candidate contract enumerates 16 source-anchored primary cells from two
designs, 50/100 persons, 5/15 items, and 5/15 raters. Their expected observation
counts range from 500 to 22,500. Nine exceed the present 2,000-observation
short-NUTS bound. The four-category known-truth generator and MCMC-free
structural preflight are implemented. They expose whether each candidate can
be generated and structurally compiled, but do not resolve resource coverage,
freeze cells, authorize execution, or provide recovery evidence.

The primary resource plan selects four ordered 4-category representatives with
500, 1,250, 3,750, and 7,500 observations. Pass only one row at a time to
`mgmfrm_validation_resource_probe`; execution remains explicit and
memory-guarded. These gradient cells do not span every primary axis. The
shared bounded short-NUTS adapter accepts either one five-category stress row
or one four-category primary row without duplicating fit and diagnostic
orchestration. The first two primary resource rows meet the current workload
bound; the later rows remain gradient-only under the present policy. All four
use resource-only seeds, distinct in role from structural-preflight and future
evaluation seeds. The first two rows can be passed by `cell_id` to
`mgmfrm_validation_isolated_resource_probe`; the later two fail the current
short-NUTS workload bound before a worker starts.

Four decisions still block execution: final primary grid cells, evaluation
replications, analysis resource caps, and independently reviewed scientific
thresholds. Until the grid and replications are frozen, the analysis attempt
denominator remains deliberately not computable. Runtime pilots may inform
cost and batching, not scientific cutoffs or backend rankings. The design
contract is expressed through documented package APIs and semantic options.

Initial resource profiling is explicit and inert by default:

```julia
probe_plan = mgmfrm_validation_resource_probe()

# Executes no MCMC; workload and available-memory bounds are checked first.
probe = mgmfrm_validation_resource_probe(execute_measurement = true)
probe.rows
probe.runtime
```

The measured operation is a warmed ForwardDiff log-density/gradient evaluation
for one dense and one connected-sparse regular-response cell. It records typed
failures and preserves the planned denominator without returning fit objects.
The explicit path uses a 2 GiB available-memory screen with a non-lowerable
1 GiB floor before data generation or gradient evaluation. Rejection preserves
every cell as unstarted. On macOS, `Sys.free_memory()` is retained as a raw
free-page observation but is not used alone as available memory. The probe
separately records a conservative `free + inactive + speculative` estimate and
the system memory-pressure percentage; both the byte floor and pressure check
must pass. The observation basis is explicit, and a failed macOS observation
falls back visibly rather than silently. The screen is operational risk
control, not a memory reservation or validation threshold.
The timings are local operational metadata only: they cannot choose priors, Q,
scientific thresholds, or a preferred backend, and they cannot be extrapolated
to four-chain NUTS. A bounded short-NUTS resource probe and an explicit memory
review remain necessary before final grid and resource caps are frozen.

The direct short-NUTS primitive is also inert unless execution is explicit:

```julia
short_plan = mgmfrm_validation_short_nuts_resource_probe()

# The planned validation route runs it once in a dedicated worker.
isolated_default = mgmfrm_validation_isolated_resource_probe(
    execute_measurement = true,
)

# Primary work order: one eligible primary cell in its own worker.
isolated_primary = mgmfrm_validation_isolated_resource_probe(
    first(primary_resource_plan.rows).cell_id,
    execute_measurement = true,
)
```

Its only cell is connected-sparse and uses one AdvancedHMC chain with 25
warmup transitions and 25 retained draws. The default available-memory
requirement is 2 GiB with a non-lowerable 1 GiB floor. Rejection occurs before
generation or MCMC. A successful run discards fit objects, preserves typed attempt rows,
and records elapsed time, cumulative Julia allocations, and endpoint free
memory. It does not claim peak memory or convergence and cannot freeze the
final analysis resource policy by itself. Calling the direct primitive with
`execute_measurement = true` remains useful for debugging, but the validation
work order does not duplicate that MCMC run before the isolated invocation.

Scaled profiling is a separate MCMC-free plan:

```julia
scaled = mgmfrm_validation_scaled_resource_plan()

# After the isolated default sparse probe succeeds, submit one cell identifier.
next_probe = mgmfrm_validation_isolated_resource_probe(
    scaled.execution_order[1],
    execute_measurement = true,
)
```

The legacy stress/scaling sequence contains 144, 600, 600, and 2,000
observations. The two
600-observation cells deliberately contrast connected-sparse and dense layouts
instead of assuming observation count alone determines cost. Any memory,
generation, fit, diagnostic, or unexpected-allocation problem stops manual
progression. These cells are not the final scientific sample-size grid.

`Sys.maxrss()` is recorded before and after short-NUTS as process-lifetime
maximum resident memory. In a reused Julia process it is not attributable to
the probe interval, even when it increases. The isolated surface above starts
one child only after the parent available-memory check passes.

The child repeats the workload and available-memory checks and returns one
compact JSON receipt; its fit object is discarded. A wall-time timeout
terminates the single-threaded worker and is retained as a typed terminal state. The recorded
peak RSS is attributable to that dedicated worker process, but includes
startup, package loading, compilation, generation, sampling, and diagnostics.
It is therefore not a sampler-only measurement. Julia, OS, architecture,
thread, wall-time, raw free memory, the distinct available-memory estimate and
its observation basis, and memory pressure are retained without requiring a
repository or commit
identity. Run the cells sequentially, inspect each receipt before continuing,
and use
`maximum_observations_per_cell = 2_000` explicitly for the final 2,000-row
scaled cell. These operational receipts neither assess convergence nor freeze
scientific or resource thresholds.

Review any collected results without rerunning them:

```julia
resource_review = mgmfrm_validation_isolated_resource_review((
    isolated_default,
    next_probe,
))
resource_review.rows
resource_review.summary
resource_review.stage_1_operability
```

The review requires unique cells in the declared contiguous order beginning
with either the default sparse stress cell or the first eligible primary cell.
Stress and primary collections cannot be mixed into a passing sequence. The
review preserves incomplete and rejected results together with divergences,
tree depth, leapfrog-step count, step size, and E-BFMI chain coverage. These
short-chain geometry fields are operational observations, not convergence or
scientific decisions. The review applies no thresholds and never advances
automatically. For primary-grid receipts, `stage_1_operability` maps the two
minimum-support candidate cells to their resource records and reports whether
both completed receipts and denominators are present. Complete submission only
permits a manual operability-scope decision; the milestone remains open and no
convergence, recovery, portable-performance, or scientific claim is made.
When receipts are absent, recovery or submission of existing records precedes
any consideration of a rerun.

## Clustered Responses and Testlet Identity

When multiple criteria, items, or raters refer to the same response, map the
source columns explicitly:

```julia
clustered_data = FacetData(clustered_ratings;
    person = :examinee,
    rater = :rater,
    item = :criterion,
    score = :score,
    response_id = :essay_id,
    testlet_id = :prompt_id,
    occasion = :occasion,
)
```

`response_id` denotes one globally unique scored response. It must map to one
person, one testlet, and, when recorded, one occasion. If response identifiers
are unique only within person, construct a composite identifier before calling
`FacetData`. `testlet_id` is separate from the existing `task` role: the package
does not silently reinterpret task metadata as a testlet. All three fields are
metadata in the current likelihood and add no fitted parameter.

Use [`testlet_design_check`](@ref) to examine the intended clustered effect:

```julia
design_check = testlet_design_check(clustered_data;
    target = :scalar_shared_cluster,
    independent_ratings_declared = true,
)
```

The check separates identifier validity, structural identification, the scope
of the named candidate, the frozen structural profile, current fitting support,
and pair-family-specific diagnostic support. The fields
`structurally_eligible_for_candidate`, `structural_profile_met`, and
`current_fit_supported` are deliberately distinct; the last remains `false`
for every clustered effect in this release. An `:ok` status means only that the
unchanged structural screen is met. `:unsupported_candidate` distinguishes a
current candidate-shape limitation, such as repeated responses in the first
scalar slice, from `:underidentified`; `:error` indicates inconsistent response
identity or duplicate response-rater-item keys. Any threshold override is
labelled `support_profile = :custom_unvalidated`. Declaring independent ratings
records a design fact supplied by the analyst; it does not verify independence
from the scores.

The initial scalar target requires one response per person-by-testlet,
multiple indicators per response, multiple testlets per person, multiple
persons per testlet, and connected ordinary and person-by-testlet graphs.
Repeated responses are evaluated separately because stable person-by-testlet
variation and response-specific variation cannot be distinguished from one
occasion. Halo support requires the multiple-indicator rater-response cells to
co-occur within independently multiply rated responses; a graph joined only by
one shared response is rejected by the frozen screen. Rater-by-task support
requires ordinary, rater-task, and person-task connectivity, replicated cells,
multiple raters per task, and shared person or response links. Fixed-Q MGMFRM
support additionally requires the person-testlet base graph, a connected
Q-by-testlet graph, within-testlet Q contrasts, and no perfect dimension-testlet
alignment. `diagnostic_pair_support` reports support separately by testlet for
the contract's applicable pair families; it is not a local-independence result.

[`local_dependence_contract`](@ref) records the provisional matching,
duplicate, adjusted-Q3, FDR, global maximum-statistic, and conditional versus
marginal predictive-check rules. It keeps three estimands distinct: item Q3
when each response-item has one rating and each response has one rater, item Q3 within a common
response-by-rater unit, and rater-pair association on a common
response-by-item unit. It never silently averages multiple raters or repeated
responses; cross-rater cross-item pairing is also unavailable until its
independence and weighting rules are predeclared. Estimation and adjusted-Q3
centering are stratified by `testlet_id`. Pair support is evaluated draw by
draw from the joint validity mask, with both an absolute draw minimum and an
eligible-draw fraction; undefined or sparse correlations remain report-only.
The named `:ld0_v1` thresholds are frozen but uncalibrated; threshold
sensitivity must use `profile = :custom_unvalidated`.

[`local_dependence_summary`](@ref) now evaluates those three pair families for
fitted MFRM and guarded GMFRM/MGMFRM objects. It reports raw and adjusted-Q3-
style draw summaries for item pairs, same-response/same-criterion rater-pair
association, common units and distinct common responses, family-by-testlet
support graphs, paired posterior predictive tail fractions, within-family BH
values, and one all-family maximum-statistic reference. Draw indices must be
distinct; `ndraws` uses sampling without replacement. A rater pair supported by
many criteria from only one response is marked as single-response
concentration and cannot justify a halo interpretation. Pair rows require at
least one common unit; zero-overlap combinations are retained in aggregate
family counts and testlet-stratified support graphs rather than materialized as
quadratically many empty rows. `family_status` and `testlet_status` distinguish
global family support from a sparse individual testlet; single-rating
applicability is also testlet-specific. Candidate-pair rows, shared-unit links,
positive-pair-by-draw cells, pair/common-unit-by-draw cells, and predictive
cells have separate resource counts and fail with an actionable error before
large work begins. The package still does not enable FDR/FWER decision labels,
declare local dependence, identify its mechanism, or fit a testlet random
effect.

## Known-Truth Local-Dependence Validation

LD1a adds a sampler-free way to exercise those structural contracts:

```julia
grid = local_dependence_simulation_grid()
generated = simulate_local_dependence(first(grid))
```

The frozen grid contains 22 matched scenarios spanning null and exact-zero
controls, study-local near-zero through large person-by-testlet variation,
pair-support boundaries, connected sparsity, pre-fit rejection controls,
rater-response halo, rater-by-task severity, omitted multidimensionality,
randomized drift, ability-confounded no-drift order, ability-informed rater
assignment, and a testlet-plus-sequence mixture. Scores come from an
adjacent-category kernel
implemented separately from the fitted likelihood. Each result retains the
intended category scale even when a realized sample omits an extreme category,
and records semantic event-keyed uniforms, component truth, sequence position,
design checks, and pre-allocation rating, probability, and truth-cell counts.

`max_ratings`, `max_probability_cells`, and `max_truth_cells` are checked from
the requested design before latent or row-level arrays are allocated. Facet
truth and response uniforms use stable semantic integer keys, so adding a
person or item does not renumber the common truth. The recorded engine is
Julia's `MersenneTwister`; bit-for-bit portability across Julia RNG
implementations is not claimed, and the versioned plan record includes project
and manifest fingerprints for its reproduction environment.

The ability-confounded no-drift scenario tests whether case mix and presentation
order can create a misleading time pattern. It does not materialize parameter
anchors, common linking responses, or time-distributed benchmark responses;
their amount, range, and early/middle/late placement remain separate design
studies. LD1a establishes generator and pre-fit behavior. LD1b0 adds an
MCMC-free protocol and scorer validation layer that keeps missing, failed,
rejected, unsupported, and completed replications distinct. LD1b1 adds
`local_dependence_calibration_pilot_contract` and
`local_dependence_calibration_pilot_check`, which freeze a 30-replication
pilot plan for each of the 22 scenarios and validate its study-specific sampler
and diagnostic requirements. The check runs no fit or MCMC, and the pilot
and evaluation remain unrun. It supplies no repeated-calibration, power,
diagnostic-decision, or mechanism-identification evidence. Clustered effects
remain unsupported for fitting.

Use [`validation_suggestions`](@ref) to convert validation issues into
machine-readable next-step suggestions:

```julia
validation_suggestions(validation)
```

`mfrm_spec` currently supports `thresholds = :rating_scale` and
`thresholds = :partial_credit`. The default `family = :mfrm`,
`dimensions = 1`, and `discrimination = :none` configuration is the
fit-supported minimal MFRM/RSM/PCM slice. `family = :gmfrm` and
`family = :mgmfrm` can be declared for manifest and constraint review, but they
have `estimation_status = :specified_only` and are rejected by `getdesign`
unless `preview = true` is requested. Preview designs expose parameter names and
block ranges for design review, but are not accepted by `fit` unless they are
one of the guarded experimental generalized candidates.

Use [`model_ladder`](@ref) to inspect the package's fit-supported and
specified-only model ladder, and [`constraint_table`](@ref) to inspect
constraints, transforms, prior-block declarations, DFF validation-only rows,
and multidimensional Q-mask gauge declarations.

For fixed-Q MGMFRM work, call [`q_matrix_validation`](@ref) before or after
`mfrm_spec`. It reports binary-mask schema checks, empty item rows, empty
dimensions, duplicate or aliased dimension columns, fixed cross-loading policy,
the generic structural rank allowed by the Q zero pattern, person-specific
dimension support, positive-loading/pure-item warnings, the standard-normal
identity-correlation prior anchor, and dimension-specific person-rater-item
subgraph coverage. Invalid fixed-Q specs throw an actionable error that points
back to this manifest.

Inspect `validation.identification` to keep three claims separate:

- `likelihood_support.q_full_column_structural_rank` asks whether some loading
  matrix with the declared zero pattern can generically have full column rank;
- `likelihood_support.person_rows` asks the same question for the items actually
  observed for each person, so an incomplete row is reported as relying on the
  population prior for at least one ability direction; and
- `prior_anchor` records that the current origin, scale, and latent rotation are
  anchored by standard-normal abilities and fixed identity correlation, rather
  than identified by the likelihood alone.

`guarded_fit_structure_ready` retains the current experimental pre-fit boundary.
`conservative_stable_structure_ready` is stricter: it additionally requires
full person-level dimension support, at least one pure item per dimension, and
connected dimension-specific facet graphs. It is a sufficient structural
screen only; it does not replace recovery, sensitivity, or external validation.

For a specified-only GMFRM/MGMFRM, use `getdesign(spec; preview = true)` to
inspect the source-aligned generalized blocks without enabling fitting. GMFRM
previews expose item-discrimination, rater-consistency, and rater-step blocks.
MGMFRM previews expose person-by-dimension, item-dimension-discrimination,
rater-consistency, and item-step blocks. The separate guarded generalized fit
paths use `BayesianMGMFRM.Experimental.fit(spec)` and are limited to the
one-dimensional rater-consistency GMFRM candidate and the fixed-Q
confirmatory MGMFRM candidate with `dimensions >= 2`.

Use [`design_row_table`](@ref) when you need row-level compiler evidence. The
table shows the facet labels, identified parameter indexes, source-step path, and
preview generalized parameter indexes touched by each observed rating. For
specified-only GMFRM/MGMFRM specs, call
`design_row_table(spec; preview = true)`; this remains an inspection path and
does not make those likelihoods fit-ready.

Use [`linear_predictor_table`](@ref) when you need the same compiler evidence
for every response category, not only the observed category. This table is the
denominator-level review surface for checking category-specific location
multipliers, step paths, item-discrimination blocks, rater-consistency blocks,
and item-dimension-discrimination blocks before broad GMFRM/MGMFRM likelihoods
are enabled.

For the current fit-supported MFRM/RSM/PCM slice, use
[`linear_predictor_values`](@ref) with a parameter vector to add numeric
`eta`, row log-denominator, and category log-probability values to the same
row-by-category structure. Numeric values remain disabled for specified-only
GMFRM/MGMFRM previews.

Pass the `validation_report` from `validate_design`, or pass the same `bias`
terms to `mfrm_spec`, when you want the DFF cell evidence retained in the spec.
Supplied validation reports are accepted only for the same `FacetData`; if
`bias` or `min_cell_count` is passed again, the validation options must also
match.

`getdesign(spec)` returns a compact compiled design object with stable parameter
names and block ranges. The current minimal design fixes the first rater and
item levels as references and represents threshold steps with a sum-to-zero
constraint.

`FacetData`, `FacetSpec`, and `FacetDesign` contain mutable Julia collections,
so construction alone is not a permanent immutability guarantee. Numerical,
cache-request, and design-manifest entry points therefore recheck the current
data signature and compiler-derived spec/design fields. Use
[`design_identity`](@ref) to perform this check explicitly and obtain the
canonical SHA-256 identity of the encoded data, model specification, parameter
order, block ranges, and identification declarations:

```julia
identity = design_identity(design)
identity.algorithm   # :sha256
identity.value       # canonical semantic design fingerprint
```

If the underlying data, Q matrix, parameter names, block ranges, or
identification declarations were changed after validation/compilation, the
entry point fails and asks for a new `FacetData`, validation report,
specification, or compiled design. `fit` and `MFRMLogDensity` retain a validated
deep snapshot rather than the caller's mutable design object; compare designs
with `design_identity(...).value`, not object identity (`===`).
For cross-process provenance, use ordinary portable facet labels such as
strings, symbols, integers, and tuples of those values. A custom label type
whose `repr` embeds an object address cannot provide a portable fingerprint.

Use [`model_manifest`](@ref) to capture the current data/spec/design provenance
contract for reports and future cached fits:

```julia
model_manifest(data; view = :public)
model_manifest(spec; view = :public)
model_manifest(design; view = :public)
```

This is the scaffold for the full MFRM/GMFRM/MGMFRM compiler. The ordinary
model-fitting API remains the minimal MFRM/RSM/PCM configuration; guarded
experimental generalized fits are opt-in through
`BayesianMGMFRM.Experimental.fit(spec)`
for the narrow scalar GMFRM and fixed-Q confirmatory MGMFRM candidates described
above.

## Reporting Data Before Fitting

The first reporting helpers expose fit-independent data for Quarto tables and
figures without adding a plotting dependency:

```julia
coverage = coverage_summary(spec)
heatmap_data = coverage_matrix(data; rows = :rater, columns = :person)
overlap = rater_overlap(data; unit = :person_item)
linking = anchor_linking_summary(spec; unit = :person_item, view = :public)
rating_design = rating_design_check(spec; unit = :person_item, view = :public)
thresholds = threshold_map_data(design; params = zeros(length(design.parameter_names)))
```

`coverage_summary` returns long-form category counts, facet-level counts, and
compact facet summaries. `coverage_matrix` returns a facet-by-facet count
matrix for heat maps. `rater_overlap` returns pairwise overlap counts and
Jaccard overlap for the chosen rated unit. With clustered metadata, units also
include `:response_id`, `:testlet_id`, `:person_testlet`, and
`:response_item`. The two testlet-based units are marked as descriptive
coverage: sharing only a testlet label does not establish shared-response
rater linking, so `anchor_linking_summary` and `rating_design_check` reject
them as linking units. The response-based units are explicitly marked as
common-response linking candidates. `anchor_linking_summary` combines
declared hard/soft anchor rows, anchor target checks, rater overlap
connectedness, and optional anchor-axis sensitivity coverage; it is a
diagnostic report, not an anchor refit or linking-constant estimator.
`rating_design_check` packages the observed rating-graph components, weak
rater links, anchor coverage, complete-grid coverage, repeated ratings, sparse
person-rater-item cells, optional time/order metadata, and nonignorable rater
assignment limitation into report rows. Because the current `FacetData`
contract stores observed complete long-format rows rather than an external
planned-design table, structural versus accidental missingness is reported as
not identifiable from the observed data alone. The same review is threaded into
`model_manifest` and `fit_report`.

Three names in this diagnostic require careful interpretation. The legacy
`optional_time_order_fields` row only reports whether categorical `occasion`
metadata exist; it does not verify within-rater sequence, timestamps, or
randomized presentation. `nonignorable_assignment_flagged = true` is a standing
limitation warning, not a data-driven finding that assignment was nonrandom.
The `sparse_person_rater_item_blocks` row counts observed cells below the
requested repetition threshold; it is not the overall fraction of a planned
rating grid that was sampled.

Likewise, `anchor_coverage` checks declared hard/soft parameter-anchor targets.
It does not count common responses used to link raters. For design studies,
report `multiply_scored_target_fraction` (the proportion of unique person--item
targets scored by at least two raters), `common_linking_target_fraction` (the
proportion deliberately shared by the designated linking raters), and the
corresponding share of all rating events separately. A double-rated design has
`multiply_scored_target_fraction = 1` even when it has no special all-rater
common set. Controlled benchmarks with reference information are a fourth
quantity. The design-robustness examples materialize separate 5% and 10%
all-rater common sets and report planned and observed denominators, target
displacement under a fixed rating-event budget, and achieved order/ability
metrics. These MCMC-free checks do not provide repeated paired-recovery
evidence.

`threshold_map_data` returns rating-scale or partial-credit threshold-step
metadata, including derived sum-to-zero steps when a parameter vector is
supplied.
