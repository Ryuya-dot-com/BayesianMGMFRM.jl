#!/usr/bin/env julia

using JSON3
using SHA
using TOML

import BayesianMGMFRM

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_fit_metric_threshold_sensitivity.json")

include(joinpath(@__DIR__, "local_json.jl"))

const INPUT_ARTIFACTS = [
    (name = :q_revision_construct_validity_review,
        path = "test/fixtures/mgmfrm_q_revision_construct_validity_review.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_q_revision_construct_validity_review.v1",
        pass_policy = :summary_passed),
    (name = :guarded_local_fit_entrypoint,
        path = "test/fixtures/mgmfrm_guarded_local_fit_entrypoint.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_guarded_local_fit_entrypoint.v1",
        pass_policy = :summary_passed),
]

const REFERENCE_RECORDS = [
    (citation_key = :vehtari_gelman_gabry_2017_loo_waic,
        topic = :waic_loo_predictive_fit,
        source = :doi,
        doi = "10.1007/s11222-016-9696-4",
        url = "https://doi.org/10.1007/s11222-016-9696-4"),
    (citation_key = :vehtari_gelman_simpson_2021_rank_normalized_rhat,
        topic = :mcmc_convergence_diagnostics,
        source = :doi,
        doi = "10.1214/20-BA1221",
        url = "https://doi.org/10.1214/20-BA1221"),
    (citation_key = :sinharay_johnson_stern_2006_ppc_irt,
        topic = :posterior_predictive_model_checking_for_irt,
        source = :doi,
        doi = "10.1177/0146621605285517",
        url = "https://doi.org/10.1177/0146621605285517"),
    (citation_key = :wright_linacre_1994_mean_square_ranges,
        topic = :rasch_infit_outfit_threshold_ranges,
        source = :url,
        doi = missing,
        url = "https://www.rasch.org/rmt/rmt83b.htm"),
    (citation_key = :linacre_2002_infit_outfit_interpretation,
        topic = :rasch_infit_outfit_interpretation,
        source = :url,
        doi = missing,
        url = "https://www.rasch.org/rmt/rmt162f.htm"),
    (citation_key = :christensen_makransky_horton_2017_yens_q3,
        topic = :local_dependence_thresholds_depend_on_setting,
        source = :doi,
        doi = "10.1177/0146621616677520",
        url = "https://doi.org/10.1177/0146621616677520"),
    (citation_key = :smith_schumacker_bush_1998_item_mean_squares,
        topic = :sample_size_sensitive_item_mean_square_thresholds,
        source = :url,
        doi = missing,
        url = "https://pubmed.ncbi.nlm.nih.gov/9661732/"),
]

const THRESHOLD_PROFILES = Any[
    (profile = :strict_bayesian_workflow,
        rationale = :publication_grade_mcmc_and_tight_predictive_screening,
        rhat_threshold = 1.01,
        ess_threshold = 400.0,
        waic_p_threshold = 0.4,
        pareto_k_threshold = 0.7,
        calibration_abs_threshold = 0.08,
        ppc_abs_threshold = 0.08,
        mean_square_rule = :fixed,
        infit_lower = 0.8,
        infit_upper = 1.2,
        outfit_lower = 0.8,
        outfit_upper = 1.2),
    (profile = :screening_workflow,
        rationale = :local_screening_with_common_rasch_mean_square_range,
        rhat_threshold = 1.05,
        ess_threshold = 100.0,
        waic_p_threshold = 0.4,
        pareto_k_threshold = 0.7,
        calibration_abs_threshold = 0.20,
        ppc_abs_threshold = 0.20,
        mean_square_rule = :fixed,
        infit_lower = 0.7,
        infit_upper = 1.3,
        outfit_lower = 0.7,
        outfit_upper = 1.3),
    (profile = :exploratory_rasch_lenient,
        rationale = :lenient_local_exploration_not_public_claim_ready,
        rhat_threshold = 1.10,
        ess_threshold = 20.0,
        waic_p_threshold = 0.4,
        pareto_k_threshold = 0.7,
        calibration_abs_threshold = 0.35,
        ppc_abs_threshold = 0.35,
        mean_square_rule = :fixed,
        infit_lower = 0.5,
        infit_upper = 1.5,
        outfit_lower = 0.5,
        outfit_upper = 1.5),
    (profile = :sample_size_mean_square,
        rationale = :sample_size_sensitive_mean_square_screening,
        rhat_threshold = 1.05,
        ess_threshold = 100.0,
        waic_p_threshold = 0.4,
        pareto_k_threshold = 0.7,
        calibration_abs_threshold = 0.20,
        ppc_abs_threshold = 0.20,
        mean_square_rule = :sample_size,
        infit_lower = missing,
        infit_upper = missing,
        outfit_lower = missing,
        outfit_upper = missing),
]

const SIMULATION_REGIMES = [
    (regime = :balanced_reference,
        description = :original_guarded_fit_entrypoint_table,
        perturbation = :none),
    (regime = :item3_secondary_dimension_signal,
        description = :item3_scores_shift_with_secondary_dimension_pattern,
        perturbation = :item3_person_pattern),
    (regime = :rater_method_noise,
        description = :rater_two_item_three_scores_flipped_to_mimic_method_noise,
        perturbation = :rater_item_interaction),
]

const PROTOCOL = (;
    protocol_id = "mgmfrm_fit_metric_threshold_sensitivity_v1",
    review_kind = :local_construct_reviewed_q_fit_metric_threshold_sensitivity,
    publication_or_registration_action = false,
    local_only = true,
    entrypoint = "fit(spec; experimental = true)",
    existing_model_fit_surface = :mfrm_fit_stats_infit_outfit,
    current_mgmfrm_fit_surfaces = [
        :waic,
        :loo,
        :posterior_predictive_check,
        :calibration_table,
        :direct_parameter_shift,
    ],
    sampler = (;
        backend = :advancedhmc,
        sampler = :nuts,
        chains = 1,
        warmup = 0,
        draws = 4,
        step_size = 0.02,
        target_accept = 0.8,
        max_depth = 2,
        metric = :unit,
        seed_base = 20260810,
    ),
    mfrm_baseline_sampler = (;
        backend = :advancedhmc,
        sampler = :nuts,
        chains = 2,
        warmup = 0,
        draws = 4,
        step_size = 0.02,
        target_accept = 0.8,
        max_depth = 2,
        metric = :unit,
        seed_base = 20260910,
    ),
    thresholds = (;
        require_q_revision_construct_validity_review_passed = true,
        require_guarded_local_fit_entrypoint_passed = true,
        require_reference_records_public_only = true,
        require_threshold_profiles_recorded = true,
        require_simulation_regimes_recorded = true,
        require_all_construct_reviewed_candidates_checked = true,
        require_all_mgmfrm_fit_pairs_succeeded = true,
        require_all_fit_metric_values_finite = true,
        require_mfrm_baseline_mean_square_recorded = true,
        require_existing_model_comparison_recorded = true,
        require_parameter_shift_recorded = true,
        require_no_single_threshold_profile_promoted = true,
        require_no_mcmc_convergence_claim = true,
        require_no_automatic_q_revision = true,
        require_no_public_q_revision_claim = true,
        require_no_public_fit_metric_claim = true,
        require_no_publication_or_registration_action = true,
    ),
)

function usage()
    return """
    Generate the local MGMFRM fit-metric threshold sensitivity artifact.

    This artifact compares construct-reviewed declared/candidate Q fits with
    existing MFRM fit-statistic diagnostics across deterministic local
    simulation regimes. It records how WAIC, LOO, posterior predictive,
    calibration, infit/outfit, and common direct-parameter summaries change
    under multiple literature-motivated threshold profiles. It does not make
    convergence, Q-revision, or public fit claims.

    Usage:
      julia --project=. scripts/generate_mgmfrm_fit_metric_threshold_sensitivity.jl [--output PATH]
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

project_version() =
    String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])
file_sha256(path::AbstractString) = bytes2hex(open(sha256, path))
local_path(path::AbstractString) = normpath(joinpath(ROOT, path))

function artifact_record(spec)
    path = local_path(spec.path)
    exists = isfile(path)
    if !exists
        return (;
            artifact = spec.name,
            path = spec.path,
            exists = false,
            sha256 = missing,
            expected_schema = spec.expected_schema,
            schema = missing,
            schema_matches = false,
            pass_policy = spec.pass_policy,
            summary_passed = false,
            summary = (; passed = false),
        )
    end
    parsed = JSON3.read(read(path, String))
    schema = String(parsed[:schema])
    schema_matches = schema == spec.expected_schema
    summary = parsed[:summary]
    summary_passed =
        spec.pass_policy === :summary_passed && Bool(summary[:passed])
    return (;
        artifact = spec.name,
        path = spec.path,
        exists,
        sha256 = file_sha256(path),
        expected_schema = spec.expected_schema,
        schema,
        schema_matches,
        pass_policy = spec.pass_policy,
        summary_passed,
        summary = input_summary(spec.name, summary),
    )
end

function input_summary(name::Symbol, summary)
    name === :q_revision_construct_validity_review && return (;
        passed = Bool(summary[:passed]),
        n_construct_review_rows = Int(summary[:n_construct_review_rows]),
        n_construct_supported_candidates =
            Int(summary[:n_construct_supported_candidates]),
        construct_validity_supported_for_all_reviewed =
            Bool(summary[:construct_validity_supported_for_all_reviewed]),
        supported_candidates_remain_manual_local_only =
            Bool(summary[:supported_candidates_remain_manual_local_only]),
        no_automatic_q_revision = Bool(summary[:no_automatic_q_revision]),
        no_public_q_revision_claim = Bool(summary[:no_public_q_revision_claim]),
        next_gate = String(summary[:next_gate]),
    )
    name === :guarded_local_fit_entrypoint && return (;
        passed = Bool(summary[:passed]),
        n_fit_entrypoint_rows = Int(summary[:n_fit_entrypoint_rows]),
        all_guarded_fit_attempts_succeeded =
            Bool(summary[:all_guarded_fit_attempts_succeeded]),
        fit_outputs_finite = Bool(summary[:fit_outputs_finite]),
        all_candidates_remain_manual_local_only =
            Bool(summary[:all_candidates_remain_manual_local_only]),
        no_automatic_q_revision = Bool(summary[:no_automatic_q_revision]),
        no_public_q_revision_claim = Bool(summary[:no_public_q_revision_claim]),
        next_gate = String(summary[:next_gate]),
    )
    return (; passed = Bool(summary[:passed]))
end

function parsed_input_artifact(spec)
    path = local_path(spec.path)
    isfile(path) || error("input artifact is missing: $(spec.path)")
    return JSON3.read(read(path, String))
end

function record_by_name(records, name::Symbol)
    return only(record for record in records if record.artifact === name)
end

function q_matrix_from_json(rows)
    n_rows = length(rows)
    n_cols = length(first(rows))
    matrix = Matrix{Bool}(undef, n_rows, n_cols)
    for row in 1:n_rows, col in 1:n_cols
        matrix[row, col] = Bool(rows[row][col])
    end
    return matrix
end

function q_matrix_rows(matrix::AbstractMatrix{Bool})
    return [[Bool(matrix[row, col]) for col in axes(matrix, 2)]
        for row in axes(matrix, 1)]
end

function base_table()
    return (;
        examinee = [
            "E1", "E1", "E1", "E1", "E1", "E1",
            "E2", "E2", "E2", "E2", "E2", "E2",
            "E3", "E3", "E3", "E3", "E3", "E3",
        ],
        rater = [
            "R1", "R1", "R1", "R2", "R2", "R2",
            "R1", "R1", "R1", "R2", "R2", "R2",
            "R1", "R1", "R1", "R2", "R2", "R2",
        ],
        item = [
            "I1", "I2", "I3", "I1", "I2", "I3",
            "I1", "I2", "I3", "I1", "I2", "I3",
            "I1", "I2", "I3", "I1", "I2", "I3",
        ],
        score = [0, 1, 2, 1, 2, 0, 1, 0, 2, 2, 1, 0, 2, 1, 0, 0, 2, 1],
    )
end

function perturb_score(score::Int, person::String, rater::String, item::String,
        regime::Symbol)
    regime === :balanced_reference && return score
    if regime === :item3_secondary_dimension_signal
        item == "I3" || return score
        person == "E1" && return max(score - 1, 0)
        person == "E3" && return min(score + 1, 2)
        return score
    end
    if regime === :rater_method_noise
        rater == "R2" && item == "I3" && return 2 - score
        return score
    end
    error("unknown simulation regime: $regime")
end

function regime_table(regime::Symbol)
    table = base_table()
    scores = [
        perturb_score(
            table.score[index],
            table.examinee[index],
            table.rater[index],
            table.item[index],
            regime,
        )
        for index in eachindex(table.score)
    ]
    return merge(table, (; score = scores))
end

function facet_data(table)
    return BayesianMGMFRM.FacetData(table;
        person = :examinee,
        rater = :rater,
        item = :item,
        score = :score)
end

function average(values)
    isempty(values) && return 0.0
    return sum(Float64(value) for value in values) / length(values)
end

function finite_matrix(matrix)
    return all(isfinite, vec(matrix))
end

finite_or_missing(value) = value isa Real && isfinite(Float64(value)) ?
    Float64(value) : missing

function fit_mgmfrm(data, q_matrix::AbstractMatrix{Bool}, seed::Int)
    sampler = PROTOCOL.sampler
    spec = BayesianMGMFRM.mfrm_spec(data;
        family = :mgmfrm,
        dimensions = size(q_matrix, 2),
        q_matrix)
    return BayesianMGMFRM.fit(spec;
        experimental = true,
        backend = sampler.backend,
        ndraws = sampler.draws,
        warmup = sampler.warmup,
        chains = sampler.chains,
        step_size = sampler.step_size,
        target_accept = sampler.target_accept,
        max_depth = sampler.max_depth,
        metric = sampler.metric,
        seed,
        progress = false)
end

function fit_mfrm(data, seed::Int)
    sampler = PROTOCOL.mfrm_baseline_sampler
    spec = BayesianMGMFRM.mfrm_spec(data; thresholds = :partial_credit)
    return BayesianMGMFRM.fit(spec;
        backend = sampler.backend,
        ndraws = sampler.draws,
        warmup = sampler.warmup,
        chains = sampler.chains,
        step_size = sampler.step_size,
        target_accept = sampler.target_accept,
        max_depth = sampler.max_depth,
        metric = sampler.metric,
        seed,
        progress = false)
end

function max_abs_calibration_error(rows)
    isempty(rows) && return 0.0
    return maximum(Float64(row.absolute_calibration_error) for row in rows)
end

function max_abs_ppc_mean_error(rows)
    isempty(rows) && return 0.0
    return maximum(abs(Float64(row.observed) - Float64(row.replicated_mean))
        for row in rows)
end

function metric_surface(fit)
    waic_stat = BayesianMGMFRM.waic(fit)
    loo_stat = BayesianMGMFRM.loo(fit; min_tail_draws = 2)
    calibration_rows =
        BayesianMGMFRM.calibration_table(fit; bins = 3, interval = 0.8)
    ppc = BayesianMGMFRM.posterior_predictive_check(fit)
    ppc_rows = BayesianMGMFRM.predictive_check_summary(ppc; interval = 0.8)
    return (;
        waic = waic_stat,
        loo = loo_stat,
        calibration_rows,
        ppc_rows,
        max_abs_calibration_error = max_abs_calibration_error(calibration_rows),
        max_abs_ppc_mean_error = max_abs_ppc_mean_error(ppc_rows),
        finite =
            isfinite(Float64(waic_stat.waic)) &&
            isfinite(Float64(waic_stat.elpd_waic)) &&
            isfinite(Float64(waic_stat.p_waic)) &&
            isfinite(Float64(loo_stat.looic)) &&
            isfinite(Float64(loo_stat.elpd_loo)) &&
            isfinite(Float64(loo_stat.max_pareto_k)) &&
            all(row -> isfinite(Float64(row.absolute_calibration_error)),
                calibration_rows) &&
            all(row -> isfinite(Float64(row.observed)) &&
                isfinite(Float64(row.replicated_mean)), ppc_rows),
    )
end

function mcmc_summary(fit)
    summary = fit.diagnostic_surface.summary
    return (;
        flag = summary.flag,
        passed = Bool(summary.passed),
        n_chains = Int(summary.n_chains),
        draws_per_chain = Int(summary.draws_per_chain),
        total_draws = Int(summary.total_draws),
        rhat_threshold = Float64(summary.rhat_threshold),
        ess_threshold = Float64(summary.ess_threshold),
        max_rhat = finite_or_missing(summary.max_rhat),
        min_ess = finite_or_missing(summary.min_ess),
        n_insufficient_chains = Int(summary.n_insufficient_chains),
        n_sampler_warnings = Int(summary.n_sampler_warnings),
        n_nonfinite_logdensity = Int(summary.n_nonfinite_logdensity),
        n_nonfinite_direct_loglikelihood =
            Int(summary.n_nonfinite_direct_loglikelihood),
        n_failed_direct_constraints = Int(summary.n_failed_direct_constraints),
        n_divergences = Int(summary.n_divergences),
        n_max_treedepth = Int(summary.n_max_treedepth),
        mcmc_convergence_claim_allowed = false,
    )
end

function fit_summary_row(scenario::Symbol, regime::Symbol, model_role::Symbol,
        q_matrix::AbstractMatrix{Bool}, fit, metrics, seed::Int)
    summary = mcmc_summary(fit)
    return (;
        scenario,
        regime,
        model_role,
        q_matrix = q_matrix_rows(q_matrix),
        seed,
        n_observations = fit.design.spec.data.n,
        n_items = length(fit.design.spec.data.item_levels),
        n_dimensions = fit.design.spec.dimensions,
        n_raw_parameters = size(fit.draws, 2),
        n_direct_parameters = size(fit.direct_draws, 2),
        n_draws = size(fit.draws, 1),
        waic = Float64(metrics.waic.waic),
        elpd_waic = Float64(metrics.waic.elpd_waic),
        p_waic = Float64(metrics.waic.p_waic),
        high_variance_count = Int(metrics.waic.high_variance_count),
        looic = Float64(metrics.loo.looic),
        elpd_loo = Float64(metrics.loo.elpd_loo),
        max_pareto_k = Float64(metrics.loo.max_pareto_k),
        bad_pareto_k_count = Int(metrics.loo.bad_pareto_k_count),
        max_abs_calibration_error =
            Float64(metrics.max_abs_calibration_error),
        max_abs_ppc_mean_error = Float64(metrics.max_abs_ppc_mean_error),
        finite_raw_draws = finite_matrix(fit.draws),
        finite_direct_draws = finite_matrix(fit.direct_draws),
        finite_direct_loglikelihood = all(isfinite, fit.direct_loglikelihood),
        finite_pointwise_loglikelihood =
            finite_matrix(fit.direct_pointwise_loglikelihood),
        finite_metric_surface = Bool(metrics.finite),
        diagnostic_summary = summary,
    )
end

function count_waic_flags(fit, threshold::Real)
    rows = BayesianMGMFRM.waic_diagnostics(fit; threshold)
    return count(row -> row.flag !== :ok, rows)
end

function count_loo_flags(fit, threshold::Real)
    rows = BayesianMGMFRM.loo_diagnostics(fit;
        threshold,
        min_tail_draws = 2)
    return count(row -> row.flag !== :ok, rows)
end

function threshold_evaluation_row(scenario::Symbol, regime::Symbol,
        model_role::Symbol, fit, metrics, profile)
    n_waic = count_waic_flags(fit, profile.waic_p_threshold)
    n_loo = count_loo_flags(fit, profile.pareto_k_threshold)
    n_calibration = count(row ->
            abs(Float64(row.calibration_error)) >
                Float64(profile.calibration_abs_threshold),
        metrics.calibration_rows)
    n_ppc = count(row ->
            abs(Float64(row.observed) - Float64(row.replicated_mean)) >
                Float64(profile.ppc_abs_threshold),
        metrics.ppc_rows)
    n_total = n_waic + n_loo + n_calibration + n_ppc
    return (;
        scenario,
        regime,
        model_role,
        profile = profile.profile,
        waic_p_threshold = profile.waic_p_threshold,
        pareto_k_threshold = profile.pareto_k_threshold,
        calibration_abs_threshold = profile.calibration_abs_threshold,
        ppc_abs_threshold = profile.ppc_abs_threshold,
        n_waic_flagged = n_waic,
        n_loo_flagged = n_loo,
        n_calibration_flagged = n_calibration,
        n_ppc_flagged = n_ppc,
        n_metric_flags = n_total,
        metric_profile_passed_without_mcmc = n_total == 0,
        mcmc_convergence_claim_allowed = false,
        overall_reporting_allowed = false,
        reporting_blocker = :short_local_fit_no_mcmc_convergence_claim,
    )
end

function direct_parameter_means(fit)
    names = String.(fit.design.parameter_names)
    means = Dict{String,Float64}()
    for col in axes(fit.direct_draws, 2)
        means[names[col]] = average(@view fit.direct_draws[:, col])
    end
    return means
end

function parameter_shift_record(scenario::Symbol, regime::Symbol,
        declared_fit, candidate_fit)
    declared = direct_parameter_means(declared_fit)
    candidate = direct_parameter_means(candidate_fit)
    common = sort(collect(intersect(keys(declared), keys(candidate))))
    shifts = [abs(candidate[name] - declared[name]) for name in common]
    changed = setdiff(union(collect(keys(declared)), collect(keys(candidate))), common)
    return (;
        scenario,
        regime,
        n_common_direct_parameters = length(common),
        n_changed_direct_parameter_names = length(changed),
        mean_abs_common_direct_parameter_shift = average(shifts),
        max_abs_common_direct_parameter_shift =
            isempty(shifts) ? 0.0 : maximum(shifts),
        n_common_direct_parameters_shifted_gt_0_10 =
            count(>(0.10), shifts),
        n_common_direct_parameters_shifted_gt_0_25 =
            count(>(0.25), shifts),
        candidate_specific_direct_parameters =
            sort(collect(setdiff(keys(candidate), keys(declared)))),
        declared_specific_direct_parameters =
            sort(collect(setdiff(keys(declared), keys(candidate)))),
    )
end

function metric_comparison_row(scenario::Symbol, regime::Symbol,
        declared_metrics, candidate_metrics, shift)
    return (;
        scenario,
        regime,
        comparison = :candidate_minus_declared,
        delta_elpd_waic = Float64(candidate_metrics.waic.elpd_waic -
            declared_metrics.waic.elpd_waic),
        delta_waic = Float64(candidate_metrics.waic.waic -
            declared_metrics.waic.waic),
        delta_elpd_loo = Float64(candidate_metrics.loo.elpd_loo -
            declared_metrics.loo.elpd_loo),
        delta_looic = Float64(candidate_metrics.loo.looic -
            declared_metrics.loo.looic),
        delta_max_abs_calibration_error =
            Float64(candidate_metrics.max_abs_calibration_error -
                declared_metrics.max_abs_calibration_error),
        delta_max_abs_ppc_mean_error =
            Float64(candidate_metrics.max_abs_ppc_mean_error -
                declared_metrics.max_abs_ppc_mean_error),
        candidate_lower_waic = candidate_metrics.waic.waic <
            declared_metrics.waic.waic,
        candidate_lower_looic = candidate_metrics.loo.looic <
            declared_metrics.loo.looic,
        n_common_direct_parameters = shift.n_common_direct_parameters,
        mean_abs_common_direct_parameter_shift =
            shift.mean_abs_common_direct_parameter_shift,
        max_abs_common_direct_parameter_shift =
            shift.max_abs_common_direct_parameter_shift,
        interpretation = :local_diagnostic_only_not_q_revision_evidence,
    )
end

function mfrm_metric_summary_row(regime::Symbol, fit, metrics, seed::Int)
    return (;
        regime,
        model = :mfrm_partial_credit_baseline,
        seed,
        n_observations = fit.design.spec.data.n,
        n_items = length(fit.design.spec.data.item_levels),
        n_draws = size(fit.draws, 1),
        waic = Float64(metrics.waic.waic),
        elpd_waic = Float64(metrics.waic.elpd_waic),
        p_waic = Float64(metrics.waic.p_waic),
        looic = Float64(metrics.loo.looic),
        elpd_loo = Float64(metrics.loo.elpd_loo),
        max_pareto_k = Float64(metrics.loo.max_pareto_k),
        max_abs_calibration_error =
            Float64(metrics.max_abs_calibration_error),
        max_abs_ppc_mean_error = Float64(metrics.max_abs_ppc_mean_error),
        finite_metric_surface = Bool(metrics.finite),
    )
end

function mfrm_fit_stat_rows(regime::Symbol, fit)
    rows = BayesianMGMFRM.fit_stats(fit; by = :item, interval = 0.8)
    return [
        (regime,
            model = :mfrm_partial_credit_baseline,
            facet = row.facet,
            level = row.level,
            n_obs = Int(row.n_obs),
            infit_mean = Float64(row.infit_mean),
            outfit_mean = Float64(row.outfit_mean),
            tiny_variance_count = Int(row.tiny_variance_count),
            fit_flag = row.flag)
        for row in rows
    ]
end

function mean_square_bounds(profile, n_obs::Int)
    if profile.mean_square_rule === :sample_size
        root_n = sqrt(Float64(n_obs))
        return (;
            infit_lower = max(0.05, 1.0 - 2.0 / root_n),
            infit_upper = 1.0 + 2.0 / root_n,
            outfit_lower = max(0.05, 1.0 - 6.0 / root_n),
            outfit_upper = 1.0 + 6.0 / root_n,
        )
    end
    return (;
        infit_lower = Float64(profile.infit_lower),
        infit_upper = Float64(profile.infit_upper),
        outfit_lower = Float64(profile.outfit_lower),
        outfit_upper = Float64(profile.outfit_upper),
    )
end

function mfrm_threshold_row(regime::Symbol, fit_rows, profile)
    infit_flags = 0
    outfit_flags = 0
    bounds_rows = NamedTuple[]
    for row in fit_rows
        bounds = mean_square_bounds(profile, row.n_obs)
        infit_flag =
            row.infit_mean < bounds.infit_lower ||
            row.infit_mean > bounds.infit_upper
        outfit_flag =
            row.outfit_mean < bounds.outfit_lower ||
            row.outfit_mean > bounds.outfit_upper
        infit_flags += infit_flag ? 1 : 0
        outfit_flags += outfit_flag ? 1 : 0
        push!(bounds_rows, (;
            level = row.level,
            n_obs = row.n_obs,
            infit_lower = bounds.infit_lower,
            infit_upper = bounds.infit_upper,
            outfit_lower = bounds.outfit_lower,
            outfit_upper = bounds.outfit_upper,
            infit_flag,
            outfit_flag,
        ))
    end
    return (;
        regime,
        model = :mfrm_partial_credit_baseline,
        profile = profile.profile,
        mean_square_rule = profile.mean_square_rule,
        n_item_rows = length(fit_rows),
        n_infit_flagged = infit_flags,
        n_outfit_flagged = outfit_flags,
        n_mean_square_flagged = infit_flags + outfit_flags,
        profile_passed = infit_flags + outfit_flags == 0,
        bounds_rows,
        interpretation = :existing_mfrm_fit_stat_threshold_sensitivity,
    )
end

function existing_model_comparison_row(scenario::Symbol, regime::Symbol,
        model_role::Symbol, mfrm_metrics, mgmfrm_metrics)
    return (;
        scenario,
        regime,
        existing_model = :mfrm_partial_credit_baseline,
        current_model = model_role,
        delta_elpd_waic_mgmfrm_minus_mfrm =
            Float64(mgmfrm_metrics.waic.elpd_waic -
                mfrm_metrics.waic.elpd_waic),
        delta_waic_mgmfrm_minus_mfrm =
            Float64(mgmfrm_metrics.waic.waic - mfrm_metrics.waic.waic),
        delta_elpd_loo_mgmfrm_minus_mfrm =
            Float64(mgmfrm_metrics.loo.elpd_loo -
                mfrm_metrics.loo.elpd_loo),
        delta_looic_mgmfrm_minus_mfrm =
            Float64(mgmfrm_metrics.loo.looic - mfrm_metrics.loo.looic),
        delta_max_abs_calibration_error =
            Float64(mgmfrm_metrics.max_abs_calibration_error -
                mfrm_metrics.max_abs_calibration_error),
        delta_max_abs_ppc_mean_error =
            Float64(mgmfrm_metrics.max_abs_ppc_mean_error -
                mfrm_metrics.max_abs_ppc_mean_error),
        interpretation = :existing_model_reference_only_not_model_superiority_claim,
    )
end

function construct_review_rows(artifact)
    return [
        row for row in artifact[:construct_review_rows]
        if Bool(row[:construct_review_supported]) &&
            Bool(row[:manual_local_q_revision_candidate_allowed])
    ]
end

function reference_records_are_public_only()
    return all(row ->
            !(:item_key in keys(row)) &&
            (String(row.source) == "doi" || String(row.source) == "url") &&
            !isempty(String(row.url)),
        REFERENCE_RECORDS)
end

function build_artifact()
    input_records = [artifact_record(spec) for spec in INPUT_ARTIFACTS]
    construct_artifact = parsed_input_artifact(INPUT_ARTIFACTS[1])
    construct_rows = construct_review_rows(construct_artifact)

    all_input_artifacts_present = all(record -> record.exists, input_records)
    all_expected_schemas = all(record -> record.schema_matches, input_records)
    all_input_summaries_passed =
        all(record -> record.summary_passed, input_records)
    q_review_passed =
        record_by_name(input_records, :q_revision_construct_validity_review).
        summary_passed
    guarded_entrypoint_passed =
        record_by_name(input_records, :guarded_local_fit_entrypoint).
        summary_passed

    mfrm_metric_rows = NamedTuple[]
    mfrm_fit_rows = NamedTuple[]
    mfrm_threshold_rows = NamedTuple[]
    mfrm_metric_by_regime = Dict{Symbol,Any}()
    for (regime_index, regime_spec) in pairs(SIMULATION_REGIMES)
        table = regime_table(regime_spec.regime)
        data = facet_data(table)
        seed = PROTOCOL.mfrm_baseline_sampler.seed_base + 100 * regime_index
        fit = fit_mfrm(data, seed)
        metrics = metric_surface(fit)
        mfrm_metric_by_regime[regime_spec.regime] = metrics
        push!(mfrm_metric_rows, mfrm_metric_summary_row(
            regime_spec.regime, fit, metrics, seed))
        rows = mfrm_fit_stat_rows(regime_spec.regime, fit)
        append!(mfrm_fit_rows, rows)
        for profile in THRESHOLD_PROFILES
            push!(mfrm_threshold_rows,
                mfrm_threshold_row(regime_spec.regime, rows, profile))
        end
    end

    mgmfrm_fit_rows = NamedTuple[]
    mgmfrm_threshold_rows = NamedTuple[]
    parameter_shift_rows = NamedTuple[]
    metric_comparison_rows = NamedTuple[]
    existing_model_comparison_rows = NamedTuple[]

    for (scenario_index, source_row) in pairs(construct_rows)
        scenario = Symbol(String(source_row[:scenario]))
        declared_q = q_matrix_from_json(source_row[:declared_q])
        candidate_q = q_matrix_from_json(source_row[:candidate_q])
        for (regime_index, regime_spec) in pairs(SIMULATION_REGIMES)
            table = regime_table(regime_spec.regime)
            data = facet_data(table)
            seed_base = PROTOCOL.sampler.seed_base +
                1000 * scenario_index +
                100 * regime_index
            declared_fit = fit_mgmfrm(data, declared_q, seed_base + 1)
            candidate_fit = fit_mgmfrm(data, candidate_q, seed_base + 2)
            declared_metrics = metric_surface(declared_fit)
            candidate_metrics = metric_surface(candidate_fit)

            push!(mgmfrm_fit_rows, fit_summary_row(
                scenario,
                regime_spec.regime,
                :declared_q,
                declared_q,
                declared_fit,
                declared_metrics,
                seed_base + 1))
            push!(mgmfrm_fit_rows, fit_summary_row(
                scenario,
                regime_spec.regime,
                :construct_reviewed_candidate_q,
                candidate_q,
                candidate_fit,
                candidate_metrics,
                seed_base + 2))

            for profile in THRESHOLD_PROFILES
                push!(mgmfrm_threshold_rows, threshold_evaluation_row(
                    scenario,
                    regime_spec.regime,
                    :declared_q,
                    declared_fit,
                    declared_metrics,
                    profile))
                push!(mgmfrm_threshold_rows, threshold_evaluation_row(
                    scenario,
                    regime_spec.regime,
                    :construct_reviewed_candidate_q,
                    candidate_fit,
                    candidate_metrics,
                    profile))
            end

            shift = parameter_shift_record(
                scenario, regime_spec.regime, declared_fit, candidate_fit)
            push!(parameter_shift_rows, shift)
            push!(metric_comparison_rows, metric_comparison_row(
                scenario, regime_spec.regime, declared_metrics,
                candidate_metrics, shift))
            for (model_role, metrics) in (
                    (:declared_q, declared_metrics),
                    (:construct_reviewed_candidate_q, candidate_metrics))
                push!(existing_model_comparison_rows,
                    existing_model_comparison_row(
                        scenario,
                        regime_spec.regime,
                        model_role,
                        mfrm_metric_by_regime[regime_spec.regime],
                        metrics))
            end
        end
    end

    all_mgmfrm_fit_pairs_succeeded =
        length(mgmfrm_fit_rows) ==
        2 * length(construct_rows) * length(SIMULATION_REGIMES)
    all_fit_metric_values_finite =
        all(row -> Bool(row.finite_metric_surface), mgmfrm_fit_rows) &&
        all(row -> Bool(row.finite_metric_surface), mfrm_metric_rows)
    all_parameter_shift_values_finite =
        all(row -> isfinite(row.mean_abs_common_direct_parameter_shift) &&
            isfinite(row.max_abs_common_direct_parameter_shift),
        parameter_shift_rows)
    threshold_profiles_change_at_least_one_flag =
        length(unique(row.n_metric_flags for row in mgmfrm_threshold_rows)) > 1 ||
        length(unique(row.n_mean_square_flagged for row in mfrm_threshold_rows)) > 1
    mfrm_baseline_mean_square_recorded =
        length(mfrm_fit_rows) ==
        length(SIMULATION_REGIMES) * length(facet_data(base_table()).item_levels)
    existing_model_comparison_recorded =
        length(existing_model_comparison_rows) ==
        2 * length(construct_rows) * length(SIMULATION_REGIMES)
    parameter_shift_recorded =
        length(parameter_shift_rows) ==
        length(construct_rows) * length(SIMULATION_REGIMES) &&
        all(row -> row.n_common_direct_parameters > 0, parameter_shift_rows)
    reference_records_public_only = reference_records_are_public_only()
    no_single_threshold_profile_promoted = true
    no_mcmc_convergence_claim = true
    no_automatic_q_revision = true
    no_public_q_revision_claim = true
    no_public_fit_metric_claim = true
    no_publication_or_registration_action = true
    n_fit_metric_evidence_cells =
        length(metric_comparison_rows) +
        length(existing_model_comparison_rows) +
        length(mgmfrm_threshold_rows) +
        length(mfrm_threshold_rows)

    passed = all_input_artifacts_present &&
        all_expected_schemas &&
        all_input_summaries_passed &&
        q_review_passed &&
        guarded_entrypoint_passed &&
        reference_records_public_only &&
        !isempty(THRESHOLD_PROFILES) &&
        !isempty(SIMULATION_REGIMES) &&
        length(construct_rows) > 0 &&
        all_mgmfrm_fit_pairs_succeeded &&
        all_fit_metric_values_finite &&
        mfrm_baseline_mean_square_recorded &&
        existing_model_comparison_recorded &&
        parameter_shift_recorded &&
        all_parameter_shift_values_finite &&
        no_single_threshold_profile_promoted &&
        no_mcmc_convergence_claim &&
        no_automatic_q_revision &&
        no_public_q_revision_claim &&
        no_public_fit_metric_claim &&
        no_publication_or_registration_action

    return (;
        schema =
            "bayesianmgmfrm.mgmfrm_fit_metric_threshold_sensitivity.v1",
        family = :mgmfrm,
        scope = :construct_reviewed_q_fit_metric_threshold_sensitivity,
        status = :fit_metric_threshold_sensitivity_recorded,
        decision =
            :record_metric_threshold_sensitivity_keep_reporting_policy_local_only,
        public_fit = true,
        experimental_public = true,
        fit_ready = true,
        local_only = true,
        q_revision_public = false,
        automatic_q_revision = false,
        public_fit_metric_claim = false,
        publication_or_registration_action = false,
        package = (;
            name = "BayesianMGMFRM",
            version = project_version(),
            julia_version = string(VERSION),
        ),
        protocol = PROTOCOL,
        input_artifacts = input_records,
        reference_records = REFERENCE_RECORDS,
        threshold_profiles = THRESHOLD_PROFILES,
        simulation_regimes = SIMULATION_REGIMES,
        mfrm_metric_rows,
        mfrm_fit_stat_rows = mfrm_fit_rows,
        mfrm_threshold_evaluation_rows = mfrm_threshold_rows,
        mgmfrm_fit_rows,
        mgmfrm_threshold_evaluation_rows = mgmfrm_threshold_rows,
        parameter_shift_rows,
        metric_comparison_rows,
        existing_model_comparison_rows,
        decision_record = (;
            selected_decision =
                :fit_metric_threshold_sensitivity_recorded_local_only,
            existing_mfrm_fit_stats_used_as_reference = true,
            mgmfrm_infit_outfit_directly_supported = false,
            mgmfrm_waic_loo_ppc_calibration_recorded = true,
            mcmc_convergence_claim_allowed = false,
            automatic_q_revision_allowed = false,
            public_q_revision_claim_allowed = false,
            public_fit_metric_claim_allowed = false,
            reporting_policy =
                :report_profile_sensitivity_before_interpreting_local_fit_metrics,
            required_followup = :construct_reviewed_q_fit_reporting_policy,
        ),
        summary = (;
            passed,
            publication_or_registration_action = false,
            local_only = true,
            all_input_artifacts_present,
            all_expected_schemas,
            all_input_summaries_passed,
            q_revision_construct_validity_review_passed = q_review_passed,
            guarded_local_fit_entrypoint_passed = guarded_entrypoint_passed,
            reference_records_public_only,
            n_reference_records = length(REFERENCE_RECORDS),
            n_threshold_profiles = length(THRESHOLD_PROFILES),
            n_simulation_regimes = length(SIMULATION_REGIMES),
            n_construct_reviewed_candidates = length(construct_rows),
            n_mfrm_baseline_fit_objects = length(mfrm_metric_rows),
            n_mfrm_fit_stat_rows = length(mfrm_fit_rows),
            n_mfrm_threshold_evaluation_rows = length(mfrm_threshold_rows),
            n_mgmfrm_fit_pairs =
                length(construct_rows) * length(SIMULATION_REGIMES),
            n_mgmfrm_fit_objects = length(mgmfrm_fit_rows),
            n_mgmfrm_threshold_evaluation_rows = length(mgmfrm_threshold_rows),
            n_parameter_shift_rows = length(parameter_shift_rows),
            n_metric_comparison_rows = length(metric_comparison_rows),
            n_existing_model_comparison_rows =
                length(existing_model_comparison_rows),
            n_fit_metric_evidence_cells,
            all_mgmfrm_fit_pairs_succeeded,
            all_fit_metric_values_finite,
            all_parameter_shift_values_finite,
            threshold_profiles_change_at_least_one_flag,
            mfrm_baseline_mean_square_recorded,
            existing_model_comparison_recorded,
            parameter_shift_recorded,
            infit_outfit_mgmfrm_directly_supported = false,
            no_single_threshold_profile_promoted,
            no_mcmc_convergence_claim,
            no_automatic_q_revision,
            no_public_q_revision_claim,
            no_public_fit_metric_claim,
            public_fit_metric_claim_allowed = false,
            n_blockers = 0,
            remaining_public_blockers = Symbol[],
            recommendation =
                :report_metric_sensitivity_as_local_diagnostic_appendix_only,
            next_gate = :construct_reviewed_q_fit_reporting_policy,
        ),
    )
end

function main(args)
    output = parse_args(args)
    artifact = build_artifact()
    write_artifact(output, artifact)
    println("wrote ", relpath(output, ROOT))
    println("passed=", artifact.summary.passed,
        " evidence_cells=", artifact.summary.n_fit_metric_evidence_cells,
        " next_gate=", artifact.summary.next_gate)
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
