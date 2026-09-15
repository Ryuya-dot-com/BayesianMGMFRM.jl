module WarmupReportChecks
using Test, BayesianMGMFRM
const B = BayesianMGMFRM

include("fixtures/reporting_fit.jl")

report_for(f; kwargs...) = fit_report(f; include_posterior_predictive = false,
    include_category_functioning = false, include_rater_homogeneity = false,
    include_calibration = false, include_waic = false, include_loo = false,
    include_artifact = false, kwargs...)
jsonvalue(value) = B._json_export_value(value)
warmup_preview(markdown) = first(split(last(split(markdown, "### warmup / rows"; limit = 2)), "\n### "; limit = 2))
table_headers(markdown) = [lines[i - 1] for lines in (split(markdown, '\n'),)
    for i in 2:length(lines) if startswith(lines[i], "| ---")]

@testset "warmup report sections across families and backend labels (no sampling)" begin
    for family in (:mfrm, :gmfrm, :mgmfrm), backend in (:advancedhmc, :cmdstan)
        println(stderr, "Checking warmup report: ", family, " / ", backend)
        flush(stderr)
        f = reporting_fit(family; backend)
        report = report_for(f; on_section_error = :throw, require_complete = true)
        @test isequal(report.warmup.rows, sampler_diagnostics(f; phase = :warmup))
        @test report.warmup.status === :computed && report.warmup.n_rows == 1
        row = only(report.warmup.rows)
        @test (row.n_divergences, row.n_max_treedepth, row.n_nonfinite_logdensity) == (1, 1, 1)
        @test report.report_status === :complete
        @test isequal(report.diagnostics, diagnostics(f))
        @test isempty(B._fit_report_warning_rows(report))
        @test !hasproperty(row, :flag)
        @test only(r for r in fit_report_sections(report) if r.section === :warmup).row_fields == [:rows]
        public_report = fit_report_public(report)
        @test isequal(public_report.warmup.rows, report.warmup.rows)
        @test public_report.warmup.interpretation == report.warmup.interpretation
        @test fit_report_public(public_report) === public_report
        for projected in (report, public_report)
            markdown = fit_report_markdown(projected)
            @test occursin("### warmup / rows", markdown)
            @test occursin(projected.warmup.interpretation, markdown)
            @test !occursin("## Warnings", markdown)
            mktempdir() do directory
                save_fit_report_bundle(directory, projected; require_complete = true)
                loaded = load_fit_report_bundle(directory; require_complete = true)
                @test loaded["warmup"]["rows"] == jsonvalue(projected.warmup.rows)
                @test loaded["warmup"]["interpretation"] == projected.warmup.interpretation
                @test isequal(fit_report_rows(loaded, :warmup), loaded["warmup"]["rows"])
                @test warmup_preview(fit_report_markdown(loaded)) == warmup_preview(markdown)
                @test table_headers(fit_report_markdown(loaded)) == table_headers(markdown)
                tables = load_fit_report_tables(joinpath(directory, "tables"))
                table = only(t for t in tables if t["section"] == "warmup")
                @test table["rows"] == loaded["warmup"]["rows"]
                @test table["row_field"] == "rows" && table["n_rows"] == 1
                @test loaded["diagnostics"] == jsonvalue(projected.diagnostics)
            end
        end
    end
end

@testset "warmup report coverage and captured errors (no sampling)" begin
    for (warmup, recorded, coverage) in ((3, false, :not_recorded), (0, true, :not_run), (0, false, :not_run))
        f = reporting_fit(:mfrm; warmup, recorded)
        report = report_for(f; require_complete = true)
        row = only(report.warmup.rows)
        @test row.coverage === coverage
        @test isequal(row.observed_iterations, warmup == 0 ? 0 : missing)
        @test isequal(row.n_divergences, warmup == 0 ? 0 : missing)
        mktempdir() do directory
            save_fit_report_bundle(directory, fit_report_public(report))
            loaded = load_fit_report_bundle(directory)
            saved = only(loaded["warmup"]["rows"])
            @test saved["observed_iterations"] === (warmup == 0 ? 0 : nothing)
            @test saved["n_divergences"] === (warmup == 0 ? 0 : nothing)
            @test occursin(String(coverage), read(joinpath(directory, "fit_report.md"), String))
        end
    end
    f = reporting_fit(:mfrm)
    empty!(f.sampler_controls.warmup_diagnostics)
    incomplete = report_for(f)
    @test incomplete.warmup.status === :error
    @test incomplete.report_status === :incomplete
    @test only(fit_report_health(incomplete).error_sections).section === :warmup
    @test_throws ArgumentError report_for(f; on_section_error = :throw)
    @test_throws ArgumentError report_for(f; require_complete = true)
    mktempdir() do directory
        path = joinpath(directory, "incomplete.json")
        save_fit_report(path, fit_report_public(incomplete))
        @test load_fit_report(path)["warmup"]["status"] == "error"
        @test_throws ArgumentError load_fit_report(path; require_complete = true)
    end
end
end
