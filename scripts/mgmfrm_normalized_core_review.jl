module MGMFRMNormalizedCoreReview

# Reuse the frozen core quantity definitions, without reusing its raw prior or cohort.
using BayesianMGMFRM, Serialization, JSON3, SHA
const B=BayesianMGMFRM
include("run_mgmfrm_foundation_oracle.jl")
include("mgmfrm_core_evaluation.jl")
const F=MGMFRMFoundationOracle
const E=MGMFRMCoreEvaluation

function review(input, samples, output, roster; fitting_prior=nothing)
    ispath(output) && error("Review output must be new")
    p=F.prepare(input)
    if fitting_prior !== nothing
        p=merge(p,(;target=B._normalized_mgmfrm_target(p.spec,fitting_prior)))
    end
    record=open(deserialize,samples)
    identity=B._mgmfrm_normalized_prior_identity(p.target)
    checked=B._restore_mgmfrm_normalized_prior_samples(record;expected_identity=identity)
    run=record.run
    run.controls.chains==4 && run.controls.ndraws==1000 || error("Expected four fixed 1000-draw chains")
    run.chain_ids==repeat(1:4;inner=1000) && run.iterations==repeat(1:1000;outer=4) || error("Wrong chain order")
    base=E.sbc_quantities(p.target.base,run.draws;parameter_names=checked.raw_parameter_names)
    truth_raw=Float64.(p.x.raw_truth)
    truth_base=E.sbc_quantities(p.target.base,permutedims(truth_raw);parameter_names=checked.raw_parameter_names)
    design=p.target.base.design
    loc=B._mgmfrm_location_coordinates(design,checked.diagnostics.direct_values.direct_draws)
    truth_direct=permutedims(B._mgmfrm_source_constrained_params_from_unconstrained(design,truth_raw))
    truth_loc=B._mgmfrm_location_coordinates(design,truth_direct)
    chosen=findall(r->r.block!==:item_location,loc)
    names=[base.names;[loc[i].parameter for i in chosen]]
    names==roster && length(names)==150 || error("Declared 150-quantity roster changed")
    values=hcat(base.values,[loc[i].values for i in chosen]...)
    truths=[vec(truth_base.values);[only(truth_loc[i].values) for i in chosen]]
    diagnostic=B.diagnostics(B.Experimental.NormalizedMGMFRMFit(record;expected_identity=identity))
    metrics(x,n)=B._candidate_mcmc_diagnostic_rows(x,n,4;
        split_chains=true,rhat_threshold=1.01,ess_threshold=400.)
    focal=metrics(values,names)
    location=metrics(hcat(getproperty.(loc,:values)...),getproperty.(loc,:parameter))
    moments=F.R.location_moments(p.target.base,run.draws)
    residuals=metrics(moments.values,moments.names)
    original_gate=diagnostic.summary.passed && all(r->r.flag===:ok,residuals) &&
        all(r->!ismissing(r.e_bfmi) && isfinite(r.e_bfmi) && r.e_bfmi>=.3,run.sampler_rows)
    qualified=original_gate && all(r->r.flag===:ok,vcat(focal,location))
    precision=F.MGMFRMCoreIntervalReview.quantile_precision(values;parameter_names=names,chains=4)
    z=moments.conditional_output[:,7:8]
    zprecision=F.MGMFRMCoreIntervalReview.quantile_precision(z;
        parameter_names=["location_z_D1","location_z_D2"],chains=4)
    reference=F.check_reference(p.target,p.x)
    mkpath(output)
    writejson(name,x)=B._write_json_record(joinpath(output,name),x)
    ENDIAN_BOM==0x04030201 || error("Little-endian export required")
    open(io->write(io,values),joinpath(output,"values.bin"),"w")
    writejson("review.json",(;names,truths,precision,focal,location,residuals,
        original_gate,qualified,diagnostic=diagnostic.summary,sampler_rows=run.sampler_rows,
        input_sha256=F.digest(input),samples_sha256=F.digest(samples),target_identity=identity,
        values=(;sha256=F.digest(joinpath(output,"values.bin")),shape=size(values),
            format=:little_endian_float64,order=:column_major),scientific_acceptance=false))
    writejson("oracle-input.json",(;z_columns=[z[:,i] for i in 1:2],precision=zprecision,
        truth_z=reference.truth_z,qualified,samples_sha256=F.digest(samples)))
    println("Saved 150-quantity review: ",output,"; original gate=",original_gate,"; expanded gate=",qualified)
    return (;qualified,names)
end
end

if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==4 || error("usage: mgmfrm_normalized_core_review.jl INPUT SAMPLES NEW_OUTPUT ROSTER.json")
    MGMFRMNormalizedCoreReview.review(ARGS[1:3]...,
        String.(MGMFRMNormalizedCoreReview.JSON3.read(read(ARGS[4],String))))
end
