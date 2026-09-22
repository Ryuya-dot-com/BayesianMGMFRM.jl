# Optional check: run in an environment containing BayesianMGMFRM and CairoMakie.
println("Posterior figure checks: Julia ", VERSION); flush(stdout)
include("posterior_plot.jl")
println("Loading CairoMakie"); flush(stdout)
using Test, BayesianMGMFRM, CairoMakie
const B = BayesianMGMFRM
CairoMakie.activate!(; type = "svg")

function check_posterior_render(directory)
    @testset "editable posterior figures and cache reload" begin
        @test Base.get_extension(B, :BayesianMGMFRMCairoMakieExt) !== nothing
        for family in (:mfrm, :gmfrm, :mgmfrm)
            println("Rendering and reloading ", family); flush(stdout)
            f = PosteriorPlotChecks.fits[family]
            figure = B.plot_posterior(f)
            @test figure isa Figure
            axes = filter(x -> x isa Axis, figure.content)
            data = B._posterior_plot_data(f)
            @test length(axes) == length(data.groups)
            @test sum(length(ax.yticks[][2]) for ax in axes) == length(data.rows)
            @test all(ax -> ax.yreversed[], axes)
            @test sum(length(ax.scene.plots) for ax in axes) ==
                sum(row.fixed ? 1 : 2 for row in data.rows)
            original_label = axes[1].xlabel[]
            axes[1].xlabel = "Edited model coordinate"
            @test axes[1].xlabel[] == "Edited model coordinate"
            axes[1].xlabel = original_label
            for extension in ("pdf", "svg", "png")
                path = joinpath(directory, "$family.$extension")
                save(path, figure)
                @test filesize(path) > 1000
            end
            cache = joinpath(directory, "$family.jls")
            save_fit_cache(cache, f)
            loaded = load_fit_cache(cache)
            @test B._posterior_plot_data(loaded).rows == data.rows
            @test B._posterior_plot_data(loaded).diagnostic == data.diagnostic
            @test B.plot_posterior(loaded; block = :person) isa Figure
            @test B.plot_posterior(loaded; scale = :raw, block = :person) isa Figure
        end
        for family in (:mfrm, :gmfrm, :mgmfrm)
            println("Predictive rendering and reloading ", family); flush(stdout)
            fit = PosteriorPlotChecks.fits[family]
            data = B._predictive_plot_data(fit; ndraws = 80, seed = 42)
            figure = B.plot_predictive(fit; ndraws = 80, seed = 42)
            @test figure isa Figure
            ax = only(filter(x -> x isa Axis, figure.content))
            @test ax.yticks[][2] == string.(fit.design.spec.data.category_levels)
            @test ax.yreversed[]
            @test first.(ax.scene.plots[2][1][]) ≈ getproperty.(data.rows, :replicated_mean)
            @test first.(ax.scene.plots[3][1][]) ≈ getproperty.(data.rows, :observed)
            original = ax.xlabel[]; ax.xlabel = "Rating proportion"
            @test ax.xlabel[] == "Rating proportion"
            ax.xlabel = original
            for extension in ("pdf", "svg", "png")
                path = joinpath(directory, "$family-predictive.$extension")
                save(path, figure)
                @test filesize(path) > 1000
            end
            loaded = load_fit_cache(joinpath(directory, "$family.jls"))
            reloaded = B._predictive_plot_data(loaded; ndraws = 80, seed = 42)
            @test isequal(reloaded, data)
            @test B.plot_predictive(loaded; draw_indices = [1, 1, 4], interval = 0.8, seed = 42) isa Figure
        end
        unused_data = FacetData((; person = [1, 1, 1, 2, 2, 2], item = [1, 1, 2, 1, 2, 2],
            rater = [1, 2, 1, 1, 2, 1], score = [0, 2, 0, 2, 0, 2]);
            person = :person, item = :item, rater = :rater, score = :score, category_levels = 0:3)
        unused = PosteriorPlotChecks.reporting_fit(:mgmfrm; data = unused_data)
        figure = B.plot_predictive(unused; ndraws = 80, seed = 23)
        @test only(filter(x -> x isa Axis, figure.content)).yticks[][2] == ["0", "1", "2", "3"]
        save(joinpath(directory, "unused-category-predictive.png"), figure)
        for name in sort!(collect(keys(PosteriorPlotChecks.wright_fits)))
            println("Wright-map rendering and reloading ", name); flush(stdout)
            fit = PosteriorPlotChecks.wright_fits[name]
            data = B._wright_plot_data(fit)
            figure = B.plot_wright(fit)
            @test figure isa Figure
            axes = filter(x -> x isa Axis, figure.content)
            @test length(axes) == length(data.groups)
            @test all(ax -> !ax.yreversed[], axes)
            @test all(ax -> ax.finallimits[].origin[2] == first(axes).finallimits[].origin[2] &&
                ax.finallimits[].widths[2] == first(axes).finallimits[].widths[2], axes)
            for (ax, facet) in zip(axes, data.groups)
                rows = filter(row -> row.facet === facet, data.rows)
                @test length(ax.xticks[][2]) == length(rows)
                @test length(ax.scene.plots) == 1 + sum(row.is_fixed ? 1 : 2 for row in rows)
                offset = 1
                for (position, row) in enumerate(rows)
                    offset += row.is_fixed ? 1 : 2
                    point = only(ax.scene.plots[offset][1][])
                    @test point[1] ≈ position && point[2] ≈ row.position_median
                end
            end
            original = first(axes).ylabel[]; first(axes).ylabel = "Edited logit label"
            @test first(axes).ylabel[] == "Edited logit label"
            first(axes).ylabel = original
            for extension in ("pdf", "svg", "png")
                path = joinpath(directory, "$name-wright.$extension")
                save(path, figure)
                @test filesize(path) > 1000
            end
            cache = joinpath(directory, "$name-wright.jls")
            save_fit_cache(cache, fit)
            @test isequal(B._wright_plot_data(load_fit_cache(cache)), data)
        end
        figure = B.plot_wright(PosteriorPlotChecks.wright_fits[:anchored];
            facets = :rater, include_thresholds = false, interval = 0.8)
        @test length(filter(x -> x isa Axis, figure.content)) == 1
        save(joinpath(directory, "rater-only-wright.png"), figure)
        for family in (:gmfrm, :mgmfrm)
            @test_throws ArgumentError B.plot_wright(PosteriorPlotChecks.fits[family])
        end
        for family in (:mfrm, :gmfrm, :mgmfrm)
            println("Trace/rank rendering and reloading ", family); flush(stdout)
            fit = PosteriorPlotChecks.chain_fits[family]
            names = fit isa MFRMFit ? fit.design.parameter_names[1:2] : fit.diagnostic_surface.raw_parameter_names[1:2]
            data = B._diagnostic_plot_data(fit; parameters = names)
            figure = B.plot_diagnostics(fit; parameters = names)
            @test figure isa Figure
            axes = filter(x -> x isa Axis, figure.content)
            @test length(axes) == 4
            for chain in 1:2
                points = axes[1].scene.plots[chain][1][]
                @test first.(points) == 1:20
                @test last.(points) ≈ data.rows[1].values[(20 * (chain - 1) + 1):(20 * chain)]
            end
            original_xlabel = axes[1].xlabel[]
            axes[1].xlabel = "Retained iteration"
            @test axes[1].xlabel[] == "Retained iteration"
            axes[1].xlabel = original_xlabel
            for extension in ("pdf", "svg", "png")
                path = joinpath(directory, "$family-diagnostics.$extension")
                save(path, figure)
                @test filesize(path) > 1000
            end
            cache = joinpath(directory, "$family-chains.jls")
            save_fit_cache(cache, fit)
            loaded = load_fit_cache(cache)
            reloaded = B._diagnostic_plot_data(loaded; parameters = names)
            @test isequal(reloaded.rows, data.rows)
            @test reloaded.sampler_notes == data.sampler_notes
            @test B.plot_diagnostics(loaded; scale = :model, block = :person) isa Figure
        end
        one = B.plot_diagnostics(PosteriorPlotChecks.fits[:mfrm]; parameters = "person[1]")
        @test length(filter(x -> x isa Axis, one.content)) == 2
        save(joinpath(directory, "single-chain-diagnostics.png"), one)
        fixed = B.plot_diagnostics(PosteriorPlotChecks.chain_fits[:mfrm]; scale = :model,
            parameters = ["rater[1]", "step[item=1,2]"])
        @test length(filter(x -> x isa Axis, fixed.content)) == 4
        save(joinpath(directory, "fixed-derived-diagnostics.png"), fixed)
        tiny = B.plot_diagnostics(PosteriorPlotChecks.reporting_fit(:mfrm; chains = 2, ndraws = 1); block = :person)
        @test tiny isa Figure
        @test B.plot_diagnostics(PosteriorPlotChecks.chain_fits[:mfrm]; parameters = "person[1]", bins = 1) isa Figure
        fixed_axes = filter(x -> x isa Axis, fixed.content)
        @test Tuple(fixed_axes[1].limits[][1]) == (0.5, 20.5)
        only_fixed = B.plot_diagnostics(PosteriorPlotChecks.chain_fits[:mfrm]; scale = :model, parameters = "rater[1]")
        @test only_fixed isa Figure
        labelled = PosteriorPlotChecks.reporting_fit(:mgmfrm;
            dimension_labels = ["Word-level comprehensibility", "Accentedness"])
        figure = B.plot_posterior(labelled; block = :person)
        @test occursin("Word-level comprehensibility", filter(x -> x isa Axis, figure.content)[1].title[])
        save(joinpath(directory, "dimensions.png"), figure)
        anchored = PosteriorPlotChecks.reporting_fit(:mfrm;
            anchors = [(; block = :rater, level = 2, value = 0.75, type = :hard)])
        save(joinpath(directory, "anchored.png"), B.plot_posterior(anchored; block = :rater))
    end
end

if isempty(ARGS)
    mktempdir(check_posterior_render)
else
    mkpath(only(ARGS))
    check_posterior_render(only(ARGS))
end
