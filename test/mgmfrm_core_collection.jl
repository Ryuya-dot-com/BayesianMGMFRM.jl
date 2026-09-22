using Test
include(joinpath(@__DIR__,"..","scripts","run_mgmfrm_core_rehearsal.jl"))
const R=MGMFRMCoreRehearsal
const E=R.E
const P=R.P
root,output=ARGS
mkpath(output)
contract=joinpath(root,"plan","bound-plan-02.json")

@testset "Observed stops and precision warnings keep the complete study denominator" begin
    for (label,statuses,reasons) in [
        ("collected-stop-01",["fit_error";fill("missing_attempt",11)],("fit_error","missing_attempt")),
        ("collected-precision-01",vcat(["mcse_unavailable","fit_error"],fill("missing_attempt",10)),("mcse_unavailable","fit_error"))]
        v=P.readjson(joinpath(root,label,"worker","collection.json"))
        @test v.execution_scope=="owned_python_fixture"
        @test v.planned_jobs==12 && v.independent_dataset_pairs==1
        @test !v.scientific_acceptance && !v.replication_claims && !v.numerical_precision_accepted
        @test v.new_sampler_runs==0
        @test [r.study_status for r in v.operational]==statuses
        for (r,reason) in zip(v.recovery,reasons)
            @test r.quantity_roster_available && length(r.summaries)==159
            @test all(s -> s.result.planned==1 && s.result.usable==0 && s.result.unresolved==1,r.summaries)
            @test all(s -> getproperty(s.result.reasons,Symbol(reason))==1,r.summaries)
            @test all(s -> s.result.conditional_bias===nothing && s.result.bias_mcse===nothing,r.summaries)
            @test all(s -> s.result.all_attempt_coverage_bounds==[0.0,1.0],r.summaries)
        end
        for c in v.cv
            r=c.result.result
            @test r.planned_folds==5 && r.usable_folds==0 && length(r.ledger)==5
            @test r.score===nothing && r.status=="incomplete"
            @test all(f -> f.status=="missing_attempt",r.ledger)
        end
        @test length(v.paired)==4
        @test all(p -> p.planned==1 && p.unresolved==1 && p.descriptive_complete==0,v.paired)
        @test all(p -> p.descriptive_replication_mcse===nothing && p.combined_first_order_mcse===nothing,v.paired)
    end
end

@testset "Collection rejects changed IDs, artifact bytes and fit references" begin
    source=joinpath(root,"collected-precision-01","ledger.json")
    for mode in (:id,:hash,:fit_reference)
        ledger=P.JSON3.read(read(source,String),Dict{String,Any})
        if mode===:id
            ledger["rows"][1]["job_id"]="wrong-id"
        elseif mode===:hash
            ledger["rows"][1]["attempt"]["sha256"]=repeat("0",64)
        else
            ref=ledger["rows"][1]["attempt"]
            a=E.deserialize(IOBuffer(E.checked_bytes(ref["path"],ref["sha256"])))
            payload=Base.structdiff(a,(;content_hash=a.content_hash))
            altered=E.seal(merge(payload,(;reference=merge(a.reference,(;seed=a.reference.seed+1)))))
            directory=joinpath(output,"different-fit-reference")
            R.save_attempt(directory,altered)
            archive=joinpath(directory,"attempt.jls")
            ledger["rows"][1]["attempt"]=Dict("path"=>archive,"sha256"=>P.digest(archive))
        end
        path=joinpath(output,string(mode)*".json");P.writejson(path,ledger)
        destination=joinpath(output,"forbidden-"*string(mode))
        @test_throws ArgumentError R.collect_ledger(contract,path,destination)
        @test !ispath(destination)
    end
end
P.writejson(joinpath(output,"tests.json"),(;tests_passed=true,new_sampler_runs=0,
    scope="Owned Python workers and hand-constructed precision warning; no fitted estimates",
    scientific_acceptance=false))
