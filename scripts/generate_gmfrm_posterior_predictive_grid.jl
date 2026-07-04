#!/usr/bin/env julia

using Random
using SHA
using TOML

import BayesianMGMFRM

module GMFRMFitValidationGrid
include(joinpath(@__DIR__, "generate_gmfrm_experimental_fit_validation_grid.jl"))
end

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures", "gmfrm_posterior_predictive_grid.json")

include(joinpath(@__DIR__, "local_json.jl"))

const FITGRID = GMFRMFitValidationGrid
const SMOKE = FITGRID.SMOKE

const PROTOCOL = (;
    protocol_id = "scalar_gmfrm_posterior_predictive_grid_v1",
    review_kind = :local_guarded_experimental_posterior_predictive_grid,
    publication_or_registration_action = false,
    superseded_by_sparse_pathology_recovery_grid = true,
    entrypoint_under_validation =
        "posterior_predictive_check(fit(spec; experimental = true))",
    simulation_source = :scalar_gmfrm_experimental_fit_validation_grid_scenarios,
    data_grid = SMOKE.PROTOCOL.grid,
    sampler = FITGRID.PROTOCOL.sampler,
    diagnostics = FITGRID.PROTOCOL.diagnostics,
    posterior_predictive = (;
        draw_policy = :all_fit_draws,
        interval = 0.9,
        calibration_bins = 3,
        category_calibration = :highest_observed_category,
    ),
    thresholds = (;
        n_scenarios = 3,
        n_observations = SMOKE.PROTOCOL.grid.observations,
        n_replicates_per_scenario =
            FITGRID.PROTOCOL.sampler.draws * FITGRID.PROTOCOL.sampler.chains,
        n_summary_rows =
            1 + SMOKE.PROTOCOL.grid.categories + SMOKE.PROTOCOL.grid.persons +
            SMOKE.PROTOCOL.grid.raters + SMOKE.PROTOCOL.grid.items,
        require_ppc_returned = true,
        require_replicated_scores_in_categories = true,
        require_probability_sums = true,
        require_summary_rows_finite = true,
        require_mean_score_inside_interval = true,
        require_calibration_rows_finite = true,
        max_summary_outside_interval_rate = 0.75,
        max_absolute_summary_error = 1.0,
        max_absolute_mean_score_error = 0.75,
        max_absolute_category_proportion_error = 0.75,
        max_absolute_calibration_error = 1.0,
    ),
)

const SCENARIOS = [
    (FITGRID.SCENARIOS[1]..., ppc_seed = 20260951),
    (FITGRID.SCENARIOS[2]..., ppc_seed = 20260952),
    (FITGRID.SCENARIOS[3]..., ppc_seed = 20260953),
]

function usage()
    return """
    Generate the local scalar GMFRM posterior predictive-grid artifact.

    The grid runs the guarded `fit(spec; experimental = true)` method over
    fixed scalar GMFRM simulation scenarios and records posterior predictive
    checks plus calibration rows. It does not publish, register, or broaden the
    generalized model surface.

    Usage:
      julia --project=. scripts/generate_gmfrm_posterior_predictive_grid.jl [--output PATH]
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

function file_sha256(path::AbstractString)
    return bytes2hex(open(sha256, path))
end

function fixture_reference(path::AbstractString)
    local_path = joinpath(ROOT, path)
    return (;
        artifact = path,
        exists = isfile(local_path),
        sha256 = isfile(local_path) ? file_sha256(local_path) : missing,
    )
end

function finite_numeric_record(value)
    value isa Real || return true
    return isfinite(Float64(value))
end

function all_top_level_numeric_finite(row)
    return all(key -> finite_numeric_record(getproperty(row, key)), keys(row))
end

function score_count_rows(scores, levels)
    total = length(scores)
    return [(score = level,
        n = count(==(level), scores),
        proportion = total == 0 ? NaN : count(==(level), scores) / total)
        for level in levels]
end

function summary_group_rows(summary_rows)
    stats = sort(unique(row.statistic for row in summary_rows); by = string)
    rows = NamedTuple[]
    for statistic in stats
        rows_for_stat = [row for row in summary_rows if row.statistic === statistic]
        errors = [abs(row.observed - row.replicated_mean) for row in rows_for_stat]
        tails = [row.two_sided_tail_probability for row in rows_for_stat
            if isfinite(row.two_sided_tail_probability)]
        push!(rows, (;
            statistic,
            n_rows = length(rows_for_stat),
            n_outside_interval = count(row -> row.flag !== :ok, rows_for_stat),
            max_absolute_error = maximum(errors),
            min_two_sided_tail_probability = isempty(tails) ? NaN : minimum(tails),
        ))
    end
    return rows
end

function max_abs_error(rows)
    isempty(rows) && return NaN
    return maximum(abs(row.observed - row.replicated_mean) for row in rows)
end

function max_abs_calibration_error(rows)
    isempty(rows) && return NaN
    return maximum(row.absolute_calibration_error for row in rows)
end

function probability_sums_valid(probabilities)
    max_error = 0.0
    for draw in axes(probabilities, 1), row in axes(probabilities, 2)
        max_error = max(max_error, abs(sum(@view probabilities[draw, row, :]) - 1.0))
    end
    return (valid = max_error <= 1e-10, max_sum_error = max_error)
end

function finite_matrix_summary(matrix::AbstractMatrix{<:Real})
    values = vec(Float64.(matrix))
    return (;
        shape = collect(size(matrix)),
        all_finite = all(isfinite, values),
        minimum = minimum(values),
        maximum = maximum(values),
        mean = sum(values) / length(values),
    )
end

function scenario_record(spec)
    simulated = FITGRID.table_for_scenario(spec)
    data = SMOKE.facet_data(simulated.table)
    gmfrm_spec = BayesianMGMFRM.mfrm_spec(
        data;
        family = :gmfrm,
        discrimination = :rater,
    )
    fit = BayesianMGMFRM.fit(
        gmfrm_spec;
        experimental = true,
        FITGRID.sampler_kwargs(spec.fit_seed)...,
    )
    draw_indices = collect(1:size(fit.draws, 1))
    probabilities = BayesianMGMFRM.predictive_probabilities(
        fit;
        draw_indices,
    )
    expected = BayesianMGMFRM.expected_scores(fit; draw_indices)
    variances = BayesianMGMFRM.predictive_variances(fit; draw_indices)
    residuals = BayesianMGMFRM.predictive_residuals(fit; draw_indices)
    ppc = BayesianMGMFRM.posterior_predictive_check(
        fit;
        draw_indices,
        rng = MersenneTwister(spec.ppc_seed),
    )
    summary_rows = BayesianMGMFRM.predictive_check_summary(
        ppc;
        interval = PROTOCOL.posterior_predictive.interval,
    )
    calibration_rows = BayesianMGMFRM.calibration_table(
        fit;
        draw_indices,
        bins = PROTOCOL.posterior_predictive.calibration_bins,
        interval = PROTOCOL.posterior_predictive.interval,
    )
    category_calibration_rows = BayesianMGMFRM.calibration_table(
        fit;
        target = :category_probability,
        category = last(data.category_levels),
        draw_indices,
        bins = PROTOCOL.posterior_predictive.calibration_bins,
        interval = PROTOCOL.posterior_predictive.interval,
    )
    mean_score_rows = [row for row in summary_rows if row.statistic === :mean_score]
    category_rows = [row for row in summary_rows if row.statistic === :category_proportion]
    outside_count = count(row -> row.flag !== :ok, summary_rows)
    probability_review = probability_sums_valid(probabilities)
    replicated_scores = vec(ppc.replicated_scores)
    replicated_scores_valid =
        all(score -> score in data.category_levels, replicated_scores)
    expected_min = minimum(data.category_levels)
    expected_max = maximum(data.category_levels)
    expected_scores_in_range =
        all(value -> expected_min - 1e-10 <= value <= expected_max + 1e-10,
            expected)
    calibration_all_rows = [calibration_rows..., category_calibration_rows...]
    summary_rows_finite = all(all_top_level_numeric_finite, summary_rows)
    calibration_rows_finite = all(all_top_level_numeric_finite, calibration_all_rows)
    passed = fit isa BayesianMGMFRM.GMFRMFit &&
        collect(size(ppc.replicated_scores)) == [length(draw_indices), data.n] &&
        replicated_scores_valid &&
        Bool(probability_review.valid) &&
        summary_rows_finite &&
        calibration_rows_finite &&
        only(mean_score_rows).flag === :ok &&
        outside_count / length(summary_rows) <=
            PROTOCOL.thresholds.max_summary_outside_interval_rate &&
        max_abs_error(summary_rows) <= PROTOCOL.thresholds.max_absolute_summary_error &&
        max_abs_error(mean_score_rows) <=
            PROTOCOL.thresholds.max_absolute_mean_score_error &&
        max_abs_error(category_rows) <=
            PROTOCOL.thresholds.max_absolute_category_proportion_error &&
        max_abs_calibration_error(calibration_all_rows) <=
            PROTOCOL.thresholds.max_absolute_calibration_error &&
        expected_scores_in_range &&
        all(>=(0.0), variances)

    return (;
        scenario = spec.scenario,
        simulation_seed = spec.simulation_seed,
        fit_seed = spec.fit_seed,
        posterior_predictive_seed = spec.ppc_seed,
        raw_truth_sha256 = FITGRID.raw_truth_hash(spec.raw_truth),
        simulated_data = (;
            n_observations = data.n,
            score_counts = FITGRID.score_count_rows(simulated.table.score),
            person_levels = data.person_levels,
            rater_levels = data.rater_levels,
            item_levels = data.item_levels,
            category_levels = data.category_levels,
        ),
        fit_record = (;
            type = String(nameof(typeof(fit))),
            backend = fit.backend,
            sampler = fit.sampler,
            raw_draws_shape = collect(size(fit.draws)),
            direct_draws_shape = collect(size(fit.direct_draws)),
            pointwise_loglikelihood_shape =
                collect(size(fit.direct_pointwise_loglikelihood)),
        ),
        predictive_probability_review = (;
            shape = collect(size(probabilities)),
            probability_sums_valid = probability_review.valid,
            max_probability_sum_error = probability_review.max_sum_error,
            expected_scores = finite_matrix_summary(expected),
            predictive_variances = finite_matrix_summary(variances),
            predictive_residuals = finite_matrix_summary(residuals),
            expected_scores_in_range,
        ),
        posterior_predictive_review = (;
            draw_indices,
            replicated_scores_shape = collect(size(ppc.replicated_scores)),
            replicated_score_counts =
                score_count_rows(replicated_scores, data.category_levels),
            replicated_scores_in_categories = replicated_scores_valid,
            n_summary_rows = length(summary_rows),
            summary_rows,
            summary_group_rows = summary_group_rows(summary_rows),
        ),
        calibration_review = (;
            expected_score_rows = calibration_rows,
            category_probability_rows = category_calibration_rows,
            top_category = last(data.category_levels),
            n_rows = length(calibration_all_rows),
            all_rows_finite = calibration_rows_finite,
            max_absolute_calibration_error =
                max_abs_calibration_error(calibration_all_rows),
        ),
        summary = (;
            passed,
            ppc_returned = true,
            n_replicates = length(draw_indices),
            n_summary_rows = length(summary_rows),
            replicated_scores_in_categories = replicated_scores_valid,
            probability_sums_valid = probability_review.valid,
            summary_rows_finite,
            calibration_rows_finite,
            mean_score_inside_interval = only(mean_score_rows).flag === :ok,
            n_summary_rows_outside_interval = outside_count,
            outside_interval_rate = outside_count / length(summary_rows),
            max_absolute_summary_error = max_abs_error(summary_rows),
            max_absolute_mean_score_error = max_abs_error(mean_score_rows),
            max_absolute_category_proportion_error = max_abs_error(category_rows),
            max_absolute_calibration_error =
                max_abs_calibration_error(calibration_all_rows),
            expected_scores_in_range,
            predictive_variances_nonnegative = all(>=(0.0), variances),
        ),
    )
end

function grid_artifact()
    scenarios = [scenario_record(spec) for spec in SCENARIOS]
    passed = all(scenario -> scenario.summary.passed, scenarios)
    return (;
        schema = "bayesianmgmfrm.gmfrm_posterior_predictive_grid.v1",
        family = :gmfrm,
        scope = :scalar_gmfrm_fit_ready_candidate,
        status = :guarded_experimental_posterior_predictive_grid_recorded,
        decision = :keep_guarded_experimental,
        public_fit = true,
        experimental_public = true,
        fit_ready = true,
        package = (;
            name = "BayesianMGMFRM",
            version = project_version(),
            julia_version = string(VERSION),
        ),
        protocol = PROTOCOL,
        reviewed_artifacts = [
            fixture_reference("test/fixtures/gmfrm_experimental_fit_validation_grid.json"),
        ],
        scenarios,
        decision_record = (;
            public_fit_allowed = true,
            experimental_keyword_enabled = true,
            public_exposure_support =
                :satisfied_by_sparse_pathology_recovery_grid,
            interpretation =
                :guarded_scalar_gmfrm_posterior_predictive_grid_passed,
            required_followup = :scalar_gmfrm_prior_likelihood_sensitivity_grid,
        ),
        summary = (;
            passed,
            publication_or_registration_action = false,
            superseded_by_sparse_pathology_recovery_grid = true,
            n_scenarios = length(scenarios),
            n_passed_scenarios = count(scenario -> scenario.summary.passed, scenarios),
            n_replicates_per_scenario =
                PROTOCOL.thresholds.n_replicates_per_scenario,
            all_ppc_returned =
                all(scenario -> scenario.summary.ppc_returned, scenarios),
            all_replicated_scores_in_categories =
                all(scenario -> scenario.summary.replicated_scores_in_categories,
                    scenarios),
            all_probability_sums_valid =
                all(scenario -> scenario.summary.probability_sums_valid, scenarios),
            all_summary_rows_finite =
                all(scenario -> scenario.summary.summary_rows_finite, scenarios),
            all_calibration_rows_finite =
                all(scenario -> scenario.summary.calibration_rows_finite, scenarios),
            all_mean_scores_inside_interval =
                all(scenario -> scenario.summary.mean_score_inside_interval,
                    scenarios),
            max_outside_interval_rate =
                maximum(scenario.summary.outside_interval_rate for scenario in scenarios),
            max_absolute_summary_error =
                maximum(scenario.summary.max_absolute_summary_error
                    for scenario in scenarios),
            max_absolute_mean_score_error =
                maximum(scenario.summary.max_absolute_mean_score_error
                    for scenario in scenarios),
            max_absolute_category_proportion_error =
                maximum(scenario.summary.max_absolute_category_proportion_error
                    for scenario in scenarios),
            max_absolute_calibration_error =
                maximum(scenario.summary.max_absolute_calibration_error
                    for scenario in scenarios),
            remaining_public_blockers =
                [:scalar_gmfrm_prior_likelihood_sensitivity_grid_missing],
            recommendation =
                :keep_guarded_experimental_until_prior_likelihood_sensitivity_grid,
            next_gate = :scalar_gmfrm_prior_likelihood_sensitivity_grid,
        ),
    )
end

function main(args)
    output = parse_args(args)
    artifact = grid_artifact()
    write_artifact(output, artifact)
    println("wrote ", relpath(output, ROOT))
    println("passed=", artifact.summary.passed,
        " scenarios=", artifact.summary.n_scenarios,
        " next_gate=", artifact.summary.next_gate)
    return nothing
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    main(ARGS)
end
