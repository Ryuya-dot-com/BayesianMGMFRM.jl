module MGMFRMNormalizedReplication
using BayesianMGMFRM, JSON3, Dates
include("mgmfrm_normalized_core_review.jl")
include("mgmfrm_normalized_location.jl")
const R=MGMFRMNormalizedCoreReview
const F=R.F
const B=BayesianMGMFRM
const CONTROLS=merge(F.CONTROLS,(;seed=26093003))

function run(input,roster_path,output)
    ispath(output) && error("Output must be new; never repeat a started attempt")
    p=F.prepare(input)
    reference=F.check_reference(p.target,p.x)
    roster=String.(JSON3.read(read(roster_path,String)))
    length(roster)==length(unique(roster))==150 || error("Expected 150 unique quantities")
    repo=dirname(@__DIR__)
    files=[joinpath(d,f) for folder in ("src","scripts") for
        (d,_,fs) in walkdir(joinpath(repo,folder)) for f in fs
        if any(ext->endswith(f,ext),(".jl",".stan",".py"))]
    append!(files,[joinpath(repo,f) for f in ("Project.toml","Manifest.toml")])
    hashes=Dict(relpath(f,repo)=>F.digest(f) for f in files)
    input_hash=F.digest(input); roster_hash=F.digest(roster_path)
    mkpath(output)
    writejson(name,value)=B._write_json_record(joinpath(output,name),value)
    writejson("protocol.json",(;created_utc=string(now(UTC)),julia_version=string(VERSION),
        input=abspath(input),input_sha256=input_hash,roster=abspath(roster_path),roster_sha256=roster_hash,
        source_sha256=hashes,controls=CONTROLS,backend=:advancedhmc,
        target_identity=B._mgmfrm_normalized_prior_identity(p.target),reference,
        maximum_fits=1,retries=0,extend_draws=false,initialization=:zero_raw_plus_jitter,
        qualification="Raw/direct AND 150 quantities AND 17 location quantities AND nine location moments; Rhat <= 1.01, bulk/tail ESS >= 400, retained divergences/depth hits zero, E-BFMI >= .3",
        multipliers=(2.,4.),quantile_ess_floor=400.,diagnostic_failure=:all_unresolved,
        scope=:one_independent_candidate_C_dataset_transformed_only,
        scientific_acceptance=false))
    starts=NamedTuple[]; counts=zeros(Int,4)
    observer=e->begin
        if e.phase===:sampling_start
            push!(starts,(;chain=e.chain,raw=copy(e.initial_raw),sampling=copy(e.initial_sampling)))
            println(now(UTC)," chain ",e.chain," start");flush(stdout)
        elseif e.phase===:transition
            counts[e.chain]+=1
            if counts[e.chain]%500==0
                println(now(UTC)," chain ",e.chain," transition ",counts[e.chain]);flush(stdout)
            end
        elseif e.phase===:sampling_end
            println(now(UTC)," chain ",e.chain," end");flush(stdout)
        end
    end
    phase=:sampling
    try
        elapsed=@elapsed result=MGMFRMNormalizedLocation.sample(p.target;
            CONTROLS...,record_warmup=true,_sampling_observer=observer)
        path=joinpath(output,"samples.jls")
        B._save_serialized_record(path,result.record)
        writejson("execution.json",(;elapsed_seconds=elapsed,starts,counts,
            samples_sha256=F.digest(path),controls=result.record.run.controls,
            retained_leapfrog_steps=sum(r.n_steps for r in result.record.run.sampler_stats)))
        phase=:review
        review=R.review(input,path,joinpath(output,"review"),roster)
        @assert F.digest(input)==input_hash && F.digest(roster_path)==roster_hash
        @assert all(F.digest(joinpath(repo,f))==h for (f,h) in hashes)
        writejson("completion.json",(;completed=true,qualified=review.qualified,
            input_and_sources_unchanged=true,scientific_acceptance=false))
    catch err
        writejson("failure.json",(;phase,error=sprint(showerror,err),starts,counts,retry=false))
        rethrow()
    end
end
end

if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==3 || error("usage: run_mgmfrm_normalized_replication.jl INPUT ROSTER NEW_OUTPUT")
    MGMFRMNormalizedReplication.run(ARGS...)
end
