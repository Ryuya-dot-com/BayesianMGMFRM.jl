#!/usr/bin/env julia

using Dates
using SHA
using Statistics
using TOML

import BayesianMGMFRM

module QMisspec
include(joinpath(@__DIR__,
    "generate_mgmfrm_uto_style_q_misspecification_mcmc_simulations.jl"))
end

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_PREVIOUS_JSON =
    joinpath(ROOT, "artifacts", "uto_style_q_misspecification_mcmc_simulations",
        "uto_style_q_misspecification_mcmc_simulations.json")
const DEFAULT_OUTPUT_JSON =
    joinpath(ROOT, "artifacts",
        "uto_style_replicated_q_misspecification_category_bridge",
        "uto_style_replicated_q_misspecification_category_bridge.json")
const DEFAULT_OUTPUT_MD =
    joinpath(ROOT, "artifacts",
        "uto_style_replicated_q_misspecification_category_bridge",
        "uto_style_replicated_q_misspecification_category_bridge.md")

include(joinpath(@__DIR__, "local_json.jl"))

const OUTPUT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_uto_style_replicated_q_misspecification_category_bridge.v1"
const CATEGORY_LEVELS = QMisspec.CATEGORY_LEVELS
const DEFAULT_THRESHOLDS = QMisspec.DEFAULT_THRESHOLDS
const DEFAULT_SEEDS = [20260707, 20260717]
const MCMC_MODEL_NAMES = (
    :declared_q_mgmfrm_mcmc,
    :candidate_q_mgmfrm_mcmc,
    :rotated_wrong_q_mgmfrm_mcmc,
    :scalar_gmfrm_mcmc,
)

function usage()
    return """
    Replicate the Uto-style Q-misspecification MCMC checks and add category
    calibration diagnostics.

    This local diagnostic reruns the explicit-null, false-add, false-drop,
    weak-dimension, and rater-noise/Q-misspecification proxy scenarios across
    multiple seeds. It scores each heldout category probability surface with
    log score, Brier score, category-distribution total variation, and
    cumulative-threshold L1. Public fit-threshold, model-weight, and Q-revision
    claims remain blocked.

    Usage:
      julia --project=. scripts/generate_mgmfrm_uto_style_replicated_q_misspecification_category_bridge.jl [options]

    Options:
      --output-json PATH       JSON artifact path.
      --output-md PATH         Markdown report path.
      --previous-json PATH     Earlier Q-misspecification MCMC artifact path.
      --scenarios LIST         Comma-separated scenario names.
      --seeds LIST             Comma-separated base seeds. Default: 20260707,20260717.
      --thresholds LIST        Comma-separated dLogScore thresholds. Default: 0,2,4,8.
      --n-persons N            Number of persons. Default: 6.
      --n-raters N             Number of raters. Default: 3.
      --heldout-fraction X     Observation holdout fraction. Default: 0.17.
      --chains N               MCMC chains. Default: 2.
      --warmup-per-chain N     Warmup iterations per chain. Default: 16.
      --draws-per-chain N      Posterior draws per chain. Default: 16.
      --target-acceptance X    NUTS target acceptance. Default: 0.8.
      --prior-profile NAME     Internal source prior profile: default, tight, or diffuse.
                               Default: default.
      --progress               Show sampler progress.
    """
end

function parse_symbol_list(text::AbstractString)
    values = Symbol[]
    for part in split(text, ",")
        stripped = strip(part)
        isempty(stripped) && continue
        push!(values, Symbol(stripped))
    end
    isempty(values) && error("list must contain at least one value")
    length(unique(values)) == length(values) || error("list values must be unique")
    return values
end

function parse_seed_list(text::AbstractString)
    values = Int[]
    for part in split(text, ",")
        stripped = strip(part)
        isempty(stripped) && continue
        push!(values, parse(Int, stripped))
    end
    isempty(values) && error("--seeds must contain at least one value")
    length(unique(values)) == length(values) || error("--seeds must be unique")
    return values
end

function parse_thresholds(text::AbstractString)
    values = Float64[]
    for part in split(text, ",")
        stripped = strip(part)
        isempty(stripped) && continue
        push!(values, parse(Float64, stripped))
    end
    isempty(values) && error("--thresholds must contain at least one value")
    all(>=(0), values) || error("--thresholds must be non-negative")
    length(unique(values)) == length(values) ||
        error("--thresholds must be unique")
    return sort(values)
end

function scenario_by_name(name::Symbol)
    matches = [scenario for scenario in QMisspec.SCENARIO_LIBRARY
        if scenario.name === name]
    isempty(matches) && error("unknown scenario: $name")
    return only(matches)
end

function parse_args(args)
    output_json = DEFAULT_OUTPUT_JSON
    output_md = DEFAULT_OUTPUT_MD
    previous_json = DEFAULT_PREVIOUS_JSON
    scenario_names = [scenario.name for scenario in QMisspec.SCENARIO_LIBRARY]
    seeds = copy(DEFAULT_SEEDS)
    thresholds = copy(DEFAULT_THRESHOLDS)
    n_persons = 6
    n_raters = 3
    heldout_fraction = 0.17
    chains = 2
    warmup_per_chain = 16
    draws_per_chain = 16
    target_acceptance = 0.8
    prior_profile = :default
    progress = false

    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--output-json"
            index < length(args) || error("--output-json requires a path")
            output_json = abspath(args[index + 1])
            index += 2
        elseif arg == "--output-md"
            index < length(args) || error("--output-md requires a path")
            output_md = abspath(args[index + 1])
            index += 2
        elseif arg == "--previous-json"
            index < length(args) || error("--previous-json requires a path")
            previous_json = abspath(args[index + 1])
            index += 2
        elseif arg == "--scenarios"
            index < length(args) || error("--scenarios requires a comma list")
            scenario_names = parse_symbol_list(args[index + 1])
            index += 2
        elseif arg == "--seeds"
            index < length(args) || error("--seeds requires a comma list")
            seeds = parse_seed_list(args[index + 1])
            index += 2
        elseif arg == "--thresholds"
            index < length(args) || error("--thresholds requires a comma list")
            thresholds = parse_thresholds(args[index + 1])
            index += 2
        elseif arg == "--n-persons"
            index < length(args) || error("--n-persons requires an integer")
            n_persons = parse(Int, args[index + 1])
            index += 2
        elseif arg == "--n-raters"
            index < length(args) || error("--n-raters requires an integer")
            n_raters = parse(Int, args[index + 1])
            index += 2
        elseif arg == "--heldout-fraction"
            index < length(args) ||
                error("--heldout-fraction requires a number")
            heldout_fraction = parse(Float64, args[index + 1])
            index += 2
        elseif arg == "--chains"
            index < length(args) || error("--chains requires an integer")
            chains = parse(Int, args[index + 1])
            index += 2
        elseif arg == "--warmup-per-chain"
            index < length(args) ||
                error("--warmup-per-chain requires an integer")
            warmup_per_chain = parse(Int, args[index + 1])
            index += 2
        elseif arg == "--draws-per-chain"
            index < length(args) ||
                error("--draws-per-chain requires an integer")
            draws_per_chain = parse(Int, args[index + 1])
            index += 2
        elseif arg == "--target-acceptance"
            index < length(args) ||
                error("--target-acceptance requires a number")
            target_acceptance = parse(Float64, args[index + 1])
            index += 2
        elseif arg == "--prior-profile"
            index < length(args) || error("--prior-profile requires a name")
            prior_profile = Symbol(args[index + 1])
            index += 2
        elseif arg == "--progress"
            progress = true
            index += 1
        elseif arg in ("-h", "--help")
            println(usage())
            exit(0)
        else
            error("unknown argument: $arg")
        end
    end

    n_persons >= 6 || error("--n-persons must be at least 6")
    n_raters >= 3 || error("--n-raters must be at least 3")
    0 < heldout_fraction < 0.5 ||
        error("--heldout-fraction must be in (0, 0.5)")
    chains >= 1 || error("--chains must be positive")
    warmup_per_chain >= 0 || error("--warmup-per-chain must be non-negative")
    draws_per_chain >= 1 || error("--draws-per-chain must be positive")
    0 < target_acceptance < 1 ||
        error("--target-acceptance must be in (0, 1)")
    prior_profile in (:default, :tight, :diffuse) ||
        error("--prior-profile must be default, tight, or diffuse")
    scenarios = [scenario_by_name(name) for name in scenario_names]
    return (;
        output_json,
        output_md,
        previous_json,
        scenarios,
        seeds,
        thresholds,
        n_persons,
        n_items = size(QMisspec.Q_BASE, 1),
        n_raters,
        heldout_fraction,
        chains,
        warmup_per_chain,
        draws_per_chain,
        target_acceptance,
        prior_profile,
        progress,
    )
end

project_version() =
    String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])
file_sha256(path::AbstractString) = bytes2hex(open(sha256, path))
rel(path::AbstractString) = relpath(path, ROOT)
round3(value) = round(Float64(value); digits = 3)
round4(value) = round(Float64(value); digits = 4)

function direct_probability_array(design, direct_draws::AbstractMatrix)
    n_draws = size(direct_draws, 1)
    n_observations = design.spec.data.n
    n_categories = length(CATEGORY_LEVELS)
    out = zeros(Float64, n_draws, n_observations, n_categories)
    fixture_values = design.spec.family === :gmfrm ?
        BayesianMGMFRM._gmfrm_source_fixture_values :
        BayesianMGMFRM._mgmfrm_source_fixture_values
    for draw in axes(direct_draws, 1)
        values = fixture_values(design, vec(direct_draws[draw, :]))
        for row in values
            out[draw, Int(row.row), Int(row.category_index)] =
                exp(Float64(row.log_probability))
        end
    end
    return out
end

function probability_means(probabilities::Array{Float64,3}, heldout_indices)
    heldout = probabilities[:, heldout_indices, :]
    out = zeros(Float64, length(heldout_indices), size(probabilities, 3))
    for observation in eachindex(heldout_indices), category in axes(out, 2)
        out[observation, category] =
            mean(@view heldout[:, observation, category])
    end
    return out
end

function direct_probability_means(design, direct_draws, heldout_indices)
    return probability_means(direct_probability_array(design, direct_draws),
        heldout_indices)
end

observed_scores(full_rows, heldout_indices) =
    [full_rows[index].score for index in heldout_indices]

function score_index(score::Integer)
    index = findfirst(==(score), CATEGORY_LEVELS)
    index === nothing && error("unknown category score: $score")
    return index
end

function repeated_probability_means(probabilities::AbstractVector{<:Real},
        n_observations::Int)
    out = zeros(Float64, n_observations, length(probabilities))
    for row in 1:n_observations
        out[row, :] .= probabilities
    end
    return out
end

function reference_probability_means(model::Symbol, train_rows, full_rows,
        heldout_indices)
    global_probs = QMisspec.SmallMCMC.smoothed_probs(train_rows)
    model === :null_or_intercept_reference &&
        return repeated_probability_means(global_probs, length(heldout_indices))
    item_rater = QMisspec.SmallMCMC.grouped_smoothed_probs(
        train_rows,
        row -> (row.item, row.rater),
    )
    output = zeros(Float64, length(heldout_indices), length(CATEGORY_LEVELS))
    for (heldout_row, observation) in pairs(heldout_indices)
        row = full_rows[observation]
        output[heldout_row, :] .=
            get(item_rater, (row.item, row.rater), global_probs)
    end
    return output
end

function oracle_probability_means(full_rows, generated, scenario, heldout_indices)
    generated.truth_available || return nothing
    model_spec = (model = :truth_q_source_oracle, family = :mgmfrm,
        q_field = :declared_q)
    truth_scenario = merge(scenario, (; declared_q = scenario.true_q))
    full = QMisspec.design_for_rows(full_rows, model_spec, truth_scenario)
    direct = QMisspec.truth_direct_params(full.design, generated.truth)
    return direct_probability_means(full.design, reshape(direct, 1, :),
        heldout_indices)
end

function fit_model_probability_means(model_spec, scenario, train_rows, full_rows,
        heldout_indices, options)
    started = time_ns()
    train = QMisspec.design_for_rows(train_rows, model_spec, scenario)
    full = QMisspec.design_for_rows(full_rows, model_spec, scenario)
    layout_matches = train.design.parameter_names == full.design.parameter_names
    fit = BayesianMGMFRM.fit(train.spec;
        experimental = true,
        prior = QMisspec.SmallMCMC.source_prior(options.prior_profile),
        backend = :advancedhmc,
        ndraws = options.draws_per_chain,
        warmup = options.warmup_per_chain,
        chains = options.chains,
        seed = options.seed + scenario.seed_offset +
               QMisspec.model_seed_offset(model_spec.model),
        target_accept = options.target_acceptance,
        progress = options.progress,
    )
    elapsed_seconds = (time_ns() - started) / 1e9
    summary = fit.diagnostic_surface.summary
    probabilities = direct_probability_means(full.design, fit.direct_draws,
        heldout_indices)
    metadata = (;
        model = model_spec.model,
        model_family = fit.design.spec.family,
        fit_succeeded = true,
        scoring_succeeded = true,
        returned_type = Symbol(nameof(typeof(fit))),
        layout_matches,
        n_train_observations = length(train_rows),
        n_heldout_observations = length(heldout_indices),
        n_raw_parameters = size(fit.draws, 2),
        n_direct_parameters = size(fit.direct_draws, 2),
        n_draws = size(fit.direct_draws, 1),
        chains = options.chains,
        warmup_per_chain = options.warmup_per_chain,
        draws_per_chain = options.draws_per_chain,
        sampler = fit.sampler,
        backend = fit.backend,
        sampler_flag = summary.flag,
        n_sampler_warnings = Int(summary.n_sampler_warnings),
        n_nonfinite_logdensity = Int(summary.n_nonfinite_logdensity),
        n_failed_direct_constraints =
            Int(summary.n_failed_direct_constraints),
        elapsed_seconds = round3(elapsed_seconds),
    )
    return (; model = model_spec.model, probabilities, metadata)
end

function failed_probability_set(model_spec, err, options, train_rows,
        heldout_indices)
    metadata = (;
        model = model_spec.model,
        model_family = model_spec.family,
        fit_succeeded = false,
        scoring_succeeded = false,
        returned_type = missing,
        layout_matches = false,
        n_train_observations = length(train_rows),
        n_heldout_observations = length(heldout_indices),
        n_raw_parameters = missing,
        n_direct_parameters = missing,
        n_draws = 0,
        chains = options.chains,
        warmup_per_chain = options.warmup_per_chain,
        draws_per_chain = options.draws_per_chain,
        sampler = :nuts,
        backend = :advancedhmc,
        sampler_flag = :fit_failed,
        n_sampler_warnings = missing,
        n_nonfinite_logdensity = missing,
        n_failed_direct_constraints = missing,
        elapsed_seconds = missing,
        error = sprint(showerror, err),
    )
    return (; model = model_spec.model, probabilities = nothing, metadata)
end

function oracle_probability_set(full_rows, generated, scenario, heldout_indices)
    probabilities = oracle_probability_means(full_rows, generated, scenario,
        heldout_indices)
    probabilities === nothing && return nothing
    metadata = (;
        model = :truth_q_source_oracle,
        model_family = :mgmfrm,
        fit_succeeded = true,
        scoring_succeeded = true,
        returned_type = :known_truth_source_oracle,
        layout_matches = true,
        n_train_observations = missing,
        n_heldout_observations = length(heldout_indices),
        n_raw_parameters = 0,
        n_direct_parameters = missing,
        n_draws = 1,
        chains = 0,
        warmup_per_chain = 0,
        draws_per_chain = 0,
        sampler = :known_truth,
        backend = :source_fixture,
        sampler_flag = :not_applicable,
        n_sampler_warnings = 0,
        n_nonfinite_logdensity = 0,
        n_failed_direct_constraints = 0,
        elapsed_seconds = 0.0,
    )
    return (; model = :truth_q_source_oracle, probabilities, metadata)
end

function reference_probability_set(model::Symbol, train_rows, full_rows,
        heldout_indices)
    probabilities = reference_probability_means(model, train_rows, full_rows,
        heldout_indices)
    metadata = (;
        model,
        model_family = :empirical_reference,
        fit_succeeded = true,
        scoring_succeeded = true,
        returned_type = :smoothed_reference_probabilities,
        layout_matches = true,
        n_train_observations = length(train_rows),
        n_heldout_observations = length(heldout_indices),
        n_raw_parameters = 0,
        n_direct_parameters = 0,
        n_draws = 0,
        chains = 0,
        warmup_per_chain = 0,
        draws_per_chain = 0,
        sampler = :empirical_smoothing,
        backend = :reference,
        sampler_flag = :not_applicable,
        n_sampler_warnings = 0,
        n_nonfinite_logdensity = 0,
        n_failed_direct_constraints = 0,
        elapsed_seconds = 0.0,
    )
    return (; model, probabilities, metadata)
end

function model_probability_sets(train_rows, full_rows, heldout_indices,
        generated, scenario, options)
    sets = NamedTuple[]
    oracle = oracle_probability_set(full_rows, generated, scenario,
        heldout_indices)
    oracle === nothing || push!(sets, oracle)
    for spec in QMisspec.MCMC_MODEL_SPECS
        try
            push!(sets, fit_model_probability_means(spec, scenario, train_rows,
                full_rows, heldout_indices, options))
        catch err
            push!(sets, failed_probability_set(spec, err, options, train_rows,
                heldout_indices))
        end
    end
    for model in (:item_rater_reference, :null_or_intercept_reference)
        push!(sets, reference_probability_set(model, train_rows, full_rows,
            heldout_indices))
    end
    return sets
end

function log_score(probabilities::AbstractMatrix, scores)
    total = 0.0
    for row in eachindex(scores)
        probability = probabilities[row, score_index(scores[row])]
        total += log(max(probability, eps(Float64)))
    end
    return total
end

function multiclass_brier(probabilities::AbstractMatrix, scores)
    total = 0.0
    for row in eachindex(scores), category in eachindex(CATEGORY_LEVELS)
        observed = CATEGORY_LEVELS[category] == scores[row] ? 1.0 : 0.0
        total += (probabilities[row, category] - observed)^2
    end
    return total / length(scores)
end

function expected_score_mae(probabilities::AbstractMatrix, scores)
    expected = [sum(Float64(CATEGORY_LEVELS[category]) *
                    probabilities[row, category]
                    for category in eachindex(CATEGORY_LEVELS))
        for row in axes(probabilities, 1)]
    return mean(abs.(Float64.(scores) .- expected))
end

function category_distribution_rows(context, model::Symbol,
        probabilities::AbstractMatrix, scores)
    n = length(scores)
    rows = NamedTuple[]
    for category in eachindex(CATEGORY_LEVELS)
        observed_share =
            count(==(CATEGORY_LEVELS[category]), scores) / n
        predicted_share = mean(@view probabilities[:, category])
        push!(rows, (;
            context...,
            model,
            category = CATEGORY_LEVELS[category],
            observed_count =
                count(==(CATEGORY_LEVELS[category]), scores),
            observed_share = round4(observed_share),
            predicted_share = round4(predicted_share),
            share_gap = round4(predicted_share - observed_share),
            abs_share_gap = round4(abs(predicted_share - observed_share)),
            public_claim_allowed = false,
        ))
    end
    return rows
end

function cumulative_threshold_rows(context, model::Symbol,
        probabilities::AbstractMatrix, scores)
    rows = NamedTuple[]
    for threshold_index in 2:length(CATEGORY_LEVELS)
        threshold = CATEGORY_LEVELS[threshold_index]
        observed_share = count(score -> score >= threshold, scores) /
                         length(scores)
        predicted_share = mean(sum(probabilities[row, threshold_index:end])
            for row in axes(probabilities, 1))
        push!(rows, (;
            context...,
            model,
            threshold = Symbol("score_ge_", threshold),
            threshold_score = threshold,
            observed_share = round4(observed_share),
            predicted_share = round4(predicted_share),
            share_gap = round4(predicted_share - observed_share),
            abs_share_gap = round4(abs(predicted_share - observed_share)),
            public_claim_allowed = false,
        ))
    end
    return rows
end

function failed_model_summary_row(context, metadata, scores)
    return merge(context, metadata, (;
        rank = missing,
        heldout_log_score = NaN,
        mean_log_score = NaN,
        multiclass_brier = NaN,
        expected_score_mae = NaN,
        category_total_variation = NaN,
        max_abs_category_gap = NaN,
        cumulative_l1 = NaN,
        n_categories_used =
            count(category -> any(==(category), scores), CATEGORY_LEVELS),
        min_observed_category_count =
            minimum(count(==(category), scores) for category in CATEGORY_LEVELS),
        min_observed_category_share =
            round4(minimum(count(==(category), scores)
                for category in CATEGORY_LEVELS) / length(scores)),
        public_claim_allowed = false,
    ))
end

function model_summary_row(context, model::Symbol,
        probabilities::AbstractMatrix, scores, metadata)
    category_rows = category_distribution_rows(context, model, probabilities,
        scores)
    cumulative_rows = cumulative_threshold_rows(context, model, probabilities,
        scores)
    min_count = minimum(count(==(category), scores)
        for category in CATEGORY_LEVELS)
    return merge(context, metadata, (;
        rank = missing,
        heldout_log_score = round3(log_score(probabilities, scores)),
        mean_log_score = round3(log_score(probabilities, scores) /
                                length(scores)),
        multiclass_brier = round4(multiclass_brier(probabilities, scores)),
        expected_score_mae = round4(expected_score_mae(probabilities, scores)),
        category_total_variation =
            round4(0.5 * sum(row.abs_share_gap for row in category_rows)),
        max_abs_category_gap =
            round4(maximum(row.abs_share_gap for row in category_rows)),
        cumulative_l1 =
            round4(sum(row.abs_share_gap for row in cumulative_rows)),
        n_categories_used =
            count(category -> any(==(category), scores), CATEGORY_LEVELS),
        min_observed_category_count = min_count,
        min_observed_category_share = round4(min_count / length(scores)),
        public_claim_allowed = false,
    ))
end

function ranked_summary_rows(rows)
    finite = [row for row in rows if isfinite(Float64(row.heldout_log_score))]
    ranked = sort(finite; by = row -> Float64(row.heldout_log_score),
        rev = true)
    rank_by_model = Dict(row.model => index for (index, row) in pairs(ranked))
    return [merge(row, (; rank = get(rank_by_model, row.model, missing)))
        for row in rows]
end

function row_by_model(rows, model::Symbol)
    matches = [row for row in rows if row.model === model]
    isempty(matches) && return nothing
    return only(matches)
end

function comparison_rows(rows)
    null = row_by_model(rows, :null_or_intercept_reference)
    output = NamedTuple[]
    null === nothing && return output
    isfinite(Float64(null.heldout_log_score)) || return output
    for row in rows
        row.model === :null_or_intercept_reference && continue
        isfinite(Float64(row.heldout_log_score)) || continue
        delta_brier = row.multiclass_brier - null.multiclass_brier
        delta_tv = row.category_total_variation - null.category_total_variation
        delta_cumulative = row.cumulative_l1 - null.cumulative_l1
        push!(output, (;
            comparison = Symbol(string(row.model, "_minus_null")),
            model = row.model,
            baseline = :null_or_intercept_reference,
            delta_log_score =
                round3(row.heldout_log_score - null.heldout_log_score),
            delta_brier = round4(delta_brier),
            delta_expected_score_mae =
                round4(row.expected_score_mae - null.expected_score_mae),
            delta_category_total_variation = round4(delta_tv),
            delta_cumulative_l1 = round4(delta_cumulative),
            category_calibration_aligned =
                delta_brier <= 0 &&
                delta_tv <= 0 &&
                delta_cumulative <= 0,
            public_claim_allowed = false,
        ))
    end
    return output
end

function comparison_metric(rows, model::Symbol, field::Symbol)
    matches = [row for row in rows if row.model === model]
    isempty(matches) && return NaN
    return Float64(getproperty(only(matches), field))
end

function model_metric_delta(rows, lhs::Symbol, rhs::Symbol, field::Symbol)
    lhs_row = row_by_model(rows, lhs)
    rhs_row = row_by_model(rows, rhs)
    lhs_row === nothing && return NaN
    rhs_row === nothing && return NaN
    lhs_value = Float64(getproperty(lhs_row, field))
    rhs_value = Float64(getproperty(rhs_row, field))
    isfinite(lhs_value) || return NaN
    isfinite(rhs_value) || return NaN
    return lhs_value - rhs_value
end

function calibration_aligned(rows, model::Symbol)
    brier = comparison_metric(rows, model, :delta_brier)
    tv = comparison_metric(rows, model, :delta_category_total_variation)
    cumulative = comparison_metric(rows, model, :delta_cumulative_l1)
    return isfinite(brier) && isfinite(tv) && isfinite(cumulative) &&
           brier <= 0 && tv <= 0 && cumulative <= 0
end

function scenario_cell_row(options, scenario, split, rows, comparisons)
    finite = [row for row in rows if isfinite(Float64(row.heldout_log_score))]
    leader = isempty(finite) ? nothing :
        first(sort(finite; by = row -> Float64(row.heldout_log_score),
            rev = true))
    candidate_dlog =
        comparison_metric(comparisons, :candidate_q_mgmfrm_mcmc,
            :delta_log_score)
    candidate_aligned = calibration_aligned(comparisons,
        :candidate_q_mgmfrm_mcmc)
    declared_aligned = calibration_aligned(comparisons,
        :declared_q_mgmfrm_mcmc)
    return (;
        seed = options.seed + scenario.seed_offset,
        base_seed = options.seed,
        prior_profile = options.prior_profile,
        scenario = scenario.name,
        axis = scenario.axis,
        role = scenario.role,
        expected = scenario.expected,
        generator = scenario.generator,
        n_train_observations = length(split.train_rows),
        n_heldout_observations = length(split.heldout_indices),
        split_attempts = split.split_attempts,
        observed_best_model = leader === nothing ? :missing : leader.model,
        declared_delta_log_score_vs_null =
            round3(comparison_metric(comparisons, :declared_q_mgmfrm_mcmc,
                :delta_log_score)),
        candidate_delta_log_score_vs_null = round3(candidate_dlog),
        rotated_wrong_delta_log_score_vs_null =
            round3(comparison_metric(comparisons,
                :rotated_wrong_q_mgmfrm_mcmc, :delta_log_score)),
        scalar_delta_log_score_vs_null =
            round3(comparison_metric(comparisons, :scalar_gmfrm_mcmc,
                :delta_log_score)),
        candidate_minus_declared_log_score =
            round3(model_metric_delta(rows, :candidate_q_mgmfrm_mcmc,
                :declared_q_mgmfrm_mcmc, :heldout_log_score)),
        candidate_minus_declared_brier =
            round4(model_metric_delta(rows, :candidate_q_mgmfrm_mcmc,
                :declared_q_mgmfrm_mcmc, :multiclass_brier)),
        candidate_minus_declared_category_total_variation =
            round4(model_metric_delta(rows, :candidate_q_mgmfrm_mcmc,
                :declared_q_mgmfrm_mcmc, :category_total_variation)),
        candidate_minus_declared_cumulative_l1 =
            round4(model_metric_delta(rows, :candidate_q_mgmfrm_mcmc,
                :declared_q_mgmfrm_mcmc, :cumulative_l1)),
        candidate_delta_brier_vs_null =
            round4(comparison_metric(comparisons, :candidate_q_mgmfrm_mcmc,
                :delta_brier)),
        candidate_delta_category_total_variation_vs_null =
            round4(comparison_metric(comparisons, :candidate_q_mgmfrm_mcmc,
                :delta_category_total_variation)),
        candidate_delta_cumulative_l1_vs_null =
            round4(comparison_metric(comparisons, :candidate_q_mgmfrm_mcmc,
                :delta_cumulative_l1)),
        declared_category_calibration_aligned_vs_null = declared_aligned,
        candidate_category_calibration_aligned_vs_null = candidate_aligned,
        candidate_predictive_category_caveat =
            isfinite(candidate_dlog) && candidate_dlog > 0 &&
            !candidate_aligned,
        public_claim_allowed = false,
    )
end

function risk_label(row, threshold)
    declared_pass = row.declared_delta_log_score_vs_null >= threshold
    candidate_pass = row.candidate_delta_log_score_vs_null >= threshold
    scalar_pass = row.scalar_delta_log_score_vs_null >= threshold
    candidate_aligned = row.candidate_category_calibration_aligned_vs_null
    declared_aligned = row.declared_category_calibration_aligned_vs_null
    if row.axis in (:explicit_null, :false_add, :q_misspecification_rater_noise)
        candidate_pass && candidate_aligned &&
            return :candidate_false_promotion_risk
        candidate_pass && return :candidate_false_promotion_with_category_caveat
        declared_pass && declared_aligned &&
            return :declared_model_false_promotion_risk
        declared_pass && return :declared_model_false_promotion_with_category_caveat
        scalar_pass && return :scalar_reference_screening_pass
        return :specificity_not_failed
    elseif row.axis === :false_drop
        candidate_pass || return :candidate_false_negative_risk
        candidate_aligned ||
            return :candidate_power_with_category_caveat
        row.candidate_minus_declared_log_score <= 0 &&
            return :candidate_does_not_improve_over_declared
        return :candidate_power_observed
    elseif row.axis === :weak_dimension
        declared_pass || return :weak_dimension_false_negative_risk
        declared_aligned || return :weak_dimension_with_category_caveat
        return :weak_dimension_screening_pass
    end
    return :manual_review_required
end

function threshold_rows(cell_rows, thresholds)
    rows = NamedTuple[]
    for row in cell_rows, threshold in thresholds
        candidate_pass = row.candidate_delta_log_score_vs_null >= threshold
        declared_pass = row.declared_delta_log_score_vs_null >= threshold
        push!(rows, (;
            seed = row.seed,
            base_seed = row.base_seed,
            prior_profile = row.prior_profile,
            scenario = row.scenario,
            axis = row.axis,
            threshold = round3(threshold),
            declared_passed = declared_pass,
            candidate_passed = candidate_pass,
            rotated_wrong_passed =
                row.rotated_wrong_delta_log_score_vs_null >= threshold,
            scalar_passed = row.scalar_delta_log_score_vs_null >= threshold,
            declared_category_calibration_aligned =
                row.declared_category_calibration_aligned_vs_null,
            candidate_category_calibration_aligned =
                row.candidate_category_calibration_aligned_vs_null,
            candidate_predictive_category_caveat =
                candidate_pass &&
                !row.candidate_category_calibration_aligned_vs_null,
            candidate_minus_declared_log_score =
                row.candidate_minus_declared_log_score,
            candidate_delta_brier_vs_null =
                row.candidate_delta_brier_vs_null,
            candidate_delta_category_total_variation_vs_null =
                row.candidate_delta_category_total_variation_vs_null,
            candidate_delta_cumulative_l1_vs_null =
                row.candidate_delta_cumulative_l1_vs_null,
            risk_interpretation = risk_label(row, threshold),
            public_claim_allowed = false,
        ))
    end
    return rows
end

function threshold_summary_rows(thresholds)
    rows = NamedTuple[]
    for threshold in sort(unique(row.threshold for row in thresholds))
        group = [row for row in thresholds if row.threshold == threshold]
        n = length(group)
        false_promotion = count(row -> row.risk_interpretation in
            (:candidate_false_promotion_risk,
             :candidate_false_promotion_with_category_caveat), group)
        false_negative = count(row -> row.risk_interpretation in
            (:candidate_false_negative_risk,
             :weak_dimension_false_negative_risk), group)
        category_caveat =
            count(row -> row.candidate_predictive_category_caveat, group)
        push!(rows, (;
            threshold,
            n_cells = n,
            n_candidate_passed = count(row -> row.candidate_passed, group),
            n_candidate_false_promotion_risk = false_promotion,
            candidate_false_promotion_rate = round4(false_promotion / n),
            n_candidate_false_promotion_with_category_caveat =
                count(row -> row.risk_interpretation ===
                    :candidate_false_promotion_with_category_caveat, group),
            n_declared_false_promotion_risk =
                count(row -> row.risk_interpretation in
                    (:declared_model_false_promotion_risk,
                     :declared_model_false_promotion_with_category_caveat),
                    group),
            n_candidate_false_negative_risk = false_negative,
            candidate_false_negative_rate = round4(false_negative / n),
            n_candidate_power_observed =
                count(row -> row.risk_interpretation ===
                    :candidate_power_observed, group),
            n_candidate_predictive_category_caveat = category_caveat,
            candidate_predictive_category_caveat_rate =
                round4(category_caveat / n),
            public_claim_allowed = false,
        ))
    end
    return rows
end

function finite_mean(values)
    finite = [Float64(value) for value in values if isfinite(Float64(value))]
    isempty(finite) && return NaN
    return mean(finite)
end

function summary_for_threshold(rows, threshold)
    matches = [row for row in rows if row.threshold == threshold]
    isempty(matches) && return nothing
    return only(matches)
end

function finding_rows(cell_rows, threshold_summary, model_rows)
    threshold2 = summary_for_threshold(threshold_summary, 2.0)
    threshold4 = summary_for_threshold(threshold_summary, 4.0)
    false_add = [row for row in cell_rows if row.axis === :false_add]
    false_drop = [row for row in cell_rows if row.axis === :false_drop]
    caveat_cells =
        count(row -> row.candidate_predictive_category_caveat, cell_rows)
    mcmc_warning_rows = [row for row in model_rows
        if row.model in MCMC_MODEL_NAMES && row.sampler_flag !== :ok]
    return [
        (finding = :replicated_q_misspecification_category_bridge_recorded,
            severity = :info,
            evidence = string(length(cell_rows), " seed-scenario cell(s)"),
            implication =
                :threshold_policy_now_has_replicated_predictive_and_category_checks),
        (finding = :mcmc_budget_recheck,
            severity = isempty(mcmc_warning_rows) ? :info : :warning,
            evidence = string(length(mcmc_warning_rows),
                " MCMC model row(s) have non-ok sampler flags"),
            implication =
                :remaining_warnings_require_larger_publication_grade_budget),
        (finding = :threshold_2_specificity_recheck,
            severity = threshold2 === nothing ? :warning :
                threshold2.n_candidate_false_promotion_risk == 0 ?
                :info : :warning,
            evidence = threshold2 === nothing ? "threshold 2 missing" :
                string("false-promotion rate = ",
                    threshold2.candidate_false_promotion_rate),
            implication =
                :low_thresholds_need_explicit_false_alarm_controls),
        (finding = :threshold_4_power_recheck,
            severity = threshold4 === nothing ? :warning :
                threshold4.n_candidate_false_negative_risk == 0 ?
                :info : :warning,
            evidence = threshold4 === nothing ? "threshold 4 missing" :
                string("false-negative rate = ",
                    threshold4.candidate_false_negative_rate),
            implication =
                :strict_thresholds_need_false_drop_and_weak_dimension_power_checks),
        (finding = :category_caveat_screen,
            severity = caveat_cells == 0 ? :info : :warning,
            evidence = string(caveat_cells,
                " cell(s) have candidate predictive gain with category caveat"),
            implication =
                :fit_thresholds_should_require_category_calibration_alignment),
        (finding = :false_add_candidate_margin_mean,
            severity = isempty(false_add) ? :warning :
                finite_mean(row.candidate_minus_declared_log_score
                    for row in false_add) <= 0 ? :info : :warning,
            evidence = isempty(false_add) ? "missing" :
                string("mean candidate-declared dLogScore = ",
                    round3(finite_mean(row.candidate_minus_declared_log_score
                        for row in false_add))),
            implication =
                :extra_loading_candidates_need_specificity_before_q_revision),
        (finding = :false_drop_candidate_margin_mean,
            severity = isempty(false_drop) ? :warning :
                finite_mean(row.candidate_minus_declared_log_score
                    for row in false_drop) > 0 ? :info : :warning,
            evidence = isempty(false_drop) ? "missing" :
                string("mean candidate-declared dLogScore = ",
                    round3(finite_mean(row.candidate_minus_declared_log_score
                        for row in false_drop))),
            implication =
                :missing_loading_power_depends_on_candidate_margin),
        (finding = :public_claims_blocked,
            severity = :blocker,
            evidence =
                "local replicated small-MCMC and category-calibration bridge",
            implication =
                :do_not_claim_public_fit_thresholds_model_weights_or_q_revisions),
    ]
end

function scenario_category_cell(options, seed::Int, scenario)
    base_options = merge(options, (; seed))
    fitopts = QMisspec.fit_options(base_options, scenario)
    generated = QMisspec.generate_rows(fitopts, scenario)
    split = QMisspec.SmallMCMC.split_rows(generated.rows, fitopts)
    scores = observed_scores(generated.rows, split.heldout_indices)
    scenario_seed = fitopts.seed + scenario.seed_offset
    context = (;
        seed = scenario_seed,
        base_seed = seed,
        prior_profile = fitopts.prior_profile,
        scenario = scenario.name,
        axis = scenario.axis,
        role = scenario.role,
    )
    sets = model_probability_sets(split.train_rows, generated.rows,
        split.heldout_indices, generated, scenario, fitopts)
    model_rows = NamedTuple[]
    category_rows = NamedTuple[]
    cumulative_rows = NamedTuple[]
    for set in sets
        if set.probabilities === nothing
            push!(model_rows,
                failed_model_summary_row(context, set.metadata, scores))
            continue
        end
        push!(model_rows, model_summary_row(context, set.model,
            set.probabilities, scores, set.metadata))
        append!(category_rows, category_distribution_rows(context, set.model,
            set.probabilities, scores))
        append!(cumulative_rows, cumulative_threshold_rows(context, set.model,
            set.probabilities, scores))
    end
    ranked = ranked_summary_rows(model_rows)
    comparisons = [merge(row, context, (; public_claim_allowed = false))
        for row in comparison_rows(ranked)]
    cell = scenario_cell_row(fitopts, scenario, split, ranked, comparisons)
    return (;
        cell_row = cell,
        model_rows = ranked,
        comparison_rows = comparisons,
        category_distribution_rows = category_rows,
        cumulative_threshold_rows = cumulative_rows,
    )
end

function table(io, headers, rows)
    println(io, "| ", join(headers, " | "), " |")
    println(io, "| ", join(fill("---", length(headers)), " | "), " |")
    for row in rows
        println(io, "| ", join(string.(row), " | "), " |")
    end
    println(io)
end

function render_markdown(path, artifact)
    mkpath(dirname(path))
    open(path, "w") do io
        println(io,
            "# Replicated Uto-Style Q-Misspecification Category Bridge")
        println(io)
        println(io, "- Generated at: `", artifact.generated_at, "`")
        println(io, "- Local only: `true`")
        println(io, "- Public claims allowed: `false`")
        println(io)
        println(io, "## Interpretation")
        println(io)
        println(io,
            "This report reruns the local Q-misspecification MCMC scenarios ",
            "across seeds and joins predictive dLogScore thresholds to category ",
            "calibration. A threshold pass is treated as a screening event only; ",
            "public threshold, model-weight, and Q-revision claims remain blocked.")
        println(io)
        println(io, "## Findings")
        table(io, ["Finding", "Severity", "Evidence", "Implication"],
            [[row.finding, row.severity, row.evidence, row.implication]
             for row in artifact.finding_rows])
        println(io, "## Scenario Cells")
        table(io, ["Seed", "Scenario", "Axis", "Best", "Declared dLog",
                "Candidate dLog", "Candidate-Declared dLog",
                "Candidate dBrier", "Candidate dTV", "Candidate dCumL1",
                "Caveat"],
            [[row.seed, row.scenario, row.axis, row.observed_best_model,
                row.declared_delta_log_score_vs_null,
                row.candidate_delta_log_score_vs_null,
                row.candidate_minus_declared_log_score,
                row.candidate_delta_brier_vs_null,
                row.candidate_delta_category_total_variation_vs_null,
                row.candidate_delta_cumulative_l1_vs_null,
                row.candidate_predictive_category_caveat]
             for row in artifact.scenario_cell_rows])
        println(io, "## Threshold Summary")
        table(io, ["Threshold", "Cells", "Candidate Passed",
                "False Promotion", "False Promotion Rate", "False Negative",
                "False Negative Rate", "Category Caveat"],
            [Any[row.threshold, row.n_cells, row.n_candidate_passed,
                row.n_candidate_false_promotion_risk,
                row.candidate_false_promotion_rate,
                row.n_candidate_false_negative_risk,
                row.candidate_false_negative_rate,
                row.n_candidate_predictive_category_caveat]
             for row in artifact.threshold_summary_rows])
        println(io, "## Threshold Rows")
        table(io, ["Seed", "Scenario", "Threshold", "Declared",
                "Candidate", "Candidate Cal", "Candidate-Declared dLog",
                "Risk"],
            [[row.seed, row.scenario, row.threshold, row.declared_passed,
                row.candidate_passed,
                row.candidate_category_calibration_aligned,
                row.candidate_minus_declared_log_score,
                row.risk_interpretation]
             for row in artifact.threshold_rows])
        println(io, "## Model Category Metrics")
        table(io, ["Seed", "Scenario", "Model", "Rank", "LogScore",
                "Brier", "TV", "CumL1", "Sampler", "Draws"],
            [[row.seed, row.scenario, row.model, row.rank,
                row.heldout_log_score, row.multiclass_brier,
                row.category_total_variation, row.cumulative_l1,
                row.sampler_flag, row.n_draws]
             for row in artifact.model_score_rows])
        println(io, "## Boundary")
        println(io)
        println(io,
            "This is still a local diagnostic, not publication-grade evidence. ",
            "The next gate should either increase the MCMC budget further or ",
            "turn the predictive-plus-category rule into an explicit simulation ",
            "policy before any public threshold language is used.")
    end
    return path
end

function input_artifact_rows(options)
    rows = NamedTuple[]
    if isfile(options.previous_json)
        push!(rows, (;
            artifact = :q_misspecification_mcmc_simulations,
            path = rel(options.previous_json),
            sha256 = file_sha256(options.previous_json),
        ))
    end
    return rows
end

function build_artifact(options)
    cell_rows = NamedTuple[]
    model_rows = NamedTuple[]
    comparison_rows_all = NamedTuple[]
    category_rows = NamedTuple[]
    cumulative_rows = NamedTuple[]
    for seed in options.seeds, scenario in options.scenarios
        cell = scenario_category_cell(options, seed, scenario)
        push!(cell_rows, cell.cell_row)
        append!(model_rows, cell.model_rows)
        append!(comparison_rows_all, cell.comparison_rows)
        append!(category_rows, cell.category_distribution_rows)
        append!(cumulative_rows, cell.cumulative_threshold_rows)
    end
    thresholds = threshold_rows(cell_rows, options.thresholds)
    threshold_summary = threshold_summary_rows(thresholds)
    findings = finding_rows(cell_rows, threshold_summary, model_rows)
    mcmc_warning_rows = [row for row in model_rows
        if row.model in MCMC_MODEL_NAMES && row.sampler_flag !== :ok]
    threshold2 = summary_for_threshold(threshold_summary, 2.0)
    threshold4 = summary_for_threshold(threshold_summary, 4.0)
    return (;
        schema = OUTPUT_SCHEMA,
        family = :mgmfrm,
        scope = :uto_style_replicated_q_misspecification_category_bridge,
        status = :local_replicated_q_misspecification_category_bridge_recorded,
        generated_at = string(now(UTC)),
        package = (;
            name = "BayesianMGMFRM",
            version = project_version(),
            julia_version = string(VERSION),
        ),
        local_only = true,
        publication_or_registration_action = false,
        public_fit_metric_claim = false,
        public_q_revision_claim = false,
        automatic_q_revision = false,
        public_model_weight_claim = false,
        sparse_mgmfrm_superiority_claim = false,
        input_artifacts = input_artifact_rows(options),
        design = (;
            scenarios = [scenario.name for scenario in options.scenarios],
            seeds = options.seeds,
            thresholds = options.thresholds,
            n_persons = options.n_persons,
            n_items = options.n_items,
            n_raters = options.n_raters,
            heldout_fraction = options.heldout_fraction,
            q_base = QMisspec.q_rows(QMisspec.Q_BASE),
            q_false_add = QMisspec.q_rows(QMisspec.Q_FALSE_ADD),
            q_rotated_wrong = QMisspec.q_rows(QMisspec.Q_ROTATED_WRONG),
        ),
        fit_controls = (;
            backend = :advancedhmc,
            sampler = :nuts,
            chains = options.chains,
            warmup_per_chain = options.warmup_per_chain,
            draws_per_chain = options.draws_per_chain,
            target_acceptance = options.target_acceptance,
            prior_profile = options.prior_profile,
            progress = options.progress,
        ),
        scenario_cell_rows = cell_rows,
        model_score_rows = model_rows,
        comparison_rows = comparison_rows_all,
        category_distribution_rows = category_rows,
        cumulative_threshold_rows = cumulative_rows,
        threshold_rows = thresholds,
        threshold_summary_rows = threshold_summary,
        finding_rows = findings,
        summary = (;
            passed = all(row.fit_succeeded for row in model_rows
                if row.model in MCMC_MODEL_NAMES),
            n_seeds = length(options.seeds),
            n_scenarios = length(options.scenarios),
            n_seed_scenario_cells = length(cell_rows),
            n_model_score_rows = length(model_rows),
            n_category_distribution_rows = length(category_rows),
            n_cumulative_threshold_rows = length(cumulative_rows),
            n_threshold_rows = length(thresholds),
            threshold_2_candidate_false_promotion_rate =
                threshold2 === nothing ? missing :
                threshold2.candidate_false_promotion_rate,
            threshold_4_false_negative_rate =
                threshold4 === nothing ? missing :
                threshold4.candidate_false_negative_rate,
            n_candidate_predictive_category_caveat_cells =
                count(row -> row.candidate_predictive_category_caveat,
                    cell_rows),
            n_mcmc_warning_rows = length(mcmc_warning_rows),
            no_public_fit_metric_claim = true,
            no_public_q_revision_claim = true,
            no_automatic_q_revision = true,
            no_public_model_weight_claim = true,
            no_sparse_superiority_claim = true,
            next_gate =
                :larger_budget_predictive_category_threshold_policy,
        ),
    )
end

function main(args = ARGS)
    options = parse_args(args)
    artifact = build_artifact(options)
    write_artifact(options.output_json, artifact)
    render_markdown(options.output_md, artifact)
    println("wrote ", rel(options.output_json))
    println("wrote ", rel(options.output_md))
    println("cells=", artifact.summary.n_seed_scenario_cells,
        " threshold_2_false_promotion_rate=",
        artifact.summary.threshold_2_candidate_false_promotion_rate,
        " threshold_4_false_negative_rate=",
        artifact.summary.threshold_4_false_negative_rate,
        " category_caveats=",
        artifact.summary.n_candidate_predictive_category_caveat_cells,
        " next_gate=", artifact.summary.next_gate)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
