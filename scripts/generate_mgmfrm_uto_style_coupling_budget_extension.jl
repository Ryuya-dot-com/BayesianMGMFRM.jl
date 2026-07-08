#!/usr/bin/env julia

using Dates
using JSON3
using SHA
using TOML

module CouplingPilot
include(joinpath(@__DIR__,
    "generate_mgmfrm_uto_style_person_item_step_coupling_pilot.jl"))
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
const DEFAULT_BASELINE_COUPLING_JSON =
    joinpath(ROOT, "artifacts",
        "uto_style_person_item_step_coupling_pilot",
        "uto_style_person_item_step_coupling_pilot.json")
const DEFAULT_OUTPUT_JSON =
    joinpath(ROOT, "artifacts",
        "uto_style_coupling_budget_extension",
        "uto_style_coupling_budget_extension.json")
const DEFAULT_OUTPUT_MD =
    joinpath(ROOT, "artifacts",
        "uto_style_coupling_budget_extension",
        "uto_style_coupling_budget_extension.md")

include(joinpath(@__DIR__, "local_json.jl"))

const OUTPUT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_uto_style_coupling_budget_extension.v1"

function usage()
    return """
    Run an extended-draw coupling stability gate for the rank-warning cells.

    By default this keeps the draws_x4 warmup and chains, doubles retained
    draws per chain, and compares rank/coupling summaries against the previous
    person/item/item-step coupling pilot.

    Usage:
      julia --project=. scripts/generate_mgmfrm_uto_style_coupling_budget_extension.jl [options]

    Options:
      --plan-json PATH              Block-targeted follow-up plan artifact.
      --warning-surface-json PATH   Baseline warning-surface artifact.
      --parameterization-json PATH  Parameterization-audit artifact.
      --baseline-coupling-json PATH Previous coupling pilot artifact.
      --output-json PATH            JSON artifact path.
      --output-md PATH              Markdown report path.
      --draws-multiplier N          Retained-draw multiplier vs draws_x4. Default: 2.
      --warmup-multiplier N         Warmup multiplier vs draws_x4. Default: 1.
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
    baseline_coupling_json = DEFAULT_BASELINE_COUPLING_JSON
    output_json = DEFAULT_OUTPUT_JSON
    output_md = DEFAULT_OUTPUT_MD
    draws_multiplier = 2
    warmup_multiplier = 1
    init_jitter = 0.0
    top_couplings = CouplingPilot.DEFAULT_TOP_COUPLINGS
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
        elseif arg == "--baseline-coupling-json"
            index < length(args) ||
                error("--baseline-coupling-json requires a path")
            baseline_coupling_json = abspath(args[index + 1])
            index += 2
        elseif arg == "--output-json"
            index < length(args) || error("--output-json requires a path")
            output_json = abspath(args[index + 1])
            index += 2
        elseif arg == "--output-md"
            index < length(args) || error("--output-md requires a path")
            output_md = abspath(args[index + 1])
            index += 2
        elseif arg == "--draws-multiplier"
            index < length(args) ||
                error("--draws-multiplier requires an integer")
            draws_multiplier = parse(Int, args[index + 1])
            index += 2
        elseif arg == "--warmup-multiplier"
            index < length(args) ||
                error("--warmup-multiplier requires an integer")
            warmup_multiplier = parse(Int, args[index + 1])
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
            baseline_coupling_json)
        isfile(path) || error("input artifact not found: $path")
    end
    draws_multiplier >= 1 || error("--draws-multiplier must be positive")
    warmup_multiplier >= 1 || error("--warmup-multiplier must be positive")
    isfinite(init_jitter) && init_jitter >= 0 ||
        error("--init-jitter must be finite and non-negative")
    top_couplings >= 1 || error("--top-couplings must be positive")
    max_jobs >= 0 || error("--max-jobs must be non-negative")
    return (; plan_json, warning_surface_json, parameterization_json,
        baseline_coupling_json, output_json, output_md, draws_multiplier,
        warmup_multiplier, init_jitter, top_couplings, max_jobs, progress)
end

project_version() =
    String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])
file_sha256(path::AbstractString) = bytes2hex(open(sha256, path))
rel(path::AbstractString) = relpath(path, ROOT)
read_json(path::AbstractString) = JSON3.read(read(path, String))
symbol_value(value) = Symbol(string(value))
int_value(value) = Int(value)
round4(value) = round(Float64(value); digits = 4)

function extended_profile(base_profile, options)
    return (;
        profile = :coupling_draws_extended,
        chains = int_value(base_profile.chains),
        warmup_per_chain =
            int_value(base_profile.warmup_per_chain) *
            int_value(options.warmup_multiplier),
        draws_per_chain =
            int_value(base_profile.draws_per_chain) *
            int_value(options.draws_multiplier),
        target_acceptance = Float64(base_profile.target_acceptance),
        purpose = :coupling_stability_draw_budget_extension,
        expected_use = :local_diagnostic_only,
        public_claim_allowed = false,
    )
end

function model_key(row)
    return (symbol_value(row.model), int_value(row.split_offset))
end

function baseline_model_map(baseline)
    return Dict(model_key(row) => row for row in baseline.model_rows)
end

function model_comparison_rows(model_rows, baseline)
    base = baseline_model_map(baseline)
    rows = NamedTuple[]
    for row in model_rows
        key = model_key(row)
        haskey(base, key) || error("baseline coupling row not found for $key")
        old = base[key]
        push!(rows, (;
            model = row.model,
            split_offset = row.split_offset,
            baseline_rank_flag = symbol_value(old.rank_flag),
            extended_rank_flag = row.rank_flag,
            baseline_max_rank_rhat = round4(old.max_rank_rhat),
            extended_max_rank_rhat = row.max_rank_rhat,
            delta_max_rank_rhat =
                round4(row.max_rank_rhat - Float64(old.max_rank_rhat)),
            baseline_min_bulk_ess = round4(old.min_bulk_ess),
            extended_min_bulk_ess = row.min_bulk_ess,
            delta_min_bulk_ess =
                round4(row.min_bulk_ess - Float64(old.min_bulk_ess)),
            baseline_min_tail_ess = round4(old.min_tail_ess),
            extended_min_tail_ess = row.min_tail_ess,
            delta_min_tail_ess =
                round4(row.min_tail_ess - Float64(old.min_tail_ess)),
            baseline_max_abs_correlation =
                round4(old.max_abs_warning_correlation),
            extended_max_abs_correlation = row.max_abs_warning_correlation,
            delta_max_abs_correlation =
                round4(row.max_abs_warning_correlation -
                       Float64(old.max_abs_warning_correlation)),
            baseline_max_chain_sep =
                round4(old.max_target_chain_mean_range_z),
            extended_max_chain_sep = row.max_target_chain_mean_range_z,
            delta_max_chain_sep =
                round4(row.max_target_chain_mean_range_z -
                       Float64(old.max_target_chain_mean_range_z)),
            cleared_rank_warning = row.rank_flag === :ok,
            improved_rank_surface =
                row.max_rank_rhat <= Float64(old.max_rank_rhat) &&
                (row.min_bulk_ess >= Float64(old.min_bulk_ess) ||
                 row.min_tail_ess >= Float64(old.min_tail_ess)),
            public_claim_allowed = false,
        ))
    end
    return rows
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
        (artifact = :baseline_person_item_step_coupling_pilot,
            path = rel(options.baseline_coupling_json),
            sha256 = file_sha256(options.baseline_coupling_json)),
    ]
end

function finding_rows(model_rows, coupling_rows, comparison_rows)
    max_corr = isempty(coupling_rows) ? 0.0 :
        maximum(row.abs_correlation for row in coupling_rows)
    n_strong = count(row -> row.abs_correlation >= CouplingPilot.STRONG_CORRELATION,
        coupling_rows)
    n_improved = count(row -> Bool(row.improved_rank_surface), comparison_rows)
    n_cleared = count(row -> Bool(row.cleared_rank_warning), comparison_rows)
    n_geometry = count(row -> row.n_divergences > 0 ||
                             row.n_max_treedepth > 0 ||
                             row.n_sampler_warnings > 0, model_rows)
    return [
        (finding = :coupling_budget_extension_recorded,
            severity = :info,
            evidence = string(length(model_rows), " model row(s) rerun"),
            implication = :draw_budget_sensitivity_checked,
            public_claim_allowed = false),
        (finding = :rank_warning_clearance,
            severity = n_cleared == length(model_rows) ? :info : :warning,
            evidence = string(n_cleared, "/", length(model_rows),
                " rank warnings cleared"),
            implication = :rank_warnings_remain_blocker_if_not_all_clear,
            public_claim_allowed = false),
        (finding = :rank_surface_improvement,
            severity = n_improved > 0 ? :info : :warning,
            evidence = string(n_improved, "/", length(model_rows),
                " rows improved rank surface"),
            implication = :draw_budget_helpful_only_if_stable,
            public_claim_allowed = false),
        (finding = :strong_coupling_detected,
            severity = n_strong > 0 ? :warning : :info,
            evidence = string(n_strong, " row(s) >= ",
                CouplingPilot.STRONG_CORRELATION, "; max=", round4(max_corr)),
            implication = n_strong > 0 ?
                :target_strong_coupling_before_api_change :
                :no_strong_coupling_under_extended_budget,
            public_claim_allowed = false),
        (finding = :geometry_still_not_primary,
            severity = n_geometry == 0 ? :info : :warning,
            evidence = string(n_geometry, "/", length(model_rows),
                " geometry warning rows"),
            implication = n_geometry == 0 ?
                :continue_rank_parameterization_diagnostics :
                :review_geometry_controls,
            public_claim_allowed = false),
        (finding = :public_claims_blocked,
            severity = :blocker,
            evidence = :local_budget_extension_only,
            implication =
                :do_not_claim_public_thresholds_q_revisions_or_model_weights,
            public_claim_allowed = false),
    ]
end

function next_gate(comparison_rows, coupling_rows)
    all(row -> Bool(row.cleared_rank_warning), comparison_rows) &&
        return :replicate_extended_draw_budget_before_api_change
    any(row -> row.abs_correlation >= CouplingPilot.STRONG_CORRELATION,
        coupling_rows) &&
        return :target_strong_coupling_parameterization_pilot
    any(row -> Bool(row.improved_rank_surface), comparison_rows) &&
        return :replicate_extended_draw_budget_or_draws_x16_gate
    return :rank_warning_block_design_review_before_reparameterization
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
        println(io, "# Uto-Style Coupling Budget Extension")
        println(io)
        println(io, "- Generated at: `", artifact.generated_at, "`")
        println(io, "- Draws per chain: `",
            artifact.fit_controls.draws_per_chain, "`")
        println(io, "- Warmup per chain: `",
            artifact.fit_controls.warmup_per_chain, "`")
        println(io, "- Local only: `true`")
        println(io, "- Public claims allowed: `false`")
        println(io)
        println(io, "## Findings")
        table(io, ["Finding", "Severity", "Evidence", "Implication"],
            [[row.finding, row.severity, row.evidence, row.implication]
             for row in artifact.finding_rows])
        println(io, "## Model Comparison Rows")
        table(io, ["Model", "Split", "Base Flag", "Extended Flag",
                "dRhat", "dBulk", "dTail", "dMaxCorr", "dChainSep",
                "Cleared"],
            [[row.model, row.split_offset, row.baseline_rank_flag,
                row.extended_rank_flag, row.delta_max_rank_rhat,
                row.delta_min_bulk_ess, row.delta_min_tail_ess,
                row.delta_max_abs_correlation, row.delta_max_chain_sep,
                row.cleared_rank_warning]
             for row in artifact.model_comparison_rows])
        println(io, "## Top Couplings")
        table(io, ["Model", "Split", "Target", "Coupled", "Corr",
                "Abs Corr", "Hint"],
            [[row.model, row.split_offset, row.target_parameter,
                row.coupled_parameter, row.correlation, row.abs_correlation,
                row.action_hint]
             for row in artifact.coupling_rows[1:min(24,
                 length(artifact.coupling_rows))]])
        println(io, "## Boundary")
        println(io)
        println(io,
            "This gate checks retained-draw sensitivity for the local coupling ",
            "surface. It does not change the package API and does not authorize ",
            "public fit-threshold, Q-revision, model-weight, or sparse-",
            "superiority claims.")
    end
    return path
end

function build_artifact(options)
    plan = read_json(options.plan_json)
    surface = read_json(options.warning_surface_json)
    parameterization = read_json(options.parameterization_json)
    baseline = read_json(options.baseline_coupling_json)
    base_profile =
        CouplingPilot.InitJitter.RankGate.DrawsX2.profile_by_name(
            plan,
            :draws_x4_gate,
        )
    profile = extended_profile(base_profile, options)
    jobs =
        CouplingPilot.InitJitter.RankGate.DrawsX2.smoke_jobs(plan,
            options.max_jobs)
    run_options = (;
        progress = options.progress,
        init_jitter = Float64(options.init_jitter),
        top_couplings = int_value(options.top_couplings),
    )
    model_rows = NamedTuple[]
    coupling_rows = NamedTuple[]
    for job in jobs
        result = CouplingPilot.execute_job(surface, parameterization, profile,
            job, run_options)
        push!(model_rows, result.model_row)
        append!(coupling_rows, result.coupling_rows)
    end
    sorted_couplings = sort(coupling_rows;
        by = row -> (-row.abs_correlation, string(row.target_parameter),
            string(row.coupled_parameter)))
    block_rows = CouplingPilot.block_coupling_summary(sorted_couplings)
    comparison_rows = model_comparison_rows(model_rows, baseline)
    findings = finding_rows(model_rows, sorted_couplings, comparison_rows)
    return (;
        schema = OUTPUT_SCHEMA,
        family = :mgmfrm,
        scope = :uto_style_coupling_budget_extension,
        status = :local_coupling_budget_extension_recorded,
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
            profile = profile.profile,
            chains = profile.chains,
            warmup_per_chain = profile.warmup_per_chain,
            draws_per_chain = profile.draws_per_chain,
            target_acceptance = profile.target_acceptance,
            init_jitter = Float64(options.init_jitter),
            draws_multiplier = int_value(options.draws_multiplier),
            warmup_multiplier = int_value(options.warmup_multiplier),
            top_couplings = int_value(options.top_couplings),
            progress = options.progress,
        ),
        diagnostic_policy = (;
            baseline_schema = string(baseline.schema),
            strong_correlation = CouplingPilot.STRONG_CORRELATION,
            moderate_correlation = CouplingPilot.MODERATE_CORRELATION,
            parameterization_patch_applied = false,
            public_claim_allowed = false,
        ),
        job_rows = jobs,
        model_rows,
        model_comparison_rows = comparison_rows,
        coupling_rows = sorted_couplings,
        block_coupling_rows = block_rows,
        finding_rows = findings,
        summary = (;
            passed = true,
            n_jobs = length(jobs),
            n_model_rows = length(model_rows),
            n_coupling_rows = length(sorted_couplings),
            n_rank_warnings =
                count(row -> row.rank_flag !== :ok, model_rows),
            n_rank_warnings_cleared =
                count(row -> Bool(row.cleared_rank_warning), comparison_rows),
            n_rank_surface_improved =
                count(row -> Bool(row.improved_rank_surface), comparison_rows),
            n_strong_couplings =
                count(row -> row.abs_correlation >=
                    CouplingPilot.STRONG_CORRELATION, sorted_couplings),
            n_moderate_couplings =
                count(row -> row.abs_correlation >=
                    CouplingPilot.MODERATE_CORRELATION, sorted_couplings),
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
            next_gate = next_gate(comparison_rows, sorted_couplings),
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
        " cleared=", artifact.summary.n_rank_warnings_cleared,
        " improved=", artifact.summary.n_rank_surface_improved,
        " strong=", artifact.summary.n_strong_couplings,
        " max_corr=", artifact.summary.max_abs_correlation,
        " next_gate=", artifact.summary.next_gate)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
