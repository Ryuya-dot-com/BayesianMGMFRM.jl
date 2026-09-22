# Optional CairoMakie test. Explicit cache paths replay real results; ordinary
# use generates synthetic records and never depends on research artifacts.
using BayesianMGMFRM, CairoMakie, Test, Random, Serialization
isdefined(@__MODULE__, :MGMFRMCorrelated2DFixtures) || include("mgmfrm_correlated_2d_fixtures.jl")
const B = BayesianMGMFRM

function check_correlated_render(fit, directory)
    options = (; include_prior_predictive = true, prior_predictive_ndraws = 19,
        prior_interval = 0.8, posterior_lower = 0.1, posterior_upper = 0.9,
        predictive_interval = 0.7, draw_indices = [8, 1, 1, 3], seed = 73, include_artifact = false)
    choices = (; posterior = (; block = :item_dimension_discrimination, dimension = 2),
        diagnostics = (; block = :latent_correlation), predictive = (;),
        prior = (; block = :latent_correlation), prior_predictive = (;))
    mkpath(directory)
    context = B._mgmfrm_correlated_2d_report_context(fit)
    report = fit_report(fit; options..., view = :full, require_complete = true)
    public = fit_report_public(report)
    @test !report.diagnostics.summary.passed
    path = joinpath(directory, "bundle")
    manifest = save_fit_report_bundle(path, fit; options..., figures = choices, require_complete = true)
    reopened = load_fit_report_bundle(path; require_complete = true)
    @test reopened["direct_posterior"] == B._json_export_value(public.direct_posterior)
    @test reopened["posterior_predictive"] == B._json_export_value(public.posterior_predictive)
    @test length(manifest.figures) == 5
    for kind in keys(choices)
        payload = B._read_json_dict(joinpath(path, "figures", "$kind.json"), "correlated figure inputs")
        @test payload["report_content_hash"]["value"] == manifest.report_content_hash.value
        @test payload["target_identity"] == fit.record.target_identity
        @test payload["source_sample_content_hash"] == fit.record.content_hash
        @test payload["data"]["backend"] == String(fit.record.run.backend)
        @test occursin("LKJ eta", payload["caption"])
        @test !occursin("unit logits", lowercase(payload["caption"]))
        if kind === :posterior
            data = B._mgmfrm_correlated_2d_plot_data(context; choices.posterior..., interval = 0.8)
            @test payload["data"] == B._json_export_value(data)
            for row in data.rows
                reported = only(filter(r -> r.parameter == row.parameter, report.direct_posterior.rows))
                @test row.lower ≈ reported.lower && row.upper ≈ reported.upper
            end
        elseif kind === :diagnostics
            @test only(payload["data"]["rows"])["values"] == tanh.(fit.record.run.draws[:, end])
            @test occursin("MCMC warnings", payload["caption"])
        elseif kind === :predictive
            @test payload["data"]["rows"] == B._json_export_value(predictive_check_plot_data(
                filter(r -> r.statistic === :category_proportion, report.posterior_predictive.rows)))
            @test payload["data"]["draw_indices"] == report.posterior_predictive.draw_indices
            @test payload["data"]["rng"]["seed"] == report.posterior_predictive.rng.seed
        elseif kind === :prior
            @test only(payload["data"]["rows"]) == B._json_export_value(only(report.prior_predictive.correlation_rows))
        end
        for suffix in ("pdf", "svg", "json")
            @test filesize(joinpath(path, "figures", "$kind.$suffix")) > 100
        end
    end
    for (name, options) in (("ability", (; block = :person, dimension = 2)),
            ("rho", (; block = :latent_correlation)), ("raw-rho", (; block = :latent_correlation, scale = :raw)))
        fig = B.plot_posterior(fit; options..., interval = 0.8)
        @test fig isa Figure
        axes = filter(x -> x isa Axis, fig.content)
        @test length(axes) == 1
        data = B._mgmfrm_correlated_2d_plot_data(context; options..., interval = 0.8)
        @test length(only(axes).yticks[][2]) == length(data.rows)
        old = only(axes).xlabel[]; only(axes).xlabel = "Edited coordinate"; @test only(axes).xlabel[] == "Edited coordinate"
        only(axes).xlabel = old
        save(joinpath(directory, "$name.png"), fig)
    end
    @test B.plot_diagnostics(fit; block = :latent_correlation, scale = :raw) isa Figure
    @test B.plot_predictive(fit; ndraws = 10, seed = 73) isa Figure
    files() = Dict(relpath(joinpath(d, n), path) => read(joinpath(d, n)) for (d, _, ns) in walkdir(path) for n in ns)
    before = files()
    @test_throws ArgumentError save_fit_report_bundle(path, fit; options..., overwrite = true,
        figures = (; posterior = (; parameters = ["absent"])))
    @test files() == before
    @test_throws ArgumentError save_fit_report_bundle(path, fit; options..., overwrite = true,
        figures = (; posterior = (; interval = 0.8)))
    @test files() == before
    for kind in keys(choices), suffix in ("pdf", "svg", "json")
        p = joinpath(path, "figures", "$kind.$suffix"); bytes = read(p)
        write(p, vcat(bytes, UInt8[0x20]))
        @test_throws ArgumentError load_fit_report_bundle(path)
        write(p, bytes)
    end
    @test files() == before
    @test fit.record.content_hash == B._mgmfrm_normalized_sample_hash(fit.record)
end

function run_correlated_render(directory, paths)
    @testset "correlated MGMFRM report figures and saved-result replay" begin
        if isempty(paths)
            for backend in (:advancedhmc, :cmdstan)
                t = MGMFRMCorrelated2DFixtures.target(); r = MGMFRMCorrelated2DFixtures.synthetic_record(t; backend)
                fit = B.Experimental.CorrelatedMGMFRMFit(r; expected_identity = r.target_identity)
                check_correlated_render(fit, joinpath(directory, String(backend)))
            end
        else
            for (i, path) in enumerate(paths)
                bytes = read(path); fit = load_fit_cache(path)
                check_correlated_render(fit, joinpath(directory, "$(fit.record.run.backend)-$i"))
                @test read(path) == bytes
            end
        end
    end
end
root = get(ENV, "BAYESIANMGMFRM_CORRELATED_REPORT_FIGURES", nothing)
root === nothing ? mktempdir(dir -> run_correlated_render(dir, ARGS)) : run_correlated_render(root, ARGS)
