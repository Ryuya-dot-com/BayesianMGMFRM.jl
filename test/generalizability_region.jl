module GeneralizabilityRegionTests
using BayesianMGMFRM, LinearAlgebra, Statistics, Test
const G=BayesianMGMFRM.Generalizability
BLAS.set_num_threads(1)
@testset "Balanced mean squares and kernel trace identities" begin
    for nested in (false,true)
        ids=[(p,r,t) for p in 1:4 for r in 1:3 for t in 1:2]
        table=(person=first.(ids),rater=getindex.(ids,2),task=last.(ids),
            a=[p+.3r-.5t+sin(p*r*t) for (p,r,t) in ids],
            b=[.2p-r+.2t+cos(2p*r*t) for (p,r,t) in ids])
        t=G.model(table;person=:person,facets=(rater=:rater,task=:task),scores=(:a,:b),
            nesting=nested ? (rater=:task,) : (;),prior=:none)
        d=G.likelihood_data(t);m=G.anova_moments(t,d);K=length(t.components);N=length(ids)
        @test sum(m.df)==N-1
        # Independent dense projection, avoiding the group-mean algorithm.
        projections=Matrix{Float64}[]
        for (j,b) in enumerate(t.components)
            Z=Float64.(b.index .== (1:length(b.levels))')
            H=Z*((Z'Z)\Z').-1/N
            for k in 1:j-1
                issubset(t.components[k].factors,b.factors) && (H-=projections[k])
            end
            push!(projections,H)
            @test H*H≈H atol=1e-12
            @test tr(H)≈m.df[j]
            @test reshape(m.mean_squares[j],2,2)≈t.scores'H*t.scores/m.df[j] atol=1e-12
            for (k,c) in enumerate(t.components)
                A=Float64.(c.index .== c.index')
                expected=issubset(b.factors,c.factors) ? N/m.levels[k] : 0.
                @test tr(H*A)/m.df[j]≈expected atol=1e-12
            end
        end
        record=(;anova_moments=m,components=[(;b.name,b.factors) for b in t.components],scores=[:a,:b],n_observations=N)
        @test G.check_anova_moments(record)==m
        region=G.mean_square_region(record,[.7,.3],.95)
        @test region.status===:mean_square_region
        values=G.region_design_intervals(region,record.components,(rater=3,task=2),zeros(6))
        @test all(s->s.status===:mean_square_region,values)
        @test 0<=values[1].lower<=values[1].upper<=1
        @test 0<=values[2].lower<=values[2].upper<=1
        @test values[4].upper>=values[3].upper>0
        @test region.max_residual<=1e-9
        incomplete=(; (k=>v[2:end] for (k,v) in pairs(table))...)
        bad=G.model(incomplete;person=:person,facets=(rater=:rater,task=:task),scores=(:a,:b),nesting=nested ? (rater=:task,) : (;),prior=:none)
        @test G.anova_moments(bad,G.likelihood_data(bad))===nothing
    end
end
@testset "Bounded region vertices and empty sets" begin
    # z=(person,rater,residual), with lambda=(z1+z3,z2+z3,z3).
    B=[1. 0 1;0 1 1;0 0 1]
    r=G.region_vertices(B,[2.,3.,1.],[4.,5.,2.])
    @test size(r.vertices,2)>0
    @test minimum(r.vertices[1,:])≈0
    @test maximum(r.vertices[1,:])≈3
    @test minimum(r.vertices[2,:])≈1
    @test maximum(r.vertices[2,:])≈4
    @test isempty(G.region_vertices(B,[.1,3.,2.],[1.,5.,3.]).vertices)
end
end
