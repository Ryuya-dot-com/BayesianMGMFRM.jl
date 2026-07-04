#!/usr/bin/env julia

using SHA
using TOML

import BayesianMGMFRM

module GMFRMIntervalDecisionGrid
include(joinpath(@__DIR__, "generate_gmfrm_interval_decision_grid.jl"))
end

module GMFRMSparseDesignGrid
include(joinpath(@__DIR__, "generate_gmfrm_sparse_design_grid.jl"))
end

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures", "gmfrm_waic_influence_review.json")

include(joinpath(@__DIR__, "local_json.jl"))

const BASE = GMFRMIntervalDecisionGrid.GMFRMBaselineCalibrationGrid
const SMOKE = BASE.GMFRMRecoverySmoke

const PROTOCOL = (;
    protocol_id = "scalar_gmfrm_waic_influence_review_v1",
    simulation_sources = (
        :scalar_gmfrm_interval_decision_grid_v1,
        :scalar_gmfrm_sparse_design_grid_v1,
    ),
    review_kind = :local_pointwise_waic_influence_review,
    publication_or_registration_action = false,
    pointwise_threshold = 0.4,
    influence_action = :remove_union_of_flagged_observations_within_scenario,
    models = GMFRMIntervalDecisionGrid.PROTOCOL.models,
    gmfrm_sampler = GMFRMIntervalDecisionGrid.PROTOCOL.gmfrm_sampler,
    baseline_sampler = GMFRMIntervalDecisionGrid.PROTOCOL.baseline_sampler,
    diagnostics = GMFRMIntervalDecisionGrid.PROTOCOL.diagnostics,
    decision_rules = (;
        public_exposure_decision = :keep_internal,
        high_variance_waic_review_recorded = true,
        require_all_samplers_passed = true,
        require_masked_comparison_finite = true,
        psis_loo_or_exact_loo_required_before_public_exposure = true,
    ),
    thresholds = (;
        n_full_crossed_scenarios = length(BASE.SCENARIOS),
        n_sparse_scenarios = length(GMFRMSparseDesignGrid.SCENARIOS),
        n_models_per_scenario = length(GMFRMIntervalDecisionGrid.PROTOCOL.models),
        min_retained_observations_after_mask = 4,
        require_same_observations_within_scenario = true,
        require_sampler_passed = true,
        require_finite_elpd = true,
    ),
)

function usage()
    return """
    Generate the local scalar GMFRM WAIC influence-review artifact.

    Usage:
      julia --project=. scripts/generate_gmfrm_waic_influence_review.jl [--output PATH]
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

function pointwise_se(values::AbstractVector{<:Real})
    n = length(values)
    n <= 1 && return NaN
    mean_value = sum(Float64, values) / n
    ss = sum((Float64(value) - mean_value)^2 for value in values)
    return sqrt(n * ss / (n - 1))
end

function maybe_float(value)
    return ismissing(value) ? missing : Float64(value)
end

function maybe_int(value)
    return ismissing(value) ? missing : Int(value)
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

function baseline_model_with_loglik(data, model::Symbol, thresholds::Symbol, seed::Int)
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
    loglik = BayesianMGMFRM.pointwise_loglikelihood_matrix(fit)
    stat = BayesianMGMFRM.waic(loglik)
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
    result = BASE.model_record(record, stat, expected, data.score)
    return (; result, loglik, stat, design)
end

function gmfrm_model_with_loglik(data, table, seed::Int)
    gmfrm = GMFRMIntervalDecisionGrid.gmfrm_result_with_diagnostics(data, table, seed)
    loglik = gmfrm.diagnostics.direct_pointwise_loglikelihood
    stat = BayesianMGMFRM.waic(loglik)
    return (; result = gmfrm.result, loglik, stat, design = gmfrm.design)
end

function comparison_rows(models, stats)
    order = sortperm(eachindex(stats); by = index -> stats[index].elpd_waic, rev = true)
    best = stats[order[1]]
    unnormalized_weights = [exp(stat.elpd_waic - best.elpd_waic) for stat in stats]
    weight_total = sum(unnormalized_weights)
    rows = NamedTuple[]
    for (rank, index) in pairs(order)
        result = models[index].result
        stat = stats[index]
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
        ))
    end
    return rows
end

function observation_record(data, observation::Int)
    return (;
        observation,
        person = data.person_levels[data.person[observation]],
        rater = data.rater_levels[data.rater[observation]],
        item = data.item_levels[data.item[observation]],
        score = data.score[observation],
        category = data.category_levels[data.category[observation]],
    )
end

function flagged_rows(data, model, stat)
    rows = NamedTuple[]
    threshold = PROTOCOL.pointwise_threshold
    for observation in 1:stat.n_observations
        p_waic = stat.pointwise.p_waic[observation]
        p_waic > threshold || continue
        push!(rows, (;
            model = model.result.model,
            observation_record(data, observation)...,
            p_waic,
            lppd = stat.pointwise.lppd[observation],
            elpd_waic = stat.pointwise.elpd_waic[observation],
            waic = stat.pointwise.waic[observation],
            threshold,
            flag = :high_loglik_variance,
        ))
    end
    sort!(rows; by = row -> (-row.p_waic, String(row.model), row.observation))
    return rows
end

function masked_stat(model, retained_observations)
    return BayesianMGMFRM.waic(model.loglik[:, retained_observations])
end

function full_crossed_source_record(spec)
    simulated = BASE.table_for_scenario(spec)
    return (;
        scenario_group = :full_crossed,
        scenario = spec.scenario,
        sparse_pattern = missing,
        simulation_seed = spec.simulation_seed,
        table = simulated.table,
        gmfrm_seed = spec.gmfrm_seed,
        partial_credit_seed = spec.partial_credit_seed,
        rating_scale_seed = spec.rating_scale_seed,
    )
end

function sparse_source_record(spec)
    simulated = GMFRMSparseDesignGrid.table_for_scenario(spec)
    return (;
        scenario_group = :sparse_connected,
        scenario = spec.scenario,
        sparse_pattern = spec.sparse_pattern,
        simulation_seed = simulated.actual_simulation_seed,
        table = simulated.table,
        gmfrm_seed = spec.gmfrm_seed,
        partial_credit_seed = spec.partial_credit_seed,
        rating_scale_seed = spec.rating_scale_seed,
    )
end

function scenario_passed(full_rows, masked_rows, flagged_union, n_observations)
    thresholds = PROTOCOL.thresholds
    length(full_rows) == thresholds.n_models_per_scenario || return false
    length(masked_rows) == thresholds.n_models_per_scenario || return false
    if thresholds.require_same_observations_within_scenario
        length(unique(row.n_observations for row in full_rows)) == 1 || return false
    end
    retained = n_observations - length(flagged_union)
    retained >= thresholds.min_retained_observations_after_mask || return false
    if thresholds.require_sampler_passed
        all(row -> row.sampler_summary.internal_passed, full_rows) || return false
    end
    if thresholds.require_finite_elpd
        all(row -> isfinite(row.elpd_waic) && isfinite(row.waic), full_rows) ||
            return false
        all(row -> isfinite(row.elpd_waic) && isfinite(row.waic), masked_rows) ||
            return false
    end
    return true
end

function scenario_review(source)
    data = SMOKE.facet_data(source.table)
    models = [
        gmfrm_model_with_loglik(data, source.table, source.gmfrm_seed),
        baseline_model_with_loglik(
            data,
            :mfrm_partial_credit,
            :partial_credit,
            source.partial_credit_seed,
        ),
        baseline_model_with_loglik(
            data,
            :mfrm_rating_scale,
            :rating_scale,
            source.rating_scale_seed,
        ),
    ]
    stats = [model.stat for model in models]
    full_rows = comparison_rows(models, stats)
    flagged_by_model = reduce(vcat, [flagged_rows(data, model, model.stat)
        for model in models]; init = NamedTuple[])
    flagged_union = sort(unique(row.observation for row in flagged_by_model))
    retained_observations = setdiff(collect(1:data.n), flagged_union)
    masked_stats = [masked_stat(model, retained_observations) for model in models]
    masked_rows = comparison_rows(models, masked_stats)
    gmfrm_full = only(row for row in full_rows if row.model === :gmfrm_internal_candidate)
    gmfrm_masked = only(row for row in masked_rows if row.model === :gmfrm_internal_candidate)
    passed = scenario_passed(full_rows, masked_rows, flagged_union, data.n)
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
        full_comparison_rows = full_rows,
        flagged_observation_rows = flagged_by_model,
        flagged_observation_union = [
            observation_record(data, observation) for observation in flagged_union
        ],
        masked_comparison_rows = masked_rows,
        influence_summary = (;
            passed,
            n_observations = data.n,
            n_flagged_model_observations = length(flagged_by_model),
            n_flagged_unique_observations = length(flagged_union),
            flagged_unique_fraction = length(flagged_union) / data.n,
            n_retained_observations = length(retained_observations),
            max_p_waic = maximum(row.p_waic for row in flagged_by_model),
            full_best_model = full_rows[1].model,
            masked_best_model = masked_rows[1].model,
            best_model_changed = full_rows[1].model !== masked_rows[1].model,
            gmfrm_full_rank = gmfrm_full.rank,
            gmfrm_masked_rank = gmfrm_masked.rank,
            gmfrm_rank_changed = gmfrm_full.rank != gmfrm_masked.rank,
            gmfrm_full_elpd_difference = gmfrm_full.elpd_difference,
            gmfrm_masked_elpd_difference = gmfrm_masked.elpd_difference,
            all_samplers_passed =
                all(row -> row.sampler_summary.internal_passed, full_rows),
            all_masked_comparisons_finite =
                all(row -> isfinite(row.elpd_waic) && isfinite(row.waic),
                    masked_rows),
            selected_decision = :keep_internal,
        ),
    )
end

function grid_artifact()
    sources = [
        [full_crossed_source_record(spec) for spec in BASE.SCENARIOS]...,
        [sparse_source_record(spec) for spec in GMFRMSparseDesignGrid.SCENARIOS]...,
    ]
    reviews = [scenario_review(source) for source in sources]
    all_full_rows = reduce(vcat, [review.full_comparison_rows for review in reviews])
    all_masked_rows = reduce(vcat, [review.masked_comparison_rows for review in reviews])
    all_flagged_rows = reduce(vcat, [review.flagged_observation_rows for review in reviews])
    passed = all(review -> review.influence_summary.passed, reviews)
    keep_internal_count =
        count(review -> review.influence_summary.selected_decision === :keep_internal,
            reviews)
    return (;
        schema = "bayesianmgmfrm.gmfrm_waic_influence_review.v1",
        family = :gmfrm,
        scope = :scalar_gmfrm_fit_ready_candidate,
        status = :internal_waic_influence_review,
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
                :pointwise_waic_influence_review_recorded_but_high_variance_persists,
            required_followup = :psis_loo_or_exact_loo_review,
        ),
        summary = (;
            passed,
            n_scenario_reviews = length(reviews),
            n_full_crossed_scenarios =
                count(review -> review.scenario_group === :full_crossed, reviews),
            n_sparse_scenarios =
                count(review -> review.scenario_group === :sparse_connected, reviews),
            n_passed_scenarios =
                count(review -> review.influence_summary.passed, reviews),
            n_models = length(all_full_rows),
            n_flagged_model_observations = length(all_flagged_rows),
            max_p_waic = maximum(row.p_waic for row in all_flagged_rows),
            min_retained_observations =
                minimum(review.influence_summary.n_retained_observations
                    for review in reviews),
            n_best_model_changes_after_flagged_removal =
                count(review -> review.influence_summary.best_model_changed, reviews),
            n_gmfrm_rank_changes_after_flagged_removal =
                count(review -> review.influence_summary.gmfrm_rank_changed, reviews),
            all_samplers_passed =
                all(review -> review.influence_summary.all_samplers_passed, reviews),
            all_masked_comparisons_finite =
                all(review -> review.influence_summary.all_masked_comparisons_finite,
                    reviews),
            any_high_variance_waic =
                any(row -> row.warning !== :ok, all_full_rows) ||
                any(row -> row.warning !== :ok, all_masked_rows),
            keep_internal_decision_count = keep_internal_count,
            decision_stability =
                keep_internal_count == length(reviews) ? :stable_keep_internal :
                :unstable,
            remaining_public_blockers = [
                :high_variance_waic_requires_psis_loo_followup,
            ],
            recommendation = :keep_internal_until_psis_loo_followup,
            next_gate = :scalar_gmfrm_psis_loo_review,
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
        " flagged=", artifact.summary.n_flagged_model_observations,
        " best_model_changes=",
        artifact.summary.n_best_model_changes_after_flagged_removal,
        " next=", artifact.summary.next_gate)
    return nothing
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    main(ARGS)
end
