module MGMFRMFoundationPredictionRun
using BayesianMGMFRM, JSON3, Dates, Serialization, Statistics, LinearAlgebra
include("mgmfrm_foundation_prediction.jl")
const C=MGMFRMFoundationPrediction
const B=C.B
const E=C.E
const F=C.F
const REPO=dirname(@__DIR__)
readjson(path)=JSON3.read(read(path,String))
function save(path,x)
    ispath(path) && error("Never overwrite evidence: $path")
    B._write_json_record(path,x)
end

function cpu_seconds()
    # This local study uses macOS's process CPU clock (SDK _time.h, clock ID 12).
    Sys.isapple() || error("This study's process CPU clock requires macOS")
    return ccall(:clock_gettime_nsec_np,UInt64,(Cuint,),12)/1e9
end

"""Original diagnostic roster, with its observed likelihood restricted to training rows."""
function geometry(full_target, target, record, checked, roster)
    B._mgmfrm_normalized_prior_identity(target)==record.target_identity || error("Review target differs from saved fit")
    record.run.checked.rhat_threshold==1.01 && record.run.checked.ess_threshold==400. &&
        record.run.split_chains_requested && record.run.actual_split || error("Diagnostic policy mismatch")
    raw=record.run.draws;direct=checked.diagnostics.direct_values.direct_draws
    base=E.sbc_quantities(full_target.base,raw;parameter_names=checked.raw_parameter_names)
    last(base.names)=="observed_log_likelihood" || error("Likelihood coordinate changed")
    base.values[:,end]=[B._source_fixture_loglikelihood(target.base,collect(r)) for r in eachrow(raw)]
    all(i->isapprox(base.values[i,end]+B.logprior(target,collect(raw[i,:])),record.run.logdensities[i];
        atol=1e-8,rtol=1e-10),(1,2000,4000)) || error("Training likelihood/prior does not reconstruct saved density")
    loc=B._mgmfrm_location_coordinates(target.base.design,direct)
    selected=findall(r->r.block!==:item_location,loc)
    names=[base.names;[loc[i].parameter for i in selected]]
    names==roster && length(names)==150 || error("Original diagnostic roster changed")
    values=hcat(base.values,[loc[i].values for i in selected]...)
    metrics(x,n)=B._candidate_mcmc_diagnostic_rows(x,n,4;
        split_chains=true,rhat_threshold=1.01,ess_threshold=400.)
    diagnostic=B.diagnostics(B.Experimental.NormalizedMGMFRMFit(record;expected_identity=record.target_identity))
    focal=metrics(values,names)
    location=metrics(hcat(getproperty.(loc,:values)...),getproperty.(loc,:parameter))
    moments=F.R.location_moments(target.base,raw)
    residuals=metrics(moments.values,moments.names)
    extra=C.S.extra_quantities(target,raw)
    extra_names=[extra.names;["a[I$i]" for i in 1:5]]
    extra_values=hcat(extra.values,exp.(raw[:,110:114]))
    extra_diagnostic=metrics(extra_values,extra_names)
    precision=B.posterior_mcse(extra_values;chains=4,parameter_names=extra_names,probabilities=(.05,.95))
    finite(x)=x isa Real && isfinite(x) && x>=0
    rows=map(eachindex(extra_names)) do j
        m=precision[j];sd=std(extra_values[:,j]);lo,hi=m.quantiles;width=hi.estimate-lo.estimate
        good=sd>0 && finite(m.mean_mcse) && m.mean_mcse/sd<=.05 && width>0 &&
            finite(lo.mcse) && finite(hi.mcse) && max(lo.mcse,hi.mcse)/width<=.05
        (;parameter=extra_names[j],diagnostic=extra_diagnostic[j],precision=m,posterior_sd=sd,
            local_precision_passed=good)
    end
    original_gate=diagnostic.summary.passed && all(r->r.flag===:ok,residuals) &&
        all(r->!ismissing(r.e_bfmi) && isfinite(r.e_bfmi) && r.e_bfmi>=.3,record.run.sampler_rows)
    core_qualified=original_gate && all(r->r.flag===:ok,vcat(focal,location))
    qualified=core_qualified && all(r->r.diagnostic.flag===:ok && r.local_precision_passed,rows)
    return (;qualified,core_qualified,original_gate,diagnostic=diagnostic.summary,focal,location,residuals,
        extra=rows,sampler_rows=record.run.sampler_rows,
        likelihood_scope=:training_only,scientific_acceptance=false)
end

function prepare(root)
    draft=JSON3.read(read(joinpath(root,"design.json"),String),Dict{String,Any})
    draft["schema"]=="mgmfrm.foundation_prediction_study.v1" || error("Wrong study schema")
    ispath(joinpath(root,"plan.json")) && error("Plan already frozen")
    attempts=NamedTuple[]
    mkpath(joinpath(root,"bindings"))
    for block in 1:draft["blocks"], condition in ("R0","R1")
        input=relpath(joinpath(root,"inputs","B$(lpad(block,3,'0'))-$condition.json"),REPO)
        hash=F.digest(joinpath(REPO,input));split_seed=draft["split_seed_base"]+block
        panel=C.prepare(joinpath(REPO,input),hash;split_seed)
        panel.p.x.assessment_id==draft["study_id"] && panel.p.x.block==block &&
            panel.p.x.condition==condition || error("Input/study identity mismatch")
        for (suffix,sd) in (("025",.25),("050",.5),("100",1.)),fold in 1:5
            id="B$(lpad(block,3,'0'))-$condition-$suffix-F$fold"
            context=C.fold_context(panel,fold,sd)
            binding=joinpath(root,"bindings","$id.json");save(binding,context.binding)
            push!(attempts,(;id,block,condition,sd,fold,input,input_sha256=hash,split_seed,
                person_seed=panel.p.x.person_seed,score_seed=panel.p.x.score_seed,
                seed=draft["fit_seed_base"]+length(attempts)+1,
                target_identity=context.binding.target_identity,binding_identity=context.binding.content_hash,
                binding=relpath(binding,REPO),binding_sha256=F.digest(binding)))
        end
    end
    length(attempts)==30draft["blocks"] && length(unique(a.target_identity for a in attempts))==length(attempts) ||
        error("Repeated or missing training target")
    files=[joinpath(d,f) for folder in ("src","scripts","test") for (d,_,fs) in walkdir(joinpath(REPO,folder))
        for f in fs if any(ext->endswith(f,ext),(".jl",".stan",".py"))]
    append!(files,[joinpath(REPO,p) for p in ("Project.toml","Manifest.toml")])
    roster="results/workflows/20260926-normalized-core-review-01/roster.json"
    merge!(draft,Dict("attempts"=>attempts,"controls"=>Base.structdiff(F.CONTROLS,(;seed=nothing)),
        "roster"=>roster,"roster_sha256"=>F.digest(joinpath(REPO,roster)),
        "design_sha256"=>F.digest(joinpath(root,"design.json")),
        "source_sha256"=>Dict(relpath(p,REPO)=>F.digest(p) for p in files),
        "julia_binary"=>joinpath(Sys.BINDIR,Base.julia_exename()),"julia_version"=>string(VERSION),
        "created_utc"=>string(now(UTC))))
    save(joinpath(root,"plan.json"),draft)
    println("Frozen ",length(attempts)," training targets; posterior fits 0");flush(stdout)
end

function check_plan(root)
    plan=readjson(joinpath(root,"plan.json"))
    plan.schema=="mgmfrm.foundation_prediction_study.v1" && plan.execution_allowed===true &&
        plan.scientific_acceptance===false && plan.stage in ("pilot","main") || error("Wrong execution scope")
    F.digest(joinpath(root,"design.json"))==plan.design_sha256 || error("Design changed")
    Threads.nthreads()==1 && BLAS.get_num_threads()==1 || error("One Julia/BLAS thread required")
    for (p,h) in pairs(plan.source_sha256)
        F.digest(joinpath(REPO,String(p)))==h || error("Frozen source changed: $p")
    end
    F.digest(joinpath(REPO,plan.roster))==plan.roster_sha256 || error("Roster changed")
    for (k,v) in pairs(plan.controls)
        expected=getproperty(F.CONTROLS,Symbol(k))
        (expected isa Symbol ? String(expected)==v : expected==v) || error("Control override")
    end
    return plan
end

function attempt(root,plan,a)
    output=joinpath(root,"attempts",a.id)
    ispath(output) && error("Never rerun a started attempt: $(a.id)")
    panel=C.prepare(joinpath(REPO,a.input),a.input_sha256;split_seed=Int(a.split_seed))
    panel.p.x.assessment_id==plan.study_id && panel.p.x.block==a.block &&
        panel.p.x.condition==a.condition && panel.p.x.person_seed==a.person_seed &&
        panel.p.x.score_seed==a.score_seed || error("Input provenance mismatch")
    context=C.fold_context(panel,Int(a.fold),Float64(a.sd))
    context.binding.content_hash==a.binding_identity && context.binding.target_identity==a.target_identity &&
        F.digest(joinpath(REPO,a.binding))==a.binding_sha256 || error("Training binding changed")
    mkpath(output)
    writejson(n,x)=save(joinpath(output,n),x)
    plan_hash=F.digest(joinpath(root,"plan.json"));start=time_ns();cpu_start=cpu_seconds()
    writejson("started.json",(;id=a.id,attempt=a,plan_sha256=plan_hash,created_utc=string(now(UTC)),
        process_id=getpid(),stage=plan.stage,scientific_acceptance=false))
    counts=zeros(Int,4);starts=NamedTuple[]
    observer=e->begin
        if e.phase===:sampling_start
            push!(starts,(;chain=e.chain,raw=copy(e.initial_raw),sampling=copy(e.initial_sampling)))
        elseif e.phase===:transition
            counts[e.chain]+=1
            counts[e.chain]%500==0 && (println(now(UTC)," ",a.id," chain ",e.chain," transition ",counts[e.chain]);flush(stdout))
        end
    end
    phase=:sampling
    try
        cpu_fit=cpu_seconds()
        measured=@timed B.Experimental.fit(context.spec;prior=context.prior,
            sampling_coordinates=:orthogonal_person_mean_item_offset,
            merge(F.CONTROLS,(;seed=Int(a.seed)))...,record_warmup=true,_sampling_observer=observer)
        fit_cpu_seconds=cpu_seconds()-cpu_fit;fit=measured.value
        phase=:persistence
        counts==fill(2000,4) || error("Incomplete transition observation")
        samples=joinpath(output,"samples.jls");B._save_serialized_record(samples,fit.record)
        writejson("execution.json",(;fit_seconds=measured.time,fit_cpu_seconds,
            compile_seconds=measured.compile_time,gc_seconds=measured.gctime,allocated_bytes=measured.bytes,
            starts,counts,samples_sha256=F.digest(samples),target_identity=fit.record.target_identity,
            controls=fit.record.run.controls,retained_leapfrog_steps=sum(r.n_steps for r in fit.record.run.sampler_stats)))
        phase=:review
        record=open(deserialize,samples)
        checked=C.check_fit(context,record;seed=Int(a.seed))
        review=geometry(panel.p.target,context.target,record,checked,String.(readjson(joinpath(REPO,plan.roster))))
        writejson("review.json",(;review...,samples_sha256=F.digest(samples),binding_identity=a.binding_identity))
        primary_qualified=false
        if review.qualified
            phase=:scoring
            score=C.score_draws(context,checked.diagnostics.direct_values.direct_draws;
                chain_ids=record.run.chain_ids,iterations=record.run.iterations)
            primary=first(score.monte_carlo_error.rows)
            primary_qualified=primary.status===:first_order_candidate && primary.diagnostic.flag===:ok
            writejson("score.json",(;score...,samples_sha256=F.digest(samples),binding_identity=a.binding_identity,
                primary_qualified,scientific_acceptance=false))
        end
        check_plan(root)
        F.digest(joinpath(root,"plan.json"))==plan_hash && F.digest(joinpath(REPO,a.input))==a.input_sha256 || error("Inputs changed")
        writejson("completion.json",(;completed=true,geometry_qualified=review.qualified,primary_qualified,
            plan_sha256=plan_hash,binding_identity=a.binding_identity,
            attempt_seconds=(time_ns()-start)/1e9,attempt_cpu_seconds=cpu_seconds()-cpu_start,
            maximum_rss_bytes=Sys.maxrss(),
            output_sha256=Dict(n=>F.digest(joinpath(output,n)) for n in
                ("execution.json","review.json","score.json") if isfile(joinpath(output,n))),
            scientific_acceptance=false))
        println(now(UTC)," completed ",a.id,"; geometry=",review.qualified,"; loss=",primary_qualified);flush(stdout)
    catch err
        writejson("failure.json",(;phase,error=sprint(showerror,err),counts,starts,retry=false,
            plan_sha256=plan_hash,binding_identity=a.binding_identity,
            attempt_seconds=(time_ns()-start)/1e9,attempt_cpu_seconds=cpu_seconds()-cpu_start))
        phase===:sampling || rethrow()
    end
end

function worker(root,worker)
    worker in (1,2) || error("Worker must be 1 or 2")
    plan=check_plan(root);hash=F.digest(joinpath(root,"plan.json"))
    for a in plan.attempts
        mod1(a.block,2)==worker || continue
        F.digest(joinpath(root,"plan.json"))==hash || error("Plan changed")
        attempt(root,plan,a)
        GC.gc()
    end
end
end

if abspath(PROGRAM_FILE)==@__FILE__
    if length(ARGS)==2 && ARGS[1]=="prepare"
        MGMFRMFoundationPredictionRun.prepare(abspath(ARGS[2]))
    elseif length(ARGS)==3 && ARGS[1]=="worker"
        MGMFRMFoundationPredictionRun.worker(abspath(ARGS[2]),parse(Int,ARGS[3]))
    else
        error("usage: run_mgmfrm_foundation_prediction.jl prepare ROOT | worker ROOT 1/2")
    end
end
