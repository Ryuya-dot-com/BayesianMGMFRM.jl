#!/usr/bin/env julia

using Dates
using Random
using SHA
using Statistics
using TOML

import BayesianMGMFRM

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT_JSON =
    joinpath(ROOT, "artifacts", "uto_style_small_mcmc_refit",
        "uto_style_small_mcmc_refit.json")
const DEFAULT_OUTPUT_MD =
    joinpath(ROOT, "artifacts", "uto_style_small_mcmc_refit",
        "uto_style_small_mcmc_refit.md")

include(joinpath(@__DIR__, "local_json.jl"))

const OUTPUT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_uto_style_small_mcmc_refit.v1"
const CATEGORY_LEVELS = [0, 1, 2]

const Q_TRUE = Bool[
    1 0
    1 0
    1 0
    0 1
    0 1
    0 1
]

const Q_WRONG = Bool[
    1 0
    1 0
    0 1
    1 0
    0 1
    0 1
]

const MCMC_MODELS = [
    :true_q_mgmfrm_mcmc,
    :wrong_q_mgmfrm_mcmc,
    :scalar_gmfrm_mcmc,
]

const REFERENCE_MODELS = [
    :true_q_source_oracle,
    :item_rater_reference,
    :null_or_intercept_reference,
]

function usage()
    return """
    Run a local small MCMC refit under an Uto-style known-truth condition.

    The response data are generated from the same guarded source likelihood
    used by the current experimental MGMFRM fit path. This is a local
    diagnostic: it is not a publication-grade simulation and keeps public
    fit/model-weight/Q claims blocked.

    Usage:
      julia --project=. scripts/generate_mgmfrm_uto_style_small_mcmc_refit.jl [options]

    Options:
      --output-json PATH       JSON artifact path.
      --output-md PATH         Markdown report path.
      --n-persons N            Number of persons. Default: 12.
      --n-raters N             Number of raters. Default: 3.
      --heldout-fraction X     Observation holdout fraction. Default: 0.17.
      --chains N               MCMC chains. Default: 1.
      --warmup-per-chain N     Warmup iterations per chain. Default: 30.
      --draws-per-chain N      Posterior draws per chain. Default: 30.
      --target-acceptance X    NUTS target acceptance. Default: 0.8.
      --prior-profile NAME     Internal source prior profile: default, tight, or diffuse.
                               Default: default.
      --seed N                 Base random seed. Default: 20260707.
      --progress               Show sampler progress.
    """
end

function parse_args(args)
    output_json = DEFAULT_OUTPUT_JSON
    output_md = DEFAULT_OUTPUT_MD
    n_persons = 12
    n_raters = 3
    heldout_fraction = 0.17
    chains = 1
    warmup_per_chain = 30
    draws_per_chain = 30
    target_acceptance = 0.8
    prior_profile = :default
    seed = 20260707
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
        elseif arg == "--n-persons"
            index < length(args) || error("--n-persons requires an integer")
            n_persons = parse(Int, args[index + 1])
            index += 2
        elseif arg == "--n-raters"
            index < length(args) || error("--n-raters requires an integer")
            n_raters = parse(Int, args[index + 1])
            index += 2
        elseif arg == "--heldout-fraction"
            index < length(args) || error("--heldout-fraction requires a number")
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
        elseif arg == "--seed"
            index < length(args) || error("--seed requires an integer")
            seed = parse(Int, args[index + 1])
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

    return (;
        output_json,
        output_md,
        n_persons,
        n_items = size(Q_TRUE, 1),
        n_raters,
        heldout_fraction,
        chains,
        warmup_per_chain,
        draws_per_chain,
        target_acceptance,
        prior_profile,
        seed,
        progress,
    )
end

project_version() =
    String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])
file_sha256(path::AbstractString) = bytes2hex(open(sha256, path))
rel(path::AbstractString) = relpath(path, ROOT)
round3(value) = round(Float64(value); digits = 3)
round4(value) = round(Float64(value); digits = 4)

function mean_or_nan(values)
    collected = Float64.(collect(values))
    isempty(collected) && return NaN
    return mean(collected)
end

function logmeanexp(values::AbstractVector{<:Real})
    isempty(values) && return NaN
    max_value = maximum(values)
    isfinite(max_value) || return max_value
    return max_value +
        log(sum(exp(Float64(value) - max_value) for value in values) /
            length(values))
end

function centered(values)
    output = collect(Float64, values)
    output .-= mean(output)
    return output
end

function full_cross_rows(options; scores = nothing)
    rows = NamedTuple[]
    row_index = 0
    for person in 1:options.n_persons,
            rater in 1:options.n_raters,
            item in 1:options.n_items
        row_index += 1
        score = scores === nothing ?
            CATEGORY_LEVELS[mod(person + rater + item, length(CATEGORY_LEVELS)) + 1] :
            scores[row_index]
        push!(rows, (;
            examinee = person,
            rater,
            item,
            score = Int(score),
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

function facet_data(rows)
    return BayesianMGMFRM.FacetData(table_from_rows(rows);
        person = :examinee,
        rater = :rater,
        item = :item,
        score = :score,
    )
end

function q_rows(matrix::AbstractMatrix{Bool})
    return [[Bool(matrix[row, col]) for col in axes(matrix, 2)]
        for row in axes(matrix, 1)]
end

function design_for_rows(rows, model::Symbol)
    data = facet_data(rows)
    if model === :scalar_gmfrm_mcmc
        spec = BayesianMGMFRM.mfrm_spec(data;
            family = :gmfrm,
            discrimination = :rater,
        )
    elseif model in (:true_q_mgmfrm_mcmc, :true_q_source_oracle)
        spec = BayesianMGMFRM.mfrm_spec(data;
            family = :mgmfrm,
            dimensions = size(Q_TRUE, 2),
            q_matrix = Q_TRUE,
        )
    elseif model === :wrong_q_mgmfrm_mcmc
        spec = BayesianMGMFRM.mfrm_spec(data;
            family = :mgmfrm,
            dimensions = size(Q_WRONG, 2),
            q_matrix = Q_WRONG,
        )
    else
        error("model does not have a design: $model")
    end
    return (;
        data,
        spec,
        design = BayesianMGMFRM.getdesign(spec; preview = true),
    )
end

function source_prior(profile::Symbol)
    profile === :default && return BayesianMGMFRM._SourceFixturePrior()
    profile === :tight && return BayesianMGMFRM._SourceFixturePrior(;
        person_sd = 0.7,
        rater_sd = 0.7,
        item_sd = 0.7,
        log_discrimination_sd = 0.25,
        log_consistency_sd = 0.25,
        step_sd = 0.7,
    )
    profile === :diffuse && return BayesianMGMFRM._SourceFixturePrior(;
        person_sd = 1.5,
        rater_sd = 1.5,
        item_sd = 1.5,
        log_discrimination_sd = 0.8,
        log_consistency_sd = 0.8,
        step_sd = 1.5,
    )
    error("unknown prior profile: $profile")
end

function prior_values(profile::Symbol)
    prior = source_prior(profile)
    return (;
        person_sd = prior.person_sd,
        rater_sd = prior.rater_sd,
        item_sd = prior.item_sd,
        log_discrimination_sd = prior.log_discrimination_sd,
        log_consistency_sd = prior.log_consistency_sd,
        step_sd = prior.step_sd,
    )
end

function truth_components(options, rng::AbstractRNG)
    dims = size(Q_TRUE, 2)
    theta = options.ability_scale *
        [randn(rng) for _ in 1:options.n_persons, _ in 1:dims]
    for person in 1:options.n_persons
        theta[person, 2] =
            options.ability_scale * (0.20 * randn(rng) -
                                     0.70 * theta[person, 1] /
                                     max(options.ability_scale, eps()))
    end
    item_difficulty = centered(range(-0.75, 0.75; length = options.n_items))
    item_discrimination = zeros(Float64, options.n_items, dims)
    for item in 1:options.n_items, dim in 1:dims
        if Q_TRUE[item, dim]
            item_discrimination[item, dim] =
                options.item_discrimination_scale *
                (0.90 + 0.25 * rand(rng))
        end
    end
    rater_severity = centered(options.rater_severity_scale .*
        range(-1.0, 1.0; length = options.n_raters))
    consistency_raw = [exp(options.rater_consistency_spread *
        (2 * (rater - 1) / max(options.n_raters - 1, 1) - 1))
        for rater in 1:options.n_raters]
    rater_consistency =
        consistency_raw ./ (prod(consistency_raw)^(1 / length(consistency_raw)))
    return (;
        theta,
        item_difficulty,
        item_discrimination,
        rater_severity,
        rater_consistency,
        item_step = (:item_step in keys(options)) ?
            Float64(options.item_step) : -0.55,
    )
end

function truth_direct_params(design::BayesianMGMFRM.FacetDesign, truth)
    params = zeros(Float64, length(design.parameter_names))
    data = design.spec.data
    dims = design.spec.dimensions
    person_block = design.blocks[:person]
    for person_index in eachindex(data.person_levels), dim in 1:dims
        params[person_block[(person_index - 1) * dims + dim]] =
            truth.theta[Int(data.person_levels[person_index]), dim]
    end
    for rater_index in eachindex(data.rater_levels)
        rater = Int(data.rater_levels[rater_index])
        params[design.blocks[:rater][rater_index]] = truth.rater_severity[rater]
        params[design.blocks[:rater_consistency][rater_index]] =
            truth.rater_consistency[rater]
    end
    for item_index in eachindex(data.item_levels)
        item = Int(data.item_levels[item_index])
        params[design.blocks[:item][item_index]] =
            truth.item_difficulty[item]
        params[design.blocks[:item_steps][item_index]] = truth.item_step
    end
    index_by_name = Dict(name => index for (index, name) in
        pairs(design.parameter_names))
    for item_index in eachindex(data.item_levels)
        item = Int(data.item_levels[item_index])
        for dim in 1:dims
            design.spec.q_matrix[item_index, dim] || continue
            name = "item_dimension_discrimination[item=$(data.item_levels[item_index]),$(design.spec.dimension_labels[dim])]"
            params[index_by_name[name]] =
                truth.item_discrimination[item, dim]
        end
    end
    return params
end

function score_probabilities_from_fixture_rows(fixture_rows, n_rows::Int)
    probs = [zeros(Float64, length(CATEGORY_LEVELS)) for _ in 1:n_rows]
    for row in fixture_rows
        probs[Int(row.row)][Int(row.category_index)] =
            exp(Float64(row.log_probability))
    end
    return probs
end

function sample_category(rng::AbstractRNG, probabilities)
    draw = rand(rng)
    cumulative = 0.0
    for index in eachindex(probabilities)
        cumulative += probabilities[index]
        draw <= cumulative && return CATEGORY_LEVELS[index]
    end
    return last(CATEGORY_LEVELS)
end

function generate_source_rows(options)
    rng = MersenneTwister(options.seed)
    dummy_rows = full_cross_rows(options)
    dummy = design_for_rows(dummy_rows, :true_q_source_oracle)
    truth = truth_components(options, rng)
    direct = truth_direct_params(dummy.design, truth)
    fixture_rows =
        BayesianMGMFRM._mgmfrm_source_fixture_values(dummy.design, direct)
    probs = score_probabilities_from_fixture_rows(fixture_rows, length(dummy_rows))
    scores = [sample_category(rng, probs[row]) for row in eachindex(dummy_rows)]
    rows = full_cross_rows(options; scores)
    return (; rows, truth, direct_params = direct)
end

function valid_split(train_rows, options)
    try
        data = facet_data(train_rows)
        return length(data.person_levels) == options.n_persons &&
               length(data.rater_levels) == options.n_raters &&
               length(data.item_levels) == options.n_items &&
               data.category_levels == CATEGORY_LEVELS
    catch
        return false
    end
end

function split_rows(rows, options)
    rng = MersenneTwister(options.seed + 17)
    n = length(rows)
    n_heldout = max(1, round(Int, options.heldout_fraction * n))
    for attempt in 1:200
        indices = shuffle(rng, collect(1:n))
        heldout = sort(indices[1:n_heldout])
        heldout_set = Set(heldout)
        train_rows = [rows[index] for index in 1:n if !(index in heldout_set)]
        valid_split(train_rows, options) && return (;
            train_rows,
            heldout_indices = heldout,
            split_attempts = attempt,
        )
    end
    error("could not find a training split retaining all facets/categories")
end

function expected_scores_from_direct(design, direct_draws::AbstractMatrix)
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

function score_direct_draws(model::Symbol, full_design, direct_draws,
        heldout_indices)
    full_loglikelihood =
        BayesianMGMFRM.pointwise_loglikelihood_matrix(
            full_design,
            direct_draws,
        )
    expected = expected_scores_from_direct(full_design, direct_draws)
    heldout_loglikelihood = full_loglikelihood[:, heldout_indices]
    heldout_expected = expected[:, heldout_indices]
    observed = Float64.(full_design.spec.data.score[heldout_indices])
    pointwise_elpd =
        [logmeanexp(vec(heldout_loglikelihood[:, column]))
            for column in axes(heldout_loglikelihood, 2)]
    expected_score_mean =
        [mean_or_nan(heldout_expected[:, column])
            for column in axes(heldout_expected, 2)]
    abs_errors = abs.(observed .- expected_score_mean)
    return (;
        score = (;
            model,
            scoring_succeeded = true,
            heldout_elpd = sum(pointwise_elpd; init = 0.0),
            mean_log_predictive_density = mean(pointwise_elpd),
            heldout_expected_score_mae = mean(abs_errors),
            heldout_expected_score_rmse = sqrt(mean(abs_errors .^ 2)),
            n_heldout_observations = length(heldout_indices),
            public_claim_allowed = false,
        ),
        pointwise_rows = [(;
            model,
            observation = heldout_indices[index],
            observed_score = Int(observed[index]),
            pointwise_log_predictive_density = pointwise_elpd[index],
            expected_score_mean = expected_score_mean[index],
            absolute_expected_score_error = abs_errors[index],
            public_claim_allowed = false,
        ) for index in eachindex(heldout_indices)],
    )
end

function fit_model(model::Symbol, train_rows, full_rows, heldout_indices,
        options)
    started = time_ns()
    train = design_for_rows(train_rows, model)
    full = design_for_rows(full_rows, model)
    layout_matches = train.design.parameter_names == full.design.parameter_names
    fit = BayesianMGMFRM.fit(train.spec;
        experimental = true,
        prior = source_prior(options.prior_profile),
        backend = :advancedhmc,
        ndraws = options.draws_per_chain,
        warmup = options.warmup_per_chain,
        chains = options.chains,
        seed = options.seed + model_seed_offset(model),
        target_accept = options.target_acceptance,
        progress = options.progress,
    )
    scored = score_direct_draws(model, full.design, fit.direct_draws,
        heldout_indices)
    elapsed_seconds = (time_ns() - started) / 1e9
    summary = fit.diagnostic_surface.summary
    fit_row = merge(scored.score, (;
        model_family = fit.design.spec.family,
        fit_succeeded = true,
        returned_type = Symbol(nameof(typeof(fit))),
        layout_matches,
        n_train_observations = length(train_rows),
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
    ))
    return (; fit_row, pointwise_rows = scored.pointwise_rows)
end

function failed_fit_row(model::Symbol, err, options, train_rows, heldout_indices)
    return (;
        model,
        model_family = model === :scalar_gmfrm_mcmc ? :gmfrm : :mgmfrm,
        fit_succeeded = false,
        scoring_succeeded = false,
        returned_type = missing,
        layout_matches = false,
        n_train_observations = length(train_rows),
        n_heldout_observations = length(heldout_indices),
        heldout_elpd = NaN,
        mean_log_predictive_density = NaN,
        heldout_expected_score_mae = NaN,
        heldout_expected_score_rmse = NaN,
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
        public_claim_allowed = false,
    )
end

function model_seed_offset(model::Symbol)
    model === :true_q_mgmfrm_mcmc && return 101
    model === :wrong_q_mgmfrm_mcmc && return 203
    model === :scalar_gmfrm_mcmc && return 307
    return 409
end

function smoothed_probs(rows; alpha = 1.0)
    counts = Dict(score => alpha for score in CATEGORY_LEVELS)
    for row in rows
        counts[row.score] += 1
    end
    total = sum(values(counts); init = 0.0)
    return [counts[score] / total for score in CATEGORY_LEVELS]
end

function grouped_smoothed_probs(rows, key_fn; alpha = 1.0)
    groups = Dict{Any,Dict{Int,Float64}}()
    for row in rows
        key = key_fn(row)
        counts = get!(groups, key, Dict(score => alpha for score in CATEGORY_LEVELS))
        counts[row.score] += 1
    end
    return Dict(key => begin
        total = sum(values(counts); init = 0.0)
        [counts[score] / total for score in CATEGORY_LEVELS]
    end for (key, counts) in groups)
end

function score_reference(model::Symbol, train_rows, full_rows, heldout_indices)
    global_probs = smoothed_probs(train_rows)
    item_rater = grouped_smoothed_probs(train_rows,
        row -> (row.item, row.rater))
    pointwise_rows = NamedTuple[]
    lpds = Float64[]
    abs_errors = Float64[]
    for observation in heldout_indices
        row = full_rows[observation]
        probs = if model === :null_or_intercept_reference
            global_probs
        elseif model === :item_rater_reference
            get(item_rater, (row.item, row.rater), global_probs)
        else
            error("unknown reference model: $model")
        end
        score_index = findfirst(==(row.score), CATEGORY_LEVELS)
        lpd = log(max(probs[score_index], eps(Float64)))
        expected = sum(Float64(CATEGORY_LEVELS[index]) * probs[index]
            for index in eachindex(CATEGORY_LEVELS))
        abs_error = abs(Float64(row.score) - expected)
        push!(lpds, lpd)
        push!(abs_errors, abs_error)
        push!(pointwise_rows, (;
            model,
            observation,
            observed_score = row.score,
            pointwise_log_predictive_density = lpd,
            expected_score_mean = expected,
            absolute_expected_score_error = abs_error,
            public_claim_allowed = false,
        ))
    end
    return (;
        fit_row = (;
            model,
            model_family = :analytic_reference,
            fit_succeeded = true,
            scoring_succeeded = true,
            returned_type = :analytic_reference,
            layout_matches = true,
            n_train_observations = length(train_rows),
            n_heldout_observations = length(heldout_indices),
            heldout_elpd = sum(lpds; init = 0.0),
            mean_log_predictive_density = mean(lpds),
            heldout_expected_score_mae = mean(abs_errors),
            heldout_expected_score_rmse = sqrt(mean(abs_errors .^ 2)),
            n_raw_parameters = 0,
            n_direct_parameters = 0,
            n_draws = 0,
            chains = 0,
            warmup_per_chain = 0,
            draws_per_chain = 0,
            sampler = :analytic,
            backend = :analytic,
            sampler_flag = :not_applicable,
            n_sampler_warnings = 0,
            n_nonfinite_logdensity = 0,
            n_failed_direct_constraints = 0,
            elapsed_seconds = 0.0,
            public_claim_allowed = false,
        ),
        pointwise_rows,
    )
end

function score_oracle(full_rows, truth, heldout_indices)
    full = design_for_rows(full_rows, :true_q_source_oracle)
    direct = truth_direct_params(full.design, truth)
    scored = score_direct_draws(:true_q_source_oracle, full.design,
        reshape(direct, 1, :), heldout_indices)
    fit_row = merge(scored.score, (;
        model_family = :mgmfrm,
        fit_succeeded = true,
        returned_type = :known_truth_source_oracle,
        layout_matches = true,
        n_train_observations = missing,
        n_raw_parameters = 0,
        n_direct_parameters = length(direct),
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
    ))
    return (; fit_row, pointwise_rows = scored.pointwise_rows)
end

function score_all_models(full_rows, train_rows, heldout_indices, truth, options)
    fit_rows = NamedTuple[]
    pointwise = NamedTuple[]

    oracle = score_oracle(full_rows, truth, heldout_indices)
    push!(fit_rows, oracle.fit_row)
    append!(pointwise, oracle.pointwise_rows)

    for model in MCMC_MODELS
        try
            result = fit_model(model, train_rows, full_rows, heldout_indices,
                options)
            push!(fit_rows, result.fit_row)
            append!(pointwise, result.pointwise_rows)
        catch err
            push!(fit_rows, failed_fit_row(model, err, options, train_rows,
                heldout_indices))
        end
    end

    for model in (:item_rater_reference, :null_or_intercept_reference)
        result = score_reference(model, train_rows, full_rows, heldout_indices)
        push!(fit_rows, result.fit_row)
        append!(pointwise, result.pointwise_rows)
    end

    return (; fit_rows, pointwise_rows = pointwise)
end

function ranked_rows(fit_rows)
    finite_rows = [row for row in fit_rows if isfinite(Float64(row.heldout_elpd))]
    ranked = sort(finite_rows; by = row -> Float64(row.heldout_elpd), rev = true)
    rank_by_model = Dict(row.model => index for (index, row) in pairs(ranked))
    return [merge(row, (rank = get(rank_by_model, row.model, missing),))
        for row in fit_rows]
end

function row_by_model(rows, model)
    matches = [row for row in rows if row.model === model]
    isempty(matches) && return nothing
    return only(matches)
end

function comparison_rows(rows)
    null = row_by_model(rows, :null_or_intercept_reference)
    true_mcmc = row_by_model(rows, :true_q_mgmfrm_mcmc)
    oracle = row_by_model(rows, :true_q_source_oracle)
    output = NamedTuple[]
    for row in rows
        row.model in (:null_or_intercept_reference,) && continue
        if null !== nothing && isfinite(Float64(row.heldout_elpd))
            push!(output, (;
                comparison = Symbol(string(row.model, "_minus_null")),
                model = row.model,
                baseline = :null_or_intercept_reference,
                delta_elpd = round3(row.heldout_elpd - null.heldout_elpd),
                delta_mae = round3(row.heldout_expected_score_mae -
                                   null.heldout_expected_score_mae),
                public_claim_allowed = false,
            ))
        end
    end
    if oracle !== nothing && true_mcmc !== nothing &&
            isfinite(Float64(true_mcmc.heldout_elpd))
        push!(output, (;
            comparison = :true_q_mgmfrm_mcmc_minus_true_q_source_oracle,
            model = :true_q_mgmfrm_mcmc,
            baseline = :true_q_source_oracle,
            delta_elpd = round3(true_mcmc.heldout_elpd - oracle.heldout_elpd),
            delta_mae = round3(true_mcmc.heldout_expected_score_mae -
                               oracle.heldout_expected_score_mae),
            public_claim_allowed = false,
        ))
    end
    return output
end

function finding_rows(rows, comparisons)
    leader = first(sort([row for row in rows
        if isfinite(Float64(row.heldout_elpd))];
        by = row -> Float64(row.heldout_elpd), rev = true))
    true_vs_null = [row for row in comparisons
        if row.comparison === :true_q_mgmfrm_mcmc_minus_null]
    oracle_vs_null = [row for row in comparisons
        if row.comparison === :true_q_source_oracle_minus_null]
    mcmc_vs_oracle = [row for row in comparisons
        if row.comparison === :true_q_mgmfrm_mcmc_minus_true_q_source_oracle]
    direction_recovered =
        !isempty(true_vs_null) && only(true_vs_null).delta_elpd > 0
    return [
        (finding = :source_oracle_margin_recorded,
            severity = isempty(oracle_vs_null) ? :warning : :info,
            evidence = isempty(oracle_vs_null) ? "missing" :
                string("oracle dELPD vs null = ",
                    only(oracle_vs_null).delta_elpd),
            implication = :data_generating_signal_checked_before_mcmc),
        (finding = :true_q_mcmc_direction,
            severity = direction_recovered ? :info : :warning,
            evidence = isempty(true_vs_null) ? "true-Q MCMC failed" :
                string("true-Q MCMC dELPD vs null = ",
                    only(true_vs_null).delta_elpd,
                    "; leader = ", leader.model),
            implication = direction_recovered ?
                :uto_style_direction_survived_small_refit :
                :estimation_layer_can_reverse_or_blunt_oracle_direction),
        (finding = :mcmc_estimation_loss_vs_oracle,
            severity = isempty(mcmc_vs_oracle) ? :warning : :info,
            evidence = isempty(mcmc_vs_oracle) ? "missing" :
                string("true-Q MCMC dELPD vs oracle = ",
                    only(mcmc_vs_oracle).delta_elpd),
            implication = :quantifies_posterior_recovery_gap),
        (finding = :public_claims_blocked,
            severity = :blocker,
            evidence = "single local small-refit diagnostic only",
            implication = :do_not_claim_public_mgmfrm_superiority),
    ]
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
        println(io, "# Uto-Style Small MCMC Refit")
        println(io)
        println(io, "- Generated at: `", artifact.generated_at, "`")
        println(io, "- Local only: `true`")
        println(io, "- Public claims allowed: `false`")
        println(io)
        println(io, "## Interpretation")
        println(io)
        println(io,
            "This is a small known-truth MCMC refit diagnostic. The data are ",
            "generated from the same guarded source likelihood used by the ",
            "experimental fit path, then scored on a common observation holdout.")
        println(io)
        println(io, "## Findings")
        table(io, ["Finding", "Severity", "Evidence", "Implication"],
            [[row.finding, row.severity, row.evidence, row.implication]
             for row in artifact.finding_rows])
        println(io, "## Design")
        table(io, ["Field", "Value"], [
            ["persons", artifact.design.n_persons],
            ["items", artifact.design.n_items],
            ["raters", artifact.design.n_raters],
            ["train observations", artifact.design.n_train_observations],
            ["heldout observations", artifact.design.n_heldout_observations],
            ["chains", artifact.fit_controls.chains],
            ["warmup per chain", artifact.fit_controls.warmup_per_chain],
            ["draws per chain", artifact.fit_controls.draws_per_chain],
        ])
        println(io, "## Scores")
        table(io, ["Rank", "Model", "Family", "ELPD", "Mean LPD", "MAE",
                "RMSE", "Fit", "Sampler Flag"],
            [[row.rank, row.model, row.model_family,
                round3(row.heldout_elpd),
                round3(row.mean_log_predictive_density),
                round3(row.heldout_expected_score_mae),
                round3(row.heldout_expected_score_rmse),
                row.fit_succeeded, row.sampler_flag]
             for row in artifact.model_score_rows])
        println(io, "## Comparisons")
        table(io, ["Comparison", "dELPD", "dMAE"],
            [[row.comparison, row.delta_elpd, row.delta_mae]
             for row in artifact.comparison_rows])
        println(io, "## Boundary")
        println(io)
        println(io,
            "This file is a local diagnostic for the inconsistency mechanism. ",
            "It does not establish public fit thresholds, model weights, Q-matrix ",
            "revision claims, or sparse-MGMFRM superiority.")
    end
    return path
end

function build_artifact(parsed_options)
    generation_options = merge(parsed_options, (;
        ability_scale = 1.25,
        item_discrimination_scale = 1.15,
        rater_severity_scale = 0.55,
        rater_consistency_spread = 0.35,
    ))
    generated = generate_source_rows(generation_options)
    split = split_rows(generated.rows, generation_options)
    scored = score_all_models(generated.rows, split.train_rows,
        split.heldout_indices, generated.truth, parsed_options)
    model_rows = ranked_rows(scored.fit_rows)
    comparisons = comparison_rows(model_rows)
    findings = finding_rows(model_rows, comparisons)
    true_q = row_by_model(model_rows, :true_q_mgmfrm_mcmc)
    null = row_by_model(model_rows, :null_or_intercept_reference)
    direction_recovered =
        true_q !== nothing && null !== nothing &&
        isfinite(Float64(true_q.heldout_elpd)) &&
        true_q.heldout_elpd > null.heldout_elpd
    return (;
        schema = OUTPUT_SCHEMA,
        family = :mgmfrm,
        scope = :uto_style_small_known_truth_mcmc_refit,
        status = :local_small_mcmc_refit_recorded,
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
        public_model_weight_claim = false,
        sparse_mgmfrm_superiority_claim = false,
        design = (;
            scenario = :uto_like_source_aligned_strong_signal_small_mcmc,
            q_true = q_rows(Q_TRUE),
            q_wrong = q_rows(Q_WRONG),
            n_persons = parsed_options.n_persons,
            n_items = parsed_options.n_items,
            n_raters = parsed_options.n_raters,
            n_observations = length(generated.rows),
            n_train_observations = length(split.train_rows),
            n_heldout_observations = length(split.heldout_indices),
            heldout_fraction = parsed_options.heldout_fraction,
            heldout_indices = split.heldout_indices,
            split_attempts = split.split_attempts,
            category_levels = CATEGORY_LEVELS,
            source_scale = 1.7,
        ),
        fit_controls = (;
            backend = :advancedhmc,
            sampler = :nuts,
            chains = parsed_options.chains,
            warmup_per_chain = parsed_options.warmup_per_chain,
            draws_per_chain = parsed_options.draws_per_chain,
            target_acceptance = parsed_options.target_acceptance,
            prior_profile = parsed_options.prior_profile,
            prior_values = prior_values(parsed_options.prior_profile),
            seed = parsed_options.seed,
            progress = parsed_options.progress,
        ),
        model_score_rows = model_rows,
        comparison_rows = comparisons,
        finding_rows = findings,
        pointwise_rows = scored.pointwise_rows,
        summary = (;
            passed = all(row.fit_succeeded for row in model_rows
                if row.model in MCMC_MODELS),
            true_q_mcmc_direction_recovered = direction_recovered,
            observed_best_model =
                first(sort([row for row in model_rows
                    if isfinite(Float64(row.heldout_elpd))];
                    by = row -> Float64(row.heldout_elpd), rev = true)).model,
            no_public_fit_metric_claim = true,
            no_public_q_revision_claim = true,
            no_public_model_weight_claim = true,
            no_sparse_superiority_claim = true,
            next_gate = :replicate_small_mcmc_refit_and_prior_sensitivity,
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
    println("best=", artifact.summary.observed_best_model,
        " true_q_direction_recovered=",
        artifact.summary.true_q_mcmc_direction_recovered,
        " next_gate=", artifact.summary.next_gate)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
