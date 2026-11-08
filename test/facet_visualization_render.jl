# Optional CairoMakie checks. All draws are deterministic artificial fixtures.
module FacetVisualizationRenderChecks
using Test, BayesianMGMFRM, CairoMakie
const B=BayesianMGMFRM
include("fixtures/reporting_fit.jl")
include("fixtures/wright_histogram_fit.jl")

function check(directory)
    @testset "Facet display render and numeric inputs" begin
        f=wright_histogram_fit(;npeople=6,thresholds=:partial_credit)
        data=B.wright_ridge_data(f;bandwidth=.08)
        note=IOBuffer()
        fig=B.plot_wright(f;kind=:ridge,bandwidth=.08,annotation_io=note)
        axes=filter(x->x isa Axis,fig.content)
        @test length(axes)==4
        @test all(ax->ax.xlabel[]=="Logit position",axes)
        @test all(ax->ax.finallimits[].origin[1]==axes[1].finallimits[].origin[1] &&
            ax.finallimits[].widths[1]==axes[1].finallimits[].widths[1],axes)
        text=String(take!(note))
        @test occursin(data.diagnostic,text)
        @test occursin("not a population distribution",text)
        write(joinpath(directory,"wright-ridge-note.txt"),"Artificial display fixture; not fitted posterior evidence.\n"*text)
        B._write_json_record(joinpath(directory,"wright-ridge.json"),data)
        for suffix in ("png","pdf","svg")
            path=joinpath(directory,"wright-ridge.$suffix");save(path,fig)
            @test filesize(path)>1000
        end
        bundle=joinpath(directory,"ridge-report")
        manifest=save_fit_report_bundle(bundle,f;
            figures=(wright=(kind=:ridge,bandwidth=.08),),
            include_artifact=false,include_loo=false,include_waic=false,
            include_calibration=false,include_category_functioning=false,
            include_rater_homogeneity=false,include_grouped_predictive=false,
            include_posterior_predictive=false)
        payload=B.JSON3.read(read(joinpath(bundle,"figures/wright.json"),String))
        @test payload.data.ridge.grid==data.ridge.grid
        @test payload.data.ridge.bandwidth==data.ridge.bandwidth
        @test length(payload.data.ridge.densities)==length(data.rows)
        @test load_fit_report_bundle(bundle;return_manifest=true)["schema"]==manifest.schema
        g=reporting_fit(:mgmfrm;chains=2,ndraws=20,amplitude=.15,q_matrix=Bool[1 1;0 1])
        options=(;item=1,rater=2,x=range(-2,2;length=21),y=range(-2,2;length=19))
        s=B.item_response_surface(g;options...)
        B._write_json_record(joinpath(directory,"surface.json"),s)
        for layout in (:panels,:heatmaps)
            note=IOBuffer()
            fig=B.plot_response_surface(g;options...,layout,annotation_io=note)
            axes3=filter(x->x isa Axis3,fig.content)
            axes2=filter(x->x isa Axis,fig.content)
            @test length(axes3)==(layout===:panels ? 3 : 0)
            @test length(axes2)==(layout===:panels ? 3 : 6)
            means=layout===:panels ? axes3 : axes2[1:2:end]
            widths=layout===:panels ? axes2 : axes2[2:2:end]
            for k in 1:3
                @test means[k].scene.plots[1][3][]≈s.mean[:,:,k]
                @test widths[k].scene.plots[1][3][]≈s.interval_width[:,:,k]
                @test Tuple(means[k].scene.plots[1].colorrange[])==(0.,1.)
                @test widths[k].scene.plots[1].colorrange[]==widths[1].scene.plots[1].colorrange[]
            end
            text=String(take!(note))
            @test occursin(s.diagnostic,text) && occursin("not MCSE",text)
            write(joinpath(directory,"surface-$layout-note.txt"),"Artificial display fixture; not fitted posterior evidence.\n"*text)
            for suffix in ("png","pdf","svg")
                path=joinpath(directory,"surface-$layout.$suffix");save(path,fig)
                @test filesize(path)>1000
            end
        end
        pure=reporting_fit(:mgmfrm;chains=2,ndraws=20)
        fig=B.plot_response_surface(pure;item=1,rater=1,layout=:panels,x=[-1.,1.],y=[-1.,1.],annotation_io=devnull)
        @test all(ax->occursin("Q excludes θ₂",ax.title[]),filter(x->x isa Axis3,fig.content))
        @test_throws ArgumentError B.plot_response_surface(g;options...,layout=:invalid)
    end
end
end
