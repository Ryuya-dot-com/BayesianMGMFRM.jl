module MGMFRMNormalizedLocationComparison
using BayesianMGMFRM, JSON3, SHA, Dates, Statistics
const B=BayesianMGMFRM
include("run_mgmfrm_foundation_oracle.jl")
include("mgmfrm_normalized_location.jl")
const F=MGMFRMFoundationOracle
const N=MGMFRMNormalizedLocation
const CONTROLS=merge(F.CONTROLS,(;seed=26092901))

function run(input, output)
    ispath(output) && error("Comparison output must be new")
    p=F.prepare(input)
    reference=F.check_reference(p.target,p.x)
    repo=dirname(@__DIR__)
    files=[joinpath(d,f) for (d,_,fs) in walkdir(joinpath(repo,"src")) for f in fs
        if endswith(f,".jl") || endswith(f,".stan")]
    append!(files,[joinpath(repo,f) for f in ("Project.toml","Manifest.toml",
        "scripts/run_mgmfrm_normalized_location_comparison.jl",
        "scripts/run_mgmfrm_foundation_oracle.jl","scripts/mgmfrm_normalized_location.jl",
        "scripts/mgmfrm_core_recovery_review.jl","scripts/mgmfrm_core_location_conditional.jl",
        "scripts/mgmfrm_core_interval_review.jl","scripts/mgmfrm_location_oracle_review.py",
        "scripts/mgmfrm_core_rank_review.py","scripts/mgmfrm_core_sbc_review.py",
        "scripts/mgmfrm_core_coverage_review.py")])
    hashes=Dict(relpath(f,repo)=>F.digest(f) for f in files)
    input_hash=F.digest(input)
    mkpath(output)
    writejson(path,value)=B._write_json_record(joinpath(output,path),value)
    writejson("protocol.json",(;created_utc=string(now(UTC)),julia_version=string(VERSION),
        input=abspath(input),input_sha256=input_hash,source_sha256=hashes,controls=CONTROLS,
        backend=:advancedhmc,order=(:raw,:location),maximum_fits=2,retries=0,extend_draws=false,
        target_identity=B._mgmfrm_normalized_prior_identity(p.target),
        prior=B._mgmfrm_normalized_prior_record(p.target),reference,
        qualification="Existing raw/direct gate AND all nine location diagnostics AND every E-BFMI >= .3",
        primary="Gate status, D1/D2 location R-hat and ESS, k=2 exact conditional classification risks",
        secondary="k=4 risk sensitivity; retained leapfrog counts, ESS/step; wall time includes JIT and is descriptive",
        quantile_ess_floor=400.,multipliers=(2.,4.),initialization=:zero_raw_plus_jitter,
        rng_note="Same seed and jitter policy; adaptive trajectories consume different random streams; later chain starts need not match",
        scope=:one_previously_inspected_dataset_not_general_acceptance,scientific_acceptance=false))
    for coordinate in (:raw,:location)
        directory=String(coordinate)
        mkpath(joinpath(output,directory))
        starts=NamedTuple[]
        observer=e->begin
            if e.phase===:sampling_start
                push!(starts,(;chain=e.chain,raw=copy(e.initial_raw),sampling=copy(e.initial_sampling)))
                println(now(UTC)," ",coordinate," chain ",e.chain," start");flush(stdout)
            elseif e.phase===:sampling_end
                println(now(UTC)," ",coordinate," chain ",e.chain," end");flush(stdout)
            end
        end
        try
            elapsed=@elapsed result=coordinate===:raw ?
                B._mgmfrm_normalized_prior_sample(p.target;CONTROLS...,record_warmup=true,_sampling_observer=observer) :
                N.sample(p.target;CONTROLS...,record_warmup=true,_sampling_observer=observer)
            record=result.record
            path=joinpath(output,directory,"samples.jls")
            B._save_serialized_record(path,record)
            fit=B.Experimental.NormalizedMGMFRMFit(record;expected_identity=record.target_identity)
            d=diagnostics(fit)
            moments=F.R.location_moments(p.target.base,record.run.draws)
            z=moments.conditional_output[:,7:8]
            extra=B._candidate_mcmc_diagnostic_rows(moments.values,moments.names,4;
                split_chains=true,rhat_threshold=1.01,ess_threshold=400.)
            qualified=d.summary.passed && all(r->r.flag===:ok,extra) &&
                all(r->!ismissing(r.e_bfmi) && isfinite(r.e_bfmi) && r.e_bfmi>=.3,record.run.sampler_rows)
            precision=F.MGMFRMCoreIntervalReview.quantile_precision(z;
                parameter_names=["location_z_D1","location_z_D2"],chains=4)
            writejson(joinpath(directory,"oracle-input.json"),(;z_columns=[z[:,i] for i in 1:2],
                precision,qualified,diagnostic=d.summary,location_diagnostics=extra,
                truth_z=reference.truth_z,samples_sha256=F.digest(path)))
            writejson(joinpath(directory,"diagnostics.json"),d)
            writejson(joinpath(directory,"execution.json"),(;elapsed_seconds=elapsed,starts,
                retained_leapfrog_steps=sum(r.n_steps for r in record.run.sampler_stats),
                target_identity=record.target_identity,controls=record.run.controls,
                sampler_rows=record.run.sampler_rows,
                moment_means=vec(mean(moments.values;dims=1)),
                moment_mcse=B.posterior_mcse(moments.values;chains=4,parameter_names=moments.names,probabilities=()),
                completed=true,qualified))
            println(coordinate," saved; qualified=",qualified);flush(stdout)
        catch err
            writejson(joinpath(directory,"failure.json"),(;error=sprint(showerror,err),starts,retry=false))
            println(coordinate," failed; retained failure, no retry");flush(stdout)
        end
    end
    @assert F.digest(input)==input_hash
    @assert all(F.digest(joinpath(repo,f))==h for (f,h) in hashes)
    writejson("completion.json",(;source_and_input_unchanged=true,
        completed=[c for c in ("raw","location") if isfile(joinpath(output,c,"execution.json"))],
        scientific_acceptance=false))
end
end

if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==2 || error("usage: run_mgmfrm_normalized_location_comparison.jl INPUT.json NEW_DIRECTORY")
    MGMFRMNormalizedLocationComparison.run(ARGS...)
end
