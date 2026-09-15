module ReportFigureChecks
using Test, BayesianMGMFRM, Random, SHA
const B = BayesianMGMFRM
include("fixtures/reporting_fit.jl")
const options = (; include_artifact = false, include_loo = false, include_waic = false,
    include_calibration = false, include_category_functioning = false,
    include_rater_homogeneity = false, include_grouped_predictive = false)
readjson(path) = B.JSON3.read(read(path, String), Dict{String,Any})
const directory = get(ENV, "BAYESIANMGMFRM_REPORT_FIGURE_OUTPUT", mktempdir())
mkpath(directory)

@testset "report-only compatibility and figure requests" begin
    report = (; schema = "bayesianmgmfrm.fit_report.v1", object = :fit_report,
        family = :mfrm, created_at = "2026-09-14", estimation_status = :fit_supported,
        posterior = (; status = :computed, rows = [(; parameter = "rater[2]", median = 0.1)], n_rows = 1))
    for value in (report, fit_report_public(report))
        mktempdir() do path
            m = save_fit_report_bundle(path, value)
            @test m.schema == "bayesianmgmfrm.fit_report_bundle_export.v1"
            @test !hasproperty(m, :figures)
            @test load_fit_report_bundle(path)["posterior"]["n_rows"] == 1
            @test load_fit_report_bundle(path; return_manifest = true)["content_hash"]["value"] == m.content_hash.value
            before = read(joinpath(path, "manifest.json"))
            @test_throws ArgumentError save_fit_report_bundle(path, value;
                overwrite = true, figures = (posterior = (;),))
            @test read(joinpath(path, "manifest.json")) == before
            @test_throws ArgumentError save_fit_report_bundle(path, value;
                overwrite = true, figures = (posterior = (;),), seed = 42)
        end
    end
    f = reporting_fit(:mfrm; ndraws = 8, chains = 2)
    for figures in (true, (;), (unknown = (;),), (posterior = (interval = 0.9,),))
        path = joinpath(directory, "bad-options")
        @test_throws ArgumentError save_fit_report_bundle(path, f; figures, options...)
        @test !ispath(path)
    end
    @test_throws ArgumentError save_fit_report_bundle(joinpath(directory, "bad-seed"), f; seed = 42, options...)
    if Base.get_extension(B, :BayesianMGMFRMCairoMakieExt) === nothing
        @test_throws ArgumentError save_fit_report_bundle(joinpath(directory, "no-renderer"), f;
            figures = (posterior = (;),), options...)
        @test !ispath(joinpath(directory, "no-renderer"))
    end
end

if Base.get_extension(B, :BayesianMGMFRMCairoMakieExt) !== nothing
    @testset "figures and report share data, settings and persistence" begin
        for family in (:mfrm, :gmfrm, :mgmfrm)
            println("Report figure bundle: ", family); flush(stdout)
            fit = family === :mgmfrm ? reporting_fit(family; chains = 2, ndraws = 8,
                dimension_labels = ["Reasoning", "Communication"]) :
                reporting_fit(family; chains = 2, ndraws = 8)
            posterior = family === :mgmfrm ? (; block = :person, dimension = "Communication") : (; block = :rater)
            figures = (; posterior, diagnostics = posterior, predictive = (;))
            family === :mfrm && (figures = merge(figures, (; wright = (;))))
            path = joinpath(directory, String(family))
            cache = joinpath(directory, "$family.jls")
            save_fit_cache(cache, fit)
            before = sha256(read(cache)); restored = load_fit_cache(cache)
            Random.seed!(918); expected_random = rand(); Random.seed!(918)
            manifest = save_fit_report_bundle(path, restored; figures, seed = 42, ndraws = 12,
                posterior_lower = 0.05, posterior_upper = 0.95, predictive_interval = 0.8,
                view = :public, require_complete = true, options...)
            @test rand() == expected_random
            @test sha256(read(cache)) == before
            @test manifest.schema == "bayesianmgmfrm.fit_report_bundle_export.v2"
            @test length(manifest.figures) == length(figures)
            report = load_fit_report_bundle(path; require_complete = true)
            @test report["family"] == String(family)
            @test report["report_status"] == "complete"
            @test load_fit_report_bundle(path; return_manifest = true)["content_hash"]["value"] == manifest.content_hash.value
            for row in manifest.figures
                data = readjson(joinpath(path, "figures", "$(row.kind).json"))
                @test data["report_content_hash"]["value"] == manifest.report_content_hash.value
                @test data["caption"] == row.caption
                @test occursin(row.caption, read(joinpath(path, "fit_report.md"), String))
                @test occursin("figures/$(row.kind).svg", read(joinpath(path, "fit_report.md"), String))
                for file in row.files
                    @test isfile(joinpath(path, file.path))
                    @test bytes2hex(sha256(read(joinpath(path, file.path)))) == file.content_hash.value
                    @test filesize(joinpath(path, file.path)) > 100
                end
            end
            posterior_data = readjson(joinpath(path, "figures/posterior.json"))["data"]
            @test posterior_data["interval"] ≈ 0.9
            @test posterior_data["rows"] == B._json_export_value(B._posterior_plot_data(fit; posterior..., interval = 0.95 - 0.05).rows)
            section = family === :mfrm ? "posterior" : "direct_posterior"
            for row in posterior_data["rows"]
                row["fixed"] && continue
                reference = only(filter(r -> r["parameter"] == row["parameter"], report[section]["rows"]))
                @test row["median"] == reference["median"]
                @test row["lower"] ≈ reference["lower"]
                @test row["upper"] ≈ reference["upper"]
            end
            predictive_data = readjson(joinpath(path, "figures/predictive.json"))["data"]
            reference = filter(r -> r["statistic"] == "category_proportion", report["posterior_predictive"]["rows"])
            @test predictive_data["interval"] == 0.8
            @test predictive_data["draw_indices"] == report["posterior_predictive"]["draw_indices"]
            for (row, source) in zip(predictive_data["rows"], reference), key in ("observed", "replicated_mean", "replicated_lower", "replicated_upper")
                @test row[key] == source[key]
            end
            diagnostics_data = readjson(joinpath(path, "figures/diagnostics.json"))["data"]
            @test diagnostics_data["chain_ids"] == fit.chain_ids
            @test diagnostics_data["iterations"] == fit.iterations
            @test !haskey(diagnostics_data, "summary")
            if family === :mgmfrm
                @test all(r -> r["dimension"] == 2, posterior_data["rows"])
            end
            old_manifest = read(joinpath(path, "manifest.json"))
            @test_throws ArgumentError save_fit_report_bundle(path, fit;
                overwrite = true, figures = (posterior = (parameters = ["absent"],),), options...)
            @test read(joinpath(path, "manifest.json")) == old_manifest
            @test load_fit_report_bundle(path)["family"] == String(family)
            # Detect edits to either vector figures or their numerical inputs.
            for ext in ("pdf", "svg", "json")
                file = joinpath(path, "figures", "posterior.$ext")
                original = read(file); write(file, vcat(original, UInt8[0x20]))
                @test_throws ArgumentError load_fit_report_bundle(path)
                write(file, original)
            end
            altered = readjson(joinpath(path, "manifest.json"))
            altered["figures"][1]["files"][1]["path"] = "../outside.pdf"
            B._write_json_record(joinpath(path, "manifest.json"), altered)
            @test_throws ArgumentError load_fit_report_bundle(path; verify_hash = false)
            write(joinpath(path, "manifest.json"), old_manifest)
        end
        f = load_fit_cache(joinpath(directory, "mfrm.jls"))
        for extra in ((; posterior_lower = 0.1), (; rhat_threshold = 1.1),
                (; rng = MersenneTwister(2)), (; seed = true), (; include_posterior_predictive = false))
            path = joinpath(directory, "invalid-settings")
            @test_throws ArgumentError save_fit_report_bundle(path, f;
                figures = (posterior = (;), predictive = (;)), options..., extra...)
            @test !ispath(path)
        end
        @test_throws ArgumentError save_fit_report_bundle(joinpath(directory, "bad-wright"),
            load_fit_cache(joinpath(directory, "gmfrm.jls")); figures = (wright = (;),), options...)
        replay = joinpath(directory, "replay")
        save_fit_report_bundle(replay, f; figures = (predictive = (;),), seed = 42, ndraws = 12,
            predictive_interval = 0.8, options...)
        @test readjson(joinpath(replay, "figures/predictive.json"))["data"] ==
            readjson(joinpath(directory, "mfrm/figures/predictive.json"))["data"]
    end
    println("Report figure output retained at ", directory)
end
end
