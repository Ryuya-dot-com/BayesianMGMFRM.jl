#!/usr/bin/env julia

using Dates
using JSON3
using SHA
using TOML

import BayesianMGMFRM

module BudgetExtension
include(joinpath(@__DIR__,
    "generate_mgmfrm_uto_style_coupling_budget_extension.jl"))
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
const DEFAULT_BASELINE_EXTENSION_JSON =
    joinpath(ROOT, "artifacts",
        "uto_style_coupling_budget_extension",
        "uto_style_coupling_budget_extension.json")
const DEFAULT_OUTPUT_JSON =
    joinpath(ROOT, "artifacts",
        "uto_style_extended_budget_replication_gate",
        "uto_style_extended_budget_replication_gate.json")
const DEFAULT_OUTPUT_MD =
    joinpath(ROOT, "artifacts",
        "uto_style_extended_budget_replication_gate",
        "uto_style_extended_budget_replication_gate.md")

include(joinpath(@__DIR__, "local_json.jl"))

const OUTPUT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_uto_style_extended_budget_replication_gate.v1"
const DEFAULT_REPLICATE_SEED_OFFSET = 1009
const COUPLING_DELTA_REVIEW_THRESHOLD = 0.15

function usage()
    return """
    Replicate the extended-draw MGMFRM budget gate under an independent seed.

    This reruns the same three priority cells as the coupling-budget extension
    with the same warmup/draw controls, but adds a deterministic replicate seed
    offset. The goal is to check whether the previous rank-warning clearance is
    seed-stable before changing package APIs or public documentation wording.

    Usage:
      julia --project=. scripts/generate_mgmfrm_uto_style_extended_budget_replication_gate.jl [options]

    Options:
      --plan-json PATH                Block-targeted follow-up plan artifact.
      --warning-surface-json PATH     Baseline warning-surface artifact.
      --parameterization-json PATH    Parameterization-audit artifact.
      --baseline-extension-json PATH  Previous extended-budget artifact.
      --output-json PATH              JSON artifact path.
      --output-md PATH                Markdown report path.
      --draws-multiplier N            Retained-draw multiplier vs draws_x4. Default: 2.
      --warmup-multiplier N           Warmup multiplier vs draws_x4. Default: 1.
      --init-jitter VALUE             Raw initial jitter. Default: 0.0.
      --top-couplings N               Top couplings per warning parameter. Default: 6.
      --replicate-seed-offset N       Added sampler seed offset. Default: 1009.
      --max-jobs N                    Limit jobs. Default: all priority jobs.
      --progress                      Show sampler progress.
    """
end

function parse_args(args)
    plan_json = DEFAULT_PLAN_JSON
    warning_surface_json = DEFAULT_WARNING_SURFACE_JSON
    parameterization_json = DEFAULT_PARAMETERIZATION_JSON
    baseline_extension_json = DEFAULT_BASELINE_EXTENSION_JSON
    output_json = DEFAULT_OUTPUT_JSON
    output_md = DEFAULT_OUTPUT_MD
    draws_multiplier = 2
    warmup_multiplier = 1
    init_jitter = 0.0
    top_couplings = BudgetExtension.CouplingPilot.DEFAULT_TOP_COUPLINGS
    replicate_seed_offset = DEFAULT_REPLICATE_SEED_OFFSET
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
        elseif arg == "--baseline-extension-json"
            index < length(args) ||
                error("--baseline-extension-json requires a path")
            baseline_extension_json = abspath(args[index + 1])
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
        elseif arg == "--replicate-seed-offset"
            index < length(args) ||
                error("--replicate-seed-offset requires an integer")
            replicate_seed_offset = parse(Int, args[index + 1])
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
            baseline_extension_json)
        isfile(path) || error("input artifact not found: $path")
    end
    draws_multiplier >= 1 || error("--draws-multiplier must be positive")
    warmup_multiplier >= 1 || error("--warmup-multiplier must be positive")
    isfinite(init_jitter) && init_jitter >= 0 ||
        error("--init-jitter must be finite and non-negative")
    top_couplings >= 1 || error("--top-couplings must be positive")
    replicate_seed_offset != 0 ||
        error("--replicate-seed-offset must be nonzero")
    max_jobs >= 0 || error("--max-jobs must be non-negative")
    return (; plan_json, warning_surface_json, parameterization_json,
        baseline_extension_json, output_json, output_md, draws_multiplier,
        warmup_multiplier, init_jitter, top_couplings, replicate_seed_offset,
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

function fit_for_job(surface, profile, job, progress::Bool,
        init_jitter::Float64, replicate_seed_offset::Int)
    rankgate = BudgetExtension.CouplingPilot.InitJitter.RankGate
    drawsx2 = rankgate.DrawsX2
    options = drawsx2.run_options(surface, profile, progress)
    cell = drawsx2.selected_cell(surface, job)
    split_context =
        drawsx2.WarningSurface.scenario_split(
            options,
            cell,
            job.split_offset,
        )
    scenario = split_context.scenario
    fitopts = split_context.fitopts
    spec = drawsx2.model_spec(job.model)
    train = drawsx2.WarningSurface.QMisspec.design_for_rows(
        split_context.split.train_rows,
        spec,
        scenario,
    )
    model_seed_offset =
        drawsx2.WarningSurface.QMisspec.model_seed_offset(spec.model)
    replicate_base_seed =
        fitopts.seed + scenario.seed_offset + replicate_seed_offset
    sampler_seed = replicate_base_seed + model_seed_offset
    fit = BayesianMGMFRM.fit(train.spec;
        experimental = true,
        prior = drawsx2.WarningSurface.QMisspec.SmallMCMC.source_prior(
            fitopts.prior_profile),
        backend = :advancedhmc,
        ndraws = fitopts.draws_per_chain,
        warmup = fitopts.warmup_per_chain,
        chains = fitopts.chains,
        seed = sampler_seed,
        target_accept = fitopts.target_acceptance,
        init_jitter,
        progress = fitopts.progress,
    )
    context = drawsx2.WarningSurface.fit_context(
        cell,
        job.split_offset,
        split_context.split_seed,
        scenario,
        fitopts,
    )
    return (;
        fit,
        context = merge(context, (;
            replicate_seed_offset,
            replicate_base_seed,
            sampler_seed,
        )),
    )
end

function execute_job(surface, parameterization, profile, job, options)
    result = fit_for_job(surface, profile, job, options.progress,
        Float64(options.init_jitter), int_value(options.replicate_seed_offset))
    diagnostic = result.fit.diagnostic_surface
    chains = int_value(profile.chains)
    raw_rows =
        BudgetExtension.CouplingPilot.InitJitter.RankGate.rank_parameter_rows(
            diagnostic.draws,
            diagnostic.raw_parameter_names,
            chains,
            :raw_unconstrained,
        )
    raw_summary =
        BudgetExtension.CouplingPilot.InitJitter.RankGate.rank_summary(raw_rows)
    current_by_name = Dict(row.parameter => row for row in raw_rows)
    name_to_index = Dict(String(name) => index
        for (index, name) in pairs(diagnostic.raw_parameter_names))
    chain_stats = BudgetExtension.CouplingPilot.chain_separation_by_name(
        diagnostic.draws,
        diagnostic.raw_parameter_names,
        chains,
    )
    warning_rows = BudgetExtension.CouplingPilot.warning_rows_for_job(
        parameterization,
        job,
    )
    model_context = merge(result.context, (;
        model = symbol_value(job.model),
        split_offset = int_value(job.split_offset),
        init_jitter = Float64(options.init_jitter),
    ))
    coupling_rows = NamedTuple[]
    for warning in warning_rows
        haskey(current_by_name, warning.parameter) ||
            error("current diagnostic missing warning parameter $(warning.parameter)")
        append!(coupling_rows,
            BudgetExtension.CouplingPilot.coupling_rows_for_warning(
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
        model_row = BudgetExtension.CouplingPilot.model_summary_row(
            result.context,
            job,
            result.fit,
            raw_summary,
            warning_rows,
            coupling_rows,
        ),
        coupling_rows,
    )
end

function model_key(row)
    return (symbol_value(row.model), int_value(row.split_offset))
end

function baseline_model_map(baseline)
    return Dict(model_key(row) => row for row in baseline.model_rows)
end

function replication_comparison_rows(model_rows, baseline)
    base = baseline_model_map(baseline)
    rows = NamedTuple[]
    for row in model_rows
        key = model_key(row)
        haskey(base, key) || error("baseline extension row not found for $key")
        old = base[key]
        delta_corr = round4(row.max_abs_warning_correlation -
                            Float64(old.max_abs_warning_correlation))
        push!(rows, (;
            model = row.model,
            split_offset = row.split_offset,
            baseline_rank_flag = symbol_value(old.rank_flag),
            replicate_rank_flag = row.rank_flag,
            baseline_max_rank_rhat = round4(old.max_rank_rhat),
            replicate_max_rank_rhat = row.max_rank_rhat,
            delta_max_rank_rhat =
                round4(row.max_rank_rhat - Float64(old.max_rank_rhat)),
            baseline_min_bulk_ess = round4(old.min_bulk_ess),
            replicate_min_bulk_ess = row.min_bulk_ess,
            delta_min_bulk_ess =
                round4(row.min_bulk_ess - Float64(old.min_bulk_ess)),
            baseline_min_tail_ess = round4(old.min_tail_ess),
            replicate_min_tail_ess = row.min_tail_ess,
            delta_min_tail_ess =
                round4(row.min_tail_ess - Float64(old.min_tail_ess)),
            baseline_max_abs_correlation =
                round4(old.max_abs_warning_correlation),
            replicate_max_abs_correlation = row.max_abs_warning_correlation,
            delta_max_abs_correlation = delta_corr,
            baseline_max_chain_sep =
                round4(old.max_target_chain_mean_range_z),
            replicate_max_chain_sep = row.max_target_chain_mean_range_z,
            delta_max_chain_sep =
                round4(row.max_target_chain_mean_range_z -
                       Float64(old.max_target_chain_mean_range_z)),
            replicated_rank_clearance =
                row.rank_flag === :ok && symbol_value(old.rank_flag) === :ok,
            coupling_delta_review =
                abs(delta_corr) > COUPLING_DELTA_REVIEW_THRESHOLD,
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
        (artifact = :baseline_coupling_budget_extension,
            path = rel(options.baseline_extension_json),
            sha256 = file_sha256(options.baseline_extension_json)),
    ]
end

function prompt_rows(comparison_rows, model_rows, coupling_rows)
    n = length(model_rows)
    replicated =
        count(row -> Bool(row.replicated_rank_clearance), comparison_rows)
    n_geometry = count(row -> row.n_divergences > 0 ||
                             row.n_max_treedepth > 0 ||
                             row.n_sampler_warnings > 0, model_rows)
    n_strong = count(row -> row.abs_correlation >=
                           BudgetExtension.CouplingPilot.STRONG_CORRELATION,
        coupling_rows)
    n_corr_review =
        count(row -> Bool(row.coupling_delta_review), comparison_rows)
    return [
        (step = :independent_seed_replication,
            prompt = :did_the_512_draw_clearance_replicate_under_a_new_seed,
            observed = string(replicated, "/", n, " replicated"),
            decision = replicated == n ? :continue : :add_third_seed_before_any_api_change,
            public_claim_allowed = false),
        (step = :geometry_screen,
            prompt = :did_the_new_seed_introduce_divergence_treedepth_or_sampler_warnings,
            observed = string(n_geometry, "/", n, " geometry-warning rows"),
            decision = n_geometry == 0 ? :continue_rank_budget_work :
                :review_geometry_controls_first,
            public_claim_allowed = false),
        (step = :coupling_screen,
            prompt = :did_warning_parameter_couplings_cross_the_strong_threshold,
            observed = string(n_strong, " strong rows; ",
                n_corr_review, " model rows exceed delta-review threshold"),
            decision = n_strong == 0 ? :avoid_parameterization_change_for_now :
                :target_strong_coupling_before_documentation,
            public_claim_allowed = false),
        (step = :mcmc_budget_policy,
            prompt = :is_this_enough_to_change_package_defaults,
            observed = :one_independent_seed_replication_only,
            decision = :check_warmup_or_second_seed_before_default_change,
            public_claim_allowed = false),
    ]
end

function finding_rows(model_rows, coupling_rows, comparison_rows)
    max_corr = isempty(coupling_rows) ? 0.0 :
        maximum(row.abs_correlation for row in coupling_rows)
    n = length(model_rows)
    n_replicated =
        count(row -> Bool(row.replicated_rank_clearance), comparison_rows)
    n_corr_review =
        count(row -> Bool(row.coupling_delta_review), comparison_rows)
    n_strong = count(row -> row.abs_correlation >=
                           BudgetExtension.CouplingPilot.STRONG_CORRELATION,
        coupling_rows)
    n_geometry = count(row -> row.n_divergences > 0 ||
                             row.n_max_treedepth > 0 ||
                             row.n_sampler_warnings > 0, model_rows)
    return [
        (finding = :extended_budget_replication_recorded,
            severity = :info,
            evidence = string(n, " model row(s) rerun with independent seed"),
            implication = :seed_stability_checked_before_api_change,
            public_claim_allowed = false),
        (finding = :rank_warning_clearance_replicated,
            severity = n_replicated == n ? :info : :warning,
            evidence = string(n_replicated, "/", n,
                " rows replicated rank-warning clearance"),
            implication = n_replicated == n ?
                :retained_draw_budget_explanation_strengthened :
                :seed_sensitive_rank_warning_remains,
            public_claim_allowed = false),
        (finding = :coupling_delta_review,
            severity = n_corr_review == 0 ? :info : :warning,
            evidence = string(n_corr_review, "/", n,
                " model rows exceeded abs delta > ",
                COUPLING_DELTA_REVIEW_THRESHOLD),
            implication = n_corr_review == 0 ?
                :coupling_surface_broadly_stable :
                :review_coupling_shift_before_documenting,
            public_claim_allowed = false),
        (finding = :strong_coupling_detected,
            severity = n_strong > 0 ? :warning : :info,
            evidence = string(n_strong, " row(s) >= ",
                BudgetExtension.CouplingPilot.STRONG_CORRELATION,
                "; max=", round4(max_corr)),
            implication = n_strong > 0 ?
                :target_strong_coupling_before_api_change :
                :no_strong_coupling_under_replicated_extended_budget,
            public_claim_allowed = false),
        (finding = :geometry_still_not_primary,
            severity = n_geometry == 0 ? :info : :warning,
            evidence = string(n_geometry, "/", n, " geometry warning rows"),
            implication = n_geometry == 0 ?
                :rank_budget_not_geometry_is_current_local_explanation :
                :review_geometry_controls,
            public_claim_allowed = false),
        (finding = :public_claims_blocked,
            severity = :blocker,
            evidence = :local_independent_seed_replication_only,
            implication =
                :do_not_claim_public_thresholds_q_revisions_or_model_weights,
            public_claim_allowed = false),
    ]
end

function next_gate(model_rows, coupling_rows, comparison_rows)
    all(row -> Bool(row.replicated_rank_clearance), comparison_rows) ||
        return :third_seed_replication_or_parameterization_audit
    any(row -> row.n_divergences > 0 ||
               row.n_max_treedepth > 0 ||
               row.n_sampler_warnings > 0, model_rows) &&
        return :geometry_control_review_before_budget_guidance
    any(row -> row.abs_correlation >=
               BudgetExtension.CouplingPilot.STRONG_CORRELATION,
        coupling_rows) &&
        return :target_strong_coupling_parameterization_pilot
    return :warmup_sensitivity_check_before_default_budget_guidance
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
        println(io, "# Uto-Style Extended Budget Replication Gate")
        println(io)
        println(io, "- Generated at: `", artifact.generated_at, "`")
        println(io, "- Draws per chain: `",
            artifact.fit_controls.draws_per_chain, "`")
        println(io, "- Warmup per chain: `",
            artifact.fit_controls.warmup_per_chain, "`")
        println(io, "- Replicate seed offset: `",
            artifact.fit_controls.replicate_seed_offset, "`")
        println(io, "- Local only: `true`")
        println(io, "- Public claims allowed: `false`")
        println(io)
        println(io, "## Decision Prompts")
        table(io, ["Step", "Prompt", "Observed", "Decision"],
            [[row.step, row.prompt, row.observed, row.decision]
             for row in artifact.prompt_rows])
        println(io, "## Findings")
        table(io, ["Finding", "Severity", "Evidence", "Implication"],
            [[row.finding, row.severity, row.evidence, row.implication]
             for row in artifact.finding_rows])
        println(io, "## Replication Comparison Rows")
        table(io, ["Model", "Split", "Base Flag", "Rep Flag", "dRhat",
                "dBulk", "dTail", "dMaxCorr", "dChainSep", "Replicated",
                "Corr Review"],
            [[row.model, row.split_offset, row.baseline_rank_flag,
                row.replicate_rank_flag, row.delta_max_rank_rhat,
                row.delta_min_bulk_ess, row.delta_min_tail_ess,
                row.delta_max_abs_correlation, row.delta_max_chain_sep,
                row.replicated_rank_clearance, row.coupling_delta_review]
             for row in artifact.model_comparison_rows])
        println(io, "## Model Rows")
        table(io, ["Model", "Split", "Rank Flag", "Rank Rhat", "Bulk ESS",
                "Tail ESS", "Sampler Seed", "Max Corr", "Max Chain Sep"],
            [[row.model, row.split_offset, row.rank_flag, row.max_rank_rhat,
                row.min_bulk_ess, row.min_tail_ess, row.sampler_seed,
                row.max_abs_warning_correlation,
                row.max_target_chain_mean_range_z]
             for row in artifact.model_rows])
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
            "This gate checks whether the retained-draw explanation is stable ",
            "under one independent sampler seed. It does not change the package ",
            "API and does not authorize public fit-threshold, Q-revision, ",
            "model-weight, or sparse-superiority claims.")
    end
    return path
end

function build_artifact(options)
    plan = read_json(options.plan_json)
    surface = read_json(options.warning_surface_json)
    parameterization = read_json(options.parameterization_json)
    baseline = read_json(options.baseline_extension_json)
    base_profile =
        BudgetExtension.CouplingPilot.InitJitter.RankGate.DrawsX2.profile_by_name(
            plan,
            :draws_x4_gate,
        )
    profile = BudgetExtension.extended_profile(base_profile, options)
    jobs =
        BudgetExtension.CouplingPilot.InitJitter.RankGate.DrawsX2.smoke_jobs(
            plan,
            options.max_jobs,
        )
    run_options = (;
        progress = options.progress,
        init_jitter = Float64(options.init_jitter),
        top_couplings = int_value(options.top_couplings),
        replicate_seed_offset = int_value(options.replicate_seed_offset),
    )
    model_rows = NamedTuple[]
    coupling_rows = NamedTuple[]
    for job in jobs
        result = execute_job(surface, parameterization, profile, job,
            run_options)
        push!(model_rows, result.model_row)
        append!(coupling_rows, result.coupling_rows)
    end
    sorted_couplings = sort(coupling_rows;
        by = row -> (-row.abs_correlation, string(row.target_parameter),
            string(row.coupled_parameter)))
    block_rows =
        BudgetExtension.CouplingPilot.block_coupling_summary(sorted_couplings)
    comparison_rows = replication_comparison_rows(model_rows, baseline)
    prompts = prompt_rows(comparison_rows, model_rows, sorted_couplings)
    findings = finding_rows(model_rows, sorted_couplings, comparison_rows)
    return (;
        schema = OUTPUT_SCHEMA,
        family = :mgmfrm,
        scope = :uto_style_extended_budget_replication_gate,
        status = :local_extended_budget_replication_recorded,
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
            replicate_seed_offset = int_value(options.replicate_seed_offset),
            progress = options.progress,
        ),
        diagnostic_policy = (;
            baseline_schema = string(baseline.schema),
            strong_correlation =
                BudgetExtension.CouplingPilot.STRONG_CORRELATION,
            moderate_correlation =
                BudgetExtension.CouplingPilot.MODERATE_CORRELATION,
            coupling_delta_review_threshold = COUPLING_DELTA_REVIEW_THRESHOLD,
            parameterization_patch_applied = false,
            public_claim_allowed = false,
        ),
        job_rows = jobs,
        model_rows,
        model_comparison_rows = comparison_rows,
        coupling_rows = sorted_couplings,
        block_coupling_rows = block_rows,
        prompt_rows = prompts,
        finding_rows = findings,
        summary = (;
            passed =
                all(row -> Bool(row.replicated_rank_clearance),
                    comparison_rows) &&
                all(row -> row.n_divergences == 0 &&
                           row.n_max_treedepth == 0 &&
                           row.n_sampler_warnings == 0, model_rows),
            n_jobs = length(jobs),
            n_model_rows = length(model_rows),
            n_coupling_rows = length(sorted_couplings),
            n_rank_warnings =
                count(row -> row.rank_flag !== :ok, model_rows),
            n_rank_clearance_replicated =
                count(row -> Bool(row.replicated_rank_clearance),
                    comparison_rows),
            n_coupling_delta_review =
                count(row -> Bool(row.coupling_delta_review), comparison_rows),
            n_strong_couplings =
                count(row -> row.abs_correlation >=
                    BudgetExtension.CouplingPilot.STRONG_CORRELATION,
                    sorted_couplings),
            n_moderate_couplings =
                count(row -> row.abs_correlation >=
                    BudgetExtension.CouplingPilot.MODERATE_CORRELATION,
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
            next_gate = next_gate(model_rows, sorted_couplings,
                comparison_rows),
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
        " replicated=", artifact.summary.n_rank_clearance_replicated,
        " corr_review=", artifact.summary.n_coupling_delta_review,
        " strong=", artifact.summary.n_strong_couplings,
        " max_corr=", artifact.summary.max_abs_correlation,
        " geometry=", artifact.summary.n_geometry_warning_rows,
        " next_gate=", artifact.summary.next_gate)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
