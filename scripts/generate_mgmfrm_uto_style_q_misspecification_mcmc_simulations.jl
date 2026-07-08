#!/usr/bin/env julia

using Dates
using JSON3
using Random
using SHA
using Statistics
using TOML

import BayesianMGMFRM

module SmallMCMC
include(joinpath(@__DIR__, "generate_mgmfrm_uto_style_small_mcmc_refit.jl"))
end

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_EXPANSION_JSON =
    joinpath(ROOT, "artifacts",
        "uto_style_threshold_q_misspecification_expansion",
        "uto_style_threshold_q_misspecification_expansion.json")
const DEFAULT_OUTPUT_JSON =
    joinpath(ROOT, "artifacts",
        "uto_style_q_misspecification_mcmc_simulations",
        "uto_style_q_misspecification_mcmc_simulations.json")
const DEFAULT_OUTPUT_MD =
    joinpath(ROOT, "artifacts",
        "uto_style_q_misspecification_mcmc_simulations",
        "uto_style_q_misspecification_mcmc_simulations.md")

include(joinpath(@__DIR__, "local_json.jl"))

const OUTPUT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_uto_style_q_misspecification_mcmc_simulations.v1"
const CATEGORY_LEVELS = SmallMCMC.CATEGORY_LEVELS
const DEFAULT_THRESHOLDS = [0.0, 2.0, 4.0, 8.0]
const Q_BASE = SmallMCMC.Q_TRUE
const Q_FALSE_ADD = Bool[
    1 0
    1 0
    1 1
    0 1
    0 1
    0 1
]
const Q_FALSE_DROP_TRUE = Q_FALSE_ADD
const Q_ROTATED_WRONG = SmallMCMC.Q_WRONG

const SCENARIO_LIBRARY = [
    (;
        name = :explicit_null_no_multidimensional_signal,
        axis = :explicit_null,
        role = :false_alarm_control,
        seed_offset = 0,
        generator = :null_uniform,
        true_q = Q_BASE,
        declared_q = Q_BASE,
        candidate_q = Q_FALSE_ADD,
        ability_scale = 0.0,
        item_discrimination_scale = 0.0,
        rater_severity_scale = 0.0,
        rater_consistency_spread = 0.0,
        item_step = 0.0,
        expected = :no_mgmfrm_threshold_pass,
    ),
    (;
        name = :false_add_extra_loading,
        axis = :false_add,
        role = :specificity_probe,
        seed_offset = 1009,
        generator = :mgmfrm_source,
        true_q = Q_BASE,
        declared_q = Q_BASE,
        candidate_q = Q_FALSE_ADD,
        ability_scale = 0.80,
        item_discrimination_scale = 0.80,
        rater_severity_scale = 0.30,
        rater_consistency_spread = 0.15,
        item_step = -0.20,
        expected = :candidate_extra_loading_should_not_be_promoted,
    ),
    (;
        name = :false_drop_missing_loading,
        axis = :false_drop,
        role = :power_probe,
        seed_offset = 2027,
        generator = :mgmfrm_source,
        true_q = Q_FALSE_DROP_TRUE,
        declared_q = Q_BASE,
        candidate_q = Q_FALSE_DROP_TRUE,
        ability_scale = 0.90,
        item_discrimination_scale = 0.95,
        rater_severity_scale = 0.35,
        rater_consistency_spread = 0.18,
        item_step = -0.30,
        expected = :candidate_missing_loading_should_gain,
    ),
    (;
        name = :weak_dimension,
        axis = :weak_dimension,
        role = :false_negative_probe,
        seed_offset = 3037,
        generator = :mgmfrm_source,
        true_q = Q_BASE,
        declared_q = Q_BASE,
        candidate_q = Q_BASE,
        ability_scale = 0.35,
        item_discrimination_scale = 0.50,
        rater_severity_scale = 0.20,
        rater_consistency_spread = 0.08,
        item_step = 0.25,
        expected = :strict_thresholds_may_miss_weak_signal,
    ),
    (;
        name = :rater_noise_q_misspec_proxy,
        axis = :q_misspecification_rater_noise,
        role = :specificity_probe,
        seed_offset = 4049,
        generator = :mgmfrm_source,
        true_q = Q_BASE,
        declared_q = Q_BASE,
        candidate_q = Q_FALSE_ADD,
        ability_scale = 0.12,
        item_discrimination_scale = 0.20,
        rater_severity_scale = 0.70,
        rater_consistency_spread = 0.70,
        item_step = 0.10,
        expected = :q_candidate_should_not_absorb_rater_noise,
    ),
]

const MCMC_MODEL_SPECS = [
    (model = :declared_q_mgmfrm_mcmc, family = :mgmfrm, q_field = :declared_q),
    (model = :candidate_q_mgmfrm_mcmc, family = :mgmfrm, q_field = :candidate_q),
    (model = :rotated_wrong_q_mgmfrm_mcmc, family = :mgmfrm,
        q_field = :rotated_wrong_q),
    (model = :scalar_gmfrm_mcmc, family = :gmfrm, q_field = :not_applicable),
]

function usage()
    return """
    Run local Uto-style Q-misspecification MCMC simulations.

    This executes a small MCMC batch for explicit-null, false-add, false-drop,
    weak-dimension, and rater-noise/Q-misspecification proxy scenarios. It is a
    local diagnostic only: thresholds remain screening profiles and no public
    fit, model-weight, automatic Q-revision, or sparse-superiority claim is
    allowed.

    Usage:
      julia --project=. scripts/generate_mgmfrm_uto_style_q_misspecification_mcmc_simulations.jl [options]

    Options:
      --expansion-json PATH    Threshold/Q expansion JSON used as input evidence.
      --output-json PATH       JSON artifact path.
      --output-md PATH         Markdown report path.
      --scenarios LIST         Comma-separated scenarios. Default: all.
      --thresholds LIST        Comma-separated dELPD thresholds. Default: 0,2,4,8.
      --n-persons N            Number of persons. Default: 6.
      --n-raters N             Number of raters. Default: 3.
      --heldout-fraction X     Observation holdout fraction. Default: 0.17.
      --chains N               MCMC chains. Default: 1.
      --warmup-per-chain N     Warmup iterations per chain. Default: 12.
      --draws-per-chain N      Posterior draws per chain. Default: 12.
      --target-acceptance X    NUTS target acceptance. Default: 0.8.
      --prior-profile NAME     Internal source prior profile: default, tight, or diffuse.
                               Default: default.
      --seed N                 Base random seed. Default: 20260707.
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
    matches = [scenario for scenario in SCENARIO_LIBRARY
        if scenario.name === name]
    isempty(matches) && error("unknown scenario: $name")
    return only(matches)
end

function parse_args(args)
    expansion_json = DEFAULT_EXPANSION_JSON
    output_json = DEFAULT_OUTPUT_JSON
    output_md = DEFAULT_OUTPUT_MD
    scenario_names = [scenario.name for scenario in SCENARIO_LIBRARY]
    thresholds = copy(DEFAULT_THRESHOLDS)
    n_persons = 6
    n_raters = 3
    heldout_fraction = 0.17
    chains = 1
    warmup_per_chain = 12
    draws_per_chain = 12
    target_acceptance = 0.8
    prior_profile = :default
    seed = 20260707
    progress = false

    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--expansion-json"
            index < length(args) || error("--expansion-json requires a path")
            expansion_json = abspath(args[index + 1])
            index += 2
        elseif arg == "--output-json"
            index < length(args) || error("--output-json requires a path")
            output_json = abspath(args[index + 1])
            index += 2
        elseif arg == "--output-md"
            index < length(args) || error("--output-md requires a path")
            output_md = abspath(args[index + 1])
            index += 2
        elseif arg == "--scenarios"
            index < length(args) || error("--scenarios requires a comma list")
            scenario_names = parse_symbol_list(args[index + 1])
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

    isfile(expansion_json) || error("expansion JSON not found: $expansion_json")
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
        expansion_json,
        output_json,
        output_md,
        scenarios,
        thresholds,
        n_persons,
        n_items = size(Q_BASE, 1),
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

function centered(values)
    output = collect(Float64, values)
    output .-= mean(output)
    return output
end

function q_rows(matrix::AbstractMatrix{Bool})
    return [[Bool(matrix[row, col]) for col in axes(matrix, 2)]
        for row in axes(matrix, 1)]
end

function q_for_field(scenario, field::Symbol)
    field === :declared_q && return scenario.declared_q
    field === :candidate_q && return scenario.candidate_q
    field === :rotated_wrong_q && return Q_ROTATED_WRONG
    error("no q_matrix for field $field")
end

function design_for_rows(rows, model_spec, scenario)
    data = SmallMCMC.facet_data(rows)
    if model_spec.family === :gmfrm
        spec = BayesianMGMFRM.mfrm_spec(data;
            family = :gmfrm,
            discrimination = :rater,
        )
    else
        q_matrix = q_for_field(scenario, model_spec.q_field)
        spec = BayesianMGMFRM.mfrm_spec(data;
            family = :mgmfrm,
            dimensions = size(q_matrix, 2),
            q_matrix,
        )
    end
    return (;
        data,
        spec,
        design = BayesianMGMFRM.getdesign(spec; preview = true),
    )
end

function truth_components(options, scenario, rng::AbstractRNG)
    dims = size(scenario.true_q, 2)
    theta = options.ability_scale *
        [randn(rng) for _ in 1:options.n_persons, _ in 1:dims]
    if dims >= 2 && options.ability_scale > 0
        for person in 1:options.n_persons
            theta[person, 2] =
                options.ability_scale * (0.20 * randn(rng) -
                                         0.70 * theta[person, 1] /
                                         max(options.ability_scale, eps()))
        end
    end
    item_difficulty = centered(range(-0.55, 0.55; length = options.n_items))
    item_discrimination = zeros(Float64, options.n_items, dims)
    for item in 1:options.n_items, dim in 1:dims
        scenario.true_q[item, dim] || continue
        item_discrimination[item, dim] =
            max(0.05, options.item_discrimination_scale *
                      (0.90 + 0.25 * rand(rng)))
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
        item_step = Float64(options.item_step),
    )
end

function truth_direct_params(design::BayesianMGMFRM.FacetDesign, truth)
    return SmallMCMC.truth_direct_params(design, truth)
end

function score_probabilities_from_fixture_rows(fixture_rows, n_rows::Int)
    return SmallMCMC.score_probabilities_from_fixture_rows(fixture_rows, n_rows)
end

function generate_mgmfrm_source_rows(options, scenario)
    rng = MersenneTwister(options.seed + scenario.seed_offset)
    dummy_rows = SmallMCMC.full_cross_rows(options)
    dummy_spec = (model = :truth_source, family = :mgmfrm,
        q_field = :declared_q)
    dummy_scenario = merge(scenario, (; declared_q = scenario.true_q))
    dummy = design_for_rows(dummy_rows, dummy_spec, dummy_scenario)
    truth = truth_components(options, scenario, rng)
    direct = truth_direct_params(dummy.design, truth)
    fixture_rows =
        BayesianMGMFRM._mgmfrm_source_fixture_values(dummy.design, direct)
    probs = score_probabilities_from_fixture_rows(fixture_rows,
        length(dummy_rows))
    scores = [SmallMCMC.sample_category(rng, probs[row])
        for row in eachindex(dummy_rows)]
    rows = SmallMCMC.full_cross_rows(options; scores)
    return (; rows, truth, direct_params = direct, truth_available = true)
end

function generate_null_rows(options, scenario)
    rng = MersenneTwister(options.seed + scenario.seed_offset)
    dummy_rows = SmallMCMC.full_cross_rows(options)
    probs = [0.34, 0.33, 0.33]
    scores = [SmallMCMC.sample_category(rng, probs)
        for _ in eachindex(dummy_rows)]
    rows = SmallMCMC.full_cross_rows(options; scores)
    return (; rows, truth = missing, direct_params = Float64[],
        truth_available = false)
end

function generate_rows(options, scenario)
    scenario.generator === :null_uniform &&
        return generate_null_rows(options, scenario)
    scenario.generator === :mgmfrm_source &&
        return generate_mgmfrm_source_rows(options, scenario)
    error("unknown generator: $(scenario.generator)")
end

function fit_options(options, scenario)
    return merge(options, (;
        seed = options.seed + scenario.seed_offset,
        ability_scale = scenario.ability_scale,
        item_discrimination_scale = scenario.item_discrimination_scale,
        rater_severity_scale = scenario.rater_severity_scale,
        rater_consistency_spread = scenario.rater_consistency_spread,
        item_step = scenario.item_step,
    ))
end

function score_oracle(full_rows, generated, scenario, heldout_indices)
    generated.truth_available || return nothing
    model_spec = (model = :truth_q_source_oracle, family = :mgmfrm,
        q_field = :declared_q)
    truth_scenario = merge(scenario, (; declared_q = scenario.true_q))
    full = design_for_rows(full_rows, model_spec, truth_scenario)
    direct = truth_direct_params(full.design, generated.truth)
    scored = SmallMCMC.score_direct_draws(:truth_q_source_oracle, full.design,
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

function model_seed_offset(model::Symbol)
    model === :declared_q_mgmfrm_mcmc && return 101
    model === :candidate_q_mgmfrm_mcmc && return 203
    model === :rotated_wrong_q_mgmfrm_mcmc && return 251
    model === :scalar_gmfrm_mcmc && return 307
    return 409
end

function fit_model(model_spec, scenario, train_rows, full_rows,
        heldout_indices, options)
    started = time_ns()
    train = design_for_rows(train_rows, model_spec, scenario)
    full = design_for_rows(full_rows, model_spec, scenario)
    layout_matches = train.design.parameter_names == full.design.parameter_names
    fit = BayesianMGMFRM.fit(train.spec;
        experimental = true,
        prior = SmallMCMC.source_prior(options.prior_profile),
        backend = :advancedhmc,
        ndraws = options.draws_per_chain,
        warmup = options.warmup_per_chain,
        chains = options.chains,
        seed = options.seed + scenario.seed_offset +
               model_seed_offset(model_spec.model),
        target_accept = options.target_acceptance,
        progress = options.progress,
    )
    scored = SmallMCMC.score_direct_draws(model_spec.model, full.design,
        fit.direct_draws, heldout_indices)
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

function failed_fit_row(model_spec, err, options, train_rows, heldout_indices)
    return (;
        model = model_spec.model,
        model_family = model_spec.family,
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

function score_models(full_rows, train_rows, heldout_indices, generated,
        scenario, options)
    fit_rows = NamedTuple[]
    pointwise_rows = NamedTuple[]
    oracle = score_oracle(full_rows, generated, scenario, heldout_indices)
    if oracle !== nothing
        push!(fit_rows, oracle.fit_row)
        append!(pointwise_rows, oracle.pointwise_rows)
    end
    for spec in MCMC_MODEL_SPECS
        try
            result = fit_model(spec, scenario, train_rows, full_rows,
                heldout_indices, options)
            push!(fit_rows, result.fit_row)
            append!(pointwise_rows, result.pointwise_rows)
        catch err
            push!(fit_rows, failed_fit_row(spec, err, options, train_rows,
                heldout_indices))
        end
    end
    for model in (:item_rater_reference, :null_or_intercept_reference)
        result = SmallMCMC.score_reference(model, train_rows, full_rows,
            heldout_indices)
        push!(fit_rows, result.fit_row)
        append!(pointwise_rows, result.pointwise_rows)
    end
    return (; fit_rows, pointwise_rows)
end

function ranked_rows(fit_rows)
    finite_rows = [row for row in fit_rows if isfinite(Float64(row.heldout_elpd))]
    ranked = sort(finite_rows; by = row -> Float64(row.heldout_elpd), rev = true)
    rank_by_model = Dict(row.model => index for (index, row) in pairs(ranked))
    return [merge(row, (rank = get(rank_by_model, row.model, missing),))
        for row in fit_rows]
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
    for row in rows
        row.model === :null_or_intercept_reference && continue
        if isfinite(Float64(row.heldout_elpd))
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
    return output
end

function comparison_value(rows, model::Symbol)
    matches = [row for row in rows if row.model === model]
    isempty(matches) && return NaN
    return Float64(only(matches).delta_elpd)
end

function model_delta(rows, lhs::Symbol, rhs::Symbol)
    lhs_row = row_by_model(rows, lhs)
    rhs_row = row_by_model(rows, rhs)
    lhs_row === nothing && return NaN
    rhs_row === nothing && return NaN
    isfinite(Float64(lhs_row.heldout_elpd)) || return NaN
    isfinite(Float64(rhs_row.heldout_elpd)) || return NaN
    return Float64(lhs_row.heldout_elpd - rhs_row.heldout_elpd)
end

function scenario_cell_row(options, scenario, split, rows, comparisons)
    finite = [row for row in rows if isfinite(Float64(row.heldout_elpd))]
    leader = isempty(finite) ? nothing :
        first(sort(finite; by = row -> Float64(row.heldout_elpd), rev = true))
    return (;
        seed = options.seed + scenario.seed_offset,
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
        declared_delta_elpd_vs_null =
            round3(comparison_value(comparisons, :declared_q_mgmfrm_mcmc)),
        candidate_delta_elpd_vs_null =
            round3(comparison_value(comparisons, :candidate_q_mgmfrm_mcmc)),
        rotated_wrong_delta_elpd_vs_null =
            round3(comparison_value(comparisons,
                :rotated_wrong_q_mgmfrm_mcmc)),
        scalar_delta_elpd_vs_null =
            round3(comparison_value(comparisons, :scalar_gmfrm_mcmc)),
        candidate_minus_declared_elpd =
            round3(model_delta(rows, :candidate_q_mgmfrm_mcmc,
                :declared_q_mgmfrm_mcmc)),
        declared_minus_scalar_elpd =
            round3(model_delta(rows, :declared_q_mgmfrm_mcmc,
                :scalar_gmfrm_mcmc)),
        candidate_minus_scalar_elpd =
            round3(model_delta(rows, :candidate_q_mgmfrm_mcmc,
                :scalar_gmfrm_mcmc)),
        public_claim_allowed = false,
    )
end

function risk_label(row, threshold)
    declared_pass = row.declared_delta_elpd_vs_null >= threshold
    candidate_pass = row.candidate_delta_elpd_vs_null >= threshold
    scalar_pass = row.scalar_delta_elpd_vs_null >= threshold
    if row.axis in (:explicit_null, :false_add, :q_misspecification_rater_noise)
        candidate_pass && return :candidate_false_promotion_risk
        declared_pass && return :declared_model_false_promotion_risk
        scalar_pass && return :scalar_reference_screening_pass
        return :specificity_not_failed
    elseif row.axis === :false_drop
        candidate_pass || return :candidate_false_negative_risk
        row.candidate_minus_declared_elpd <= 0 &&
            return :candidate_does_not_improve_over_declared
        return :candidate_power_observed
    elseif row.axis === :weak_dimension
        declared_pass || return :weak_dimension_false_negative_risk
        return :weak_dimension_screening_pass
    end
    return :manual_review_required
end

function threshold_rows(cell_rows, thresholds)
    rows = NamedTuple[]
    for row in cell_rows, threshold in thresholds
        push!(rows, (;
            seed = row.seed,
            prior_profile = row.prior_profile,
            scenario = row.scenario,
            axis = row.axis,
            threshold = round3(threshold),
            declared_passed = row.declared_delta_elpd_vs_null >= threshold,
            candidate_passed = row.candidate_delta_elpd_vs_null >= threshold,
            rotated_wrong_passed =
                row.rotated_wrong_delta_elpd_vs_null >= threshold,
            scalar_passed = row.scalar_delta_elpd_vs_null >= threshold,
            candidate_minus_declared_elpd = row.candidate_minus_declared_elpd,
            risk_interpretation = risk_label(row, threshold),
            public_claim_allowed = false,
        ))
    end
    return rows
end

function scenario_simulation_cell(options, scenario)
    fitopts = fit_options(options, scenario)
    generated = generate_rows(fitopts, scenario)
    split = SmallMCMC.split_rows(generated.rows, fitopts)
    scored = score_models(generated.rows, split.train_rows,
        split.heldout_indices, generated, scenario, fitopts)
    ranked = ranked_rows(scored.fit_rows)
    comparisons = comparison_rows(ranked)
    cell = scenario_cell_row(fitopts, scenario, split, ranked, comparisons)
    return (;
        cell_row = cell,
        model_rows = [merge(row, (;
            seed = fitopts.seed,
            prior_profile = fitopts.prior_profile,
            scenario = scenario.name,
            axis = scenario.axis,
            public_claim_allowed = false,
        )) for row in ranked],
        comparison_rows = [merge(row, (;
            seed = fitopts.seed,
            prior_profile = fitopts.prior_profile,
            scenario = scenario.name,
            axis = scenario.axis,
            public_claim_allowed = false,
        )) for row in comparisons],
        pointwise_rows = [merge(row, (;
            seed = fitopts.seed,
            prior_profile = fitopts.prior_profile,
            scenario = scenario.name,
            axis = scenario.axis,
            public_claim_allowed = false,
        )) for row in scored.pointwise_rows],
    )
end

function threshold_summary_rows(thresholds)
    rows = NamedTuple[]
    for threshold in sort(unique(row.threshold for row in thresholds))
        group = [row for row in thresholds if row.threshold == threshold]
        push!(rows, (;
            threshold,
            n_cells = length(group),
            n_candidate_false_promotion_risk =
                count(row -> row.risk_interpretation ===
                    :candidate_false_promotion_risk, group),
            n_declared_false_promotion_risk =
                count(row -> row.risk_interpretation ===
                    :declared_model_false_promotion_risk, group),
            n_candidate_false_negative_risk =
                count(row -> row.risk_interpretation in
                    (:candidate_false_negative_risk,
                     :weak_dimension_false_negative_risk), group),
            n_candidate_power_observed =
                count(row -> row.risk_interpretation ===
                    :candidate_power_observed, group),
            public_claim_allowed = false,
        ))
    end
    return rows
end

function finding_rows(cell_rows, threshold_summary, model_rows)
    threshold2 = first(row for row in threshold_summary if row.threshold == 2.0)
    threshold4 = first(row for row in threshold_summary if row.threshold == 4.0)
    false_add = [row for row in cell_rows if row.axis === :false_add]
    false_drop = [row for row in cell_rows if row.axis === :false_drop]
    explicit_null = [row for row in cell_rows if row.axis === :explicit_null]
    mcmc_warning_rows = [row for row in model_rows
        if row.model in (:declared_q_mgmfrm_mcmc,
            :candidate_q_mgmfrm_mcmc,
            :rotated_wrong_q_mgmfrm_mcmc,
            :scalar_gmfrm_mcmc) &&
           row.sampler_flag !== :ok]
    return [
        (finding = :q_misspecification_mcmc_batch_recorded,
            severity = :info,
            evidence = string(length(cell_rows), " scenario cell(s) recorded"),
            implication =
                :pre_execution_map_now_has_small_mcmc_evidence),
        (finding = :short_chain_sampler_warning,
            severity = isempty(mcmc_warning_rows) ? :info : :warning,
            evidence = string(length(mcmc_warning_rows),
                " MCMC model row(s) have non-ok sampler flags"),
            implication =
                :replicate_with_larger_chains_before_public_threshold_policy),
        (finding = :threshold_2_specificity_check,
            severity = threshold2.n_candidate_false_promotion_risk == 0 ?
                :info : :warning,
            evidence = string("threshold 2 candidate false-promotion cells = ",
                threshold2.n_candidate_false_promotion_risk),
            implication =
                :low_threshold_screening_requires_specificity_controls),
        (finding = :threshold_4_power_check,
            severity = threshold4.n_candidate_false_negative_risk == 0 ?
                :info : :warning,
            evidence = string("threshold 4 candidate false-negative cells = ",
                threshold4.n_candidate_false_negative_risk),
            implication =
                :strict_thresholds_require_false_drop_and_weak_dimension_power_checks),
        (finding = :false_add_candidate_margin,
            severity = isempty(false_add) ? :warning :
                only(false_add).candidate_minus_declared_elpd <= 0 ?
                :info : :warning,
            evidence = isempty(false_add) ? "missing" :
                string("candidate - declared dELPD = ",
                    only(false_add).candidate_minus_declared_elpd),
            implication =
                :extra_loading_candidate_should_not_be_accepted_without_q_review),
        (finding = :false_drop_candidate_margin,
            severity = isempty(false_drop) ? :warning :
                only(false_drop).candidate_minus_declared_elpd > 0 ?
                :info : :warning,
            evidence = isempty(false_drop) ? "missing" :
                string("candidate - declared dELPD = ",
                    only(false_drop).candidate_minus_declared_elpd),
            implication =
                :missing_loading_power_depends_on_candidate_margin),
        (finding = :explicit_null_check,
            severity = isempty(explicit_null) ? :warning :
                only(explicit_null).candidate_delta_elpd_vs_null <= 0 ?
                :info : :warning,
            evidence = isempty(explicit_null) ? "missing" :
                string("candidate dELPD vs Null = ",
                    only(explicit_null).candidate_delta_elpd_vs_null),
            implication =
                :null_false_alarm_checks_must_remain_part_of_threshold_policy),
        (finding = :public_claims_blocked,
            severity = :blocker,
            evidence = "local small-MCMC Q-misspecification simulation only",
            implication =
                :do_not_claim_public_fit_thresholds_model_weights_or_q_revisions),
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
        println(io, "# Uto-Style Q-Misspecification MCMC Simulations")
        println(io)
        println(io, "- Generated at: `", artifact.generated_at, "`")
        println(io, "- Local only: `true`")
        println(io, "- Public claims allowed: `false`")
        println(io)
        println(io, "## Interpretation")
        println(io)
        println(io,
            "This report runs a small MCMC batch for explicit-null, false-add, ",
            "false-drop, weak-dimension, and rater-noise/Q-misspecification proxy ",
            "scenarios. It is still local diagnostic evidence; thresholds remain ",
            "screening profiles.")
        println(io)
        println(io, "## Findings")
        table(io, ["Finding", "Severity", "Evidence", "Implication"],
            [[row.finding, row.severity, row.evidence, row.implication]
             for row in artifact.finding_rows])
        println(io, "## Scenario Cells")
        table(io, ["Scenario", "Axis", "Best", "Declared dELPD",
                "Candidate dELPD", "Wrong dELPD", "Scalar dELPD",
                "Candidate-Declared", "Candidate-Scalar"],
            [[row.scenario, row.axis, row.observed_best_model,
                row.declared_delta_elpd_vs_null,
                row.candidate_delta_elpd_vs_null,
                row.rotated_wrong_delta_elpd_vs_null,
                row.scalar_delta_elpd_vs_null,
                row.candidate_minus_declared_elpd,
                row.candidate_minus_scalar_elpd]
             for row in artifact.scenario_cell_rows])
        println(io, "## Threshold Summary")
        table(io, ["Threshold", "Cells", "Candidate False Promotion",
                "Declared False Promotion", "False Negative", "Power Observed"],
            [Any[row.threshold, row.n_cells,
                row.n_candidate_false_promotion_risk,
                row.n_declared_false_promotion_risk,
                row.n_candidate_false_negative_risk,
                row.n_candidate_power_observed]
             for row in artifact.threshold_summary_rows])
        println(io, "## Threshold Rows")
        table(io, ["Scenario", "Axis", "Threshold", "Declared",
                "Candidate", "Wrong", "Scalar", "Candidate-Declared", "Risk"],
            [[row.scenario, row.axis, row.threshold, row.declared_passed,
                row.candidate_passed, row.rotated_wrong_passed,
                row.scalar_passed, row.candidate_minus_declared_elpd,
                row.risk_interpretation]
             for row in artifact.threshold_rows])
        println(io, "## Model Scores")
        table(io, ["Scenario", "Model", "Rank", "ELPD", "MAE",
                "Sampler", "Draws"],
            [[row.scenario, row.model, row.rank, round3(row.heldout_elpd),
                round3(row.heldout_expected_score_mae), row.sampler_flag,
                row.n_draws]
             for row in artifact.model_score_rows])
        println(io, "## Boundary")
        println(io)
        println(io,
            "This small batch is not publication-grade. It uses short chains and ",
            "small generated data to identify which threshold/Q failure modes need ",
            "replication, larger MCMC budgets, and category-calibration joins.")
    end
    return path
end

function build_artifact(options)
    expansion = JSON3.read(read(options.expansion_json, String))
    cell_rows = NamedTuple[]
    model_rows = NamedTuple[]
    comparison_rows_all = NamedTuple[]
    pointwise_rows = NamedTuple[]
    for scenario in options.scenarios
        cell = scenario_simulation_cell(options, scenario)
        push!(cell_rows, cell.cell_row)
        append!(model_rows, cell.model_rows)
        append!(comparison_rows_all, cell.comparison_rows)
        append!(pointwise_rows, cell.pointwise_rows)
    end
    thresholds = threshold_rows(cell_rows, options.thresholds)
    threshold_summary = threshold_summary_rows(thresholds)
    findings = finding_rows(cell_rows, threshold_summary, model_rows)
    mcmc_warning_rows = [row for row in model_rows
        if row.model in (:declared_q_mgmfrm_mcmc,
            :candidate_q_mgmfrm_mcmc,
            :rotated_wrong_q_mgmfrm_mcmc,
            :scalar_gmfrm_mcmc) &&
           row.sampler_flag !== :ok]
    return (;
        schema = OUTPUT_SCHEMA,
        family = :mgmfrm,
        scope = :uto_style_q_misspecification_mcmc_simulations,
        status = :local_q_misspecification_mcmc_simulations_recorded,
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
        input_artifacts = [
            (artifact = :threshold_q_misspecification_expansion,
                path = rel(options.expansion_json),
                schema = String(expansion.schema),
                sha256 = file_sha256(options.expansion_json),
                summary_passed = Bool(expansion.summary.passed)),
        ],
        design = (;
            scenarios = [scenario.name for scenario in options.scenarios],
            thresholds = options.thresholds,
            n_persons = options.n_persons,
            n_items = options.n_items,
            n_raters = options.n_raters,
            heldout_fraction = options.heldout_fraction,
            q_base = q_rows(Q_BASE),
            q_false_add = q_rows(Q_FALSE_ADD),
            q_rotated_wrong = q_rows(Q_ROTATED_WRONG),
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
        threshold_rows = thresholds,
        threshold_summary_rows = threshold_summary,
        pointwise_rows,
        finding_rows = findings,
        summary = (;
            passed = all(row.fit_succeeded for row in model_rows
                if row.model in (:declared_q_mgmfrm_mcmc,
                    :candidate_q_mgmfrm_mcmc,
                    :rotated_wrong_q_mgmfrm_mcmc,
                    :scalar_gmfrm_mcmc)),
            n_scenarios = length(cell_rows),
            n_model_score_rows = length(model_rows),
            n_threshold_rows = length(thresholds),
            threshold_2_candidate_false_promotion_cells =
                first(row.n_candidate_false_promotion_risk
                    for row in threshold_summary if row.threshold == 2.0),
            threshold_4_false_negative_cells =
                first(row.n_candidate_false_negative_risk
                    for row in threshold_summary if row.threshold == 4.0),
            n_mcmc_warning_rows = length(mcmc_warning_rows),
            no_public_fit_metric_claim = true,
            no_public_q_revision_claim = true,
            no_automatic_q_revision = true,
            no_public_model_weight_claim = true,
            no_sparse_superiority_claim = true,
            next_gate =
                :replicate_q_misspecification_mcmc_and_join_category_calibration,
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
    println("scenarios=", artifact.summary.n_scenarios,
        " threshold_2_false_promotion=",
        artifact.summary.threshold_2_candidate_false_promotion_cells,
        " threshold_4_false_negative=",
        artifact.summary.threshold_4_false_negative_cells,
        " next_gate=", artifact.summary.next_gate)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
