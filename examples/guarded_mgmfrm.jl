using BayesianMGMFRM

all(arg -> arg in ("--plots", "--cmdstan"), ARGS) ||
    error("Usage: julia --project=. examples/guarded_mgmfrm.jl [--plots] [--cmdstan]")
if "--plots" in ARGS
    using CairoMakie
end
backend = "--cmdstan" in ARGS ? :cmdstan : :advancedhmc

ratings = (
    examinee = ["E1", "E1", "E1", "E2", "E2", "E2"],
    rater = ["R1", "R2", "R1", "R1", "R2", "R1"],
    item = ["I1", "I1", "I2", "I1", "I2", "I2"],
    score = [0, 1, 2, 1, 0, 2],
)
data = FacetData(ratings; person = :examinee, rater = :rater, item = :item,
    score = :score, category_levels = 0:2)
validation = validate_design(data)
println(validation)
validation.passed || error("Resolve the data validation issues before fitting.")

# Q rows follow data.item_levels; columns follow dimension_labels.
q_matrix = Bool[1 0; 0 1]
dimension_labels = ["reasoning", "communication"]
spec = mfrm_spec(data; family = :mgmfrm, dimensions = 2, thresholds = :partial_credit,
    discrimination = :none, q_matrix, dimension_labels, validation_report = validation)
println("Experimental fixed-Q MGMFRM: active positive loadings estimated; latent correlation fixed to identity.")
println("Q rows: ", data.item_levels, "; dimensions: ", dimension_labels)
display(q_matrix)

output_dir = mktempdir(mkpath("results/guarded_mgmfrm"); prefix = "$(backend)-", cleanup = false)
# Only CmdStan takes a compiled-model directory; each run gets a fresh one.
backend_options = backend === :cmdstan ?
    (; cmdstan_cache_dir = joinpath(output_dir, "cmdstan-build")) : (;)
println("Output directory: ", relpath(output_dir))
println("Short demonstration: 50 warmup + 50 retained draws per chain; not sufficient for inference.")
fit_result = BayesianMGMFRM.Experimental.fit(spec; backend, ndraws = 50,
    warmup = 50, chains = 2, seed = 20260630, backend_options...)
println(fit_result)
check = diagnostics(fit_result; view = :public)
println("MCMC status: ", check.summary.flag, "; max R-hat: ", check.summary.max_rank_normalized_rhat,
    "; min bulk/tail ESS: ", check.summary.min_bulk_ess, " / ", check.summary.min_tail_ess)
check.summary.passed || println("Review diagnostics(fit_result) before interpreting estimates.")
println("Model-scale summaries below; posterior_summary(fit_result) instead uses raw computational coordinates.")
display([row[(:parameter, :median, :lower, :upper)] for row in BayesianMGMFRM.direct_posterior_summary(fit_result)])

cache_path = joinpath(output_dir, "fit.jls")
save_fit_cache(cache_path, fit_result)
restored = load_fit_cache(cache_path)
@assert isequal(BayesianMGMFRM.direct_posterior_summary(restored), BayesianMGMFRM.direct_posterior_summary(fit_result))
println("Fit saved and reloaded: ", relpath(cache_path))

# These figures use the saved fit. Wright maps are supported only for stable MFRM.
if "--plots" in ARGS
    posterior = BayesianMGMFRM.plot_posterior(restored; scale = :model, block = :person)
    chains = BayesianMGMFRM.plot_diagnostics(restored; scale = :raw,
        block = :person, dimension = "reasoning")
    predictive = BayesianMGMFRM.plot_predictive(restored; ndraws = 200, seed = 42)
    for (name, figure) in (("ability-posterior", posterior), ("reasoning-chains", chains),
            ("category-predictive", predictive))
        save(joinpath(output_dir, "$name.pdf"), figure)
    end
    save(joinpath(output_dir, "ability-posterior.svg"), posterior)
    println("Saved three PDFs and ability-posterior.svg in ", relpath(output_dir))
else
    println("Add --plots after installing CairoMakie to generate figures; see docs/src/examples.md.")
end
