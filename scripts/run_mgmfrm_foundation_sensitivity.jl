module MGMFRMFoundationSensitivityRun
using BayesianMGMFRM, JSON3, Dates
include("mgmfrm_foundation_sensitivity.jl")
const S=MGMFRMFoundationSensitivity
const B=BayesianMGMFRM
const F=S.F

function run(plan_path,id,output)
    plan=JSON3.read(read(plan_path,String))
    attempt=only(filter(r->r.id==id,plan.attempts))
    repo=dirname(@__DIR__)
    for (path,hash) in pairs(plan.source_sha256)
        F.digest(joinpath(repo,String(path)))==hash || error("Frozen source changed: $path")
    end
    input=joinpath(repo,attempt.input)
    F.digest(input)==attempt.input_sha256 || error("Input hash mismatch")
    F.digest(joinpath(repo,plan.roster))==plan.roster_sha256 || error("Roster hash mismatch")
    p=F.prepare(input)
    fixed=p.x.schema=="mgmfrm.foundation_fixed_facet_input.v1"
    if fixed
        plan.scope=="engineering_fixed_facet_rehearsal" && plan.evaluation_credit==0 &&
            plan.execution_allowed===true && attempt.panel==p.x.condition &&
            plan.person_seed==p.x.person_seed && plan.score_seed==p.x.score_seed ||
            error("Fixed-facet attempt/input scope mismatch")
    end
    for (key,value) in pairs(plan.controls)
        expected=getproperty(F.CONTROLS,Symbol(key))
        (expected isa Symbol ? String(expected)==value : expected==value) ||
            error("Unsupported control override: $key")
    end
    prior=B.Experimental.NormalizedMGMFRMPrior(;prior_model=:exchangeable,
        merge(F.SCALES,(;log_discrimination_sd=Float64(attempt.log_discrimination_sd)))...)
    target=B._normalized_mgmfrm_target(p.spec,prior)
    B._mgmfrm_normalized_prior_identity(target)==attempt.target_identity || error("Target mismatch")
    ispath(output) && error("Never replace a started attempt")
    mkpath(output)
    writejson(name,x)=B._write_json_record(joinpath(output,name),x)
    controls=merge(F.CONTROLS,(;seed=Int(attempt.seed)))
    writejson("started.json",(;id,plan_sha256=F.digest(plan_path),attempt,
        created_utc=string(now(UTC)),julia_version=string(VERSION),prior=B._mgmfrm_normalized_prior_record(target),controls,
        scope=Symbol(plan.scope),scientific_acceptance=false))
    starts=NamedTuple[];counts=zeros(Int,4)
    observer=e->begin
        if e.phase===:sampling_start
            push!(starts,(;chain=e.chain,raw=copy(e.initial_raw),sampling=copy(e.initial_sampling)))
            println(now(UTC)," ",id," chain ",e.chain," start");flush(stdout)
        elseif e.phase===:transition
            counts[e.chain]+=1
            if counts[e.chain]%500==0
                println(now(UTC)," ",id," chain ",e.chain," transition ",counts[e.chain]);flush(stdout)
            end
        elseif e.phase===:sampling_end
            println(now(UTC)," ",id," chain ",e.chain," end");flush(stdout)
        end
    end
    phase=:reference
    try
        reference=F.check_reference(target,p.x)
        phase=:sampling
        elapsed=@elapsed fit=B.Experimental.fit(p.spec;prior,
            sampling_coordinates=:orthogonal_person_mean_item_offset,
            controls...,record_warmup=true,_sampling_observer=observer)
        samples=joinpath(output,"samples.jls")
        B._save_serialized_record(samples,fit.record)
        writejson("execution.json",(;elapsed_seconds=elapsed,starts,counts,reference,
            samples_sha256=F.digest(samples),target_identity=fit.record.target_identity,
            prior=fit.record.prior,controls=fit.record.run.controls,
            retained_leapfrog_steps=sum(r.n_steps for r in fit.record.run.sampler_stats)))
        phase=:review
        roster=String.(JSON3.read(read(joinpath(repo,plan.roster),String)))
        core=S.C.review(input,samples,joinpath(output,"core"),roster;fitting_prior=prior)
        extra=S.extra_review(input,samples,joinpath(output,"core","review.json"),joinpath(output,"extra.json"))
        all(F.digest(joinpath(repo,String(path)))==hash for (path,hash) in pairs(plan.source_sha256)) ||
            error("Source changed during execution")
        F.digest(input)==attempt.input_sha256 || error("Input changed during execution")
        writejson("completion.json",(;completed=true,qualified=core.qualified,
            primary_quantities_qualified=extra.primary_quantities_qualified,
            maximum_rss_bytes=Sys.maxrss(),scientific_acceptance=false))
    catch err
        writejson("failure.json",(;phase,error=sprint(showerror,err),starts,counts,retry=false,
            maximum_rss_bytes=Sys.maxrss(),scientific_acceptance=false))
        rethrow()
    end
end
end

if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==3 || error("usage: run_mgmfrm_foundation_sensitivity.jl PLAN ATTEMPT_ID NEW_OUTPUT")
    MGMFRMFoundationSensitivityRun.run(ARGS...)
end
