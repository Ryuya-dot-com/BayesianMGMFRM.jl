#!/usr/bin/env julia

using Random
using SHA
using TOML

import BayesianMGMFRM

module GMFRMSparseDesignGrid
include(joinpath(@__DIR__, "generate_gmfrm_sparse_design_grid.jl"))
end

module GMFRMPosteriorPredictiveGrid
include(joinpath(@__DIR__, "generate_gmfrm_posterior_predictive_grid.jl"))
end

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures", "gmfrm_sparse_pathology_recovery_grid.json")

include(joinpath(@__DIR__, "local_json.jl"))

const SPARSE = GMFRMSparseDesignGrid
const PPC = GMFRMPosteriorPredictiveGrid
const FITGRID = PPC.FITGRID
const SMOKE = SPARSE.SMOKE

const PROTOCOL = (;
    protocol_id = "scalar_gmfrm_sparse_pathology_recovery_grid_v1",
    review_kind = :local_guarded_experimental_sparse_pathology_recovery_grid,
    publication_or_registration_action = false,
    entrypoint_under_validation =
        "fit(spec; experimental = true) on sparse connected pathologies",
    simulation_source = :scalar_gmfrm_sparse_design_grid_scenarios,
    reviewed_protocols = (
        :scalar_gmfrm_sparse_design_grid_v1,
        :scalar_gmfrm_posterior_predictive_grid_v1,
    ),
    sparse_pathologies = SPARSE.PROTOCOL.sparse_designs,
    validation = SPARSE.PROTOCOL.validation,
    sampler = FITGRID.PROTOCOL.sampler,
    diagnostics = FITGRID.PROTOCOL.diagnostics,
    posterior_predictive = PPC.PROTOCOL.posterior_predictive,
    thresholds = (;
        n_scenarios = 3,
        min_observations = SPARSE.PROTOCOL.thresholds.min_observations,
        max_observations = SPARSE.PROTOCOL.thresholds.max_observations,
        n_replicates_per_scenario =
            FITGRID.PROTOCOL.sampler.draws * FITGRID.PROTOCOL.sampler.chains,
        n_summary_rows = PPC.PROTOCOL.thresholds.n_summary_rows,
        require_validation_passed = true,
        require_connected_design = true,
        require_full_location_rank = true,
        require_guarded_fit_returned = true,
        require_pointwise_shape = true,
        require_information_criteria_finite = true,
        require_no_divergences = true,
        require_no_max_treedepth = true,
        require_no_failed_direct_constraints = true,
        require_no_nonfinite_logdensity = true,
        require_no_nonfinite_direct_loglikelihood = true,
        require_replicated_scores_in_categories = true,
        require_probability_sums = true,
        require_summary_rows_finite = true,
        require_calibration_rows_finite = true,
        max_direct_parameter_mean_absolute_error = 8.0,
        max_direct_block_mean_absolute_error = 5.0,
        max_summary_outside_interval_rate = 0.85,
        max_absolute_summary_error = 1.25,
        max_absolute_mean_score_error = 1.0,
        max_absolute_category_proportion_error = 1.0,
        max_absolute_calibration_error = 1.25,
    ),
)

const SCENARIOS = [
    (SPARSE.SCENARIOS[1]..., fit_seed = 20261011, ppc_seed = 20261021),
    (SPARSE.SCENARIOS[2]..., fit_seed = 20261012, ppc_seed = 20261022),
    (SPARSE.SCENARIOS[3]..., fit_seed = 20261013, ppc_seed = 20261023),
]

function usage()
    return """
    Generate the local scalar GMFRM sparse-pathology recovery-grid artifact.

    The grid reuses the predeclared sparse connected scalar GMFRM scenarios,
    runs the guarded `fit(spec; experimental = true)` method, and records
    direct-scale recovery, posterior predictive checks, calibration, and sparse
    validation pathology summaries. It does not publish, register, or broaden
    the generalized model surface.

    Usage:
      julia --project=. scripts/generate_gmfrm_sparse_pathology_recovery_grid.jl [--output PATH]
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

function max_abs_error(rows)
    isempty(rows) && return NaN
    return maximum(abs(row.observed - row.replicated_mean) for row in rows)
end

function max_abs_calibration_error(rows)
    isempty(rows) && return NaN
    return maximum(row.absolute_calibration_error for row in rows)
end

function pointwise_shape_valid(pointwise, data)
    return collect(size(pointwise)) == [
        PROTOCOL.sampler.draws * PROTOCOL.sampler.chains,
        data.n,
    ]
end

function sparse_pathology_profile(validation)
    warning_codes = [row.code for row in validation.issue_rows
        if row.severity === :warning]
    return (;
        n_observations = validation.n_observations,
        n_warnings = validation.n_warnings,
        warning_codes,
        n_components = validation.n_components,
        location_design_full_rank = validation.location_design_full_rank,
        min_dff_cell_count = isempty(validation.dff_cell_counts) ? missing :
            minimum(row.n for row in validation.dff_cell_counts),
    )
end

function scenario_record(spec)
    simulated = SPARSE.table_for_scenario(spec)
    table = simulated.table
    data = SMOKE.facet_data(table)
    validation_report = BayesianMGMFRM.validate_design(
        data;
        bias = collect(PROTOCOL.validation.bias_terms),
        min_cell_count = PROTOCOL.validation.min_cell_count,
    )
    validation = SPARSE.validation_record(data, validation_report)
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
    metadata = BayesianMGMFRM.fit_metadata(fit)
    diagnostics = BayesianMGMFRM.diagnostics(fit; FITGRID.diagnostic_kwargs()...)
    pointwise = BayesianMGMFRM.pointwise_loglikelihood_matrix(fit)
    waic_stat = BayesianMGMFRM.waic(fit)
    loo_stat = BayesianMGMFRM.loo(
        fit;
        min_tail_draws = PROTOCOL.diagnostics.loo_min_tail_draws,
    )
    truth_direct =
        BayesianMGMFRM._gmfrm_source_constrained_params_from_unconstrained(
            simulated.placeholder_design,
            spec.raw_truth,
        )
    fit.design.parameter_names == simulated.placeholder_design.parameter_names ||
        error("sparse-pathology fit changed direct parameter order")
    recovery_rows = FITGRID.direct_recovery_rows(fit, truth_direct)
    recovery_by_block = FITGRID.direct_recovery_by_block(recovery_rows)
    draw_indices = collect(1:size(fit.draws, 1))
    probabilities = BayesianMGMFRM.predictive_probabilities(fit; draw_indices)
    probability_review = PPC.probability_sums_valid(probabilities)
    expected = BayesianMGMFRM.expected_scores(fit; draw_indices)
    variances = BayesianMGMFRM.predictive_variances(fit; draw_indices)
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
    all_calibration_rows = [calibration_rows..., category_calibration_rows...]
    mean_score_rows = [row for row in summary_rows if row.statistic === :mean_score]
    category_rows = [row for row in summary_rows if row.statistic === :category_proportion]
    outside_count = count(row -> row.flag !== :ok, summary_rows)
    replicated_scores_valid =
        all(score -> score in data.category_levels, vec(ppc.replicated_scores))
    expected_min = minimum(data.category_levels)
    expected_max = maximum(data.category_levels)
    expected_scores_in_range =
        all(value -> expected_min - 1e-10 <= value <= expected_max + 1e-10,
            expected)
    diagnostic_summary = diagnostics.summary
    information_criteria_finite =
        isfinite(waic_stat.elpd_waic) && isfinite(waic_stat.waic) &&
        isfinite(loo_stat.elpd_loo) && isfinite(loo_stat.looic)
    summary_rows_finite = all(PPC.all_top_level_numeric_finite, summary_rows)
    calibration_rows_finite =
        all(PPC.all_top_level_numeric_finite, all_calibration_rows)
    passed = fit isa BayesianMGMFRM.GMFRMFit &&
        validation.passed &&
        validation.n_components == 1 &&
        validation.location_design_full_rank &&
        PROTOCOL.thresholds.min_observations <= data.n <=
            PROTOCOL.thresholds.max_observations &&
        Bool(metadata.public_fit) &&
        Bool(metadata.experimental_public) &&
        pointwise_shape_valid(pointwise, data) &&
        all(isfinite, pointwise) &&
        all(isfinite, fit.log_posterior) &&
        all(isfinite, fit.direct_loglikelihood) &&
        all(isfinite, fit.direct_pointwise_loglikelihood) &&
        information_criteria_finite &&
        diagnostic_summary.n_divergences == 0 &&
        diagnostic_summary.n_max_treedepth == 0 &&
        diagnostic_summary.n_failed_direct_constraints == 0 &&
        diagnostic_summary.n_nonfinite_logdensity == 0 &&
        diagnostic_summary.n_nonfinite_direct_loglikelihood == 0 &&
        all(row -> row.finite, recovery_rows) &&
        maximum(row.absolute_bias for row in recovery_rows) <=
            PROTOCOL.thresholds.max_direct_parameter_mean_absolute_error &&
        maximum(row.mean_absolute_error for row in recovery_by_block) <=
            PROTOCOL.thresholds.max_direct_block_mean_absolute_error &&
        replicated_scores_valid &&
        Bool(probability_review.valid) &&
        summary_rows_finite &&
        calibration_rows_finite &&
        outside_count / length(summary_rows) <=
            PROTOCOL.thresholds.max_summary_outside_interval_rate &&
        max_abs_error(summary_rows) <= PROTOCOL.thresholds.max_absolute_summary_error &&
        max_abs_error(mean_score_rows) <=
            PROTOCOL.thresholds.max_absolute_mean_score_error &&
        max_abs_error(category_rows) <=
            PROTOCOL.thresholds.max_absolute_category_proportion_error &&
        max_abs_calibration_error(all_calibration_rows) <=
            PROTOCOL.thresholds.max_absolute_calibration_error &&
        expected_scores_in_range &&
        all(>=(0.0), variances)

    return (;
        scenario = spec.scenario,
        sparse_pattern = spec.sparse_pattern,
        simulation_seed = spec.simulation_seed,
        actual_simulation_seed = simulated.actual_simulation_seed,
        fit_seed = spec.fit_seed,
        posterior_predictive_seed = spec.ppc_seed,
        raw_truth_sha256 = FITGRID.raw_truth_hash(spec.raw_truth),
        selected_row_indices = simulated.selected_indices,
        design_density = (;
            rating_density = :sparse_connected,
            n_observations = data.n,
            full_crossed_observations = SPARSE.PROTOCOL.full_crossed_observations,
            observed_fraction = data.n / SPARSE.PROTOCOL.full_crossed_observations,
            missing_observations =
                SPARSE.PROTOCOL.full_crossed_observations - data.n,
        ),
        simulated_data = (;
            n_observations = data.n,
            score_counts = PPC.score_count_rows(table.score, data.category_levels),
            person_levels = data.person_levels,
            rater_levels = data.rater_levels,
            item_levels = data.item_levels,
            category_levels = data.category_levels,
        ),
        validation,
        sparse_pathology_profile = sparse_pathology_profile(validation),
        fit_record = (;
            type = String(nameof(typeof(fit))),
            backend = fit.backend,
            sampler = fit.sampler,
            raw_draws_shape = collect(size(fit.draws)),
            direct_draws_shape = collect(size(fit.direct_draws)),
            pointwise_loglikelihood_shape = collect(size(pointwise)),
        ),
        metadata_review = (;
            public_fit = metadata.public_fit,
            experimental_public = metadata.experimental_public,
            family = metadata.family,
            dimensions = metadata.dimensions,
            discrimination = metadata.discrimination,
            n_draws = metadata.n_draws,
            n_chains = metadata.n_chains,
            draws_per_chain = metadata.draws_per_chain,
            n_parameters = metadata.n_parameters,
            n_direct_parameters = metadata.n_direct_parameters,
        ),
        diagnostics_review = (;
            schema = diagnostics.schema,
            public_fit = diagnostics.public_fit,
            experimental_public = diagnostics.experimental_public,
            summary = diagnostics.summary,
        ),
        information_criteria_review = (;
            waic = FITGRID.finite_stat_summary(waic_stat),
            loo = FITGRID.finite_stat_summary(loo_stat),
            all_top_level_numeric_finite =
                PPC.all_top_level_numeric_finite(waic_stat) &&
                PPC.all_top_level_numeric_finite(loo_stat),
        ),
        direct_recovery_rows = recovery_rows,
        direct_recovery_by_block = recovery_by_block,
        predictive_probability_review = (;
            shape = collect(size(probabilities)),
            probability_sums_valid = probability_review.valid,
            max_probability_sum_error = probability_review.max_sum_error,
            expected_scores = PPC.finite_matrix_summary(expected),
            predictive_variances = PPC.finite_matrix_summary(variances),
            expected_scores_in_range,
        ),
        posterior_predictive_review = (;
            replicated_scores_shape = collect(size(ppc.replicated_scores)),
            replicated_scores_in_categories = replicated_scores_valid,
            n_summary_rows = length(summary_rows),
            summary_rows,
            summary_group_rows = PPC.summary_group_rows(summary_rows),
        ),
        calibration_review = (;
            expected_score_rows = calibration_rows,
            category_probability_rows = category_calibration_rows,
            top_category = last(data.category_levels),
            n_rows = length(all_calibration_rows),
            all_rows_finite = calibration_rows_finite,
            max_absolute_calibration_error =
                max_abs_calibration_error(all_calibration_rows),
        ),
        summary = (;
            passed,
            n_observations = data.n,
            validation_passed = validation.passed,
            validation_warnings = validation.n_warnings,
            location_design_full_rank = validation.location_design_full_rank,
            pointwise_shape_valid = pointwise_shape_valid(pointwise, data),
            information_criteria_finite,
            n_divergences = diagnostic_summary.n_divergences,
            n_max_treedepth = diagnostic_summary.n_max_treedepth,
            n_failed_direct_constraints =
                diagnostic_summary.n_failed_direct_constraints,
            n_nonfinite_logdensity = diagnostic_summary.n_nonfinite_logdensity,
            n_nonfinite_direct_loglikelihood =
                diagnostic_summary.n_nonfinite_direct_loglikelihood,
            max_direct_parameter_mean_absolute_error =
                maximum(row.absolute_bias for row in recovery_rows),
            max_direct_block_mean_absolute_error =
                maximum(row.mean_absolute_error for row in recovery_by_block),
            ppc_returned = true,
            n_replicates = length(draw_indices),
            n_summary_rows = length(summary_rows),
            replicated_scores_in_categories = replicated_scores_valid,
            probability_sums_valid = probability_review.valid,
            summary_rows_finite,
            calibration_rows_finite,
            outside_interval_rate = outside_count / length(summary_rows),
            max_absolute_summary_error = max_abs_error(summary_rows),
            max_absolute_mean_score_error = max_abs_error(mean_score_rows),
            max_absolute_category_proportion_error = max_abs_error(category_rows),
            max_absolute_calibration_error =
                max_abs_calibration_error(all_calibration_rows),
            expected_scores_in_range,
            predictive_variances_nonnegative = all(>=(0.0), variances),
        ),
    )
end

function grid_artifact()
    scenarios = [scenario_record(spec) for spec in SCENARIOS]
    passed = all(scenario -> scenario.summary.passed, scenarios)
    all_recovery_rows =
        reduce(vcat, [scenario.direct_recovery_rows for scenario in scenarios])
    all_recovery_by_block =
        reduce(vcat, [scenario.direct_recovery_by_block for scenario in scenarios])
    return (;
        schema = "bayesianmgmfrm.gmfrm_sparse_pathology_recovery_grid.v1",
        family = :gmfrm,
        scope = :scalar_gmfrm_fit_ready_candidate,
        status = :guarded_experimental_sparse_pathology_recovery_grid_recorded,
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
            fixture_reference("test/fixtures/gmfrm_sparse_design_grid.json"),
            fixture_reference("test/fixtures/gmfrm_posterior_predictive_grid.json"),
        ],
        scenarios,
        decision_record = (;
            public_fit_allowed = true,
            experimental_keyword_enabled = true,
            public_exposure_support =
                :satisfied_for_scalar_gmfrm_prior_likelihood_sensitivity_grid_followup,
            interpretation =
                :guarded_scalar_gmfrm_sparse_pathology_recovery_grid_passed,
            required_followup = :scalar_gmfrm_prior_likelihood_sensitivity_grid,
        ),
        summary = (;
            passed,
            publication_or_registration_action = false,
            n_scenarios = length(scenarios),
            n_passed_scenarios = count(scenario -> scenario.summary.passed, scenarios),
            n_replicates_per_scenario =
                PROTOCOL.thresholds.n_replicates_per_scenario,
            n_observations_minimum =
                minimum(scenario.summary.n_observations for scenario in scenarios),
            n_observations_maximum =
                maximum(scenario.summary.n_observations for scenario in scenarios),
            all_validations_passed =
                all(scenario -> scenario.summary.validation_passed, scenarios),
            all_location_designs_full_rank =
                all(scenario -> scenario.summary.location_design_full_rank, scenarios),
            all_guarded_fit_returned =
                all(scenario -> String(scenario.fit_record.type) == "GMFRMFit",
                    scenarios),
            all_pointwise_shapes_valid =
                all(scenario -> scenario.summary.pointwise_shape_valid, scenarios),
            all_information_criteria_finite =
                all(scenario -> scenario.summary.information_criteria_finite,
                    scenarios),
            all_no_divergences =
                all(scenario -> scenario.summary.n_divergences == 0, scenarios),
            all_no_max_treedepth =
                all(scenario -> scenario.summary.n_max_treedepth == 0, scenarios),
            all_no_failed_direct_constraints =
                all(scenario -> scenario.summary.n_failed_direct_constraints == 0,
                    scenarios),
            all_no_nonfinite_logdensity =
                all(scenario -> scenario.summary.n_nonfinite_logdensity == 0,
                    scenarios),
            all_no_nonfinite_direct_loglikelihood =
                all(scenario ->
                    scenario.summary.n_nonfinite_direct_loglikelihood == 0,
                    scenarios),
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
            max_direct_parameter_mean_absolute_error =
                maximum(row.absolute_bias for row in all_recovery_rows),
            max_direct_block_mean_absolute_error =
                maximum(row.mean_absolute_error for row in all_recovery_by_block),
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
            remaining_public_blockers = [
                :scalar_gmfrm_prior_likelihood_sensitivity_grid_missing,
            ],
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
    println("wrote ", output)
    println("passed=", artifact.summary.passed,
        " scenarios=", artifact.summary.n_scenarios,
        " next_gate=", artifact.summary.next_gate)
    return nothing
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    main(ARGS)
end
