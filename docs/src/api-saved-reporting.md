# Save, reopen and report an analysis

Use the same `save_fit` / `load_fit` and `save_report` / `load_report` names
for the supported model workflows. Native fits retain draws for further analysis;
portable reports retain computed values and warnings. Reopening either does not
fit the model again. Keep the exact source, Julia and dependency environment for
native files; the portable report is the sharing format.

## One saving and reopening workflow

```julia
using BayesianMGMFRM

save_fit("analysis.jls", result)
restored = load_fit("analysis.jls")
receipt = save_report("summary.json", restored; return_receipt=true)
report = load_report(receipt.path; expected_sha256=receipt.sha256)
```

`result` is an already fitted common model, Star model, or supported experimental
sample record. Save the receipt separately when exporting: reading a changed file
and calculating its current digest does not verify the original export.
`return_receipt=true` gives the same `path` and `sha256` fields for every report
writer. Without it, the existing writer's return value is preserved.

| Result | Native reopening | Computed report |
| --- | --- | --- |
| Eight common MFRM/GMFRM/MGMFRM result types | `load_fit(path)`; existing cache validation and controls | `save_report(path, result)` uses `fit_report`; `view=:public` is available |
| Star, JointRatings, OrdinalAssociation, correlated 3D and criterion-collapse results | `load_fit(path)`; model-specific target/hash/source checks | `save_report(path, result)` uses `posterior_summary`; retains the model's report structure |
| Rater-group result | `load_fit(path)` | `save_report(path, result; reference_group=group, practical_threshold=epsilon)` |
| Rater-by-item result | `load_fit(path)` | `save_report(path, result; practical_threshold=epsilon)`; choose the substantive tolerance explicitly |
| RaterDrift / ThreeIndicator native directory | `load_fit(directory)` selects the reader from `plan.jls` | Compute the saved report with the model's `summarize`, then use `save_report` / `load_report` |
| RaterDrift / ThreeIndicator saved report | Contains computed values, not native draws | `posterior_summary(saved)` exposes the existing report, with its warnings |

The common names do not make report shapes or statistical quantities identical.
Keep the relevant [interpretation guide](interpreting-results.md),
[JointRatings guide](joint-ratings.md), [Star guide](star-association.md), or
model guide alongside the result. In particular, `reference_group` and `practical_threshold` are
scientific choices, not automatic defaults. A portable report cannot be used to
change an interval, prior, reference, or conditioning set that requires draws.

You may also pass a previously computed report to `save_report`. This retains
its calculation without recomputing a summary. For sample records, summary
keywords follow `posterior_summary`; unsupported writer/reader/summary controls
raise errors rather than being ignored. Common report readers still support
`require_complete`, `verify_hash`, and `return_record`. The external file receipt
check is independent of an embedded content hash.

Criterion-collapse, RaterDrift and ThreeIndicator reports require
`expected_sha256`; other supported reports accept it optionally. Their existing
content and producer checks remain in force. Unknown report schemas are refused.
A hash detects changed bytes; it does not establish statistical validity.
For partial RaterDrift/ThreeIndicator directories, `require_complete=false`
inspects completed chains without resuming or summarizing an incomplete fit.

The detailed recipes below summarize the eight common saved-fit types unless
another model is named. The separate observed-score alpha and ICC operations
consume ratings and also accept `FacetData` without a fit. Finite-cohort
reliability, matched-response score agreement, category use, classification
risk and ranks answer different questions. The standalone functions can also
be requested through `fit_report(...; reporting=(...))`. Experimental sample
records remain distinct from `load_fit_cache` / `fit_report`; use the unified
entry points above to select their appropriate implementations.

## [Read a saved three-outcome analysis](@id three-outcome-saved-reports)

Use `Experimental.ThreeIndicator` when you already have a supported computed
report for accentedness, comprehension difficulty and transcription error.
This interface reads results from the no-state observation model. Fitting,
new posterior contrasts and changing the prior, panel or interval level are
not available through this interface. It is separate from `load_fit_cache` and
`fit_report`; the report contains computed summaries, not posterior draws.

```julia
using BayesianMGMFRM
saved = load_report("three-outcome-report.json";
    expected_sha256 = report_sha256,
    comparison_path = "engine-comparison.json",
    comparison_sha256 = comparison_sha256)
answer = posterior_summary(saved)
answer.rows                  # means, intervals, MCSE and numerical flags
answer.focal_definitions     # exact panel, weights, pairs, L1 and position
answer.listener_support      # recorded position ranges, or :not_recorded
answer.prior                 # name and numerical prior settings
answer.prior_provenance      # :recorded or :producer_reference
answer.metadata              # outcome order, directions, scoring and units
answer.warnings              # whole-report, warmup and comparison warnings
answer.comparison.flags

receipt = save_report("shared-analysis.json", saved; return_receipt=true)
reopened = load_report(receipt.path; expected_sha256 = receipt.sha256)
```

Set `report_sha256` and `comparison_sha256` from the separately retained export
receipts. A checksum detects changes after export; computing a new checksum of
an unexpectedly changed file does not verify it against the original. The reader
checks the supported producer/format, context, row meanings and consistency of
saved numerical flags. It does not authenticate a producer or recompute an
analysis. A checksum failure calls for the original file and receipt, not a refit.

Original Julia/Stan exports and the Julia producer with mandatory input
validation are supported. Model and producer versions are checked together;
an unknown combination is refused. Preserve an unsupported export and its
receipt instead of editing its provenance to force loading. This compatibility
does not provide fitting or native-chain import.

The two comparison keywords are optional but must be supplied together. Without
them, `answer.comparison.status` is `:not_supplied` and a warning remains.
A supplied comparison must match the selected report's identity and values.
Its descriptive flags remain visible even when the individual fit passes its
numerical criteria. No new engine comparison or equivalence decision is made.
The saved copy retains both original files verbatim and refuses an existing
output path. Keep the returned checksum separately for the recipient.

When the producer records listener position support,
`answer.prior` identifies `:reference`, `:steps` or `:combined` and its numerical
settings. New reports record these explicitly. Older recognized producers
implemented only the original reference prior; their reports return
`prior_provenance=:producer_reference` with a warning. This does not alter the
source bytes or turn historical results into fits under another prior.
See [the fitting guide](@ref three-outcome-fitting) for the assumptions.

`answer.listener_support.rows` gives both sides of every listener contrast:
the requested position, listener/L1 observation count, observed bounds and
`:within_observed_range`, `:outside_observed_range` or `:unobserved_context`.
Extrapolated contrasts and absent contexts retain explicit warnings. These
are marginal position checks; they do not establish joint covariate overlap,
model identification or causal comparability, and do not alter numerical
qualification. An interval outside observed support remains conditional on
the assumed linear trend there.

Historical summaries without this information return
`answer.listener_support.status == :not_recorded` and a warning. The stored
pair definition alone cannot recover observed input ranges. Sharing and
reloading a report preserves recorded context and leaves unavailable context
unavailable; it does not recalculate the original estimates.

Read the table using the following definitions:

| Rows | Meaning and interpretation |
| --- | --- |
| `panel_probability[d,k]` | The weighted conditional probability for category `k` of outcome `d` on the stored existing-event panel. These are not new-listener predictions. |
| `panel_expected_rating[d]`, d=1,2 | Expected category on the declared 1–9 coding. Higher values are adverse. The two scales do not measure one common construct merely because both use 1–9. |
| `panel_correct_probability` | Probability of binary category 1, **correct**. Binary category 2 means incorrect. |
| `speaker/...`, `listener/...` | Left-minus-right adverse-location differences. Different-cell/cohort effects are included where specified. Listener contrasts depend on the stored stimulus L1 and transformed position; these are not context-free severity differences, score differences or common log odds ratios. |
| `correlation/...` | Marginal correlations in the named hierarchy before centering. These are not observed-score or partial correlations. |

Intervals are the stored pointwise 95% equal-tailed intervals. `mean_mcse`,
`lower_mcse` and `upper_mcse` retain the numerical uncertainty of those summaries.
Read whole-report warnings alongside a selected row. An interval including zero
is not an equivalence result, and precise computation does not guarantee a
narrow interval, identification, calibration or substantive validity. Changing
weights or taking differences between interval endpoints cannot supply a new
posterior contrast. Keep the full original report in `answer.source` when
sharing diagnostics and provenance.

The shipped `examples/saved_three_indicator_report.jl` provides the same steps
as `saved_three_indicator_report(path; expected_sha256, comparison_path,
comparison_sha256, output_path)`. Including it performs no analysis; it uses
only the installed package. See the [API reference](api-experimental.md#Three-outcome-saved-results).

## [Reopen an analysis or share its results](@id saved-result-reproduction)

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

Keeping the Julia version alone is not sufficient. A fresh project can resolve
newer dependency versions even when BayesianMGMFRM itself is pinned. Recomputed
diagnostics may then differ at floating-point precision and fail the native
cache's exact diagnostic checks. Preserve and restore the complete original
`Project.toml` and `Manifest.toml`; do not bypass integrity checks or refit merely
to read saved results. Export a portable report in the original environment when
the recipient only needs the computed results.

### What the development version has actually verified

This manual describes an unpublished local source that follows development
commit `88bd6b422bb8afeb43a4a936376efad9ea2070c8`. Both that public preview and
later local sources use version `0.1.2`; the version string alone does not
identify the code. Keep the exact source archive or revision, as explained in
[Versions and Saved Results](registration.md).

The table separates checks on earlier source snapshots from saved-result checks
on the source used by this manual. Actual fitting, installation and restoration
were checked in separate stages, with their original failures retained and
resolved separately. These results do not constitute a single successful run
of every model on the current source. The declared Julia minimum is 1.10.8;
neither that declaration nor an allowed dependency range verifies every
model/backend/environment combination.

| Environment or transfer | Verified scope | Limit that remains |
| --- | --- | --- |
| Julia 1.10.8, macOS on Apple Silicon: first MFRM analysis | An earlier local source completed the supplied 72-rating scalar PCM example: AdvancedHMC fitting, reporting and fresh-process native/JSON restoration with compiled modules enabled. | One model, explicit prior and retained dependency selection. It does not verify every MFRM threshold/backend choice, another platform or general calibration. |
| Julia 1.10.8, macOS on Apple Silicon: normalized D2 MGMFRM | Earlier local sources completed the supplied 1,000-rating example with an explicit normalized prior, four-chain AdvancedHMC fitting, reporting and fresh-process restoration. Compiled-mode fitting was checked separately after the original uncompiled run. The present reporting source also reopens, summarizes and re-saves this retained fit. | These are distinct execution stages. The same-seed compiled run is not an independent statistical replication. This does not verify other priors, model combinations or all current-source fitting routes. |
| Julia 1.12.5, macOS on Apple Silicon: eight common saved-fit types | The present reporting source loads the original fits, recomputes summaries, re-saves native caches and reopens native/JSON summaries in separate processes. Earlier published-source checks separately cover saved comparison and reporting. | The eight-type check was completed in stages under recorded launch options. Historical fits have only 16 retained draws each and retain numerical warnings; successful restoration does not make them adequate for inference. |
| Julia 1.10.8, macOS on Apple Silicon: installation and startup | Earlier local sources separately completed fresh dependency resolution/source loading/input inspection with precompilation disabled, then normal startup using the same dependency selection and an initially empty compilation cache. Later MFRM and D2 fitting used those retained dependencies. | The startup stage reused verified dependency sources. These are not one cold-install-to-fit run, a new installation of every later source or installation checks for optional plotting. |
| JointRatings, Julia 1.12.5/macOS, original dependencies | Separate saved-result operations use JointRatings' own result, report and restoration interfaces. | Its minimum-version fitting and broader-platform compatibility remain unverified. It is not a ninth common `load_fit_cache` result type. |
| Earlier Julia 1.10.8 postprocessing checks | Bounded classification/ranking, slope/profile arithmetic and synthetic-cache reconstruction were checked on earlier sources. | Artificial fixtures and saved postprocessing do not establish actual fitting for those model/prior routes. |
| JSON reports produced on 1.12.5, read on 1.10.8 | Eight earlier actual-fit bundles and separately checked slope/profile reports preserve their computed values and warnings. | No fitted object, posterior chain, new interval or new analysis is reconstructed. Older text remains older text. |
| Native cache from 1.12.5, read on 1.10.8 | The attempted downgrade was refused by native deserialization. | This reconstruction route is unsupported. Use the original Julia environment or an exported report. |
| Same Julia version, different dependencies or launch options | One native-cache refusal was resolved by restoring the original dependencies. In a separate check with unchanged source and input, `-O0` changed the last bits of R-hat, while `-O2` reproduced the saved values. | Preserve the original launch options as well as the manifest. This finding does not make `-O2` a universal repair; retain unresolved mismatches and integrity checks. |
| Windows, Linux or another machine | No complete current-source fitting/persistence acceptance is established here. | Unverified, not demonstrated broken. A CI configuration or a local Mac check is not execution evidence for another platform. |

These are engineering boundaries. The separate [scientific scope](scope.md)
still excludes general calibration, a recommended normalized-prior default and
unvalidated model-selection claims.

### Preserve enough information to reopen the fit

The report reader preserves integer tokens, including 64-bit input signatures,
without conversion through a floating-point value. Earlier readers could round
an integer outside the signed 64-bit range, or inside a mixed numeric array.
Read the unchanged original JSON with the corrected reader; a value already
rounded and re-exported cannot be recovered from that copy.

Newly saved fit reports use export envelope v2. Its JSON-payload checksum
preserves exact integer values, including large input signatures; changing an
integer by one is detected. A report bundle declares this version in its report
file entry. Both full and public reports use the new export envelope, while
their inner content hashes and native-cache formats remain unchanged.

The reader still accepts original v1 exports with their original checksum rules.
Those checksums normalize numbers through floating point and cannot distinguish
every large-integer change. The separate table and dossier formats also retain
their existing checksum rules. Re-saving an unchanged original report creates a
v2 export; it does not prove that an older file was unaltered. Retain the original
file and receipt. Readers that support only v1 reject new v2 exports: the recipient
needs a reader supporting v2, or the preserved original v1 file.

These content checksums are not hashes of the original file bytes and do not
authenticate the sender. Keep a separate SHA-256 receipt for each original file
when exact transfer identity is required. Do not bypass a failed integrity check
to make a report load.

1. Keep the native cache, original input data, analysis script, rating IDs and
   explicit model/prior/interval/reporting choices. A report is not a substitute
   for the data or analysis specification.
2. In the original session, record `VERSION`, `Sys.MACHINE`,
   `Base.active_project()` and `Pkg.status(; mode=Pkg.PKGMODE_MANIFEST)` after
   `using Pkg`. Keep the Julia launch command, including any optimization,
   bounds-checking or math-mode options. Copy that project's `Project.toml` and its `Manifest*.toml`
   files, including a version-specific manifest if present. Keep the exact
   BayesianMGMFRM commit. A manifest that points to a local checkout does not
   copy that checkout: archive its source and preserve or deliberately restore
   those path references. Do the same for locally developed dependencies.
3. Reopen with the original Julia executable and archived project. For example,
   `julia --startup-file=no --project="/path/to/archived-analysis" reopen.jl`.
   Confirm `VERSION`, `Base.active_project()` and `pkgdir(BayesianMGMFRM)` before
   loading the cache. Activating a project does not restore missing packages;
   if dependencies are unavailable, restore them from the recorded manifest
   without updating its resolved versions. A changed source or environment
   needs its own affected compatibility check.

The following can be saved as `reopen.jl` beside `analysis-fit.jls`. Run it in
that matching environment. It recomputes a report from retained draws without
fitting or generating replicated responses, and writes a **new** bundle:

```julia
using BayesianMGMFRM

fit_result = load_fit_cache(joinpath(@__DIR__, "analysis-fit.jls"))
# Omit legacy MFRM sections; category functioning simulates new ratings.
legacy_options = fit_result isa MFRMFit ?
    (; include_category_functioning=false, include_rater_homogeneity=false) : (;)
report = fit_report(fit_result; legacy_options..., view=:public,
    include_prior_predictive=false, include_posterior_predictive=false,
    include_artifact=false, include_waic=false, include_loo=false,
    posterior_lower=0.005, posterior_upper=0.995,
    on_section_error=:throw)
fit_report_health(report)
destination = joinpath(@__DIR__, "reopened-report")
save_fit_report_bundle(destination, report; require_complete=true)
restored = load_fit_report_bundle(destination; require_complete=true)
```

The posterior bounds request a central 99% interval. This minimal export does
not recreate the original report's optional sections or choices; add the
original `reporting` request when needed. Omitted predictive sections stay
unrequested. In ordinary MFRM, disabling only `include_posterior_predictive`
does **not** disable the separate legacy category-functioning section, which
simulates responses. The minimal example also omits legacy rater homogeneity;
that section need not simulate responses when using all retained draws. The newer optional `reporting.category` consumes retained draws without that
legacy replication. `require_complete=true` checks section completeness,
not convergence or precision. Inspect `diagnostics(fit_result).summary` for
`flag` and `passed`; a complete report can still have `sampler_warning` and
`passed=false`. Diagnostic rows and original sampler warnings remain in the export.

If a report already exists, reading it requires no recomputation:

```julia
report = load_fit_report("assessment-report/fit_report.json")  # One JSON export
report = load_fit_report_bundle("assessment-report")           # Whole bundle directory
```

### If reopening fails

| Observation | What to do |
| --- | --- |
| `Cannot read stream serialized with a newer version of Julia` | Start the original Julia version and archived project. Export JSON there if the recipient cannot use that environment. |
| Diagnostic/artifact mismatch after moving to a new environment | Restore the original source, full manifest and Julia launch options, then retry the read. Such a mismatch is not proof of file damage; recomputed values can depend on the execution environment. Preserve the original cache and full error if the matched environment still fails. |
| Hash mismatch in a JSON report or bundle | Compare with the original export and transfer all bundle files unchanged. Editing a table or renaming a cache does not migrate it. Do not disable integrity checks to claim a successful reproduction. |
| Destination already exists | Choose a new output directory; keep the original report. A regenerated report may reflect corrected descriptions, whereas reading old JSON preserves them. |
| Report export failed after the native fit was saved | Keep `fit.jls` and the error. Fix the export setting or destination and rebuild the report from that cache in the original environment; do not repeat fitting just to recreate a report. |
| An export directory has JSON/tables but no valid bundle manifest | Preserve the partial directory for diagnosis and export to a new destination. A partial export is not a completed bundle. Do not bypass hash checks or construct a manifest by hand. |
| A report loads but says `sampler_warning` or `insufficient_draws` | Reading succeeded; statistical adequacy did not improve. Preserve that warning when sharing the result. |

If the failed export left a valid individual `fit_report.json`, restore the
already computed report without reopening the fit or recalculating statistics:

```julia
report = load_fit_report("partial-report/fit_report.json")  # verifies this JSON export
save_fit_report_bundle("recovered-report", report; require_complete=true)
restored = load_fit_report_bundle("recovered-report"; require_complete=true)
```

Use a new destination and keep integrity checks enabled. If the JSON itself is
incomplete or fails validation, return to the saved fit in its original
environment. This route restores computed output, not posterior draws, new
intervals or figures requiring a fitted object.

When asking a maintainer for help, provide the exact source commit, Julia/OS
and manifest identity, the operation and file format, the complete error and
whether the original environment can read the file. A portable report is useful
when the task is to inspect already computed results; it cannot recover missing
draws or an unavailable original environment.
See [reporting a problem](contributing.md#report-a-problem) for the support
channel and a short version-information command.

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

legacy_options = fit_result isa MFRMFit ?
    (; include_category_functioning=false, include_rater_homogeneity=false) : (;)
report = fit_report(fit_result; reporting, legacy_options..., view=:public,
    include_prior_predictive=false, include_posterior_predictive=false, include_artifact=false,
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

## Scalar expected scores and information

The [score and information guide](score-information.md) connects a declared
item/rater design, conditional curves, joint uncertainty and saved report tables.
The opt-in `reporting.score_information` section uses all retained draws of an
ordinary scalar MFRM. Other fitted-result types are outside its initial scope.

```@docs
BayesianMGMFRM.score_information_report
```
