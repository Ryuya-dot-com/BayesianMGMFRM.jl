#!/usr/bin/env julia

using Random
using SHA
using TOML

import BayesianMGMFRM
import LogDensityProblems

module GMFRMPSISLOOReview
include(joinpath(@__DIR__, "generate_gmfrm_psis_loo_review.jl"))
end

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures", "gmfrm_exact_loo_or_kfold_review.json")

include(joinpath(@__DIR__, "local_json.jl"))

const PSIS_REVIEW = GMFRMPSISLOOReview
const WAIC_REVIEW = PSIS_REVIEW.WAIC_REVIEW
const BASE = PSIS_REVIEW.BASE
const SMOKE = PSIS_REVIEW.SMOKE

const PROTOCOL = (;
    protocol_id = "scalar_gmfrm_exact_loo_or_kfold_review_v1",
    simulation_sources = (
        :scalar_gmfrm_interval_decision_grid_v1,
        :scalar_gmfrm_sparse_design_grid_v1,
        :scalar_gmfrm_psis_loo_review_v1,
    ),
    review_kind = :local_refit_kfold_elpd_review,
    publication_or_registration_action = false,
    exact_loo_enabled = false,
    kfold_enabled = true,
    k_folds = 3,
    fold_seed = 1,
    prediction_target = :heldout_observation_log_score,
    models = PSIS_REVIEW.PROTOCOL.models,
    gmfrm_sampler = PSIS_REVIEW.PROTOCOL.gmfrm_sampler,
    baseline_sampler = PSIS_REVIEW.PROTOCOL.baseline_sampler,
    diagnostics = PSIS_REVIEW.PROTOCOL.diagnostics,
    decision_rules = (;
        public_exposure_decision = :keep_internal,
        exact_loo_or_kfold_review_recorded = true,
        require_all_training_designs_parameter_order_matched = true,
        require_all_samplers_passed = true,
        require_finite_kfold_comparison = true,
        require_all_observations_held_out_once = true,
        guarded_fit_api_dry_run_required_before_public_exposure = true,
    ),
    thresholds = (;
        n_full_crossed_scenarios = length(BASE.SCENARIOS),
        n_sparse_scenarios =
            length(WAIC_REVIEW.GMFRMSparseDesignGrid.SCENARIOS),
        n_models_per_scenario = length(PSIS_REVIEW.PROTOCOL.models),
        n_folds = 3,
        require_same_observations_within_scenario = true,
        require_sampler_passed = true,
        require_finite_elpd = true,
        require_parameter_order_match = true,
    ),
)

function usage()
    return """
    Generate the local scalar GMFRM exact LOO / K-fold review artifact.

    This artifact records deterministic 3-fold heldout refits for the internal
    scalar GMFRM candidate and public MFRM baselines. It does not perform
    publishing, registration, or public API exposure.

    Usage:
      julia --project=. scripts/generate_gmfrm_exact_loo_or_kfold_review.jl [--output PATH]
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

function logmeanexp(values::AbstractVector{<:Real})
    isempty(values) && error("values must not be empty")
    vals = Float64.(values)
    all(isfinite, vals) || error("values contain non-finite entries")
    max_value = maximum(vals)
    return max_value + log(sum(exp(value - max_value) for value in vals) / length(vals))
end

function pointwise_se(values::AbstractVector{<:Real})
    n = length(values)
    n <= 1 && return NaN
    mean_value = sum(Float64, values) / n
    ss = sum((Float64(value) - mean_value)^2 for value in values)
    return sqrt(n * ss / (n - 1))
end

function table_subset(table, indices)
    return (;
        examinee = table.examinee[indices],
        rater = table.rater[indices],
        item = table.item[indices],
        score = table.score[indices],
    )
end

function fold_indices(n_observations::Int)
    order = shuffle(Random.MersenneTwister(PROTOCOL.fold_seed),
        collect(1:n_observations))
    return [sort(order[fold:PROTOCOL.k_folds:end]) for fold in 1:PROTOCOL.k_folds]
end

function heldout_elpd(loglik::AbstractMatrix)
    return [logmeanexp(@view loglik[:, observation])
        for observation in axes(loglik, 2)]
end

function gmfrm_direct_pointwise_loglikelihood_matrix(design, direct_draws::AbstractMatrix)
    out = Matrix{Float64}(undef, size(direct_draws, 1), design.spec.data.n)
    for draw in axes(direct_draws, 1)
        out[draw, :] .= BayesianMGMFRM._gmfrm_source_pointwise_loglikelihood(
            design,
            view(direct_draws, draw, :),
        )
    end
    return out
end

function observation_record(data, observation::Int)
    return WAIC_REVIEW.observation_record(data, observation)
end

function fold_record_common(;
        model,
        family,
        source,
        threshold_regime,
        estimation_status,
        public_fit,
        seed,
        fold,
        train_indices,
        heldout_indices,
        n_parameters,
        parameter_order_sha256,
        direct_parameter_order_sha256,
        parameter_order_matched,
        sampler_summary,
        pointwise_elpd)
    return (;
        model,
        family,
        source,
        threshold_regime,
        estimation_status,
        public_fit,
        seed,
        fold,
        n_train_observations = length(train_indices),
        n_heldout_observations = length(heldout_indices),
        heldout_observations = heldout_indices,
        n_parameters,
        parameter_order_sha256,
        direct_parameter_order_sha256,
        parameter_order_matched,
        sampler_summary,
        criterion = :kfold,
        elpd_heldout = sum(pointwise_elpd),
        kfoldic_heldout = -2 * sum(pointwise_elpd),
        se_elpd_heldout = pointwise_se(pointwise_elpd),
    )
end

function baseline_fold_result(source, full_design, model::Symbol, thresholds::Symbol,
        fold::Int, train_indices, heldout_indices, seed::Int)
    train_table = table_subset(source.table, train_indices)
    train_data = SMOKE.facet_data(train_table)
    train_spec = BayesianMGMFRM.mfrm_spec(train_data; thresholds)
    train_design = BayesianMGMFRM.getdesign(train_spec)
    parameter_order_matched =
        train_design.parameter_names == full_design.parameter_names
    parameter_order_matched ||
        error("baseline parameter order changed for $(source.scenario) fold $fold")

    sampler = PROTOCOL.baseline_sampler
    prior = BayesianMGMFRM.MFRMPrior()
    fit = BayesianMGMFRM.fit(train_design;
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
    loglik_full = BayesianMGMFRM.pointwise_loglikelihood_matrix(
        full_design,
        fit.draws,
    )
    pointwise_elpd = heldout_elpd(loglik_full[:, heldout_indices])
    record = fold_record_common(;
        model,
        family = :mfrm,
        source = :public_minimal_fit,
        threshold_regime = thresholds,
        estimation_status = :fit_supported,
        public_fit = true,
        seed,
        fold,
        train_indices,
        heldout_indices,
        n_parameters = length(train_design.parameter_names),
        parameter_order_sha256 = parameter_order_hash(train_design.parameter_names),
        direct_parameter_order_sha256 = missing,
        parameter_order_matched,
        sampler_summary = WAIC_REVIEW.baseline_sampler_summary_record(
            diagnostics.summary,
        ),
        pointwise_elpd,
    )
    return (; record, pointwise_elpd)
end

function gmfrm_fold_result(source, full_design, fold::Int, train_indices,
        heldout_indices, seed::Int)
    train_table = table_subset(source.table, train_indices)
    train_design = SMOKE.scalar_gmfrm_design(train_table)
    train_target = BayesianMGMFRM._gmfrm_promotion_candidate_logdensity(train_design)
    full_target = BayesianMGMFRM._gmfrm_promotion_candidate_logdensity(full_design)
    parameter_order_matched =
        train_target.blueprint.parameter_names == full_target.blueprint.parameter_names &&
        train_target.blueprint.constrained_parameter_names ==
            full_target.blueprint.constrained_parameter_names
    parameter_order_matched ||
        error("GMFRM parameter order changed for $(source.scenario) fold $fold")

    sampler = PROTOCOL.gmfrm_sampler
    diagnostics = BayesianMGMFRM._gmfrm_promotion_candidate_sampler_diagnostics(
        train_target,
        zeros(LogDensityProblems.dimension(train_target));
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
    loglik_full = gmfrm_direct_pointwise_loglikelihood_matrix(
        full_design,
        diagnostics.direct_draws,
    )
    pointwise_elpd = heldout_elpd(loglik_full[:, heldout_indices])
    record = fold_record_common(;
        model = :gmfrm_internal_candidate,
        family = :gmfrm,
        source = :internal_raw_candidate,
        threshold_regime = :generalized_partial_credit,
        estimation_status = :internal_promotion_candidate,
        public_fit = false,
        seed,
        fold,
        train_indices,
        heldout_indices,
        n_parameters = train_target.blueprint.n_parameters,
        parameter_order_sha256 =
            parameter_order_hash(train_target.blueprint.parameter_names),
        direct_parameter_order_sha256 =
            parameter_order_hash(train_target.blueprint.constrained_parameter_names),
        parameter_order_matched,
        sampler_summary = BASE.gmfrm_sampler_summary_record(diagnostics.summary),
        pointwise_elpd,
    )
    return (; record, pointwise_elpd)
end

function model_kfold_result(source, full_data, folds, model::Symbol)
    n = full_data.n
    pointwise = fill(NaN, n)
    records = NamedTuple[]
    if model === :gmfrm_internal_candidate
        full_design = SMOKE.scalar_gmfrm_design(source.table)
        for (fold, heldout_indices) in pairs(folds)
            train_indices = setdiff(collect(1:n), heldout_indices)
            result = gmfrm_fold_result(
                source,
                full_design,
                fold,
                train_indices,
                heldout_indices,
                source.gmfrm_seed + fold,
            )
            pointwise[heldout_indices] .= result.pointwise_elpd
            push!(records, result.record)
        end
    elseif model === :mfrm_partial_credit
        full_design = BayesianMGMFRM.getdesign(
            BayesianMGMFRM.mfrm_spec(full_data; thresholds = :partial_credit),
        )
        for (fold, heldout_indices) in pairs(folds)
            train_indices = setdiff(collect(1:n), heldout_indices)
            result = baseline_fold_result(
                source,
                full_design,
                :mfrm_partial_credit,
                :partial_credit,
                fold,
                train_indices,
                heldout_indices,
                source.partial_credit_seed + fold,
            )
            pointwise[heldout_indices] .= result.pointwise_elpd
            push!(records, result.record)
        end
    elseif model === :mfrm_rating_scale
        full_design = BayesianMGMFRM.getdesign(
            BayesianMGMFRM.mfrm_spec(full_data; thresholds = :rating_scale),
        )
        for (fold, heldout_indices) in pairs(folds)
            train_indices = setdiff(collect(1:n), heldout_indices)
            result = baseline_fold_result(
                source,
                full_design,
                :mfrm_rating_scale,
                :rating_scale,
                fold,
                train_indices,
                heldout_indices,
                source.rating_scale_seed + fold,
            )
            pointwise[heldout_indices] .= result.pointwise_elpd
            push!(records, result.record)
        end
    else
        error("unknown model: $model")
    end
    all(isfinite, pointwise) ||
        error("not all observations received heldout elpd for $(source.scenario) $model")
    first_record = first(records)
    return (;
        model,
        family = first_record.family,
        source = first_record.source,
        threshold_regime = first_record.threshold_regime,
        estimation_status = first_record.estimation_status,
        public_fit = first_record.public_fit,
        n_parameters = first_record.n_parameters,
        parameter_order_sha256 = first_record.parameter_order_sha256,
        direct_parameter_order_sha256 = first_record.direct_parameter_order_sha256,
        fold_records = records,
        pointwise_elpd = pointwise,
        elpd_kfold = sum(pointwise),
        kfoldic = -2 * sum(pointwise),
        se_elpd_kfold = pointwise_se(pointwise),
        se_kfoldic = pointwise_se(-2 .* pointwise),
        n_folds = length(folds),
        n_observations = n,
        min_train_observations =
            minimum(row.n_train_observations for row in records),
        min_heldout_observations =
            minimum(row.n_heldout_observations for row in records),
        max_heldout_observations =
            maximum(row.n_heldout_observations for row in records),
        all_parameter_orders_matched =
            all(row -> row.parameter_order_matched, records),
        all_samplers_passed =
            all(row -> row.sampler_summary.internal_passed, records),
    )
end

function kfold_comparison_rows(results)
    order = sortperm(eachindex(results); by = index -> results[index].elpd_kfold,
        rev = true)
    best = results[order[1]]
    unnormalized_weights =
        [exp(result.elpd_kfold - best.elpd_kfold) for result in results]
    weight_total = sum(unnormalized_weights)
    rows = NamedTuple[]
    for (rank, index) in pairs(order)
        result = results[index]
        pointwise_difference = result.pointwise_elpd .- best.pointwise_elpd
        push!(rows, (;
            model = result.model,
            family = result.family,
            source = result.source,
            threshold_regime = result.threshold_regime,
            estimation_status = result.estimation_status,
            public_fit = result.public_fit,
            n_parameters = result.n_parameters,
            parameter_order_sha256 = result.parameter_order_sha256,
            direct_parameter_order_sha256 = result.direct_parameter_order_sha256,
            rank,
            criterion = :kfold,
            prediction_target = PROTOCOL.prediction_target,
            elpd_kfold = result.elpd_kfold,
            elpd_difference = result.elpd_kfold - best.elpd_kfold,
            se_elpd_difference = pointwise_se(pointwise_difference),
            se_elpd_kfold = result.se_elpd_kfold,
            kfoldic = result.kfoldic,
            kfoldic_difference = result.kfoldic - best.kfoldic,
            se_kfoldic = result.se_kfoldic,
            relative_weight = unnormalized_weights[index] / weight_total,
            n_folds = result.n_folds,
            n_observations = result.n_observations,
            min_train_observations = result.min_train_observations,
            min_heldout_observations = result.min_heldout_observations,
            max_heldout_observations = result.max_heldout_observations,
            all_parameter_orders_matched = result.all_parameter_orders_matched,
            all_samplers_passed = result.all_samplers_passed,
            warning = result.all_samplers_passed ? :ok : :sampler_warning,
        ))
    end
    return rows
end

function scenario_passed(comparison_rows, fold_records, heldout_counts)
    thresholds = PROTOCOL.thresholds
    length(comparison_rows) == thresholds.n_models_per_scenario || return false
    all(==(1), heldout_counts) || return false
    if thresholds.require_same_observations_within_scenario
        length(unique(row.n_observations for row in comparison_rows)) == 1 ||
            return false
    end
    if thresholds.require_parameter_order_match
        all(row -> row.all_parameter_orders_matched, comparison_rows) || return false
        all(row -> row.parameter_order_matched, fold_records) || return false
    end
    if thresholds.require_sampler_passed
        all(row -> row.all_samplers_passed, comparison_rows) || return false
        all(row -> row.sampler_summary.internal_passed, fold_records) || return false
    end
    if thresholds.require_finite_elpd
        all(row -> isfinite(row.elpd_kfold) && isfinite(row.kfoldic),
            comparison_rows) || return false
    end
    return true
end

function scenario_review(source)
    full_data = SMOKE.facet_data(source.table)
    folds = fold_indices(full_data.n)
    heldout_counts = zeros(Int, full_data.n)
    for fold in folds
        heldout_counts[fold] .+= 1
    end
    results = [model_kfold_result(source, full_data, folds, model)
        for model in PROTOCOL.models]
    comparison_rows = kfold_comparison_rows(results)
    fold_records = reduce(vcat, [result.fold_records for result in results])
    gmfrm_row = only(row for row in comparison_rows
        if row.model === :gmfrm_internal_candidate)
    passed = scenario_passed(comparison_rows, fold_records, heldout_counts)
    return (;
        scenario_group = source.scenario_group,
        scenario = source.scenario,
        sparse_pattern = source.sparse_pattern,
        simulation_seed = source.simulation_seed,
        simulated_data = (;
            n_observations = full_data.n,
            score_counts = BASE.score_count_rows(source.table.score),
            person_levels = full_data.person_levels,
            rater_levels = full_data.rater_levels,
            item_levels = full_data.item_levels,
            category_levels = full_data.category_levels,
        ),
        folds = [
            (;
                fold,
                heldout_observations = heldout,
                n_heldout_observations = length(heldout),
                heldout_rows = [observation_record(full_data, observation)
                    for observation in heldout],
            )
            for (fold, heldout) in pairs(folds)
        ],
        fold_model_rows = fold_records,
        kfold_comparison_rows = comparison_rows,
        kfold_summary = (;
            passed,
            n_observations = full_data.n,
            n_folds = length(folds),
            all_observations_held_out_once = all(==(1), heldout_counts),
            min_train_observations =
                minimum(row.n_train_observations for row in fold_records),
            min_heldout_observations =
                minimum(row.n_heldout_observations for row in fold_records),
            max_heldout_observations =
                maximum(row.n_heldout_observations for row in fold_records),
            best_model = comparison_rows[1].model,
            gmfrm_rank = gmfrm_row.rank,
            gmfrm_elpd_difference = gmfrm_row.elpd_difference,
            gmfrm_kfoldic_difference = gmfrm_row.kfoldic_difference,
            gmfrm_relative_weight = gmfrm_row.relative_weight,
            all_parameter_orders_matched =
                all(row -> row.all_parameter_orders_matched, comparison_rows),
            all_samplers_passed =
                all(row -> row.all_samplers_passed, comparison_rows),
            all_kfold_comparisons_finite =
                all(row -> isfinite(row.elpd_kfold) && isfinite(row.kfoldic),
                    comparison_rows),
            selected_decision = :keep_internal,
        ),
    )
end

function full_crossed_source_record(spec)
    return WAIC_REVIEW.full_crossed_source_record(spec)
end

function sparse_source_record(spec)
    return WAIC_REVIEW.sparse_source_record(spec)
end

function grid_artifact()
    sources = [
        [full_crossed_source_record(spec) for spec in BASE.SCENARIOS]...,
        [sparse_source_record(spec)
            for spec in WAIC_REVIEW.GMFRMSparseDesignGrid.SCENARIOS]...,
    ]
    reviews = [scenario_review(source) for source in sources]
    all_rows = reduce(vcat, [review.kfold_comparison_rows for review in reviews])
    all_fold_rows = reduce(vcat, [review.fold_model_rows for review in reviews])
    passed = all(review -> review.kfold_summary.passed, reviews)
    keep_internal_count =
        count(review -> review.kfold_summary.selected_decision === :keep_internal,
            reviews)
    return (;
        schema = "bayesianmgmfrm.gmfrm_exact_loo_or_kfold_review.v1",
        family = :gmfrm,
        scope = :scalar_gmfrm_fit_ready_candidate,
        status = :internal_exact_loo_or_kfold_review,
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
                :kfold_refit_review_recorded_and_exact_loo_gate_satisfied,
            required_followup = :guarded_fit_api_dry_run,
        ),
        summary = (;
            passed,
            n_scenario_reviews = length(reviews),
            n_full_crossed_scenarios =
                count(review -> review.scenario_group === :full_crossed, reviews),
            n_sparse_scenarios =
                count(review -> review.scenario_group === :sparse_connected, reviews),
            n_passed_scenarios =
                count(review -> review.kfold_summary.passed, reviews),
            n_models = length(all_rows),
            n_fold_model_records = length(all_fold_rows),
            n_folds = PROTOCOL.k_folds,
            all_observations_held_out_once =
                all(review -> review.kfold_summary.all_observations_held_out_once,
                    reviews),
            all_parameter_orders_matched =
                all(review -> review.kfold_summary.all_parameter_orders_matched,
                    reviews),
            all_samplers_passed =
                all(review -> review.kfold_summary.all_samplers_passed, reviews),
            all_kfold_comparisons_finite =
                all(review -> review.kfold_summary.all_kfold_comparisons_finite,
                    reviews),
            min_train_observations =
                minimum(review.kfold_summary.min_train_observations
                    for review in reviews),
            n_gmfrm_best_model_scenarios =
                count(review -> review.kfold_summary.best_model ===
                    :gmfrm_internal_candidate, reviews),
            max_gmfrm_kfoldic_difference =
                maximum(review.kfold_summary.gmfrm_kfoldic_difference
                    for review in reviews),
            min_gmfrm_relative_weight =
                minimum(review.kfold_summary.gmfrm_relative_weight
                    for review in reviews),
            keep_internal_decision_count = keep_internal_count,
            decision_stability =
                keep_internal_count == length(reviews) ? :stable_keep_internal :
                :unstable,
            remaining_public_blockers = [
                :guarded_fit_api_dry_run_missing,
            ],
            recommendation = :keep_internal_until_guarded_fit_api_dry_run,
            next_gate = :scalar_gmfrm_guarded_fit_api_dry_run,
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
        " fold_records=", artifact.summary.n_fold_model_records,
        " gmfrm_best=", artifact.summary.n_gmfrm_best_model_scenarios,
        " next=", artifact.summary.next_gate)
    return nothing
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    main(ARGS)
end
