```@raw html
<a id="保存済みモデルの予測比較・回復評価：隔離したAPI候補"></a>
<a id="保存済みモデルの予測比較・回復評価：隔離したAPI候補-1"></a>
```

# Saved Prediction, Model Comparison and Recovery

!!! note "Unreleased documentation preview — 13 October 2026"
    This manual includes unreleased interfaces and examples. It is not the
    documentation of an installed release. Model support and scientific
    acceptance remain as stated on each page.

Use this workflow to compare predictions for the same ratings and evaluate
named parameters against generating truths. The common operations cover eight
fit types: scalar MFRM and GMFRM, raw and normalized MGMFRM, correlated MGMFRM,
fixed-coefficient multidimensional MFRM, correlated MFRM and exchangeable-rater
MFRM. Their model, prior and fitting restrictions remain different; see the
[scope and operation table](scope.md#common-operation-support).

Run the examples with the candidate project loaded through `julia --project=.`.
Saved-result evaluation does not fit a posterior. K-fold scoring additionally
requires a fit trained separately on each fold's training data. The
[API reference](api-prediction-recovery.md) documents arguments and return values.

| Your question | Route | What the output establishes |
| --- | --- | --- |
| How do models predict the same observed ratings? | `compare_predictions` | Descriptive WAIC or raw IS-LOO comparison from fitted training data. |
| How do models predict ratings excluded from fitting? | `prediction_refit_plan` → `prediction_fold_observations` → `prediction_kfold` → `compare_kfold_predictions` | K-fold comparison of saved training fits, conditional on existing facet levels. |
| How close are estimates to generating truths? | `recovery_quantities` → `recovery_evaluation` | Named-quantity evaluation and MCMC MCSE for one dataset. |
| What happens across independent datasets with the same design and truths? | `recovery_replications` | Quantity-specific summaries retaining every planned replication; replication SE requires evidence of dataset independence. |

These functions do not select a model automatically, establish construct validity
or recommend a sufficient number of persons or raters. Separate changes to
fixed/estimated coefficients, dimensions/Q, covariance and priors before
interpreting a comparison. The output retains these model contracts; it does
not align ability components across models with different dimensions.

```@raw html
<a id="保存から比較まで"></a>
<a id="保存から比較まで-1"></a>
```

## Compare saved fits

Start with results saved by `save_fit_cache(path, fit)`. Replace the example IDs
with persistent rating IDs from your study. Each rating needs its own ID,
including multiple ratings by one rater or of the same response. Matching row
numbers alone does not establish matching data.

```julia
using BayesianMGMFRM
include("examples/saved_model_comparison.jl") # Run from the candidate project root.

result = saved_model_comparison(
    "MFRM" => "mfrm.jls",
    "GMFRM" => "gmfrm.jls",
    "MGMFRM D2" => "mgmfrm-d2.jls";
    dataset_id="rating-study-v1",
    observation_ids=rating_ids,
    comparison_axis=:dimensions,
    criterion=:waic,
    baseline="MFRM",
    se_unit=:none,
)

[(; row.model, row.elpd_difference, row.se_elpd_difference,
    row.sampling_warning, row.criterion_warning,
    row.problem_observation_ids) for row in result.rows]
```

For fits already in memory, call
`BayesianMGMFRM.compare_predictions("MFRM"=>fit1, "GMFRM"=>fit2; ...)`.
For previously extracted `BayesianMGMFRM.prediction_observations(...)` bundles,
omit the ID arguments: the bundles already retain them. Supply only fits or
only prediction bundles, never a mixture.

When row orders differ, pass
`observation_ids=Dict("MFRM"=>ids1, "GMFRM"=>ids2, ...)`, with each vector in its
fit's original row order. Scores, person/item/rater labels, additional facets,
category definitions and the complete training-data binding are checked before
alignment to the baseline model. Inputs are unchanged. Draws from different
fits need not be paired; each fit uses all original chains and retained draws.
Subsampled, reordered or resampled draw collections are rejected.

```@raw html
<a id="比較軸・評価指標・不確実性"></a>
<a id="比較軸・評価指標・不確実性-1"></a>
```

## Comparison axes, scores and uncertainty

| Argument | Meaning |
| --- | --- |
| `comparison_axis=:model` | Require the same dimensions and Q. Inspect metadata for differences in family and other assumptions. |
| `:dimensions` | Allow dimensions and Q to differ while comparing predictions of identical observations. |
| `:q_matrix` | Allow Q to differ at the same dimension count. |
| `criterion=:waic` | Compute the existing WAIC from original pointwise log likelihoods. |
| `:raw_loo` | Unsmoothed importance-sampling LOO; inspect weight instability. |
| `:hill_smoothed_loo` | The existing Hill smoother; not independently reference-validated PSIS. |
| `se_unit=:none` | Default: difference SE is `missing`; no inferential unit is silently selected. |
| `:observation` | Approximate SE treating ratings as exchangeable units. |
| `:person` | Sum ELPD differences within each person, then compute an approximate SE treating persons as exchangeable units. |

For rating differences `d_i`, the observation-level SE is `sqrt(N * var(d))`.
The person-level version uses person totals `D_g` and `sqrt(G * var(D))`.
One unit returns `missing`. This is one-way aggregation, not a general correction
for crossed item/rater dependence. Selecting a unit does not establish its
exchangeability. Neither estimate is MCMC MCSE or the replication SE of a
design simulation.

`elpd_difference` is model minus baseline, so positive values favor that model
on the selected score. Rows retain input order; no winner, automatic adoption
or posterior model probability is returned. Do not decide from point-estimate
rankings while uncertainty or warnings remain unresolved.

An axis label does not isolate the effect of changing that axis. For example,
the scalar GMFRM has rater-owned steps, whereas fixed-Q MGMFRM has item-owned
steps; slope and scale conventions also differ. Their predictive comparison
can address the complete alternatives, but cannot attribute a difference solely
to dimensionality. Review [threshold ownership](model-equations.md#Generalized-Partial-Credit-and-Multidimensional-Structure)
and the saved `model_contract`.

This route approximates omission of one rating with the specification and level
sets fixed. It is conditional on existing levels, not leave-person/rater/item-out
cross-validation, integration over new levels or refitted K-fold evaluation.
Match the prediction and omission units to the question; see the
[loo FAQ](https://mc-stan.org/loo/articles/online-only/faq.html).

```@raw html
<a id="診断と互換性"></a>
<a id="診断と互換性-1"></a>
```

## Diagnostics and compatibility

Each row retains sampling warnings, criterion warnings, problem rating IDs,
retained-draw counts, model information and saved-sample hashes where supported.
Warned models are not dropped from the comparison roster. Even
`status=:descriptive` does not establish scientific acceptance. Comparison MCMC
MCSE, relative-efficiency correction and crossed-cluster adjustment are not
computed. Predictive fit does not establish construct validity or interval coverage.

Schemas are `bayesianmgmfrm.prediction_comparison.v1`,
`bayesianmgmfrm.prediction_observations.v1` and
`bayesianmgmfrm.prediction_criteria.v1`. Re-extract earlier `.prototype.v1`
bundles from their saved fits with the candidate API. Existing `compare_models`,
`sensitivity_comparison`, fit-cache formats and root exports retain their
interfaces. Call candidate operations with the `BayesianMGMFRM.` prefix; their
final acceptance remains open.

The available checks cover analytic scores, synthetic draws, persistence,
invalid-input rejection and compatibility. They do not establish model-selection
accuracy, empirical recommendations, study-design guarantees or release completion.

```@raw html
<a id="MGMFRMと固定係数の多次元MFRMのレポート"></a>
<a id="MGMFRMと固定係数の多次元MFRMのレポート-1"></a>
```

## Reports for MGMFRM and fixed-coefficient multidimensional MFRM

The following saved-fit types accept the same WAIC and raw IS-LOO arguments in
`fit_report` and `save_fit_report_bundle`. Existing diagnostics, prediction
summaries and persistence routes are retained.

| Result type | Model |
| --- | --- |
| `Experimental.NormalizedMGMFRMFit` | Normalized prior; identity population ability correlation. |
| `Experimental.CorrelatedMGMFRMFit` | Two-dimensional correlated MGMFRM. |
| `MultidimensionalMFRMFit` | Independent multidimensional MFRM with fixed Q coefficients and unit logits, using canonical records. |
| `Experimental.CorrelatedMFRMFit` | The correlated two-dimensional fixed-coefficient model. |
| `Experimental.ExchangeableMFRMFit` | Exchangeable rater prior with independent or admitted two-dimensional correlated abilities. |

Fixed versus estimated coefficients, D/Q, covariance and rater priors remain
separate model choices. Reports preserve their respective model, prior and
scale records. Legacy fixed-Q v1 records can be read for common comparison and
criteria, but public reports still reject them because their specification
semantics differ. Do not migrate them by changing a format label.

```julia
fit = load_fit_cache("mgmfrm.jls")
report = fit_report(fit;
    dataset_id="rating-study-v1", observation_ids=rating_ids,
    include_waic=true, include_loo=true,
    draw_indices=[1, 2, 2], # Used only for posterior-predictive display.
    require_complete=true,
)
save_fit_report_bundle("mgmfrm-report", report; require_complete=true)
restored = load_fit_report_bundle("mgmfrm-report"; require_complete=true)
```

For these five report types, `include_waic` and `include_loo` both default to
`false`, producing `:not_requested` sections. Historical `:unsupported` sections
remain readable. Requested criteria require a dataset ID and unique rating IDs;
supplying those criterion IDs without requesting a criterion is rejected. The
original three fit types retain their existing report keywords and defaults.

WAIC/LOO use all retained draws and chains independently of `draw_indices`.
Their `rows` contain total ELPD, approximate SE, draw counts and warnings;
`diagnostic_rows` contain pointwise ELPD, diagnostics and rating IDs.
`problem_observation_ids` and `problem_rows` identify criterion warnings, so a
problem near the end of the full observation table remains visible in a preview.
Markdown truncates previews to the requested row count; JSON and tables retain
all rows. LOO settings are `loo_threshold=0.7`, `loo_tail_fraction=0.2` and
`loo_min_tail_draws=5`. Report LOO is unsmoothed. Changing a warning threshold
does not improve precision or establish scientific acceptance.

Use `posterior_mcse(fit)` for parameter-summary MCMC error. Normalized/correlated
MGMFRM reports also contain `direct_posterior.mcse_rows`; that table was not added
to fixed-coefficient MFRM reports. Criterion `se_elpd` is an approximate SE across
observations, without MCMC or crossed-cluster correction. These interpretations
and warnings survive public display, Markdown, JSON, tables and reload.

WAIC and LOO are separate sections: an error in one does not erase the other.
`on_section_error=:capture` retains an incomplete report; `require_complete=true`
rejects that state. `:computed` and `report_status=:complete` describe report
execution, not successful inference.

`examples/saved_mgmfrm_report.jl` generates these five report types without
refitting. `examples/normalized_mgmfrm.jl` starts from synthetic data and saves
rating IDs; its short MCMC is inadequate for inference. Existing numerical and
figure checks remain evidence for their recorded scope. The common APIs below
prepare refits and score/aggregate saved folds. Automatic multi-model refitting,
new-level prediction, reference PSIS and model-selection validation remain open.

```@raw html
<a id="K-foldの学習データを固定し、保存結果で保留データを採点する"></a>
<a id="K-foldの学習データを固定し、保存結果で保留データを採点する-1"></a>
```

## Prepare K-fold training data and score held-out ratings

For prediction of unused ratings of known persons, raters and items, score each
fold with posterior draws fitted only to its training data. This differs from
training-data WAIC/LOO. New-person or new-rater generalization requires a separate
prediction target and integration. Decide in advance whether all ratings of a
response must be held out together.

```julia
using BayesianMGMFRM, Serialization

# Prespecify data/spec, prior, persistent rating_ids and the splitting rule.
plan = kfold_plan(spec.data; k=5, group_by=:response_id)
prepared = BayesianMGMFRM.prediction_refit_plan(spec, plan;
    prior=MFRMPrior(), dataset_id="rating-study-v1", observation_ids=rating_ids)
request = prepared.folds[1]
serialize("fold-1-request.jls", request)

# Scalar MFRM example; use the sampler settings from the analysis plan.
training_fit = fit(request.model; prior=request.prior,
    chains=4, warmup=1000, ndraws=1000)
save_fit_cache("fold-1-fit.jls", training_fit)

# Resume with the same request and its matching saved training fit.
include("examples/saved_fold_predictions.jl")
scored = saved_fold_predictions("fold-1-fit.jls", deserialize("fold-1-request.jls"))
scored.pointwise_loglikelihood   # draw × heldout rating
scored.observation_ids          # Persistent IDs in this column order.
scored.sampling_quality         # Retains diagnostic warnings.
```

Preparation/scoring themselves perform no fitting and need no full-data posterior.
For GMFRM, MGMFRM, normalized MGMFRM, fixed-Q multidimensional MFRM and their
admitted correlated/exchangeable-prior routes, explicitly supply the corresponding
experimental model and prior, then use
`Experimental.fit(request.model; prior=request.prior, ...)`.
Existing dimension, Q, prior and backend restrictions apply. The example's
iteration counts do not guarantee precision.

Preparation checks every fold and existing-level condition. Training data are
the exact complement of held-out data, and every rating is held out once.
`FacetData(table)` normally sorts levels; explicitly encoded inputs can use a
different order. Training preserves the original level order so reconstruction
of the last level does not move its induced prior to another label. Item/Q
alignment, dimension names, prior scales and covariance are preserved.
Grouping on metadata does not add a fitted effect.

Scoring detects altered requests and checks the actual training data, model,
prior and correlation configuration. Full-data fits, different priors/LKJ
settings and damaged samples are rejected. Already correlated draws are not
transformed again. Legacy fixed-MFRM v1 records are not automatically migrated.

All retained draws/chains are used, including diagnostic warnings.
`include_probabilities=false` avoids allocating category-probability arrays.
Returned likelihoods exclude priors and Jacobians. `source_binding` joins source
data to persistent IDs; `split_binding` binds the split. They agree across
models/dimensions using the same data and split, while training-target identities
also include the model/prior. These checks detect mismatches; they do not certify
convergence or execution history. Held-out results are rejected by the
training-data WAIC/LOO entry `prediction_criteria`.

There is no automatic all-model/all-fold refit runner. Aggregation below checks
source, split and prediction target rather than matching only row counts or
positions. It cannot detect whether held-out outcomes informed later model or
prior tuning. Fitting and figure rendering are separate operations.

## Matched dimensionality comparison

To ask whether the same ratings benefit from multiple ability dimensions,
compare the one-dimensional MGMFRM restriction with a between-item MGMFRM.
Both use item-owned steps, the 1.7 response multiplier, positive loadings and
rater consistency. The ordinary scalar GMFRM uses a different equation; see
[the distinction and prior limits](model-equations.md#One-versus-multiple-dimensions-under-the-same-kernel).

The following prepares two models without running a sampler. Use your ingested
`data`, persistent `rating_ids`, Q rows in `data.item_levels` order, and dimension
names. Choose prior scales before inspecting held-out outcomes; the values
below illustrate the arguments and are not calibrated defaults.

```julia
using BayesianMGMFRM
const E = BayesianMGMFRM.Experimental
include("examples/matched_dimension_refit_plans.jl")

prior = E.NormalizedMGMFRMPrior(prior_model=:exchangeable,
    person_sd=1.0, rater_sd=0.5, item_sd=1.0,
    log_discrimination_sd=0.3, log_consistency_sd=0.3, step_sd=0.7)
split = kfold_plan(data; k=5, group_by=:response_id)
plans = matched_dimension_refit_plans(data, split;
    q_matrix=study_q, dimension_labels=study_dimension_names,
    prior, dataset_id="rating-study-v1", observation_ids=rating_ids)
```

The comparison Q must have at least two columns and exactly one active entry
per item. Both plans use the identical split and prior settings. The shared
validator still checks level coverage and Q support. Grouping by response ID
holds its ratings together; it does not add response dependence to the fitted
model. This is prediction for existing persons, items and raters, not new-level
prediction. A design that cannot retain every facet level in training is rejected.

Each entry is a label paired with a prepared plan. Fit each plan's training
requests using your chosen backend and justified numerical controls:

```julia
label, prepared = first(plans)
request = first(prepared.folds)
fit = E.fit(request.model; prior=request.prior, backend=:advancedhmc,
    chains=4, warmup=1000, ndraws=1000, seed=20261012)
save_fit_cache("one-dimension-fold-1.jls", fit)
score = BayesianMGMFRM.prediction_fold_observations(fit, request;
    include_probabilities=false)
score.sampling_quality
```

Repeat for every request of both plans, keeping every fit, diagnostic warning
and execution failure. The counts above are an example, not a precision
assurance. Aggregate all folds with `prediction_kfold`, then call
`compare_kfold_predictions("One dimension"=>one, "Multiple dimensions"=>many;
comparison_axis=:dimensions)` as described below. The complete-cache helper
`saved_kfold_comparison` can also use these prepared plans.

This comparison keeps one loading per item and the same marginal prior rules,
but changes person-level dependence through dimension sharing. Equal scale
arguments do not equalize joint prior predictive distributions. Data-sampling K-fold SE remains unavailable; optional numerical MCSE is
described below. A returned score difference alone does not
establish dimensionality, construct validity or a reproducible advantage.

```@raw html
<a id="保存した全foldの集約とモデル比較"></a>
<a id="保存した全foldの集約とモデル比較-1"></a>
```

## Aggregate all saved folds and compare models

Prepare each model with the same source data, persistent IDs and split. Save
`prepared` with `Serialization.serialize` and reuse it when resuming. Once
training fits are saved, the example scores held-out ratings and compares models:

```julia
include("examples/saved_kfold_comparison.jl")

result = saved_kfold_comparison(
    "MFRM" => (; prepared=mfrm_prepared,
        caches=Dict(1=>"mfrm-fold-1.jls", 2=>"mfrm-fold-2.jls")),
    "MGMFRM D2" => (; prepared=mgmfrm_prepared,
        caches=Dict(1=>"mgmfrm-fold-1.jls", 2=>"mgmfrm-fold-2.jls"));
    comparison_axis=:dimensions, baseline="MFRM",
)
[(; row.model, row.elpd, row.elpd_difference, row.complete,
    row.status, row.sampling_warning, row.se_elpd_difference) for row in result.rows]
result.rows[1].folds # Per-fold status, diagnostics, failures and saved-sample identity.
```

This example uses two folds; supply the cache mapping for every fold in your
actual plan. Declare `:model`, `:dimensions` or `:q_matrix` as above. Inspect
`model_contract` for covariance, coefficients, dimensions and priors instead of
inferring differences from model names. Rows retain input order, differences
are model minus baseline, and no automatic ranks, selected model or weights are
returned.

For previously scored results, use
`BayesianMGMFRM.prediction_kfold(prepared, scores; failures=...)`, then
`BayesianMGMFRM.compare_kfold_predictions("MFRM"=>a, "GMFRM"=>b; comparison_axis=:model)`.
Scores may arrive in any fold order. Persistent IDs align differently ordered
ratings after checking scores, facet labels, categories and splits. All retained
chains and draws are used.

| State | Aggregation/comparison behavior |
| --- | --- |
| All folds present, no diagnostic warning | Return complete ELPD and baseline differences; scientific acceptance remains separate. |
| All folds present, diagnostic warnings | Retain those folds/models and descriptive values; the comparison is warning-bearing. |
| Result not received | Fold is `:missing`; total ELPD is `missing`, with available rating scores retained for inspection. |
| Declared execution failure | `failures=[fold_id=>"failure reason"]` records `:failed`, distinct from missing. |
| Any candidate model incomplete | Retain completed-model scores but set every model contrast to `missing`. |
| Duplicate, mismatched split/target or altered saved content | Error; do not silently replace with missing. |

Each model in the saved example can include `failures=[2=>"storage failure"]`;
exclude that fold from `caches`. Diagnostic warnings are not discarded as
execution failures, and successful-fold sums are not treated as complete ELPD.
`diagnostics_ok` reflects recorded flags, not a convergence/performance guarantee.

Rating i is scored by `log(mean(exp(loglikelihood[s,i])))` over its training
posterior draws s, not by mean log likelihood. Holding out groups still returns
a sum of rating-wise marginal predictive scores, not the joint predictive density
obtained by multiplying within-group likelihoods before averaging over draws.

Data-sampling SE and repeated-dataset uncertainty are not computed.
Neither independent-fold SE nor simple rating-wise SE is silently substituted.
MCMC MCSE is opt-in, as described below.
Point differences alone do not establish a useful or reproducible advantage.
This route excludes new-person/rater/item marginal prediction and adjustment for
model tuning after inspecting held-out results.

### Numerical error of the K-fold comparison

Before spending more computation on a small score difference, ask whether its
MCMC error is small enough for your intended numerical comparison. This is a
question about approximating the fitted posterior, conditional on the observed
data and the chosen split. It is separate from how scores would change with
new data, a different split, or a different model/prior. The distinction between
MCSE and data-sampling SE is also explained in the
[loo glossary](https://mc-stan.org/loo/reference/loo-glossary.html).

Request `mcse=:delta` when aggregating the existing saved scores:

```julia
one = BayesianMGMFRM.prediction_kfold(one_plan, one_scores;
    mcse=:delta, independent_fold_rng=true)
many = BayesianMGMFRM.prediction_kfold(many_plan, many_scores;
    mcse=:delta, independent_fold_rng=true)
comparison = BayesianMGMFRM.compare_kfold_predictions(
    "One dimension"=>one, "Multiple dimensions"=>many;
    comparison_axis=:dimensions, independent_model_rng=true)

[(; row.model, row.elpd_difference,
    numerical_error=row.difference_mcmc_error,
    data_sampling_se=row.se_elpd_difference,
    row.sampling_warning) for row in comparison.rows]
one.folds[1].mcmc_error # Includes draw count and concentration information.
```

Use the `true` declarations only if fold fits and model fits actually used
independent MCMC random streams, respectively. Reusing the same random stream,
paired/common random numbers, or posterior draws does not satisfy this condition.
Different seeds alone are not a proof of independence. Independence here concerns
the simulations conditional on the data; training folds may still overlap.
Detectable sample-hash reuse is rejected, but the API cannot certify how the
random streams were generated. Without the declarations, the relevant combined
MCSE remains missing and available fold-level results are retained.

The existing `saved_kfold_comparison(...; mcse=:delta,
independent_fold_rng=true, independent_model_rng=true)` example forwards these
options when starting from fit-cache paths. Omitting the options preserves the
previous result structure and values. The result is serializable with Julia's
`Serialization`; keep the source-bound prepared plans and score records together.

For a fold with draws s and held-out ratings i, define

```math
\widehat\ell_i=\log\left(S^{-1}\sum_s p_{si}\right),\qquad
u_s=\sum_i\left(\frac{p_{si}}{S^{-1}\sum_t p_{ti}}-1\right).
```

The implementation evaluates the ratio using log probabilities and `expm1`, so
very small category probabilities need not be exponentiated on their original
scale. Applying the existing autocorrelation-aware mean MCSE to the joint
influence sequence u gives a **first-order delta approximation** to the numerical
error of the fold's sum of log predictive probabilities. Summing influences
within each draw retains covariance between ratings. Adding separate rating-wise
variances would generally give a different answer. The mean-MCSE calculation
uses the installed [MCMCDiagnosticTools implementation](https://julia.arviz.org/MCMCDiagnosticTools/),
with the package's existing split-chain convention. This is not PSIS or an
importance-weight calculation.

Independent fold errors combine as the square root of the sum of their squared
MCSEs. Independent model errors combine in the same way for a difference. This
sums **MCMC variances**, not variances of fold scores across overlapping datasets.
Naive fold-independence estimates of data-sampling uncertainty can be misleading;
see [Bengio and Grandvalet (2004)](https://www.jmlr.org/papers/v5/grandvalet04a.html).

| Field or state | Interpretation |
| --- | --- |
| `mcmc_error.value` | Estimated computational standard error of total ELPD, in natural-log units. |
| `mcmc_error.per_rating` | The same error divided by the number of scored ratings; not a rating-wise independence SE. |
| `difference_mcmc_error` | Error of the reported model-minus-baseline difference, subject to the separate simulation-independence declaration. |
| `:first_order_approximation` | The estimate is available, but convergence, adequate mixing and the local linear approximation still need review. |
| Fewer than two chains or ten retained draws per chain | MCSE is missing; these minima are computational guards, not evidence that ten draws suffice. |
| `:first_order_degenerate` | The influence is constant or numerically cancels. Higher-order error can remain; zero MCSE is not reported. |
| `max_draw_probability_share` | Largest contribution of a single draw to any rating's estimated predictive mean. Concentration near one calls the approximation into question; no calibrated cutoff is imposed. |
| Missing/failed fold or unavailable required MCSE | Total/difference MCSE is missing. Scores, failures and diagnostics remain visible. |
| Baseline minus itself | Exactly zero computational error for this identity when the comparison is complete. It is not evidence of model adequacy. |

MCSE does not bound finite-MCMC bias, missed posterior modes, model
misspecification or uncertainty from collecting data. For example, if two rating
probabilities move in opposite directions, the first derivative of their summed
log means can cancel while second-order variability remains. Small MCSE alone
therefore does not justify selecting a dimension count, declaring equivalence,
or ignoring diagnostic warnings. No automatic extension of a fit, precision
threshold, confidence interval or model ranking is performed.

Preparation and scoring use the unreleased `v2` schemas, which retain the complete
fold roster and content hashes. Rebuild older candidate preparations/scores from
the same specification/split and rescore their matching saved fits; no new MCMC
is required. Fit-cache formats and fold-request `v1` remain unchanged. Hashes
detect accidental modification; they do not authenticate execution history or
prove absence of data leakage.

```@raw html
<a id="設計シミュレーションのための共通回復評価"></a>
<a id="設計シミュレーションのための共通回復評価-1"></a>
```

## Evaluate recovery for design simulations

`BayesianMGMFRM.recovery_quantities(fit)` and
`BayesianMGMFRM.recovery_evaluation(fit, truth; ...)` match named model quantities
to truths across the same eight fit types. They evaluate saved draws from one
dataset, without generating data, fitting, aggregating independent replications,
performing SBC or recommending sample sizes. Fixed-coefficient MFRM requires
canonical records; legacy v1 is rejected.

```julia
using BayesianMGMFRM, Serialization
include("examples/saved_recovery_evaluation.jl")

fit = load_fit_cache("simulation-fit.jls")
catalog = BayesianMGMFRM.recovery_quantities(fit)
[(; r.parameter, r.block, r.dimension_label, r.parameter_space, r.fixed)
    for r in catalog.rows]

# A model-coordinate name => truth dictionary saved during generation.
# Match generating and analysis targets in advance; do not use estimates as truth.
truth = deserialize("truth-model-coordinates.jls")
evaluation = saved_recovery_evaluation("simulation-fit.jls", truth;
    dataset_id="design-A-replication-001", observation_ids=rating_ids, interval=.95)
evaluation.rows
evaluation.sampling_quality
```

Specify any nonempty subset of quantities. Unknown names, nonfinite truths,
correlation truths outside [-1,1] and duplicate rating IDs are rejected. Rows
retain model order rather than dictionary order. The catalogue includes supported
reconstructed last severities/steps, correlations and structural constants.
`derived=missing` means the existing route lacks derivation metadata, not that
the quantity is an independent parameter.

Truths must match the listed scale, facet labels and identification constraints.
Fixed-coefficient MFRM retains unit logits; generalized models retain their own
scales. Correlations are evaluated as rho, not Fisher z, and correlated ability
draws are not transformed twice. Cross-dimensional alignment, cross-model
rescaling and truth centering are not automatic. Matching names alone does not
establish identical estimands: GMFRM has sum-zero item difficulties and free
severities, whereas MGMFRM has sum-zero severities. GMFRM item discrimination
and rater consistency are dimensionless, separate from location scales.

| Output | Meaning and limit |
| --- | --- |
| `posterior_mean`, `posterior_sd`, `posterior_lower/upper` | Summaries and the requested equal-tailed interval using all retained draws/chains. |
| `bias` | This posterior mean minus truth; not average bias across independent datasets. |
| `squared_error`, `interval_width`, `covered` | One-quantity, one-dataset evaluations; coverage applies only to estimated quantities. |
| `fixed`, `coverage_applicable` | Constants have `covered=missing` and `coverage_applicable=false`; point intervals do not count as calibration. |
| `fixed_value_matches_truth` | Whether a constant equals its declared truth; disagreement is warned, not silently corrected. |
| `mcse` | Existing MCMC MCSE for the same quantity's mean, SD and interval endpoints; unavailable values retain their status and `missing`. |
| `sampling_quality`, `sampling_warning` | Original diagnostics; warnings do not erase evaluation values. |
| `source_binding`, `model_contract`, `evaluated_draws_hash` | Data/ID, model/prior/scale and evaluated-draw identities. |

A constant's zero MCSE follows from its fixed model value, not precise estimation
or model correctness. Endpoint MCSE does not certify a coverage classification,
and this function applies no precision threshold. MCMC error differs from
between-dataset replication uncertainty; see the
[Stan posterior-analysis guide](https://mc-stan.org/docs/reference-manual/analysis.html).

Do not count persons, items, chains or folds within one fit as independent
simulation replications. Historical `parameter_recovery_summary` summarizes
parameter rows descriptively, without replication SE; its vector-truth interface
and meaning remain unchanged. Do not pass all new rows, including constants,
into that old summary indiscriminately. Selecting `coverage_applicable` rows
still does not turn them into independent replications.

SBC needs a separate design generating parameters and data from the analysis
model's joint prior across multiple datasets. Fixed-truth recovery is not SBC;
see the [Stan SBC guide](https://mc-stan.org/docs/stan-users-guide/simulation-based-calibration.html).
The API cannot authenticate generation or independence, so it retains
`generating_truth_verification=:not_established`,
`independent_replications=:not_verified` and `sbc=:not_performed`.
The next operation reuses these evaluations. A general data-generation,
fitting and between-design comparison runner is not implemented.

```@raw html
<a id="固定した真値でのデータセット間の回復集計"></a>
<a id="固定した真値でのデータセット間の回復集計-1"></a>
```

## Aggregate fixed-truth recovery across datasets

`BayesianMGMFRM.recovery_replications` matches saved `recovery_evaluation`
results to a planned dataset roster and summarizes bias, mean absolute error,
MSE, RMSE, coverage and mean interval width for each quantity. One dataset is
one replication for that quantity. Persons, items, chains, folds and other
parameter rows do not increase the replication count. Use separate `scenario_id`
values for different sample sizes, allocations, analysis models, priors or truths.

```julia
using BayesianMGMFRM, Serialization
include("examples/saved_recovery_replications.jl")
# Each file contains that dataset's serialized recovery_evaluation.
summary = saved_recovery_replications(["recovery-D1.jls", "recovery-D2.jls"];
    planned_dataset_ids=["D1", "D2", "D3", "D4"],
    parameters=["theta[P1]"], # Use a name from the actual recovery_quantities result.
    scenario_id="predeclared-fixed-design-A",
    dataset_independence=(status=:unresolved, evidence="Generation and seed independence remain unverified"),
    failures=["D3" => "Estimation interrupted"])
```

Here D1/D2 are completed, D3 failed and D4 is missing. Prespecify the roster and
quantities before seeing results. Inferring the denominator from available files
would exclude failures. Dataset IDs must be unique and failure reasons explicit.
Duplicate/unplanned IDs, both a result and failure for one ID, and altered
records are rejected. Output follows the planned roster regardless of input order.

| Output | Interpretation |
| --- | --- |
| `ledger` | Every planned completed/failed/missing dataset, retaining completed evaluations, diagnostics and MCSE. |
| `summaries[i].all_completed` | Descriptive results for all completed datasets containing that quantity, including numerical warnings. |
| `summaries[i].without_warnings` | Excludes sampling warnings, unavailable quantity MCSE and fixed-value/truth disagreement; this is not passage of a precision threshold. |
| `dispositions` | Quantity-specific missingness, constants and warnings; datasets evaluating only other quantities remain in the denominator. |
| `n_datasets`, `n_unresolved`, `n_planned` | Used, unresolved and planned counts. Constants receive no recovery summary or coverage rate. |
| `all_planned_coverage_bounds` | With c covered, n used and N planned, `[c/N, (c+N-n)/N]`. This assigns every unresolved outcome 0 or 1; it is not a confidence interval. |

Results are conditional on completed/selected datasets. Favorable warning-free
summaries do not establish performance over the entire planned design. Continuous
performance over all planned datasets is unavailable when outcomes remain
unresolved. Coverage bounds concern the computed 0/1 interval decisions and do
not correct finite-MCMC endpoint error.

Only with evidence of independent datasets from the same generating condition,
set `dataset_independence=(status=:declared_independent, evidence="Reference to the actual generation plan and seed rule")`.
For at least two used datasets, replication SE is the metric's sample SD
(denominator n−1) divided by √n. RMSE SE uses `SE(MSE)/(2√MSE)`; at zero MSE this
first-order approximation returns `missing`. Empirical zero variance, including
all-zero/all-one coverage, is labeled `:empirical_zero_variance`; zero reported
SE is not evidence of zero uncertainty. These SEs do not sum the fits' MCMC MCSE.
For separating questions, generating conditions, failures and simulation
uncertainty, see [Morris, White & Crowther (2019)](https://doi.org/10.1002/sim.8086).

Reused sample records, or identical target/evaluated-draw pairs under different
IDs, are retained in `repeated_evaluation_evidence` and suppress replication SE.
This detects some duplicates; different hashes/IDs do not establish independence.
The function rejects mismatched model/prior/scale/interval probability and changed
truths for evaluated quantities. It cannot verify the full generating process,
allocation, seed rule or every generating parameter. Check name/scale alignment
in the study design. Distribution-generated assurance, paired condition contrasts,
SBC and precision-based design acceptance are outside this operation.

```@raw html
<a id="比較・診断・保存を一つの手順で確認する"></a>
<a id="比較・診断・保存を一つの手順で確認する-1"></a>
```

## Connect comparison, diagnostics and persistence

`examples/saved_prediction_workflow.jl` connects all eight common fit types to
comparison, diagnostics, parameter MCSE and public report save/reload. Scalar
MFRM, scalar GMFRM and raw MGMFRM use the same example as the five recorded types
above. Supply fits saved in the same observation order and their persistent
rating-ID vector. For different row orders, use `saved_model_comparison` with
its per-model ID dictionary and the individual report routes. Fixed-coefficient
MFRM reports still require canonical records.

```julia
using BayesianMGMFRM
include("examples/saved_prediction_workflow.jl")

analysis = saved_prediction_workflow(
    "Independent" => "normalized.jls",
    "Correlated" => "correlated.jls";
    directory="comparison-reports", # A new output directory.
    dataset_id="rating-study-v1",
    observation_ids=rating_ids,
    comparison_axis=:model,
)
analysis.comparison.rows
analysis.models[1].diagnostics
analysis.models[1].parameter_mcse
analysis.models[1].report["waic"] # The report reloaded after saving.
```

Output directories are `model-1`, `model-2`, etc.; labels remain in the result.
All comparisons, diagnostics and reports are computed before saving, so unsupported
inputs do not leave partial reports. Existing destinations are not overwritten.
This does not provide an all-model rollback after an external file-write failure.

The example accepts `:waic` or `:raw_loo` and leaves difference SE uncomputed.
Each report requests both criteria regardless of the comparison criterion;
`require_complete=true` stops before saving if either cannot be computed.
Labels such as Independent/Correlated do not isolate a correlation effect when
priors or other assumptions also differ. Inspect each model contract and retain
warnings and unresolved decisions. This example performs neither fitting nor
figure rendering.

### Include explicit category, reliability and agreement choices

Add `reporting_by_model` to the same call to carry the selected reporting
sections through save/reload. Supply a dictionary containing every model label;
use `nothing` for a model that needs no additional sections. Each nonempty choice
uses the `category`, `agreement` and/or `reliability` options from
[integrated reporting](api-saved-reporting.md#One-report-with-explicit-analysis-choices).
The example supplies the common dataset and rating IDs to these sections, so
they cannot accidentally report a different row identity from the comparison.
Do not repeat those IDs in the per-model options.

```julia
catalogue = BayesianMGMFRM.recovery_quantities(load_fit_cache("normalized.jls"))
first_dimension_persons = [q.parameter for q in catalogue.rows
    if q.block === :person && q.dimension === 1 && !q.fixed]
cohort = (id="Fitted person cohort, dimension 1",
    parameters=first_dimension_persons, target=:centered)

# response_ids identify actual responses in the same row order as rating_ids.
# Keep distinct repeated performances distinct; do not infer them from person alone.
agreement = (response_ids=response_ids, interval=.95, se_unit=:person)
choices = Dict(
    "MFRM" => (category=(interval=.99,), agreement=agreement),
    "MGMFRM D2" => (category=(interval=.99,), agreement=agreement,
        reliability=[cohort]),
)
analysis = saved_prediction_workflow(
    "MFRM" => "mfrm.jls", "MGMFRM D2" => "normalized.jls";
    directory="comparison-with-reporting", dataset_id="rating-study-v1",
    observation_ids=rating_ids, comparison_axis=:dimensions,
    reporting_by_model=choices,
)
analysis.models[2].report["posterior_reliability"]["rows"]
analysis.models[2].report["rater_agreement"]["warning_rows"]
```

This explicitly selects the fitted-person cohort on the first dimension and
removes its draw-specific mean. It does not choose a population/design reliability
target or combine dimensions. The 99% category intervals are pointwise ETIs;
the 95% agreement intervals describe conditional expected agreement. Neither
option changes the intervals in unrelated report sections or supplies calibrated
coverage. Retain sampling warnings and unavailable MCSE.

For the original three fit types, this focused example omits the extra legacy
category-functioning, rater-homogeneity and calibration sections. Request the
common sections explicitly as above, or use `fit_report` separately for other
native diagnostics. Native scalar/generalized WAIC/LOO tables retain their row
indices; persistent IDs are in the common comparison and requested integrated
sections. The underlying report schemas are not rewritten to look identical.

Unknown/duplicate/missing model keys, misplaced identity options or failed
requested sections stop before any report is written. Completed reports retain
warnings: `require_complete=true` checks execution, not inferential adequacy.
The function remains an example composed of existing public operations, with no
automatic refitting, retries, model winner or new scientific acceptance.
