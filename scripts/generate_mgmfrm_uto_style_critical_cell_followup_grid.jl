#!/usr/bin/env julia

using Dates
using JSON3
using SHA
using Statistics
using TOML

module ReplicatedQCategory
include(joinpath(@__DIR__,
    "generate_mgmfrm_uto_style_replicated_q_misspecification_category_bridge.jl"))
end

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_MULTIAXIS_JSON =
    joinpath(ROOT, "artifacts", "uto_style_multiaxis_instability_diagnosis",
        "uto_style_multiaxis_instability_diagnosis.json")
const DEFAULT_OUTPUT_JSON =
    joinpath(ROOT, "artifacts", "uto_style_critical_cell_followup_grid",
        "uto_style_critical_cell_followup_grid.json")
const DEFAULT_OUTPUT_MD =
    joinpath(ROOT, "artifacts", "uto_style_critical_cell_followup_grid",
        "uto_style_critical_cell_followup_grid.md")

include(joinpath(@__DIR__, "local_json.jl"))

const OUTPUT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_uto_style_critical_cell_followup_grid.v1"
const DEFAULT_N_PERSONS_GRID = [6, 10, 16]

function usage()
    return """
    Build a critical-cell follow-up grid for the local MGMFRM instability
    diagnosis.

    This script reads the multi-axis diagnosis, reconstructs the base seeds for
    budget-sensitive cells, and creates a sampler/split/sample-size follow-up
    grid. It also screens heldout category support under larger n-persons
    settings. It does not run MCMC and does not make public fit-threshold,
    model-weight, or Q-revision claims.

    Usage:
      julia --project=. scripts/generate_mgmfrm_uto_style_critical_cell_followup_grid.jl [options]

    Options:
      --multiaxis-json PATH     Multi-axis diagnosis artifact.
      --output-json PATH        JSON artifact path.
      --output-md PATH          Markdown report path.
      --n-persons-grid LIST     Comma-separated n-persons grid. Default: 6,10,16.
      --heldout-fraction X      Observation holdout fraction. Default: 0.17.
      --n-raters N              Number of raters. Default: 3.
    """
end

function parse_int_list(text::AbstractString)
    values = Int[]
    for part in split(text, ",")
        stripped = strip(part)
        isempty(stripped) && continue
        push!(values, parse(Int, stripped))
    end
    isempty(values) && error("integer list must contain at least one value")
    length(unique(values)) == length(values) ||
        error("integer list values must be unique")
    return sort(values)
end

function parse_args(args)
    multiaxis_json = DEFAULT_MULTIAXIS_JSON
    output_json = DEFAULT_OUTPUT_JSON
    output_md = DEFAULT_OUTPUT_MD
    n_persons_grid = copy(DEFAULT_N_PERSONS_GRID)
    heldout_fraction = 0.17
    n_raters = 3

    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--multiaxis-json"
            index < length(args) || error("--multiaxis-json requires a path")
            multiaxis_json = abspath(args[index + 1])
            index += 2
        elseif arg == "--output-json"
            index < length(args) || error("--output-json requires a path")
            output_json = abspath(args[index + 1])
            index += 2
        elseif arg == "--output-md"
            index < length(args) || error("--output-md requires a path")
            output_md = abspath(args[index + 1])
            index += 2
        elseif arg == "--n-persons-grid"
            index < length(args) ||
                error("--n-persons-grid requires a comma list")
            n_persons_grid = parse_int_list(args[index + 1])
            index += 2
        elseif arg == "--heldout-fraction"
            index < length(args) ||
                error("--heldout-fraction requires a number")
            heldout_fraction = parse(Float64, args[index + 1])
            index += 2
        elseif arg == "--n-raters"
            index < length(args) || error("--n-raters requires an integer")
            n_raters = parse(Int, args[index + 1])
            index += 2
        elseif arg in ("-h", "--help")
            println(usage())
            exit(0)
        else
            error("unknown argument: $arg")
        end
    end

    isfile(multiaxis_json) ||
        error("multi-axis diagnosis artifact is missing: $multiaxis_json")
    all(>=(6), n_persons_grid) ||
        error("--n-persons-grid values must be at least 6")
    n_raters >= 3 || error("--n-raters must be at least 3")
    0 < heldout_fraction < 0.5 ||
        error("--heldout-fraction must be in (0, 0.5)")
    return (;
        multiaxis_json,
        output_json,
        output_md,
        n_persons_grid,
        heldout_fraction,
        n_raters,
    )
end

project_version() =
    String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])
file_sha256(path::AbstractString) = bytes2hex(open(sha256, path))
rel(path::AbstractString) = relpath(path, ROOT)
round4(value) = round(Float64(value); digits = 4)

function read_json(path::AbstractString)
    return JSON3.read(read(path, String))
end

function scenario_by_name(name)
    ReplicatedQCategory.scenario_by_name(Symbol(string(name)))
end

function base_seed_for_actual_seed(actual_seed::Integer, scenario)
    return Int(actual_seed) - 2 * Int(scenario.seed_offset)
end

function critical_cell_rows(multiaxis)
    rows = NamedTuple[]
    for row in multiaxis.critical_cell_rows
        scenario = scenario_by_name(row.scenario)
        actual_seed = Int(row.seed)
        base_seed = base_seed_for_actual_seed(actual_seed, scenario)
        push!(rows, (;
            scenario = Symbol(string(row.scenario)),
            axis = Symbol(string(row.axis)),
            actual_seed,
            base_seed,
            scenario_seed_offset = Int(scenario.seed_offset),
            baseline_budget = Symbol(string(row.baseline_budget)),
            comparison_budget = Symbol(string(row.comparison_budget)),
            delta_candidate_log_score = Float64(row.delta_candidate_log_score),
            n_threshold_risk_changes = Int(row.n_threshold_risk_changes),
            changed_threshold_risks =
                [Symbol(string(value)) for value in row.changed_threshold_risks],
            public_claim_allowed = false,
        ))
    end
    return rows
end

function followup_run_rows(critical_rows)
    rows = NamedTuple[]
    for row in critical_rows
        push!(rows, (;
            gate = :sampler_remediation,
            scenario = row.scenario,
            axis = row.axis,
            base_seed = row.base_seed,
            actual_seed = row.actual_seed,
            n_persons = 6,
            chains = 4,
            warmup_per_chain = 64,
            draws_per_chain = 64,
            target_acceptance = 0.85,
            requires_split_seed_control = false,
            priority = :highest,
            rationale =
                :resolve_or_explain_sampler_warning_before_threshold_policy,
            public_claim_allowed = false,
        ))
        push!(rows, (;
            gate = :split_robustness,
            scenario = row.scenario,
            axis = row.axis,
            base_seed = row.base_seed,
            actual_seed = row.actual_seed,
            n_persons = 6,
            chains = 2,
            warmup_per_chain = 32,
            draws_per_chain = 32,
            target_acceptance = 0.8,
            requires_split_seed_control = true,
            priority = :high,
            rationale =
                :repeat_holdout_splits_after_decoupling_generation_and_split_seed,
            public_claim_allowed = false,
        ))
        if row.axis in (:false_add, :q_misspecification_rater_noise)
            push!(rows, (;
                gate = :specificity_scaling,
                scenario = row.scenario,
                axis = row.axis,
                base_seed = row.base_seed,
                actual_seed = row.actual_seed,
                n_persons = 10,
                chains = 2,
                warmup_per_chain = 32,
                draws_per_chain = 32,
                target_acceptance = 0.8,
                requires_split_seed_control = false,
                priority = :high,
                rationale =
                    :check_false_promotion_under_more_persons_before_q_suggestion,
                public_claim_allowed = false,
            ))
        elseif row.axis === :explicit_null
            push!(rows, (;
                gate = :negative_control_scaling,
                scenario = row.scenario,
                axis = row.axis,
                base_seed = row.base_seed,
                actual_seed = row.actual_seed,
                n_persons = 10,
                chains = 2,
                warmup_per_chain = 32,
                draws_per_chain = 32,
                target_acceptance = 0.8,
                requires_split_seed_control = false,
                priority = :high,
                rationale =
                    :check_false_alarm_boundary_under_more_observations,
                public_claim_allowed = false,
            ))
        end
    end
    return rows
end

function score_counts(rows)
    return Dict(score => count(row -> row.score == score, rows)
        for score in ReplicatedQCategory.CATEGORY_LEVELS)
end

function support_screen_row(options, critical_row, n_persons::Int)
    scenario = scenario_by_name(critical_row.scenario)
    base_options = (;
        seed = critical_row.base_seed,
        n_persons,
        n_items = size(ReplicatedQCategory.QMisspec.Q_BASE, 1),
        n_raters = options.n_raters,
        heldout_fraction = options.heldout_fraction,
        chains = 1,
        warmup_per_chain = 0,
        draws_per_chain = 1,
        target_acceptance = 0.8,
        prior_profile = :default,
        progress = false,
    )
    fitopts =
        ReplicatedQCategory.QMisspec.fit_options(base_options, scenario)
    generated =
        ReplicatedQCategory.QMisspec.generate_rows(fitopts, scenario)
    split = ReplicatedQCategory.QMisspec.SmallMCMC.split_rows(
        generated.rows,
        fitopts,
    )
    heldout_rows = generated.rows[split.heldout_indices]
    train_counts = score_counts(split.train_rows)
    heldout_counts = score_counts(heldout_rows)
    train_min = minimum(values(train_counts))
    heldout_min = minimum(values(heldout_counts))
    return (;
        scenario = critical_row.scenario,
        axis = critical_row.axis,
        base_seed = critical_row.base_seed,
        actual_seed =
            critical_row.base_seed + 2 * critical_row.scenario_seed_offset,
        n_persons,
        n_observations = length(generated.rows),
        n_train_observations = length(split.train_rows),
        n_heldout_observations = length(split.heldout_indices),
        split_attempts = split.split_attempts,
        train_count_score_0 = train_counts[0],
        train_count_score_1 = train_counts[1],
        train_count_score_2 = train_counts[2],
        heldout_count_score_0 = heldout_counts[0],
        heldout_count_score_1 = heldout_counts[1],
        heldout_count_score_2 = heldout_counts[2],
        min_train_category_count = train_min,
        min_heldout_category_count = heldout_min,
        heldout_all_categories_present = heldout_min > 0,
        support_status = heldout_min >= 3 ? :adequate_for_category_screen :
            heldout_min >= 1 ? :thin_but_present : :missing_category,
        public_claim_allowed = false,
    )
end

function support_screen_rows(options, critical_rows)
    rows = NamedTuple[]
    for critical in critical_rows, n_persons in options.n_persons_grid
        push!(rows, support_screen_row(options, critical, n_persons))
    end
    return rows
end

function recommendation_rows(support_rows, followup_rows)
    thin_baseline = count(row -> row.n_persons == 6 &&
        row.support_status !== :adequate_for_category_screen, support_rows)
    sampler_jobs = count(row -> row.gate === :sampler_remediation,
        followup_rows)
    split_jobs = count(row -> row.gate === :split_robustness,
        followup_rows)
    return [
        (recommendation = :run_sampler_remediation_first,
            priority = :highest,
            evidence = string(sampler_jobs, " critical sampler job(s)"),
            implication =
                :threshold_policy_stays_blocked_until_warning_pattern_is_resolved,
            public_claim_allowed = false),
        (recommendation = :add_split_seed_control,
            priority = :high,
            evidence = string(split_jobs,
                " split-robustness job(s) require split seed decoupling"),
            implication =
                :generation_seed_and_holdout_split_should_be_separate_controls,
            public_claim_allowed = false),
        (recommendation = :increase_category_support,
            priority = thin_baseline == 0 ? :medium : :high,
            evidence = string(thin_baseline,
                " baseline critical cell(s) have thin heldout category support"),
            implication =
                :sample_size_scaling_should_precede_public_category_thresholds,
            public_claim_allowed = false),
    ]
end

function input_artifact_rows(options)
    return [(artifact = :multiaxis_instability_diagnosis,
        path = rel(options.multiaxis_json),
        sha256 = file_sha256(options.multiaxis_json))]
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
        println(io, "# Uto-Style Critical Cell Follow-Up Grid")
        println(io)
        println(io, "- Generated at: `", artifact.generated_at, "`")
        println(io, "- Local only: `true`")
        println(io, "- Public claims allowed: `false`")
        println(io)
        println(io, "## Interpretation")
        println(io)
        println(io,
            "This report turns the multi-axis diagnosis into a targeted follow-up ",
            "grid. It reconstructs the base seed for each budget-sensitive cell, ",
            "separates sampler, split, and sample-size probes, and screens heldout ",
            "category support before running another large MCMC batch.")
        println(io)
        println(io, "## Critical Cells")
        table(io, ["Scenario", "Axis", "Base Seed", "Actual Seed",
                "Risk Changes", "Changed Risks"],
            [[row.scenario, row.axis, row.base_seed, row.actual_seed,
                row.n_threshold_risk_changes,
                join(string.(row.changed_threshold_risks), ", ")]
             for row in artifact.critical_cell_rows])
        println(io, "## Follow-Up Runs")
        table(io, ["Gate", "Scenario", "Base Seed", "n", "Chains",
                "Warmup", "Draws", "Split Seed Control", "Priority"],
            [[row.gate, row.scenario, row.base_seed, row.n_persons,
                row.chains, row.warmup_per_chain, row.draws_per_chain,
                row.requires_split_seed_control, row.priority]
             for row in artifact.followup_run_rows])
        println(io, "## Category Support Screen")
        table(io, ["Scenario", "Base Seed", "n", "Heldout", "Heldout 0",
                "Heldout 1", "Heldout 2", "Min Heldout", "Status"],
            [[row.scenario, row.base_seed, row.n_persons,
                row.n_heldout_observations, row.heldout_count_score_0,
                row.heldout_count_score_1, row.heldout_count_score_2,
                row.min_heldout_category_count, row.support_status]
             for row in artifact.support_screen_rows])
        println(io, "## Recommendations")
        table(io, ["Recommendation", "Priority", "Evidence", "Implication"],
            [[row.recommendation, row.priority, row.evidence, row.implication]
             for row in artifact.recommendation_rows])
        println(io, "## Boundary")
        println(io)
        println(io,
            "This is a follow-up design artifact, not MCMC evidence. It keeps ",
            "public fit thresholds, Q revision, model weights, and sparse ",
            "superiority claims blocked.")
    end
    return path
end

function build_artifact(options)
    multiaxis = read_json(options.multiaxis_json)
    critical = critical_cell_rows(multiaxis)
    followups = followup_run_rows(critical)
    support = support_screen_rows(options, critical)
    recommendations = recommendation_rows(support, followups)
    thin_baseline = count(row -> row.n_persons == minimum(options.n_persons_grid) &&
        row.support_status !== :adequate_for_category_screen, support)
    return (;
        schema = OUTPUT_SCHEMA,
        family = :mgmfrm,
        scope = :uto_style_critical_cell_followup_grid,
        status = :local_critical_cell_followup_grid_recorded,
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
            n_persons_grid = options.n_persons_grid,
            n_raters = options.n_raters,
            heldout_fraction = options.heldout_fraction,
        ),
        critical_cell_rows = critical,
        followup_run_rows = followups,
        support_screen_rows = support,
        recommendation_rows = recommendations,
        summary = (;
            passed = true,
            n_critical_cells = length(critical),
            n_followup_run_rows = length(followups),
            n_support_screen_rows = length(support),
            n_sampler_remediation_jobs =
                count(row -> row.gate === :sampler_remediation, followups),
            n_split_robustness_jobs =
                count(row -> row.gate === :split_robustness, followups),
            n_jobs_requiring_split_seed_control =
                count(row -> row.requires_split_seed_control, followups),
            n_thin_baseline_support_cells = thin_baseline,
            no_public_fit_metric_claim = true,
            no_public_q_revision_claim = true,
            no_automatic_q_revision = true,
            no_public_model_weight_claim = true,
            no_sparse_superiority_claim = true,
            next_gate = :implement_split_seed_control_then_run_sampler_grid,
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
    println("critical_cells=", artifact.summary.n_critical_cells,
        " followup_rows=", artifact.summary.n_followup_run_rows,
        " split_seed_jobs=",
        artifact.summary.n_jobs_requiring_split_seed_control,
        " next_gate=", artifact.summary.next_gate)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
