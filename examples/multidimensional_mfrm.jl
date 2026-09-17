using BayesianMGMFRM
using Random

all(arg -> arg in ("--plots", "--cmdstan", "--correlated", "--prior-only"), ARGS) ||
    error("Usage: julia --project=. examples/multidimensional_mfrm.jl [--plots] [--cmdstan] [--correlated] [--prior-only]")
if "--plots" in ARGS
    using CairoMakie
end
backend = "--cmdstan" in ARGS ? :cmdstan : :advancedhmc

cells = [(p, i, r) for p in 1:3 for i in 1:4 for r in 1:2]
data = FacetData((; person = first.(cells), item = getindex.(cells, 2),
    rater = last.(cells), score = [mod(sum(cell), 4) for cell in cells]);
    person = :person, item = :item, rater = :rater, score = :score, category_levels = 0:3)
validation = validate_design(data)
println(validation)
validation.passed || error("Resolve the data validation issues before fitting.")

# Q rows follow data.item_levels; columns follow dimension_labels.
q_matrix = Bool[1 0; 1 0; 0 1; 0 1]
dimension_labels = ["reasoning", "communication"]
spec = mfrm_spec(data; family = :mfrm, dimensions = 2, q_matrix, dimension_labels,
    thresholds = :partial_credit, validation_report = validation)
prior = MFRMPrior(person_sd = 0.7, rater_sd = 0.4, item_sd = 0.6, step_sd = 0.5)
println("Experimental multidimensional MFRM: Q coefficients and rater consistency fixed at one; unit logits.")
correlated = "--correlated" in ARGS
model = correlated ? BayesianMGMFRM.Experimental.correlated(spec; lkj_eta = 2) : spec
println(correlated ? "Population correlation estimated with an LKJ(2) prior." : "Latent correlation fixed to identity.")
println("Person/item locations anchored by zero-centered priors.")
println("Q rows: ", data.item_levels, "; dimensions: ", dimension_labels)
display(q_matrix)

output_dir = mktempdir(mkpath("results/multidimensional_mfrm"); prefix = "$(backend)-", cleanup = false)
backend_options = backend === :cmdstan ?
    (; cmdstan_cache_dir = joinpath(output_dir, "cmdstan-build")) : (;)
println("Output directory: ", abspath(output_dir))
prior_check = BayesianMGMFRM.Experimental.prior_predictive_check(model;
    prior, ndraws = 1000, rng = MersenneTwister(42))
println("Prior-implication status: ", prior_check.implication_diagnostics.flag)
display(prior_check.parameter_summary)
display(predictive_check_summary(prior_check))
if "--plots" in ARGS
    save(joinpath(output_dir, "ability-prior.pdf"), BayesianMGMFRM.plot_prior(prior_check;
        block = :person, dimension = "communication"))
    correlated && save(joinpath(output_dir, "correlation-prior.svg"),
        BayesianMGMFRM.plot_prior(prior_check; block = :latent_correlation))
    save(joinpath(output_dir, "prior-predictive.pdf"), BayesianMGMFRM.plot_predictive(prior_check))
end
println("Review prior scales and score implications before interpreting a fit.")
"--prior-only" in ARGS && exit(0)
println("Short demonstration: 50 warmup + 50 retained draws per chain; not sufficient for inference.")
fit_result = BayesianMGMFRM.Experimental.fit(model; backend, prior,
    ndraws = 50, warmup = 50, chains = 2, seed = 20260915, backend_options...)
println(fit_result)
check = diagnostics(fit_result)
println("MCMC status: ", check.summary.flag, "; max R-hat: ", check.summary.max_rank_normalized_rhat,
    "; min bulk/tail ESS: ", check.summary.min_bulk_ess, " / ", check.summary.min_tail_ess)
println("Review diagnostics(fit_result) before interpreting estimates.")

cache_path = joinpath(output_dir, "fit.jls")
save_fit_cache(cache_path, fit_result)
restored = load_fit_cache(cache_path)
@assert isequal(fit_metadata(restored), fit_metadata(fit_result))
@assert isequal(BayesianMGMFRM.direct_posterior_summary(restored), BayesianMGMFRM.direct_posterior_summary(fit_result))

selection = correlated ? (; block = :latent_correlation) : (; block = :person, dimension = "reasoning")
figures = "--plots" in ARGS ? (
    posterior = selection, diagnostics = selection, predictive = (;)) : nothing
report_dir = joinpath(output_dir, "report")
save_fit_report_bundle(report_dir, restored; view = :public, figures,
    posterior_lower = 0.05, posterior_upper = 0.95, ndraws = 100, seed = 42)
load_fit_report_bundle(report_dir) # Verify exported files without refitting.
println("Saved and verified fit and report: ", abspath(output_dir))
println("The report labels fixed/derived coordinates; report completion does not imply MCMC convergence.")
"--plots" in ARGS || println("Add --plots with CairoMakie installed to include PDF/SVG figures in the report bundle.")
