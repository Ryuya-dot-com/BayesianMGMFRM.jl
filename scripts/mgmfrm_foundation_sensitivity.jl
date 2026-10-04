module MGMFRMFoundationSensitivity
using BayesianMGMFRM, JSON3, Serialization, Statistics, Dates
include("mgmfrm_normalized_core_review.jl")
const B=BayesianMGMFRM
const C=MGMFRMNormalizedCoreReview
const F=C.F
const R=F.R

function extra_quantities(target,raw)
    q=R.quantities(target.base,raw)
    indices=findall(r->r.block in (:centered_person,:person_mean),q.roster)
    names=q.names[indices]; columns=[q.draws[:,i] for i in indices]
    for i in 1:5
        push!(names,"log_loading[I$i]");push!(columns,raw[:,109+i])
    end
    for (i,j) in ((1,2),(3,4),(3,5),(4,5))
        push!(names,"log_loading[I$i]-log_loading[I$j]")
        push!(columns,raw[:,109+i]-raw[:,109+j])
    end
    return (;names,values=hcat(columns...),recovery=q)
end

function extra_review(input,samples,core_review,output)
    ispath(output) && error("Extra review output must be new")
    p=F.prepare(input)
    record=open(deserialize,samples)
    target=B._MGMFRMNormalizedPriorLogDensity(p.spec,record.prior;
        expected_identity=record.target_identity)
    checked=B._restore_mgmfrm_normalized_prior_samples(record;
        expected_identity=record.target_identity)
    core=JSON3.read(read(core_review,String))
    core.input_sha256==F.digest(input) && core.samples_sha256==F.digest(samples) &&
        core.target_identity==record.target_identity || error("Core review binding mismatch")
    run=record.run
    run.chain_ids==repeat(1:4;inner=1000) && run.iterations==repeat(1:1000;outer=4) ||
        error("Expected four ordered 1000-draw chains")
    extra=extra_quantities(target,run.draws)
    metrics(x,n)=B._candidate_mcmc_diagnostic_rows(x,n,4;
        split_chains=true,rhat_threshold=1.01,ess_threshold=400.)
    diagnostic=metrics(extra.values,extra.names)
    precision=B.posterior_mcse(extra.values;chains=4,parameter_names=extra.names,
        probabilities=(.05,.95))
    finite(x)=x isa Real && isfinite(x) && x>=0
    rows=map(eachindex(extra.names)) do j
        m=precision[j];sd=std(extra.values[:,j]);lo,hi=m.quantiles
        width=hi.estimate-lo.estimate
        good=sd>0 && finite(m.mean_mcse) && m.mean_mcse/sd<=.05 && width>0 &&
            finite(lo.mcse) && finite(hi.mcse) && max(lo.mcse,hi.mcse)/width<=.05
        (;parameter=extra.names[j],estimate=mean(extra.values[:,j]),posterior_sd=sd,
            diagnostic=diagnostic[j],precision=m,local_precision_passed=good,
            qualified=core.qualified && diagnostic[j].flag===:ok && good)
    end
    truth=R.quantities(target.base,permutedims(Float64.(p.x.raw_truth)))
    error_mcse=R.person_error_mcse(extra.recovery,truth;chains=4)
    println(now(UTC)," parameter precision ready; ",sum(r.qualified for r in rows),"/",length(rows));flush(stdout)
    # Existing probabilities, per-draw covariance and chain order are retained.
    prob=B._mgmfrm_predictive_probabilities_direct(target.base.design,
        checked.diagnostics.direct_values.direct_draws)
    maximum(abs.(sum(prob;dims=3).-1))<1e-12 || error("Probabilities do not normalize")
    prediction=NamedTuple[]
    for start in 1:25:size(prob,2)
        ids=start:min(start+24,size(prob,2))
        names=["probability[row=$i,category=$k]" for k in 1:4 for i in ids]
        values=reshape(prob[:,ids,:],4000,:)
        ms=B.posterior_mcse(values;chains=4,parameter_names=names,probabilities=())
        ds=metrics(values,names)
        for (j,(k,i)) in enumerate((k,i) for k in 1:4 for i in ids)
            good=finite(ms[j].mean_mcse) && ms[j].mean_mcse<=.01
            push!(prediction,(;row=i,category=k,estimate=mean(values[:,j]),
                mean_mcse=ms[j].mean_mcse,diagnostic=ds[j],
                qualified=core.qualified && ds[j].flag===:ok && good))
        end
        start%250==1 && (println(now(UTC)," probability rows ",last(ids),"/",size(prob,2));flush(stdout))
    end
    payload=(;input_sha256=F.digest(input),samples_sha256=F.digest(samples),
        core_review_sha256=F.digest(core_review),target_identity=record.target_identity,
        prior=record.prior,original_gate=core.qualified,rows,error_mcse,prediction,
        primary_quantities_qualified=core.qualified && all(r->r.qualified,rows),
        prediction_scope=:in_sample_prior_sensitivity_not_heldout,
        error_mcse_scope=:first_order_MCMC_not_replication_error_or_bias_bound,
        scientific_acceptance=false)
    B._write_json_record(output,payload)
    println(now(UTC)," saved extra review ",output);flush(stdout)
    return payload
end

function loading_review(input,samples,extra,output)
    ispath(output) && error("Loading review output must be new")
    p=F.prepare(input);record=open(deserialize,samples)
    extra.input_sha256==F.digest(input) && extra.samples_sha256==F.digest(samples) &&
        extra.target_identity==record.target_identity || error("Loading review binding mismatch")
    B._restore_mgmfrm_normalized_prior_samples(record;expected_identity=record.target_identity)
    target=B._MGMFRMNormalizedPriorLogDensity(p.spec,record.prior;expected_identity=record.target_identity)
    q=R.quantities(target.base,record.run.draws)
    t=R.quantities(target.base,permutedims(Float64.(p.x.raw_truth)))
    selected=findall(r->r.block===:loading,q.roster)
    subset(x)=(;names=x.names[selected],roster=x.roster[selected],draws=x.draws[:,selected])
    q=subset(q);t=subset(t)
    metrics=B._candidate_mcmc_diagnostic_rows(q.draws,q.names,4;
        split_chains=true,rhat_threshold=1.01,ess_threshold=400.)
    reviewed=R.review(q,t;chains=4)
    finite(x)=x isa Real && isfinite(x) && x>=0
    rows=map(eachindex(q.names)) do j
        r=reviewed.rows[j];ci=only(filter(x->x.level==.9,r.intervals))
        local90=r.posterior_sd>0 && finite(r.precision.mean_mcse) &&
            r.precision.mean_mcse/r.posterior_sd<=.05 &&
            finite(ci.maximum_endpoint_mcse_over_width) && ci.maximum_endpoint_mcse_over_width<=.05
        qualified90=extra.primary_quantities_qualified && metrics[j].flag===:ok && local90
        (;r...,diagnostic=metrics[j],qualified90,
            coverage90_status=!qualified90 || ci.boundary_sensitivity!==false ? :unresolved :
                (ci.covered ? :covered : :not_covered))
    end
    payload=(;rows,target_identity=record.target_identity,input_sha256=F.digest(input),
        samples_sha256=F.digest(samples),evaluation_credit=p.x.evaluation_credit,scientific_acceptance=false)
    B._write_json_record(output,payload)
    return payload
end

end

if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==4 || error("usage: mgmfrm_foundation_sensitivity.jl INPUT SAMPLES CORE_REVIEW NEW_OUTPUT")
    MGMFRMFoundationSensitivity.extra_review(ARGS...)
end
