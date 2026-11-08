# Rater Drift: Fitting, Static Comparison and Saved Results

Did a judge become harsher when judging the same performances over time?
`BayesianMGMFRM.Experimental.RaterDrift` checks a scalar random-walk (RW1)
rating design, fits RW1 and matched static models, and reviews their saved reports. It preserves the
reference, prior, uncertainty and numerical warnings of the original analysis.

This experimental entry provides **input checking, four-chain fitting, native
restoration, computed reports and descriptive static/RW1 comparison**. Changing
the planned contrasts and prediction are not yet provided. Reading a report does not establish
coverage, reliable drift detection or a recommended prior. These operations do
not change the models accepted by `Experimental.fit`.

## Prepare the rating rows

Each row is one observed rating. `performance` identifies the same recording or
performance, `rater` identifies a judge, and `event_id` identifies one scoring
event. The same judge or task in two years is not itself a common performance.
Repeated recordings can link the severity scale across years. Judges may rate
different new performances alongside these common recordings.

The following four rows are an artificial input example, not a fitted dataset
or evidence about drift:

```julia
using BayesianMGMFRM
drift = BayesianMGMFRM.Experimental.RaterDrift

rows = [
    (event_id="e1", performance="recording-A", rater="judge-A", time="2024", score=1),
    (event_id="e2", performance="recording-A", rater="judge-B", time="2024", score=2),
    (event_id="e3", performance="recording-A", rater="judge-A", time="2026", score=1),
    (event_id="e4", performance="recording-A", rater="judge-B", time="2026", score=1),
]
input_options = (;
    categories=3,                   # full support: 0, 1, 2
    time_ticks=[2024, 2025, 2026],   # keep the unrated year
    time_labels=["2024", "2025", "2026"], time_unit="year")
model = drift.model(rows; input_options...,
    innovation_log_sd_mean=log(0.2)) # illustrative prior, not a default
allocation = drift.design_review(model;
    reference="2024", panel_weights=[0.5, 0.5])
allocation.status
allocation.panel_status
```

Missing ratings are omitted; zero is an observed score. Scores must already use
the declared zero-based ordinal support. A common category count and one rating
criterion are required. The model has rater-owned steps, fixed coefficients and
an adjacent-category logit multiplier of 1.7. Positive severity reduces the
probability of a high rating. It is distinct from the item-step planning model.

Ticks advance by one declared time unit. Empty bins retain process uncertainty;
removing 2025 would silently change the model. Trial-level ratings enter the
likelihood directly, while severity states live on the chosen time grid. This
is not a second-stage regression on separately estimated annual severities.
Choosing annual bins does not resolve within-session drift.

| Allocation status | Meaning |
| --- | --- |
| `reference` | Change from this bin to itself is fixed at zero. |
| `linked` | This likelihood identifies the contrast; precision can still be poor. |
| `process_only_endpoint` | At least one endpoint has no direct ratings; interpretation depends on the process and prior. |
| `data_confounded` | The allocation does not identify this change separately from other model locations. |

The fixed-panel contrast is checked directly with the declared weights. It is
not classified by requiring every individual contrast to be identified. Exact
rank calculations are intended for small input designs and do not assess sample
size adequacy. Proper priors can yield a posterior for an unlinked design;
that does not establish likelihood identification.

## Fit and retain the chains

Choose the innovation prior, reference, fixed-panel weights, credible mass,
practical-change tolerance and required MCSE before fitting. These choices
answer different questions: the credible interval represents posterior
uncertainty, the tolerance defines a substantively small change, and MCSE
measures simulation error. The following settings illustrate the interface;
they do not guarantee precision or adequate information for your design.
Use your actual `model`, not the four-row teaching input above, for inference.

Start Julia with one thread, use a project with its retained `Manifest.toml`,
and set BLAS to one thread:

```julia
using LinearAlgebra
BLAS.set_num_threads(1)
plan = drift.prepare(model;
    controls=(ndraws=8000, warmup=1500, step_size=0.03,
              target_accept=0.99, max_depth=12,
              metric=:diagonal, ad_backend=:ForwardDiff),
    chain_seeds=[1101, 1102, 1103, 1104],
    reference="2024", panel_weights=[0.5, 0.5],
    epsilon=0.2, interval=0.9,
    precision=(mean_mcse_max=0.01, endpoint_mcse_max=0.02))
fitted = drift.fit(plan; directory="rw1-chains") # performs inference
saved = drift.summarize(fitted)                 # no random generation
review = drift.report(saved)
review.source.numerical_qualified
review.warnings
receipt = drift.save_report("rw1-report.json", saved)
```

`prepare` supplies four deterministic dispersed starts, with log innovation SD
near its prior mean. It accepts explicit `initial_points` when needed. All
settings are retained in the plan. The fit uses the noncentered RW1 target and
four serial diagonal-metric ForwardDiff NUTS chains; it does not use the generic
`Experimental.fit` method. A new output directory is required.

`fit` writes each returned chain before validating it and preserves a failure
record if a chain fails. Earlier completed chains remain available. There is no
automatic retry, draw extension or MCMC resumption. Inspect incomplete output
with `drift.load_fit("rw1-chains"; require_complete=false).saved`; it cannot be
summarized as a complete fit. Fix the cause before deciding whether another
explicit attempt is scientifically and computationally justified.

All raw and model coordinates, retained sampler telemetry and each nonzero
planned contrast contribute to numerical qualification. The checks require
rank-normalized R-hat below 1.01, bulk and tail ESS of at least 400, no retained
divergences or invalid sampler values, E-BFMI of at least 0.3, and the declared
mean/endpoint MCSE limits. Warmup and maximum-tree-depth warnings remain visible.
Passing these checks does not establish statistical calibration or identification.

An eligible isolated unrated interior bin uses conditional integration only
when each chain supports batch sizes 100, 200, 400 and 800 with at least ten
complete batches of each size. Otherwise, the report keeps the joint-draw
interval and its numerical result, with `insufficient_retained_batches` shown
explicitly. A fully observed grid also yields a report without integration.
No data or grid bins are removed to obtain a numerical pass.

In a new Julia process with the same source, Julia, dependency environment and
thread settings:

```julia
restored_fit = drift.load_fit("rw1-chains")
restored_report = drift.summarize(restored_fit)
```

Native restoration checks the original environment, controls, checksums,
iteration order, telemetry and every retained target density. Use trusted local
files only: Julia native deserialization is not an untrusted-file format.
Historical private-chain records and other environments are not migrated by
this operation. For reading computed values in a different environment, retain
the portable JSON report and receipt as well as the original native environment.

`examples/fit_rater_drift.jl` defines `fit_rater_drift(rows, directory;
model_options, fit_options)` for the model → plan → fit → report → save route.
Including the file does not run a fit. Its caller provides actual rows and all
scientific and sampler settings. Keep the returned report warnings with results.

## Compare a matched static model

Does allowing severity to vary change the estimated performance locations and
judge severities? Fit the same ordered ratings with `process=:static`. This
model has one uncertain severity per judge, repeated at every grid time. It uses
the same performance, baseline-severity and normalized rater-step priors and
logit scale as RW1. It has **no innovation variable or prior**; do not approximate
it by choosing an extremely small RW1 innovation SD.

Reuse the actual rows and `input_options` from your RW1 analysis. The example
below retains the reference, weights, interval and precision settings in `plan`;
chain seeds are explicitly chosen for the static fit. Controls may differ
between models when prospectively justified, while numerical criteria agree.

```julia
static_model = drift.model(rows; input_options..., process=:static)
static_plan = drift.prepare(static_model;
    controls=plan.controls, chain_seeds=[2101, 2102, 2103, 2104],
    reference=plan.reference, panel_weights=plan.panel_weights,
    epsilon=plan.epsilon, interval=plan.interval, precision=plan.precision)
static_fit = drift.fit(static_plan; directory="static-chains")
static_report = drift.summarize(static_fit)
comparison = drift.compare(static_report, saved) # static first, RW1 second
answer = drift.report(comparison)
answer.locations   # paired rows with separate static and RW1 marginal summaries
answer.trajectory  # reference-relative changes under each model
answer.comparison_numerical_qualified
answer.warnings
comparison_receipt = drift.save_report("static-rw1-comparison.json", comparison)
reopened = drift.load_report(comparison_receipt.path;
    expected_sha256=comparison_receipt.sha256)
```

`locations` aligns each performance and each judge/time severity. Read its
`static` and `rw1` fields separately: mean, median, pointwise interval, mean and
endpoint MCSE, diagnostic and precision flags. Static severity levels have
nonzero posterior uncertainty, even though all of its changes in `trajectory`
are imposed zeros. Those zeros are not evidence that the judge remained stable.
Absolute locations use the models' proper priors for anchoring; they do not
establish likelihood identification. Keep the allocation checks alongside them.

Location summaries use the retained joint draws. Conditional integration applies
only to eligible **changes** in the trajectory report; it does not replace
location intervals. A location MCSE failure therefore can coexist with a passing
trajectory gate. `comparison_numerical_qualified` requires both trajectory/whole-fit
gates and every displayed location's diagnostic and precision criteria.
All failures and warnings remain in the saved comparison; they never trigger
an automatic extension or a different seed.

This comparison describes sensitivity to a model assumption. It supplies no
cross-model difference posterior: draw 100 in one fit is not jointly sampled
with draw 100 in the other. It does not compute model probabilities, predictive
ranking, detection performance or a preferred model. Overlapping intervals and
precise estimates do not settle model adequacy. Future predictive comparison
would require its own training/evaluation design and uncertainty assessment.

Different outcomes, event order, labels, category support, grid, reference,
weights, interval, tolerance or numerical policies are rejected. Different
retained chain lengths are allowed. Older computed reports without location
summaries remain readable, but cannot supply those missing summaries for a
comparison. Preserve their original draws and environment; no native migration
or inferred replacement values are performed here.

The saved comparison embeds the exact source JSON and checksums of both reports.
Reopening recomputes its descriptive table from those sources, retaining model
conditions and warnings. `examples/compare_saved_rater_drift.jl` runs this
report/comparison/save route from two report paths and their SHA-256 receipts,
without sampling or loading native chains.

## Read a saved computed report

Use a report and its separately retained SHA-256 receipt from a supported
producer, including `summarize` above. No posterior is bundled with this
example. Use `load_fit`, rather than `load_report`, for native-chain directories.

```julia
saved = drift.load_report("rw1-report.json"; expected_sha256=report_sha256)
review = drift.report(saved)
table = drift.trajectory(saved; rater="judge-A") # or rater=:panel
table.rows
review.warnings
```

Use a judge ID actually stored in the report. `:panel` uses its original fixed
weights. Each table row gives a mean, median, lower and upper credible limits,
mean and endpoint MCSE, numerical status, and design status. The displayed
quantity is severity at that time **minus severity at the saved reference**.
The reference zero has no estimated MCSE; it is not an absolutely known severity.
For a static report every change is structurally zero, including nonreference bins.

Intervals are marginal equal-tailed intervals at the saved probability. They
are **not a simultaneous credible band**. MCSE describes simulation error in
the reported estimates, not measurement uncertainty. Interval mass, reference,
weights and prior cannot be changed from this computed summary. Such changes
would require the original joint draws and an appropriate analysis route.

Some isolated unrated interior bins have conditional Gaussian-mixture summaries.
These integrate the empty state conditional on neighboring states and process
SD, improving numerical precision without adding data or narrowing the model's
posterior by fiat. The original joint-draw report remains available as
`review.source.original_report`, including its original qualification, event
probabilities, warmup and retained-sampling diagnostics. Unavailable CDF tail ESS
and paired-comparison warnings remain visible. A better endpoint MCSE does not
erase a sampler failure or establish statistical calibration.

Compare separately retained reports for prior sensitivity. A numerically precise
interval may still be sensitive to the innovation prior or miss the truth in a
known-truth example. This entry neither chooses a prior nor combines reports
into a model-selection result.

## Plot and save

```julia
using CairoMakie
open("severity-note.txt", "w") do note
    figure = drift.plot_trajectory(saved; rater="judge-A", annotation_io=note)
    save("severity-change.svg", figure)
end
receipt = drift.save_report("reviewed-rw1-report.json", saved)
# In a new Julia process, load BayesianMGMFRM again and use the saved receipt:
restored = drift.load_report(receipt.path; expected_sha256=receipt.sha256)
```

The plot retains every time bin. Orange points mark process-only or confounded
contrasts, and a diamond marks a structurally fixed change. In static reports all changes
are fixed at zero; this does not make severity levels certain. Lines connect displayed medians;
they do not imply a continuous-time estimate. Keep the external note with the
image: it records the interval definition, scale, prior, numerical status and
whole-report warnings even when only one judge is drawn. `table.rows` provides
the same numbers for further export.

`save_report` refuses an existing path and preserves the complete source JSON
bytes and checksum inside a versioned envelope. The returned receipt identifies
the new file. Portable report reading is distinct from native posterior-chain
compatibility, recomputing diagnostics or resuming MCMC. Keep the original
environment and retained draws for those operations. A checksum detects changed
bytes; trust and statistical validity require more than a matching checksum.

The supplied `examples/review_saved_rater_drift.jl` performs the report/table/save
route using only documented package operations. On an ordinary warning, inspect
`review.warnings` and the corresponding original diagnostic before interpreting
the interval; do not treat a selected judge's precise interval as approval of
the whole fit. Unexpected schema/checksum errors require the correct original
file and receipt, not bypassing the check.

RW1 describes temporal severity variation. It does not detect change points,
separate preceding-stimulus effects, estimate a causal recalibration effect,
or show growth in different contestants across years.

## Help

```@docs
BayesianMGMFRM.Experimental.RaterDrift.contract
BayesianMGMFRM.Experimental.RaterDrift.model
BayesianMGMFRM.Experimental.RaterDrift.design_review
BayesianMGMFRM.Experimental.RaterDrift.prepare
BayesianMGMFRM.Experimental.RaterDrift.fit
BayesianMGMFRM.Experimental.RaterDrift.load_fit
BayesianMGMFRM.Experimental.RaterDrift.summarize
BayesianMGMFRM.Experimental.RaterDrift.compare
BayesianMGMFRM.Experimental.RaterDrift.load_report
BayesianMGMFRM.Experimental.RaterDrift.report
BayesianMGMFRM.Experimental.RaterDrift.trajectory
BayesianMGMFRM.Experimental.RaterDrift.save_report
BayesianMGMFRM.Experimental.RaterDrift.plot_trajectory
```
