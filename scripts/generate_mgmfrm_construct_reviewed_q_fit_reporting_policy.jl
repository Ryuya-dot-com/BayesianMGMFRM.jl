#!/usr/bin/env julia

using JSON3
using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_construct_reviewed_q_fit_reporting_policy.json")
const INPUT_PATH =
    "test/fixtures/mgmfrm_fit_metric_threshold_sensitivity.json"
const INPUT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_fit_metric_threshold_sensitivity.v1"

include(joinpath(@__DIR__, "local_json.jl"))

const PROTOCOL = (;
    protocol_id = "mgmfrm_construct_reviewed_q_fit_reporting_policy_v1",
    review_kind = :local_construct_reviewed_q_fit_reporting_policy,
    publication_or_registration_action = false,
    local_only = true,
    input_fit_metric_artifact = INPUT_PATH,
    decision_target = :construct_reviewed_q_fit_reporting_policy,
    policy_scope = :local_diagnostic_appendix_only,
    thresholds = (;
        require_fit_metric_threshold_sensitivity_passed = true,
        require_threshold_profile_decision_surface = true,
        require_candidate_declared_indicator_conflicts_recorded = true,
        require_existing_mfrm_reference_comparison_recorded = true,
        require_parameter_shift_impact_recorded = true,
        require_no_single_threshold_profile_promoted = true,
        require_no_automatic_q_revision = true,
        require_no_public_q_revision_claim = true,
        require_no_public_fit_metric_claim = true,
        require_no_publication_or_registration_action = true,
    ),
)

function usage()
    return """
    Generate the local MGMFRM construct-reviewed Q fit reporting policy.

    This artifact consumes the fit-metric threshold sensitivity fixture and
    turns the raw MFRM/MGMFRM fit-surface comparisons into a local reporting
    policy. It records threshold-profile dependence, indicator conflicts, and
    direct-parameter shifts without promoting a single fit threshold, revising
    Q automatically, or making public fit claims.

    Usage:
      julia --project=. scripts/generate_mgmfrm_construct_reviewed_q_fit_reporting_policy.jl [--output PATH]
    """
end

function parse_args(args)
    output = DEFAULT_OUTPUT
    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--output"
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
    return output
end

project_version() = String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])
file_sha256(path::AbstractString) = bytes2hex(open(sha256, path))
fixture_path(path::AbstractString) = normpath(joinpath(ROOT, path))

as_string(value) = String(value)
as_float(value) = Float64(value)
as_int(value) = Int(value)
as_bool(value) = Bool(value)

function input_record(fixture)
    path = fixture_path(INPUT_PATH)
    return (;
        artifact = :mgmfrm_fit_metric_threshold_sensitivity,
        path = INPUT_PATH,
        exists = isfile(path),
        schema = as_string(fixture[:schema]),
        expected_schema = INPUT_SCHEMA,
        schema_matches = as_string(fixture[:schema]) == INPUT_SCHEMA,
        sha256 = file_sha256(path),
        summary_passed = as_bool(fixture[:summary][:passed]),
        next_gate = as_string(fixture[:summary][:next_gate]),
    )
end

function unique_strings(values)
    return sort!(collect(Set(as_string(value) for value in values)))
end

function mean_int(rows, key::Symbol)
    isempty(rows) && return 0.0
    return sum(as_int(row[key]) for row in rows) / length(rows)
end

function shift_band(mean_abs_shift::Real, max_abs_shift::Real)
    max_abs_shift >= 0.25 && return :large_local_shift
    mean_abs_shift >= 0.10 && return :large_mean_shift
    max_abs_shift >= 0.10 && return :moderate_local_shift
    mean_abs_shift > 0 && return :small_local_shift
    return :no_shift
end

function direction_from_delta(delta::Real)
    delta < 0 && return :candidate_lower_error
    delta > 0 && return :candidate_higher_error
    return :candidate_equal_error
end

function predictive_direction(row)
    lower_waic = as_bool(row[:candidate_lower_waic])
    lower_looic = as_bool(row[:candidate_lower_looic])
    lower_waic && lower_looic && return :candidate_lower_waic_and_looic
    !lower_waic && !lower_looic && return :declared_lower_waic_and_looic
    return :mixed_waic_looic
end

function parameter_shift_by_key(rows)
    output = Dict{Tuple{String, String}, Any}()
    for row in rows
        output[(as_string(row[:scenario]), as_string(row[:regime]))] = row
    end
    return output
end

function threshold_profile_rows(fixture)
    mgmfrm_thresholds = collect(fixture[:mgmfrm_threshold_evaluation_rows])
    mfrm_thresholds = collect(fixture[:mfrm_threshold_evaluation_rows])
    profiles = unique_strings(row[:profile] for row in fixture[:threshold_profiles])
    rows = NamedTuple[]
    for profile in profiles
        mgmfrm_rows = [row for row in mgmfrm_thresholds
                       if as_string(row[:profile]) == profile]
        mfrm_rows = [row for row in mfrm_thresholds
                     if as_string(row[:profile]) == profile]
        mgmfrm_flags = [as_int(row[:n_metric_flags]) for row in mgmfrm_rows]
        mfrm_passes = count(row -> as_bool(row[:profile_passed]), mfrm_rows)
        mgmfrm_passes =
            count(row -> as_bool(row[:metric_profile_passed_without_mcmc]),
                mgmfrm_rows)
        push!(rows, (;
            profile = Symbol(profile),
            n_mfrm_threshold_rows = length(mfrm_rows),
            n_mfrm_profile_passes = mfrm_passes,
            n_mfrm_profile_failures = length(mfrm_rows) - mfrm_passes,
            n_mgmfrm_threshold_rows = length(mgmfrm_rows),
            n_mgmfrm_metric_profile_passes_without_mcmc = mgmfrm_passes,
            n_mgmfrm_metric_profile_failures_without_mcmc =
                length(mgmfrm_rows) - mgmfrm_passes,
            min_mgmfrm_metric_flags = minimum(mgmfrm_flags),
            max_mgmfrm_metric_flags = maximum(mgmfrm_flags),
            mean_mgmfrm_metric_flags = mean_int(mgmfrm_rows, :n_metric_flags),
            mfrm_decision_is_threshold_sensitive =
                0 < mfrm_passes < length(mfrm_rows),
            mgmfrm_decision_is_threshold_sensitive =
                minimum(mgmfrm_flags) != maximum(mgmfrm_flags),
            reporting_role = :threshold_sensitivity_row_only,
        ))
    end
    return rows
end

function scenario_impact_rows(fixture)
    comparisons = collect(fixture[:metric_comparison_rows])
    shifts = parameter_shift_by_key(fixture[:parameter_shift_rows])
    rows = NamedTuple[]
    for row in comparisons
        scenario = as_string(row[:scenario])
        regime = as_string(row[:regime])
        shift = shifts[(scenario, regime)]
        mean_shift = as_float(row[:mean_abs_common_direct_parameter_shift])
        max_shift = as_float(row[:max_abs_common_direct_parameter_shift])
        push!(rows, (;
            scenario = Symbol(scenario),
            regime = Symbol(regime),
            predictive_direction = predictive_direction(row),
            calibration_direction =
                direction_from_delta(as_float(row[:delta_max_abs_calibration_error])),
            ppc_direction =
                direction_from_delta(as_float(row[:delta_max_abs_ppc_mean_error])),
            delta_elpd_waic = as_float(row[:delta_elpd_waic]),
            delta_elpd_loo = as_float(row[:delta_elpd_loo]),
            delta_max_abs_calibration_error =
                as_float(row[:delta_max_abs_calibration_error]),
            delta_max_abs_ppc_mean_error =
                as_float(row[:delta_max_abs_ppc_mean_error]),
            n_common_direct_parameters = as_int(row[:n_common_direct_parameters]),
            mean_abs_common_direct_parameter_shift = mean_shift,
            max_abs_common_direct_parameter_shift = max_shift,
            n_common_direct_parameters_shifted_gt_0_10 =
                as_int(shift[:n_common_direct_parameters_shifted_gt_0_10]),
            n_common_direct_parameters_shifted_gt_0_25 =
                as_int(shift[:n_common_direct_parameters_shifted_gt_0_25]),
            parameter_shift_band = shift_band(mean_shift, max_shift),
            q_revision_implication =
                :manual_construct_review_only_not_automatic_q_revision,
        ))
    end
    return rows
end

function indicator_conflict_rows(scenario_rows)
    rows = NamedTuple[]
    for row in scenario_rows
        predictive_candidate =
            row.predictive_direction === :candidate_lower_waic_and_looic
        calibration_candidate =
            row.calibration_direction === :candidate_lower_error
        ppc_candidate = row.ppc_direction === :candidate_lower_error
        n_conflicts = (predictive_candidate != calibration_candidate ? 1 : 0) +
            (predictive_candidate != ppc_candidate ? 1 : 0) +
            (calibration_candidate != ppc_candidate ? 1 : 0)
        push!(rows, (;
            scenario = row.scenario,
            regime = row.regime,
            predictive_candidate_preferred = predictive_candidate,
            calibration_candidate_preferred = calibration_candidate,
            ppc_candidate_preferred = ppc_candidate,
            n_indicator_pair_conflicts = n_conflicts,
            conflict_level = n_conflicts == 0 ? :none :
                n_conflicts == 1 ? :single_pair_conflict :
                :multiple_pair_conflicts,
            reporting_decision =
                :report_conflict_matrix_not_single_fit_decision,
        ))
    end
    return rows
end

function existing_model_reference_rows(fixture)
    rows = NamedTuple[]
    for row in fixture[:existing_model_comparison_rows]
        push!(rows, (;
            scenario = Symbol(as_string(row[:scenario])),
            regime = Symbol(as_string(row[:regime])),
            current_model = Symbol(as_string(row[:current_model])),
            current_lower_waic_than_mfrm =
                as_float(row[:delta_waic_mgmfrm_minus_mfrm]) < 0,
            current_lower_looic_than_mfrm =
                as_float(row[:delta_looic_mgmfrm_minus_mfrm]) < 0,
            current_calibration_error_lower_than_mfrm =
                as_float(row[:delta_max_abs_calibration_error]) < 0,
            current_ppc_error_lower_than_mfrm =
                as_float(row[:delta_max_abs_ppc_mean_error]) < 0,
            reference_role =
                :existing_mfrm_reference_only_not_model_superiority_claim,
        ))
    end
    return rows
end

function reporting_policy_rows()
    return [
        (surface = :mfrm_infit_outfit,
            reporting_role = :existing_model_reference,
            public_claim_allowed = false,
            required_context = :threshold_profile_and_sample_size_rule),
        (surface = :mgmfrm_waic_loo,
            reporting_role = :predictive_local_diagnostic,
            public_claim_allowed = false,
            required_context = :heldout_or_exact_followup_before_claim_use),
        (surface = :mgmfrm_ppc_calibration,
            reporting_role = :misfit_pattern_local_diagnostic,
            public_claim_allowed = false,
            required_context = :report_with_threshold_sensitivity),
        (surface = :direct_parameter_shift,
            reporting_role = :impact_screening,
            public_claim_allowed = false,
            required_context = :common_parameter_and_q_specific_parameter_split),
        (surface = :q_revision,
            reporting_role = :manual_construct_review_only,
            public_claim_allowed = false,
            required_context = :external_construct_validity_and_cv_policy),
        (surface = :single_fit_threshold,
            reporting_role = :not_promoted,
            public_claim_allowed = false,
            required_context = :no_single_threshold_profile_is_decisive),
    ]
end

function build_artifact()
    input_text = read(fixture_path(INPUT_PATH), String)
    fixture = JSON3.read(input_text)
    input = input_record(fixture)
    profile_rows = threshold_profile_rows(fixture)
    scenario_rows = scenario_impact_rows(fixture)
    conflict_rows = indicator_conflict_rows(scenario_rows)
    existing_rows = existing_model_reference_rows(fixture)
    policy_rows = reporting_policy_rows()

    all_input_ok = input.exists && input.schema_matches &&
        input.summary_passed &&
        input.next_gate == "construct_reviewed_q_fit_reporting_policy"
    all_conflicts_recorded =
        length(conflict_rows) == length(scenario_rows) &&
        any(row -> row.n_indicator_pair_conflicts > 0, conflict_rows)
    all_parameter_shifts_recorded =
        all(row -> row.n_common_direct_parameters > 0, scenario_rows) &&
        all(row -> row.max_abs_common_direct_parameter_shift >= 0, scenario_rows)
    threshold_profile_surface_recorded =
        length(profile_rows) == as_int(fixture[:summary][:n_threshold_profiles])
    existing_reference_recorded =
        length(existing_rows) ==
            as_int(fixture[:summary][:n_existing_model_comparison_rows])
    no_public_fit_metric_claim =
        as_bool(fixture[:summary][:no_public_fit_metric_claim])
    no_public_q_revision_claim =
        as_bool(fixture[:summary][:no_public_q_revision_claim])
    no_automatic_q_revision =
        as_bool(fixture[:summary][:no_automatic_q_revision])
    no_single_threshold_profile_promoted =
        as_bool(fixture[:summary][:no_single_threshold_profile_promoted])
    all_policy_rows_block_public_claims =
        all(row -> row.public_claim_allowed == false, policy_rows)
    n_reporting_evidence_cells =
        length(profile_rows) +
        length(scenario_rows) +
        length(conflict_rows) +
        length(existing_rows) +
        length(policy_rows)
    passed = all_input_ok &&
        threshold_profile_surface_recorded &&
        all_conflicts_recorded &&
        existing_reference_recorded &&
        all_parameter_shifts_recorded &&
        no_single_threshold_profile_promoted &&
        no_automatic_q_revision &&
        no_public_q_revision_claim &&
        no_public_fit_metric_claim &&
        all_policy_rows_block_public_claims

    return (;
        schema =
            "bayesianmgmfrm.mgmfrm_construct_reviewed_q_fit_reporting_policy.v1",
        family = :mgmfrm,
        scope = :construct_reviewed_q_fit_reporting_policy,
        status = :construct_reviewed_q_fit_reporting_policy_recorded,
        decision = :keep_fit_metrics_local_report_threshold_sensitivity_only,
        public_fit = true,
        experimental_public = true,
        fit_ready = true,
        local_only = true,
        public_fit_metric_claim = false,
        public_q_revision_claim = false,
        automatic_q_revision = false,
        publication_or_registration_action = false,
        package = (;
            name = "BayesianMGMFRM",
            version = project_version(),
            julia_version = string(VERSION),
        ),
        protocol = PROTOCOL,
        input_artifacts = [input],
        threshold_profile_decision_rows = profile_rows,
        scenario_impact_rows = scenario_rows,
        indicator_conflict_rows = conflict_rows,
        existing_model_reference_rows = existing_rows,
        reporting_policy_rows = policy_rows,
        decision_record = (;
            selected_decision =
                :keep_fit_metrics_local_report_threshold_sensitivity_only,
            existing_mfrm_fit_stats_used_as_reference = true,
            candidate_declared_indicator_conflicts_recorded =
                all_conflicts_recorded,
            parameter_shift_impact_recorded = all_parameter_shifts_recorded,
            mcmc_convergence_claim_allowed = false,
            automatic_q_revision_allowed = false,
            public_q_revision_claim_allowed = false,
            public_fit_metric_claim_allowed = false,
            required_followup = :heldout_prediction_or_external_validation_before_claims,
        ),
        summary = (;
            passed,
            publication_or_registration_action = false,
            local_only = true,
            all_input_artifacts_present = input.exists,
            all_expected_schemas = input.schema_matches,
            all_input_summaries_passed = input.summary_passed,
            fit_metric_threshold_sensitivity_passed = input.summary_passed,
            input_next_gate_matched = input.next_gate ==
                "construct_reviewed_q_fit_reporting_policy",
            threshold_profile_surface_recorded,
            indicator_conflicts_recorded = all_conflicts_recorded,
            existing_model_reference_recorded = existing_reference_recorded,
            parameter_shift_impact_recorded = all_parameter_shifts_recorded,
            all_policy_rows_block_public_claims,
            no_single_threshold_profile_promoted,
            no_automatic_q_revision,
            no_public_q_revision_claim,
            no_public_fit_metric_claim,
            public_fit_metric_claim_allowed = false,
            public_q_revision_claim_allowed = false,
            n_input_artifacts = 1,
            n_threshold_profile_decision_rows = length(profile_rows),
            n_scenario_impact_rows = length(scenario_rows),
            n_indicator_conflict_rows = length(conflict_rows),
            n_existing_model_reference_rows = length(existing_rows),
            n_reporting_policy_rows = length(policy_rows),
            n_reporting_evidence_cells,
            n_conflict_rows_with_conflicts =
                count(row -> row.n_indicator_pair_conflicts > 0, conflict_rows),
            n_moderate_or_larger_parameter_shift_rows =
                count(row -> row.parameter_shift_band in
                    (:moderate_local_shift, :large_mean_shift, :large_local_shift),
                    scenario_rows),
            n_blockers = 0,
            remaining_public_blockers = Symbol[],
            recommendation =
                :report_construct_reviewed_q_fit_metrics_as_local_appendix_only,
            next_gate = :heldout_prediction_or_external_validation_before_claims,
        ),
    )
end

function main(args)
    output = parse_args(args)
    artifact = build_artifact()
    write_artifact(output, artifact)
    println("wrote ", relpath(output, ROOT))
    println("passed=", artifact.summary.passed,
        " reporting_cells=", artifact.summary.n_reporting_evidence_cells,
        " conflicts=", artifact.summary.n_conflict_rows_with_conflicts)
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
