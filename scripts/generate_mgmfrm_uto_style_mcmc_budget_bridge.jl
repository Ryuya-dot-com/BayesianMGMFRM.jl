#!/usr/bin/env julia

using Dates
using SHA
using Statistics
using TOML

import BayesianMGMFRM

module Bridge
include(joinpath(@__DIR__, "generate_mgmfrm_uto_style_calibration_bridge.jl"))
end

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT_JSON =
    joinpath(ROOT, "artifacts", "uto_style_mcmc_budget_bridge",
        "uto_style_mcmc_budget_bridge.json")
const DEFAULT_OUTPUT_MD =
    joinpath(ROOT, "artifacts", "uto_style_mcmc_budget_bridge",
        "uto_style_mcmc_budget_bridge.md")

include(joinpath(@__DIR__, "local_json.jl"))

const OUTPUT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_uto_style_mcmc_budget_bridge.v1"
const DEFAULT_THRESHOLDS = Bridge.DEFAULT_THRESHOLDS
const DEFAULT_PROFILES = [:default]
const DEFAULT_THIN_STRIDES = [1, 2]

const BUDGET_LIBRARY = [
    (;
        name = :baseline_20_20,
        role = :current_bridge_reference_budget,
        chains = 2,
        warmup_per_chain = 20,
        draws_per_chain = 20,
        expected_effect = :reference,
    ),
    (;
        name = :long_warmup_80_20,
        role = :burnin_or_adaptation_probe,
        chains = 2,
        warmup_per_chain = 80,
        draws_per_chain = 20,
        expected_effect = :tests_warmup_without_more_retained_draws,
    ),
    (;
        name = :more_draws_20_80,
        role = :retained_draw_monte_carlo_probe,
        chains = 2,
        warmup_per_chain = 20,
        draws_per_chain = 80,
        expected_effect = :tests_more_retained_draws_without_longer_warmup,
    ),
    (;
        name = :increased_80_80,
        role = :larger_mcmc_budget_probe,
        chains = 2,
        warmup_per_chain = 80,
        draws_per_chain = 80,
        expected_effect = :tests_more_warmup_and_more_retained_draws,
    ),
]

function usage()
    return """
    Generate a local Uto-style MGMFRM MCMC-budget bridge.

    This reruns the calibration bridge on the same generated rows/splits while
    varying warmup and retained draws. Thinning is recorded as post-hoc
    retained-draw thinning for scoring sensitivity; the current fit API does
    not expose sampler-level thinning.

    Usage:
      julia --project=. scripts/generate_mgmfrm_uto_style_mcmc_budget_bridge.jl [options]

    Options:
      --output-json PATH       JSON artifact path.
      --output-md PATH         Markdown report path.
      --seeds LIST             Comma-separated base seeds. Default: 20260707.
      --profiles LIST          Comma-separated profiles. Default: default.
      --scenarios LIST         Comma-separated scenarios. Default: all bridge scenarios.
      --budget-profiles LIST   Comma-separated budgets. Default: all.
                               Choices: baseline_20_20, long_warmup_80_20,
                               more_draws_20_80, increased_80_80.
      --thresholds LIST        Comma-separated dELPD thresholds. Default: 0,2,4,8.
      --thin-strides LIST      Comma-separated post-hoc retained-draw strides.
                               Default: 1,2. Stride 1 is unthinned.
      --n-persons N            Number of persons. Default: 8.
      --n-raters N             Number of raters. Default: 3.
      --heldout-fraction X     Observation holdout fraction. Default: 0.17.
      --target-acceptance X    NUTS target acceptance. Default: 0.8.
      --progress               Show sampler progress.
    """
end

function parse_seed_list(text::AbstractString)
    seeds = Int[]
    for part in split(text, ",")
        stripped = strip(part)
        isempty(stripped) && continue
        push!(seeds, parse(Int, stripped))
    end
    isempty(seeds) && error("--seeds must contain at least one integer")
    length(unique(seeds)) == length(seeds) ||
        error("--seeds must be unique")
    return seeds
end

function parse_profile_list(text::AbstractString)
    profiles = Symbol[]
    for part in split(text, ",")
        stripped = strip(part)
        isempty(stripped) && continue
        profile = Symbol(stripped)
        profile in (:default, :tight, :diffuse) ||
            error("profile must be one of default, tight, diffuse")
        push!(profiles, profile)
    end
    isempty(profiles) && error("--profiles must contain at least one profile")
    length(unique(profiles)) == length(profiles) ||
        error("--profiles must be unique")
    return profiles
end

function parse_positive_int_list(text::AbstractString, option::AbstractString)
    values = Int[]
    for part in split(text, ",")
        stripped = strip(part)
        isempty(stripped) && continue
        value = parse(Int, stripped)
        value >= 1 || error("$option values must be positive")
        push!(values, value)
    end
    isempty(values) && error("$option must contain at least one value")
    length(unique(values)) == length(values) ||
        error("$option values must be unique")
    return sort(values)
end

function budget_by_name(name::Symbol)
    matches = [budget for budget in BUDGET_LIBRARY if budget.name === name]
    isempty(matches) && error("unknown budget profile: $name")
    return only(matches)
end

function parse_args(args)
    output_json = DEFAULT_OUTPUT_JSON
    output_md = DEFAULT_OUTPUT_MD
    seeds = [20260707]
    profiles = copy(DEFAULT_PROFILES)
    scenario_names = [scenario.name for scenario in Bridge.SCENARIO_LIBRARY]
    budget_names = [budget.name for budget in BUDGET_LIBRARY]
    thresholds = copy(DEFAULT_THRESHOLDS)
    thin_strides = copy(DEFAULT_THIN_STRIDES)
    n_persons = 8
    n_raters = 3
    heldout_fraction = 0.17
    target_acceptance = 0.8
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
        elseif arg == "--seeds"
            index < length(args) || error("--seeds requires a comma list")
            seeds = parse_seed_list(args[index + 1])
            index += 2
        elseif arg == "--profiles"
            index < length(args) || error("--profiles requires a comma list")
            profiles = parse_profile_list(args[index + 1])
            index += 2
        elseif arg == "--scenarios"
            index < length(args) || error("--scenarios requires a comma list")
            scenario_names = Bridge.parse_symbol_list(args[index + 1])
            index += 2
        elseif arg == "--budget-profiles"
            index < length(args) ||
                error("--budget-profiles requires a comma list")
            budget_names = Bridge.parse_symbol_list(args[index + 1])
            index += 2
        elseif arg == "--thresholds"
            index < length(args) || error("--thresholds requires a comma list")
            thresholds = Bridge.parse_thresholds(args[index + 1])
            index += 2
        elseif arg == "--thin-strides"
            index < length(args) ||
                error("--thin-strides requires a comma list")
            thin_strides =
                parse_positive_int_list(args[index + 1], "--thin-strides")
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
        elseif arg == "--target-acceptance"
            index < length(args) ||
                error("--target-acceptance requires a number")
            target_acceptance = parse(Float64, args[index + 1])
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
    0 < target_acceptance < 1 ||
        error("--target-acceptance must be in (0, 1)")
    scenarios = [Bridge.scenario_by_name(name) for name in scenario_names]
    budgets = [budget_by_name(name) for name in budget_names]
    return (;
        output_json,
        output_md,
        seeds,
        profiles,
        scenarios,
        budgets,
        thresholds,
        thin_strides,
        n_persons,
        n_items = size(Bridge.SmallMCMC.Q_TRUE, 1),
        n_raters,
        heldout_fraction,
        target_acceptance,
        progress,
    )
end

project_version() =
    String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])
file_sha256(path::AbstractString) = bytes2hex(open(sha256, path))
rel(path::AbstractString) = relpath(path, ROOT)
round3(value) = round(Float64(value); digits = 3)
round4(value) = round(Float64(value); digits = 4)

function generation_options(options, seed::Int, profile::Symbol, scenario)
    return (;
        output_json = "",
        output_md = "",
        n_persons = options.n_persons,
        n_items = options.n_items,
        n_raters = options.n_raters,
        heldout_fraction = options.heldout_fraction,
        chains = 1,
        warmup_per_chain = 0,
        draws_per_chain = 1,
        target_acceptance = options.target_acceptance,
        prior_profile = profile,
        seed = seed + scenario.seed_offset,
        progress = false,
        ability_scale = scenario.ability_scale,
        item_discrimination_scale = scenario.item_discrimination_scale,
        rater_severity_scale = scenario.rater_severity_scale,
        rater_consistency_spread = scenario.rater_consistency_spread,
        item_step = scenario.item_step,
    )
end

function fit_options(options, seed::Int, profile::Symbol, scenario, budget)
    return (;
        output_json = "",
        output_md = "",
        n_persons = options.n_persons,
        n_items = options.n_items,
        n_raters = options.n_raters,
        heldout_fraction = options.heldout_fraction,
        chains = budget.chains,
        warmup_per_chain = budget.warmup_per_chain,
        draws_per_chain = budget.draws_per_chain,
        target_acceptance = options.target_acceptance,
        prior_profile = profile,
        seed = seed + scenario.seed_offset,
        progress = options.progress,
    )
end

function scoring_variant(thin_stride::Int)
    thin_stride == 1 && return :all_retained_draws
    return Symbol("posthoc_thin_", thin_stride)
end

function thinned_draws(draws::AbstractMatrix, thin_stride::Int)
    thin_stride == 1 && return draws
    indices = collect(1:thin_stride:size(draws, 1))
    isempty(indices) && error("thin stride left no draws")
    return draws[indices, :]
end

function context_tuple(seed::Int, profile::Symbol, scenario, budget,
        thin_stride::Int)
    return (;
        seed,
        prior_profile = profile,
        scenario = scenario.name,
        budget_profile = budget.name,
        budget_role = budget.role,
        chains = budget.chains,
        warmup_per_chain = budget.warmup_per_chain,
        draws_per_chain = budget.draws_per_chain,
        thin_stride,
        scoring_variant = scoring_variant(thin_stride),
        public_claim_allowed = false,
    )
end

function add_context(row, seed::Int, profile::Symbol, scenario, budget,
        thin_stride::Int)
    return merge(row, context_tuple(seed, profile, scenario, budget, thin_stride))
end

function static_score_rows(full_rows, train_rows, heldout_indices, truth)
    rows = NamedTuple[]
    oracle = Bridge.SmallMCMC.score_oracle(full_rows, truth, heldout_indices)
    push!(rows, oracle.fit_row)
    item_rater = Bridge.SmallMCMC.score_reference(
        :item_rater_reference,
        train_rows,
        full_rows,
        heldout_indices,
    )
    push!(rows, item_rater.fit_row)
    null = Bridge.SmallMCMC.score_reference(
        :null_or_intercept_reference,
        train_rows,
        full_rows,
        heldout_indices,
    )
    push!(rows, null.fit_row)
    return rows
end

function fit_model_score_rows(model::Symbol, train_rows, full_rows,
        heldout_indices, fitopts, thin_strides)
    started = time_ns()
    train = Bridge.SmallMCMC.design_for_rows(train_rows, model)
    full = Bridge.SmallMCMC.design_for_rows(full_rows, model)
    layout_matches = train.design.parameter_names == full.design.parameter_names
    fit = BayesianMGMFRM.fit(train.spec;
        experimental = true,
        prior = Bridge.SmallMCMC.source_prior(fitopts.prior_profile),
        backend = :advancedhmc,
        ndraws = fitopts.draws_per_chain,
        warmup = fitopts.warmup_per_chain,
        chains = fitopts.chains,
        seed = fitopts.seed + Bridge.SmallMCMC.model_seed_offset(model),
        target_accept = fitopts.target_acceptance,
        progress = fitopts.progress,
    )
    elapsed_seconds = (time_ns() - started) / 1e9
    summary = fit.diagnostic_surface.summary
    output = NamedTuple[]
    for thin_stride in thin_strides
        direct = thinned_draws(fit.direct_draws, thin_stride)
        scored = Bridge.SmallMCMC.score_direct_draws(
            model,
            full.design,
            direct,
            heldout_indices,
        )
        push!(output, merge(scored.score, (;
            model_family = fit.design.spec.family,
            fit_succeeded = true,
            returned_type = Symbol(nameof(typeof(fit))),
            layout_matches,
            n_train_observations = length(train_rows),
            n_raw_parameters = size(fit.draws, 2),
            n_direct_parameters = size(fit.direct_draws, 2),
            n_draws = size(direct, 1),
            unthinned_n_draws = size(fit.direct_draws, 1),
            chains = fitopts.chains,
            warmup_per_chain = fitopts.warmup_per_chain,
            draws_per_chain = fitopts.draws_per_chain,
            sampler = fit.sampler,
            backend = fit.backend,
            sampler_flag = summary.flag,
            n_sampler_warnings = Int(summary.n_sampler_warnings),
            n_nonfinite_logdensity = Int(summary.n_nonfinite_logdensity),
            n_failed_direct_constraints =
                Int(summary.n_failed_direct_constraints),
            elapsed_seconds = round3(elapsed_seconds),
            thin_stride,
            scoring_variant = scoring_variant(thin_stride),
        )))
    end
    return output
end

function failed_model_score_rows(model::Symbol, err, fitopts, train_rows,
        heldout_indices, thin_strides)
    return [(;
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
        unthinned_n_draws = 0,
        chains = fitopts.chains,
        warmup_per_chain = fitopts.warmup_per_chain,
        draws_per_chain = fitopts.draws_per_chain,
        sampler = :nuts,
        backend = :advancedhmc,
        sampler_flag = :fit_failed,
        n_sampler_warnings = missing,
        n_nonfinite_logdensity = missing,
        n_failed_direct_constraints = missing,
        elapsed_seconds = missing,
        error = sprint(showerror, err),
        thin_stride,
        scoring_variant = scoring_variant(thin_stride),
        public_claim_allowed = false,
    ) for thin_stride in thin_strides]
end

function fit_mcmc_rows(train_rows, full_rows, heldout_indices, fitopts,
        thin_strides)
    rows = NamedTuple[]
    for model in Bridge.SmallMCMC.MCMC_MODELS
        try
            append!(rows, fit_model_score_rows(model, train_rows, full_rows,
                heldout_indices, fitopts, thin_strides))
        catch err
            append!(rows, failed_model_score_rows(model, err, fitopts,
                train_rows, heldout_indices, thin_strides))
        end
    end
    return rows
end

function ranked_group(rows)
    finite_rows = [row for row in rows if isfinite(Float64(row.heldout_elpd))]
    ranked = sort(finite_rows; by = row -> Float64(row.heldout_elpd), rev = true)
    rank_by_model = Dict(row.model => index for (index, row) in pairs(ranked))
    return [merge(row, (rank = get(rank_by_model, row.model, missing),))
        for row in rows]
end

function row_by_model(rows, model::Symbol)
    matches = [row for row in rows if row.model === model]
    isempty(matches) && return nothing
    return only(matches)
end

function comparison_rows(rows)
    null = row_by_model(rows, :null_or_intercept_reference)
    oracle = row_by_model(rows, :true_q_source_oracle)
    true_mcmc = row_by_model(rows, :true_q_mgmfrm_mcmc)
    output = NamedTuple[]
    for row in rows
        row.model === :null_or_intercept_reference && continue
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

function comparison_value(rows, comparison::Symbol, field::Symbol)
    matches = [row for row in rows if row.comparison === comparison]
    isempty(matches) && return NaN
    return Float64(getproperty(only(matches), field))
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

function scenario_cell_row(seed::Int, profile::Symbol, scenario, budget,
        thin_stride::Int, rows, comparisons)
    true_q = row_by_model(rows, :true_q_mgmfrm_mcmc)
    null = row_by_model(rows, :null_or_intercept_reference)
    finite = [row for row in rows if isfinite(Float64(row.heldout_elpd))]
    leader = isempty(finite) ? nothing :
        first(sort(finite; by = row -> Float64(row.heldout_elpd), rev = true))
    true_delta = comparison_value(comparisons,
        :true_q_mgmfrm_mcmc_minus_null, :delta_elpd)
    oracle_delta = comparison_value(comparisons,
        :true_q_source_oracle_minus_null, :delta_elpd)
    mcmc_loss = comparison_value(comparisons,
        :true_q_mgmfrm_mcmc_minus_true_q_source_oracle, :delta_elpd)
    return (;
        context_tuple(seed, profile, scenario, budget, thin_stride)...,
        n_heldout_observations =
            null === nothing ? missing : null.n_heldout_observations,
        observed_best_model = leader === nothing ? :missing : leader.model,
        true_q_direction_recovered =
            true_q !== nothing && null !== nothing &&
            isfinite(Float64(true_q.heldout_elpd)) &&
            true_q.heldout_elpd > null.heldout_elpd,
        oracle_delta_elpd_vs_null = round3(oracle_delta),
        true_q_mcmc_delta_elpd_vs_null = round3(true_delta),
        true_q_mcmc_delta_elpd_vs_oracle = round3(mcmc_loss),
        wrong_q_delta_elpd_vs_null = round3(comparison_value(comparisons,
            :wrong_q_mgmfrm_mcmc_minus_null, :delta_elpd)),
        scalar_delta_elpd_vs_null = round3(comparison_value(comparisons,
            :scalar_gmfrm_mcmc_minus_null, :delta_elpd)),
        true_q_minus_wrong_q_elpd =
            round3(model_delta(rows, :true_q_mgmfrm_mcmc,
                :wrong_q_mgmfrm_mcmc)),
        true_q_minus_scalar_elpd =
            round3(model_delta(rows, :true_q_mgmfrm_mcmc,
                :scalar_gmfrm_mcmc)),
        oracle_to_mcmc_loss_abs = round3(oracle_delta - true_delta),
        oracle_positive_mcmc_nonpositive =
            isfinite(oracle_delta) && isfinite(true_delta) &&
            oracle_delta > 0 && true_delta <= 0,
        true_q_sampler_flag = true_q === nothing ? :missing :
            true_q.sampler_flag,
        true_q_scored_draws = true_q === nothing ? 0 : true_q.n_draws,
        true_q_unthinned_draws =
            true_q === nothing || !(:unthinned_n_draws in keys(true_q)) ?
            missing : true_q.unthinned_n_draws,
    )
end

function threshold_rows(cell_rows, thresholds)
    rows = NamedTuple[]
    for row in cell_rows, threshold in thresholds
        oracle_pass = row.oracle_delta_elpd_vs_null >= threshold
        mcmc_pass = row.true_q_mcmc_delta_elpd_vs_null >= threshold
        push!(rows, (;
            seed = row.seed,
            prior_profile = row.prior_profile,
            scenario = row.scenario,
            budget_profile = row.budget_profile,
            scoring_variant = row.scoring_variant,
            thin_stride = row.thin_stride,
            threshold = round3(threshold),
            metric = :delta_elpd_vs_null,
            oracle_true_q_passed = oracle_pass,
            mcmc_true_q_passed = mcmc_pass,
            scalar_passed = row.scalar_delta_elpd_vs_null >= threshold,
            wrong_q_passed = row.wrong_q_delta_elpd_vs_null >= threshold,
            decision_profile =
                oracle_pass && mcmc_pass ? :oracle_and_mcmc_clear :
                oracle_pass && !mcmc_pass ? :oracle_only :
                !oracle_pass && mcmc_pass ? :mcmc_only :
                :neither_clear,
            public_claim_allowed = false,
        ))
    end
    return rows
end

function finite_values(rows, field::Symbol)
    return [Float64(getproperty(row, field)) for row in rows
        if isfinite(Float64(getproperty(row, field)))]
end

function mean_round(rows, field::Symbol)
    values = finite_values(rows, field)
    isempty(values) && return NaN
    return round3(mean(values))
end

function min_round(rows, field::Symbol)
    values = finite_values(rows, field)
    isempty(values) && return NaN
    return round3(minimum(values))
end

function stability_rows(cell_rows)
    output = NamedTuple[]
    keys = sort(unique((row.budget_profile, row.scoring_variant, row.scenario)
        for row in cell_rows);
        by = key -> (string(key[1]), string(key[2]), string(key[3])))
    for (budget, variant, scenario) in keys
        group = [row for row in cell_rows
            if row.budget_profile === budget &&
               row.scoring_variant === variant &&
               row.scenario === scenario]
        n = length(group)
        push!(output, (;
            budget_profile = budget,
            scoring_variant = variant,
            scenario,
            n_cells = n,
            direction_recovery_rate =
                round4(count(row -> row.true_q_direction_recovered, group) / n),
            oracle_positive_mcmc_nonpositive_rate =
                round4(count(row -> row.oracle_positive_mcmc_nonpositive,
                    group) / n),
            mean_oracle_delta_elpd_vs_null =
                mean_round(group, :oracle_delta_elpd_vs_null),
            mean_true_q_mcmc_delta_elpd_vs_null =
                mean_round(group, :true_q_mcmc_delta_elpd_vs_null),
            min_true_q_mcmc_delta_elpd_vs_null =
                min_round(group, :true_q_mcmc_delta_elpd_vs_null),
            mean_oracle_to_mcmc_loss_abs =
                mean_round(group, :oracle_to_mcmc_loss_abs),
            min_true_q_minus_wrong_q_elpd =
                min_round(group, :true_q_minus_wrong_q_elpd),
            public_claim_allowed = false,
        ))
    end
    return output
end

function threshold_stability_rows(thresholds)
    output = NamedTuple[]
    keys = sort(unique((row.budget_profile, row.scoring_variant, row.scenario,
            row.threshold) for row in thresholds);
        by = key -> (string(key[1]), string(key[2]), string(key[3]), key[4]))
    for (budget, variant, scenario, threshold) in keys
        group = [row for row in thresholds
            if row.budget_profile === budget &&
               row.scoring_variant === variant &&
               row.scenario === scenario &&
               row.threshold == threshold]
        n = length(group)
        push!(output, (;
            budget_profile = budget,
            scoring_variant = variant,
            scenario,
            threshold,
            n_cells = n,
            oracle_pass_rate =
                round4(count(row -> row.oracle_true_q_passed, group) / n),
            mcmc_pass_rate =
                round4(count(row -> row.mcmc_true_q_passed, group) / n),
            scalar_pass_rate =
                round4(count(row -> row.scalar_passed, group) / n),
            wrong_q_pass_rate =
                round4(count(row -> row.wrong_q_passed, group) / n),
            oracle_only_rate =
                round4(count(row -> row.decision_profile === :oracle_only,
                    group) / n),
            public_claim_allowed = false,
        ))
    end
    return output
end

function row_key(row)
    return (row.seed, row.prior_profile, row.scenario, row.scoring_variant)
end

function budget_contrast_rows(cell_rows)
    baseline = Dict{Any,Any}()
    for row in cell_rows
        row.budget_profile === :baseline_20_20 || continue
        baseline[row_key(row)] = row
    end
    output = NamedTuple[]
    for row in cell_rows
        row.budget_profile === :baseline_20_20 && continue
        base = get(baseline, row_key(row), nothing)
        base === nothing && continue
        push!(output, (;
            seed = row.seed,
            prior_profile = row.prior_profile,
            scenario = row.scenario,
            scoring_variant = row.scoring_variant,
            baseline_budget = :baseline_20_20,
            budget_profile = row.budget_profile,
            baseline_true_q_delta_elpd_vs_null =
                base.true_q_mcmc_delta_elpd_vs_null,
            budget_true_q_delta_elpd_vs_null =
                row.true_q_mcmc_delta_elpd_vs_null,
            delta_from_baseline =
                round3(row.true_q_mcmc_delta_elpd_vs_null -
                       base.true_q_mcmc_delta_elpd_vs_null),
            direction_changed =
                row.true_q_direction_recovered !=
                base.true_q_direction_recovered,
            public_claim_allowed = false,
        ))
    end
    return output
end

function thinning_threshold_difference_rows(thresholds)
    output = NamedTuple[]
    keys = unique((row.seed, row.prior_profile, row.scenario,
        row.budget_profile, row.threshold) for row in thresholds)
    for key in keys
        all_rows = [row for row in thresholds
            if (row.seed, row.prior_profile, row.scenario,
                    row.budget_profile, row.threshold) == key &&
               row.scoring_variant === :all_retained_draws]
        thin_rows = [row for row in thresholds
            if (row.seed, row.prior_profile, row.scenario,
                    row.budget_profile, row.threshold) == key &&
               row.scoring_variant !== :all_retained_draws]
        isempty(all_rows) && continue
        all_row = only(all_rows)
        for thin_row in thin_rows
            all_row.mcmc_true_q_passed == thin_row.mcmc_true_q_passed &&
                continue
            push!(output, (;
                seed = all_row.seed,
                prior_profile = all_row.prior_profile,
                scenario = all_row.scenario,
                budget_profile = all_row.budget_profile,
                threshold = all_row.threshold,
                unthinned_passed = all_row.mcmc_true_q_passed,
                thinned_variant = thin_row.scoring_variant,
                thinned_passed = thin_row.mcmc_true_q_passed,
                public_claim_allowed = false,
            ))
        end
    end
    return output
end

function finding_rows(stability, threshold_stability, contrasts, thresholds)
    all_retained = [row for row in stability
        if row.scoring_variant === :all_retained_draws]
    strong = [row for row in all_retained
        if row.scenario === :strong_source_aligned]
    moderate = [row for row in all_retained
        if row.scenario === :moderate_transition]
    weak_t4 = [row for row in threshold_stability
        if row.scenario === :weak_compressed_category &&
           row.threshold == 4.0 &&
           row.scoring_variant === :all_retained_draws]
    changed = [row for row in contrasts if row.direction_changed]
    thinning_differences = thinning_threshold_difference_rows(thresholds)
    return [
        (finding = :warmup_and_draw_budget_recorded,
            severity = :info,
            evidence = string(length(unique(row.budget_profile
                for row in stability)), " budget profile(s) scored"),
            implication =
                :separates_warmup_adaptation_and_retained_draw_budget),
        (finding = :strong_anchor_budget_check,
            severity = all(row.direction_recovery_rate == 1.0
                for row in strong) ? :info : :warning,
            evidence = isempty(strong) ? "not run" :
                string("minimum mean true-Q dELPD across budgets = ",
                    round3(minimum(row.mean_true_q_mcmc_delta_elpd_vs_null
                        for row in strong))),
            implication =
                :checks_whether_uto_style_anchor_survives_larger_mcmc_budget),
        (finding = :moderate_boundary_budget_check,
            severity = any(row.direction_recovery_rate > 0.0
                for row in moderate) ? :warning : :info,
            evidence = isempty(moderate) ? "not run" :
                string("maximum mean true-Q dELPD across budgets = ",
                    round3(maximum(row.mean_true_q_mcmc_delta_elpd_vs_null
                        for row in moderate))),
            implication =
                :checks_whether_moderate_flip_is_resolved_by_more_mcmc),
        (finding = :weak_threshold_budget_check,
            severity = any(row.mcmc_pass_rate > 0.0 for row in weak_t4) ?
                :warning : :info,
            evidence = isempty(weak_t4) ? "not run" :
                string("max threshold-4 MCMC pass rate = ",
                    round4(maximum(row.mcmc_pass_rate for row in weak_t4))),
            implication =
                :checks_whether_higher_threshold_failure_is_budget_sensitive),
        (finding = :direction_change_from_baseline,
            severity = isempty(changed) ? :info : :warning,
            evidence = string(length(changed),
                " non-baseline cell(s) changed recovered/not-recovered status"),
            implication =
                :if_nonzero_inspect_budget_specific_sampler_diagnostics),
        (finding = :posthoc_thinning_threshold_difference,
            severity = isempty(thinning_differences) ? :info : :warning,
            evidence = string(length(thinning_differences),
                " threshold cell(s) changed MCMC pass status after post-hoc thinning"),
            implication =
                :near_cutoff_thresholds_are_sensitive_to_scoring_draw_subsampling),
        (finding = :thinning_is_posthoc_only,
            severity = :info,
            evidence = "fit API exposes warmup/draws/chains but not sampler-level thinning",
            implication =
                :thinning_rows_are_scoring_sensitivity_not_new_sampler_runs),
        (finding = :public_claims_blocked,
            severity = :blocker,
            evidence = "local MCMC-budget bridge only",
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
        println(io, "# Uto-Style MCMC-Budget Calibration Bridge")
        println(io)
        println(io, "- Generated at: `", artifact.generated_at, "`")
        println(io, "- Local only: `true`")
        println(io, "- Public claims allowed: `false`")
        println(io)
        println(io, "## Interpretation")
        println(io)
        println(io,
            "This report reruns the calibration bridge on the same generated ",
            "rows and observation splits while varying MCMC warmup and retained ",
            "draws. Thinning rows use post-hoc retained-draw subsampling for ",
            "scoring sensitivity; they are not sampler-level thinning.")
        println(io)
        println(io, "## Findings")
        table(io, ["Finding", "Severity", "Evidence", "Implication"],
            [[row.finding, row.severity, row.evidence, row.implication]
             for row in artifact.finding_rows])
        println(io, "## Budget Stability")
        table(io, ["Budget", "Variant", "Scenario", "Cells", "Recovery",
                "Oracle+/MCMC-", "Mean MCMC dELPD", "Min MCMC dELPD",
                "Mean Oracle-MCMC Loss", "Min True-Wrong"],
            [[row.budget_profile, row.scoring_variant, row.scenario,
                row.n_cells, row.direction_recovery_rate,
                row.oracle_positive_mcmc_nonpositive_rate,
                row.mean_true_q_mcmc_delta_elpd_vs_null,
                row.min_true_q_mcmc_delta_elpd_vs_null,
                row.mean_oracle_to_mcmc_loss_abs,
                row.min_true_q_minus_wrong_q_elpd]
             for row in artifact.stability_rows])
        println(io, "## Threshold Stability")
        table(io, ["Budget", "Variant", "Scenario", "Threshold",
                "Oracle Pass", "MCMC Pass", "Scalar Pass", "Wrong-Q Pass",
                "Oracle Only"],
            [[row.budget_profile, row.scoring_variant, row.scenario,
                row.threshold, row.oracle_pass_rate, row.mcmc_pass_rate,
                row.scalar_pass_rate, row.wrong_q_pass_rate,
                row.oracle_only_rate]
             for row in artifact.threshold_stability_rows])
        println(io, "## Budget Contrasts")
        table(io, ["Seed", "Profile", "Scenario", "Variant", "Budget",
                "Baseline dELPD", "Budget dELPD", "Delta", "Direction Changed"],
            [[row.seed, row.prior_profile, row.scenario, row.scoring_variant,
                row.budget_profile, row.baseline_true_q_delta_elpd_vs_null,
                row.budget_true_q_delta_elpd_vs_null, row.delta_from_baseline,
                row.direction_changed]
             for row in artifact.budget_contrast_rows])
        println(io, "## Post-Hoc Thinning Threshold Differences")
        table(io, ["Seed", "Profile", "Scenario", "Budget", "Threshold",
                "Unthinned", "Thinned Variant", "Thinned"],
            [[row.seed, row.prior_profile, row.scenario, row.budget_profile,
                row.threshold, row.unthinned_passed, row.thinned_variant,
                row.thinned_passed]
             for row in artifact.thinning_threshold_difference_rows])
        println(io, "## Boundary")
        println(io)
        println(io,
            "This file is a local MCMC-budget diagnostic. It can identify ",
            "whether a calibration-bridge conclusion is sensitive to warmup, ",
            "retained draws, or post-hoc retained-draw thinning, but it does ",
            "not establish public fit thresholds.")
    end
    return path
end

function build_artifact(options)
    all_model_rows = NamedTuple[]
    all_comparison_rows = NamedTuple[]
    cell_rows = NamedTuple[]

    for seed in options.seeds, profile in options.profiles,
            scenario in options.scenarios
        genopts = generation_options(options, seed, profile, scenario)
        generated = Bridge.SmallMCMC.generate_source_rows(genopts)
        split = Bridge.SmallMCMC.split_rows(generated.rows, genopts)
        static_rows = static_score_rows(generated.rows, split.train_rows,
            split.heldout_indices, generated.truth)

        for budget in options.budgets
            fitopts = fit_options(options, seed, profile, scenario, budget)
            mcmc_rows = fit_mcmc_rows(split.train_rows, generated.rows,
                split.heldout_indices, fitopts, options.thin_strides)
            for thin_stride in options.thin_strides
                context = context_tuple(seed, profile, scenario, budget,
                    thin_stride)
                static_context_rows = [merge(row, context) for row in static_rows]
                mcmc_context_rows = [add_context(row, seed, profile, scenario,
                    budget, thin_stride) for row in mcmc_rows
                    if row.thin_stride == thin_stride]
                group = ranked_group(vcat(static_context_rows,
                    mcmc_context_rows))
                comparisons = [merge(row, context) for row in comparison_rows(group)]
                append!(all_model_rows, group)
                append!(all_comparison_rows, comparisons)
                push!(cell_rows, scenario_cell_row(seed, profile, scenario,
                    budget, thin_stride, group, comparisons))
            end
        end
    end

    thresholds = threshold_rows(cell_rows, options.thresholds)
    stability = stability_rows(cell_rows)
    threshold_stability = threshold_stability_rows(thresholds)
    contrasts = budget_contrast_rows(cell_rows)
    thinning_differences = thinning_threshold_difference_rows(thresholds)
    findings = finding_rows(stability, threshold_stability, contrasts,
        thresholds)

    return (;
        schema = OUTPUT_SCHEMA,
        family = :mgmfrm,
        scope = :uto_style_mcmc_budget_bridge,
        status = :local_mcmc_budget_bridge_recorded,
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
            seeds = options.seeds,
            profiles = options.profiles,
            scenarios = [scenario.name for scenario in options.scenarios],
            budget_profiles = [budget.name for budget in options.budgets],
            thresholds = options.thresholds,
            thin_strides = options.thin_strides,
            n_persons = options.n_persons,
            n_items = options.n_items,
            n_raters = options.n_raters,
            heldout_fraction = options.heldout_fraction,
            q_true = Bridge.SmallMCMC.q_rows(Bridge.SmallMCMC.Q_TRUE),
            q_wrong = Bridge.SmallMCMC.q_rows(Bridge.SmallMCMC.Q_WRONG),
            thinning_policy =
                :posthoc_retained_draw_scoring_sensitivity_not_sampler_thinning,
        ),
        fit_controls = (;
            backend = :advancedhmc,
            sampler = :nuts,
            target_acceptance = options.target_acceptance,
            progress = options.progress,
        ),
        budget_rows = [(;
            name = budget.name,
            role = budget.role,
            chains = budget.chains,
            warmup_per_chain = budget.warmup_per_chain,
            draws_per_chain = budget.draws_per_chain,
            total_retained_draws =
                budget.chains * budget.draws_per_chain,
            expected_effect = budget.expected_effect,
            public_claim_allowed = false,
        ) for budget in options.budgets],
        scenario_cell_rows = cell_rows,
        threshold_rows = thresholds,
        model_score_rows = all_model_rows,
        comparison_rows = all_comparison_rows,
        stability_rows = stability,
        threshold_stability_rows = threshold_stability,
        budget_contrast_rows = contrasts,
        thinning_threshold_difference_rows = thinning_differences,
        finding_rows = findings,
        summary = (;
            passed = all(row.true_q_sampler_flag !== :fit_failed
                for row in cell_rows),
            n_scenario_budget_cells = length(cell_rows),
            n_model_score_rows = length(all_model_rows),
            n_threshold_rows = length(thresholds),
            n_budget_contrast_rows = length(contrasts),
            n_direction_changes_from_baseline =
                count(row -> row.direction_changed, contrasts),
            total_oracle_only_threshold_cells =
                count(row -> row.decision_profile === :oracle_only,
                    thresholds),
            no_public_fit_metric_claim = true,
            no_public_q_revision_claim = true,
            no_public_model_weight_claim = true,
            no_sparse_superiority_claim = true,
            next_gate =
                :category_calibration_metric_design_or_publication_grade_budget_selection,
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
    println("scenario_budget_cells=",
        artifact.summary.n_scenario_budget_cells,
        " direction_changes_from_baseline=",
        artifact.summary.n_direction_changes_from_baseline,
        " oracle_only_threshold_cells=",
        artifact.summary.total_oracle_only_threshold_cells,
        " next_gate=", artifact.summary.next_gate)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
