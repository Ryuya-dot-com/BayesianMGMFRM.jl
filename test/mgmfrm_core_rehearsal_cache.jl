using Test
include(joinpath(@__DIR__,"..","scripts","run_mgmfrm_core_rehearsal.jl"))
const R=MGMFRMCoreRehearsal
const E=R.E
const P=R.P
root=only(ARGS)
old="results/workflows/20260921-core-generator-01"
directory=joinpath(old,"fixed")
files=(;generation="generation.json",raw_truth="raw-truth.json",truth="truth.json",observed="observed.json")
hashes=map(f -> P.digest(joinpath(directory,f)),files)
g=P.readjson(joinpath(directory,"generation.json"))
plan=E.evaluation_plan(["historical","absent"];mode=:fixed,backend=:advancedhmc,generator_sha256=g.generator_sha256)
input=E.bind_panel(plan,"historical";directory,hashes)
preflight=E.input_preflight(plan,input)
j=(;job_id="historical-cache-test",plan,input,split=nothing,fold=nothing,fit_seed=9220101,
    preflight,spec=P.specification(input.observed;require_all_categories=false))
cache=joinpath(old,"pilot-01","advancedhmc","fit.jls")
reference=(;path=cache,sha256=P.digest(cache),seed=9220101)

@testset "Saved-fit scoring persists real recovery and explicit unresolved precision" begin
    r=R.score_job(j,reference,joinpath(root,"scored"))
    @test r.status===:prepared && r.primary_precision_passed
    restored=E.deserialize(joinpath(root,"scored","attempt.jls"))
    @test restored==r && E.check_seal(restored)==restored
    R.worker_result(joinpath(old,"pilot-01","contract.json"),j,:score,joinpath(root,"scored"),r)
    envelope=P.readjson(joinpath(root,"scored","worker-result.json"))
    @test envelope.status=="prepared" && envelope.phase=="score"
    @test envelope.job_id==j.job_id && envelope.dataset_id==input.id && envelope.fit_seed==reference.seed
    @test envelope.artifact_sha256[Symbol("attempt.jls")]==P.digest(joinpath(root,"scored","attempt.jls"))
    @test envelope.artifact_sha256[Symbol("attempt.json")]==P.digest(joinpath(root,"scored","attempt.json")) && !envelope.scientific_acceptance
    @test_throws ErrorException R.worker_result(joinpath(old,"pilot-01","contract.json"),j,:score,joinpath(root,"scored"),r)
    original=P.readjson("results/workflows/20260921-core-fit-binding-01/recovery-replay.json")
    @test length(r.rows)==159
    for (a,b) in zip(r.rows,original.rows)
        @test a.parameter==b.parameter && a.estimate≈b.estimate && a.lower≈b.lower && a.upper≈b.upper
    end
    good=E.summarize_recovery(plan,[restored];parameter="b[I1]")
    @test good.planned==2 && good.usable==1 && good.unresolved==1
    # A hand-edited precision-warning fixture checks persistence/denominators;
    # it is not a newly observed defect in the qualified historical fit.
    rows=[a.parameter=="b[I1]" ? merge(a,(;local_precision_passed=false)) : a for a in r.rows]
    warning=E.seal(merge(Base.structdiff(r,(;content_hash=nothing)),
        (;rows,status=:mcse_unavailable,primary_precision_passed=false)))
    R.save_attempt(joinpath(root,"precision-warning-fixture"),warning)
    kept=E.deserialize(joinpath(root,"precision-warning-fixture","attempt.jls"))
    unresolved=E.summarize_recovery(plan,[kept];parameter="b[I1]")
    @test kept.status===:mcse_unavailable && kept.reference==reference && length(kept.rows)==159
    @test unresolved.planned==2 && unresolved.usable==0 && unresolved.unresolved==2
    @test unresolved.all_attempt_coverage_bounds==(0.,1.)
    @test unresolved.reasons[:mcse_unavailable]==1 && unresolved.reasons[:missing_attempt]==1
    @test_throws ErrorException R.save_attempt(joinpath(root,"scored"),r)
    @test P.digest(cache)==reference.sha256
    P.writejson(joinpath(root,"tests.json"),(;tests_passed=true,scope=:historical_fixed_fit_and_artificial_warning,
        good,unresolved,new_sampler_runs=0,cv_refits=0,formal_recovery_replications=0,scientific_acceptance=false))
end
