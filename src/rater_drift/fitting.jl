"""
    prepare(model; controls, chain_seeds, reference, panel_weights, epsilon,
            interval, precision, initial_points=nothing)

Bind the scalar RW1 or matched static target, four distinct chain seeds, fixed panel,
reference and precision limits before fitting. No sampler or generator runs.
`controls` is a NamedTuple with `ndraws`, `warmup`, `step_size`, `target_accept`,
`max_depth`, `metric=:diagonal`, `ad_backend=:ForwardDiff`, in that order.
`precision=(mean_mcse_max=..., endpoint_mcse_max=...)` gives positive absolute
MCSE limits in severity units, not scientific defaults. `epsilon` is the positive
practical-change tolerance; `interval` is the pointwise credible mass.

Four deterministic dispersed starts are supplied by default. For RW1, log
innovation SD starts near its prior mean. Alternatively supply four distinct finite Float64 raw
coordinate vectors. Preserve the returned plan and its explicit settings.
An explicit project and retained Manifest are required. Native records bind
the exact source, project, dependencies, Julia, platform and thread settings.
"""
function prepare(t::M.Target; controls, chain_seeds, reference, panel_weights,
        epsilon, interval, precision, initial_points=nothing)
    _require(t.static ? t.parameterization===:centered : t.parameterization===:noncentered,
        "use the static or noncentered scalar RW1 model")
    if initial_points===nothing
        initial_points=[[.1sin(j+.4c) for j in 1:M.L.dimension(t)] for c in 1:4]
        !t.static && foreach(q->q[end-t.R+1:end].+=t.mu_sigma,initial_points)
    end
    RaterDriftWorkflow.prepare(t; controls, initial_points, chain_seeds,
        reference, panel_weights, epsilon, interval, precision)
end

"""Retained static/RW1 chains and their bound plan; construct with `fit` or `load_fit`."""
struct NativeFit
    saved::NamedTuple
    function NativeFit(saved::NamedTuple)
        t=RaterDriftWorkflow.check_plan(saved.plan)
        _require(saved.plan.kind===:posterior && (t.static ? t.parameterization===:centered : t.parameterization===:noncentered),
            "a posterior static or noncentered RW1 plan is required")
        ids=[c.chain for c in saved.chains]
        _require(issorted(ids) && length(unique(ids))==length(ids),"ordered distinct chains required")
        foreach(c->RaterDriftWorkflow.check_chain(saved.plan,c;t),saved.chains)
        new(saved)
    end
end

"""
    fit(plan; directory)

Run four serial AdvancedHMC NUTS chains and return a `NativeFit`. This call
performs inference. Use one Julia thread and one BLAS thread. `directory` must
not exist. The plan, chain starts, returned outputs, completed chains and any
failure are retained there; existing outputs are never overwritten. A failed
attempt is not retried or extended. These files are not sampler checkpoints.
The target, controls and original environment must still match `prepare`.
"""
function fit(plan::NamedTuple; directory::AbstractString)
    t=RaterDriftWorkflow.check_plan(plan)
    _require(plan.kind===:posterior && (t.static ? t.parameterization===:centered : t.parameterization===:noncentered),
        "a posterior static or noncentered RW1 plan is required")
    NativeFit(RaterDriftWorkflow.run_chains(plan,directory;sampling_authorized=true))
end

"""
    load_fit(directory; require_complete=true)

Restore trusted local static/RW1 native chains written by `fit` in their original source
and dependency environment. Checksums, starts/seeds, iterations, telemetry and
every retained target density are checked. Julia Serialization is for trusted
files only; validation after loading does not make untrusted files safe.
This is not import of historical private chains or cross-environment migration.

With `require_complete=false`, inspect completed chains after a failed run via
`result.saved.chains` and `result.saved.plan`. An incomplete result cannot be
summarized. This operation does not resume sampling or replace failure records.
"""
function load_fit(directory::AbstractString; require_complete=true)
    _require(require_complete isa Bool,"require_complete must be Boolean")
    NativeFit(RaterDriftWorkflow.load_completed(directory;require_complete))
end

"""
    summarize(fit)

Compute a `SavedReport` from four complete static/RW1 chains without random generation.
Keep the plan's reference, interval, practical tolerance and panel weights.
Original joint-draw diagnostics and reports always remain available. Performance
and severity location marginals are also retained, with separate MCSE/diagnostic
flags. Their levels use prior anchoring. Static changes are structural zeros;
static severity levels remain uncertain. Location flags supplement, rather than
replace, the existing trajectory numerical gate.

Eligible isolated unrated interior bins receive conditional Gaussian-mixture
intervals when every chain supports the fixed batches 100, 200, 400 and 800
(at least ten batches of each size). Otherwise retain joint-draw intervals,
MCSE, numerical criteria and an explicit integration-status warning. This does
not extend a chain to improve its result. Numerical qualification is distinct
from coverage, reliable drift detection and scientific acceptance.
"""
function summarize(fit::NativeFit)
    # Revalidate mutable arrays before using a previously returned object.
    NativeFit(fit.saved)
    result=RaterDriftBridge.report(fit.saved)
    text=JSON3.write(B._json_export_value(result))
    SavedReport(text,_digest(text))
end
