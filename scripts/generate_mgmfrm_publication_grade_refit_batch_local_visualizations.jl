#!/usr/bin/env julia

using Dates
using JSON3
using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_REPORT =
    joinpath(ROOT, "artifacts", "publication_grade_refit_batch", "reports",
        "missing_loading_revised_q_diagnostic_report.json")
const DEFAULT_OUTPUT_DIR =
    joinpath(ROOT, "artifacts", "publication_grade_refit_batch",
        "visualizations", "missing_loading_revised_q")

include(joinpath(@__DIR__, "local_json.jl"))

const REPORT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_publication_grade_refit_batch_local_diagnostic_report.v1"
const VISUALIZATION_SCHEMA =
    "bayesianmgmfrm.mgmfrm_publication_grade_refit_batch_local_visualizations.v1"

const MODEL_LABELS = Dict(
    "null_or_intercept_reference" => "Null",
    "scalar_gmfrm_baseline" => "Scalar",
    "confirmatory_mgmfrm_current_q" => "Current Q",
    "construct_reviewed_revised_q_mgmfrm" => "Revised Q",
    "sparse_mgmfrm_current_q" => "Sparse Q",
)

const PROFILE_LABELS = Dict(
    "strict_bayesian_workflow" => "Strict",
    "screening_workflow" => "Screening",
    "exploratory_rasch_lenient" => "Lenient",
    "sample_size_mean_square" => "Sample size",
)

const PROFILE_ORDER = [
    "strict_bayesian_workflow",
    "screening_workflow",
    "exploratory_rasch_lenient",
    "sample_size_mean_square",
]

function usage()
    return """
    Generate local SVG visualizations for a publication-grade refit batch
    diagnostic report.

    The output is intentionally local-only and plotting-backend independent.
    It writes SVG charts and a JSON plot-data bundle under artifacts/.

    Usage:
      julia --project=. scripts/generate_mgmfrm_publication_grade_refit_batch_local_visualizations.jl [options]

    Options:
      --report PATH      Local diagnostic report JSON.
      --output-dir PATH  Output directory for SVG and JSON artifacts.
    """
end

function parse_args(args)
    report = DEFAULT_REPORT
    output_dir = DEFAULT_OUTPUT_DIR
    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--report"
            index < length(args) || error("--report requires a path")
            report = abspath(args[index + 1])
            index += 2
        elseif arg == "--output-dir"
            index < length(args) || error("--output-dir requires a path")
            output_dir = abspath(args[index + 1])
            index += 2
        elseif arg in ("-h", "--help")
            println(usage())
            exit(0)
        else
            error("unknown argument: $arg")
        end
    end
    return (; report, output_dir)
end

project_version() =
    String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])
file_sha256(path::AbstractString) = bytes2hex(open(sha256, path))
rel(path::AbstractString) = relpath(path, ROOT)

as_string(value) = String(value)
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

function load_report(path::AbstractString)
    isfile(path) || error("report is missing: $path")
    report = JSON3.read(read(path, String))
    schema = as_string(report[:schema])
    schema == REPORT_SCHEMA ||
        error("unexpected report schema: $schema")
    return report
end

function escape_xml(value)
    text = string(value)
    text = replace(text, "&" => "&amp;")
    text = replace(text, "<" => "&lt;")
    text = replace(text, ">" => "&gt;")
    text = replace(text, "\"" => "&quot;")
    text = replace(text, "'" => "&apos;")
    return text
end

function model_label(model)
    key = as_string(model)
    return get(MODEL_LABELS, key,
        replace(titlecase(replace(key, "_" => " ")), "Mgmfrm" => "MGMFRM"))
end

function profile_label(profile)
    key = as_string(profile)
    return get(PROFILE_LABELS, key,
        replace(titlecase(replace(key, "_" => " ")), "Q" => "Q"))
end

function diagnostic_suffix(row)
    return as_bool(row[:all_diagnostic_gates_passed]) ? "" : " (diag flag)"
end

function axis_ticks(min_value, max_value; n = 5)
    span = max(max_value - min_value, eps(Float64))
    return [min_value + span * (i - 1) / (n - 1) for i in 1:n]
end

function write_svg(path::AbstractString, svg::AbstractString)
    mkpath(dirname(path))
    open(path, "w") do io
        write(io, svg)
    end
    return path
end

function format_num(value; digits = 3)
    return string(round(Float64(value); digits))
end

function format_pct(value)
    return string(round(100 * Float64(value); digits = 0), "%")
end

function mean_elpd_svg(report, model_rows)
    rows = sort(collect(model_rows);
        by = row -> as_float(row[:mean_heldout_elpd]), rev = true)
    values = [as_float(row[:mean_heldout_elpd]) for row in rows]
    min_value = minimum(values)
    max_value = maximum(values)
    span = max(max_value - min_value, eps(Float64))

    width = 980
    left = 280
    right = 230
    top = 86
    row_h = 58
    bottom = 76
    plot_w = width - left - right
    height = top + row_h * length(rows) + bottom
    scenario = escape_xml(report[:scenario])

    io = IOBuffer()
    println(io,
        """<svg xmlns="http://www.w3.org/2000/svg" width="$width" height="$height" viewBox="0 0 $width $height" role="img" aria-label="Mean heldout ELPD by model">""")
    println(io, "<rect width=\"$width\" height=\"$height\" fill=\"#ffffff\"/>")
    println(io,
        "<text x=\"24\" y=\"34\" font-family=\"Arial, sans-serif\" font-size=\"22\" font-weight=\"700\" fill=\"#1f2933\">Mean heldout ELPD by model</text>")
    println(io,
        "<text x=\"24\" y=\"60\" font-family=\"Arial, sans-serif\" font-size=\"13\" fill=\"#52616b\">Scenario: $scenario. Higher ELPD is better; failed diagnostic gates are marked in red.</text>")

    axis_y = top + row_h * length(rows) + 18
    println(io,
        "<line x1=\"$left\" y1=\"$axis_y\" x2=\"$(left + plot_w)\" y2=\"$axis_y\" stroke=\"#9aa5b1\" stroke-width=\"1\"/>")
    for tick in axis_ticks(min_value, max_value)
        x = left + plot_w * (tick - min_value) / span
        println(io,
            "<line x1=\"$x\" y1=\"$(top - 6)\" x2=\"$x\" y2=\"$axis_y\" stroke=\"#e4e7eb\" stroke-width=\"1\"/>")
        println(io,
            "<text x=\"$x\" y=\"$(axis_y + 20)\" text-anchor=\"middle\" font-family=\"Arial, sans-serif\" font-size=\"11\" fill=\"#52616b\">$(format_num(tick; digits = 1))</text>")
    end

    for (index, row) in enumerate(rows)
        y = top + (index - 1) * row_h
        mid_y = y + 28
        model = escape_xml(model_label(row[:model]) * diagnostic_suffix(row))
        value = as_float(row[:mean_heldout_elpd])
        bar_w = max(4.0, plot_w * (value - min_value) / span)
        color = as_bool(row[:all_diagnostic_gates_passed]) ? "#2f7d5c" : "#b42318"
        println(io,
            "<text x=\"24\" y=\"$(mid_y - 4)\" font-family=\"Arial, sans-serif\" font-size=\"14\" font-weight=\"700\" fill=\"#1f2933\">$model</text>")
        println(io,
            "<text x=\"24\" y=\"$(mid_y + 15)\" font-family=\"Arial, sans-serif\" font-size=\"11\" fill=\"#52616b\">mean rank $(format_num(row[:mean_rank]; digits = 1)), MAE $(format_num(row[:mean_heldout_expected_score_mae]; digits = 3))</text>")
        println(io,
            "<rect x=\"$left\" y=\"$(y + 8)\" width=\"$bar_w\" height=\"30\" rx=\"3\" fill=\"$color\"/>")
        println(io,
            "<text x=\"$(left + bar_w + 10)\" y=\"$(mid_y + 5)\" font-family=\"Arial, sans-serif\" font-size=\"13\" fill=\"#1f2933\">$(format_num(value; digits = 3))</text>")
    end
    println(io,
        "<text x=\"24\" y=\"$(height - 18)\" font-family=\"Arial, sans-serif\" font-size=\"11\" fill=\"#7b8794\">Local diagnostic visualization; not a public model-weight claim.</text>")
    println(io, "</svg>")
    return String(take!(io))
end

function rank_color(rank)
    colors = Dict(
        1 => "#2f7d5c",
        2 => "#4c78a8",
        3 => "#f2c94c",
        4 => "#f2994a",
        5 => "#d64545",
    )
    return get(colors, rank, "#cbd2d9")
end

function fold_rank_heatmap_svg(report, model_rows, fold_rows)
    models = [as_string(row[:model]) for row in sort(collect(model_rows);
        by = row -> as_float(row[:mean_rank]))]
    folds = sort(unique(as_int(row[:fold]) for row in fold_rows))
    row_by_key = Dict((as_int(row[:fold]), as_string(row[:model])) => row
        for row in fold_rows)

    left = 112
    top = 108
    cell_w = 134
    cell_h = 56
    right = 96
    bottom = 58
    width = left + cell_w * length(models) + right
    height = top + cell_h * length(folds) + bottom
    scenario = escape_xml(report[:scenario])

    io = IOBuffer()
    println(io,
        """<svg xmlns="http://www.w3.org/2000/svg" width="$width" height="$height" viewBox="0 0 $width $height" role="img" aria-label="Fold rank heatmap">""")
    println(io, "<rect width=\"$width\" height=\"$height\" fill=\"#ffffff\"/>")
    println(io,
        "<text x=\"24\" y=\"34\" font-family=\"Arial, sans-serif\" font-size=\"22\" font-weight=\"700\" fill=\"#1f2933\">Fold rank heatmap</text>")
    println(io,
        "<text x=\"24\" y=\"60\" font-family=\"Arial, sans-serif\" font-size=\"13\" fill=\"#52616b\">Scenario: $scenario. Rank 1 is best within fold; red outline marks diagnostic gate failure.</text>")
    for (col, model) in enumerate(models)
        x = left + (col - 1) * cell_w + cell_w / 2
        println(io,
            "<text x=\"$x\" y=\"91\" text-anchor=\"middle\" font-family=\"Arial, sans-serif\" font-size=\"12\" font-weight=\"700\" fill=\"#1f2933\">$(escape_xml(model_label(model)))</text>")
    end
    for (row_index, fold) in enumerate(folds)
        y = top + (row_index - 1) * cell_h
        println(io,
            "<text x=\"70\" y=\"$(y + 34)\" text-anchor=\"end\" font-family=\"Arial, sans-serif\" font-size=\"13\" font-weight=\"700\" fill=\"#1f2933\">Fold $fold</text>")
        for (col, model) in enumerate(models)
            x = left + (col - 1) * cell_w
            row = row_by_key[(fold, model)]
            rank = as_int(row[:rank])
            color = rank_color(rank)
            stroke = as_bool(row[:diagnostic_gate_passed]) ? "#ffffff" : "#b42318"
            stroke_width = as_bool(row[:diagnostic_gate_passed]) ? 1 : 4
            println(io,
                "<rect x=\"$x\" y=\"$y\" width=\"$(cell_w - 8)\" height=\"$(cell_h - 8)\" rx=\"3\" fill=\"$color\" stroke=\"$stroke\" stroke-width=\"$stroke_width\"/>")
            fill = rank == 3 ? "#1f2933" : "#ffffff"
            println(io,
                "<text x=\"$(x + (cell_w - 8) / 2)\" y=\"$(y + 30)\" text-anchor=\"middle\" font-family=\"Arial, sans-serif\" font-size=\"18\" font-weight=\"700\" fill=\"$fill\">$rank</text>")
            println(io,
                "<text x=\"$(x + (cell_w - 8) / 2)\" y=\"$(y + 45)\" text-anchor=\"middle\" font-family=\"Arial, sans-serif\" font-size=\"10\" fill=\"$fill\">ELPD $(format_num(row[:heldout_elpd]; digits = 1))</text>")
        end
    end
    println(io, "</svg>")
    return String(take!(io))
end

function pass_rate_color(rate)
    t = clamp(Float64(rate), 0.0, 1.0)
    if t == 0.0
        return "#eef2f6"
    end
    r0, g0, b0 = 215, 239, 211
    r1, g1, b1 = 35, 132, 67
    boosted = sqrt(t)
    r = round(Int, r0 + boosted * (r1 - r0))
    g = round(Int, g0 + boosted * (g1 - g0))
    b = round(Int, b0 + boosted * (b1 - b0))
    return "rgb($r,$g,$b)"
end

function threshold_profile_heatmap_svg(report, model_rows, profile_rows)
    models = [as_string(row[:model]) for row in sort(collect(model_rows);
        by = row -> as_float(row[:mean_rank]))]
    profiles = [profile for profile in PROFILE_ORDER
        if any(row -> as_string(row[:profile]) == profile, profile_rows)]
    row_by_key = Dict((as_string(row[:model]), as_string(row[:profile])) => row
        for row in profile_rows)

    left = 176
    top = 118
    cell_w = 132
    cell_h = 60
    right = 72
    bottom = 62
    width = left + cell_w * length(profiles) + right
    height = top + cell_h * length(models) + bottom
    scenario = escape_xml(report[:scenario])

    io = IOBuffer()
    println(io,
        """<svg xmlns="http://www.w3.org/2000/svg" width="$width" height="$height" viewBox="0 0 $width $height" role="img" aria-label="Threshold profile pass-rate heatmap">""")
    println(io, "<rect width=\"$width\" height=\"$height\" fill=\"#ffffff\"/>")
    println(io,
        "<text x=\"24\" y=\"34\" font-family=\"Arial, sans-serif\" font-size=\"22\" font-weight=\"700\" fill=\"#1f2933\">Threshold profile pass rate</text>")
    println(io,
        "<text x=\"24\" y=\"60\" font-family=\"Arial, sans-serif\" font-size=\"13\" fill=\"#52616b\">Scenario: $scenario. Cells show passed/evaluable rows; darker green means higher pass rate.</text>")
    for (col, profile) in enumerate(profiles)
        x = left + (col - 1) * cell_w + cell_w / 2
        println(io,
            "<text x=\"$x\" y=\"96\" text-anchor=\"middle\" font-family=\"Arial, sans-serif\" font-size=\"12\" font-weight=\"700\" fill=\"#1f2933\">$(escape_xml(profile_label(profile)))</text>")
    end
    for (row_index, model) in enumerate(models)
        y = top + (row_index - 1) * cell_h
        println(io,
            "<text x=\"154\" y=\"$(y + 31)\" text-anchor=\"end\" font-family=\"Arial, sans-serif\" font-size=\"12\" font-weight=\"700\" fill=\"#1f2933\">$(escape_xml(model_label(model)))</text>")
        for (col, profile) in enumerate(profiles)
            x = left + (col - 1) * cell_w
            row = row_by_key[(model, profile)]
            rate = as_float(row[:pass_rate_among_evaluable])
            color = pass_rate_color(rate)
            println(io,
                "<rect x=\"$x\" y=\"$y\" width=\"$(cell_w - 8)\" height=\"$(cell_h - 8)\" rx=\"3\" fill=\"$color\" stroke=\"#ffffff\" stroke-width=\"1\"/>")
            text_fill = rate >= 0.45 ? "#ffffff" : "#1f2933"
            passed = as_int(row[:n_passed_rows])
            evaluable = as_int(row[:n_evaluable_rows])
            println(io,
                "<text x=\"$(x + (cell_w - 8) / 2)\" y=\"$(y + 25)\" text-anchor=\"middle\" font-family=\"Arial, sans-serif\" font-size=\"15\" font-weight=\"700\" fill=\"$text_fill\">$passed/$evaluable</text>")
            println(io,
                "<text x=\"$(x + (cell_w - 8) / 2)\" y=\"$(y + 43)\" text-anchor=\"middle\" font-family=\"Arial, sans-serif\" font-size=\"11\" fill=\"$text_fill\">$(format_pct(rate))</text>")
        end
    end
    println(io,
        "<text x=\"24\" y=\"$(height - 20)\" font-family=\"Arial, sans-serif\" font-size=\"11\" fill=\"#7b8794\">Threshold profiles are diagnostic sensitivity checks; no profile is promoted for public claims here.</text>")
    println(io, "</svg>")
    return String(take!(io))
end

function model_plot_rows(model_rows)
    return [(;
        model = Symbol(as_string(row[:model])),
        label = model_label(row[:model]),
        mean_rank = as_float(row[:mean_rank]),
        n_fold_wins = as_int(row[:n_fold_wins]),
        mean_heldout_elpd = as_float(row[:mean_heldout_elpd]),
        mean_delta_elpd_from_best =
            as_float(row[:mean_delta_elpd_from_best]),
        mean_heldout_expected_score_mae =
            as_float(row[:mean_heldout_expected_score_mae]),
        all_diagnostic_gates_passed =
            as_bool(row[:all_diagnostic_gates_passed]),
    ) for row in model_rows]
end

function fold_heatmap_rows(fold_rows)
    return [(;
        fold = as_int(row[:fold]),
        model = Symbol(as_string(row[:model])),
        label = model_label(row[:model]),
        rank = as_int(row[:rank]),
        heldout_elpd = as_float(row[:heldout_elpd]),
        delta_elpd_from_best = as_float(row[:delta_elpd_from_best]),
        diagnostic_gate_passed = as_bool(row[:diagnostic_gate_passed]),
    ) for row in fold_rows]
end

function threshold_heatmap_rows(profile_rows)
    return [(;
        model = Symbol(as_string(row[:model])),
        model_label = model_label(row[:model]),
        profile = Symbol(as_string(row[:profile])),
        profile_label = profile_label(row[:profile]),
        n_evaluable_rows = as_int(row[:n_evaluable_rows]),
        n_passed_rows = as_int(row[:n_passed_rows]),
        n_flagged_rows = as_int(row[:n_flagged_rows]),
        pass_rate_among_evaluable =
            as_float(row[:pass_rate_among_evaluable]),
        threshold_profile_promoted =
            as_bool(row[:threshold_profile_promoted]),
        public_fit_metric_claim_allowed =
            as_bool(row[:public_fit_metric_claim_allowed]),
    ) for row in profile_rows]
end

function write_visualization_markdown(path::AbstractString, source_report_path,
    report, model_rows, mean_elpd_path, fold_rank_path, threshold_path)
    mkpath(dirname(path))
    rows = collect(model_rows)
    best = rows[argmax([as_float(row[:mean_heldout_elpd]) for row in rows])]
    diagnostic_flags = [model_label(row[:model]) for row in rows
        if !as_bool(row[:all_diagnostic_gates_passed])]
    flagged_text = isempty(diagnostic_flags) ? "none" :
        join(sort(diagnostic_flags), ", ")
    summary = report[:summary]
    open(path, "w") do io
        println(io, "# Local Visualization Report")
        println(io)
        println(io, "- Scenario: `", as_string(report[:scenario]), "`")
        println(io, "- Source report: `",
            relpath(source_report_path, dirname(path)), "`")
        println(io, "- Local only: `true`")
        println(io,
            "- Public fit, Q-revision, and model-weight claims: `blocked`")
        println(io)
        println(io, "## Key readouts")
        println(io)
        println(io, "- Best mean heldout ELPD in this slice: ",
            model_label(best[:model]), " (",
            format_num(best[:mean_heldout_elpd]; digits = 3), ")")
        println(io, "- Diagnostic gate flags: ", flagged_text)
        println(io, "- Threshold-profile passed/evaluable rows: ",
            as_int(summary[:n_threshold_profile_passed_rows]), "/",
            as_int(summary[:n_threshold_profile_evaluable_rows]))
        println(io)
        println(io, "## Figures")
        println(io)
        println(io, "### Mean heldout ELPD")
        println(io)
        println(io, "![Mean heldout ELPD](",
            relpath(mean_elpd_path, dirname(path)), ")")
        println(io)
        println(io, "### Fold rank heatmap")
        println(io)
        println(io, "![Fold rank heatmap](",
            relpath(fold_rank_path, dirname(path)), ")")
        println(io)
        println(io, "### Threshold profile pass rate")
        println(io)
        println(io, "![Threshold profile pass rate](",
            relpath(threshold_path, dirname(path)), ")")
    end
    return path
end

function main(args = ARGS)
    options = parse_args(args)
    report = load_report(options.report)
    mkpath(options.output_dir)

    model_rows = collect(report[:model_rank_summary_rows])
    fold_rows = collect(report[:fold_rank_rows])
    profile_rows = collect(report[:threshold_profile_summary_rows])

    mean_elpd_path = joinpath(options.output_dir, "mean_heldout_elpd.svg")
    fold_rank_path = joinpath(options.output_dir, "fold_rank_heatmap.svg")
    threshold_path =
        joinpath(options.output_dir, "threshold_profile_pass_rate.svg")
    plot_data_path = joinpath(options.output_dir, "plot_data.json")
    report_md_path = joinpath(options.output_dir, "visualization_report.md")

    write_svg(mean_elpd_path, mean_elpd_svg(report, model_rows))
    write_svg(fold_rank_path, fold_rank_heatmap_svg(report, model_rows, fold_rows))
    write_svg(threshold_path,
        threshold_profile_heatmap_svg(report, model_rows, profile_rows))
    write_visualization_markdown(report_md_path, options.report, report,
        model_rows, mean_elpd_path, fold_rank_path, threshold_path)

    artifact = (;
        schema = VISUALIZATION_SCHEMA,
        generated_at = Dates.format(now(UTC), dateformat"yyyy-mm-ddTHH:MM:SSZ"),
        package = (;
            name = "BayesianMGMFRM",
            version = project_version(),
        ),
        source_report = rel(options.report),
        source_report_sha256 = file_sha256(options.report),
        scenario = as_string(report[:scenario]),
        local_only = true,
        backend = :static_svg_no_plotting_dependency,
        public_fit_metric_claim_allowed = false,
        public_model_weight_claim_allowed = false,
        public_q_revision_claim_allowed = false,
        model_rank_plot_rows = model_plot_rows(model_rows),
        fold_rank_heatmap_rows = fold_heatmap_rows(fold_rows),
        threshold_profile_heatmap_rows = threshold_heatmap_rows(profile_rows),
        output_files = (;
            mean_heldout_elpd = rel(mean_elpd_path),
            fold_rank_heatmap = rel(fold_rank_path),
            threshold_profile_pass_rate = rel(threshold_path),
            plot_data = rel(plot_data_path),
            visualization_report = rel(report_md_path),
        ),
    )
    write_artifact(plot_data_path, artifact)

    println("wrote ", rel(mean_elpd_path))
    println("wrote ", rel(fold_rank_path))
    println("wrote ", rel(threshold_path))
    println("wrote ", rel(report_md_path))
    println("wrote ", rel(plot_data_path))
end

main()
