#!/usr/bin/env julia

using SHA
using TOML

import BayesianMGMFRM
import LogDensityProblems
import Random

module GMFRMRecoverySmoke
include(joinpath(@__DIR__, "generate_gmfrm_recovery_smoke.jl"))
end

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures", "gmfrm_baseline_calibration_grid.json")

include(joinpath(@__DIR__, "local_json.jl"))

const PROTOCOL = (;
    protocol_id = "scalar_gmfrm_baseline_calibration_grid_v1",
    simulation_source = :scalar_gmfrm_recovery_smoke_grid_variant,
    data_grid = GMFRMRecoverySmoke.PROTOCOL.grid,
    models = (:gmfrm_internal_candidate, :mfrm_partial_credit, :mfrm_rating_scale),
    calibration = (;
        target = :expected_score,
        bins = 3,
    ),
    gmfrm_sampler = (;
        backend = GMFRMRecoverySmoke.PROTOCOL.sampler.backend,
        sampler = GMFRMRecoverySmoke.PROTOCOL.sampler.sampler,
        chains = GMFRMRecoverySmoke.PROTOCOL.sampler.chains,
        warmup = GMFRMRecoverySmoke.PROTOCOL.sampler.warmup,
        draws = GMFRMRecoverySmoke.PROTOCOL.sampler.draws,
        step_size = GMFRMRecoverySmoke.PROTOCOL.sampler.step_size,
        target_accept = GMFRMRecoverySmoke.PROTOCOL.sampler.target_accept,
        max_depth = GMFRMRecoverySmoke.PROTOCOL.sampler.max_depth,
        max_energy_error = GMFRMRecoverySmoke.PROTOCOL.sampler.max_energy_error,
        metric = GMFRMRecoverySmoke.PROTOCOL.sampler.metric,
        ad_backend = GMFRMRecoverySmoke.PROTOCOL.sampler.ad_backend,
        init_jitter = GMFRMRecoverySmoke.PROTOCOL.sampler.init_jitter,
        split_chains = GMFRMRecoverySmoke.PROTOCOL.sampler.split_chains,
    ),
    baseline_sampler = (;
        backend = :advancedhmc,
        sampler = :nuts,
        chains = 2,
        warmup = 64,
        draws = 64,
        step_size = 0.03,
        target_accept = 0.8,
        max_depth = 6,
        max_energy_error = 1000.0,
        metric = :unit,
        ad_backend = :ForwardDiff,
        init_jitter = 0.0,
        split_chains = true,
    ),
    diagnostics = (;
        rhat_threshold = 1.2,
        ess_threshold = 8.0,
    ),
    thresholds = (;
        n_scenarios = 3,
        n_models_per_scenario = 3,
        n_observations = GMFRMRecoverySmoke.PROTOCOL.grid.observations,
        require_all_scenarios_passed = true,
        require_same_observations = true,
        require_finite_elpd = true,
        require_finite_calibration = true,
        require_sampler_passed = true,
        max_expected_score_rmse = 1.25,
        max_mean_absolute_calibration_error = 0.75,
    ),
)

const SCENARIOS = [
    (;
        scenario = :near_rasch,
        simulation_seed = 20260751,
        gmfrm_seed = 20260752,
        partial_credit_seed = 20260753,
        rating_scale_seed = 20260754,
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
        scenario = :moderate_generalized,
        simulation_seed = GMFRMRecoverySmoke.PROTOCOL.simulation_seed,
        gmfrm_seed = 20260755,
        partial_credit_seed = 20260756,
        rating_scale_seed = 20260757,
        raw_truth = GMFRMRecoverySmoke.TRUTH_RAW,
    ),
    (;
        scenario = :stronger_generalized,
        simulation_seed = 20260758,
        gmfrm_seed = 20260759,
        partial_credit_seed = 20260760,
        rating_scale_seed = 20260761,
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
    Generate the local scalar GMFRM baseline-calibration grid artifact.

    Usage:
      julia --project=. scripts/generate_gmfrm_baseline_calibration_grid.jl [--output PATH]
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

function score_count_rows(scores)
    return [(score = value, n = count(==(value), scores))
        for value in sort(unique(scores))]
end

function mean_float(values)
    return sum(Float64, values) / length(values)
end

function pointwise_se(values::AbstractVector{<:Real})
    n = length(values)
    n <= 1 && return NaN
    mean_value = mean_float(values)
    ss = sum((Float64(value) - mean_value)^2 for value in values)
    return sqrt(n * ss / (n - 1))
end

function maybe_float(value)
    return ismissing(value) ? missing : Float64(value)
end

function maybe_int(value)
    return ismissing(value) ? missing : Int(value)
end

function table_for_scenario(spec)
    placeholder_design =
        GMFRMRecoverySmoke.scalar_gmfrm_design(GMFRMRecoverySmoke.placeholder_table())
    direct_truth =
        BayesianMGMFRM._gmfrm_source_constrained_params_from_unconstrained(
            placeholder_design,
            spec.raw_truth,
        )
    scores = GMFRMRecoverySmoke.sample_scores(
        placeholder_design,
        direct_truth;
        rng = Random.MersenneTwister(spec.simulation_seed),
    )
    base = GMFRMRecoverySmoke.placeholder_table()
    return (;
        placeholder_design,
        direct_truth,
        table = (;
            examinee = base.examinee,
            rater = base.rater,
            item = base.item,
            score = scores,
        ),
    )
end

function gmfrm_expected_scores(design, direct_draws::AbstractMatrix)
    data = design.spec.data
    levels = Float64.(data.category_levels)
    out = Matrix{Float64}(undef, size(direct_draws, 1), data.n)
    for draw in axes(direct_draws, 1)
        rows = BayesianMGMFRM._gmfrm_source_fixture_values(
            design,
            view(direct_draws, draw, :),
        )
        for observation in 1:data.n
            observation_rows = [row for row in rows if row.row == observation]
            expected = 0.0
            for row in observation_rows
                category_index = findfirst(==(row.category), data.category_levels)
                expected += levels[category_index] * exp(row.log_probability)
            end
            out[draw, observation] = expected
        end
    end
    return out
end

function column_means(matrix::AbstractMatrix{<:Real})
    means = Vector{Float64}(undef, size(matrix, 2))
    for col in axes(matrix, 2)
        means[col] = mean_float(@view matrix[:, col])
    end
    return means
end

function calibration_rows(expected::AbstractMatrix{<:Real},
        observed::AbstractVector{<:Real};
        bins::Int)
    n = length(observed)
    n == size(expected, 2) ||
        error("expected score matrix observation count does not match observed scores")
    predicted_mean = column_means(expected)
    order = sortperm(predicted_mean; alg = MergeSort)
    nbins = min(bins, n)
    assignments = Vector{Int}(undef, n)
    for (rank, row) in pairs(order)
        assignments[row] = min(nbins, fld((rank - 1) * nbins, n) + 1)
    end
    rows = NamedTuple[]
    for bin in 1:nbins
        indices = findall(==(bin), assignments)
        observed_mean = mean_float(@view observed[indices])
        predicted_bin_mean = mean_float(@view predicted_mean[indices])
        calibration_error = observed_mean - predicted_bin_mean
        push!(rows, (;
            target = :expected_score,
            bin,
            n_observations = length(indices),
            predicted_bin_lower = minimum(@view predicted_mean[indices]),
            predicted_bin_upper = maximum(@view predicted_mean[indices]),
            observed_mean,
            predicted_mean = predicted_bin_mean,
            calibration_error,
            absolute_calibration_error = abs(calibration_error),
        ))
    end
    return rows
end

function predictive_metrics(expected::AbstractMatrix{<:Real},
        observed::AbstractVector{<:Real},
    calibration)
    predicted_mean = column_means(expected)
    residuals = Float64.(observed) .- predicted_mean
    calibration_mae =
        mean_float([row.absolute_calibration_error for row in calibration])
    return (;
        mean_observed_score = mean_float(observed),
        mean_predicted_score = mean_float(predicted_mean),
        mean_residual = mean_float(residuals),
        mean_absolute_residual = mean_float(abs.(residuals)),
        expected_score_rmse = sqrt(mean_float(residuals .^ 2)),
        mean_absolute_calibration_error = calibration_mae,
        max_absolute_calibration_error =
            maximum(row.absolute_calibration_error for row in calibration),
    )
end

function gmfrm_sampler_summary_record(summary)
    return (;
        internal_flag = summary.flag,
        internal_passed = summary.passed,
        n_chains = summary.n_chains,
        draws_per_chain = summary.draws_per_chain,
        total_draws = summary.total_draws,
        max_rhat = summary.max_rhat,
        min_ess = summary.min_ess,
        n_bad_rhat = summary.n_bad_rhat,
        n_low_ess = summary.n_low_ess,
        n_divergences = summary.n_divergences,
        n_max_treedepth = summary.n_max_treedepth,
        e_bfmi = summary.e_bfmi,
        n_sampler_warnings = summary.n_sampler_warnings,
        n_block_warnings = summary.n_block_warnings,
        n_direct_block_warnings = summary.n_direct_block_warnings,
        n_nonfinite_logdensity = summary.n_nonfinite_logdensity,
        n_nonfinite_direct_loglikelihood =
            summary.n_nonfinite_direct_loglikelihood,
        n_failed_direct_constraints = summary.n_failed_direct_constraints,
    )
end

function baseline_sampler_summary_record(summary)
    return (;
        internal_flag = summary.flag,
        internal_passed = summary.passed,
        n_chains = summary.n_chains,
        draws_per_chain = summary.draws_per_chain,
        total_draws = summary.total_draws,
        n_parameters = summary.n_parameters,
        max_rhat = maybe_float(summary.max_rhat),
        min_ess = maybe_float(summary.min_ess),
        n_bad_rhat = summary.n_bad_rhat,
        n_low_ess = summary.n_low_ess,
        n_divergences = maybe_int(summary.n_divergences),
        n_max_treedepth = maybe_int(summary.n_max_treedepth),
        e_bfmi = maybe_float(summary.e_bfmi),
        n_sampler_warnings = summary.n_sampler_warnings,
        n_block_warnings = summary.n_block_warnings,
        n_nonfinite_log_posterior = summary.n_nonfinite_log_posterior,
    )
end

function model_record(record, stat, expected, observed)
    calibration = calibration_rows(
        expected,
        observed;
        bins = PROTOCOL.calibration.bins,
    )
    return (;
        record...,
        stat,
        expected_score_calibration = calibration,
        predictive_metrics = predictive_metrics(expected, observed, calibration),
    )
end

function gmfrm_model_result(data, table, seed::Int)
    design = GMFRMRecoverySmoke.scalar_gmfrm_design(table)
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
    expected = gmfrm_expected_scores(design, diagnostics.direct_draws)
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
        sampler_summary = gmfrm_sampler_summary_record(diagnostics.summary),
    )
    return model_record(record, stat, expected, data.score)
end

function baseline_model_result(data, model::Symbol, thresholds::Symbol, seed::Int)
    spec = BayesianMGMFRM.mfrm_spec(data; thresholds)
    design = BayesianMGMFRM.getdesign(spec)
    sampler = PROTOCOL.baseline_sampler
    prior = BayesianMGMFRM.MFRMPrior()
    fit = BayesianMGMFRM.fit(design;
        prior,
        backend = sampler.backend,
        ndraws = sampler.draws,
        warmup = sampler.warmup,
        chains = sampler.chains,
        step_size = sampler.step_size,
        seed,
        target_accept = sampler.target_accept,
        max_depth = sampler.max_depth,
        max_energy_error = sampler.max_energy_error,
        metric = sampler.metric,
        ad_backend = sampler.ad_backend,
        init_jitter = sampler.init_jitter,
        progress = false)
    diagnostics = BayesianMGMFRM.diagnostics(fit;
        split_chains = sampler.split_chains,
        rhat_threshold = PROTOCOL.diagnostics.rhat_threshold,
        ess_threshold = PROTOCOL.diagnostics.ess_threshold)
    stat = BayesianMGMFRM.waic(fit)
    expected = BayesianMGMFRM.expected_scores(fit)
    record = (;
        model,
        family = :mfrm,
        source = :public_minimal_fit,
        threshold_regime = thresholds,
        estimation_status = :fit_supported,
        public_fit = true,
        seed,
        n_parameters = length(design.parameter_names),
        parameter_order_sha256 = parameter_order_hash(design.parameter_names),
        direct_parameter_order_sha256 = missing,
        sampler_summary = baseline_sampler_summary_record(diagnostics.summary),
    )
    return model_record(record, stat, expected, data.score)
end

function comparison_rows(results)
    stats = [result.stat for result in results]
    order = sortperm(eachindex(stats); by = index -> stats[index].elpd_waic, rev = true)
    best = stats[order[1]]
    unnormalized_weights = [exp(stat.elpd_waic - best.elpd_waic) for stat in stats]
    weight_total = sum(unnormalized_weights)
    rows = NamedTuple[]
    for (rank, index) in pairs(order)
        result = results[index]
        stat = result.stat
        pointwise_difference = stat.pointwise.elpd_waic .- best.pointwise.elpd_waic
        push!(rows, (;
            model = result.model,
            family = result.family,
            source = result.source,
            threshold_regime = result.threshold_regime,
            estimation_status = result.estimation_status,
            public_fit = result.public_fit,
            seed = result.seed,
            n_parameters = result.n_parameters,
            parameter_order_sha256 = result.parameter_order_sha256,
            direct_parameter_order_sha256 = result.direct_parameter_order_sha256,
            sampler_summary = result.sampler_summary,
            rank,
            criterion = :waic,
            elpd_waic = stat.elpd_waic,
            elpd_difference = stat.elpd_waic - best.elpd_waic,
            se_elpd_difference = pointwise_se(pointwise_difference),
            se_elpd_waic = stat.se_elpd_waic,
            waic = stat.waic,
            waic_difference = stat.waic - best.waic,
            se_waic = stat.se_waic,
            relative_weight = unnormalized_weights[index] / weight_total,
            p_waic = stat.p_waic,
            lppd = stat.lppd,
            n_draws = stat.n_draws,
            n_observations = stat.n_observations,
            high_variance_count = stat.high_variance_count,
            warning = stat.warning,
            expected_score_calibration = result.expected_score_calibration,
            predictive_metrics = result.predictive_metrics,
        ))
    end
    return rows
end

function scenario_passed(rows)
    thresholds = PROTOCOL.thresholds
    length(rows) == thresholds.n_models_per_scenario || return false
    if thresholds.require_same_observations &&
            length(unique(row.n_observations for row in rows)) != 1
        return false
    end
    all(row -> row.n_observations == thresholds.n_observations, rows) || return false
    if thresholds.require_finite_elpd
        all(row -> isfinite(row.elpd_waic) && isfinite(row.waic), rows) || return false
    end
    if thresholds.require_finite_calibration
        all(row -> isfinite(row.predictive_metrics.expected_score_rmse) &&
            isfinite(row.predictive_metrics.mean_absolute_calibration_error), rows) ||
            return false
    end
    if thresholds.require_sampler_passed
        all(row -> row.sampler_summary.internal_passed, rows) || return false
    end
    all(row -> row.predictive_metrics.expected_score_rmse <=
        thresholds.max_expected_score_rmse, rows) || return false
    all(row -> row.predictive_metrics.mean_absolute_calibration_error <=
        thresholds.max_mean_absolute_calibration_error, rows) || return false
    return true
end

function scenario_record(spec)
    simulated = table_for_scenario(spec)
    table = simulated.table
    data = GMFRMRecoverySmoke.facet_data(table)
    results = [
        gmfrm_model_result(data, table, spec.gmfrm_seed),
        baseline_model_result(
            data,
            :mfrm_partial_credit,
            :partial_credit,
            spec.partial_credit_seed,
        ),
        baseline_model_result(
            data,
            :mfrm_rating_scale,
            :rating_scale,
            spec.rating_scale_seed,
        ),
    ]
    rows = comparison_rows(results)
    gmfrm_row = only(row for row in rows if row.model === :gmfrm_internal_candidate)
    passed = scenario_passed(rows)
    return (;
        scenario = spec.scenario,
        simulation_seed = spec.simulation_seed,
        raw_truth_sha256 = bytes2hex(sha256(codeunits(join(spec.raw_truth, "\n")))),
        simulated_data = (;
            n_observations = data.n,
            score_counts = score_count_rows(table.score),
            person_levels = data.person_levels,
            rater_levels = data.rater_levels,
            item_levels = data.item_levels,
            category_levels = data.category_levels,
        ),
        model_rows = rows,
        summary = (;
            passed,
            best_model = rows[1].model,
            gmfrm_rank = gmfrm_row.rank,
            gmfrm_elpd_difference = gmfrm_row.elpd_difference,
            gmfrm_expected_score_rmse =
                gmfrm_row.predictive_metrics.expected_score_rmse,
            gmfrm_mean_absolute_calibration_error =
                gmfrm_row.predictive_metrics.mean_absolute_calibration_error,
            any_high_variance_waic = any(row -> row.warning !== :ok, rows),
        ),
    )
end

function grid_artifact()
    scenarios = [scenario_record(spec) for spec in SCENARIOS]
    passed = all(scenario -> scenario.summary.passed, scenarios)
    all_rows = reduce(vcat, [scenario.model_rows for scenario in scenarios])
    return (;
        schema = "bayesianmgmfrm.gmfrm_baseline_calibration_grid.v1",
        family = :gmfrm,
        scope = :scalar_gmfrm_fit_ready_candidate,
        status = :internal_baseline_calibration_grid,
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
            n_models = length(all_rows),
            n_public_baseline_models = count(row -> row.public_fit, all_rows),
            n_internal_candidate_models = count(row -> !row.public_fit, all_rows),
            best_model_counts = [
                (model,
                    n = count(scenario -> scenario.summary.best_model === model, scenarios))
                for model in PROTOCOL.models
            ],
            max_expected_score_rmse =
                maximum(row.predictive_metrics.expected_score_rmse for row in all_rows),
            max_mean_absolute_calibration_error = maximum(
                row.predictive_metrics.mean_absolute_calibration_error for row in all_rows),
            any_high_variance_waic = any(row -> row.warning !== :ok, all_rows),
            recommendation = :keep_internal_until_public_exposure_review,
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
        " max_rmse=", artifact.summary.max_expected_score_rmse,
        " max_cal_mae=", artifact.summary.max_mean_absolute_calibration_error)
    return nothing
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    main(ARGS)
end
