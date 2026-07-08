#!/usr/bin/env julia

using Dates
using JSON3
using SHA
using Statistics
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_ARTIFACT_DIR =
    joinpath(ROOT, "artifacts", "publication_grade_refit_batch")
const DEFAULT_OUTPUT_DIR =
    joinpath(ROOT, "artifacts", "publication_grade_refit_batch", "reports")
const HELDOUT_SCORE_SCHEMA =
    "bayesianmgmfrm.mgmfrm_publication_grade_refit_job_heldout_score.v1"
const OUTPUT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_publication_grade_refit_batch_local_error_decomposition.v1"
const NULL_MODEL = "null_or_intercept_reference"

include(joinpath(@__DIR__, "local_json.jl"))

const MODEL_LABELS = Dict(
    "null_or_intercept_reference" => "Null",
    "scalar_gmfrm_baseline" => "Scalar",
    "confirmatory_mgmfrm_current_q" => "Current Q",
    "construct_reviewed_revised_q_mgmfrm" => "Revised Q",
    "sparse_mgmfrm_current_q" => "Sparse Q",
)

function usage()
    return """
    Generate a local pointwise error-decomposition report for an executed
    publication-grade refit batch slice.

    The report compares each non-null model with the null/intercept reference
    on the same heldout observations. It is descriptive and local-only.

    Usage:
      julia --project=. scripts/generate_mgmfrm_publication_grade_refit_batch_local_error_decomposition.jl [options]

    Options:
      --artifact-dir PATH  Directory containing *_heldout_score.json files.
      --scenario NAME      Scenario to analyze.
      --output-json PATH   JSON report path.
      --output-md PATH     Markdown report path.
    """
end

function parse_args(args)
    artifact_dir = DEFAULT_ARTIFACT_DIR
    scenario = "missing_loading_revised_q"
    output_json = nothing
    output_md = nothing
    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--artifact-dir"
            index < length(args) || error("--artifact-dir requires a path")
            artifact_dir = abspath(args[index + 1])
            index += 2
        elseif arg == "--scenario"
            index < length(args) || error("--scenario requires a name")
            scenario = String(args[index + 1])
            index += 2
        elseif arg == "--output-json"
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
    safe_scenario = replace(scenario, r"[^A-Za-z0-9_.-]" => "_")
    output_json === nothing && (output_json =
        joinpath(DEFAULT_OUTPUT_DIR,
            string(safe_scenario, "_error_decomposition.json")))
    output_md === nothing && (output_md =
        joinpath(DEFAULT_OUTPUT_DIR,
            string(safe_scenario, "_error_decomposition.md")))
    return (; artifact_dir, scenario, output_json, output_md)
end

project_version() =
    String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])
file_sha256(path::AbstractString) = bytes2hex(open(sha256, path))
rel(path::AbstractString) = relpath(path, ROOT)

as_string(value) = String(value)
as_symbol(value) = Symbol(String(value))
as_bool(value) = Bool(value)
as_int(value) = Int(value)
as_float(value) = Float64(value)

function round3(value)
    ismissing(value) && return missing
    return round(Float64(value); digits = 3)
end

function round4(value)
    ismissing(value) && return missing
    return round(Float64(value); digits = 4)
end

function mean_or_missing(values)
    isempty(values) && return missing
    return mean(values)
end

function model_label(model)
    key = as_string(model)
    return get(MODEL_LABELS, key,
        replace(titlecase(replace(key, "_" => " ")), "Mgmfrm" => "MGMFRM"))
end

function heldout_score_files(dir::AbstractString)
    isdir(dir) || error("artifact directory is missing: $dir")
    return sort([joinpath(dir, file) for file in readdir(dir)
        if endswith(file, "_heldout_score.json")])
end

function load_heldout_scores(dir::AbstractString, scenario::AbstractString)
    artifacts = NamedTuple[]
    for path in heldout_score_files(dir)
        artifact = JSON3.read(read(path, String))
        as_string(artifact[:schema]) == HELDOUT_SCORE_SCHEMA || continue
        as_string(artifact[:scenario]) == scenario || continue
        push!(artifacts, (;
            path,
            artifact,
            sha256 = file_sha256(path),
        ))
    end
    isempty(artifacts) &&
        error("no heldout score artifacts found for scenario: $scenario")
    return artifacts
end

function pointwise_rows(artifacts)
    rows = NamedTuple[]
    for source in artifacts
        artifact = source.artifact
        summary = artifact[:summary]
        as_bool(summary[:heldout_predictive_score_computed]) ||
            continue
        for row in artifact[:heldout_pointwise_rows]
            push!(rows, (;
                execution_unit_id = as_symbol(row[:execution_unit_id]),
                scenario = as_symbol(row[:scenario]),
                model = as_symbol(row[:model]),
                fold = as_int(row[:fold]),
                observation = as_int(row[:observation]),
                heldout_position = as_int(row[:heldout_position]),
                person = as_string(row[:person]),
                rater = as_string(row[:rater]),
                item = as_string(row[:item]),
                observed_score = as_int(row[:observed_score]),
                pointwise_log_predictive_density =
                    as_float(row[:pointwise_log_predictive_density]),
                expected_score_mean = as_float(row[:expected_score_mean]),
                observed_minus_expected_score =
                    as_float(row[:observed_minus_expected_score]),
                absolute_expected_score_error =
                    as_float(row[:absolute_expected_score_error]),
                squared_expected_score_error =
                    as_float(row[:squared_expected_score_error]),
                finite_score = as_bool(row[:finite_score]),
                public_claim_allowed = false,
            ))
        end
    end
    return rows
end

function group_rows(rows, keyfn)
    groups = Dict{Any, Vector{Any}}()
    for row in rows
        key = keyfn(row)
        push!(get!(groups, key, Any[]), row)
    end
    return groups
end

function point_key(row)
    return (row.fold, row.observation, row.heldout_position, row.person,
        row.rater, row.item, row.observed_score)
end

function model_summary_rows(rows)
    groups = group_rows(rows, row -> row.model)
    output = NamedTuple[]
    for (model, group) in groups
        lpds = [row.pointwise_log_predictive_density for row in group]
        abs_errors = [row.absolute_expected_score_error for row in group]
        squared_errors = [row.squared_expected_score_error for row in group]
        signed_errors = [row.observed_minus_expected_score for row in group]
        observed = [row.observed_score for row in group]
        expected = [row.expected_score_mean for row in group]
        push!(output, (;
            model,
            label = model_label(model),
            n_folds = length(unique(row.fold for row in group)),
            n_pointwise_rows = length(group),
            heldout_elpd = round3(sum(lpds; init = 0.0)),
            mean_log_predictive_density = round3(mean(lpds)),
            mean_absolute_expected_score_error = round3(mean(abs_errors)),
            root_mean_squared_expected_score_error =
                round3(sqrt(mean(squared_errors))),
            mean_observed_score = round3(mean(observed)),
            mean_expected_score = round3(mean(expected)),
            mean_observed_minus_expected_score = round3(mean(signed_errors)),
            all_pointwise_scores_finite = all(row.finite_score for row in group),
            public_claim_allowed = false,
        ))
    end
    return sort(output; by = row -> row.heldout_elpd, rev = true)
end

function fold_model_summary_rows(rows)
    groups = group_rows(rows, row -> (row.fold, row.model))
    summaries = NamedTuple[]
    for ((fold, model), group) in groups
        lpds = [row.pointwise_log_predictive_density for row in group]
        abs_errors = [row.absolute_expected_score_error for row in group]
        push!(summaries, (;
            fold,
            model,
            label = model_label(model),
            n_pointwise_rows = length(group),
            heldout_elpd = round3(sum(lpds; init = 0.0)),
            mean_log_predictive_density = round3(mean(lpds)),
            mean_absolute_expected_score_error = round3(mean(abs_errors)),
            public_claim_allowed = false,
        ))
    end
    ranked = NamedTuple[]
    for fold in sort(unique(row.fold for row in summaries))
        fold_rows = sort([row for row in summaries if row.fold == fold];
            by = row -> row.heldout_elpd, rev = true)
        for (rank, row) in enumerate(fold_rows)
            push!(ranked, merge(row, (rank = rank,)))
        end
    end
    return sort(ranked; by = row -> (row.fold, row.rank))
end

function comparison_rows(rows)
    null_rows = [row for row in rows if as_string(row.model) == NULL_MODEL]
    null_by_key = Dict(point_key(row) => row for row in null_rows)
    comparisons = NamedTuple[]
    missing_null = 0
    for row in rows
        as_string(row.model) == NULL_MODEL && continue
        key = point_key(row)
        if !haskey(null_by_key, key)
            missing_null += 1
            continue
        end
        null_row = null_by_key[key]
        delta_lpd =
            row.pointwise_log_predictive_density -
            null_row.pointwise_log_predictive_density
        delta_abs =
            row.absolute_expected_score_error -
            null_row.absolute_expected_score_error
        push!(comparisons, (;
            model = row.model,
            label = model_label(row.model),
            fold = row.fold,
            observation = row.observation,
            heldout_position = row.heldout_position,
            person = row.person,
            rater = row.rater,
            item = row.item,
            observed_score = row.observed_score,
            model_log_predictive_density =
                row.pointwise_log_predictive_density,
            null_log_predictive_density =
                null_row.pointwise_log_predictive_density,
            delta_lpd_vs_null = delta_lpd,
            model_expected_score = row.expected_score_mean,
            null_expected_score = null_row.expected_score_mean,
            expected_score_shift_vs_null =
                row.expected_score_mean - null_row.expected_score_mean,
            model_absolute_expected_score_error =
                row.absolute_expected_score_error,
            null_absolute_expected_score_error =
                null_row.absolute_expected_score_error,
            delta_abs_error_vs_null = delta_abs,
            model_better_lpd_than_null = delta_lpd > 0,
            model_better_abs_error_than_null = delta_abs < 0,
            public_claim_allowed = false,
        ))
    end
    return comparisons, missing_null
end

function summarize_comparisons(rows, keyfn, rowfn)
    groups = group_rows(rows, keyfn)
    output = NamedTuple[]
    for (key, group) in groups
        push!(output, rowfn(key, group))
    end
    return output
end

function model_vs_null_summary_rows(rows)
    output = summarize_comparisons(rows, row -> row.model,
        function (model, group)
        delta_lpd = [row.delta_lpd_vs_null for row in group]
        delta_abs = [row.delta_abs_error_vs_null for row in group]
        expected_shift = [row.expected_score_shift_vs_null for row in group]
        (; model,
            label = model_label(model),
            n_pointwise_rows = length(group),
            total_delta_lpd_vs_null = round3(sum(delta_lpd; init = 0.0)),
            mean_delta_lpd_vs_null = round3(mean(delta_lpd)),
            n_lpd_better_than_null =
                count(row -> row.model_better_lpd_than_null, group),
            share_lpd_better_than_null =
                round4(count(row -> row.model_better_lpd_than_null, group) /
                       length(group)),
            mean_delta_abs_error_vs_null = round3(mean(delta_abs)),
            n_abs_error_better_than_null =
                count(row -> row.model_better_abs_error_than_null, group),
            share_abs_error_better_than_null =
                round4(count(row -> row.model_better_abs_error_than_null,
                    group) / length(group)),
            mean_expected_score_shift_vs_null = round3(mean(expected_shift)),
            mean_model_expected_score =
                round3(mean(row.model_expected_score for row in group)),
            mean_null_expected_score =
                round3(mean(row.null_expected_score for row in group)),
            local_interpretation =
                mean(delta_lpd) < 0 && mean(delta_abs) > 0 ?
                    :lags_null_on_lpd_and_expected_score_error :
                    :mixed_pointwise_behavior,
            public_claim_allowed = false)
        end)
    return sort(output; by = row -> row.total_delta_lpd_vs_null, rev = true)
end

function fold_vs_null_summary_rows(rows)
    output = summarize_comparisons(rows, row -> (row.model, row.fold),
        function (key, group)
        model, fold = key
        delta_lpd = [row.delta_lpd_vs_null for row in group]
        delta_abs = [row.delta_abs_error_vs_null for row in group]
        (; model,
            label = model_label(model),
            fold,
            n_pointwise_rows = length(group),
            total_delta_lpd_vs_null = round3(sum(delta_lpd; init = 0.0)),
            mean_delta_lpd_vs_null = round3(mean(delta_lpd)),
            mean_delta_abs_error_vs_null = round3(mean(delta_abs)),
            share_lpd_better_than_null =
                round4(count(row -> row.model_better_lpd_than_null, group) /
                       length(group)),
            share_abs_error_better_than_null =
                round4(count(row -> row.model_better_abs_error_than_null,
                    group) / length(group)),
            public_claim_allowed = false)
        end)
    return sort(output; by = row -> (row.fold, row.total_delta_lpd_vs_null),
        rev = false)
end

function score_category_vs_null_summary_rows(rows)
    output = summarize_comparisons(rows, row -> (row.model, row.observed_score),
        function (key, group)
        model, observed_score = key
        delta_lpd = [row.delta_lpd_vs_null for row in group]
        delta_abs = [row.delta_abs_error_vs_null for row in group]
        (; model,
            label = model_label(model),
            observed_score,
            n_pointwise_rows = length(group),
            mean_delta_lpd_vs_null = round3(mean(delta_lpd)),
            mean_delta_abs_error_vs_null = round3(mean(delta_abs)),
            share_lpd_better_than_null =
                round4(count(row -> row.model_better_lpd_than_null, group) /
                       length(group)),
            mean_model_expected_score =
                round3(mean(row.model_expected_score for row in group)),
            mean_null_expected_score =
                round3(mean(row.null_expected_score for row in group)),
            mean_expected_score_shift_vs_null =
                round3(mean(row.expected_score_shift_vs_null for row in group)),
            public_claim_allowed = false)
        end)
    return sort(output; by = row -> (row.model, row.observed_score))
end

function facet_vs_null_summary_rows(rows)
    output = NamedTuple[]
    for facet in (:person, :rater, :item)
        groups = group_rows(rows, row -> (row.model, getproperty(row, facet)))
        for ((model, value), group) in groups
            delta_lpd = [row.delta_lpd_vs_null for row in group]
            delta_abs = [row.delta_abs_error_vs_null for row in group]
            push!(output, (;
                model,
                label = model_label(model),
                facet,
                value = String(value),
                n_pointwise_rows = length(group),
                mean_delta_lpd_vs_null = round3(mean(delta_lpd)),
                mean_delta_abs_error_vs_null = round3(mean(delta_abs)),
                share_lpd_better_than_null =
                    round4(count(row -> row.model_better_lpd_than_null,
                        group) / length(group)),
                mean_expected_score_shift_vs_null =
                    round3(mean(row.expected_score_shift_vs_null
                        for row in group)),
                public_claim_allowed = false,
            ))
        end
    end
    return sort(output; by = row -> (row.model, row.facet,
        row.mean_delta_lpd_vs_null))
end

function worst_pointwise_lpd_loss_rows(rows; per_model = 5)
    output = NamedTuple[]
    for model in sort(unique(row.model for row in rows); by = string)
        model_rows = sort([row for row in rows if row.model == model];
            by = row -> row.delta_lpd_vs_null)
        for row in Iterators.take(model_rows, min(per_model, length(model_rows)))
            push!(output, (;
                model = row.model,
                label = row.label,
                fold = row.fold,
                observation = row.observation,
                person = row.person,
                rater = row.rater,
                item = row.item,
                observed_score = row.observed_score,
                model_log_predictive_density =
                    round3(row.model_log_predictive_density),
                null_log_predictive_density =
                    round3(row.null_log_predictive_density),
                delta_lpd_vs_null = round3(row.delta_lpd_vs_null),
                model_expected_score = round3(row.model_expected_score),
                null_expected_score = round3(row.null_expected_score),
                delta_abs_error_vs_null =
                    round3(row.delta_abs_error_vs_null),
                public_claim_allowed = false,
            ))
        end
    end
    return output
end

function finding_rows(point_rows, fold_rows, model_vs_null_rows,
    missing_null_rows)
    fold_leaders = [first([row for row in fold_rows if row.fold == fold])
        for fold in sort(unique(row.fold for row in fold_rows))]
    null_wins = count(row -> as_string(row.model) == NULL_MODEL, fold_leaders)
    all_structured_lag_lpd =
        all(row -> row.mean_delta_lpd_vs_null < 0, model_vs_null_rows)
    all_structured_lag_abs =
        all(row -> row.mean_delta_abs_error_vs_null > 0, model_vs_null_rows)
    n_per_model = Dict(row.model => row.n_pointwise_rows
        for row in model_summary_rows(point_rows))
    min_n = minimum(values(n_per_model))
    max_n = maximum(values(n_per_model))
    return [
        (finding = :heldout_slice_is_small,
            severity = :warning,
            evidence = string(min_n, "-", max_n,
                " heldout pointwise rows per model across ",
                length(fold_leaders), " folds"),
            implication = :treat_rankings_as_local_diagnostic_not_public_claim),
        (finding = :null_reference_wins_completed_folds,
            severity = null_wins == length(fold_leaders) ? :warning : :info,
            evidence = string(null_wins, "/", length(fold_leaders),
                " completed folds led by the null/intercept reference"),
            implication = :investigate_signal_strength_q_matrix_and_calibration),
        (finding = :structured_models_lag_null_on_pointwise_lpd,
            severity = all_structured_lag_lpd ? :warning : :info,
            evidence = all_structured_lag_lpd ?
                "all non-null models have negative mean delta LPD vs null" :
                "at least one non-null model has mixed or positive delta LPD",
            implication = :do_not_claim_mgmfrm_predictive_superiority),
        (finding = :structured_models_lag_null_on_expected_score_error,
            severity = all_structured_lag_abs ? :warning : :info,
            evidence = all_structured_lag_abs ?
                "all non-null models have positive mean delta absolute expected-score error vs null" :
                "expected-score error is mixed across non-null models",
            implication = :inspect_expected_score_calibration_before_threshold_promotion),
        (finding = :null_matching_complete,
            severity = missing_null_rows == 0 ? :info : :blocker,
            evidence = string(missing_null_rows,
                " non-null pointwise rows lacked a matching null row"),
            implication = missing_null_rows == 0 ?
                :pointwise_null_comparison_is_complete :
                :decomposition_requires_repaired_matching),
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

function render_markdown(path::AbstractString, artifact)
    mkpath(dirname(path))
    open(path, "w") do io
        println(io, "# MGMFRM Local Error Decomposition")
        println(io)
        println(io, "- Scenario: `", artifact.scenario, "`")
        println(io, "- Null baseline: `", artifact.null_model, "`")
        println(io, "- Generated at: `", artifact.generated_at, "`")
        println(io, "- Local only: `true`")
        println(io, "- Public claims allowed: `false`")
        println(io)

        println(io, "## Reading Rules")
        println(io)
        println(io,
            "- `delta_lpd_vs_null < 0` means the model assigned lower ",
            "log predictive density than the null baseline for the same ",
            "heldout observation.")
        println(io,
            "- `delta_abs_error_vs_null > 0` means the model's expected ",
            "score was farther from the observed score than the null ",
            "baseline for the same heldout observation.")
        println(io)

        println(io, "## Findings")
        table(io, ["Finding", "Severity", "Evidence", "Implication"], [
            [row.finding, row.severity, row.evidence, row.implication]
            for row in artifact.finding_rows
        ])

        println(io, "## Model Summary")
        table(io, ["Model", "Rows", "ELPD", "Mean LPD", "MAE", "RMSE",
                "Mean Observed", "Mean Expected", "Bias Obs-Exp"],
            [[row.label, row.n_pointwise_rows, row.heldout_elpd,
                row.mean_log_predictive_density,
                row.mean_absolute_expected_score_error,
                row.root_mean_squared_expected_score_error,
                row.mean_observed_score, row.mean_expected_score,
                row.mean_observed_minus_expected_score]
             for row in artifact.model_summary_rows])

        println(io, "## Model vs Null")
        table(io, ["Model", "Rows", "Total dLPD", "Mean dLPD",
                "LPD Better", "Mean dAbsErr", "AbsErr Better",
                "Expected Shift", "Interpretation"],
            [[row.label, row.n_pointwise_rows,
                row.total_delta_lpd_vs_null, row.mean_delta_lpd_vs_null,
                row.share_lpd_better_than_null,
                row.mean_delta_abs_error_vs_null,
                row.share_abs_error_better_than_null,
                row.mean_expected_score_shift_vs_null,
                row.local_interpretation]
             for row in artifact.model_vs_null_summary_rows])

        println(io, "## Fold vs Null")
        table(io, ["Fold", "Model", "Rows", "Total dLPD", "Mean dLPD",
                "Mean dAbsErr", "LPD Better"],
            [[row.fold, row.label, row.n_pointwise_rows,
                row.total_delta_lpd_vs_null, row.mean_delta_lpd_vs_null,
                row.mean_delta_abs_error_vs_null,
                row.share_lpd_better_than_null]
             for row in artifact.fold_vs_null_summary_rows])

        println(io, "## Observed Score Category vs Null")
        table(io, ["Model", "Observed", "Rows", "Mean dLPD", "Mean dAbsErr",
                "LPD Better", "Model Exp", "Null Exp", "Exp Shift"],
            [[row.label, row.observed_score, row.n_pointwise_rows,
                row.mean_delta_lpd_vs_null,
                row.mean_delta_abs_error_vs_null,
                row.share_lpd_better_than_null,
                row.mean_model_expected_score, row.mean_null_expected_score,
                row.mean_expected_score_shift_vs_null]
             for row in artifact.score_category_vs_null_summary_rows])

        println(io, "## Largest Pointwise LPD Losses vs Null")
        table(io, ["Model", "Fold", "Obs", "Person", "Rater", "Item",
                "Score", "Model LPD", "Null LPD", "dLPD",
                "Model Exp", "Null Exp", "dAbsErr"],
            [[row.label, row.fold, row.observation, row.person, row.rater,
                row.item, row.observed_score,
                row.model_log_predictive_density,
                row.null_log_predictive_density,
                row.delta_lpd_vs_null,
                row.model_expected_score, row.null_expected_score,
                row.delta_abs_error_vs_null]
             for row in artifact.worst_pointwise_lpd_loss_rows])

        println(io, "## Interpretation Boundary")
        println(io)
        println(io,
            "This report explains the completed local scenario only. It is ",
            "not evidence for a public model-weight, fit-threshold, Q-revision, ",
            "or sparse-superiority claim. The next technical step is to repeat ",
            "this decomposition after expanding the remaining scenarios and to ",
            "connect the score-category and facet rows with Q-matrix revisions, ",
            "simulation thresholds, and construct-validation evidence.")
    end
    return path
end

function build_artifact(options)
    heldout_artifacts = load_heldout_scores(options.artifact_dir,
        options.scenario)
    points = pointwise_rows(heldout_artifacts)
    models = sort(unique(as_string(row.model) for row in points))
    NULL_MODEL in models ||
        error("null baseline model is missing for scenario: $(options.scenario)")
    comparisons, missing_null = comparison_rows(points)
    fold_rows = fold_model_summary_rows(points)
    model_rows = model_summary_rows(points)
    model_vs_null = model_vs_null_summary_rows(comparisons)
    fold_vs_null = fold_vs_null_summary_rows(comparisons)
    score_category_vs_null = score_category_vs_null_summary_rows(comparisons)
    facet_vs_null = facet_vs_null_summary_rows(comparisons)
    worst_rows = worst_pointwise_lpd_loss_rows(comparisons)
    findings = finding_rows(points, fold_rows, model_vs_null, missing_null)
    return (;
        schema = OUTPUT_SCHEMA,
        family = :mgmfrm,
        scope = :publication_grade_refit_batch_local_error_decomposition,
        status = :local_error_decomposition_recorded,
        scenario = Symbol(options.scenario),
        null_model = Symbol(NULL_MODEL),
        local_only = true,
        batch_only = true,
        publication_or_registration_action = false,
        public_fit_metric_claim = false,
        public_q_revision_claim = false,
        public_model_weight_claim = false,
        sparse_mgmfrm_superiority_claim = false,
        generated_at = string(now(UTC)),
        package = (;
            name = "BayesianMGMFRM",
            version = project_version(),
            julia_version = string(VERSION),
        ),
        source_heldout_artifacts = [(;
            path = rel(source.path),
            sha256 = source.sha256,
            model = as_symbol(source.artifact[:model]),
            fold = as_int(source.artifact[:fold]),
            n_heldout_pointwise_rows =
                as_int(source.artifact[:summary][:n_heldout_pointwise_rows]),
        ) for source in heldout_artifacts],
        summary = (;
            n_models = length(models),
            n_source_heldout_artifacts = length(heldout_artifacts),
            n_pointwise_rows = length(points),
            n_non_null_pointwise_comparison_rows = length(comparisons),
            n_missing_null_comparison_rows = missing_null,
            no_public_fit_metric_claim = true,
            no_public_q_revision_claim = true,
            no_public_model_weight_claim = true,
            no_sparse_superiority_claim = true,
            next_gate = :run_remaining_publication_grade_refit_batch_jobs,
        ),
        finding_rows = findings,
        model_summary_rows = model_rows,
        fold_model_summary_rows = fold_rows,
        model_vs_null_summary_rows = model_vs_null,
        fold_vs_null_summary_rows = fold_vs_null,
        score_category_vs_null_summary_rows = score_category_vs_null,
        facet_vs_null_summary_rows = facet_vs_null,
        worst_pointwise_lpd_loss_rows = worst_rows,
    )
end

function main(args)
    options = parse_args(args)
    artifact = build_artifact(options)
    write_artifact(options.output_json, artifact)
    render_markdown(options.output_md, artifact)
    println("wrote ", rel(options.output_json))
    println("wrote ", rel(options.output_md))
    println("scenario=", artifact.scenario,
        " models=", artifact.summary.n_models,
        " pointwise_rows=", artifact.summary.n_pointwise_rows,
        " comparison_rows=",
        artifact.summary.n_non_null_pointwise_comparison_rows,
        " missing_null_rows=",
        artifact.summary.n_missing_null_comparison_rows)
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
