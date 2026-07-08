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
paths use `fit(spec; experimental = true)` and are limited to the
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

`getdesign(spec)` returns a minimal internal design object with stable parameter
names and block ranges. The current minimal design fixes the first rater and
item levels as references and represents threshold steps with a sum-to-zero
constraint.

Use [`model_manifest`](@ref) to capture the current data/spec/design provenance
contract for reports and future cached fits:

```julia
model_manifest(data)
model_manifest(spec)
model_manifest(design)
```

This is the scaffold for the full MFRM/GMFRM/MGMFRM compiler. The ordinary
model-fitting API remains the minimal MFRM/RSM/PCM configuration; guarded
experimental generalized fits are opt-in through `fit(spec; experimental = true)`
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
matrix for heat maps. `rater_overlap` returns pairwise rater linking counts and
Jaccard overlap for the chosen rated unit. `anchor_linking_summary` combines
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
`threshold_map_data` returns rating-scale or partial-credit threshold-step
metadata, including derived sum-to-zero steps when a parameter vector is
supplied.
