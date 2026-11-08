module NormalizedMGMFRMExample

using BayesianMGMFRM, Random
const E = BayesianMGMFRM.Experimental

function print_help(io)
    println(io, """
Usage: normalized_mgmfrm.jl [MODE] [--figures]

Modes (choose one):
  --help, -h          Show this help; no fitting or output files.
  --inspect-example  Inspect the 1,000 fixed teaching ratings (the default).
  --fit-example      Fit the teaching data: 4 chains, 1,000 warmup + 1,000 retained draws each.
  --saved-fit PATH   Read a trusted fit in its original environment and write a verified report.
  --demo             Run a tiny demonstration with random draws and short chains; not for inference.

No arguments inspect the data, Q, dimension support and explicit priors without sampling.
--figures requires CairoMakie and --fit-example, --saved-fit or --demo.
The saved-fit route creates a new output folder without fitting or predictive random draws.
If an export fails after saving fit.jls, keep it and use --saved-fit to recover the report.
""")
end

function options(args)
    figures = count(==("--figures"), args)
    remaining = filter(!=("--figures"), args)
    example_mode = isempty(remaining) || remaining == ["--inspect-example"] ? :inspect :
        remaining in (["--help"], ["-h"]) ? :help :
        remaining == ["--fit-example"] ? :fit :
        remaining == ["--demo"] ? :demo : :none
    figures <= 1 && (example_mode !== :none ||
        (length(remaining) == 2 && first(remaining) == "--saved-fit" &&
         !startswith(last(remaining), "--"))) &&
        !(example_mode in (:inspect, :help) && figures == 1) || throw(ArgumentError(
        "Choose one mode: --inspect-example (default), --fit-example, --saved-fit PATH, --demo or --help. --figures requires a fit, saved fit or demo; use --help for details."))
    return (; figures=figures == 1,
        saved_fit=example_mode !== :none || isempty(remaining) ? nothing : last(remaining),
        example_mode)
end

"""Read the fixed artificial ratings and prepare the two-dimensional example, without fitting or random generation."""
function example_inputs()
    ratings = include(joinpath(@__DIR__, "normalized_mgmfrm_ratings.jl"))
    data = FacetData(ratings; person=:person, item=:item, rater=:rater,
        score=:score, category_levels=1:4)
    validation = validate_design(data)
    validation.passed || error("Resolve the data-validation errors before fitting: $validation")
    spec = mfrm_spec(data; family=:mgmfrm, thresholds=:partial_credit, dimensions=2,
        q_matrix=Bool[1 0; 1 0; 0 1; 0 1; 0 1],
        dimension_labels=["dim=1", "dim=2"], validation_report=validation)
    # These explicit scales reproduce this teaching example, not a general prior recommendation.
    prior = E.NormalizedMGMFRMPrior(; prior_model=:exchangeable,
        person_sd=1.0, rater_sd=sqrt(2.0), item_sd=1.0,
        log_discrimination_sd=.25, log_consistency_sd=sqrt(2.0)/2, step_sd=sqrt(2.0))
    controls = (; backend=:advancedhmc, chains=4, warmup=1000, ndraws=1000,
        seed=20261008110001, sampling_coordinates=:orthogonal_person_mean_item_offset,
        step_size=.03, target_accept=.9, max_depth=10, metric=:diagonal,
        init_jitter=.1, max_energy_error=1000.0, ad_backend=:ForwardDiff,
        rhat_threshold=1.01, ess_threshold=400.0, record_warmup=true, progress=false)
    return (; data, spec, prior, controls)
end

function print_example(io, prepared)
    data, spec, prior, controls = prepared.data, prepared.spec, prepared.prior, prepared.controls
    println(io, "Fixed artificial MGMFRM teaching data: $(data.n) ratings; $(length(data.person_levels)) people; $(length(data.item_levels)) items; $(length(data.rater_levels)) raters.")
    println(io, "Ordered categories: ", join(data.category_levels, ", "))
    println(io, "Missing person/item/rater combinations are unobserved, not zero scores.")
    println(io, "Dimensions: ", join(spec.dimension_labels, ", "), "; latent correlations fixed at zero.")
    for (i, item) in enumerate(data.item_levels)
        active = spec.dimension_labels[findall(spec.q_matrix[i,:])]
        println(io, "  $item measures ", join(active, ", "), " with an estimated positive loading.")
    end
    q_check = q_matrix_validation(spec)
    support = q_check.identification.likelihood_support
    println(io, "Person-level dimension support: $(length(support.person_rows) - support.n_persons_incomplete)/$(length(support.person_rows)) have full structural rank.")
    for row in support.person_rows
        row.full_column_rank && continue
        if isempty(row.unobserved_dimension_labels)
            println(io, "  $(row.person_label): observed items do not separate all ability directions; review Q and the prior.")
        else
            println(io, "  $(row.person_label): no ratings for ", join(row.unobserved_dimension_labels, ", "), "; do not interpret these as directly measured abilities.")
        end
    end
    println(io, "Structural support does not guarantee precise estimates. Inspect q_matrix_validation(spec) for all Q and dimension-specific connectivity warnings.")
    println(io, "Each item owns its partial-credit steps. Rater severities sum to zero; positive consistencies have product one.")
    println(io, "Normalized exchangeable prior; explicit scales: ", prior.scales)
    println(io, "Scales reproduce this example; they are not a general prior recommendation.")
    println(io, "Fit settings: $(controls.chains) chains, each $(controls.warmup) warmup + $(controls.ndraws) retained draws; seed $(controls.seed).")
    println(io, "Inspect diagnostics and MCSE after fitting; these settings do not guarantee an adequate fit for other data.")
end

function demonstration()
    cells = [(p, i, r) for p in 1:3 for i in 1:4 for r in 1:3]
    data = FacetData((; person=first.(cells), item=getindex.(cells,2), rater=last.(cells),
        score=[mod(p+i+r,4) for (p,i,r) in cells]);
        person=:person, item=:item, rater=:rater, score=:score, category_levels=0:3)
    spec = mfrm_spec(data; family=:mgmfrm, dimensions=2,
        q_matrix=Bool[1 0; 1 0; 0 1; 0 1], dimension_labels=["reasoning", "communication"])
    # Illustrative scales, not a scientifically selected prior.
    prior = E.NormalizedMGMFRMPrior(; prior_model=:exchangeable,
        person_sd=.8, rater_sd=.6, item_sd=.9,
        log_discrimination_sd=.3, log_consistency_sd=.4, step_sd=.7)
    check = E.prior_predictive_check(spec; prior, ndraws=100, rng=MersenneTwister(24))
    display(first(predictive_check_summary(check)))
    println("Short workflow demonstration: 10 warmup + 12 retained draws per chain; insufficient for inference.")
    return E.fit(spec; prior, sampling_coordinates=:orthogonal_person_mean_item_offset,
        chains=2, warmup=10, ndraws=12, max_depth=3, seed=24, record_warmup=true)
end

function print_answer(io, report, metadata)
    println(io, "What abilities does this fitted model estimate?")
    println(io, "Observed ratings: $(metadata.n_observations); people: $(metadata.n_persons); items: $(metadata.n_items); raters: $(metadata.n_raters).")
    println(io, "Retained draws: $(metadata.n_draws) across $(metadata.n_chains) chains.")
    println(io, "Ability dimensions: ", join(metadata.dimension_labels, ", "))
    println(io, "Latent correlations are fixed at zero, not estimated from these ratings.")
    println(io, "Whole-fit MCMC status: ", report.diagnostics.summary.flag)
    println(io, report.diagnostics.summary.passed ?
        "Diagnostics pass; assess the reported MCSE against your question before interpretation." :
        "Do not interpret these estimates yet: the saved fit has numerical warnings.")
    println(io, "First person's separate ability estimates (95% central intervals):")
    people = filter(row -> row.block === :person, report.direct_posterior.rows)
    for row in first(people, metadata.dimensions)
        mcse = only(filter(r -> r.parameter == row.parameter, report.direct_posterior.mcse_rows))
        println(io, "  $(row.parameter): $(round(row.mean; digits=3)) [$(round(row.lower; digits=3)), $(round(row.upper; digits=3))]; mean MCSE=$(mcse.mean_mcse)")
    end
    println(io, "Abilities use the saved prior-defined scale; different dimensions are not an overall ranking.")
    println(io, "All persons, prior settings and endpoint MCSE are in report/. Calibration is not established by passing diagnostics.")
end

"""
    NormalizedMGMFRMExample.main(args=String[]; output_parent="results/normalized_mgmfrm")

Pass `["--saved-fit", "path/to/fit.jls"]` to read a trusted normalized MGMFRM
cache in its original dependency environment, without fitting or random draws.
The supplied fit's data, model, prior and warnings are preserved. Save a new
cache, readable answer and public report, and verify reload. Optional
`--figures` requires CairoMakie. `--inspect-example` checks and explains the
bundled 1,000 fixed artificial ratings without fitting or creating output files.
`--fit-example` fits those ratings with the explicit four-chain settings in
`example_inputs()` and reports the result without predictive random draws.
With no arguments, inspect the fixed teaching inputs without fitting or random
draws. `--help` (or `-h`) explains the modes without creating output files.
`--demo` runs the original short interface demonstration, which generates prior
draws and is inadequate for inference.
Including this file only defines functions.
"""
function main(args=String[]; output_parent="results/normalized_mgmfrm")
    request = options(args)
    if request.example_mode === :help
        print_help(stdout)
        return (; help_only=true)
    end
    if request.example_mode === :inspect
        prepared = example_inputs()
        print_example(stdout, prepared)
        println("Inspection complete; no fit or random draws were generated. Use --fit-example to estimate this model.")
        return (; prepared, inspection_only=true)
    end
    if request.figures
        @eval using CairoMakie
    end
    saved = request.saved_fit !== nothing
    predictive = request.example_mode === :demo
    result = if request.example_mode === :fit
        prepared = example_inputs()
        print_example(stdout, prepared)
        E.fit(prepared.spec; prior=prepared.prior, prepared.controls...)
    else
        saved ? load_fit_cache(request.saved_fit) : demonstration()
    end
    result isa E.NormalizedMGMFRMFit || throw(ArgumentError(
        "This example requires a normalized MGMFRM fit cache."))
    directory = mktempdir(mkpath(output_parent); cleanup=false)
    path = joinpath(directory, "fit.jls")
    save_fit_cache(path, result)
    println("Saved fit before reporting: ", abspath(path))
    metadata = fit_metadata(result)
    report = fit_report(result; view=:public, require_complete=true,
        include_effective_slopes=true,
        include_prior_predictive=predictive, include_posterior_predictive=predictive,
        prior_predictive_ndraws=100, seed=24,
        include_waic=predictive, include_loo=predictive,
        dataset_id=predictive ? "normalized-example-v1" : nothing,
        observation_ids=predictive ? ["rating-$i" for i in 1:metadata.n_observations] : nothing)
    restored = load_fit_cache(path)
    @assert isequal(fit_metadata(restored), metadata)
    @assert isequal(posterior_summary(restored), posterior_summary(result))
    @assert isequal(posterior_summary(restored; scale=:model),
        BayesianMGMFRM.direct_posterior_summary(result))
    @assert isequal(posterior_summary(restored; estimand=:adjacent_logit_slope),
        posterior_summary(result; estimand=:adjacent_logit_slope))
    if predictive
        write(joinpath(directory, "observation_ids.txt"),
            join(["rating-$i" for i in 1:metadata.n_observations], "\n") * "\n")
    end
    report_path = joinpath(directory, "report")
    save_fit_report_bundle(report_path, report; require_complete=true)
    reopened = load_fit_report_bundle(report_path; require_complete=true)
    @assert reopened["diagnostics"]["summary"]["passed"] == report.diagnostics.summary.passed
    @assert reopened["metadata"]["target_identity"] == metadata.target_identity
    open(joinpath(directory, "answer.txt"), "w") do io
        print_answer(io, report, metadata)
    end
    if request.figures
        # The plotting extension was loaded above; dispatch in its current world.
        Base.invokelatest(save_fit_report_bundle, joinpath(directory, "figures"), restored;
            figures=(;posterior=(;block=:person,dimension=first(metadata.dimension_labels)),
                diagnostics=(;block=:item_dimension_discrimination,dimension=first(metadata.dimension_labels))),
            include_prior_predictive=false, include_posterior_predictive=false,
            require_complete=true)
    end
    print_answer(stdout, report, metadata)
    println("Saved and verified: ", abspath(directory))
    return (; directory, report, metadata)
end

end

if abspath(PROGRAM_FILE) == @__FILE__
    NormalizedMGMFRMExample.main(ARGS)
end
