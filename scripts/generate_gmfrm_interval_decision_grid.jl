#!/usr/bin/env julia

using SHA
using TOML

import BayesianMGMFRM
import LogDensityProblems

module GMFRMBaselineCalibrationGrid
include(joinpath(@__DIR__, "generate_gmfrm_baseline_calibration_grid.jl"))
end

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures", "gmfrm_interval_decision_grid.json")

include(joinpath(@__DIR__, "local_json.jl"))

const BASE_PROTOCOL = GMFRMBaselineCalibrationGrid.PROTOCOL

const PROTOCOL = (;
    protocol_id = "scalar_gmfrm_interval_decision_grid_v1",
    simulation_source = :scalar_gmfrm_baseline_calibration_grid_v1,
    data_grid = BASE_PROTOCOL.data_grid,
    scenarios = Tuple(scenario.scenario for scenario in GMFRMBaselineCalibrationGrid.SCENARIOS),
    intervals = (0.8, 0.95),
    models = BASE_PROTOCOL.models,
    gmfrm_sampler = BASE_PROTOCOL.gmfrm_sampler,
    baseline_sampler = BASE_PROTOCOL.baseline_sampler,
    diagnostics = BASE_PROTOCOL.diagnostics,
    decision_rules = (;
        prediction_target = :same_observation_waic,
        public_exposure_decision = :keep_internal,
        require_all_samplers_passed = true,
        high_variance_waic_blocks_public_exposure = true,
        sparse_design_grid_required_before_exposure = true,
        psis_loo_or_influence_review_required_before_exposure = true,
    ),
    thresholds = (;
        n_scenarios = length(GMFRMBaselineCalibrationGrid.SCENARIOS),
        n_models_per_scenario = length(BASE_PROTOCOL.models),
        n_observations = BASE_PROTOCOL.thresholds.n_observations,
        require_same_observations = true,
        require_sampler_passed = true,
        require_finite_intervals = true,
        require_decision_stability = true,
    ),
)

function usage()
    return """
    Generate the local scalar GMFRM interval/decision grid artifact.

    Usage:
      julia --project=. scripts/generate_gmfrm_interval_decision_grid.jl [--output PATH]
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

function project_version()
    project = TOML.parsefile(joinpath(ROOT, "Project.toml"))
    return String(project["version"])
end

function parameter_order_hash(names)
    return bytes2hex(sha256(codeunits(join(names, "\n"))))
end

function recovery_row_record(row)
    return (;
        parameter = row.parameter,
        parameter_index = row.parameter_index,
        block = row.block,
        true_value = row.true_value,
        posterior_mean = row.posterior_mean,
        posterior_sd = row.posterior_sd,
        posterior_median = row.posterior_median,
        posterior_lower = row.posterior_lower,
        posterior_upper = row.posterior_upper,
        interval_probability = row.interval_probability,
        bias = row.bias,
        absolute_bias = row.absolute_bias,
        relative_bias = row.relative_bias,
        interval_width = row.interval_width,
        covered = row.covered,
        flag = row.flag,
    )
end

function recovery_summary_record(row)
    return (;
        by = row.by,
        group = row.group,
        n_parameters = row.n_parameters,
        mean_bias = row.mean_bias,
        mean_absolute_error = row.mean_absolute_error,
        rmse = row.rmse,
        median_absolute_error = row.median_absolute_error,
        max_absolute_error = row.max_absolute_error,
        coverage_rate = row.coverage_rate,
        nominal_coverage = row.nominal_coverage,
        coverage_gap = row.coverage_gap,
        mean_interval_width = row.mean_interval_width,
        n_covered = row.n_covered,
        flag = row.flag,
    )
end

function gmfrm_result_with_diagnostics(data, table, seed::Int)
    design = GMFRMBaselineCalibrationGrid.GMFRMRecoverySmoke.scalar_gmfrm_design(table)
    target = BayesianMGMFRM._gmfrm_promotion_candidate_logdensity(design)
    sampler = PROTOCOL.gmfrm_sampler
    diagnostics = BayesianMGMFRM._gmfrm_promotion_candidate_sampler_diagnostics(
        target,
        zeros(LogDensityProblems.dimension(target));
        seed,
        ndraws = sampler.draws,
        warmup = sampler.warmup,
        chains = sampler.chains,
        step_size = sampler.step_size,
        target_accept = sampler.target_accept,
        max_depth = sampler.max_depth,
        max_energy_error = sampler.max_energy_error,
        metric = sampler.metric,
        ad_backend = sampler.ad_backend,
        init_jitter = sampler.init_jitter,
        split_chains = sampler.split_chains,
        rhat_threshold = PROTOCOL.diagnostics.rhat_threshold,
        ess_threshold = PROTOCOL.diagnostics.ess_threshold,
        progress = false,
    )
    stat = BayesianMGMFRM.waic(diagnostics.direct_pointwise_loglikelihood)
    expected = GMFRMBaselineCalibrationGrid.gmfrm_expected_scores(
        design,
        diagnostics.direct_draws,
    )
    record = (;
        model = :gmfrm_internal_candidate,
        family = :gmfrm,
        source = :internal_raw_candidate,
        threshold_regime = :generalized_partial_credit,
        estimation_status = :internal_promotion_candidate,
        public_fit = false,
        seed,
        n_parameters = target.blueprint.n_parameters,
        parameter_order_sha256 = parameter_order_hash(target.blueprint.parameter_names),
        direct_parameter_order_sha256 =
            parameter_order_hash(target.blueprint.constrained_parameter_names),
        sampler_summary =
            GMFRMBaselineCalibrationGrid.gmfrm_sampler_summary_record(
                diagnostics.summary,
            ),
    )
    result = GMFRMBaselineCalibrationGrid.model_record(
        record,
        stat,
        expected,
        data.score,
    )
    return (; result, diagnostics, design, target)
end

function interval_record(design, direct_draws, direct_truth, interval::Real)
    recovery_rows = BayesianMGMFRM.parameter_recovery(
        design,
        direct_draws,
        direct_truth;
        interval,
    )
    by_block = BayesianMGMFRM.parameter_recovery_summary(recovery_rows; by = :block)
    overall = only(BayesianMGMFRM.parameter_recovery_summary(recovery_rows; by = :all))
    return (;
        interval_probability = interval,
        recovery_by_block = [recovery_summary_record(row) for row in by_block],
        recovery_overall = recovery_summary_record(overall),
        missed_interval_rows = [
            recovery_row_record(row) for row in recovery_rows if !row.covered
        ],
        summary = (;
            n_parameters = length(recovery_rows),
            n_blocks = length(by_block),
            overall_coverage_rate = overall.coverage_rate,
            min_block_coverage_rate = minimum(row.coverage_rate for row in by_block),
            max_block_mean_absolute_error =
                maximum(row.mean_absolute_error for row in by_block),
            max_parameter_absolute_error =
                maximum(row.absolute_bias for row in recovery_rows),
            mean_interval_width = overall.mean_interval_width,
            n_missed_intervals = count(row -> !row.covered, recovery_rows),
            all_intervals_finite = all(row -> isfinite(row.posterior_lower) &&
                isfinite(row.posterior_upper) &&
                isfinite(row.interval_width), recovery_rows),
        ),
    )
end

function decision_record(model_rows)
    gmfrm_row = only(row for row in model_rows if row.model === :gmfrm_internal_candidate)
    any_high_variance = any(row -> row.warning !== :ok, model_rows)
    all_samplers_passed = all(row -> row.sampler_summary.internal_passed, model_rows)
    selected_decision = :keep_internal
    return (;
        selected_decision,
        public_fit_allowed = false,
        experimental_keyword_enabled = false,
        prediction_target = PROTOCOL.decision_rules.prediction_target,
        best_model = model_rows[1].model,
        gmfrm_rank = gmfrm_row.rank,
        gmfrm_relative_weight = gmfrm_row.relative_weight,
        gmfrm_elpd_difference = gmfrm_row.elpd_difference,
        all_samplers_passed,
        any_high_variance_waic = any_high_variance,
        decision_rules = [
            (rule = :all_samplers_passed,
                satisfied = all_samplers_passed,
                effect = :necessary_but_not_sufficient),
            (rule = :high_variance_waic_blocks_public_exposure,
                satisfied = any_high_variance,
                effect = :keep_internal),
            (rule = :sparse_design_grid_required_before_exposure,
                satisfied = true,
                effect = :keep_internal_until_sparse_grid_recorded),
            (rule = :psis_loo_or_influence_review_required_before_exposure,
                satisfied = true,
                effect = :keep_internal_until_waic_followup_recorded),
        ],
        blocker_rows = [
            (blocker = :high_variance_waic_requires_followup,
                severity = :blocking,
                required_action =
                    :add_influence_or_psis_loo_review_before_public_fit),
            (blocker = :sparse_design_grid_missing,
                severity = :blocking,
                required_action = :run_scalar_gmfrm_sparse_design_grid),
        ],
    )
end

function scenario_passed(intervals, decision, model_rows)
    thresholds = PROTOCOL.thresholds
    length(model_rows) == thresholds.n_models_per_scenario || return false
    if thresholds.require_same_observations &&
            length(unique(row.n_observations for row in model_rows)) != 1
        return false
    end
    all(row -> row.n_observations == thresholds.n_observations, model_rows) ||
        return false
    if thresholds.require_sampler_passed
        all(row -> row.sampler_summary.internal_passed, model_rows) || return false
    end
    if thresholds.require_finite_intervals
        all(row -> row.summary.all_intervals_finite, intervals) || return false
    end
    if thresholds.require_decision_stability
        decision.selected_decision === :keep_internal || return false
    end
    return true
end

function scenario_record(spec)
    simulated = GMFRMBaselineCalibrationGrid.table_for_scenario(spec)
    table = simulated.table
    data = GMFRMBaselineCalibrationGrid.GMFRMRecoverySmoke.facet_data(table)
    gmfrm = gmfrm_result_with_diagnostics(data, table, spec.gmfrm_seed)
    gmfrm.design.parameter_names == simulated.placeholder_design.parameter_names ||
        error("simulated design changed direct parameter order")
    baseline_results = [
        GMFRMBaselineCalibrationGrid.baseline_model_result(
            data,
            :mfrm_partial_credit,
            :partial_credit,
            spec.partial_credit_seed,
        ),
        GMFRMBaselineCalibrationGrid.baseline_model_result(
            data,
            :mfrm_rating_scale,
            :rating_scale,
            spec.rating_scale_seed,
        ),
    ]
    model_rows = GMFRMBaselineCalibrationGrid.comparison_rows([
        gmfrm.result,
        baseline_results...,
    ])
    intervals = [
        interval_record(
            gmfrm.design,
            gmfrm.diagnostics.direct_draws,
            simulated.direct_truth,
            interval,
        )
        for interval in PROTOCOL.intervals
    ]
    decision = decision_record(model_rows)
    passed = scenario_passed(intervals, decision, model_rows)
    return (;
        scenario = spec.scenario,
        simulation_seed = spec.simulation_seed,
        raw_truth_sha256 = bytes2hex(sha256(codeunits(join(spec.raw_truth, "\n")))),
        simulated_data = (;
            n_observations = data.n,
            score_counts = GMFRMBaselineCalibrationGrid.score_count_rows(table.score),
            person_levels = data.person_levels,
            rater_levels = data.rater_levels,
            item_levels = data.item_levels,
            category_levels = data.category_levels,
        ),
        gmfrm_parameter_order = gmfrm.design.parameter_names,
        gmfrm_parameter_order_sha256 = parameter_order_hash(gmfrm.design.parameter_names),
        model_rows,
        interval_coverage = intervals,
        decision,
        summary = (;
            passed,
            selected_decision = decision.selected_decision,
            best_model = decision.best_model,
            gmfrm_rank = decision.gmfrm_rank,
            any_high_variance_waic = decision.any_high_variance_waic,
            min_interval_coverage_rate = minimum(
                row.summary.overall_coverage_rate for row in intervals),
            min_block_coverage_rate =
                minimum(row.summary.min_block_coverage_rate for row in intervals),
            max_parameter_absolute_error =
                maximum(row.summary.max_parameter_absolute_error for row in intervals),
        ),
    )
end

function grid_artifact()
    scenarios = [scenario_record(spec) for spec in GMFRMBaselineCalibrationGrid.SCENARIOS]
    passed = all(scenario -> scenario.summary.passed, scenarios)
    all_intervals = reduce(vcat, [scenario.interval_coverage for scenario in scenarios])
    all_model_rows = reduce(vcat, [scenario.model_rows for scenario in scenarios])
    keep_internal_count =
        count(scenario -> scenario.decision.selected_decision === :keep_internal,
            scenarios)
    any_high_variance = any(row -> row.warning !== :ok, all_model_rows)
    return (;
        schema = "bayesianmgmfrm.gmfrm_interval_decision_grid.v1",
        family = :gmfrm,
        scope = :scalar_gmfrm_fit_ready_candidate,
        status = :internal_interval_decision_grid,
        public_fit = false,
        experimental_public = false,
        fit_ready = false,
        package = (;
            name = "BayesianMGMFRM",
            version = project_version(),
            julia_version = string(VERSION),
        ),
        protocol = PROTOCOL,
        scenarios,
        summary = (;
            passed,
            n_scenarios = length(scenarios),
            n_passed_scenarios = count(scenario -> scenario.summary.passed, scenarios),
            n_interval_records = length(all_intervals),
            n_models = length(all_model_rows),
            all_local_intervals_finite =
                all(row -> row.summary.all_intervals_finite, all_intervals),
            min_interval_coverage_rate =
                minimum(row.summary.overall_coverage_rate for row in all_intervals),
            min_block_coverage_rate =
                minimum(row.summary.min_block_coverage_rate for row in all_intervals),
            max_parameter_absolute_error =
                maximum(row.summary.max_parameter_absolute_error for row in all_intervals),
            keep_internal_decision_count = keep_internal_count,
            decision_stability =
                keep_internal_count == length(scenarios) ? :stable_keep_internal :
                :unstable,
            any_high_variance_waic = any_high_variance,
            remaining_public_blockers = [
                :high_variance_waic_requires_followup,
                :sparse_design_grid_missing,
            ],
            recommendation = :keep_internal_until_sparse_and_waic_followup,
            next_gate = :scalar_gmfrm_sparse_design_grid,
        ),
    )
end

function main(args)
    output = parse_args(args)
    artifact = grid_artifact()
    write_artifact(output, artifact)
    println("Wrote ", output)
    println("passed=", artifact.summary.passed,
        " scenarios=", artifact.summary.n_scenarios,
        " min_interval_coverage=", artifact.summary.min_interval_coverage_rate,
        " decision=", artifact.summary.decision_stability)
    return nothing
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    main(ARGS)
end
