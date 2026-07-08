#!/usr/bin/env julia

using Dates
using SHA
using Statistics
using TOML

module ReplicatedQCategory
include(joinpath(@__DIR__,
    "generate_mgmfrm_uto_style_replicated_q_misspecification_category_bridge.jl"))
end

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_PREVIOUS_JSON =
    joinpath(ROOT, "artifacts",
        "uto_style_replicated_q_misspecification_category_bridge",
        "uto_style_replicated_q_misspecification_category_bridge.json")
const DEFAULT_OUTPUT_JSON =
    joinpath(ROOT, "artifacts", "uto_style_q_category_budget_stability",
        "uto_style_q_category_budget_stability.json")
const DEFAULT_OUTPUT_MD =
    joinpath(ROOT, "artifacts", "uto_style_q_category_budget_stability",
        "uto_style_q_category_budget_stability.md")

include(joinpath(@__DIR__, "local_json.jl"))

const OUTPUT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_uto_style_q_category_budget_stability.v1"
const DEFAULT_BUDGETS = [:current_16_16, :increased_32_32]
const MCMC_MODEL_NAMES = ReplicatedQCategory.MCMC_MODEL_NAMES

function usage()
    return """
    Check whether replicated Q/category threshold calls are stable under larger
    local MCMC budgets.

    The default reruns the replicated Q-misspecification/category bridge over
    two budget profiles: current_16_16 and increased_32_32. It compares
    candidate dLogScore, Brier, category total variation, cumulative-threshold
    L1, threshold risk labels, and sampler-warning counts. Public threshold,
    model-weight, and Q-revision claims remain blocked.

    Usage:
      julia --project=. scripts/generate_mgmfrm_uto_style_q_category_budget_stability.jl [options]

    Options:
      --output-json PATH       JSON artifact path.
      --output-md PATH         Markdown report path.
      --previous-json PATH     Replicated Q/category bridge artifact path.
      --budgets LIST           Budget profiles. Default: current_16_16,increased_32_32.
                               Available: current_16_16, warmup_32_draws_16,
                               warmup_16_draws_32, increased_32_32.
      --scenarios LIST         Comma-separated scenario names.
      --seeds LIST             Comma-separated base seeds. Default: 20260707,20260717.
      --thresholds LIST        Comma-separated dLogScore thresholds. Default: 0,2,4,8.
      --n-persons N            Number of persons. Default: 6.
      --n-raters N             Number of raters. Default: 3.
      --heldout-fraction X     Observation holdout fraction. Default: 0.17.
      --target-acceptance X    NUTS target acceptance. Default: 0.8.
      --prior-profile NAME     Internal source prior profile: default, tight, or diffuse.
                               Default: default.
      --progress               Show sampler progress.
    """
end

function parse_symbol_list(text::AbstractString)
    values = Symbol[]
    for part in split(text, ",")
        stripped = strip(part)
        isempty(stripped) && continue
        push!(values, Symbol(stripped))
    end
    isempty(values) && error("list must contain at least one value")
    length(unique(values)) == length(values) || error("list values must be unique")
    return values
end

function parse_seed_list(text::AbstractString)
    values = Int[]
    for part in split(text, ",")
        stripped = strip(part)
        isempty(stripped) && continue
        push!(values, parse(Int, stripped))
    end
    isempty(values) && error("--seeds must contain at least one value")
    length(unique(values)) == length(values) || error("--seeds must be unique")
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
        error("--thresholds must be unique")
    return sort(values)
end

function budget_profile(name::Symbol)
    name === :current_16_16 &&
        return (; budget = name, chains = 2, warmup_per_chain = 16,
            draws_per_chain = 16)
    name === :warmup_32_draws_16 &&
        return (; budget = name, chains = 2, warmup_per_chain = 32,
            draws_per_chain = 16)
    name === :warmup_16_draws_32 &&
        return (; budget = name, chains = 2, warmup_per_chain = 16,
            draws_per_chain = 32)
    name === :increased_32_32 &&
        return (; budget = name, chains = 2, warmup_per_chain = 32,
            draws_per_chain = 32)
    error("unknown budget profile: $name")
end

function parse_args(args)
    output_json = DEFAULT_OUTPUT_JSON
    output_md = DEFAULT_OUTPUT_MD
    previous_json = DEFAULT_PREVIOUS_JSON
    budget_names = copy(DEFAULT_BUDGETS)
    scenario_names =
        [scenario.name for scenario in ReplicatedQCategory.QMisspec.SCENARIO_LIBRARY]
    seeds = copy(ReplicatedQCategory.DEFAULT_SEEDS)
    thresholds = copy(ReplicatedQCategory.DEFAULT_THRESHOLDS)
    n_persons = 6
    n_raters = 3
    heldout_fraction = 0.17
    target_acceptance = 0.8
    prior_profile = :default
    progress = false

    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--output-json"
            index < length(args) || error("--output-json requires a path")
            output_json = abspath(args[index + 1])
            index += 2
        elseif arg == "--output-md"
            index < length(args) || error("--output-md requires a path")
            output_md = abspath(args[index + 1])
            index += 2
        elseif arg == "--previous-json"
            index < length(args) || error("--previous-json requires a path")
            previous_json = abspath(args[index + 1])
            index += 2
        elseif arg == "--budgets"
            index < length(args) || error("--budgets requires a comma list")
            budget_names = parse_symbol_list(args[index + 1])
            index += 2
        elseif arg == "--scenarios"
            index < length(args) || error("--scenarios requires a comma list")
            scenario_names = parse_symbol_list(args[index + 1])
            index += 2
        elseif arg == "--seeds"
            index < length(args) || error("--seeds requires a comma list")
            seeds = parse_seed_list(args[index + 1])
            index += 2
        elseif arg == "--thresholds"
            index < length(args) || error("--thresholds requires a comma list")
            thresholds = parse_thresholds(args[index + 1])
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

    n_persons >= 6 || error("--n-persons must be at least 6")
    n_raters >= 3 || error("--n-raters must be at least 3")
    0 < heldout_fraction < 0.5 ||
        error("--heldout-fraction must be in (0, 0.5)")
    0 < target_acceptance < 1 ||
        error("--target-acceptance must be in (0, 1)")
    prior_profile in (:default, :tight, :diffuse) ||
        error("--prior-profile must be default, tight, or diffuse")
    budgets = [budget_profile(name) for name in budget_names]
    scenarios =
        [ReplicatedQCategory.scenario_by_name(name) for name in scenario_names]
    return (;
        output_json,
        output_md,
        previous_json,
        budgets,
        scenarios,
        seeds,
        thresholds,
        n_persons,
        n_items = size(ReplicatedQCategory.QMisspec.Q_BASE, 1),
        n_raters,
        heldout_fraction,
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

function scenario_budget_options(options, budget)
    return merge(options, (;
        chains = budget.chains,
        warmup_per_chain = budget.warmup_per_chain,
        draws_per_chain = budget.draws_per_chain,
    ))
end

function add_budget(row, budget)
    return merge(row, (;
        budget = budget.budget,
        chains = budget.chains,
        warmup_per_chain = budget.warmup_per_chain,
        draws_per_chain = budget.draws_per_chain,
        public_claim_allowed = false,
    ))
end

function scenario_budget_cell(options, budget, seed::Int, scenario)
    budget_options = scenario_budget_options(options, budget)
    cell = ReplicatedQCategory.scenario_category_cell(
        budget_options,
        seed,
        scenario,
    )
    return (;
        cell_row = add_budget(cell.cell_row, budget),
        model_rows = [add_budget(row, budget) for row in cell.model_rows],
        comparison_rows =
            [add_budget(row, budget) for row in cell.comparison_rows],
        category_distribution_rows =
            [add_budget(row, budget)
             for row in cell.category_distribution_rows],
        cumulative_threshold_rows =
            [add_budget(row, budget)
             for row in cell.cumulative_threshold_rows],
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
            budget = row.budget,
            seed = row.seed,
            base_seed = row.base_seed,
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
            candidate_delta_brier_vs_null =
                row.candidate_delta_brier_vs_null,
            candidate_delta_category_total_variation_vs_null =
                row.candidate_delta_category_total_variation_vs_null,
            candidate_delta_cumulative_l1_vs_null =
                row.candidate_delta_cumulative_l1_vs_null,
            risk_interpretation = risk_label(row, threshold),
            public_claim_allowed = false,
        ))
    end
    return rows
end

function threshold_summary_rows(thresholds)
    rows = NamedTuple[]
    budgets = sort(unique(row.budget for row in thresholds); by = string)
    threshold_values = sort(unique(row.threshold for row in thresholds))
    for budget in budgets, threshold in threshold_values
        group = [row for row in thresholds
            if row.budget === budget && row.threshold == threshold]
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
            budget,
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

function row_by_key(rows; budget, seed, scenario)
    matches = [row for row in rows
        if row.budget === budget && row.seed == seed && row.scenario === scenario]
    isempty(matches) && return nothing
    return only(matches)
end

function threshold_by_key(rows; budget, seed, scenario, threshold)
    matches = [row for row in rows
        if row.budget === budget && row.seed == seed &&
           row.scenario === scenario && row.threshold == threshold]
    isempty(matches) && return nothing
    return only(matches)
end

function budget_delta_rows(cell_rows, threshold_rows_all, budgets, thresholds)
    length(budgets) < 2 && return NamedTuple[]
    baseline = first(budgets).budget
    comparison_budgets = [budget.budget for budget in budgets[2:end]]
    output = NamedTuple[]
    keys = unique((row.seed, row.scenario, row.axis) for row in cell_rows
        if row.budget === baseline)
    for comparison_budget in comparison_budgets, key in keys
        seed, scenario, axis = key
        base = row_by_key(cell_rows; budget = baseline, seed, scenario)
        next = row_by_key(cell_rows; budget = comparison_budget, seed, scenario)
        base === nothing && continue
        next === nothing && continue
        threshold_changes = 0
        risk_changes = Symbol[]
        for threshold in thresholds
            base_t = threshold_by_key(threshold_rows_all; budget = baseline,
                seed, scenario, threshold = round3(threshold))
            next_t = threshold_by_key(threshold_rows_all;
                budget = comparison_budget, seed, scenario,
                threshold = round3(threshold))
            base_t === nothing && continue
            next_t === nothing && continue
            changed = base_t.candidate_passed != next_t.candidate_passed ||
                      base_t.risk_interpretation !== next_t.risk_interpretation
            threshold_changes += changed ? 1 : 0
            changed && push!(risk_changes,
                Symbol(string("t", threshold, "_", base_t.risk_interpretation,
                    "_to_", next_t.risk_interpretation)))
        end
        push!(output, (;
            baseline_budget = baseline,
            comparison_budget,
            seed,
            scenario,
            axis,
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
            baseline_candidate_caveat =
                base.candidate_predictive_category_caveat,
            comparison_candidate_caveat =
                next.candidate_predictive_category_caveat,
            n_threshold_risk_changes = threshold_changes,
            changed_threshold_risks = risk_changes,
            public_claim_allowed = false,
        ))
    end
    return output
end

function sampler_warning_rows(model_rows)
    return [row for row in model_rows
        if row.model in MCMC_MODEL_NAMES && row.sampler_flag !== :ok]
end

function sampler_warning_summary_rows(model_rows)
    rows = NamedTuple[]
    for budget in sort(unique(row.budget for row in model_rows); by = string)
        group = [row for row in model_rows
            if row.budget === budget && row.model in MCMC_MODEL_NAMES]
        warnings = [row for row in group if row.sampler_flag !== :ok]
        push!(rows, (;
            budget,
            n_mcmc_model_rows = length(group),
            n_mcmc_warning_rows = length(warnings),
            mcmc_warning_rate =
                isempty(group) ? NaN : round4(length(warnings) / length(group)),
            n_mcmc_warning = count(row -> row.sampler_flag === :mcmc_warning,
                group),
            n_sampler_warning =
                count(row -> row.sampler_flag === :sampler_warning, group),
            public_claim_allowed = false,
        ))
    end
    return rows
end

function summary_value(rows, budget::Symbol, threshold, field::Symbol)
    matches = [row for row in rows
        if row.budget === budget && row.threshold == threshold]
    isempty(matches) && return missing
    return getproperty(only(matches), field)
end

function warning_summary_value(rows, budget::Symbol, field::Symbol)
    matches = [row for row in rows if row.budget === budget]
    isempty(matches) && return missing
    return getproperty(only(matches), field)
end

function finding_rows(threshold_summary, delta_rows, warning_summary, budgets)
    baseline = first(budgets).budget
    last_budget = last(budgets).budget
    threshold2_false_promotion =
        summary_value(threshold_summary, last_budget, 2.0,
            :candidate_false_promotion_rate)
    threshold4_false_negative =
        summary_value(threshold_summary, last_budget, 4.0,
            :candidate_false_negative_rate)
    baseline_t2 =
        summary_value(threshold_summary, baseline, 2.0,
            :candidate_false_promotion_rate)
    baseline_t4 =
        summary_value(threshold_summary, baseline, 4.0,
            :candidate_false_negative_rate)
    risk_changes =
        sum((row.n_threshold_risk_changes for row in delta_rows); init = 0)
    last_warning = [row for row in warning_summary if row.budget === last_budget]
    last_warning_count = isempty(last_warning) ? missing :
        only(last_warning).n_mcmc_warning_rows
    return [
        (finding = :q_category_budget_stability_recorded,
            severity = :info,
            evidence = string(length(budgets), " budget profile(s)"),
            implication =
                :threshold_policy_now_has_budget_sensitivity_evidence),
        (finding = :threshold_2_budget_sensitivity,
            severity = threshold2_false_promotion == baseline_t2 ? :info :
                :warning,
            evidence = string("baseline=", baseline_t2,
                ", last_budget=", threshold2_false_promotion),
            implication =
                :low_threshold_specificity_must_be_budget_stable),
        (finding = :threshold_4_budget_sensitivity,
            severity = threshold4_false_negative == baseline_t4 ? :info :
                :warning,
            evidence = string("baseline=", baseline_t4,
                ", last_budget=", threshold4_false_negative),
            implication =
                :strict_threshold_power_must_be_budget_stable),
        (finding = :threshold_risk_label_changes,
            severity = risk_changes == 0 ? :info : :warning,
            evidence = string(risk_changes,
                " threshold risk label change(s) across budget comparison"),
            implication =
                :near_cutoff_cells_need_larger_budget_or_repeated_seeds),
        (finding = :mcmc_warning_budget_recheck,
            severity = last_warning_count == 0 ? :info : :warning,
            evidence = string(last_warning_count,
                " warning row(s) in the last budget profile"),
            implication =
                :publication_grade_threshold_policy_requires_sampler_remediation),
        (finding = :public_claims_blocked,
            severity = :blocker,
            evidence = "local Q/category budget-stability check only",
            implication =
                :do_not_claim_public_fit_thresholds_model_weights_or_q_revisions),
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
        println(io, "# Uto-Style Q/Category Budget Stability")
        println(io)
        println(io, "- Generated at: `", artifact.generated_at, "`")
        println(io, "- Local only: `true`")
        println(io, "- Public claims allowed: `false`")
        println(io)
        println(io, "## Interpretation")
        println(io)
        println(io,
            "This report reruns the replicated Q/category bridge across MCMC ",
            "budget profiles. It checks whether candidate threshold calls, ",
            "category-calibration caveats, and sampler warnings are stable when ",
            "warmup and retained draws are increased.")
        println(io)
        println(io, "## Findings")
        table(io, ["Finding", "Severity", "Evidence", "Implication"],
            [[row.finding, row.severity, row.evidence, row.implication]
             for row in artifact.finding_rows])
        println(io, "## Threshold Summary")
        table(io, ["Budget", "Threshold", "Cells", "Candidate Passed",
                "False Promotion Rate", "False Negative Rate",
                "Category Caveat Rate"],
            [Any[row.budget, row.threshold, row.n_cells,
                row.n_candidate_passed,
                row.candidate_false_promotion_rate,
                row.candidate_false_negative_rate,
                row.candidate_predictive_category_caveat_rate]
             for row in artifact.threshold_summary_rows])
        println(io, "## Budget Deltas")
        table(io, ["Comparison", "Seed", "Scenario", "dCandidateLog",
                "dCand-DeclLog", "dBrier", "dTV", "dCumL1",
                "Risk Changes"],
            [[Symbol(string(row.baseline_budget, "_to_",
                    row.comparison_budget)),
                row.seed, row.scenario, row.delta_candidate_log_score,
                row.delta_candidate_minus_declared_log_score,
                row.delta_candidate_brier,
                row.delta_candidate_category_total_variation,
                row.delta_candidate_cumulative_l1,
                row.n_threshold_risk_changes]
             for row in artifact.budget_delta_rows])
        println(io, "## Warning Summary")
        table(io, ["Budget", "MCMC Rows", "Warnings", "Warning Rate",
                "MCMC Warning", "Sampler Warning"],
            [Any[row.budget, row.n_mcmc_model_rows,
                row.n_mcmc_warning_rows, row.mcmc_warning_rate,
                row.n_mcmc_warning, row.n_sampler_warning]
             for row in artifact.sampler_warning_summary_rows])
        println(io, "## Scenario Cells")
        table(io, ["Budget", "Seed", "Scenario", "Best", "Candidate dLog",
                "Candidate dBrier", "Candidate dTV", "Candidate dCumL1",
                "Caveat"],
            [[row.budget, row.seed, row.scenario, row.observed_best_model,
                row.candidate_delta_log_score_vs_null,
                row.candidate_delta_brier_vs_null,
                row.candidate_delta_category_total_variation_vs_null,
                row.candidate_delta_cumulative_l1_vs_null,
                row.candidate_predictive_category_caveat]
             for row in artifact.scenario_cell_rows])
        println(io, "## Boundary")
        println(io)
        println(io,
            "This is a local budget-stability diagnostic. A public threshold ",
            "policy still requires stable predictive-plus-category behavior and ",
            "sampler warnings that are resolved or explained under a larger ",
            "pre-registered MCMC budget.")
    end
    return path
end

function input_artifact_rows(options)
    rows = NamedTuple[]
    if isfile(options.previous_json)
        push!(rows, (;
            artifact = :replicated_q_misspecification_category_bridge,
            path = rel(options.previous_json),
            sha256 = file_sha256(options.previous_json),
        ))
    end
    return rows
end

function build_artifact(options)
    cell_rows = NamedTuple[]
    model_rows = NamedTuple[]
    comparison_rows_all = NamedTuple[]
    category_rows = NamedTuple[]
    cumulative_rows = NamedTuple[]
    for budget in options.budgets, seed in options.seeds,
            scenario in options.scenarios
        cell = scenario_budget_cell(options, budget, seed, scenario)
        push!(cell_rows, cell.cell_row)
        append!(model_rows, cell.model_rows)
        append!(comparison_rows_all, cell.comparison_rows)
        append!(category_rows, cell.category_distribution_rows)
        append!(cumulative_rows, cell.cumulative_threshold_rows)
    end
    thresholds = threshold_rows(cell_rows, options.thresholds)
    threshold_summary = threshold_summary_rows(thresholds)
    delta_rows =
        budget_delta_rows(cell_rows, thresholds, options.budgets,
            options.thresholds)
    warning_summary = sampler_warning_summary_rows(model_rows)
    findings =
        finding_rows(threshold_summary, delta_rows, warning_summary,
            options.budgets)
    return (;
        schema = OUTPUT_SCHEMA,
        family = :mgmfrm,
        scope = :uto_style_q_category_budget_stability,
        status = :local_q_category_budget_stability_recorded,
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
            budgets = options.budgets,
            scenarios = [scenario.name for scenario in options.scenarios],
            seeds = options.seeds,
            thresholds = options.thresholds,
            n_persons = options.n_persons,
            n_items = options.n_items,
            n_raters = options.n_raters,
            heldout_fraction = options.heldout_fraction,
        ),
        fit_controls = (;
            backend = :advancedhmc,
            sampler = :nuts,
            target_acceptance = options.target_acceptance,
            prior_profile = options.prior_profile,
            progress = options.progress,
        ),
        scenario_cell_rows = cell_rows,
        model_score_rows = model_rows,
        comparison_rows = comparison_rows_all,
        category_distribution_rows = category_rows,
        cumulative_threshold_rows = cumulative_rows,
        threshold_rows = thresholds,
        threshold_summary_rows = threshold_summary,
        budget_delta_rows = delta_rows,
        sampler_warning_summary_rows = warning_summary,
        finding_rows = findings,
        summary = (;
            passed = all(row.fit_succeeded for row in model_rows
                if row.model in MCMC_MODEL_NAMES),
            n_budget_profiles = length(options.budgets),
            n_seed_scenario_budget_cells = length(cell_rows),
            n_model_score_rows = length(model_rows),
            n_threshold_rows = length(thresholds),
            n_budget_delta_rows = length(delta_rows),
            n_threshold_risk_changes =
                sum((row.n_threshold_risk_changes for row in delta_rows);
                    init = 0),
            last_budget = last(options.budgets).budget,
            last_budget_threshold_2_candidate_false_promotion_rate =
                summary_value(threshold_summary, last(options.budgets).budget,
                    2.0, :candidate_false_promotion_rate),
            last_budget_threshold_4_false_negative_rate =
                summary_value(threshold_summary, last(options.budgets).budget,
                    4.0, :candidate_false_negative_rate),
            last_budget_mcmc_warning_rows =
                warning_summary_value(warning_summary,
                    last(options.budgets).budget, :n_mcmc_warning_rows),
            no_public_fit_metric_claim = true,
            no_public_q_revision_claim = true,
            no_automatic_q_revision = true,
            no_public_model_weight_claim = true,
            no_sparse_superiority_claim = true,
            next_gate = :pre_registered_larger_budget_threshold_policy,
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
    println("budget_cells=", artifact.summary.n_seed_scenario_budget_cells,
        " risk_changes=", artifact.summary.n_threshold_risk_changes,
        " last_budget_t2_false_promotion=",
        artifact.summary.last_budget_threshold_2_candidate_false_promotion_rate,
        " last_budget_t4_false_negative=",
        artifact.summary.last_budget_threshold_4_false_negative_rate,
        " next_gate=", artifact.summary.next_gate)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
