module ReportColumnChecks
using Test, BayesianMGMFRM
const B = BayesianMGMFRM

render(rows; kwargs...) = sprint(io -> B._write_markdown_table(io, rows; kwargs...))
function table_headers(markdown)
    lines = split(markdown, '\n')
    return [lines[i - 1] for i in 2:length(lines) if startswith(lines[i], "| ---")]
end

@testset "shared Markdown column order" begin
    rows = [(; zebra = "最後", upper = 1.0, mean = 0.0, parameter = "θ[1]",
        lower = -1.0, sd = 0.2, median = missing, alpha = "先頭")]
    expected = [:parameter, :mean, :sd, :median, :lower, :upper, :alpha, :zebra]
    @test B._markdown_row_fields(rows, 1) == expected
    markdown = render(rows)
    @test startswith(markdown, "| parameter | mean | sd | median | lower | upper | alpha | zebra |")
    @test occursin("| θ[1] | 0.0 | 0.2 |  | -1.0 | 1.0 | 先頭 | 最後 |", markdown)
    for converted in (
            [Dict(pairs(first(rows)))],
            [Dict(reverse(collect(pairs(first(rows)))))],
            B._json_export_value(rows))
        @test B._markdown_row_fields(converted, 1) == expected
        @test render(converted) == markdown
    end
    heterogeneous = Any[rows...,
        Dict("parameter" => "θ[2]", "mean" => nothing, "extra" => true)]
    @test render(heterogeneous) == render(B._json_export_value(heterogeneous))
    @test occursin("| θ[2] |  |  |  |  |  |  | true |  |", render(heterogeneous))
    @test render(rows; fields = (:upper, :parameter)) ==
        "| upper | parameter |\n| --- | --- |\n| 1.0 | θ[1] |\n"
    @test render(NamedTuple[]) == "*No rows to preview.*\n"
    @test render(rows; max_rows = 0) == "*No rows to preview.*\n"
    @test render(heterogeneous; max_rows = 1) ==
        render(B._json_export_value(heterogeneous); max_rows = 1)

    report = (; schema = "bayesianmgmfrm.fit_report.v1", object = :fit_report,
        created_at = "2026-09-13T00:00:00", family = :mfrm,
        estimation_status = :fit_supported,
        posterior = (; status = :computed, rows = heterogeneous, n_rows = 2),
        calibration = (; status = :computed, rows = NamedTuple[], n_rows = 0))
    explained = merge(report, (; metadata = (; model_label = "Named model", backend_label = "Named backend",
        target_identity = "target-identity", source_sample_content_hash = "sample-identity"),
        interpretation = "Generation completeness is separate from MCMC quality.",
        posterior = merge(report.posterior, (; interpretation = "Coordinate units explained.")),
        calibration = (; status = :unsupported, reason = "Calibration adapter unavailable."),
        loo = (; status = :error, message = "LOO calculation failed.")))
    for payload in (explained, B._json_export_value(explained)), max_rows in (0, 6)
        markdown = fit_report_markdown(payload; max_rows)
        for text in ("Named model", "Named backend", "target-identity", "sample-identity",
                "Generation completeness is separate", "Coordinate units explained.",
                "Calibration adapter unavailable.", "LOO calculation failed.")
            @test occursin(text, markdown)
        end
        @test count("Coordinate units explained.", markdown) == 1
    end
    @test !occursin("Coordinate units explained.", fit_report_markdown(report))
    mktempdir() do directory
        for (label, projected) in (("full", report), ("public", fit_report_public(report)))
            original_hash = B._fit_report_content_hash_record(projected)
            bundle = joinpath(directory, label)
            save_fit_report_bundle(bundle, projected; include_empty = true)
            loaded = load_fit_report_bundle(bundle)
            for (max_rows, include_empty) in ((0, false), (1, false), (6, true))
                before = fit_report_markdown(projected; max_rows, include_empty)
                after = fit_report_markdown(loaded; max_rows, include_empty)
                @test table_headers(after) == table_headers(before)
            end
            @test B._fit_report_content_hash_record(projected) == original_hash
            label == "public" && @test B._fit_report_content_hash_record(loaded) == original_hash
            @test loaded["posterior"]["rows"] == B._json_export_value(heterogeneous)
            tables = load_fit_report_tables(joinpath(bundle, "tables"))
            @test only(t for t in tables if t["section"] == "posterior")["rows"] ==
                loaded["posterior"]["rows"]
        end

        dossier = fit_report_dossier(:example => report;
            comparison_rows = [(; upper = 0.3, estimate = 0.1, model = "A", lower = -0.1)],
            sensitivity_rows = [(; sd = missing, mean = 0.0, parameter = "θ[1]")],
            evidence_rows = [(; zebra = "Z", alpha = "A")])
        path = joinpath(directory, "dossier.json")
        save_fit_report_dossier(path, dossier)
        loaded = load_fit_report_dossier(path)
        @test table_headers(fit_report_dossier_markdown(loaded)) ==
            table_headers(fit_report_dossier_markdown(dossier))
        for field in (:report_rows, :section_rows, :comparison_rows, :sensitivity_rows, :evidence_rows)
            @test isequal(loaded[String(field)], B._json_export_value(getproperty(dossier, field)))
        end
        @test occursin("| model | estimate | lower | upper |", fit_report_dossier_markdown(dossier))
        @test occursin("| parameter | mean | sd |", fit_report_dossier_markdown(loaded))
    end
end
end
