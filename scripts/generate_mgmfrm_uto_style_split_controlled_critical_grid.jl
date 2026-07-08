#!/usr/bin/env julia

using Dates
using JSON3
using Random
using SHA
using Statistics
using TOML

module ReplicatedQCategory
include(joinpath(@__DIR__,
    "generate_mgmfrm_uto_style_replicated_q_misspecification_category_bridge.jl"))
end

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_FOLLOWUP_JSON =
    joinpath(ROOT, "artifacts", "uto_style_critical_cell_followup_grid",
        "uto_style_critical_cell_followup_grid.json")
const DEFAULT_OUTPUT_JSON =
    joinpath(ROOT, "artifacts", "uto_style_split_controlled_critical_grid",
        "uto_style_split_controlled_critical_grid.json")
const DEFAULT_OUTPUT_MD =
    joinpath(ROOT, "artifacts", "uto_style_split_controlled_critical_grid",
        "uto_style_split_controlled_critical_grid.md")

include(joinpath(@__DIR__, "local_json.jl"))

const OUTPUT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_uto_style_split_controlled_critical_grid.v1"
const DEFAULT_SPLIT_OFFSETS = [17, 101]
const DEFAULT_THRESHOLDS = ReplicatedQCategory.DEFAULT_THRESHOLDS
const MCMC_MODEL_NAMES = ReplicatedQCategory.MCMC_MODEL_NAMES

function usage()
    return """
    Run a split-seed controlled pilot on the critical MGMFRM cells.

    Generation seeds are kept fixed at the base seeds reconstructed by the
    critical-cell follow-up grid, while holdout split seeds are controlled as
    base_seed + split_offset. This isolates split sensitivity from generation
    sensitivity. The default is still a local diagnostic and does not make
    public fit-threshold, model-weight, or Q-revision claims.

    Usage:
      julia --project=. scripts/generate_mgmfrm_uto_style_split_controlled_critical_grid.jl [options]

    Options:
      --followup-json PATH      Critical-cell follow-up grid artifact.
      --output-json PATH        JSON artifact path.
      --output-md PATH          Markdown report path.
      --split-offsets LIST      Comma-separated split offsets. Default: 17,101.
      --thresholds LIST         Comma-separated dLogScore thresholds. Default: 0,2,4,8.
      --max-critical-cells N    Limit critical cells for smoke runs. Default: all.
      --n-persons N             Number of persons. Default: 6.
      --n-raters N              Number of raters. Default: 3.
      --heldout-fraction X      Observation holdout fraction. Default: 0.17.
      --chains N                MCMC chains. Default: 2.
      --warmup-per-chain N      Warmup iterations per chain. Default: 32.
      --draws-per-chain N       Posterior draws per chain. Default: 32.
      --target-acceptance X     NUTS target acceptance. Default: 0.8.
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
    followup_json = DEFAULT_FOLLOWUP_JSON
    output_json = DEFAULT_OUTPUT_JSON
    output_md = DEFAULT_OUTPUT_MD
    split_offsets = copy(DEFAULT_SPLIT_OFFSETS)
    thresholds = copy(DEFAULT_THRESHOLDS)
    max_critical_cells = 0
    n_persons = 6
    n_raters = 3
    heldout_fraction = 0.17
    chains = 2
    warmup_per_chain = 32
    draws_per_chain = 32
    target_acceptance = 0.8
    prior_profile = :default
    progress = false

    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--followup-json"
            index < length(args) || error("--followup-json requires a path")
            followup_json = abspath(args[index + 1])
            index += 2
        elseif arg == "--output-json"
            index < length(args) || error("--output-json requires a path")
            output_json = abspath(args[index + 1])
            index += 2
        elseif arg == "--output-md"
            index < length(args) || error("--output-md requires a path")
            output_md = abspath(args[index + 1])
            index += 2
        elseif arg == "--split-offsets"
            index < length(args) || error("--split-offsets requires a list")
            split_offsets = parse_int_list(args[index + 1], "--split-offsets")
            index += 2
        elseif arg == "--thresholds"
            index < length(args) || error("--thresholds requires a list")
            thresholds = parse_thresholds(args[index + 1])
            index += 2
        elseif arg == "--max-critical-cells"
            index < length(args) ||
                error("--max-critical-cells requires an integer")
            max_critical_cells = parse(Int, args[index + 1])
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

    isfile(followup_json) || error("follow-up artifact not found: $followup_json")
    max_critical_cells >= 0 || error("--max-critical-cells must be non-negative")
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
        followup_json,
        output_json,
        output_md,
        split_offsets,
        thresholds,
        max_critical_cells,
        n_persons,
        n_items = size(ReplicatedQCategory.QMisspec.Q_BASE, 1),
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

function read_json(path::AbstractString)
    return JSON3.read(read(path, String))
end

function scenario_by_name(name)
    ReplicatedQCategory.scenario_by_name(Symbol(string(name)))
end

function critical_rows(followup, max_critical_cells::Int)
    rows = [(;
        scenario = Symbol(string(row.scenario)),
        axis = Symbol(string(row.axis)),
        base_seed = Int(row.base_seed),
        actual_seed = Int(row.actual_seed),
        n_threshold_risk_changes = Int(row.n_threshold_risk_changes),
        changed_threshold_risks =
            [Symbol(string(value)) for value in row.changed_threshold_risks],
    ) for row in followup.critical_cell_rows]
    max_critical_cells == 0 && return rows
    return rows[1:min(max_critical_cells, length(rows))]
end

function controlled_split_rows(rows, options, split_seed::Int)
    rng = MersenneTwister(split_seed)
    n = length(rows)
    n_heldout = max(1, round(Int, options.heldout_fraction * n))
    for attempt in 1:200
        indices = shuffle(rng, collect(1:n))
        heldout = sort(indices[1:n_heldout])
        heldout_set = Set(heldout)
        train_rows = [rows[index] for index in 1:n if !(index in heldout_set)]
        ReplicatedQCategory.QMisspec.SmallMCMC.valid_split(
            train_rows,
            options,
        ) && return (;
            train_rows,
            heldout_indices = heldout,
            split_attempts = attempt,
            split_seed,
        )
    end
    error("could not find a training split retaining all facets/categories")
end

function score_counts(rows)
    return Dict(score => count(row -> row.score == score, rows)
        for score in ReplicatedQCategory.CATEGORY_LEVELS)
end

function scenario_cell_with_split(options, critical, split_offset::Int)
    scenario = scenario_by_name(critical.scenario)
    base_options = merge(options, (; seed = critical.base_seed))
    fitopts = ReplicatedQCategory.QMisspec.fit_options(base_options, scenario)
    generated =
        ReplicatedQCategory.QMisspec.generate_rows(fitopts, scenario)
    split_seed = critical.base_seed + split_offset
    split = controlled_split_rows(generated.rows, fitopts, split_seed)
    scores =
        ReplicatedQCategory.observed_scores(generated.rows,
            split.heldout_indices)
    scenario_seed = fitopts.seed + scenario.seed_offset
    context = (;
        seed = scenario_seed,
        base_seed = critical.base_seed,
        split_seed,
        split_offset,
        prior_profile = fitopts.prior_profile,
        scenario = scenario.name,
        axis = scenario.axis,
        role = scenario.role,
    )
    sets = ReplicatedQCategory.model_probability_sets(
        split.train_rows,
        generated.rows,
        split.heldout_indices,
        generated,
        scenario,
        fitopts,
    )
    model_rows = NamedTuple[]
    category_rows = NamedTuple[]
    cumulative_rows = NamedTuple[]
    for set in sets
        if set.probabilities === nothing
            push!(model_rows,
                ReplicatedQCategory.failed_model_summary_row(
                    context,
                    set.metadata,
                    scores,
                ))
            continue
        end
        push!(model_rows, ReplicatedQCategory.model_summary_row(
            context,
            set.model,
            set.probabilities,
            scores,
            set.metadata,
        ))
        append!(category_rows, ReplicatedQCategory.category_distribution_rows(
            context,
            set.model,
            set.probabilities,
            scores,
        ))
        append!(cumulative_rows, ReplicatedQCategory.cumulative_threshold_rows(
            context,
            set.model,
            set.probabilities,
            scores,
        ))
    end
    ranked = ReplicatedQCategory.ranked_summary_rows(model_rows)
    comparisons = [merge(row, context, (; public_claim_allowed = false))
        for row in ReplicatedQCategory.comparison_rows(ranked)]
    cell = ReplicatedQCategory.scenario_cell_row(
        fitopts,
        scenario,
        split,
        ranked,
        comparisons,
    )
    heldout_rows = generated.rows[split.heldout_indices]
    heldout_counts = score_counts(heldout_rows)
    train_counts = score_counts(split.train_rows)
    return (;
        cell_row = merge(cell, (;
            split_seed,
            split_offset,
            base_seed = critical.base_seed,
            original_actual_seed = critical.actual_seed,
            heldout_count_score_0 = heldout_counts[0],
            heldout_count_score_1 = heldout_counts[1],
            heldout_count_score_2 = heldout_counts[2],
            min_heldout_category_count = minimum(values(heldout_counts)),
            train_count_score_0 = train_counts[0],
            train_count_score_1 = train_counts[1],
            train_count_score_2 = train_counts[2],
            min_train_category_count = minimum(values(train_counts)),
            public_claim_allowed = false,
        )),
        model_rows = ranked,
        comparison_rows = comparisons,
        category_distribution_rows = category_rows,
        cumulative_threshold_rows = cumulative_rows,
    )
end

function risk_label(row, threshold)
    declared_pass = row.declared_delta_log_score_vs_null >= threshold
    candidate_pass = row.candidate_delta_log_score_vs_null >= threshold
    scalar_pass = row.scalar_delta_log_score_vs_null >= threshold
    candidate_aligned = row.candidate_category_calibration_aligned_vs_null
    declared_aligned = row.declared_category_calibration_aligned_vs_null
    if row.axis in (:explicit_null, :false_add, :q_misspecification_rater_noise)
        candidate_pass && candidate_aligned &&
            return :candidate_false_promotion_risk
        candidate_pass && return :candidate_false_promotion_with_category_caveat
        declared_pass && declared_aligned &&
            return :declared_model_false_promotion_risk
        declared_pass && return :declared_model_false_promotion_with_category_caveat
        scalar_pass && return :scalar_reference_screening_pass
        return :specificity_not_failed
    elseif row.axis === :false_drop
        candidate_pass || return :candidate_false_negative_risk
        candidate_aligned ||
            return :candidate_power_with_category_caveat
        row.candidate_minus_declared_log_score <= 0 &&
            return :candidate_does_not_improve_over_declared
        return :candidate_power_observed
    elseif row.axis === :weak_dimension
        declared_pass || return :weak_dimension_false_negative_risk
        declared_aligned || return :weak_dimension_with_category_caveat
        return :weak_dimension_screening_pass
    end
    return :manual_review_required
end

function threshold_rows(cell_rows, thresholds)
    rows = NamedTuple[]
    for row in cell_rows, threshold in thresholds
        candidate_pass = row.candidate_delta_log_score_vs_null >= threshold
        declared_pass = row.declared_delta_log_score_vs_null >= threshold
        push!(rows, (;
            seed = row.seed,
            base_seed = row.base_seed,
            split_seed = row.split_seed,
            split_offset = row.split_offset,
            prior_profile = row.prior_profile,
            scenario = row.scenario,
            axis = row.axis,
            threshold = round3(threshold),
            declared_passed = declared_pass,
            candidate_passed = candidate_pass,
            rotated_wrong_passed =
                row.rotated_wrong_delta_log_score_vs_null >= threshold,
            scalar_passed = row.scalar_delta_log_score_vs_null >= threshold,
            candidate_category_calibration_aligned =
                row.candidate_category_calibration_aligned_vs_null,
            candidate_predictive_category_caveat =
                candidate_pass &&
                !row.candidate_category_calibration_aligned_vs_null,
            candidate_minus_declared_log_score =
                row.candidate_minus_declared_log_score,
            risk_interpretation = risk_label(row, threshold),
            public_claim_allowed = false,
        ))
    end
    return rows
end

function threshold_summary_rows(thresholds)
    rows = NamedTuple[]
    for threshold in sort(unique(row.threshold for row in thresholds))
        group = [row for row in thresholds if row.threshold == threshold]
        n = length(group)
        false_promotion = count(row -> row.risk_interpretation in
            (:candidate_false_promotion_risk,
             :candidate_false_promotion_with_category_caveat), group)
        false_negative = count(row -> row.risk_interpretation in
            (:candidate_false_negative_risk,
             :weak_dimension_false_negative_risk), group)
        caveat =
            count(row -> row.candidate_predictive_category_caveat, group)
        push!(rows, (;
            threshold,
            n_cells = n,
            n_candidate_passed = count(row -> row.candidate_passed, group),
            n_candidate_false_promotion_risk = false_promotion,
            candidate_false_promotion_rate = round4(false_promotion / n),
            n_candidate_false_negative_risk = false_negative,
            candidate_false_negative_rate = round4(false_negative / n),
            n_candidate_predictive_category_caveat = caveat,
            candidate_predictive_category_caveat_rate = round4(caveat / n),
            public_claim_allowed = false,
        ))
    end
    return rows
end

function cell_by_key(rows; base_seed, scenario, split_offset)
    matches = [row for row in rows
        if row.base_seed == base_seed && row.scenario === scenario &&
           row.split_offset == split_offset]
    isempty(matches) && return nothing
    return only(matches)
end

function threshold_by_key(rows; base_seed, scenario, split_offset, threshold)
    matches = [row for row in rows
        if row.base_seed == base_seed && row.scenario === scenario &&
           row.split_offset == split_offset && row.threshold == threshold]
    isempty(matches) && return nothing
    return only(matches)
end

function split_delta_rows(cell_rows, threshold_rows_all, split_offsets, thresholds)
    length(split_offsets) < 2 && return NamedTuple[]
    baseline_offset = first(split_offsets)
    comparison_offsets = split_offsets[2:end]
    keys = unique((row.base_seed, row.scenario, row.axis) for row in cell_rows
        if row.split_offset == baseline_offset)
    rows = NamedTuple[]
    for split_offset in comparison_offsets, key in keys
        base_seed, scenario, axis = key
        base = cell_by_key(cell_rows; base_seed, scenario,
            split_offset = baseline_offset)
        next = cell_by_key(cell_rows; base_seed, scenario, split_offset)
        base === nothing && continue
        next === nothing && continue
        risk_changes = Symbol[]
        for threshold in thresholds
            base_t = threshold_by_key(threshold_rows_all; base_seed, scenario,
                split_offset = baseline_offset, threshold = round3(threshold))
            next_t = threshold_by_key(threshold_rows_all; base_seed, scenario,
                split_offset, threshold = round3(threshold))
            base_t === nothing && continue
            next_t === nothing && continue
            changed = base_t.candidate_passed != next_t.candidate_passed ||
                      base_t.risk_interpretation !== next_t.risk_interpretation
            changed && push!(risk_changes,
                Symbol(string("t", threshold, "_", base_t.risk_interpretation,
                    "_to_", next_t.risk_interpretation)))
        end
        push!(rows, (;
            base_seed,
            scenario,
            axis,
            baseline_split_offset = baseline_offset,
            comparison_split_offset = split_offset,
            baseline_split_seed = base.split_seed,
            comparison_split_seed = next.split_seed,
            delta_candidate_log_score =
                round3(next.candidate_delta_log_score_vs_null -
                       base.candidate_delta_log_score_vs_null),
            delta_candidate_minus_declared_log_score =
                round3(next.candidate_minus_declared_log_score -
                       base.candidate_minus_declared_log_score),
            delta_candidate_brier =
                round4(next.candidate_delta_brier_vs_null -
                       base.candidate_delta_brier_vs_null),
            delta_candidate_category_total_variation =
                round4(next.candidate_delta_category_total_variation_vs_null -
                       base.candidate_delta_category_total_variation_vs_null),
            delta_candidate_cumulative_l1 =
                round4(next.candidate_delta_cumulative_l1_vs_null -
                       base.candidate_delta_cumulative_l1_vs_null),
            n_threshold_risk_changes = length(risk_changes),
            changed_threshold_risks = risk_changes,
            public_claim_allowed = false,
        ))
    end
    return rows
end

function mcmc_warning_rows(model_rows)
    [row for row in model_rows
     if row.model in MCMC_MODEL_NAMES && row.sampler_flag !== :ok]
end

function finding_rows(split_delta_rows, threshold_summary, model_rows)
    risk_changes =
        sum((row.n_threshold_risk_changes for row in split_delta_rows);
            init = 0)
    warnings = mcmc_warning_rows(model_rows)
    threshold2 = [row for row in threshold_summary if row.threshold == 2.0]
    threshold4 = [row for row in threshold_summary if row.threshold == 4.0]
    threshold2_rate = isempty(threshold2) ? missing :
        only(threshold2).candidate_false_promotion_rate
    threshold4_rate = isempty(threshold4) ? missing :
        only(threshold4).candidate_false_negative_rate
    return [
        (finding = :split_controlled_critical_grid_recorded,
            severity = :info,
            evidence = string(length(split_delta_rows),
                " split comparison row(s)"),
            implication = :generation_and_holdout_split_are_now_decoupled,
            public_claim_allowed = false),
        (finding = :split_sensitivity_screen,
            severity = risk_changes == 0 ? :info : :warning,
            evidence = string(risk_changes,
                " threshold risk change(s) across split offsets"),
            implication =
                :split_variability_must_be_resolved_before_threshold_policy,
            public_claim_allowed = false),
        (finding = :threshold_2_false_promotion_screen,
            severity = threshold2_rate == 0 ? :info : :warning,
            evidence = string("threshold 2 false-promotion rate = ",
                threshold2_rate),
            implication = :low_threshold_specificity_remains_under_review,
            public_claim_allowed = false),
        (finding = :threshold_4_false_negative_screen,
            severity = threshold4_rate == 0 ? :info : :warning,
            evidence = string("threshold 4 false-negative rate = ",
                threshold4_rate),
            implication = :strict_threshold_power_remains_under_review,
            public_claim_allowed = false),
        (finding = :sampler_warning_screen,
            severity = isempty(warnings) ? :info : :warning,
            evidence = string(length(warnings),
                " MCMC model row(s) have non-ok sampler flags"),
            implication = :sampler_remediation_still_required,
            public_claim_allowed = false),
        (finding = :public_claims_blocked,
            severity = :blocker,
            evidence = "local split-controlled critical-cell pilot only",
            implication =
                :do_not_claim_public_fit_thresholds_model_weights_or_q_revisions,
            public_claim_allowed = false),
    ]
end

function input_artifact_rows(options)
    return [(artifact = :critical_cell_followup_grid,
        path = rel(options.followup_json),
        sha256 = file_sha256(options.followup_json))]
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
        println(io, "# Uto-Style Split-Controlled Critical Grid")
        println(io)
        println(io, "- Generated at: `", artifact.generated_at, "`")
        println(io, "- Local only: `true`")
        println(io, "- Public claims allowed: `false`")
        println(io)
        println(io, "## Interpretation")
        println(io)
        println(io,
            "This report reruns only the budget-sensitive critical cells while ",
            "decoupling generation seeds from holdout split seeds. It is a ",
            "split-control pilot, not a publication-grade sampler remediation.")
        println(io)
        println(io, "## Findings")
        table(io, ["Finding", "Severity", "Evidence", "Implication"],
            [[row.finding, row.severity, row.evidence, row.implication]
             for row in artifact.finding_rows])
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
        println(io, "## Threshold Summary")
        table(io, ["Threshold", "Cells", "Candidate Passed",
                "False Promotion Rate", "False Negative Rate",
                "Category Caveat Rate"],
            [Any[row.threshold, row.n_cells, row.n_candidate_passed,
                row.candidate_false_promotion_rate,
                row.candidate_false_negative_rate,
                row.candidate_predictive_category_caveat_rate]
             for row in artifact.threshold_summary_rows])
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
            "This is local split-control evidence. Public threshold, automatic Q ",
            "revision, model-weight, and sparse-superiority claims remain blocked.")
    end
    return path
end

function build_artifact(options)
    followup = read_json(options.followup_json)
    critical = critical_rows(followup, options.max_critical_cells)
    cell_rows = NamedTuple[]
    model_rows = NamedTuple[]
    comparison_rows_all = NamedTuple[]
    category_rows = NamedTuple[]
    cumulative_rows = NamedTuple[]
    for critical_row in critical, split_offset in options.split_offsets
        cell = scenario_cell_with_split(options, critical_row, split_offset)
        push!(cell_rows, cell.cell_row)
        append!(model_rows, cell.model_rows)
        append!(comparison_rows_all, cell.comparison_rows)
        append!(category_rows, cell.category_distribution_rows)
        append!(cumulative_rows, cell.cumulative_threshold_rows)
    end
    thresholds = threshold_rows(cell_rows, options.thresholds)
    threshold_summary = threshold_summary_rows(thresholds)
    split_deltas =
        split_delta_rows(cell_rows, thresholds, options.split_offsets,
            options.thresholds)
    findings = finding_rows(split_deltas, threshold_summary, model_rows)
    warnings = mcmc_warning_rows(model_rows)
    return (;
        schema = OUTPUT_SCHEMA,
        family = :mgmfrm,
        scope = :uto_style_split_controlled_critical_grid,
        status = :local_split_controlled_critical_grid_recorded,
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
            split_seed_rule = :base_seed_plus_split_offset,
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
        critical_cell_rows = critical,
        scenario_cell_rows = cell_rows,
        model_score_rows = model_rows,
        comparison_rows = comparison_rows_all,
        category_distribution_rows = category_rows,
        cumulative_threshold_rows = cumulative_rows,
        threshold_rows = thresholds,
        threshold_summary_rows = threshold_summary,
        split_delta_rows = split_deltas,
        finding_rows = findings,
        summary = (;
            passed = all(row.fit_succeeded for row in model_rows
                if row.model in MCMC_MODEL_NAMES),
            n_critical_cells = length(critical),
            n_split_offsets = length(options.split_offsets),
            n_split_controlled_cells = length(cell_rows),
            n_model_score_rows = length(model_rows),
            n_threshold_rows = length(thresholds),
            n_split_delta_rows = length(split_deltas),
            n_threshold_risk_changes =
                sum((row.n_threshold_risk_changes for row in split_deltas);
                    init = 0),
            n_mcmc_warning_rows = length(warnings),
            no_public_fit_metric_claim = true,
            no_public_q_revision_claim = true,
            no_automatic_q_revision = true,
            no_public_model_weight_claim = true,
            no_sparse_superiority_claim = true,
            next_gate = :run_sampler_remediation_on_split_stable_cells,
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
    println("split_cells=", artifact.summary.n_split_controlled_cells,
        " risk_changes=", artifact.summary.n_threshold_risk_changes,
        " mcmc_warnings=", artifact.summary.n_mcmc_warning_rows,
        " next_gate=", artifact.summary.next_gate)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
