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
- singleton person, rater, item, and optional metadata levels;
- connectedness of the person-rater-item graph;
- rank of the current reference-constrained minimal location design;
- item/category support warnings for weakly informed partial-credit thresholds;
- empty, sparse, and potentially confounded DFF cells for requested `bias`
  terms.

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

Use [`testlet_design_audit`](@ref) to examine the intended clustered effect:

```julia
audit = testlet_design_audit(clustered_data;
    target = :scalar_shared_cluster,
    independent_ratings_declared = true,
)
```

The audit separates identifier validity, structural identification, the scope
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
applicability is also testlet-specific. Audit-pair rows, shared-unit links,
positive-pair-by-draw cells, pair/common-unit-by-draw cells, and predictive
cells have separate preflight counts and fail with an actionable error before
large work begins. The package still does not enable FDR/FWER decision labels,
declare local dependence, identify its mechanism, or fit a testlet random
effect.

## Known-Truth Local-Dependence Preflight

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
design audits, and pre-allocation rating, probability, and truth-cell counts.

`max_ratings`, `max_probability_cells`, and `max_truth_cells` are checked from
the requested design before latent or row-level arrays are allocated. Facet
truth and response uniforms use stable semantic integer keys, so adding a
person or item does not renumber the common truth. The recorded engine is
Julia's `MersenneTwister`; bit-for-bit portability across Julia RNG
implementations is not claimed, and the versioned preflight records project
and manifest fingerprints for its reproduction environment.

The ability-confounded no-drift scenario tests whether case mix and presentation
order can create a misleading time pattern. It does not materialize parameter
anchors, common linking responses, or time-distributed benchmark responses;
their amount, range, and early/middle/late placement remain separate design
studies. LD1a establishes generator and pre-fit behavior. LD1b0 adds an
MCMC-free protocol and scorer validation layer that keeps missing, failed,
rejected, unsupported, and completed replications distinct. LD1b1 adds
`local_dependence_calibration_pilot_contract` and
`local_dependence_calibration_pilot_preflight`, which validate a
`30 × 22 = 660` execution plan without running it. The planned rows contain 540
eligible fitting jobs and 120 planned structural rejections. A retry cannot
replace the original failed outcome, and the operational candidate bounds are
study-local.
The MCMC-free `local_dependence_pilot_protocol_preflight.json` artifact records
that rank-normalized R-hat and bulk/tail ESS capability is available and the
pilot execution protocol is authorized under the exact diagnostic dependency
and operation-order record, primary fields, tail probability, minimum chain and
draw requirements, complete-chain E-BFMI coverage, and recorded SHA-256 digest
of `src/bayesian_fit.jl`. This authorization is not a completed run or
calibration evidence. The pilot and evaluation are still
pending; the 50- and 100-replication evaluation sizes must be selected and
frozen after the pilot and before evaluation. The magnitude settings are not
universal cutoffs, and no calibration evidence, pairwise power, diagnostic
decision, or mechanism interpretation is available.

The MCMC-free `local_dependence_pilot_batch_execution_harness.json` dry run
checks the complete 660-row layout of 540 eligible fitting jobs and 120 planned
pre-fit rejections. Before a result can contribute to aggregation, its frozen
job identity, seeds, attempt, terminal status, executor identity, role-specific
evidence content, and file digests must agree. Every role binds one source
artifact and its upstream evidence hashes. The frozen `pilot_contract` and
ordered 660 job rows are verified against canonical SHA-256 values. A
`pre_fit_rejected` result requires `generated_data`, then
`structural_rejection_audit`, then a `calibration_row` conforming to the
existing public calibration-row contract. The simulation member is checked for
response data, table-column lengths, probability cells, truth and row-truth
arrays, structural eligibility, and data/score/design signatures. Fit evidence
must use the structured `local_dependence_pilot_fit_artifact_export.v1` JSON
wrapper with retained draws, log posterior values, and sampler statistics. Its
package-native content hash must be verified by the future pinned canonical
executor before JSON projection; the batch runner separately recomputes the
canonical JSON payload hash and verifies the exact file SHA-256. The JSON
projection cannot soundly reconstruct the native typed hash. Data,
design, fit-artifact, retained-draw, chain, and iteration provenance is compared
across fit, sampler, local-dependence, and calibration evidence. The custom
`local_dependence_pilot_summary_bundle.v1` directly records the draw-selection
and posterior-predictive seeds; the runner compares both with its evidence
payload, the frozen job, and the calibration execution seeds. Draw selection
uses the frozen `sha256_seeded_rank_without_replacement_v1` algorithm, and the
runner recomputes its ordered draw indices from the frozen seed.
The posterior-predictive seed is source-bound, but seed-to-result replay
verification remains
pending the canonical single-job executor and bounded smoke review. A
`diagnostic_failed` result may name `sampler_quality_gate` only when that gate
failed, or `local_dependence_summary` only after it passed. Generated resource
counts and frozen sampler-quality conditions are checked explicitly; symbolic
links, hard links, and unmanifested files are
rejected. These checks establish result consistency and provenance, not
statistical calibration or model adequacy. The controller prohibits
overwriting primary outcomes, preserves remediation as
additive records, and on resume first rescans the complete attempt archive as
the source of truth. It then verifies and compares the derived checkpoint and
skips only verified terminal primary records. The generated dry run does not
assess an attempt archive. Snapshot values are rechecked against a static
inventory, but that is not an atomic completed-attempt seal. The canonical
single-job executor, bounded smoke review, completed-attempt seal, and
append-only recovery or retirement path for interrupted attempts remain
required before execution.

No response data are generated, no model is fitted, and no MCMC is run; pilot
results, calibration or power estimates, diagnostic decisions, and mechanism
interpretations remain unavailable.

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
positive-loading anchor warnings, and dimension-specific person-rater-item
subgraph coverage. Invalid fixed-Q specs throw an actionable error that points
back to this manifest.

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
model_manifest(data)
model_manifest(spec)
model_manifest(design)
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
linking = anchor_linking_summary(spec; unit = :person_item)
rating_design = rating_design_audit(spec; unit = :person_item)
thresholds = threshold_map_data(design; params = zeros(length(design.parameter_names)))
```

`coverage_summary` returns long-form category counts, facet-level counts, and
compact facet summaries. `coverage_matrix` returns a facet-by-facet count
matrix for heat maps. `rater_overlap` returns pairwise overlap counts and
Jaccard overlap for the chosen rated unit. With clustered metadata, units also
include `:response_id`, `:testlet_id`, `:person_testlet`, and
`:response_item`. The two testlet-based units are marked as descriptive
coverage: sharing only a testlet label does not establish shared-response
rater linking, so `anchor_linking_summary` and `rating_design_audit` reject
them as linking units. The response-based units are explicitly marked as
common-response linking candidates. `anchor_linking_summary` combines
declared hard/soft anchor rows, anchor target checks, rater overlap
connectedness, and optional anchor-axis sensitivity coverage; it is a
diagnostic report, not an anchor refit or linking-constant estimator.
`rating_design_audit` packages the observed rating-graph components, weak
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
quantity. The versioned `existing_api_design_robustness_plan.json` demonstrates
these distinctions with physically materialized 5% and 10% all-rater common
sets. The companion MCMC-free stress-grid artifact records both planned and
observed denominators, target displacement under a fixed rating-event budget,
and achieved order/ability metrics. Its contract checks pass, while repeated
paired recovery remains a separate required gate.

`threshold_map_data` returns rating-scale or partial-credit threshold-step
metadata, including derived sum-to-zero steps when a parameter vector is
supplied.
