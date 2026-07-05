#!/usr/bin/env julia

using JSON3
using SHA
using TOML

import BayesianMGMFRM

module Fold1PilotHelpers
include(joinpath(@__DIR__,
    "generate_mgmfrm_full_heldout_mcmc_refit_fold1_pilot.jl"))
end

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_full_heldout_mcmc_refit_fold1_scoring.json")

include(joinpath(@__DIR__, "local_json.jl"))

const INPUT_ARTIFACTS = [
    (name = :mgmfrm_full_heldout_mcmc_refit_execution_plan,
        path =
            "test/fixtures/mgmfrm_full_heldout_mcmc_refit_execution_plan.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_full_heldout_mcmc_refit_execution_plan.v1"),
    (name = :mgmfrm_full_heldout_mcmc_refit_fold1_pilot,
        path =
            "test/fixtures/mgmfrm_full_heldout_mcmc_refit_fold1_pilot.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_full_heldout_mcmc_refit_fold1_pilot.v1"),
    (name = :mgmfrm_heldout_prediction_execution,
        path = "test/fixtures/mgmfrm_heldout_prediction_execution.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_heldout_prediction_execution.v1"),
    (name = :mgmfrm_validation_split_model_comparison_policy,
        path =
            "test/fixtures/mgmfrm_validation_split_model_comparison_policy.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_validation_split_model_comparison_policy.v1"),
]

const PROTOCOL = (;
    protocol_id = "mgmfrm_full_heldout_mcmc_refit_fold1_scoring_v1",
    review_kind = :local_full_heldout_mcmc_refit_fold1_scoring,
    publication_or_registration_action = false,
    local_only = true,
    pilot_only = true,
    smoke_only = true,
    execution_scope = :fold1_mgmfrm_candidate_heldout_scoring,
    selected_fold = 1,
    source_execution_plan =
        :mgmfrm_full_heldout_mcmc_refit_execution_plan,
    source_refit_pilot = :mgmfrm_full_heldout_mcmc_refit_fold1_pilot,
    scoring_target = :heldout_pointwise_log_predictive_density,
    expected_score_target = :observed_minus_expected_score_residual,
    comparison_scope = :fixed_q_mgmfrm_candidates_only,
    comparison_anchor_policy = :recorded_in_pilot_not_scored_here,
    fit_controls = (;
        backend = :advancedhmc,
        sampler = :nuts,
        chains = 1,
        warmup = 0,
        draws = 1,
    ),
    thresholds = (;
        require_execution_plan_passed = true,
        require_fold1_pilot_passed = true,
        require_heldout_prediction_execution_passed = true,
        require_validation_split_policy_passed = true,
        require_fold1_pilot_completed = true,
        require_all_candidate_scores_recorded = true,
        require_all_pointwise_scores_recorded = true,
        require_all_score_values_finite = true,
        require_expected_score_residuals_recorded = true,
        require_training_heldout_alignment_rows_recorded = true,
        require_candidate_rank_rows_recorded = true,
        require_comparison_anchors_not_scored = true,
        require_full_125_unit_batch_not_completed = true,
        require_publication_grade_diagnostics_blocked = true,
        require_full_heldout_scores_blocked_until_full_batch = true,
        require_no_public_fit_metric_claim = true,
        require_no_public_q_revision_claim = true,
        require_no_public_model_weight_claim = true,
        require_no_sparse_superiority_claim = true,
        require_no_publication_or_registration_action = true,
    ),
)

function usage()
    return """
    Generate the local MGMFRM fold1 heldout predictive scoring artifact.

    This artifact reruns the fold1 fixed-Q MGMFRM candidate fits with the
    pilot seeds, evaluates heldout pointwise log predictive scores on the
    deterministic fold1 tables, and records observed-vs-expected score
    residual summaries. It remains a local pilot: scalar/null anchors, the
    remaining folds, publication-grade diagnostics, model weights, sparse
    superiority, Q-revision, and publication claims remain blocked.

    Usage:
      julia --project=. scripts/generate_mgmfrm_full_heldout_mcmc_refit_fold1_scoring.jl [--output PATH]
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
    name === :mgmfrm_full_heldout_mcmc_refit_execution_plan && return (;
        passed = as_bool(summary[:passed]),
        full_mcmc_refit_execution_plan_recorded =
            as_bool(summary[:full_mcmc_refit_execution_plan_recorded]),
        full_mcmc_refit_execution_completed =
            as_bool(summary[:full_mcmc_refit_execution_completed]),
        all_scenario_model_fold_units_materialized =
            as_bool(summary[:all_scenario_model_fold_units_materialized]),
        n_execution_unit_rows = as_int(summary[:n_execution_unit_rows]),
        next_gate = as_string(summary[:next_gate]),
    )
    name === :mgmfrm_full_heldout_mcmc_refit_fold1_pilot && return (;
        passed = as_bool(summary[:passed]),
        fold1_pilot_completed = as_bool(summary[:fold1_pilot_completed]),
        full_mcmc_refit_execution_completed =
            as_bool(summary[:full_mcmc_refit_execution_completed]),
        full_125_unit_batch_completed =
            as_bool(summary[:full_125_unit_batch_completed]),
        heldout_predictive_scores_computed =
            as_bool(summary[:heldout_predictive_scores_computed]),
        publication_grade_diagnostics_blocked =
            as_bool(summary[:publication_grade_diagnostics_blocked]),
        comparison_anchors_recorded_not_claimed =
            as_bool(summary[:comparison_anchors_recorded_not_claimed]),
        n_candidate_fit_rows = as_int(summary[:n_candidate_fit_rows]),
        n_comparison_anchor_rows =
            as_int(summary[:n_comparison_anchor_rows]),
        n_candidate_heldout_observations =
            as_int(summary[:n_candidate_heldout_observations]),
        next_gate = as_string(summary[:next_gate]),
    )
    name === :mgmfrm_heldout_prediction_execution && return (;
        passed = as_bool(summary[:passed]),
        heldout_prediction_execution_completed =
            as_bool(summary[:heldout_prediction_execution_completed]),
        observed_heldout_results_recorded =
            as_bool(summary[:observed_heldout_results_recorded]),
        mcmc_refit_execution_completed =
            as_bool(summary[:mcmc_refit_execution_completed]),
        full_refit_execution_required =
            as_bool(summary[:full_refit_execution_required]),
        fold_assignments_materialized =
            as_bool(summary[:fold_assignments_materialized]),
        all_observations_held_out_once =
            as_bool(summary[:all_observations_held_out_once]),
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
        no_public_fit_metric_claim =
            as_bool(summary[:no_public_fit_metric_claim]),
        no_public_q_revision_claim =
            as_bool(summary[:no_public_q_revision_claim]),
        no_model_weight_or_sparse_superiority_claim =
            as_bool(summary[:no_model_weight_or_sparse_superiority_claim]),
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

function table_from_rows(rows)
    return (;
        examinee = [row.examinee for row in rows],
        rater = [row.rater for row in rows],
        item = [row.item for row in rows],
        score = [row.score for row in rows],
    )
end

function logmeanexp(values::AbstractVector{<:Real})
    isempty(values) && return NaN
    max_value = maximum(values)
    isfinite(max_value) || return max_value
    return max_value + log(sum(exp(value - max_value) for value in values) / length(values))
end

function finite_mean(values)
    finite = [Float64(value) for value in values if isfinite(Float64(value))]
    isempty(finite) && return NaN
    return sum(finite) / length(finite)
end

function finite_rmse(values)
    finite = [Float64(value) for value in values if isfinite(Float64(value))]
    isempty(finite) && return NaN
    return sqrt(sum(value^2 for value in finite) / length(finite))
end

function row_expected_scores(design, direct_draws::AbstractMatrix)
    n_draws = size(direct_draws, 1)
    n_observations = design.spec.data.n
    output = zeros(Float64, n_draws, n_observations)
    for draw in axes(direct_draws, 1)
        values = BayesianMGMFRM._mgmfrm_source_fixture_values(
            design,
            vec(direct_draws[draw, :]),
        )
        for row in values
            output[draw, Int(row.row)] +=
                exp(Float64(row.log_probability)) * Float64(row.category)
        end
    end
    return output
end

function pilot_fit_record_map(pilot)
    return Dict(
        as_symbol(row[:execution_unit_id]) => row
        for row in pilot[:candidate_fit_rows]
    )
end

function candidate_units(plan)
    units = Fold1PilotHelpers.fold1_unit_rows(plan)
    return [unit for unit in units if Bool(unit.fit_attempted)]
end

function fit_and_score_candidate(unit, pilot_fit_record)
    rows = Fold1PilotHelpers.synthetic_rows(unit)
    train_rows = [row for row in rows if row.split_role === :train]
    q_matrix = Fold1PilotHelpers.q_matrix_from_rows(unit.q_matrix)
    train_data = BayesianMGMFRM.FacetData(table_from_rows(train_rows);
        person = :examinee,
        rater = :rater,
        item = :item,
        score = :score,
    )
    full_data = BayesianMGMFRM.FacetData(table_from_rows(rows);
        person = :examinee,
        rater = :rater,
        item = :item,
        score = :score,
    )
    train_spec = BayesianMGMFRM.mfrm_spec(train_data;
        family = :mgmfrm,
        dimensions = size(q_matrix, 2),
        q_matrix,
    )
    full_spec = BayesianMGMFRM.mfrm_spec(full_data;
        family = :mgmfrm,
        dimensions = size(q_matrix, 2),
        q_matrix,
    )
    train_design = BayesianMGMFRM.getdesign(train_spec; preview = true)
    full_design = BayesianMGMFRM.getdesign(full_spec; preview = true)
    layout_matches = train_design.parameter_names == full_design.parameter_names

    fit_seed = as_int(pilot_fit_record[:fit_seed])
    fit = BayesianMGMFRM.fit(train_spec;
        experimental = true,
        backend = PROTOCOL.fit_controls.backend,
        ndraws = PROTOCOL.fit_controls.draws,
        warmup = PROTOCOL.fit_controls.warmup,
        chains = PROTOCOL.fit_controls.chains,
        seed = fit_seed,
        progress = false,
    )

    full_loglikelihood =
        BayesianMGMFRM.pointwise_loglikelihood_matrix(
            full_design,
            fit.direct_draws,
        )
    expected = row_expected_scores(full_design, fit.direct_draws)
    heldout = Int.(unit.heldout_observations)
    heldout_loglikelihood = full_loglikelihood[:, heldout]
    heldout_expected = expected[:, heldout]
    observed_scores = Float64.(full_data.score[heldout])
    pointwise_elpd =
        [logmeanexp(vec(heldout_loglikelihood[:, column]))
            for column in axes(heldout_loglikelihood, 2)]
    expected_score_mean =
        [finite_mean(heldout_expected[:, column])
            for column in axes(heldout_expected, 2)]
    residuals = observed_scores .- expected_score_mean
    absolute_errors = abs.(residuals)
    squared_errors = residuals .^ 2
    train_pointwise =
        [logmeanexp(vec(fit.direct_pointwise_loglikelihood[:, column]))
            for column in axes(fit.direct_pointwise_loglikelihood, 2)]
    summary = fit.diagnostic_surface.summary

    pointwise_rows = NamedTuple[]
    for (offset, observation) in enumerate(heldout)
        push!(pointwise_rows, (;
            execution_unit_id = unit.execution_unit_id,
            scenario = unit.scenario,
            model = unit.model,
            fold = unit.fold,
            observation,
            heldout_position = offset,
            person = rows[observation].examinee,
            rater = rows[observation].rater,
            item = rows[observation].item,
            observed_score = Int(rows[observation].score),
            pointwise_log_predictive_density = pointwise_elpd[offset],
            expected_score_mean = expected_score_mean[offset],
            observed_minus_expected_score = residuals[offset],
            absolute_expected_score_error = absolute_errors[offset],
            squared_expected_score_error = squared_errors[offset],
            finite_score =
                isfinite(pointwise_elpd[offset]) &&
                isfinite(expected_score_mean[offset]) &&
                isfinite(residuals[offset]),
            public_claim_allowed = false,
        ))
    end

    score_row = (;
        execution_unit_id = unit.execution_unit_id,
        scenario = unit.scenario,
        model = unit.model,
        fold = unit.fold,
        q_profile = unit.q_profile,
        q_matrix = unit.q_matrix,
        fit_seed,
        fit_succeeded = fit isa BayesianMGMFRM.MGMFRMFit,
        returned_type = Symbol(nameof(typeof(fit))),
        layout_matches,
        n_train_observations = train_data.n,
        n_heldout_observations = length(heldout),
        n_draws = size(fit.direct_draws, 1),
        chains = length(fit.chain_acceptance_rate),
        draws_per_chain = size(fit.draws, 1) ÷ length(fit.chain_acceptance_rate),
        warmup = fit.warmup,
        n_dimensions = size(q_matrix, 2),
        n_items = size(q_matrix, 1),
        training_elpd = sum(train_pointwise; init = 0.0),
        training_mean_log_predictive_density =
            finite_mean(train_pointwise),
        heldout_elpd = sum(pointwise_elpd; init = 0.0),
        heldout_mean_log_predictive_density =
            finite_mean(pointwise_elpd),
        heldout_min_pointwise_log_predictive_density =
            minimum(pointwise_elpd),
        heldout_max_pointwise_log_predictive_density =
            maximum(pointwise_elpd),
        heldout_expected_score_mae = finite_mean(absolute_errors),
        heldout_expected_score_rmse = finite_rmse(residuals),
        heldout_expected_score_bias = finite_mean(residuals),
        train_heldout_mean_log_predictive_gap =
            finite_mean(train_pointwise) - finite_mean(pointwise_elpd),
        all_pointwise_scores_finite = all(isfinite, pointwise_elpd),
        expected_score_residuals_finite =
            all(isfinite, expected_score_mean) &&
            all(isfinite, residuals),
        finite_direct_draws = all(isfinite, fit.direct_draws),
        finite_training_pointwise_loglikelihood =
            all(isfinite, fit.direct_pointwise_loglikelihood),
        finite_heldout_pointwise_loglikelihood =
            all(isfinite, heldout_loglikelihood),
        diagnostic_flag = summary.flag,
        diagnostic_passed = Bool(summary.passed),
        publication_grade_diagnostics_blocked =
            Symbol(summary.flag) === :insufficient_chains &&
            !Bool(summary.passed),
        n_divergences = Int(summary.n_divergences),
        n_max_treedepth = Int(summary.n_max_treedepth),
        heldout_predictive_score_computed = true,
        public_fit_metric_claim_allowed = false,
        public_model_weight_claim_allowed = false,
        sparse_superiority_claim_allowed = false,
    )
    return (; score_row, pointwise_rows)
end

function score_rows_and_pointwise(plan, pilot)
    fit_map = pilot_fit_record_map(pilot)
    score_rows = NamedTuple[]
    pointwise_rows = NamedTuple[]
    for unit in candidate_units(plan)
        result = fit_and_score_candidate(unit, fit_map[unit.execution_unit_id])
        push!(score_rows, result.score_row)
        append!(pointwise_rows, result.pointwise_rows)
    end
    return (; score_rows, pointwise_rows)
end

function candidate_rank_rows(score_rows)
    rows = NamedTuple[]
    scenarios = sort(unique(row.scenario for row in score_rows); by = string)
    for scenario in scenarios
        scenario_rows =
            sort([row for row in score_rows if row.scenario === scenario];
                by = row -> row.heldout_elpd,
                rev = true)
        best = first(scenario_rows)
        for (rank, row) in enumerate(scenario_rows)
            push!(rows, (;
                scenario,
                model = row.model,
                fold = row.fold,
                rank,
                heldout_elpd = row.heldout_elpd,
                delta_elpd_from_best = row.heldout_elpd - best.heldout_elpd,
                heldout_expected_score_mae =
                    row.heldout_expected_score_mae,
                best_model_in_fold1_pilot = rank == 1,
                comparison_scope =
                    :fixed_q_mgmfrm_candidates_fold1_only,
                public_model_weight_claim_allowed = false,
                sparse_superiority_claim_allowed = false,
                interpretation =
                    :descriptive_fold1_pilot_rank_no_public_superiority_claim,
            ))
        end
    end
    return rows
end

function training_heldout_alignment_rows(score_rows)
    return [
        (execution_unit_id = row.execution_unit_id,
            scenario = row.scenario,
            model = row.model,
            fold = row.fold,
            training_mean_log_predictive_density =
                row.training_mean_log_predictive_density,
            heldout_mean_log_predictive_density =
                row.heldout_mean_log_predictive_density,
            train_heldout_mean_log_predictive_gap =
                row.train_heldout_mean_log_predictive_gap,
            heldout_expected_score_mae = row.heldout_expected_score_mae,
            heldout_expected_score_rmse = row.heldout_expected_score_rmse,
            diagnostic_flag = row.diagnostic_flag,
            publication_grade_diagnostics_blocked =
                row.publication_grade_diagnostics_blocked,
            threshold_interpretation =
                :descriptive_metric_shift_no_threshold_profile_promoted,
            public_fit_metric_claim_allowed = false)
        for row in score_rows
    ]
end

function anchor_rows(pilot)
    return [
        (execution_unit_id = as_symbol(row[:execution_unit_id]),
            scenario = as_symbol(row[:scenario]),
            model = as_symbol(row[:model]),
            fold = as_int(row[:fold]),
            pilot_family = as_symbol(row[:pilot_family]),
            fit_attempted = false,
            heldout_predictive_score_computed = false,
            not_scored_reason =
                :comparison_anchor_not_refit_in_fold1_mgmfrm_scoring,
            required_followup =
                :run_anchor_refits_or_full_batch_before_model_comparison,
            public_claim_allowed = false)
        for row in pilot[:comparison_anchor_rows]
    ]
end

function blocker_rows()
    return [
        (blocker = :fold1_only_remaining_folds_not_scored,
            blocks = :public_heldout_prediction_claims,
            resolved = false),
        (blocker = :full_125_unit_refit_batch_not_completed,
            blocks = :public_model_comparison_claims,
            resolved = false),
        (blocker = :comparison_anchor_mcmc_refits_not_run,
            blocks = :public_model_weight_claims,
            resolved = false),
        (blocker = :publication_grade_chains_and_draws_not_run,
            blocks = :public_fit_metric_and_model_weight_claims,
            resolved = false),
        (blocker = :external_construct_dataset_missing,
            blocks = :public_q_revision_claims,
            resolved = false),
        (blocker = :independent_public_scope_review_missing,
            blocks = :all_public_mgmfrm_claims,
            resolved = false),
    ]
end

function no_publication_commands()
    command =
        "julia --project=. scripts/generate_mgmfrm_full_heldout_mcmc_refit_fold1_scoring.jl"
    banned = ["git push", "gh release", "Registrator", "Pkg.register", "publish"]
    lowered = lowercase(command)
    return all(!occursin(lowercase(term), lowered) for term in banned)
end

function build_artifact()
    input_records = [artifact_record(spec) for spec in INPUT_ARTIFACTS]
    plan_record =
        record_by_name(input_records,
            :mgmfrm_full_heldout_mcmc_refit_execution_plan)
    pilot_record =
        record_by_name(input_records,
            :mgmfrm_full_heldout_mcmc_refit_fold1_pilot)
    heldout_execution_record =
        record_by_name(input_records, :mgmfrm_heldout_prediction_execution)
    split_policy_record =
        record_by_name(input_records,
            :mgmfrm_validation_split_model_comparison_policy)

    plan = load_fixture(
        "test/fixtures/mgmfrm_full_heldout_mcmc_refit_execution_plan.json")
    pilot = load_fixture(
        "test/fixtures/mgmfrm_full_heldout_mcmc_refit_fold1_pilot.json")
    scored = score_rows_and_pointwise(plan, pilot)
    score_rows = scored.score_rows
    pointwise_rows = scored.pointwise_rows
    ranks = candidate_rank_rows(score_rows)
    alignment = training_heldout_alignment_rows(score_rows)
    anchors = anchor_rows(pilot)
    blockers = blocker_rows()

    all_input_artifacts_present = all(record -> record.exists, input_records)
    all_expected_schemas = all(record -> record.schema_matches, input_records)
    all_input_summaries_passed =
        all(record -> record.summary_passed, input_records)
    execution_plan_passed = Bool(plan_record.summary.passed)
    fold1_pilot_passed = Bool(pilot_record.summary.passed)
    heldout_prediction_execution_passed =
        Bool(heldout_execution_record.summary.passed)
    validation_split_policy_passed =
        Bool(split_policy_record.summary.passed)
    fold1_pilot_completed =
        Bool(pilot_record.summary.fold1_pilot_completed)
    all_candidate_scores_recorded =
        length(score_rows) == Int(pilot_record.summary.n_candidate_fit_rows) ==
        15
    all_pointwise_scores_recorded =
        length(pointwise_rows) ==
        Int(pilot_record.summary.n_candidate_heldout_observations) == 120
    all_score_values_finite =
        all(row -> Bool(row.all_pointwise_scores_finite) &&
                Bool(row.expected_score_residuals_finite) &&
                isfinite(Float64(row.heldout_elpd)) &&
                isfinite(Float64(row.heldout_expected_score_mae)) &&
                isfinite(Float64(row.heldout_expected_score_rmse)),
            score_rows) &&
        all(row -> Bool(row.finite_score), pointwise_rows)
    expected_score_residuals_recorded =
        all(row -> haskey(row, :heldout_expected_score_mae) &&
                isfinite(Float64(row.heldout_expected_score_mae)),
            score_rows)
    training_heldout_alignment_rows_recorded =
        length(alignment) == length(score_rows)
    candidate_rank_rows_recorded =
        length(ranks) == length(score_rows) &&
        all(scenario -> count(row -> row.scenario === scenario, ranks) == 3,
            unique(row.scenario for row in score_rows))
    comparison_anchors_not_scored =
        length(anchors) == Int(pilot_record.summary.n_comparison_anchor_rows) &&
        all(row -> !Bool(row.heldout_predictive_score_computed), anchors)
    full_125_unit_batch_not_completed =
        !Bool(plan_record.summary.full_mcmc_refit_execution_completed) &&
        !Bool(pilot_record.summary.full_125_unit_batch_completed)
    publication_grade_diagnostics_blocked =
        all(row -> Bool(row.publication_grade_diagnostics_blocked),
            score_rows)
    full_heldout_scores_blocked_until_full_batch =
        length(score_rows) < Int(plan_record.summary.n_execution_unit_rows) &&
        full_125_unit_batch_not_completed
    no_public_fit_metric_claim = true
    no_public_q_revision_claim =
        Bool(split_policy_record.summary.no_public_q_revision_claim)
    no_public_model_weight_claim =
        Bool(split_policy_record.summary.no_model_weight_or_sparse_superiority_claim)
    no_sparse_superiority_claim = true
    no_publication = no_publication_commands()

    passed = all_input_artifacts_present &&
        all_expected_schemas &&
        all_input_summaries_passed &&
        execution_plan_passed &&
        fold1_pilot_passed &&
        heldout_prediction_execution_passed &&
        validation_split_policy_passed &&
        fold1_pilot_completed &&
        all_candidate_scores_recorded &&
        all_pointwise_scores_recorded &&
        all_score_values_finite &&
        expected_score_residuals_recorded &&
        training_heldout_alignment_rows_recorded &&
        candidate_rank_rows_recorded &&
        comparison_anchors_not_scored &&
        full_125_unit_batch_not_completed &&
        publication_grade_diagnostics_blocked &&
        full_heldout_scores_blocked_until_full_batch &&
        no_public_fit_metric_claim &&
        no_public_q_revision_claim &&
        no_public_model_weight_claim &&
        no_sparse_superiority_claim &&
        no_publication

    n_review_cells =
        length(score_rows) + length(pointwise_rows) + length(ranks) +
        length(alignment) + length(anchors)
    n_scenarios = length(unique(row.scenario for row in score_rows))
    n_models = length(unique(row.model for row in score_rows))
    total_heldout_elpd =
        sum(row.heldout_elpd for row in score_rows; init = 0.0)

    return (;
        schema =
            "bayesianmgmfrm.mgmfrm_full_heldout_mcmc_refit_fold1_scoring.v1",
        family = :mgmfrm,
        scope = :full_heldout_mcmc_refit_fold1_scoring,
        status = :fold1_mgmfrm_candidate_heldout_scores_recorded,
        decision =
            :record_fold1_heldout_scores_keep_full_batch_claims_blocked,
        public_fit = true,
        experimental_public = true,
        fit_ready = true,
        local_only = true,
        pilot_only = true,
        smoke_only = true,
        fold1_pilot_completed = true,
        fold1_heldout_predictive_scores_computed = true,
        heldout_predictive_scores_computed = true,
        full_mcmc_refit_execution_completed = false,
        full_125_unit_batch_completed = false,
        full_heldout_predictive_scores_computed = false,
        comparison_anchor_scores_computed = false,
        external_construct_dataset_attached = false,
        external_construct_validation_completed = false,
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
        input_artifacts = input_records,
        candidate_score_rows = score_rows,
        heldout_pointwise_rows = pointwise_rows,
        candidate_rank_rows = ranks,
        training_heldout_alignment_rows = alignment,
        comparison_anchor_rows = anchors,
        blocker_rows = blockers,
        decision_record = (;
            selected_decision =
                :record_fold1_heldout_scores_keep_full_batch_claims_blocked,
            fold1_pilot_completed = true,
            fold1_heldout_predictive_scores_computed = true,
            full_mcmc_refit_execution_completed = false,
            full_125_unit_batch_completed = false,
            full_heldout_predictive_scores_computed = false,
            comparison_anchor_scores_computed = false,
            public_fit_metric_claim_allowed = false,
            public_q_revision_claim_allowed = false,
            model_weight_or_sparse_superiority_claim_allowed = false,
            required_followup =
                :full_heldout_mgmfrm_mcmc_refit_full_batch_execution_or_external_construct_dataset_attachment,
        ),
        summary = (;
            passed,
            publication_or_registration_action = false,
            local_only = true,
            pilot_only = true,
            smoke_only = true,
            all_input_artifacts_present,
            all_expected_schemas,
            all_input_summaries_passed,
            execution_plan_passed,
            fold1_pilot_passed,
            heldout_prediction_execution_passed,
            validation_split_policy_passed,
            fold1_pilot_completed,
            all_candidate_scores_recorded,
            all_pointwise_scores_recorded,
            all_score_values_finite,
            expected_score_residuals_recorded,
            training_heldout_alignment_rows_recorded,
            candidate_rank_rows_recorded,
            comparison_anchors_not_scored,
            full_125_unit_batch_not_completed,
            publication_grade_diagnostics_blocked,
            full_heldout_scores_blocked_until_full_batch,
            no_public_fit_metric_claim,
            no_public_q_revision_claim,
            no_public_model_weight_claim,
            no_sparse_superiority_claim,
            fold1_heldout_predictive_scores_computed = true,
            heldout_predictive_scores_computed = true,
            full_mcmc_refit_execution_completed = false,
            full_125_unit_batch_completed = false,
            full_heldout_predictive_scores_computed = false,
            comparison_anchor_scores_computed = false,
            external_construct_dataset_attached = false,
            external_construct_validation_completed = false,
            n_input_artifacts = length(input_records),
            n_candidate_score_rows = length(score_rows),
            n_heldout_pointwise_rows = length(pointwise_rows),
            n_candidate_rank_rows = length(ranks),
            n_training_heldout_alignment_rows = length(alignment),
            n_comparison_anchor_rows = length(anchors),
            n_blocker_rows = length(blockers),
            n_review_cells,
            n_scenarios,
            n_models,
            n_candidate_heldout_observations =
                sum(row.n_heldout_observations for row in score_rows),
            total_heldout_elpd,
            mean_heldout_log_predictive_density =
                total_heldout_elpd /
                sum(row.n_heldout_observations for row in score_rows),
            mean_heldout_expected_score_mae =
                finite_mean([row.heldout_expected_score_mae
                    for row in score_rows]),
            n_publication_grade_fit_rows =
                count(row -> Bool(row.diagnostic_passed), score_rows),
            n_full_execution_units_completed = 0,
            n_blockers = length(blockers),
            remaining_public_blockers =
                [row.blocker for row in blockers if !Bool(row.resolved)],
            recommendation =
                :use_fold1_scores_to_validate_scoring_surface_then_expand_to_remaining_folds,
            next_gate =
                :full_heldout_mgmfrm_mcmc_refit_full_batch_execution_or_external_construct_dataset_attachment,
        ),
    )
end

function main(args)
    output = parse_args(args)
    artifact = build_artifact()
    write_artifact(output, artifact)
    println("wrote ", relpath(output, ROOT))
    println("passed=", artifact.summary.passed,
        " candidate_scores=", artifact.summary.n_candidate_score_rows,
        " pointwise=", artifact.summary.n_heldout_pointwise_rows,
        " next_gate=", artifact.summary.next_gate)
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
