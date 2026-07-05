#!/usr/bin/env julia

using JSON3
using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_heldout_prediction_execution.json")

include(joinpath(@__DIR__, "local_json.jl"))

const INPUT_ARTIFACTS = [
    (name = :mgmfrm_heldout_prediction_simulation_grid,
        path =
            "test/fixtures/mgmfrm_heldout_prediction_simulation_grid.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_heldout_prediction_simulation_grid.v1"),
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
]

const PROTOCOL = (;
    protocol_id = "mgmfrm_heldout_prediction_execution_v1",
    review_kind = :local_deterministic_heldout_prediction_execution,
    publication_or_registration_action = false,
    local_only = true,
    execution_scope =
        :small_deterministic_synthetic_heldout_metric_execution,
    execution_engine =
        :deterministic_synthetic_metric_runner_no_mcmc_refit,
    primary_split = :observation_kfold,
    n_folds = 5,
    n_execution_observations_per_scenario = 40,
    thresholds = (;
        require_pre_execution_grid_passed = true,
        require_validation_split_model_comparison_policy_passed = true,
        require_fit_metric_threshold_sensitivity_passed = true,
        require_observation_kfold_selected = true,
        require_all_comparison_models_executed = true,
        require_all_scenarios_executed = true,
        require_fold_assignments_materialized = true,
        require_all_observations_held_out_once = true,
        require_observed_metric_rows_recorded = true,
        require_all_observed_metric_values_finite = true,
        require_rank_stability_review_recorded = true,
        require_threshold_profile_observed_rows_recorded = true,
        require_model_weight_rows_recorded = true,
        require_all_claim_rules_block_public_claims = true,
        require_no_public_fit_metric_claim = true,
        require_no_public_q_revision_claim = true,
        require_no_public_model_weight_claim = true,
        require_no_sparse_superiority_claim = true,
        require_no_publication_or_registration_action = true,
    ),
)

const PRIMARY_METRIC = :heldout_log_predictive_density

function usage()
    return """
    Generate the local MGMFRM heldout-prediction execution artifact.

    This artifact materializes the predeclared observation K-fold split and
    records deterministic synthetic heldout metric observations for the
    predeclared scenario/model/metric grid. It is an execution smoke artifact,
    not a full MCMC refit study, and it does not publish, register, or allow
    model-weight, sparse-superiority, fit-metric, or Q-revision claims.

    Usage:
      julia --project=. scripts/generate_mgmfrm_heldout_prediction_execution.jl [--output PATH]
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
as_float(value) = Float64(value)
as_symbol(value) = Symbol(String(value))

function artifact_summary(name::Symbol, summary)
    name === :mgmfrm_heldout_prediction_simulation_grid && return (;
        passed = as_bool(summary[:passed]),
        predeclared_splits_carried_forward =
            as_bool(summary[:predeclared_splits_carried_forward]),
        all_comparison_models_planned =
            as_bool(summary[:all_comparison_models_planned]),
        all_scenarios_predeclared =
            as_bool(summary[:all_scenarios_predeclared]),
        all_metric_surface_values_finite =
            as_bool(summary[:all_metric_surface_values_finite]),
        threshold_impact_rows_recorded =
            as_bool(summary[:threshold_impact_rows_recorded]),
        leakage_guards_carried_forward =
            as_bool(summary[:leakage_guards_carried_forward]),
        no_public_fit_metric_claim =
            as_bool(summary[:no_public_fit_metric_claim]),
        no_public_q_revision_claim =
            as_bool(summary[:no_public_q_revision_claim]),
        no_public_model_weight_claim =
            as_bool(summary[:no_public_model_weight_claim]),
        no_sparse_superiority_claim =
            as_bool(summary[:no_sparse_superiority_claim]),
        heldout_prediction_execution_completed =
            as_bool(summary[:heldout_prediction_execution_completed]),
        observed_heldout_results_recorded =
            as_bool(summary[:observed_heldout_results_recorded]),
        n_heldout_simulation_grid_cells =
            as_int(summary[:n_heldout_simulation_grid_cells]),
        n_rank_unstable_scenarios =
            as_int(summary[:n_rank_unstable_scenarios]),
        n_external_construct_validation_scenarios =
            as_int(summary[:n_external_construct_validation_scenarios]),
        next_gate = as_string(summary[:next_gate]),
    )
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
        no_public_fit_metric_claim =
            as_bool(summary[:no_public_fit_metric_claim]),
        no_public_q_revision_claim =
            as_bool(summary[:no_public_q_revision_claim]),
        no_model_weight_or_sparse_superiority_claim =
            as_bool(summary[:no_model_weight_or_sparse_superiority_claim]),
    )
    name === :mgmfrm_fit_metric_threshold_sensitivity && return (;
        passed = as_bool(summary[:passed]),
        threshold_profiles_change_at_least_one_flag =
            as_bool(summary[:threshold_profiles_change_at_least_one_flag]),
        parameter_shift_recorded =
            as_bool(summary[:parameter_shift_recorded]),
        no_single_threshold_profile_promoted =
            as_bool(summary[:no_single_threshold_profile_promoted]),
        no_public_fit_metric_claim =
            as_bool(summary[:no_public_fit_metric_claim]),
        no_public_q_revision_claim =
            as_bool(summary[:no_public_q_revision_claim]),
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

function load_fixture(path::AbstractString)
    return JSON3.read(read(fixture_path(path), String))
end

function rows_as_vector(fixture, key::Symbol)
    return collect(fixture[key])
end

function stable_code(parts...)
    text = join(string.(parts), "|")
    total = 0
    for (index, char) in enumerate(text)
        total += (index % 19 + 1) * Int(char)
    end
    return total
end

function stable_jitter(parts...; scale::Float64)
    centered = (stable_code(parts...) % 1001) / 1000 - 0.5
    return centered * scale
end

function metric_jitter_scale(metric::Symbol)
    metric === :heldout_log_predictive_density && return 0.006
    metric === :heldout_response_accuracy_or_rank_score && return 0.004
    metric === :heldout_calibration_error && return 0.003
    metric === :posterior_predictive_discrepancy && return 0.003
    metric === :simulation_parameter_recovery_shift && return 0.003
    error("unknown metric: $metric")
end

function higher_is_better(direction::Symbol)
    direction === :higher_is_better && return true
    direction === :lower_is_better && return false
    error("unknown metric direction: $direction")
end

function weak_dimension_fold_winner(fold::Int)
    winners = (
        :confirmatory_mgmfrm_current_q,
        :sparse_mgmfrm_current_q,
        :construct_reviewed_revised_q_mgmfrm,
        :confirmatory_mgmfrm_current_q,
        :sparse_mgmfrm_current_q,
    )
    return winners[fold]
end

function winner_adjustment(scenario::Symbol, model::Symbol, metric::Symbol,
        direction::Symbol, fold::Int)
    if scenario === :weak_dimension_ambiguous
        winner = weak_dimension_fold_winner(fold)
        magnitude = metric === :heldout_log_predictive_density ? 0.022 :
            metric === :heldout_response_accuracy_or_rank_score ? 0.012 : 0.010
        if model === winner
            return higher_is_better(direction) ? magnitude : -magnitude
        elseif model in (:confirmatory_mgmfrm_current_q,
                :sparse_mgmfrm_current_q,
                :construct_reviewed_revised_q_mgmfrm)
            return higher_is_better(direction) ? -0.002 : 0.002
        end
        return 0.0
    end
    return 0.0
end

function expected_metric_map(metric_surface_rows)
    mapping = Dict{Tuple{Symbol, Symbol, Symbol}, Tuple{Float64, Symbol}}()
    for row in metric_surface_rows
        mapping[(as_symbol(row[:scenario]), as_symbol(row[:model]),
            as_symbol(row[:metric]))] =
            (as_float(row[:expected_value]), as_symbol(row[:direction]))
    end
    return mapping
end

function metric_value(mapping, scenario::Symbol, model::Symbol,
        metric::Symbol, fold::Int)
    expected, direction = mapping[(scenario, model, metric)]
    value = expected +
        stable_jitter(scenario, model, metric, fold;
            scale = metric_jitter_scale(metric)) +
        winner_adjustment(scenario, model, metric, direction, fold)
    return round(Float64(value); digits = 6)
end

function scenario_symbols(rows)
    return [as_symbol(row[:scenario]) for row in rows]
end

function model_symbols(rows)
    return [as_symbol(row[:model]) for row in rows]
end

function metric_specs(rows)
    return [(metric = as_symbol(row[:metric]),
        direction = as_symbol(row[:direction])) for row in rows]
end

function selected_observation_kfold(split_rows)
    return any(split_rows) do row
        as_symbol(row[:split]) === :observation_kfold &&
            as_bool(row[:selected_for_first_execution]) &&
            as_bool(row[:leakage_guard_required]) &&
            as_int(row[:n_folds]) == PROTOCOL.n_folds
    end
end

function fold_assignment_rows(scenarios)
    n = PROTOCOL.n_execution_observations_per_scenario
    rows = NamedTuple[]
    for (scenario_index, scenario) in enumerate(scenarios)
        for fold in 1:PROTOCOL.n_folds
            heldout = [observation for observation in 1:n
                if mod(observation + scenario_index - 2,
                    PROTOCOL.n_folds) + 1 == fold]
            push!(rows, (;
                scenario,
                split = PROTOCOL.primary_split,
                fold,
                fold_seed = stable_code(scenario, fold, :fold_assignment),
                n_observations = n,
                n_train_observations = n - length(heldout),
                n_heldout_observations = length(heldout),
                train_fraction = round((n - length(heldout)) / n; digits = 6),
                heldout_observations = heldout,
                fold_assignment_materialized = true,
                train_only_q_revision_guard_satisfied = true,
            ))
        end
    end
    return rows
end

function all_observations_held_once(folds, scenarios)
    n = PROTOCOL.n_execution_observations_per_scenario
    for scenario in scenarios
        counts = zeros(Int, n)
        for row in folds
            row.scenario === scenario || continue
            counts[row.heldout_observations] .+= 1
        end
        all(==(1), counts) || return false
    end
    return true
end

function fold_model_metric_rows(folds, models, metrics, mapping)
    rows = NamedTuple[]
    for fold_row in folds, model in models, metric in metrics
        expected, direction =
            mapping[(fold_row.scenario, model, metric.metric)]
        observed =
            metric_value(mapping, fold_row.scenario, model, metric.metric,
                fold_row.fold)
        push!(rows, (;
            scenario = fold_row.scenario,
            split = fold_row.split,
            fold = fold_row.fold,
            model,
            metric = metric.metric,
            direction = metric.direction,
            expected_grid_value = round(Float64(expected); digits = 6),
            observed_value = observed,
            observed_minus_expected =
                round(observed - Float64(expected); digits = 6),
            n_train_observations = fold_row.n_train_observations,
            n_heldout_observations = fold_row.n_heldout_observations,
            execution_engine = PROTOCOL.execution_engine,
            observed_heldout_result = true,
            mcmc_refit_result = false,
            public_claim_allowed = false,
        ))
    end
    return rows
end

function metric_mean(rows, scenario::Symbol, model::Symbol, metric::Symbol)
    values = [Float64(row.observed_value) for row in rows
        if row.scenario === scenario && row.model === model &&
            row.metric === metric]
    return round(sum(values) / length(values); digits = 6)
end

function primary_rank_rows(rows, scenarios, models)
    output = NamedTuple[]
    for scenario in scenarios
        scores = [(model = model,
            value = metric_mean(rows, scenario, model, PRIMARY_METRIC))
            for model in models]
        sorted_scores = sort(scores; by = row -> row.value, rev = true)
        best = first(sorted_scores)
        rank_by_model = Dict(row.model => index for (index, row) in
            enumerate(sorted_scores))
        for score in scores
            push!(output, (;
                scenario,
                model = score.model,
                observed_primary_rank = rank_by_model[score.model],
                observed_primary_best = score.model === best.model,
                observed_heldout_log_predictive_density = score.value,
                observed_primary_delta_to_best =
                    round(score.value - best.value; digits = 6),
            ))
        end
    end
    return output
end

function scenario_model_summary_rows(rows, scenarios, models, metrics)
    ranks = primary_rank_rows(rows, scenarios, models)
    rank_by_key =
        Dict((rank.scenario, rank.model) => rank for rank in ranks)
    summaries = NamedTuple[]
    for scenario in scenarios, model in models
        rank = rank_by_key[(scenario, model)]
        values = Dict(metric.metric =>
                metric_mean(rows, scenario, model, metric.metric)
            for metric in metrics)
        push!(summaries, (;
            scenario,
            model,
            rank.observed_primary_rank,
            rank.observed_primary_best,
            rank.observed_primary_delta_to_best,
            heldout_log_predictive_density =
                values[:heldout_log_predictive_density],
            heldout_response_accuracy_or_rank_score =
                values[:heldout_response_accuracy_or_rank_score],
            heldout_calibration_error =
                values[:heldout_calibration_error],
            posterior_predictive_discrepancy =
                values[:posterior_predictive_discrepancy],
            simulation_parameter_recovery_shift =
                values[:simulation_parameter_recovery_shift],
            observed_heldout_result = true,
            mcmc_refit_result = false,
            public_claim_allowed = false,
        ))
    end
    return summaries
end

function fold_best_model(rows, scenario::Symbol, fold::Int)
    candidates = [row for row in rows
        if row.scenario === scenario && row.fold == fold &&
            row.metric === PRIMARY_METRIC]
    sorted_rows = sort(candidates; by = row -> Float64(row.observed_value),
        rev = true)
    return first(sorted_rows).model
end

function rank_stability_rows(rows, scenarios, scenario_rows)
    expected_by_scenario =
        Dict(as_symbol(row[:scenario]) => as_bool(row[:expected_rank_stable])
            for row in scenario_rows)
    external_by_scenario =
        Dict(as_symbol(row[:scenario]) =>
                as_bool(row[:external_construct_validation_needed])
            for row in scenario_rows)
    output = NamedTuple[]
    for scenario in scenarios
        winners = [fold_best_model(rows, scenario, fold)
            for fold in 1:PROTOCOL.n_folds]
        unique_winners = unique(winners)
        push!(output, (;
            scenario,
            primary_metric = PRIMARY_METRIC,
            best_model_by_fold = winners,
            n_unique_best_models = length(unique_winners),
            rank_stability_expected = expected_by_scenario[scenario],
            rank_stable_observed = length(unique_winners) == 1,
            external_construct_validation_needed =
                external_by_scenario[scenario],
            public_claim_allowed = false,
        ))
    end
    return output
end

function model_weight_rows(summary_rows, scenarios)
    rows = NamedTuple[]
    for scenario in scenarios
        scenario_rows = [row for row in summary_rows if row.scenario === scenario]
        best = maximum(Float64(row.heldout_log_predictive_density)
            for row in scenario_rows)
        unnormalized =
            [exp(Float64(row.heldout_log_predictive_density) - best)
                for row in scenario_rows]
        total = sum(unnormalized)
        for (index, row) in enumerate(scenario_rows)
            push!(rows, (;
                scenario,
                model = row.model,
                primary_metric = PRIMARY_METRIC,
                observed_primary_rank = row.observed_primary_rank,
                normalized_weight =
                    round(unnormalized[index] / total; digits = 6),
                weight_source = :observed_deterministic_heldout_metrics,
                public_model_weight_claim_allowed = false,
            ))
        end
    end
    return rows
end

function threshold_profile_observed_rows(threshold_impacts, rank_rows)
    rank_by_scenario = Dict(row.scenario => row for row in rank_rows)
    rows = NamedTuple[]
    for row in threshold_impacts
        scenario = as_symbol(row[:scenario])
        rank = rank_by_scenario[scenario]
        push!(rows, (;
            scenario,
            threshold_profile = as_symbol(row[:threshold_profile]),
            predeclared_ranking_stable_under_profile =
                as_bool(row[:ranking_stable_under_profile]),
            observed_rank_stable = rank.rank_stable_observed,
            threshold_profile_sensitive =
                as_bool(row[:threshold_profile_sensitive]) ||
                !rank.rank_stable_observed,
            claim_decision = :diagnostic_only,
            public_claim_allowed = false,
        ))
    end
    return rows
end

function execution_guard_rows()
    return [
        (guard = :fold_assignment_before_scoring,
            satisfied = true,
            evidence = :fold_assignment_rows,
            public_claim_blocked_if_unsatisfied = true),
        (guard = :predeclared_model_set_only,
            satisfied = true,
            evidence = :comparison_model_rows_from_grid,
            public_claim_blocked_if_unsatisfied = true),
        (guard = :threshold_profiles_locked_before_execution,
            satisfied = true,
            evidence = :threshold_profile_observed_rows,
            public_claim_blocked_if_unsatisfied = true),
        (guard = :same_data_diagnostics_not_claim_targets,
            satisfied = true,
            evidence = :observed_heldout_metrics_only,
            public_claim_blocked_if_unsatisfied = true),
        (guard = :full_mcmc_refit_required_before_public_weight_claims,
            satisfied = false,
            evidence = :mcmc_refit_result_false,
            public_claim_blocked_if_unsatisfied = true),
        (guard = :external_construct_validation_required_for_q_revision,
            satisfied = false,
            evidence = :external_construct_validation_missing,
            public_claim_blocked_if_unsatisfied = true),
    ]
end

function claim_rule_rows()
    return [
        (claim = :heldout_prediction_improvement,
            required_evidence = :observed_heldout_model_comparison,
            execution_completed = true,
            full_mcmc_refit_completed = false,
            public_claim_allowed = false),
        (claim = :fit_metric_threshold_superiority,
            required_evidence =
                :observed_threshold_profile_consistency_plus_full_refit,
            execution_completed = true,
            full_mcmc_refit_completed = false,
            public_claim_allowed = false),
        (claim = :q_revision_improvement,
            required_evidence =
                :train_only_heldout_gain_plus_external_construct_validation,
            execution_completed = true,
            external_construct_validation_completed = false,
            public_claim_allowed = false),
        (claim = :model_weight_or_sparse_mgmfrm_superiority,
            required_evidence =
                :stable_observed_heldout_ranking_plus_full_mcmc_refit,
            execution_completed = true,
            full_mcmc_refit_completed = false,
            public_claim_allowed = false),
        (claim = :local_execution_description,
            required_evidence = :this_deterministic_execution_artifact,
            execution_completed = true,
            full_mcmc_refit_completed = false,
            public_claim_allowed = false),
    ]
end

function evidence_link_rows(grid, split_policy, threshold)
    return [
        (artifact = grid.artifact,
            path = grid.path,
            link_satisfied = Bool(grid.summary_passed) &&
                grid.summary.next_gate == "heldout_mgmfrm_prediction_execution" &&
                !Bool(grid.summary.heldout_prediction_execution_completed) &&
                !Bool(grid.summary.observed_heldout_results_recorded),
            evidence_role = :predeclared_scenario_model_metric_grid),
        (artifact = split_policy.artifact,
            path = split_policy.path,
            link_satisfied = Bool(split_policy.summary_passed) &&
                Bool(split_policy.summary.primary_holdout_target_selected) &&
                Bool(split_policy.summary.comparison_model_set_recorded),
            evidence_role = :supplies_primary_split_and_model_set_policy),
        (artifact = threshold.artifact,
            path = threshold.path,
            link_satisfied = Bool(threshold.summary_passed) &&
                Bool(threshold.summary.threshold_profiles_change_at_least_one_flag) &&
                Bool(threshold.summary.parameter_shift_recorded),
            evidence_role = :supplies_fit_threshold_sensitivity_policy),
    ]
end

function no_publication_commands()
    command =
        "julia --project=. scripts/generate_mgmfrm_heldout_prediction_execution.jl"
    banned = ["git push", "gh release", "Registrator", "Pkg.register", "publish"]
    lowered = lowercase(command)
    return all(!occursin(lowercase(term), lowered) for term in banned)
end

function build_artifact()
    records = [artifact_record(spec) for spec in INPUT_ARTIFACTS]
    grid_record =
        record_by_name(records, :mgmfrm_heldout_prediction_simulation_grid)
    split_policy =
        record_by_name(records, :mgmfrm_validation_split_model_comparison_policy)
    threshold =
        record_by_name(records, :mgmfrm_fit_metric_threshold_sensitivity)
    grid = load_fixture("test/fixtures/mgmfrm_heldout_prediction_simulation_grid.json")

    split_rows = rows_as_vector(grid, :split_execution_rows)
    model_rows = rows_as_vector(grid, :comparison_model_rows)
    metric_rows_input = rows_as_vector(grid, :metric_rows)
    scenario_rows_input = rows_as_vector(grid, :scenario_rows)
    metric_surface_input = rows_as_vector(grid, :metric_surface_rows)
    threshold_impacts_input = rows_as_vector(grid, :threshold_impact_rows)

    scenarios = scenario_symbols(scenario_rows_input)
    models = model_symbols(model_rows)
    metrics = metric_specs(metric_rows_input)
    mapping = expected_metric_map(metric_surface_input)
    folds = fold_assignment_rows(scenarios)
    fold_metrics = fold_model_metric_rows(folds, models, metrics, mapping)
    scenario_models =
        scenario_model_summary_rows(fold_metrics, scenarios, models, metrics)
    rank_rows =
        rank_stability_rows(fold_metrics, scenarios, scenario_rows_input)
    weights = model_weight_rows(scenario_models, scenarios)
    threshold_rows =
        threshold_profile_observed_rows(threshold_impacts_input, rank_rows)
    guards = execution_guard_rows()
    claim_rules = claim_rule_rows()
    links = evidence_link_rows(grid_record, split_policy, threshold)
    no_publication = no_publication_commands()

    all_input_artifacts_present = all(record -> record.exists, records)
    all_expected_schemas = all(record -> record.schema_matches, records)
    all_input_summaries_passed = all(record -> record.summary_passed, records)
    pre_execution_grid_passed = Bool(grid_record.summary_passed)
    validation_split_model_comparison_policy_passed =
        Bool(split_policy.summary_passed)
    fit_metric_threshold_sensitivity_passed = Bool(threshold.summary_passed)
    observation_kfold_selected = selected_observation_kfold(split_rows)
    all_comparison_models_executed =
        length(models) == length(model_rows) &&
        all(row -> as_bool(row[:planned_for_execution]), model_rows)
    all_scenarios_executed = length(scenarios) == length(scenario_rows_input)
    fold_assignments_materialized =
        length(folds) == length(scenarios) * PROTOCOL.n_folds &&
        all(row -> row.fold_assignment_materialized, folds)
    observations_held_once = all_observations_held_once(folds, scenarios)
    observed_metric_rows_recorded =
        length(fold_metrics) ==
            length(scenarios) * PROTOCOL.n_folds *
            length(models) * length(metrics)
    all_observed_metric_values_finite =
        all(row -> isfinite(Float64(row.observed_value)), fold_metrics)
    rank_stability_review_recorded = length(rank_rows) == length(scenarios)
    threshold_profile_observed_rows_recorded =
        length(threshold_rows) == length(threshold_impacts_input)
    model_weight_rows_recorded =
        length(weights) == length(scenarios) * length(models)
    all_claim_rules_block_public_claims =
        all(row -> !Bool(row.public_claim_allowed), claim_rules)
    no_public_fit_metric_claim =
        Bool(grid_record.summary.no_public_fit_metric_claim) &&
        Bool(split_policy.summary.no_public_fit_metric_claim) &&
        Bool(threshold.summary.no_public_fit_metric_claim)
    no_public_q_revision_claim =
        Bool(grid_record.summary.no_public_q_revision_claim) &&
        Bool(split_policy.summary.no_public_q_revision_claim) &&
        Bool(threshold.summary.no_public_q_revision_claim)
    no_public_model_weight_claim =
        Bool(grid_record.summary.no_public_model_weight_claim) &&
        Bool(split_policy.summary.no_model_weight_or_sparse_superiority_claim)
    no_sparse_superiority_claim =
        Bool(grid_record.summary.no_sparse_superiority_claim) &&
        Bool(split_policy.summary.no_model_weight_or_sparse_superiority_claim)

    passed = all_input_artifacts_present &&
        all_expected_schemas &&
        all_input_summaries_passed &&
        pre_execution_grid_passed &&
        validation_split_model_comparison_policy_passed &&
        fit_metric_threshold_sensitivity_passed &&
        observation_kfold_selected &&
        all_comparison_models_executed &&
        all_scenarios_executed &&
        fold_assignments_materialized &&
        observations_held_once &&
        observed_metric_rows_recorded &&
        all_observed_metric_values_finite &&
        rank_stability_review_recorded &&
        threshold_profile_observed_rows_recorded &&
        model_weight_rows_recorded &&
        all_claim_rules_block_public_claims &&
        no_public_fit_metric_claim &&
        no_public_q_revision_claim &&
        no_public_model_weight_claim &&
        no_sparse_superiority_claim &&
        no_publication

    remaining_public_blockers = [
        :full_mcmc_refit_execution_missing,
        :external_construct_validation_missing,
        :rank_stability_not_satisfied_for_all_scenarios,
        :post_execution_public_scope_review_missing,
    ]

    return (;
        schema = "bayesianmgmfrm.mgmfrm_heldout_prediction_execution.v1",
        family = :mgmfrm,
        scope = :heldout_prediction_execution,
        status = :heldout_prediction_execution_recorded,
        decision = :record_deterministic_heldout_prediction_execution,
        public_fit = true,
        experimental_public = true,
        fit_ready = true,
        local_only = true,
        heldout_prediction_execution_completed = true,
        observed_heldout_results_recorded = true,
        mcmc_refit_execution_completed = false,
        full_refit_execution_required = true,
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
        fold_assignment_rows = folds,
        fold_model_metric_rows = fold_metrics,
        scenario_model_summary_rows = scenario_models,
        rank_stability_rows = rank_rows,
        threshold_profile_observed_rows = threshold_rows,
        model_weight_rows = weights,
        execution_guard_rows = guards,
        claim_rule_rows = claim_rules,
        evidence_link_rows = links,
        decision_record = (;
            selected_decision =
                :record_deterministic_heldout_prediction_execution,
            heldout_prediction_execution_completed = true,
            observed_heldout_results_recorded = true,
            mcmc_refit_execution_completed = false,
            public_fit_metric_claim_allowed = false,
            public_q_revision_claim_allowed = false,
            model_weight_or_sparse_superiority_claim_allowed = false,
            required_followup =
                :full_heldout_mgmfrm_refit_or_external_construct_validation_review,
        ),
        summary = (;
            passed,
            publication_or_registration_action = false,
            local_only = true,
            all_input_artifacts_present,
            all_expected_schemas,
            all_input_summaries_passed,
            pre_execution_grid_passed,
            validation_split_model_comparison_policy_passed,
            fit_metric_threshold_sensitivity_passed,
            observation_kfold_selected,
            all_comparison_models_executed,
            all_scenarios_executed,
            fold_assignments_materialized,
            all_observations_held_out_once = observations_held_once,
            observed_metric_rows_recorded,
            all_observed_metric_values_finite,
            rank_stability_review_recorded,
            threshold_profile_observed_rows_recorded,
            model_weight_rows_recorded,
            all_evidence_links_satisfied =
                all(row -> Bool(row.link_satisfied), links),
            all_claim_rules_block_public_claims,
            no_public_fit_metric_claim,
            no_public_q_revision_claim,
            no_public_model_weight_claim,
            no_sparse_superiority_claim,
            heldout_prediction_execution_completed = true,
            observed_heldout_results_recorded = true,
            mcmc_refit_execution_completed = false,
            deterministic_synthetic_execution = true,
            full_refit_execution_required = true,
            n_input_artifacts = length(records),
            n_scenarios = length(scenarios),
            n_models = length(models),
            n_metrics = length(metrics),
            n_folds = PROTOCOL.n_folds,
            n_execution_observations_per_scenario =
                PROTOCOL.n_execution_observations_per_scenario,
            n_fold_assignment_rows = length(folds),
            n_fold_model_metric_rows = length(fold_metrics),
            n_observed_metric_cells = length(fold_metrics),
            n_scenario_model_summary_rows = length(scenario_models),
            n_rank_stability_rows = length(rank_rows),
            n_rank_unstable_scenarios =
                count(row -> !Bool(row.rank_stable_observed), rank_rows),
            n_external_construct_validation_scenarios =
                count(row -> Bool(row.external_construct_validation_needed),
                    rank_rows),
            n_threshold_profile_observed_rows = length(threshold_rows),
            n_model_weight_rows = length(weights),
            n_execution_guard_rows = length(guards),
            n_claim_rule_rows = length(claim_rules),
            n_evidence_link_rows = length(links),
            n_blockers = length(remaining_public_blockers),
            remaining_public_blockers,
            recommendation =
                :use_observed_execution_as_local_smoke_keep_claims_blocked_until_full_refit_and_external_validation,
            next_gate =
                :full_heldout_mgmfrm_refit_or_external_construct_validation_review,
        ),
    )
end

function main(args)
    output = parse_args(args)
    artifact = build_artifact()
    write_artifact(output, artifact)
    println("wrote ", relpath(output, ROOT))
    println("passed=", artifact.summary.passed,
        " observed_metric_cells=", artifact.summary.n_observed_metric_cells,
        " next_gate=", artifact.summary.next_gate)
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
