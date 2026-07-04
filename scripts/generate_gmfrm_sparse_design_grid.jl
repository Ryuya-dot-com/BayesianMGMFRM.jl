#!/usr/bin/env julia

using LinearAlgebra
using Random
using SHA
using TOML

import BayesianMGMFRM

module GMFRMIntervalDecisionGrid
include(joinpath(@__DIR__, "generate_gmfrm_interval_decision_grid.jl"))
end

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures", "gmfrm_sparse_design_grid.json")

include(joinpath(@__DIR__, "local_json.jl"))

const BASE = GMFRMIntervalDecisionGrid.GMFRMBaselineCalibrationGrid
const SMOKE = BASE.GMFRMRecoverySmoke

const PROTOCOL = (;
    protocol_id = "scalar_gmfrm_sparse_design_grid_v1",
    simulation_source = :scalar_gmfrm_interval_decision_grid_v1,
    full_crossed_observations = SMOKE.PROTOCOL.grid.observations,
    sparse_designs = (;
        persons = SMOKE.PROTOCOL.grid.persons,
        items = SMOKE.PROTOCOL.grid.items,
        raters = SMOKE.PROTOCOL.grid.raters,
        categories = SMOKE.PROTOCOL.grid.categories,
        rating_density = :sparse_connected,
        patterns = (
            :half_crossed_parity,
            :reference_bridge,
            :cyclic_missing_item_cells,
        ),
    ),
    validation = (;
        bias_terms = ((:rater, :item),),
        min_cell_count = 3,
        require_no_validation_errors = true,
        require_connected_design = true,
        require_full_location_rank = true,
        warnings_recorded_not_blocking = true,
    ),
    intervals = GMFRMIntervalDecisionGrid.PROTOCOL.intervals,
    models = GMFRMIntervalDecisionGrid.PROTOCOL.models,
    gmfrm_sampler = GMFRMIntervalDecisionGrid.PROTOCOL.gmfrm_sampler,
    baseline_sampler = GMFRMIntervalDecisionGrid.PROTOCOL.baseline_sampler,
    diagnostics = GMFRMIntervalDecisionGrid.PROTOCOL.diagnostics,
    decision_rules = (;
        prediction_target = :same_observation_waic,
        public_exposure_decision = :keep_internal,
        sparse_design_grid_recorded = true,
        require_all_samplers_passed = true,
        high_variance_waic_blocks_public_exposure = true,
        psis_loo_or_influence_review_required_before_exposure = true,
    ),
    thresholds = (;
        n_scenarios = 3,
        n_models_per_scenario = length(GMFRMIntervalDecisionGrid.PROTOCOL.models),
        max_observations = SMOKE.PROTOCOL.grid.observations - 1,
        min_observations = 18,
        require_same_observations_within_scenario = true,
        require_sampler_passed = true,
        require_finite_elpd = true,
        require_finite_calibration = true,
        require_finite_intervals = true,
        require_decision_stability = true,
    ),
)

const SCENARIOS = [
    (;
        scenario = :balanced_parity_sparse,
        sparse_pattern = :half_crossed_parity,
        simulation_seed = 20260831,
        gmfrm_seed = 20260832,
        partial_credit_seed = 20260833,
        rating_scale_seed = 20260834,
        raw_truth = [
            -0.4, -0.1, 0.1, 0.4,
            -0.2, 0.0, 0.2,
            -0.15, 0.15,
            log(1.05), log(0.95),
            log(1.05), log(0.95), log(1.0),
            0.1, -0.05, 0.0,
        ],
    ),
    (;
        scenario = :reference_bridge_sparse,
        sparse_pattern = :reference_bridge,
        simulation_seed = 20260835,
        gmfrm_seed = 20260836,
        partial_credit_seed = 20260837,
        rating_scale_seed = 20260838,
        raw_truth = SMOKE.TRUTH_RAW,
    ),
    (;
        scenario = :cyclic_missing_item_sparse,
        sparse_pattern = :cyclic_missing_item_cells,
        simulation_seed = 20260839,
        gmfrm_seed = 20260840,
        partial_credit_seed = 20260841,
        rating_scale_seed = 20260842,
        raw_truth = [
            -0.8, -0.25, 0.25, 0.8,
            -0.45, 0.05, 0.4,
            -0.4, 0.2,
            log(1.6), log(0.7),
            log(1.4), log(0.75), log(1.1),
            0.35, -0.25, 0.1,
        ],
    ),
]

function usage()
    return """
    Generate the local scalar GMFRM sparse-design grid artifact.

    Usage:
      julia --project=. scripts/generate_gmfrm_sparse_design_grid.jl [--output PATH]
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

function sparse_indices(pattern::Symbol)
    base = SMOKE.placeholder_table()
    indices = Int[]
    for index in eachindex(base.examinee)
        person = parse(Int, base.examinee[index][2:end])
        rater = parse(Int, base.rater[index][2:end])
        item = parse(Int, base.item[index][2:end])
        selected = pattern === :half_crossed_parity ?
            isodd(person + rater + item) :
            pattern === :reference_bridge ?
            (rater == 1 || item == 1 ||
                (isodd(person) && rater == item && rater > 1) ||
                (iseven(person) && rater + item == 5)) :
            pattern === :cyclic_missing_item_cells ?
            item != mod(person + rater, 3) + 1 :
            throw(ArgumentError("unknown sparse pattern: $pattern"))
        selected && push!(indices, index)
    end
    return indices
end

function table_subset(indices, scores)
    base = SMOKE.placeholder_table()
    return (;
        examinee = base.examinee[indices],
        rater = base.rater[indices],
        item = base.item[indices],
        score = scores,
    )
end

function placeholder_table_for_pattern(pattern::Symbol)
    indices = sparse_indices(pattern)
    base = SMOKE.placeholder_table()
    return (; table = table_subset(indices, base.score[indices]), indices)
end

function score_count_rows(scores)
    return BASE.score_count_rows(scores)
end

function sampled_scores_with_full_scale(design, direct_truth, seed::Int)
    for offset in 0:250
        actual_seed = seed + offset
        scores = SMOKE.sample_scores(
            design,
            direct_truth;
            rng = Random.MersenneTwister(actual_seed),
        )
        if length(unique(scores)) == 3 && minimum(scores) == 0 && maximum(scores) == 2
            return (; scores, actual_seed)
        end
    end
    error("could not sample sparse scores using all three score categories")
end

function table_for_scenario(spec)
    placeholder = placeholder_table_for_pattern(spec.sparse_pattern)
    placeholder_design = SMOKE.scalar_gmfrm_design(placeholder.table)
    placeholder_design.spec.data.category_levels == [0, 1, 2] ||
        error("sparse placeholder must keep the full three-category scale")
    direct_truth =
        BayesianMGMFRM._gmfrm_source_constrained_params_from_unconstrained(
            placeholder_design,
            spec.raw_truth,
        )
    sampled = sampled_scores_with_full_scale(
        placeholder_design,
        direct_truth,
        spec.simulation_seed,
    )
    table = table_subset(placeholder.indices, sampled.scores)
    data = SMOKE.facet_data(table)
    data.category_levels == [0, 1, 2] ||
        error("sampled sparse table changed category levels")
    return (;
        placeholder_design,
        direct_truth,
        table,
        selected_indices = placeholder.indices,
        actual_simulation_seed = sampled.actual_seed,
    )
end

function issue_record(issue)
    return (;
        code = issue.code,
        severity = issue.severity,
        message = issue.message,
        context_keys = sort([String(key) for key in keys(issue.context)]),
    )
end

function category_count_rows(report)
    return [
        (category = category, n = report.category_counts[category])
        for category in sort(collect(keys(report.category_counts)))
    ]
end

function facet_count_rows(report)
    rows = NamedTuple[]
    for facet in (:person, :rater, :item)
        counts = report.facet_counts[facet]
        for level in sort(collect(keys(counts)); by = string)
            push!(rows, (; facet, level, n = counts[level]))
        end
    end
    return rows
end

function component_rows(report)
    return [
        (component = index,
            n_nodes = length(component),
            nodes = [(facet = node[1], level = node[2]) for node in component])
        for (index, component) in pairs(report.components)
    ]
end

function dff_cell_count_rows(report)
    rows = NamedTuple[]
    for (term, counts) in report.dff_counts
        left, right = term
        for ((left_level, right_level), n) in sort(collect(counts); by = string)
            push!(rows, (;
                left_facet = left,
                right_facet = right,
                left_level,
                right_level,
                n,
            ))
        end
    end
    return rows
end

function validation_record(data, report)
    matrix = BayesianMGMFRM._minimal_location_matrix(data)
    location_rank = rank(matrix)
    n_location_parameters = size(matrix, 2)
    issue_rows = [issue_record(issue) for issue in report.issues]
    return (;
        n_observations = data.n,
        passed = report.passed,
        n_errors = count(row -> row.severity === :error, issue_rows),
        n_warnings = count(row -> row.severity === :warning, issue_rows),
        issue_rows,
        issue_codes = [row.code for row in issue_rows],
        category_counts = category_count_rows(report),
        facet_counts = facet_count_rows(report),
        components = component_rows(report),
        n_components = length(report.components),
        component_sizes = length.(report.components),
        location_design_rank = location_rank,
        n_location_parameters,
        location_design_full_rank = location_rank == n_location_parameters,
        dff_cell_counts = dff_cell_count_rows(report),
    )
end

function selected_cell_rows(table)
    return [
        (row = index,
            person = table.examinee[index],
            rater = table.rater[index],
            item = table.item[index],
            score = table.score[index])
        for index in eachindex(table.score)
    ]
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
            (rule = :sparse_design_grid_recorded,
                satisfied = true,
                effect = :satisfies_sparse_gate_for_scalar_candidate),
            (rule = :all_samplers_passed,
                satisfied = all_samplers_passed,
                effect = :necessary_but_not_sufficient),
            (rule = :high_variance_waic_blocks_public_exposure,
                satisfied = any_high_variance,
                effect = :keep_internal),
            (rule = :psis_loo_or_influence_review_required_before_exposure,
                satisfied = true,
                effect = :keep_internal_until_waic_followup_recorded),
        ],
        blocker_rows = [
            (blocker = :high_variance_waic_requires_followup,
                severity = :blocking,
                required_action =
                    :add_influence_or_psis_loo_review_before_public_fit),
        ],
    )
end

function scenario_passed(validation, intervals, decision, model_rows, n_observations)
    thresholds = PROTOCOL.thresholds
    length(model_rows) == thresholds.n_models_per_scenario || return false
    thresholds.min_observations <= n_observations <= thresholds.max_observations ||
        return false
    if thresholds.require_same_observations_within_scenario &&
            length(unique(row.n_observations for row in model_rows)) != 1
        return false
    end
    all(row -> row.n_observations == n_observations, model_rows) || return false
    validation.passed || return false
    validation.n_components == 1 || return false
    validation.location_design_full_rank || return false
    if thresholds.require_sampler_passed
        all(row -> row.sampler_summary.internal_passed, model_rows) || return false
    end
    if thresholds.require_finite_elpd
        all(row -> isfinite(row.elpd_waic) && isfinite(row.waic), model_rows) ||
            return false
    end
    if thresholds.require_finite_calibration
        all(row -> isfinite(row.predictive_metrics.expected_score_rmse) &&
            isfinite(row.predictive_metrics.mean_absolute_calibration_error), model_rows) ||
            return false
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
    simulated = table_for_scenario(spec)
    table = simulated.table
    data = SMOKE.facet_data(table)
    validation_report = BayesianMGMFRM.validate_design(
        data;
        bias = collect(PROTOCOL.validation.bias_terms),
        min_cell_count = PROTOCOL.validation.min_cell_count,
    )
    validation = validation_record(data, validation_report)
    gmfrm = GMFRMIntervalDecisionGrid.gmfrm_result_with_diagnostics(
        data,
        table,
        spec.gmfrm_seed,
    )
    gmfrm.design.parameter_names == simulated.placeholder_design.parameter_names ||
        error("simulated sparse design changed direct parameter order")
    baseline_results = [
        BASE.baseline_model_result(
            data,
            :mfrm_partial_credit,
            :partial_credit,
            spec.partial_credit_seed,
        ),
        BASE.baseline_model_result(
            data,
            :mfrm_rating_scale,
            :rating_scale,
            spec.rating_scale_seed,
        ),
    ]
    model_rows = BASE.comparison_rows([
        gmfrm.result,
        baseline_results...,
    ])
    intervals = [
        GMFRMIntervalDecisionGrid.interval_record(
            gmfrm.design,
            gmfrm.diagnostics.direct_draws,
            simulated.direct_truth,
            interval,
        )
        for interval in PROTOCOL.intervals
    ]
    decision = decision_record(model_rows)
    passed = scenario_passed(validation, intervals, decision, model_rows, data.n)
    return (;
        scenario = spec.scenario,
        sparse_pattern = spec.sparse_pattern,
        simulation_seed = spec.simulation_seed,
        actual_simulation_seed = simulated.actual_simulation_seed,
        raw_truth_sha256 = bytes2hex(sha256(codeunits(join(spec.raw_truth, "\n")))),
        selected_row_indices = simulated.selected_indices,
        selected_cells = selected_cell_rows(table),
        design_density = (;
            rating_density = :sparse_connected,
            n_observations = data.n,
            full_crossed_observations = PROTOCOL.full_crossed_observations,
            observed_fraction = data.n / PROTOCOL.full_crossed_observations,
            missing_observations = PROTOCOL.full_crossed_observations - data.n,
        ),
        simulated_data = (;
            n_observations = data.n,
            score_counts = score_count_rows(table.score),
            person_levels = data.person_levels,
            rater_levels = data.rater_levels,
            item_levels = data.item_levels,
            category_levels = data.category_levels,
        ),
        validation,
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
            validation_passed = validation.passed,
            validation_warnings = validation.n_warnings,
            location_design_rank = validation.location_design_rank,
            n_location_parameters = validation.n_location_parameters,
            min_interval_coverage_rate =
                minimum(row.summary.overall_coverage_rate for row in intervals),
            min_block_coverage_rate =
                minimum(row.summary.min_block_coverage_rate for row in intervals),
            max_parameter_absolute_error =
                maximum(row.summary.max_parameter_absolute_error for row in intervals),
        ),
    )
end

function grid_artifact()
    scenarios = [scenario_record(spec) for spec in SCENARIOS]
    passed = all(scenario -> scenario.summary.passed, scenarios)
    all_intervals = reduce(vcat, [scenario.interval_coverage for scenario in scenarios])
    all_model_rows = reduce(vcat, [scenario.model_rows for scenario in scenarios])
    all_validation_rows = [scenario.validation for scenario in scenarios]
    keep_internal_count =
        count(scenario -> scenario.decision.selected_decision === :keep_internal,
            scenarios)
    any_high_variance = any(row -> row.warning !== :ok, all_model_rows)
    return (;
        schema = "bayesianmgmfrm.gmfrm_sparse_design_grid.v1",
        family = :gmfrm,
        scope = :scalar_gmfrm_fit_ready_candidate,
        status = :internal_sparse_design_grid,
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
            n_sparse_validation_records = length(all_validation_rows),
            n_interval_records = length(all_intervals),
            n_models = length(all_model_rows),
            n_observations_minimum =
                minimum(scenario.design_density.n_observations for scenario in scenarios),
            n_observations_maximum =
                maximum(scenario.design_density.n_observations for scenario in scenarios),
            all_sparse_validations_passed =
                all(row -> row.passed, all_validation_rows),
            all_location_designs_full_rank =
                all(row -> row.location_design_full_rank, all_validation_rows),
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
            ],
            recommendation = :keep_internal_until_waic_followup,
            next_gate = :scalar_gmfrm_waic_influence_review,
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
        " min_n=", artifact.summary.n_observations_minimum,
        " max_n=", artifact.summary.n_observations_maximum,
        " decision=", artifact.summary.decision_stability)
    return nothing
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    main(ARGS)
end
