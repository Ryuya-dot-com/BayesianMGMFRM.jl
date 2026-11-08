module FirstIRTAnalysis

using BayesianMGMFRM
using BayesianMGMFRM: JSON3

"""Prepare fixed binary responses and explicit Rasch settings without fitting."""
function inputs()
    responses = include(joinpath(@__DIR__, "first_irt_responses.jl"))
    data = FacetData(responses; person=:person, item=:item, score=:score,
        rater=nothing, category_levels=0:1)
    validation = validate_design(data)
    validation.passed || error("Resolve design errors before fitting: $validation")
    spec = mfrm_spec(data; validation_report=validation)
    prior = MFRMPrior(person_sd=1.5, item_sd=1.0, rater_sd=1.0, step_sd=1.0)
    controls = (; backend=:advancedhmc, chains=4, warmup=1000, ndraws=4000,
        seed=2026102609, init=zeros(length(getdesign(spec).parameter_names)),
        init_jitter=.1, step_size=.05, target_accept=.9, max_depth=10,
        max_energy_error=1000.0, metric=:diagonal, ad_backend=:ForwardDiff,
        progress=false)
    return (; data, spec, prior, controls)
end

"""Read joint-posterior summaries and numerical precision without new random draws."""
function result(fitted, prepared=inputs())
    fitted isa MFRMFit || throw(ArgumentError("This example requires a scalar MFRM fit."))
    design_identity(fitted.design) == design_identity(getdesign(prepared.spec)) ||
        throw(ArgumentError("The saved fit does not match these responses and model."))
    fitted.prior == prepared.prior || throw(ArgumentError("The saved fit uses a different prior."))
    check = diagnostics(fitted; view=:public, rhat_threshold=1.01, ess_threshold=400)
    summaries = posterior_summary(fitted; lower=.025, upper=.975)
    errors = posterior_mcse(fitted; probabilities=(.025,.5,.975))
    focal = map(("person[P001]", "item[I02]", "item[I03]")) do name
        s = only(filter(r -> r.parameter == name, summaries))
        m = only(filter(r -> r.parameter == name, errors))
        lo, hi = first(m.quantiles).mcse, last(m.quantiles).mcse
        available = m.mcse_status === :available &&
            all(x -> x isa Real && isfinite(x) && x >= 0, (m.mean_mcse,lo,hi))
        qualified = check.summary.passed && available &&
            m.mean_mcse <= .01 && max(lo,hi) <= .03
        (;parameter=name, mean=s.mean, lower=s.lower, upper=s.upper,
            mean_mcse=m.mean_mcse, lower_mcse=lo, upper_mcse=hi, qualified)
    end
    return (;question="How difficult are I02 and I03 relative to I01?",
        origin="fixed artificial binary responses; not a recovery study",
        observations=prepared.data.n, model="Unit-logit binary Rasch; I01 fixed at zero; no rater facet",
        interval_probability=.95, unit="logit", focal,
        numerically_qualified=all(r -> r.qualified, focal),
        diagnostics=check.summary,
        mcse_limits=(;mean=.01, endpoint=.03),
        interpretation="Positive item values mean harder than I01. Intervals including zero leave the direction unresolved. Check numerical qualification before interpreting; three items give limited person information.")
end

"""
    FirstIRTAnalysis.main(args=String[]; output_parent="results/first_irt_analysis")

Fit once and save the artificial example, or review a trusted cache using
`["--saved-fit", "path/to/fit.jls"]` without fitting. Including this file runs
neither generation nor inference. `inputs()` only prepares the input/model.
"""
function main(args=String[]; output_parent="results/first_irt_analysis")
    (isempty(args) || (length(args)==2 && args[1]=="--saved-fit")) ||
        throw(ArgumentError("Usage: first_irt_analysis.jl [--saved-fit path/to/fit.jls]"))
    prepared = inputs()
    out = mktempdir(mkpath(output_parent); prefix="analysis-", cleanup=false)
    fitted = isempty(args) ? fit(prepared.spec; prior=prepared.prior, prepared.controls...) :
        load_fit_cache(args[2])
    cache = joinpath(out,"fit.jls")
    save_fit_cache(cache, fitted)
    println("Saved fit: ", abspath(cache)); flush(stdout)
    answer = result(fitted, prepared)
    open(io -> JSON3.write(io, answer), joinpath(out,"answer.json"), "w")
    println(answer.question)
    for row in answer.focal
        println(row.parameter, ": mean = ", round(row.mean;digits=3),
            "; 95% interval = [", round(row.lower;digits=3), ", ",
            round(row.upper;digits=3), "]; numerical checks: ", row.qualified)
    end
    println(answer.interpretation)
    return (;directory=out, answer)
end

end

if abspath(PROGRAM_FILE) == @__FILE__
    FirstIRTAnalysis.main(ARGS)
end
