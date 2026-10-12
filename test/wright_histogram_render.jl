module WrightHistogramRenderChecks
using BayesianMGMFRM, CairoMakie, Test
const B = BayesianMGMFRM
const W = Main.WrightHistogramChecks
axes(fig) = filter(x -> x isa Axis, fig.content)
@testset "editable histogram Wright and report output" begin
    io = IOBuffer(); fig = B.plot_wright(W.fit; W.options..., annotation_io = io)
    note = String(take!(io)); ax = axes(fig)
    @test fig isa Figure
    @test isempty(filter(x -> x isa Label, fig.content))
    @test length(ax) == 4
    @test ax[1].xlabel[] == "Number of persons"
    @test occursin("N = 80", ax[1].title[])
    @test all(a -> a.finallimits[].origin[2] == ax[1].finallimits[].origin[2] &&
        a.finallimits[].widths[2] == ax[1].finallimits[].widths[2], ax)
    @test fig.scene.viewport[].widths[1] < 2000
    @test occursin("one posterior median per person", note)
    @test occursin("Counts in increasing logit order", note)
    @test occursin("MCMC", note)
    h = B._wright_plot_data(W.fit; W.options...).histogram
    bars = only(p for p in ax[1].scene.plots if p isa BarPlot)
    # Test the plotted rectangles, including unequal bin widths, against numerical edges/counts.
    rectangles = bars.plots[1][1][]
    @test length(rectangles) == length(h.counts)
    for (b, rectangle) in enumerate(rectangles)
        @test rectangle.origin[1] ≈ 0
        @test rectangle.origin[2] ≈ h.edges[b]
        @test rectangle.widths[1] ≈ h.counts[b]
        @test rectangle.widths[2] ≈ h.edges[b+1] - h.edges[b]
    end
    embedded = B.plot_wright(W.fit; W.options..., annotation_io = nothing)
    labels = [String(x.text[]) for x in embedded.content if x isa Label]
    @test note == replace(labels[end-1], '\n' => ' ') * "\n\nNote. " * labels[end] * "\n"
    only_person = B.plot_wright(W.fit; W.options..., facets = :person, include_thresholds = false,
        annotation_io = IOBuffer())
    @test length(axes(only_person)) == 1
    for family in (:gmfrm, :mgmfrm)
        @test_throws ArgumentError B.plot_wright(W.reporting_fit(family); person_display = :histogram)
    end
    mktempdir() do dir
        for suffix in ("pdf", "svg", "png")
            path = joinpath(dir, "wright.$suffix"); save(path, fig)
            @test filesize(path) > 1000
        end
        bundle = joinpath(dir, "report")
        manifest = save_fit_report_bundle(bundle, W.fit; seed = 11,
            figures = (; wright = W.options), include_artifact = false,
            include_loo = false, include_waic = false, include_calibration = false,
            include_category_functioning = false, include_rater_homogeneity = false,
            include_grouped_predictive = false, ndraws = 2)
        payload = B.JSON3.read(read(joinpath(bundle, "figures/wright.json"), String))
        @test payload.data.histogram.counts == h.counts
        @test payload.data.histogram.edges == h.edges
        @test length(payload.data.rows) == 99
        @test payload.annotation_text == note
        @test occursin("*Note.* " * payload.caption, read(joinpath(bundle, "fit_report.md"), String))
        @test load_fit_report_bundle(bundle; return_manifest = true)["schema"] == manifest.schema
    end
end
end
