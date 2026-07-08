#!/usr/bin/env julia

using Dates
using JSON3
using SHA
using Statistics
using TOML

module InitJitter
include(joinpath(@__DIR__, "generate_mgmfrm_uto_style_init_jitter_smoke.jl"))
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
const DEFAULT_PARAMETERIZATION_JSON =
    joinpath(ROOT, "artifacts",
        "uto_style_rank_warning_parameterization_audit",
        "uto_style_rank_warning_parameterization_audit.json")
const DEFAULT_INIT_JITTER_JSON =
    joinpath(ROOT, "artifacts",
        "uto_style_init_jitter_smoke",
        "uto_style_init_jitter_smoke.json")
const DEFAULT_OUTPUT_JSON =
    joinpath(ROOT, "artifacts",
        "uto_style_person_item_step_coupling_pilot",
        "uto_style_person_item_step_coupling_pilot.json")
const DEFAULT_OUTPUT_MD =
    joinpath(ROOT, "artifacts",
        "uto_style_person_item_step_coupling_pilot",
        "uto_style_person_item_step_coupling_pilot.md")

include(joinpath(@__DIR__, "local_json.jl"))

const OUTPUT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_uto_style_person_item_step_coupling_pilot.v1"
const DEFAULT_INIT_JITTER = 0.0
const DEFAULT_TOP_COUPLINGS = 6
const STRONG_CORRELATION = 0.70
const MODERATE_CORRELATION = 0.40

function usage()
    return """
    Run a posterior-draw coupling pilot for person/item/item-step warning blocks.

    This reruns the same draws_x4 priority cells, computes rank diagnostics,
    measures chain-mean separation for warning parameters, and records the
    strongest posterior draw correlations between warning parameters and the
    person/item/item-step-related blocks.

    Usage:
      julia --project=. scripts/generate_mgmfrm_uto_style_person_item_step_coupling_pilot.jl [options]

    Options:
      --plan-json PATH              Block-targeted follow-up plan artifact.
      --warning-surface-json PATH   Baseline warning-surface artifact.
      --parameterization-json PATH  Parameterization-audit artifact.
      --init-jitter-json PATH       Init-jitter smoke artifact.
      --output-json PATH            JSON artifact path.
      --output-md PATH              Markdown report path.
      --init-jitter VALUE           Raw initial jitter. Default: 0.0.
      --top-couplings N             Top couplings per warning parameter. Default: 6.
      --max-jobs N                  Limit jobs. Default: all priority jobs.
      --progress                    Show sampler progress.
    """
end

function parse_args(args)
    plan_json = DEFAULT_PLAN_JSON
    warning_surface_json = DEFAULT_WARNING_SURFACE_JSON
    parameterization_json = DEFAULT_PARAMETERIZATION_JSON
    init_jitter_json = DEFAULT_INIT_JITTER_JSON
    output_json = DEFAULT_OUTPUT_JSON
    output_md = DEFAULT_OUTPUT_MD
    init_jitter = DEFAULT_INIT_JITTER
    top_couplings = DEFAULT_TOP_COUPLINGS
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
        elseif arg == "--parameterization-json"
            index < length(args) ||
                error("--parameterization-json requires a path")
            parameterization_json = abspath(args[index + 1])
            index += 2
        elseif arg == "--init-jitter-json"
            index < length(args) ||
                error("--init-jitter-json requires a path")
            init_jitter_json = abspath(args[index + 1])
            index += 2
        elseif arg == "--output-json"
            index < length(args) || error("--output-json requires a path")
            output_json = abspath(args[index + 1])
            index += 2
        elseif arg == "--output-md"
            index < length(args) || error("--output-md requires a path")
            output_md = abspath(args[index + 1])
            index += 2
        elseif arg == "--init-jitter"
            index < length(args) || error("--init-jitter requires a value")
            init_jitter = parse(Float64, args[index + 1])
            index += 2
        elseif arg == "--top-couplings"
            index < length(args) || error("--top-couplings requires an integer")
            top_couplings = parse(Int, args[index + 1])
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
    for path in (plan_json, warning_surface_json, parameterization_json,
            init_jitter_json)
        isfile(path) || error("input artifact not found: $path")
    end
    isfinite(init_jitter) && init_jitter >= 0 ||
        error("--init-jitter must be finite and non-negative")
    top_couplings >= 1 || error("--top-couplings must be positive")
    max_jobs >= 0 || error("--max-jobs must be non-negative")
    return (; plan_json, warning_surface_json, parameterization_json,
        init_jitter_json, output_json, output_md, init_jitter, top_couplings,
        max_jobs, progress)
end

project_version() =
    String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])
file_sha256(path::AbstractString) = bytes2hex(open(sha256, path))
rel(path::AbstractString) = relpath(path, ROOT)
read_json(path::AbstractString) = JSON3.read(read(path, String))
symbol_value(value) = Symbol(string(value))
int_value(value) = Int(value)
round4(value) = round(Float64(value); digits = 4)
round_or_missing(value) = isfinite(Float64(value)) ? round4(value) : missing

function parameter_block(parameter::AbstractString)
    startswith(parameter, "person[") && return :person
    startswith(parameter, "item_step[") && return :item_steps
    startswith(parameter, "item[") && return :item
    startswith(parameter, "raw_log_item_dimension_discrimination[") &&
        return :log_item_dimension_discrimination
    startswith(parameter, "raw_log_rater_consistency[") &&
        return :log_rater_consistency_free
    startswith(parameter, "raw_rater[") && return :rater_free
    return :other
end

function warning_rows_for_job(parameterization, job)
    rows = NamedTuple[]
    for row in parameterization.warning_parameter_rows
        symbol_value(row.model) === symbol_value(job.model) || continue
        int_value(row.base_seed) == int_value(job.base_seed) || continue
        symbol_value(row.scenario) === symbol_value(job.scenario) || continue
        int_value(row.split_offset) == int_value(job.split_offset) || continue
        push!(rows, (;
            parameter = String(row.parameter),
            block = symbol_value(row.block),
            baseline_rank_rhat = round4(row.rank_rhat),
            baseline_bulk_ess = round4(row.bulk_ess),
            baseline_tail_ess = round4(row.tail_ess),
            baseline_warning_reasons =
                [symbol_value(reason) for reason in row.warning_reasons],
        ))
    end
    return rows
end

function pearson(x::AbstractVector{<:Real}, y::AbstractVector{<:Real})
    length(x) == length(y) || throw(ArgumentError("vectors must have equal length"))
    length(x) >= 2 || return NaN
    mx = mean(x)
    my = mean(y)
    dx = Float64.(x) .- mx
    dy = Float64.(y) .- my
    sx = sqrt(sum(abs2, dx))
    sy = sqrt(sum(abs2, dy))
    (sx == 0 || sy == 0) && return NaN
    return sum(dx .* dy) / (sx * sy)
end

function chain_separation_by_name(draws::AbstractMatrix{<:Real}, names,
        chains::Int)
    values = InitJitter.RankGate.draw_matrix_to_array(draws, chains)
    out = Dict{String,NamedTuple}()
    for param in axes(values, 3)
        matrix = values[:, :, param]
        flat = vec(matrix)
        sd = std(flat)
        means = [mean(@view matrix[:, chain]) for chain in 1:chains]
        mean_range = maximum(means) - minimum(means)
        mean_range_z = sd == 0 ? 0.0 : mean_range / sd
        out[String(names[param])] = (;
            chain_mean_min = round4(minimum(means)),
            chain_mean_max = round4(maximum(means)),
            chain_mean_range = round4(mean_range),
            chain_mean_range_z = round4(mean_range_z),
            chain_sd = round4(sd),
        )
    end
    return out
end

function action_hint(target_block::Symbol, coupled_block::Symbol)
    target_block === :item_steps &&
        coupled_block in (:item, :person) &&
        return :item_step_location_or_ability_coupling
    target_block === :item &&
        coupled_block === :item_steps &&
        return :item_location_threshold_coupling
    target_block === :person &&
        coupled_block in (:item, :item_steps) &&
        return :person_location_threshold_coupling
    target_block === coupled_block &&
        return Symbol("within_", target_block, "_coupling")
    return :general_cross_block_coupling
end

function coupling_rows_for_warning(draws, names, name_to_index, chain_stats,
        warning, current_row, model_context, top_couplings::Int)
    haskey(name_to_index, warning.parameter) ||
        error("warning parameter not found in draw names: $(warning.parameter)")
    target_index = name_to_index[warning.parameter]
    target_draws = @view draws[:, target_index]
    rows = NamedTuple[]
    for (other_index, other_name_raw) in pairs(names)
        other_name = String(other_name_raw)
        other_index == target_index && continue
        coupled_block = parameter_block(other_name)
        coupled_block in (:person, :item, :item_steps,
            :log_item_dimension_discrimination, :log_rater_consistency_free,
            :rater_free) || continue
        corr = pearson(target_draws, @view draws[:, other_index])
        isfinite(corr) || continue
        target_block = symbol_value(warning.block)
        push!(rows, merge(model_context, (;
            target_parameter = warning.parameter,
            target_block,
            coupled_parameter = other_name,
            coupled_block,
            correlation = round4(corr),
            abs_correlation = round4(abs(corr)),
            current_rank_rhat = round4(current_row.rank_rhat),
            current_bulk_ess = round4(current_row.bulk_ess),
            current_tail_ess = round4(current_row.tail_ess),
            baseline_rank_rhat = warning.baseline_rank_rhat,
            baseline_bulk_ess = warning.baseline_bulk_ess,
            baseline_tail_ess = warning.baseline_tail_ess,
            baseline_warning_reasons = warning.baseline_warning_reasons,
            target_chain_mean_range_z =
                chain_stats[warning.parameter].chain_mean_range_z,
            coupled_chain_mean_range_z =
                chain_stats[other_name].chain_mean_range_z,
            action_hint = action_hint(target_block, coupled_block),
            public_claim_allowed = false,
        )))
    end
    sorted = sort(rows; by = row -> (-row.abs_correlation,
        string(row.coupled_block), string(row.coupled_parameter)))
    return sorted[1:min(top_couplings, length(sorted))]
end

function model_summary_row(context, job, fit, raw_summary, warning_rows,
        coupling_rows)
    summary = fit.diagnostic_surface.summary
    max_corr = isempty(coupling_rows) ? missing :
        maximum(row.abs_correlation for row in coupling_rows)
    max_chain_sep = isempty(coupling_rows) ? missing :
        maximum(row.target_chain_mean_range_z for row in coupling_rows)
    strongest = isempty(coupling_rows) ? missing :
        coupling_rows[argmax(row.abs_correlation for row in coupling_rows)]
    return merge(context, (;
        model = symbol_value(job.model),
        split_offset = int_value(job.split_offset),
        chains = Int(summary.n_chains),
        warmup_per_chain = Int(fit.warmup),
        draws_per_chain = Int(summary.draws_per_chain),
        total_draws = Int(summary.total_draws),
        rank_flag = raw_summary.flag,
        max_rank_rhat = raw_summary.max_rank_rhat,
        min_bulk_ess = raw_summary.min_bulk_ess,
        min_tail_ess = raw_summary.min_tail_ess,
        n_warning_parameters = length(warning_rows),
        max_abs_warning_correlation = max_corr,
        max_target_chain_mean_range_z = max_chain_sep,
        strongest_coupling = ismissing(strongest) ? missing :
            string(strongest.target_parameter, " -> ",
                strongest.coupled_parameter),
        strongest_action_hint = ismissing(strongest) ? missing :
            strongest.action_hint,
        n_divergences = Int(summary.n_divergences),
        n_max_treedepth = Int(summary.n_max_treedepth),
        n_sampler_warnings = Int(summary.n_sampler_warnings),
        public_claim_allowed = false,
    ))
end

function execute_job(surface, parameterization, profile, job, options)
    result = InitJitter.fit_for_job(surface, profile, job, options.progress,
        Float64(options.init_jitter))
    diagnostic = result.fit.diagnostic_surface
    chains = int_value(profile.chains)
    raw_rows = InitJitter.RankGate.rank_parameter_rows(diagnostic.draws,
        diagnostic.raw_parameter_names, chains, :raw_unconstrained)
    raw_summary = InitJitter.RankGate.rank_summary(raw_rows)
    current_by_name = Dict(row.parameter => row for row in raw_rows)
    name_to_index = Dict(String(name) => index
        for (index, name) in pairs(diagnostic.raw_parameter_names))
    chain_stats = chain_separation_by_name(diagnostic.draws,
        diagnostic.raw_parameter_names, chains)
    warning_rows = warning_rows_for_job(parameterization, job)
    model_context = merge(result.context, (;
        model = symbol_value(job.model),
        split_offset = int_value(job.split_offset),
        init_jitter = Float64(options.init_jitter),
    ))
    coupling_rows = NamedTuple[]
    for warning in warning_rows
        haskey(current_by_name, warning.parameter) ||
            error("current diagnostic missing warning parameter $(warning.parameter)")
        append!(coupling_rows, coupling_rows_for_warning(
            diagnostic.draws,
            diagnostic.raw_parameter_names,
            name_to_index,
            chain_stats,
            warning,
            current_by_name[warning.parameter],
            model_context,
            int_value(options.top_couplings),
        ))
    end
    return (;
        model_row = model_summary_row(result.context, job, result.fit,
            raw_summary, warning_rows, coupling_rows),
        coupling_rows,
    )
end

function block_coupling_summary(coupling_rows)
    keys = sort(unique((row.target_block, row.coupled_block)
        for row in coupling_rows); by = pair -> string(pair[1], ":", pair[2]))
    rows = NamedTuple[]
    for (target_block, coupled_block) in keys
        selected = [row for row in coupling_rows
            if row.target_block === target_block &&
               row.coupled_block === coupled_block]
        push!(rows, (;
            target_block,
            coupled_block,
            n_pairs = length(selected),
            max_abs_correlation =
                round4(maximum(row.abs_correlation for row in selected)),
            mean_abs_correlation =
                round4(mean(row.abs_correlation for row in selected)),
            n_strong = count(row -> row.abs_correlation >= STRONG_CORRELATION,
                selected),
            n_moderate = count(row -> row.abs_correlation >= MODERATE_CORRELATION,
                selected),
            action_hint = only(sort(unique(row.action_hint for row in selected);
                by = string)[1:1]),
            public_claim_allowed = false,
        ))
    end
    return sort(rows; by = row -> (-row.max_abs_correlation,
        string(row.target_block), string(row.coupled_block)))
end

function input_artifact_rows(options)
    return [
        (artifact = :block_targeted_warning_followup_plan,
            path = rel(options.plan_json),
            sha256 = file_sha256(options.plan_json)),
        (artifact = :sampler_warning_surface_diagnosis,
            path = rel(options.warning_surface_json),
            sha256 = file_sha256(options.warning_surface_json)),
        (artifact = :rank_warning_parameterization_audit,
            path = rel(options.parameterization_json),
            sha256 = file_sha256(options.parameterization_json)),
        (artifact = :init_jitter_smoke,
            path = rel(options.init_jitter_json),
            sha256 = file_sha256(options.init_jitter_json)),
    ]
end

function finding_rows(model_rows, coupling_rows)
    max_corr = isempty(coupling_rows) ? 0.0 :
        maximum(row.abs_correlation for row in coupling_rows)
    n_strong = count(row -> row.abs_correlation >= STRONG_CORRELATION,
        coupling_rows)
    n_geometry = count(row -> row.n_divergences > 0 ||
                             row.n_max_treedepth > 0 ||
                             row.n_sampler_warnings > 0, model_rows)
    return [
        (finding = :coupling_pilot_recorded,
            severity = :info,
            evidence = string(length(coupling_rows), " top coupling row(s)"),
            implication = :posterior_draw_coupling_surface_available,
            public_claim_allowed = false),
        (finding = :strong_coupling_detected,
            severity = n_strong > 0 ? :warning : :info,
            evidence = string(n_strong, " row(s) >= ", STRONG_CORRELATION,
                "; max=", round4(max_corr)),
            implication = n_strong > 0 ?
                :parameterization_pilot_should_target_strong_pairs :
                :coupling_not_dominant_under_current_threshold,
            public_claim_allowed = false),
        (finding = :geometry_still_not_primary,
            severity = n_geometry == 0 ? :info : :warning,
            evidence = string(n_geometry, "/", length(model_rows),
                " model rows had geometry warnings"),
            implication = n_geometry == 0 ?
                :focus_block_parameterization :
                :review_geometry_controls_before_reparameterization,
            public_claim_allowed = false),
        (finding = :public_claims_blocked,
            severity = :blocker,
            evidence = :local_coupling_pilot_only,
            implication =
                :do_not_claim_public_thresholds_q_revisions_or_model_weights,
            public_claim_allowed = false),
    ]
end

function next_gate(coupling_rows)
    any(row -> row.abs_correlation >= STRONG_CORRELATION &&
               row.action_hint in (:item_location_threshold_coupling,
                   :item_step_location_or_ability_coupling),
        coupling_rows) &&
        return :orthogonal_item_step_contrast_design_pilot
    any(row -> row.abs_correlation >= STRONG_CORRELATION &&
               row.action_hint === :person_location_threshold_coupling,
        coupling_rows) &&
        return :person_block_location_contrast_design_pilot
    return :replicate_coupling_pilot_or_extend_draw_budget
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
        println(io, "# Uto-Style Person/Item/Item-Step Coupling Pilot")
        println(io)
        println(io, "- Generated at: `", artifact.generated_at, "`")
        println(io, "- Init jitter: `", artifact.fit_controls.init_jitter, "`")
        println(io, "- Local only: `true`")
        println(io, "- Public claims allowed: `false`")
        println(io)
        println(io, "## Findings")
        table(io, ["Finding", "Severity", "Evidence", "Implication"],
            [[row.finding, row.severity, row.evidence, row.implication]
             for row in artifact.finding_rows])
        println(io, "## Model Rows")
        table(io, ["Model", "Split", "Rank Flag", "Rank Rhat", "Bulk ESS",
                "Tail ESS", "Warnings", "Max Corr", "Max Chain Sep",
                "Strongest"],
            [[row.model, row.split_offset, row.rank_flag, row.max_rank_rhat,
                row.min_bulk_ess, row.min_tail_ess, row.n_warning_parameters,
                row.max_abs_warning_correlation,
                row.max_target_chain_mean_range_z, row.strongest_coupling]
             for row in artifact.model_rows])
        println(io, "## Top Couplings")
        table(io, ["Model", "Split", "Target", "Target Block", "Coupled",
                "Coupled Block", "Corr", "Abs Corr", "Hint"],
            [[row.model, row.split_offset, row.target_parameter,
                row.target_block, row.coupled_parameter, row.coupled_block,
                row.correlation, row.abs_correlation, row.action_hint]
             for row in artifact.coupling_rows[1:min(24,
                 length(artifact.coupling_rows))]])
        println(io, "## Block Coupling Summary")
        table(io, ["Target Block", "Coupled Block", "Pairs", "Max Abs Corr",
                "Mean Abs Corr", "Strong", "Moderate", "Hint"],
            [[row.target_block, row.coupled_block, row.n_pairs,
                row.max_abs_correlation, row.mean_abs_correlation,
                row.n_strong, row.n_moderate, row.action_hint]
             for row in artifact.block_coupling_rows])
        println(io, "## Boundary")
        println(io)
        println(io,
            "This pilot measures posterior draw coupling under the current ",
            "guarded parameterization. It does not change the package API and ",
            "does not authorize public fit-threshold, Q-revision, model-weight, ",
            "or sparse-superiority claims.")
    end
    return path
end

function build_artifact(options)
    plan = read_json(options.plan_json)
    surface = read_json(options.warning_surface_json)
    parameterization = read_json(options.parameterization_json)
    read_json(options.init_jitter_json)
    profile = InitJitter.RankGate.DrawsX2.profile_by_name(plan, :draws_x4_gate)
    jobs = InitJitter.RankGate.DrawsX2.smoke_jobs(plan, options.max_jobs)
    model_rows = NamedTuple[]
    coupling_rows = NamedTuple[]
    for job in jobs
        result = execute_job(surface, parameterization, profile, job, options)
        push!(model_rows, result.model_row)
        append!(coupling_rows, result.coupling_rows)
    end
    sorted_couplings = sort(coupling_rows;
        by = row -> (-row.abs_correlation, string(row.target_parameter),
            string(row.coupled_parameter)))
    block_rows = block_coupling_summary(sorted_couplings)
    findings = finding_rows(model_rows, sorted_couplings)
    return (;
        schema = OUTPUT_SCHEMA,
        family = :mgmfrm,
        scope = :uto_style_person_item_step_coupling_pilot,
        status = :local_coupling_pilot_recorded,
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
        input_artifacts = input_artifact_rows(options),
        fit_controls = (;
            profile = :draws_x4_gate,
            chains = int_value(profile.chains),
            warmup_per_chain = int_value(profile.warmup_per_chain),
            draws_per_chain = int_value(profile.draws_per_chain),
            target_acceptance = Float64(profile.target_acceptance),
            init_jitter = Float64(options.init_jitter),
            top_couplings = int_value(options.top_couplings),
            progress = options.progress,
        ),
        diagnostic_policy = (;
            strong_correlation = STRONG_CORRELATION,
            moderate_correlation = MODERATE_CORRELATION,
            parameterization_patch_applied = false,
            public_claim_allowed = false,
        ),
        job_rows = jobs,
        model_rows,
        coupling_rows = sorted_couplings,
        block_coupling_rows = block_rows,
        finding_rows = findings,
        summary = (;
            passed = true,
            n_jobs = length(jobs),
            n_model_rows = length(model_rows),
            n_coupling_rows = length(sorted_couplings),
            n_strong_couplings =
                count(row -> row.abs_correlation >= STRONG_CORRELATION,
                    sorted_couplings),
            n_moderate_couplings =
                count(row -> row.abs_correlation >= MODERATE_CORRELATION,
                    sorted_couplings),
            max_abs_correlation = isempty(sorted_couplings) ? missing :
                maximum(row.abs_correlation for row in sorted_couplings),
            n_geometry_warning_rows =
                count(row -> row.n_divergences > 0 ||
                       row.n_max_treedepth > 0 ||
                       row.n_sampler_warnings > 0, model_rows),
            no_public_fit_metric_claim = true,
            no_public_q_revision_claim = true,
            no_automatic_q_revision = true,
            no_public_model_weight_claim = true,
            no_sparse_superiority_claim = true,
            next_gate = next_gate(sorted_couplings),
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
        " strong=", artifact.summary.n_strong_couplings,
        " max_corr=", artifact.summary.max_abs_correlation,
        " geometry=", artifact.summary.n_geometry_warning_rows,
        " next_gate=", artifact.summary.next_gate)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
