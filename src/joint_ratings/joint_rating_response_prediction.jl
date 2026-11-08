"""Internal deterministic future-rating marginals for JointRatings."""
module JointRatingResponsePrediction
using LinearAlgebra
import BayesianMGMFRM as B
import ..JointRatingStatic as S
import ..JointRatingWorkflow as W
import ..JointRatingPredictionPrecision as P
import ..Numerics as A

"""
    prediction_design(target, rows; response_effect)

Declare future rating events using the seven joint-rating IDs and exactly the
fitted predictor columns, without scores. IDs for observations and rating events
must be new. `response_effect=:existing` retains a known response's person/task;
`:new` requires a new response ID, including another production by a known
person on the same task. Person, task, rater and criterion must be known.
Prediction rows need not contain both criteria or have full predictor rank.
"""
function prediction_design(t::S.Target,rows;response_effect)
    response_effect in (:existing,:new) || throw(ArgumentError("response_effect must be :existing or :new"))
    rows isa Union{Tuple,AbstractVector} && !isempty(rows) || throw(ArgumentError("declare prediction rows"))
    ids=S.J.IDS;fields=(ids...,t.predictor_names...)
    all(r->Set(propertynames(r))==Set(fields),rows) ||
        throw(ArgumentError("prediction rows require seven IDs and exactly the fitted predictors, without scores"))
    all(r->all(f->S.J.nonempty_id(getproperty(r,f)),ids),rows) || throw(ArgumentError("prediction IDs must be nonempty strings"))
    all(r->all(f->begin
        x=getproperty(r,f)
        x isa Real && !(x isa Bool) && isfinite(x) && isfinite(Float64(x))
    end,t.predictor_names),rows) || throw(ArgumentError("prediction predictors must be finite numbers in the fitted units"))
    canonical=[NamedTuple{fields}((Tuple(String(getproperty(r,f)) for f in ids)...,
        Tuple(Float64(getproperty(r,f)) for f in t.predictor_names)...)) for r in rows]
    length(unique(r.observation_id for r in canonical))==length(canonical) || throw(ArgumentError("duplicate prediction observation ID"))
    length(unique((r.rating_event_id,r.criterion) for r in canonical))==length(canonical) || throw(ArgumentError("duplicate prediction event/criterion"))
    old_ids=Set(t.data.observation_ids);old_events=Set(t.data.rating_event_ids)
    all(r->!(r.observation_id in old_ids) && !(r.rating_event_id in old_events),canonical) ||
        throw(ArgumentError("future observations and rating events must be absent from training"))
    trained=Dict(r.response_id=>(r.person,r.task) for r in t.data.rows)
    owners=Dict{String,Tuple{String,String}}();events=Dict{String,Tuple{String,String}}()
    for r in canonical
        pair=(r.person,r.task);event=(r.response_id,r.rater)
        get(owners,r.response_id,pair)==pair || throw(ArgumentError("a response cannot change person/task"))
        get(events,r.rating_event_id,event)==event || throw(ArgumentError("a rating event cannot change response/rater"))
        owners[r.response_id]=pair;events[r.rating_event_id]=event
        if response_effect===:existing
            get(trained,r.response_id,nothing)==pair || throw(ArgumentError("existing response must retain its trained person/task"))
        else
            !haskey(trained,r.response_id) || throw(ArgumentError("new response ID must be absent from training"))
        end
    end
    facets=(:person,:task,:rater,:criterion)
    indices=NamedTuple{facets}(Tuple(begin
        lookup=Dict(id=>i for (i,id) in enumerate(getproperty(t.levels,f)))
        all(r->haskey(lookup,getproperty(r,f)),canonical) || throw(ArgumentError("new $f levels are unsupported"))
        [lookup[getproperty(r,f)] for r in canonical]
    end for f in facets))
    lookup=Dict(id=>i for (i,id) in enumerate(t.levels.response_id))
    response_index=response_effect===:existing ? [lookup[r.response_id] for r in canonical] : zeros(Int,length(canonical))
    X=Float64[getproperty(r,f) for r in canonical,f in t.predictor_names]
    return (;rows=canonical,response_effect,indices,response_index,X)
end

function checked_quadrature(atol,maxevals)
    atol isa Real && !(atol isa Bool) && isfinite(atol) && 1e-12<=atol<1 ||
        throw(ArgumentError("quadrature_atol must be in [1e-12,1)"))
    A.checked_count(maxevals,"quadrature_maxevals")
    return nothing
end

# Artificial finite coordinates may exercise this extractor; only report
# validates posterior provenance. No retained parameter draw is discarded.
function probability_draws(t,draws,design;quadrature_atol,quadrature_maxevals)
    checked_quadrature(quadrature_atol,quadrature_maxevals)
    size(draws,1)>0 || throw(ArgumentError("parameter draws must not be empty"))
    K=t.sizes[5];N=length(design.rows);values=zeros(size(draws,1),N*K)
    error=zeros(N);evaluations=zeros(Int,N)
    for (s,q) in enumerate(eachrow(draws))
        v=S.coordinates(t,q)
        for n in 1:N
            ix=design.indices;c=ix.criterion[n];g=t.indices.threshold_group[c]
            eta=v.theta[c,ix.person[n]]-v.task[c,ix.task[n]]-v.rater[ix.rater[n],c]+dot(view(design.X,n,:),v.beta)
            probabilities=if design.response_effect===:existing
                B._ld1_pcm_probabilities(eta+v.response[c,design.response_index[n]],v.steps[:,g])
            else
                integrated=A.marginal_pcm(eta,v.response_sd[c],v.steps[:,g];atol=quadrature_atol,maxevals=quadrature_maxevals)
                error[n]=max(error[n],integrated.estimated_error)
                evaluations[n]+=integrated.evaluations
                integrated.values[1:K]
            end
            values[s,(n-1)*K+1:n*K]=probabilities
        end
    end
    all(x->isfinite(x) && 0<=x<=1,values) || throw(ArgumentError("invalid predicted probability"))
    return (;values,maximum_estimated_error=error,evaluations)
end

"""
    report(record, rows; response_effect, intervals=(.9,.99),
           quadrature_atol=1e-8, quadrature_maxevals=10000,
           policy=JointRatingPredictionPrecision.POLICY, block_rows=8)

Report marginal category probabilities for future rating events. Existing
responses use their retained effects; new responses integrate a centered Normal
effect with each draw's criterion-specific response SD. The prediction is
conditional on known person/task/rater levels and all original training data.
Intervals summarize posterior uncertainty in probabilities, not future scores.
Numerical integration error and posterior MCSE are reported separately. The
policy is an engineering proposal; global sampler warnings remain disqualifying.
No joint response score, new person/task/rater or heldout accuracy is provided.
"""
function report(record,rows;response_effect,intervals=(.9,.99),quadrature_atol=1e-8,
        quadrature_maxevals=10000,policy=P.POLICY,block_rows::Int=8)
    policy=P.checked_policy(policy);checked_quadrature(quadrature_atol,quadrature_maxevals)
    block_rows>=1 || throw(ArgumentError("block_rows must be positive"))
    masses=B._posterior_interval_probabilities(intervals)
    !isempty(masses) && allunique(masses) || throw(ArgumentError("declare distinct interval masses"))
    t=W.restore(record);design=prediction_design(t,rows;response_effect);source=W.report(record)
    source_ok=record.run.controls.chains>=policy.min_chains &&
        all(d->P.diagnostic_ok(d,policy),[source.raw_diagnostics;source.model_diagnostics]) &&
        all(s->s.n_divergences==0 && s.n_nonfinite_logdensity==0 && s.n_max_treedepth==0 &&
            isfinite(s.e_bfmi) && s.e_bfmi>=policy.ebfmi_min,source.sampler)
    request=(;target_identity=record.target_identity,source_sample_content_hash=record.content_hash,
        rows=design.rows,response_effect,predictor_names=t.predictor_names,intervals=Tuple(masses),
        quadrature_atol=Float64(quadrature_atol),quadrature_maxevals,policy)
    columns=NamedTuple[];posterior=NamedTuple[];mcse=NamedTuple[];diagnostics=NamedTuple[];decisions=NamedTuple[];integration=NamedTuple[]
    K=t.sizes[5];N=length(design.rows)
    for start in 1:block_rows:N
        subset=prediction_design(t,design.rows[start:min(start+block_rows-1,N)];response_effect)
        extracted=probability_draws(t,record.run.draws,subset;quadrature_atol,quadrature_maxevals)
        meta=[begin
            r=subset.rows[n];c=t.data.criteria[subset.indices.criterion[n]]
            labels=c.direction===:higher_is_more ? c.levels : reverse(c.levels)
            (;parameter="probability[$(repr(r.observation_id)),$k]",r.observation_id,r.person,r.task,
                r.response_id,r.rating_event_id,r.rater,r.criterion,threshold_group=c.threshold_group,
                canonical_category=k,raw_category=labels[k+1])
        end for n in eachindex(subset.rows) for k in 0:K-1]
        summaries=P.summarize(extracted.values,String[c.parameter for c in meta],record.run.controls.chains,masses,policy)
        append!(columns,meta);append!(posterior,summaries.posterior)
        append!(mcse,[merge(m,(;parameter_space=:response_prediction_probability)) for m in summaries.mcse])
        append!(diagnostics,[merge(d,(;parameter_space=:response_prediction_probability)) for d in summaries.diagnostics])
        append!(decisions,[begin
            integration_ok=extracted.maximum_estimated_error[cld(j,K)]<=min(policy.mean_mcse_max,policy.endpoint_mcse_max)
            merge(d,(;source_diagnostics_ok=source_ok,integration_error_ok=integration_ok,
                computationally_qualified=source_ok && integration_ok && d.diagnostics_ok && d.precision_status===:precision_met))
        end for (j,d) in enumerate(summaries.decisions)])
        append!(integration,[(;observation_id=r.observation_id,maximum_estimated_error=extracted.maximum_estimated_error[n],
            evaluations=extracted.evaluations[n]) for (n,r) in enumerate(subset.rows)])
    end
    return (;schema="bayesianmgmfrm.joint_rating_response_prediction.v1",request,
        request_identity=B._cache_hash(request),backend=record.run.backend,
        public_api=false,scientific_acceptance=false,interval_method=:equal_tailed,
        conditioning=:observed_training_data_and_known_person_task_rater,
        estimand=response_effect===:existing ? :existing_response_probability : :new_response_marginal_probability,
        parameter_chain_ids=copy(record.run.chain_ids),parameter_iterations=copy(record.run.iterations),
        columns,posterior,mcse,diagnostics,decisions,
        integration=(;method=response_effect===:new ? :adaptive_gauss_kronrod_with_normal_tail_bound : :not_needed,
            error_status=:estimated_not_certified,rows=integration),
        source_diagnostics=(;source.status,source.controls,source.raw_diagnostics,source.model_diagnostics,
            source.sampler,source.warmup,qualified=source_ok,parameter_mcse_qualification=:not_assessed_by_prediction_report),
        policy_status=:engineering_proposal,
        memory=(;block_rows,maximum_probability_buffer_elements=size(record.run.draws,1)*min(block_rows,N)*K),
        summary=(;quantities=length(posterior),computationally_qualified=count(d->d.computationally_qualified,decisions)),
        joint_prediction=:unsupported,
        interpretation="Each row is marginal. Multiplying rows loses shared-response and posterior dependence; this report is not a joint score or heldout validation. Intervals describe probabilities, not future outcomes.")
end
end
