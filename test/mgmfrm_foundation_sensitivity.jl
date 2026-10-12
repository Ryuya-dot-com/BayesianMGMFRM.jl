using Test, BayesianMGMFRM, Random
include(joinpath(@__DIR__,"../scripts/mgmfrm_foundation_sensitivity.jl"))
const S=MGMFRMFoundationSensitivity
const B=BayesianMGMFRM

@testset "Loading-only sensitivity target and centered quantity identities" begin
    cells=[(p,i,r) for p in sort(["P$i" for i in 1:50]) for i in 1:5 for r in 1:5]
    data=FacetData((;person=first.(cells),item=["I$(x[2])" for x in cells],
        rater=["R$(x[3])" for x in cells],score=[mod1(i,4) for i in eachindex(cells)]);
        person=:person,item=:item,rater=:rater,score=:score,category_levels=1:4)
    spec=mfrm_spec(data;family=:mgmfrm,dimensions=2,thresholds=:partial_credit,q_matrix=S.F.Q)
    prior(sd)=B.Experimental.NormalizedMGMFRMPrior(;prior_model=:exchangeable,
        merge(S.F.SCALES,(;log_discrimination_sd=sd))...)
    base=B._normalized_mgmfrm_target(spec,prior(.5))
    raw=.2randn(MersenneTwister(26092750),24,128)
    q=S.extra_quantities(base,raw)
    @test length(q.names)==length(unique(q.names))==111
    @test q.values[:,end-3] ≈ raw[:,110]-raw[:,111]
    for d in 1:2
        ids=findall(n->startswith(n,"centered_person[") && endswith(n,"dim=$d]"),q.names)
        @test length(ids)==50
        @test maximum(abs.(sum(q.values[:,ids];dims=2)))<1e-12
    end
    for sd in (.25,1.)
        alt=B._normalized_mgmfrm_target(spec,prior(sd))
        @test B._mgmfrm_normalized_prior_identity(alt)!=B._mgmfrm_normalized_prior_identity(base)
        @test Base.structdiff(B._mgmfrm_normalized_prior_record(alt).scales,(;log_discrimination_sd=nothing)) ==
            Base.structdiff(B._mgmfrm_normalized_prior_record(base).scales,(;log_discrimination_sd=nothing))
        for x in eachrow(raw)
            expected=-5log(sd/.5)-sum(abs2,x[110:114])/2*(1/sd^2-1/.5^2)
            @test B.LogDensityProblems.logdensity(alt,x)-B.LogDensityProblems.logdensity(base,x) ≈ expected atol=1e-10
        end
    end
end
