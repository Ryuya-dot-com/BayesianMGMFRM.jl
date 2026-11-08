# Long-Format Data and Pre-Fit Validation

!!! note "Unreleased documentation preview — 13 October 2026"
    This manual includes unreleased interfaces and examples. It is not the
    documentation of an installed release. Model support and scientific
    acceptance remain as stated on each page.

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
    category_levels = 0:2,
    group = :group,
)

validation = validate_design(data; bias = [(:rater, :group)])
validation.passed || error(validation)
spec = mfrm_spec(data; thresholds = :partial_credit, validation_report = validation)
```

`FacetData` records deterministic integer indexes and stable label maps for
persons, raters, items, the intended consecutive integer score scale, and
optional metadata roles. Pass `category_levels` when the form defines that
scale. If the keyword is omitted, the backward-compatible default is the
contiguous integer range from the observed minimum through maximum.
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

## Responses without a rater facet

For test responses with person, item and score columns, explicitly use
`rater=nothing`. A missing or misspelled rater column is still an error when a
column name is supplied. With intended scores `0:1`, the ordinary scalar
`mfrm_spec` model is binary Rasch/1PL: item discrimination is one and the logit
is person ability minus item difficulty. For consecutive ordered scores, the
same entry supports scalar partial-credit and rating-scale models.

```julia
data = FacetData(responses; person=:person, item=:item, score=:score,
    rater=nothing, category_levels=0:1)
validation = validate_design(data)
validation.passed || error(validation)
spec = mfrm_spec(data; validation_report=validation)
```

There are no estimated rater parameters. The existing representation retains
one fixed-zero level named `no_rater`; it is not a real judge. Encoded tables
and parameter-reference tables can show this level. The specification display
and `data.columns.rater === nothing` distinguish it from an observed rater.
Keep `rater=nothing` when reconstructing these responses from an exported table.
Saved native objects and report metadata retain the absent-column declaration.
Rater anchors and rater bias terms are rejected. Generalized and multidimensional
models are outside this entry's scope.

Use the [worked IRT example](examples.md#Ordinary-binary-IRT-without-raters)
for a complete input, explicit priors, estimation and saved review. Missing
answers remain absent rows; do not replace them with zeros. Preserve the full
intended category scale and inspect validation warnings before fitting.

## [Read your own CSV ratings](@id import-csv)

Start with a CSV file containing one **observed rating** per row. A speaking
assessment might use `person` for the participant, `item` for the rubric
criterion, `rater` for the judge and `score` for the ordered category. Keep the
original file and its coding instructions. Unobserved combinations should remain
absent: neither a zero nor an invented rating represents a missing observation.

The following is a format excerpt, not a complete analysis dataset:

```text
person,item,rater,score
001,I1,R1,3
001,I2,R1,2
1,I1,R1,4
1,I2,R1,3
```

Here `001` and `1` are different participant IDs. Read identifier columns as
text so numeric inference cannot merge them. If a spreadsheet has already
removed the zeros before export, the import cannot recover them. Check the
source IDs and their meanings before combining files.

Install CSV.jl in the [separate analysis project](index.md#Install-this-development-preview).
The recipe was checked with CSV.jl 0.10.16; to use the same parser version, run
`import Pkg; Pkg.add(name="CSV", version="0.10.16")` once in that project.
CSV.jl is an optional import tool, not a dependency added to the model package.
Keep the analysis project's `Project.toml` and `Manifest.toml` with your source.

For a comma-separated file with the four column names above and intended
categories 1 through 4, run:

```julia
# CSV import: inspect observed ratings without fitting.
using BayesianMGMFRM, CSV

ratings_path = "ratings.csv"  # replace with your file's path
ratings = CSV.File(ratings_path; delim=',',
    types=Dict(:person => String, :item => String, :rater => String, :score => Int),
    strict=true)
data = FacetData(ratings; person=:person, item=:item, rater=:rater,
    score=:score, category_levels=1:4)
display(data)
display((; persons=data.person_levels, items=data.item_levels,
    raters=data.rater_levels, categories=data.category_levels))
validation = validate_design(data)
display(validation)
for issue in validation.issues
    println(issue.severity, " [", issue.code, "]: ", issue.message)
end
validation.passed || error("Resolve the reported design errors before specifying a model.")
```

Replace the column names in **both** `types` and `FacetData` if yours differ;
change `delim` for a different separator. Set `category_levels` to the rating
form's full consecutive integer scale, including unused categories. If the form
uses verbal labels, first define and preserve their substantive order and an
explicit integer mapping; alphabetic order is not a rating scale.

`strict=true` makes invalid typed values, such as `poor` or `2.5` in the integer
score column, an import error. Empty required cells become missing and are
rejected by `FacetData`, which reports the column and row positions. Scores
outside `category_levels` are also rejected. Correct a coding error at its
source; for genuinely missing scores, retain a record of exclusions and the
reason before passing observed ratings. The recipe does not drop rows or impute
scores. Text missing-value codes such as `NA` require an explicit decision in
your import specification. See the [CSV.jl parsing options](https://csv.juliadata.org/stable/reading/).

Inspect warnings even when `validation.passed` is true: it means no checked
error was found, not that your sample size, dimensional structure or precision
is adequate. Adding a year, group or task column to a CSV does not automatically
estimate that effect. Use an explicitly supported model and role mapping;
shared performances need [response and criterion identities](joint-ratings.md).

### Continue with your own two-dimensional specification

Keep the `data` and `validation` objects above. The bundled example's
`example_inputs()` always reads its bundled ratings; it is not an importer for
your file. For a study where I1 and I2 measure fluency and I3–I5 measure accuracy,
the next step is:

```julia
# MGMFRM specification: use the imported data, not the bundled example.
q_by_item = Dict("I1" => (true, false), "I2" => (true, false),
    "I3" => (false, true), "I4" => (false, true), "I5" => (false, true))
Set(keys(q_by_item)) == Set(data.item_levels) ||
    error("Match the Q mapping to all observed item labels before continuing.")
q = Bool[q_by_item[item][d] for item in data.item_levels, d in 1:2]
spec = mfrm_spec(data; family=:mgmfrm, thresholds=:partial_credit,
    dimensions=2, q_matrix=q, dimension_labels=["Fluency", "Accuracy"],
    validation_report=validation)
q_check = q_matrix_validation(spec)
println("Q check passed: ", q_check.passed,
    "; warnings: ", q_check.summary.n_warning_rows)
display([(; check=row.check, severity=row.severity, status=row.status)
    for row in q_check.rows if row.severity != :info])
q_check.passed || error("Resolve the reported Q errors before fitting.")
display([(; person=row.person_label, unobserved=row.unobserved_dimension_labels,
    rank=row.structural_rank)
    for row in q_check.identification.likelihood_support.person_rows
    if !row.full_column_rank])
```

Replace the item mapping and dimension names with those justified by your rubric.
Q is assembled in the package's item order, so changing CSV row order cannot
reassign an item to another dimension. The final display lists people who lack
structural support for all ability directions. An empty list does not establish
adequate precision; [the dimension-support example](#person-dimension-support)
explains missing-dimension and rank warnings.

These steps stop at input checks and model specification. For fitting, choose
all six scales of the [normalized prior](experimental.md#MGMFRM-prior-choice-and-comparable-scales)
explicitly for your study and review the [current scientific scope](scope.md#current-scientific-evidence).
The bundled teaching prior and iteration count are not automatic defaults for
your data. Follow the [normalized MGMFRM workflow](examples.md#Explicit-normalized-prior-MGMFRM-workflow)
for the fit, diagnostics, interpretation and saved-result operations.

## Ordinal Response-Pattern Stress

Use [`ordinal_response_pattern_audit`](@ref) before fitting when category use
or boundary responses are part of the design risk:

```julia
audit = ordinal_response_pattern_audit(data)
audit.status
audit.category_scale.intended_levels
audit.category_scale.observed_levels
audit.category_scale.unobserved_interior_categories
audit.category_scale.unobserved_endpoint_categories
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
or an automatic scientific failure. Proper priors regularize these weakly
informed parameters; report the affected levels and examine sensitivity to prior
regimes. If the entire dataset contains only one score category, the ordered-
response likelihood is not estimable and `validate_design` returns an error.

The ordinary `FacetData` constructor infers the scale from the observed
minimum through maximum unless `category_levels` is supplied. For example,
`category_levels = 0:4` preserves five intended categories even when the
realized data contain only scores 1 through 4. `validate_design` then returns
the warning code `:unobserved_declared_endpoint`, and the response-pattern
audit separates the intended, observed, interior-unobserved, and endpoint-
unobserved categories. The likelihood, predictions, refit subsets, model and
fit metadata, and serialized fit cache retain the declared scale. The package
does not silently collapse it; deciding whether a category is structurally
possible or should be collapsed remains an analysis decision.

## [Check which dimensions each person was rated on](@id person-dimension-support)

In a two-dimensional speaking assessment, one participant may have fluency
ratings but no ratings on items that measure accuracy. The overall rating graph
can still be connected, and ordinary data validation can pass. That does not
mean both abilities have been measured for that participant. Run the Q check
after constructing the model and inspect the person-level results, not just
its overall `passed` flag.

Q rows follow `data.item_levels`, which need not be the order of rows in your
input table. Build Q from item names so that reordering a spreadsheet does not
change which construct an item measures. Keep the substantive item-to-dimension
mapping explicit; software cannot check whether that mapping fits your theory.

This complete example reads the existing artificial teaching ratings and omits
P1's ratings on the second dimension to illustrate an incomplete assignment.
It does not generate scores or fit a model. For your analysis, use your observed
rows and your own item mapping; do not remove ratings to reproduce this example.

```julia
# MGMFRM person-dimension inspection; no sampling.
using BayesianMGMFRM

ratings = include(joinpath(pkgdir(BayesianMGMFRM), "examples",
    "normalized_mgmfrm_ratings.jl"))
keep = [!(p == "P1" && i in ("I3", "I4", "I5"))
    for (p, i) in zip(ratings.person, ratings.item)]
observed = map(column -> column[keep], ratings)
data = FacetData(observed; person=:person, item=:item, rater=:rater,
    score=:score, category_levels=1:4)
validation = validate_design(data)
validation.passed || error(validation)

q_by_item = Dict("I1" => (true, false), "I2" => (true, false),
    "I3" => (false, true), "I4" => (false, true), "I5" => (false, true))
Set(keys(q_by_item)) == Set(data.item_levels) ||
    error("Match the Q mapping to all observed item labels before continuing.")
q = Bool[q_by_item[item][d] for item in data.item_levels, d in 1:2]
spec = mfrm_spec(data; family=:mgmfrm, thresholds=:partial_credit,
    dimensions=2, q_matrix=q, dimension_labels=["dim=1", "dim=2"],
    validation_report=validation)
q_check = q_matrix_validation(spec)
affected = [(; person=row.person_label,
    unobserved=row.unobserved_dimension_labels, rank=row.structural_rank)
    for row in q_check.identification.likelihood_support.person_rows
    if !row.full_column_rank]
display(affected)  # P1: unobserved dim=2, structural rank 1 rather than 2.
```

Here ordinary validation and `q_check.passed` both pass; the latter rejects
errors but retains warnings. The person-level result identifies the missing
dimension. Repeating ratings on P1's first-dimension items cannot supply ratings
for the second dimension. Do not fill absent rows with zero scores or treat a
converged posterior as evidence that those ratings exist.

For this independent-dimension model with independent person priors, an ability
coordinate absent from every observed item for that person has no likelihood
contribution: its posterior remains its prior. This statement assumes the stated
fixed prior and no extra terms coupling that coordinate to measured ones.
A correlated-ability model may borrow information under its correlation
assumptions; it still does not create direct ratings on the missing dimension.

When several dimensions load on the same items, a person may touch every
dimension yet still lack enough distinct items to separate all ability
directions. Then `unobserved` can be empty while `full_column_rank` is false.
Review the Q pattern and the person's observed items together. Even full
structural rank is only a support check: it does not establish precise estimates,
good recovery, or adequate overlap within each dimension. Inspect all Q warnings
and use [the pre-fit API help](api-data-design.md) for the full results.

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
current candidate-shape limitation, such as repeated responses in the scalar
shared-cluster target, from `:underidentified`; `:error` indicates inconsistent response
identity or duplicate response-rater-item keys. Any threshold override is
labelled `support_profile = :custom_unvalidated`. Declaring independent ratings
records a design fact supplied by the analyst; it does not verify independence
from the scores.

The `target = :scalar_shared_cluster` structural screen requires one response per person-by-testlet,
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

## Model Specification and Design Inspection

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

The stable MFRM slice also accepts exact individual rater/item hard anchors.
For a worked declaration and the distinction from a default reference or a
starting value, see [references and anchors](learning-guide.md#references-and-anchors).
Each declaration needs a supported block, explicit observed level, finite
non-Boolean logit value, and `type = :hard`. The anchor replaces that block's
default first-level-zero gauge and is omitted from the sampled/prior vector.
Multiple exact anchors may be combined across rater and item blocks, but they
do not waive the ordinary connectedness/rank validation gate and do not by
themselves establish common-response linking. Group anchoring of disconnected
subsets is outside the stable numerical scope.
Soft anchors and malformed or duplicate hard-anchor declarations remain
`specified_only` and fail closed at `getdesign`.

For fixed-Q MGMFRM work, call [`q_matrix_validation`](@ref) before or after
`mfrm_spec`. It reports binary-mask schema checks, empty item rows, empty
dimensions, duplicate or aliased dimension columns, fixed cross-loading policy,
the generic structural rank allowed by the Q zero pattern, person-specific
dimension support, positive-loading/pure-item warnings, the default standard-normal
identity-correlation prior anchor, and dimension-specific person-rater-item
subgraph coverage. Invalid fixed-Q specs throw an actionable error that points
back to this manifest.

Inspect the `identification` field returned by `q_matrix_validation(spec)`
to keep three claims separate:

- `likelihood_support.q_full_column_structural_rank` asks whether some loading
  matrix with the declared zero pattern can generically have full column rank;
- `likelihood_support.person_rows` asks the same question for the items actually
  observed for each person, so an incomplete row is reported as relying on the
  population prior for at least one ability direction; and
- `prior_anchor` records the design-reference standard-normal ability prior
  and fixed identity correlation, rather than likelihood-only identification.
  It is not an external fixed calibration and does not enable `anchors` for MGMFRM.
  An actual experimental fit can use a different `person_sd`; its diagnostics
  and artifacts record that resolved prior. See [prior and coordinate
  conventions](experimental.md#Workflow).

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
confirmatory MGMFRM candidate with `dimensions >= 1` and an explicit Q.
The one-column restriction retains the MGMFRM equation and item-owned steps;
it is distinct from the scalar rater-step GMFRM.

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
and item-dimension-discrimination blocks. Inspection does not extend the
configurations accepted by the experimental fitting API.

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

For optional parameter inspection, compile the stable specification:

```julia
design = getdesign(spec)
```

The design contains parameter names and block ranges. Without declared hard
anchors, it fixes the first rater and item levels as references; threshold
steps use a sum-to-zero constraint. Ordinary fitting can call `fit(spec)`
directly without this separate compilation step.

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

The ordinary model-fitting API supports the minimal MFRM/RSM/PCM
configuration; guarded
experimental generalized fits are opt-in through
`BayesianMGMFRM.Experimental.fit(spec)`
for the narrow scalar GMFRM and fixed-Q confirmatory MGMFRM candidates described
above.

## Reporting Data Before Fitting

These reporting helpers expose fit-independent data for Quarto tables and
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
It does not count common responses used to link raters. When reporting linking,
distinguish the proportion of unique person--item targets scored by at least
two raters, the proportion deliberately shared by designated linking raters,
and the corresponding share of all rating events. A design can double-score
every target without a special all-rater common set. Controlled benchmarks
with reference information are another distinct quantity.

`threshold_map_data` returns rating-scale or partial-credit threshold-step
metadata, including derived sum-to-zero steps when a parameter vector is
supplied.
## [Inspect a three-outcome input](@id three-outcome-input)

For the experimental no-state model of accentedness, comprehension difficulty
and transcription error, inspect the labelled input before attempting an
analysis. This operation checks the declared data contract; it does not fit the
model or establish identification, adequate linking or suitable priors.

```julia
using BayesianMGMFRM
T = BayesianMGMFRM.Experimental.ThreeIndicator
path = joinpath(pkgdir(BayesianMGMFRM), "examples", "data",
                "three_indicator_165.json")
answer = T.inspect_input(path;
    expected_sha256 = "af7aa24174eb601443c017543adb59b01d9109668db5c799568cc032db31e1ba")

answer.counts               # 165 events, 5 listeners, 11 speaker-style levels
answer.category_counts      # all 9/9/2 categories, including zero counts
answer.fixed_design         # rank 17 of 17 columns for this example
answer.block_start_events
answer.labels
answer.metadata
answer.warnings
```

This bundled input is an existing synthetic example with three words,
33 recordings and two listener cohorts. It contains no empirical participant
results and is not a recommended sample size. The checksum above identifies
its exact file bytes. For another JSON input, supply its separately retained
receipt; do not replace a failed receipt with a newly computed one merely to
bypass a mismatch. `inspect_input(input)` also accepts an already loaded
JSON3 object or a NamedTuple with the same fields.

One event is one listener's trial on one recording, with all three outcomes
observed. The first interface requires the following fields:

| Fields | Required meaning |
| --- | --- |
| `N, R, S, W, G, J, P` | Numbers of events, listeners, speaker-style levels, words, listener cohorts, recordings and fixed predictors. `J=S*W`, `P=15`. |
| `K`, `use_state`, `y` | `K=[9,9,2]`, `use_state=0`, and an `N × 3` integer matrix. Category 1 of the binary outcome is correct; category 2 is incorrect. The other two outcomes use 1–9, with higher categories adverse. Missing triples are rejected without dropping rows. |
| `rater, speaker, word, token, l1` | Length-`N` one-based indices. L1 row order is ENG, JPN, CHN. All declared listeners, speaker-style levels, words and recordings must occur. |
| `rater_group, speaker_cell, token_lookup` | Length-`R` cohort assignment; length-`S` condition assignment; `S × W` recording lookup containing each of `1:J` exactly once. There must be at least two listeners per cohort and two speaker-style levels per condition cell. |
| `trial, previous_trial` | Rows are grouped by listener index, with contiguous trials starting at 1. `previous_trial` is 0 at the listener's first event and the preceding **global row index** thereafter, including across blocks. |
| `X, predictor_names, within_time, l1_contrast` | `N × 15` finite predictor matrix, its exact names/order below, length-`N` position identical to `X[:,8]`, and the fixed `3 × 2` orthonormal, zero-sum L1 basis. |
| `labels` | Unique, nonempty ID arrays named `event, rater, speaker, word, token, cohort`, in index order. Speaker-style levels are distinct; an additional physical-speaker hierarchy is not supplied. |
| `metadata` | `outcomes=["accentedness","comprehension_difficulty","transcription_error"]`, `direction="higher_is_adverse"`, `binary_coding="1=correct;2=incorrect"`, and nonempty `scoring_version`, `predictor_units`, `source`. |

JSON matrices are arrays of rows. Condition cells 1–5 are ENG-natural,
JPN-natural, JPN-accented, CHN-natural and CHN-accented. The predictor order is:

1. Columns 1–4: `current_JPN_natural`, `current_JPN_accented`,
   `current_CHN_natural`, `current_CHN_accented`. These zero/one indicators
   must agree with the current speaker-style level's condition.
2. Columns 5–7: `block_2`, `block_3`, `block_4`. All zero means block 1;
   at most one is one, and blocks cannot run backwards within a listener.
3. Column 8: `within_time`, using the declared numeric units.
4. Columns 9–13: `previous_JPN_natural`, `previous_JPN_accented`,
   `previous_CHN_natural`, `previous_CHN_accented`, `previous_START`.
   At each listener or block boundary, START is one and the others are zero.
   Otherwise these columns describe the preceding trial's condition;
   all zero means preceding ENG-natural.
5. Columns 14–15: `word_lag_log`, `talker_lag_log`, with transformations and
   units retained in metadata.

The inspector checks recording ownership, scoring, labels, trial/condition
consistency and the rank of the fixed design including the intercept and cohort
indicators. Full fixed rank does not establish identification of the hierarchical
model or justify fitting. Recording coverage does not establish adequate links
between all listeners. Numeric position and lag transformations cannot be
reconstructed from this input alone: compare them with your preprocessing and
retain their units. Changing units also changes the meaning of coefficient
priors.

If a check fails, correct the source mapping or preprocessing before exporting
a new input. Do not relabel binary outcomes, pad missing categories, reorder
trials or change condition columns merely to obtain a pass. The inspector
does not modify the input. The example `examples/three_indicator_input.jl`
provides `three_indicator_input(path; expected_sha256)` using only the installed
package. Three-outcome fitting remains unavailable through this interface.
For already computed analyses, see [saved three-outcome results](api-saved-reporting.md#three-outcome-saved-reports).
