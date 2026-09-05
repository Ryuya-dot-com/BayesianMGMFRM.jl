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
    score = [0, 1, 2, 1, 0, 2],
)

data = FacetData(ratings;
    person = :examinee,
    rater = :rater,
    item = :item,
    score = :score,
)
validation = validate_design(data)
validation.passed || error(validation)

# Q rows follow `data.item_levels`; columns follow `dimension_labels`.
q_matrix = Bool[1 0; 0 1]
spec = mfrm_spec(data;
    thresholds = :partial_credit,
    family = :mgmfrm,
    dimensions = 2,
    dimension_labels = ["reasoning", "communication"],
    discrimination = :none,
    q_matrix,
    anchors = [],
    validation_report = validation,
)
design = getdesign(spec; preview = true)

print_header("Guarded MGMFRM Design")
println(data)
println(spec)
println(design)
println("Validation passed: ", validation.passed)
println("Q row order: ", data.item_levels)
println("Q-matrix: ", q_matrix)
println("Parameters: ", join(design.parameter_names, ", "))
print_rows("Constraints", constraint_table(spec);
    fields = (:block, :constraint, :status, :note))
manifest = model_manifest(spec; view = :public)
println("Manifest: object=", manifest.object,
    ", family=", manifest.spec.family,
    ", dimensions=", manifest.spec.dimensions,
    ", status=experimental preview")

smoke_controls = (;
    seed = 20260630,
    ndraws = 2,
    warmup = 0,
    chains = 1,
    step_size = 0.02,
    max_depth = 8,
    metric = :unit,
)
fit_result = BayesianMGMFRM.Experimental.fit(spec; smoke_controls...)

print_header("Guarded MGMFRM Fit")
println(fit_result)
metadata = fit_metadata(fit_result; view = :public)
println("Fit metadata: backend=", metadata.backend,
    ", sampler=", metadata.sampler,
    ", draws=", metadata.n_draws,
    ", chains=", metadata.n_chains,
    ", status=experimental")
diagnostic_surface = diagnostics(fit_result; view = :public)
println("Overall diagnostics: ", diagnostic_surface.summary.flag)
print_rows("Sampler diagnostics", sampler_diagnostics(fit_result);
    fields = (:chain, :acceptance_rate, :n_nonfinite_logdensity, :flag))
print_rows("Posterior summary", posterior_summary(fit_result);
    fields = (:parameter, :mean, :sd, :lower, :upper))

ppc = posterior_predictive_check(fit_result;
    draw_indices = [1, 2],
    rng = MersenneTwister(20260633),
)
print_rows("Posterior predictive rows", predictive_check_summary(ppc);
    fields = (:statistic, :level, :observed, :replicated_mean, :flag))

println()
println("Smoke completed. Two draws and one chain are not suitable for inference.")
