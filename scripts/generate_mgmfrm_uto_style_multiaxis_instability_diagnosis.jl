#!/usr/bin/env julia

using Dates
using JSON3
using SHA
using Statistics
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_BUDGET_STABILITY_JSON =
    joinpath(ROOT, "artifacts", "uto_style_q_category_budget_stability",
        "uto_style_q_category_budget_stability.json")
const DEFAULT_REPLICATED_Q_CATEGORY_JSON =
    joinpath(ROOT, "artifacts",
        "uto_style_replicated_q_misspecification_category_bridge",
        "uto_style_replicated_q_misspecification_category_bridge.json")
const DEFAULT_Q_MCMC_JSON =
    joinpath(ROOT, "artifacts", "uto_style_q_misspecification_mcmc_simulations",
        "uto_style_q_misspecification_mcmc_simulations.json")
const DEFAULT_CATEGORY_BRIDGE_JSON =
    joinpath(ROOT, "artifacts", "uto_style_category_calibration_bridge",
        "uto_style_category_calibration_bridge.json")
const DEFAULT_THRESHOLD_PROFILE_JSON =
    joinpath(ROOT, "artifacts",
        "uto_style_threshold_false_alarm_power_profiles",
        "uto_style_threshold_false_alarm_power_profiles.json")
const DEFAULT_MCMC_BUDGET_JSON =
    joinpath(ROOT, "artifacts", "uto_style_mcmc_budget_bridge",
        "uto_style_mcmc_budget_bridge.json")
const DEFAULT_PRIOR_SENSITIVITY_JSON =
    joinpath(ROOT, "artifacts", "uto_style_prior_sensitivity",
        "uto_style_prior_sensitivity.json")
const DEFAULT_OUTPUT_JSON =
    joinpath(ROOT, "artifacts", "uto_style_multiaxis_instability_diagnosis",
        "uto_style_multiaxis_instability_diagnosis.json")
const DEFAULT_OUTPUT_MD =
    joinpath(ROOT, "artifacts", "uto_style_multiaxis_instability_diagnosis",
        "uto_style_multiaxis_instability_diagnosis.md")

include(joinpath(@__DIR__, "local_json.jl"))

const OUTPUT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_uto_style_multiaxis_instability_diagnosis.v1"

function usage()
    return """
    Synthesize the local MGMFRM threshold/category/Q diagnostics into a
    multi-axis instability diagnosis.

    This script reads existing artifacts only. It does not run MCMC and does
    not promote public threshold, model-weight, sparse-superiority, or Q
    revision claims.

    Usage:
      julia --project=. scripts/generate_mgmfrm_uto_style_multiaxis_instability_diagnosis.jl [options]

    Options:
      --budget-stability-json PATH
      --replicated-q-category-json PATH
      --q-mcmc-json PATH
      --category-bridge-json PATH
      --threshold-profile-json PATH
      --mcmc-budget-json PATH
      --prior-sensitivity-json PATH
      --output-json PATH
      --output-md PATH
    """
end

function parse_args(args)
    budget_stability_json = DEFAULT_BUDGET_STABILITY_JSON
    replicated_q_category_json = DEFAULT_REPLICATED_Q_CATEGORY_JSON
    q_mcmc_json = DEFAULT_Q_MCMC_JSON
    category_bridge_json = DEFAULT_CATEGORY_BRIDGE_JSON
    threshold_profile_json = DEFAULT_THRESHOLD_PROFILE_JSON
    mcmc_budget_json = DEFAULT_MCMC_BUDGET_JSON
    prior_sensitivity_json = DEFAULT_PRIOR_SENSITIVITY_JSON
    output_json = DEFAULT_OUTPUT_JSON
    output_md = DEFAULT_OUTPUT_MD

    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--budget-stability-json"
            index < length(args) ||
                error("--budget-stability-json requires a path")
            budget_stability_json = abspath(args[index + 1])
            index += 2
        elseif arg == "--replicated-q-category-json"
            index < length(args) ||
                error("--replicated-q-category-json requires a path")
            replicated_q_category_json = abspath(args[index + 1])
            index += 2
        elseif arg == "--q-mcmc-json"
            index < length(args) || error("--q-mcmc-json requires a path")
            q_mcmc_json = abspath(args[index + 1])
            index += 2
        elseif arg == "--category-bridge-json"
            index < length(args) ||
                error("--category-bridge-json requires a path")
            category_bridge_json = abspath(args[index + 1])
            index += 2
        elseif arg == "--threshold-profile-json"
            index < length(args) ||
                error("--threshold-profile-json requires a path")
            threshold_profile_json = abspath(args[index + 1])
            index += 2
        elseif arg == "--mcmc-budget-json"
            index < length(args) ||
                error("--mcmc-budget-json requires a path")
            mcmc_budget_json = abspath(args[index + 1])
            index += 2
        elseif arg == "--prior-sensitivity-json"
            index < length(args) ||
                error("--prior-sensitivity-json requires a path")
            prior_sensitivity_json = abspath(args[index + 1])
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
    return (;
        budget_stability_json,
        replicated_q_category_json,
        q_mcmc_json,
        category_bridge_json,
        threshold_profile_json,
        mcmc_budget_json,
        prior_sensitivity_json,
        output_json,
        output_md,
    )
end

project_version() =
    String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])
file_sha256(path::AbstractString) = bytes2hex(open(sha256, path))
rel(path::AbstractString) = relpath(path, ROOT)
round3(value) = round(Float64(value); digits = 3)
round4(value) = round(Float64(value); digits = 4)

function read_json(path::AbstractString)
    isfile(path) || error("required artifact is missing: $path")
    return JSON3.read(read(path, String))
end

str(value) = string(value)
num(value) = Float64(value)
asbool(value) = Bool(value)

function finite_mean(values)
    finite = [Float64(value) for value in values if isfinite(Float64(value))]
    isempty(finite) && return NaN
    return mean(finite)
end

function finite_range(values)
    finite = [Float64(value) for value in values if isfinite(Float64(value))]
    isempty(finite) && return (NaN, NaN)
    return (minimum(finite), maximum(finite))
end

function count_axis(rows, axis::AbstractString)
    count(row -> str(row.axis) == axis, rows)
end

function min_category_count(model_rows)
    values = Int[]
    for row in model_rows
        haskey(row, :min_observed_category_count) || continue
        push!(values, Int(row.min_observed_category_count))
    end
    isempty(values) && return missing
    return minimum(values)
end

function max_category_count(model_rows)
    values = Int[]
    for row in model_rows
        haskey(row, :min_observed_category_count) || continue
        push!(values, Int(row.min_observed_category_count))
    end
    isempty(values) && return missing
    return maximum(values)
end

function axis_summary_rows(budget)
    rows = NamedTuple[]
    axes = sort(unique(str(row.axis) for row in budget.scenario_cell_rows))
    for axis in axes
        group = [row for row in budget.scenario_cell_rows if str(row.axis) == axis]
        values = [num(row.candidate_delta_log_score_vs_null) for row in group]
        lo, hi = finite_range(values)
        push!(rows, (;
            axis = Symbol(axis),
            n_cells = length(group),
            min_candidate_delta_log_score = round3(lo),
            max_candidate_delta_log_score = round3(hi),
            mean_candidate_delta_log_score = round3(finite_mean(values)),
            n_candidate_category_caveats =
                count(row -> asbool(row.candidate_predictive_category_caveat),
                    group),
            n_best_truth_oracle =
                count(row -> str(row.observed_best_model) ==
                    "truth_q_source_oracle", group),
            n_best_competing_structured =
                count(row -> str(row.observed_best_model) in
                    ("rotated_wrong_q_mgmfrm_mcmc", "scalar_gmfrm_mcmc"),
                    group),
            public_claim_allowed = false,
        ))
    end
    return rows
end

function critical_cell_rows(budget)
    rows = NamedTuple[]
    for row in budget.budget_delta_rows
        num(row.n_threshold_risk_changes) > 0 || continue
        push!(rows, (;
            seed = Int(row.seed),
            scenario = Symbol(str(row.scenario)),
            axis = Symbol(str(row.axis)),
            baseline_budget = Symbol(str(row.baseline_budget)),
            comparison_budget = Symbol(str(row.comparison_budget)),
            delta_candidate_log_score = round3(row.delta_candidate_log_score),
            delta_candidate_minus_declared_log_score =
                round3(row.delta_candidate_minus_declared_log_score),
            delta_candidate_brier = round4(row.delta_candidate_brier),
            delta_candidate_category_total_variation =
                round4(row.delta_candidate_category_total_variation),
            delta_candidate_cumulative_l1 =
                round4(row.delta_candidate_cumulative_l1),
            n_threshold_risk_changes = Int(row.n_threshold_risk_changes),
            changed_threshold_risks =
                [Symbol(str(value)) for value in row.changed_threshold_risks],
            public_claim_allowed = false,
        ))
    end
    return rows
end

function mechanism_row(hypothesis, plausibility, score, evidence,
        counterevidence, next_probe)
    return (;
        hypothesis,
        plausibility,
        evidence_score = score,
        evidence,
        counterevidence,
        next_probe,
        public_claim_allowed = false,
    )
end

function mechanism_rows(inputs, axis_rows, critical_rows)
    budget = inputs.budget
    replicated = inputs.replicated
    threshold = inputs.threshold
    category = inputs.category
    mcmc_budget = inputs.mcmc_budget
    prior = inputs.prior

    false_add_cells = [row for row in budget.scenario_cell_rows
        if str(row.axis) == "false_add"]
    false_drop_cells = [row for row in budget.scenario_cell_rows
        if str(row.axis) == "false_drop"]
    rater_noise_cells = [row for row in budget.scenario_cell_rows
        if str(row.axis) == "q_misspecification_rater_noise"]
    false_add_caveats =
        count(row -> asbool(row.candidate_predictive_category_caveat),
            false_add_cells)
    false_add_candidate_minus_declared =
        finite_mean(row.candidate_minus_declared_log_score
            for row in false_add_cells)
    false_drop_values =
        [num(row.candidate_delta_log_score_vs_null)
         for row in false_drop_cells]
    false_drop_lo, false_drop_hi = finite_range(false_drop_values)
    rater_values =
        [num(row.candidate_delta_log_score_vs_null)
         for row in rater_noise_cells]
    rater_lo, rater_hi = finite_range(rater_values)
    min_count = min_category_count(budget.model_score_rows)
    max_count = max_category_count(budget.model_score_rows)

    return [
        mechanism_row(
            :sampler_budget_instability,
            :high,
            5,
            string("last budget warning rows = ",
                budget.summary.last_budget_mcmc_warning_rows,
                "; risk-label changes = ",
                budget.summary.n_threshold_risk_changes,
                "; threshold 2 false-promotion rate moved to ",
                budget.summary.last_budget_threshold_2_candidate_false_promotion_rate),
            string("Earlier source-aligned MCMC-budget bridge had ",
                mcmc_budget.summary.n_direction_changes_from_baseline,
                " direction changes from baseline."),
            :run_pre_registered_larger_budget_on_critical_cells,
        ),
        mechanism_row(
            :threshold_cutoff_sensitivity,
            :high,
            5,
            string("threshold 2 false-promotion rate moved 0.2 -> ",
                budget.summary.last_budget_threshold_2_candidate_false_promotion_rate,
                "; threshold 4 false-negative rate = ",
                budget.summary.last_budget_threshold_4_false_negative_rate,
                "; competing pass at threshold 2 = ",
                threshold.summary.threshold_2_max_competing_model_pass_rate,
                "; weak power at threshold 4 = ",
                threshold.summary.threshold_4_weak_power_rate),
            "Thresholds are screening profiles, not validated public cutoffs.",
            :estimate_false_alarm_power_curves_by_scenario_and_metric,
        ),
        mechanism_row(
            :category_calibration_mismatch,
            :medium_high,
            4,
            string("replicated Q/category caveat cells = ",
                replicated.summary.n_candidate_predictive_category_caveat_cells,
                "; false-add caveats across budget cells = ",
                false_add_caveats, "/", length(false_add_cells)),
            string("Source-aligned category bridge had ",
                category.summary.n_predictive_gain_with_category_caveat_cells,
                " predictive/category-caveat cells."),
            :require_predictive_gain_brier_tv_and_cumulative_alignment,
        ),
        mechanism_row(
            :false_add_q_specificity,
            :high,
            5,
            string("false-add candidate dLogScore was positive vs Null in ",
                length(false_add_cells), " budget cells, but mean candidate - ",
                "declared dLogScore = ",
                round3(false_add_candidate_minus_declared),
                " and false-add caveats = ", false_add_caveats),
            "False-add signal is not evidence for automatic Q expansion.",
            :add_false_add_specificity_grid_with_noise_and_category_checks,
        ),
        mechanism_row(
            :false_drop_power_seed_variability,
            :high,
            4,
            string("false-drop candidate dLogScore range = [",
                round3(false_drop_lo), ", ", round3(false_drop_hi),
                "]; threshold 4 false-negative rate = ",
                budget.summary.last_budget_threshold_4_false_negative_rate),
            "One seed shows strong recovery while another remains negative.",
            :run_split_repeated_false_drop_power_and_sample_size_scaling,
        ),
        mechanism_row(
            :rater_noise_or_competing_structure,
            :high,
            4,
            string("rater-noise candidate dLogScore range = [",
                round3(rater_lo), ", ", round3(rater_hi),
                "]; at least one rater-noise cell chose rotated/wrong Q as best."),
            "Rater-noise and Q-structure can be confounded in small data.",
            :add_rater_noise_ablation_and_competing_wrong_q_controls,
        ),
        mechanism_row(
            :heldout_split_and_category_sparsity,
            :high,
            4,
            string("minimum observed heldout category count across model rows = ",
                min_count, " (max minimum count = ", max_count,
                "); risk-label changes occurred in ",
                length(critical_rows), " seed-scenario cells."),
            "Current cells are intentionally small local diagnostics.",
            :use_repeated_stratified_splits_and_min_category_support_rules,
        ),
        mechanism_row(
            :prior_profile_only,
            :low,
            2,
            string("prior-sensitivity artifact passed = ",
                prior.summary.passed),
            "Prior profiles did not reverse the source-aligned recovery pattern.",
            :keep_prior_sensitivity_as_secondary_not_primary_explanation,
        ),
        mechanism_row(
            :general_mgmfrm_impossibility,
            :low,
            1,
            "Strong source-aligned conditions recover the expected direction.",
            "The issue is conditional instability, not a general impossibility result.",
            :avoid_broad_negative_or_positive_mgmfrm_claims,
        ),
    ]
end

function recommendation_rows()
    return [
        (gate = :sampler_remediation,
            action =
                :rerun_critical_cells_with_pre_registered_larger_chains,
            rationale =
                "All 32/32 MCMC rows still have warnings; thresholds cannot be public while diagnostics remain unresolved.",
            public_claim_allowed = false),
        (gate = :split_robustness,
            action =
                :repeat_holdout_splits_with_min_category_support_constraints,
            rationale =
                "Risk labels moved under budget changes and heldout category counts can be as low as 1.",
            public_claim_allowed = false),
        (gate = :sample_size_scaling,
            action =
                :rerun_false_add_false_drop_and_rater_noise_at_larger_n,
            rationale =
                "False-drop and rater-noise axes show large seed ranges in candidate dLogScore.",
            public_claim_allowed = false),
        (gate = :threshold_policy,
            action =
                :require_predictive_gain_category_alignment_specificity_power_and_budget_stability,
            rationale =
                "Threshold 2 has false-promotion risk and threshold 4 has false-negative risk.",
            public_claim_allowed = false),
        (gate = :q_revision_policy,
            action =
                :separate_q_suggestion_from_automatic_q_revision,
            rationale =
                "False-add candidates can beat Null while losing to declared Q and showing category caveats.",
            public_claim_allowed = false),
    ]
end

function input_artifact_rows(options)
    return [
        (artifact = :q_category_budget_stability,
            path = rel(options.budget_stability_json),
            sha256 = file_sha256(options.budget_stability_json)),
        (artifact = :replicated_q_misspecification_category_bridge,
            path = rel(options.replicated_q_category_json),
            sha256 = file_sha256(options.replicated_q_category_json)),
        (artifact = :q_misspecification_mcmc_simulations,
            path = rel(options.q_mcmc_json),
            sha256 = file_sha256(options.q_mcmc_json)),
        (artifact = :category_calibration_bridge,
            path = rel(options.category_bridge_json),
            sha256 = file_sha256(options.category_bridge_json)),
        (artifact = :threshold_false_alarm_power_profiles,
            path = rel(options.threshold_profile_json),
            sha256 = file_sha256(options.threshold_profile_json)),
        (artifact = :mcmc_budget_bridge,
            path = rel(options.mcmc_budget_json),
            sha256 = file_sha256(options.mcmc_budget_json)),
        (artifact = :prior_sensitivity,
            path = rel(options.prior_sensitivity_json),
            sha256 = file_sha256(options.prior_sensitivity_json)),
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
        println(io, "# Uto-Style Multi-Axis Instability Diagnosis")
        println(io)
        println(io, "- Generated at: `", artifact.generated_at, "`")
        println(io, "- Local only: `true`")
        println(io, "- Public claims allowed: `false`")
        println(io)
        println(io, "## Interpretation")
        println(io)
        println(io,
            "This report treats the current instability as multi-causal. It ",
            "does not choose one explanation prematurely; it ranks explanations ",
            "that are supported by the local artifacts and separates them from ",
            "low-plausibility or still-untested explanations.")
        println(io)
        println(io, "## Hypotheses")
        table(io, ["Hypothesis", "Plausibility", "Score", "Evidence",
                "Counterevidence", "Next Probe"],
            [[row.hypothesis, row.plausibility, row.evidence_score,
                row.evidence, row.counterevidence, row.next_probe]
             for row in artifact.mechanism_rows])
        println(io, "## Axis Summary")
        table(io, ["Axis", "Cells", "Min dLog", "Max dLog", "Mean dLog",
                "Caveats", "Truth Best", "Competing Best"],
            [[row.axis, row.n_cells, row.min_candidate_delta_log_score,
                row.max_candidate_delta_log_score,
                row.mean_candidate_delta_log_score,
                row.n_candidate_category_caveats,
                row.n_best_truth_oracle,
                row.n_best_competing_structured]
             for row in artifact.axis_summary_rows])
        println(io, "## Critical Budget-Sensitive Cells")
        table(io, ["Seed", "Scenario", "Axis", "dCandidateLog",
                "dCand-DeclLog", "dBrier", "dTV", "dCumL1", "Changes"],
            [[row.seed, row.scenario, row.axis,
                row.delta_candidate_log_score,
                row.delta_candidate_minus_declared_log_score,
                row.delta_candidate_brier,
                row.delta_candidate_category_total_variation,
                row.delta_candidate_cumulative_l1,
                row.n_threshold_risk_changes]
             for row in artifact.critical_cell_rows])
        println(io, "## Recommended Gates")
        table(io, ["Gate", "Action", "Rationale"],
            [[row.gate, row.action, row.rationale]
             for row in artifact.recommendation_rows])
        println(io, "## Boundary")
        println(io)
        println(io,
            "This is a synthesis of local diagnostics. It blocks public fit ",
            "thresholds, automatic Q revision, model weights, and sparse ",
            "superiority claims until the proposed gates pass.")
    end
    return path
end

function build_artifact(options)
    inputs = (;
        budget = read_json(options.budget_stability_json),
        replicated = read_json(options.replicated_q_category_json),
        q_mcmc = read_json(options.q_mcmc_json),
        category = read_json(options.category_bridge_json),
        threshold = read_json(options.threshold_profile_json),
        mcmc_budget = read_json(options.mcmc_budget_json),
        prior = read_json(options.prior_sensitivity_json),
    )
    axis_rows = axis_summary_rows(inputs.budget)
    critical_rows = critical_cell_rows(inputs.budget)
    mechanisms = mechanism_rows(inputs, axis_rows, critical_rows)
    recommendations = recommendation_rows()
    high_rows = [row for row in mechanisms
        if row.plausibility in (:high, :medium_high)]
    return (;
        schema = OUTPUT_SCHEMA,
        family = :mgmfrm,
        scope = :uto_style_multiaxis_instability_diagnosis,
        status = :local_multiaxis_instability_diagnosis_recorded,
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
        mechanism_rows = mechanisms,
        axis_summary_rows = axis_rows,
        critical_cell_rows = critical_rows,
        recommendation_rows = recommendations,
        summary = (;
            passed = true,
            n_input_artifacts = 7,
            n_mechanisms = length(mechanisms),
            n_high_or_medium_high_mechanisms = length(high_rows),
            n_axis_summary_rows = length(axis_rows),
            n_critical_budget_sensitive_cells = length(critical_rows),
            highest_priority_mechanisms =
                [row.hypothesis for row in mechanisms if row.evidence_score >= 5],
            no_public_fit_metric_claim = true,
            no_public_q_revision_claim = true,
            no_automatic_q_revision = true,
            no_public_model_weight_claim = true,
            no_sparse_superiority_claim = true,
            next_gate = :critical_cell_sampler_split_and_sample_size_grid,
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
    println("mechanisms=", artifact.summary.n_mechanisms,
        " high_or_medium_high=",
        artifact.summary.n_high_or_medium_high_mechanisms,
        " critical_cells=",
        artifact.summary.n_critical_budget_sensitive_cells,
        " next_gate=", artifact.summary.next_gate)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
