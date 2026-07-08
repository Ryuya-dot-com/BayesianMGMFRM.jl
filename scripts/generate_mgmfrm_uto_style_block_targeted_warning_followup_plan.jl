#!/usr/bin/env julia

using Dates
using JSON3
using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_WARNING_SURFACE_JSON =
    joinpath(ROOT, "artifacts",
        "uto_style_sampler_warning_surface_diagnosis",
        "uto_style_sampler_warning_surface_diagnosis.json")
const DEFAULT_OUTPUT_JSON =
    joinpath(ROOT, "artifacts",
        "uto_style_block_targeted_warning_followup_plan",
        "uto_style_block_targeted_warning_followup_plan.json")
const DEFAULT_OUTPUT_MD =
    joinpath(ROOT, "artifacts",
        "uto_style_block_targeted_warning_followup_plan",
        "uto_style_block_targeted_warning_followup_plan.md")

include(joinpath(@__DIR__, "local_json.jl"))

const OUTPUT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_uto_style_block_targeted_warning_followup_plan.v1"
const MCMC_MODEL_NAMES = (
    :declared_q_mgmfrm_mcmc,
    :candidate_q_mgmfrm_mcmc,
    :rotated_wrong_q_mgmfrm_mcmc,
    :scalar_gmfrm_mcmc,
)

function usage()
    return """
    Build a block-targeted follow-up plan for Uto-style sampler warnings.

    This reads the sampler-warning surface diagnosis, ranks warning-heavy
    parameter blocks and model/split cells, and writes the next local budget
    and parameterization jobs. It does not rerun MCMC; it makes the next rerun
    small and auditable. Public threshold, model-weight, Q-revision, and sparse
    superiority claims remain blocked.

    Usage:
      julia --project=. scripts/generate_mgmfrm_uto_style_block_targeted_warning_followup_plan.jl [options]

    Options:
      --warning-surface-json PATH  Warning-surface diagnosis artifact.
      --output-json PATH           JSON artifact path.
      --output-md PATH             Markdown report path.
      --top-blocks N               Number of block targets to list. Default: 4.
      --top-model-splits N         Number of model/split jobs to list. Default: 3.
    """
end

function parse_args(args)
    warning_surface_json = DEFAULT_WARNING_SURFACE_JSON
    output_json = DEFAULT_OUTPUT_JSON
    output_md = DEFAULT_OUTPUT_MD
    top_blocks = 4
    top_model_splits = 3

    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--warning-surface-json"
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
        elseif arg == "--top-blocks"
            index < length(args) || error("--top-blocks requires an integer")
            top_blocks = parse(Int, args[index + 1])
            index += 2
        elseif arg == "--top-model-splits"
            index < length(args) ||
                error("--top-model-splits requires an integer")
            top_model_splits = parse(Int, args[index + 1])
            index += 2
        elseif arg in ("-h", "--help")
            println(usage())
            exit(0)
        else
            error("unknown argument: $arg")
        end
    end

    isfile(warning_surface_json) ||
        error("warning-surface artifact not found: $warning_surface_json")
    top_blocks >= 1 || error("--top-blocks must be positive")
    top_model_splits >= 1 || error("--top-model-splits must be positive")
    return (; warning_surface_json, output_json, output_md, top_blocks,
        top_model_splits)
end

project_version() =
    String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])
file_sha256(path::AbstractString) = bytes2hex(open(sha256, path))
rel(path::AbstractString) = relpath(path, ROOT)
read_json(path::AbstractString) = JSON3.read(read(path, String))
round3(value) = round(Float64(value); digits = 3)
round4(value) = round(Float64(value); digits = 4)

function finite_float(value)
    ismissing(value) && return missing
    float = Float64(value)
    return isfinite(float) ? float : missing
end

function finite_values(values)
    output = Float64[]
    for value in values
        float = finite_float(value)
        ismissing(float) || push!(output, float)
    end
    return output
end

function maximum_or_missing(values)
    finite = finite_values(values)
    isempty(finite) && return missing
    return maximum(finite)
end

function minimum_or_missing(values)
    finite = finite_values(values)
    isempty(finite) && return missing
    return minimum(finite)
end

round_or_missing(value) =
    ismissing(finite_float(value)) ? missing : round4(finite_float(value))
symbol_value(value) = Symbol(string(value))
int_value(value) = Int(value)

function block_recommendation(block::Symbol)
    block === :person &&
        return :ability_block_budget_identification_check
    block in (:item, :item_free) &&
        return :item_location_anchor_and_budget_check
    block in (:item_steps, :rater_steps) &&
        return :step_threshold_category_support_check
    block in (:log_item_dimension_discrimination,
        :log_item_discrimination_free) &&
        return :discrimination_transform_and_q_anchor_check
    block in (:log_rater_consistency, :log_rater_consistency_free) &&
        return :rater_consistency_transform_check
    block in (:rater, :rater_free) &&
        return :rater_severity_constraint_check
    return :manual_parameterization_review
end

function priority_score(max_rhat, min_ess, n_bad_rhat::Int, n_low_ess::Int)
    rhat_gap = ismissing(finite_float(max_rhat)) ? 0.0 :
        max(0.0, finite_float(max_rhat) - 1.01)
    ess_gap = ismissing(finite_float(min_ess)) ? 0.0 :
        max(0.0, 400.0 - finite_float(min_ess))
    return round3(n_low_ess + 2 * n_bad_rhat + 1000 * rhat_gap +
                  ess_gap / 10)
end

function raw_block_priority_rows(block_rows)
    raw = [row for row in block_rows
        if symbol_value(row.parameter_space) === :raw_unconstrained]
    blocks = sort(unique(symbol_value(row.block) for row in raw); by = string)
    rows = NamedTuple[]
    for block in blocks
        group = [row for row in raw if symbol_value(row.block) === block]
        max_rhat = maximum_or_missing(row.max_rhat for row in group)
        min_ess = minimum_or_missing(row.min_ess for row in group)
        n_bad_rhat = sum(int_value(row.n_bad_rhat) for row in group)
        n_low_ess = sum(int_value(row.n_low_ess) for row in group)
        push!(rows, (;
            block,
            parameter_space = :raw_unconstrained,
            n_rows = length(group),
            n_warning_rows =
                count(row -> symbol_value(row.flag) !== :ok, group),
            n_models = length(unique(symbol_value(row.model) for row in group)),
            n_splits = length(unique((int_value(row.base_seed),
                symbol_value(row.scenario), int_value(row.split_offset))
                for row in group)),
            max_rhat = round_or_missing(max_rhat),
            min_ess = round_or_missing(min_ess),
            total_bad_rhat = n_bad_rhat,
            total_low_ess = n_low_ess,
            priority_score =
                priority_score(max_rhat, min_ess, n_bad_rhat, n_low_ess),
            recommendation = block_recommendation(block),
            public_claim_allowed = false,
        ))
    end
    return sort(rows; by = row -> (-row.priority_score, string(row.block)))
end

function direct_block_surface_rows(block_rows)
    direct = [row for row in block_rows
        if symbol_value(row.parameter_space) === :direct_constrained]
    blocks = sort(unique(symbol_value(row.block) for row in direct);
        by = string)
    rows = NamedTuple[]
    for block in blocks
        group = [row for row in direct if symbol_value(row.block) === block]
        push!(rows, (;
            block,
            parameter_space = :direct_constrained,
            n_rows = length(group),
            n_warning_rows =
                count(row -> symbol_value(row.flag) !== :ok, group),
            max_rhat = round_or_missing(maximum_or_missing(
                row.max_rhat for row in group)),
            min_ess = round_or_missing(minimum_or_missing(
                row.min_ess for row in group)),
            total_bad_rhat = sum(int_value(row.n_bad_rhat) for row in group),
            total_low_ess = sum(int_value(row.n_low_ess) for row in group),
            public_claim_allowed = false,
        ))
    end
    return sort(rows; by = row -> (-row.total_low_ess, string(row.block)))
end

function model_split_priority_rows(model_rows)
    keys = sort(unique((symbol_value(row.model), int_value(row.base_seed),
        symbol_value(row.scenario), int_value(row.split_offset))
        for row in model_rows); by = string)
    rows = NamedTuple[]
    for key in keys
        model, base_seed, scenario, split_offset = key
        group = [row for row in model_rows
            if symbol_value(row.model) === model &&
               int_value(row.base_seed) == base_seed &&
               symbol_value(row.scenario) === scenario &&
               int_value(row.split_offset) == split_offset]
        row = only(group)
        score = priority_score(row.max_rhat, row.min_ess,
            int_value(row.n_bad_rhat), int_value(row.n_low_ess))
        push!(rows, (;
            model,
            base_seed,
            scenario,
            split_offset,
            split_seed = int_value(row.split_seed),
            diagnostic_flag = symbol_value(row.diagnostic_flag),
            warning_source = symbol_value(row.warning_source),
            max_rhat = round_or_missing(row.max_rhat),
            min_ess = round_or_missing(row.min_ess),
            n_bad_rhat = int_value(row.n_bad_rhat),
            n_low_ess = int_value(row.n_low_ess),
            priority_score = score,
            public_claim_allowed = false,
        ))
    end
    return sort(rows; by = row -> (-row.priority_score, string(row.model)))
end

function budget_profile_rows(surface)
    controls = surface.fit_controls
    chains = int_value(controls.chains)
    warmup = int_value(controls.warmup_per_chain)
    draws = int_value(controls.draws_per_chain)
    target_acceptance = Float64(controls.target_acceptance)
    return [
        (profile = :current_recorded,
            chains,
            warmup_per_chain = warmup,
            draws_per_chain = draws,
            target_acceptance,
            purpose = :baseline_warning_surface,
            expected_use = :reference_only,
            public_claim_allowed = false),
        (profile = :draws_x2_smoke,
            chains,
            warmup_per_chain = warmup,
            draws_per_chain = 2 * draws,
            target_acceptance,
            purpose = :test_linear_ess_gain_before_large_grid,
            expected_use = :first_executable_followup,
            public_claim_allowed = false),
        (profile = :draws_x4_gate,
            chains,
            warmup_per_chain = 2 * warmup,
            draws_per_chain = 4 * draws,
            target_acceptance,
            purpose = :attempt_to_clear_ess_threshold_if_smoke_improves,
            expected_use = :second_stage_local_gate,
            public_claim_allowed = false),
        (profile = :chains_x6_rhat_check,
            chains = max(6, chains),
            warmup_per_chain = warmup,
            draws_per_chain = 2 * draws,
            target_acceptance,
            purpose = :separate_rhat_sensitivity_from_draw_count,
            expected_use = :rhat_specific_followup,
            public_claim_allowed = false),
        (profile = :parameterization_audit,
            chains = 0,
            warmup_per_chain = 0,
            draws_per_chain = 0,
            target_acceptance = 0.0,
            purpose = :inspect_high_priority_blocks_without_new_mcmc,
            expected_use = :parallel_code_review_and_model_review,
            public_claim_allowed = false),
    ]
end

function execution_job_rows(block_rows, model_split_rows, options)
    top_blocks = [row.block for row in
        block_rows[1:min(options.top_blocks, length(block_rows))]]
    focus = model_split_rows[1:min(options.top_model_splits,
        length(model_split_rows))]
    rows = NamedTuple[]
    for (index, row) in pairs(focus)
        push!(rows, (;
            sequence = index,
            job = Symbol("draws_x2_smoke_", row.model, "_split_",
                row.split_offset),
            profile = :draws_x2_smoke,
            model = row.model,
            base_seed = row.base_seed,
            scenario = row.scenario,
            split_offset = row.split_offset,
            target_blocks = top_blocks,
            success_check =
                :warning_source_stays_non_geometry_and_ess_rhat_improve,
            public_claim_allowed = false,
        ))
    end
    push!(rows, (;
        sequence = length(rows) + 1,
        job = :draws_x4_gate_all_models_if_smoke_improves,
        profile = :draws_x4_gate,
        model = :all_mcmc_models,
        base_seed = first(focus).base_seed,
        scenario = first(focus).scenario,
        split_offset = :all_selected_splits,
        target_blocks = top_blocks,
        success_check = :no_mcmc_warning_or_explain_remaining_block_warnings,
        public_claim_allowed = false,
    ))
    push!(rows, (;
        sequence = length(rows) + 1,
        job = :parameterization_audit_high_priority_blocks,
        profile = :parameterization_audit,
        model = :mgmfrm_and_scalar_controls,
        base_seed = first(focus).base_seed,
        scenario = first(focus).scenario,
        split_offset = :not_applicable,
        target_blocks = top_blocks,
        success_check = :identify_whether_budget_or_model_geometry_is_primary,
        public_claim_allowed = false,
    ))
    return rows
end

function finding_rows(block_rows, model_split_rows, budget_rows)
    top_block = first(block_rows)
    worst_cell = first(model_split_rows)
    return [
        (finding = :block_targeted_followup_plan_recorded,
            severity = :info,
            evidence = string(length(block_rows),
                " raw block priority row(s)"),
            implication = :next_mcmc_runs_are_now_focused,
            public_claim_allowed = false),
        (finding = :dominant_warning_block,
            severity = :warning,
            evidence = string(top_block.block, " priority score ",
                top_block.priority_score, "; min ESS ", top_block.min_ess,
                "; max Rhat ", top_block.max_rhat),
            implication = top_block.recommendation,
            public_claim_allowed = false),
        (finding = :worst_model_split_cell,
            severity = :warning,
            evidence = string(worst_cell.model, " split ",
                worst_cell.split_offset, "; min ESS ", worst_cell.min_ess,
                "; max Rhat ", worst_cell.max_rhat),
            implication = :run_draws_x2_smoke_before_large_grid,
            public_claim_allowed = false),
        (finding = :thinning_not_primary,
            severity = :info,
            evidence = "warnings are raw R-hat/ESS with no geometry warnings",
            implication =
                :increase_draws_chains_or_review_parameterization_first,
            public_claim_allowed = false),
        (finding = :public_claims_blocked,
            severity = :blocker,
            evidence = "local follow-up plan only",
            implication =
                :do_not_claim_public_fit_thresholds_model_weights_or_q_revisions,
            public_claim_allowed = false),
    ]
end

function source_summary_record(summary)
    return (;
        n_model_diagnostic_rows = int_value(summary.n_model_diagnostic_rows),
        n_warning_rows = int_value(summary.n_warning_rows),
        n_raw_rhat_ess_warning_rows =
            int_value(summary.n_raw_rhat_ess_warning_rows),
        n_sampler_geometry_warning_rows =
            int_value(summary.n_sampler_geometry_warning_rows),
        n_direct_transform_warning_rows =
            int_value(summary.n_direct_transform_warning_rows),
        next_gate = symbol_value(summary.next_gate),
        no_public_fit_metric_claim = Bool(summary.no_public_fit_metric_claim),
        no_public_q_revision_claim = Bool(summary.no_public_q_revision_claim),
    )
end

function input_artifact_rows(options)
    return [(artifact = :sampler_warning_surface_diagnosis,
        path = rel(options.warning_surface_json),
        sha256 = file_sha256(options.warning_surface_json))]
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
        println(io, "# Uto-Style Block-Targeted Warning Follow-Up Plan")
        println(io)
        println(io, "- Generated at: `", artifact.generated_at, "`")
        println(io, "- Local only: `true`")
        println(io, "- Public claims allowed: `false`")
        println(io)
        println(io, "## Findings")
        table(io, ["Finding", "Severity", "Evidence", "Implication"],
            [[row.finding, row.severity, row.evidence, row.implication]
             for row in artifact.finding_rows])
        println(io, "## Raw Block Priorities")
        table(io, ["Block", "Rows", "Models", "Splits", "Max Rhat",
                "Min ESS", "Bad Rhat", "Low ESS", "Score", "Action"],
            [[row.block, row.n_rows, row.n_models, row.n_splits,
                row.max_rhat, row.min_ess, row.total_bad_rhat,
                row.total_low_ess, row.priority_score, row.recommendation]
             for row in artifact.raw_block_priority_rows])
        println(io, "## Model/Split Priorities")
        table(io, ["Model", "Split", "Max Rhat", "Min ESS", "Bad Rhat",
                "Low ESS", "Score"],
            [[row.model, row.split_offset, row.max_rhat, row.min_ess,
                row.n_bad_rhat, row.n_low_ess, row.priority_score]
             for row in artifact.model_split_priority_rows])
        println(io, "## Budget Profiles")
        table(io, ["Profile", "Chains", "Warmup", "Draws", "Purpose"],
            [[row.profile, row.chains, row.warmup_per_chain,
                row.draws_per_chain, row.purpose]
             for row in artifact.budget_profile_rows])
        println(io, "## Execution Jobs")
        table(io, ["Seq", "Job", "Profile", "Model", "Split", "Blocks"],
            [[row.sequence, row.job, row.profile, row.model,
                row.split_offset, join(string.(row.target_blocks), ", ")]
             for row in artifact.execution_job_rows])
        println(io, "## Boundary")
        println(io)
        println(io,
            "This is a local execution plan. It narrows the next sampler ",
            "follow-up and does not authorize public threshold or Q-revision ",
            "claims.")
    end
    return path
end

function build_artifact(options)
    surface = read_json(options.warning_surface_json)
    raw_blocks = raw_block_priority_rows(surface.block_diagnostic_rows)
    direct_blocks = direct_block_surface_rows(surface.block_diagnostic_rows)
    model_splits = model_split_priority_rows(surface.model_diagnostic_rows)
    budgets = budget_profile_rows(surface)
    jobs = execution_job_rows(raw_blocks, model_splits, options)
    findings = finding_rows(raw_blocks, model_splits, budgets)
    return (;
        schema = OUTPUT_SCHEMA,
        family = :mgmfrm,
        scope = :uto_style_block_targeted_warning_followup_plan,
        status = :local_block_targeted_followup_plan_recorded,
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
        source_summary = source_summary_record(surface.summary),
        raw_block_priority_rows = raw_blocks,
        direct_block_surface_rows = direct_blocks,
        model_split_priority_rows = model_splits,
        budget_profile_rows = budgets,
        execution_job_rows = jobs,
        finding_rows = findings,
        summary = (;
            passed = true,
            n_raw_block_priority_rows = length(raw_blocks),
            n_direct_block_surface_rows = length(direct_blocks),
            n_model_split_priority_rows = length(model_splits),
            n_budget_profiles = length(budgets),
            n_execution_jobs = length(jobs),
            top_raw_block = first(raw_blocks).block,
            top_raw_block_priority_score = first(raw_blocks).priority_score,
            top_model_split_model = first(model_splits).model,
            top_model_split_offset = first(model_splits).split_offset,
            recommended_first_profile = :draws_x2_smoke,
            no_public_fit_metric_claim = true,
            no_public_q_revision_claim = true,
            no_automatic_q_revision = true,
            no_public_model_weight_claim = true,
            no_sparse_superiority_claim = true,
            next_gate = :execute_draws_x2_smoke_on_priority_model_splits,
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
    println("top_block=", artifact.summary.top_raw_block,
        " top_model=", artifact.summary.top_model_split_model,
        " split=", artifact.summary.top_model_split_offset,
        " jobs=", artifact.summary.n_execution_jobs,
        " next_gate=", artifact.summary.next_gate)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
