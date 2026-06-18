# Long-Format Data and Pre-Fit Validation

`BayesianMGMFRM.jl` starts from long-format rating data: one row per rating
event. The v0.1 data/spec slice is intentionally estimation-free. Its purpose is
to make common weak or non-estimable many-facet design patterns visible before
a sampler is called.

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

`mfrm_spec` currently supports `thresholds = :rating_scale` and
`thresholds = :partial_credit`. Pass the `validation_report` from
`validate_design`, or pass the same `bias` terms to `mfrm_spec`, when you want
the DFF cell evidence retained in the spec. Supplied validation reports are
accepted only for the same `FacetData`; if `bias` or `min_cell_count` is passed
again, the validation options must also match.

`getdesign(spec)` returns a minimal internal design object with stable parameter
names and block ranges. The current minimal design fixes the first rater and
item levels as references and represents threshold steps with a sum-to-zero
constraint.

This is the scaffold for the full MFRM/GMFRM/MGMFRM compiler; it is not yet a
model-fitting API.

## Reporting Data Before Fitting

The first reporting helpers expose fit-independent data for Quarto tables and
figures without adding a plotting dependency:

```julia
coverage = coverage_summary(spec)
heatmap_data = coverage_matrix(data; rows = :rater, columns = :person)
overlap = rater_overlap(data; unit = :person_item)
thresholds = threshold_map_data(design; params = zeros(length(design.parameter_names)))
```

`coverage_summary` returns long-form category counts, facet-level counts, and
compact facet summaries. `coverage_matrix` returns a facet-by-facet count
matrix for heat maps. `rater_overlap` returns pairwise rater linking counts and
Jaccard overlap for the chosen rated unit. `threshold_map_data` returns
rating-scale or partial-credit threshold-step metadata, including derived
sum-to-zero steps when a parameter vector is supplied.
