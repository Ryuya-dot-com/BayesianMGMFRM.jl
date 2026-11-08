# Concurrent Three-Outcome Study

The separate `ThreeIndicator.ConcurrentInput` route checks a concurrent table of
preliminary and additional listeners with 9/9/2 responses. Its current scope is
mathematical inspection, fitting, joint posterior probabilities/contrasts,
conditional posterior predictive response checks, and
portable model specifications and computed reports. The preliminary-only
fitting and saved-report routes above remain separate; their fitting methods do
not accept this concurrent target.

```julia
using BayesianMGMFRM, SHA
T = BayesianMGMFRM.Experimental.ThreeIndicator
# rows is a labelled row iterator, for example CSV.File(path).
input = T.ConcurrentInput(rows; source_sha256=bytes2hex(sha256(read(path))))
target = getdesign(input; prior=:steps, interaction=:full)
design_summary(target)
contract(target)
q = initial_params(target)  # a deterministic inspection point, not an estimate
value, gradient = logdensity_and_gradient(target, q)
logprior(target, q) + loglikelihood(target, q)
effects = coordinates(target, q)
receipt = save_report("concurrent-model.json", target)
restored = load_report(receipt.path; expected_sha256=receipt.sha256)
```

The table must supply `source`, `experiment`, `trial_index`, `block_index`,
`within_block_index`, `speaker_id`, `speaker_l1`, `style`, `word_number`,
`target_word`, `rater_id`, `token_id`, `speaker_style_id`, `accentedness`,
`comprehensibility` and `intelligibility_exact`. Study labels are `main_222` and
`english_20`; the three source cohorts are `original_202`, `gapfill_22` and
`english_20`. The historical first label denotes the **retained original cohort**,
not a requirement to include 202 original listeners. The application uses 200
retained originals, 22 gap-fill listeners and 20 additional listeners. Speaker
language/style cells are ENG-natural, JPN-natural/accented and
CHN-natural/accented. Additional listeners hear ENG-natural recordings only.

Trial numbers must be contiguous within listeners. Blocks contain 25 positions,
up to four preliminary or six additional blocks. Physical-speaker and word lag
histories cross block boundaries; previous language/style starts again at each
block. The 15 preliminary and nine additional predictors are study-specific.
The intercept, these predictors and two cohort contrasts must have rank 27.
Recording identities must map one-to-one onto the complete speaker-style × word
grid; ratings of that grid can be incomplete. This is a study-specific adapter,
not an arbitrary facet/formula API or a claim of empirical identification.

All outcomes point toward difficulty: ordinal responses stay in 1:9, and exact
transcription correctness 1/0 becomes category 1/2. The multiplier is **1**; the
word/listener slope product multiplies the complete location-minus-step term.
The binary step is fixed at zero. Declare `prior` as `:reference`, `:steps`,
`:combined`, or a `T.ConcurrentPrior` object. `contract(target)` records the actual
numerical settings. The preliminary-only model still accepts only its presets.

### Inspect a same-event ordinal association

The default `association=:independent` factorizes the three responses conditional
on their shared effects. A separate experimental mathematical target allows a
single Plackett association between accentedness and comprehension difficulty:

```julia
associated = getdesign(input; prior=:steps, interaction=:full,
    association=:plackett, association_log_sd=1.0)  # explicit working prior
q = initial_params(associated)
value, gradient = logdensity_and_gradient(associated, q)
pointwise_loglikelihood(associated, q)  # one joint 9×9×2 event per row
contract(associated)
receipt = save_report("associated-model.json", associated)
restored = load_report(receipt.path; expected_sha256=receipt.sha256)
reference_data = stan_data(associated)  # src/stan/concurrent_ac.stan
```

The appended coordinate is `ac_log_psi = log(psi)`, with an independent normalized
`Normal(0, association_log_sd)` prior on this log coordinate. The SD must be supplied
explicitly; 1.0 is an example working prior, not a generally validated default.
There is no additional Jacobian on `log(psi)`. Expressing the same prior as a density
on `psi` would require division by `psi`.

The Plackett cell law preserves both ordinal marginals at each parameter state;
the binary response remains conditionally independent of the ordinal pair. At
`ac_log_psi=0`, the likelihood and original-coordinate scores recover the independent
model. The score in the new association direction generally remains nonzero.
The complete augmented log posterior also contains the new normalized prior term;
it is not numerically identical to the old log posterior at zero.

This parameter is shared across the three listener cohorts. It describes residual
same-event association conditional on the modeled effects. It does not establish
causal halo, construct identity, or temporal recalibration. Original univariate
prior predictive distributions are preserved algebraically; posterior marginals
and contrasts can still change after conditioning on the joint observations.

The same fitted lifecycle now supports this extension, including native and
`pair_132` sampler coordinates. The association coordinate is unchanged by that
chart and is included in raw/model summaries and whole-fit diagnostics.

```julia
prior_check = prior_predictive_check(associated; ndraws=100, seed=41)
plan = prepare_fit(associated; chains=2, warmup=100, ndraws=100, seed=42,
    parameterization=:pair_132)  # operation settings, not a precision recommendation
fitted = fit(plan; directory="associated-fit")
posterior_check = predictive_check(fitted; seed=43)
save_report("associated-prior-check.json", prior_check)
save_report("associated-posterior-check.json", posterior_check)
reopened = load_fit("associated-fit")
posterior_summary(reopened; parameters=["ac_log_psi"])
```

`predictive_check(associated; ...)` is also a prior predictive check: parameters
come from independent joint-prior draws. `predictive_check(fitted; ...)` conditions
on the joint retained posterior states and existing effects. It does not refit the
model. Each event draws A from its marginal, C from the conditional C-given-A row
of the exact joint table, and the binary response independently conditional on the
full state. Joint expected counts and conditional variances use the joint cell
probability. All draws preserve chain, iteration, event and source-row identities.
Only counts and discrepancies are retained, without a response cube.

`event_probabilities` and `contrast` still report outcome marginals using every
joint parameter state; they do not return a joint 9×9 table. Their source model and
warnings identify the association. Posterior intervals for probabilities are
separate from intervals for replicated response counts. An unqualified short fit
remains visibly unqualified in its reports and PPC.

Predictive schema v3 records the replication law and exact decimal-string seeds.
Prior v2 and posterior v1/v2 reports for the independent model remain readable;
legacy schemas cannot be relabeled as dependent-response checks. Portable model
specifications preserve the explicit association prior. Native fits still require
their producing source/environment; this is not migration of old caches.

The supplied analytic likelihood gradient handles the precision-switching cell
evaluator. High-precision cell/table fallbacks share a lock to protect their use
of process-global BigFloat precision during threaded chains. Ordinary calculations
and independent chains can proceed concurrently; no parallel speed advantage is
promised. This lock does not coordinate unrelated external BigFloat code.
Strong association can make fallback expensive. Unrepresentable positive table
probabilities or precision-resource limits raise explicit errors without clipping
or changing the prior. The Stan adapter remains a finite-point reference for
`interaction=:full`; its extreme-tail sampling range is not qualified. Small
operation checks establish neither convergence, prior adequacy nor empirical PPC
improvement.

### Choose numerical priors

Start with a named preset and override the settings justified by your study:

```julia
# Syntax example, not recommended scientific scales.
prior = T.ConcurrentPrior(:steps;
    intercept_sd=(1.5, 1.5, 2.0),
    beta_sd=(0.7, 0.7, 1.0),
    step_coordinate_sd=0.8,
    pair_sd_scale=0.3,
    lkj_eta=2.0, pair_lkj_eta=4.0)
target = getdesign(input; prior, interaction=:full)
contract(target).prior
prior_check = prior_predictive_check(target; ndraws=100, seed=42)
# Use this same target with prepare_fit/fit and save_report/load_report.
```

This changes numbers within the Gaussian, half-normal and LKJ families. It does
not accept arbitrary distribution objects or change the response model. All
active scales and LKJ shapes must be finite and positive; Boolean values, unknown
keywords, incomplete saved settings and wrong vector lengths are rejected.
Arrays supplied to the constructor are copied into immutable tuples.

| Setting | Meaning |
| --- | --- |
| `sd_scale` | Six half-normal scales for speaker, word, listener, recording, time and language population SDs, in that order |
| `step_sd_scale` | Half-normal scale for listener-specific step population SDs |
| `intercept_sd`, `beta_sd` | Three zero-mean Gaussian SDs, ordered as accentedness, comprehension difficulty, transcription error |
| `cohort_sd` | Gaussian SD of each additional cohort contrast |
| `slope_log_sd` | Gaussian kernel scale for centered log word/listener slopes |
| `step_mean`, `step_coordinate_sd` | Eight centered transition means shared by the ordinal outcomes, and SD on their seven orthonormal contrast coordinates |
| `lkj_eta` | LKJ shape for each of the six population correlation blocks |
| `pair_sd_scale`, `pair_lkj_eta` | Half-normal SD scale and, under `interaction=:full`, LKJ shape for the raw listener×word population effect |

For the ordinal step vector, with orthonormal contrast matrix H,
`step = H*q`, `q ~ Normal(H' * step_mean, step_coordinate_sd^2 * I)`.
Its covariance is `step_coordinate_sd^2 * (I - ones(8,8)/8)`. Means must sum to
zero; their order does not impose hard ordering on sampled steps. Other general
effect means remain zero. Population SD hyperpriors are not the marginal SDs of
reconstructed centered/convolved effects. All settings use this model's multiplier
one scale; priors from a multiplier-1.7 model cannot be copied by name alone.

Portable model schema v2 retains the complete custom prior. The reader also
accepts legacy v1 preset model specifications. Native fit plans use v3 and still
require their exact producing source/environment; this is not old-cache migration.
Prior/posterior reports preserve the resolved settings, and changing a prior
requires a new target/fit, not relabelling existing posterior draws.

`stan_data(target)` exports JSON-ready data for `src/stan/concurrent.stan` with
all numerical priors. This independent reference currently requires
`interaction=:full`; it does not compile/run Stan or import its posterior draws.
Finite density/gradient agreement verifies implementation, not posterior agreement,
prior suitability or scientific acceptance.

`interaction=:none` omits the listener×word term. `:diagonal` and `:full` add a
persistent raw pair vector with diagonal or full three-outcome covariance.
The named presets use provisional independent half-normal SD priors with scale 0.5;
`:full` uses LKJ(2) correlations. A `ConcurrentPrior` can explicitly override both. These are explicit alternatives, not an empirically
accepted default or additional construct dimensions.

The target exactly integrates redundant Gaussian components. It convolves their
covariances with the original word/listener/cohort priors, including the additional
ENG listener's inseparable language-contrast contribution. `coordinates` returns
the resulting **effective** word/listener/cohort effects and globally double-centered
pair residual E. It does not return the original population components; the
`original_population_components` field explicitly records this limitation. In
particular, `pair_covariance` describes the raw population B, whereas E's marginal
covariance is `(1-1/R)*(1-1/W)*pair_covariance`. Original B and main-effect draws
require their joint conditional Gaussian reconstruction. Do not interpret effective
effects or conditional means as those original draws.

`pointwise_loglikelihood` has one entry per sorted event, summing its three
conditionally independent response terms. `design_summary(target).source_rows`
maps each sorted event back to its input row. This vector is not a held-out
predictive score with shared effects integrated out. `save_report` in this example
saves **only a model specification**, with rows, declared source checksum, prior
choice and interaction restriction; it stores no parameter point or posterior.
The supplied source checksum is provenance declared by the caller, while the
receipt verifies the saved specification bytes. Restore with the typed constructor
shown above, retaining the generating package/environment for reproducibility.

The gradient uses analytic likelihood/large-block adjoints and automatic
differentiation of small covariance factors. Finite density/derivative checks do
not establish sampler convergence, practical MCMC cost, prior adequacy, anchor
invariance or construct dimensionality. Fitting and posterior contrasts use the shared operations below. Joint
original-component draw recovery remains unavailable for this target.

## Prior prediction, posterior probabilities, and posterior predictive checks

The parameter source determines what a check answers. The two predictive checks
are not interchangeable, and the abbreviation "PPC" alone can obscure this.

| Operation | Parameter source | What it describes | Concurrent support |
| --- | --- | --- | --- |
| `prior_predictive_check(target; ndraws, seed)` | Joint prior, before fitting | Replicated responses implied by the prior on the declared design | Available; existing roster and assignment |
| `event_probabilities(result; ...)` | Fitted posterior | Uncertainty in conditional category probabilities | Available |
| `predictive_check(result; seed=...)` | Fitted posterior | Replicated responses compared with the observed responses | Available for existing levels/design |

For prior prediction, parameters follow ``\theta\sim p(\theta)``. For posterior
prediction they follow ``\theta\sim p(\theta\mid y)``; in either case responses
are then generated from ``p(y^{\mathrm{rep}}\mid\theta)``. The concurrent fitted
operation below is explicitly a **posterior predictive check**; passing a target
to `predictive_check` instead generates from the prior. Its report
stores `check_type="posterior_predictive"`, `parameter_source="fitted_posterior"`
and `prior_predictive_performed=false`. Reweighting a prior in a sensitivity
analysis is also distinct from generating prior predictive responses.

### Prior predictive responses before fitting

```julia
# target = getdesign(input; prior=:steps, interaction=:full)
prior_check = prior_predictive_check(target; ndraws=100, seed=42)
# Equivalent unified entry: predictive_check(target; ndraws=100, seed=42)
prior_check.check_type                 # "prior_predictive"
prior_check.data_used_to_estimate_parameters  # false
prior_check.rows                       # 202 replicated-count summaries
prior_receipt = save_report("prior-predictive.json", prior_check; return_receipt=true)
prior_reopened = load_report(prior_receipt.path; expected_sha256=prior_receipt.sha256)
```

The count `100` illustrates the operation, not a precision recommendation. Every
replication draws one complete joint-prior parameter vector and one response
table. Effects for the supplied roster are redrawn from the prior; assignment,
category support and presentation histories remain fixed. This is different
from the posterior check's conditioning on fitted effects. The normalized
Gaussian, half-normal and LKJ prior components are sampled in the effective
coordinates of the existing target, including their induced dependence.

The current target constructor requires a complete valid response table. Its
responses provide observed comparisons only: changing responses while retaining
the design/prior leaves seeded prior replications unchanged. This supports
checking a specified prior before fitting on an existing design, not an API for
a response-free future design. A prior chosen using those data is still
data-informed; `data_used_to_estimate_parameters=false` describes the generator,
not the provenance of the analyst's prior choices.

`mean` summarizes replicated counts; `conditional_expected_mean` averages the
sum of category probabilities over prior draws. They estimate the same expectation
but the probability calculation omits response-generation noise. Their sample
variances/quantile ranges are different; only replicated-count ranges appear in
`lower`/`upper`. Original probability-only prior audits should not be presented
as distributions of replicated counts.

Prior draws are independent, so mean/CDF MCSE uses the sample standard deviation
divided by the square root of the draw count, not MCMC chain diagnostics. A constant
sample has unavailable precision unless support makes the event certain. Discrete
endpoint CDF screens have the same descriptive limitations noted below; more
draws may be needed. Observed values inside broad prior ranges do not establish
a suitable prior, and outside flags are not a prior-selection rule. Shared report
saving retains explicit prior provenance and all limitations. Neither check
chooses a scientific default or certifies model adequacy.

### Exact seeds and saved report versions

Both concurrent predictive reports now use schema version 2. Seeds are decimal
strings so large integers survive JSON normalization exactly; use
`parse(Int, report.seed)` to reuse the original seed in the same source/environment.
The RNG and Julia version are retained; identical seeds do not promise identical
streams across Julia/dependency versions. Posterior v1 reports remain readable,
but their large stream seeds may have been rounded during serialization. Preserve
those reports and original results; do not claim exact regeneration from the
rounded fields. The v2 representation repairs provenance without changing the
model, prior or response-generation law.

### Posterior predictive responses after fitting

```julia
# result is a fitted ConcurrentWorkflow.Fit in its generating environment.
check = predictive_check(result; seed=42, conditioning=:existing_levels)
check.check_type
check.posterior_fit_qualified  # Qualification of the fitted posterior only
check.rows                    # Marginal and A/C joint replicated counts
check.joint                   # Maximum joint-cell discrepancies
check.discrete_endpoints_unresolved
receipt = save_report("posterior-predictive.json", check; return_receipt=true)
reopened = load_report(receipt.path; expected_sha256=receipt.sha256)
```

`posterior_predictive_check(result; seed=42)` calls the same implementation.
Every retained joint posterior state generates one complete response table;
all channels and events share that state. Do not multiply separately averaged
channel probabilities: the shared state carries posterior predictive dependence.
The model retains its original multiplier **1**, 9/9/2 supports and higher-is-adverse
direction; binary category 1 is correct transcription and category 2 is error.
Preliminary and additional study denominators are reported separately.

Existing effects, allocation and presentation histories remain conditioned on.
This does not generate new listeners, recording populations or held-out responses.
Replicated count intervals describe response variability, not intervals for
expected category probabilities. The 202 summaries cover marginal categories
and A/C joint cells; dependence involving the binary channel and repeated-profile
residual patterns are outside this bounded check.

Mean and inclusive-tail MCSE preserve the original chain order and response
generation noise. A constant chain gives unavailable MCSE unless the event is
known analytically from support (such as count ≥ 0). Integer count intervals use
the inverse empirical CDF. Endpoint precision is a pointwise two-MCSE screen of
the CDF immediately below and at each endpoint, **not quantile MCSE** or a
simultaneous confidence guarantee. Unresolved endpoints remain visible. Maximum
discrepancy interval precision is not computed. Predictive tail areas and outside
flags are descriptive; favorable values do not certify scientific adequacy or
erase failed posterior diagnostics.

If you already hold an intact concurrent probability/contrast report for the
same fit, pass `qualification_report=that_report` to reuse its whole-fit
diagnostics. The content seal and fit identity are checked; source-report warnings
retain their own scope. Otherwise those diagnostics are computed once. All
retained draws are used; generation cost grows with retained states × events.
Only count/discrepancy arrays are accumulated, without a retained response cube.
The computed report stores seeds and draw identities; generating native fits
still require their original source/environment. No migration is provided.

## Probabilities, the eight study contrasts and the ENG reference panel

For a declared parameter point, use the same lifecycle verbs as other models:

```julia
observed = event_probabilities(target, q; rows=[1, 2])
observed.rows[1].probabilities  # three vectors: 9, 9, 2 categories
observed.rows[1].correct_probability  # binary category 1
comparisons = contrast(target, q)
comparisons.comparisons[1].difference.probabilities
reference = event_probabilities(target, q; panel=:eng_reference)
reference.recordings
reference.speakers
receipt = save_report("probability-contrasts.json", comparisons)
restored = load_report(receipt.path; expected_sha256=receipt.sha256)
```

`rows` indexes the target's sorted events, not the original CSV. Every returned
row retains its event/rater/token IDs and both target and source row numbers.
Omitting `rows` evaluates all existing events. This is conditional prediction at
existing levels and histories, not held-out prediction with effects integrated out.

`contrast(target, q)` uses the original eight definitions:

| Left minus right | Averaging rows on each side |
| --- | --- |
| JPN natural minus ENG natural | preliminary rows in each condition |
| JPN accented minus ENG natural | preliminary rows in each condition |
| CHN natural minus ENG natural | preliminary rows in each condition |
| CHN accented minus ENG natural | preliminary rows in each condition |
| JPN accented minus JPN natural | preliminary rows in each condition |
| CHN accented minus CHN natural | preliminary rows in each condition |
| Block 4 minus block 1 | preliminary rows in each block |
| Trials 51–100 minus trials 1–50 | preliminary rows in each half |

The adapter requires each preliminary listener's complete 100-trial protocol,
with 20 observations per condition. Each side receives equal row weights; the
same preliminary listeners occur on both sides. Additional-study rows have zero
averaging weight. They can still inform the shared parameters in a joint
fit. The actual 222-listener design has 4,440 rows per condition, 5,550 per block
and 11,100 per half. The reported differences use the **same parameter point**
on both sides. These observed-assignment/history averages do not isolate causal
language or time effects. All categories are retained; a positive correctness
difference means better transcription, whereas higher ordinal categories mean
more difficulty. Expected ordinal ratings are descriptive numeric-score summaries.

`panel=:eng_reference` has a different estimand: each known ENG recording is
predicted for all preliminary listeners with equal listener weights, at block 1,
within-block position 13 (centered time zero), previous condition ENG-natural and
both log lags zero. All fixed predictors are zero in this declared context.
Each ENG speaker-style profile then averages its recordings over words equally.
The original data produce 450 recording profiles and nine speaker-style profiles,
using 222 listeners and 50 words. This context need not have occurred jointly.
The 200 additional-only recordings receive `cross_study_extrapolation=true`;
`observed_preliminary_listeners` describes identity coverage, not coverage of
the standardized context. Existing listener–word pairs must have been observed.
The operation does not predict new listeners or new words, and it does not
establish invariance of shared recordings across studies. Additional listeners
are excluded from the reference population. Average probabilities first;
probabilities at a mean latent location generally give a different result.

These reports have `kind="fixed_parameter_point"`, `posterior=false` and no
intervals or MCSE. They bind model/input, parameter-point digest, producer and
environment; the parameter vector itself is not stored. Retain the parameter
point separately when reproduction is needed. `save_report` refuses overwrites
and checks content and semantic consistency. `load_report` requires the separate
SHA-256 receipt and preserves the original producer metadata. A checksum detects
changes; it does not authenticate a producer or establish statistical validity.
A successful fixed-point calculation is not a fit, posterior contrast or scientific
acceptance. Use the concurrent fitted workflow below to obtain joint draws and
assess their numerical precision. Raw population-component reconstruction remains
separate and unavailable.

## Concurrent fitting and posterior precision

Use a new output directory and explicit iteration counts and seed:

```julia
plan = prepare_fit(target; ndraws=1000, warmup=1000, chains=4, seed=29)
fit_report(plan)  # inspect controls, source bindings and array storage estimates
result = fit(plan; directory="concurrent-fit")  # performs inference
# Alternatively: fit(target; directory=..., ndraws=..., warmup=..., seed=...)
qualification = qualify(result)
diagnostics(result)
contrast_report = contrast(result)
probability_report = event_probabilities(result; rows=[1, 2])
# Explicitly request this potentially expensive standardized panel:
reference_report = event_probabilities(result; panel=:eng_reference)
receipt = save_report("concurrent-contrasts.json", contrast_report)
restored_report = load_report(receipt.path; expected_sha256=receipt.sha256)
save_fit("concurrent-fit.jls", result)
restored_fit = load_fit("concurrent-fit.jls")
```

The iteration counts above illustrate syntax; they are not a precision guarantee
or a selected empirical fit. This experimental route reuses the existing analytic
NUTS target and AdvancedHMC's standard diagonal-metric adaptation. Defaults are
`target_accept=.9`, `max_depth=10`, `step_size=.03`, and `init_jitter=.1` around
`initial_params(target)`; `initial` may be supplied explicitly. Seeded normal
jitter gives distinct starting points but does not establish exploration across
posterior modes. The likelihood multiplier remains one and the declared prior
and Gaussian reduction are unchanged. Inspect `sampler_controls(result)`.

`fit_report(plan).adaptation_plan` reports the installed adaptor version, actual
window schedule and whether step size and mass matrix will be learned separately.
With AdvancedHMC 0.8.5 defaults, 100 or 149 warmup iterations give no metric update;
150 gives one, which is not a claim of sufficient adaptation. Short/zero warmup
remains allowed with a warning when a diagonal request retains the initial identity
metric. No windows, defaults or iteration counts are silently changed.

`sampler_controls(result).adaptation` retains observed metric-change iterations,
the final **inverse** mass diagonal and retained step size for each completed
chain. The existing observation callback copies metric values after adaptation;
these records are preserved in native fits and new computed reports. Planned
update boundaries and observed numeric changes are distinct. This compact record
is not a sampler checkpoint, a posterior covariance estimate or a convergence
criterion. Older computed reports may omit it and keep their original metadata.

Chains run serially by default. Start Julia with `--threads=2`, then pass
`chain_execution=:threads, max_parallel_chains=2` to `prepare_fit` (or directly to
`fit`) to run at most two chains together. The effective worker count is the minimum
of the cap, planned chains and available default-pool Julia threads; with one thread,
the threaded request still runs only one worker. Inspect `fit_report(plan).execution`
before fitting and `sampler_controls(result).execution` afterward. Computed posterior
reports preserve the same execution metadata. Each chain uses its prepared seed in
either mode, with separate targets, sampler workspaces and adaptation observations.
Scheduling alone does not change the per-chain random stream in the same environment.
Parallelism increases live workspace and does not guarantee speedup or qualification.

`progress=true` uses one monitor for all chains. A fresh `SamplingProgress` can also
be supplied; its percentage counts transitions, not convergence or persistence.
If a worker fails, queued work stops, active samplers observe cancellation at their
transition boundaries, and all workers finish or cancel before the error returns.
Already completed chains are preserved. There is no automatic fit resumption.

Successful chains publish the validated returned file as the completed file,
without retaining a second full copy. Validation or publication failures retain
the returned record for diagnosis. The directory retains the plan and each started, completed or failed
chain. There is no automatic retry, iteration extension or MCMC resumption.
`load_fit("concurrent-fit"; require_complete=false)` inspects completed chains
after an interruption. `qualify` marks such a result incomplete; posterior reports
require all planned chains. Native files are for trusted input in the original
source/Julia/Project/Manifest environment. Portable computed reports preserve
producer metadata and can be read without replaying native samples.

`posterior_summary(result; scale=:model, parameters=...)` and `posterior_mcse`
inspect named effective coordinates returned by `parameter_names(result)`.
Use `scale=:raw` for primitive coordinates. Effective effects are not recovered
original population components. `diagnostics` checks all primitive and effective
model coordinates, including nonlinear scales/correlations, plus sampler and
warmup telemetry. Structurally zero additional-listener L1 coordinates and absent
pair effects are distinguished from accidentally constant sampled quantities.

`contrast(result)` evaluates left, right and difference in every same joint draw.
Its `.rows` names identify contrast number, side, outcome and category; `.definitions`
retains the original labels, populations, signed weights and denominators.
`event_probabilities(result; rows=...)` requires an explicit existing-row selection;
its reference-panel alternative retains the recording/speaker IDs and extrapolation
flags. Means and pointwise equal-tailed intervals describe conditional category
probabilities, not response prediction intervals. The 9/9/2 supports and category-1
correctness keep their original meanings. Expected scores are descriptive.

Each row retains mean and quantile MCSE and rank/ESS diagnostics. Default limits
are R-hat ≤1.01, bulk/tail ESS ≥400, at least four chains, zero retained divergences
or maximum-depth hits, and E-BFMI ≥0.3. Probability mean/quantile MCSE must be ≤0.005;
expected-score MCSE must be ≤0.02. The mean, median and both interval endpoints
are checked. Missing MCSE, degenerate sampled quantities and incomplete telemetry
cannot pass. `numerical_qualified` combines whole-fit diagnostics and all requested
focal diagnostics/precision. A good focal result never removes a whole-fit warning.
Numerical qualification is not prior adequacy, model adequacy, linking invariance
or evidence for a particular number of constructs.

Report computation uses complete joint draws and can consume substantial memory
and time. `fit_report(plan)` gives raw draw, effective-model and focal matrix byte
counts, excluding object overhead, sampler workspace and temporary copies; they
are not peak RAM predictions. The actual full pair target needs about 399 MB per
1,000 joint primitive draws. Source/model checks and reporting populations are
prepared once per report, while parameter-dependent probabilities are evaluated
in each draw. Save a computed report to avoid repeating its diagnostics and MCSE.


### Experimental sampler coordinates

For a full listener–word covariance, `prepare_fit(...; parameterization=:pair_132)`
selects an alternative Gaussian factor chart. The default remains `:native`.
This changes computational coordinates while preserving the joint model and prior;
it is not a different psychological outcome ordering. Improved mixing, precision
or runtime is not established by correct derivatives or local curvature checks.

Supply `initial` in the target's ordinary native coordinates. The prepared center
is converted once; jitter and metric adaptation operate in the selected sampler
coordinates. `fit_report(plan).coordinates` and `sampler_controls(result).coordinates`
record these choices. Retained raw draws stay in sampler coordinates, with rotated
columns named `pair_q_132[...]`; model summaries and every probability/contrast
operation convert each joint draw before using the original reporting kernel.
`coordinates(result, q)` inspects effective-model effects from a sampler vector;
`logposterior(result, q)` and `logdensity_and_gradient(result, q)` evaluate the
stored sampler chart. A target returned by `getdesign(result)` still uses native
coordinates. Do not pass transformed raw vectors directly to that target.

Native files retain chart metadata and source/environment bindings. New portable
posterior reports use schema v2 and retain the experimental warning. Existing v1
computed reports remain readable with their checksums; this does not migrate
historical native chains to the current source. Non-full pair models reject the
132 option. Numerical qualification and focal precision requirements are unchanged.
