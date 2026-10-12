# Saved-fit Reporting Candidate API

These qualified candidate functions summarize the eight common saved-fit types.
Posterior summaries consume original retained draws and preserve numerical warnings
and source identity. The separate observed-score alpha and ICC operations consume ratings
and also accept `FacetData` without a fit. No fitting is performed. Their uncertainty definitions differ: a
finite-cohort reliability functional, matched-response score agreement, category use/steps/conditional curves, binary classification risk, and finite-cohort ranks answer distinct questions.

Read the [interpretation guide](interpreting-results.md) and the
[saved-fit examples](examples.md) before reporting their values. The standalone functions can also be requested together through
`fit_report(...; reporting=(...))`; see the integrated example below. The ordinary
MFRM diagnostics, including the historical replicated-category summary, remain
in the [Workflow and Diagnostics API](api-workflow-diagnostics.md).

## Reopen an analysis or share its results

Choose the saved format for the task:

| Task | Saved format and limitation |
| --- | --- |
| Recompute summaries or request another analysis from retained draws | Use `save_fit_cache` / `load_fit_cache` in the original Julia and package environment. Keep the Julia version (`VERSION`), `Project.toml` and `Manifest.toml` with the cache. A `.jls` cache uses Julia's native serialization; package support for two Julia versions does not guarantee that their caches are interchangeable. |
| Read or share already computed results | Use `save_fit_report_bundle` / `load_fit_report_bundle`. The bundle contains portable JSON reports and tables, with Markdown for reading. It preserves the reported values, warnings and identities; it does not reconstruct a fitted object or supply draws for a new analysis. |

For example, a cache written with Julia 1.12 can be rejected by Julia 1.10 with
`Cannot read stream serialized with a newer version of Julia`. Reopen that cache
in its original environment and export a report bundle there. Renaming the file
does not convert its format. An inability to read this binary cache is separate
from the package's ability to run an analysis under Julia 1.10.

## One report with explicit analysis choices

The optional `reporting` named tuple is shared by all eight supported saved-fit
types. Omitting it preserves the previous report behavior. Choose sections by
supplying `category=(...)`, `agreement=(...)` and/or a `reliability` tuple/vector
of named cohorts. The optional `classification=(;parameters, cutoff, pass_probability, interval=0.90)` adds a binary decision section; omitting it preserves the previous report shape. A missing legacy section is `:not_requested`; no cohort, target or
response matching is silently inferred.

Optional `alpha=(item="fluency", level=:ordinal, response_ids=performance_ids)`
adds observed-score alpha with the same dataset/rating identities. It uses no
posterior draws and supplies no SE or interval; see its API below.

Optional `icc=(item="fluency", model=:two_way_random, definition=:agreement,
unit=:single, score_scale=:interval, response_ids=performance_ids)` adds
`intraclass_correlation`. It requires a complete response-by-rater rectangle
for the selected item and an explicit equal-gap score assumption. There is no
silent complete-case deletion. The observed-data section supplies no SE or
interval; the existing fit diagnostics remain visible in their own section.

```julia
reporting = (;
    dataset_id="assessment-2026", observation_ids=rating_ids,
    category=(;interval=0.99),
    agreement=(;response_ids=performance_ids, interval=0.99, se_unit=:person),
    reliability=[(;id="Ability A", parameters=person_names_A, target=:centered)])

report = fit_report(fit_result; reporting, view=:public,
    include_posterior_predictive=false, include_artifact=false,
    include_waic=false, include_loo=false)
report.category_report.usage_rows
report.posterior_reliability.rows
report.rater_agreement.rows
fit_report_health(report)

save_fit_report_bundle("assessment-report", report; require_complete=true)
restored = load_fit_report_bundle("assessment-report"; require_complete=true)
```

`rating_ids` are persistent unique IDs in fitted-row order. `performance_ids`
identify actual shared performances; existing fitted response metadata may be
used by omitting that vector. The category and agreement sections share the same
dataset/rating identities. When normalized/correlated MGMFRM or multidimensional
MFRM reports also request predictive criteria, their top-level `dataset_id` and
`observation_ids` must match these identities.

`person_names_A` must contain exact estimated location-coordinate names for one
ability dimension. Inspect `BayesianMGMFRM.recovery_quantities(fit_result)` and
choose the cohort deliberately. Add a separate named cohort for another dimension;
select `target=:absolute` or `:centered` to match the question. Optional normalized
weights and the coordinate roster remain in the results. Fixed anchors are not
valid members of a reliability cohort.

Each category/agreement options tuple forwards the corresponding standalone API's
keywords, except their shared dataset/rating IDs. For example, category options
can contain `profiles`, and agreement options can choose an adjacent-category
tolerance. A reliability cohort accepts `id`, `parameters`, `target` and optional
`weights`. All three sections use every original retained draw, regardless of
`ndraws` or `draw_indices` used for the report's other prediction summaries.

New section names are `category_report`, `posterior_reliability` and
`rater_agreement`. The historical ordinary-MFRM `category_functioning` section
keeps its different predictive-replication interpretation and existing defaults.
The new flattened rows are intended for tables; `result` (or reliability
`results`) retains detailed quantities, MCSE, source identities and assumptions.
`source_result_hash` identifies the original standalone API result before report
projection. It is not a hash of the projected `result`; the full report and its
public/bundle exports have their own integrity records.

`on_section_error=:capture` retains section failures and successful neighboring
sections. Failed reliability cohorts stay listed alongside successful cohorts.
`on_section_error=:throw` raises the underlying error. `require_complete=true`
rejects captured failures; it does not establish convergence, MCSE adequacy,
measurement validity or the availability of every optional quantity. Unknown
request keys, inconsistent IDs and ambiguous cohort names fail before reporting.
Sampling, numerical, category-review and no-overlap warnings remain visible in
Markdown and table/JSON exports. No new model fitting is performed.

## Finite-cohort posterior reliability

```@docs
BayesianMGMFRM.posterior_reliability
```

## Common-response score agreement

```@docs
BayesianMGMFRM.rater_agreement
```

## Observed-score Krippendorff alpha

```@docs
BayesianMGMFRM.krippendorff_alpha
```

This operation takes `FacetData` and needs no fit. In an existing fit report,
request `reporting=(dataset_id="study", observation_ids=rating_ids,
alpha=(item="fluency", level=:ordinal, response_ids=response_ids))`.
The optional `krippendorff_alpha` section preserves observed disagreement,
expected disagreement, category margins and excluded singleton IDs through
public JSON/Markdown/table bundles. Omission leaves existing report fields
unchanged. Its descriptive status does not certify the fitted model.

## Owner-aware category functioning

```@docs
BayesianMGMFRM.category_report
```

## Conditional ability precision and classification

```@docs
BayesianMGMFRM.posterior_classification
```

To include this result in the same public report and bundle, add
`classification=(;parameters=person_names_A, cutoff=study_cutoff,
pass_probability=study_probability_rule, interval=0.99)` to `reporting`.
It needs no observation IDs of its own. `posterior_classification.rows` contains
individual results and `posterior_classification.cohort_rows` contains the four
cohort summaries; both are exported as tables. This option also works in each
model's `reporting_by_model` entry in `saved_prediction_workflow`.
The required rules must be justified on each model's fitted ability scale;
sharing their numeric values across models does not establish scale equivalence.

Invalid coordinates/rules follow the same section-error and `require_complete`
policies as other reports. Captured errors remain errors on public export and
reload. Read the [decision interpretation](interpreting-results.md#Posterior-classification-and-conditional-ability-precision)
before presenting a probability as evidence for a pass/fail decision.


## Finite-cohort posterior ranking

```@docs
BayesianMGMFRM.posterior_ranking
```

Add `ranking=(;parameters=person_names_A, direction=:higher, top_k=3,
interval=0.99)` to `reporting` for a cohort with at least three people.
`posterior_ranking.rows` exports each person's rank summary and top-k probability
bounds, with cohort size, direction, interval and tie policy included in the
table. Full MCSE/status details, diagnostics and source identity remain in
`posterior_ranking.result`. The same request works in the per-model
`reporting_by_model` entries of `saved_prediction_workflow`.

Omitting `ranking` or supplying `nothing` preserves the preceding report shape.
An invalid cohort or exceeded `max_rank_cells` follows the existing captured-error
and `require_complete` policy. A complete report still may contain unavailable
MCSE. The [ranking interpretation guide](interpreting-results.md#Posterior-ranks-within-an-explicit-cohort)
explains pointwise intervals, cohort dependence, ties and what ranks omit.

## Observed-score intraclass correlation

```julia
icc = BayesianMGMFRM.intraclass_correlation(data;
    item="fluency", model=:two_way_random, definition=:agreement,
    unit=:single, score_scale=:interval,
    dataset_id="assessment-2026", observation_ids=rating_ids,
    response_ids=performance_ids)
icc.icc
icc.status
icc.anova_rows
icc.unit_rows
```

Here N is the number of response units, K the number of raters, and
`MS_response`, `MS_rater` and `MS_error` are the two-way ANOVA mean squares.
The numerator in all four point formulas is `MS_response - MS_error`:

| Definition and unit | Denominator |
| --- | --- |
| Agreement, single | `MS_response + (K-1)*MS_error + K*(MS_rater-MS_error)/N` |
| Agreement, average | `MS_response + (MS_rater-MS_error)/N` |
| Consistency, single | `MS_response + (K-1)*MS_error` |
| Consistency, average | `MS_response` |

The residual combines response-by-rater interaction and measurement error;
with one rating per cell these components cannot be separated. Negative component
differences are not set to zero. A negative ICC with a positive denominator is
retained; a zero or negative denominator returns missing ICC with a distinct
status, retaining any finite `raw_ratio` for inspection. That raw ratio is not an
admissible reliability result. Constant scores everywhere therefore do not
produce an informative coefficient. Near-zero denominators can make ratios
unstable; inspect the ANOVA table rather than interpreting a cutoff mechanically.

```@docs
BayesianMGMFRM.intraclass_correlation
```
