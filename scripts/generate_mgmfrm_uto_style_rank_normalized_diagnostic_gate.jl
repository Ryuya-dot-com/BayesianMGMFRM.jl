#!/usr/bin/env julia

using Dates
using JSON3
using SHA
using Statistics
using TOML

import BayesianMGMFRM

module DrawsX2
include(joinpath(@__DIR__, "generate_mgmfrm_uto_style_draws_x2_smoke_followup.jl"))
end

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_PLAN_JSON =
    joinpath(ROOT, "artifacts",
        "uto_style_block_targeted_warning_followup_plan",
        "uto_style_block_targeted_warning_followup_plan.json")
const DEFAULT_WARNING_SURFACE_JSON =
    joinpath(ROOT, "artifacts",
        "uto_style_sampler_warning_surface_diagnosis",
        "uto_style_sampler_warning_surface_diagnosis.json")
const DEFAULT_DRAWS_X4_JSON =
    joinpath(ROOT, "artifacts", "uto_style_draws_x4_gate_followup",
        "uto_style_draws_x4_gate_followup.json")
const DEFAULT_STAN_REVIEW_JSON =
    joinpath(ROOT, "artifacts",
        "uto_style_stan_guided_sampler_remediation_review",
        "uto_style_stan_guided_sampler_remediation_review.json")
const DEFAULT_OUTPUT_JSON =
    joinpath(ROOT, "artifacts",
        "uto_style_rank_normalized_diagnostic_gate",
        "uto_style_rank_normalized_diagnostic_gate.json")
const DEFAULT_OUTPUT_MD =
    joinpath(ROOT, "artifacts",
        "uto_style_rank_normalized_diagnostic_gate",
        "uto_style_rank_normalized_diagnostic_gate.md")

include(joinpath(@__DIR__, "local_json.jl"))

const OUTPUT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_uto_style_rank_normalized_diagnostic_gate.v1"
const RHAT_THRESHOLD = 1.01
const ESS_THRESHOLD = 400.0

function usage()
    return """
    Run a local rank-normalized R-hat / bulk ESS / tail ESS diagnostic gate.

    This reruns the priority cells with the draws_x4 profile and computes a
    Stan-inspired rank-normalized diagnostic surface for raw and direct
    parameters. The implementation is local and provisional; it is intended to
    decide whether the remaining classical R-hat/ESS warnings are still a
    blocker before public threshold or Q-revision wording.

    Usage:
      julia --project=. scripts/generate_mgmfrm_uto_style_rank_normalized_diagnostic_gate.jl [options]

    Options:
      --plan-json PATH             Block-targeted follow-up plan artifact.
      --warning-surface-json PATH  Baseline warning-surface artifact.
      --draws-x4-json PATH         Draws-x4 gate artifact.
      --stan-review-json PATH      Stan-guided review artifact.
      --output-json PATH           JSON artifact path.
      --output-md PATH             Markdown report path.
      --max-jobs N                 Limit jobs. Default: all draws-x2 priority jobs.
      --progress                   Show sampler progress.
    """
end

function parse_args(args)
    plan_json = DEFAULT_PLAN_JSON
    warning_surface_json = DEFAULT_WARNING_SURFACE_JSON
    draws_x4_json = DEFAULT_DRAWS_X4_JSON
    stan_review_json = DEFAULT_STAN_REVIEW_JSON
    output_json = DEFAULT_OUTPUT_JSON
    output_md = DEFAULT_OUTPUT_MD
    max_jobs = 0
    progress = false

    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--plan-json"
            index < length(args) || error("--plan-json requires a path")
            plan_json = abspath(args[index + 1])
            index += 2
        elseif arg == "--warning-surface-json"
            index < length(args) ||
                error("--warning-surface-json requires a path")
            warning_surface_json = abspath(args[index + 1])
            index += 2
        elseif arg == "--draws-x4-json"
            index < length(args) || error("--draws-x4-json requires a path")
            draws_x4_json = abspath(args[index + 1])
            index += 2
        elseif arg == "--stan-review-json"
            index < length(args) || error("--stan-review-json requires a path")
            stan_review_json = abspath(args[index + 1])
            index += 2
        elseif arg == "--output-json"
            index < length(args) || error("--output-json requires a path")
            output_json = abspath(args[index + 1])
            index += 2
        elseif arg == "--output-md"
            index < length(args) || error("--output-md requires a path")
            output_md = abspath(args[index + 1])
            index += 2
        elseif arg == "--max-jobs"
            index < length(args) || error("--max-jobs requires an integer")
            max_jobs = parse(Int, args[index + 1])
            index += 2
        elseif arg == "--progress"
            progress = true
            index += 1
        elseif arg in ("-h", "--help")
            println(usage())
            exit(0)
        else
            error("unknown argument: $arg")
        end
    end

    isfile(plan_json) || error("plan artifact not found: $plan_json")
    isfile(warning_surface_json) ||
        error("warning-surface artifact not found: $warning_surface_json")
    isfile(draws_x4_json) || error("draws-x4 artifact not found: $draws_x4_json")
    isfile(stan_review_json) ||
        error("Stan-guided review artifact not found: $stan_review_json")
    max_jobs >= 0 || error("--max-jobs must be non-negative")
    return (; plan_json, warning_surface_json, draws_x4_json, stan_review_json,
        output_json, output_md, max_jobs, progress)
end

project_version() =
    String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])
file_sha256(path::AbstractString) = bytes2hex(open(sha256, path))
rel(path::AbstractString) = relpath(path, ROOT)
read_json(path::AbstractString) = JSON3.read(read(path, String))
round3(value) = round(Float64(value); digits = 3)
round4(value) = round(Float64(value); digits = 4)
symbol_value(value) = Symbol(string(value))
int_value(value) = Int(value)

function finite_float(value)
    ismissing(value) && return missing
    float = Float64(value)
    return isfinite(float) ? float : missing
end

round_or_missing(value) =
    ismissing(finite_float(value)) ? missing : round4(finite_float(value))

function normal_quantile(p::Float64)
    0 < p < 1 || throw(ArgumentError("p must be in (0, 1)"))
    a = (-39.69683028665376, 220.9460984245205, -275.9285104469687,
        138.3577518672690, -30.66479806614716, 2.506628277459239)
    b = (-54.47609879822406, 161.5858368580409, -155.6989798598866,
        66.80131188771972, -13.28068155288572)
    c = (-0.007784894002430293, -0.3223964580411365, -2.400758277161838,
        -2.549732539343734, 4.374664141464968, 2.938163982698783)
    d = (0.007784695709041462, 0.3224671290700398,
        2.445134137142996, 3.754408661907416)
    plow = 0.02425
    phigh = 1 - plow
    if p < plow
        q = sqrt(-2 * log(p))
        return (((((c[1] * q + c[2]) * q + c[3]) * q + c[4]) * q +
                 c[5]) * q + c[6]) /
               ((((d[1] * q + d[2]) * q + d[3]) * q + d[4]) * q + 1)
    elseif p > phigh
        q = sqrt(-2 * log(1 - p))
        return -(((((c[1] * q + c[2]) * q + c[3]) * q + c[4]) * q +
                  c[5]) * q + c[6]) /
               ((((d[1] * q + d[2]) * q + d[3]) * q + d[4]) * q + 1)
    else
        q = p - 0.5
        r = q * q
        return (((((a[1] * r + a[2]) * r + a[3]) * r + a[4]) * r +
                 a[5]) * r + a[6]) * q /
               (((((b[1] * r + b[2]) * r + b[3]) * r + b[4]) * r +
                 b[5]) * r + 1)
    end
end

function average_ranks(values::Vector{Float64})
    order = sortperm(values)
    ranks = zeros(Float64, length(values))
    index = 1
    while index <= length(values)
        last = index
        while last < length(values) &&
              values[order[last + 1]] == values[order[index]]
            last += 1
        end
        average = (index + last) / 2
        for rank_index in index:last
            ranks[order[rank_index]] = average
        end
        index = last + 1
    end
    return ranks
end

function quantile_sorted(sorted_values::Vector{Float64}, p::Float64)
    n = length(sorted_values)
    n >= 1 || throw(ArgumentError("empty values"))
    n == 1 && return only(sorted_values)
    position = 1 + (n - 1) * p
    lower = floor(Int, position)
    upper = ceil(Int, position)
    lower == upper && return sorted_values[lower]
    weight = position - lower
    return (1 - weight) * sorted_values[lower] + weight * sorted_values[upper]
end

function draw_matrix_to_array(draws::AbstractMatrix{<:Real}, chains::Int)
    total, nparams = size(draws)
    total % chains == 0 || error("uneven chains")
    iterations = div(total, chains)
    out = Array{Float64}(undef, iterations, chains, nparams)
    for chain in 1:chains
        rows = ((chain - 1) * iterations + 1):(chain * iterations)
        for param in 1:nparams
            out[:, chain, param] .= Float64.(@view draws[rows, param])
        end
    end
    return out
end

function split_matrix(matrix::Matrix{Float64})
    iterations, chains = size(matrix)
    iterations < 4 && return matrix
    half = div(iterations, 2)
    out = Matrix{Float64}(undef, half, 2 * chains)
    for chain in 1:chains
        out[:, 2 * chain - 1] .= matrix[1:half, chain]
        out[:, 2 * chain] .= matrix[(iterations - half + 1):iterations, chain]
    end
    return out
end

function chain_variance(values::AbstractVector{<:Real})
    length(values) <= 1 && return NaN
    return var(Float64.(values); corrected = true)
end

function rhat_ess_matrix(matrix::Matrix{Float64})
    iterations, chains = size(matrix)
    total = iterations * chains
    (chains < 2 || iterations < 2) &&
        return (rhat = NaN, ess = NaN, flag = :insufficient_chains)
    means = [mean(@view matrix[:, chain]) for chain in 1:chains]
    vars = [chain_variance(@view matrix[:, chain]) for chain in 1:chains]
    W = mean(vars)
    B = iterations * chain_variance(means)
    if !(isfinite(W) && isfinite(B)) || W < 0 || B < 0
        return (rhat = NaN, ess = NaN, flag = :degenerate_draws)
    end
    if W == 0
        rhat = B == 0 ? 1.0 : Inf
        ess = B == 0 ? Float64(total) : NaN
        return (rhat = rhat, ess = ess,
            flag = isfinite(rhat) ? :ok : :degenerate_draws)
    end
    var_plus = ((iterations - 1) / iterations) * W + B / iterations
    rhat = sqrt(max(var_plus / W, 0.0))
    autocorrelations = Float64[]
    for lag in 1:(iterations - 1)
        autocov = 0.0
        for chain in 1:chains
            chain_mean = means[chain]
            total_lag = 0.0
            for iteration in 1:(iterations - lag)
                total_lag += (matrix[iteration, chain] - chain_mean) *
                             (matrix[iteration + lag, chain] - chain_mean)
            end
            autocov += total_lag / (iterations - 1)
        end
        push!(autocorrelations, autocov / (chains * W))
    end
    positive_sum = 0.0
    lag = 1
    while lag <= length(autocorrelations)
        if lag == length(autocorrelations)
            autocorrelations[lag] > 0 &&
                (positive_sum += autocorrelations[lag])
            break
        end
        pair_sum = autocorrelations[lag] + autocorrelations[lag + 1]
        pair_sum > 0 || break
        positive_sum += pair_sum
        lag += 2
    end
    tau = max(1.0, 1 + 2 * positive_sum)
    ess = clamp(total / tau, 1.0, Float64(total))
    return (rhat = rhat, ess = ess,
        flag = isfinite(rhat) && isfinite(ess) ? :ok : :degenerate_draws)
end

function rank_normalized_matrix(matrix::Matrix{Float64})
    iterations, chains = size(matrix)
    flat = vec(matrix)
    ranks = average_ranks(flat)
    n = length(flat)
    normalized = [normal_quantile((rank - 0.375) / (n + 0.25))
                  for rank in ranks]
    return reshape(normalized, iterations, chains)
end

function rank_diagnostic_for_matrix(matrix::Matrix{Float64})
    z = rank_normalized_matrix(matrix)
    split_z = split_matrix(z)
    bulk = rhat_ess_matrix(split_z)
    folded = abs.(z .- median(vec(z)))
    folded_rhat = rhat_ess_matrix(split_matrix(folded)).rhat
    finite_rhats = filter(isfinite, [bulk.rhat, folded_rhat])
    rank_rhat = isempty(finite_rhats) ? NaN : maximum(finite_rhats)
    sorted_values = sort(vec(matrix))
    low_q = quantile_sorted(sorted_values, 0.05)
    high_q = quantile_sorted(sorted_values, 0.95)
    low_indicator = split_matrix(Float64.(matrix .<= low_q))
    high_indicator = split_matrix(Float64.(matrix .>= high_q))
    low_ess = rhat_ess_matrix(low_indicator).ess
    high_ess = rhat_ess_matrix(high_indicator).ess
    finite_tail_ess = filter(isfinite, [low_ess, high_ess])
    tail_ess = isempty(finite_tail_ess) ? NaN : minimum(finite_tail_ess)
    return (;
        rank_rhat,
        folded_rank_rhat = folded_rhat,
        bulk_ess = bulk.ess,
        tail_ess,
        low_tail_ess = low_ess,
        high_tail_ess = high_ess,
        flag = (rank_rhat <= RHAT_THRESHOLD &&
                bulk.ess >= ESS_THRESHOLD &&
                tail_ess >= ESS_THRESHOLD) ? :ok : :rank_warning,
    )
end

function rank_parameter_rows(draws::AbstractMatrix{<:Real}, names, chains::Int,
        parameter_space::Symbol)
    values = draw_matrix_to_array(draws, chains)
    iterations, original_chains, nparams = size(values)
    rows = NamedTuple[]
    for param in 1:nparams
        diagnostic = rank_diagnostic_for_matrix(values[:, :, param])
        push!(rows, (;
            parameter_space,
            parameter = String(names[param]),
            diagnostic_method = :rank_normalized_rhat_bulk_tail_ess,
            diagnostic_status = :local_stan_inspired_approximation,
            n_chains = original_chains,
            draws_per_chain = iterations,
            total_draws = iterations * original_chains,
            rank_rhat = round4(diagnostic.rank_rhat),
            folded_rank_rhat = round4(diagnostic.folded_rank_rhat),
            bulk_ess = round4(diagnostic.bulk_ess),
            tail_ess = round4(diagnostic.tail_ess),
            low_tail_ess = round4(diagnostic.low_tail_ess),
            high_tail_ess = round4(diagnostic.high_tail_ess),
            flag = diagnostic.flag,
            public_claim_allowed = false,
        ))
    end
    return rows
end

function block_rows(parameter_rows, blocks, parameter_space::Symbol)
    by_name = Dict(row.parameter => row for row in parameter_rows)
    rows = NamedTuple[]
    for block in blocks
        names = [String(name) for name in block.parameter_names]
        selected = [by_name[name] for name in names if haskey(by_name, name)]
        isempty(selected) && continue
        push!(rows, (;
            parameter_space,
            block = symbol_value(block.block),
            n_parameters = length(selected),
            max_rank_rhat = round4(maximum(row.rank_rhat for row in selected)),
            min_bulk_ess = round4(minimum(row.bulk_ess for row in selected)),
            min_tail_ess = round4(minimum(row.tail_ess for row in selected)),
            n_bad_rank_rhat =
                count(row -> row.rank_rhat > RHAT_THRESHOLD, selected),
            n_low_bulk_ess =
                count(row -> row.bulk_ess < ESS_THRESHOLD, selected),
            n_low_tail_ess =
                count(row -> row.tail_ess < ESS_THRESHOLD, selected),
            flag = any(row -> row.flag !== :ok, selected) ?
                :rank_warning : :ok,
            public_claim_allowed = false,
        ))
    end
    return rows
end

function rank_summary(parameter_rows)
    return (;
        n_parameters = length(parameter_rows),
        max_rank_rhat = round4(maximum(row.rank_rhat for row in parameter_rows)),
        min_bulk_ess = round4(minimum(row.bulk_ess for row in parameter_rows)),
        min_tail_ess = round4(minimum(row.tail_ess for row in parameter_rows)),
        n_bad_rank_rhat =
            count(row -> row.rank_rhat > RHAT_THRESHOLD, parameter_rows),
        n_low_bulk_ess =
            count(row -> row.bulk_ess < ESS_THRESHOLD, parameter_rows),
        n_low_tail_ess =
            count(row -> row.tail_ess < ESS_THRESHOLD, parameter_rows),
        flag = any(row -> row.flag !== :ok, parameter_rows) ?
            :rank_warning : :ok,
    )
end

function fit_for_job(surface, profile, job, progress::Bool)
    options = DrawsX2.run_options(surface, profile, progress)
    cell = DrawsX2.selected_cell(surface, job)
    split_context =
        DrawsX2.WarningSurface.scenario_split(options, cell, job.split_offset)
    scenario = split_context.scenario
    fitopts = split_context.fitopts
    spec = DrawsX2.model_spec(job.model)
    train = DrawsX2.WarningSurface.QMisspec.design_for_rows(
        split_context.split.train_rows,
        spec,
        scenario,
    )
    fit = BayesianMGMFRM.fit(train.spec;
        experimental = true,
        prior = DrawsX2.WarningSurface.QMisspec.SmallMCMC.source_prior(
            fitopts.prior_profile),
        backend = :advancedhmc,
        ndraws = fitopts.draws_per_chain,
        warmup = fitopts.warmup_per_chain,
        chains = fitopts.chains,
        seed = fitopts.seed + scenario.seed_offset +
               DrawsX2.WarningSurface.QMisspec.model_seed_offset(spec.model),
        target_accept = fitopts.target_acceptance,
        progress = fitopts.progress,
    )
    context = DrawsX2.WarningSurface.fit_context(cell, job.split_offset,
        split_context.split_seed, scenario, fitopts)
    return (; fit, context)
end

function draws_x4_row(draws_x4, job)
    matches = [row for row in draws_x4.comparison_rows
        if symbol_value(row.model) === job.model &&
           int_value(row.base_seed) == job.base_seed &&
           symbol_value(row.scenario) === job.scenario &&
           int_value(row.split_offset) == job.split_offset]
    isempty(matches) && error("draws-x4 row not found for $(job.job)")
    return only(matches)
end

function model_row(context, job, fit, raw_summary, direct_summary, draws_x4)
    summary = fit.diagnostic_surface.summary
    return merge(context, (;
        model = job.model,
        model_family = fit.design.spec.family,
        split_offset = job.split_offset,
        chains = Int(summary.n_chains),
        warmup_per_chain = Int(fit.warmup),
        draws_per_chain = Int(summary.draws_per_chain),
        total_draws = Int(summary.total_draws),
        classical_flag = symbol_value(draws_x4.draws_x4_flag),
        classical_max_rhat = round_or_missing(draws_x4.draws_x4_max_rhat),
        classical_min_ess = round_or_missing(draws_x4.draws_x4_min_ess),
        rank_flag = raw_summary.flag,
        raw_max_rank_rhat = raw_summary.max_rank_rhat,
        raw_min_bulk_ess = raw_summary.min_bulk_ess,
        raw_min_tail_ess = raw_summary.min_tail_ess,
        raw_n_bad_rank_rhat = raw_summary.n_bad_rank_rhat,
        raw_n_low_bulk_ess = raw_summary.n_low_bulk_ess,
        raw_n_low_tail_ess = raw_summary.n_low_tail_ess,
        direct_rank_flag = direct_summary.flag,
        direct_max_rank_rhat = direct_summary.max_rank_rhat,
        direct_min_bulk_ess = direct_summary.min_bulk_ess,
        direct_min_tail_ess = direct_summary.min_tail_ess,
        n_divergences = Int(summary.n_divergences),
        n_max_treedepth = Int(summary.n_max_treedepth),
        n_sampler_warnings = Int(summary.n_sampler_warnings),
        public_claim_allowed = false,
    ))
end

function execute_job(surface, draws_x4, profile, job, progress::Bool)
    result = fit_for_job(surface, profile, job, progress)
    fit = result.fit
    diagnostic = fit.diagnostic_surface
    raw_rows = rank_parameter_rows(diagnostic.draws,
        diagnostic.raw_parameter_names, profile.chains, :raw_unconstrained)
    direct_rows = rank_parameter_rows(diagnostic.direct_draws,
        diagnostic.direct_parameter_names, profile.chains, :direct_constrained)
    raw_blocks = block_rows(raw_rows, diagnostic.raw_blocks, :raw_unconstrained)
    direct_blocks =
        block_rows(direct_rows, diagnostic.direct_blocks, :direct_constrained)
    raw_summary = rank_summary(raw_rows)
    direct_summary = rank_summary(direct_rows)
    x4 = draws_x4_row(draws_x4, job)
    return (;
        model_row = model_row(result.context, job, fit, raw_summary,
            direct_summary, x4),
        parameter_rows = [merge(result.context, row, (; model = job.model,
            split_offset = job.split_offset)) for row in vcat(raw_rows, direct_rows)],
        block_rows = [merge(result.context, row, (; model = job.model,
            split_offset = job.split_offset)) for row in vcat(raw_blocks, direct_blocks)],
    )
end

function input_artifact_rows(options)
    return [
        (artifact = :block_targeted_warning_followup_plan,
            path = rel(options.plan_json),
            sha256 = file_sha256(options.plan_json)),
        (artifact = :sampler_warning_surface_diagnosis,
            path = rel(options.warning_surface_json),
            sha256 = file_sha256(options.warning_surface_json)),
        (artifact = :draws_x4_gate_followup,
            path = rel(options.draws_x4_json),
            sha256 = file_sha256(options.draws_x4_json)),
        (artifact = :stan_guided_sampler_remediation_review,
            path = rel(options.stan_review_json),
            sha256 = file_sha256(options.stan_review_json)),
    ]
end

function finding_rows(model_rows)
    cleared = count(row -> row.rank_flag === :ok, model_rows)
    n = length(model_rows)
    return [
        (finding = :rank_normalized_gate_recorded,
            severity = :info,
            evidence = string(n, " priority model/split job(s) rerun"),
            implication = :stan_inspired_rank_diagnostics_available,
            public_claim_allowed = false),
        (finding = :rank_warning_clearance,
            severity = cleared == n ? :info : :warning,
            evidence = string(cleared, "/", n,
                " raw rank diagnostic rows cleared"),
            implication =
                :public_threshold_wording_remains_blocked_if_not_all_clear,
            public_claim_allowed = false),
        (finding = :geometry_still_not_primary,
            severity = all(row -> row.n_divergences == 0 &&
                         row.n_max_treedepth == 0 &&
                         row.n_sampler_warnings == 0, model_rows) ?
                :info : :warning,
            evidence = "divergence/tree-depth/sampler warning counts recorded",
            implication = :parameterization_and_rank_diagnostics_remain_primary,
            public_claim_allowed = false),
        (finding = :public_claims_blocked,
            severity = :blocker,
            evidence = "local rank-normalized gate only",
            implication =
                :do_not_claim_public_fit_thresholds_model_weights_or_q_revisions,
            public_claim_allowed = false),
    ]
end

function table(io, headers, rows)
    println(io, "| ", join(headers, " | "), " |")
    println(io, "| ", join(fill("---", length(headers)), " | "), " |")
    for row in rows
        println(io, "| ", join(string.(row), " | "), " |")
    end
    println(io)
end

function render_markdown(path, artifact)
    mkpath(dirname(path))
    open(path, "w") do io
        println(io, "# Uto-Style Rank-Normalized Diagnostic Gate")
        println(io)
        println(io, "- Generated at: `", artifact.generated_at, "`")
        println(io, "- Local only: `true`")
        println(io, "- Public claims allowed: `false`")
        println(io)
        println(io, "## Findings")
        table(io, ["Finding", "Severity", "Evidence", "Implication"],
            [[row.finding, row.severity, row.evidence, row.implication]
             for row in artifact.finding_rows])
        println(io, "## Model Rows")
        table(io, ["Model", "Split", "Classical Flag", "Classical Rhat",
                "Classical ESS", "Rank Flag", "Rank Rhat", "Bulk ESS",
                "Tail ESS"],
            [[row.model, row.split_offset, row.classical_flag,
                row.classical_max_rhat, row.classical_min_ess, row.rank_flag,
                row.raw_max_rank_rhat, row.raw_min_bulk_ess,
                row.raw_min_tail_ess]
             for row in artifact.model_rows])
        println(io, "## Top Raw Blocks")
        raw_blocks = [row for row in artifact.block_rows
            if row.parameter_space === :raw_unconstrained]
        sorted_blocks = sort(raw_blocks; by = row ->
            (-(row.n_bad_rank_rhat + row.n_low_bulk_ess + row.n_low_tail_ess),
             string(row.block)))
        table(io, ["Model", "Split", "Block", "Rank Rhat", "Bulk ESS",
                "Tail ESS", "Flag"],
            [[row.model, row.split_offset, row.block, row.max_rank_rhat,
                row.min_bulk_ess, row.min_tail_ess, row.flag]
             for row in sorted_blocks[1:min(12, length(sorted_blocks))]])
        println(io, "## Boundary")
        println(io)
        println(io,
            "This local gate implements a Stan-inspired approximation to ",
            "rank-normalized R-hat and bulk/tail ESS. It is not yet a stable ",
            "package diagnostic API and does not authorize public threshold ",
            "or Q-revision claims.")
    end
    return path
end

function build_artifact(options)
    plan = read_json(options.plan_json)
    surface = read_json(options.warning_surface_json)
    draws_x4 = read_json(options.draws_x4_json)
    profile = DrawsX2.profile_by_name(plan, :draws_x4_gate)
    jobs = DrawsX2.smoke_jobs(plan, options.max_jobs)
    model_rows = NamedTuple[]
    parameter_rows = NamedTuple[]
    block_rows_all = NamedTuple[]
    for job in jobs
        result = execute_job(surface, draws_x4, profile, job, options.progress)
        push!(model_rows, result.model_row)
        append!(parameter_rows, result.parameter_rows)
        append!(block_rows_all, result.block_rows)
    end
    findings = finding_rows(model_rows)
    return (;
        schema = OUTPUT_SCHEMA,
        family = :mgmfrm,
        scope = :uto_style_rank_normalized_diagnostic_gate,
        status = :local_rank_normalized_gate_recorded,
        generated_at = string(now(UTC)),
        package = (;
            name = "BayesianMGMFRM",
            version = project_version(),
            julia_version = string(VERSION),
        ),
        local_only = true,
        publication_or_registration_action = false,
        public_fit_metric_claim = false,
        public_q_revision_claim = false,
        automatic_q_revision = false,
        public_model_weight_claim = false,
        sparse_mgmfrm_superiority_claim = false,
        diagnostic_policy = (;
            method = :rank_normalized_rhat_bulk_tail_ess,
            status = :local_stan_inspired_approximation,
            rhat_threshold = RHAT_THRESHOLD,
            ess_threshold = ESS_THRESHOLD,
            tail_ess = :min_indicator_ess_at_5_and_95_percent,
            stable_public_api = false,
        ),
        input_artifacts = input_artifact_rows(options),
        fit_controls = (;
            profile = :draws_x4_gate,
            chains = int_value(profile.chains),
            warmup_per_chain = int_value(profile.warmup_per_chain),
            draws_per_chain = int_value(profile.draws_per_chain),
            target_acceptance = Float64(profile.target_acceptance),
            progress = options.progress,
        ),
        job_rows = jobs,
        model_rows,
        parameter_rows,
        block_rows = block_rows_all,
        finding_rows = findings,
        summary = (;
            passed = all(row -> row.rank_flag === :ok, model_rows),
            n_jobs = length(jobs),
            n_model_rows = length(model_rows),
            n_parameter_rows = length(parameter_rows),
            n_block_rows = length(block_rows_all),
            n_rank_warnings =
                count(row -> row.rank_flag !== :ok, model_rows),
            n_geometry_warning_rows =
                count(row -> row.n_divergences > 0 ||
                       row.n_max_treedepth > 0 ||
                       row.n_sampler_warnings > 0, model_rows),
            no_public_fit_metric_claim = true,
            no_public_q_revision_claim = true,
            no_automatic_q_revision = true,
            no_public_model_weight_claim = true,
            no_sparse_superiority_claim = true,
            next_gate = all(row -> row.rank_flag === :ok, model_rows) ?
                :promote_rank_diagnostics_to_package_surface :
                :parameterization_audit_for_rank_warning_blocks,
        ),
    )
end

function main(args = ARGS)
    options = parse_args(args)
    artifact = build_artifact(options)
    write_artifact(options.output_json, artifact)
    render_markdown(options.output_md, artifact)
    println("wrote ", rel(options.output_json))
    println("wrote ", rel(options.output_md))
    println("jobs=", artifact.summary.n_jobs,
        " rank_warnings=", artifact.summary.n_rank_warnings,
        " geometry_warnings=", artifact.summary.n_geometry_warning_rows,
        " next_gate=", artifact.summary.next_gate)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
