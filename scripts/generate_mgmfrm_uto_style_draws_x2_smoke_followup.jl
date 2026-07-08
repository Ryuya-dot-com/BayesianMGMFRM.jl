#!/usr/bin/env julia

using Dates
using JSON3
using SHA
using TOML

module WarningSurface
include(joinpath(@__DIR__,
    "generate_mgmfrm_uto_style_sampler_warning_surface_diagnosis.jl"))
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
const DEFAULT_OUTPUT_JSON =
    joinpath(ROOT, "artifacts", "uto_style_draws_x2_smoke_followup",
        "uto_style_draws_x2_smoke_followup.json")
const DEFAULT_OUTPUT_MD =
    joinpath(ROOT, "artifacts", "uto_style_draws_x2_smoke_followup",
        "uto_style_draws_x2_smoke_followup.md")

include(joinpath(@__DIR__, "local_json.jl"))

const OUTPUT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_uto_style_draws_x2_smoke_followup.v1"

function usage()
    return """
    Execute the draws_x2 smoke jobs from the block-targeted warning plan.

    The smoke run reruns only the priority model/split cells with twice the
    retained draws. It checks whether the raw R-hat/ESS warning surface improves
    before launching a wider or more expensive grid.

    Usage:
      julia --project=. scripts/generate_mgmfrm_uto_style_draws_x2_smoke_followup.jl [options]

    Options:
      --plan-json PATH             Block-targeted follow-up plan artifact.
      --warning-surface-json PATH  Baseline warning-surface artifact.
      --output-json PATH           JSON artifact path.
      --output-md PATH             Markdown report path.
      --max-jobs N                 Limit smoke jobs. Default: all draws_x2 jobs.
      --progress                   Show sampler progress.
    """
end

function parse_args(args)
    plan_json = DEFAULT_PLAN_JSON
    warning_surface_json = DEFAULT_WARNING_SURFACE_JSON
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
    max_jobs >= 0 || error("--max-jobs must be non-negative")
    return (; plan_json, warning_surface_json, output_json, output_md,
        max_jobs, progress)
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

function smoke_jobs(plan, max_jobs::Int)
    rows = [(;
        sequence = int_value(row.sequence),
        job = symbol_value(row.job),
        profile = symbol_value(row.profile),
        model = symbol_value(row.model),
        base_seed = int_value(row.base_seed),
        scenario = symbol_value(row.scenario),
        split_offset = int_value(row.split_offset),
        target_blocks = [symbol_value(block) for block in row.target_blocks],
        success_check = symbol_value(row.success_check),
        public_claim_allowed = false,
    ) for row in plan.execution_job_rows
        if symbol_value(row.profile) === :draws_x2_smoke]
    max_jobs == 0 && return rows
    return rows[1:min(max_jobs, length(rows))]
end

function profile_by_name(plan, name::Symbol)
    matches = [row for row in plan.budget_profile_rows
        if symbol_value(row.profile) === name]
    isempty(matches) && error("profile not found: $name")
    return only(matches)
end

function selected_cell(surface, job)
    matches = [row for row in surface.selected_cell_rows
        if int_value(row.base_seed) == int_value(job.base_seed) &&
           symbol_value(row.scenario) === symbol_value(job.scenario)]
    isempty(matches) && error("selected cell not found for job $(job.job)")
    row = only(matches)
    return (;
        scenario = symbol_value(row.scenario),
        axis = symbol_value(row.axis),
        base_seed = int_value(row.base_seed),
        actual_seed = int_value(row.actual_seed),
        previous_n_threshold_risk_changes =
            int_value(row.previous_n_threshold_risk_changes),
        previous_delta_candidate_log_score =
            Float64(row.previous_delta_candidate_log_score),
        previous_changed_threshold_risks =
            [symbol_value(value)
             for value in row.previous_changed_threshold_risks],
    )
end

function model_spec(model::Symbol)
    matches = [spec for spec in WarningSurface.QMisspec.MCMC_MODEL_SPECS
        if spec.model === model]
    isempty(matches) && error("model spec not found: $model")
    return only(matches)
end

function baseline_model_row(surface, job)
    matches = [row for row in surface.model_diagnostic_rows
        if symbol_value(row.model) === symbol_value(job.model) &&
           int_value(row.base_seed) == int_value(job.base_seed) &&
           symbol_value(row.scenario) === symbol_value(job.scenario) &&
           int_value(row.split_offset) == int_value(job.split_offset)]
    isempty(matches) && error("baseline model row not found for $(job.job)")
    return only(matches)
end

function baseline_block_row(surface, job, block::Symbol)
    matches = [row for row in surface.block_diagnostic_rows
        if symbol_value(row.parameter_space) === :raw_unconstrained &&
           symbol_value(row.model) === symbol_value(job.model) &&
           int_value(row.base_seed) == int_value(job.base_seed) &&
           symbol_value(row.scenario) === symbol_value(job.scenario) &&
           int_value(row.split_offset) == int_value(job.split_offset) &&
           symbol_value(row.block) === block]
    isempty(matches) && return nothing
    return only(matches)
end

function run_options(surface, profile, progress::Bool)
    return (;
        n_persons = int_value(surface.design.n_persons),
        n_items = int_value(surface.design.n_items),
        n_raters = int_value(surface.design.n_raters),
        heldout_fraction = Float64(surface.design.heldout_fraction),
        chains = int_value(profile.chains),
        warmup_per_chain = int_value(profile.warmup_per_chain),
        draws_per_chain = int_value(profile.draws_per_chain),
        target_acceptance = Float64(profile.target_acceptance),
        prior_profile = symbol_value(surface.fit_controls.prior_profile),
        progress,
    )
end

function comparison_row(job, baseline, smoke)
    delta_min_ess = finite_float(smoke.min_ess) - finite_float(baseline.min_ess)
    delta_max_rhat =
        finite_float(smoke.max_rhat) - finite_float(baseline.max_rhat)
    delta_bad_rhat = int_value(smoke.n_bad_rhat) -
                     int_value(baseline.n_bad_rhat)
    delta_low_ess = int_value(smoke.n_low_ess) -
                    int_value(baseline.n_low_ess)
    return (;
        job = symbol_value(job.job),
        model = symbol_value(job.model),
        base_seed = int_value(job.base_seed),
        scenario = symbol_value(job.scenario),
        split_offset = int_value(job.split_offset),
        baseline_flag = symbol_value(baseline.diagnostic_flag),
        smoke_flag = smoke.diagnostic_flag,
        baseline_max_rhat = round_or_missing(baseline.max_rhat),
        smoke_max_rhat = smoke.max_rhat,
        delta_max_rhat = round4(delta_max_rhat),
        baseline_min_ess = round_or_missing(baseline.min_ess),
        smoke_min_ess = smoke.min_ess,
        delta_min_ess = round4(delta_min_ess),
        baseline_bad_rhat = int_value(baseline.n_bad_rhat),
        smoke_bad_rhat = smoke.n_bad_rhat,
        delta_bad_rhat,
        baseline_low_ess = int_value(baseline.n_low_ess),
        smoke_low_ess = smoke.n_low_ess,
        delta_low_ess,
        improved_min_ess = delta_min_ess > 0,
        improved_max_rhat = delta_max_rhat < 0,
        reduced_warning_counts = delta_bad_rhat <= 0 && delta_low_ess <= 0,
        public_claim_allowed = false,
    )
end

function block_delta_rows(job, surface, smoke_block_rows)
    rows = NamedTuple[]
    targets = [symbol_value(block) for block in job.target_blocks]
    for block in targets
        base = baseline_block_row(surface, job, block)
        base === nothing && continue
        matches = [row for row in smoke_block_rows
            if symbol_value(row.parameter_space) === :raw_unconstrained &&
               symbol_value(row.block) === block]
        isempty(matches) && continue
        smoke = only(matches)
        push!(rows, (;
            job = symbol_value(job.job),
            model = symbol_value(job.model),
            split_offset = int_value(job.split_offset),
            block,
            baseline_max_rhat = round_or_missing(base.max_rhat),
            smoke_max_rhat = smoke.max_rhat,
            delta_max_rhat =
                round4(finite_float(smoke.max_rhat) -
                       finite_float(base.max_rhat)),
            baseline_min_ess = round_or_missing(base.min_ess),
            smoke_min_ess = smoke.min_ess,
            delta_min_ess =
                round4(finite_float(smoke.min_ess) -
                       finite_float(base.min_ess)),
            baseline_bad_rhat = int_value(base.n_bad_rhat),
            smoke_bad_rhat = smoke.n_bad_rhat,
            delta_bad_rhat =
                int_value(smoke.n_bad_rhat) - int_value(base.n_bad_rhat),
            baseline_low_ess = int_value(base.n_low_ess),
            smoke_low_ess = smoke.n_low_ess,
            delta_low_ess =
                int_value(smoke.n_low_ess) - int_value(base.n_low_ess),
            public_claim_allowed = false,
        ))
    end
    return rows
end

function execute_job(surface, profile, job, progress::Bool)
    options = run_options(surface, profile, progress)
    cell = selected_cell(surface, job)
    split_context =
        WarningSurface.scenario_split(options, cell, int_value(job.split_offset))
    scenario = split_context.scenario
    fitopts = split_context.fitopts
    context = WarningSurface.fit_context(cell, int_value(job.split_offset),
        split_context.split_seed, scenario, fitopts)
    result = WarningSurface.model_diagnostic_rows(
        model_spec(symbol_value(job.model)),
        scenario,
        split_context,
        split_context.split.train_rows,
        split_context.generated.rows,
        split_context.split.heldout_indices,
        fitopts,
        context,
    )
    baseline = baseline_model_row(surface, job)
    comp = comparison_row(job, baseline, result.model_row)
    blocks = block_delta_rows(job, surface, result.block_rows)
    return (; model_row = result.model_row, sampler_rows = result.sampler_rows,
        block_rows = result.block_rows, comparison_row = comp,
        block_delta_rows = blocks)
end

function finding_rows(comparisons)
    n = length(comparisons)
    min_ess_improved = count(row -> Bool(row.improved_min_ess), comparisons)
    rhat_improved = count(row -> Bool(row.improved_max_rhat), comparisons)
    counts_reduced = count(row -> Bool(row.reduced_warning_counts),
        comparisons)
    return [
        (finding = :draws_x2_smoke_executed,
            severity = :info,
            evidence = string(n, " priority model/split job(s)"),
            implication = :first_budget_followup_completed,
            public_claim_allowed = false),
        (finding = :min_ess_response,
            severity = min_ess_improved == n ? :info : :warning,
            evidence = string(min_ess_improved, "/", n,
                " jobs improved minimum ESS"),
            implication = :assess_whether_draw_count_is_sufficient,
            public_claim_allowed = false),
        (finding = :rhat_response,
            severity = rhat_improved == n ? :info : :warning,
            evidence = string(rhat_improved, "/", n,
                " jobs improved maximum R-hat"),
            implication = :assess_whether_chain_count_or_parameterization_matters,
            public_claim_allowed = false),
        (finding = :warning_count_response,
            severity = counts_reduced == n ? :info : :warning,
            evidence = string(counts_reduced, "/", n,
                " jobs reduced both bad-Rhat and low-ESS counts"),
            implication = :large_grid_should_wait_if_counts_do_not_improve,
            public_claim_allowed = false),
        (finding = :public_claims_blocked,
            severity = :blocker,
            evidence = "local draws_x2 smoke only",
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
        println(io, "# Uto-Style Draws-x2 Smoke Follow-Up")
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
        table(io, ["Job", "Flag", "dMaxRhat", "dMinESS", "dBadRhat",
                "dLowESS"],
            [[row.job, row.smoke_flag, row.delta_max_rhat,
                row.delta_min_ess, row.delta_bad_rhat, row.delta_low_ess]
             for row in artifact.comparison_rows])
        println(io, "## Target Block Deltas")
        table(io, ["Job", "Block", "dMaxRhat", "dMinESS", "dBadRhat",
                "dLowESS"],
            [[row.job, row.block, row.delta_max_rhat, row.delta_min_ess,
                row.delta_bad_rhat, row.delta_low_ess]
             for row in artifact.block_delta_rows])
        println(io, "## Boundary")
        println(io)
        println(io,
            "This smoke run tests whether more retained draws move the warning ",
            "surface in the expected direction. It is not a public fit-threshold ",
            "or model-selection result.")
    end
    return path
end

function build_artifact(options)
    plan = read_json(options.plan_json)
    surface = read_json(options.warning_surface_json)
    profile = profile_by_name(plan, :draws_x2_smoke)
    jobs = smoke_jobs(plan, options.max_jobs)
    model_rows = NamedTuple[]
    sampler_rows = NamedTuple[]
    block_rows = NamedTuple[]
    comparison_rows = NamedTuple[]
    block_deltas = NamedTuple[]
    for job in jobs
        result = execute_job(surface, profile, job, options.progress)
        push!(model_rows, result.model_row)
        append!(sampler_rows, result.sampler_rows)
        append!(block_rows, result.block_rows)
        push!(comparison_rows, result.comparison_row)
        append!(block_deltas, result.block_delta_rows)
    end
    findings = finding_rows(comparison_rows)
    return (;
        schema = OUTPUT_SCHEMA,
        family = :mgmfrm,
        scope = :uto_style_draws_x2_smoke_followup,
        status = :local_draws_x2_smoke_recorded,
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
            profile = :draws_x2_smoke,
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
        comparison_rows,
        block_delta_rows = block_deltas,
        finding_rows = findings,
        summary = (;
            passed = all(row -> Bool(row.improved_min_ess),
                comparison_rows),
            n_jobs = length(jobs),
            n_model_diagnostic_rows = length(model_rows),
            n_warning_rows =
                count(row -> row.diagnostic_flag !== :ok, model_rows),
            n_min_ess_improved =
                count(row -> Bool(row.improved_min_ess), comparison_rows),
            n_max_rhat_improved =
                count(row -> Bool(row.improved_max_rhat), comparison_rows),
            n_warning_counts_reduced =
                count(row -> Bool(row.reduced_warning_counts),
                    comparison_rows),
            no_public_fit_metric_claim = true,
            no_public_q_revision_claim = true,
            no_automatic_q_revision = true,
            no_public_model_weight_claim = true,
            no_sparse_superiority_claim = true,
            next_gate =
                all(row -> Bool(row.improved_min_ess), comparison_rows) ?
                :run_draws_x4_gate_or_chain_count_check :
                :prioritize_parameterization_audit_before_larger_grid,
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
        " min_ess_improved=", artifact.summary.n_min_ess_improved,
        " rhat_improved=", artifact.summary.n_max_rhat_improved,
        " next_gate=", artifact.summary.next_gate)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
