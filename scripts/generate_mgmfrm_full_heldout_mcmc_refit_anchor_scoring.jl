#!/usr/bin/env julia

using JSON3
using SHA
using TOML

import BayesianMGMFRM

module CandidateBatchScoring
include(joinpath(@__DIR__,
    "generate_mgmfrm_full_heldout_mcmc_refit_candidate_batch_scoring.jl"))
end

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_full_heldout_mcmc_refit_anchor_scoring.json")

include(joinpath(@__DIR__, "local_json.jl"))

const ANCHOR_MODELS = (:scalar_gmfrm_baseline, :null_or_intercept_reference)

const INPUT_ARTIFACTS = [
    (name = :mgmfrm_full_heldout_mcmc_refit_execution_plan,
        path =
            "test/fixtures/mgmfrm_full_heldout_mcmc_refit_execution_plan.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_full_heldout_mcmc_refit_execution_plan.v1"),
    (name = :mgmfrm_full_heldout_mcmc_refit_candidate_batch_scoring,
        path =
            "test/fixtures/mgmfrm_full_heldout_mcmc_refit_candidate_batch_scoring.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_full_heldout_mcmc_refit_candidate_batch_scoring.v1"),
    (name = :mgmfrm_heldout_prediction_execution,
        path =
            "test/fixtures/mgmfrm_heldout_prediction_execution.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_heldout_prediction_execution.v1"),
    (name = :mgmfrm_validation_split_model_comparison_policy,
        path =
            "test/fixtures/mgmfrm_validation_split_model_comparison_policy.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_validation_split_model_comparison_policy.v1"),
]

const PROTOCOL = (;
    protocol_id = "mgmfrm_full_heldout_mcmc_refit_anchor_scoring_v1",
    review_kind = :local_full_heldout_anchor_scoring,
    publication_or_registration_action = false,
    local_only = true,
    pilot_only = true,
    smoke_only = true,
    execution_scope = :all_fold_scalar_and_reference_anchor_scoring,
    selected_folds = (1, 2, 3, 4, 5),
    source_execution_plan =
        :mgmfrm_full_heldout_mcmc_refit_execution_plan,
    source_candidate_batch =
        :mgmfrm_full_heldout_mcmc_refit_candidate_batch_scoring,
    scoring_target = :heldout_pointwise_log_predictive_density,
    expected_score_target = :observed_minus_expected_score_residual,
    anchor_models = ANCHOR_MODELS,
    scalar_anchor_policy =
        :guarded_scalar_gmfrm_rater_consistency_refit_scored,
    reference_anchor_policy =
        :training_fold_intercept_category_rate_with_dirichlet_smoothing,
    comparison_scope =
        :fixed_q_mgmfrm_candidates_with_scalar_and_reference_anchors,
    fit_controls = (;
        backend = :advancedhmc,
        sampler = :nuts,
        chains = 1,
        warmup = 0,
        draws = 1,
        scalar_seed_offset = 200000,
    ),
    reference_controls = (;
        smoothing = :symmetric_dirichlet,
        alpha = 1.0,
        categories = (0, 1, 2),
    ),
    thresholds = (;
        require_execution_plan_passed = true,
        require_candidate_batch_scoring_passed = true,
        require_heldout_prediction_execution_passed = true,
        require_validation_split_policy_passed = true,
        require_anchor_units_selected = true,
        require_scalar_anchor_refits_succeeded = true,
        require_reference_anchor_scores_recorded = true,
        require_all_anchor_scores_recorded = true,
        require_all_anchor_pointwise_scores_recorded = true,
        require_all_anchor_score_values_finite = true,
        require_anchor_fold_completion_rows_recorded = true,
        require_anchor_kfold_rows_recorded = true,
        require_combined_model_kfold_rows_recorded = true,
        require_combined_rank_rows_recorded = true,
        require_candidate_and_anchor_scores_cover_125_units = true,
        require_comparison_anchor_scores_computed = true,
        require_publication_grade_diagnostics_blocked = true,
        require_external_construct_dataset_still_required = true,
        require_no_public_fit_metric_claim = true,
        require_no_public_q_revision_claim = true,
        require_no_public_model_weight_claim = true,
        require_no_sparse_superiority_claim = true,
        require_no_publication_or_registration_action = true,
    ),
)

function usage()
    return """
    Generate the local MGMFRM heldout anchor scoring artifact.

    This artifact scores the scalar GMFRM and intercept/reference anchors for
    every scenario x fold cell in the full heldout execution plan. It then
    joins those anchor k-fold summaries to the existing fixed-Q MGMFRM
    candidate batch scores for a descriptive 125-unit comparison. It remains
    local and smoke-sized: publication-grade diagnostics, public model-weight
    claims, sparse-superiority claims, Q-revision claims, and publication
    actions remain blocked.

    Usage:
      julia --project=. scripts/generate_mgmfrm_full_heldout_mcmc_refit_anchor_scoring.jl [--output PATH]
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
        n_scenarios = as_int(summary[:n_scenarios]),
        n_models = as_int(summary[:n_models]),
        n_folds = as_int(summary[:n_folds]),
        next_gate = as_string(summary[:next_gate]),
    )
    name === :mgmfrm_full_heldout_mcmc_refit_candidate_batch_scoring &&
        return (;
            passed = as_bool(summary[:passed]),
            fixed_q_mgmfrm_candidate_batch_completed =
                as_bool(summary[:fixed_q_mgmfrm_candidate_batch_completed]),
            fixed_q_mgmfrm_candidate_heldout_scores_computed =
                as_bool(summary[
                    :fixed_q_mgmfrm_candidate_heldout_scores_computed]),
            comparison_anchor_scores_computed =
                as_bool(summary[:comparison_anchor_scores_computed]),
            n_candidate_score_rows =
                as_int(summary[:n_candidate_score_rows]),
            n_heldout_pointwise_rows =
                as_int(summary[:n_heldout_pointwise_rows]),
            n_scenario_model_kfold_rows =
                as_int(summary[:n_scenario_model_kfold_rows]),
            n_comparison_anchor_rows =
                as_int(summary[:n_comparison_anchor_rows]),
            n_full_execution_units_completed =
                as_int(summary[:n_full_execution_units_completed]),
            n_full_execution_units_remaining =
                as_int(summary[:n_full_execution_units_remaining]),
            next_gate = as_string(summary[:next_gate]),
        )
    name === :mgmfrm_heldout_prediction_execution && return (;
        passed = as_bool(summary[:passed]),
        heldout_prediction_execution_completed =
            as_bool(summary[:heldout_prediction_execution_completed]),
        mcmc_refit_execution_completed =
            as_bool(summary[:mcmc_refit_execution_completed]),
        full_refit_execution_required =
            as_bool(summary[:full_refit_execution_required]),
        fold_assignments_materialized =
            as_bool(summary[:fold_assignments_materialized]),
        all_observations_held_out_once =
            as_bool(summary[:all_observations_held_out_once]),
        n_scenarios = as_int(summary[:n_scenarios]),
        n_models = as_int(summary[:n_models]),
        n_folds = as_int(summary[:n_folds]),
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

function anchor_role(model::Symbol)
    model === :scalar_gmfrm_baseline &&
        return :scalar_gmfrm_anchor_refit_scored
    model === :null_or_intercept_reference &&
        return :intercept_reference_anchor_scored
    error("unknown anchor model: $model")
end

function scenario_n_items(scenario::Symbol)
    profile = CandidateBatchScoring.FoldPilotHelpers.q_profile(
        scenario,
        :confirmatory_mgmfrm_current_q,
    )
    return size(profile.q_matrix, 1)
end

function anchor_unit_rows(plan)
    rows = NamedTuple[]
    for unit in CandidateBatchScoring.candidate_batch_unit_rows(plan)
        unit.model in ANCHOR_MODELS || continue
        n_items = scenario_n_items(unit.scenario)
        scalar_anchor = unit.model === :scalar_gmfrm_baseline
        push!(rows, (;
            execution_unit_id = unit.execution_unit_id,
            scenario = unit.scenario,
            model = unit.model,
            fold = unit.fold,
            split = unit.split,
            anchor_family = scalar_anchor ?
                :gmfrm_scalar_baseline_anchor : :reference_anchor,
            anchor_role = anchor_role(unit.model),
            scoring_method = scalar_anchor ?
                :guarded_scalar_gmfrm_mcmc_refit :
                :analytic_intercept_category_rate,
            mcmc_refit_attempted = scalar_anchor,
            analytic_reference_scored = !scalar_anchor,
            n_dimensions = scalar_anchor ? 1 : 0,
            n_items,
            n_train_observations = unit.n_train_observations,
            n_heldout_observations = unit.n_heldout_observations,
            heldout_observations = unit.heldout_observations,
            planned_minimum_chains = unit.planned_minimum_chains,
            planned_minimum_draws_per_chain =
                unit.planned_minimum_draws_per_chain,
            planned_minimum_warmup_per_chain =
                unit.planned_minimum_warmup_per_chain,
            anchor_chains = scalar_anchor ? PROTOCOL.fit_controls.chains : 0,
            anchor_draws_per_chain =
                scalar_anchor ? PROTOCOL.fit_controls.draws : 0,
            anchor_warmup_per_chain =
                scalar_anchor ? PROTOCOL.fit_controls.warmup : 0,
            plan_random_seed = unit.plan_random_seed,
            rank_ambiguity_resolution_required =
                unit.rank_ambiguity_resolution_required,
            external_construct_validation_required =
                unit.external_construct_validation_required,
            full_unit_execution_status = unit.full_unit_execution_status,
            public_claim_allowed = false,
        ))
    end
    return rows
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
    return max_value + log(sum(exp(value - max_value) for value in values) /
                           length(values))
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
    fixture_values = design.spec.family === :gmfrm ?
        BayesianMGMFRM._gmfrm_source_fixture_values :
        BayesianMGMFRM._mgmfrm_source_fixture_values
    for draw in axes(direct_draws, 1)
        values = fixture_values(design, vec(direct_draws[draw, :]))
        for row in values
            output[draw, Int(row.row)] +=
                exp(Float64(row.log_probability)) * Float64(row.category)
        end
    end
    return output
end

function scalar_anchor_score(unit)
    rows = CandidateBatchScoring.FoldPilotHelpers.synthetic_rows(unit)
    train_rows = [row for row in rows if row.split_role === :train]
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
        family = :gmfrm,
        discrimination = :rater,
    )
    full_spec = BayesianMGMFRM.mfrm_spec(full_data;
        family = :gmfrm,
        discrimination = :rater,
    )
    train_design = BayesianMGMFRM.getdesign(train_spec; preview = true)
    full_design = BayesianMGMFRM.getdesign(full_spec; preview = true)
    layout_matches = train_design.parameter_names == full_design.parameter_names
    fit_seed = Int(unit.plan_random_seed) +
        PROTOCOL.fit_controls.scalar_seed_offset

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

    pointwise_rows = heldout_pointwise_rows(
        unit,
        rows,
        heldout,
        pointwise_elpd,
        expected_score_mean,
        residuals,
        absolute_errors,
        squared_errors,
    )
    score_row = (;
        execution_unit_id = unit.execution_unit_id,
        scenario = unit.scenario,
        model = unit.model,
        fold = unit.fold,
        anchor_family = unit.anchor_family,
        anchor_role = unit.anchor_role,
        scoring_method = unit.scoring_method,
        fit_seed,
        fit_succeeded = fit isa BayesianMGMFRM.GMFRMFit,
        scoring_succeeded = true,
        returned_type = Symbol(nameof(typeof(fit))),
        layout_matches,
        mcmc_refit_attempted = true,
        analytic_reference_scored = false,
        n_train_observations = train_data.n,
        n_heldout_observations = length(heldout),
        n_draws = size(fit.direct_draws, 1),
        chains = length(fit.chain_acceptance_rate),
        draws_per_chain = size(fit.draws, 1) ÷
            length(fit.chain_acceptance_rate),
        warmup = fit.warmup,
        n_dimensions = 1,
        n_items = unit.n_items,
        training_elpd = sum(train_pointwise; init = 0.0),
        training_mean_log_predictive_density = finite_mean(train_pointwise),
        heldout_elpd = sum(pointwise_elpd; init = 0.0),
        heldout_mean_log_predictive_density = finite_mean(pointwise_elpd),
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
    return (; score_row, pointwise_rows, probability_rows = NamedTuple[])
end

function reference_probabilities(train_rows, categories::Vector{Int})
    alpha = Float64(PROTOCOL.reference_controls.alpha)
    counts = Dict(category => 0 for category in categories)
    for row in train_rows
        counts[Int(row.score)] = counts[Int(row.score)] + 1
    end
    denominator = length(train_rows) + alpha * length(categories)
    probabilities = Dict(
        category => (counts[category] + alpha) / denominator
        for category in categories
    )
    expected_score =
        sum(Float64(category) * probabilities[category] for category in categories)
    return (; counts, probabilities, expected_score)
end

function reference_anchor_score(unit)
    rows = CandidateBatchScoring.FoldPilotHelpers.synthetic_rows(unit)
    train_rows = [row for row in rows if row.split_role === :train]
    categories = Int.(collect(PROTOCOL.reference_controls.categories))
    reference = reference_probabilities(train_rows, categories)
    heldout = Int.(unit.heldout_observations)
    pointwise_elpd =
        [log(reference.probabilities[Int(rows[observation].score)])
            for observation in heldout]
    expected_score_mean = fill(reference.expected_score, length(heldout))
    observed_scores = [Float64(rows[observation].score) for observation in heldout]
    residuals = observed_scores .- expected_score_mean
    absolute_errors = abs.(residuals)
    squared_errors = residuals .^ 2
    train_pointwise =
        [log(reference.probabilities[Int(row.score)]) for row in train_rows]
    pointwise_rows = heldout_pointwise_rows(
        unit,
        rows,
        heldout,
        pointwise_elpd,
        expected_score_mean,
        residuals,
        absolute_errors,
        squared_errors,
    )
    probability_rows = [
        (execution_unit_id = unit.execution_unit_id,
            scenario = unit.scenario,
            model = unit.model,
            fold = unit.fold,
            category,
            training_count = reference.counts[category],
            smoothing_alpha = Float64(PROTOCOL.reference_controls.alpha),
            smoothed_probability = reference.probabilities[category],
            public_claim_allowed = false)
        for category in categories
    ]
    score_row = (;
        execution_unit_id = unit.execution_unit_id,
        scenario = unit.scenario,
        model = unit.model,
        fold = unit.fold,
        anchor_family = unit.anchor_family,
        anchor_role = unit.anchor_role,
        scoring_method = unit.scoring_method,
        fit_seed = missing,
        fit_succeeded = true,
        scoring_succeeded = true,
        returned_type = :AnalyticInterceptReference,
        layout_matches = true,
        mcmc_refit_attempted = false,
        analytic_reference_scored = true,
        n_train_observations = length(train_rows),
        n_heldout_observations = length(heldout),
        n_draws = 1,
        chains = 0,
        draws_per_chain = 0,
        warmup = 0,
        n_dimensions = 0,
        n_items = unit.n_items,
        training_elpd = sum(train_pointwise; init = 0.0),
        training_mean_log_predictive_density = finite_mean(train_pointwise),
        heldout_elpd = sum(pointwise_elpd; init = 0.0),
        heldout_mean_log_predictive_density = finite_mean(pointwise_elpd),
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
        finite_direct_draws = true,
        finite_training_pointwise_loglikelihood = all(isfinite, train_pointwise),
        finite_heldout_pointwise_loglikelihood = all(isfinite, pointwise_elpd),
        diagnostic_flag = :analytic_reference_no_mcmc,
        diagnostic_passed = false,
        publication_grade_diagnostics_blocked = true,
        n_divergences = 0,
        n_max_treedepth = 0,
        heldout_predictive_score_computed = true,
        public_fit_metric_claim_allowed = false,
        public_model_weight_claim_allowed = false,
        sparse_superiority_claim_allowed = false,
    )
    return (; score_row, pointwise_rows, probability_rows)
end

function heldout_pointwise_rows(
        unit,
        rows,
        heldout,
        pointwise_elpd,
        expected_score_mean,
        residuals,
        absolute_errors,
        squared_errors)
    output = NamedTuple[]
    for (offset, observation) in enumerate(heldout)
        push!(output, (;
            execution_unit_id = unit.execution_unit_id,
            scenario = unit.scenario,
            model = unit.model,
            fold = unit.fold,
            anchor_family = unit.anchor_family,
            scoring_method = unit.scoring_method,
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
    return output
end

function score_rows_and_pointwise(units)
    score_rows = NamedTuple[]
    pointwise_rows = NamedTuple[]
    probability_rows = NamedTuple[]
    for unit in units
        result = unit.model === :scalar_gmfrm_baseline ?
            scalar_anchor_score(unit) :
            reference_anchor_score(unit)
        push!(score_rows, result.score_row)
        append!(pointwise_rows, result.pointwise_rows)
        append!(probability_rows, result.probability_rows)
    end
    return (; score_rows, pointwise_rows, probability_rows)
end

function anchor_fold_completion_rows(score_rows, pointwise_rows)
    rows = NamedTuple[]
    scenarios = sort(unique(row.scenario for row in score_rows); by = string)
    folds = sort(unique(row.fold for row in score_rows))
    for scenario in scenarios, fold in folds
        fold_scores =
            [row for row in score_rows if row.scenario === scenario &&
                                          Int(row.fold) == fold]
        fold_pointwise =
            [row for row in pointwise_rows if row.scenario === scenario &&
                                               Int(row.fold) == fold]
        push!(rows, (;
            scenario,
            fold,
            n_anchor_models_scored = length(fold_scores),
            n_heldout_pointwise_rows = length(fold_pointwise),
            heldout_observations =
                sort(unique(row.observation for row in fold_pointwise)),
            anchor_fold_complete =
                length(fold_scores) == length(ANCHOR_MODELS) &&
                length(fold_pointwise) ==
                    sum(row.n_heldout_observations for row in fold_scores),
            public_claim_allowed = false,
        ))
    end
    return rows
end

function scenario_model_kfold_rows(score_rows, pointwise_rows;
        comparison_scope::Symbol = :anchor_models_all_folds_only,
        source_artifact::Symbol = :mgmfrm_full_heldout_mcmc_refit_anchor_scoring)
    rows = NamedTuple[]
    keys = sort(unique((row.scenario, row.model) for row in score_rows);
        by = pair -> (string(pair[1]), string(pair[2])))
    for (scenario, model) in keys
        model_scores =
            sort([row for row in score_rows if row.scenario === scenario &&
                                           row.model === model];
                by = row -> row.fold)
        model_pointwise =
            [row for row in pointwise_rows if row.scenario === scenario &&
                                           row.model === model]
        heldout_elpd = sum(row.heldout_elpd for row in model_scores; init = 0.0)
        residuals =
            [row.observed_minus_expected_score for row in model_pointwise]
        absolute_errors =
            [row.absolute_expected_score_error for row in model_pointwise]
        push!(rows, (;
            scenario,
            model,
            source_artifact,
            n_folds = length(model_scores),
            folds = [row.fold for row in model_scores],
            n_heldout_observations =
                sum(row.n_heldout_observations for row in model_scores),
            heldout_elpd,
            heldout_mean_log_predictive_density =
                heldout_elpd /
                sum(row.n_heldout_observations for row in model_scores),
            kfoldic = -2 * heldout_elpd,
            heldout_expected_score_mae = finite_mean(absolute_errors),
            heldout_expected_score_rmse = finite_rmse(residuals),
            heldout_expected_score_bias = finite_mean(residuals),
            all_folds_scored =
                length(model_scores) == length(PROTOCOL.selected_folds),
            all_scores_finite =
                all(row -> Bool(row.all_pointwise_scores_finite),
                    model_scores),
            publication_grade_diagnostics_blocked =
                all(row -> Bool(row.publication_grade_diagnostics_blocked),
                    model_scores),
            comparison_scope,
            public_model_weight_claim_allowed = false,
            sparse_superiority_claim_allowed = false,
        ))
    end
    return rows
end

function candidate_kfold_rows(candidate_batch)
    return [
        (scenario = as_symbol(row[:scenario]),
            model = as_symbol(row[:model]),
            source_artifact =
                :mgmfrm_full_heldout_mcmc_refit_candidate_batch_scoring,
            n_folds = as_int(row[:n_folds]),
            folds = [as_int(value) for value in row[:folds]],
            n_heldout_observations = as_int(row[:n_heldout_observations]),
            heldout_elpd = as_float(row[:heldout_elpd]),
            heldout_mean_log_predictive_density =
                as_float(row[:heldout_mean_log_predictive_density]),
            kfoldic = as_float(row[:kfoldic]),
            heldout_expected_score_mae =
                as_float(row[:heldout_expected_score_mae]),
            heldout_expected_score_rmse =
                as_float(row[:heldout_expected_score_rmse]),
            heldout_expected_score_bias =
                as_float(row[:heldout_expected_score_bias]),
            all_folds_scored = as_bool(row[:all_folds_scored]),
            all_scores_finite = as_bool(row[:all_scores_finite]),
            publication_grade_diagnostics_blocked =
                as_bool(row[:publication_grade_diagnostics_blocked]),
            comparison_scope = PROTOCOL.comparison_scope,
            public_model_weight_claim_allowed = false,
            sparse_superiority_claim_allowed = false)
        for row in candidate_batch[:scenario_model_kfold_rows]
    ]
end

function combined_model_kfold_rows(candidate_batch, anchor_kfold_rows)
    candidate_rows = candidate_kfold_rows(candidate_batch)
    anchor_rows = [
        merge(row, (comparison_scope = PROTOCOL.comparison_scope,))
        for row in anchor_kfold_rows
    ]
    return vcat(candidate_rows, anchor_rows)
end

function combined_rank_rows(combined_rows)
    rows = NamedTuple[]
    scenarios = sort(unique(row.scenario for row in combined_rows); by = string)
    for scenario in scenarios
        scenario_rows =
            sort([row for row in combined_rows if row.scenario === scenario];
                by = row -> row.heldout_elpd,
                rev = true)
        best = first(scenario_rows)
        for (rank, row) in enumerate(scenario_rows)
            push!(rows, (;
                scenario,
                model = row.model,
                source_artifact = row.source_artifact,
                rank,
                heldout_elpd = row.heldout_elpd,
                delta_elpd_from_best = row.heldout_elpd - best.heldout_elpd,
                kfoldic = row.kfoldic,
                heldout_expected_score_mae =
                    row.heldout_expected_score_mae,
                best_model_in_descriptive_125_unit_comparison = rank == 1,
                comparison_scope = PROTOCOL.comparison_scope,
                public_model_weight_claim_allowed = false,
                sparse_superiority_claim_allowed = false,
                interpretation =
                    :descriptive_full_scoring_rank_no_public_superiority_claim,
            ))
        end
    end
    return rows
end

function resolved_gate_rows()
    return [
        (gate = :scalar_gmfrm_anchor_heldout_scores,
            resolved = true,
            resolution =
                :all_scenario_fold_scalar_gmfrm_anchor_scores_recorded,
            public_claim_allowed = false),
        (gate = :intercept_reference_anchor_heldout_scores,
            resolved = true,
            resolution =
                :all_scenario_fold_reference_anchor_scores_recorded,
            public_claim_allowed = false),
        (gate = :candidate_anchor_descriptive_comparison,
            resolved = true,
            resolution =
                :candidate_and_anchor_kfold_rows_joined_for_local_review,
            public_claim_allowed = false),
    ]
end

function blocker_rows()
    return [
        (blocker = :publication_grade_chains_and_draws_not_run,
            blocks = :public_fit_metric_and_model_weight_claims,
            resolved = false),
        (blocker = :reference_anchor_is_analytic_not_mcmc_refit,
            blocks = :full_mcmc_refit_completion_claims,
            resolved = false),
        (blocker = :external_construct_dataset_missing,
            blocks = :public_q_revision_claims,
            resolved = false),
        (blocker = :public_model_weight_calibration_not_authorized,
            blocks = :public_model_weight_claims,
            resolved = false),
        (blocker = :independent_public_scope_review_missing,
            blocks = :all_public_mgmfrm_claims,
            resolved = false),
    ]
end

function no_publication_commands()
    command =
        "julia --project=. scripts/generate_mgmfrm_full_heldout_mcmc_refit_anchor_scoring.jl"
    banned = ["git push", "gh release", "Registrator", "Pkg.register", "publish"]
    lowered = lowercase(command)
    return all(!occursin(lowercase(term), lowered) for term in banned)
end

function build_artifact()
    input_records = [artifact_record(spec) for spec in INPUT_ARTIFACTS]
    plan_record =
        record_by_name(input_records,
            :mgmfrm_full_heldout_mcmc_refit_execution_plan)
    candidate_record =
        record_by_name(input_records,
            :mgmfrm_full_heldout_mcmc_refit_candidate_batch_scoring)
    heldout_execution_record =
        record_by_name(input_records, :mgmfrm_heldout_prediction_execution)
    split_policy_record =
        record_by_name(input_records,
            :mgmfrm_validation_split_model_comparison_policy)
    plan = load_fixture(
        "test/fixtures/mgmfrm_full_heldout_mcmc_refit_execution_plan.json")
    candidate_batch = load_fixture(
        "test/fixtures/mgmfrm_full_heldout_mcmc_refit_candidate_batch_scoring.json")

    units = anchor_unit_rows(plan)
    scored = score_rows_and_pointwise(units)
    score_rows = scored.score_rows
    pointwise_rows = scored.pointwise_rows
    probability_rows = scored.probability_rows
    fold_completion = anchor_fold_completion_rows(score_rows, pointwise_rows)
    anchor_kfold_rows = scenario_model_kfold_rows(score_rows, pointwise_rows)
    combined_kfold_rows = combined_model_kfold_rows(
        candidate_batch,
        anchor_kfold_rows,
    )
    ranks = combined_rank_rows(combined_kfold_rows)
    resolved = resolved_gate_rows()
    blockers = blocker_rows()

    all_input_artifacts_present = all(record -> record.exists, input_records)
    all_expected_schemas = all(record -> record.schema_matches, input_records)
    all_input_summaries_passed =
        all(record -> record.summary_passed, input_records)
    execution_plan_passed = Bool(plan_record.summary.passed)
    candidate_batch_scoring_passed = Bool(candidate_record.summary.passed)
    heldout_prediction_execution_passed =
        Bool(heldout_execution_record.summary.passed)
    validation_split_policy_passed =
        Bool(split_policy_record.summary.passed)
    expected_anchor_units =
        Int(heldout_execution_record.summary.n_scenarios) *
        length(ANCHOR_MODELS) *
        Int(heldout_execution_record.summary.n_folds)
    anchor_units_selected =
        length(units) == expected_anchor_units &&
        all(unit -> unit.model in ANCHOR_MODELS, units) &&
        all(unit -> Int(unit.fold) in PROTOCOL.selected_folds, units)
    scalar_anchor_refits_succeeded =
        count(row -> row.model === :scalar_gmfrm_baseline, score_rows) ==
        Int(heldout_execution_record.summary.n_scenarios) *
        Int(heldout_execution_record.summary.n_folds) &&
        all(row -> row.model !== :scalar_gmfrm_baseline ||
                   (Bool(row.fit_succeeded) &&
                    Bool(row.layout_matches) &&
                    Bool(row.mcmc_refit_attempted)),
            score_rows)
    reference_anchor_scores_recorded =
        count(row -> row.model === :null_or_intercept_reference, score_rows) ==
        Int(heldout_execution_record.summary.n_scenarios) *
        Int(heldout_execution_record.summary.n_folds) &&
        all(row -> row.model !== :null_or_intercept_reference ||
                   (Bool(row.scoring_succeeded) &&
                    Bool(row.analytic_reference_scored) &&
                    !Bool(row.mcmc_refit_attempted)),
            score_rows)
    all_anchor_scores_recorded = length(score_rows) == expected_anchor_units
    expected_pointwise_rows =
        sum(unit.n_heldout_observations for unit in units)
    all_anchor_pointwise_scores_recorded =
        length(pointwise_rows) == expected_pointwise_rows
    all_anchor_score_values_finite =
        all(row -> Bool(row.all_pointwise_scores_finite) &&
                Bool(row.expected_score_residuals_finite) &&
                isfinite(Float64(row.heldout_elpd)) &&
                isfinite(Float64(row.heldout_expected_score_mae)) &&
                isfinite(Float64(row.heldout_expected_score_rmse)),
            score_rows) &&
        all(row -> Bool(row.finite_score), pointwise_rows)
    anchor_fold_completion_rows_recorded =
        length(fold_completion) ==
        Int(heldout_execution_record.summary.n_scenarios) *
        Int(heldout_execution_record.summary.n_folds) &&
        all(row -> Bool(row.anchor_fold_complete), fold_completion)
    anchor_kfold_rows_recorded =
        length(anchor_kfold_rows) ==
        Int(heldout_execution_record.summary.n_scenarios) *
        length(ANCHOR_MODELS) &&
        all(row -> Bool(row.all_folds_scored) &&
                   Bool(row.all_scores_finite),
            anchor_kfold_rows)
    combined_model_kfold_rows_recorded =
        length(combined_kfold_rows) ==
        Int(heldout_execution_record.summary.n_scenarios) *
        Int(heldout_execution_record.summary.n_models)
    combined_rank_rows_recorded =
        length(ranks) == length(combined_kfold_rows) &&
        all(scenario -> count(row -> row.scenario === scenario, ranks) ==
                        Int(heldout_execution_record.summary.n_models),
            unique(row.scenario for row in combined_kfold_rows))
    candidate_and_anchor_scores_cover_125_units =
        Int(candidate_record.summary.n_candidate_score_rows) +
        length(score_rows) == Int(plan_record.summary.n_execution_unit_rows) &&
        Int(candidate_record.summary.n_heldout_pointwise_rows) +
        length(pointwise_rows) ==
            Int(plan_record.summary.n_execution_unit_rows) * 8
    comparison_anchor_scores_computed =
        all_anchor_scores_recorded &&
        all_anchor_pointwise_scores_recorded &&
        !Bool(candidate_record.summary.comparison_anchor_scores_computed)
    publication_grade_diagnostics_blocked =
        all(row -> Bool(row.publication_grade_diagnostics_blocked),
            score_rows)
    external_construct_dataset_still_required =
        any(unit -> Bool(unit.external_construct_validation_required), units)
    no_public_fit_metric_claim = true
    no_public_q_revision_claim =
        Bool(split_policy_record.summary.no_public_q_revision_claim)
    no_public_model_weight_claim =
        Bool(split_policy_record.summary.no_model_weight_or_sparse_superiority_claim) &&
        all(row -> !Bool(row.public_model_weight_claim_allowed), ranks)
    no_sparse_superiority_claim =
        all(row -> !Bool(row.sparse_superiority_claim_allowed), ranks)
    no_publication = no_publication_commands()

    passed = all_input_artifacts_present &&
        all_expected_schemas &&
        all_input_summaries_passed &&
        execution_plan_passed &&
        candidate_batch_scoring_passed &&
        heldout_prediction_execution_passed &&
        validation_split_policy_passed &&
        anchor_units_selected &&
        scalar_anchor_refits_succeeded &&
        reference_anchor_scores_recorded &&
        all_anchor_scores_recorded &&
        all_anchor_pointwise_scores_recorded &&
        all_anchor_score_values_finite &&
        anchor_fold_completion_rows_recorded &&
        anchor_kfold_rows_recorded &&
        combined_model_kfold_rows_recorded &&
        combined_rank_rows_recorded &&
        candidate_and_anchor_scores_cover_125_units &&
        comparison_anchor_scores_computed &&
        publication_grade_diagnostics_blocked &&
        external_construct_dataset_still_required &&
        no_public_fit_metric_claim &&
        no_public_q_revision_claim &&
        no_public_model_weight_claim &&
        no_sparse_superiority_claim &&
        no_publication

    n_review_cells =
        length(units) + length(score_rows) + length(pointwise_rows) +
        length(probability_rows) + length(fold_completion) +
        length(anchor_kfold_rows) + length(combined_kfold_rows) +
        length(ranks) + length(resolved) + length(blockers)
    total_anchor_heldout_elpd =
        sum(row.heldout_elpd for row in score_rows; init = 0.0)
    total_anchor_heldout_observations =
        sum(row.n_heldout_observations for row in score_rows)

    return (;
        schema =
            "bayesianmgmfrm.mgmfrm_full_heldout_mcmc_refit_anchor_scoring.v1",
        family = :mgmfrm,
        scope = :full_heldout_mcmc_refit_anchor_scoring,
        status = :scalar_and_reference_anchor_scores_recorded,
        decision =
            :record_anchor_scores_join_candidate_comparison_keep_public_claims_blocked,
        public_fit = true,
        experimental_public = true,
        fit_ready = true,
        local_only = true,
        pilot_only = true,
        smoke_only = true,
        fixed_q_mgmfrm_candidate_batch_completed = true,
        fixed_q_mgmfrm_candidate_heldout_scores_computed = true,
        scalar_anchor_scores_computed = true,
        reference_anchor_scores_computed = true,
        comparison_anchor_scores_computed = true,
        full_125_unit_scoring_completed = true,
        full_heldout_predictive_scores_computed = true,
        full_mcmc_refit_execution_completed = false,
        full_125_unit_mcmc_refit_batch_completed = false,
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
        anchor_execution_unit_rows = units,
        anchor_score_rows = score_rows,
        heldout_pointwise_rows = pointwise_rows,
        reference_probability_rows = probability_rows,
        anchor_fold_completion_rows = fold_completion,
        anchor_scenario_model_kfold_rows = anchor_kfold_rows,
        combined_scenario_model_kfold_rows = combined_kfold_rows,
        combined_rank_rows = ranks,
        resolved_gate_rows = resolved,
        blocker_rows = blockers,
        decision_record = (;
            selected_decision =
                :record_anchor_scores_join_candidate_comparison_keep_public_claims_blocked,
            fixed_q_mgmfrm_candidate_batch_completed = true,
            scalar_anchor_scores_computed = true,
            reference_anchor_scores_computed = true,
            comparison_anchor_scores_computed = true,
            full_125_unit_scoring_completed = true,
            full_mcmc_refit_execution_completed = false,
            full_125_unit_mcmc_refit_batch_completed = false,
            public_fit_metric_claim_allowed = false,
            public_q_revision_claim_allowed = false,
            model_weight_or_sparse_superiority_claim_allowed = false,
            required_followup =
                :publication_grade_refit_diagnostics_or_external_construct_dataset_review,
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
            candidate_batch_scoring_passed,
            heldout_prediction_execution_passed,
            validation_split_policy_passed,
            anchor_units_selected,
            scalar_anchor_refits_succeeded,
            reference_anchor_scores_recorded,
            all_anchor_scores_recorded,
            all_anchor_pointwise_scores_recorded,
            all_anchor_score_values_finite,
            anchor_fold_completion_rows_recorded,
            anchor_kfold_rows_recorded,
            combined_model_kfold_rows_recorded,
            combined_rank_rows_recorded,
            candidate_and_anchor_scores_cover_125_units,
            comparison_anchor_scores_computed,
            publication_grade_diagnostics_blocked,
            external_construct_dataset_still_required,
            no_public_fit_metric_claim,
            no_public_q_revision_claim,
            no_public_model_weight_claim,
            no_sparse_superiority_claim,
            fixed_q_mgmfrm_candidate_batch_completed = true,
            fixed_q_mgmfrm_candidate_heldout_scores_computed = true,
            scalar_anchor_scores_computed = true,
            reference_anchor_scores_computed = true,
            full_125_unit_scoring_completed = true,
            full_heldout_predictive_scores_computed = true,
            full_mcmc_refit_execution_completed = false,
            full_125_unit_mcmc_refit_batch_completed = false,
            external_construct_dataset_attached = false,
            external_construct_validation_completed = false,
            n_input_artifacts = length(input_records),
            n_planned_execution_units =
                Int(plan_record.summary.n_execution_unit_rows),
            n_candidate_score_rows =
                Int(candidate_record.summary.n_candidate_score_rows),
            n_candidate_pointwise_rows =
                Int(candidate_record.summary.n_heldout_pointwise_rows),
            n_anchor_execution_unit_rows = length(units),
            n_anchor_score_rows = length(score_rows),
            n_scalar_anchor_score_rows =
                count(row -> row.model === :scalar_gmfrm_baseline, score_rows),
            n_reference_anchor_score_rows =
                count(row -> row.model === :null_or_intercept_reference,
                    score_rows),
            n_anchor_heldout_pointwise_rows = length(pointwise_rows),
            n_reference_probability_rows = length(probability_rows),
            n_anchor_fold_completion_rows = length(fold_completion),
            n_anchor_scenario_model_kfold_rows = length(anchor_kfold_rows),
            n_combined_scenario_model_kfold_rows = length(combined_kfold_rows),
            n_combined_rank_rows = length(ranks),
            n_resolved_gate_rows = length(resolved),
            n_blocker_rows = length(blockers),
            n_review_cells,
            n_scenarios = Int(heldout_execution_record.summary.n_scenarios),
            n_models = Int(heldout_execution_record.summary.n_models),
            n_folds = length(PROTOCOL.selected_folds),
            n_full_execution_units_scored =
                Int(candidate_record.summary.n_candidate_score_rows) +
                length(score_rows),
            n_full_execution_units_remaining_for_scoring = 0,
            n_candidate_and_anchor_pointwise_rows =
                Int(candidate_record.summary.n_heldout_pointwise_rows) +
                length(pointwise_rows),
            n_anchor_heldout_observations =
                total_anchor_heldout_observations,
            total_anchor_heldout_elpd,
            mean_anchor_heldout_log_predictive_density =
                total_anchor_heldout_elpd / total_anchor_heldout_observations,
            mean_anchor_heldout_expected_score_mae =
                finite_mean([row.heldout_expected_score_mae
                    for row in score_rows]),
            n_publication_grade_anchor_fit_rows =
                count(row -> Bool(row.diagnostic_passed), score_rows),
            n_blockers = length(blockers),
            remaining_public_blockers =
                [row.blocker for row in blockers if !Bool(row.resolved)],
            recommendation =
                :use_descriptive_125_unit_comparison_to_plan_publication_grade_refits_or_external_construct_dataset_review,
            next_gate =
                :publication_grade_refit_diagnostics_or_external_construct_dataset_review,
        ),
    )
end

function main(args)
    output = parse_args(args)
    artifact = build_artifact()
    write_artifact(output, artifact)
    println("wrote ", relpath(output, ROOT))
    println("passed=", artifact.summary.passed,
        " anchor_scores=", artifact.summary.n_anchor_score_rows,
        " combined_kfold=", artifact.summary.n_combined_scenario_model_kfold_rows,
        " next_gate=", artifact.summary.next_gate)
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
