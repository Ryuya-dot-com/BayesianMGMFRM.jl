using BayesianMGMFRM, Random

all(arg -> arg in ("--cmdstan", "--figures"), ARGS) ||
    error("Usage: julia --project=. examples/correlated_mgmfrm.jl [--cmdstan] [--figures]")
"--figures" in ARGS && (@eval using CairoMakie)
backend = "--cmdstan" in ARGS ? :cmdstan : :advancedhmc
cells = [(p, i, r) for p in 1:3 for i in 1:4 for r in 1:3]
data = FacetData((; person = first.(cells), item = getindex.(cells, 2), rater = last.(cells),
    score = [mod(p + i + r, 4) for (p, i, r) in cells]);
    person = :person, item = :item, rater = :rater, score = :score, category_levels = 0:3)
spec = mfrm_spec(data; family = :mgmfrm, dimensions = 2,
    q_matrix = Bool[1 0; 0 1; 1 0; 0 1], dimension_labels = ["reasoning", "communication"])
model = BayesianMGMFRM.Experimental.correlated(spec; lkj_eta = 2)
# Illustrative raw-coordinate scales; choose and assess priors for the actual study.
prior = BayesianMGMFRM.Experimental.GeneralizedPrior(; person_sd = 0.7, rater_sd = 0.4,
    item_sd = 0.6, log_discrimination_sd = 0.3, log_consistency_sd = 0.2, step_sd = 0.5)
prior_check = BayesianMGMFRM.Experimental.prior_predictive_check(model;
    prior, ndraws = 100, rng = MersenneTwister(92143))
println("Prior rating implications: ", prior_check.implication_diagnostics.flag)
display(first(predictive_check_summary(prior_check)))
directory = mktempdir(mkpath("results/correlated_mgmfrm"); prefix = "$(backend)-", cleanup = false)
options = backend === :cmdstan ? (; cmdstan_cache_dir = joinpath(directory, "compile")) : (;)
println(model)
println("Short interface demonstration: 10 warmup + 12 retained iterations per chain; not sufficient for inference.")
result = BayesianMGMFRM.Experimental.fit(model; prior, backend, ndraws = 12, warmup = 10,
    chains = 2, seed = 92141, step_size = 0.03, max_depth = 4, init_jitter = 0.02, options...)
check = diagnostics(result)
println("MCMC status: ", check.summary.flag, "; inspect diagnostics before interpreting estimates.")
display(sampler_diagnostics(result; phase = :warmup))
display(last(BayesianMGMFRM.direct_posterior_summary(result))) # rho, not Fisher z
display(last(posterior_mcse(result)))
prediction = posterior_predictive_check(result; rng = MersenneTwister(92144))
println("Predictive comparison for the existing persons, items, raters and rating rows.")
display(first(predictive_check_summary(prediction)))
path = joinpath(directory, "fit.jls")
save_fit_cache(path, result)
restored = load_fit_cache(path)
@assert isequal(posterior_mcse(restored), posterior_mcse(result))
@assert predictive_probabilities(restored) == predictive_probabilities(result)
@assert isequal(posterior_predictive_check(restored; rng = MersenneTwister(92144)), prediction)
println("Saved and reloaded: ", relpath(path))
println("Saved predictions reproduce exactly. Same-data agreement does not establish convergence or new-person performance.")
report_options = (; include_prior_predictive = true, prior_predictive_ndraws = 100, seed = 92144)
report = fit_report(restored; report_options..., require_complete = true)
@assert isequal(report.direct_posterior, fit_report(result; report_options...).direct_posterior)
figures = "--figures" in ARGS ? (;
    posterior = (; block = :item_dimension_discrimination, dimension = "communication"),
    diagnostics = (; block = :latent_correlation), predictive = (;),
    prior = (; block = :latent_correlation), prior_predictive = (;)) : nothing
report_path = joinpath(directory, "report")
save_fit_report_bundle(report_path, restored; report_options..., figures, require_complete = true)
reopened = load_fit_report_bundle(report_path; require_complete = true)
@assert reopened["report_status"] == "complete"
println("Report saved: ", relpath(report_path))
println("Report completeness means no failed sections; sampling warnings still apply.")
