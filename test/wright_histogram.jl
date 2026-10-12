module WrightHistogramChecks
using BayesianMGMFRM, Test, Random, Statistics, SHA
const B = BayesianMGMFRM
include("fixtures/reporting_fit.jl")
include("fixtures/wright_histogram_fit.jl")

const fit = wright_histogram_fit()
const options = (; person_display = :histogram, bins = [-3., -1., 0., 0.5, 1., 3.])
@testset "Wright person frequency counts and roster" begin
    @test B._wright_person_histogram([-1., -0.5, 0., 0., 0.5, 1.], [-1., 0., 1.]).counts == [2, 4]
    @test B._wright_person_histogram([0.], nothing).edges == [-0.5, 0.5]
    @test B._wright_person_histogram(fill(2., 80), 1).counts == [80]
    @test B._wright_person_histogram(fill(2., 80), 1).edges == [1.5, 2.5]
    data = B._wright_plot_data(fit; options...)
    people = filter(r -> r.facet === :person, data.rows)
    h = data.histogram
    @test length(people) == h.n_persons == sum(h.counts) == 80
    @test length(data.rows) == 99
    @test data.n_individual_positions == 19
    @test getproperty.(people, :level) == fit.design.spec.data.person_levels
    @test getproperty.(people, :position_median) == [median(fit.draws[:, k]) for k in fit.design.blocks[:person]]
    @test h.counts == [count(r -> h.edges[b] <= r.position_median &&
        (b == length(h.counts) ? r.position_median <= h.edges[b+1] : r.position_median < h.edges[b+1]), people)
        for b in eachindex(h.counts)]
    @test h.summary === :posterior_median
    @test h.closure === :left_closed_last_closed
    @test isequal(data.rows, wright_map_data(fit))
    @test data.diagnostic == B._plot_diagnostic_note(diagnostics(fit).summary)
    @test_throws ArgumentError B._wright_plot_data(fit)
    @test_throws ArgumentError B._wright_plot_data(fit; options..., max_levels = 18)
    @test B._wright_plot_data(fit; options..., max_levels = 19).histogram.counts == h.counts
    @test B._wright_plot_data(fit; options..., facets = :person, include_thresholds = false,
        max_levels = 1).n_individual_positions == 0
    reversed = B._wright_plot_data(fit; options..., facets = (:item, :person, :rater), include_thresholds = false)
    @test reversed.groups == [:item, :person, :rater]
    @test reversed.histogram == h
    automatic = B._wright_plot_data(fit; person_display = :histogram).histogram
    @test length(automatic.counts) == 9
    @test sum(automatic.counts) == 80
    @test first(automatic.edges) == minimum(r.position_median for r in people)
    @test last(automatic.edges) == maximum(r.position_median for r in people)
    for bins in (0, -1, true, 2.5, :auto, [], [0.], [0., 0.], [1., 0.],
            [-Inf, Inf], [-3., NaN, 3.], [-3., 0., 2.], [-2., 0., 3.], [false, true], ["a", "b"])
        @test_throws ArgumentError B._wright_plot_data(fit; person_display = :histogram, bins)
    end
    for bad in ((; person_display = :unknown), (; person_display = missing), (; bins = 3),
            (; person_display = :histogram, facets = :rater))
        @test_throws ArgumentError B._wright_plot_data(fit; bad...)
    end
    @test_throws ArgumentError B._wright_person_histogram([1.], [-floatmax(Float64), floatmax(Float64)])
    Random.seed!(211); expected = rand(); Random.seed!(211)
    B._wright_plot_data(fit; options...)
    @test rand() == expected
    mktempdir() do dir
        path = joinpath(dir, "fit.jls"); save_fit_cache(path, fit)
        before = sha256(read(path))
        @test isequal(B._wright_plot_data(load_fit_cache(path); options...), data)
        @test sha256(read(path)) == before
    end
    for thresholds in (:rating_scale, :partial_credit), categories in (0:1, 0:3)
        anchors = [(; block = :rater, level = "R2", value = 0.75, type = :hard),
            (; block = :item, level = "I2", value = 1.25, type = :hard)]
        f = wright_histogram_fit(; npeople = 3, thresholds, categories, anchors)
        old = B._wright_plot_data(f)
        new = B._wright_plot_data(f; person_display = :histogram)
        @test old.person_display === :intervals && old.histogram === nothing
        @test isequal(new.rows, old.rows)
        @test new.n_draws == old.n_draws
        @test count(r -> r.is_fixed && r.facet !== :threshold, new.rows) == 2
        @test all(r -> !r.is_fixed || r.position_lower == r.position_upper == r.fixed_value, new.rows)
    end
end
end
