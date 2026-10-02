# Standalone input/target check: pass a directory produced by
# scripts/mgmfrm_foundation_fixed_facet_input.py. Never launches a sampler.
using Test, JSON3, BayesianMGMFRM
include(joinpath(@__DIR__,"../scripts/run_mgmfrm_foundation_sensitivity.jl"))
const W=MGMFRMFoundationSensitivityRun
const F=W.F
const B=BayesianMGMFRM
length(ARGS)==1 || error("usage: mgmfrm_foundation_fixed_facet.jl INPUT_DIRECTORY")

@testset "Fixed-facet input and normalized target binding" begin
    prepared=[F.prepare(joinpath(ARGS[1],"$c.json")) for c in ("R0","R1")]
    @test prepared[1].x.raw_truth[1:109]==prepared[2].x.raw_truth[1:109]
    @test prepared[1].x.raw_truth[112:128]==prepared[2].x.raw_truth[112:128]
    identities=String[]
    for p in prepared, sd in (.25,.5,1.)
        prior=B.Experimental.NormalizedMGMFRMPrior(;prior_model=:exchangeable,
            merge(F.SCALES,(;log_discrimination_sd=sd))...)
        target=B._normalized_mgmfrm_target(p.spec,prior)
        push!(identities,B._mgmfrm_normalized_prior_identity(target))
        F.check_reference(target,p.x)
    end
    @test length(unique(identities))==6
    original=read(joinpath(ARGS[1],"R1.json"),String)
    mktempdir() do dir
        file=joinpath(dir,"input.json")
        mutations=[x->(x["condition"]="R0"),x->(x["log_prior"]=0.),
            x->(x["candidate_id"]="raw"),x->(x["scope"]="evaluation"),
            x->(x["evaluation_credit"]=1),x->(x["raw_truth"][105]+=.1),
            x->reverse!(x["ordered_ids"]["person"]),
            x->(x["generator_sha256"]="wrong"),x->(x["scales"]["person_sd"]=2.)]
        for mutate in mutations
            payload=JSON3.read(original,Dict{String,Any});mutate(payload)
            write(file,JSON3.write(payload))
            @test_throws ErrorException F.prepare(file)
        end
        legacy=JSON3.read(original,Dict{String,Any})
        legacy["schema"]="mgmfrm.foundation_oracle_input.v1"
        write(file,JSON3.write(legacy))
        @test B._mgmfrm_normalized_prior_identity(F.prepare(file).target)==identities[5]
    end
end
