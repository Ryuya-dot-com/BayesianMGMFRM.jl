# Plan a Rating Study

Suppose three raters will assess speeches, and you can afford 72 ratings.
Should all three raters assess a few common speakers, or should pairs of raters
share more speakers? Equal numbers of ratings need not provide equal information:
shared ratings help separate speaker ability from rater severity. A useful design
study asks whether the resulting uncertainty is small enough for your decision,
as well as whether the model can be estimated reliably.

`BayesianMGMFRM.Experimental.RecoveryPlanning` connects a rating allocation to
the existing response generator, actual-data checks and saved-fit recovery review.
It prepares inputs and reads results. It does not run a simulation automatically.
The optional execution example below explicitly runs one planned dataset and
saves its stage records; including the example alone performs no computation.
Start with a small workflow check, then choose a meaningful precision target and
replication uncertainty requirement before a larger study.

## Choose the question and supported model

This route uses a **unidimensional MFRM with fixed unit slopes and item-owned
partial-credit steps**, on the unit-logit scale. The first canonical rater and
item have zero reference values; each item's steps sum to zero. Categories are
consecutive integers. The analysis prior is an explicit `MFRMPrior`.

For example, `rater[R2]` measures R2's severity relative to reference R1.
Positive severity lowers the expected score for an otherwise identical speaker.
The reference value is a scale convention, not evidence that R1 is unbiased.
An item can represent a scoring criterion in this scalar model; this assumes
one ability underlying the criteria. It does not fit a multidimensional construct
or a halo effect. Optional response IDs preserve grouping metadata but add no
dependence term. Other model/generator combinations need their own workflow.

Distinguish three questions:

| Study | What changes across datasets? | What it can evaluate |
| --- | --- | --- |
| Fixed-truth recovery, supported here | Responses change; generating parameter values are held fixed within a scenario | Bias, RMSE, coverage, interval width and availability at that scenario |
| Joint-prior SBC, input, explicit execution and saved-study review available here | Parameters are drawn jointly from the model's prior, then responses are generated | Calibration of posterior computation under that generative model; saved ranks support a conditional full-roster assessment |
| Decision assurance | Parameters and data follow a stated design distribution, and a decision rule is evaluated | Frequency of meeting that particular decision criterion |

A fixed-truth width count is not automatically SBC or decision assurance. The
generating values need not be typical of the analysis prior. Specify both.

## Prepare the allocation before scores exist

The bundled example prepares either of two allocations for 12 people, three
raters and four items. Both have 72 ratings and 24 ratings per rater:

| `allocation` | Shared people | Shared person–item combinations | Extra ratings |
| --- | ---: | ---: | ---: |
| `:concentrated` | 3, each assessed by all three raters | 12 | 24 |
| `:distributed` | 6, each assessed by two raters | 24 | 24 |

Each person first receives four ratings from one rater. The extra ratings create
links between raters. The two allocations change the pattern of overlap while
keeping the total rating budget fixed. One dataset for each is a workflow
example, not enough to recommend either design.

The following code only reads environment files and prepares a plan. Set
`manifest_path` to the manifest actually used by your active project; if using a
version-specific manifest, supply that file instead of `Manifest.toml`.

```julia
using BayesianMGMFRM
const P = BayesianMGMFRM.Experimental.RecoveryPlanning
include(joinpath(pkgdir(BayesianMGMFRM), "examples", "plan_mfrm_recovery.jl"))
manifest_path = joinpath(dirname(Base.active_project()), "Manifest.toml")
provenance = MFRMRecoveryExample.provenance(; manifest=manifest_path)
plan = MFRMRecoveryExample.example_plan(; allocation=:distributed, provenance)
job = only(plan.jobs)
length(plan.assignments)  # 72 planned ratings; no score column
plan.parameters          # ("rater[R2]",)
plan.interval            # 0.90: a central equal-tailed credible interval
```

The example's prior scales, true values, sampling settings and MCSE tolerances
are explicit teaching values, not recommended defaults. `provenance` records a
hash of the package's source tree and the selected project/manifest files; it
does not independently attest what a later worker executed.

For your own allocation, call `P.prepare(assignments; ...)`. Each row has exactly
`person`, `rater` and `item` nonempty string labels. Declare all levels and all
generating coordinates, including zero references and every item step. The
function rejects duplicate cells, unknown or unused levels, non-centered steps
and a rank-deficient location design. Graph connectivity alone is insufficient.
Declare the full dataset roster and distinct response/fit seeds in advance;
different seed values alone do not prove independent random streams.

Read `?BayesianMGMFRM.Experimental.RecoveryPlanning.prepare` in Julia for the
complete argument contract. [API help](api-experimental.md#Recovery-planning)
also documents each operation.

## Connect to generation and actual-data fitting

The objects have distinct roles:

| Operation | Result and use |
| --- | --- |
| `P.generator_input(plan, dataset_id)` | `design` and `direct_truth` for `simulate_responses`; its cyclic scores are structural placeholders, never actual outcomes |
| `P.bind_observations(plan, dataset_id, table)` | Save actual scores and their plan identity before model validation |
| `P.bind_data(plan, dataset_id, table)` | Validated actual data, design, prior and direct truth vector for analysis |
| `P.review_fit(plan, observations, path; cache_sha256)` | Check a saved native fit and compute recovery with numerical qualification |

**Only fit the design returned by `bind_data` for the actual response table.**
The generator's placeholder design exists because the existing generator takes
a `FacetDesign`; its scores play no role in the generating probabilities.

The next fragment **generates responses** when run. It is separate from plan
preparation:

```julia
using Random
input = P.generator_input(plan, job.dataset_id)
actual_table = simulate_responses(input.design, input.direct_truth;
    rng=MersenneTwister(job.response_seed), output=:table)
```

Save `actual_table` first. Then bind and save the observations before constructing
the fit input. A valid all-one-category outcome can be preserved even though the
fitter rejects it. Record that failure; do not silently redraw or omit it.

```julia
observations = P.bind_observations(plan, job.dataset_id, actual_table)
# Save observations before this validation step, using a new output path.
bound = P.bind_data(plan, job.dataset_id, actual_table)
```

To fit, pass `bound.design` and `bound.prior` to the existing `fit` API, with
the settings in `plan.sampler` and the job's `fit_seed`. The `:algorithm` and
`:gradient_backend` entries describe recorded metadata, so omit them from fit
keywords. Save the native fit with `save_fit_cache`. This is explicit estimation,
not an operation performed by preparing or binding the plan. Keep the original
Julia and dependency environment for reopening native caches.

## Execute one dataset with saved checkpoints

The reusable example connects the operations above. Including it only defines
functions. **Calling `run_job` can generate responses and run MCMC**; inspect the
plan and its sampling budget first. The following call uses a fixed-truth PCM
plan; the joint-prior SBC call is shown below. Work in the original compatible Julia/dependency environment
and retain its Project and Manifest with your study.

```julia
include(joinpath(pkgdir(BayesianMGMFRM), "examples", "run_mfrm_recovery.jl"))
record = P.ledger(plan)  # one full roster, including unattempted jobs
P.review(plan, record)
mkpath("study-runs")
result = MFRMRecoveryRun.run_job(plan, record, job.dataset_id;
    output_dir="study-runs/dataset-001", through=:recovery)
record = result.ledger
result.costs
```

Supply `through=:generation` to stop after saving responses and their binding,
or `through=:fit` to stop after saving the fitted model. To continue, pass the
returned ledger, the same dataset ID, a later `through` stage and a **new** output
directory. A completed generation or fit is reused after its artifact hash is
checked. This can also finish recovery for a compatible older ledger whose
generation and fit stages are complete. Keep all referenced directories. When
processing the next dataset, pass the latest full ledger so other jobs' outcomes
are retained. Use one writer; do not run jobs concurrently with separate copies
of the same ledger.

Each new output directory retains `plan.jls`, `runtime.jls`, `ledger-00.jls`,
numbered ledger checkpoints, stage artifacts and `outcome.jls`. The final outcome
contains the resulting ledger. `runtime.jls` records runtime labels, not a full
environment archive or independent execution certificate. Stage costs report
wall seconds through artifact saving and that artifact's byte size. They exclude
setup, ledger bookkeeping, CPU time, peak memory and other files in the directory.
These quantities should not be interpreted as the total cost of a design study.

If execution throws an error, read the saved outcome and inventory before
continuing:

```julia
using Serialization
outcome = deserialize("study-runs/dataset-001/outcome.jls")
P.review(plan, outcome.ledger)
```

A failed stage retains its kind/reason and is terminal. An interrupted process
may leave a `:started` checkpoint without a final outcome. Inspect the latest
readable checkpoint and any partial artifact; neither state is permission to
retry, regenerate data or continue an interrupted chain. Existing directories
are refused. All-one-category responses are saved before fitting rejects them,
so they remain failed planned outcomes rather than being silently redrawn.
If storage fails, the failure record itself may be unavailable; keep the partial
directory and earlier checkpoints. A completed requested stage is a read-only
no-op and does not create another output directory.

After successful recovery, `result.ledger` can be passed directly to
`summarize_recovery` below. Computational completion and numerical qualification
are separate: a warning-bearing fit still receives a completed recovery record
whose exclusions remain visible in the study summary.

## Review saved fits and aggregate the study

Use the cache hash recorded when the fit was saved. A newly computed hash alone
does not verify that it is the same historical file.

```julia
checked = P.review_fit(plan, observations, cache_path;
    cache_sha256=expected_cache_sha256)
checked.numerically_qualified
checked.precision
checked.recovery.rows
```

This checks actual scores, model, prior, parameter order, sampler settings,
fit seed and draw counts. Global sampling warnings exclude qualification even
if the focal mean has small MCSE. Both central-interval endpoints and the mean
must meet the declared MCSE limits; unavailable MCSE does not pass.
For a 99% central interval, prepare the plan with `interval=0.99`. This is not HDI.

For fixed-truth recovery, save each `checked` result with Serialization as the
ledger's recovery artifact. The generation artifact must contain the bound
observations, and the fit artifact must be the native cache. The full ledger
then supplies the planned denominator, failures and saved reviews automatically:

```julia
using Serialization
saved_ledger = deserialize("study-ledger.jls")
study = P.summarize_recovery(plan, saved_ledger;
    scenario_id="distributed-72",
    dataset_independence=(status=:unresolved,
        evidence="Independent dataset generation has not been established"),
    max_interval_widths=Dict("rater[R2]"=>1.0),
    width_confidence_level=0.95)
study.counts
study.roster        # includes failures, unfinished work and artifact problems
study.replications # existing recovery_replications result, ready for plotting
```

The width of 1.0 logit is an illustrative decision target, not a recommendation.
This call uses the plan's focal quantities, interval and MCSE limits. Missing or
changed artifacts remain unresolved; failed stages retain their reasons, and
unattempted jobs are distinguished from started but unfinished work. Completed
review contents are checked against the plan, observations and saved cache hash;
inconsistent contents stop aggregation. No native cache is deserialized or
rescored. Use trusted files in their compatible Julia environment.

`study.roster` reports whole-job qualification across all focal quantities.
Inside `study.replications`, qualification is per quantity: a poorly estimated
quantity does not discard another quantity that meets its own criteria. The
result is sealed and can be saved with Serialization at a new path. Pass
`study.replications` to the precision plotting functions below. Keep each
allocation/truth scenario separate, and declare the basis for dataset independence
before interpreting replication SE or a width-target confidence interval.
Unresolved independence leaves those uncertainty estimates unavailable.

The lower-level `BayesianMGMFRM.recovery_replications` remains available for
separately assembled evaluations. It requires all planned IDs and explicit
failure records; collecting only successful files changes the denominator.

The [saved recovery guide](common_prediction_comparison.md#Count-how-often-the-width-target-is-met)
shows `max_interval_widths` for a chosen measurement target. MCSE limits concern
the numerical accuracy of posterior summaries; interval-width limits concern
measurement precision. They answer different questions. Qualified-subset
frequency, unresolved-outcome bounds for all planned datasets and replication
uncertainty must remain distinct. Neither one successful fit nor a narrow mean
interval width establishes the frequency of achieving your target.

## Interpret precision-target uncertainty

The following optional display helps interpret a **fixed-truth width-target
study**. When aggregating its recovery records,
set `max_interval_widths`, `mcse_limits` and `width_confidence_level=0.95` in
`BayesianMGMFRM.recovery_replications`. Declare independent, identically
distributed dataset replications only when the generation plan warrants it.
The resulting `precision_qualified.width_target.conditional_confidence_interval`
is a per-quantity Clopper-Pearson confidence interval for meeting the width
target among numerically qualified datasets. It is not a posterior credible
interval. Unresolved independence or no qualified results leaves it unavailable.

Even one success out of one qualified dataset gives a 95% interval of
approximately **[0.025, 1]**. Two successes out of two give **[0.158, 1]**, despite
an empirical SE of zero. Neither establishes reliable target attainment. The
[R exact binomial reference](https://stat.ethz.ch/R-manual/R-devel/library/stats/html/binom.test.html)
describes the interval's repeated-sampling interpretation.

```julia
using BayesianMGMFRM, CairoMakie, Serialization
# These are saved recovery_replications summaries, not raw fit caches.
summaries = deserialize.(["design-A-summary.jls", "design-B-summary.jls"])
rows = BayesianMGMFRM.design_precision_plot_data(summaries; parameter="rater[R2]")
figure = open("design-precision-note.txt", "w") do note
    BayesianMGMFRM.plot_design_precision(summaries;
        parameter="rater[R2]", annotation_io=note)
end
save("design-precision.svg", figure)
save("design-precision.pdf", figure)
```

The left panel shows the conditional frequency and available confidence interval.
The right panel retains every planned dataset in an unresolved-outcome envelope;
it is **not** a confidence interval. All-failed scenarios remain visible. Each row
shows its width target and qualified/planned counts. Different model, prior,
truth or allocation choices must still be explained; matching quantity names
alone does not make scenarios scientifically comparable. These are separate
per-scenario intervals, not a test of the difference between designs, simultaneous
intervals or a rule for repeatedly checking and stopping a study. They concern
estimated widths and do not correct MCMC classification error near the threshold.
Keep the numerical summaries and external note with exported figures. Plotting
does not generate data, refit models or promote the experimental design workflow
to an accepted design recommendation.

## Prepare a joint-prior SBC study

Simulation-based calibration (SBC) asks whether posterior computation is calibrated
under the model's own joint prior and likelihood. Each dataset has a new parameter
vector drawn from the analysis prior, followed by new responses. A fixed-truth
study or a few chosen parameter vectors cannot answer this question. See the
[Stan SBC guide](https://mc-stan.org/docs/stan-users-guide/simulation-based-calibration.html)
for the rank argument and the effects of dependent posterior draws.

Reuse the allocation, settings and provenance from `plan` above. The following
fragment prepares two jobs without generating parameters, scores or posterior
samples. Two jobs illustrate the inputs; they are not an adequate SBC study.

```julia
prior = MFRMPrior(person_sd=1.5, rater_sd=1.0, item_sd=1.0, step_sd=1.0)
sbc_jobs = [(; dataset_id="sbc-$i", parameter_seed=3i,
              response_seed=3i+1, fit_seed=3i+2) for i in 1:2]
study = P.prepare_sbc(plan.assignments; levels=plan.levels,
    category_levels=plan.category_levels, jobs=sbc_jobs,
    prior, generating_prior=prior, parameters=plan.parameters,
    interval=plan.interval, sampler=plan.sampler, provenance=plan.provenance,
    precision=Dict(plan.precision), response_ids=plan.response_ids,
    rank_settings=(iterations=Tuple(1:10:plan.sampler.ndraws),
        dependence_policy="Assess selected-draw dependence; preserve unresolved outcomes"))
sbc_job = first(study.jobs)
parameter_input = P.prior_input(study, sbc_job.dataset_id)
study_ledger = P.ledger(study)  # every planned dataset, before generation
```

`rank_settings` fixes the retained iteration IDs to use from every chain, before
data generation. The interval of ten is an illustration, not evidence that
these draws will be independent. State an assessment policy appropriate to your
model; do not change the selection after looking for a favorable rank plot.
Omitting the setting keeps an input-only plan valid, but such a plan cannot use
the saved-rank review below.

Every free person, nonreference rater/item and free item-step coordinate has an
independent zero-mean normal prior with its declared scale. Draw **all** these
coordinates, not just the focal `plan.parameters`. The reference rater and item
stay at zero. For K categories there are K−2 independent steps per item; the
last step is their negative sum. Thus its variance is `(K-2)*step_sd^2` and its
covariance with each free step is `-step_sd^2`. Drawing K−1 independent steps and
then centering them would use a different prior. For binary scores the sole step
is zero. These constraints match the existing analysis model.

The next fragment **draws a prior parameter vector** when run. The RNG must
match the declaration in `plan.provenance`; the bundled example declares
`Random.MersenneTwister`.

```julia
using Random
parameter_rng = MersenneTwister(parameter_input.parameter_seed)
free_values = Dict(c.parameter => c.mean + c.sd * randn(parameter_rng)
                  for c in parameter_input.coordinates)
dataset_plan = P.bind_prior_draw(study, sbc_job.dataset_id, free_values;
    generating_prior=prior, parameter_seed=sbc_job.parameter_seed)
```

Save `dataset_plan` before response generation. It contains the realized full
truth, analysis prior, settings and parent study identity. Then follow the
generation, binding, fitting and saved-review instructions above, using
`dataset_plan` in place of `plan` and `sbc_job` in place of `job`. Use a separate
RNG initialized from `sbc_job.response_seed` for responses and the declared
`fit_seed` for fitting. Different seeds record distinct streams; they alone do
not establish statistical independence. The supplied provenance and seed are
declarations: binding values cannot verify that they were actually sampled.

Use **the parent `study` and `study_ledger`** for stage records so failed and
unattempted datasets remain in the denominator. Save the bound dataset plan
separately and register the observations alone as the generation artifact.
`summarize_sbc` expects those observations, not a wrapper containing both objects.
Keep the bound truth
even if response generation or fitting fails; preserve single-category outcomes
and their validation failures rather than redrawing them. The
`study.template` is only for allocation validation; its zero values are not
generating truths. `generator_input` rejects this parent SBC study: supply the
bound `dataset_plan` instead.

`recovery_replications` does not implement SBC across varying truths. Preparing
inputs does not establish calibration, a suitable replication count or a
preferred rating design.

## Execute one SBC dataset with saved checkpoints

The same example accepts the parent SBC study prepared above. **This call draws
all prior coordinates, generates responses and fits one model.** Inspect the
full study budget first. Merely including the example does not start this work.

```julia
using Serialization
include(joinpath(pkgdir(BayesianMGMFRM), "examples", "run_mfrm_recovery.jl"))
mkpath("sbc-runs")
sbc_result = MFRMRecoveryRun.run_job(study, study_ledger, sbc_job.dataset_id;
    output_dir="sbc-runs/sbc-1", through=:recovery,
    posterior_dependence=(status=:unresolved,
        evidence="Selected-draw independence has not been established"))
study_ledger = sbc_result.ledger
rank_review = deserialize("sbc-runs/sbc-1/recovery.jls")
rank_review.exclusions
```

The runner requires `rank_settings` before any generation and the declared
`Random.MersenneTwister` RNG. It uses separate parameter, response and fit seeds.
It saves `prior-input.jls`, the realized free coordinates in `prior-draw.jls`,
and `dataset-plan.jls` before generating responses. Reference coordinates and
dependent final steps are reconstructed by `bind_prior_draw`; the zero template
is never used as the generating truth. Actual responses are saved before data
validation, and `generation.jls` contains the bound observations.

As in fixed-truth execution, choose `through=:generation` or `:fit` to stop at
a saved boundary. Continue with the same **parent study**, the latest full
ledger, the same dataset ID and a new output directory. Keep `dataset-plan.jls`
beside the referenced generation artifact. The runner checks the complete bound
plan against the study and its observations before fitting or rank review;
missing or mismatched truth records stop the operation. Failed/started stages
are never automatically redrawn or retried. Keep the whole run directory,
including prior records and unsuccessful outcomes.

Pending `:recovery` requires an explicit `posterior_dependence` assessment.
An unresolved assessment still produces descriptive ranks and exclusions.
Convergence, a thinning interval or distinct seeds does not establish independent
rank draws. The completed parent ledger can be passed directly to
`summarize_sbc` below. It retains failed, unattempted and numerically excluded
jobs; it does not convert successful execution into a calibration finding.
Fixed artificial tests of this connection are not an SBC experiment.

## Review SBC ranks from a saved fit

After saving an SBC dataset plan, observations and native fit, use their original
study and recorded cache hash. The following operation reads the saved fit and
computes summaries; it does not generate parameters, responses or posterior draws.

```julia
rank_review = P.review_sbc_fit(study, dataset_plan, observations, cache_path;
    cache_sha256=expected_cache_sha256,
    posterior_dependence=(status=:unresolved,
        evidence="Selected-draw dependence has not yet been assessed"))
rank_review.ranks
rank_review.exclusions
rank_review.quantity_diagnostics
```

The function checks the parent study and complete bound truth, then performs the
same data, prior, sampler, seed and native-cache checks as `review_fit`. It uses
the predeclared retained iterations from each chain and saves their row, chain
and iteration IDs in the result. Numerical diagnostics use **all retained
draws**, so subsetting for ranks does not hide a poorly mixed chain.

The test quantities are the focal free parameters in `plan.parameters` and
`joint_log_likelihood`: the log probability of the actual observed responses,
evaluated at the true parameters and at each retained parameter vector. Parameter
ranks alone can miss an algorithm that ignores the data; a data-dependent test
quantity helps detect that failure. See
[Modrák and colleagues](https://arxiv.org/abs/2211.02383).

For L selected draws, a zero-based rank ranges from 0 to L. `lower` counts
draws strictly below the truth, and `upper` adds those exactly equal to it.
For example, truth 0 among `[-2, -1, 0, 0, 3]` gives the inclusive range [2, 4].
With no ties, `rank` equals `lower`. With ties, `rank` is `missing`: the
operation does not choose the lower endpoint, midpoint or a random position.
The theoretical discrete-uniform rank needs suitable random tie breaking when
ties occur. Keep unresolved ties rather than silently treating either endpoint
as that randomized rank. Near-equal floating-point values are not exact ties.

`rank_eligible` is false when any of the following remains unresolved:

- Global fit diagnostics or the planned focal mean/interval-endpoint MCSE limits.
- Diagnostics for a test quantity: rank-normalized split R-hat at most 1.01 and
  bulk/tail ESS at least 400, computed on all retained draws.
- Posterior dependence of the selected draws, assessed against the declared policy.
- Exact ties in any test quantity.

Descriptive rank ranges remain visible for excluded fits. A
`posterior_dependence` status of `:declared_independent` must cite the assessment
in `evidence`; the software records that declaration and does not verify it.
Passing R-hat/ESS checks or selecting every tenth iteration is not proof of
independence. Diagnostics, dependence and tie exclusions remain separate fields.

Save `rank_review` at a new path and retain it with the parent study ledger.
Record failed and unattempted datasets as well; do not form a success-only SBC
summary. `summarize_sbc` below combines these saved reviews with the full ledger.
Even `rank_eligible=true` verifies neither the prior-generating history nor
posterior calibration, and does not recommend a rating allocation.

## Summarize all planned SBC datasets

`P.summarize_sbc` reads the parent study ledger and retains every planned ID.
For each completed dataset, the `generation` artifact must be the serialized
bound observations, the `fit` artifact the native cache, and the `recovery`
artifact the serialized `rank_review`. Use `record_stage` as described below
and save each returned ledger. Completed stages mean that files were saved;
a completed review can still exclude a fit from the rank calculation.

With the two-job preparation example above, this call describes two unattempted
jobs. After execution, pass the updated ledger containing the saved artifacts:

```julia
study_summary = P.summarize_sbc(study, study_ledger; alpha=0.05,
    dataset_independence=(status=:unresolved,
        evidence="Independence across planned datasets has not been assessed"))
study_summary.counts
study_summary.exclusion_counts
study_summary.quantities
```

The summary checks saved file hashes, dataset/study/observation/fit identities,
selected iterations and the declared quantity family. It reads observations and
rank reviews in their compatible Julia environment, without loading or rescoring
native fits. Use trusted local records. Reusing a cache or saved sample under
two dataset IDs raises an error. Legacy scalar reviews without a source-sample
hash use the fitted target plus the evaluated focal-draw hash, matching
`recovery_replications`. This identifies those recorded values, not unrecorded
sampling history. Missing or changed files, failures, unfinished
stages and absent attempts stay in `roster` and in the planned denominator;
malformed completed records require correction before a summary can be returned.
Failure reasons, stage states, descriptive ranks and numerical/dependence/tie
exclusions remain visible. Verified relocation works without editing old paths
embedded in the reviews.

For each quantity, let N be **all planned datasets**, L the selected posterior
draws per dataset, c the eligible ranks at most k, and u the unresolved datasets.
At k below L, `lower=c/N` and `upper=(c+u)/N` describe every possible completion
of the missing ranks. Both are 1 at k=L. These bounds describe missing results;
they are **not confidence bands**. For example, two eligible ranks of 0 among
eight planned datasets give [0.25, 1] at k=0, rather than a success-only CDF of 1.
A tie in any quantity excludes the dataset's entire primary rank family, while
retaining its descriptive tie ranges. There is no automatic tie randomization.

Across-dataset independence is separate from the posterior-draw dependence
assessment in each review. With `dataset_independence.status=:unresolved`,
`epsilon`, `band_lower`, `band_upper` and `resolved_departure` are missing and
`conditional_screen=:assumptions_unresolved`. Only the descriptive bounds remain.
An explicit `:declared_independent` assessment, with supporting `evidence`, enables
a **conditional** comparison with the uniform-rank reference `(k+1)/(L+1)`.

For T predeclared quantities (all focal coordinates plus the joint log likelihood),
the missing-rank bounds are widened by `sqrt(log(2*T/alpha)/(2*N))` and clipped
to [0,1]. This applies the Dvoretzky–Kiefer–Wolfowitz–Massart bound with a
Bonferroni adjustment over T quantities; independence between quantities is not
required. See [Reeve's proof and discussion](https://arxiv.org/abs/2403.16651).
Independent datasets and valid iid posterior ranks remain assumptions, not facts
established by diagnostic thresholds or declaration text.

`:departure` means the reference lies outside the widened bounds at some rank,
even allowing for all unresolved outcomes. `:no_resolved_departure` means no such
departure was detected; `:unresolved` means no eligible ranks were available.
None is a calibration certificate or a design recommendation. Choose alpha before
inspecting results and assess the fixed roster once; repeated monitoring or
selection across studies is not covered by this bound. Small rosters and many
unresolved datasets can yield little sensitivity. Actual prior generation,
posterior correctness and independence need their own evidence. The operation
performs no fitting, generation, tie breaking, retry or file writing.

## Choose rank resolution and a finite assessment

Choose the selected draws and the repeated-study question **before** generating
any parameters or responses. These are separate decisions: more selected draws
give finer ranks, while more datasets improve the precision of their distribution.
Neither replaces checking that each fitted posterior is numerically usable.

One prospective option uses a single, prespecified retained iteration from each
separately initialized and adapted chain. For example, 19 chains with 1,000 warmup
and 2,000 retained iterations give 38,000 draws for diagnostics, but only 19 for
the rank. The rank then ranges from 0 to 19 and its null CDF advances in steps of
0.05. This is an illustrative computational setting, not a sampling default or
a guarantee about the accuracy of a posterior's 5% quantile.

The following prepares a **new study**, using the allocation, prior, provenance
and independently chosen job roster from the preparation example. It performs
no generation or fitting. Do not apply this policy retrospectively to an existing
study whose selection or acceptance criteria were different.

```julia
chain_sampler = merge(plan.sampler, (;chains=19, warmup=1000, ndraws=2000))
chain_policy = "One final draw per separately initialized/adapted chain; " *
    "conditional on independent pseudorandom innovations and posterior stationarity"
chain_study = P.prepare_sbc(plan.assignments; levels=plan.levels,
    category_levels=plan.category_levels, jobs=sbc_jobs,
    prior, generating_prior=prior, parameters=plan.parameters,
    interval=plan.interval, sampler=chain_sampler, provenance=plan.provenance,
    precision=Dict(plan.precision), response_ids=plan.response_ids,
    rank_settings=(iterations=(2000,), dependence_policy=chain_policy))
chain_ledger = P.ledger(chain_study)
```

For the scalar AdvancedHMC route, initialization, metric, kernel and adaptation
are constructed separately for each chain. A single final draw avoids using
within-chain pairs in the rank. Conditional independence still assumes suitable
independent random innovations; the implementation consumes a pseudorandom stream
sequentially. Full-chain diagnostics assess mixing and numerical problems but
cannot prove stationary posterior marginals. Use separate parameter, response
and fit streams, and never initialize fitted chains from the generating truth.
This reasoning does not automatically apply to another sampler or shared
adaptation scheme. Record `:unresolved` when these assumptions are unsupported.

When this prospective policy is justified, supply its evidence through
`posterior_dependence` to the existing `run_job` operation. Execute the declared
roster, preserving each returned ledger and every failed or excluded job. A
successful feasibility run checks operations and cost; its one or two ranks do
not establish calibration. Save the study and latest ledger, retain their original
environment and artifacts, then use `summarize_sbc` after reopening them with
`Serialization.deserialize`. This saved-only step does not repeat generation or
fitting. An already completed stage can be reused; an interrupted MCMC chain
cannot be resumed by the ledger.

For a concrete precision calculation, suppose the two predeclared quantities
are R2 severity and joint log likelihood. With 175 independent datasets and
alpha 0.05, the simultaneous DKW radius is about 0.1119. For a rank-CDF departure
of at least 0.20, the probability of both non-detection and an unresolved fraction
at most 0.02 is bounded by about 0.1972 under the stated assumptions. A power
claim of at least 0.8028 additionally assumes that exclusion bound always holds;
observing few exclusions afterwards does not establish conditional power.
Preserve more exclusions if they occur, widen the bounds, and report the weaker
answer without replacing datasets. These numbers concern a large, specified
departure, not small tail errors or every possible error in a posterior.

Finite ranks also smooth differences in the underlying posterior probabilities.
Some nonuniform posterior-probability distributions can give exactly uniform
finite ranks, even with infinitely many datasets. More chains can reduce a
particular blind spot but cannot eliminate all such cases. Report the selected
quantities, number of ranks, detection objective, exclusions and assumptions
alongside the result. `:no_resolved_departure` means that the specified assessment
found no departure; it is not evidence that all uncertainty estimates are correct.

## Preserve failures and inspect unfinished work

`P.ledger(plan)` includes every planned dataset. For each generation, fit and
recovery stage, use `P.record_stage` to return a new record: `:not_started` →
`:started` → `:completed` or `:failed`. Save the started record before executing
work; save a completed record only after saving its artifact. Failure requires
a reason and `failure_kind=:validation`, `:computation` or `:persistence`.

`P.review(plan, ledger)` checks artifact hashes and shows completed, failed,
unfinished and unrecorded work. Completed means that an artifact was recorded,
not that its numerical diagnostics passed. An unfinished stage needs inspection
for an existing process or orphan output before any manual recovery decision.
The functions do not restart a failed job or resume an interrupted MCMC chain.

Plans and ledgers use Julia Serialization in a compatible environment, absolute
artifact paths and a single writer. Keep successive records at new paths; there
is no atomic saving or concurrent execution scheduler. The legacy `example.*`
schema names remain for compatibility with previously saved v2 plans and v1
observation/review/ledger records. Content hashes detect alteration, not false
provenance declarations. Older v1 plans require explicit reconstruction; do not
relabel them as v2.


## Move a saved study folder

Moving a folder does not update the absolute paths recorded in its ledger.
A subsequent `P.review` can therefore report missing files even when the
outputs were copied correctly. Use `P.relocate_ledger` to verify the copied
files and return a ledger with the new paths.

First copy or move the study folder, preserving its subdirectories and file
names. Load its saved plan and ledger in a compatible environment. Let
`old_study_directory` be the original absolute directory path (it need not
still exist), and `new_study_directory` the directory containing the copied
files. Both roots refer to the same part of the directory tree. Every artifact
recorded in the ledger must be under the original root.

```julia
using Serialization
moved = P.relocate_ledger(plan, ledger;
    source_root=old_study_directory,
    destination_root=abspath(new_study_directory))
inventory = P.review(plan, moved)
inventory.counts
new_record_path = joinpath(new_study_directory, "ledger-relocated.jls")
ispath(new_record_path) && error("Choose a new ledger filename; retain existing records")
serialize(new_record_path, moved)
```

The operation verifies every recorded artifact at its new relative location
before returning. A missing file, a changed byte or an artifact outside the
source root causes an error. It does not replace missing results, search for a
similar filename or regenerate anything. Completed, failed, unfinished and
unrecorded datasets retain their original states. Files with the same basename
in different subdirectories remain distinct.

Keep the original ledger. `moved.relocations` records its hash and both roots;
subsequent `record_stage` updates retain this history. For another move, use the
latest ledger and its current artifact root. A plan with no recorded artifacts
needs no path changes and returns an unchanged ledger.

This function only verifies file bytes and changes the returned ledger. It does
not copy files, reopen a fit, resume a chain or change historical paths embedded
inside saved reports. To inspect a moved fit, pass its new artifact path and
unchanged recorded hash to `review_fit` in the original compatible environment.
File identity alone does not establish native-cache compatibility on another
Julia version or operating system. `review` checks the artifacts again and can
detect changes made after relocation.
