module FirstMFRMAnalysis

using BayesianMGMFRM
using BayesianMGMFRM: JSON3

const MCSE_LIMITS = (; mean=.01, endpoint=.02)

"""Prepare the tutorial's fixed artificial data, model, prior and sampling settings; do not fit."""
function inputs()
    ratings = include(joinpath(@__DIR__, "first_analysis_ratings.jl"))
    data = FacetData(ratings; person=:person, item=:item, rater=:rater,
        score=:score, category_levels=0:3)
    validation = validate_design(data)
    validation.passed || error("Resolve the data-validation errors before fitting: $validation")
    spec = mfrm_spec(data; thresholds=:partial_credit, validation_report=validation)
    prior = MFRMPrior(person_sd=1.5, rater_sd=1.0, item_sd=1.0, step_sd=1.0)
    controls = (; backend=:advancedhmc, chains=4, warmup=1000, ndraws=1000,
        seed=2026101402, step_size=.05, init=zeros(length(getdesign(spec).parameter_names)),
        init_jitter=.1, target_accept=.9, max_depth=10, max_energy_error=1000.0,
        metric=:diagonal, ad_backend=:ForwardDiff, progress=false)
    return (; data, spec, prior, controls)
end

function numerical_checks_pass(diagnostics_passed, mcse)
    endpoints = (first(mcse.quantiles).mcse, last(mcse.quantiles).mcse)
    values = (mcse.mean_mcse, endpoints...)
    return diagnostics_passed && mcse.mcse_status === :available &&
        all(x -> x isa Real && !(x isa Bool) && isfinite(x) && x >= 0, values) &&
        values[1] <= MCSE_LIMITS.mean && all(x -> x <= MCSE_LIMITS.endpoint, endpoints)
end

function interpretation(qualified, lower, upper)
    !qualified && return "Numerical checks need attention. Do not interpret the severity contrast yet. The fit is saved for diagnosis; inspect diagnostics(fit) and posterior_mcse(fit)."
    lower > 0 && return "The 90% interval is above zero: these ratings support R2 being more severe than R1 under this model and prior."
    upper < 0 && return "The 90% interval is below zero: these ratings support R2 being less severe than R1 under this model and prior."
    return "The 90% interval includes zero: these ratings do not give a clear direction for the R2-R1 severity difference under this model and prior. This does not show that the raters are equivalent."
end

"""Read the tutorial's fitted contrast and numerical checks, without random draws or refitting."""
function result(fitted, prepared=inputs())
    fitted isa MFRMFit || throw(ArgumentError("This example needs a scalar MFRM fit."))
    design_identity(fitted.design) == design_identity(getdesign(prepared.spec)) ||
        throw(ArgumentError("The saved fit does not match the tutorial's ratings and model."))
    fitted.prior == prepared.prior || throw(ArgumentError("The saved fit uses a different prior."))
    check = diagnostics(fitted; view=:public)
    lower, upper = (1-.9)/2, (1+.9)/2
    summary = only(filter(r -> r.parameter == "rater[R2]",
        posterior_summary(fitted; lower, upper)))
    mcse = only(filter(r -> r.parameter == "rater[R2]",
        posterior_mcse(fitted; probabilities=(lower,.5,upper))))
    qualified = numerical_checks_pass(check.summary.passed, mcse)
    return (; question="Is R2 more severe than R1?",
        data=(; origin="fixed artificial teaching data", ratings=prepared.data.n,
            people=length(prepared.data.person_levels), items=length(prepared.data.item_levels),
            raters=length(prepared.data.rater_levels), categories=prepared.data.category_levels),
        model="One-dimensional partial-credit MFRM; R1 is the zero-severity reference",
        prior=(;person_sd=prepared.prior.person_sd,rater_sd=prepared.prior.rater_sd,
            item_sd=prepared.prior.item_sd,step_sd=prepared.prior.step_sd),
        parameter="rater[R2]", unit="logit", interval_probability=.9,
        mean=summary.mean, lower=summary.lower, upper=summary.upper,
        numerically_qualified=qualified,
        diagnostics=(;flag=String(check.summary.flag),
            max_rhat=check.summary.max_rank_normalized_rhat,
            min_bulk_ess=check.summary.min_bulk_ess, min_tail_ess=check.summary.min_tail_ess,
            summary=check.summary),
        sampler=(;retained=check.sampler_rows, warmup=sampler_diagnostics(fitted;phase=:warmup)),
        numerical_criteria=(;purpose="Illustrative computational tolerances for this teaching example; not scientific effect-size thresholds.",
            unit="logit", mean_mcse_limit=MCSE_LIMITS.mean, endpoint_mcse_limit=MCSE_LIMITS.endpoint),
        mean_mcse=mcse.mean_mcse,
        endpoint_mcse=(first(mcse.quantiles).mcse,last(mcse.quantiles).mcse),
        interpretation=interpretation(qualified,summary.lower,summary.upper))
end

diagnostic_value(value) = ismissing(value) ? "unavailable" : string(value)

function print_result(io, r)
    println(io, r.question)
    println(io, "Artificial ratings: $(r.data.ratings); people: $(r.data.people); items: $(r.data.items); raters: $(r.data.raters).")
    println(io, "Positive values mean that R2 is more severe than R1, after accounting for persons and items.")
    println(io, "Numerical checks: ", r.numerically_qualified ? "passed" : "need attention")
    println(io, "Posterior mean: $(round(r.mean;digits=3)) logit; 90% interval: [$(round(r.lower;digits=3)), $(round(r.upper;digits=3))].")
    println(io, r.interpretation)
    println(io, "MCSE (logit): mean=$(diagnostic_value(r.mean_mcse)); interval endpoints=$(diagnostic_value(r.endpoint_mcse[1])), $(diagnostic_value(r.endpoint_mcse[2])).")
    println(io, "Illustrative MCSE limits (logit): mean <= $(r.numerical_criteria.mean_mcse_limit); each endpoint <= $(r.numerical_criteria.endpoint_mcse_limit). These are not scientific effect-size thresholds.")
    println(io, "Retained-draw diagnostics: $(r.diagnostics.flag); maximum R-hat=$(diagnostic_value(r.diagnostics.max_rhat)); minimum bulk/tail ESS=$(diagnostic_value(r.diagnostics.min_bulk_ess))/$(diagnostic_value(r.diagnostics.min_tail_ess)).")
    println(io, "Sampler diagnostics for retained draws (per chain):")
    for row in r.sampler.retained
        println(io, "  Chain $(row.chain): divergences=$(diagnostic_value(row.n_divergences)); maximum-depth hits=$(diagnostic_value(row.n_max_treedepth)); nonfinite log densities=$(row.n_nonfinite_log_posterior); E-BFMI=$(diagnostic_value(row.e_bfmi)); flag=$(row.flag).")
    end
    println(io, "Warmup diagnostics (separate from retained draws; no warmup pass/fail rule):")
    for row in r.sampler.warmup
        println(io, "  Chain $(row.chain): coverage=$(row.coverage); recorded/expected iterations=$(diagnostic_value(row.observed_iterations))/$(row.expected_iterations); divergences=$(diagnostic_value(row.n_divergences)); maximum-depth hits=$(diagnostic_value(row.n_max_treedepth)); nonfinite log densities=$(diagnostic_value(row.n_nonfinite_logdensity)).")
    end
    println(io, "Unavailable telemetry is not zero. Passing these numerical checks does not establish model adequacy or interval calibration.")
end

"""
    FirstMFRMAnalysis.main(args=String[]; output_parent="results/first_analysis")

Fit the fixed teaching dataset, or pass `["--saved-fit", "path/to/fit.jls"]`
to read a matching trusted cache without fitting. Save a new fit cache and
plain-text/JSON answer, reload them, and return the output directory and result.
Including this file defines these functions without running an analysis.
"""
function main(args=String[]; output_parent="results/first_analysis")
    (isempty(args) || (length(args)==2 && args[1]=="--saved-fit")) ||
        throw(ArgumentError("Usage: first_analysis.jl [--saved-fit path/to/fit.jls]"))
    prepared = inputs()
    # A unique directory preserves diagnostic evidence from earlier attempts.
    out = mktempdir(mkpath(output_parent); prefix="analysis-", cleanup=false)
    fitted = isempty(args) ? fit(prepared.spec; prior=prepared.prior, prepared.controls...) : load_fit_cache(args[2])
    cache = joinpath(out,"fit.jls")
    save_fit_cache(cache,fitted)
    println("Saved fit: ",abspath(cache))
    flush(stdout)
    answer = result(fitted, prepared)
    restored = load_fit_cache(cache)
    isequal(result(restored,prepared),answer) || error("Saved and reloaded answers differ.")
    open(joinpath(out,"answer.txt"),"w") do io
        print_result(io,answer)
    end
    json_path = joinpath(out,"answer.json")
    open(json_path,"w") do io
        JSON3.write(io,answer)
    end
    JSON3.read(read(json_path,String)).mean == answer.mean || error("Saved JSON answer differs.")
    print_result(stdout,answer)
    println("Saved fit.jls, answer.txt and answer.json in ",abspath(out))
    return (; directory=out, answer)
end

end

if abspath(PROGRAM_FILE) == @__FILE__
    FirstMFRMAnalysis.main(ARGS)
end
