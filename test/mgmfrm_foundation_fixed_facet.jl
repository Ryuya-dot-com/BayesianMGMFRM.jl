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
        assessment=JSON3.read(original,Dict{String,Any})
        merge!(assessment,Dict("schema"=>"mgmfrm.foundation_fixed_facet_assessment_input.v1",
            "scope"=>"prospective_fixed_facet_assessment","evaluation_credit"=>1,
            "assessment_id"=>"check-01","block"=>1))
        write(file,JSON3.write(assessment))
        @test B._mgmfrm_normalized_prior_identity(F.prepare(file).target)==identities[5]
        for (key,value) in (("block",true),("block",0),("evaluation_credit",true),
                            ("assessment_id","../bad"),("scientific_acceptance",true))
            bad=copy(assessment);bad[key]=value;write(file,JSON3.write(bad))
            @test_throws ErrorException F.prepare(file)
        end
        write(file,JSON3.write(assessment))
        roster=joinpath(dir,"roster.json");write(roster,"[]")
        attempt=Dict("id"=>"check","input"=>file,"input_sha256"=>F.digest(file),
            "panel"=>"R1","block"=>1,"person_seed"=>assessment["person_seed"],
            "score_seed"=>assessment["score_seed"])
        plan=Dict("schema"=>"mgmfrm.foundation_fixed_facet_assessment.v1",
            "scope"=>assessment["scope"],"execution_allowed"=>true,"evaluation_credit"=>1,
            "scientific_acceptance"=>false,"assessment_id"=>"check-01","blocks"=>1,
            "attempts"=>[attempt],"source_sha256"=>Dict(),"roster"=>roster,
            "roster_sha256"=>F.digest(roster),"controls"=>Dict("warmup"=>2))
        planpath=joinpath(dir,"plan.json");destination=joinpath(dir,"never-created")
        # Valid binding reaches the forbidden control; malformed binding fails earlier.
        write(planpath,JSON3.write(plan))
        @test_throws "Unsupported control override" W.run(planpath,"check",destination)
        for (key,value) in (("panel","R0"),("block",2),("person_seed",0),("score_seed",0))
            bad=deepcopy(plan);bad["attempts"][1][key]=value
            write(planpath,JSON3.write(bad))
            @test_throws "Assessment attempt/input scope mismatch" W.run(planpath,"check",destination)
        end
        @test !ispath(destination)
    end
end
