module MGMFRMCoreRehearsal

# The 12-slot proposal remains blocked. Preparation and trusted-cache scoring
# are sampler-free; the fitting entry requires a separate reviewed contract.
include(joinpath(@__DIR__,"mgmfrm_core_evaluation.jl"))
const E=MGMFRMCoreEvaluation
const P=E.P
const B=E.B

function checked_contract(path)
    c=P.readjson(path)
    c.schema=="core.paired_rehearsal.v1" && c.purpose=="execution_feasibility_only" &&
        c.backend=="advancedhmc" && c.ids==["pair-001"] && c.maximum_fits==12 ||
        throw(ArgumentError("Wrong rehearsal proposal"))
    abspath(c.directory)==dirname(abspath(path)) || throw(ArgumentError("Relocated contract"))
    bytes=E.checked_bytes(joinpath(c.directory,"proposal.json"),c.proposal_sha256)
    proposed=P.JSON3.read(bytes)
    all(k -> c[k]==proposed[k],keys(proposed)) || throw(ArgumentError("Bound plan changed from proposal"))
    for (name,h) in pairs(c.source_sha256)
        P.digest(joinpath(P.REPO,String(name)))==h || throw(ArgumentError("Changed source: $name"))
    end
    for k in keys(P.CONTROLS)
        expected=getproperty(P.CONTROLS,k)
        getproperty(c.controls,k)==(expected isa Symbol ? String(expected) : expected) ||
            throw(ArgumentError("Changed sampler controls"))
    end
    c.initial_raw==zeros(128) && c.prior=="implementation_reference" || throw(ArgumentError("Changed initialization/prior"))
    length(c.jobs)==12 && length(unique(j.job_id for j in c.jobs))==12 &&
        length(unique(j.fit_seed for j in c.jobs))==12 || throw(ArgumentError("Incomplete/duplicate jobs"))
    for condition in ("R0","R1")
        jobs=filter(j -> j.condition==condition,c.jobs)
        length(jobs)==6 && count(j -> j.fold===nothing,jobs)==1 &&
            sort([Int(j.fold) for j in jobs if j.fold!==nothing])==collect(1:5) ||
            throw(ArgumentError("Expected a full fit and all five folds per condition"))
    end
    reserved=[c.seeds.person,c.seeds.response,c.seeds.split]
    length(unique(reserved))==3 && all(c.jobs) do j
        j.dataset_id=="pair-001" && j.fit_seed isa Integer && !(j.fit_seed isa Bool) &&
        j.fit_seed>=0 && !(j.fit_seed in reserved) &&
        j.split_seed==(j.fold===nothing ? nothing : c.seeds.split) &&
        j.training_rows==(j.fold===nothing ? 1250 : 1000) && j.heldout_rows==(j.fold===nothing ? 0 : 250)
    end || throw(ArgumentError("Job seed/split/geometry mismatch"))
    return c
end

function prepare_job(c,id)
    j=only(filter(j -> j.job_id==id,c.jobs))
    plan=E.evaluation_plan(String.(c.ids);mode=:recovery,condition=String(j.condition),
        backend=:advancedhmc,generator_sha256=String(c.generator_sha256))
    entry=getproperty(c.inputs,Symbol(j.condition))
    hashes=(;generation=String(entry.hashes.generation),raw_truth=String(entry.hashes.raw_truth),
        truth=String(entry.hashes.truth),observed=String(entry.hashes.observed))
    input=E.bind_panel(plan,j.dataset_id;directory=String(entry.directory),hashes)
    input.generation.person_seed==c.seeds.person && input.generation.score_seed==c.seeds.response ||
        throw(ArgumentError("Generation seeds differ from proposal"))
    split=j.fold===nothing ? nothing : E.bind_folds(plan,input;seed=Int(j.split_seed))
    preflight=E.input_preflight(plan,input;split,fold=j.fold)
    spec=if preflight.passed
        full=P.specification(input.observed;require_all_categories=false)
        split===nothing ? full : B._refit_training_spec(full,
            B._loo_refit_training_data(full.data,preflight.training_rows))
    else
        nothing
    end
    return (;job_id=String(id),plan,input,split,fold=j.fold,fit_seed=Int(j.fit_seed),preflight,spec)
end

function prepare_all(path,output)
    c=checked_contract(path)
    jobs=[prepare_job(c,j.job_id) for j in c.jobs]
    rows=map(jobs) do j
        t=j.spec===nothing ? nothing : P.target(j.spec)
        (;j.job_id,j.fold,j.fit_seed,condition=j.plan.condition,id=j.input.id,
            plan_identity=j.plan.content_hash,input_identity=j.input.content_hash,
            split_identity=j.split===nothing ? nothing : j.split.content_hash,
            training_rows=j.preflight.training_rows,preflight=j.preflight,
            target_identity=t===nothing ? nothing : B.design_identity(t.design).value,
            raw_names=t===nothing ? nothing : t.blueprint.parameter_names,
            initial_logdensity=t===nothing ? nothing : B.LogDensityProblems.logdensity(t,zeros(128)))
    end
    P.writejson(output,(;contract_sha256=P.digest(path),rows,new_sampler_runs=0,
        execution_allowed=false,scientific_acceptance=false))
    return jobs
end

job_failure(j,status,detail)=j.fold===nothing ?
    E.failure(j.plan,j.input.id,status;detail,input=j.input) :
    E.fold_failure(j.plan,j.input,j.split,j.fold,status;detail)

function save_attempt(directory,attempt)
    E.check_seal(attempt)
    mkpath(directory)
    json=joinpath(directory,"attempt.json");archive=joinpath(directory,"attempt.jls")
    (ispath(json) || ispath(archive)) && error("Do not overwrite an attempt")
    P.writejson(json,attempt)
    E.serialize(archive,attempt)
    return attempt
end

function worker_result(path,j,phase,directory,value)
    cached=phase===:fit && hasproperty(value,:path)
    files=cached ? ("fit.jls","fit-result.json") : ("attempt.json","attempt.jls")
    P.writejson(joinpath(directory,"worker-result.json"),(;job_id=j.job_id,dataset_id=j.input.id,
        condition=j.plan.condition,j.fold,j.fit_seed,phase,contract_sha256=P.digest(path),
        status=cached ? :fit_saved_not_yet_scored : value.status,
        artifact_sha256=Dict(n=>P.digest(joinpath(directory,n)) for n in files),scientific_acceptance=false))
end

"""Sampler-free collection of the controller's complete immutable roster.
Changed evidence fails closed; unknown termination stays a missing study slot.
"""
function collect_ledger(path,ledger_path,directory)
    c=checked_contract(path)
    ledger=P.readjson(ledger_path)
    ledger.schema=="core.rehearsal.ledger.v1" && ledger.plan.sha256==P.digest(path) &&
        abspath(ledger.plan.path)==abspath(path) && ledger.planned==12 || throw(ArgumentError("Wrong controller ledger"))
    manifest=P.JSON3.read(E.checked_bytes(ledger.batch_started.path,ledger.batch_started.sha256))
    manifest.plan==ledger.plan || throw(ArgumentError("Controller manifest/plan mismatch"))
    length(ledger.rows)==12 && [r.job_id for r in ledger.rows]==[j.job_id for j in c.jobs] ||
        throw(ArgumentError("Incomplete or reordered controller roster"))
    jobs=[prepare_job(c,j.job_id) for j in c.jobs]
    attempts=Dict{String,Any}()
    operational=NamedTuple[]
    for (j,row,planned) in zip(jobs,ledger.rows,c.jobs)
        row.condition==j.plan.condition && row.dataset_id==j.input.id && row.fold==j.fold &&
            row.fit_seed==j.fit_seed || throw(ArgumentError("Controller row/job mismatch"))
        # Recheck the bytes validated by the parent, before deserializing our own archive.
        for stage in row.stages,e in stage.evidence
            E.checked_bytes(e.path,e.sha256)
        end
        attempt=if row.attempt!==nothing && Symbol(row.status) in
                (:prepared,:diagnostic_warning,:mcse_unavailable,:pre_fit_rejected,:scoring_error)
            a=E.deserialize(IOBuffer(E.checked_bytes(row.attempt.path,row.attempt.sha256)))
            E.check_seal(a)
            a.id==j.input.id && a.status==Symbol(row.status) || throw(ArgumentError("Attempt/controller mismatch"))
            j.fold===nothing ? (a.plan_identity==j.plan.content_hash || throw(ArgumentError("Wrong recovery plan"))) :
                (a.fold==j.fold && a.split_identity==j.split.content_hash || throw(ArgumentError("Wrong CV split")))
            if hasproperty(a,:reference)
                fit_stage=only(filter(s -> s.phase=="fit",row.stages))
                fit_ref=only(filter(e -> basename(e.path)=="fit-result.json",fit_stage.evidence))
                saved=P.JSON3.read(E.checked_bytes(fit_ref.path,fit_ref.sha256)).reference
                all(k -> getproperty(a.reference,k)==getproperty(saved,k),(:path,:sha256,:seed)) ||
                    throw(ArgumentError("Scored attempt refers to a different saved fit"))
            end
            a
        elseif row.guard!==nothing && row.termination_recorded===true &&
                !(Symbol(row.status) in (:not_started,:started_unresolved,:evidence_unresolved,:fit_saved_unscored))
            receipt=P.JSON3.read(E.checked_bytes(row.guard.path,row.guard.sha256))
            receipt.status==row.status || throw(ArgumentError("Stop status differs from guard receipt"))
            guard_failure(j,receipt;stage=Symbol(row.stage))
        else
            nothing
        end
        attempt===nothing || (attempts[j.job_id]=attempt)
        push!(operational,(;j.job_id,j.fold,condition=j.plan.condition,controller_status=Symbol(row.status),
            study_status=attempt===nothing ? :missing_attempt : attempt.status))
    end
    recovery=NamedTuple[];cv=NamedTuple[]
    unresolved=(;status=:unresolved,evidence="No verified cross-fit independence from this execution ledger")
    for condition in ("R0","R1")
        full=only(filter(j -> j.plan.condition==condition && j.fold===nothing,jobs))
        observed=haskey(attempts,full.job_id) ? [attempts[full.job_id]] : []
        names=full.spec===nothing ? String[] :
            E.recovery_quantities(P.target(full.spec),permutedims(Float64.(full.input.truth.raw))).names
        summaries=[(;parameter=name,result=E.summarize_recovery(full.plan,observed;parameter=name)) for name in names]
        push!(recovery,(;condition,summaries,quantity_roster_available=full.spec!==nothing,
            ledger=E.attempt_ledger(full.plan,observed)))
        folds=filter(j -> j.plan.condition==condition && j.fold!==nothing,jobs)
        kept=[attempts[j.job_id] for j in folds if haskey(attempts,j.job_id)]
        push!(cv,(;condition,result=E.prepare_cv_dataset(full.plan,full.input,first(folds).split,kept;
            fold_independence=unresolved)))
    end
    paired=[E.paired_cv(jobs[1].plan,[cv[1].result],jobs[2].plan,[cv[2].result];
        metric,dataset_independence=unresolved) for metric in E.LOSS_METRICS]
    result=(;contract_sha256=P.digest(path),ledger_sha256=P.digest(ledger_path),
        execution_scope=ledger.execution_scope,operational,recovery,cv,paired,
        planned_jobs=12,independent_dataset_pairs=1,new_sampler_runs=0,scientific_acceptance=false,
        replication_claims=false,numerical_precision_accepted=false)
    mkpath(directory)
    P.writejson(joinpath(directory,"collection.json"),result)
    return result
end

"""Persist diagnostic/precision warnings, as well as failed cache/target checks.
No fitting, replacement or retry is reachable from this function.
"""
function score_job(j,reference,directory)
    attempt=if !j.preflight.passed
        j.preflight.failure
    else
        try
            reference.seed==j.fit_seed || throw(ArgumentError("Reference seed differs from planned fit seed"))
            j.fold===nothing ? E.prepare_recovery(j.plan,j.input,reference) :
                E.prepare_fold(j.plan,j.input,j.split,j.fold,reference)
        catch error
            job_failure(j,:scoring_error,sprint(showerror,error))
        end
    end
    return save_attempt(directory,attempt)
end

"""Translate only an observed, terminated guard outcome. Missing receipt or
unknown cleanup remains missing in the study ledger, with operational evidence
retained by the controller. A successful process still needs its scored result.
"""
function guard_failure(j,receipt;stage)
    stage in (:fit,:score) || throw(ArgumentError("Expected fit or score stage"))
    receipt===nothing && return nothing
    status=Symbol(receipt.status)
    status in (:completed,:cleanup_failed,:cleanup_incomplete) && return nothing
    known=!receipt.launched || (hasproperty(receipt,:exit_code) && receipt.exit_code!==nothing)
    if hasproperty(receipt,:cleanup)
        known &= isempty(receipt.cleanup.observed_live_survivors)
    end
    known || return nothing
    allowed=(:wall_limit,:wall_limit_before_launch,:rss_limit,:output_limit,:output_limit_before_launch,
        :interrupted,:command_failed,:observation_unavailable,:controller_error,:unjoined_descendants)
    status in allowed || throw(ArgumentError("Unrecognized guard status"))
    result=status in (:wall_limit,:wall_limit_before_launch) ? :timeout :
        status===:command_failed ? (stage===:fit ? :fit_error : :scoring_error) : :interrupted
    return job_failure(j,result,"Observed guard stop: stage=$stage; status=$status; worker termination recorded")
end

function fit_job(path,id,directory;sampler=B.Experimental.fit)
    c=checked_contract(path)
    c.protocol_frozen===true && c.execution_allowed===true &&
        c.review.scientific=="accepted" && c.review.execution=="accepted" ||
        throw(ArgumentError("Rehearsal is a review proposal; fitting remains disabled"))
    j=prepare_job(c,id)
    !j.preflight.passed && return save_attempt(directory,j.preflight.failure)
    mkpath(directory)
    cache=joinpath(directory,"fit.jls")
    ispath(cache) && error("Do not overwrite fit")
    P.writejson(joinpath(directory,"fit-started.json"),(;job_id=id,contract_sha256=P.digest(path),seed=j.fit_seed))
    try
        fit=sampler(j.spec;prior=P.prior(),backend=:advancedhmc,init=zeros(128),seed=j.fit_seed,P.CONTROLS...)
        B.save_fit_cache(cache,fit)
        reference=(;path=abspath(cache),sha256=P.digest(cache),seed=j.fit_seed)
        E.check_fit(j.plan,j.input,E.read_fit(reference);seed=j.fit_seed,training_rows=j.preflight.training_rows)
        P.writejson(joinpath(directory,"fit-result.json"),(;job_id=id,contract_sha256=P.digest(path),reference,
            status=:fit_saved_not_yet_scored,scientific_acceptance=false))
        return reference
    catch error
        save_attempt(directory,job_failure(j,:fit_error,sprint(showerror,error)))
        rethrow()
    end
end

function main(args)
    mode=first(args)
    if mode=="prepare" && length(args)==3
        prepare_all(args[2],args[3])
    elseif mode=="fit" && length(args)==4
        value=fit_job(args[2],args[3],args[4])
        j=prepare_job(checked_contract(args[2]),args[3])
        worker_result(args[2],j,:fit,args[4],value)
    elseif mode=="score" && length(args)==5
        c=checked_contract(args[2]);j=prepare_job(c,args[3])
        value=score_job(j,P.readjson(args[4]).reference,args[5])
        worker_result(args[2],j,:score,args[5],value)
    elseif mode=="collect" && length(args)==4
        collect_ledger(args[2],args[3],args[4])
    else
        error("Use prepare PLAN OUTPUT, fit PLAN JOB DIRECTORY, score PLAN JOB FIT_RESULT DIRECTORY, or collect PLAN LEDGER DIRECTORY")
    end
end
end

if abspath(PROGRAM_FILE)==@__FILE__
    MGMFRMCoreRehearsal.main(ARGS)
end
