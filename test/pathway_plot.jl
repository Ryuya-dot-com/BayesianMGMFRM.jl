module PathwayPlotChecks
using BayesianMGMFRM, Test, Random, Statistics
const B = BayesianMGMFRM
include("fixtures/reporting_fit.jl")
const anchors = [(; block = :rater, level = 2, value = 0.75, type = :hard),
    (; block = :item, level = 2, value = 1.25, type = :hard)]
const fit = reporting_fit(:mfrm; ndraws = 20, chains = 2, amplitude = 0.35, anchors)
const options = (; facets = (:item, :person, :rater), metric = :outfit, interval = .99)
@testset "Pathway numerical contract without fitting" begin
    @test :plot_pathway ∉ names(B)
    if Base.get_extension(B, :BayesianMGMFRMCairoMakieExt) === nothing
        err = try B.plot_pathway(fit); catch e; e; end
        @test err isa ArgumentError
        @test occursin("using CairoMakie", sprint(showerror, err))
    end
    for thresholds in (:rating_scale, :partial_credit), metric in (:infit, :outfit)
        f = reporting_fit(:mfrm; thresholds, ndraws = 20, chains = 2, amplitude = 0.5)
        original = copy(f.draws)
        data = B._pathway_plot_data(f; options..., metric)
        @test data.groups == options.facets
        @test data.n_draws == 40
        @test length(data.rows) == 6
        # Direct finite-category moments, then each draw's ratio/mean, then quantiles.
        # This independently checks the aggregation and uncertainty shown on the fit axis.
        probabilities = predictive_probabilities(f)
        scores = f.design.spec.data.category_levels
        observed = f.design.spec.data.score
        for row in data.rows
            group = getproperty(f.design.spec.data, row.facet)
            selected = findall(==(row.level_index), group)
            values = map(axes(probabilities, 1)) do d
                means = [sum(scores[k] * probabilities[d,o,k] for k in eachindex(scores)) for o in selected]
                vars = [sum((scores[k]-means[j])^2 * probabilities[d,o,k] for k in eachindex(scores)) for (j,o) in enumerate(selected)]
                residual2 = (observed[selected] .- means).^2
                metric === :infit ? sum(residual2)/sum(vars) : mean(residual2 ./ vars)
            end
            @test row.n_observations == length(selected)
            @test row.fit_median ≈ median(values)
            @test row.fit_lower ≈ quantile(values, .005)
            @test row.fit_upper ≈ quantile(values, .995)
            position = only(r for r in wright_map_data(f; include_thresholds=false, interval=.99)
                if r.facet === row.facet && r.level_index == row.level_index)
            @test row.logit_median == position.position_median
            @test row.logit_lower ≈ position.position_lower
            @test row.logit_upper ≈ position.position_upper
            @test row.is_fixed == position.is_fixed
        end
        @test f.draws == original
    end
    data = B._pathway_plot_data(fit; options...)
    @test count(r -> r.is_fixed, data.rows) == 2
    @test all(r -> r.logit_lower == r.logit_upper, filter(r -> r.is_fixed, data.rows))
    @test any(r -> r.fit_lower < r.fit_upper, filter(r -> r.is_fixed, data.rows))
    @test length(B._pathway_plot_data(fit; facets=:item).rows) == 2
    @test occursin("MCMC", data.diagnostic)
    Random.seed!(913); expected = rand(); Random.seed!(913)
    B._pathway_plot_data(fit)
    @test rand() == expected
    for kwargs in ((; metric=:zstd), (; metric=:all), (; metric=missing), (; interval=1),
            (; interval=NaN), (; facets=()), (; facets=(:item,:item)), (; facets=:threshold),
            (; max_levels=0), (; max_levels=true), (; max_levels=5), (; min_n=0),
            (; min_n=true), (; min_n=100))
        @test_throws ArgumentError B._pathway_plot_data(fit; kwargs...)
    end
    invalid = deepcopy(fit); invalid.draws[1,1] = Inf
    @test_throws ArgumentError B._pathway_plot_data(invalid)
    invalid = deepcopy(fit); invalid.chain_ids[1] = 3
    @test_throws ArgumentError B._pathway_plot_data(invalid)
    extreme = deepcopy(fit); extreme.draws[:,fit.design.blocks[:person]] .= 1000
    flagged = B._pathway_plot_data(extreme)
    @test all(r -> r.fit_flag === :tiny_predictive_variance, flagged.rows)
    @test all(r -> isfinite(r.fit_median), flagged.rows)
    binary = FacetData((; person=["P one","P one","P two","P two"],
        item=["I A","I B","I A","I B"], rater=["R A","R B","R B","R A"], score=[0,1,1,0]);
        person=:person,item=:item,rater=:rater,score=:score)
    binary_fit = reporting_fit(:mfrm; data=binary)
    binary_rows = B._pathway_plot_data(binary_fit; facets=(:rater,:item)).rows
    @test getproperty.(binary_rows,:level)==["R A","R B","I A","I B"]
    @test all(r->r.n_observations==2,binary_rows)
    @test all(r->r.fit_flag===:ok,binary_rows)
    for family in (:gmfrm,:mgmfrm)
        @test_throws ArgumentError B.plot_pathway(reporting_fit(family))
    end
    @test_throws ArgumentError B.plot_pathway((; model=:multidimensional))
    @test_throws ArgumentError B._save_mfrm_fixed_q_report_bundle("unused-pathway", (;); figures=(pathway=(;),))
    mktempdir() do dir
        path = joinpath(dir,"fit.jls"); save_fit_cache(path,fit)
        @test isequal(B._pathway_plot_data(load_fit_cache(path); options...),data)
    end
end
end
