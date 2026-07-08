#!/usr/bin/env julia

using Dates
using JSON3
using SHA
using Statistics
using TOML

module DrawsX2
include(joinpath(@__DIR__, "generate_mgmfrm_uto_style_draws_x2_smoke_followup.jl"))
end

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_RANK_GATE_JSON =
    joinpath(ROOT, "artifacts",
        "uto_style_rank_normalized_diagnostic_gate",
        "uto_style_rank_normalized_diagnostic_gate.json")
const DEFAULT_PLAN_JSON =
    joinpath(ROOT, "artifacts",
        "uto_style_block_targeted_warning_followup_plan",
        "uto_style_block_targeted_warning_followup_plan.json")
const DEFAULT_WARNING_SURFACE_JSON =
    joinpath(ROOT, "artifacts",
        "uto_style_sampler_warning_surface_diagnosis",
        "uto_style_sampler_warning_surface_diagnosis.json")
const DEFAULT_STAN_REVIEW_JSON =
    joinpath(ROOT, "artifacts",
        "uto_style_stan_guided_sampler_remediation_review",
        "uto_style_stan_guided_sampler_remediation_review.json")
const DEFAULT_OUTPUT_JSON =
    joinpath(ROOT, "artifacts",
        "uto_style_rank_warning_parameterization_audit",
        "uto_style_rank_warning_parameterization_audit.json")
const DEFAULT_OUTPUT_MD =
    joinpath(ROOT, "artifacts",
        "uto_style_rank_warning_parameterization_audit",
        "uto_style_rank_warning_parameterization_audit.md")

include(joinpath(@__DIR__, "local_json.jl"))

const OUTPUT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_uto_style_rank_warning_parameterization_audit.v1"
const RHAT_THRESHOLD = 1.01
const ESS_THRESHOLD = 400.0

function usage()
    return """
    Build a local parameterization audit for the rank-warning MGMFRM blocks.

    This is a no-new-MCMC gate. It reads the rank-normalized diagnostic gate,
    reconstructs the same train splits, joins warning parameters to observed
    support, and records implementation-level parameterization hypotheses.

    Usage:
      julia --project=. scripts/generate_mgmfrm_uto_style_rank_warning_parameterization_audit.jl [options]

    Options:
      --rank-gate-json PATH        Rank-normalized diagnostic gate artifact.
      --plan-json PATH             Block-targeted follow-up plan artifact.
      --warning-surface-json PATH  Baseline warning-surface artifact.
      --stan-review-json PATH      Stan-guided review artifact.
      --output-json PATH           JSON artifact path.
      --output-md PATH             Markdown report path.
    """
end

function parse_args(args)
    rank_gate_json = DEFAULT_RANK_GATE_JSON
    plan_json = DEFAULT_PLAN_JSON
    warning_surface_json = DEFAULT_WARNING_SURFACE_JSON
    stan_review_json = DEFAULT_STAN_REVIEW_JSON
    output_json = DEFAULT_OUTPUT_JSON
    output_md = DEFAULT_OUTPUT_MD
    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--rank-gate-json"
            index < length(args) || error("--rank-gate-json requires a path")
            rank_gate_json = abspath(args[index + 1])
            index += 2
        elseif arg == "--plan-json"
            index < length(args) || error("--plan-json requires a path")
            plan_json = abspath(args[index + 1])
            index += 2
        elseif arg == "--warning-surface-json"
            index < length(args) ||
                error("--warning-surface-json requires a path")
            warning_surface_json = abspath(args[index + 1])
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
        elseif arg in ("-h", "--help")
            println(usage())
            exit(0)
        else
            error("unknown argument: $arg")
        end
    end
    for path in (rank_gate_json, plan_json, warning_surface_json,
            stan_review_json)
        isfile(path) || error("input artifact not found: $path")
    end
    return (; rank_gate_json, plan_json, warning_surface_json,
        stan_review_json, output_json, output_md)
end

project_version() =
    String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])
file_sha256(path::AbstractString) = bytes2hex(open(sha256, path))
rel(path::AbstractString) = relpath(path, ROOT)
read_json(path::AbstractString) = JSON3.read(read(path, String))
symbol_value(value) = Symbol(string(value))
int_value(value) = Int(value)
round4(value) = round(Float64(value); digits = 4)

function finite_float(value)
    ismissing(value) && return missing
    float = Float64(value)
    return isfinite(float) ? float : missing
end

function warning_reasons(row)
    reasons = Symbol[]
    finite_float(row.rank_rhat) !== missing &&
        finite_float(row.rank_rhat) > RHAT_THRESHOLD &&
        push!(reasons, :rank_rhat)
    finite_float(row.bulk_ess) !== missing &&
        finite_float(row.bulk_ess) < ESS_THRESHOLD &&
        push!(reasons, :bulk_ess)
    finite_float(row.tail_ess) !== missing &&
        finite_float(row.tail_ess) < ESS_THRESHOLD &&
        push!(reasons, :tail_ess)
    return isempty(reasons) ? [:rank_warning] : reasons
end

function parameter_kind(parameter::AbstractString)
    startswith(parameter, "person[") && return :person
    startswith(parameter, "item_step[") && return :item_steps
    startswith(parameter, "item[") && return :item
    startswith(parameter, "raw_log_item_dimension_discrimination[") &&
        return :log_item_dimension_discrimination
    startswith(parameter, "item_dimension_discrimination[") &&
        return :item_dimension_discrimination
    startswith(parameter, "raw_log_rater_consistency[") &&
        return :log_rater_consistency
    startswith(parameter, "rater_consistency[") &&
        return :rater_consistency
    return :other
end

function parsed_parameter(parameter::AbstractString)
    person = match(r"^person\[(.+),dim=(\d+)\]$", parameter)
    person !== nothing && return (;
        kind = :person,
        label = person.captures[1],
        dim = parse(Int, person.captures[2]),
        item = missing,
        step = missing,
    )
    item = match(r"^item\[(.+)\]$", parameter)
    item !== nothing && return (;
        kind = :item,
        label = item.captures[1],
        dim = missing,
        item = item.captures[1],
        step = missing,
    )
    item_step = match(r"^item_step\[item=(.+),m=(\d+)\]$", parameter)
    item_step !== nothing && return (;
        kind = :item_steps,
        label = item_step.captures[1],
        dim = missing,
        item = item_step.captures[1],
        step = parse(Int, item_step.captures[2]),
    )
    return (;
        kind = parameter_kind(parameter),
        label = parameter,
        dim = missing,
        item = missing,
        step = missing,
    )
end

function level_index(levels, label::AbstractString)
    index = findfirst(level -> string(level) == label, collect(levels))
    return index === nothing ? missing : index
end

function counts_by_category(data, mask)
    return [
        (category = string(data.category_levels[index]),
            n = count(row -> mask[row] && data.category[row] == index,
                1:data.n))
        for index in eachindex(data.category_levels)
    ]
end

function support_status(n_rows::Int, min_category_count::Int)
    n_rows < 8 && return :low_row_support
    min_category_count == 0 && return :category_gap
    min_category_count < 3 && return :sparse_category_support
    n_rows < 16 && return :moderate_row_support
    return :adequate_local_row_support
end

function support_for_parameter(data, parameter::AbstractString)
    parsed = parsed_parameter(parameter)
    if parsed.kind === :person
        idx = level_index(data.person_levels, parsed.label)
        ismissing(idx) && return (;
            support_kind = :person,
            support_status = :level_not_found,
            n_train_rows = 0,
            n_distinct_persons = length(data.person_levels),
            n_distinct_items = 0,
            n_distinct_raters = 0,
            n_at_or_above_step = missing,
            n_below_step = missing,
            category_counts = NamedTuple[],
        )
        mask = [data.person[row] == idx for row in 1:data.n]
        category_counts = counts_by_category(data, mask)
        min_category_count = minimum(row.n for row in category_counts)
        return (;
            support_kind = :person,
            support_status =
                support_status(count(identity, mask), min_category_count),
            n_train_rows = count(identity, mask),
            n_distinct_persons = 1,
            n_distinct_items = length(unique(data.item[mask])),
            n_distinct_raters = length(unique(data.rater[mask])),
            n_at_or_above_step = missing,
            n_below_step = missing,
            category_counts,
        )
    elseif parsed.kind === :item
        idx = level_index(data.item_levels, parsed.item)
        ismissing(idx) && return (;
            support_kind = :item,
            support_status = :level_not_found,
            n_train_rows = 0,
            n_distinct_persons = 0,
            n_distinct_items = length(data.item_levels),
            n_distinct_raters = 0,
            n_at_or_above_step = missing,
            n_below_step = missing,
            category_counts = NamedTuple[],
        )
        mask = [data.item[row] == idx for row in 1:data.n]
        category_counts = counts_by_category(data, mask)
        min_category_count = minimum(row.n for row in category_counts)
        return (;
            support_kind = :item,
            support_status =
                support_status(count(identity, mask), min_category_count),
            n_train_rows = count(identity, mask),
            n_distinct_persons = length(unique(data.person[mask])),
            n_distinct_items = 1,
            n_distinct_raters = length(unique(data.rater[mask])),
            n_at_or_above_step = missing,
            n_below_step = missing,
            category_counts,
        )
    elseif parsed.kind === :item_steps
        idx = level_index(data.item_levels, parsed.item)
        ismissing(idx) && return (;
            support_kind = :item_steps,
            support_status = :level_not_found,
            n_train_rows = 0,
            n_distinct_persons = 0,
            n_distinct_items = length(data.item_levels),
            n_distinct_raters = 0,
            n_at_or_above_step = 0,
            n_below_step = 0,
            category_counts = NamedTuple[],
        )
        mask = [data.item[row] == idx for row in 1:data.n]
        category_counts = counts_by_category(data, mask)
        min_category_count = minimum(row.n for row in category_counts)
        step = Int(parsed.step)
        n_at_or_above = count(row -> mask[row] && data.category[row] >= step,
            1:data.n)
        n_below = count(row -> mask[row] && data.category[row] < step,
            1:data.n)
        status = if n_at_or_above == 0 || n_below == 0
            :step_separation
        elseif min(n_at_or_above, n_below) < 3
            :sparse_step_split
        else
            support_status(count(identity, mask), min_category_count)
        end
        return (;
            support_kind = :item_steps,
            support_status = status,
            n_train_rows = count(identity, mask),
            n_distinct_persons = length(unique(data.person[mask])),
            n_distinct_items = 1,
            n_distinct_raters = length(unique(data.rater[mask])),
            n_at_or_above_step = n_at_or_above,
            n_below_step = n_below,
            category_counts,
        )
    end
    return (;
        support_kind = parsed.kind,
        support_status = :not_applicable_for_this_audit,
        n_train_rows = data.n,
        n_distinct_persons = length(data.person_levels),
        n_distinct_items = length(data.item_levels),
        n_distinct_raters = length(data.rater_levels),
        n_at_or_above_step = missing,
        n_below_step = missing,
        category_counts = NamedTuple[],
    )
end

function raw_warning_rows(rank_gate)
    rows = NamedTuple[]
    for row in rank_gate.parameter_rows
        symbol_value(row.parameter_space) === :raw_unconstrained || continue
        symbol_value(row.flag) === :ok && continue
        parameter = String(row.parameter)
        push!(rows, (;
            model = symbol_value(row.model),
            base_seed = int_value(row.base_seed),
            scenario = symbol_value(row.scenario),
            split_offset = int_value(row.split_offset),
            parameter,
            block = parameter_kind(parameter),
            rank_rhat = round4(row.rank_rhat),
            bulk_ess = round4(row.bulk_ess),
            tail_ess = round4(row.tail_ess),
            warning_reasons = warning_reasons(row),
        ))
    end
    return rows
end

function block_warning_rows(rank_gate)
    return [(
        model = symbol_value(row.model),
        base_seed = int_value(row.base_seed),
        scenario = symbol_value(row.scenario),
        split_offset = int_value(row.split_offset),
        parameter_space = symbol_value(row.parameter_space),
        block = symbol_value(row.block),
        max_rank_rhat = round4(row.max_rank_rhat),
        min_bulk_ess = round4(row.min_bulk_ess),
        min_tail_ess = round4(row.min_tail_ess),
        n_bad_rank_rhat = int_value(row.n_bad_rank_rhat),
        n_low_bulk_ess = int_value(row.n_low_bulk_ess),
        n_low_tail_ess = int_value(row.n_low_tail_ess),
        flag = symbol_value(row.flag),
    ) for row in rank_gate.block_rows if symbol_value(row.flag) !== :ok]
end

function job_by_key(rank_gate)
    dict = Dict{Tuple{Symbol,Int,Symbol,Int},Any}()
    for job in rank_gate.job_rows
        key = (symbol_value(job.model), int_value(job.base_seed),
            symbol_value(job.scenario), int_value(job.split_offset))
        dict[key] = job
    end
    return dict
end

function train_data_for_job(surface, plan, job)
    profile = DrawsX2.profile_by_name(plan, :draws_x4_gate)
    options = DrawsX2.run_options(surface, profile, false)
    cell = DrawsX2.selected_cell(surface, job)
    split_context =
        DrawsX2.WarningSurface.scenario_split(options, cell, job.split_offset)
    spec = DrawsX2.model_spec(symbol_value(job.model))
    train = DrawsX2.WarningSurface.QMisspec.design_for_rows(
        split_context.split.train_rows,
        spec,
        split_context.scenario,
    )
    return train.spec.data
end

function support_rows(rank_gate, plan, surface, warnings)
    jobs = job_by_key(rank_gate)
    data_cache = Dict{Tuple{Symbol,Int,Symbol,Int},Any}()
    rows = NamedTuple[]
    for warning in warnings
        key = (warning.model, warning.base_seed, warning.scenario,
            warning.split_offset)
        haskey(jobs, key) || error("rank job not found for $key")
        if !haskey(data_cache, key)
            data_cache[key] = train_data_for_job(surface, plan, jobs[key])
        end
        support = support_for_parameter(data_cache[key], warning.parameter)
        push!(rows, merge(warning, support, (;
            public_claim_allowed = false,
        )))
    end
    return rows
end

function block_summary_rows(warnings)
    blocks = sort(unique(row.block for row in warnings); by = string)
    rows = NamedTuple[]
    for block in blocks
        selected = [row for row in warnings if row.block === block]
        push!(rows, (;
            block,
            n_warning_parameters = length(selected),
            n_model_splits = length(unique((row.model, row.split_offset)
                for row in selected)),
            max_rank_rhat = round4(maximum(row.rank_rhat for row in selected)),
            min_bulk_ess = round4(minimum(row.bulk_ess for row in selected)),
            min_tail_ess = round4(minimum(row.tail_ess for row in selected)),
            warning_reasons = sort(unique(reduce(vcat,
                (row.warning_reasons for row in selected))); by = string),
            public_claim_allowed = false,
        ))
    end
    return rows
end

function implementation_audit_rows(warnings, support)
    warning_blocks = Set(row.block for row in warnings)
    support_statuses(block) =
        sort(unique(row.support_status for row in support if row.block === block);
            by = string)
    return [
        (block = :person,
            current_parameterization = :identity_raw_person_ability_by_dimension,
            current_constraint = :standard_normal_location_scale_gauge,
            warning_present = :person in warning_blocks,
            support_statuses = support_statuses(:person),
            audit_diagnosis =
                :direct_identity_coordinates_show_rank_and_bulk_tail_warnings,
            recommended_next_check = :join_warning_persons_to_item_rater_category_support,
            possible_remediation =
                :support_aware_initialization_or_person_block_reparameterization,
            public_claim_allowed = false),
        (block = :item,
            current_parameterization = :identity_raw_item_difficulty,
            current_constraint = :free_item_location_with_ability_gauge_and_prior,
            warning_present = :item in warning_blocks,
            support_statuses = support_statuses(:item),
            audit_diagnosis =
                :item_difficulty_mixes_with_person_and_item_step_coordinates,
            recommended_next_check = :item_support_and_item_step_coupling_review,
            possible_remediation =
                :centered_item_step_contrast_or_block_scaled_initialization,
            public_claim_allowed = false),
        (block = :item_steps,
            current_parameterization = :identity_free_item_steps_with_derived_last_step_in_likelihood,
            current_constraint = :first_step_zero_last_step_negative_sum,
            warning_present = :item_steps in warning_blocks,
            support_statuses = support_statuses(:item_steps),
            audit_diagnosis =
                :single_item_step_rank_rhat_warning_after_rank_gate,
            recommended_next_check =
                :inspect_item_step_category_split_and_step_constraint_reporting,
            possible_remediation =
                :orthogonal_item_step_contrasts_or_item_step_support_warning,
            public_claim_allowed = false),
        (block = :log_item_dimension_discrimination,
            current_parameterization = :log_link_positive_q_masked_loading,
            current_constraint = :fixed_confirmatory_q_positive_loading,
            warning_present = :log_item_dimension_discrimination in warning_blocks,
            support_statuses = support_statuses(:log_item_dimension_discrimination),
            audit_diagnosis = :not_a_residual_rank_gate_block,
            recommended_next_check = :monitor_only_in_next_pilot,
            possible_remediation = :none_before_person_item_step_checks,
            public_claim_allowed = false),
    ]
end

function control_audit_rows(rank_gate)
    all_geometry_zero = all(row -> int_value(row.n_divergences) == 0 &&
        int_value(row.n_max_treedepth) == 0 &&
        int_value(row.n_sampler_warnings) == 0, rank_gate.model_rows)
    return [
        (control = :init_jitter,
            current_status = :not_recorded_in_gate_artifact_default_fit_value_is_zero,
            evidence =
                :fit_calls_in_uto_gate_scripts_do_not_pass_init_jitter,
            risk = :same_raw_initial_each_chain_possible,
            priority = :high,
            recommended_next_check = :init_jitter_smoke_on_same_three_cells,
            public_claim_allowed = false),
        (control = :metric,
            current_status = :default_diagonal_metric,
            evidence = :fit_calls_do_not_override_metric,
            risk = :posterior_correlation_in_person_item_step_blocks,
            priority = :medium,
            recommended_next_check =
                :dense_metric_or_block_scaled_metric_only_after_support_join,
            public_claim_allowed = false),
        (control = :target_acceptance,
            current_status = :already_0_85_in_local_gates,
            evidence = all_geometry_zero ?
                :geometry_warnings_zero : :geometry_warnings_present,
            risk = all_geometry_zero ?
                :not_primary_current_failure_mode : :requires_geometry_review,
            priority = all_geometry_zero ? :low : :high,
            recommended_next_check =
                :do_not_raise_target_acceptance_before_parameterization_audit,
            public_claim_allowed = false),
        (control = :chain_count,
            current_status = :six_chain_gate_did_not_improve_vs_draws_x4,
            evidence = :chain_count_gate_summary,
            risk = :chain_count_only_escalation_wastes_budget,
            priority = :low,
            recommended_next_check = :avoid_chain_count_only_gate,
            public_claim_allowed = false),
    ]
end

function next_gate_rows()
    return [
        (gate = :support_join_for_warning_parameters,
            priority = 1,
            status = :completed_in_this_audit,
            purpose = :separate_sparse_support_from_parameterization,
            success_check = :warning_parameters_have_support_status_rows,
            public_claim_allowed = false),
        (gate = :init_jitter_smoke,
            priority = 2,
            status = :recommended_next_executable_gate,
            purpose = :check_sensitivity_to_same_zero_initialization,
            success_check =
                :same_three_cells_rank_warnings_improve_or_are_explained,
            public_claim_allowed = false),
        (gate = :person_item_step_coupling_pilot,
            priority = 3,
            status = :planned_after_init_jitter,
            purpose =
                :test_item_difficulty_item_step_or_person_block_reparameterization,
            success_check = :rank_bulk_tail_warnings_drop_in_target_blocks,
            public_claim_allowed = false),
        (gate = :public_threshold_or_q_wording,
            priority = 99,
            status = :blocked,
            purpose = :prevent_overclaiming,
            success_check = :requires_diagnostic_clearance_and_simulation_link,
            public_claim_allowed = false),
    ]
end

function input_artifact_rows(options)
    return [
        (artifact = :rank_normalized_diagnostic_gate,
            path = rel(options.rank_gate_json),
            sha256 = file_sha256(options.rank_gate_json)),
        (artifact = :block_targeted_warning_followup_plan,
            path = rel(options.plan_json),
            sha256 = file_sha256(options.plan_json)),
        (artifact = :sampler_warning_surface_diagnosis,
            path = rel(options.warning_surface_json),
            sha256 = file_sha256(options.warning_surface_json)),
        (artifact = :stan_guided_sampler_remediation_review,
            path = rel(options.stan_review_json),
            sha256 = file_sha256(options.stan_review_json)),
        (artifact = :mgmfrm_parameterization_source,
            path = "src/facet_workflow.jl",
            sha256 = file_sha256(joinpath(ROOT, "src", "facet_workflow.jl"))),
        (artifact = :mgmfrm_sampler_source,
            path = "src/bayesian_fit.jl",
            sha256 = file_sha256(joinpath(ROOT, "src", "bayesian_fit.jl"))),
    ]
end

function finding_rows(warnings, support, control_rows)
    support_flags = sort(unique(row.support_status for row in support);
        by = string)
    init_priority = only(row.priority for row in control_rows
        if row.control === :init_jitter)
    return [
        (finding = :rank_warning_parameterization_audit_recorded,
            severity = :info,
            evidence = string(length(warnings),
                " raw warning parameter rows joined to support"),
            implication = :parameterization_gate_has_local_evidence,
            public_claim_allowed = false),
        (finding = :warning_blocks_are_targeted,
            severity = :warning,
            evidence = join(string.(sort(unique(row.block for row in warnings);
                by = string)), ","),
            implication = :focus_person_item_item_steps,
            public_claim_allowed = false),
        (finding = :support_statuses_are_mixed,
            severity = :warning,
            evidence = join(string.(support_flags), ","),
            implication =
                :do_not_treat_all_rank_warnings_as_same_failure_mode,
            public_claim_allowed = false),
        (finding = :initialization_not_yet_tested,
            severity = init_priority === :high ? :warning : :info,
            evidence = :init_jitter_not_passed_in_current_gate_scripts,
            implication = :run_init_jitter_smoke_before_heavier_refits,
            public_claim_allowed = false),
        (finding = :public_claims_blocked,
            severity = :blocker,
            evidence = :rank_warning_gate_not_cleared,
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

function compact_reasons(reasons)
    return join(string.(reasons), ",")
end

function compact_categories(counts)
    isempty(counts) && return ""
    return join((string(row.category, ":", row.n) for row in counts), ",")
end

function render_markdown(path, artifact)
    mkpath(dirname(path))
    open(path, "w") do io
        println(io, "# Uto-Style Rank-Warning Parameterization Audit")
        println(io)
        println(io, "- Generated at: `", artifact.generated_at, "`")
        println(io, "- Local only: `true`")
        println(io, "- Public claims allowed: `false`")
        println(io)
        println(io, "## Findings")
        table(io, ["Finding", "Severity", "Evidence", "Implication"],
            [[row.finding, row.severity, row.evidence, row.implication]
             for row in artifact.finding_rows])
        println(io, "## Warning Parameters")
        table(io, ["Model", "Split", "Parameter", "Block", "Reasons",
                "Rows", "Support", "Cats"],
            [[row.model, row.split_offset, row.parameter, row.block,
                compact_reasons(row.warning_reasons), row.n_train_rows,
                row.support_status, compact_categories(row.category_counts)]
             for row in artifact.support_rows])
        println(io, "## Block Summary")
        table(io, ["Block", "N", "Model Splits", "Max Rank Rhat",
                "Min Bulk ESS", "Min Tail ESS", "Reasons"],
            [[row.block, row.n_warning_parameters, row.n_model_splits,
                row.max_rank_rhat, row.min_bulk_ess, row.min_tail_ess,
                compact_reasons(row.warning_reasons)]
             for row in artifact.block_summary_rows])
        println(io, "## Implementation Audit")
        table(io, ["Block", "Current Parameterization", "Warning",
                "Diagnosis", "Next Check"],
            [[row.block, row.current_parameterization, row.warning_present,
                row.audit_diagnosis, row.recommended_next_check]
             for row in artifact.implementation_audit_rows])
        println(io, "## Control Audit")
        table(io, ["Control", "Status", "Priority", "Risk", "Next Check"],
            [[row.control, row.current_status, row.priority, row.risk,
                row.recommended_next_check]
             for row in artifact.control_audit_rows])
        println(io, "## Next Gates")
        table(io, ["Gate", "Priority", "Status", "Purpose"],
            [[row.gate, row.priority, row.status, row.purpose]
             for row in artifact.next_gate_rows])
        println(io, "## Boundary")
        println(io)
        println(io,
            "This audit does not authorize public fit-threshold, Q-revision, ",
            "model-weight, or sparse-superiority claims. It narrows the next ",
            "local executable gate to an initialization-jitter smoke check and ",
            "then a targeted person/item/item-step parameterization pilot.")
    end
    return path
end

function build_artifact(options)
    rank_gate = read_json(options.rank_gate_json)
    plan = read_json(options.plan_json)
    surface = read_json(options.warning_surface_json)
    warnings = raw_warning_rows(rank_gate)
    block_warnings = block_warning_rows(rank_gate)
    support = support_rows(rank_gate, plan, surface, warnings)
    block_summary = block_summary_rows(warnings)
    implementation_rows = implementation_audit_rows(warnings, support)
    control_rows = control_audit_rows(rank_gate)
    gates = next_gate_rows()
    findings = finding_rows(warnings, support, control_rows)
    return (;
        schema = OUTPUT_SCHEMA,
        family = :mgmfrm,
        scope = :uto_style_rank_warning_parameterization_audit,
        status = :local_parameterization_audit_recorded,
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
        diagnostic_policy = (;
            rank_gate_schema = string(rank_gate.schema),
            no_new_mcmc = true,
            support_join = true,
            parameterization_patch_applied = false,
            public_claim_allowed = false,
        ),
        warning_parameter_rows = warnings,
        rank_block_warning_rows = block_warnings,
        support_rows = support,
        block_summary_rows = block_summary,
        implementation_audit_rows = implementation_rows,
        control_audit_rows = control_rows,
        next_gate_rows = gates,
        finding_rows = findings,
        summary = (;
            passed = true,
            n_raw_warning_parameters = length(warnings),
            n_warning_blocks = length(unique(row.block for row in warnings)),
            n_rank_block_warning_rows = length(block_warnings),
            n_support_rows = length(support),
            warning_blocks = sort(unique(row.block for row in warnings);
                by = string),
            support_statuses = sort(unique(row.support_status for row in support);
                by = string),
            no_new_mcmc = true,
            no_public_fit_metric_claim = true,
            no_public_q_revision_claim = true,
            no_automatic_q_revision = true,
            no_public_model_weight_claim = true,
            no_sparse_superiority_claim = true,
            next_gate = :init_jitter_smoke_on_rank_warning_cells,
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
    println("warnings=", artifact.summary.n_raw_warning_parameters,
        " blocks=", join(string.(artifact.summary.warning_blocks), ","),
        " next_gate=", artifact.summary.next_gate)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
