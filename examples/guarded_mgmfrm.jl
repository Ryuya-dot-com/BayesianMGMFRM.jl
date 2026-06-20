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
    examinee = ["E1", "E1", "E1", "E2", "E2", "E2"],
    rater = ["R1", "R2", "R1", "R1", "R2", "R1"],
    item = ["I1", "I1", "I2", "I1", "I2", "I2"],
    task = ["T1", "T1", "T2", "T1", "T2", "T2"],
    score = [0, 1, 2, 1, 0, 2],
)

data = FacetData(ratings;
    person = :examinee,
    rater = :rater,
    item = :item,
    score = :score,
    task = :task,
)

q_matrix = Bool[1 0; 0 1]
spec = mfrm_spec(data;
    thresholds = :partial_credit,
    family = :mgmfrm,
    dimensions = 2,
    q_matrix,
)
design = getdesign(spec; preview = true)

print_header("Guarded MGMFRM Design")
println(data)
println(spec)
println(design)
println("Q-matrix: ", q_matrix)
println("Parameters: ", join(design.parameter_names, ", "))
print_rows("Constraints", constraint_table(spec);
    fields = (:block, :constraint, :status, :note))
manifest = model_manifest(spec)
println("Manifest: object=", manifest.object,
    ", family=", manifest.spec.family,
    ", dimensions=", manifest.spec.dimensions,
    ", estimation_status=", manifest.spec.estimation_status)

fit_result = fit(spec;
    experimental = true,
    seed = 20260630,
    ndraws = 2,
    warmup = 0,
    chains = 1,
    step_size = 0.02,
    max_depth = 8,
    metric = :unit,
)

print_header("Guarded MGMFRM Fit")
println(fit_result)
metadata = fit_metadata(fit_result)
println("Fit metadata: backend=", metadata.backend,
    ", sampler=", metadata.sampler,
    ", draws=", metadata.n_draws,
    ", chains=", metadata.n_chains,
    ", experimental_public=", metadata.experimental_public,
    ", guarded_local_fit=", metadata.guarded_local_fit)
artifact = fit_artifact(fit_result; include_environment = false)
println("Fit artifact: schema=", artifact.schema,
    ", q_matrix=", artifact.q_matrix,
    ", diagnostics=", artifact.diagnostics.summary.flag)
print_rows("Sampler diagnostics", sampler_diagnostics(fit_result);
    fields = (:chain, :acceptance_rate, :n_nonfinite_logdensity, :flag))
print_rows("Posterior summary", posterior_summary(fit_result);
    fields = (:parameter, :mean, :sd, :lower, :upper))
print_rows("WAIC diagnostics", waic_diagnostics(fit_result);
    fields = (:observation, :person, :rater, :item, :waic, :flag))

ppc = posterior_predictive_check(fit_result;
    draw_indices = [1, 2],
    rng = MersenneTwister(20260633),
)
print_rows("Posterior predictive rows", predictive_check_summary(ppc);
    fields = (:statistic, :level, :observed, :replicated_mean, :flag))
