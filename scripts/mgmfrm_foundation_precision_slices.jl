module MGMFRMFoundationPrecisionSlices
using BayesianMGMFRM, JSON3, SHA, Dates
const B=BayesianMGMFRM
include("mgmfrm_core_interval_review.jl")
const I=MGMFRMCoreIntervalReview
const SLICES=((:first250,1,250),(:first500,1,500),(:last500,501,1000),(:full1000,1,1000))
digest(p)=bytes2hex(sha256(read(p)))
readjson(p)=JSON3.read(read(p,String))

function run(output)
    ispath(output) && error("Output must be new")
    repo=dirname(@__DIR__)
    jobs=[(;id="previous_raw",path="results/workflows/20260926-normalized-core-review-01/raw"),
          (;id="previous_location",path="results/workflows/20260926-normalized-core-review-01/location"),
          (;id="independent_location",path="results/workflows/20260926-normalized-replication-01/run/review")]
    files=[joinpath(repo,j.path,f) for j in jobs for f in ("review.json","values.bin","oracle-input.json")]
    hashes=Dict(relpath(p,repo)=>digest(p) for p in files)
    sources=Dict(relpath(p,repo)=>digest(p) for p in (@__FILE__,joinpath(@__DIR__,"mgmfrm_core_interval_review.jl")))
    old=readjson(joinpath(repo,"results/workflows/20260926-normalized-replication-01/run/protocol.json"))
    @assert all(digest(joinpath(repo,String(p)))==h for (p,h) in pairs(old.source_sha256))
    mkpath(output)
    writejson(name,x)=B._write_json_record(joinpath(output,name),x)
    writejson("plan.json",(;created_utc=string(now(UTC)),jobs,slices=SLICES,input_sha256=hashes,
        source_sha256=sources,prior_fit_source_sha256=old.source_sha256,
        chains=4,original_draws_per_chain=1000,quantile_ess_floor=400.,multipliers=(2.,4.),
        role=:retrospective_precision_sensitivity_before_global_diagnostic_gate,
        independent_replications=false,full_draws_are_ground_truth=false,new_fits=0))
    for job in jobs
        directory=joinpath(repo,job.path)
        r=readjson(joinpath(directory,"review.json"));o=readjson(joinpath(directory,"oracle-input.json"))
        @assert digest(joinpath(directory,"values.bin"))==r.values.sha256
        @assert r.samples_sha256==o.samples_sha256
        ENDIAN_BOM==0x04030201 || error("Little-endian export required")
        values=Matrix{Float64}(undef,4000,150)
        open(io->read!(io,values),joinpath(directory,"values.bin"))
        names=[String.(r.names);["location_z_D1","location_z_D2"]]
        matrix=hcat(values,Float64.(o.z_columns[1]),Float64.(o.z_columns[2]))
        @assert size(matrix)==(4000,152) && length(unique(names))==152 && all(isfinite,matrix)
        results=map(SLICES) do (id,lo,hi)
            indices=reduce(vcat,[collect((c*1000+lo):(c*1000+hi)) for c in 0:3])
            subset=matrix[indices,:]
            precision=I.quantile_precision(subset;parameter_names=names,chains=4)
            metrics=B._candidate_mcmc_diagnostic_rows(subset,names,4;
                split_chains=true,rhat_threshold=1.01,ess_threshold=400.)
            (;id,first_iteration=lo,last_iteration=hi,selected_rows=indices,precision,metrics,
                all_focal_diagnostics_ok=all(r->r.flag===:ok,metrics[1:150]),
                original_full_fit_qualified=r.qualified,global_slice_qualification_established=false)
        end
        writejson(job.id*".json",(;names,truths=[Float64.(r.truths);Float64.(o.truth_z)],results))
        println("Completed saved-draw slices: ",job.id);flush(stdout)
    end
    @assert all(digest(joinpath(repo,p))==h for (p,h) in hashes)
    @assert all(digest(joinpath(repo,p))==h for (p,h) in sources)
    writejson("completion.json",(;new_fits=0,input_and_sources_unchanged=true,scientific_acceptance=false))
end
end

if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==1 || error("usage: mgmfrm_foundation_precision_slices.jl NEW_OUTPUT")
    MGMFRMFoundationPrecisionSlices.run(only(ARGS))
end
