#!/usr/bin/env julia

using JSON3
using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_BASELINE = joinpath(
    ROOT, "test", "fixtures", "mgmfrm_tam_overlap_baseline.json")
const DEFAULT_EXECUTION = joinpath(
    ROOT, "test", "fixtures", "mgmfrm_tam_overlap_execution_review.json")
const DEFAULT_OUTPUT = joinpath(
    ROOT, "test", "fixtures", "mgmfrm_tam_comparison_policy_review.json")
const BASELINE_SCHEMA = "bayesianmgmfrm.mgmfrm_tam_overlap_baseline.v1"
const EXECUTION_SCHEMA =
    "bayesianmgmfrm.mgmfrm_tam_overlap_execution_review.v1"
const STRUCTURAL_TOLERANCE = 1.0e-10

include(joinpath(@__DIR__, "local_json.jl"))

function usage()
    return """
    Freeze a prospective TAM comparison policy and review the item-step adapter.

    The first TAM execution is treated as a retrospective pilot. Thresholds in
    this artifact apply prospectively to a future multi-replication comparison;
    they do not convert the existing pilot into confirmatory validation.

    Usage:
      julia --project=. scripts/generate_mgmfrm_tam_comparison_policy_review.jl [--baseline PATH] [--execution PATH] [--output PATH]
    """
end

function parse_args(args)
    baseline = DEFAULT_BASELINE
    execution = DEFAULT_EXECUTION
    output = DEFAULT_OUTPUT
    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--baseline"
            index < length(args) || error("--baseline requires a path")
            baseline = abspath(args[index + 1])
            index += 2
        elseif arg == "--execution"
            index < length(args) || error("--execution requires a path")
            execution = abspath(args[index + 1])
            index += 2
        elseif arg == "--output"
            index < length(args) || error("--output requires a path")
            output = abspath(args[index + 1])
            index += 2
        elseif arg in ("-h", "--help")
            println(usage())
            exit(0)
        else
            error("unknown argument: $arg")
        end
    end
    return (; baseline, execution, output)
end

project_version() =
    String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])

function file_sha256(path::AbstractString)
    return open(path, "r") do io
        bytes2hex(sha256(io))
    end
end

load_json(path::AbstractString) = JSON3.read(read(path, String))
as_string(value) = String(value)
as_float(value) = Float64(value)
as_int(value) = Int(value)

function checked_artifact(path::AbstractString, expected_schema::AbstractString)
    isfile(path) || error("required fixture missing: $(relpath(path, ROOT))")
    artifact = load_json(path)
    schema = as_string(artifact[:schema])
    schema == expected_schema || error("unexpected schema $schema")
    return artifact
end

function comparison_by_block(execution, block::AbstractString)
    rows = [row for row in execution[:parameter_comparison_rows]
        if as_string(row[:block]) == block]
    length(rows) == 1 || error("expected one comparison row for $block")
    return only(rows)
end

function threshold_row(execution, block::Symbol, metric::Symbol,
        direction::Symbol, threshold::Real)
    comparison = comparison_by_block(execution, String(block))
    observed = as_float(comparison[metric])
    passed = direction === :minimum ? observed >= threshold : observed <= threshold
    return (;
        block,
        metric,
        direction,
        threshold = Float64(threshold),
        observed,
        passed,
        evaluation_role = :retrospective_pilot_calibration_only,
        future_role = :prospective_multireplication_gate,
    )
end

function numerical_threshold_rows(execution)
    return [
        threshold_row(execution, :item_difficulty, :pearson_correlation,
            :minimum, 0.95),
        threshold_row(execution, :item_difficulty, :mean_abs_difference,
            :maximum, 0.15),
        threshold_row(execution, :item_difficulty, :max_abs_difference,
            :maximum, 0.30),
        threshold_row(execution, :rater_severity, :pearson_correlation,
            :minimum, 0.95),
        threshold_row(execution, :rater_severity, :mean_abs_difference,
            :maximum, 0.15),
        threshold_row(execution, :rater_severity, :max_abs_difference,
            :maximum, 0.30),
        threshold_row(execution, :item_step, :pearson_correlation,
            :minimum, 0.80),
        threshold_row(execution, :item_step, :mean_abs_difference,
            :maximum, 0.25),
        threshold_row(execution, :item_step, :max_abs_difference,
            :maximum, 0.60),
    ]
end

function structural_check(check::Symbol, observed, expected, passed::Bool)
    return (;
        check,
        observed,
        expected,
        passed,
        role = :parameterization_equivalence_precondition,
    )
end

function structural_check_rows(execution)
    audit = execution[:tam_formula_adapter_audit]
    return [
        structural_check(:formula_expands_with_pseudo_facet,
            as_string(audit[:fitted_formulaA]),
            "~item + rater + item:step + psf",
            as_string(audit[:fitted_formulaA]) ==
                "~item + rater + item:step + psf"),
        structural_check(:tam_design_rows,
            as_int(audit[:n_design_rows]), 20,
            as_int(audit[:n_design_rows]) == 20),
        structural_check(:score_categories,
            as_int(audit[:n_score_categories]), 4,
            as_int(audit[:n_score_categories]) == 4),
        structural_check(:independent_xsi_columns,
            as_int(audit[:n_independent_xsi]), 22,
            as_int(audit[:n_independent_xsi]) == 22),
        structural_check(:expanded_xsi_rows,
            as_int(audit[:n_expanded_xsi]), 29,
            as_int(audit[:n_expanded_xsi]) == 29),
        structural_check(:item_step_constraint_rows,
            as_int(audit[:n_item_step_constraint_rows]), 5,
            as_int(audit[:n_item_step_constraint_rows]) == 5),
        structural_check(:rater_sum_constraint,
            as_float(audit[:rater_sum_abs]), STRUCTURAL_TOLERANCE,
            as_float(audit[:rater_sum_abs]) <= STRUCTURAL_TOLERANCE),
        structural_check(:pseudo_facet_zero_effect,
            as_float(audit[:pseudo_facet_max_abs]), STRUCTURAL_TOLERANCE,
            as_float(audit[:pseudo_facet_max_abs]) <= STRUCTURAL_TOLERANCE),
        structural_check(:item_step_sum_by_item,
            as_float(audit[:item_step_sum_max_abs]), STRUCTURAL_TOLERANCE,
            as_float(audit[:item_step_sum_max_abs]) <= STRUCTURAL_TOLERANCE),
        structural_check(:category_intercept_reconstruction,
            as_float(audit[:category_intercept_reconstruction_max_abs_error]),
            STRUCTURAL_TOLERANCE,
            as_float(audit[:category_intercept_reconstruction_max_abs_error]) <=
                STRUCTURAL_TOLERANCE),
    ]
end

function block_decision_rows(thresholds)
    return [(;
        block,
        n_thresholds = count(row -> row.block == block, thresholds),
        n_passed = count(row -> row.block == block && row.passed, thresholds),
        all_pilot_thresholds_passed =
            all(row -> row.block != block || row.passed, thresholds),
        interpretation = block === :item_step ?
            :adapter_structure_confirmed_but_pilot_precision_below_future_gate :
            :pilot_consistent_with_future_gate_not_confirmatory,
    ) for block in (:item_difficulty, :rater_severity, :item_step)]
end

function build_artifact(baseline_path::AbstractString,
        execution_path::AbstractString)
    baseline = checked_artifact(baseline_path, BASELINE_SCHEMA)
    execution = checked_artifact(execution_path, EXECUTION_SCHEMA)
    thresholds = numerical_threshold_rows(execution)
    structural = structural_check_rows(execution)
    blocks = block_decision_rows(thresholds)
    structural_passed = all(row -> row.passed, structural)
    numerical_passed = all(row -> row.passed, thresholds)
    return (;
        schema = "bayesianmgmfrm.mgmfrm_tam_comparison_policy_review.v1",
        family = :mfrm,
        scope = :tam_comparison_policy_and_item_step_adapter_review,
        status = :prospective_thresholds_frozen_adapter_structure_confirmed,
        decision =
            :run_multireplication_tam_comparison_keep_external_claim_blocked,
        local_only = true,
        external_software = :tam,
        external_software_validation_completed = false,
        public_claim_release_allowed = false,
        publication_or_registration_action = false,
        package = (;
            name = "BayesianMGMFRM",
            version = project_version(),
            julia_version = string(VERSION),
        ),
        protocol = (;
            protocol_id = :mgmfrm_tam_comparison_policy_review_v1,
            generator =
                "scripts/generate_mgmfrm_tam_comparison_policy_review.jl",
            generator_source_sha256 = file_sha256(@__FILE__),
            baseline_artifact = relpath(baseline_path, ROOT),
            baseline_artifact_sha256 = file_sha256(baseline_path),
            execution_artifact = relpath(execution_path, ROOT),
            execution_artifact_sha256 = file_sha256(execution_path),
            threshold_freeze_order =
                :after_initial_pilot_before_multireplication_execution,
            current_pilot_role = :retrospective_calibration_only,
            future_runs_role = :prospective_confirmatory_gate,
            structural_tolerance = STRUCTURAL_TOLERANCE,
        ),
        relationship_to_tam = (;
            overlapping_model =
                :unidimensional_many_facet_rasch_partial_credit,
            shared_terms = [
                :person_location,
                :item_difficulty,
                :rater_severity,
                :item_specific_category_steps,
            ],
            shared_constraints = [
                :unit_discrimination,
                :sum_to_zero_rater_effects,
                :sum_to_zero_item_steps_within_item,
            ],
            estimator_difference =
                :tam_marginal_maximum_likelihood_vs_package_bayesian_posterior,
            current_comparison_target = :known_truth_recovery_not_direct_estimate_equality,
            excluded_generalizations = [
                :free_item_discrimination,
                :rater_consistency,
                :multidimensional_fixed_q_loading,
                :generalized_gmfrm_or_mgmfrm_validation,
            ],
        ),
        item_step_adapter = (;
            tam_expanded_parameter = :item_colon_step,
            package_parameter = :partial_credit_item_step,
            mapping = :same_item_and_adjacent_step_after_tam_constraint_expansion,
            tam_category_intercept_equation =
                :k_times_item_plus_rater_plus_cumulative_item_step,
            package_adjacent_increment_equation =
                :ability_minus_item_minus_rater_minus_item_step,
            sign_convention =
                :tam_AXsi_uses_cumulative_difficulty_intercepts_subtracted_from_ability,
            structure_review_completed = structural_passed,
            numerical_precision_review_completed = false,
        ),
        structural_check_rows = structural,
        numerical_threshold_rows = thresholds,
        block_decision_rows = blocks,
        claim_limits = [
            :thresholds_frozen_after_first_pilot_not_before_it,
            :single_pilot_cannot_confirm_external_software_agreement,
            :item_step_pilot_misses_future_correlation_and_mean_absolute_difference_gates,
            :future_multireplication_results_required,
            :no_facets_or_conquest_execution,
            :no_generalized_gmfrm_or_mgmfrm_external_validation,
            :no_public_claim_release,
        ],
        summary = (;
            passed = structural_passed && !numerical_passed,
            structural_adapter_checks_passed = structural_passed,
            prospective_thresholds_frozen = true,
            current_pilot_all_numerical_thresholds_passed = numerical_passed,
            current_pilot_item_and_rater_thresholds_passed =
                all(row -> row.block == :item_step || row.passed, thresholds),
            current_pilot_item_step_thresholds_passed =
                all(row -> row.block != :item_step || row.passed, thresholds),
            n_structural_checks = length(structural),
            n_structural_checks_passed = count(row -> row.passed, structural),
            n_numerical_thresholds = length(thresholds),
            n_numerical_thresholds_passed = count(row -> row.passed, thresholds),
            external_software_validation_completed = false,
            public_claim_release_allowed = false,
            next_gate = :run_predeclared_multireplication_tam_comparison,
        ),
    )
end

function main(args)
    parsed = parse_args(args)
    artifact = build_artifact(parsed.baseline, parsed.execution)
    write_artifact(parsed.output, artifact)
    println("wrote ", relpath(parsed.output, ROOT))
    println(
        "structural_pass=", artifact.summary.structural_adapter_checks_passed,
        " numerical_pass=", artifact.summary.current_pilot_all_numerical_thresholds_passed,
        " thresholds=", artifact.summary.n_numerical_thresholds,
    )
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
