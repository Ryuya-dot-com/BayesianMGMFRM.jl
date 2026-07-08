#!/usr/bin/env julia

using Dates
using SHA
using Statistics
using TOML

import BayesianMGMFRM

module BudgetBridge
include(joinpath(@__DIR__, "generate_mgmfrm_uto_style_mcmc_budget_bridge.jl"))
end

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT_JSON =
    joinpath(ROOT, "artifacts", "uto_style_category_calibration_bridge",
        "uto_style_category_calibration_bridge.json")
const DEFAULT_OUTPUT_MD =
    joinpath(ROOT, "artifacts", "uto_style_category_calibration_bridge",
        "uto_style_category_calibration_bridge.md")

include(joinpath(@__DIR__, "local_json.jl"))

const OUTPUT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_uto_style_category_calibration_bridge.v1"
const CATEGORY_LEVELS = BudgetBridge.Bridge.SmallMCMC.CATEGORY_LEVELS
const DEFAULT_THRESHOLDS = BudgetBridge.DEFAULT_THRESHOLDS
const DEFAULT_BUDGETS = [:baseline_20_20, :increased_80_80]
const DEFAULT_THIN_STRIDES = [1, 2]

function usage()
    return """
    Generate a local Uto-style MGMFRM category-calibration bridge.

    This reruns selected calibration-bridge scenarios and MCMC budgets, then
    scores heldout observations with category-probability calibration metrics:
    category distribution gaps, cumulative threshold gaps, multiclass Brier
    score, and expected-score MAE. It keeps dELPD thresholds as diagnostic
    profiles and does not promote public fit thresholds.

    Usage:
      julia --project=. scripts/generate_mgmfrm_uto_style_category_calibration_bridge.jl [options]

    Options:
      --output-json PATH       JSON artifact path.
      --output-md PATH         Markdown report path.
      --seed N                 Base random seed. Default: 20260707.
      --profile NAME           Internal source prior profile. Default: default.
      --scenarios LIST         Comma-separated scenarios. Default: all bridge scenarios.
      --budget-profiles LIST   Comma-separated budgets. Default: baseline_20_20,increased_80_80.
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

function parse_args(args)
    output_json = DEFAULT_OUTPUT_JSON
    output_md = DEFAULT_OUTPUT_MD
    seed = 20260707
    profile = :default
    scenario_names = [scenario.name for scenario in
        BudgetBridge.Bridge.SCENARIO_LIBRARY]
    budget_names = copy(DEFAULT_BUDGETS)
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
        elseif arg == "--seed"
            index < length(args) || error("--seed requires an integer")
            seed = parse(Int, args[index + 1])
            index += 2
        elseif arg == "--profile"
            index < length(args) || error("--profile requires a name")
            profile = Symbol(args[index + 1])
            index += 2
        elseif arg == "--scenarios"
            index < length(args) || error("--scenarios requires a comma list")
            scenario_names =
                BudgetBridge.Bridge.parse_symbol_list(args[index + 1])
            index += 2
        elseif arg == "--budget-profiles"
            index < length(args) ||
                error("--budget-profiles requires a comma list")
            budget_names =
                BudgetBridge.Bridge.parse_symbol_list(args[index + 1])
            index += 2
        elseif arg == "--thresholds"
            index < length(args) || error("--thresholds requires a comma list")
            thresholds = BudgetBridge.Bridge.parse_thresholds(args[index + 1])
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

    profile in (:default, :tight, :diffuse) ||
        error("--profile must be default, tight, or diffuse")
    n_persons >= 6 || error("--n-persons must be at least 6")
    n_raters >= 3 || error("--n-raters must be at least 3")
    0 < heldout_fraction < 0.5 ||
        error("--heldout-fraction must be in (0, 0.5)")
    0 < target_acceptance < 1 ||
        error("--target-acceptance must be in (0, 1)")
    scenarios = [BudgetBridge.Bridge.scenario_by_name(name)
        for name in scenario_names]
    budgets = [BudgetBridge.budget_by_name(name) for name in budget_names]
    return (;
        output_json,
        output_md,
        seed,
        profile,
        scenarios,
        budgets,
        thresholds,
        thin_strides,
        n_persons,
        n_items = size(BudgetBridge.Bridge.SmallMCMC.Q_TRUE, 1),
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

function generation_options(options, scenario)
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
        prior_profile = options.profile,
        seed = options.seed + scenario.seed_offset,
        progress = false,
        ability_scale = scenario.ability_scale,
        item_discrimination_scale = scenario.item_discrimination_scale,
        rater_severity_scale = scenario.rater_severity_scale,
        rater_consistency_spread = scenario.rater_consistency_spread,
        item_step = scenario.item_step,
    )
end

function fit_options(options, scenario, budget)
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
        prior_profile = options.profile,
        seed = options.seed + scenario.seed_offset,
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

function observed_scores(full_rows, heldout_indices)
    return [full_rows[index].score for index in heldout_indices]
end

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
    global_probs = BudgetBridge.Bridge.SmallMCMC.smoothed_probs(train_rows)
    model === :null_or_intercept_reference &&
        return repeated_probability_means(global_probs, length(heldout_indices))
    item_rater = BudgetBridge.Bridge.SmallMCMC.grouped_smoothed_probs(
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

function oracle_probability_means(full_rows, truth, heldout_indices)
    full = BudgetBridge.Bridge.SmallMCMC.design_for_rows(
        full_rows,
        :true_q_source_oracle,
    )
    direct =
        BudgetBridge.Bridge.SmallMCMC.truth_direct_params(full.design, truth)
    return direct_probability_means(full.design, reshape(direct, 1, :),
        heldout_indices)
end

function fit_model_probability_means(model::Symbol, train_rows, full_rows,
        heldout_indices, fitopts, thin_strides)
    started = time_ns()
    train = BudgetBridge.Bridge.SmallMCMC.design_for_rows(train_rows, model)
    full = BudgetBridge.Bridge.SmallMCMC.design_for_rows(full_rows, model)
    layout_matches = train.design.parameter_names == full.design.parameter_names
    fit = BayesianMGMFRM.fit(train.spec;
        experimental = true,
        prior = BudgetBridge.Bridge.SmallMCMC.source_prior(
            fitopts.prior_profile,
        ),
        backend = :advancedhmc,
        ndraws = fitopts.draws_per_chain,
        warmup = fitopts.warmup_per_chain,
        chains = fitopts.chains,
        seed = fitopts.seed +
               BudgetBridge.Bridge.SmallMCMC.model_seed_offset(model),
        target_accept = fitopts.target_acceptance,
        progress = fitopts.progress,
    )
    elapsed_seconds = (time_ns() - started) / 1e9
    summary = fit.diagnostic_surface.summary
    return [(;
        model,
        probabilities = direct_probability_means(
            full.design,
            thinned_draws(fit.direct_draws, thin_stride),
            heldout_indices,
        ),
        metadata = (;
            model,
            model_family = fit.design.spec.family,
            fit_succeeded = true,
            returned_type = Symbol(nameof(typeof(fit))),
            layout_matches,
            n_train_observations = length(train_rows),
            n_heldout_observations = length(heldout_indices),
            n_draws = size(thinned_draws(fit.direct_draws, thin_stride), 1),
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
            public_claim_allowed = false,
        ),
    ) for thin_stride in thin_strides]
end

function failed_model_probability_means(model::Symbol, err, fitopts,
        heldout_indices, thin_strides)
    return [(;
        model,
        probabilities = zeros(Float64, length(heldout_indices),
            length(CATEGORY_LEVELS)) .* NaN,
        metadata = (;
            model,
            model_family = model === :scalar_gmfrm_mcmc ? :gmfrm : :mgmfrm,
            fit_succeeded = false,
            returned_type = missing,
            layout_matches = false,
            n_train_observations = missing,
            n_heldout_observations = length(heldout_indices),
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
        ),
    ) for thin_stride in thin_strides]
end

function model_probability_sets(train_rows, full_rows, heldout_indices, truth,
        fitopts, thin_strides)
    sets = NamedTuple[]
    oracle_probs = oracle_probability_means(full_rows, truth, heldout_indices)
    for thin_stride in thin_strides
        push!(sets, (;
            model = :true_q_source_oracle,
            probabilities = oracle_probs,
            metadata = (;
                model = :true_q_source_oracle,
                model_family = :mgmfrm,
                fit_succeeded = true,
                returned_type = :known_truth_source_oracle,
                n_heldout_observations = length(heldout_indices),
                n_draws = 1,
                thin_stride,
                scoring_variant = scoring_variant(thin_stride),
                sampler_flag = :not_applicable,
                public_claim_allowed = false,
            ),
        ))
        for reference_model in (:item_rater_reference,
                :null_or_intercept_reference)
            push!(sets, (;
                model = reference_model,
                probabilities = reference_probability_means(
                    reference_model,
                    train_rows,
                    full_rows,
                    heldout_indices,
                ),
                metadata = (;
                    model = reference_model,
                    model_family = :analytic_reference,
                    fit_succeeded = true,
                    returned_type = :analytic_reference,
                    n_heldout_observations = length(heldout_indices),
                    n_draws = 0,
                    thin_stride,
                    scoring_variant = scoring_variant(thin_stride),
                    sampler_flag = :not_applicable,
                    public_claim_allowed = false,
                ),
            ))
        end
    end
    for model in BudgetBridge.Bridge.SmallMCMC.MCMC_MODELS
        try
            append!(sets, fit_model_probability_means(
                model,
                train_rows,
                full_rows,
                heldout_indices,
                fitopts,
                thin_strides,
            ))
        catch err
            append!(sets, failed_model_probability_means(model, err, fitopts,
                heldout_indices, thin_strides))
        end
    end
    return sets
end

function log_score(probabilities::AbstractMatrix, scores)
    values = Float64[]
    for row in eachindex(scores)
        probability = probabilities[row, score_index(scores[row])]
        push!(values, log(max(probability, eps(Float64))))
    end
    return sum(values; init = 0.0)
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
    return [(;
        context...,
        model,
        category = CATEGORY_LEVELS[category],
        observed_count =
            count(==(CATEGORY_LEVELS[category]), scores),
        observed_share =
            round4(count(==(CATEGORY_LEVELS[category]), scores) / n),
        predicted_share = round4(mean(@view probabilities[:, category])),
        share_gap = round4(mean(@view probabilities[:, category]) -
                           count(==(CATEGORY_LEVELS[category]), scores) / n),
        abs_share_gap =
            round4(abs(mean(@view probabilities[:, category]) -
                       count(==(CATEGORY_LEVELS[category]), scores) / n)),
        public_claim_allowed = false,
    ) for category in eachindex(CATEGORY_LEVELS)]
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

function model_summary_row(context, model::Symbol,
        probabilities::AbstractMatrix, scores)
    category_rows = category_distribution_rows(context, model, probabilities,
        scores)
    threshold_rows = cumulative_threshold_rows(context, model, probabilities,
        scores)
    n_used = count(category ->
        any(==(category), scores), CATEGORY_LEVELS)
    min_count = minimum(count(==(category), scores)
        for category in CATEGORY_LEVELS)
    return (;
        context...,
        model,
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
            round4(sum(row.abs_share_gap for row in threshold_rows)),
        n_heldout = length(scores),
        n_categories_used = n_used,
        min_observed_category_count = min_count,
        min_observed_category_share = round4(min_count / length(scores)),
        public_claim_allowed = false,
    )
end

function context_tuple(options, scenario, budget, thin_stride)
    return (;
        seed = options.seed,
        prior_profile = options.profile,
        scenario = scenario.name,
        budget_profile = budget.name,
        chains = budget.chains,
        warmup_per_chain = budget.warmup_per_chain,
        draws_per_chain = budget.draws_per_chain,
        thin_stride,
        scoring_variant = scoring_variant(thin_stride),
    )
end

function row_by_model(rows, model::Symbol)
    matches = [row for row in rows if row.model === model]
    isempty(matches) && return nothing
    return only(matches)
end

function category_bridge_cell(options, scenario, budget)
    genopts = generation_options(options, scenario)
    generated = BudgetBridge.Bridge.SmallMCMC.generate_source_rows(genopts)
    split = BudgetBridge.Bridge.SmallMCMC.split_rows(generated.rows, genopts)
    scores = observed_scores(generated.rows, split.heldout_indices)
    fitopts = fit_options(options, scenario, budget)
    sets = model_probability_sets(
        split.train_rows,
        generated.rows,
        split.heldout_indices,
        generated.truth,
        fitopts,
        options.thin_strides,
    )

    summary_rows = NamedTuple[]
    category_rows = NamedTuple[]
    cumulative_rows = NamedTuple[]
    metadata_rows = NamedTuple[]

    for set in sets
        thin_stride = set.metadata.thin_stride
        context = context_tuple(options, scenario, budget, thin_stride)
        push!(summary_rows, model_summary_row(context, set.model,
            set.probabilities, scores))
        append!(category_rows, category_distribution_rows(context, set.model,
            set.probabilities, scores))
        append!(cumulative_rows, cumulative_threshold_rows(context, set.model,
            set.probabilities, scores))
        push!(metadata_rows, merge(set.metadata, context))
    end
    return (;
        summary_rows,
        category_rows,
        cumulative_rows,
        metadata_rows,
    )
end

function comparison_rows(summary_rows)
    output = NamedTuple[]
    keys = sort(unique((row.scenario, row.budget_profile, row.scoring_variant)
        for row in summary_rows);
        by = key -> (string(key[1]), string(key[2]), string(key[3])))
    for (scenario, budget, variant) in keys
        group = [row for row in summary_rows
            if row.scenario === scenario &&
               row.budget_profile === budget &&
               row.scoring_variant === variant]
        null = row_by_model(group, :null_or_intercept_reference)
        true_q = row_by_model(group, :true_q_mgmfrm_mcmc)
        null === nothing && continue
        true_q === nothing && continue
        push!(output, (;
            seed = true_q.seed,
            prior_profile = true_q.prior_profile,
            scenario,
            budget_profile = budget,
            scoring_variant = variant,
            model = :true_q_mgmfrm_mcmc,
            baseline = :null_or_intercept_reference,
            delta_log_score_vs_null =
                round3(true_q.heldout_log_score - null.heldout_log_score),
            delta_brier_vs_null =
                round4(true_q.multiclass_brier - null.multiclass_brier),
            delta_category_total_variation_vs_null =
                round4(true_q.category_total_variation -
                       null.category_total_variation),
            delta_cumulative_l1_vs_null =
                round4(true_q.cumulative_l1 - null.cumulative_l1),
            public_claim_allowed = false,
        ))
    end
    return output
end

function threshold_link_rows(comparisons, thresholds)
    rows = NamedTuple[]
    for comparison in comparisons, threshold in thresholds
        push!(rows, (;
            comparison.seed,
            comparison.prior_profile,
            comparison.scenario,
            comparison.budget_profile,
            comparison.scoring_variant,
            threshold = round3(threshold),
            passed_delta_log_score =
                comparison.delta_log_score_vs_null >= threshold,
            delta_log_score_vs_null = comparison.delta_log_score_vs_null,
            delta_brier_vs_null = comparison.delta_brier_vs_null,
            delta_category_total_variation_vs_null =
                comparison.delta_category_total_variation_vs_null,
            delta_cumulative_l1_vs_null = comparison.delta_cumulative_l1_vs_null,
            calibration_interpretation =
                comparison.delta_log_score_vs_null >= threshold &&
                comparison.delta_category_total_variation_vs_null <= 0 &&
                comparison.delta_cumulative_l1_vs_null <= 0 ?
                :predictive_and_category_calibration_aligned :
                comparison.delta_log_score_vs_null >= threshold ?
                :predictive_gain_with_category_calibration_caveat :
                :threshold_not_cleared,
            public_claim_allowed = false,
        ))
    end
    return rows
end

function best_model_rows(summary_rows)
    rows = NamedTuple[]
    keys = sort(unique((row.scenario, row.budget_profile, row.scoring_variant)
        for row in summary_rows);
        by = key -> (string(key[1]), string(key[2]), string(key[3])))
    for (scenario, budget, variant) in keys
        group = [row for row in summary_rows
            if row.scenario === scenario &&
               row.budget_profile === budget &&
               row.scoring_variant === variant]
        log_leader = first(sort(group; by = row -> row.heldout_log_score,
            rev = true))
        brier_leader = first(sort(group; by = row -> row.multiclass_brier))
        category_leader = first(sort(group;
            by = row -> row.category_total_variation))
        push!(rows, (;
            seed = log_leader.seed,
            prior_profile = log_leader.prior_profile,
            scenario,
            budget_profile = budget,
            scoring_variant = variant,
            best_log_score_model = log_leader.model,
            best_brier_model = brier_leader.model,
            best_category_distribution_model = category_leader.model,
            true_q_best_log_score =
                log_leader.model === :true_q_mgmfrm_mcmc,
            true_q_best_brier =
                brier_leader.model === :true_q_mgmfrm_mcmc,
            true_q_best_category_distribution =
                category_leader.model === :true_q_mgmfrm_mcmc,
            public_claim_allowed = false,
        ))
    end
    return rows
end

function finding_rows(summary_rows, comparisons, threshold_links)
    weak_true = [row for row in summary_rows
        if row.scenario === :weak_compressed_category &&
           row.model === :true_q_mgmfrm_mcmc &&
           row.scoring_variant === :all_retained_draws]
    moderate = [row for row in comparisons
        if row.scenario === :moderate_transition &&
           row.scoring_variant === :all_retained_draws]
    threshold_caveats = [row for row in threshold_links
        if row.calibration_interpretation ===
           :predictive_gain_with_category_calibration_caveat]
    aligned = [row for row in threshold_links
        if row.calibration_interpretation ===
           :predictive_and_category_calibration_aligned]
    return [
        (finding = :category_calibration_metrics_recorded,
            severity = :info,
            evidence = string(length(summary_rows),
                " model-summary row(s) recorded"),
            implication =
                :dELPD_thresholds_can_now_be_read_with_category_gaps),
        (finding = :weak_category_calibration_gap_recorded,
            severity = isempty(weak_true) ? :warning : :info,
            evidence = isempty(weak_true) ? "not run" :
                string("weak true-Q max category TV = ",
                    round4(maximum(row.category_total_variation
                        for row in weak_true))),
            implication =
                :weak_threshold_failure_can_be_compared_to_category_distribution_error),
        (finding = :moderate_transition_remains_predictively_negative,
            severity = any(row.delta_log_score_vs_null >= 0
                for row in moderate) ? :warning : :info,
            evidence = isempty(moderate) ? "not run" :
                string("maximum moderate true-Q delta log score = ",
                    round3(maximum(row.delta_log_score_vs_null
                        for row in moderate))),
            implication =
                :category_metrics_should_not_rescue_a_negative_predictive_margin),
        (finding = :threshold_calibration_alignment_profile,
            severity = isempty(threshold_caveats) ? :info : :warning,
            evidence = string(length(aligned),
                " aligned threshold cell(s), ",
                length(threshold_caveats), " caveat cell(s)"),
            implication =
                :threshold_claims_need_category_calibration_conditions),
        (finding = :public_claims_blocked,
            severity = :blocker,
            evidence = "local category-calibration bridge only",
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
        println(io, "# Uto-Style Category-Calibration Bridge")
        println(io)
        println(io, "- Generated at: `", artifact.generated_at, "`")
        println(io, "- Local only: `true`")
        println(io, "- Public claims allowed: `false`")
        println(io)
        println(io, "## Interpretation")
        println(io)
        println(io,
            "This report adds category-probability calibration to the ",
            "calibration bridge. It compares dELPD/log-score thresholds with ",
            "category distribution gaps, cumulative threshold gaps, Brier score, ",
            "and expected-score MAE on the same heldout rows.")
        println(io)
        println(io, "## Findings")
        table(io, ["Finding", "Severity", "Evidence", "Implication"],
            [[row.finding, row.severity, row.evidence, row.implication]
             for row in artifact.finding_rows])
        println(io, "## True-Q vs Null Calibration")
        table(io, ["Scenario", "Budget", "Variant", "dLogScore",
                "dBrier", "dCategoryTV", "dCumulativeL1"],
            [[row.scenario, row.budget_profile, row.scoring_variant,
                row.delta_log_score_vs_null, row.delta_brier_vs_null,
                row.delta_category_total_variation_vs_null,
                row.delta_cumulative_l1_vs_null]
             for row in artifact.comparison_rows])
        println(io, "## Threshold Link")
        table(io, ["Scenario", "Budget", "Variant", "Threshold", "Passed",
                "dLogScore", "dCategoryTV", "dCumulativeL1", "Interpretation"],
            [[row.scenario, row.budget_profile, row.scoring_variant,
                row.threshold, row.passed_delta_log_score,
                row.delta_log_score_vs_null,
                row.delta_category_total_variation_vs_null,
                row.delta_cumulative_l1_vs_null,
                row.calibration_interpretation]
             for row in artifact.threshold_link_rows])
        println(io, "## Model Calibration Summary")
        table(io, ["Scenario", "Budget", "Variant", "Model", "LogScore",
                "Brier", "CategoryTV", "MaxCatGap", "CumulativeL1", "MAE"],
            [[row.scenario, row.budget_profile, row.scoring_variant,
                row.model, row.heldout_log_score, row.multiclass_brier,
                row.category_total_variation, row.max_abs_category_gap,
                row.cumulative_l1, row.expected_score_mae]
             for row in artifact.summary_rows])
        println(io, "## Best Models by Metric")
        table(io, ["Scenario", "Budget", "Variant", "Best LogScore",
                "Best Brier", "Best Category Distribution"],
            [[row.scenario, row.budget_profile, row.scoring_variant,
                row.best_log_score_model, row.best_brier_model,
                row.best_category_distribution_model]
             for row in artifact.best_model_rows])
        println(io, "## Category Distribution Rows")
        table(io, ["Scenario", "Budget", "Variant", "Model", "Category",
                "Observed", "Predicted", "Gap"],
            [[row.scenario, row.budget_profile, row.scoring_variant,
                row.model, row.category, row.observed_share,
                row.predicted_share, row.share_gap]
             for row in artifact.category_rows])
        println(io, "## Boundary")
        println(io)
        println(io,
            "These are local calibration diagnostics. They do not define ",
            "public fit cutoffs. A threshold should only be promoted after its ",
            "predictive gain, category distribution error, cumulative threshold ",
            "error, and false-alarm/power behavior are jointly calibrated.")
    end
    return path
end

function build_artifact(options)
    summary_rows = NamedTuple[]
    category_rows = NamedTuple[]
    cumulative_rows = NamedTuple[]
    metadata_rows = NamedTuple[]

    for scenario in options.scenarios, budget in options.budgets
        cell = category_bridge_cell(options, scenario, budget)
        append!(summary_rows, cell.summary_rows)
        append!(category_rows, cell.category_rows)
        append!(cumulative_rows, cell.cumulative_rows)
        append!(metadata_rows, cell.metadata_rows)
    end
    comparisons = comparison_rows(summary_rows)
    threshold_links = threshold_link_rows(comparisons, options.thresholds)
    best_rows = best_model_rows(summary_rows)
    findings = finding_rows(summary_rows, comparisons, threshold_links)
    return (;
        schema = OUTPUT_SCHEMA,
        family = :mgmfrm,
        scope = :uto_style_category_calibration_bridge,
        status = :local_category_calibration_bridge_recorded,
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
            seed = options.seed,
            profile = options.profile,
            scenarios = [scenario.name for scenario in options.scenarios],
            budget_profiles = [budget.name for budget in options.budgets],
            thresholds = options.thresholds,
            thin_strides = options.thin_strides,
            n_persons = options.n_persons,
            n_items = options.n_items,
            n_raters = options.n_raters,
            heldout_fraction = options.heldout_fraction,
            q_true = BudgetBridge.Bridge.SmallMCMC.q_rows(
                BudgetBridge.Bridge.SmallMCMC.Q_TRUE,
            ),
            q_wrong = BudgetBridge.Bridge.SmallMCMC.q_rows(
                BudgetBridge.Bridge.SmallMCMC.Q_WRONG,
            ),
            category_levels = CATEGORY_LEVELS,
        ),
        fit_controls = (;
            backend = :advancedhmc,
            sampler = :nuts,
            target_acceptance = options.target_acceptance,
            progress = options.progress,
        ),
        summary_rows,
        comparison_rows = comparisons,
        threshold_link_rows = threshold_links,
        best_model_rows = best_rows,
        category_rows,
        cumulative_threshold_rows = cumulative_rows,
        model_metadata_rows = metadata_rows,
        finding_rows = findings,
        summary = (;
            passed = all(row.fit_succeeded for row in metadata_rows
                if row.model in BudgetBridge.Bridge.SmallMCMC.MCMC_MODELS),
            n_summary_rows = length(summary_rows),
            n_category_rows = length(category_rows),
            n_threshold_link_rows = length(threshold_links),
            n_predictive_and_category_aligned_threshold_cells =
                count(row -> row.calibration_interpretation ===
                    :predictive_and_category_calibration_aligned,
                    threshold_links),
            n_predictive_gain_with_category_caveat_cells =
                count(row -> row.calibration_interpretation ===
                    :predictive_gain_with_category_calibration_caveat,
                    threshold_links),
            no_public_fit_metric_claim = true,
            no_public_q_revision_claim = true,
            no_public_model_weight_claim = true,
            no_sparse_superiority_claim = true,
            next_gate =
                :simulate_threshold_false_alarm_and_power_profiles,
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
    println("summary_rows=", artifact.summary.n_summary_rows,
        " aligned_threshold_cells=",
        artifact.summary.n_predictive_and_category_aligned_threshold_cells,
        " caveat_threshold_cells=",
        artifact.summary.n_predictive_gain_with_category_caveat_cells,
        " next_gate=", artifact.summary.next_gate)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
