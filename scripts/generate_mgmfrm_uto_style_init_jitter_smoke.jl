#!/usr/bin/env julia

using Dates
using JSON3
using SHA
using TOML

import BayesianMGMFRM

module RankGate
include(joinpath(@__DIR__,
    "generate_mgmfrm_uto_style_rank_normalized_diagnostic_gate.jl"))
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
const DEFAULT_RANK_GATE_JSON =
    joinpath(ROOT, "artifacts",
        "uto_style_rank_normalized_diagnostic_gate",
        "uto_style_rank_normalized_diagnostic_gate.json")
const DEFAULT_PARAMETERIZATION_AUDIT_JSON =
    joinpath(ROOT, "artifacts",
        "uto_style_rank_warning_parameterization_audit",
        "uto_style_rank_warning_parameterization_audit.json")
const DEFAULT_OUTPUT_JSON =
    joinpath(ROOT, "artifacts",
        "uto_style_init_jitter_smoke",
        "uto_style_init_jitter_smoke.json")
const DEFAULT_OUTPUT_MD =
    joinpath(ROOT, "artifacts",
        "uto_style_init_jitter_smoke",
        "uto_style_init_jitter_smoke.md")

include(joinpath(@__DIR__, "local_json.jl"))

const OUTPUT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_uto_style_init_jitter_smoke.v1"
const DEFAULT_INIT_JITTER = 0.05

function usage()
    return """
    Run an init-jitter smoke check for the rank-warning MGMFRM cells.

    This reruns the same three priority cells as the rank-normalized gate with
    the draws_x4 budget and a small nonzero raw initial jitter. It checks
    whether the remaining rank/bulk/tail warnings are sensitive to all chains
    starting at the same zero raw vector.

    Usage:
      julia --project=. scripts/generate_mgmfrm_uto_style_init_jitter_smoke.jl [options]

    Options:
      --plan-json PATH              Block-targeted follow-up plan artifact.
      --warning-surface-json PATH   Baseline warning-surface artifact.
      --draws-x4-json PATH          Draws-x4 comparison artifact.
      --rank-gate-json PATH         Baseline rank-normalized gate artifact.
      --parameterization-json PATH  Parameterization-audit artifact.
      --output-json PATH            JSON artifact path.
      --output-md PATH              Markdown report path.
      --init-jitter VALUE           Raw initial jitter. Default: 0.05.
      --max-jobs N                  Limit jobs. Default: all priority jobs.
      --progress                    Show sampler progress.
    """
end

function parse_args(args)
    plan_json = DEFAULT_PLAN_JSON
    warning_surface_json = DEFAULT_WARNING_SURFACE_JSON
    draws_x4_json = DEFAULT_DRAWS_X4_JSON
    rank_gate_json = DEFAULT_RANK_GATE_JSON
    parameterization_json = DEFAULT_PARAMETERIZATION_AUDIT_JSON
    output_json = DEFAULT_OUTPUT_JSON
    output_md = DEFAULT_OUTPUT_MD
    init_jitter = DEFAULT_INIT_JITTER
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
        elseif arg == "--rank-gate-json"
            index < length(args) || error("--rank-gate-json requires a path")
            rank_gate_json = abspath(args[index + 1])
            index += 2
        elseif arg == "--parameterization-json"
            index < length(args) ||
                error("--parameterization-json requires a path")
            parameterization_json = abspath(args[index + 1])
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
    for path in (plan_json, warning_surface_json, draws_x4_json,
            rank_gate_json, parameterization_json)
        isfile(path) || error("input artifact not found: $path")
    end
    isfinite(init_jitter) && init_jitter >= 0 ||
        error("--init-jitter must be finite and non-negative")
    max_jobs >= 0 || error("--max-jobs must be non-negative")
    return (; plan_json, warning_surface_json, draws_x4_json, rank_gate_json,
        parameterization_json, output_json, output_md, init_jitter, max_jobs,
        progress)
end

project_version() =
    String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])
file_sha256(path::AbstractString) = bytes2hex(open(sha256, path))
rel(path::AbstractString) = relpath(path, ROOT)
read_json(path::AbstractString) = JSON3.read(read(path, String))
symbol_value(value) = Symbol(string(value))
int_value(value) = Int(value)
round4(value) = round(Float64(value); digits = 4)

function rank_gate_row(rank_gate, job)
    matches = [row for row in rank_gate.model_rows
        if symbol_value(row.model) === symbol_value(job.model) &&
           int_value(row.base_seed) == int_value(job.base_seed) &&
           symbol_value(row.scenario) === symbol_value(job.scenario) &&
           int_value(row.split_offset) == int_value(job.split_offset)]
    isempty(matches) && error("rank gate row not found for $(job.job)")
    return only(matches)
end

function fit_for_job(surface, profile, job, progress::Bool, init_jitter::Float64)
    options = RankGate.DrawsX2.run_options(surface, profile, progress)
    cell = RankGate.DrawsX2.selected_cell(surface, job)
    split_context =
        RankGate.DrawsX2.WarningSurface.scenario_split(
            options,
            cell,
            job.split_offset,
        )
    scenario = split_context.scenario
    fitopts = split_context.fitopts
    spec = RankGate.DrawsX2.model_spec(job.model)
    train = RankGate.DrawsX2.WarningSurface.QMisspec.design_for_rows(
        split_context.split.train_rows,
        spec,
        scenario,
    )
    fit = BayesianMGMFRM.fit(train.spec;
        experimental = true,
        prior = RankGate.DrawsX2.WarningSurface.QMisspec.SmallMCMC.source_prior(
            fitopts.prior_profile),
        backend = :advancedhmc,
        ndraws = fitopts.draws_per_chain,
        warmup = fitopts.warmup_per_chain,
        chains = fitopts.chains,
        seed = fitopts.seed + scenario.seed_offset +
               RankGate.DrawsX2.WarningSurface.QMisspec.model_seed_offset(
                   spec.model),
        target_accept = fitopts.target_acceptance,
        init_jitter,
        progress = fitopts.progress,
    )
    context = RankGate.DrawsX2.WarningSurface.fit_context(
        cell,
        job.split_offset,
        split_context.split_seed,
        scenario,
        fitopts,
    )
    return (; fit, context)
end

function model_row(context, job, fit, raw_summary, direct_summary, baseline,
        init_jitter)
    summary = fit.diagnostic_surface.summary
    delta_rhat = round4(raw_summary.max_rank_rhat -
                        Float64(baseline.raw_max_rank_rhat))
    delta_bulk = round4(raw_summary.min_bulk_ess -
                        Float64(baseline.raw_min_bulk_ess))
    delta_tail = round4(raw_summary.min_tail_ess -
                        Float64(baseline.raw_min_tail_ess))
    improved = delta_rhat < 0 && (delta_bulk > 0 || delta_tail > 0)
    cleared = raw_summary.flag === :ok
    return merge(context, (;
        model = symbol_value(job.model),
        model_family = fit.design.spec.family,
        split_offset = int_value(job.split_offset),
        chains = Int(summary.n_chains),
        warmup_per_chain = Int(fit.warmup),
        draws_per_chain = Int(summary.draws_per_chain),
        total_draws = Int(summary.total_draws),
        init_jitter,
        baseline_rank_flag = symbol_value(baseline.rank_flag),
        baseline_max_rank_rhat = round4(baseline.raw_max_rank_rhat),
        baseline_min_bulk_ess = round4(baseline.raw_min_bulk_ess),
        baseline_min_tail_ess = round4(baseline.raw_min_tail_ess),
        jitter_rank_flag = raw_summary.flag,
        jitter_max_rank_rhat = raw_summary.max_rank_rhat,
        jitter_min_bulk_ess = raw_summary.min_bulk_ess,
        jitter_min_tail_ess = raw_summary.min_tail_ess,
        delta_max_rank_rhat = delta_rhat,
        delta_min_bulk_ess = delta_bulk,
        delta_min_tail_ess = delta_tail,
        cleared_rank_warning = cleared,
        improved_rank_surface = improved,
        direct_rank_flag = direct_summary.flag,
        n_divergences = Int(summary.n_divergences),
        n_max_treedepth = Int(summary.n_max_treedepth),
        n_sampler_warnings = Int(summary.n_sampler_warnings),
        public_claim_allowed = false,
    ))
end

function execute_job(surface, rank_gate, profile, job, progress::Bool,
        init_jitter::Float64)
    result = fit_for_job(surface, profile, job, progress, init_jitter)
    diagnostic = result.fit.diagnostic_surface
    raw_rows = RankGate.rank_parameter_rows(diagnostic.draws,
        diagnostic.raw_parameter_names, int_value(profile.chains),
        :raw_unconstrained)
    direct_rows = RankGate.rank_parameter_rows(diagnostic.direct_draws,
        diagnostic.direct_parameter_names, int_value(profile.chains),
        :direct_constrained)
    raw_summary = RankGate.rank_summary(raw_rows)
    direct_summary = RankGate.rank_summary(direct_rows)
    baseline = rank_gate_row(rank_gate, job)
    return (;
        model_row = model_row(result.context, job, result.fit, raw_summary,
            direct_summary, baseline, init_jitter),
        parameter_rows = [merge(result.context, row, (; model = job.model,
            split_offset = job.split_offset, init_jitter))
            for row in vcat(raw_rows, direct_rows)],
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
        (artifact = :rank_normalized_diagnostic_gate,
            path = rel(options.rank_gate_json),
            sha256 = file_sha256(options.rank_gate_json)),
        (artifact = :rank_warning_parameterization_audit,
            path = rel(options.parameterization_json),
            sha256 = file_sha256(options.parameterization_json)),
    ]
end

function finding_rows(model_rows)
    n = length(model_rows)
    cleared = count(row -> Bool(row.cleared_rank_warning), model_rows)
    improved = count(row -> Bool(row.improved_rank_surface), model_rows)
    geometry = count(row -> row.n_divergences > 0 ||
                           row.n_max_treedepth > 0 ||
                           row.n_sampler_warnings > 0, model_rows)
    return [
        (finding = :init_jitter_smoke_recorded,
            severity = :info,
            evidence = string(n, " priority cell(s) rerun"),
            implication = :initialization_sensitivity_checked,
            public_claim_allowed = false),
        (finding = :rank_warning_clearance,
            severity = cleared == n ? :info : :warning,
            evidence = string(cleared, "/", n, " rank warnings cleared"),
            implication = :continue_parameterization_audit_if_not_all_clear,
            public_claim_allowed = false),
        (finding = :rank_surface_improvement,
            severity = improved > 0 ? :info : :warning,
            evidence = string(improved, "/", n,
                " rows improved max rank Rhat with ESS support"),
            implication =
                :init_jitter_is_not_sufficient_if_improvement_is_partial,
            public_claim_allowed = false),
        (finding = :geometry_check,
            severity = geometry == 0 ? :info : :warning,
            evidence = string(geometry, "/", n, " geometry warning rows"),
            implication = geometry == 0 ?
                :rank_parameterization_remains_primary :
                :geometry_controls_need_review,
            public_claim_allowed = false),
        (finding = :public_claims_blocked,
            severity = :blocker,
            evidence = :local_init_jitter_smoke_only,
            implication =
                :do_not_claim_public_thresholds_q_revisions_or_model_weights,
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
        println(io, "# Uto-Style Init-Jitter Smoke")
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
        table(io, ["Model", "Split", "Base Flag", "Jitter Flag",
                "Base Rhat", "Jitter Rhat", "dRhat", "Base Bulk",
                "Jitter Bulk", "dBulk", "Base Tail", "Jitter Tail",
                "dTail", "Cleared"],
            [[row.model, row.split_offset, row.baseline_rank_flag,
                row.jitter_rank_flag, row.baseline_max_rank_rhat,
                row.jitter_max_rank_rhat, row.delta_max_rank_rhat,
                row.baseline_min_bulk_ess, row.jitter_min_bulk_ess,
                row.delta_min_bulk_ess, row.baseline_min_tail_ess,
                row.jitter_min_tail_ess, row.delta_min_tail_ess,
                row.cleared_rank_warning]
             for row in artifact.model_rows])
        println(io, "## Boundary")
        println(io)
        println(io,
            "This is a local initialization-sensitivity smoke check. It does ",
            "not authorize public fit-threshold, Q-revision, model-weight, or ",
            "sparse-superiority claims.")
    end
    return path
end

function build_artifact(options)
    plan = read_json(options.plan_json)
    surface = read_json(options.warning_surface_json)
    read_json(options.draws_x4_json)
    rank_gate = read_json(options.rank_gate_json)
    read_json(options.parameterization_json)
    profile = RankGate.DrawsX2.profile_by_name(plan, :draws_x4_gate)
    jobs = RankGate.DrawsX2.smoke_jobs(plan, options.max_jobs)
    model_rows = NamedTuple[]
    parameter_rows = NamedTuple[]
    for job in jobs
        result = execute_job(surface, rank_gate, profile, job,
            options.progress, Float64(options.init_jitter))
        push!(model_rows, result.model_row)
        append!(parameter_rows, result.parameter_rows)
    end
    findings = finding_rows(model_rows)
    return (;
        schema = OUTPUT_SCHEMA,
        family = :mgmfrm,
        scope = :uto_style_init_jitter_smoke,
        status = :local_init_jitter_smoke_recorded,
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
            progress = options.progress,
        ),
        job_rows = jobs,
        model_rows,
        parameter_rows,
        finding_rows = findings,
        summary = (;
            passed = all(row -> Bool(row.cleared_rank_warning), model_rows),
            n_jobs = length(jobs),
            n_model_rows = length(model_rows),
            n_parameter_rows = length(parameter_rows),
            n_rank_warnings =
                count(row -> row.jitter_rank_flag !== :ok, model_rows),
            n_rank_warnings_cleared =
                count(row -> Bool(row.cleared_rank_warning), model_rows),
            n_rank_surface_improved =
                count(row -> Bool(row.improved_rank_surface), model_rows),
            n_geometry_warning_rows =
                count(row -> row.n_divergences > 0 ||
                       row.n_max_treedepth > 0 ||
                       row.n_sampler_warnings > 0, model_rows),
            no_public_fit_metric_claim = true,
            no_public_q_revision_claim = true,
            no_automatic_q_revision = true,
            no_public_model_weight_claim = true,
            no_sparse_superiority_claim = true,
            next_gate = all(row -> Bool(row.cleared_rank_warning), model_rows) ?
                :replicate_init_jitter_before_api_change :
                :person_item_step_coupling_parameterization_pilot,
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
        " cleared=", artifact.summary.n_rank_warnings_cleared,
        " improved=", artifact.summary.n_rank_surface_improved,
        " geometry=", artifact.summary.n_geometry_warning_rows,
        " next_gate=", artifact.summary.next_gate)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
