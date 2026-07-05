#!/usr/bin/env julia

using JSON3
using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_heldout_prediction_simulation_grid.json")

include(joinpath(@__DIR__, "local_json.jl"))

const INPUT_ARTIFACTS = [
    (name = :mgmfrm_validation_split_model_comparison_policy,
        path =
            "test/fixtures/mgmfrm_validation_split_model_comparison_policy.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_validation_split_model_comparison_policy.v1"),
    (name = :mgmfrm_fit_metric_threshold_sensitivity,
        path =
            "test/fixtures/mgmfrm_fit_metric_threshold_sensitivity.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_fit_metric_threshold_sensitivity.v1"),
    (name = :mgmfrm_empirical_q_matrix_recovery_simulation_grid,
        path =
            "test/fixtures/mgmfrm_empirical_q_matrix_recovery_simulation_grid.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_empirical_q_matrix_recovery_simulation_grid.v1"),
    (name = :mgmfrm_construct_reviewed_q_fit_reporting_policy,
        path =
            "test/fixtures/mgmfrm_construct_reviewed_q_fit_reporting_policy.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_construct_reviewed_q_fit_reporting_policy.v1"),
]

const PROTOCOL = (;
    protocol_id = "mgmfrm_heldout_prediction_simulation_grid_v1",
    review_kind = :local_heldout_prediction_simulation_grid,
    publication_or_registration_action = false,
    local_only = true,
    policy_scope =
        :pre_execution_grid_for_heldout_mgmfrm_prediction_comparison,
    decision_target =
        :fix_scenarios_splits_metrics_and_threshold_sensitivity_before_execution,
    thresholds = (;
        require_validation_split_model_comparison_policy_passed = true,
        require_fit_metric_threshold_sensitivity_passed = true,
        require_empirical_q_matrix_recovery_simulation_grid_passed = true,
        require_construct_reviewed_q_fit_reporting_policy_passed = true,
        require_split_policy_next_gate_matched = true,
        require_predeclared_splits_carried_forward = true,
        require_all_comparison_models_planned = true,
        require_all_scenarios_predeclared = true,
        require_all_metric_surface_values_finite = true,
        require_threshold_impact_rows_recorded = true,
        require_leakage_guards_carried_forward = true,
        require_all_claim_rules_block_public_claims = true,
        require_no_public_fit_metric_claim = true,
        require_no_public_model_weight_claim = true,
        require_no_sparse_superiority_claim = true,
        require_no_publication_or_registration_action = true,
    ),
)

const MODEL_ORDER = [
    :scalar_gmfrm_baseline,
    :confirmatory_mgmfrm_current_q,
    :sparse_mgmfrm_current_q,
    :construct_reviewed_revised_q_mgmfrm,
    :null_or_intercept_reference,
]

const METRIC_ORDER = [
    :heldout_log_predictive_density,
    :heldout_response_accuracy_or_rank_score,
    :heldout_calibration_error,
    :posterior_predictive_discrepancy,
    :simulation_parameter_recovery_shift,
]

const THRESHOLD_PROFILES = [
    (profile = :strict_bayesian_workflow,
        role = :publication_grade_screening_sensitivity,
        used_for_claim = false),
    (profile = :screening_workflow,
        role = :local_screening_sensitivity,
        used_for_claim = false),
    (profile = :exploratory_rasch_lenient,
        role = :lenient_exploration_sensitivity,
        used_for_claim = false),
    (profile = :sample_size_mean_square,
        role = :sample_size_rule_sensitivity,
        used_for_claim = false),
]

const SCENARIOS = [
    (scenario = :well_specified_current_q,
        data_generating_process = :fixed_q_mgmfrm_current_q,
        q_condition = :declared_q_matches_truth,
        heldout_challenge = :ordinary_observation_prediction,
        dimensions = 2,
        n_persons = 80,
        n_items = 6,
        n_raters = 4,
        n_replicates = 3,
        expected_best_model = :confirmatory_mgmfrm_current_q,
        expected_rank_stable = true,
        threshold_profile_sensitive = false,
        external_construct_validation_needed = false),
    (scenario = :missing_loading_revised_q,
        data_generating_process = :fixed_q_mgmfrm_candidate_q,
        q_condition = :declared_q_missing_one_loading,
        heldout_challenge = :q_revision_candidate_prediction,
        dimensions = 2,
        n_persons = 80,
        n_items = 6,
        n_raters = 4,
        n_replicates = 3,
        expected_best_model = :construct_reviewed_revised_q_mgmfrm,
        expected_rank_stable = true,
        threshold_profile_sensitive = true,
        external_construct_validation_needed = true),
    (scenario = :sparse_signal_current_q,
        data_generating_process = :sparse_fixed_q_mgmfrm,
        q_condition = :sparse_dimension_signal_with_current_q,
        heldout_challenge = :sparse_signal_prediction,
        dimensions = 3,
        n_persons = 90,
        n_items = 7,
        n_raters = 4,
        n_replicates = 3,
        expected_best_model = :sparse_mgmfrm_current_q,
        expected_rank_stable = true,
        threshold_profile_sensitive = true,
        external_construct_validation_needed = false),
    (scenario = :rater_method_noise,
        data_generating_process = :scalar_gmfrm_with_method_noise,
        q_condition = :q_specific_signal_weak_relative_to_rater_noise,
        heldout_challenge = :rater_method_generalization,
        dimensions = 2,
        n_persons = 80,
        n_items = 6,
        n_raters = 5,
        n_replicates = 3,
        expected_best_model = :scalar_gmfrm_baseline,
        expected_rank_stable = true,
        threshold_profile_sensitive = true,
        external_construct_validation_needed = false),
    (scenario = :weak_dimension_ambiguous,
        data_generating_process = :weak_anchor_dimension_mgmfrm,
        q_condition = :dimension_signal_near_threshold,
        heldout_challenge = :unstable_dimension_prediction,
        dimensions = 3,
        n_persons = 70,
        n_items = 5,
        n_raters = 4,
        n_replicates = 3,
        expected_best_model = :confirmatory_mgmfrm_current_q,
        expected_rank_stable = false,
        threshold_profile_sensitive = true,
        external_construct_validation_needed = true),
]

const METRIC_VALUES = Dict(
    (:well_specified_current_q, :scalar_gmfrm_baseline) =>
        (-1.350, 0.58, 0.110, 0.135, 0.180),
    (:well_specified_current_q, :confirmatory_mgmfrm_current_q) =>
        (-1.120, 0.68, 0.052, 0.070, 0.060),
    (:well_specified_current_q, :sparse_mgmfrm_current_q) =>
        (-1.155, 0.66, 0.061, 0.078, 0.075),
    (:well_specified_current_q, :construct_reviewed_revised_q_mgmfrm) =>
        (-1.135, 0.67, 0.058, 0.074, 0.068),
    (:well_specified_current_q, :null_or_intercept_reference) =>
        (-1.610, 0.43, 0.190, 0.240, 0.300),
    (:missing_loading_revised_q, :scalar_gmfrm_baseline) =>
        (-1.420, 0.55, 0.130, 0.155, 0.220),
    (:missing_loading_revised_q, :confirmatory_mgmfrm_current_q) =>
        (-1.280, 0.62, 0.094, 0.122, 0.160),
    (:missing_loading_revised_q, :sparse_mgmfrm_current_q) =>
        (-1.310, 0.60, 0.105, 0.130, 0.175),
    (:missing_loading_revised_q, :construct_reviewed_revised_q_mgmfrm) =>
        (-1.160, 0.68, 0.060, 0.080, 0.075),
    (:missing_loading_revised_q, :null_or_intercept_reference) =>
        (-1.640, 0.42, 0.205, 0.255, 0.330),
    (:sparse_signal_current_q, :scalar_gmfrm_baseline) =>
        (-1.390, 0.56, 0.118, 0.145, 0.205),
    (:sparse_signal_current_q, :confirmatory_mgmfrm_current_q) =>
        (-1.205, 0.65, 0.070, 0.088, 0.095),
    (:sparse_signal_current_q, :sparse_mgmfrm_current_q) =>
        (-1.150, 0.69, 0.055, 0.073, 0.066),
    (:sparse_signal_current_q, :construct_reviewed_revised_q_mgmfrm) =>
        (-1.230, 0.64, 0.076, 0.096, 0.105),
    (:sparse_signal_current_q, :null_or_intercept_reference) =>
        (-1.625, 0.42, 0.198, 0.250, 0.320),
    (:rater_method_noise, :scalar_gmfrm_baseline) =>
        (-1.240, 0.63, 0.078, 0.098, 0.110),
    (:rater_method_noise, :confirmatory_mgmfrm_current_q) =>
        (-1.285, 0.61, 0.096, 0.118, 0.150),
    (:rater_method_noise, :sparse_mgmfrm_current_q) =>
        (-1.315, 0.59, 0.108, 0.132, 0.170),
    (:rater_method_noise, :construct_reviewed_revised_q_mgmfrm) =>
        (-1.300, 0.60, 0.116, 0.125, 0.180),
    (:rater_method_noise, :null_or_intercept_reference) =>
        (-1.560, 0.45, 0.185, 0.230, 0.290),
    (:weak_dimension_ambiguous, :scalar_gmfrm_baseline) =>
        (-1.335, 0.58, 0.115, 0.140, 0.205),
    (:weak_dimension_ambiguous, :confirmatory_mgmfrm_current_q) =>
        (-1.235, 0.63, 0.084, 0.108, 0.130),
    (:weak_dimension_ambiguous, :sparse_mgmfrm_current_q) =>
        (-1.248, 0.62, 0.087, 0.110, 0.136),
    (:weak_dimension_ambiguous, :construct_reviewed_revised_q_mgmfrm) =>
        (-1.242, 0.63, 0.090, 0.112, 0.142),
    (:weak_dimension_ambiguous, :null_or_intercept_reference) =>
        (-1.585, 0.44, 0.192, 0.238, 0.310),
)

function usage()
    return """
    Generate the local MGMFRM heldout-prediction simulation grid.

    This artifact fixes the scenario, split, model, metric, threshold-sensitivity,
    and leakage-guard surface for the next heldout MGMFRM prediction execution.
    It records deterministic expected metric surfaces only; it does not run the
    heldout MCMC/refit execution, publish, register, or allow model-weight,
    sparse-superiority, fit-metric, or Q-revision claims.

    Usage:
      julia --project=. scripts/generate_mgmfrm_heldout_prediction_simulation_grid.jl [--output PATH]
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
as_bool(value) = Bool(value)
as_int(value) = Int(value)

function artifact_summary(name::Symbol, summary)
    name === :mgmfrm_validation_split_model_comparison_policy && return (;
        passed = as_bool(summary[:passed]),
        primary_holdout_target_selected =
            as_bool(summary[:primary_holdout_target_selected]),
        split_policy_recorded = as_bool(summary[:split_policy_recorded]),
        comparison_model_set_recorded =
            as_bool(summary[:comparison_model_set_recorded]),
        all_metrics_predeclared =
            as_bool(summary[:all_metrics_predeclared]),
        all_leakage_guards_recorded =
            as_bool(summary[:all_leakage_guards_recorded]),
        all_claim_rules_block_public_claims =
            as_bool(summary[:all_claim_rules_block_public_claims]),
        same_data_fit_metrics_diagnostic_only =
            as_bool(summary[:same_data_fit_metrics_diagnostic_only]),
        no_public_fit_metric_claim =
            as_bool(summary[:no_public_fit_metric_claim]),
        no_public_q_revision_claim =
            as_bool(summary[:no_public_q_revision_claim]),
        no_model_weight_or_sparse_superiority_claim =
            as_bool(summary[:no_model_weight_or_sparse_superiority_claim]),
        n_validation_split_policy_cells =
            as_int(summary[:n_validation_split_policy_cells]),
        next_gate = as_string(summary[:next_gate]),
    )
    name === :mgmfrm_fit_metric_threshold_sensitivity && return (;
        passed = as_bool(summary[:passed]),
        n_threshold_profiles = as_int(summary[:n_threshold_profiles]),
        n_fit_metric_evidence_cells =
            as_int(summary[:n_fit_metric_evidence_cells]),
        all_fit_metric_values_finite =
            as_bool(summary[:all_fit_metric_values_finite]),
        threshold_profiles_change_at_least_one_flag =
            as_bool(summary[:threshold_profiles_change_at_least_one_flag]),
        existing_model_comparison_recorded =
            as_bool(summary[:existing_model_comparison_recorded]),
        parameter_shift_recorded =
            as_bool(summary[:parameter_shift_recorded]),
        no_single_threshold_profile_promoted =
            as_bool(summary[:no_single_threshold_profile_promoted]),
        no_public_fit_metric_claim =
            as_bool(summary[:no_public_fit_metric_claim]),
        no_public_q_revision_claim =
            as_bool(summary[:no_public_q_revision_claim]),
        next_gate = as_string(summary[:next_gate]),
    )
    name === :mgmfrm_empirical_q_matrix_recovery_simulation_grid && return (;
        passed = as_bool(summary[:passed]),
        n_scenarios = as_int(summary[:n_scenarios]),
        all_scenarios_passed = as_bool(summary[:all_scenarios_passed]),
        all_candidate_validations_checked =
            as_bool(summary[:all_candidate_validations_checked]),
        false_public_promotion_rate_zero =
            as_bool(summary[:false_public_promotion_rate_zero]),
        empirical_q_recovery_allowed =
            as_bool(summary[:empirical_q_recovery_allowed]),
        candidate_suggestions_allowed =
            as_bool(summary[:candidate_suggestions_allowed]),
        no_automatic_q_revision =
            as_bool(summary[:no_automatic_q_revision]),
        no_public_recovery_claim =
            as_bool(summary[:no_public_recovery_claim]),
        next_gate = as_string(summary[:next_gate]),
    )
    name === :mgmfrm_construct_reviewed_q_fit_reporting_policy && return (;
        passed = as_bool(summary[:passed]),
        threshold_profile_surface_recorded =
            as_bool(summary[:threshold_profile_surface_recorded]),
        indicator_conflicts_recorded =
            as_bool(summary[:indicator_conflicts_recorded]),
        existing_model_reference_recorded =
            as_bool(summary[:existing_model_reference_recorded]),
        parameter_shift_impact_recorded =
            as_bool(summary[:parameter_shift_impact_recorded]),
        all_policy_rows_block_public_claims =
            as_bool(summary[:all_policy_rows_block_public_claims]),
        no_single_threshold_profile_promoted =
            as_bool(summary[:no_single_threshold_profile_promoted]),
        no_public_fit_metric_claim =
            as_bool(summary[:no_public_fit_metric_claim]),
        no_public_q_revision_claim =
            as_bool(summary[:no_public_q_revision_claim]),
        n_reporting_evidence_cells =
            as_int(summary[:n_reporting_evidence_cells]),
        next_gate = as_string(summary[:next_gate]),
    )
    return (; passed = as_bool(summary[:passed]))
end

function artifact_record(spec)
    path = fixture_path(spec.path)
    exists = isfile(path)
    if !exists
        return (;
            artifact = spec.name,
            path = spec.path,
            exists = false,
            sha256 = missing,
            schema = missing,
            expected_schema = spec.expected_schema,
            schema_matches = false,
            summary_passed = false,
            summary = (; passed = false),
        )
    end
    fixture = JSON3.read(read(path, String))
    schema = as_string(fixture[:schema])
    schema_matches = schema == spec.expected_schema
    summary = artifact_summary(spec.name, fixture[:summary])
    return (;
        artifact = spec.name,
        path = spec.path,
        exists,
        sha256 = file_sha256(path),
        schema,
        expected_schema = spec.expected_schema,
        schema_matches,
        summary_passed = summary.passed,
        summary,
    )
end

function record_by_name(records, name::Symbol)
    return only(record for record in records if record.artifact === name)
end

function split_execution_rows()
    return [
        (split = :observation_kfold,
            role = :primary_heldout_prediction_target,
            heldout_unit = :rating_observation,
            n_folds = 5,
            minimum_train_fraction = 0.80,
            selected_for_first_execution = true,
            sensitivity_split = false,
            leakage_guard_required = true),
        (split = :respondent_holdout,
            role = :person_generalization_sensitivity,
            heldout_unit = :respondent,
            n_folds = 5,
            minimum_train_fraction = 0.80,
            selected_for_first_execution = false,
            sensitivity_split = true,
            leakage_guard_required = true),
        (split = :item_holdout,
            role = :item_generalization_sensitivity,
            heldout_unit = :item,
            n_folds = 5,
            minimum_train_fraction = 0.80,
            selected_for_first_execution = false,
            sensitivity_split = true,
            leakage_guard_required = true),
        (split = :scenario_replicate_holdout,
            role = :simulation_replication_sensitivity,
            heldout_unit = :simulation_replicate,
            n_folds = 3,
            minimum_train_fraction = 0.80,
            selected_for_first_execution = false,
            sensitivity_split = true,
            leakage_guard_required = true),
    ]
end

function comparison_model_rows()
    return [
        (model = :scalar_gmfrm_baseline,
            family = :gmfrm,
            role = :existing_baseline,
            planned_for_execution = true,
            claim_scope = :reference_only),
        (model = :confirmatory_mgmfrm_current_q,
            family = :mgmfrm,
            role = :primary_candidate,
            planned_for_execution = true,
            claim_scope = :local_diagnostic_until_heldout_execution),
        (model = :sparse_mgmfrm_current_q,
            family = :mgmfrm,
            role = :sparsity_candidate,
            planned_for_execution = true,
            claim_scope = :local_diagnostic_until_heldout_execution),
        (model = :construct_reviewed_revised_q_mgmfrm,
            family = :mgmfrm,
            role = :q_revision_candidate,
            planned_for_execution = true,
            claim_scope = :blocked_until_external_construct_validation),
        (model = :null_or_intercept_reference,
            family = :reference,
            role = :calibration_anchor,
            planned_for_execution = true,
            claim_scope = :reference_only),
    ]
end

function metric_rows()
    return [
        (metric = :heldout_log_predictive_density,
            role = :primary_predictive_metric,
            direction = :higher_is_better),
        (metric = :heldout_response_accuracy_or_rank_score,
            role = :secondary_response_prediction_metric,
            direction = :higher_is_better),
        (metric = :heldout_calibration_error,
            role = :secondary_calibration_metric,
            direction = :lower_is_better),
        (metric = :posterior_predictive_discrepancy,
            role = :diagnostic_replication_metric,
            direction = :lower_is_better),
        (metric = :simulation_parameter_recovery_shift,
            role = :simulation_only_impact_metric,
            direction = :lower_is_better),
    ]
end

function scenario_rows()
    return [
        (;
            scenario.scenario,
            scenario.data_generating_process,
            scenario.q_condition,
            scenario.heldout_challenge,
            scenario.dimensions,
            scenario.n_persons,
            scenario.n_items,
            scenario.n_raters,
            scenario.n_replicates,
            scenario.expected_best_model,
            scenario.expected_rank_stable,
            scenario.threshold_profile_sensitive,
            scenario.external_construct_validation_needed,
            public_claim_allowed = false,
        )
        for scenario in SCENARIOS
    ]
end

function values_for(scenario::Symbol, model::Symbol)
    return METRIC_VALUES[(scenario, model)]
end

function metric_value(scenario::Symbol, model::Symbol, metric::Symbol)
    values = values_for(scenario, model)
    metric === :heldout_log_predictive_density && return values[1]
    metric === :heldout_response_accuracy_or_rank_score && return values[2]
    metric === :heldout_calibration_error && return values[3]
    metric === :posterior_predictive_discrepancy && return values[4]
    metric === :simulation_parameter_recovery_shift && return values[5]
    error("unknown metric: $metric")
end

function best_value_for_metric(scenario::Symbol, metric)
    values = [metric_value(scenario, model, metric.metric) for model in MODEL_ORDER]
    metric.direction === :higher_is_better && return maximum(values)
    return minimum(values)
end

round6(value) = round(Float64(value); digits = 6)

function metric_surface_rows(metrics)
    rows = NamedTuple[]
    for scenario in SCENARIOS, model in MODEL_ORDER, metric in metrics
        value = metric_value(scenario.scenario, model, metric.metric)
        best_value = best_value_for_metric(scenario.scenario, metric)
        distance = metric.direction === :higher_is_better ?
            best_value - value : value - best_value
        push!(rows, (;
            scenario = scenario.scenario,
            model,
            metric = metric.metric,
            direction = metric.direction,
            expected_value = round6(value),
            distance_to_scenario_best = round6(distance),
            expected_best_for_metric = abs(distance) <= 1.0e-10,
            observed_heldout_result = false,
            simulation_design_value = true,
            public_claim_allowed = false,
        ))
    end
    return rows
end

function scenario_model_summary_rows()
    rows = NamedTuple[]
    for scenario in SCENARIOS
        log_scores = [(model = model,
            value = metric_value(scenario.scenario, model,
                :heldout_log_predictive_density)) for model in MODEL_ORDER]
        sorted_models = sort(log_scores; by = row -> row.value, rev = true)
        rank_by_model = Dict(row.model => index for (index, row) in
            enumerate(sorted_models))
        for model in MODEL_ORDER
            values = values_for(scenario.scenario, model)
            push!(rows, (;
                scenario = scenario.scenario,
                model,
                expected_primary_rank = rank_by_model[model],
                expected_primary_best =
                    model === scenario.expected_best_model,
                rank_stability_expected = scenario.expected_rank_stable,
                heldout_log_predictive_density = round6(values[1]),
                heldout_response_accuracy_or_rank_score = round6(values[2]),
                heldout_calibration_error = round6(values[3]),
                posterior_predictive_discrepancy = round6(values[4]),
                simulation_parameter_recovery_shift = round6(values[5]),
                public_claim_allowed = false,
            ))
        end
    end
    return rows
end

function threshold_impact_rows()
    rows = NamedTuple[]
    for scenario in SCENARIOS, profile in THRESHOLD_PROFILES
        strict_ambiguous =
            scenario.scenario === :weak_dimension_ambiguous ||
            (scenario.scenario === :rater_method_noise &&
             profile.profile === :strict_bayesian_workflow)
        push!(rows, (;
            scenario = scenario.scenario,
            threshold_profile = profile.profile,
            ranking_stable_under_profile =
                scenario.expected_rank_stable && !strict_ambiguous,
            threshold_profile_sensitive =
                scenario.threshold_profile_sensitive || strict_ambiguous,
            claim_decision = :diagnostic_only,
            public_claim_allowed = false,
        ))
    end
    return rows
end

function leakage_guard_rows()
    return [
        (guard = :fold_assignment_before_fit,
            execution_requirement =
                :materialize_indices_before_any_model_fit,
            carried_from_policy = true,
            public_claim_blocked_if_unsatisfied = true),
        (guard = :q_revision_train_only,
            execution_requirement =
                :estimate_candidate_q_using_training_data_only,
            carried_from_policy = true,
            public_claim_blocked_if_unsatisfied = true),
        (guard = :threshold_profiles_locked_before_fit,
            execution_requirement =
                :lock_threshold_profiles_before_heldout_execution,
            carried_from_policy = true,
            public_claim_blocked_if_unsatisfied = true),
        (guard = :model_weight_claim_heldout_only,
            execution_requirement =
                :derive_model_weights_from_executed_heldout_metrics_only,
            carried_from_policy = true,
            public_claim_blocked_if_unsatisfied = true),
        (guard = :same_data_diagnostics_not_claim_targets,
            execution_requirement =
                :exclude_same_data_waic_loo_from_claim_targets,
            carried_from_policy = true,
            public_claim_blocked_if_unsatisfied = true),
        (guard = :external_validation_not_used_for_tuning,
            execution_requirement =
                :do_not_tune_splits_or_thresholds_on_external_validation,
            carried_from_policy = true,
            public_claim_blocked_if_unsatisfied = true),
    ]
end

function claim_rule_rows()
    return [
        (claim = :heldout_prediction_improvement,
            required_evidence = :executed_heldout_model_comparison,
            grid_recorded = true,
            execution_completed = false,
            public_claim_allowed = false),
        (claim = :fit_metric_threshold_superiority,
            required_evidence =
                :executed_heldout_metric_consistency_across_profiles,
            grid_recorded = true,
            execution_completed = false,
            public_claim_allowed = false),
        (claim = :q_revision_improvement,
            required_evidence =
                :train_only_heldout_gain_plus_external_construct_validation,
            grid_recorded = true,
            execution_completed = false,
            public_claim_allowed = false),
        (claim = :model_weight_or_sparse_mgmfrm_superiority,
            required_evidence =
                :executed_heldout_prediction_study_with_stable_ranking,
            grid_recorded = true,
            execution_completed = false,
            public_claim_allowed = false),
        (claim = :local_grid_description,
            required_evidence = :this_pre_execution_grid,
            grid_recorded = true,
            execution_completed = true,
            public_claim_allowed = false),
    ]
end

function evidence_link_rows(policy, threshold, qrecovery, reporting)
    return [
        (artifact = policy.artifact,
            path = policy.path,
            link_satisfied = Bool(policy.summary_passed) &&
                policy.summary.next_gate ==
                    "heldout_mgmfrm_prediction_simulation_grid" &&
                Bool(policy.summary.split_policy_recorded) &&
                Bool(policy.summary.comparison_model_set_recorded),
            evidence_role = :supplies_split_model_metric_policy),
        (artifact = threshold.artifact,
            path = threshold.path,
            link_satisfied = Bool(threshold.summary_passed) &&
                Bool(threshold.summary.threshold_profiles_change_at_least_one_flag) &&
                Bool(threshold.summary.parameter_shift_recorded),
            evidence_role = :supplies_threshold_and_parameter_shift_sensitivity),
        (artifact = qrecovery.artifact,
            path = qrecovery.path,
            link_satisfied = Bool(qrecovery.summary_passed) &&
                Bool(qrecovery.summary.all_scenarios_passed) &&
                !Bool(qrecovery.summary.empirical_q_recovery_allowed),
            evidence_role = :supplies_q_misspecification_scenarios),
        (artifact = reporting.artifact,
            path = reporting.path,
            link_satisfied = Bool(reporting.summary_passed) &&
                Bool(reporting.summary.threshold_profile_surface_recorded) &&
                Bool(reporting.summary.all_policy_rows_block_public_claims),
            evidence_role = :supplies_reporting_claim_block_policy),
    ]
end

function best_model_count_rows()
    rows = NamedTuple[]
    for model in MODEL_ORDER
        n_best = count(scenario -> scenario.expected_best_model === model,
            SCENARIOS)
        n_best > 0 && push!(rows, (model, n = n_best))
    end
    return rows
end

function no_publication_commands()
    command =
        "julia --project=. scripts/generate_mgmfrm_heldout_prediction_simulation_grid.jl"
    banned = ["git push", "gh release", "Registrator", "Pkg.register", "publish"]
    lowered = lowercase(command)
    return all(!occursin(lowercase(term), lowered) for term in banned)
end

function build_artifact()
    records = [artifact_record(spec) for spec in INPUT_ARTIFACTS]
    policy =
        record_by_name(records, :mgmfrm_validation_split_model_comparison_policy)
    threshold =
        record_by_name(records, :mgmfrm_fit_metric_threshold_sensitivity)
    qrecovery =
        record_by_name(records,
            :mgmfrm_empirical_q_matrix_recovery_simulation_grid)
    reporting =
        record_by_name(records,
            :mgmfrm_construct_reviewed_q_fit_reporting_policy)

    splits = split_execution_rows()
    models = comparison_model_rows()
    metrics = metric_rows()
    scenarios = scenario_rows()
    metric_surface = metric_surface_rows(metrics)
    scenario_models = scenario_model_summary_rows()
    threshold_profiles = THRESHOLD_PROFILES
    threshold_impacts = threshold_impact_rows()
    leakage_guards = leakage_guard_rows()
    claim_rules = claim_rule_rows()
    links = evidence_link_rows(policy, threshold, qrecovery, reporting)
    best_counts = best_model_count_rows()
    no_publication = no_publication_commands()

    all_input_artifacts_present = all(record -> record.exists, records)
    all_expected_schemas = all(record -> record.schema_matches, records)
    all_input_summaries_passed = all(record -> record.summary_passed, records)
    split_policy_next_gate_matched =
        policy.summary.next_gate == "heldout_mgmfrm_prediction_simulation_grid"
    predeclared_splits_carried_forward =
        length(splits) == 4 &&
        any(row -> Bool(row.selected_for_first_execution), splits) &&
        all(row -> Bool(row.leakage_guard_required), splits)
    all_comparison_models_planned =
        length(models) == length(MODEL_ORDER) &&
        all(row -> Bool(row.planned_for_execution), models)
    all_scenarios_predeclared =
        length(scenarios) == length(SCENARIOS) &&
        all(row -> !Bool(row.public_claim_allowed), scenarios)
    all_metric_surface_values_finite =
        all(row -> isfinite(Float64(row.expected_value)), metric_surface)
    threshold_impact_rows_recorded =
        length(threshold_impacts) ==
            length(SCENARIOS) * length(THRESHOLD_PROFILES) &&
        all(row -> !Bool(row.public_claim_allowed), threshold_impacts)
    leakage_guards_carried_forward =
        all(row -> Bool(row.carried_from_policy) &&
            Bool(row.public_claim_blocked_if_unsatisfied), leakage_guards)
    all_claim_rules_block_public_claims =
        all(row -> !Bool(row.public_claim_allowed), claim_rules)
    no_public_fit_metric_claim =
        Bool(policy.summary.no_public_fit_metric_claim) &&
        Bool(threshold.summary.no_public_fit_metric_claim) &&
        Bool(reporting.summary.no_public_fit_metric_claim)
    no_public_q_revision_claim =
        Bool(policy.summary.no_public_q_revision_claim) &&
        Bool(threshold.summary.no_public_q_revision_claim) &&
        Bool(reporting.summary.no_public_q_revision_claim) &&
        Bool(qrecovery.summary.no_public_recovery_claim)
    no_public_model_weight_claim =
        Bool(policy.summary.no_model_weight_or_sparse_superiority_claim)
    no_sparse_superiority_claim = no_public_model_weight_claim

    passed = all_input_artifacts_present &&
        all_expected_schemas &&
        all_input_summaries_passed &&
        split_policy_next_gate_matched &&
        predeclared_splits_carried_forward &&
        all_comparison_models_planned &&
        all_scenarios_predeclared &&
        all_metric_surface_values_finite &&
        threshold_impact_rows_recorded &&
        leakage_guards_carried_forward &&
        all_claim_rules_block_public_claims &&
        no_public_fit_metric_claim &&
        no_public_q_revision_claim &&
        no_public_model_weight_claim &&
        no_sparse_superiority_claim &&
        no_publication

    remaining_public_blockers = [
        :heldout_prediction_execution_missing,
        :external_construct_validation_missing,
        :model_rank_stability_not_observed,
    ]

    return (;
        schema =
            "bayesianmgmfrm.mgmfrm_heldout_prediction_simulation_grid.v1",
        family = :mgmfrm,
        scope = :heldout_prediction_simulation_grid,
        status = :heldout_prediction_simulation_grid_recorded,
        decision =
            :record_pre_execution_heldout_prediction_simulation_grid,
        public_fit = true,
        experimental_public = true,
        fit_ready = true,
        local_only = true,
        heldout_prediction_execution_completed = false,
        observed_heldout_results_recorded = false,
        publication_or_registration_action = false,
        public_fit_metric_claim = false,
        public_q_revision_claim = false,
        public_model_weight_claim = false,
        sparse_mgmfrm_superiority_claim = false,
        package = (;
            name = "BayesianMGMFRM",
            version = project_version(),
            julia_version = string(VERSION),
        ),
        protocol = PROTOCOL,
        input_artifacts = records,
        split_execution_rows = splits,
        comparison_model_rows = models,
        metric_rows = metrics,
        scenario_rows = scenarios,
        scenario_model_summary_rows = scenario_models,
        metric_surface_rows = metric_surface,
        threshold_profile_rows = threshold_profiles,
        threshold_impact_rows = threshold_impacts,
        leakage_guard_rows = leakage_guards,
        claim_rule_rows = claim_rules,
        evidence_link_rows = links,
        best_model_count_rows = best_counts,
        decision_record = (;
            selected_decision =
                :record_pre_execution_heldout_prediction_simulation_grid,
            split_policy_carried_forward =
                predeclared_splits_carried_forward,
            comparison_model_set_carried_forward =
                all_comparison_models_planned,
            scenario_grid_recorded = all_scenarios_predeclared,
            threshold_profiles_carried_forward =
                threshold_impact_rows_recorded,
            heldout_prediction_execution_completed = false,
            observed_heldout_results_recorded = false,
            public_fit_metric_claim_allowed = false,
            public_q_revision_claim_allowed = false,
            model_weight_or_sparse_superiority_claim_allowed = false,
            required_followup = :heldout_mgmfrm_prediction_execution,
        ),
        summary = (;
            passed,
            publication_or_registration_action = false,
            local_only = true,
            all_input_artifacts_present,
            all_expected_schemas,
            all_input_summaries_passed,
            validation_split_model_comparison_policy_passed =
                policy.summary_passed,
            fit_metric_threshold_sensitivity_passed =
                threshold.summary_passed,
            empirical_q_matrix_recovery_simulation_grid_passed =
                qrecovery.summary_passed,
            construct_reviewed_q_fit_reporting_policy_passed =
                reporting.summary_passed,
            split_policy_next_gate_matched,
            predeclared_splits_carried_forward,
            all_comparison_models_planned,
            all_scenarios_predeclared,
            all_metric_surface_values_finite,
            threshold_impact_rows_recorded,
            leakage_guards_carried_forward,
            all_evidence_links_satisfied =
                all(row -> Bool(row.link_satisfied), links),
            all_claim_rules_block_public_claims,
            no_public_fit_metric_claim,
            no_public_q_revision_claim,
            no_public_model_weight_claim,
            no_sparse_superiority_claim,
            heldout_prediction_execution_completed = false,
            observed_heldout_results_recorded = false,
            heldout_execution_required = true,
            n_input_artifacts = length(records),
            n_split_execution_rows = length(splits),
            n_comparison_model_rows = length(models),
            n_metric_rows = length(metrics),
            n_scenarios = length(scenarios),
            n_scenario_model_summary_rows = length(scenario_models),
            n_metric_surface_rows = length(metric_surface),
            n_threshold_profiles = length(threshold_profiles),
            n_threshold_impact_rows = length(threshold_impacts),
            n_leakage_guard_rows = length(leakage_guards),
            n_claim_rule_rows = length(claim_rules),
            n_evidence_link_rows = length(links),
            n_heldout_simulation_grid_cells = length(metric_surface),
            n_rank_unstable_scenarios =
                count(row -> !Bool(row.expected_rank_stable), scenarios),
            n_external_construct_validation_scenarios =
                count(row -> Bool(row.external_construct_validation_needed),
                    scenarios),
            n_blockers = length(remaining_public_blockers),
            remaining_public_blockers,
            best_model_counts = best_counts,
            recommendation =
                :run_heldout_mgmfrm_prediction_execution_before_model_weight_or_sparse_claims,
            next_gate = :heldout_mgmfrm_prediction_execution,
        ),
    )
end

function main(args)
    output = parse_args(args)
    artifact = build_artifact()
    write_artifact(output, artifact)
    println("wrote ", relpath(output, ROOT))
    println("passed=", artifact.summary.passed,
        " metric_surface_rows=", artifact.summary.n_metric_surface_rows,
        " next_gate=", artifact.summary.next_gate)
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
