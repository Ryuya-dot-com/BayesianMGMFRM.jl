module FirstMFRMAnalysisV02

using BayesianMGMFRM

const MCSE_LIMITS = (; mean = 0.01, endpoint = 0.02)

function check_input(fitted, prepared)
    A = BayesianMGMFRM.AdditiveFacets
    fitted isa A.Fit || throw(ArgumentError(
        "This example requires a standard MRCML fit. For the reference-coded example, use examples/legacy/first_analysis.jl."))
    A.checked(fitted)
    isequal(fitted.record.target, A.record(prepared.spec)) ||
        throw(ArgumentError("The saved fit does not match this example's ratings, model and prior."))
    return fitted
end

"""
    FirstMFRMAnalysisV02.inputs()

Prepare the fixed 72-rating teaching dataset, standard v0.2 isometric 1D MFRM
specification (`prior = :default`, orthonormal Helmert sum-to-zero facets and
steps, `population_mean ~ Normal(0, 2.5)`, `residual_sd[person] ~ HalfNormal(1.0)`),
pre-fit validation, prior summary, and explicit NUTS controls without sampling.
"""
function inputs()
    ratings = include(joinpath(@__DIR__, "first_analysis_ratings.jl"))
    spec = mfrm_spec(
        ratings;
        person = :person,
        score = :score,
        facets = (item = :item, rater = :rater),
        steps = :item,
        category_levels = 0:3,
        prior = :default,
    )
    validation = validate_design(spec)
    validation.passed || error("Resolve pre-fit validation errors before fitting: $validation")
    summary = design_summary(spec)
    controls = (;
        chains = 4,
        warmup = 1000,
        ndraws = 1000,
        seed = 2026112401,
        target_accept = 0.90,
        max_depth = 10,
        chain_execution = :serial,
        progress = false,
    )
    return (; ratings, spec, validation, design_summary = summary, controls)
end

function numerical_checks_pass(q_rep, contrast_res)
    mc = contrast_res.mcse
    endpoints = (mc.lower, mc.upper)
    values = (mc.mean, endpoints...)
    return q_rep.qualified &&
        mc.status === :available &&
        all(x -> x isa Real && !(x isa Bool) && isfinite(x) && x >= 0.0, values) &&
        values[1] <= MCSE_LIMITS.mean &&
        all(x -> x <= MCSE_LIMITS.endpoint, endpoints)
end

function interpretation(qualified::Bool, lower::Real, upper::Real)
    !qualified && return "Numerical checks need attention. Withhold the severity contrast conclusion and inspect diagnostics(fitted) and qualify(fitted)."
    lower > 0.0 && return "The 90% credible interval lies above zero: these ratings support R2 being more severe than R1 under this model and prior."
    upper < 0.0 && return "The 90% credible interval lies below zero: these ratings support R2 being less severe than R1 under this model and prior."
    return "The 90% credible interval includes zero: these ratings do not clearly establish which rater is more severe under this model and prior. This does not prove equivalence."
end

"""
    FirstMFRMAnalysisV02.result(fitted, prepared = inputs(); ppc_seed = 2026112402, fit_stats_seed = 2026112403)

Summarize the R2 - R1 severity contrast, whole-fit qualification, posterior-integrated
vs. plug-in rater Infit/Outfit statistics, person reliability, and posterior predictive
category-proportion checks from a completed v0.2 fit.
"""
function result(fitted, prepared = inputs(); ppc_seed::Int = 2026112402, fit_stats_seed::Int = 2026112403)
    check_input(fitted, prepared)
    q_rep = qualify(fitted)
    mcmc_diag = diagnostics(fitted)
    r2_vs_r1 = contrast(fitted; facet = :rater, left = "R2", right = "R1", interval = 0.90)
    raters = facet_summary(fitted; facet = :rater, interval = 0.90)
    fit_stats = diagnostics(fitted; kind = :fit_statistics, by = :rater, level = 0.90, seed = fit_stats_seed)
    rel = reliability(fitted; facet = :person, interval = 0.90)
    ppc = predictive_check(fitted; ndraws = 1000, seed = ppc_seed, interval = 0.90)
    qualified = numerical_checks_pass(q_rep, r2_vs_r1)
    return (;
        question = "Is R2 more severe than R1?",
        data = (;
            origin = "fixed artificial teaching data",
            ratings = length(prepared.ratings.score),
            people = length(unique(prepared.ratings.person)),
            items = length(unique(prepared.ratings.item)),
            raters = length(unique(prepared.ratings.rater)),
            categories = 0:3,
        ),
        model = "Standard v0.2 1D isometric partial-credit MFRM (prior = :default)",
        prior_summary = prepared.design_summary.prior_summary,
        contrast = r2_vs_r1,
        raters = raters.rows,
        fit_statistics = fit_stats.rows,
        reliability = rel,
        ppc = ppc,
        qualification = q_rep,
        warmup = mcmc_diag.warmup,
        numerically_qualified = qualified,
        numerical_criteria = (;
            purpose = "Illustrative computational tolerances for this teaching example; not scientific effect-size thresholds.",
            unit = "logit",
            mean_mcse_limit = MCSE_LIMITS.mean,
            endpoint_mcse_limit = MCSE_LIMITS.endpoint,
        ),
        interpretation = interpretation(qualified, r2_vs_r1.lower, r2_vs_r1.upper),
    )
end

function print_result(io::IO, r)
    println(io, r.question)
    println(io, "Artificial ratings: $(r.data.ratings); people: $(r.data.people); items: $(r.data.items); raters: $(r.data.raters).")
    println(io, "Model: $(r.model)")
    println(io, "Prior: person SD ~ $(r.prior_summary.person.label); population_mean ~ $(r.prior_summary.population_mean.distribution); facets/steps = orthonormal Helmert sum-to-zero (marginal SD 1.0).")
    println(io, "Whole-fit qualification: ", r.qualification.qualified ? "passed" : "failed",
        " (max R-hat = $(round(r.qualification.max_rhat; digits = 4)), ",
        "min bulk/tail ESS = $(round(r.qualification.min_bulk_ess; digits = 1))/$(round(r.qualification.min_tail_ess; digits = 1)), ",
        "retained divergences = $(r.qualification.n_divergences), retained max-depth hits = $(r.qualification.n_max_treedepth)).")
    if hasproperty(r, :warmup) && !isempty(r.warmup)
        w_div = [row.n_divergences for row in r.warmup]
        w_td = [row.n_max_treedepth for row in r.warmup]
        if all(x -> x isa Integer, w_div)
            per_chain = join(["chain $(row.chain)=$(row.n_divergences)" for row in r.warmup], ", ")
            total_td = all(x -> x isa Integer, w_td) ? sum(w_td) : missing
            println(io, "Warmup adaptation events (excluded from retained draws): $(sum(w_div)) total divergences ($per_chain); max-depth hits = $(total_td).")
        end
    end
    c = r.contrast
    println(io, "R2 - R1 severity contrast (logit): mean = $(round(c.mean; digits = 3)), median = $(round(c.median; digits = 3)), 90% interval = [$(round(c.lower; digits = 3)), $(round(c.upper; digits = 3))].")
    println(io, "Contrast MCSE (logit): mean = $(round(c.mcse.mean; digits = 4)), interval endpoints = $(round(c.mcse.lower; digits = 4)), $(round(c.mcse.upper; digits = 4)).")
    println(io, r.interpretation)
    println(io, "Rater posterior-integrated vs. plug-in Infit/Outfit MNSQ (90% posterior interval):")
    for row in r.fit_statistics
        println(io, "  $(row.level): Infit mean=$(round(row.infit_mnsq_mean; digits = 3)) [$(round(row.infit_mnsq_lower; digits = 3)), $(round(row.infit_mnsq_upper; digits = 3))] (plug-in $(round(row.plugin_infit_mnsq; digits = 3))); ",
            "Outfit mean=$(round(row.outfit_mnsq_mean; digits = 3)) [$(round(row.outfit_mnsq_lower; digits = 3)), $(round(row.outfit_mnsq_upper; digits = 3))] (plug-in $(round(row.plugin_outfit_mnsq; digits = 3))).")
    end
    println(io, "Person finite-cohort reliability = $(round(r.reliability.reliability; digits = 3)); numerical MCSE = $(r.reliability.mcse.value).")
    println(io, "Passing numerical checks does not establish model adequacy or interval calibration.")
end

"""
    FirstMFRMAnalysisV02.main(args = String[]; output_parent = "results/first_analysis_v02")

Run the complete standard v0.2 1D MFRM teaching walkthrough:
validate -> inspect priors -> fit (4 NUTS chains) -> qualify -> contrast ->
posterior-integrated Infit/Outfit -> reliability -> PPC -> save & verify via
native cache (`save_fit`/`load_fit`) and SHA-256 `PortableHandoff`.
Pass `["--saved-fit", "path/to/fit.jls"]` to recompute reports from a matching
trusted native cache without fitting. Reporting includes seeded predictive
generation. Including this file does not run an analysis.
"""
function main(args = String[]; output_parent::AbstractString = "results/first_analysis_v02")
    (isempty(args) || (length(args) == 2 && args[1] == "--saved-fit")) ||
        throw(ArgumentError("Usage: first_analysis.jl [--saved-fit path/to/fit.jls]"))
    prepared = inputs()
    saved = isempty(args) ? nothing : check_input(load_fit(args[2]), prepared)
    out = mktempdir(mkpath(output_parent); prefix = "analysis-v02-", cleanup = false)
    fitted = saved === nothing ? fit(prepared.spec; prepared.controls...) : saved
    cache_path = joinpath(out, "fit.jls")
    save_fit(cache_path, fitted)
    println("Saved fit: ", relpath(cache_path))
    flush(stdout)
    handoff = BayesianMGMFRM.PortableHandoff.export_handoff(fitted)
    handoff_path = joinpath(out, "handoff.json")
    BayesianMGMFRM.PortableHandoff.save_handoff(handoff_path, handoff)
    loaded_handoff = BayesianMGMFRM.PortableHandoff.load_handoff(handoff_path)
    loaded_handoff.record.handoff_bundle_sha256 == handoff.record.handoff_bundle_sha256 ||
        error("PortableHandoff digest mismatch on reload.")
    restored = load_fit(cache_path)
    isequal(posterior_summary(restored), posterior_summary(fitted)) ||
        error("Saved and reloaded native fit summaries differ.")
    answer = result(restored, prepared)
    answer_path = joinpath(out, "answer.txt")
    open(answer_path, "w") do io
        print_result(io, answer)
    end
    print_result(stdout, answer)
    println("Saved fit.jls, handoff.json and answer.txt in ", relpath(out))
    return (; directory = out, fitted, result = answer, handoff = loaded_handoff)
end

end

if abspath(PROGRAM_FILE) == @__FILE__
    FirstMFRMAnalysisV02.main(ARGS)
end
