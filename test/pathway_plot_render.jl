module PathwayPlotRenderChecks
using BayesianMGMFRM, CairoMakie, Test
const B = BayesianMGMFRM
const P = parentmodule(@__MODULE__).PathwayPlotChecks
axes(fig) = filter(x -> x isa Axis, fig.content)
const directory = get(ENV,"BAYESIANMGMFRM_PATHWAY_OUTPUT",mktempdir())
const report_options = (; include_artifact=false, include_loo=false, include_waic=false,
    include_calibration=false, include_category_functioning=false,
    include_rater_homogeneity=false, include_grouped_predictive=false,
    include_posterior_predictive=false)
@testset "Pathway rendering, cache and report bundle" begin
    mkpath(directory)
    io = IOBuffer(); fig = B.plot_pathway(P.fit; P.options..., annotation_io=io)
    note = String(take!(io)); data = B._pathway_plot_data(P.fit; P.options...)
    @test fig isa Figure
    @test isempty(filter(x -> x isa Label,fig.content))
    @test length(axes(fig)) == 3
    @test all(ax -> ax.finallimits[] == first(axes(fig)).finallimits[], axes(fig))
    for (facet,ax) in zip(data.groups,axes(fig))
        @test ax.xlabel[] == "Outfit mean square"
        rows = filter(r -> r.facet === facet,data.rows)
        @test all(x -> x isa CairoMakie.Makie.Text, last(ax.scene.plots,length(rows)))
        points = filter(x -> x isa Scatter,ax.scene.plots)
        @test length(points) == length(rows)
        for (point,row) in zip(points,rows)
            @test point[1][][1][1] ≈ row.fit_median
            @test point[1][][1][2] ≈ row.logit_median
            @test point.marker[] == CairoMakie.Makie.to_spritemarker(row.is_fixed ? :diamond : :circle)
        end
    end
    @test occursin("99.0%",note) && occursin("not a joint",note)
    @test occursin(data.diagnostic,note)
    @test occursin("horizontal fit intervals",note)
    embedded = B.plot_pathway(P.fit; P.options..., annotation_io=nothing)
    labels = [String(x.text[]) for x in embedded.content if x isa Label]
    @test note == labels[end-1] * "\n\nNote. " * labels[end] * "\n"
    @test_throws ArgumentError B.plot_pathway(P.fit;annotation_io=IOBuffer(;read=true,write=false))
    @test length(axes(B.plot_pathway(P.fit;facets=:rater,annotation_io=IOBuffer()))) == 1
    extreme = deepcopy(P.fit); extreme.draws[:,P.fit.design.blocks[:person]] .= 1000
    flagged_note = IOBuffer(); B.plot_pathway(extreme; annotation_io=flagged_note)
    @test occursin("tiny_predictive_variance",String(take!(flagged_note)))
    for suffix in ("pdf","svg","png")
        path = joinpath(directory,"pathway.$suffix");save(path,fig)
        @test filesize(path)>1000
    end
    bundle = joinpath(directory,"report")
    opts = (; facets=P.options.facets,metric=:outfit)
    manifest = save_fit_report_bundle(bundle,P.fit;figures=(pathway=opts,),
        posterior_lower=.005,posterior_upper=.995,report_options...)
    payload = B.JSON3.read(read(joinpath(bundle,"figures/pathway.json"),String),Dict{String,Any})
    @test payload["kind"] == "pathway"
    @test payload["annotation_text"] == note
    @test payload["data"]["n_draws"] == 40
    @test count(r -> r["is_fixed"],payload["data"]["rows"]) == 2
    @test occursin("*Note.* "*payload["caption"],read(joinpath(bundle,"fit_report.md"),String))
    @test load_fit_report_bundle(bundle;return_manifest=true)["schema"] == manifest.schema
    save_fit_cache(joinpath(directory,"fit.jls"),P.fit)
    save_fit_report_bundle(joinpath(directory,"replay"),load_fit_cache(joinpath(directory,"fit.jls"));
        figures=(pathway=opts,),posterior_lower=.005,posterior_upper=.995,report_options...)
    replay = B.JSON3.read(read(joinpath(directory,"replay/figures/pathway.json"),String),Dict{String,Any})
    @test payload["data"] == replay["data"]
    original_manifest=read(joinpath(bundle,"manifest.json"))
    @test_throws ArgumentError save_fit_report_bundle(bundle,P.fit; overwrite=true,
        figures=(pathway=(min_n=100,),),report_options...)
    @test read(joinpath(bundle,"manifest.json"))==original_manifest
    @test_throws ArgumentError save_fit_report_bundle(joinpath(directory,"bad-interval"),P.fit;
        figures=(pathway=(;),),posterior_lower=.1,report_options...)
    @test !ispath(joinpath(directory,"bad-interval"))
    @test_throws ArgumentError B._fit_report_figure_options((pathway=(interval=.9,),))
    for family in (:gmfrm,:mgmfrm)
        @test_throws ArgumentError save_fit_report_bundle(joinpath(directory,"bad-$family"),
            P.reporting_fit(family);figures=(pathway=(;),),report_options...)
    end
    for suffix in ("pdf","svg","json")
        path=joinpath(bundle,"figures/pathway.$suffix"); original=read(path)
        write(path,vcat(original,UInt8[0x20]))
        @test_throws ArgumentError load_fit_report_bundle(bundle)
        write(path,original)
    end
end
end
