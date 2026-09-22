using BayesianMGMFRM

all(arg -> arg in ("--plots", "--cmdstan"), ARGS) ||
    error("Usage: julia --project=. examples/minimal.jl [--plots] [--cmdstan]")
if "--plots" in ARGS
    using CairoMakie
end
backend = "--cmdstan" in ARGS ? :cmdstan : :advancedhmc

ratings = (
    examinee = ["E1", "E1", "E1", "E1", "E2", "E2", "E2", "E2"],
    rater = ["R1", "R2", "R1", "R2", "R1", "R2", "R1", "R2"],
    item = ["I1", "I1", "I2", "I2", "I1", "I1", "I2", "I2"],
    score = [0, 1, 2, 0, 1, 2, 0, 2],
)
data = FacetData(ratings; person = :examinee, rater = :rater, item = :item,
    score = :score, category_levels = 0:2)
validation = validate_design(data)
println(validation)
validation.passed || error("Resolve the data validation issues before fitting.")
spec = mfrm_spec(data; thresholds = :partial_credit, validation_report = validation)

# Keep each run in its own directory, including a fresh CmdStan build if selected.
output_dir = mktempdir(mkpath("results/minimal"); prefix = "$(backend)-", cleanup = false)
println("Output directory: ", relpath(output_dir))
println("Short demonstration: 50 warmup + 50 retained draws per chain; not sufficient for inference.")
fit_result = fit(spec; backend, ndraws = 50, warmup = 50, chains = 2, seed = 102,
    cmdstan_cache_dir = backend === :cmdstan ? joinpath(output_dir, "cmdstan-build") : nothing)
println(fit_result)
check = diagnostics(fit_result; view = :public)
println("MCMC status: ", check.summary.flag, "; max R-hat: ", check.summary.max_rank_normalized_rhat,
    "; min bulk/tail ESS: ", check.summary.min_bulk_ess, " / ", check.summary.min_tail_ess)
check.summary.passed || println("Review diagnostics(fit_result) before interpreting estimates.")
display([row[(:parameter, :median, :lower, :upper)] for row in posterior_summary(fit_result)])

cache_path = joinpath(output_dir, "fit.jls")
save_fit_cache(cache_path, fit_result)
restored = load_fit_cache(cache_path)
@assert isequal(posterior_summary(restored), posterior_summary(fit_result))
println("Fit saved and reloaded: ", relpath(cache_path))

# Regenerate all figures from the saved fit, without refitting or handling draw matrices.
if "--plots" in ARGS
    posterior = BayesianMGMFRM.plot_posterior(restored; block = :rater)
    chains = BayesianMGMFRM.plot_diagnostics(restored; block = :rater)
    predictive = BayesianMGMFRM.plot_predictive(restored; ndraws = 200, seed = 42)
    wright = BayesianMGMFRM.plot_wright(restored)
    for (name, figure) in (("rater-posterior", posterior), ("rater-chains", chains),
            ("category-predictive", predictive), ("wright-map", wright))
        save(joinpath(output_dir, "$name.pdf"), figure)
    end
    save(joinpath(output_dir, "wright-map.svg"), wright)
    println("Saved four PDFs and wright-map.svg in ", relpath(output_dir))
else
    println("Add --plots after installing CairoMakie to generate figures; see docs/src/examples.md.")
end
