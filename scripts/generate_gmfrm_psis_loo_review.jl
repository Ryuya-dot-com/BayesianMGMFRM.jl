#!/usr/bin/env julia

using TOML

import BayesianMGMFRM

module GMFRMWAICInfluenceReview
include(joinpath(@__DIR__, "generate_gmfrm_waic_influence_review.jl"))
end

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures", "gmfrm_psis_loo_review.json")

include(joinpath(@__DIR__, "local_json.jl"))

const WAIC_REVIEW = GMFRMWAICInfluenceReview
const BASE = WAIC_REVIEW.BASE
const SMOKE = WAIC_REVIEW.SMOKE

const PROTOCOL = (;
    protocol_id = "scalar_gmfrm_psis_loo_review_v1",
    simulation_sources = (
        :scalar_gmfrm_interval_decision_grid_v1,
        :scalar_gmfrm_sparse_design_grid_v1,
        :scalar_gmfrm_waic_influence_review_v1,
    ),
    review_kind = :local_raw_importance_loo_pareto_k_review,
    publication_or_registration_action = false,
    psis_smoothing_enabled = false,
    loo_method = :raw_importance_sampling,
    pareto_k_estimator = :hill_log_tail,
    pareto_k_threshold = 0.7,
    tail_fraction = 0.2,
    min_tail_draws = 5,
    models = WAIC_REVIEW.PROTOCOL.models,
    gmfrm_sampler = WAIC_REVIEW.PROTOCOL.gmfrm_sampler,
    baseline_sampler = WAIC_REVIEW.PROTOCOL.baseline_sampler,
    diagnostics = WAIC_REVIEW.PROTOCOL.diagnostics,
    decision_rules = (;
        public_exposure_decision = :keep_internal,
        raw_importance_loo_review_recorded = true,
        psis_smoothing_enabled = false,
        require_all_samplers_passed = true,
        require_finite_loo_comparison = true,
        high_pareto_k_blocks_public_exposure = true,
        exact_loo_or_kfold_required_before_public_exposure = true,
    ),
    thresholds = (;
        n_full_crossed_scenarios = length(BASE.SCENARIOS),
        n_sparse_scenarios =
            length(WAIC_REVIEW.GMFRMSparseDesignGrid.SCENARIOS),
        n_models_per_scenario = length(WAIC_REVIEW.PROTOCOL.models),
        require_same_observations_within_scenario = true,
        require_sampler_passed = true,
        require_finite_elpd = true,
    ),
)

function usage()
    return """
    Generate the local scalar GMFRM PSIS/LOO review artifact.

    This artifact records raw importance-sampling LOO and Pareto-k screening.
    It does not perform public registration, publishing, or PSIS smoothing.

    Usage:
      julia --project=. scripts/generate_gmfrm_psis_loo_review.jl [--output PATH]
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

function pointwise_se(values::AbstractVector{<:Real})
    n = length(values)
    n <= 1 && return NaN
    mean_value = sum(Float64, values) / n
    ss = sum((Float64(value) - mean_value)^2 for value in values)
    return sqrt(n * ss / (n - 1))
end

function full_crossed_source_record(spec)
    return WAIC_REVIEW.full_crossed_source_record(spec)
end

function sparse_source_record(spec)
    return WAIC_REVIEW.sparse_source_record(spec)
end

function loo_stat(model)
    return BayesianMGMFRM.loo(model.loglik;
        pareto_k_threshold = PROTOCOL.pareto_k_threshold,
        tail_fraction = PROTOCOL.tail_fraction,
        min_tail_draws = PROTOCOL.min_tail_draws)
end

function waic_comparison_rows(models, stats)
    return WAIC_REVIEW.comparison_rows(models, stats)
end

function loo_comparison_rows(models, stats)
    order = sortperm(eachindex(stats); by = index -> stats[index].elpd_loo, rev = true)
    best = stats[order[1]]
    unnormalized_weights = [exp(stat.elpd_loo - best.elpd_loo) for stat in stats]
    weight_total = sum(unnormalized_weights)
    rows = NamedTuple[]
    for (rank, index) in pairs(order)
        result = models[index].result
        stat = stats[index]
        pointwise_difference = stat.pointwise.elpd_loo .- best.pointwise.elpd_loo
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
            criterion = :loo,
            method = stat.method,
            psis_smoothing = stat.psis_smoothing,
            pareto_k_estimator = stat.pareto_k_estimator,
            elpd_loo = stat.elpd_loo,
            elpd_difference = stat.elpd_loo - best.elpd_loo,
            se_elpd_difference = pointwise_se(pointwise_difference),
            se_elpd_loo = stat.se_elpd_loo,
            looic = stat.looic,
            looic_difference = stat.looic - best.looic,
            se_looic = stat.se_looic,
            relative_weight = unnormalized_weights[index] / weight_total,
            p_loo = stat.p_loo,
            lppd = stat.lppd,
            n_draws = stat.n_draws,
            n_observations = stat.n_observations,
            max_pareto_k = stat.max_pareto_k,
            bad_pareto_k_count = stat.bad_pareto_k_count,
            min_effective_sample_size = stat.min_effective_sample_size,
            warning = stat.warning,
        ))
    end
    return rows
end

function observation_record(data, observation::Int)
    return WAIC_REVIEW.observation_record(data, observation)
end

function pareto_flagged_rows(data, model, stat)
    rows = NamedTuple[]
    threshold = PROTOCOL.pareto_k_threshold
    for observation in 1:stat.n_observations
        pareto_k = stat.pointwise.pareto_k[observation]
        pareto_k > threshold || continue
        push!(rows, (;
            model = model.result.model,
            observation_record(data, observation)...,
            pareto_k,
            effective_sample_size =
                stat.pointwise.effective_sample_size[observation],
            tail_draws = stat.pointwise.tail_draws[observation],
            lppd = stat.pointwise.lppd[observation],
            p_loo = stat.pointwise.p_loo[observation],
            elpd_loo = stat.pointwise.elpd_loo[observation],
            looic = stat.pointwise.looic[observation],
            threshold,
            flag = :high_pareto_k,
        ))
    end
    sort!(rows; by = row -> (-row.pareto_k, String(row.model), row.observation))
    return rows
end

function scenario_passed(waic_rows, loo_rows)
    thresholds = PROTOCOL.thresholds
    length(waic_rows) == thresholds.n_models_per_scenario || return false
    length(loo_rows) == thresholds.n_models_per_scenario || return false
    if thresholds.require_same_observations_within_scenario
        length(unique(row.n_observations for row in loo_rows)) == 1 || return false
    end
    if thresholds.require_sampler_passed
        all(row -> row.sampler_summary.internal_passed, loo_rows) || return false
    end
    if thresholds.require_finite_elpd
        all(row -> isfinite(row.elpd_waic) && isfinite(row.waic), waic_rows) ||
            return false
        all(row -> isfinite(row.elpd_loo) && isfinite(row.looic), loo_rows) ||
            return false
    end
    return true
end

function scenario_review(source)
    data = SMOKE.facet_data(source.table)
    models = [
        WAIC_REVIEW.gmfrm_model_with_loglik(data, source.table, source.gmfrm_seed),
        WAIC_REVIEW.baseline_model_with_loglik(
            data,
            :mfrm_partial_credit,
            :partial_credit,
            source.partial_credit_seed,
        ),
        WAIC_REVIEW.baseline_model_with_loglik(
            data,
            :mfrm_rating_scale,
            :rating_scale,
            source.rating_scale_seed,
        ),
    ]
    waic_stats = [model.stat for model in models]
    loo_stats = [loo_stat(model) for model in models]
    waic_rows = waic_comparison_rows(models, waic_stats)
    loo_rows = loo_comparison_rows(models, loo_stats)
    flagged_rows = reduce(vcat, [pareto_flagged_rows(data, model, stat)
        for (model, stat) in zip(models, loo_stats)]; init = NamedTuple[])
    flagged_union = sort(unique(row.observation for row in flagged_rows))
    gmfrm_waic = only(row for row in waic_rows if row.model === :gmfrm_internal_candidate)
    gmfrm_loo = only(row for row in loo_rows if row.model === :gmfrm_internal_candidate)
    passed = scenario_passed(waic_rows, loo_rows)
    return (;
        scenario_group = source.scenario_group,
        scenario = source.scenario,
        sparse_pattern = source.sparse_pattern,
        simulation_seed = source.simulation_seed,
        simulated_data = (;
            n_observations = data.n,
            score_counts = BASE.score_count_rows(source.table.score),
            person_levels = data.person_levels,
            rater_levels = data.rater_levels,
            item_levels = data.item_levels,
            category_levels = data.category_levels,
        ),
        waic_comparison_rows = waic_rows,
        loo_comparison_rows = loo_rows,
        high_pareto_observation_rows = flagged_rows,
        high_pareto_observation_union = [
            observation_record(data, observation) for observation in flagged_union
        ],
        loo_summary = (;
            passed,
            n_observations = data.n,
            n_high_pareto_model_observations = length(flagged_rows),
            n_high_pareto_unique_observations = length(flagged_union),
            high_pareto_unique_fraction = length(flagged_union) / data.n,
            max_pareto_k = maximum(row.max_pareto_k for row in loo_rows),
            min_effective_sample_size =
                minimum(row.min_effective_sample_size for row in loo_rows),
            waic_best_model = waic_rows[1].model,
            loo_best_model = loo_rows[1].model,
            best_model_changed_from_waic =
                waic_rows[1].model !== loo_rows[1].model,
            gmfrm_waic_rank = gmfrm_waic.rank,
            gmfrm_loo_rank = gmfrm_loo.rank,
            gmfrm_rank_changed_from_waic =
                gmfrm_waic.rank != gmfrm_loo.rank,
            gmfrm_waic_elpd_difference = gmfrm_waic.elpd_difference,
            gmfrm_loo_elpd_difference = gmfrm_loo.elpd_difference,
            all_samplers_passed =
                all(row -> row.sampler_summary.internal_passed, loo_rows),
            all_loo_comparisons_finite =
                all(row -> isfinite(row.elpd_loo) && isfinite(row.looic),
                    loo_rows),
            any_high_pareto_k = any(row -> row.warning !== :ok, loo_rows),
            selected_decision = :keep_internal,
        ),
    )
end

function grid_artifact()
    sources = [
        [full_crossed_source_record(spec) for spec in BASE.SCENARIOS]...,
        [sparse_source_record(spec)
            for spec in WAIC_REVIEW.GMFRMSparseDesignGrid.SCENARIOS]...,
    ]
    reviews = [scenario_review(source) for source in sources]
    all_loo_rows = reduce(vcat, [review.loo_comparison_rows for review in reviews])
    all_flagged_rows = reduce(vcat,
        [review.high_pareto_observation_rows for review in reviews];
        init = NamedTuple[])
    passed = all(review -> review.loo_summary.passed, reviews)
    keep_internal_count =
        count(review -> review.loo_summary.selected_decision === :keep_internal,
            reviews)
    any_high_pareto_k = any(row -> row.warning !== :ok, all_loo_rows)
    remaining_public_blockers = any_high_pareto_k ?
        [:high_pareto_k_requires_exact_loo_or_kfold_followup] :
        [:raw_importance_loo_requires_psis_or_exact_loo_confirmation]
    recommendation = any_high_pareto_k ?
        :keep_internal_until_exact_loo_or_kfold_followup :
        :keep_internal_until_psis_or_exact_loo_confirmation
    next_gate = any_high_pareto_k ?
        :scalar_gmfrm_exact_loo_or_kfold_review :
        :scalar_gmfrm_psis_smoothing_or_exact_loo_confirmation
    return (;
        schema = "bayesianmgmfrm.gmfrm_psis_loo_review.v1",
        family = :gmfrm,
        scope = :scalar_gmfrm_fit_ready_candidate,
        status = :internal_psis_loo_review,
        public_fit = false,
        experimental_public = false,
        fit_ready = false,
        package = (;
            name = "BayesianMGMFRM",
            version = project_version(),
            julia_version = string(VERSION),
        ),
        protocol = PROTOCOL,
        scenario_reviews = reviews,
        decision_record = (;
            selected_decision = :keep_internal,
            public_fit_allowed = false,
            experimental_keyword_enabled = false,
            public_exposure_support = :insufficient_for_public_experimental_fit,
            interpretation =
                :raw_importance_loo_review_recorded_but_not_public_sufficient,
            required_followup =
                any_high_pareto_k ? :exact_loo_or_kfold_review :
                :psis_smoothing_or_exact_loo_confirmation,
        ),
        summary = (;
            passed,
            n_scenario_reviews = length(reviews),
            n_full_crossed_scenarios =
                count(review -> review.scenario_group === :full_crossed, reviews),
            n_sparse_scenarios =
                count(review -> review.scenario_group === :sparse_connected, reviews),
            n_passed_scenarios =
                count(review -> review.loo_summary.passed, reviews),
            n_models = length(all_loo_rows),
            n_high_pareto_model_observations = length(all_flagged_rows),
            n_high_pareto_unique_scenario_observations =
                sum(review -> review.loo_summary.n_high_pareto_unique_observations,
                    reviews),
            max_pareto_k = maximum(row.max_pareto_k for row in all_loo_rows),
            min_effective_sample_size =
                minimum(row.min_effective_sample_size for row in all_loo_rows),
            n_best_model_changes_from_waic_to_loo =
                count(review -> review.loo_summary.best_model_changed_from_waic,
                    reviews),
            n_gmfrm_rank_changes_from_waic_to_loo =
                count(review -> review.loo_summary.gmfrm_rank_changed_from_waic,
                    reviews),
            all_samplers_passed =
                all(review -> review.loo_summary.all_samplers_passed, reviews),
            all_loo_comparisons_finite =
                all(review -> review.loo_summary.all_loo_comparisons_finite,
                    reviews),
            any_high_pareto_k,
            psis_smoothing_enabled = false,
            keep_internal_decision_count = keep_internal_count,
            decision_stability =
                keep_internal_count == length(reviews) ? :stable_keep_internal :
                :unstable,
            remaining_public_blockers,
            recommendation,
            next_gate,
        ),
    )
end

function main(args)
    output = parse_args(args)
    artifact = grid_artifact()
    write_artifact(output, artifact)
    println("Wrote ", output)
    println("passed=", artifact.summary.passed,
        " scenarios=", artifact.summary.n_scenario_reviews,
        " high_pareto=", artifact.summary.n_high_pareto_model_observations,
        " max_k=", artifact.summary.max_pareto_k,
        " next=", artifact.summary.next_gate)
    return nothing
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    main(ARGS)
end
