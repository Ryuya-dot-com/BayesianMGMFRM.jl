# Optional example checks: artificial draws, no fitting.
using Test, BayesianMGMFRM, CairoMakie
const B = BayesianMGMFRM
include("fixtures/reporting_fit.jl")
include("../examples/response_surface_variants.jl")

@testset "Item and rater surface comparisons" begin
    fit = reporting_fit(:mgmfrm; chains = 2, ndraws = 20)
    options = (; items = [2, 1], raters = [2, 1], category = 2,
        x = [-1., 0., 1.], y = [-2., 0., 2.])
    io = IOBuffer()
    result = response_surface_variants(fit; options..., annotation_io = io)
    @test result.item_data[1] === result.rater_data[1]
    @test [s.item for s in result.item_data] == [2, 1]
    @test [s.rater for s in result.rater_data] == [2, 1]
    @test all(s -> s.rater == 2, result.item_data)
    @test all(s -> s.item == 2, result.rater_data)
    @test result.item_data[1].active_dimensions == (false, true)
    @test result.item_data[2].active_dimensions == (true, false)
    @test occursin(result.item_note, String(take!(io)))
    @test occursin("Images omit uncertainty", result.rater_note)
    @test occursin(result.item_data[1].diagnostic, result.item_note)
    for (figure, data) in ((result.items, result.item_data), (result.raters, result.rater_data))
        axes = filter(block -> block isa Axis3, figure.content)
        @test length(axes) == 2
        @test !any(block -> block isa Label, figure.content)
        @test only(filter(block -> block isa Colorbar, figure.content)).limits[] == (0, 1)
        for (axis, surface) in zip(axes, data)
            reference = B.item_response_surface(fit; item = surface.item, rater = surface.rater,
                x = options.x, y = options.y, category = 2, interval = 0.90)
            @test surface.mean == reference.mean
            @test surface.lower == reference.lower && surface.upper == reference.upper
            @test axis.scene.plots[1][3][] ≈ surface.mean
            @test Tuple(axis.scene.plots[1].colorrange[]) == (0, 1)
            @test axis.limits[] == (-1., 1., -2., 2., 0, 1)
            @test axis.azimuth[] ≈ 1.275pi && axis.elevation[] ≈ pi / 7
            @test surface.n_draws == 40
        end
    end
    for override in ((; items = Int[]), (; raters = Int[]), (; items = [1, "1"]),
        (; raters = [2, 2]), (; items = [99]), (; raters = [99]),
        (; category = :all), (; category = 99), (; category = true),
        (; x = [1., -1.]), (; annotation_io = nothing))
        @test_throws ArgumentError response_surface_variants(fit;
            merge(options, (; annotation_io = IOBuffer()), override)...)
    end
    mktemp() do path, stream
        redirect_stdout(stream) do
            single = response_surface_variants(fit; items = [1], raters = [1],
                category = 2, x = [-1., 1.], y = [-1., 1.])
            @test length(single.item_data) == length(single.rater_data) == 1
            @test length(filter(block -> block isa Axis3, single.items.content)) == 1
        end
        flush(stream)
        @test occursin("Item Comparison at Rater 1", read(path, String))
        @test occursin("Rater Comparison at Item 1", read(path, String))
    end
end
