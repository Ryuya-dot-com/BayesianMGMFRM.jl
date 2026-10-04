# Optional CairoMakie check; deterministic reporting objects, no MCMC.
using Test, BayesianMGMFRM, CairoMakie
const B = BayesianMGMFRM
include("fixtures/reporting_fit.jl")
const surface_render_fits = Dict(
    :pure => reporting_fit(:mgmfrm; chains=2, ndraws=20, dimension_labels=["Expression", "Technique"]),
    :mixed => reporting_fit(:mgmfrm; chains=2, ndraws=20, q_matrix=Bool[1 1;0 1],
        dimension_labels=["Expression", "Technique"]))

function check_surface_render(directory)
    @testset "Editable 3D response surfaces" begin
        for (name, category) in ((:pure,nothing), (:mixed,nothing), (:mixed,1), (:mixed,:all))
            fit = surface_render_fits[name]
            options = (;item=1,rater=2,x=range(-2,2;length=21),y=range(-2,2;length=17),category)
            data = B.item_response_surface(fit; options...)
            figure = B.plot_response_surface(fit; options...,azimuth=1.2pi,elevation=.3)
            @test figure isa Figure
            ax = only(filter(x -> x isa Axis3,figure.content))
            heats = filter(x -> x isa Axis,figure.content)
            @test ax.xlabel[] == "θ₁" && ax.ylabel[] == "θ₂"
            @test ax.zlabel[] == data.quantity_label
            @test ax.azimuth[] ≈ 1.2pi && ax.elevation[] ≈ .3
            extension = Base.get_extension(B,:BayesianMGMFRMCairoMakieExt)
            colors = extension._response_category_colors(length(data.category_levels))
            if category === :all
                @test length(ax.scene.plots) == length(heats) == 3
                for k in 1:3
                    @test ax.scene.plots[k][3][] ≈ data.mean[:,:,k]
                    @test ax.scene.plots[k].color[] == colors[k]
                    @test heats[k].scene.plots[1][3][] ≈ data.interval_width[:,:,k]
                    @test heats[k].title[] == "Rating $(data.category_levels[k])"
                end
                @test all(h -> h.scene.plots[1].colorrange[] == heats[1].scene.plots[1].colorrange[], heats)
            else
                @test ax.scene.plots[1][3][] ≈ data.mean
                @test only(heats).scene.plots[1][3][] ≈ data.interval_width
                category !== nothing && @test ax.scene.plots[1].color[] == colors[findfirst(==(category),data.category_levels)]
            end
            @test count(x -> x isa Legend,figure.content) == (category === nothing ? 0 : 1)
            if category !== nothing
                legend = only(filter(x -> x isa Legend,figure.content))
                entries = only(legend.entrygroups[])[2]
                levels = category === :all ? data.category_levels : [category]
                @test [entry.attributes.label[] for entry in entries] == ["Rating $k" for k in levels]
            end
            labels = [string(x.text[]) for x in figure.content if x isa Label]
            @test any(label -> occursin(data.diagnostic,label),labels)
            @test any(label -> occursin("Rater 2",label),labels)
            name === :pure && @test any(label -> occursin("flat along that axis",label),labels)
            ax.zlabel = "Edited expected rating"
            @test ax.zlabel[] == "Edited expected rating"
            ax.zlabel = data.quantity_label
            heading = first(filter(x -> x isa Label,figure.content))
            heading.text[] = "Synthetic illustration (no fit)\n" * heading.text[]
            for suffix in ("png","svg")
                file = joinpath(directory,"$name-$(something(category,"mean")).$suffix")
                save(file,figure)
                @test filesize(file) > 1000
            end
        end
        reversed = B.plot_response_surface(surface_render_fits[:mixed]; item=1,rater=1,
            dimensions=(2,1),x=[-1.,1.],y=[-1.,1.])
        ax = only(filter(x -> x isa Axis3,reversed.content))
        @test ax.xlabel[] == "θ₂" && ax.ylabel[] == "θ₁"
        @test length(ax.scene.plots) == 3 # default is all categories
        extension = Base.get_extension(B,:BayesianMGMFRMCairoMakieExt)
        @test length(unique(extension._response_category_colors(9))) == 9
    end
end

if isempty(ARGS)
    mktempdir(check_surface_render)
else
    mkpath(only(ARGS))
    check_surface_render(only(ARGS))
end
