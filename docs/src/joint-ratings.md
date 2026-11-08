# Shared-response Joint Ratings

Use `BayesianMGMFRM.Experimental.JointRatings` when two criteria assess the same
produced response and their dependence matters. For example, a learner answers
a task, two raters assess that recording, and each assesses accuracy and fluency.
The learner, physical task, recording, rating event and criterion have different
roles. A second recording of the same learner answering the same task is a new
response, not a new person or task.

!!! warning "Local experimental candidate"
    This interface is available in this candidate, not the published preview or
    a stable release. Packaging does not establish scientific acceptance.
    Existing short saved fits remain unqualified. A four-category new-response
    score also retains unresolved quadrature order agreement. Inspect the
    source diagnostics and numerical qualification flags before interpretation.

Start with the [experimental model guide](experimental.md) for the broader model
catalogue. This is one bounded composition, not a generic selector for every
MFRM/GMFRM/MGMFRM, mixed-category, five-facet or three-dimensional model.

The shared constructor `Experimental.joint_rating_spec(...; association=:none)`
selects this target. It supports fitting, design summaries and mathematical
inspection. Shared `prior_draw`, `simulate`, and `prior_predictive_check` are
not implemented for this route; their availability for `association=:star`
does not extend to it. Supplying an additional metadata column also does not
add an estimated effect. Numeric `predictor_columns` enter the location only
with the corresponding explicit coefficient priors. Their meaning and coding
must be retained with the analysis: native records preserve predictor names
and values, but do not preserve arbitrary source columns such as occasion labels.

For explicit criterion means, estimated person SDs and additional within-event
ordinal association, use the separate [OrdinalAssociation route](ordinal-association.md).
Its priors, target and sample files differ from the route described on this page.

## Open a saved analysis

```julia
using BayesianMGMFRM, JSON3
const J = BayesianMGMFRM.Experimental.JointRatings

J.contract()
saved = load_fit("joint-samples.jls")
parameters = posterior_summary(saved; lower=.005, upper=.995, intervals=(.99,))
parameters.model.prior
parameters.result.posterior
parameters.result.raw_diagnostics
parameters.result.model_diagnostics
parameters.result.mcse
parameters.result.sampler

save_report("joint-parameters.json", parameters)
reopened = JSON3.read(read("joint-parameters.json", String)).data
reopened.result.sampler
```

These are JointRatings-specific records and reports. Use `J.load_result` and
`J.report`; the common `load_fit_cache` and `fit_report` recipes for the other
eight result types do not accept these records.

Use trusted native files and their original Julia/dependency environment.
Native serialization is for lossless replay in that environment, not arbitrary
cross-version transfer. JSON preserves a readable report and its warnings;
it cannot supply posterior draws for another calculation. An explicit
`nonfinite` object preserves a diagnostic NaN/Inf, while `missing` becomes null.
Saving refuses to overwrite existing files. No sampler runs when loading,
reporting, contrasting, predicting or scoring.

`report`, `contrast`, `predict` and `score` return the model specification, target identity,
source sample identity and API boundary alongside the calculation in `.result`.
Native saves retain the original sample schema and content identity, so earlier
trusted sample files can be validated without conversion. Original payloads
retain their experimental/non-accepted status fields.

## Name the rating unit and scale

Supply observed rows as named tuples:

```julia
row = (observation_id="obs-1", person="learner-1", task="task-1",
       response_id="recording-1", rating_event_id="assessment-1",
       rater="rater-1", criterion="accuracy", score=2)
criteria = (
    (criterion="accuracy", levels=1:4 |> collect,
     direction=:higher_is_more, threshold_group="accuracy"),
    (criterion="fluency", levels=1:4 |> collect,
     direction=:higher_is_more, threshold_group="fluency"),
)
```

| Field | Meaning |
| --- | --- |
| `observation_id` | Unique observed score |
| `person`, `task` | Learner and physical task |
| `response_id` | One production by that person on that task |
| `rating_event_id` | One assessment by one rater of one response; multiple criteria may share the event |
| `rater`, `criterion` | Known rater and named criterion |
| `score` | Raw integer category, encoded in the declared direction exactly once |

Declare all possible categories, including unused ones. For `:higher_is_less`,
an increasing raw category label represents a decreasing canonical score.
Both criteria need the same number of categories, although raw labels may
differ. Matching `threshold_group` values share a step vector; different groups
estimate different vectors. Missing and recused ratings are omitted. Duplicated
observations, conflicting response ownership or event ownership are rejected.
At least two persons, tasks and raters and both criteria per person are required.
These checks do not establish adequate overlap, covariance identification or
precision for a study.

## Model and explicit prior

The adjacent-category log odds use unit logits:

```math
\log\frac{P(Y_n=k)}{P(Y_n=k-1)}
= \theta_{p(n),c(n)} - b_{t(n),c(n)} - s_{r(n),c(n)}
  + u_{o(n),c(n)} + x_n^\mathsf{T}\beta - \tau_{g(c(n)),k}.
```

Each person's two abilities have unit marginal SD and an estimated correlation.
Task effects are criterion-specific normal effects. Rater effects sum to zero
within each criterion; step vectors sum to zero within each threshold group.
Response effects are bivariate normal with estimated marginal SDs and correlation.
The two correlation priors are explicit LKJ priors using stable Cholesky
coordinates and transformation Jacobians. Response log-SDs have normal priors.
The coefficients of ability, task, severity and response are fixed at one;
estimated item discrimination and rater consistency are not part of this model.
Criterion-specific task locations have proper priors; a full-rank predictor
matrix alone does not identify every additive component from the likelihood.

```julia
# Illustration only: these numbers are not recommended scientific defaults.
prior = (task_sd=.5, rater_sd=(.5,.5), step_sd=(.5,.5),
         response_log_sd_mean=(-1.,-1.), response_log_sd_sd=(.5,.5),
         beta_sd=(), person_lkj_eta=2., response_lkj_eta=2.)
# ratings must contain the full observed panel, not only the single row above.
model = J.model(ratings; criteria, prior)
```

Vectors follow sorted criterion/threshold-group IDs. Predictor columns follow
the explicit `predictor_columns` order and retain their input units. No intercept,
centering or scaling is inferred. Rater and step SDs are orthonormal contrast
kernel SDs: for a block of length `m`, each marginal variance is
`kernel_sd^2 * (1 - 1/m)`. A binary step block is fixed at zero.

`J.fit(model; ndraws, warmup, chains, seed)` explicitly starts Julia sampling.
Julia defaults to `ad_backend=:auto`, selecting the exact analytic gradient for
this target. Explicit `:ForwardDiff` and `:ReverseDiff` overrides remain available;
`result.run.controls.ad_backend` records the selected backend. For progress,
pass `progress=SamplingProgress(path="progress.json")` with a fresh path. Its
percentage counts transitions, including warmup; it does not measure convergence.
For the matched Stan backend, use `backend=:cmdstan` and
`compiled=J.verified_stan(native_check_directory)`. The native receipt and binary
must match the bundled source; no compilation or installation happens implicitly.
Sampling controls are computational choices, not model/prior choices. Inspect
diagnostics before interpretation, then use `save_fit(path, result)`.
Availability of a fitting backend does not establish recovery, SBC calibration
or adequate numerical precision for an application.

## Compare two people or raters within a criterion

To ask how two speakers differ on one construct, subtract their coordinates
within each joint posterior draw. Subtracting the endpoints of two marginal
intervals does not give a credible interval for their difference.

```julia
ability = J.contrast(saved; facet=:person, criterion="accuracy",
                     left="learner-1", right="learner-2", interval=.95)
severity = J.contrast(saved; facet=:rater, criterion="accuracy",
                      left="listener-1", right="listener-2", interval=.95)
ability.result.summary
severity.result.summary.precision
severity.result.source_diagnostics
save_report("severity-difference.json", severity)
```

Replace these illustrative labels with exact IDs in `saved.target`. Both IDs
must belong to the selected facet and the same criterion. Positive `left - right`
means more of the canonical trait for people, or greater severity for raters.
Greater severity lowers the canonical score, even when the criterion's declared
raw-score direction is reversed. The criterion definition travels with the
answer. Differences use unit logits, not rating points.

Read the equal-tailed interval together with its endpoint MCSE and the whole-fit
diagnostics. `sampling_warning` retains the existing diagnostic screen; its
thresholds are in `diagnostic_policy`. A small MCSE for this contrast cannot
remove warnings elsewhere in the fit. Focal precision is not automatically
qualified. Constant sampled events do not establish a zero MCSE. An optional
`rope=(lower, upper)` describes an inclusive region on the same unit-logit scale;
justify its bounds from the substantive question before interpreting its mass.

All original chains and paired draws are retained. The computed report records
the source identity, chain/iteration IDs and an evaluated-draw hash, and can be
saved and read using the JSON procedure above. No new fitting or random draws
occur. The result describes the fitted latent effects; it is not a difference in
raw score, a causal fairness judgment, or a prediction for a new recording.
Cross-criterion differences and other facets are not provided by this method.

## Predict probabilities or score a response

Prediction rows have the seven IDs and the fitted numeric predictor columns,
with **no score**. Observation and rating-event IDs must be new. Person, task,
rater and criterion must be known fitted levels.

- `response_effect=:existing` uses a fitted response and its estimated effect.
- `response_effect=:new` requires a new response ID and integrates its Gaussian
  response effect; it still conditions on known persons, tasks and raters.

```julia
probabilities = J.predict(saved, future_rows; response_effect=:new,
                          intervals=(.9,.99))
probabilities.result.columns       # original category labels and threshold owner
probabilities.result.posterior
probabilities.result.decisions     # source, integration and MCSE qualifications
save_report("joint-probabilities.json", probabilities)

# scored_rows additionally contains the raw observed/hypothetical integer score.
scores = J.score(saved, scored_rows; response_effect=:new)
scores.result.rows
scores.result.source_diagnostics
save_report("joint-scores.json", scores)
```

Probability intervals are equal-tailed credible intervals for category
probabilities, not outcome intervals or HDIs. Requesting 99% does not establish
accurate tail endpoints; MCSE and source diagnostics remain relevant.

Marginal row probabilities cannot be multiplied to obtain a joint response
probability. `score` multiplies conditional probabilities within a response,
integrates the shared effect, averages over posterior parameter draws, and
then takes the log. It also reports the different quantity, the posterior mean
log probability. Default integration orders `(16,32,64)` must agree within
`1e-5` nat for every draw in both final successive comparisons. Disagreement
remains visible and unqualified; agreement is not a certified error bound.
No draw is silently removed and no integration/sampling extension is automatic.

The reported sum is a sum of marginal response log scores. It is not a joint
probability for the whole dataset and has no aggregate MCSE or data-sampling SE.
Supplying scores does not make this heldout validation: whole-response training
exclusion, matched refits and comparison uncertainty require separate work.
Sparse rating allocations, mixed supports, unknown levels, further effects,
3D covariance, accepted scientific priors and reliable model selection remain
outside this integration's evidence.

## Executable saved-result example and help

`examples/joint_ratings_saved.jl` uses this namespace only; no prototype `include`
or dated repository folder is needed:

```sh
julia --project=. examples/joint_ratings_saved.jl --help
julia --project=. examples/joint_ratings_saved.jl joint-samples.jls request.json output.json
```

The JSON request has exactly `operation` (`"predict"` or `"score"`),
`response_effect` (`"existing"` or `"new"`) and `rows` (the schema above).
The example never fits a model or generates outcomes. Bring your own trusted
samples and request; private or historical research samples are not bundled.

In Julia, use `?BayesianMGMFRM.Experimental.JointRatings.predict` or
`@doc BayesianMGMFRM.Experimental.JointRatings.score`. All entry points are
listed in the [experimental API reference](api-experimental.md#Joint-ratings).
