#!/usr/bin/env julia

using Dates
using JSON3
using SHA
using TOML

module SplitGrid
include(joinpath(@__DIR__,
    "generate_mgmfrm_uto_style_split_controlled_critical_grid.jl"))
end

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_SPLIT_GRID_JSON =
    joinpath(ROOT, "artifacts", "uto_style_split_controlled_critical_grid",
        "uto_style_split_controlled_critical_grid.json")
const DEFAULT_OUTPUT_JSON =
    joinpath(ROOT, "artifacts", "uto_style_sampler_remediation_critical_pilot",
        "uto_style_sampler_remediation_critical_pilot.json")
const DEFAULT_OUTPUT_MD =
    joinpath(ROOT, "artifacts", "uto_style_sampler_remediation_critical_pilot",
        "uto_style_sampler_remediation_critical_pilot.md")

include(joinpath(@__DIR__, "local_json.jl"))

const OUTPUT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_uto_style_sampler_remediation_critical_pilot.v1"
const DEFAULT_SPLIT_OFFSETS = SplitGrid.DEFAULT_SPLIT_OFFSETS
const DEFAULT_THRESHOLDS = SplitGrid.DEFAULT_THRESHOLDS
const MCMC_MODEL_NAMES = SplitGrid.MCMC_MODEL_NAMES

function usage()
    return """
    Run a targeted sampler-remediation pilot on split-stable critical cells.

    By default, this reads the split-controlled critical grid, selects cells
    whose threshold risk labels were stable across split offsets, and reruns
    them with a larger local MCMC budget. It is a local diagnostic only; public
    fit-threshold, model-weight, and Q-revision claims remain blocked.

    Usage:
      julia --project=. scripts/generate_mgmfrm_uto_style_sampler_remediation_critical_pilot.jl [options]

    Options:
      --split-grid-json PATH    Split-controlled critical grid artifact.
      --output-json PATH        JSON artifact path.
      --output-md PATH          Markdown report path.
      --cell-mode MODE          stable, sensitive, or all. Default: stable.
      --split-offsets LIST      Comma-separated split offsets. Default: 17,101.
      --thresholds LIST         Comma-separated dLogScore thresholds. Default: 0,2,4,8.
      --max-cells N             Limit selected cells for smoke runs. Default: all.
      --n-persons N             Number of persons. Default: 6.
      --n-raters N              Number of raters. Default: 3.
      --heldout-fraction X      Observation holdout fraction. Default: 0.17.
      --chains N                MCMC chains. Default: 4.
      --warmup-per-chain N      Warmup iterations per chain. Default: 64.
      --draws-per-chain N       Posterior draws per chain. Default: 64.
      --target-acceptance X     NUTS target acceptance. Default: 0.85.
      --prior-profile NAME      Internal source prior profile: default, tight, or diffuse.
                                Default: default.
      --progress                Show sampler progress.
    """
end

function parse_int_list(text::AbstractString, option::AbstractString)
    values = Int[]
    for part in split(text, ",")
        stripped = strip(part)
        isempty(stripped) && continue
        push!(values, parse(Int, stripped))
    end
    isempty(values) && error("$option must contain at least one value")
    length(unique(values)) == length(values) ||
        error("$option values must be unique")
    return values
end

function parse_thresholds(text::AbstractString)
    values = Float64[]
    for part in split(text, ",")
        stripped = strip(part)
        isempty(stripped) && continue
        push!(values, parse(Float64, stripped))
    end
    isempty(values) && error("--thresholds must contain at least one value")
    all(>=(0), values) || error("--thresholds must be non-negative")
    length(unique(values)) == length(values) ||
        error("--thresholds values must be unique")
    return sort(values)
end

function parse_args(args)
    split_grid_json = DEFAULT_SPLIT_GRID_JSON
    output_json = DEFAULT_OUTPUT_JSON
    output_md = DEFAULT_OUTPUT_MD
    cell_mode = :stable
    split_offsets = copy(DEFAULT_SPLIT_OFFSETS)
    thresholds = copy(DEFAULT_THRESHOLDS)
    max_cells = 0
    n_persons = 6
    n_raters = 3
    heldout_fraction = 0.17
    chains = 4
    warmup_per_chain = 64
    draws_per_chain = 64
    target_acceptance = 0.85
    prior_profile = :default
    progress = false

    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--split-grid-json"
            index < length(args) || error("--split-grid-json requires a path")
            split_grid_json = abspath(args[index + 1])
            index += 2
        elseif arg == "--output-json"
            index < length(args) || error("--output-json requires a path")
            output_json = abspath(args[index + 1])
            index += 2
        elseif arg == "--output-md"
            index < length(args) || error("--output-md requires a path")
            output_md = abspath(args[index + 1])
            index += 2
        elseif arg == "--cell-mode"
            index < length(args) || error("--cell-mode requires a value")
            cell_mode = Symbol(args[index + 1])
            index += 2
        elseif arg == "--split-offsets"
            index < length(args) || error("--split-offsets requires a list")
            split_offsets = parse_int_list(args[index + 1], "--split-offsets")
            index += 2
        elseif arg == "--thresholds"
            index < length(args) || error("--thresholds requires a list")
            thresholds = parse_thresholds(args[index + 1])
            index += 2
        elseif arg == "--max-cells"
            index < length(args) || error("--max-cells requires an integer")
            max_cells = parse(Int, args[index + 1])
            index += 2
        elseif arg == "--n-persons"
            index < length(args) || error("--n-persons requires an integer")
            n_persons = parse(Int, args[index + 1])
            index += 2
        elseif arg == "--n-raters"
            index < length(args) || error("--n-raters requires an integer")
            n_raters = parse(Int, args[index + 1])
            index += 2
        elseif arg == "--heldout-fraction"
            index < length(args) ||
                error("--heldout-fraction requires a number")
            heldout_fraction = parse(Float64, args[index + 1])
            index += 2
        elseif arg == "--chains"
            index < length(args) || error("--chains requires an integer")
            chains = parse(Int, args[index + 1])
            index += 2
        elseif arg == "--warmup-per-chain"
            index < length(args) ||
                error("--warmup-per-chain requires an integer")
            warmup_per_chain = parse(Int, args[index + 1])
            index += 2
        elseif arg == "--draws-per-chain"
            index < length(args) ||
                error("--draws-per-chain requires an integer")
            draws_per_chain = parse(Int, args[index + 1])
            index += 2
        elseif arg == "--target-acceptance"
            index < length(args) ||
                error("--target-acceptance requires a number")
            target_acceptance = parse(Float64, args[index + 1])
            index += 2
        elseif arg == "--prior-profile"
            index < length(args) || error("--prior-profile requires a name")
            prior_profile = Symbol(args[index + 1])
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

    isfile(split_grid_json) ||
        error("split grid artifact not found: $split_grid_json")
    cell_mode in (:stable, :sensitive, :all) ||
        error("--cell-mode must be stable, sensitive, or all")
    max_cells >= 0 || error("--max-cells must be non-negative")
    n_persons >= 6 || error("--n-persons must be at least 6")
    n_raters >= 3 || error("--n-raters must be at least 3")
    0 < heldout_fraction < 0.5 ||
        error("--heldout-fraction must be in (0, 0.5)")
    chains >= 1 || error("--chains must be positive")
    warmup_per_chain >= 0 || error("--warmup-per-chain must be non-negative")
    draws_per_chain >= 1 || error("--draws-per-chain must be positive")
    0 < target_acceptance < 1 ||
        error("--target-acceptance must be in (0, 1)")
    prior_profile in (:default, :tight, :diffuse) ||
        error("--prior-profile must be default, tight, or diffuse")
    return (;
        split_grid_json,
        output_json,
        output_md,
        cell_mode,
        split_offsets,
        thresholds,
        max_cells,
        n_persons,
        n_items = size(SplitGrid.ReplicatedQCategory.QMisspec.Q_BASE, 1),
        n_raters,
        heldout_fraction,
        chains,
        warmup_per_chain,
        draws_per_chain,
        target_acceptance,
        prior_profile,
        progress,
    )
end

project_version() =
    String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])
file_sha256(path::AbstractString) = bytes2hex(open(sha256, path))
rel(path::AbstractString) = relpath(path, ROOT)
round3(value) = round(Float64(value); digits = 3)
round4(value) = round(Float64(value); digits = 4)

read_json(path::AbstractString) = JSON3.read(read(path, String))

function actual_seed(base_seed::Integer, scenario)
    return Int(base_seed) + 2 * Int(scenario.seed_offset)
end

function selected_cells(split_grid, mode::Symbol, max_cells::Int)
    rows = NamedTuple[]
    for row in split_grid.split_delta_rows
        stable = Int(row.n_threshold_risk_changes) == 0
        keep = mode === :all ||
               (mode === :stable && stable) ||
               (mode === :sensitive && !stable)
        keep || continue
        scenario = SplitGrid.scenario_by_name(row.scenario)
        push!(rows, (;
            scenario = Symbol(string(row.scenario)),
            axis = Symbol(string(row.axis)),
            base_seed = Int(row.base_seed),
            actual_seed = actual_seed(Int(row.base_seed), scenario),
            previous_n_threshold_risk_changes =
                Int(row.n_threshold_risk_changes),
            previous_delta_candidate_log_score =
                Float64(row.delta_candidate_log_score),
            previous_changed_threshold_risks =
                [Symbol(string(value)) for value in row.changed_threshold_risks],
        ))
    end
    max_cells == 0 && return rows
    return rows[1:min(max_cells, length(rows))]
end

function scenario_cell(options, cell, split_offset::Int)
    critical = (;
        scenario = cell.scenario,
        axis = cell.axis,
        base_seed = cell.base_seed,
        actual_seed = cell.actual_seed,
        n_threshold_risk_changes = cell.previous_n_threshold_risk_changes,
        changed_threshold_risks = cell.previous_changed_threshold_risks,
    )
    return SplitGrid.scenario_cell_with_split(options, critical, split_offset)
end

function threshold_rows(cell_rows, thresholds)
    SplitGrid.threshold_rows(cell_rows, thresholds)
end

function threshold_summary_rows(thresholds)
    SplitGrid.threshold_summary_rows(thresholds)
end

function split_delta_rows(cell_rows, threshold_rows_all, split_offsets, thresholds)
    SplitGrid.split_delta_rows(cell_rows, threshold_rows_all, split_offsets,
        thresholds)
end

function mcmc_warning_rows(model_rows)
    [row for row in model_rows
     if row.model in MCMC_MODEL_NAMES && row.sampler_flag !== :ok]
end

function sampler_flag_summary_rows(model_rows)
    rows = NamedTuple[]
    flags = sort(unique(Symbol(row.sampler_flag) for row in model_rows
        if row.model in MCMC_MODEL_NAMES); by = string)
    for flag in flags
        push!(rows, (;
            sampler_flag = flag,
            n_rows = count(row -> row.model in MCMC_MODEL_NAMES &&
                Symbol(row.sampler_flag) === flag, model_rows),
            public_claim_allowed = false,
        ))
    end
    return rows
end

function finding_rows(split_deltas, threshold_summary, model_rows)
    risk_changes =
        sum((row.n_threshold_risk_changes for row in split_deltas); init = 0)
    warnings = mcmc_warning_rows(model_rows)
    threshold2 = [row for row in threshold_summary if row.threshold == 2.0]
    threshold2_rate = isempty(threshold2) ? missing :
        only(threshold2).candidate_false_promotion_rate
    return [
        (finding = :sampler_remediation_pilot_recorded,
            severity = :info,
            evidence = string(length(model_rows), " total model score row(s)"),
            implication = :larger_budget_pilot_completed_for_selected_cells,
            public_claim_allowed = false),
        (finding = :sampler_warning_after_remediation,
            severity = isempty(warnings) ? :info : :warning,
            evidence = string(length(warnings),
                " selected MCMC model row(s) still have non-ok sampler flags"),
            implication =
                :warnings_must_be_resolved_or_explained_before_public_thresholds,
            public_claim_allowed = false),
        (finding = :split_stability_after_remediation,
            severity = risk_changes == 0 ? :info : :warning,
            evidence = string(risk_changes,
                " threshold risk change(s) across split offsets"),
            implication =
                :split_stability_should_be_required_before_threshold_policy,
            public_claim_allowed = false),
        (finding = :threshold_2_false_promotion_after_remediation,
            severity = threshold2_rate == 0 ? :info : :warning,
            evidence = string("threshold 2 false-promotion rate = ",
                threshold2_rate),
            implication = :low_threshold_specificity_remains_under_review,
            public_claim_allowed = false),
        (finding = :public_claims_blocked,
            severity = :blocker,
            evidence = "local sampler-remediation pilot only",
            implication =
                :do_not_claim_public_fit_thresholds_model_weights_or_q_revisions,
            public_claim_allowed = false),
    ]
end

function input_artifact_rows(options)
    return [(artifact = :split_controlled_critical_grid,
        path = rel(options.split_grid_json),
        sha256 = file_sha256(options.split_grid_json))]
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
        println(io, "# Uto-Style Sampler Remediation Critical Pilot")
        println(io)
        println(io, "- Generated at: `", artifact.generated_at, "`")
        println(io, "- Local only: `true`")
        println(io, "- Public claims allowed: `false`")
        println(io)
        println(io, "## Interpretation")
        println(io)
        println(io,
            "This report reruns selected critical cells with a larger local MCMC ",
            "budget. The default selection is split-stable cells only; it tests ",
            "whether sampler warnings clear before expanding to split-sensitive ",
            "cells.")
        println(io)
        println(io, "## Findings")
        table(io, ["Finding", "Severity", "Evidence", "Implication"],
            [[row.finding, row.severity, row.evidence, row.implication]
             for row in artifact.finding_rows])
        println(io, "## Selected Cells")
        table(io, ["Scenario", "Axis", "Base Seed", "Previous Risk Changes"],
            [[row.scenario, row.axis, row.base_seed,
                row.previous_n_threshold_risk_changes]
             for row in artifact.selected_cell_rows])
        println(io, "## Split Deltas")
        table(io, ["Scenario", "Base Seed", "Split Offsets", "dCandidateLog",
                "dCand-DeclLog", "dBrier", "dTV", "dCumL1", "Risk Changes"],
            [[row.scenario, row.base_seed,
                string(row.baseline_split_offset, "->",
                    row.comparison_split_offset),
                row.delta_candidate_log_score,
                row.delta_candidate_minus_declared_log_score,
                row.delta_candidate_brier,
                row.delta_candidate_category_total_variation,
                row.delta_candidate_cumulative_l1,
                row.n_threshold_risk_changes]
             for row in artifact.split_delta_rows])
        println(io, "## Sampler Flags")
        table(io, ["Sampler Flag", "Rows"],
            [[row.sampler_flag, row.n_rows]
             for row in artifact.sampler_flag_summary_rows])
        println(io, "## Scenario Cells")
        table(io, ["Scenario", "Base Seed", "Split Offset", "Best",
                "Candidate dLog", "Candidate dBrier", "Candidate dTV",
                "Candidate dCumL1", "Min Heldout"],
            [[row.scenario, row.base_seed, row.split_offset,
                row.observed_best_model,
                row.candidate_delta_log_score_vs_null,
                row.candidate_delta_brier_vs_null,
                row.candidate_delta_category_total_variation_vs_null,
                row.candidate_delta_cumulative_l1_vs_null,
                row.min_heldout_category_count]
             for row in artifact.scenario_cell_rows])
        println(io, "## Boundary")
        println(io)
        println(io,
            "This is local sampler-remediation evidence. Public threshold, ",
            "automatic Q revision, model-weight, and sparse-superiority claims ",
            "remain blocked.")
    end
    return path
end

function build_artifact(options)
    split_grid = read_json(options.split_grid_json)
    cells = selected_cells(split_grid, options.cell_mode, options.max_cells)
    cell_rows = NamedTuple[]
    model_rows = NamedTuple[]
    comparison_rows_all = NamedTuple[]
    category_rows = NamedTuple[]
    cumulative_rows = NamedTuple[]
    for cell in cells, split_offset in options.split_offsets
        result = scenario_cell(options, cell, split_offset)
        push!(cell_rows, result.cell_row)
        append!(model_rows, result.model_rows)
        append!(comparison_rows_all, result.comparison_rows)
        append!(category_rows, result.category_distribution_rows)
        append!(cumulative_rows, result.cumulative_threshold_rows)
    end
    thresholds = threshold_rows(cell_rows, options.thresholds)
    threshold_summary = threshold_summary_rows(thresholds)
    split_deltas =
        split_delta_rows(cell_rows, thresholds, options.split_offsets,
            options.thresholds)
    flag_summary = sampler_flag_summary_rows(model_rows)
    warnings = mcmc_warning_rows(model_rows)
    findings = finding_rows(split_deltas, threshold_summary, model_rows)
    return (;
        schema = OUTPUT_SCHEMA,
        family = :mgmfrm,
        scope = :uto_style_sampler_remediation_critical_pilot,
        status = :local_sampler_remediation_critical_pilot_recorded,
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
        design = (;
            cell_mode = options.cell_mode,
            split_offsets = options.split_offsets,
            thresholds = options.thresholds,
            n_persons = options.n_persons,
            n_items = options.n_items,
            n_raters = options.n_raters,
            heldout_fraction = options.heldout_fraction,
        ),
        fit_controls = (;
            backend = :advancedhmc,
            sampler = :nuts,
            chains = options.chains,
            warmup_per_chain = options.warmup_per_chain,
            draws_per_chain = options.draws_per_chain,
            target_acceptance = options.target_acceptance,
            prior_profile = options.prior_profile,
            progress = options.progress,
        ),
        selected_cell_rows = cells,
        scenario_cell_rows = cell_rows,
        model_score_rows = model_rows,
        comparison_rows = comparison_rows_all,
        category_distribution_rows = category_rows,
        cumulative_threshold_rows = cumulative_rows,
        threshold_rows = thresholds,
        threshold_summary_rows = threshold_summary,
        split_delta_rows = split_deltas,
        sampler_flag_summary_rows = flag_summary,
        finding_rows = findings,
        summary = (;
            passed = all(row.fit_succeeded for row in model_rows
                if row.model in MCMC_MODEL_NAMES),
            n_selected_cells = length(cells),
            n_split_offsets = length(options.split_offsets),
            n_remediation_cells = length(cell_rows),
            n_model_score_rows = length(model_rows),
            n_mcmc_warning_rows = length(warnings),
            n_threshold_risk_changes =
                sum((row.n_threshold_risk_changes for row in split_deltas);
                    init = 0),
            no_public_fit_metric_claim = true,
            no_public_q_revision_claim = true,
            no_automatic_q_revision = true,
            no_public_model_weight_claim = true,
            no_sparse_superiority_claim = true,
            next_gate = isempty(warnings) ?
                :expand_sampler_remediation_to_split_sensitive_cells :
                :diagnose_sampler_warning_surface,
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
    println("selected_cells=", artifact.summary.n_selected_cells,
        " remediation_cells=", artifact.summary.n_remediation_cells,
        " mcmc_warnings=", artifact.summary.n_mcmc_warning_rows,
        " risk_changes=", artifact.summary.n_threshold_risk_changes,
        " next_gate=", artifact.summary.next_gate)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
