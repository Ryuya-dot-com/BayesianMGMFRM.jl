module MGMFRMFoundationPredictionContinue
include("run_mgmfrm_foundation_prediction.jl")
using Dates, Serialization, JSON3
const W=MGMFRMFoundationPredictionRun
const C=W.C
const F=W.F

function check(root,continuation)
    p=W.check_plan(root);c=W.readjson(joinpath(continuation,"plan.json"))
    c.schema=="mgmfrm.foundation_prediction_continuation.v1" || error("Wrong continuation")
    abspath(joinpath(W.REPO,c.pilot_root))==root || error("Wrong pilot root")
    c.pilot_plan_sha256==F.digest(joinpath(root,"plan.json")) || error("Pilot changed")
    for (path,hash) in pairs(c.source_sha256)
        F.digest(joinpath(W.REPO,String(path)))==hash || error("Continuation source changed: $path")
    end
    return p,c
end

function review_saved(root,p,a,output)
    ispath(output) && error("New restoration output required")
    original=joinpath(root,"attempts",a.id)
    started=W.readjson(joinpath(original,"started.json"))
    started.attempt==a && started.plan_sha256==F.digest(joinpath(root,"plan.json")) || error("Started record changed")
    execution=W.readjson(joinpath(original,"execution.json"))
    samples=joinpath(original,"samples.jls");hash=F.digest(samples)
    execution.samples_sha256==hash && execution.counts==fill(2000,4) &&
        execution.target_identity==a.target_identity || error("Saved execution incomplete or changed")
    panel=C.prepare(joinpath(W.REPO,a.input),a.input_sha256;split_seed=Int(a.split_seed))
    panel.p.x.assessment_id==p.study_id && panel.p.x.block==a.block &&
        panel.p.x.condition==a.condition && panel.p.x.person_seed==a.person_seed &&
        panel.p.x.score_seed==a.score_seed || error("Input provenance mismatch")
    context=C.fold_context(panel,Int(a.fold),Float64(a.sd))
    context.binding.content_hash==a.binding_identity && context.binding.target_identity==a.target_identity &&
        F.digest(joinpath(W.REPO,a.binding))==a.binding_sha256 || error("Training binding changed")
    record=open(deserialize,samples)
    checked=C.check_fit(context,record;seed=Int(a.seed))
    review=W.geometry(panel.p.target,context.target,record,checked,String.(W.readjson(joinpath(W.REPO,p.roster))))
    mkpath(output)
    W.save(joinpath(output,"review.json"),(;review...,samples_sha256=hash,binding_identity=a.binding_identity))
    primary_qualified=false
    if review.qualified
        score=C.score_draws(context,checked.diagnostics.direct_values.direct_draws;
            chain_ids=record.run.chain_ids,iterations=record.run.iterations)
        primary=first(score.monte_carlo_error.rows)
        primary_qualified=primary.status===:first_order_candidate && primary.diagnostic.flag===:ok
        W.save(joinpath(output,"score.json"),(;score...,samples_sha256=hash,binding_identity=a.binding_identity,
            primary_qualified,scientific_acceptance=false))
    end
    F.digest(samples)==hash || error("Saved samples changed")
    return (;geometry_qualified=review.qualified,primary_qualified)
end

function restore(root,continuation)
    p,c=check(root,continuation);continuation_hash=F.digest(joinpath(continuation,"plan.json"))
    replay=only(a for a in p.attempts if a.id==c.replay_id)
    replay_out=joinpath(continuation,"replay")
    reviewed=review_saved(root,p,replay,replay_out)
    original=joinpath(root,"attempts",replay.id)
    old=W.readjson(joinpath(original,"completion.json"))
    reviewed.geometry_qualified==old.geometry_qualified && reviewed.primary_qualified==old.primary_qualified ||
        error("Replay qualification differs")
    names=reviewed.geometry_qualified ? ("review.json","score.json") : ("review.json",)
    for name in names
        # Exact serialized equality checks every diagnostic, probability and loss.
        F.digest(joinpath(replay_out,name))==F.digest(joinpath(original,name)) || error("Replay differs: $name")
    end
    W.save(joinpath(continuation,"replay-verification.json"),(;status=:passed,id=replay.id,
        posterior_fits=0,comparison=:byte_identical_review_and_score,
        outputs=Dict(n=>F.digest(joinpath(replay_out,n)) for n in names),
        continuation_plan_sha256=continuation_hash))
    println(now(UTC)," saved-fit replay passed");flush(stdout)
    a=only(a for a in p.attempts if a.id==c.recovery_id)
    output=joinpath(continuation,"restored");original=joinpath(root,"attempts",a.id)
    sort(readdir(original))==["execution.json","samples.jls","started.json"] || error("Unexpected recovery state")
    start=time_ns();cpu=W.cpu_seconds()
    result=review_saved(root,p,a,output)
    check(root,continuation)
    F.digest(joinpath(continuation,"plan.json"))==continuation_hash || error("Continuation changed")
    hashes=Dict(n=>F.digest(joinpath(output,n)) for n in ("review.json","score.json") if isfile(joinpath(output,n)))
    hashes["execution.json"]=F.digest(joinpath(original,"execution.json"))
    W.save(joinpath(output,"completion.json"),(;completed=true,result...,
        plan_sha256=F.digest(joinpath(root,"plan.json")),binding_identity=a.binding_identity,
        attempt_seconds=nothing,attempt_cpu_seconds=nothing,maximum_rss_bytes=nothing,
        output_sha256=hashes,scientific_acceptance=false,
        recovery=(;created_utc=string(now(UTC)),posterior_fits=0,
            continuation_plan_sha256=continuation_hash,recovery_seconds=(time_ns()-start)/1e9,
            recovery_cpu_seconds=W.cpu_seconds()-cpu,recovery_process_maximum_rss_bytes=Sys.maxrss(),
            reason=:disk_full_during_original_review_save,
            timing_note="Original total wall/CPU and peak RSS unavailable; fit timing remains in execution.json.")))
    println(now(UTC)," restored ",a.id,"; geometry=",result.geometry_qualified,
        "; loss=",result.primary_qualified);flush(stdout)
end

function worker(root,continuation,number)
    number in (1,2) || error("Worker must be 1 or 2")
    p,c=check(root,continuation);hash=F.digest(joinpath(continuation,"plan.json"))
    ids=String.(c.unstarted_ids)
    length(unique(ids))==length(ids) && all(id->any(a->a.id==id,p.attempts),ids) || error("Invalid remaining IDs")
    for a in p.attempts
        a.id in ids && mod1(a.block,2)==number || continue
        F.digest(joinpath(continuation,"plan.json"))==hash || error("Continuation changed")
        W.attempt(root,p,a)
        GC.gc()
    end
end
end

if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS) in (3,4) || error("usage: ROOT CONTINUATION restore | ROOT CONTINUATION worker 1/2")
    root,continuation=abspath.(ARGS[1:2])
    if ARGS[3]=="restore" && length(ARGS)==3
        MGMFRMFoundationPredictionContinue.restore(root,continuation)
    elseif ARGS[3]=="worker" && length(ARGS)==4
        MGMFRMFoundationPredictionContinue.worker(root,continuation,parse(Int,ARGS[4]))
    else
        error("Invalid continuation command")
    end
end
