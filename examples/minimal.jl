using BayesianMGMFRM
using Random

function compact_row(row, fields::Tuple)
    return (; (field => getproperty(row, field) for field in fields)...)
end

function print_rows(label, rows; fields = nothing, limit::Int = 4)
    row_vector = collect(rows)
    println(label, " (", length(row_vector), " rows)")
    for row in Iterators.take(row_vector, limit)
        println("  ", fields === nothing ? row : compact_row(row, fields))
    end
    length(row_vector) > limit &&
        println("  ... ", length(row_vector) - limit, " more")
end

function print_header(label)
    println()
    println("== ", label, " ==")
end

ratings = (
    examinee = ["E1", "E1", "E1", "E1", "E2", "E2", "E2", "E2"],
    rater = ["R1", "R2", "R1", "R2", "R1", "R2", "R1", "R2"],
    item = ["I1", "I1", "I2", "I2", "I1", "I1", "I2", "I2"],
    group = ["A", "A", "B", "B", "B", "B", "A", "A"],
    score = [0, 1, 2, 0, 1, 2, 0, 2],
)

data = FacetData(ratings;
    person = :examinee,
    rater = :rater,
    item = :item,
    score = :score,
    group = :group,
)

validation = validate_design(data; bias = [(:rater, :group)])
spec = mfrm_spec(data; thresholds = :partial_credit, validation_report = validation)
design = getdesign(spec)

print_header("Design")
println(data)
println(validation)
println(spec)
println(design)
println("Parameters: ", join(design.parameter_names, ", "))
print_rows("Model ladder", model_ladder(); fields = (:family, :scope, :estimation_status))
print_rows("Constraints", constraint_table(design);
    fields = (:block, :constraint, :status, :n_parameters))
manifest = model_manifest(design)
println("Manifest: schema=", manifest.schema,
    ", object=", manifest.object,
    ", observations=", manifest.data.n_observations,
    ", parameters=", length(design.parameter_names),
    ", validation_issues=", manifest.validation.n_issues)
coverage = coverage_summary(spec)
println("Coverage: ratings=", coverage.n_ratings,
    ", persons=", coverage.n_persons,
    ", raters=", coverage.n_raters,
    ", items=", coverage.n_items,
    ", categories=", coverage.n_categories)
println("Coverage matrix: ", coverage_matrix(data; rows = :rater, columns = :person))
print_rows("Rater overlap", rater_overlap(data))
print_rows("Threshold map", threshold_map_data(design; params = zeros(length(design.parameter_names)));
    fields = (:thresholds, :item, :step, :status, :value))

prior = MFRMPrior()
target = MFRMLogDensity(design; prior)
init = initial_params(target)
print_header("Target")
println("Log-density target: ", target)
println("Initial parameters: ", init)
print_rows("Linear predictor rows at init", linear_predictor_values(design, init);
    fields = (:row, :category, :observed, :eta, :log_probability),
    limit = 6)
println("Log likelihood at init: ", loglikelihood(design, init))
println("Log prior at init: ", logprior(design, init, prior))
println("Log posterior at init: ", logposterior(design, init, prior))
prior_ppc = prior_predictive_check(spec; prior, ndraws = 4, rng = MersenneTwister(101))
cache_path = joinpath(mktempdir(), "minimal_fit.jls")
fit_result = cached_fit(spec;
    cache_path,
    prior,
    ndraws = 4,
    warmup = 4,
    chains = 2,
    step_size = 0.1,
    seed = 102,
)
ppc = posterior_predictive_check(fit_result; ndraws = 4, rng = MersenneTwister(103))

print_header("Fit")
print_rows("Prior predictive rows", predictive_check_summary(prior_ppc);
    fields = (:statistic, :level, :observed, :replicated_mean, :flag))
println("Fit cache path: ", cache_path)
println("Fit cache key: ", fit_cache_key(spec; prior, ndraws = 4, warmup = 4, chains = 2, step_size = 0.1, seed = 102))
metadata = fit_metadata(fit_result)
println("Fit metadata: backend=", metadata.backend,
    ", sampler=", metadata.sampler,
    ", draws=", metadata.n_draws,
    ", chains=", metadata.n_chains,
    ", acceptance_rate=", round(metadata.acceptance_rate; digits = 3))
fit_manifest = model_manifest(fit_result)
println("Fit manifest: object=", fit_manifest.object,
    ", parameters=", fit_manifest.design.n_parameters,
    ", diagnostic_flag=", fit_manifest.diagnostics.flag)
artifact = fit_artifact(fit_result; include_environment = false)
println("Fit artifact: schema=", artifact.schema,
    ", draws=", artifact.reproducibility.artifact_policy.draws,
    ", diagnostics=", artifact.diagnostics.summary.flag)
report = fit_report(fit_result;
    include_prior_predictive = true,
    prior_predictive_ndraws = 4,
    ndraws = 4,
    rng = MersenneTwister(106),
    artifact_include_environment = false)
println("Fit report: schema=", report.schema,
    ", posterior_rows=", report.posterior.n_rows,
    ", calibration_rows=", report.calibration.n_rows,
    ", loo_status=", report.loo.status)
diagnostic_surface = diagnostics(fit_result)
println("Diagnostic summary: ", compact_row(diagnostic_surface.summary,
    (:flag, :passed, :n_chains, :draws_per_chain, :max_rhat, :min_ess)))
print_rows("Sampler diagnostics", diagnostic_surface.sampler_rows;
    fields = (:chain, :acceptance_rate, :n_nonfinite_log_posterior, :flag))
print_rows("MCMC diagnostics", diagnostic_surface.parameter_rows;
    fields = (:parameter, :rhat, :ess, :flag))
print_rows("Parameter block diagnostics", diagnostic_surface.block_rows;
    fields = (:block, :max_rhat, :min_ess, :flag))
print_rows("Posterior summary", posterior_summary(fit_result);
    fields = (:parameter, :mean, :sd, :lower, :upper))
print_rows("WAIC diagnostics", waic_diagnostics(fit_result);
    fields = (:observation, :person, :rater, :item, :waic, :flag))
print_rows("Calibration", calibration_table(fit_result; bins = 2);
    fields = (:target, :bin, :observed_mean, :predicted_mean, :flag))
print_rows("Posterior predictive rows", predictive_check_summary(ppc);
    fields = (:statistic, :level, :observed, :replicated_mean, :flag))
