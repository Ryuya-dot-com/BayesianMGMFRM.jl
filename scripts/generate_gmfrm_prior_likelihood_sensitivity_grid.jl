#!/usr/bin/env julia

using Random
using SHA
using TOML

import BayesianMGMFRM

module GMFRMSparsePathologyRecoveryGrid
include(joinpath(@__DIR__, "generate_gmfrm_sparse_pathology_recovery_grid.jl"))
end

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures", "gmfrm_prior_likelihood_sensitivity_grid.json")

include(joinpath(@__DIR__, "local_json.jl"))

const SPATH = GMFRMSparsePathologyRecoveryGrid
const FITGRID = SPATH.FITGRID
const PPC = SPATH.PPC
const SMOKE = SPATH.SMOKE

const PRIOR_PROFILES = [
    (name = :baseline_raw_prior, scale = 1.0,
        person_sd = 1.0, rater_sd = 1.0, item_sd = 1.0,
        log_discrimination_sd = 0.5, log_consistency_sd = 0.5, step_sd = 1.0),
    (name = :globally_tighter_raw_prior, scale = 0.8,
        person_sd = 0.8, rater_sd = 0.8, item_sd = 0.8,
        log_discrimination_sd = 0.4, log_consistency_sd = 0.4, step_sd = 0.8),
    (name = :globally_weaker_raw_prior, scale = 1.25,
        person_sd = 1.25, rater_sd = 1.25, item_sd = 1.25,
        log_discrimination_sd = 0.625, log_consistency_sd = 0.625, step_sd = 1.25),
    (name = :tighter_generalized_scale_prior, scale = 1.0,
        person_sd = 1.0, rater_sd = 1.0, item_sd = 1.0,
        log_discrimination_sd = 0.35, log_consistency_sd = 0.35, step_sd = 1.0),
    (name = :weaker_generalized_scale_prior, scale = 1.0,
        person_sd = 1.0, rater_sd = 1.0, item_sd = 1.0,
        log_discrimination_sd = 0.75, log_consistency_sd = 0.75, step_sd = 1.0),
]

const LIKELIHOOD_POWERS = [0.8, 1.0, 1.2]

const PROTOCOL = (;
    protocol_id = "scalar_gmfrm_prior_likelihood_sensitivity_grid_v1",
    review_kind = :local_guarded_experimental_prior_likelihood_sensitivity_grid,
    publication_or_registration_action = false,
    entrypoint_under_validation =
        "importance-reweighted fit(spec; experimental = true) prior and likelihood sensitivity",
    simulation_source = :scalar_gmfrm_sparse_pathology_recovery_grid_scenarios,
    reviewed_protocols = (
        :scalar_gmfrm_sparse_pathology_recovery_grid_v1,
        :scalar_gmfrm_guarded_exposure_review_v1,
    ),
    sensitivity_method = (;
        draw_source = :guarded_experimental_gmfrm_fit_draws,
        prior_sensitivity = :raw_coordinate_importance_reweighting,
        likelihood_sensitivity = :power_likelihood_tempering,
        refit_policy = :not_refit_local_guarded_screen,
        normalization = :self_normalized_importance_weights,
    ),
    prior_profiles = PRIOR_PROFILES,
    likelihood_powers = LIKELIHOOD_POWERS,
    sampler = SPATH.PROTOCOL.sampler,
    diagnostics = SPATH.PROTOCOL.diagnostics,
    thresholds = (;
        n_scenarios = length(SPATH.SCENARIOS),
        n_prior_profiles = length(PRIOR_PROFILES),
        n_likelihood_powers = length(LIKELIHOOD_POWERS),
        n_sensitivity_cells = length(PRIOR_PROFILES) * length(LIKELIHOOD_POWERS),
        n_draws_per_cell =
            SPATH.PROTOCOL.sampler.draws * SPATH.PROTOCOL.sampler.chains,
        require_guarded_fit_returned = true,
        require_all_logweights_finite = true,
        require_baseline_identity = true,
        require_weight_ess_rate_minimum = 0.05,
        require_all_direct_shifts_finite = true,
        require_all_predictive_shifts_finite = true,
        max_direct_parameter_mean_shift = 3.0,
        max_direct_block_mean_shift = 2.0,
        max_expected_score_shift = 1.25,
        max_top_category_probability_shift = 0.60,
        max_loglikelihood_mean_shift = 20.0,
        max_logposterior_decomposition_error = 1e-8,
    ),
)

const SCENARIOS = SPATH.SCENARIOS

function usage()
    return """
    Generate the local scalar GMFRM prior/likelihood sensitivity-grid artifact.

    The grid reruns the guarded scalar GMFRM sparse-pathology scenarios and
    performs self-normalized importance reweighting over raw-coordinate prior
    profiles and likelihood-power settings. It is a local guarded screen only:
    it does not publish, register, broaden the public API, or refit under
    alternate priors.

    Usage:
      julia --project=. scripts/generate_gmfrm_prior_likelihood_sensitivity_grid.jl [--output PATH]
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

function fixture_reference(path::AbstractString; hash_policy::Symbol = :sha256)
    local_path = joinpath(ROOT, path)
    return (;
        artifact = path,
        exists = isfile(local_path),
        hash_policy,
        sha256 =
            hash_policy === :sha256 && isfile(local_path) ? file_sha256(local_path) :
            missing,
    )
end

function source_prior(profile)
    return BayesianMGMFRM._SourceFixturePrior(;
        person_sd = profile.person_sd,
        rater_sd = profile.rater_sd,
        item_sd = profile.item_sd,
        log_discrimination_sd = profile.log_discrimination_sd,
        log_consistency_sd = profile.log_consistency_sd,
        step_sd = profile.step_sd,
    )
end

function source_prior_record(prior)
    return (;
        person_sd = prior.person_sd,
        rater_sd = prior.rater_sd,
        item_sd = prior.item_sd,
        log_discrimination_sd = prior.log_discrimination_sd,
        log_consistency_sd = prior.log_consistency_sd,
        step_sd = prior.step_sd,
    )
end

function finite_vector_summary(values)
    vector = Float64.(collect(values))
    return (;
        n = length(vector),
        all_finite = all(isfinite, vector),
        minimum = minimum(vector),
        maximum = maximum(vector),
        mean = sum(vector) / length(vector),
    )
end

function normalized_weight_summary(logweights::AbstractVector{<:Real})
    logs = Float64.(collect(logweights))
    all_finite = all(isfinite, logs)
    if !all_finite
        weights = fill(NaN, length(logs))
        return (weights = weights, summary = (;
            all_logweights_finite = false,
            logweight_range = NaN,
            effective_sample_size = NaN,
            effective_sample_size_rate = NaN,
            maximum_weight = NaN,
            normalized_entropy = NaN,
        ))
    end
    centered = logs .- maximum(logs)
    raw = exp.(centered)
    total = sum(raw)
    weights = raw ./ total
    ess = 1 / sum(abs2, weights)
    entropy = -sum(weight == 0 ? 0.0 : weight * log(weight) for weight in weights)
    return (weights = weights, summary = (;
        all_logweights_finite = true,
        logweight_range = maximum(logs) - minimum(logs),
        effective_sample_size = ess,
        effective_sample_size_rate = ess / length(weights),
        maximum_weight = maximum(weights),
        normalized_entropy = entropy / log(length(weights)),
    ))
end

function weighted_mean_columns(matrix::AbstractMatrix{<:Real},
        weights::AbstractVector{<:Real})
    return [sum(weights[row] * Float64(matrix[row, col]) for row in axes(matrix, 1))
        for col in axes(matrix, 2)]
end

function direct_parameter_shift_rows(fit, weighted_direct_mean, baseline_direct_mean)
    shifts = weighted_direct_mean .- baseline_direct_mean
    return [(;
        parameter = fit.design.parameter_names[index],
        parameter_index = index,
        block = FITGRID.parameter_block(fit.design, index),
        baseline_mean = baseline_direct_mean[index],
        weighted_mean = weighted_direct_mean[index],
        shift = shifts[index],
        absolute_shift = abs(shifts[index]),
        finite = isfinite(shifts[index]),
    ) for index in eachindex(shifts)]
end

function direct_block_shift_rows(parameter_rows)
    blocks = sort(unique(row.block for row in parameter_rows); by = string)
    rows = NamedTuple[]
    for block in blocks
        rows_for_block = [row for row in parameter_rows if row.block === block]
        abs_shifts = [row.absolute_shift for row in rows_for_block]
        push!(rows, (;
            block,
            n_parameters = length(rows_for_block),
            mean_absolute_shift = sum(abs_shifts) / length(abs_shifts),
            max_absolute_shift = maximum(abs_shifts),
            all_finite = all(row -> row.finite, rows_for_block),
        ))
    end
    return rows
end

function mean_abs_shift(weighted_values, baseline_values)
    shifts = Float64.(weighted_values) .- Float64.(baseline_values)
    return sum(abs, shifts) / length(shifts)
end

function max_abs_shift(weighted_values, baseline_values)
    shifts = Float64.(weighted_values) .- Float64.(baseline_values)
    return maximum(abs, shifts)
end

function logprior_vector(target, draws)
    return [BayesianMGMFRM._source_fixture_logprior(target, collect(@view draws[row, :]))
        for row in axes(draws, 1)]
end

function scenario_record(spec)
    simulated = SPATH.SPARSE.table_for_scenario(spec)
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
    baseline_direct_mean = vec(sum(fit.direct_draws; dims = 1) ./ size(fit.direct_draws, 1))
    expected_scores = BayesianMGMFRM.expected_scores(fit; draw_indices)
    baseline_expected_mean = vec(sum(expected_scores; dims = 1) ./ size(expected_scores, 1))
    probabilities = BayesianMGMFRM.predictive_probabilities(fit; draw_indices)
    top_category_probabilities = probabilities[:, :, end]
    baseline_top_category_mean =
        vec(sum(top_category_probabilities; dims = 1) ./ size(top_category_probabilities, 1))
    baseline_prior = fit.prior
    baseline_target =
        BayesianMGMFRM._gmfrm_promotion_candidate_logdensity(gmfrm_spec; prior = baseline_prior)
    baseline_logprior = logprior_vector(baseline_target, fit.draws)
    loglikelihood = Float64.(fit.direct_loglikelihood)
    decomposition_error =
        maximum(abs.(Float64.(fit.log_posterior) .- (loglikelihood .+ baseline_logprior)))

    cells = NamedTuple[]
    for profile in PRIOR_PROFILES
        prior = source_prior(profile)
        target = BayesianMGMFRM._gmfrm_promotion_candidate_logdensity(gmfrm_spec; prior)
        profile_logprior = logprior_vector(target, fit.draws)
        for power in LIKELIHOOD_POWERS
            logweights =
                (Float64(power) - 1.0) .* loglikelihood .+
                profile_logprior .- baseline_logprior
            weight_result = normalized_weight_summary(logweights)
            weights = weight_result.weights
            weighted_direct_mean = weighted_mean_columns(fit.direct_draws, weights)
            parameter_rows =
                direct_parameter_shift_rows(fit, weighted_direct_mean, baseline_direct_mean)
            block_rows = direct_block_shift_rows(parameter_rows)
            weighted_expected_mean = weighted_mean_columns(expected_scores, weights)
            weighted_top_category_mean =
                weighted_mean_columns(top_category_probabilities, weights)
            weighted_loglikelihood_mean =
                sum(weights[index] * loglikelihood[index] for index in eachindex(weights))
            baseline_loglikelihood_mean = sum(loglikelihood) / length(loglikelihood)
            push!(cells, (;
                prior_profile = profile.name,
                prior = source_prior_record(prior),
                likelihood_power = Float64(power),
                n_draws = length(weights),
                weight_review = weight_result.summary,
                logprior_review = (;
                    baseline = finite_vector_summary(baseline_logprior),
                    sensitivity = finite_vector_summary(profile_logprior),
                    delta = finite_vector_summary(profile_logprior .- baseline_logprior),
                ),
                loglikelihood_review = (;
                    baseline_mean = baseline_loglikelihood_mean,
                    weighted_mean = weighted_loglikelihood_mean,
                    shift = weighted_loglikelihood_mean - baseline_loglikelihood_mean,
                    absolute_shift =
                        abs(weighted_loglikelihood_mean - baseline_loglikelihood_mean),
                ),
                direct_parameter_shift_rows = parameter_rows,
                direct_block_shift_rows = block_rows,
                predictive_shift_review = (;
                    expected_score_max_absolute_shift =
                        max_abs_shift(weighted_expected_mean, baseline_expected_mean),
                    expected_score_mean_absolute_shift =
                        mean_abs_shift(weighted_expected_mean, baseline_expected_mean),
                    top_category_probability_max_absolute_shift =
                        max_abs_shift(weighted_top_category_mean,
                            baseline_top_category_mean),
                    top_category_probability_mean_absolute_shift =
                        mean_abs_shift(weighted_top_category_mean,
                            baseline_top_category_mean),
                ),
                summary = (;
                    all_logweights_finite =
                        weight_result.summary.all_logweights_finite,
                    weight_ess_rate =
                        weight_result.summary.effective_sample_size_rate,
                    max_direct_parameter_mean_shift =
                        maximum(row.absolute_shift for row in parameter_rows),
                    max_direct_block_mean_shift =
                        maximum(row.mean_absolute_shift for row in block_rows),
                    max_expected_score_shift =
                        max_abs_shift(weighted_expected_mean, baseline_expected_mean),
                    max_top_category_probability_shift =
                        max_abs_shift(weighted_top_category_mean,
                            baseline_top_category_mean),
                    loglikelihood_mean_absolute_shift =
                        abs(weighted_loglikelihood_mean - baseline_loglikelihood_mean),
                ),
            ))
        end
    end

    baseline_cell = only(cell for cell in cells
        if cell.prior_profile === :baseline_raw_prior &&
            cell.likelihood_power == 1.0)
    baseline_identity =
        baseline_cell.summary.max_direct_parameter_mean_shift <= 1e-10 &&
        baseline_cell.summary.max_expected_score_shift <= 1e-10 &&
        baseline_cell.summary.max_top_category_probability_shift <= 1e-10
    all_cells_finite =
        all(cell -> cell.summary.all_logweights_finite, cells) &&
        all(cell -> all(row -> row.finite, cell.direct_parameter_shift_rows), cells)
    min_ess_rate = minimum(cell.summary.weight_ess_rate for cell in cells)
    max_direct_parameter_shift =
        maximum(cell.summary.max_direct_parameter_mean_shift for cell in cells)
    max_direct_block_shift =
        maximum(cell.summary.max_direct_block_mean_shift for cell in cells)
    max_expected_score_shift =
        maximum(cell.summary.max_expected_score_shift for cell in cells)
    max_top_category_probability_shift =
        maximum(cell.summary.max_top_category_probability_shift for cell in cells)
    max_loglikelihood_shift =
        maximum(cell.summary.loglikelihood_mean_absolute_shift for cell in cells)
    passed = fit isa BayesianMGMFRM.GMFRMFit &&
        all_cells_finite &&
        baseline_identity &&
        min_ess_rate >= PROTOCOL.thresholds.require_weight_ess_rate_minimum &&
        max_direct_parameter_shift <=
            PROTOCOL.thresholds.max_direct_parameter_mean_shift &&
        max_direct_block_shift <=
            PROTOCOL.thresholds.max_direct_block_mean_shift &&
        max_expected_score_shift <= PROTOCOL.thresholds.max_expected_score_shift &&
        max_top_category_probability_shift <=
            PROTOCOL.thresholds.max_top_category_probability_shift &&
        max_loglikelihood_shift <= PROTOCOL.thresholds.max_loglikelihood_mean_shift &&
        decomposition_error <=
            PROTOCOL.thresholds.max_logposterior_decomposition_error

    return (;
        scenario = spec.scenario,
        sparse_pattern = spec.sparse_pattern,
        fit_seed = spec.fit_seed,
        n_observations = data.n,
        fit_record = (;
            type = String(nameof(typeof(fit))),
            raw_draws_shape = collect(size(fit.draws)),
            direct_draws_shape = collect(size(fit.direct_draws)),
            pointwise_loglikelihood_shape = collect(size(fit.direct_pointwise_loglikelihood)),
        ),
        baseline_prior = source_prior_record(baseline_prior),
        baseline_logposterior_decomposition = (;
            maximum_absolute_error = decomposition_error,
            passed =
                decomposition_error <=
                PROTOCOL.thresholds.max_logposterior_decomposition_error,
        ),
        sensitivity_cells = cells,
        summary = (;
            passed,
            n_sensitivity_cells = length(cells),
            n_prior_profiles = length(PRIOR_PROFILES),
            n_likelihood_powers = length(LIKELIHOOD_POWERS),
            all_cells_finite,
            baseline_identity,
            min_weight_ess_rate = min_ess_rate,
            max_weight =
                maximum(cell.weight_review.maximum_weight for cell in cells),
            max_direct_parameter_mean_shift = max_direct_parameter_shift,
            max_direct_block_mean_shift = max_direct_block_shift,
            max_expected_score_shift,
            max_top_category_probability_shift,
            max_loglikelihood_mean_shift = max_loglikelihood_shift,
            max_logposterior_decomposition_error = decomposition_error,
        ),
    )
end

function grid_artifact()
    scenarios = [scenario_record(spec) for spec in SCENARIOS]
    passed = all(scenario -> scenario.summary.passed, scenarios)
    return (;
        schema = "bayesianmgmfrm.gmfrm_prior_likelihood_sensitivity_grid.v1",
        family = :gmfrm,
        scope = :scalar_gmfrm_fit_ready_candidate,
        status = :guarded_experimental_prior_likelihood_sensitivity_grid_recorded,
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
            fixture_reference(
                "test/fixtures/gmfrm_sparse_pathology_recovery_grid.json"),
            fixture_reference(
                "test/fixtures/gmfrm_guarded_exposure_review.json";
                hash_policy = :existence_only_avoids_cyclic_review_hash),
        ],
        scenarios,
        decision_record = (;
            public_fit_allowed = true,
            experimental_keyword_enabled = true,
            public_exposure_support =
                :satisfied_for_scalar_gmfrm_real_data_case_study_followup,
            interpretation =
                :guarded_scalar_gmfrm_prior_likelihood_sensitivity_grid_passed,
            required_followup = :scalar_gmfrm_real_data_case_study,
        ),
        summary = (;
            passed,
            publication_or_registration_action = false,
            n_scenarios = length(scenarios),
            n_passed_scenarios = count(scenario -> scenario.summary.passed, scenarios),
            n_sensitivity_cells =
                sum(scenario.summary.n_sensitivity_cells for scenario in scenarios),
            n_prior_profiles = length(PRIOR_PROFILES),
            n_likelihood_powers = length(LIKELIHOOD_POWERS),
            all_cells_finite =
                all(scenario -> scenario.summary.all_cells_finite, scenarios),
            all_baseline_identity =
                all(scenario -> scenario.summary.baseline_identity, scenarios),
            min_weight_ess_rate =
                minimum(scenario.summary.min_weight_ess_rate for scenario in scenarios),
            max_weight =
                maximum(scenario.summary.max_weight for scenario in scenarios),
            max_direct_parameter_mean_shift =
                maximum(scenario.summary.max_direct_parameter_mean_shift
                    for scenario in scenarios),
            max_direct_block_mean_shift =
                maximum(scenario.summary.max_direct_block_mean_shift
                    for scenario in scenarios),
            max_expected_score_shift =
                maximum(scenario.summary.max_expected_score_shift
                    for scenario in scenarios),
            max_top_category_probability_shift =
                maximum(scenario.summary.max_top_category_probability_shift
                    for scenario in scenarios),
            max_loglikelihood_mean_shift =
                maximum(scenario.summary.max_loglikelihood_mean_shift
                    for scenario in scenarios),
            max_logposterior_decomposition_error =
                maximum(scenario.summary.max_logposterior_decomposition_error
                    for scenario in scenarios),
            remaining_public_blockers = [
                :scalar_gmfrm_real_data_case_study_missing,
            ],
            recommendation =
                :keep_guarded_experimental_until_real_data_case_study,
            next_gate = :scalar_gmfrm_real_data_case_study,
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
        " min_ess_rate=", artifact.summary.min_weight_ess_rate,
        " next_gate=", artifact.summary.next_gate)
    return nothing
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    main(ARGS)
end
