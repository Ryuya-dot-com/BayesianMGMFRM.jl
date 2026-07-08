#!/usr/bin/env julia

using Dates
using JSON3
using SHA
using Statistics
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_REVIEW =
    joinpath(ROOT, "artifacts", "publication_grade_refit_batch",
        "current_batch_results_review.json")
const DEFAULT_OUTPUT_DIR =
    joinpath(ROOT, "artifacts", "publication_grade_refit_batch", "reports")
const DEFAULT_VISUALIZATION_ROOT =
    joinpath(ROOT, "artifacts", "publication_grade_refit_batch",
        "visualizations")

include(joinpath(@__DIR__, "local_json.jl"))

const REVIEW_SCHEMA =
    "bayesianmgmfrm.mgmfrm_publication_grade_refit_batch_results_review.v1"

function usage()
    return """
    Generate a local diagnostic report for an executed publication-grade refit
    batch slice.

    This report is intentionally local-only. It reads a local batch results
    review that may include ignored runner artifacts, summarizes one scenario's
    execution coverage, heldout ranks, threshold-profile sensitivity, and
    diagnostic failures, and writes both JSON and Markdown outputs under
    artifacts/.

    Usage:
      julia --project=. scripts/generate_mgmfrm_publication_grade_refit_batch_local_diagnostic_report.jl [options]

    Options:
      --review PATH       Local batch results review JSON.
      --scenario NAME     Scenario to report.
      --output-json PATH  JSON report path.
      --output-md PATH    Markdown report path.
    """
end

function parse_args(args)
    review = DEFAULT_REVIEW
    scenario = "missing_loading_revised_q"
    output_json = nothing
    output_md = nothing
    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--review"
            index < length(args) || error("--review requires a path")
            review = abspath(args[index + 1])
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
            string(safe_scenario, "_diagnostic_report.json")))
    output_md === nothing && (output_md =
        joinpath(DEFAULT_OUTPUT_DIR,
            string(safe_scenario, "_diagnostic_report.md")))
    return (; review, scenario, output_json, output_md)
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

function json_get(object, key::Symbol, default = missing)
    haskey(object, key) || return default
    value = object[key]
    value === nothing && return default
    ismissing(value) && return default
    return value
end

function load_review(path::AbstractString)
    isfile(path) || error("review is missing: $path")
    review = JSON3.read(read(path, String))
    schema = as_string(review[:schema])
    schema == REVIEW_SCHEMA ||
        error("unexpected review schema: $schema")
    return review
end

function rows_for_scenario(rows, scenario::AbstractString)
    return [row for row in rows if as_string(row[:scenario]) == scenario]
end

function mean_or_missing(values)
    isempty(values) && return missing
    return mean(values)
end

function round3(value)
    ismissing(value) && return missing
    return round(Float64(value); digits = 3)
end

function model_rank_summary_rows(rank_rows)
    models = sort(unique(as_string(row[:model]) for row in rank_rows))
    output = NamedTuple[]
    for model in models
        rows = [row for row in rank_rows if as_string(row[:model]) == model]
        ranks = [as_int(row[:rank]) for row in rows]
        elpds = [as_float(row[:heldout_elpd]) for row in rows]
        deltas = [as_float(row[:delta_elpd_from_best]) for row in rows]
        maes = [as_float(row[:heldout_expected_score_mae]) for row in rows]
        rmses = [as_float(row[:heldout_expected_score_rmse]) for row in rows]
        push!(output, (;
            model = Symbol(model),
            n_folds = length(rows),
            mean_rank = round3(mean_or_missing(ranks)),
            best_rank = minimum(ranks),
            worst_rank = maximum(ranks),
            n_fold_wins = count(==(1), ranks),
            mean_heldout_elpd = round3(mean_or_missing(elpds)),
            mean_delta_elpd_from_best = round3(mean_or_missing(deltas)),
            mean_heldout_expected_score_mae = round3(mean_or_missing(maes)),
            mean_heldout_expected_score_rmse = round3(mean_or_missing(rmses)),
            all_diagnostic_gates_passed =
                all(row -> as_bool(row[:diagnostic_gate_passed]), rows),
            public_model_weight_claim_allowed = false,
        ))
    end
    return output
end

function fold_rank_rows(rank_rows)
    rows = sort(rank_rows;
        by = row -> (as_int(row[:fold]), as_int(row[:rank])))
    return [(;
        fold = as_int(row[:fold]),
        rank = as_int(row[:rank]),
        model = as_symbol(row[:model]),
        heldout_elpd = round3(as_float(row[:heldout_elpd])),
        delta_elpd_from_best =
            round3(as_float(row[:delta_elpd_from_best])),
        heldout_expected_score_mae =
            round3(as_float(row[:heldout_expected_score_mae])),
        heldout_expected_score_rmse =
            round3(as_float(row[:heldout_expected_score_rmse])),
        diagnostic_gate_passed = as_bool(row[:diagnostic_gate_passed]),
        public_model_weight_claim_allowed = false,
    ) for row in rows]
end

function scenario_model_execution_rows(review, scenario::AbstractString)
    rows = rows_for_scenario(review[:scenario_model_summary_rows], scenario)
    return [(;
        model = as_symbol(row[:model]),
        n_execution_units = as_int(row[:n_execution_units]),
        n_complete_artifact_units =
            as_int(row[:n_complete_artifact_units]),
        n_executed_units = as_int(row[:n_executed_units]),
        n_diagnostic_gate_passed_units =
            as_int(row[:n_diagnostic_gate_passed_units]),
        n_heldout_scored_units = as_int(row[:n_heldout_scored_units]),
        public_claim_allowed = false,
    ) for row in rows]
end

function threshold_profile_summary_rows(review, scenario::AbstractString)
    rows =
        rows_for_scenario(review[:threshold_profile_scenario_model_summary_rows],
            scenario)
    return [(;
        model = as_symbol(row[:model]),
        profile = as_symbol(row[:profile]),
        n_threshold_profile_rows =
            as_int(row[:n_threshold_profile_rows]),
        n_evaluable_rows = as_int(row[:n_evaluable_rows]),
        n_passed_rows = as_int(row[:n_passed_rows]),
        n_flagged_rows = as_int(row[:n_flagged_rows]),
        pass_rate_among_evaluable =
            round3(json_get(row, :pass_rate_among_evaluable, missing)),
        any_threshold_profile_passed =
            as_bool(row[:any_threshold_profile_passed]),
        all_evaluable_rows_passed =
            as_bool(row[:all_evaluable_rows_passed]),
        threshold_profile_promoted = false,
        public_fit_metric_claim_allowed = false,
    ) for row in rows]
end

function diagnostic_failure_rows(review, scenario::AbstractString)
    rows = rows_for_scenario(review[:diagnostic_failure_rows], scenario)
    return [(;
        execution_unit_id = as_symbol(row[:execution_unit_id]),
        model = as_symbol(row[:model]),
        fold = as_int(row[:fold]),
        diagnostic = as_symbol(row[:diagnostic]),
        source = as_symbol(row[:source]),
        comparison = as_symbol(row[:comparison]),
        threshold = json_get(row, :threshold, missing),
        value = json_get(row, :value, missing),
        failure_kind = as_symbol(row[:failure_kind]),
        public_claim_allowed = false,
    ) for row in rows]
end

function visualization_rows(scenario::AbstractString)
    safe_scenario = replace(scenario, r"[^A-Za-z0-9_.-]" => "_")
    dir = joinpath(DEFAULT_VISUALIZATION_ROOT, safe_scenario)
    files = [
        (:visualization_report, "visualization_report.md"),
        (:mean_heldout_elpd, "mean_heldout_elpd.svg"),
        (:fold_rank_heatmap, "fold_rank_heatmap.svg"),
        (:threshold_profile_pass_rate, "threshold_profile_pass_rate.svg"),
        (:plot_data, "plot_data.json"),
    ]
    return [(;
        kind,
        path = rel(joinpath(dir, filename)),
        exists = isfile(joinpath(dir, filename)),
        public_claim_allowed = false,
    ) for (kind, filename) in files]
end

function related_report_rows(scenario::AbstractString)
    safe_scenario = replace(scenario, r"[^A-Za-z0-9_.-]" => "_")
    files = [
        (:error_decomposition,
            string(safe_scenario, "_error_decomposition.md")),
        (:error_decomposition_data,
            string(safe_scenario, "_error_decomposition.json")),
    ]
    return [(;
        kind,
        path = rel(joinpath(DEFAULT_OUTPUT_DIR, filename)),
        exists = isfile(joinpath(DEFAULT_OUTPUT_DIR, filename)),
        public_claim_allowed = false,
    ) for (kind, filename) in files]
end

function finding_rows(summary, execution_rows, rank_summary,
        threshold_rows, failures)
    n_units = sum(row.n_execution_units for row in execution_rows; init = 0)
    n_executed = sum(row.n_executed_units for row in execution_rows; init = 0)
    n_heldout = sum(row.n_heldout_scored_units for row in execution_rows; init = 0)
    n_profile_evaluable =
        sum(row.n_evaluable_rows for row in threshold_rows; init = 0)
    n_profile_passed =
        sum(row.n_passed_rows for row in threshold_rows; init = 0)
    winners = [row for row in rank_summary if row.n_fold_wins > 0]
    leader = isempty(winners) ? missing :
        first(sort(winners; by = row -> (-row.n_fold_wins, row.mean_rank)))
    return [
        (finding = :scenario_execution_complete,
            severity = n_units == n_executed == n_heldout ? :info : :blocker,
            evidence = string(n_executed, "/", n_units,
                " units executed and ", n_heldout, " heldout scored"),
            implication = :scenario_can_be_diagnosed_locally),
        (finding = :heldout_rank_leader,
            severity = :warning,
            evidence = ismissing(leader) ? "no leader" :
                string(leader.model, " won ", leader.n_fold_wins,
                    " folds; mean rank ", leader.mean_rank),
            implication = :do_not_claim_mgmfrm_superiority_from_this_scenario),
        (finding = :threshold_profile_sensitivity,
            severity = n_profile_passed == 0 ? :warning : :info,
            evidence = string(n_profile_passed, "/", n_profile_evaluable,
                " evaluable threshold-profile rows passed"),
            implication = :threshold_wording_must_remain_profile_specific),
        (finding = :diagnostic_failure_present,
            severity = isempty(failures) ? :info : :blocker,
            evidence = string(length(failures),
                " diagnostic failure row(s); batch gates passed ",
                summary[:n_diagnostic_gate_passed_units], "/",
                summary[:n_diagnostics_observed_units]),
            implication = :public_claims_remain_blocked),
        (finding = :public_claims_blocked,
            severity = :blocker,
            evidence = join(String.(summary[:remaining_public_blockers]), "; "),
            implication = :local_diagnostic_report_only),
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
        println(io, "# MGMFRM Publication-Grade Refit Local Diagnostic Report")
        println(io)
        println(io, "- Scenario: `", artifact.scenario, "`")
        println(io, "- Source review: `", artifact.source_review.path, "`")
        println(io, "- Generated at: `", artifact.generated_at, "`")
        println(io, "- Local only: `", artifact.local_only, "`")
        println(io, "- Public claims allowed: `false`")
        println(io)

        s = artifact.summary
        println(io, "## Summary")
        table(io, ["Metric", "Value"], [
            ["Executed units", s.n_executed_units],
            ["Heldout scored units", s.n_heldout_scored_units],
            ["Diagnostic gates passed", string(s.n_diagnostic_gate_passed_units,
                "/", s.n_diagnostics_observed_units)],
            ["Diagnostic failures", s.n_diagnostic_failure_rows],
            ["Threshold profile rows", s.n_threshold_profile_evaluable_rows],
            ["Threshold profile rows passed", s.n_threshold_profile_passed_rows],
            ["Threshold profile rows flagged", s.n_threshold_profile_flagged_rows],
            ["Next gate", s.next_gate],
        ])

        present_visualizations =
            [row for row in artifact.visualization_rows if row.exists]
        if !isempty(present_visualizations)
            println(io, "## Visualizations")
            println(io)
            println(io,
                "These local figures visualize the diagnostic slice only. ",
                "They do not permit public fit, Q-revision, model-weight, ",
                "or sparse-superiority claims.")
            println(io)
            for row in present_visualizations
                label = replace(titlecase(replace(String(row.kind), "_" => " ")),
                    "Elpd" => "ELPD")
                if endswith(String(row.path), ".svg")
                    println(io, "### ", label)
                    println(io)
                    println(io, "![", label, "](",
                        relpath(joinpath(ROOT, row.path), dirname(path)), ")")
                    println(io)
                else
                    println(io, "- ", label, ": `",
                        relpath(joinpath(ROOT, row.path), dirname(path)), "`")
                    println(io)
                end
            end
            println(io)
        end

        present_related_reports =
            [row for row in artifact.related_report_rows if row.exists]
        if !isempty(present_related_reports)
            println(io, "## Related Local Diagnostics")
            println(io)
            for row in present_related_reports
                label = replace(titlecase(replace(String(row.kind), "_" => " ")),
                    "Json" => "JSON")
                println(io, "- ", label, ": `",
                    relpath(joinpath(ROOT, row.path), dirname(path)), "`")
            end
            println(io)
        end

        println(io, "## Findings")
        table(io, ["Finding", "Severity", "Evidence", "Implication"], [
            [row.finding, row.severity, row.evidence, row.implication]
            for row in artifact.finding_rows
        ])

        println(io, "## Model Rank Summary")
        table(io,
            ["Model", "Folds", "Mean Rank", "Wins", "Mean ELPD",
                "Mean Delta", "Mean MAE", "Gate"],
            [[row.model, row.n_folds, row.mean_rank, row.n_fold_wins,
                row.mean_heldout_elpd, row.mean_delta_elpd_from_best,
                row.mean_heldout_expected_score_mae,
                row.all_diagnostic_gates_passed]
             for row in artifact.model_rank_summary_rows])

        println(io, "## Fold Ranks")
        table(io,
            ["Fold", "Rank", "Model", "ELPD", "Delta", "MAE", "Gate"],
            [[row.fold, row.rank, row.model, row.heldout_elpd,
                row.delta_elpd_from_best, row.heldout_expected_score_mae,
                row.diagnostic_gate_passed]
             for row in artifact.fold_rank_rows])

        println(io, "## Threshold Profiles")
        table(io,
            ["Model", "Profile", "Evaluable", "Passed", "Flagged", "Pass Rate"],
            [[row.model, row.profile, row.n_evaluable_rows,
                row.n_passed_rows, row.n_flagged_rows,
                row.pass_rate_among_evaluable]
             for row in artifact.threshold_profile_summary_rows])

        println(io, "## Diagnostic Failures")
        if isempty(artifact.diagnostic_failure_rows)
            println(io, "No diagnostic failure rows were observed.")
            println(io)
        else
            table(io,
                ["Unit", "Model", "Fold", "Diagnostic", "Value",
                    "Threshold", "Failure"],
                [[row.execution_unit_id, row.model, row.fold,
                    row.diagnostic, row.value, row.threshold,
                    row.failure_kind]
                 for row in artifact.diagnostic_failure_rows])
        end

        println(io, "## Interpretation Boundary")
        println(io,
            "This report is a local diagnostic artifact. It does not permit ",
            "public fit-metric, Q-revision, model-weight, or sparse-superiority ",
            "claims. The completed scenario is useful for identifying threshold ",
            "profile sensitivity and model-ranking behavior before expanding the ",
            "remaining batch.")
    end
    return path
end

function build_artifact(options)
    review = load_review(options.review)
    rank_rows = rows_for_scenario(review[:heldout_model_rank_rows],
        options.scenario)
    execution_rows = scenario_model_execution_rows(review, options.scenario)
    model_ranks = model_rank_summary_rows(rank_rows)
    fold_ranks = fold_rank_rows(rank_rows)
    threshold_rows = threshold_profile_summary_rows(review, options.scenario)
    failures = diagnostic_failure_rows(review, options.scenario)
    summary = review[:summary]
    n_executed = sum(row.n_executed_units for row in execution_rows; init = 0)
    n_heldout = sum(row.n_heldout_scored_units for row in execution_rows; init = 0)
    n_diag_passed =
        sum(row.n_diagnostic_gate_passed_units for row in execution_rows; init = 0)
    n_diag_observed =
        sum(row.n_executed_units for row in execution_rows; init = 0)
    n_threshold_evaluable =
        sum(row.n_evaluable_rows for row in threshold_rows; init = 0)
    n_threshold_passed =
        sum(row.n_passed_rows for row in threshold_rows; init = 0)
    n_threshold_flagged =
        sum(row.n_flagged_rows for row in threshold_rows; init = 0)
    local_summary = (;
        passed = true,
        scenario = Symbol(options.scenario),
        n_models = length(execution_rows),
        n_execution_units = sum(row.n_execution_units
            for row in execution_rows; init = 0),
        n_executed_units = n_executed,
        n_heldout_scored_units = n_heldout,
        n_diagnostics_observed_units = n_diag_observed,
        n_diagnostic_gate_passed_units = n_diag_passed,
        n_diagnostic_failure_rows = length(failures),
        n_threshold_profile_evaluable_rows = n_threshold_evaluable,
        n_threshold_profile_passed_rows = n_threshold_passed,
        n_threshold_profile_flagged_rows = n_threshold_flagged,
        no_public_fit_metric_claim = true,
        no_public_q_revision_claim = true,
        no_public_model_weight_claim = true,
        no_sparse_superiority_claim = true,
        next_gate = as_symbol(summary[:next_gate]),
    )
    findings = finding_rows(summary, execution_rows, model_ranks,
        threshold_rows, failures)
    return (;
        schema =
            "bayesianmgmfrm.mgmfrm_publication_grade_refit_batch_local_diagnostic_report.v1",
        family = :mgmfrm,
        scope = :publication_grade_refit_batch_local_diagnostic_report,
        status = :local_diagnostic_report_recorded,
        decision = :keep_public_claims_blocked_after_local_batch_slice,
        scenario = Symbol(options.scenario),
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
        source_review = (;
            path = rel(options.review),
            sha256 = file_sha256(options.review),
            schema = REVIEW_SCHEMA,
            local_artifacts_ignored =
                as_bool(review[:local_artifacts_ignored_for_fixture]) == false ?
                    false : true,
            review_summary = (;
                n_executed_units = as_int(summary[:n_executed_units]),
                n_diagnostic_failure_rows =
                    as_int(summary[:n_diagnostic_failure_rows]),
                n_threshold_profile_evaluable_rows =
                    as_int(summary[:n_threshold_profile_evaluable_rows]),
                next_gate = as_symbol(summary[:next_gate]),
            ),
        ),
        execution_rows,
        model_rank_summary_rows = model_ranks,
        fold_rank_rows = fold_ranks,
        threshold_profile_summary_rows = threshold_rows,
        diagnostic_failure_rows = failures,
        visualization_rows = visualization_rows(options.scenario),
        related_report_rows = related_report_rows(options.scenario),
        finding_rows = findings,
        summary = local_summary,
    )
end

function main(args)
    options = parse_args(args)
    artifact = build_artifact(options)
    write_artifact(options.output_json, artifact)
    render_markdown(options.output_md, artifact)
    println("wrote ", rel(options.output_json))
    println("wrote ", rel(options.output_md))
    println("scenario=", artifact.summary.scenario,
        " executed=", artifact.summary.n_executed_units,
        " diagnostic_failures=", artifact.summary.n_diagnostic_failure_rows,
        " threshold_passed=",
        artifact.summary.n_threshold_profile_passed_rows,
        " next_gate=", artifact.summary.next_gate)
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
