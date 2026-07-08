#!/usr/bin/env julia

using Dates
using JSON3
using SHA
using TOML

module ReplicationGate
include(joinpath(@__DIR__,
    "generate_mgmfrm_uto_style_extended_budget_replication_gate.jl"))
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
const DEFAULT_BASELINE_REPLICATION_JSON =
    joinpath(ROOT, "artifacts",
        "uto_style_extended_budget_replication_gate",
        "uto_style_extended_budget_replication_gate.json")
const DEFAULT_OUTPUT_JSON =
    joinpath(ROOT, "artifacts",
        "uto_style_warmup_thinning_sensitivity_gate",
        "uto_style_warmup_thinning_sensitivity_gate.json")
const DEFAULT_OUTPUT_MD =
    joinpath(ROOT, "artifacts",
        "uto_style_warmup_thinning_sensitivity_gate",
        "uto_style_warmup_thinning_sensitivity_gate.md")

include(joinpath(@__DIR__, "local_json.jl"))

const OUTPUT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_uto_style_warmup_thinning_sensitivity_gate.v1"
const DEFAULT_REPLICATE_SEED_OFFSET =
    ReplicationGate.DEFAULT_REPLICATE_SEED_OFFSET

function usage()
    return """
    Run a warmup/thinning sensitivity gate for the MGMFRM rank-warning cells.

    This reruns the same three priority cells with retained draws fixed at the
    extended-budget level and warmup increased by default from 128 to 256 per
    chain. It then computes rank-normalized diagnostics on the full retained
    draws and on post-hoc thinned draws. The thinning check is diagnostic only;
    the public fit API does not expose sampler-level thinning.

    Usage:
      julia --project=. scripts/generate_mgmfrm_uto_style_warmup_thinning_sensitivity_gate.jl [options]

    Options:
      --plan-json PATH                  Block-targeted follow-up plan artifact.
      --warning-surface-json PATH       Baseline warning-surface artifact.
      --baseline-replication-json PATH  Extended-budget replication artifact.
      --output-json PATH                JSON artifact path.
      --output-md PATH                  Markdown report path.
      --draws-multiplier N              Retained-draw multiplier vs draws_x4. Default: 2.
      --warmup-multiplier N             Warmup multiplier vs draws_x4. Default: 2.
      --init-jitter VALUE               Raw initial jitter. Default: 0.0.
      --replicate-seed-offset N         Added sampler seed offset. Default: 1009.
      --thin-factors LIST               Comma-separated factors. Default: 2,4.
      --max-jobs N                      Limit jobs. Default: all priority jobs.
      --progress                        Show sampler progress.
    """
end

function parse_thin_factors(value::AbstractString)
    factors = [parse(Int, strip(part)) for part in split(value, ",")
        if !isempty(strip(part))]
    isempty(factors) && error("--thin-factors must contain at least one value")
    any(factor -> factor <= 1, factors) &&
        error("--thin-factors must be integers greater than 1")
    return sort(unique(factors))
end

function parse_args(args)
    plan_json = DEFAULT_PLAN_JSON
    warning_surface_json = DEFAULT_WARNING_SURFACE_JSON
    baseline_replication_json = DEFAULT_BASELINE_REPLICATION_JSON
    output_json = DEFAULT_OUTPUT_JSON
    output_md = DEFAULT_OUTPUT_MD
    draws_multiplier = 2
    warmup_multiplier = 2
    init_jitter = 0.0
    replicate_seed_offset = DEFAULT_REPLICATE_SEED_OFFSET
    thin_factors = [2, 4]
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
        elseif arg == "--baseline-replication-json"
            index < length(args) ||
                error("--baseline-replication-json requires a path")
            baseline_replication_json = abspath(args[index + 1])
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
        elseif arg == "--replicate-seed-offset"
            index < length(args) ||
                error("--replicate-seed-offset requires an integer")
            replicate_seed_offset = parse(Int, args[index + 1])
            index += 2
        elseif arg == "--thin-factors"
            index < length(args) || error("--thin-factors requires a list")
            thin_factors = parse_thin_factors(args[index + 1])
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
    for path in (plan_json, warning_surface_json, baseline_replication_json)
        isfile(path) || error("input artifact not found: $path")
    end
    draws_multiplier >= 1 || error("--draws-multiplier must be positive")
    warmup_multiplier >= 1 || error("--warmup-multiplier must be positive")
    isfinite(init_jitter) && init_jitter >= 0 ||
        error("--init-jitter must be finite and non-negative")
    replicate_seed_offset != 0 ||
        error("--replicate-seed-offset must be nonzero")
    max_jobs >= 0 || error("--max-jobs must be non-negative")
    return (; plan_json, warning_surface_json, baseline_replication_json,
        output_json, output_md, draws_multiplier, warmup_multiplier,
        init_jitter, replicate_seed_offset, thin_factors, max_jobs, progress)
end

project_version() =
    String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])
file_sha256(path::AbstractString) = bytes2hex(open(sha256, path))
rel(path::AbstractString) = relpath(path, ROOT)
read_json(path::AbstractString) = JSON3.read(read(path, String))
symbol_value(value) = Symbol(string(value))
int_value(value) = Int(value)
round4(value) = round(Float64(value); digits = 4)

function sensitivity_profile(base_profile, options)
    return (;
        profile = :warmup_thinning_sensitivity,
        chains = int_value(base_profile.chains),
        warmup_per_chain =
            int_value(base_profile.warmup_per_chain) *
            int_value(options.warmup_multiplier),
        draws_per_chain =
            int_value(base_profile.draws_per_chain) *
            int_value(options.draws_multiplier),
        target_acceptance = Float64(base_profile.target_acceptance),
        purpose = :warmup_thinning_sensitivity,
        expected_use = :local_diagnostic_only,
        public_claim_allowed = false,
    )
end

function thin_draws(draws::AbstractMatrix{<:Real}, chains::Int,
        thin_factor::Int)
    thin_factor == 1 && return draws
    total, _ = size(draws)
    total % chains == 0 || error("uneven chains")
    draws_per_chain = div(total, chains)
    draws_per_chain >= thin_factor ||
        error("thin factor larger than draws per chain")
    indices = Int[]
    for chain in 1:chains
        first_index = (chain - 1) * draws_per_chain + 1
        last_index = chain * draws_per_chain
        append!(indices, first_index:thin_factor:last_index)
    end
    return draws[indices, :]
end

function rank_surface_for_draws(diagnostic, chains::Int, thin_factor::Int)
    rankgate = ReplicationGate.BudgetExtension.CouplingPilot.InitJitter.RankGate
    draws = thin_draws(diagnostic.draws, chains, thin_factor)
    rows = rankgate.rank_parameter_rows(draws,
        diagnostic.raw_parameter_names, chains, :raw_unconstrained)
    summary = rankgate.rank_summary(rows)
    return (; rows, summary, total_draws = size(draws, 1),
        draws_per_chain = div(size(draws, 1), chains))
end

function execute_job(surface, profile, job, options)
    result = ReplicationGate.fit_for_job(surface, profile, job,
        options.progress, Float64(options.init_jitter),
        int_value(options.replicate_seed_offset))
    diagnostic = result.fit.diagnostic_surface
    chains = int_value(profile.chains)
    summary = diagnostic.summary
    thin_factors = vcat([1], options.thin_factors)
    rows = NamedTuple[]
    for thin_factor in thin_factors
        ranked = rank_surface_for_draws(diagnostic, chains, thin_factor)
        push!(rows, merge(result.context, (;
            model = symbol_value(job.model),
            split_offset = int_value(job.split_offset),
            thin_factor,
            chains,
            warmup_per_chain = Int(result.fit.warmup),
            draws_per_chain = ranked.draws_per_chain,
            total_draws = ranked.total_draws,
            rank_flag = ranked.summary.flag,
            max_rank_rhat = ranked.summary.max_rank_rhat,
            min_bulk_ess = ranked.summary.min_bulk_ess,
            min_tail_ess = ranked.summary.min_tail_ess,
            n_divergences = Int(summary.n_divergences),
            n_max_treedepth = Int(summary.n_max_treedepth),
            n_sampler_warnings = Int(summary.n_sampler_warnings),
            public_claim_allowed = false,
        )))
    end
    return (; sensitivity_rows = rows)
end

function model_key(row)
    return (symbol_value(row.model), int_value(row.split_offset))
end

function baseline_model_map(baseline)
    return Dict(model_key(row) => row for row in baseline.model_rows)
end

function full_rows(sensitivity_rows)
    return [row for row in sensitivity_rows if int_value(row.thin_factor) == 1]
end

function warmup_comparison_rows(model_rows, baseline)
    base = baseline_model_map(baseline)
    rows = NamedTuple[]
    for row in model_rows
        key = model_key(row)
        haskey(base, key) || error("baseline replication row not found for $key")
        old = base[key]
        delta_rhat = round4(row.max_rank_rhat - Float64(old.max_rank_rhat))
        delta_bulk = round4(row.min_bulk_ess - Float64(old.min_bulk_ess))
        delta_tail = round4(row.min_tail_ess - Float64(old.min_tail_ess))
        push!(rows, (;
            model = row.model,
            split_offset = row.split_offset,
            baseline_warmup_per_chain = int_value(old.warmup_per_chain),
            sensitivity_warmup_per_chain = row.warmup_per_chain,
            baseline_rank_flag = symbol_value(old.rank_flag),
            sensitivity_rank_flag = row.rank_flag,
            baseline_max_rank_rhat = round4(old.max_rank_rhat),
            sensitivity_max_rank_rhat = row.max_rank_rhat,
            delta_max_rank_rhat = delta_rhat,
            baseline_min_bulk_ess = round4(old.min_bulk_ess),
            sensitivity_min_bulk_ess = row.min_bulk_ess,
            delta_min_bulk_ess = delta_bulk,
            baseline_min_tail_ess = round4(old.min_tail_ess),
            sensitivity_min_tail_ess = row.min_tail_ess,
            delta_min_tail_ess = delta_tail,
            warmup_rank_clearance_replicated =
                row.rank_flag === :ok && symbol_value(old.rank_flag) === :ok,
            warmup_improved =
                delta_rhat <= 0 && (delta_bulk >= 0 || delta_tail >= 0),
            public_claim_allowed = false,
        ))
    end
    return rows
end

function thinning_comparison_rows(sensitivity_rows)
    base = Dict(model_key(row) => row for row in full_rows(sensitivity_rows))
    rows = NamedTuple[]
    for row in sensitivity_rows
        int_value(row.thin_factor) == 1 && continue
        full = base[model_key(row)]
        push!(rows, (;
            model = row.model,
            split_offset = row.split_offset,
            thin_factor = row.thin_factor,
            full_rank_flag = full.rank_flag,
            thinned_rank_flag = row.rank_flag,
            full_draws_per_chain = full.draws_per_chain,
            thinned_draws_per_chain = row.draws_per_chain,
            full_max_rank_rhat = full.max_rank_rhat,
            thinned_max_rank_rhat = row.max_rank_rhat,
            delta_max_rank_rhat =
                round4(row.max_rank_rhat - full.max_rank_rhat),
            full_min_bulk_ess = full.min_bulk_ess,
            thinned_min_bulk_ess = row.min_bulk_ess,
            delta_min_bulk_ess =
                round4(row.min_bulk_ess - full.min_bulk_ess),
            full_min_tail_ess = full.min_tail_ess,
            thinned_min_tail_ess = row.min_tail_ess,
            delta_min_tail_ess =
                round4(row.min_tail_ess - full.min_tail_ess),
            thinning_preserved_ok = row.rank_flag === :ok,
            public_claim_allowed = false,
        ))
    end
    return rows
end

function thin_factor_rows(thinning_rows)
    factors = sort(unique(row.thin_factor for row in thinning_rows))
    rows = NamedTuple[]
    for factor in factors
        selected = [row for row in thinning_rows if row.thin_factor == factor]
        push!(rows, (;
            thin_factor = factor,
            n_rows = length(selected),
            n_rank_warnings =
                count(row -> row.thinned_rank_flag !== :ok, selected),
            n_preserved_ok =
                count(row -> Bool(row.thinning_preserved_ok), selected),
            max_rank_rhat =
                round4(maximum(row.thinned_max_rank_rhat for row in selected)),
            min_bulk_ess =
                round4(minimum(row.thinned_min_bulk_ess for row in selected)),
            min_tail_ess =
                round4(minimum(row.thinned_min_tail_ess for row in selected)),
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
        (artifact = :extended_budget_replication_gate,
            path = rel(options.baseline_replication_json),
            sha256 = file_sha256(options.baseline_replication_json)),
    ]
end

function prompt_rows(warmup_rows, thinning_rows, model_rows)
    n = length(model_rows)
    full_clear = count(row -> row.rank_flag === :ok, model_rows)
    improved = count(row -> Bool(row.warmup_improved), warmup_rows)
    thin_preserved = count(row -> Bool(row.thinning_preserved_ok),
        thinning_rows)
    n_thin = length(thinning_rows)
    thin_warnings = count(row -> row.thinned_rank_flag !== :ok,
        thinning_rows)
    return [
        (step = :warmup_sensitivity,
            prompt = :does_doubling_warmup_change_the_extended_budget_conclusion,
            observed = string(full_clear, "/", n, " full rows ok; ",
                improved, "/", n, " improved vs baseline replication"),
            decision = full_clear == n ? :retained_draw_conclusion_stable :
                :review_warmup_budget_before_guidance,
            public_claim_allowed = false),
        (step = :post_hoc_thinning,
            prompt = :does_thinning_remove_rank_or_ess_risk,
            observed = string(thin_preserved, "/", n_thin,
                " thinned rows ok; ", thin_warnings, " warnings"),
            decision = thin_warnings == 0 ? :thinning_not_needed_if_full_ok :
                :do_not_use_thinning_as_primary_fix,
            public_claim_allowed = false),
        (step = :default_policy,
            prompt = :is_this_enough_to_change_package_defaults,
            observed = :local_three_cell_warmup_thinning_gate_only,
            decision = :document_local_budget_guidance_before_default_change,
            public_claim_allowed = false),
    ]
end

function finding_rows(warmup_rows, thinning_rows, model_rows)
    n = length(model_rows)
    full_clear = count(row -> row.rank_flag === :ok, model_rows)
    improved = count(row -> Bool(row.warmup_improved), warmup_rows)
    thin_warnings = count(row -> row.thinned_rank_flag !== :ok,
        thinning_rows)
    n_geometry = count(row -> row.n_divergences > 0 ||
                             row.n_max_treedepth > 0 ||
                             row.n_sampler_warnings > 0, model_rows)
    return [
        (finding = :warmup_sensitivity_recorded,
            severity = :info,
            evidence = string(n, " model row(s) rerun with increased warmup"),
            implication = :burnin_sensitivity_checked_locally,
            public_claim_allowed = false),
        (finding = :warmup_rank_clearance,
            severity = full_clear == n ? :info : :warning,
            evidence = string(full_clear, "/", n,
                " full retained-draw rows ok; ", improved, "/", n,
                " improved vs baseline replication"),
            implication = full_clear == n ?
                :rank_clearance_not_lost_with_more_warmup :
                :warmup_budget_needs_more_review,
            public_claim_allowed = false),
        (finding = :post_hoc_thinning_check,
            severity = thin_warnings == 0 ? :info : :warning,
            evidence = string(thin_warnings, "/", length(thinning_rows),
                " thinned diagnostic rows had rank warnings"),
            implication = thin_warnings == 0 ?
                :thinning_not_required_for_current_clearance :
                :thinning_can_reduce_effective_diagnostic_support,
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
            evidence = :local_three_cell_sensitivity_gate_only,
            implication =
                :do_not_claim_public_thresholds_q_revisions_or_model_weights,
            public_claim_allowed = false),
    ]
end

function next_gate(model_rows, thinning_rows)
    all(row -> row.rank_flag === :ok, model_rows) ||
        return :additional_warmup_or_seed_sensitivity_before_guidance
    any(row -> row.thinned_rank_flag !== :ok, thinning_rows) &&
        return :document_thinning_not_primary_fix_and_prepare_budget_guidance
    return :document_retained_draw_budget_guidance_before_default_change
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
        println(io, "# Uto-Style Warmup/Thinning Sensitivity Gate")
        println(io)
        println(io, "- Generated at: `", artifact.generated_at, "`")
        println(io, "- Warmup per chain: `",
            artifact.fit_controls.warmup_per_chain, "`")
        println(io, "- Draws per chain: `",
            artifact.fit_controls.draws_per_chain, "`")
        println(io, "- Thin factors: `",
            join(artifact.fit_controls.thin_factors, ","), "`")
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
        println(io, "## Warmup Comparison Rows")
        table(io, ["Model", "Split", "Base Warmup", "New Warmup",
                "Base Flag", "New Flag", "dRhat", "dBulk", "dTail",
                "Improved"],
            [[row.model, row.split_offset, row.baseline_warmup_per_chain,
                row.sensitivity_warmup_per_chain, row.baseline_rank_flag,
                row.sensitivity_rank_flag, row.delta_max_rank_rhat,
                row.delta_min_bulk_ess, row.delta_min_tail_ess,
                row.warmup_improved]
             for row in artifact.warmup_comparison_rows])
        println(io, "## Thinning Comparison Rows")
        table(io, ["Model", "Split", "Thin", "Full Flag", "Thin Flag",
                "Full Draws", "Thin Draws", "dRhat", "dBulk", "dTail",
                "Preserved"],
            [[row.model, row.split_offset, row.thin_factor,
                row.full_rank_flag, row.thinned_rank_flag,
                row.full_draws_per_chain, row.thinned_draws_per_chain,
                row.delta_max_rank_rhat, row.delta_min_bulk_ess,
                row.delta_min_tail_ess, row.thinning_preserved_ok]
             for row in artifact.thinning_comparison_rows])
        println(io, "## Thin-Factor Summary")
        table(io, ["Thin", "Rows", "Warnings", "Preserved OK", "Max Rhat",
                "Min Bulk", "Min Tail"],
            [Any[row.thin_factor, row.n_rows, row.n_rank_warnings,
                row.n_preserved_ok, row.max_rank_rhat, row.min_bulk_ess,
                row.min_tail_ess]
             for row in artifact.thin_factor_rows])
        println(io, "## Boundary")
        println(io)
        println(io,
            "This gate checks local warmup and post-hoc thinning sensitivity. ",
            "It does not add sampler-level thinning to the public API and does ",
            "not authorize public fit-threshold, Q-revision, model-weight, or ",
            "sparse-superiority claims.")
    end
    return path
end

function build_artifact(options)
    plan = read_json(options.plan_json)
    surface = read_json(options.warning_surface_json)
    baseline = read_json(options.baseline_replication_json)
    base_profile =
        ReplicationGate.BudgetExtension.CouplingPilot.InitJitter.RankGate.DrawsX2.profile_by_name(
            plan,
            :draws_x4_gate,
        )
    profile = sensitivity_profile(base_profile, options)
    jobs =
        ReplicationGate.BudgetExtension.CouplingPilot.InitJitter.RankGate.DrawsX2.smoke_jobs(
            plan,
            options.max_jobs,
        )
    run_options = (;
        progress = options.progress,
        init_jitter = Float64(options.init_jitter),
        replicate_seed_offset = int_value(options.replicate_seed_offset),
        thin_factors = int_value.(options.thin_factors),
    )
    sensitivity_rows = NamedTuple[]
    for job in jobs
        result = execute_job(surface, profile, job, run_options)
        append!(sensitivity_rows, result.sensitivity_rows)
    end
    model_rows = full_rows(sensitivity_rows)
    warmup_rows = warmup_comparison_rows(model_rows, baseline)
    thinning_rows = thinning_comparison_rows(sensitivity_rows)
    thin_rows = thin_factor_rows(thinning_rows)
    prompts = prompt_rows(warmup_rows, thinning_rows, model_rows)
    findings = finding_rows(warmup_rows, thinning_rows, model_rows)
    return (;
        schema = OUTPUT_SCHEMA,
        family = :mgmfrm,
        scope = :uto_style_warmup_thinning_sensitivity_gate,
        status = :local_warmup_thinning_sensitivity_recorded,
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
            replicate_seed_offset = int_value(options.replicate_seed_offset),
            thin_factors = int_value.(options.thin_factors),
            progress = options.progress,
        ),
        diagnostic_policy = (;
            baseline_schema = string(baseline.schema),
            rank_rhat_threshold =
                ReplicationGate.BudgetExtension.CouplingPilot.InitJitter.RankGate.RHAT_THRESHOLD,
            ess_threshold =
                ReplicationGate.BudgetExtension.CouplingPilot.InitJitter.RankGate.ESS_THRESHOLD,
            sampler_level_thinning_api = false,
            public_claim_allowed = false,
        ),
        job_rows = jobs,
        sensitivity_rows,
        model_rows,
        warmup_comparison_rows = warmup_rows,
        thinning_comparison_rows = thinning_rows,
        thin_factor_rows = thin_rows,
        prompt_rows = prompts,
        finding_rows = findings,
        summary = (;
            passed = all(row -> row.rank_flag === :ok, model_rows),
            n_jobs = length(jobs),
            n_model_rows = length(model_rows),
            n_sensitivity_rows = length(sensitivity_rows),
            n_full_rank_warnings =
                count(row -> row.rank_flag !== :ok, model_rows),
            n_warmup_improved =
                count(row -> Bool(row.warmup_improved), warmup_rows),
            n_thinning_rows = length(thinning_rows),
            n_thinning_rank_warnings =
                count(row -> row.thinned_rank_flag !== :ok, thinning_rows),
            n_geometry_warning_rows =
                count(row -> row.n_divergences > 0 ||
                       row.n_max_treedepth > 0 ||
                       row.n_sampler_warnings > 0, model_rows),
            no_public_fit_metric_claim = true,
            no_public_q_revision_claim = true,
            no_automatic_q_revision = true,
            no_public_model_weight_claim = true,
            no_sparse_superiority_claim = true,
            next_gate = next_gate(model_rows, thinning_rows),
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
        " full_warnings=", artifact.summary.n_full_rank_warnings,
        " warmup_improved=", artifact.summary.n_warmup_improved,
        " thinning_warnings=", artifact.summary.n_thinning_rank_warnings,
        " geometry=", artifact.summary.n_geometry_warning_rows,
        " next_gate=", artifact.summary.next_gate)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
