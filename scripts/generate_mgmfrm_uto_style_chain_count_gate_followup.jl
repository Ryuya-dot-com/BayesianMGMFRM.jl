#!/usr/bin/env julia

using Dates
using JSON3
using SHA
using TOML

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
const DEFAULT_DRAWS_X2_JSON =
    joinpath(ROOT, "artifacts", "uto_style_draws_x2_smoke_followup",
        "uto_style_draws_x2_smoke_followup.json")
const DEFAULT_DRAWS_X4_JSON =
    joinpath(ROOT, "artifacts", "uto_style_draws_x4_gate_followup",
        "uto_style_draws_x4_gate_followup.json")
const DEFAULT_OUTPUT_JSON =
    joinpath(ROOT, "artifacts", "uto_style_chain_count_gate_followup",
        "uto_style_chain_count_gate_followup.json")
const DEFAULT_OUTPUT_MD =
    joinpath(ROOT, "artifacts", "uto_style_chain_count_gate_followup",
        "uto_style_chain_count_gate_followup.md")

include(joinpath(@__DIR__, "local_json.jl"))

const OUTPUT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_uto_style_chain_count_gate_followup.v1"

function usage()
    return """
    Execute the chain-count gate after draws_x2 and draws_x4 follow-ups.

    This reruns the same priority model/split cells with the plan's
    `chains_x6_rhat_check` profile. It is designed to separate residual R-hat
    sensitivity from retained-draw count after draws_x4 improved, but did not
    clear, the MCMC warning surface.

    Usage:
      julia --project=. scripts/generate_mgmfrm_uto_style_chain_count_gate_followup.jl [options]

    Options:
      --plan-json PATH             Block-targeted follow-up plan artifact.
      --warning-surface-json PATH  Baseline warning-surface artifact.
      --draws-x2-json PATH         Draws-x2 smoke artifact.
      --draws-x4-json PATH         Draws-x4 gate artifact.
      --output-json PATH           JSON artifact path.
      --output-md PATH             Markdown report path.
      --max-jobs N                 Limit chain-count jobs. Default: all draws-x2 jobs.
      --progress                   Show sampler progress.
    """
end

function parse_args(args)
    plan_json = DEFAULT_PLAN_JSON
    warning_surface_json = DEFAULT_WARNING_SURFACE_JSON
    draws_x2_json = DEFAULT_DRAWS_X2_JSON
    draws_x4_json = DEFAULT_DRAWS_X4_JSON
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
        elseif arg == "--draws-x2-json"
            index < length(args) || error("--draws-x2-json requires a path")
            draws_x2_json = abspath(args[index + 1])
            index += 2
        elseif arg == "--draws-x4-json"
            index < length(args) || error("--draws-x4-json requires a path")
            draws_x4_json = abspath(args[index + 1])
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
    isfile(draws_x2_json) || error("draws-x2 artifact not found: $draws_x2_json")
    isfile(draws_x4_json) || error("draws-x4 artifact not found: $draws_x4_json")
    max_jobs >= 0 || error("--max-jobs must be non-negative")
    return (; plan_json, warning_surface_json, draws_x2_json, draws_x4_json,
        output_json, output_md, max_jobs, progress)
end

project_version() =
    String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])
file_sha256(path::AbstractString) = bytes2hex(open(sha256, path))
rel(path::AbstractString) = relpath(path, ROOT)
read_json(path::AbstractString) = JSON3.read(read(path, String))
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
delta(new_value, old_value) = round4(finite_float(new_value) - finite_float(old_value))

function chain_jobs(draws_x2, max_jobs::Int)
    rows = [(;
        sequence = int_value(row.sequence),
        source_job = symbol_value(row.job),
        job = Symbol(replace(string(row.job), "draws_x2_smoke" => "chains_x6_rhat")),
        profile = :chains_x6_rhat_check,
        model = symbol_value(row.model),
        base_seed = int_value(row.base_seed),
        scenario = symbol_value(row.scenario),
        split_offset = int_value(row.split_offset),
        target_blocks = [symbol_value(block) for block in row.target_blocks],
        success_check = :separate_chain_count_from_retained_draw_count,
        public_claim_allowed = false,
    ) for row in draws_x2.job_rows]
    max_jobs == 0 && return rows
    return rows[1:min(max_jobs, length(rows))]
end

function model_row(artifact, job)
    matches = [row for row in artifact.model_diagnostic_rows
        if symbol_value(row.model) === job.model &&
           int_value(row.base_seed) == job.base_seed &&
           symbol_value(row.scenario) === job.scenario &&
           int_value(row.split_offset) == job.split_offset]
    isempty(matches) && error("model row not found for $(job.job)")
    return only(matches)
end

function block_row(rows, job, block::Symbol)
    matches = [row for row in rows
        if symbol_value(row.parameter_space) === :raw_unconstrained &&
           symbol_value(row.model) === job.model &&
           int_value(row.base_seed) == job.base_seed &&
           symbol_value(row.scenario) === job.scenario &&
           int_value(row.split_offset) == job.split_offset &&
           symbol_value(row.block) === block]
    isempty(matches) && return nothing
    return only(matches)
end

function comparison_row(job, baseline, draws_x2, draws_x4, chain)
    return (;
        job = job.job,
        source_job = job.source_job,
        model = job.model,
        base_seed = job.base_seed,
        scenario = job.scenario,
        split_offset = job.split_offset,
        baseline_flag = symbol_value(baseline.diagnostic_flag),
        draws_x2_flag = symbol_value(draws_x2.diagnostic_flag),
        draws_x4_flag = symbol_value(draws_x4.diagnostic_flag),
        chain_flag = chain.diagnostic_flag,
        baseline_max_rhat = round_or_missing(baseline.max_rhat),
        draws_x2_max_rhat = round_or_missing(draws_x2.max_rhat),
        draws_x4_max_rhat = round_or_missing(draws_x4.max_rhat),
        chain_max_rhat = chain.max_rhat,
        delta_chain_max_rhat_vs_x2 = delta(chain.max_rhat, draws_x2.max_rhat),
        delta_chain_max_rhat_vs_x4 = delta(chain.max_rhat, draws_x4.max_rhat),
        baseline_min_ess = round_or_missing(baseline.min_ess),
        draws_x2_min_ess = round_or_missing(draws_x2.min_ess),
        draws_x4_min_ess = round_or_missing(draws_x4.min_ess),
        chain_min_ess = chain.min_ess,
        delta_chain_min_ess_vs_x2 = delta(chain.min_ess, draws_x2.min_ess),
        delta_chain_min_ess_vs_x4 = delta(chain.min_ess, draws_x4.min_ess),
        baseline_bad_rhat = int_value(baseline.n_bad_rhat),
        draws_x2_bad_rhat = int_value(draws_x2.n_bad_rhat),
        draws_x4_bad_rhat = int_value(draws_x4.n_bad_rhat),
        chain_bad_rhat = chain.n_bad_rhat,
        delta_chain_bad_rhat_vs_x4 =
            int_value(chain.n_bad_rhat) - int_value(draws_x4.n_bad_rhat),
        baseline_low_ess = int_value(baseline.n_low_ess),
        draws_x2_low_ess = int_value(draws_x2.n_low_ess),
        draws_x4_low_ess = int_value(draws_x4.n_low_ess),
        chain_low_ess = chain.n_low_ess,
        delta_chain_low_ess_vs_x4 =
            int_value(chain.n_low_ess) - int_value(draws_x4.n_low_ess),
        cleared_warning = chain.diagnostic_flag === :ok,
        improved_vs_x4_max_rhat =
            finite_float(chain.max_rhat) < finite_float(draws_x4.max_rhat),
        improved_vs_x4_min_ess =
            finite_float(chain.min_ess) > finite_float(draws_x4.min_ess),
        reduced_vs_x4_warning_counts =
            int_value(chain.n_bad_rhat) <= int_value(draws_x4.n_bad_rhat) &&
            int_value(chain.n_low_ess) <= int_value(draws_x4.n_low_ess),
        public_claim_allowed = false,
    )
end

function block_delta_rows(job, surface, draws_x4, chain_block_rows)
    rows = NamedTuple[]
    for block in job.target_blocks
        base = block_row(surface.block_diagnostic_rows, job, block)
        x4 = block_row(draws_x4.block_diagnostic_rows, job, block)
        chain = block_row(chain_block_rows, job, block)
        (base === nothing || x4 === nothing || chain === nothing) && continue
        push!(rows, (;
            job = job.job,
            model = job.model,
            split_offset = job.split_offset,
            block,
            baseline_max_rhat = round_or_missing(base.max_rhat),
            draws_x4_max_rhat = round_or_missing(x4.max_rhat),
            chain_max_rhat = round_or_missing(chain.max_rhat),
            delta_chain_max_rhat_vs_x4 = delta(chain.max_rhat, x4.max_rhat),
            baseline_min_ess = round_or_missing(base.min_ess),
            draws_x4_min_ess = round_or_missing(x4.min_ess),
            chain_min_ess = round_or_missing(chain.min_ess),
            delta_chain_min_ess_vs_x4 = delta(chain.min_ess, x4.min_ess),
            delta_chain_bad_rhat_vs_x4 =
                int_value(chain.n_bad_rhat) - int_value(x4.n_bad_rhat),
            delta_chain_low_ess_vs_x4 =
                int_value(chain.n_low_ess) - int_value(x4.n_low_ess),
            public_claim_allowed = false,
        ))
    end
    return rows
end

function execute_job(surface, draws_x2, draws_x4, profile, job, progress::Bool)
    result = DrawsX2.execute_job(surface, profile, job, progress)
    baseline = DrawsX2.baseline_model_row(surface, job)
    x2 = model_row(draws_x2, job)
    x4 = model_row(draws_x4, job)
    comp = comparison_row(job, baseline, x2, x4, result.model_row)
    blocks = block_delta_rows(job, surface, draws_x4, result.block_rows)
    return (; result.model_row, result.sampler_rows, result.block_rows,
        comparison_row = comp, block_delta_rows = blocks)
end

function finding_rows(comparisons)
    n = length(comparisons)
    n_clear = count(row -> Bool(row.cleared_warning), comparisons)
    n_rhat = count(row -> Bool(row.improved_vs_x4_max_rhat), comparisons)
    n_ess = count(row -> Bool(row.improved_vs_x4_min_ess), comparisons)
    n_counts = count(row -> Bool(row.reduced_vs_x4_warning_counts),
        comparisons)
    return [
        (finding = :chain_count_gate_executed,
            severity = :info,
            evidence = string(n, " priority model/split job(s)"),
            implication = :chain_count_followup_completed,
            public_claim_allowed = false),
        (finding = :warning_clearance,
            severity = n_clear == n ? :info : :warning,
            evidence = string(n_clear, "/", n,
                " jobs cleared mcmc warnings"),
            implication =
                :remaining_warnings_need_parameterization_or_rank_diagnostics,
            public_claim_allowed = false),
        (finding = :chain_count_rhat_response,
            severity = n_rhat == n ? :info : :warning,
            evidence = string(n_rhat, "/", n,
                " jobs improved max R-hat versus draws_x4"),
            implication = :chain_count_helped_if_rhat_improved,
            public_claim_allowed = false),
        (finding = :chain_count_ess_response,
            severity = n_ess == n ? :info : :warning,
            evidence = string(n_ess, "/", n,
                " jobs improved min ESS versus draws_x4"),
            implication = :draws_may_matter_more_than_chain_count_if_not,
            public_claim_allowed = false),
        (finding = :public_claims_blocked,
            severity = :blocker,
            evidence = "local chain-count gate only",
            implication =
                :do_not_claim_public_fit_thresholds_model_weights_or_q_revisions,
            public_claim_allowed = false),
    ]
end

function input_artifact_rows(options)
    return [
        (artifact = :block_targeted_warning_followup_plan,
            path = rel(options.plan_json),
            sha256 = file_sha256(options.plan_json)),
        (artifact = :sampler_warning_surface_diagnosis,
            path = rel(options.warning_surface_json),
            sha256 = file_sha256(options.warning_surface_json)),
        (artifact = :draws_x2_smoke_followup,
            path = rel(options.draws_x2_json),
            sha256 = file_sha256(options.draws_x2_json)),
        (artifact = :draws_x4_gate_followup,
            path = rel(options.draws_x4_json),
            sha256 = file_sha256(options.draws_x4_json)),
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
        println(io, "# Uto-Style Chain-Count Gate Follow-Up")
        println(io)
        println(io, "- Generated at: `", artifact.generated_at, "`")
        println(io, "- Local only: `true`")
        println(io, "- Public claims allowed: `false`")
        println(io)
        println(io, "## Findings")
        table(io, ["Finding", "Severity", "Evidence", "Implication"],
            [[row.finding, row.severity, row.evidence, row.implication]
             for row in artifact.finding_rows])
        println(io, "## Model Comparisons")
        table(io, ["Job", "Flag", "dRhat vs x4", "dESS vs x4",
                "dBad vs x4", "dLow vs x4"],
            [[row.job, row.chain_flag, row.delta_chain_max_rhat_vs_x4,
                row.delta_chain_min_ess_vs_x4,
                row.delta_chain_bad_rhat_vs_x4,
                row.delta_chain_low_ess_vs_x4]
             for row in artifact.comparison_rows])
        println(io, "## Target Block Deltas")
        table(io, ["Job", "Block", "dRhat vs x4", "dESS vs x4",
                "dBad vs x4", "dLow vs x4"],
            [[row.job, row.block, row.delta_chain_max_rhat_vs_x4,
                row.delta_chain_min_ess_vs_x4,
                row.delta_chain_bad_rhat_vs_x4,
                row.delta_chain_low_ess_vs_x4]
             for row in artifact.block_delta_rows])
        println(io, "## Boundary")
        println(io)
        println(io,
            "This gate isolates chain-count effects after retained draws helped ",
            "but did not fully clear warnings. It is not public fit-threshold or ",
            "model-selection evidence.")
    end
    return path
end

function build_artifact(options)
    plan = read_json(options.plan_json)
    surface = read_json(options.warning_surface_json)
    draws_x2 = read_json(options.draws_x2_json)
    draws_x4 = read_json(options.draws_x4_json)
    profile = DrawsX2.profile_by_name(plan, :chains_x6_rhat_check)
    jobs = chain_jobs(draws_x2, options.max_jobs)
    model_rows = NamedTuple[]
    sampler_rows = NamedTuple[]
    block_rows = NamedTuple[]
    comparisons = NamedTuple[]
    block_deltas = NamedTuple[]
    for job in jobs
        result = execute_job(surface, draws_x2, draws_x4, profile, job,
            options.progress)
        push!(model_rows, result.model_row)
        append!(sampler_rows, result.sampler_rows)
        append!(block_rows, result.block_rows)
        push!(comparisons, result.comparison_row)
        append!(block_deltas, result.block_delta_rows)
    end
    findings = finding_rows(comparisons)
    return (;
        schema = OUTPUT_SCHEMA,
        family = :mgmfrm,
        scope = :uto_style_chain_count_gate_followup,
        status = :local_chain_count_gate_recorded,
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
            profile = :chains_x6_rhat_check,
            chains = int_value(profile.chains),
            warmup_per_chain = int_value(profile.warmup_per_chain),
            draws_per_chain = int_value(profile.draws_per_chain),
            target_acceptance = Float64(profile.target_acceptance),
            progress = options.progress,
        ),
        job_rows = jobs,
        model_diagnostic_rows = model_rows,
        sampler_chain_rows = sampler_rows,
        block_diagnostic_rows = block_rows,
        comparison_rows = comparisons,
        block_delta_rows = block_deltas,
        finding_rows = findings,
        summary = (;
            passed = all(row -> Bool(row.cleared_warning), comparisons),
            n_jobs = length(jobs),
            n_model_diagnostic_rows = length(model_rows),
            n_warning_rows =
                count(row -> row.diagnostic_flag !== :ok, model_rows),
            n_warnings_cleared =
                count(row -> Bool(row.cleared_warning), comparisons),
            n_max_rhat_improved_vs_x4 =
                count(row -> Bool(row.improved_vs_x4_max_rhat), comparisons),
            n_min_ess_improved_vs_x4 =
                count(row -> Bool(row.improved_vs_x4_min_ess), comparisons),
            n_warning_counts_reduced_vs_x4 =
                count(row -> Bool(row.reduced_vs_x4_warning_counts),
                    comparisons),
            no_public_fit_metric_claim = true,
            no_public_q_revision_claim = true,
            no_automatic_q_revision = true,
            no_public_model_weight_claim = true,
            no_sparse_superiority_claim = true,
            next_gate = all(row -> Bool(row.cleared_warning), comparisons) ?
                :expand_chain_count_gate_to_split_stable_cells :
                :parameterization_audit_and_rank_normalized_diagnostics,
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
        " warnings=", artifact.summary.n_warning_rows,
        " cleared=", artifact.summary.n_warnings_cleared,
        " rhat_improved_vs_x4=",
        artifact.summary.n_max_rhat_improved_vs_x4,
        " ess_improved_vs_x4=", artifact.summary.n_min_ess_improved_vs_x4,
        " next_gate=", artifact.summary.next_gate)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
