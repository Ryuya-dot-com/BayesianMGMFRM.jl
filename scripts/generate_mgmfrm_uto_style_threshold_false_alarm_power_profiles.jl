#!/usr/bin/env julia

using Dates
using JSON3
using SHA
using Statistics
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_REPLICATED_JSON =
    joinpath(ROOT, "artifacts", "uto_style_replicated_calibration_bridge",
        "uto_style_replicated_calibration_bridge.json")
const DEFAULT_BUDGET_JSON =
    joinpath(ROOT, "artifacts", "uto_style_mcmc_budget_bridge",
        "uto_style_mcmc_budget_bridge.json")
const DEFAULT_CATEGORY_JSON =
    joinpath(ROOT, "artifacts", "uto_style_category_calibration_bridge",
        "uto_style_category_calibration_bridge.json")
const DEFAULT_OUTPUT_JSON =
    joinpath(ROOT, "artifacts", "uto_style_threshold_false_alarm_power_profiles",
        "uto_style_threshold_false_alarm_power_profiles.json")
const DEFAULT_OUTPUT_MD =
    joinpath(ROOT, "artifacts", "uto_style_threshold_false_alarm_power_profiles",
        "uto_style_threshold_false_alarm_power_profiles.md")

include(joinpath(@__DIR__, "local_json.jl"))

const OUTPUT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_uto_style_threshold_false_alarm_power_profiles.v1"

function usage()
    return """
    Generate local Uto-style MGMFRM threshold false-alarm/power profiles.

    This reads the replicated calibration, MCMC-budget, and category-calibration
    bridge artifacts, then summarizes how candidate dELPD/log-score thresholds
    behave under signal scenarios and a transition/negative-control scenario.
    It does not run new MCMC and does not promote public fit thresholds.

    Usage:
      julia --project=. scripts/generate_mgmfrm_uto_style_threshold_false_alarm_power_profiles.jl [options]

    Options:
      --replicated-json PATH  Replicated calibration bridge JSON.
      --budget-json PATH      MCMC-budget bridge JSON.
      --category-json PATH    Category-calibration bridge JSON.
      --output-json PATH      JSON artifact path.
      --output-md PATH        Markdown report path.
    """
end

function parse_args(args)
    replicated_json = DEFAULT_REPLICATED_JSON
    budget_json = DEFAULT_BUDGET_JSON
    category_json = DEFAULT_CATEGORY_JSON
    output_json = DEFAULT_OUTPUT_JSON
    output_md = DEFAULT_OUTPUT_MD

    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--replicated-json"
            index < length(args) || error("--replicated-json requires a path")
            replicated_json = abspath(args[index + 1])
            index += 2
        elseif arg == "--budget-json"
            index < length(args) || error("--budget-json requires a path")
            budget_json = abspath(args[index + 1])
            index += 2
        elseif arg == "--category-json"
            index < length(args) || error("--category-json requires a path")
            category_json = abspath(args[index + 1])
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

    return (; replicated_json, budget_json, category_json, output_json,
        output_md)
end

project_version() =
    String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])
file_sha256(path::AbstractString) = bytes2hex(open(sha256, path))
rel(path::AbstractString) = relpath(path, ROOT)
round3(value) = round(Float64(value); digits = 3)
round4(value) = round(Float64(value); digits = 4)

function load_required_json(path::AbstractString, label::Symbol)
    isfile(path) || error("required input artifact missing for $label: $path")
    return JSON3.read(read(path, String))
end

function as_symbol(value)
    value isa Symbol && return value
    return Symbol(String(value))
end

function as_float(value)
    return Float64(value)
end

function rate(count_value::Integer, denominator::Integer)
    denominator == 0 && return NaN
    return round4(count_value / denominator)
end

function mean_or_nan(values)
    isempty(values) && return NaN
    return round4(mean(Float64.(values)))
end

function scenario_role(scenario)
    symbol = as_symbol(scenario)
    symbol === :strong_source_aligned && return :signal_anchor
    symbol === :weak_compressed_category && return :signal_threshold_stress
    symbol === :moderate_transition && return :transition_negative_control
    return :unclassified
end

is_signal_scenario(scenario) =
    scenario_role(scenario) in (:signal_anchor, :signal_threshold_stress)
is_negative_control_scenario(scenario) =
    scenario_role(scenario) === :transition_negative_control

function scenario_label_rows()
    return [
        (scenario = :strong_source_aligned,
            role = :signal_anchor,
            expected_decision =
                :detect_true_q_without_requiring_category_caveats,
            false_alarm_definition = :not_applicable_signal_scenario,
            power_definition = :mcmc_true_q_passes_threshold),
        (scenario = :weak_compressed_category,
            role = :signal_threshold_stress,
            expected_decision =
                :detect_true_q_at_low_thresholds_and_measure_false_negatives,
            false_alarm_definition = :not_applicable_signal_scenario,
            power_definition = :mcmc_true_q_passes_threshold),
        (scenario = :moderate_transition,
            role = :transition_negative_control,
            expected_decision =
                :do_not_promote_under_current_mcmc_and_category_evidence,
            false_alarm_definition = :mcmc_true_q_passes_threshold,
            power_definition = :not_applicable_negative_control),
    ]
end

function threshold_decision(false_promotion_rate, signal_power_rate,
        weak_power_rate, category_caveat_rate)
    isfinite(false_promotion_rate) && false_promotion_rate > 0 &&
        return :screening_only_false_promotion_observed
    isfinite(category_caveat_rate) && category_caveat_rate > 0 &&
        return :screening_only_category_caveat_observed
    isfinite(weak_power_rate) && weak_power_rate < 1 &&
        return :screening_only_strict_cutoff_misses_weak_signal
    isfinite(signal_power_rate) && signal_power_rate == 1 &&
        return :locally_balanced_screening_profile
    return :screening_only_power_loss_observed
end

function replicated_threshold_profile_rows(replicated)
    rows = collect(replicated.threshold_rows)
    thresholds = sort(unique(as_float(row.threshold) for row in rows))
    output = NamedTuple[]
    for threshold in thresholds
        group = [row for row in rows if as_float(row.threshold) == threshold]
        signal = [row for row in group if is_signal_scenario(row.scenario)]
        strong = [row for row in group
            if as_symbol(row.scenario) === :strong_source_aligned]
        weak = [row for row in group
            if as_symbol(row.scenario) === :weak_compressed_category]
        negative = [row for row in group
            if is_negative_control_scenario(row.scenario)]

        signal_power =
            rate(count(row -> Bool(row.mcmc_true_q_passed), signal),
                length(signal))
        strong_power =
            rate(count(row -> Bool(row.mcmc_true_q_passed), strong),
                length(strong))
        weak_power =
            rate(count(row -> Bool(row.mcmc_true_q_passed), weak),
                length(weak))
        false_promotion =
            rate(count(row -> Bool(row.mcmc_true_q_passed), negative),
                length(negative))
        category_caveat = 0.0

        push!(output, (;
            threshold,
            n_cells = length(group),
            n_signal_cells = length(signal),
            n_negative_control_cells = length(negative),
            signal_true_q_power_rate = signal_power,
            strong_true_q_power_rate = strong_power,
            weak_true_q_power_rate = weak_power,
            weak_false_negative_rate =
                isfinite(weak_power) ? round4(1 - weak_power) : NaN,
            negative_control_false_promotion_rate = false_promotion,
            negative_control_wrong_q_pass_rate =
                rate(count(row -> Bool(row.wrong_q_passed), negative),
                    length(negative)),
            negative_control_scalar_pass_rate =
                rate(count(row -> Bool(row.scalar_passed), negative),
                    length(negative)),
            all_wrong_q_pass_rate =
                rate(count(row -> Bool(row.wrong_q_passed), group),
                    length(group)),
            all_scalar_pass_rate =
                rate(count(row -> Bool(row.scalar_passed), group),
                    length(group)),
            oracle_only_rate =
                rate(count(row -> Bool(row.oracle_true_q_passed) &&
                    !Bool(row.mcmc_true_q_passed), group), length(group)),
            mean_true_q_margin =
                mean_or_nan([row.true_q_mcmc_delta_elpd_vs_null
                    for row in replicated.scenario_rows
                    if is_signal_scenario(row.scenario)]),
            decision_profile = threshold_decision(false_promotion,
                signal_power, weak_power, category_caveat),
            public_claim_allowed = false,
        ))
    end
    return output
end

function budget_threshold_profile_rows(budget)
    rows = collect(budget.threshold_stability_rows)
    output = NamedTuple[]
    keys = sort(unique((as_symbol(row.budget_profile),
        as_symbol(row.scoring_variant), as_float(row.threshold)) for row in rows);
        by = key -> (string(key[1]), string(key[2]), key[3]))
    for (budget_profile, scoring_variant, threshold) in keys
        group = [row for row in rows
            if as_symbol(row.budget_profile) === budget_profile &&
               as_symbol(row.scoring_variant) === scoring_variant &&
               as_float(row.threshold) == threshold]
        signal = [row for row in group if is_signal_scenario(row.scenario)]
        weak = [row for row in group
            if as_symbol(row.scenario) === :weak_compressed_category]
        negative = [row for row in group
            if is_negative_control_scenario(row.scenario)]
        signal_power = mean_or_nan([row.mcmc_pass_rate for row in signal])
        weak_power = mean_or_nan([row.mcmc_pass_rate for row in weak])
        false_promotion = mean_or_nan([row.mcmc_pass_rate for row in negative])
        push!(output, (;
            budget_profile,
            scoring_variant,
            threshold,
            n_scenarios = length(group),
            signal_true_q_power_rate = signal_power,
            weak_true_q_power_rate = weak_power,
            negative_control_false_promotion_rate = false_promotion,
            oracle_only_rate =
                mean_or_nan([row.oracle_only_rate for row in group]),
            decision_profile = threshold_decision(false_promotion,
                signal_power, weak_power, 0.0),
            public_claim_allowed = false,
        ))
    end
    return output
end

function category_threshold_profile_rows(category)
    rows = collect(category.threshold_link_rows)
    output = NamedTuple[]
    thresholds = sort(unique(as_float(row.threshold) for row in rows))
    for threshold in thresholds
        group = [row for row in rows if as_float(row.threshold) == threshold]
        signal = [row for row in group if is_signal_scenario(row.scenario)]
        strong = [row for row in group
            if as_symbol(row.scenario) === :strong_source_aligned]
        weak = [row for row in group
            if as_symbol(row.scenario) === :weak_compressed_category]
        negative = [row for row in group
            if is_negative_control_scenario(row.scenario)]
        passed = [row for row in group if Bool(row.passed_delta_log_score)]
        aligned = [row for row in signal
            if as_symbol(row.calibration_interpretation) ===
               :predictive_and_category_calibration_aligned]
        caveats = [row for row in signal
            if as_symbol(row.calibration_interpretation) ===
               :predictive_gain_with_category_calibration_caveat]

        signal_power =
            rate(count(row -> Bool(row.passed_delta_log_score), signal),
                length(signal))
        weak_power =
            rate(count(row -> Bool(row.passed_delta_log_score), weak),
                length(weak))
        false_promotion =
            rate(count(row -> Bool(row.passed_delta_log_score), negative),
                length(negative))
        caveat_rate = rate(length(caveats), length(signal))
        push!(output, (;
            threshold,
            n_cells = length(group),
            n_signal_cells = length(signal),
            n_negative_control_cells = length(negative),
            signal_log_score_power_rate = signal_power,
            strong_log_score_power_rate =
                rate(count(row -> Bool(row.passed_delta_log_score), strong),
                    length(strong)),
            weak_log_score_power_rate = weak_power,
            weak_false_negative_rate =
                isfinite(weak_power) ? round4(1 - weak_power) : NaN,
            negative_control_false_promotion_rate = false_promotion,
            signal_category_aligned_pass_rate =
                rate(length(aligned), length(signal)),
            predictive_gain_category_caveat_rate = caveat_rate,
            alignment_conditional_on_pass_rate =
                rate(count(row -> as_symbol(row.calibration_interpretation) ===
                    :predictive_and_category_calibration_aligned, passed),
                    length(passed)),
            mean_signal_delta_category_tv =
                mean_or_nan([row.delta_category_total_variation_vs_null
                    for row in signal]),
            mean_signal_delta_cumulative_l1 =
                mean_or_nan([row.delta_cumulative_l1_vs_null
                    for row in signal]),
            decision_profile = threshold_decision(false_promotion,
                signal_power, weak_power, caveat_rate),
            public_claim_allowed = false,
        ))
    end
    return output
end

function input_artifact_rows(options, replicated, budget, category)
    return [
        (artifact = :replicated_calibration_bridge,
            path = rel(options.replicated_json),
            schema = String(replicated.schema),
            sha256 = file_sha256(options.replicated_json),
            summary_passed = Bool(replicated.summary.passed)),
        (artifact = :mcmc_budget_bridge,
            path = rel(options.budget_json),
            schema = String(budget.schema),
            sha256 = file_sha256(options.budget_json),
            summary_passed = Bool(budget.summary.passed)),
        (artifact = :category_calibration_bridge,
            path = rel(options.category_json),
            schema = String(category.schema),
            sha256 = file_sha256(options.category_json),
            summary_passed = Bool(category.summary.passed)),
    ]
end

function finding_rows(threshold_rows, budget_rows, category_rows)
    threshold_4 = [row for row in threshold_rows if row.threshold == 4.0]
    threshold_2 = [row for row in threshold_rows if row.threshold == 2.0]
    category_caveat_count =
        sum(row.predictive_gain_category_caveat_rate > 0 for row in category_rows)
    false_promotion_max = maximum(
        [row.negative_control_false_promotion_rate for row in threshold_rows])
    weak_power_at_4 = isempty(threshold_4) ? NaN :
        first(threshold_4).weak_true_q_power_rate
    power_at_2 = isempty(threshold_2) ? NaN :
        first(threshold_2).signal_true_q_power_rate
    competing_pass_at_2 = isempty(threshold_2) ? NaN :
        max(first(threshold_2).all_wrong_q_pass_rate,
            first(threshold_2).all_scalar_pass_rate)
    budget_direction_changes = count(row ->
        row.decision_profile === :screening_only_false_promotion_observed,
        budget_rows)
    return [
        (finding = :threshold_false_alarm_power_profile_recorded,
            severity = :info,
            evidence = string(length(threshold_rows),
                " threshold profile row(s) from replicated simulation evidence"),
            implication =
                :thresholds_can_be_read_as_profiles_not_single_cutoffs),
        (finding = :low_threshold_screening_power,
            severity = isfinite(power_at_2) && power_at_2 == 1.0 ?
                :info : :warning,
            evidence = string("threshold 2 signal power = ", power_at_2,
                "; max negative-control false promotion = ",
                false_promotion_max),
            implication =
                :low_thresholds_are_candidate_screening_profiles_only),
        (finding = :low_threshold_model_specificity_risk,
            severity = isfinite(competing_pass_at_2) &&
                competing_pass_at_2 > 0 ? :warning : :info,
            evidence = string("threshold 2 max competing-model pass rate = ",
                competing_pass_at_2),
            implication =
                :predictive_thresholds_alone_do_not_validate_the_q_matrix),
        (finding = :strict_threshold_power_loss,
            severity = isfinite(weak_power_at_4) && weak_power_at_4 < 1.0 ?
                :warning : :info,
            evidence = string("threshold 4 weak-signal power = ",
                weak_power_at_4),
            implication =
                :threshold_4_can_create_false_negatives_for_compressed_categories),
        (finding = :category_alignment_profile,
            severity = category_caveat_count == 0 ? :info : :warning,
            evidence = string(category_caveat_count,
                " threshold row(s) with predictive-gain/category caveats"),
            implication =
                :category_calibration_should_be_required_with_predictive_gain),
        (finding = :budget_profile_screen,
            severity = budget_direction_changes == 0 ? :info : :warning,
            evidence = string(budget_direction_changes,
                " budget threshold profile row(s) showed false promotion"),
            implication =
                :budget_profiles_remain_diagnostic_until_public_budget_policy_exists),
        (finding = :public_claims_blocked,
            severity = :blocker,
            evidence = "local false-alarm/power profiling only",
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
        println(io, "# Uto-Style Threshold False-Alarm and Power Profiles")
        println(io)
        println(io, "- Generated at: `", artifact.generated_at, "`")
        println(io, "- Local only: `true`")
        println(io, "- Public claims allowed: `false`")
        println(io)
        println(io, "## Interpretation")
        println(io)
        println(io,
            "This report treats candidate dELPD/log-score thresholds as ",
            "simulation profiles. Strong and weak source-aligned scenarios are ",
            "power checks; the moderate transition scenario is a local ",
            "negative-control check for false promotion. Category calibration is ",
            "kept as a separate gate, so predictive gain alone is not promoted.")
        println(io)
        println(io, "## Findings")
        table(io, ["Finding", "Severity", "Evidence", "Implication"],
            [[row.finding, row.severity, row.evidence, row.implication]
             for row in artifact.finding_rows])
        println(io, "## Replicated Threshold Profile")
        table(io, ["Threshold", "Cells", "Signal Cells", "Negative Cells",
                "Signal Power", "Strong Power", "Weak Power",
                "Weak False Negative", "False Promotion", "Wrong-Q Pass",
                "Scalar Pass", "Oracle Only", "Decision"],
            [[row.threshold, row.n_cells, row.n_signal_cells,
                row.n_negative_control_cells, row.signal_true_q_power_rate,
                row.strong_true_q_power_rate, row.weak_true_q_power_rate,
                row.weak_false_negative_rate,
                row.negative_control_false_promotion_rate,
                row.all_wrong_q_pass_rate, row.all_scalar_pass_rate,
                row.oracle_only_rate, row.decision_profile]
             for row in artifact.threshold_profile_rows])
        println(io, "## Category-Calibrated Threshold Profile")
        table(io, ["Threshold", "Cells", "Signal Power", "Strong Power",
                "Weak Power", "Weak False Negative", "False Promotion",
                "Aligned Signal Pass", "Caveat Rate", "Aligned If Passed",
                "Mean dTV", "Mean dCumL1", "Decision"],
            [[row.threshold, row.n_cells, row.signal_log_score_power_rate,
                row.strong_log_score_power_rate,
                row.weak_log_score_power_rate, row.weak_false_negative_rate,
                row.negative_control_false_promotion_rate,
                row.signal_category_aligned_pass_rate,
                row.predictive_gain_category_caveat_rate,
                row.alignment_conditional_on_pass_rate,
                row.mean_signal_delta_category_tv,
                row.mean_signal_delta_cumulative_l1,
                row.decision_profile]
             for row in artifact.category_threshold_profile_rows])
        println(io, "## Budget Threshold Profile")
        table(io, ["Budget", "Variant", "Threshold", "Signal Power",
                "Weak Power", "False Promotion", "Oracle Only", "Decision"],
            [[row.budget_profile, row.scoring_variant, row.threshold,
                row.signal_true_q_power_rate, row.weak_true_q_power_rate,
                row.negative_control_false_promotion_rate,
                row.oracle_only_rate, row.decision_profile]
             for row in artifact.budget_threshold_profile_rows])
        println(io, "## Scenario Label Policy")
        table(io, ["Scenario", "Role", "Expected Decision",
                "False-Alarm Definition", "Power Definition"],
            [[row.scenario, row.role, row.expected_decision,
                row.false_alarm_definition, row.power_definition]
             for row in artifact.scenario_label_rows])
        println(io, "## Input Artifacts")
        table(io, ["Artifact", "Path", "Schema", "Summary Passed"],
            [[row.artifact, row.path, row.schema, row.summary_passed]
             for row in artifact.input_artifacts])
        println(io, "## Boundary")
        println(io)
        println(io,
            "This artifact is a local simulation-profile diagnostic. It can ",
            "identify candidate screening thresholds and power losses, but it ",
            "does not define public cutoffs, model weights, Q-revision rules, ",
            "or sparse-MGMFRM superiority claims.")
    end
    return path
end

function build_artifact(options)
    replicated =
        load_required_json(options.replicated_json, :replicated_calibration)
    budget = load_required_json(options.budget_json, :mcmc_budget)
    category = load_required_json(options.category_json, :category_calibration)
    threshold_rows = replicated_threshold_profile_rows(replicated)
    budget_rows = budget_threshold_profile_rows(budget)
    category_rows = category_threshold_profile_rows(category)
    findings = finding_rows(threshold_rows, budget_rows, category_rows)
    inputs = input_artifact_rows(options, replicated, budget, category)
    return (;
        schema = OUTPUT_SCHEMA,
        family = :mgmfrm,
        scope = :uto_style_threshold_false_alarm_power_profiles,
        status = :local_threshold_false_alarm_power_profile_recorded,
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
        public_model_weight_claim = false,
        sparse_mgmfrm_superiority_claim = false,
        input_artifacts = inputs,
        scenario_label_rows = scenario_label_rows(),
        threshold_profile_rows = threshold_rows,
        budget_threshold_profile_rows = budget_rows,
        category_threshold_profile_rows = category_rows,
        finding_rows = findings,
        summary = (;
            passed = all(row.summary_passed for row in inputs),
            n_threshold_profile_rows = length(threshold_rows),
            n_budget_threshold_profile_rows = length(budget_rows),
            n_category_threshold_profile_rows = length(category_rows),
            max_negative_control_false_promotion_rate =
                maximum(row.negative_control_false_promotion_rate
                    for row in threshold_rows),
            min_signal_power_rate =
                minimum(row.signal_true_q_power_rate for row in threshold_rows),
            threshold_2_signal_power_rate =
                first(row.signal_true_q_power_rate for row in threshold_rows
                    if row.threshold == 2.0),
            threshold_2_max_competing_model_pass_rate =
                first(max(row.all_wrong_q_pass_rate,
                    row.all_scalar_pass_rate) for row in threshold_rows
                    if row.threshold == 2.0),
            threshold_4_weak_power_rate =
                first(row.weak_true_q_power_rate for row in threshold_rows
                    if row.threshold == 4.0),
            category_caveat_threshold_rows =
                count(row -> row.predictive_gain_category_caveat_rate > 0,
                    category_rows),
            no_public_fit_metric_claim = true,
            no_public_q_revision_claim = true,
            no_public_model_weight_claim = true,
            no_sparse_superiority_claim = true,
            next_gate =
                :expand_null_and_q_misspecification_threshold_simulations,
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
    println("threshold_rows=", artifact.summary.n_threshold_profile_rows,
        " max_false_promotion=",
        artifact.summary.max_negative_control_false_promotion_rate,
        " threshold_2_power=",
        artifact.summary.threshold_2_signal_power_rate,
        " threshold_4_weak_power=",
        artifact.summary.threshold_4_weak_power_rate,
        " next_gate=", artifact.summary.next_gate)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
