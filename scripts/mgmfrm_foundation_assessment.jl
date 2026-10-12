# Prospective fixed-facet study: freeze targets or reuse one Julia process per worker.
using BayesianMGMFRM, JSON3, Dates
include("run_mgmfrm_foundation_sensitivity.jl")
const W=MGMFRMFoundationSensitivityRun
const F=W.F
const B=BayesianMGMFRM

function prepare_assessment(root)
    repo=dirname(@__DIR__)
    draft=JSON3.read(read(joinpath(root,"design.json"),String),Dict{String,Any})
    attempts=NamedTuple[]
    for block in 1:draft["blocks"], panel in ("R0","R1")
        input=relpath(joinpath(root,"inputs","B$(lpad(block,2,'0'))-$panel.json"),repo)
        p=F.prepare(joinpath(repo,input))
        p.x.assessment_id==draft["assessment_id"] && p.x.block==block || error("Wrong assessment input")
        for (suffix,sd) in (("025",.25),("050",.5),("100",1.))
            prior=B.Experimental.NormalizedMGMFRMPrior(;prior_model=:exchangeable,
                merge(F.SCALES,(;log_discrimination_sd=sd))...)
            target=B._normalized_mgmfrm_target(p.spec,prior)
            F.check_reference(target,p.x)
            push!(attempts,(;id="B$(lpad(block,2,'0'))-$panel-$suffix",block,panel,input,
                input_sha256=F.digest(joinpath(repo,input)),person_seed=p.x.person_seed,score_seed=p.x.score_seed,
                log_discrimination_sd=sd,seed=20261004040000+length(attempts)+1,
                target_identity=B._mgmfrm_normalized_prior_identity(target)))
        end
    end
    length(unique(a.target_identity for a in attempts))==6draft["blocks"] || error("Repeated target")
    files=[joinpath(d,f) for folder in ("src","scripts","test") for (d,_,fs) in walkdir(joinpath(repo,folder))
        for f in fs if any(ext->endswith(f,ext),(".jl",".stan",".py"))]
    append!(files,[joinpath(repo,f) for f in ("Project.toml","Manifest.toml",
        "docs/internal/mgmfrm-foundation-fixed-facet-design.md")])
    roster="results/workflows/20260926-normalized-core-review-01/roster.json"
    merge!(draft,Dict("attempts"=>attempts,"controls"=>Base.structdiff(F.CONTROLS,(;seed=nothing)),
        "roster"=>roster,"roster_sha256"=>F.digest(joinpath(repo,roster)),
        "source_sha256"=>Dict(relpath(f,repo)=>F.digest(f) for f in files),
        "julia_version"=>string(VERSION),"julia_binary"=>joinpath(Sys.BINDIR,Base.julia_exename()),
        "created_utc"=>string(now(UTC))))
    output=joinpath(root,"plan.json")
    ispath(output) && error("Plan is immutable")
    B._write_json_record(output,draft)
    println("Frozen ",length(attempts)," attempts; posterior fits 0")
end

function assessment_worker(root,worker)
    plan_path=joinpath(root,"plan.json")
    plan=JSON3.read(read(plan_path,String));plan_hash=F.digest(plan_path)
    worker in (1,2) || error("Expected worker 1 or 2")
    for a in plan.attempts
        mod1(a.block,2)==worker || continue
        F.digest(plan_path)==plan_hash || error("Frozen plan changed")
        output=joinpath(root,"attempts",a.id)
        try
            W.run(plan_path,a.id,output)
        catch err
            # A sampler exception is an outcome; reference/review or binding defects halt this worker.
            failure=joinpath(output,"failure.json")
            isfile(failure) && JSON3.read(read(failure,String)).phase=="sampling" || rethrow()
            println(stderr,"Recorded sampling failure for ",a.id,": ",sprint(showerror,err))
        end
        GC.gc()
    end
end

if abspath(PROGRAM_FILE)==@__FILE__
    if length(ARGS)==2 && ARGS[1]=="prepare"
        prepare_assessment(abspath(ARGS[2]))
    elseif length(ARGS)==3 && ARGS[1]=="worker"
        assessment_worker(abspath(ARGS[2]),parse(Int,ARGS[3]))
    else
        error("usage: mgmfrm_foundation_assessment.jl prepare ROOT | worker ROOT 1/2")
    end
end
