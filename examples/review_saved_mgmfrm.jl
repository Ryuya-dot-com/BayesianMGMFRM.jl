# Review an existing independent fixed-Q MGMFRM cache; never fit or refresh it.
using BayesianMGMFRM, CairoMakie, JSON3, SHA

function review_saved_mgmfrm(cache_path, output_dir, dimension)
    ispath(output_dir) && error("Choose a new output directory; existing reviews are preserved.")
    cache_hash = bytes2hex(open(sha256, cache_path))
    println("Loading saved fit: ", basename(cache_path)); flush(stdout)
    restored = load_fit_cache(cache_path)
    restored isa BayesianMGMFRM.MGMFRMFit ||
        error("This example requires an independent fixed-Q MGMFRM cache.")
    metadata = fit_metadata(restored; view = :public)
    dimension in metadata.dimension_labels ||
        error("Choose a stored dimension label: $(metadata.dimension_labels)")
    check = diagnostics(restored; view = :public, include_location = true)
    warmup = sampler_diagnostics(restored; phase = :warmup)
    println("Model: experimental fixed-Q MGMFRM; backend: ", metadata.backend)
    println("Selected dimension: ", dimension, "; retained draws: ", metadata.n_draws)
    println("Whole-fit diagnostics: ", check.summary.flag,
        "; location diagnostics: ", check.location_summary.flag)
    check.summary.passed || println("MCMC warnings remain: inspect review.json before interpreting estimates.")
    println("Warmup history (separate from retained diagnostics):"); display(warmup)

    println("Computing model-scale intervals and Monte Carlo errors."); flush(stdout)
    posterior = BayesianMGMFRM.direct_posterior_summary(restored;
        lower = 0.05, upper = 0.95, intervals = (0.9,))
    precision = posterior_mcse(restored; probabilities = (0.05, 0.5, 0.95))
    @assert getproperty.(posterior, :parameter) == getproperty.(precision, :parameter)
    for (estimate, error) in zip(posterior, precision)
        @assert all(isapprox(a, b) for (a, b) in zip(
            (estimate.lower, estimate.median, estimate.upper),
            getproperty.(error.quantiles, :estimate)))
    end

    # These draws simulate additional scores for existing rating rows only.
    # Posterior summaries/MCSE use every retained draw, without thinning.
    options = (; posterior_lower = 0.05, posterior_upper = 0.95,
        posterior_intervals = (0.9,), predictive_interval = 0.9, ndraws = 200,
        include_calibration = false, include_waic = false, include_loo = false)
    figures = (;
        posterior = (; block = :person, dimension, max_parameters = metadata.n_persons),
        diagnostics = (; block = :item_dimension_discrimination, dimension,
            max_parameters = metadata.n_items),
        predictive = (;))
    println("Writing report and figures from the saved fit."); flush(stdout)
    report_dir = joinpath(output_dir, "report")
    save_fit_report_bundle(report_dir, restored; options..., figures, seed = 42,
        view = :public, require_complete = true)
    reopened = load_fit_report_bundle(report_dir; require_complete = true)
    @assert reopened["diagnostics"]["summary"]["passed"] == check.summary.passed
    @assert bytes2hex(open(sha256, cache_path)) == cache_hash

    # The ordinary independent-MGMFRM report does not include these two surfaces.
    # Keep them as an explicit supplement rather than silently omitting them.
    review = (; cache_sha256 = cache_hash, metadata, diagnostics = check, warmup,
        posterior, precision, dimension, report_options = options, figures,
        seed = 42, new_fits = 0,
        interpretation = "Credible intervals describe posterior uncertainty; MCSE describes computational error. No precision threshold is applied. Same-row predictive agreement does not establish held-out performance or calibration.")
    open(joinpath(output_dir, "review.json"), "w") do io
        JSON3.pretty(io, review)
    end
    write(joinpath(output_dir, "README.md"), """
    # Saved MGMFRM review

    Whole-fit diagnostic status: **$(check.summary.flag)**.
    Finite-panel location diagnostic status: **$(check.location_summary.flag)**.
    The location assessment does not override the whole-fit assessment.

    Open [the report](report/fit_report.md) for tables and PDF/SVG figures.
    [The supplement](review.json) retains all model-scale 90% intervals, their
    endpoint/median MCSE, mean/SD MCSE, location diagnostics, warmup history and
    the saved cache SHA256. MCSE is computational error, not a credible interval;
    no precision acceptance threshold is applied. Separate locations remain
    prior-anchored; location differences do not establish absolute identification.

    Prediction uses 200 resampled joint draws, seed 42, for the existing rating
    rows. Its 90% intervals concern replicated category proportions. All retained
    draws enter parameter summaries and MCSE. Calibration, WAIC and LOO are not
    requested in this same-row descriptive walkthrough.

    The report reader verifies manifest-listed report, table and figure files;
    it does not verify this README or review.json. A complete report means that
    requested sections were produced, not that diagnostics or calibration passed.
    No new fit was run. This walkthrough is not independent scientific review.
    """)
    println("Verified report: ", report_dir)
    println("Location diagnostics and Monte Carlo errors: ", joinpath(output_dir, "review.json"))
    return review
end

length(ARGS) == 3 || error("Usage: julia --project=. examples/review_saved_mgmfrm.jl FIT.jls NEW_DIRECTORY DIMENSION_LABEL")
review_saved_mgmfrm(abspath(ARGS[1]), abspath(ARGS[2]), ARGS[3])
