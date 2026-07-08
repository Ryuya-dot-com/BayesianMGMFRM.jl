#!/usr/bin/env julia

using Dates
using Random
using SHA
using Statistics
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT_JSON =
    joinpath(ROOT, "artifacts", "uto_style_oracle_simulation",
        "uto_style_oracle_simulation.json")
const DEFAULT_OUTPUT_MD =
    joinpath(ROOT, "artifacts", "uto_style_oracle_simulation",
        "uto_style_oracle_simulation.md")

include(joinpath(@__DIR__, "local_json.jl"))

const OUTPUT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_uto_style_oracle_simulation.v1"

const CATEGORY_LEVELS = [0, 1, 2]
const MODEL_ORDER = [
    :true_q_mgmfrm_oracle,
    :scalar_gmfrm_oracle,
    :wrong_q_mgmfrm_oracle,
    :item_rater_reference,
    :null_or_intercept_reference,
]

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
    1 0
    1 0
    1 0
    1 0
]

const SCENARIOS = [
    (;
        scenario = :uto_like_multidimensional_strong_signal,
        role = :uto_conclusion_reproduction_target,
        n_persons = 160,
        n_items = 6,
        n_raters = 5,
        n_replicates = 12,
        heldout_fraction = 0.20,
        ability_scale = 1.25,
        item_discrimination_scale = 1.15,
        rater_severity_scale = 0.55,
        rater_consistency_spread = 0.35,
        expected_best_model = :true_q_mgmfrm_oracle,
        expected_alignment =
            :should_match_uto_direction_when_multidimensional_signal_is_real,
    ),
    (;
        scenario = :compact_weak_signal_failure_like,
        role = :current_failure_mechanism_probe,
        n_persons = 8,
        n_items = 6,
        n_raters = 2,
        n_replicates = 12,
        heldout_fraction = 0.20,
        ability_scale = 0.25,
        item_discrimination_scale = 0.55,
        rater_severity_scale = 0.20,
        rater_consistency_spread = 0.08,
        expected_best_model = :null_or_intercept_reference,
        expected_alignment =
            :should_explain_how_null_can_win_when_signal_is_weak_or_sparse,
    ),
]

function usage()
    return """
    Generate a local Uto-style known-truth oracle simulation.

    This simulation does not fit MCMC models. It checks whether the
    data-generating conditions emphasized by Uto-style GMFRM/MGMFRM work
    are sufficient for a true fixed-Q MGMFRM oracle to beat scalar/null
    references, and contrasts that with a compact weak-signal condition.

    Usage:
      julia --project=. scripts/generate_mgmfrm_uto_style_oracle_simulation.jl [options]

    Options:
      --output-json PATH  JSON artifact path.
      --output-md PATH    Markdown report path.
    """
end

function parse_args(args)
    output_json = DEFAULT_OUTPUT_JSON
    output_md = DEFAULT_OUTPUT_MD
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
        elseif arg in ("-h", "--help")
            println(usage())
            exit(0)
        else
            error("unknown argument: $arg")
        end
    end
    return (; output_json, output_md)
end

project_version() =
    String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])
file_sha256(path::AbstractString) = bytes2hex(open(sha256, path))
rel(path::AbstractString) = relpath(path, ROOT)

round3(value) = round(Float64(value); digits = 3)
round4(value) = round(Float64(value); digits = 4)

function softmax(etas::AbstractVector{<:Real})
    max_eta = maximum(etas)
    weights = exp.(etas .- max_eta)
    return weights ./ sum(weights)
end

function category_probabilities(location::Real, scale::Real,
        steps::Union{Tuple, AbstractVector{<:Real}})
    etas = zeros(Float64, length(CATEGORY_LEVELS))
    cumulative = 0.0
    for category_index in 2:length(CATEGORY_LEVELS)
        cumulative += Float64(scale) *
            (Float64(location) - Float64(steps[category_index - 1]))
        etas[category_index] = cumulative
    end
    return softmax(etas)
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

function log_probability_for_score(probabilities, score::Integer)
    index = findfirst(==(score), CATEGORY_LEVELS)
    index === nothing && error("unknown score: $score")
    return log(max(probabilities[index], eps(Float64)))
end

function expected_score(probabilities)
    return sum(Float64(CATEGORY_LEVELS[index]) * probabilities[index]
        for index in eachindex(CATEGORY_LEVELS))
end

function centered(values)
    output = collect(Float64, values)
    output .-= mean(output)
    return output
end

function scenario_truth(scenario, rng::AbstractRNG)
    dims = 2
    theta = scenario.ability_scale *
        [randn(rng) for _ in 1:scenario.n_persons, _ in 1:dims]
    # Make the two dimensions visibly different so a scalar collapse loses
    # information in the Uto-like condition.
    for person in 1:scenario.n_persons
        theta[person, 2] =
            scenario.ability_scale * (0.20 * randn(rng) -
                                      0.70 * theta[person, 1] /
                                      max(scenario.ability_scale, eps()))
    end
    item_difficulty = centered(range(-0.75, 0.75; length = scenario.n_items))
    item_discrimination = zeros(Float64, scenario.n_items, dims)
    for item in 1:scenario.n_items, dim in 1:dims
        if Q_TRUE[item, dim]
            item_discrimination[item, dim] =
                scenario.item_discrimination_scale * (0.90 + 0.25 * rand(rng))
        end
    end
    raw_severity = range(-1.0, 1.0; length = scenario.n_raters)
    rater_severity = centered(scenario.rater_severity_scale .* raw_severity)
    consistency_raw =
        [exp(scenario.rater_consistency_spread *
             (2 * (rater - 1) / max(scenario.n_raters - 1, 1) - 1))
         for rater in 1:scenario.n_raters]
    geometric_mean = prod(consistency_raw)^(1 / length(consistency_raw))
    rater_consistency = consistency_raw ./ geometric_mean
    item_steps = [(-0.55, 0.55) for _ in 1:scenario.n_items]
    return (;
        theta,
        item_difficulty,
        item_discrimination,
        rater_severity,
        rater_consistency,
        item_steps,
    )
end

function active_location(truth, person::Int, item::Int, q_matrix)
    total = 0.0
    for dim in axes(q_matrix, 2)
        q_matrix[item, dim] || continue
        discrimination = truth.item_discrimination[item, dim]
        if discrimination == 0.0
            active = [value for value in truth.item_discrimination[item, :]
                if value > 0.0]
            discrimination = isempty(active) ? 0.0 : mean(active)
        end
        total += discrimination * truth.theta[person, dim]
    end
    return total
end

function scalar_location(truth, person::Int, item::Int)
    theta_scalar = mean(view(truth.theta, person, :))
    active = [value for value in truth.item_discrimination[item, :]
        if value > 0.0]
    discrimination = isempty(active) ? 1.0 : mean(active)
    return discrimination * theta_scalar
end

function model_probabilities(model::Symbol, truth, row)
    if model === :true_q_mgmfrm_oracle
        ability = active_location(truth, row.person, row.item, Q_TRUE)
    elseif model === :wrong_q_mgmfrm_oracle
        ability = active_location(truth, row.person, row.item, Q_WRONG)
    elseif model === :scalar_gmfrm_oracle
        ability = scalar_location(truth, row.person, row.item)
    else
        error("model_probabilities only supports oracle structural models")
    end
    location =
        ability - truth.item_difficulty[row.item] -
        truth.rater_severity[row.rater]
    scale = 1.7 * truth.rater_consistency[row.rater]
    return category_probabilities(location, scale, truth.item_steps[row.item])
end

function simulate_rows(scenario, truth, rng::AbstractRNG)
    rows = NamedTuple[]
    for person in 1:scenario.n_persons,
            item in 1:scenario.n_items,
            rater in 1:scenario.n_raters
        base = (; person, item, rater)
        probabilities = model_probabilities(:true_q_mgmfrm_oracle, truth, base)
        score = sample_category(rng, probabilities)
        push!(rows, merge(base, (score = score,)))
    end
    return rows
end

function split_rows(rows, scenario, rng::AbstractRNG)
    n = length(rows)
    indices = collect(1:n)
    shuffle!(rng, indices)
    n_heldout = max(1, round(Int, scenario.heldout_fraction * n))
    heldout_set = Set(indices[1:n_heldout])
    train = [rows[index] for index in 1:n if !(index in heldout_set)]
    heldout = [rows[index] for index in 1:n if index in heldout_set]
    return train, heldout
end

function smoothed_category_probabilities(rows; alpha = 1.0)
    counts = Dict(score => alpha for score in CATEGORY_LEVELS)
    for row in rows
        counts[row.score] = counts[row.score] + 1.0
    end
    total = sum(values(counts))
    return [counts[score] / total for score in CATEGORY_LEVELS]
end

function smoothed_item_rater_probabilities(rows; alpha = 1.0)
    groups = Dict{Tuple{Int, Int}, Dict{Int, Float64}}()
    for row in rows
        key = (row.item, row.rater)
        counts = get!(groups, key, Dict(score => alpha for score in CATEGORY_LEVELS))
        counts[row.score] = counts[row.score] + 1.0
    end
    global_probs = smoothed_category_probabilities(rows; alpha)
    return groups, global_probs
end

function item_rater_probabilities(groups, global_probs, row)
    key = (row.item, row.rater)
    if !haskey(groups, key)
        return global_probs
    end
    counts = groups[key]
    total = sum(values(counts))
    return [counts[score] / total for score in CATEGORY_LEVELS]
end

function score_model(model::Symbol, truth, train, heldout)
    null_probs = smoothed_category_probabilities(train)
    item_rater_groups, item_rater_global =
        smoothed_item_rater_probabilities(train)
    lpds = Float64[]
    abs_errors = Float64[]
    for row in heldout
        probabilities =
            if model in (:true_q_mgmfrm_oracle, :wrong_q_mgmfrm_oracle,
                    :scalar_gmfrm_oracle)
                model_probabilities(model, truth, row)
            elseif model === :null_or_intercept_reference
                null_probs
            elseif model === :item_rater_reference
                item_rater_probabilities(item_rater_groups,
                    item_rater_global, row)
            else
                error("unknown model: $model")
            end
        push!(lpds, log_probability_for_score(probabilities, row.score))
        push!(abs_errors, abs(Float64(row.score) - expected_score(probabilities)))
    end
    return (;
        heldout_elpd = sum(lpds; init = 0.0),
        mean_log_predictive_density = mean(lpds),
        heldout_expected_score_mae = mean(abs_errors),
        n_heldout = length(heldout),
    )
end

function replicate_rows(scenario, replicate::Int)
    scenario_seed_offset =
        scenario.scenario === :uto_like_multidimensional_strong_signal ? 101 : 503
    rng = MersenneTwister(20260707 + 1000 * replicate +
                          scenario_seed_offset)
    truth = scenario_truth(scenario, rng)
    rows = simulate_rows(scenario, truth, rng)
    train, heldout = split_rows(rows, scenario, rng)
    scored = [(;
        scenario = scenario.scenario,
        replicate,
        model,
        n_train = length(train),
        n_heldout = length(heldout),
        score_model(model, truth, train, heldout)...,
        public_claim_allowed = false,
    ) for model in MODEL_ORDER]
    ranked = sort(scored; by = row -> row.heldout_elpd, rev = true)
    return [merge(row, (rank = findfirst(candidate ->
        candidate.model === row.model, ranked),))
        for row in scored]
end

function scenario_replicate_rows()
    rows = NamedTuple[]
    for scenario in SCENARIOS, replicate in 1:scenario.n_replicates
        append!(rows, replicate_rows(scenario, replicate))
    end
    return rows
end

function model_summary_rows(rows)
    output = NamedTuple[]
    for scenario in [scenario.scenario for scenario in SCENARIOS],
            model in MODEL_ORDER
        group = [row for row in rows
            if row.scenario === scenario && row.model === model]
        isempty(group) && continue
        elpds = [row.heldout_elpd for row in group]
        maes = [row.heldout_expected_score_mae for row in group]
        ranks = [row.rank for row in group]
        push!(output, (;
            scenario,
            model,
            n_replicates = length(group),
            mean_n_heldout = round3(mean(row.n_heldout for row in group)),
            mean_rank = round3(mean(ranks)),
            n_replicate_wins = count(==(1), ranks),
            mean_heldout_elpd = round3(mean(elpds)),
            sd_heldout_elpd = round3(std(elpds)),
            mean_heldout_expected_score_mae = round3(mean(maes)),
            public_claim_allowed = false,
        ))
    end
    return sort(output; by = row -> (row.scenario, row.mean_rank))
end

function delta_summary_rows(summary_rows)
    output = NamedTuple[]
    for scenario in [scenario.scenario for scenario in SCENARIOS]
        scenario_rows = [row for row in summary_rows if row.scenario === scenario]
        true_row = only(row for row in scenario_rows
            if row.model === :true_q_mgmfrm_oracle)
        for row in scenario_rows
            row.model === :true_q_mgmfrm_oracle && continue
            push!(output, (;
                scenario,
                comparison = Symbol(string(:true_q_mgmfrm_oracle, "_minus_",
                    row.model)),
                mean_elpd_gain = round3(true_row.mean_heldout_elpd -
                                        row.mean_heldout_elpd),
                mean_mae_reduction = round3(row.mean_heldout_expected_score_mae -
                                            true_row.mean_heldout_expected_score_mae),
                public_claim_allowed = false,
            ))
        end
    end
    return output
end

function estimation_budget_rows(summary_rows, delta_rows)
    output = NamedTuple[]
    for scenario in [scenario.scenario for scenario in SCENARIOS]
        true_row = only(row for row in summary_rows
            if row.scenario === scenario &&
               row.model === :true_q_mgmfrm_oracle)
        null_delta = only(row for row in delta_rows
            if row.scenario === scenario &&
               row.comparison ===
                   :true_q_mgmfrm_oracle_minus_null_or_intercept_reference)
        implication =
            null_delta.mean_elpd_gain > 100 ?
            :large_margin_should_survive_moderate_estimation_error :
            :small_margin_can_flip_under_posterior_or_prior_miscalibration
        push!(output, (;
            scenario,
            mean_heldout_n = true_row.mean_n_heldout,
            oracle_true_q_gain_vs_null = null_delta.mean_elpd_gain,
            per_heldout_observation_gain =
                round4(null_delta.mean_elpd_gain / true_row.mean_n_heldout),
            estimation_loss_needed_for_null_to_match =
                null_delta.mean_elpd_gain,
            implication,
            public_claim_allowed = false,
        ))
    end
    return output
end

function scenario_rows(summary_rows)
    rows = NamedTuple[]
    for scenario in SCENARIOS
        group = [row for row in summary_rows
            if row.scenario === scenario.scenario]
        leader = first(sort(group; by = row -> row.mean_rank))
        push!(rows, (;
            scenario = scenario.scenario,
            role = scenario.role,
            n_persons = scenario.n_persons,
            n_items = scenario.n_items,
            n_raters = scenario.n_raters,
            n_replicates = scenario.n_replicates,
            heldout_fraction = scenario.heldout_fraction,
            ability_scale = scenario.ability_scale,
            item_discrimination_scale = scenario.item_discrimination_scale,
            rater_severity_scale = scenario.rater_severity_scale,
            rater_consistency_spread = scenario.rater_consistency_spread,
            expected_best_model = scenario.expected_best_model,
            observed_best_model = leader.model,
            observed_best_matches_expected =
                leader.model === scenario.expected_best_model,
            interpretation = scenario.expected_alignment,
            public_claim_allowed = false,
        ))
    end
    return rows
end

function finding_rows(scenarios, delta_rows)
    uto = only(row for row in scenarios
        if row.scenario === :uto_like_multidimensional_strong_signal)
    compact = only(row for row in scenarios
        if row.scenario === :compact_weak_signal_failure_like)
    uto_null = only(row for row in delta_rows
        if row.scenario === :uto_like_multidimensional_strong_signal &&
           row.comparison === :true_q_mgmfrm_oracle_minus_null_or_intercept_reference)
    compact_null = only(row for row in delta_rows
        if row.scenario === :compact_weak_signal_failure_like &&
           row.comparison === :true_q_mgmfrm_oracle_minus_null_or_intercept_reference)
    return [
        (finding = :uto_like_condition_reproduces_direction,
            severity = uto.observed_best_matches_expected ? :info : :warning,
            evidence = string("observed best = ", uto.observed_best_model,
                "; expected = ", uto.expected_best_model,
                "; true-Q ELPD gain vs null = ", uto_null.mean_elpd_gain),
            implication = :uto_style_improvement_requires_real_multidimensional_signal_and_design_support),
        (finding = :compact_weak_signal_keeps_oracle_advantage_but_small,
            severity = compact.observed_best_model === :true_q_mgmfrm_oracle ?
                :warning : :info,
            evidence = string("observed best = ", compact.observed_best_model,
                "; true-Q ELPD gain vs null = ", compact_null.mean_elpd_gain),
            implication = :current_null_win_requires_estimation_noise_prior_shrinkage_or_calibration_loss),
        (finding = :oracle_not_mcmc_fit,
            severity = :warning,
            evidence = "uses known truth and empirical references; no posterior refit",
            implication = :next_step_is_small_mcmc_refit_under_uto_like_known_truth),
        (finding = :public_claims_blocked,
            severity = :blocker,
            evidence = "local simulation only; no real-data or full MCMC validation",
            implication = :do_not_claim_mgmfrm_superiority),
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
        println(io, "# Uto-Style MGMFRM Oracle Simulation")
        println(io)
        println(io, "- Generated at: `", artifact.generated_at, "`")
        println(io, "- Local only: `true`")
        println(io, "- Public claims allowed: `false`")
        println(io)
        println(io, "## Interpretation")
        println(io)
        println(io,
            "This is a known-truth oracle simulation, not an MCMC refit. ",
            "It asks whether Uto-style conditions themselves point in the ",
            "same direction as the literature before we spend time on a larger ",
            "posterior refit.")
        println(io)
        println(io, "## Findings")
        table(io, ["Finding", "Severity", "Evidence", "Implication"], [
            [row.finding, row.severity, row.evidence, row.implication]
            for row in artifact.finding_rows
        ])
        println(io, "## Scenarios")
        table(io, ["Scenario", "Role", "Persons", "Items", "Raters",
                "Replicates", "Expected Best", "Observed Best", "Match"],
            [[row.scenario, row.role, row.n_persons, row.n_items,
                row.n_raters, row.n_replicates, row.expected_best_model,
                row.observed_best_model, row.observed_best_matches_expected]
             for row in artifact.scenario_rows])
        println(io, "## Model Summary")
        table(io, ["Scenario", "Model", "Heldout N", "Mean Rank", "Wins",
                "Mean ELPD", "SD ELPD", "Mean MAE"],
            [[row.scenario, row.model, row.mean_n_heldout, row.mean_rank,
                row.n_replicate_wins, row.mean_heldout_elpd,
                row.sd_heldout_elpd, row.mean_heldout_expected_score_mae]
             for row in artifact.model_summary_rows])
        println(io, "## True-Q MGMFRM Deltas")
        table(io, ["Scenario", "Comparison", "Mean ELPD Gain",
                "Mean MAE Reduction"],
            [[row.scenario, row.comparison, row.mean_elpd_gain,
                row.mean_mae_reduction]
             for row in artifact.delta_summary_rows])
        println(io, "## Estimation Error Budget")
        table(io, ["Scenario", "Heldout N", "Oracle Gain vs Null",
                "Gain per Heldout Row", "Loss Needed to Tie Null",
                "Implication"],
            [[row.scenario, row.mean_heldout_n,
                row.oracle_true_q_gain_vs_null,
                row.per_heldout_observation_gain,
                row.estimation_loss_needed_for_null_to_match,
                row.implication]
             for row in artifact.estimation_budget_rows])
        println(io, "## Boundary")
        println(io)
        println(io,
            "The result separates data-generating signal from estimation. ",
            "It supports the Uto-style direction under strong known-truth ",
            "conditions, but the compact condition shows that the oracle margin ",
            "is small enough for posterior recovery, prior sensitivity, or ",
            "calibration loss to change the observed ranking.")
    end
    return path
end

function build_artifact()
    replicate_surface = scenario_replicate_rows()
    summaries = model_summary_rows(replicate_surface)
    deltas = delta_summary_rows(summaries)
    budgets = estimation_budget_rows(summaries, deltas)
    scenarios = scenario_rows(summaries)
    findings = finding_rows(scenarios, deltas)
    return (;
        schema = OUTPUT_SCHEMA,
        family = :mgmfrm,
        scope = :uto_style_known_truth_oracle_simulation,
        status = :local_oracle_simulation_recorded,
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
        simulation_design = (;
            q_true = [collect(row) for row in eachrow(Q_TRUE)],
            q_wrong = [collect(row) for row in eachrow(Q_WRONG)],
            category_levels = CATEGORY_LEVELS,
            source_scale = 1.7,
            split = :observation_holdout,
            scoring = :known_truth_oracle_and_training_empirical_references,
        ),
        literature_alignment = [
            (source = :uto_2021_multidimensional_gmfrm,
                implemented_condition =
                    :multidimensional_rubric_items_with_rater_severity_and_consistency,
                omitted_condition = :posterior_hmc_refit,
                implication = :oracle_precheck_before_mcmc),
            (source = :current_local_failure_case,
                implemented_condition = :compact_weak_signal_contrast,
                omitted_condition = :same_synthetic_rows_as_publication_batch,
                implication = :mechanism_probe_not_exact_replication),
        ],
        scenario_rows = scenarios,
        model_summary_rows = summaries,
        delta_summary_rows = deltas,
        estimation_budget_rows = budgets,
        finding_rows = findings,
        replicate_surface_rows = replicate_surface,
        summary = (;
            passed = true,
            n_scenarios = length(scenarios),
            n_replicate_surface_rows = length(replicate_surface),
            compact_true_q_gain_vs_null =
                only(row for row in budgets if row.scenario ===
                    :compact_weak_signal_failure_like).oracle_true_q_gain_vs_null,
            compact_loss_needed_for_null_to_match =
                only(row for row in budgets if row.scenario ===
                    :compact_weak_signal_failure_like).
                    estimation_loss_needed_for_null_to_match,
            uto_like_observed_best =
                only(row for row in scenarios if row.scenario ===
                    :uto_like_multidimensional_strong_signal).observed_best_model,
            compact_observed_best =
                only(row for row in scenarios if row.scenario ===
                    :compact_weak_signal_failure_like).observed_best_model,
            no_public_fit_metric_claim = true,
            no_public_q_revision_claim = true,
            no_public_model_weight_claim = true,
            no_sparse_superiority_claim = true,
            next_gate = :small_mcmc_refit_under_uto_like_known_truth,
        ),
    )
end

function main(args = ARGS)
    options = parse_args(args)
    artifact = build_artifact()
    write_artifact(options.output_json, artifact)
    render_markdown(options.output_md, artifact)
    println("wrote ", rel(options.output_json))
    println("wrote ", rel(options.output_md))
    println("uto_like_best=", artifact.summary.uto_like_observed_best,
        " compact_best=", artifact.summary.compact_observed_best,
        " next_gate=", artifact.summary.next_gate)
end

main()
