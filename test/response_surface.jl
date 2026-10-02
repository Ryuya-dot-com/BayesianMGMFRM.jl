module ResponseSurfaceChecks
using Test, Statistics, BayesianMGMFRM, LinearAlgebra
const B = BayesianMGMFRM
include("fixtures/reporting_fit.jl")

const three_data = FacetData((; person=repeat(1:3; inner=6),
    item=repeat(repeat(1:3; inner=2),3), rater=repeat(1:2,9), score=repeat(0:2,6));
    person=:person, item=:item, rater=:rater, score=:score)
const fits = Dict(
    :pure => reporting_fit(:mgmfrm; chains=2, ndraws=20, dimension_labels=["Expression", "Technique"]),
    :mixed => reporting_fit(:mgmfrm; chains=2, ndraws=20, q_matrix=Bool[1 1; 0 1],
        dimension_labels=["Expression", "Technique"]),
    :three => reporting_fit(:mgmfrm; chains=2, ndraws=20, dimensions=3, data=three_data,
        q_matrix=Bool[1 1 0; 0 1 1; 0 0 1], dimension_labels=["A", "B", "C"]))

@testset "Conditional item response surfaces without fitting" begin
    @test :item_response_surface ∉ names(B)
    @test :plot_response_surface ∉ names(B)
    for (kind, fit) in fits
        fixed = kind === :three ? Dict("C" => .4) : Dict()
        options = (; item="1", rater="1", x=[-1.2, .3, 2.1], y=[-.9, .8],
            fixed_abilities=fixed, interval=.8, category=nothing)
        raw_before, direct_before = copy(fit.draws), copy(fit.direct_draws)
        surface = B.item_response_surface(fit; options...)
        @test surface.n_draws == surface.total_draws == 40
        @test size(surface.mean) == (3, 2)
        @test surface.interval_width ≈ surface.upper-surface.lower
        @test surface.diagnostic == B._plot_diagnostic_note(fit.diagnostic_surface.summary)
        @test surface.diagnostic_flag == fit.diagnostic_surface.summary.flag
        @test surface.diagnostic_flag !== :ok
        @test surface.dimension_labels == Tuple(fit.design.spec.dimension_labels[1:2])
        @test surface.active_dimensions == (true, kind !== :pure)
        categories = [B.item_response_surface(fit; options..., category=k) for k in 0:2]
        all_categories = B.item_response_surface(fit; options..., category=:all)
        @test size(all_categories.mean) == (3, 2, 3)
        @test all_categories.category_levels == [0,1,2]
        for k in 1:3, field in (:mean, :lower, :upper, :interval_width)
            @test getproperty(all_categories,field)[:,:,k] ≈ getproperty(categories[k],field)
        end
        @test dropdims(sum(all_categories.mean;dims=3);dims=3) ≈ ones(3,2)
        @test sum(s.mean for s in categories) ≈ ones(3, 2)
        @test sum(k*categories[k+1].mean for k in 0:2) ≈ surface.mean
        @test all(s -> all(0 .<= s.lower .<= s.upper .<= 1), categories)
        @test all(0 .<= surface.mean .<= 2)
        @test all(diff(surface.mean; dims=1) .> 0)
        @test kind === :pure ? surface.mean[:,1] == surface.mean[:,2] : all(diff(surface.mean; dims=2) .> 0)
        # Match the actual observation-level model kernel after assigning the
        # hypothetical ability vector to a copy of the observed person's row.
        row = findfirst(i -> fit.design.spec.data.item[i]==1 && fit.design.spec.data.rater[i]==1,
                        1:fit.design.spec.data.n)
        person = fit.design.spec.data.person[row]
        D = fit.design.spec.dimensions
        person_columns = fit.design.blocks[:person][(person-1)*D+1:person*D]
        loading_indices = B._mgmfrm_source_loading_index_matrix(fit.design)
        reference, probabilities = zeros(40, 3), zeros(3)
        for (j,y) in enumerate(surface.y), (i,x) in enumerate(surface.x)
            for sample in 1:40
                direct = copy(fit.direct_draws[sample,:])
                direct[person_columns] = D==2 ? [x,y] : [x,y,.4]
                B._mgmfrm_category_probabilities!(probabilities, fit.design,
                    loading_indices, direct, row)
                reference[sample,:] = probabilities
            end
            expected = reference * [0,1,2]
            @test surface.mean[i,j] ≈ mean(expected)
            @test surface.lower[i,j] ≈ quantile(expected,.1)
            @test surface.upper[i,j] ≈ quantile(expected,.9)
            for k in 1:3
                @test categories[k].mean[i,j] ≈ mean(reference[:,k])
                @test categories[k].lower[i,j] ≈ quantile(reference[:,k],.1)
                @test categories[k].upper[i,j] ≈ quantile(reference[:,k],.9)
            end
        end
        swapped = B.item_response_surface(fit; options..., dimensions=(2,1), x=options.y, y=options.x)
        @test swapped.mean ≈ transpose(surface.mean)
        @test swapped.lower ≈ transpose(surface.lower)
        named = B.item_response_surface(fit; options..., dimensions=surface.dimension_labels)
        @test named.mean == surface.mean
        single = B.item_response_surface(fit; options..., draw_indices=[3])
        @test single.lower == single.upper == single.mean
        @test single.draw_indices == [3]
        @test fit.draws == raw_before && fit.direct_draws == direct_before
        mktempdir() do directory
            path = joinpath(directory,"surface-fit.jls")
            save_fit_cache(path,fit)
            @test isequal(B.item_response_surface(load_fit_cache(path); options...), surface)
        end
    end
    pure = fits[:pure]
    request = (;item="1",rater="1",category=nothing,x=[-1.,1.],y=[-1.,1.])
    for invalid in ((;item="missing"), (;rater="missing"), (;category=3), (;category=true), (;category=:unknown),
            (;dimensions=(1,1)), (;dimensions=(1,4)), (;dimensions=(true,2)),
            (;dimensions=("missing",2)), (;dimensions=(1,)), (;x=[1.]),
            (;x=[1.,1.]), (;y=[1.,-1.]), (;x=[NaN,1.]), (;x=[false,true]),
            (;interval=1.), (;interval=NaN), (;draw_indices=Int[]),
            (;draw_indices=[0]), (;draw_indices=[true]), (;draw_indices=[1.0]),
            (;draw_indices=[1,1]), (;fixed_abilities=Dict(1=>0.)))
        @test_throws ArgumentError B.item_response_surface(pure; request...,invalid...)
    end
    @test_throws ArgumentError B.item_response_surface(fits[:three]; request...)
    @test_throws ArgumentError B.item_response_surface(fits[:three]; request...,fixed_abilities=Dict(3=>Inf))
    @test_throws ArgumentError B.item_response_surface(fits[:three]; request...,fixed_abilities=Dict(3=>0.,"C"=>1.))
    # A hand-written three-category PCM oracle checks the 1.7 multiplier,
    # item/rater selection, reconstructed last rater, and draw-wise averaging.
    wide = reporting_fit(:mgmfrm; chains=2, ndraws=20, amplitude=.8, q_matrix=Bool[1 1;0 1])
    design = wide.design
    loadings = B._mgmfrm_source_loading_index_matrix(design)
    function oracle(params, item, rater, x, y; levels=[0,1,2])
        a = [loadings[item,d]==0 ? 0. : params[loadings[item,d]] for d in 1:2]
        eta = dot(a,[x,y])-params[design.blocks[:item][item]]-params[design.blocks[:rater][rater]]
        scale = 1.7params[design.blocks[:rater_consistency][rater]]
        step = params[design.blocks[:item_steps][item]]
        logits = [0., scale*(eta-step), 2scale*eta]
        probabilities = exp.(logits .- maximum(logits))
        dot(levels, probabilities/sum(probabilities))
    end
    for item in 1:2, rater in 1:2
        surface = B.item_response_surface(wide; item, rater,category=nothing,x=[-.7,.2],y=[.4,1.1])
        expected = [oracle(p,item,rater,-.7,.4) for p in eachrow(wide.direct_draws)]
        @test surface.mean[1,1] ≈ mean(expected)
        @test surface.lower[1,1] ≈ quantile(expected,.05)
        @test abs(surface.mean[1,1]-oracle(vec(mean(wide.direct_draws;dims=1)),item,rater,-.7,.4)) > 1e-5
    end
    low = B.item_response_surface(fits[:three]; item=2,rater=1,category=nothing,fixed_abilities=Dict(3=>-.8),x=[-1.,1.],y=[-1.,1.])
    high = B.item_response_surface(fits[:three]; item=2,rater=1,category=nothing,fixed_abilities=Dict(3=>.8),x=[-1.,1.],y=[-1.,1.])
    @test all(high.mean .> low.mean)
    shifted_data = FacetData((;person=[1,1,1,2,2,2],item=[1,1,2,1,2,2],rater=[1,2,1,1,2,1],score=[1,2,3,2,1,3]);
        person=:person,item=:item,rater=:rater,score=:score)
    shifted = reporting_fit(:mgmfrm;data=shifted_data,chains=2,ndraws=20)
    all_shifted = B.item_response_surface(shifted; item=1,rater=1,x=[-1.,1.],y=[-1.,1.])
    @test all_shifted.category === :all
    @test all_shifted.category_levels == [1,2,3]
    @test all_shifted.mean[:,:,1] ≈ B.item_response_surface(shifted;request...,category=1).mean
    a = B.item_response_surface(pure; request...)
    b = B.item_response_surface(shifted; request...)
    @test b.mean ≈ a.mean .+ 1
    @test B.item_response_surface(shifted;request...,category=1).mean ≈ B.item_response_surface(pure;request...,category=0).mean
    if Base.get_extension(B,:BayesianMGMFRMCairoMakieExt) === nothing
        @test_throws ArgumentError B.plot_response_surface(pure; item="1",rater="1")
    end
end
end
