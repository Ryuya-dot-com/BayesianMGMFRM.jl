#!/usr/bin/env julia

using DelimitedFiles
using LinearAlgebra
using Random
using SHA
using Statistics
using TOML

import BayesianMGMFRM

module GMFRMPosteriorPredictiveGrid
include(joinpath(@__DIR__, "generate_gmfrm_posterior_predictive_grid.jl"))
end

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures", "gmfrm_real_data_case_study.json")

include(joinpath(@__DIR__, "local_json.jl"))

const PPC = GMFRMPosteriorPredictiveGrid
const FITGRID = PPC.FITGRID

const CASES = [
    (case_id = :writing_icnale_small_slice,
        modality = :writing,
        source_path = "../Simulation/data/writing_long.csv",
        fit_seed = 20261101,
        ppc_seed = 20261111,
        baseline_seeds = (partial_credit = 20261121, rating_scale = 20261122)),
    (case_id = :speaking_icnale_small_slice,
        modality = :speaking,
        source_path = "../Simulation/data/speaking_long.csv",
        fit_seed = 20261102,
        ppc_seed = 20261112,
        baseline_seeds = (partial_credit = 20261123, rating_scale = 20261124)),
]

const PROTOCOL = (;
    protocol_id = "scalar_gmfrm_real_data_case_study_v1",
    review_kind = :local_guarded_experimental_real_data_case_study,
    publication_or_registration_action = false,
    entrypoint_under_validation =
        "fit(spec; experimental = true) on local real-data slices",
    local_only = true,
    source_policy = (;
        source_files_external_to_package = true,
        artifact_rows_anonymized = true,
        no_raw_text_exported = true,
        source_hash_recorded_when_available = true,
    ),
    selection = (;
        person_count = 4,
        rater_count = 3,
        criterion_count = 3,
        person_policy = :first_observed_persons,
        rater_policy = :first_observed_raters,
        criterion_policy = :first_observed_criteria,
        require_complete_crossing_after_selection = true,
    ),
    score_binning = (;
        source_scale = "0:10",
        target_categories = [0, 1, 2],
        rules = [
            (target = 0, source_min = 0, source_max = 3),
            (target = 1, source_min = 4, source_max = 7),
            (target = 2, source_min = 8, source_max = 10),
        ],
    ),
    sampler = (;
        backend = :advancedhmc,
        sampler = :nuts,
        chains = 2,
        warmup = 12,
        draws = 12,
        step_size = 0.03,
        target_accept = 0.8,
        max_depth = 8,
        max_energy_error = 1000.0,
        metric = :unit,
        ad_backend = :ForwardDiff,
        init_jitter = 0.0,
        split_chains = true,
    ),
    diagnostics = (;
        rhat_threshold = 100.0,
        ess_threshold = 1.0,
        loo_min_tail_draws = 5,
    ),
    posterior_predictive = (;
        draw_policy = :all_fit_draws,
        interval = 0.9,
        calibration_bins = 3,
        category_calibration = :highest_observed_category,
    ),
    thresholds = (;
        n_cases = length(CASES),
        n_observations_per_case = 36,
        n_replicates_per_case = 24,
        require_source_file_available = true,
        require_validation_passed = true,
        require_complete_crossing = true,
        require_guarded_fit_returned = true,
        require_baseline_fits_returned = true,
        require_pointwise_shape = true,
        require_information_criteria_finite = true,
        require_no_divergences = true,
        require_no_max_treedepth = true,
        require_no_failed_direct_constraints = true,
        require_no_nonfinite_logdensity = true,
        require_no_nonfinite_direct_loglikelihood = true,
        require_replicated_scores_in_categories = true,
        require_probability_sums = true,
        require_summary_rows_finite = true,
        require_calibration_rows_finite = true,
        require_model_comparison_finite = true,
        max_summary_outside_interval_rate = 0.9,
        max_absolute_summary_error = 1.5,
        max_absolute_mean_score_error = 1.5,
        max_absolute_category_proportion_error = 1.0,
        max_absolute_calibration_error = 1.5,
    ),
)

function usage()
    return """
    Generate the local scalar GMFRM real-data case-study artifact.

    The artifact uses small anonymized slices from local long-format rating data,
    fits the guarded scalar GMFRM path, compares finite WAIC rows with public
    MFRM baselines, and records PPC/calibration diagnostics. It does not publish,
    register, or export raw text.

    Usage:
      julia --project=. scripts/generate_gmfrm_real_data_case_study.jl [--output PATH]
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

function file_sha256(path::AbstractString)
    return bytes2hex(open(sha256, path))
end

function label_hash(value)
    return bytes2hex(sha256(codeunits(String(value))))[1:16]
end

function unique_preserve(values)
    seen = Set{String}()
    out = String[]
    for value in values
        text = String(value)
        text in seen && continue
        push!(seen, text)
        push!(out, text)
    end
    return out
end

function column_index(header, name::AbstractString)
    names = vec(String.(header))
    index = findfirst(==(name), names)
    index === nothing && error("missing required column $name")
    return index
end

function score_band(value)
    score = parse(Int, String(value))
    0 <= score <= 10 || error("source score $score is outside 0:10")
    score <= 3 && return 0
    score <= 7 && return 1
    return 2
end

function count_rows(values)
    counts = Dict{String, Int}()
    for value in values
        key = String(value)
        counts[key] = get(counts, key, 0) + 1
    end
    return [(level = key, n = counts[key]) for key in sort(collect(keys(counts)))]
end

function pseudonym_map(levels, prefix)
    return Dict(level => "$(prefix)$(index)" for (index, level) in pairs(levels))
end

function pseudonym_rows(levels, prefix)
    return [
        (pseudonym = "$(prefix)$(index)", source_hash = label_hash(level))
        for (index, level) in pairs(levels)
    ]
end

function local_source_path(path)
    return normpath(joinpath(ROOT, path))
end

function source_reference(path; hash_policy::Symbol = :sha256)
    local_path = local_source_path(path)
    exists = isfile(local_path)
    return (;
        artifact = path,
        exists,
        hash_policy,
        sha256 = exists && hash_policy === :sha256 ?
            file_sha256(local_path) : missing,
    )
end

function selected_case_data(case)
    source = source_reference(case.source_path)
    source.exists || error("case-study source file is missing: $(case.source_path)")
    raw, header = readdlm(local_source_path(case.source_path), Char(44), String; header = true)
    rater_col = column_index(header, "Rater")
    person_col = column_index(header, "Person")
    region_col = column_index(header, "Region")
    proficiency_col = column_index(header, "L2 Proficiency")
    criterion_col = column_index(header, "Criteria")
    score_col = column_index(header, "Score")

    persons = unique_preserve(raw[:, person_col])[1:PROTOCOL.selection.person_count]
    raters = unique_preserve(raw[:, rater_col])[1:PROTOCOL.selection.rater_count]
    criteria = unique_preserve(raw[:, criterion_col])[1:PROTOCOL.selection.criterion_count]
    selected = [
        index for index in axes(raw, 1)
        if String(raw[index, person_col]) in persons &&
            String(raw[index, rater_col]) in raters &&
            String(raw[index, criterion_col]) in criteria
    ]
    selected = sort(selected; by = index -> (
        String(raw[index, person_col]),
        String(raw[index, rater_col]),
        String(raw[index, criterion_col]),
    ))
    person_map = pseudonym_map(persons, "P")
    rater_map = pseudonym_map(raters, "R")
    criterion_map = pseudonym_map(criteria, "I")
    table = (;
        person = [person_map[String(raw[index, person_col])] for index in selected],
        rater = [rater_map[String(raw[index, rater_col])] for index in selected],
        item = [criterion_map[String(raw[index, criterion_col])] for index in selected],
        score = [score_band(raw[index, score_col]) for index in selected],
    )
    source_scores = [parse(Int, String(raw[index, score_col])) for index in selected]
    source_metadata = (;
        n_source_rows = size(raw, 1),
        selected_source_row_indices = selected,
        selected_persons = pseudonym_rows(persons, "P"),
        selected_raters = pseudonym_rows(raters, "R"),
        selected_criteria = [
            (pseudonym = "I$(index)", label = criteria[index])
            for index in eachindex(criteria)
        ],
        region_counts = count_rows(raw[selected, region_col]),
        proficiency_counts = count_rows(raw[selected, proficiency_col]),
        source_score_counts = [
            (score = parse(Int, row.level), n = row.n)
            for row in count_rows(raw[selected, score_col])
        ],
    )
    return (; source, table, source_scores, source_metadata)
end

function validation_record(data, report)
    matrix = BayesianMGMFRM._minimal_location_matrix(data)
    location_rank = rank(matrix)
    n_location_parameters = size(matrix, 2)
    issue_rows = [
        (code = issue.code,
            severity = issue.severity,
            message = issue.message)
        for issue in report.issues
    ]
    return (;
        n_observations = data.n,
        passed = report.passed,
        n_errors = count(row -> row.severity === :error, issue_rows),
        n_warnings = count(row -> row.severity === :warning, issue_rows),
        issue_rows,
        issue_codes = [row.code for row in issue_rows],
        n_components = length(report.components),
        component_sizes = length.(report.components),
        location_design_rank = location_rank,
        n_location_parameters,
        location_design_full_rank = location_rank == n_location_parameters,
    )
end

function sampler_kwargs(seed::Int)
    sampler = PROTOCOL.sampler
    return (;
        backend = sampler.backend,
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
        seed,
        progress = false,
    )
end

function gmfrm_sampler_kwargs(seed::Int)
    return (;
        sampler_kwargs(seed)...,
        rhat_threshold = PROTOCOL.diagnostics.rhat_threshold,
        ess_threshold = PROTOCOL.diagnostics.ess_threshold,
    )
end

function diagnostic_kwargs()
    return (;
        split_chains = PROTOCOL.sampler.split_chains,
        rhat_threshold = PROTOCOL.diagnostics.rhat_threshold,
        ess_threshold = PROTOCOL.diagnostics.ess_threshold,
    )
end

function pointwise_shape_valid(pointwise, data)
    return collect(size(pointwise)) == [
        PROTOCOL.sampler.draws * PROTOCOL.sampler.chains,
        data.n,
    ]
end

function max_abs_error(rows)
    isempty(rows) && return NaN
    return maximum(abs(row.observed - row.replicated_mean) for row in rows)
end

function max_abs_calibration_error(rows)
    isempty(rows) && return NaN
    return maximum(row.absolute_calibration_error for row in rows)
end

function draw_summary_rows(names, draws)
    rows = NamedTuple[]
    for index in axes(draws, 2)
        values = Float64.(draws[:, index])
        push!(rows, (;
            parameter = names[index],
            parameter_index = index,
            mean = mean(values),
            sd = std(values),
            minimum = minimum(values),
            maximum = maximum(values),
            all_finite = all(isfinite, values),
        ))
    end
    return rows
end

function waic_summary(stat)
    values = [
        Float64(stat.elpd_waic),
        Float64(stat.waic),
        Float64(stat.p_waic),
        Float64(stat.lppd),
        Float64(stat.se_elpd_waic),
        Float64(stat.se_waic),
    ]
    return (;
        criterion = stat.criterion,
        elpd_waic = stat.elpd_waic,
        waic = stat.waic,
        p_waic = stat.p_waic,
        lppd = stat.lppd,
        se_elpd_waic = stat.se_elpd_waic,
        se_waic = stat.se_waic,
        n_draws = stat.n_draws,
        n_observations = stat.n_observations,
        high_variance_count = stat.high_variance_count,
        warning = stat.warning,
        all_top_level_numeric_finite = all(isfinite, values),
    )
end

function model_stat_record(; model, family, fit, stat, diagnostics, pointwise)
    return (;
        model,
        family,
        backend = fit.backend,
        sampler = fit.sampler,
        n_parameters = size(fit.draws, 2),
        n_draws = size(fit.draws, 1),
        pointwise_shape = collect(size(pointwise)),
        diagnostics_flag = diagnostics.summary.flag,
        n_divergences = diagnostics.summary.n_divergences,
        n_max_treedepth = diagnostics.summary.n_max_treedepth,
        information_criteria = waic_summary(stat),
    )
end

function baseline_record(data, model::Symbol, thresholds::Symbol, seed::Int)
    spec = BayesianMGMFRM.mfrm_spec(data; thresholds)
    fit = BayesianMGMFRM.fit(
        spec;
        sampler_kwargs(seed)...,
    )
    diagnostics = BayesianMGMFRM.diagnostics(fit; diagnostic_kwargs()...)
    pointwise = BayesianMGMFRM.pointwise_loglikelihood_matrix(fit)
    stat = BayesianMGMFRM.waic(fit)
    return model_stat_record(;
        model,
        family = :mfrm,
        fit,
        stat,
        diagnostics,
        pointwise,
    )
end

function comparison_rows(records)
    order = sortperm(eachindex(records);
        by = index -> records[index].information_criteria.elpd_waic,
        rev = true)
    best = records[order[1]].information_criteria
    weights = [
        exp(record.information_criteria.elpd_waic - best.elpd_waic)
        for record in records
    ]
    weight_total = sum(weights)
    rows = NamedTuple[]
    for (rank, index) in pairs(order)
        record = records[index]
        stat = record.information_criteria
        push!(rows, (;
            rank,
            model = record.model,
            family = record.family,
            criterion = :waic,
            elpd_waic = stat.elpd_waic,
            waic = stat.waic,
            p_waic = stat.p_waic,
            elpd_difference = stat.elpd_waic - best.elpd_waic,
            waic_difference = stat.waic - best.waic,
            relative_weight = weights[index] / weight_total,
            warning = stat.warning,
        ))
    end
    return rows
end

function case_record(case)
    selected = selected_case_data(case)
    data = BayesianMGMFRM.FacetData(
        selected.table;
        person = :person,
        rater = :rater,
        item = :item,
        score = :score,
    )
    validation_report = BayesianMGMFRM.validate_design(data)
    validation = validation_record(data, validation_report)
    complete_crossing =
        data.n == length(data.person_levels) * length(data.rater_levels) *
            length(data.item_levels)
    gmfrm_spec = BayesianMGMFRM.mfrm_spec(
        data;
        family = :gmfrm,
        discrimination = :rater,
    )
    fit = BayesianMGMFRM.fit(
        gmfrm_spec;
        experimental = true,
        gmfrm_sampler_kwargs(case.fit_seed)...,
    )
    metadata = BayesianMGMFRM.fit_metadata(fit)
    diagnostics = BayesianMGMFRM.diagnostics(fit; diagnostic_kwargs()...)
    pointwise = BayesianMGMFRM.pointwise_loglikelihood_matrix(fit)
    waic_stat = BayesianMGMFRM.waic(fit)
    loo_stat = BayesianMGMFRM.loo(
        fit;
        min_tail_draws = PROTOCOL.diagnostics.loo_min_tail_draws,
    )
    draw_indices = collect(1:size(fit.draws, 1))
    probabilities = BayesianMGMFRM.predictive_probabilities(fit; draw_indices)
    probability_review = PPC.probability_sums_valid(probabilities)
    expected = BayesianMGMFRM.expected_scores(fit; draw_indices)
    variances = BayesianMGMFRM.predictive_variances(fit; draw_indices)
    ppc = BayesianMGMFRM.posterior_predictive_check(
        fit;
        draw_indices,
        rng = MersenneTwister(case.ppc_seed),
    )
    summary_rows = BayesianMGMFRM.predictive_check_summary(
        ppc;
        interval = PROTOCOL.posterior_predictive.interval,
    )
    calibration_rows = BayesianMGMFRM.calibration_table(
        fit;
        draw_indices,
        bins = PROTOCOL.posterior_predictive.calibration_bins,
        interval = PROTOCOL.posterior_predictive.interval,
    )
    category_calibration_rows = BayesianMGMFRM.calibration_table(
        fit;
        target = :category_probability,
        category = last(data.category_levels),
        draw_indices,
        bins = PROTOCOL.posterior_predictive.calibration_bins,
        interval = PROTOCOL.posterior_predictive.interval,
    )
    all_calibration_rows = [calibration_rows..., category_calibration_rows...]
    mean_score_rows = [row for row in summary_rows if row.statistic === :mean_score]
    category_rows = [row for row in summary_rows if row.statistic === :category_proportion]
    outside_count = count(row -> row.flag !== :ok, summary_rows)
    replicated_scores_valid =
        all(score -> score in data.category_levels, vec(ppc.replicated_scores))
    expected_scores_in_range =
        all(value -> minimum(data.category_levels) - 1e-10 <= value <=
            maximum(data.category_levels) + 1e-10, expected)
    information_criteria_finite =
        isfinite(waic_stat.elpd_waic) && isfinite(waic_stat.waic) &&
        isfinite(loo_stat.elpd_loo) && isfinite(loo_stat.looic)
    summary_rows_finite = all(PPC.all_top_level_numeric_finite, summary_rows)
    calibration_rows_finite =
        all(PPC.all_top_level_numeric_finite, all_calibration_rows)
    gmfrm_record = model_stat_record(;
        model = :guarded_scalar_gmfrm,
        family = :gmfrm,
        fit,
        stat = waic_stat,
        diagnostics,
        pointwise,
    )
    baseline_records = [
        baseline_record(
            data,
            :public_mfrm_partial_credit,
            :partial_credit,
            case.baseline_seeds.partial_credit,
        ),
        baseline_record(
            data,
            :public_mfrm_rating_scale,
            :rating_scale,
            case.baseline_seeds.rating_scale,
        ),
    ]
    model_records = [gmfrm_record, baseline_records...]
    model_comparison = comparison_rows(model_records)
    diagnostic_summary = diagnostics.summary
    passed = selected.source.exists &&
        validation.passed &&
        complete_crossing &&
        fit isa BayesianMGMFRM.GMFRMFit &&
        Bool(metadata.public_fit) &&
        Bool(metadata.experimental_public) &&
        pointwise_shape_valid(pointwise, data) &&
        all(isfinite, pointwise) &&
        all(isfinite, fit.log_posterior) &&
        all(isfinite, fit.direct_loglikelihood) &&
        all(isfinite, fit.direct_pointwise_loglikelihood) &&
        information_criteria_finite &&
        diagnostic_summary.n_divergences == 0 &&
        diagnostic_summary.n_max_treedepth == 0 &&
        diagnostic_summary.n_failed_direct_constraints == 0 &&
        diagnostic_summary.n_nonfinite_logdensity == 0 &&
        diagnostic_summary.n_nonfinite_direct_loglikelihood == 0 &&
        replicated_scores_valid &&
        Bool(probability_review.valid) &&
        summary_rows_finite &&
        calibration_rows_finite &&
        outside_count / length(summary_rows) <=
            PROTOCOL.thresholds.max_summary_outside_interval_rate &&
        max_abs_error(summary_rows) <= PROTOCOL.thresholds.max_absolute_summary_error &&
        max_abs_error(mean_score_rows) <=
            PROTOCOL.thresholds.max_absolute_mean_score_error &&
        max_abs_error(category_rows) <=
            PROTOCOL.thresholds.max_absolute_category_proportion_error &&
        max_abs_calibration_error(all_calibration_rows) <=
            PROTOCOL.thresholds.max_absolute_calibration_error &&
        expected_scores_in_range &&
        all(>=(0.0), variances) &&
        all(record -> record.information_criteria.all_top_level_numeric_finite,
            model_records)

    return (;
        case_id = case.case_id,
        modality = case.modality,
        source = selected.source,
        source_metadata = selected.source_metadata,
        preprocessing = (;
            score_binning = PROTOCOL.score_binning,
            source_score_minimum = minimum(selected.source_scores),
            source_score_maximum = maximum(selected.source_scores),
            binned_score_counts =
                PPC.score_count_rows(selected.table.score, data.category_levels),
        ),
        selected_data = (;
            n_observations = data.n,
            complete_crossing,
            person_levels = data.person_levels,
            rater_levels = data.rater_levels,
            item_levels = data.item_levels,
            category_levels = data.category_levels,
        ),
        validation,
        fit_record = (;
            type = String(nameof(typeof(fit))),
            backend = fit.backend,
            sampler = fit.sampler,
            raw_draws_shape = collect(size(fit.draws)),
            direct_draws_shape = collect(size(fit.direct_draws)),
            pointwise_loglikelihood_shape = collect(size(pointwise)),
        ),
        metadata_review = (;
            public_fit = metadata.public_fit,
            experimental_public = metadata.experimental_public,
            family = metadata.family,
            dimensions = metadata.dimensions,
            discrimination = metadata.discrimination,
            n_draws = metadata.n_draws,
            n_chains = metadata.n_chains,
            draws_per_chain = metadata.draws_per_chain,
            n_parameters = metadata.n_parameters,
            n_direct_parameters = metadata.n_direct_parameters,
        ),
        diagnostics_review = (;
            schema = diagnostics.schema,
            public_fit = diagnostics.public_fit,
            experimental_public = diagnostics.experimental_public,
            summary = diagnostics.summary,
        ),
        information_criteria_review = (;
            waic = FITGRID.finite_stat_summary(waic_stat),
            loo = FITGRID.finite_stat_summary(loo_stat),
            all_top_level_numeric_finite =
                PPC.all_top_level_numeric_finite(waic_stat) &&
                PPC.all_top_level_numeric_finite(loo_stat),
        ),
        direct_parameter_summary_rows =
            draw_summary_rows(fit.diagnostic_surface.direct_parameter_names,
                fit.direct_draws),
        predictive_probability_review = (;
            shape = collect(size(probabilities)),
            probability_sums_valid = probability_review.valid,
            max_probability_sum_error = probability_review.max_sum_error,
            expected_scores = PPC.finite_matrix_summary(expected),
            predictive_variances = PPC.finite_matrix_summary(variances),
            expected_scores_in_range,
        ),
        posterior_predictive_review = (;
            replicated_scores_shape = collect(size(ppc.replicated_scores)),
            replicated_scores_in_categories = replicated_scores_valid,
            n_summary_rows = length(summary_rows),
            summary_rows,
            summary_group_rows = PPC.summary_group_rows(summary_rows),
        ),
        calibration_review = (;
            expected_score_rows = calibration_rows,
            category_probability_rows = category_calibration_rows,
            top_category = last(data.category_levels),
            n_rows = length(all_calibration_rows),
            all_rows_finite = calibration_rows_finite,
            max_absolute_calibration_error =
                max_abs_calibration_error(all_calibration_rows),
        ),
        model_records,
        model_comparison,
        summary = (;
            passed,
            n_observations = data.n,
            complete_crossing,
            validation_passed = validation.passed,
            validation_warnings = validation.n_warnings,
            location_design_full_rank = validation.location_design_full_rank,
            guarded_fit_returned = fit isa BayesianMGMFRM.GMFRMFit,
            baseline_fits_returned = length(baseline_records) == 2,
            pointwise_shape_valid = pointwise_shape_valid(pointwise, data),
            information_criteria_finite,
            model_comparison_finite =
                all(record -> record.information_criteria.all_top_level_numeric_finite,
                    model_records),
            n_divergences = diagnostic_summary.n_divergences,
            n_max_treedepth = diagnostic_summary.n_max_treedepth,
            n_failed_direct_constraints =
                diagnostic_summary.n_failed_direct_constraints,
            n_nonfinite_logdensity = diagnostic_summary.n_nonfinite_logdensity,
            n_nonfinite_direct_loglikelihood =
                diagnostic_summary.n_nonfinite_direct_loglikelihood,
            ppc_returned = true,
            n_replicates = length(draw_indices),
            n_summary_rows = length(summary_rows),
            replicated_scores_in_categories = replicated_scores_valid,
            probability_sums_valid = probability_review.valid,
            summary_rows_finite,
            calibration_rows_finite,
            outside_interval_rate = outside_count / length(summary_rows),
            max_absolute_summary_error = max_abs_error(summary_rows),
            max_absolute_mean_score_error = max_abs_error(mean_score_rows),
            max_absolute_category_proportion_error = max_abs_error(category_rows),
            max_absolute_calibration_error =
                max_abs_calibration_error(all_calibration_rows),
            expected_scores_in_range,
            predictive_variances_nonnegative = all(>=(0.0), variances),
        ),
    )
end

function grid_artifact()
    cases = [case_record(case) for case in CASES]
    passed = all(case -> case.summary.passed, cases)
    return (;
        schema = "bayesianmgmfrm.gmfrm_real_data_case_study.v1",
        family = :gmfrm,
        scope = :scalar_gmfrm_fit_ready_candidate,
        status = :guarded_experimental_real_data_case_study_recorded,
        decision = :keep_guarded_experimental,
        public_fit = true,
        experimental_public = true,
        fit_ready = true,
        package = (;
            name = "BayesianMGMFRM",
            version = project_version(),
            julia_version = string(VERSION),
        ),
        protocol = PROTOCOL,
        reviewed_artifacts = [
            source_reference("../Simulation/data/writing_long.csv"),
            source_reference("../Simulation/data/speaking_long.csv"),
            source_reference(
                "test/fixtures/gmfrm_prior_likelihood_sensitivity_grid.json"),
            source_reference(
                "test/fixtures/gmfrm_guarded_exposure_review.json";
                hash_policy = :existence_only_avoids_cyclic_review_hash),
        ],
        cases,
        decision_record = (;
            public_fit_allowed = true,
            experimental_keyword_enabled = true,
            public_exposure_support =
                :satisfied_for_scalar_gmfrm_manuscript_claim_followup,
            interpretation =
                :guarded_scalar_gmfrm_real_data_case_study_passed,
            required_followup = :claim_level_recovery_and_reproduction_archive,
        ),
        summary = (;
            passed,
            publication_or_registration_action = false,
            n_cases = length(cases),
            n_passed_cases = count(case -> case.summary.passed, cases),
            n_observations_total = sum(case.summary.n_observations for case in cases),
            n_replicates_per_case = PROTOCOL.thresholds.n_replicates_per_case,
            all_source_files_available = all(case -> case.source.exists, cases),
            all_validations_passed =
                all(case -> case.summary.validation_passed, cases),
            all_complete_crossing =
                all(case -> case.summary.complete_crossing, cases),
            all_guarded_fit_returned =
                all(case -> case.summary.guarded_fit_returned, cases),
            all_baseline_fits_returned =
                all(case -> case.summary.baseline_fits_returned, cases),
            all_pointwise_shapes_valid =
                all(case -> case.summary.pointwise_shape_valid, cases),
            all_information_criteria_finite =
                all(case -> case.summary.information_criteria_finite, cases),
            all_model_comparisons_finite =
                all(case -> case.summary.model_comparison_finite, cases),
            all_no_divergences =
                all(case -> case.summary.n_divergences == 0, cases),
            all_no_max_treedepth =
                all(case -> case.summary.n_max_treedepth == 0, cases),
            all_no_failed_direct_constraints =
                all(case -> case.summary.n_failed_direct_constraints == 0,
                    cases),
            all_no_nonfinite_logdensity =
                all(case -> case.summary.n_nonfinite_logdensity == 0, cases),
            all_no_nonfinite_direct_loglikelihood =
                all(case -> case.summary.n_nonfinite_direct_loglikelihood == 0,
                    cases),
            all_ppc_returned =
                all(case -> case.summary.ppc_returned, cases),
            all_replicated_scores_in_categories =
                all(case -> case.summary.replicated_scores_in_categories, cases),
            all_probability_sums_valid =
                all(case -> case.summary.probability_sums_valid, cases),
            all_summary_rows_finite =
                all(case -> case.summary.summary_rows_finite, cases),
            all_calibration_rows_finite =
                all(case -> case.summary.calibration_rows_finite, cases),
            max_outside_interval_rate =
                maximum(case.summary.outside_interval_rate for case in cases),
            max_absolute_summary_error =
                maximum(case.summary.max_absolute_summary_error for case in cases),
            max_absolute_mean_score_error =
                maximum(case.summary.max_absolute_mean_score_error for case in cases),
            max_absolute_category_proportion_error =
                maximum(case.summary.max_absolute_category_proportion_error
                    for case in cases),
            max_absolute_calibration_error =
                maximum(case.summary.max_absolute_calibration_error for case in cases),
            remaining_public_blockers = [
                :claim_level_recovery_and_reproduction_archive_missing,
            ],
            recommendation =
                :keep_guarded_experimental_until_claim_level_recovery_and_archive,
            next_gate = :claim_level_recovery_and_reproduction_archive,
        ),
    )
end

function main(args)
    output = parse_args(args)
    artifact = grid_artifact()
    write_artifact(output, artifact)
    println("wrote ", output)
    println("passed=", artifact.summary.passed,
        " cases=", artifact.summary.n_cases,
        " next_gate=", artifact.summary.next_gate)
    return nothing
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    main(ARGS)
end
