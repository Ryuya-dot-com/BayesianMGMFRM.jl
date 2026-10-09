using Test, Statistics, Random
include(joinpath(@__DIR__,"../scripts/mgmfrm_core_evaluation.jl"))
include(joinpath(@__DIR__,"../scripts/mgmfrm_core_recovery_review.jl"))
const E,R=MGMFRMCoreEvaluation,MGMFRMCoreRecoveryReview
const P=E.P
observed=(;candidate_id="independent_2d_raw_primary_01",category_levels=collect(1:4),
    observations=[(;person,item="I$i",rater="R$r",score=mod1(p+i+r,4))
        for (p,person) in enumerate(P.PERSONS) for i in 1:5 for r in 1:5])
target=P.target(P.specification(observed))

@testset "Recovery quantities retain IDs, facets and location invariances" begin
    raw=.2randn(MersenneTwister(93601),64,128)
    q=R.quantities(target,raw)
    original=E.recovery_quantities(target,raw[1:3,:])
    @test length(q.names)==length(unique(q.names))==273
    @test q.names[1:159]==original.names
    @test q.draws[1:3,1:159] ≈ original.draws atol=1e-12
    shifted=copy(raw);shift=[.4,-.3]
    shifted[:,1:100] .+= permutedims(repeat(shift,50))
    for i in 1:5
        shifted[:,104+i] .+= exp.(raw[:,109+i])*shift[i<=2 ? 1 : 2]
    end
    moved=R.quantities(target,shifted)
    for block in (:centered_person,:relative_item,:person_contrast)
        ids=findall(r->r.block===block,q.roster)
        @test q.draws[:,ids] ≈ moved.draws[:,ids] atol=1e-12
    end
    for d in 1:2
        ids=findall(r->r.block===:centered_person && r.dimension==d,q.roster)
        @test all(abs.(vec(sum(q.draws[:,ids];dims=2))) .< 1e-12)
        i=findfirst(==("theta[P1,D$d]-theta[P2,D$d]"),q.names)
        p1=findfirst(==("P1"),P.PERSONS);p2=findfirst(==("P2"),P.PERSONS)
        @test q.draws[:,i] ≈ raw[:,2(p1-1)+d]-raw[:,2(p2-1)+d]
    end
    truth=R.quantities(target,reshape(.1sin.(1:128),1,:))
    review=R.review(q,truth;chains=4)
    @test length(review.rows)==273
    @test review.rows[60].intervals[1].lower ≈ quantile(raw[:,1],.05)
    @test review.rows[60].intervals[1].upper ≈ quantile(raw[:,1],.95)
    groups=R.panel_rows(review.rows)
    c=only(filter(r->r.block===:centered_person && r.dimension==1,groups))
    @test c.n_parameters==50 && c.signed_error_structurally_zero
    @test abs(c.mean_signed_error)<1e-12
    @test c.rmse>0 && c.mae>0
    for block in (:severity,:step)
        constrained=only(filter(r->r.block===block,groups))
        @test constrained.signed_error_structurally_zero && abs(constrained.mean_signed_error)<1e-12
        @test constrained.rmse>0
    end
    unavailable=[merge(r,(;intervals=map(x->merge(x,(;boundary_sensitivity=missing)),r.intervals))) for r in review.rows]
    @test all(x->x.boundary_mcse_available==0 && ismissing(x.near_endpoint_fraction),
        Iterators.flatten(r.intervals for r in R.panel_rows(unavailable)))
    @test length(R.person_error_mcse(q,truth))==4
    moments=R.location_moments(target,raw)
    @test size(moments.values)==(64,9)
    @test moments.values[:,7] ≈ moments.conditional_output[:,7].^2 .- 1
    @test_throws ArgumentError R.quantities(target,zeros(0,128))
    @test_throws ArgumentError R.quantities(target,zeros(5,127))
    invalid=copy(raw);invalid[1,1]=NaN
    @test_throws ArgumentError R.quantities(target,invalid)
    @test_throws ArgumentError R.review(q,q)
end
