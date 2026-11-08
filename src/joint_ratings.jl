"""
    BayesianMGMFRM.Experimental.JointRatings

Experimental two-criterion shared-response PCM workflow. A response is one
person's production on one physical task; a rating event is one rater's
assessment of that response. Their IDs are not interchangeable.

Use `model`, `fit`, `save_result`/`load_result`, `report`, `contrast`, `predict`, and `score`
through this namespace. `predict` returns marginal category probabilities;
`score` integrates ratings of the same response jointly. Read `contract()`
before use. This local API candidate has no scientific acceptance, stable API
guarantee, or general-purpose MGMFRM model-selection claim.
"""
module JointRatings

import BayesianMGMFRM as B
using JSON3
include("joint_ratings/numerics.jl")
include("joint_ratings/joint_rating_static.jl")
include("joint_ratings/joint_rating_workflow.jl")
include("joint_ratings/joint_rating_prediction_precision.jl")
include("joint_ratings/joint_rating_response_prediction.jl")
include("joint_ratings/joint_rating_response_score.jl")
const S = JointRatingStatic
const W = JointRatingWorkflow

"""
    contract()

Return this candidate's supported model, prediction and persistence boundaries.
Available operations are not evidence of convergence or scientific acceptance.
"""
contract() = (; status=:local_experimental_candidate, api_version=1,
    scientific_acceptance=false, stable_api=false, criteria=2,
    common_category_count=true, coefficients=:fixed_unit,
    person_marginal_sd=1., correlations=(:person, :response),
    threshold_owner=:declared_criterion_group, explicit_prior_required=true,
    known_person_task_rater_only=true, response_effects=(:existing, :new),
    intervals=:equal_tailed, hdi=false, heldout_validation=false,
    samplers=(:advancedhmc, :cmdstan), native_cache=:trusted_same_environment,
    json=:report_only, automatic_sampling=false)

"""
    model(rows; criteria, prior, predictor_columns=())

Validate a two-criterion PCM with shared response effects, fixed unit
coefficients, correlated person abilities and correlated response effects.
Rows are named tuples with `observation_id`, `person`, `task`, `response_id`,
`rating_event_id`, `rater`, `criterion` (nonempty strings), and integer `score`.
Each criterion declares `criterion`, increasing integer `levels`, `direction`
(`:higher_is_more`/`:higher_is_less`), and `threshold_group`. Declare the full
possible support, including unused categories. Both criteria need the same
category count. Missing/recused ratings are omitted, never converted to zero.

`prior` explicitly supplies `task_sd`, two `rater_sd`, one `step_sd` per sorted
threshold group, two `response_log_sd_mean`, two `response_log_sd_sd`, one
`beta_sd` per named predictor, `person_lkj_eta`, and `response_lkj_eta`.
Criterion vectors follow sorted criterion IDs. Rater/step SDs are Helmert
kernel SDs; response log-SDs have normal priors. Person marginal SDs equal one.
Numeric predictors retain their supplied units; no intercept is added.
At least two persons/tasks/raters and both criteria per person are required.
Validation does not establish covariance identification or adequate precision.
No fitting or random generation occurs here. See the Joint Ratings guide.
"""
model(rows; kwargs...) = S.Target(rows; kwargs...)

"""
    fit(model; backend=:advancedhmc, compiled=nothing, ndraws, warmup, chains,
        seed, target_accept=.9, max_depth=10, step_size=.03, init_jitter=.1)

Explicitly start sampling and retain raw draws, warmup, controls and warnings.
There is no automatic extension or accepted prior default. The `:cmdstan`
backend requires `compiled=verified_stan(directory)` from a matching successful
native finite check; it neither installs nor compiles Stan automatically.
Use `report` to inspect the result and `save_result` to preserve it.
Julia uses `ad_backend=:auto` to select the exact analytic gradient; explicit
`:ForwardDiff` and `:ReverseDiff` remain available. `run.controls.ad_backend`
records the selected backend. Julia also accepts `progress=SamplingProgress(...)`.
Available backends do not establish posterior accuracy or recovery performance.
"""
function fit(target::S.Target; backend::Symbol=:advancedhmc, compiled=nothing, kwargs...)
    if backend === :advancedhmc
        compiled === nothing || throw(ArgumentError("compiled is only for backend=:cmdstan"))
        return W.fit_julia(target; kwargs...)
    elseif backend === :cmdstan
        compiled === nothing && throw(ArgumentError("CmdStan requires verified_stan(directory)"))
        return W.fit_cmdstan(target, compiled; kwargs...)
    end
    throw(ArgumentError("backend must be :advancedhmc or :cmdstan"))
end

"""
    verified_stan(directory)

Verify a successful native-check receipt against the bundled Stan source and
the executable hash. Return the compiled descriptor required by `fit`.
No compilation, package installation or sampling occurs.
"""
verified_stan(directory::AbstractString) = W.verified_stan(directory)

"""
    save_result(path, result)

Validate and save a native sample record without overwriting an existing file.
Retains model, prior, raw draws, controls, diagnostics and content identities.
Use the original Julia and dependency environment for native replay.
"""
save_result(path::AbstractString, result) = W.save_result(path, result)

"""
    load_result(path)

Read a trusted native sample file and validate its model, content identity,
draws and retained densities. Native Julia serialization is not a portable
cross-version format and must not be used for untrusted files. Nothing is fit.
"""
load_result(path::AbstractString) = W.load_result(path)

function _report(result, operation, payload)
    return (; schema="bayesianmgmfrm.joint_rating_api_report.v1", operation,
        api=contract(), model=deepcopy(result.target),
        target_identity=result.target_identity,
        source_sample_content_hash=result.content_hash, result=payload)
end

"""
    report(result; lower=.05, upper=.95, intervals=(.9,))

Return model/prior metadata plus parameter summaries, raw/model diagnostics,
MCSE, sampler and warmup warnings in `.result`. For 99% equal-tailed intervals,
use `lower=.005, upper=.995, intervals=(.99,)`. These are not HDIs.
The report is descriptive and never upgrades an unqualified saved fit.
"""
report(result; kwargs...) = _report(result, :parameters, W.report(result; kwargs...))

# Also exercised with explicitly artificial coordinates; posterior provenance is
# checked by contrast before this extractor is called.
function _contrast_draws(t, draws; facet, criterion, left, right)
    facet in (:person, :rater) || throw(ArgumentError("facet must be :person or :rater"))
    all(S.J.nonempty_id, (criterion, left, right)) ||
        throw(ArgumentError("criterion and both IDs must be nonempty strings"))
    left != right || throw(ArgumentError("choose two distinct IDs"))
    c = findfirst(==(criterion), t.levels.criterion)
    c === nothing && throw(ArgumentError("unknown criterion"))
    ids = getproperty(t.levels, facet)
    a, b = findfirst(==(left), ids), findfirst(==(right), ids)
    (a !== nothing && b !== nothing) || throw(ArgumentError("unknown $facet ID"))
    values = Matrix{Float64}(undef, size(draws, 1), 2)
    for (i, q) in enumerate(eachrow(draws))
        v = S.coordinates(t, q)
        values[i, :] = facet === :person ? v.theta[c, [a, b]] : v.rater[[a, b], c]
    end
    return (;left=values[:, 1], right=values[:, 2],
        criterion=deepcopy(only(x for x in t.data.criteria if x.criterion == criterion)))
end

"""
    contrast(result; facet, criterion, left, right, interval=.90, rope=nothing)

Summarize a same-criterion person or rater difference, `left - right`, from a
trusted saved JointRatings result. Use `facet=:person` or `:rater` and exact
stored string IDs. All original draws retain their chain order and pairing.
The `.result.summary` contains an equal-tailed interval, mean/endpoint MCSE,
event probabilities and contrast diagnostics. An optional `(lower, upper)` ROPE
uses the same unit-logit scale; its bounds are inclusive.

A positive person difference means more of the criterion's canonical trait;
a positive rater difference means greater severity (lower canonical scores).
The declared raw-score direction is retained in `.result.criterion`. These are
latent effects, not raw-score differences or response-level predictions.
Across-criterion differences and other facets are unsupported.

Whole-source parameter, sampler and warmup diagnostics remain in
`.result.source_diagnostics`. `sampling_warning` uses the existing JointRatings
diagnostic screen; its thresholds are recorded, and passing it does not
establish focal MCSE adequacy or scientific acceptance. No refit or random draw
is made. Save with `save_report`; the JSON is a computed report, not a posterior
sample interchange format.
"""
function contrast(result; facet, criterion, left, right, interval=.90, rope=nothing)
    t = W.restore(result)
    values = _contrast_draws(t, result.run.draws; facet, criterion, left, right)
    summary = B.posterior_contrast(values.left, values.right;
        chains=result.run.controls.chains, interval, rope)
    source = W._source_diagnostics(t, result.run)
    P = JointRatingPredictionPrecision
    diagnostic_policy = (;P.POLICY.min_chains, P.POLICY.rhat_max,
        P.POLICY.ess_min, P.POLICY.ebfmi_min)
    source_ok = source.controls.chains >= diagnostic_policy.min_chains &&
        all(d -> P.diagnostic_ok(d, diagnostic_policy),
            [source.raw_diagnostics; source.model_diagnostics]) &&
        all(s -> s.n_divergences == 0 && s.n_nonfinite_logdensity == 0 &&
            s.n_max_treedepth == 0 && isfinite(s.e_bfmi) &&
            s.e_bfmi >= diagnostic_policy.ebfmi_min, source.sampler)
    payload = (;facet, left=String(left), right=String(right), criterion=values.criterion,
        operation=:difference, units=:unit_logit, interval_method=:equal_tailed,
        positive_difference=facet === :person ? :higher_canonical_trait : :greater_severity,
        summary, sampling_warning=!source_ok, diagnostic_policy,
        source_diagnostics=(;source.status, source.controls, source.raw_diagnostics,
            source.model_diagnostics, source.sampler, source.warmup, qualified=source_ok),
        parameter_chain_ids=copy(result.run.chain_ids),
        parameter_iterations=copy(result.run.iterations),
        evaluated_draws_hash=B._cache_hash((;values.left, values.right)),
        focal_precision_qualification=:not_assessed, scientific_acceptance=false, new_fits=0)
    return _report(result, :contrast, payload)
end

"""
    predict(result, rows; response_effect, intervals=(.9,.99),
        quadrature_atol=1e-8, quadrature_maxevals=10000, block_rows=8)

Return marginal category probabilities, equal-tailed intervals, MCSE and
source warnings in `.result`. Supply the seven IDs and fitted numeric predictor
columns, without scores. Observation/rating-event IDs must be new. Known
person/task/rater/criterion levels are required. `response_effect=:existing`
conditions on a fitted response; `:new` integrates a new response's Gaussian
effect. Another production by the same person on the same task needs a new ID.
Raw category labels and direction are retained. Intervals describe probability
uncertainty, not intervals for outcomes. Products of these marginals are not
joint probabilities. Uses deterministic quadrature, never predictive draws.
"""
predict(result, rows; kwargs...) = _report(result, :prediction,
    JointRatingResponsePrediction.report(result, rows; kwargs...))

"""
    score(result, rows; response_effect, orders=(16,32,64),
        log_order_tolerance=1e-5, log_score_mcse_limit=.01)

Return response-level log predictive densities and qualification flags in
`.result`. Rows have the same schema as `predict`, plus integer raw `score`.
For `:new`, jointly integrate the shared response effect before averaging
over posterior draws and taking logs. The posterior mean log probability is
reported separately. Failed integration order agreement and source warnings
remain; order agreement is not an error bound and no automatic extension occurs.
The sum is not a whole-dataset joint score. No heldout refits, data-sampling SE,
sum MCSE, predictive outcome draws or model-selection acceptance are supplied.
"""
score(result, rows; kwargs...) = _report(result, :score,
    JointRatingResponseScore.report(result, rows; kwargs...))

"""
    save_report(path, report)

Write a portable JSON report without replacing an existing file. Reopen with
`JSON3.read(read(path, String)).data`. NaN/Inf remain explicit `nonfinite`
objects; `missing` becomes null. Model/prior metadata, warnings, requests and
precision flags remain. JSON is a report, not a sample cache for new analyses.
"""
function save_report(path::AbstractString, report)
    (ispath(path) || islink(path)) && throw(ArgumentError("preserve existing report: $path"))
    report.schema == "bayesianmgmfrm.joint_rating_api_report.v1" ||
        throw(ArgumentError("expected a JointRatings report"))
    envelope=(;schema="bayesianmgmfrm.joint_rating_report_json.v1",
        encoding="NaN/Inf/-Inf use explicit nonfinite objects; missing is null. Use JLS for lossless replay.",
        data=W.jsonsafe(report))
    mkpath(dirname(path))
    mktemp(dirname(path)) do temporary, io
        JSON3.write(io, envelope)
        close(io)
        hardlink(temporary, path)
    end
    return path
end
include("joint_ratings/ordinal_association.jl")
import ..StarAssociation
end
