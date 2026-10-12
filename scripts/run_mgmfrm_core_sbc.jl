module MGMFRMCoreSBCWorker

include(joinpath(@__DIR__,"mgmfrm_core_evaluation.jl"))
include(joinpath(@__DIR__,"mgmfrm_core_interval_review.jl"))
include(joinpath(@__DIR__,"mgmfrm_core_location_conditional.jl"))
const E=MGMFRMCoreEvaluation
const I=MGMFRMCoreIntervalReview
const C=MGMFRMCoreLocationConditional
const P,B=E.P,E.B
using JSON3,Dates,Statistics,LinearAlgebra

function context(root,id)
    launch=P.readjson(joinpath(root,"launch.json"))
    id in launch.selected_ids || error("Job is outside this launch")
    P.digest(joinpath(root,"execution-setting.json"))==launch.setting_sha256 || error("Setting changed")
    setting=P.readjson(joinpath(root,"execution-setting.json"))
    for sources in (setting.source_sha256,launch.worker_sha256), (path,hash) in pairs(sources)
        P.digest(joinpath(P.REPO,String(path)))==hash || error("Bound source changed: $path")
    end
    job=only(filter(j->j.id==id,setting.jobs))
    controls=merge(P.CONTROLS,(;ndraws=Int(setting.controls.ndraws)))
    for (k,value) in pairs(controls)
        expected=getproperty(setting.controls,k)
        (value isa Symbol ? String(value)==expected : value==expected) || error("Unsupported control: $k")
    end
    setting.backend=="advancedhmc" && setting.sampling_coordinates=="orthogonal_person_mean_item_offset" ||
        error("Worker is bound to the declared backend and coordinates")
    all(getproperty(P.prior(),k)==v for (k,v) in pairs(setting.prior)) || error("Prior changed")
    all(getproperty(P.CRITERIA,k)==v for (k,v) in pairs(setting.criteria)) || error("Diagnostic criteria changed")
    setting.initialization.truth_used===false && Float64.(setting.initialization.base_raw)==zeros(128) || error("Initial values changed")
    plan=E.evaluation_plan(String[j.id for j in setting.jobs];mode=:prior,backend=:advancedhmc,
        generator_sha256=P.digest(joinpath(@__DIR__,"mgmfrm_core_reference.py")),
        retained_per_chain=controls.ndraws)
    receipt=P.readjson(joinpath(root,id,"generation-receipt.json"))
    receipt.id==id && receipt.plan_identity==launch.plan_identity || error("Generation belongs to another setting")
    hashes=(;(k=>String(getproperty(receipt.hashes,k)) for k in (:generation,:raw_truth,:truth,:observed))...)
    input=E.bind_panel(plan,id;directory=joinpath(root,"inputs",id),hashes)
    input.generation.truth_seed==job.truth_seed && input.generation.score_seed==job.score_seed || error("Generation seed mismatch")
    return (;launch,setting,job,controls,plan,input)
end

function conditional_review(raw)
    residuals=zeros(size(raw,1),9)
    for i in axes(raw,1)
        theta=Matrix(reshape(raw[i,1:100],2,50)')
        A=Float64.(P.Q).*exp.(raw[i,110:114])
        c=C.location_conditional(theta,A,raw[i,105:109];person_sd=1.,item_sd=1.)
        mu,m,v,z=c.observed_mean,c.conditional_mean,diag(c.covariance),c.standardized_residual
        residuals[i,:]=[mu-m;mu.^2-(v+m.^2);z;z.^2 .- 1;z[1]*z[2]]
    end
    names=["mean_difference_D1","mean_difference_D2","second_moment_difference_D1",
        "second_moment_difference_D2","z_D1","z_D2","z_squared_minus_one_D1",
        "z_squared_minus_one_D2","z_product_D1_D2"]
    mcse=B.posterior_mcse(residuals;chains=4,parameter_names=names,probabilities=())
    diagnostics=B._candidate_mcmc_diagnostic_rows(residuals,names,4;split_chains=true,
        rhat_threshold=1.01,ess_threshold=400.,parameter_space=:conditional_moment_residual)
    rows=map(eachindex(names)) do j
        x=reshape(residuals[:,j],:,4);half=size(x,1)÷2;se=mcse[j].mean_mcse
        (;parameter=names[j],estimate=mean(x),precision=mcse[j],diagnostics=diagnostics[j],
            mean_over_mcse=se isa Real && isfinite(se) && se>0 ? mean(x)/se : missing,
            chain_means=vec(mean(x;dims=1)),half_means=[mean(x[1:half,:]),mean(x[half+1:end,:])])
    end
    return (;residuals,names,rows)
end

function review(fit,checked,input;expected_names)
    n=B._fit_draws_per_chain(fit)
    fit.chain_ids==repeat(1:4;inner=n) && fit.iterations==repeat(1:n;outer=4) || error("Wrong chain order")
    base=E.sbc_quantities(checked.target,fit.draws;parameter_names=input.truth.raw_names)
    truth_raw=permutedims(Float64.(input.truth.raw))
    base_truth=E.sbc_quantities(checked.target,truth_raw;parameter_names=input.truth.raw_names)
    location=filter(r->r.block!==:item_location,B._mgmfrm_location_coordinates(fit.design,checked.direct))
    truth_direct=permutedims(B._mgmfrm_source_constrained_params_from_unconstrained(fit.design,vec(truth_raw)))
    truth_location=filter(r->r.block!==:item_location,B._mgmfrm_location_coordinates(fit.design,truth_direct))
    names=[base.names;getproperty.(location,:parameter)]
    names==expected_names && length(names)==150 || error("Declared quantity roster changed")
    values=hcat(base.values,getproperty.(location,:values)...)
    truths=[vec(base_truth.values);[only(r.values) for r in truth_location]]
    original=E.qualification(fit,checked,values,names)
    extra=B._mgmfrm_location_diagnostics(fit;split_chains=true,rhat_threshold=1.01,ess_threshold=400.).location_rows
    # Twelve location quantities already belong to the 150-quantity roster.
    additional=filter(r->!(r.parameter in names),extra)
    groups=merge(original.diagnostic_rows,(;focal=vcat(original.diagnostic_rows.focal,additional)))
    checked_q=E.V.qualify_diagnostics(groups,original.sampler_rows;criteria=P.CRITERIA,
        telemetry_complete=!any(r->r.reason===:incomplete_telemetry,original.failures))
    q=merge(original,checked_q,(;diagnostic_rows=groups,base_qualified=original.qualified,location_rows=extra))
    !q.qualified || original.qualified || error("Added location check upgraded a rejected fit")
    precision=I.quantile_precision(values;parameter_names=names,chains=4)
    moments=conditional_review(fit.draws)
    return (;values,names,truths,qualification=q,precision,moments)
end

function export_values(path,values,names)
    ispath(path) && error("Existing export must not be overwritten")
    ENDIAN_BOM==0x04030201 || error("Little-endian export required")
    open(io->write(io,values),path,"w")
    return (;path=abspath(path),sha256=P.digest(path),shape=size(values),names,
        format=:little_endian_float64,order=:column_major)
end

function main(root,id)
    BLAS.set_num_threads(1)
    directory=joinpath(root,id);phase=:preflight;started=time()
    isfile(joinpath(directory,"sampling-started.json")) && error("Refusing to repeat a started sampler attempt")
    try
        c=context(root,id)
        preflight=E.input_preflight(c.plan,c.input)
        P.writejson(joinpath(directory,"preflight.json"),preflight)
        preflight.passed || error("Pre-fit input rejection; preserve this slot")
        spec=P.specification(c.input.observed;require_all_categories=false)
        target=P.target(spec);truth=Float64.(c.input.truth.raw)
        isapprox(B._source_fixture_logprior(target,truth),c.input.truth.log_prior;atol=1e-9) &&
            isapprox(B._source_fixture_loglikelihood(target,truth),c.input.truth.log_likelihood;atol=1e-8) ||
            error("Independent generator and Julia target differ")
        phase=:fit
        P.writejson(joinpath(directory,"sampling-started.json"),(;id,seed=c.job.fit_seed,
            started=string(now(UTC)),controls=c.controls,sampling_coordinates=c.setting.sampling_coordinates,
            plan_identity=c.launch.plan_identity,setting_sha256=c.launch.setting_sha256))
        println("FIT_START ",id," ",now(UTC));flush(stdout)
        counter=Ref(0)
        observer=function(event)
            if event.phase===:sampling_start
                counter[]=0
            elseif event.phase===:transition
                counter[]+=1
                counter[]%500==0 && (println("SAMPLE ",id," chain=",event.chain,
                    " transitions=",counter[]," ",now(UTC));flush(stdout))
            end
            nothing
        end
        fit_start=time()
        fit=B.Experimental.fit(spec;prior=P.prior(),backend=:advancedhmc,
            sampling_coordinates=:orthogonal_person_mean_item_offset,
            init=Float64.(c.setting.initialization.base_raw),seed=Int(c.job.fit_seed),
            c.controls...,_sampling_observer=observer)
        fit_seconds=time()-fit_start;phase=:save;save_start=time()
        cache=joinpath(directory,"fit.jls");ispath(cache) && error("Existing fit")
        B.save_fit_cache(cache,fit)
        reference=(;path=abspath(cache),sha256=P.digest(cache),seed=Int(c.job.fit_seed))
        P.writejson(joinpath(directory,"fit-result.json"),(;reference,fit_seconds,sampler_controls=fit.sampler_controls))
        fit=nothing;GC.gc();fit=E.read_fit(reference)
        save_reload_seconds=time()-save_start;phase=:review;review_start=time()
        checked=E.check_fit(c.plan,c.input,fit;seed=reference.seed)
        fit.sampler_controls.sampling_coordinates===:orthogonal_person_mean_item_offset &&
            fit.sampler_controls.metric===:diagonal && fit.sampler_controls.ad_backend===:ForwardDiff || error("Saved computational settings differ")
        r=review(fit,checked,c.input;expected_names=String.(c.setting.names))
        export_record=export_values(joinpath(directory,"quantities.f64"),r.values,r.names)
        moment_export=export_values(joinpath(directory,"location-residuals.f64"),r.moments.residuals,r.moments.names)
        P.writejson(joinpath(directory,"location-moments.json"),(;rows=r.moments.rows,export_record=moment_export,
            role="Descriptive conditional moment check; no change to fit qualification or prior-002 interpretation",
            scientific_acceptance=false))
        context(root,id) # sources, declared setting and generated bytes still match
        P.digest(reference.path)==reference.sha256 || error("Saved fit changed")
        P.writejson(joinpath(directory,"worker-result.json"),(;id,julia_version=string(VERSION),plan_identity=c.launch.plan_identity,
            setting_sha256=c.launch.setting_sha256,input_hashes=c.input.hashes,reference,
            names=r.names,truths=r.truths,qualification=r.qualification,precision=r.precision,export_record,
            location_moments_sha256=P.digest(joinpath(directory,"location-moments.json")),
            fit_seconds,save_reload_seconds,review_seconds=time()-review_start,
            worker_body_seconds=time()-started,scientific_acceptance=false))
        println("COMPLETE ",id," qualified=",r.qualification.qualified," ",now(UTC));flush(stdout)
    catch error
        P.writejson(joinpath(directory,"worker-failure.json"),(;id,phase,error=sprint(showerror,error),
            backtrace=sprint(Base.show_backtrace,catch_backtrace()),interrupted=error isa InterruptException,
            elapsed_seconds=time()-started,scientific_acceptance=false))
        rethrow()
    end
end

end

if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==2 || error("Usage: run_mgmfrm_core_sbc.jl RUN_DIRECTORY DATASET_ID")
    MGMFRMCoreSBCWorker.main(abspath(ARGS[1]),ARGS[2])
end
