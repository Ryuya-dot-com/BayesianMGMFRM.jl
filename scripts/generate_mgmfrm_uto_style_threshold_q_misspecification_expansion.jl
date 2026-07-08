#!/usr/bin/env julia

using Dates
using JSON3
using SHA
using Statistics
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_THRESHOLD_PROFILE_JSON =
    joinpath(ROOT, "artifacts",
        "uto_style_threshold_false_alarm_power_profiles",
        "uto_style_threshold_false_alarm_power_profiles.json")
const DEFAULT_Q_GRID_JSON =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_empirical_q_matrix_recovery_simulation_grid.json")
const DEFAULT_HELDOUT_GRID_JSON =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_heldout_prediction_simulation_grid.json")
const DEFAULT_OUTPUT_JSON =
    joinpath(ROOT, "artifacts",
        "uto_style_threshold_q_misspecification_expansion",
        "uto_style_threshold_q_misspecification_expansion.json")
const DEFAULT_OUTPUT_MD =
    joinpath(ROOT, "artifacts",
        "uto_style_threshold_q_misspecification_expansion",
        "uto_style_threshold_q_misspecification_expansion.md")

include(joinpath(@__DIR__, "local_json.jl"))

const OUTPUT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_uto_style_threshold_q_misspecification_expansion.v1"

const EXPLICIT_NULL_SCENARIO = (;
    scenario = :explicit_null_no_multidimensional_signal,
    expansion_axis = :explicit_null,
    q_grid_source = :not_in_q_grid_added_for_threshold_false_alarm_check,
    expected_action = :retain_null_or_scalar_reference,
    expected_public_action = :block_public_mgmfrm_promotion,
    candidate_exact_recovery = false,
    false_candidate = false,
    deferred_candidate = false,
    declared_cell_f1 = NaN,
    candidate_cell_f1 = NaN,
)

function usage()
    return """
    Generate a local Uto-style threshold/Q-misspecification expansion artifact.

    This joins the Uto-style threshold false-alarm/power profile with the
    empirical Q-matrix recovery simulation grid and adds an explicit null row.
    It is a pre-execution expansion: it identifies which threshold profiles
    need explicit null, false-add, false-drop, weak-dimension, and
    Q-misspecification simulations before public cutoffs can be considered.

    Usage:
      julia --project=. scripts/generate_mgmfrm_uto_style_threshold_q_misspecification_expansion.jl [options]

    Options:
      --threshold-profile-json PATH  Uto threshold false-alarm/power JSON.
      --q-grid-json PATH             Empirical Q-matrix recovery grid JSON.
      --heldout-grid-json PATH       Heldout prediction simulation grid JSON.
      --output-json PATH             JSON artifact path.
      --output-md PATH               Markdown report path.
    """
end

function parse_args(args)
    threshold_profile_json = DEFAULT_THRESHOLD_PROFILE_JSON
    q_grid_json = DEFAULT_Q_GRID_JSON
    heldout_grid_json = DEFAULT_HELDOUT_GRID_JSON
    output_json = DEFAULT_OUTPUT_JSON
    output_md = DEFAULT_OUTPUT_MD

    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--threshold-profile-json"
            index < length(args) ||
                error("--threshold-profile-json requires a path")
            threshold_profile_json = abspath(args[index + 1])
            index += 2
        elseif arg == "--q-grid-json"
            index < length(args) || error("--q-grid-json requires a path")
            q_grid_json = abspath(args[index + 1])
            index += 2
        elseif arg == "--heldout-grid-json"
            index < length(args) || error("--heldout-grid-json requires a path")
            heldout_grid_json = abspath(args[index + 1])
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

    return (; threshold_profile_json, q_grid_json, heldout_grid_json,
        output_json, output_md)
end

project_version() =
    String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])
file_sha256(path::AbstractString) = bytes2hex(open(sha256, path))
rel(path::AbstractString) = relpath(path, ROOT)
round4(value) = round(Float64(value); digits = 4)

function load_required_json(path::AbstractString, label::Symbol)
    isfile(path) || error("required input artifact missing for $label: $path")
    return JSON3.read(read(path, String))
end

as_symbol(value) = value isa Symbol ? value : Symbol(String(value))
as_string(value) = String(value)
as_bool(value) = Bool(value)
as_float(value) = Float64(value)

function get_float(object, key::Symbol; default = NaN)
    value = object[key]
    value === nothing && return default
    return Float64(value)
end

function q_expansion_axis(scenario::Symbol, row)
    scenario === :well_separated_true_q_retained && return :well_specified_q
    scenario === :missing_loading_recovered_as_candidate &&
        return :false_drop_missing_loading
    scenario === :extra_loading_removed_as_candidate &&
        return :false_add_extra_loading
    scenario === :ambiguous_cross_loading_deferred &&
        return :ambiguous_q_misspecification
    scenario === :high_noise_false_add_not_promoted &&
        return :false_add_noise
    scenario === :low_signal_false_drop_not_promoted &&
        return :false_drop_low_signal
    scenario === :duplicate_dimension_false_add_blocked &&
        return :false_add_duplicate_dimension
    scenario === :weak_dimension_design_deferred &&
        return :weak_dimension
    scenario === :iterative_single_item_missing_loading_candidate &&
        return :false_drop_missing_loading
    scenario === :rater_consistency_noise_false_positive_manual_only &&
        return :false_add_rater_method_noise
    scenario === :three_dimension_anchor_recovery_retained &&
        return :well_specified_q
    scenario === :sparse_isolated_attribute_design_retained &&
        return :weak_or_sparse_dimension
    as_bool(row.false_candidate) && return :false_candidate_manual_review
    return :q_misspecification_other
end

function scenario_priority(axis::Symbol)
    axis === :explicit_null && return 1
    axis === :well_specified_q && return 2
    axis in (:false_drop_missing_loading, :false_drop_low_signal) && return 3
    axis in (:false_add_extra_loading, :false_add_noise,
        :false_add_duplicate_dimension, :false_add_rater_method_noise) &&
        return 4
    axis in (:weak_dimension, :weak_or_sparse_dimension) && return 5
    axis === :ambiguous_q_misspecification && return 6
    return 7
end

function threshold_profile_by_value(threshold_profile)
    result = Dict{Float64, Any}()
    for row in threshold_profile.threshold_profile_rows
        result[as_float(row.threshold)] = row
    end
    return result
end

function q_scenario_rows(q_grid)
    rows = NamedTuple[EXPLICIT_NULL_SCENARIO]
    for row in q_grid.scenario_rows
        scenario = as_symbol(row.scenario)
        summary = row.summary
        push!(rows, (;
            scenario,
            expansion_axis = q_expansion_axis(scenario, row),
            q_grid_source = :empirical_q_matrix_recovery_simulation_grid,
            expected_action = as_symbol(row.expected_action),
            expected_public_action =
                as_bool(row.public_claim_allowed) ? :review_public_action :
                :manual_review_or_block_public_revision,
            candidate_exact_recovery = as_bool(row.candidate_exact_recovery),
            false_candidate = as_bool(row.false_candidate),
            deferred_candidate =
                as_bool(summary.deferred_candidate) ||
                !as_bool(row.validation_passed),
            declared_cell_f1 = get_float(row.declared_metrics, :f1),
            candidate_cell_f1 = get_float(row.candidate_metrics, :f1),
        ))
    end
    sort!(rows; by = row -> (scenario_priority(row.expansion_axis),
        string(row.scenario)))
    return rows
end

function scenario_threshold_risk(axis::Symbol, threshold::Float64, profile)
    if axis === :explicit_null
        return profile.negative_control_false_promotion_rate == 0 ?
            :needs_explicit_null_confirmation :
            :false_alarm_risk_observed
    elseif axis === :well_specified_q
        return profile.strong_true_q_power_rate == 1 ?
            :well_specified_power_supported_locally :
            :well_specified_power_loss_risk
    elseif axis in (:false_drop_missing_loading, :false_drop_low_signal)
        threshold >= 4 && return :false_drop_or_missing_loading_false_negative_risk
        return :missing_loading_screening_power_check
    elseif axis in (:false_add_extra_loading, :false_add_noise,
            :false_add_duplicate_dimension, :false_add_rater_method_noise)
        threshold <= 2 && return :false_add_specificity_check_required
        return :stricter_threshold_reduces_false_add_but_needs_power_check
    elseif axis in (:weak_dimension, :weak_or_sparse_dimension)
        threshold >= 4 && return :weak_dimension_false_negative_risk
        return :weak_dimension_screening_only
    elseif axis === :ambiguous_q_misspecification
        return :ambiguous_q_requires_construct_review_under_any_threshold
    end
    return :manual_review_required
end

function scenario_threshold_rows(scenarios, threshold_profile)
    profiles = threshold_profile_by_value(threshold_profile)
    rows = NamedTuple[]
    for scenario in scenarios
        for threshold in sort(collect(keys(profiles)))
            profile = profiles[threshold]
            risk = scenario_threshold_risk(scenario.expansion_axis, threshold,
                profile)
            push!(rows, (;
                scenario = scenario.scenario,
                expansion_axis = scenario.expansion_axis,
                threshold,
                signal_power_rate = as_float(profile.signal_true_q_power_rate),
                weak_power_rate = as_float(profile.weak_true_q_power_rate),
                negative_control_false_promotion_rate =
                    as_float(profile.negative_control_false_promotion_rate),
                competing_model_pass_rate =
                    max(as_float(profile.all_wrong_q_pass_rate),
                        as_float(profile.all_scalar_pass_rate)),
                threshold_decision_profile =
                    as_symbol(profile.decision_profile),
                risk_interpretation = risk,
                public_claim_allowed = false,
            ))
        end
    end
    return rows
end

function axis_summary_rows(rows)
    output = NamedTuple[]
    for axis in sort(unique(row.expansion_axis for row in rows);
            by = axis -> (scenario_priority(axis), string(axis)))
        group = [row for row in rows if row.expansion_axis === axis]
        push!(output, (;
            expansion_axis = axis,
            n_scenarios = length(group),
            n_false_candidates = count(row -> row.false_candidate, group),
            n_deferred_candidates = count(row -> row.deferred_candidate, group),
            n_exact_candidate_recoveries =
                count(row -> row.candidate_exact_recovery, group),
            min_candidate_cell_f1 =
                let values = [row.candidate_cell_f1 for row in group
                        if isfinite(row.candidate_cell_f1)]
                    isempty(values) ? NaN : round4(minimum(values))
                end,
            public_claim_allowed = false,
        ))
    end
    return output
end

function threshold_expansion_summary_rows(rows)
    output = NamedTuple[]
    for threshold in sort(unique(row.threshold for row in rows))
        group = [row for row in rows if row.threshold == threshold]
        push!(output, (;
            threshold,
            n_scenario_threshold_cells = length(group),
            n_false_add_specificity_cells =
                count(row -> row.risk_interpretation ===
                    :false_add_specificity_check_required, group),
            n_false_negative_risk_cells =
                count(row -> row.risk_interpretation in
                    (:false_drop_or_missing_loading_false_negative_risk,
                     :weak_dimension_false_negative_risk), group),
            n_explicit_null_confirmation_cells =
                count(row -> row.risk_interpretation ===
                    :needs_explicit_null_confirmation, group),
            n_construct_review_cells =
                count(row -> row.risk_interpretation ===
                    :ambiguous_q_requires_construct_review_under_any_threshold,
                    group),
            public_claim_allowed = false,
        ))
    end
    return output
end

function heldout_link_rows(heldout_grid)
    rows = NamedTuple[]
    for row in heldout_grid.scenario_rows
        push!(rows, (;
            scenario = as_symbol(row.scenario),
            q_condition = as_symbol(row.q_condition),
            expected_best_model = as_symbol(row.expected_best_model),
            threshold_profile_sensitive =
                as_bool(row.threshold_profile_sensitive),
            external_construct_validation_needed =
                as_bool(row.external_construct_validation_needed),
            public_claim_allowed = false,
        ))
    end
    return rows
end

function input_artifact_rows(options, threshold_profile, q_grid, heldout_grid)
    return [
        (artifact = :uto_style_threshold_false_alarm_power_profiles,
            path = rel(options.threshold_profile_json),
            schema = as_string(threshold_profile.schema),
            sha256 = file_sha256(options.threshold_profile_json),
            summary_passed = as_bool(threshold_profile.summary.passed)),
        (artifact = :mgmfrm_empirical_q_matrix_recovery_simulation_grid,
            path = rel(options.q_grid_json),
            schema = as_string(q_grid.schema),
            sha256 = file_sha256(options.q_grid_json),
            summary_passed = as_bool(q_grid.summary.passed)),
        (artifact = :mgmfrm_heldout_prediction_simulation_grid,
            path = rel(options.heldout_grid_json),
            schema = as_string(heldout_grid.schema),
            sha256 = file_sha256(options.heldout_grid_json),
            summary_passed = as_bool(heldout_grid.summary.passed)),
    ]
end

function finding_rows(axis_rows, threshold_summary_rows, threshold_profile)
    low = first(row for row in threshold_profile.threshold_profile_rows
        if as_float(row.threshold) == 2.0)
    strict = first(row for row in threshold_profile.threshold_profile_rows
        if as_float(row.threshold) == 4.0)
    false_add_axes = [row for row in axis_rows
        if occursin("false_add", string(row.expansion_axis))]
    false_negative_t4 = first(row for row in threshold_summary_rows
        if row.threshold == 4.0).n_false_negative_risk_cells
    return [
        (finding = :q_misspecification_expansion_recorded,
            severity = :info,
            evidence = string(length(axis_rows),
                " expansion-axis summary row(s) recorded"),
            implication =
                :threshold_profiles_now_have_explicit_q_misspecification_axes),
        (finding = :threshold_2_specificity_warning,
            severity = :warning,
            evidence = string("threshold 2 competing pass rate = ",
                max(as_float(low.all_wrong_q_pass_rate),
                    as_float(low.all_scalar_pass_rate)),
                "; false-add axes = ", length(false_add_axes)),
            implication =
                :low_thresholds_need_false_add_and_rater_noise_specificity_checks),
        (finding = :threshold_4_false_negative_warning,
            severity = :warning,
            evidence = string("threshold 4 weak power = ",
                as_float(strict.weak_true_q_power_rate),
                "; false-negative risk cells = ", false_negative_t4),
            implication =
                :strict_thresholds_need_false_drop_and_weak_dimension_power_checks),
        (finding = :explicit_null_gap,
            severity = :warning,
            evidence =
                "explicit null row added as pre-execution requirement, not MCMC evidence",
            implication =
                :run_explicit_null_mcmc_simulation_before_public_false_alarm_rates),
        (finding = :public_claims_blocked,
            severity = :blocker,
            evidence = "local threshold/Q expansion only",
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
        println(io, "# Uto-Style Threshold/Q-Misspecification Expansion")
        println(io)
        println(io, "- Generated at: `", artifact.generated_at, "`")
        println(io, "- Local only: `true`")
        println(io, "- Public claims allowed: `false`")
        println(io)
        println(io, "## Interpretation")
        println(io)
        println(io,
            "This report expands the threshold false-alarm/power profile into ",
            "explicit null and Q-misspecification axes. It is a pre-execution ",
            "simulation map: it tells us which MCMC simulations must be run next, ",
            "not which public threshold to use.")
        println(io)
        println(io, "## Findings")
        table(io, ["Finding", "Severity", "Evidence", "Implication"],
            [[row.finding, row.severity, row.evidence, row.implication]
             for row in artifact.finding_rows])
        println(io, "## Expansion Axis Summary")
        table(io, ["Axis", "Scenarios", "False Candidates", "Deferred",
                "Exact Recoveries", "Min Candidate F1"],
            [[row.expansion_axis, row.n_scenarios, row.n_false_candidates,
                row.n_deferred_candidates, row.n_exact_candidate_recoveries,
                row.min_candidate_cell_f1]
             for row in artifact.axis_summary_rows])
        println(io, "## Threshold Expansion Summary")
        table(io, ["Threshold", "Cells", "False-Add Specificity",
                "False-Negative Risk", "Explicit Null", "Construct Review"],
            [Any[row.threshold, row.n_scenario_threshold_cells,
                row.n_false_add_specificity_cells,
                row.n_false_negative_risk_cells,
                row.n_explicit_null_confirmation_cells,
                row.n_construct_review_cells]
             for row in artifact.threshold_expansion_summary_rows])
        println(io, "## Scenario Rows")
        table(io, ["Scenario", "Axis", "Expected Action",
                "Candidate Exact", "False Candidate", "Deferred",
                "Declared F1", "Candidate F1"],
            [[row.scenario, row.expansion_axis, row.expected_action,
                row.candidate_exact_recovery, row.false_candidate,
                row.deferred_candidate, row.declared_cell_f1,
                row.candidate_cell_f1]
             for row in artifact.scenario_rows])
        println(io, "## Scenario/Threshold Risk Rows")
        table(io, ["Scenario", "Axis", "Threshold", "Signal Power",
                "Weak Power", "False Promotion", "Competing Pass",
                "Risk"],
            [[row.scenario, row.expansion_axis, row.threshold,
                row.signal_power_rate, row.weak_power_rate,
                row.negative_control_false_promotion_rate,
                row.competing_model_pass_rate, row.risk_interpretation]
             for row in artifact.scenario_threshold_rows])
        println(io, "## Heldout Grid Link")
        table(io, ["Scenario", "Q Condition", "Expected Best",
                "Threshold Sensitive", "External Validation Needed"],
            [[row.scenario, row.q_condition, row.expected_best_model,
                row.threshold_profile_sensitive,
                row.external_construct_validation_needed]
             for row in artifact.heldout_link_rows])
        println(io, "## Input Artifacts")
        table(io, ["Artifact", "Path", "Schema", "Summary Passed"],
            [[row.artifact, row.path, row.schema, row.summary_passed]
             for row in artifact.input_artifacts])
        println(io, "## Boundary")
        println(io)
        println(io,
            "This artifact does not run the explicit null or Q-misspecification ",
            "MCMC simulations. It blocks public threshold, model-weight, ",
            "automatic Q-revision, and sparse-superiority claims until those ",
            "simulations are executed and category-calibration checks are joined.")
    end
    return path
end

function build_artifact(options)
    threshold_profile = load_required_json(options.threshold_profile_json,
        :threshold_profile)
    q_grid = load_required_json(options.q_grid_json, :q_grid)
    heldout_grid = load_required_json(options.heldout_grid_json, :heldout_grid)

    scenarios = q_scenario_rows(q_grid)
    scenario_thresholds = scenario_threshold_rows(scenarios, threshold_profile)
    axes = axis_summary_rows(scenarios)
    threshold_summary = threshold_expansion_summary_rows(scenario_thresholds)
    heldout_links = heldout_link_rows(heldout_grid)
    inputs = input_artifact_rows(options, threshold_profile, q_grid,
        heldout_grid)
    findings = finding_rows(axes, threshold_summary, threshold_profile)

    return (;
        schema = OUTPUT_SCHEMA,
        family = :mgmfrm,
        scope = :uto_style_threshold_q_misspecification_expansion,
        status = :local_threshold_q_misspecification_expansion_recorded,
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
        input_artifacts = inputs,
        scenario_rows = scenarios,
        axis_summary_rows = axes,
        scenario_threshold_rows = scenario_thresholds,
        threshold_expansion_summary_rows = threshold_summary,
        heldout_link_rows = heldout_links,
        finding_rows = findings,
        summary = (;
            passed = all(row.summary_passed for row in inputs),
            n_scenarios = length(scenarios),
            n_expansion_axes = length(axes),
            n_scenario_threshold_rows = length(scenario_thresholds),
            n_explicit_null_scenarios =
                count(row -> row.expansion_axis === :explicit_null, scenarios),
            n_false_add_axes =
                count(row -> occursin("false_add",
                    string(row.expansion_axis)), axes),
            n_false_drop_axes =
                count(row -> occursin("false_drop",
                    string(row.expansion_axis)), axes),
            n_weak_dimension_axes =
                count(row -> occursin("weak",
                    string(row.expansion_axis)), axes),
            threshold_2_false_add_specificity_cells =
                first(row.n_false_add_specificity_cells for row in
                    threshold_summary if row.threshold == 2.0),
            threshold_4_false_negative_risk_cells =
                first(row.n_false_negative_risk_cells for row in
                    threshold_summary if row.threshold == 4.0),
            no_public_fit_metric_claim = true,
            no_public_q_revision_claim = true,
            no_automatic_q_revision = true,
            no_public_model_weight_claim = true,
            no_sparse_superiority_claim = true,
            next_gate =
                :run_explicit_null_and_q_misspecification_mcmc_simulations,
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
    println("scenarios=", artifact.summary.n_scenarios,
        " axes=", artifact.summary.n_expansion_axes,
        " threshold_2_false_add_cells=",
        artifact.summary.threshold_2_false_add_specificity_cells,
        " threshold_4_false_negative_cells=",
        artifact.summary.threshold_4_false_negative_risk_cells,
        " next_gate=", artifact.summary.next_gate)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
