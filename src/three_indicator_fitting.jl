include("three_indicator/three_indicator_workflow.jl")
const W = ThreeIndicatorWorkflow

"""
    prepare(input; prior, controls, chain_seeds, focal, initial_points=nothing)
    prepare(path; expected_sha256, prior, controls, chain_seeds, focal,
            initial_points=nothing)

Check the no-state 9/9/2 input and bind four-chain settings, named focal
quantities and the exact environment without running a sampler.
Warn when a listener contrast's position lies outside that listener/L1's
observed range or that context has no observations. Use `report(plan)` for
the ranges and counts. These marginal checks do not certify joint covariate
overlap, identification or causal comparability. Extrapolation remains allowed;
the requested contrast is not changed.

Explicitly declare `prior=:reference`, `:steps` or `:combined`.
`:steps` sets the two ordinal common-step mean vectors to -2:4/7:2,
with unit Gaussian SD before centering; it does not impose step ordering.
`:combined` also changes ordinal intercept SD from 2 to 1 and ordinal
fixed-coefficient SD from 1 to 0.5. Binary, cohort, covariance, slope and
listener step-deviation priors remain unchanged. These are explicit
application-specific choices, not generally recommended priors.
`report(plan).prior` records every prior setting in outcome order.

The original reference tuple is also accepted:
`(sd_scale=(1.,1.,1.,.5,.5,.5), step_sd_scale=.5, slope_log_sd=.3,
intercept_sd=2., cohort_sd=1., beta_sd=1., lkj_eta=2.)`.
It is an implementation reference, not a recommended empirical prior.
Custom numerical settings are not supported.

`controls` contains `ndraws`, `warmup`, `step_size`, `target_accept`, `max_depth`,
`metric=:diagonal`, `ad_backend=:ForwardDiff`, in that order.
Supply four distinct integer `chain_seeds`. `focal` declares `panel_label`,
`events`, `weights`, `speaker_pairs` and `listener_pairs`; see the example.
Intervals are fixed at 95%, with probability MCSE limits 0.005 and other limits
0.02. These numerical limits are distinct from practical-effect thresholds.

Four deterministic dispersed starts are supplied unless four raw coordinate
vectors are given. A retained Project/Manifest is required; source, environment
and thread settings bind later operations. A valid plan is not identification,
prior suitability or scientific acceptance.
"""
function prepare(input; prior, controls, chain_seeds, focal, initial_points=nothing)
    inspect_input(input)
    prior=W.M.resolve_prior(prior)
    body=Dict(String(k)=>v for (k,v) in pairs(input))
    for key in ("X","l1_contrast","y","token_lookup")
        body[key]=[collect(row) for row in eachrow(_input_matrix(body[key],key))]
    end
    canonical=JSON3.read(JSON3.write(body))
    if initial_points===nothing
        t=W.M.Target(canonical;prior)
        initial_points=[W.M.initial(t)+.03sin.((1:t.size).+.4c) for c in 1:4]
    end
    plan=W.prepare(canonical;controls,chain_seeds,focal,initial_points,prior)
    for warning in _support_warnings(_listener_support(canonical,plan.focal))
        @warn warning
    end
    plan
end

"""
    report(plan::NamedTuple)

Inspect a prepared three-outcome plan without sampling. Return the named
listener contrast positions, each listener/L1's observed count and range,
and warnings for extrapolation or unobserved contexts. Validate the original
source/environment binding first. Range endpoints are included; an empty
context has `nothing` bounds and status `:unobserved_context`.

This is a marginal position check, not joint covariate overlap, likelihood
identification, causal comparability or a posterior report. No contrast is
changed and no rank or numerical qualification is assigned.
"""
function report(plan::NamedTuple)
    t=W.check_plan(plan)
    rows=_listener_support(t.data,plan.focal)
    (;kind=:prepared_plan,api=contract(),focal_definitions=plan.focal,
      metadata=t.data.metadata,prior=W.M.prior_record(t.prior),listener_support=_support_view(rows),
      warnings=_support_warnings(rows),scientific_acceptance=false)
end
function prepare(path::AbstractString;expected_sha256,kwargs...)
    prepare(JSON3.read(_read(path,expected_sha256));kwargs...)
end

"""Native chains and their bound plan. Construct through `fit` or `load_fit`."""
struct NativeFit
    saved::NamedTuple
    function NativeFit(saved::NamedTuple)
        t=W.check_plan(saved.plan)
        _require(saved.plan.kind===:posterior,"a posterior plan is required")
        ids=[c.chain for c in saved.chains]
        _require(issorted(ids) && length(unique(ids))==length(ids),"ordered distinct chains required")
        foreach(c->W.check_chain(saved.plan,c;t),saved.chains)
        new(saved)
    end
end

"""
    fit(plan; directory)

Run four serial AdvancedHMC NUTS chains. This call performs inference.
Use one Julia thread and one BLAS thread; the declared source and environment
must still match. `directory` must not exist. Preserve the plan, starts,
returned/completed chains and failures there. Failed attempts are not retried,
extended or resumed automatically. Inspect numerical warnings with `summarize`.
"""
function fit(plan::NamedTuple;directory::AbstractString)
    W.check_plan(plan)
    _require(plan.kind===:posterior,"a posterior plan is required")
    NativeFit(W.run_chains(plan,directory;sampling_authorized=true))
end

"""
    load_fit(directory; require_complete=true)

Restore trusted local native chains from this fitting interface in their
original source/environment. Check identities, settings, telemetry and retained
densities. Julia Serialization must only be used with trusted files; checks
after deserialization do not make untrusted files safe.

This is not migration of historical private archives or cross-environment
loading. `require_complete=false` exposes completed chains of an interrupted
attempt through `result.saved`; an incomplete result cannot be summarized.
It never resumes sampling or overwrites a failure.
"""
function load_fit(directory::AbstractString;require_complete=true)
    _require(require_complete isa Bool,"require_complete must be Boolean")
    NativeFit(W.load_completed(directory;require_complete))
end

"""
    summarize(fit)

Compute a `SavedReport` from four complete chains without random generation.
Preserve the plan's panel, contrasts, 95% intervals, MCSE and all numerical
warnings, including listener position support. Range warnings do not change
numerical qualification. This can be more expensive than reading an already computed report.
Use `report` to inspect it and `save_report` to share it. No engine comparison
or new contrast is created. Numerical qualification is not scientific acceptance.
"""
function summarize(fit::NativeFit)
    result=W.report(fit.saved)
    text=JSON3.write(W.B._json_export_value(result))
    SavedReport(text,_digest(text),nothing,nothing)
end
