"""Internal deterministic response scores for JointRatings."""
module JointRatingResponseScore
using LinearAlgebra, Statistics
import BayesianMGMFRM as B
import ..JointRatingStatic as S
import ..JointRatingWorkflow as W
import ..JointRatingPredictionPrecision as P
import ..JointRatingResponsePrediction as R
isdefined(S.C,:stable_tanh) || throw(ArgumentError("the bundled joint-rating target must include stable correlation arithmetic"))

function score_design(t,rows;response_effect)
    rows isa Union{Tuple,AbstractVector} && !isempty(rows) || throw(ArgumentError("declare scored rows"))
    all(r->hasproperty(r,:score) && S.J.integer_score(r.score),rows) || throw(ArgumentError("declare integer raw scores"))
    design=R.prediction_design(t,[Base.structdiff(r,(;score=nothing)) for r in rows];response_effect)
    scores=Int[]
    for (n,r) in enumerate(rows)
        c=t.data.criteria[design.indices.criterion[n]]
        k=findfirst(==(r.score),c.levels)
        k===nothing && throw(ArgumentError("score outside declared criterion support"))
        push!(scores,c.direction===:higher_is_more ? k : length(c.levels)+1-k)
    end
    ids=unique(r.response_id for r in design.rows)
    groups=[findall(r->r.response_id==id,design.rows) for id in ids]
    return (;design,scores,response_ids=ids,groups,
        rows=[merge(r,(;score=rows[n].score)) for (n,r) in enumerate(design.rows)])
end

function quadrature_rules(orders)
    orders isa Union{Tuple,AbstractVector} && length(orders)>=3 &&
        all(n->n isa Int && 4<=n<=128,orders) && issorted(orders) && allunique(orders) ||
        throw(ArgumentError("declare at least three increasing Gauss-Hermite orders in 4:128"))
    return [begin
        e=eigen(SymTridiagonal(zeros(n),sqrt.(Float64.(1:n-1))))
        weights=abs2.(e.vectors[1,:]);weights./=sum(weights)
        (;order=n,nodes=e.values,logweights=log.(weights))
    end for n in orders]
end

function row_logprob(t,v,d,n,k,u)
    ix=d.indices;c=ix.criterion[n];g=t.indices.threshold_group[c]
    eta=v.theta[c,ix.person[n]]-v.task[c,ix.task[n]]-v.rater[ix.rater[n],c]+dot(view(d.X,n,:),v.beta)+u
    return B._ld1_pcm_probabilities(eta,v.steps[:,g];log_probabilities=true)[k]
end

function integrated_logprob(t,v,q,scored,group,rule)
    d=scored.design;criteria=unique(d.indices.criterion[group])
    if length(criteria)==1
        c=only(criteria)
        terms=[rule.logweights[j]+sum(row_logprob(t,v,d,n,scored.scores[n],v.response_sd[c]*z) for n in group)
            for (j,z) in enumerate(rule.nodes)]
    else
        # Use the stable transform, not sqrt(1-rho^2) after rho rounds to +/-1.
        z=q[t.blocks.correlation[2]]
        l=S.C.correlation_state([z],2;eta=t.prior.response_lkj_eta).L
        terms=[begin
            u=(v.response_sd[1]*z1,v.response_sd[2]*(l[2,1]*z1+l[2,2]*z2))
            rule.logweights[i]+rule.logweights[j]+sum(row_logprob(t,v,d,n,scored.scores[n],u[d.indices.criterion[n]]) for n in group)
        end for (i,z1) in enumerate(rule.nodes) for (j,z2) in enumerate(rule.nodes)]
    end
    result=B._logsumexp(terms)
    isfinite(result) && result<=1e-12 || throw(ArgumentError("nonfinite or invalid response log probability"))
    return result
end

# This extractor also admits explicitly finite mathematical fixtures. Posterior
# provenance is established only by report(record,...), never by this function.
function log_probability_draws(t,draws,scored;orders=(16,32,64))
    size(draws,1)>0 || throw(ArgumentError("parameter draws must not be empty"))
    rules=quadrature_rules(orders);d=scored.design;U=length(scored.groups)
    values=zeros(size(draws,1),U);agreement=zeros(U);evaluations=zeros(Int,U);saturated=0
    for (s,q) in enumerate(eachrow(draws))
        v=S.coordinates(t,q)
        states=(v.correlation_status.person,v.correlation_status.response)
        any(x->x.diagonal_underflow,states) && throw(ArgumentError("correlation factor underflow; no draw removed or replaced"))
        saturated+=any(x->x.partial_saturation,states)
        for (j,group) in enumerate(scored.groups)
            if d.response_effect===:existing
                values[s,j]=sum(row_logprob(t,v,d,n,scored.scores[n],v.response[d.indices.criterion[n],d.response_index[n]]) for n in group)
            else
                estimates=[integrated_logprob(t,v,q,scored,group,rule) for rule in rules]
                values[s,j]=last(estimates)
                # Two successive order changes must agree; no adaptive extension.
                agreement[j]=max(agreement[j],maximum(abs.(diff(estimates[end-2:end]))))
                dimension=length(unique(d.indices.criterion[group]))
                evaluations[j]+=sum(rule.order^dimension for rule in rules)
            end
        end
    end
    all(isfinite,values) || throw(ArgumentError("nonfinite response log probability; no draws removed"))
    return (;values,maximum_log_order_difference=agreement,evaluations,partial_saturation_draws=saturated)
end

"""
    report(record, rows; response_effect, orders=(16,32,64),
           log_order_tolerance=1e-5, log_score_mcse_limit=.01, policy=P.POLICY)

Score the supplied raw outcomes jointly within each response. For a new
response, integrate its shared bivariate Gaussian effect before averaging
over retained posterior draws. The score is log(mean(probability)), not
mean(log(probability)). Sum of response scores is not a whole-dataset joint score.

Gauss-Hermite order agreement is an engineering check, not an error bound.
All draws remain in the report; disagreement makes the score unqualified.
The delta-method MCSE concerns the log posterior mean probability. No credible
interval for a future score, data-sampling SE, refit, or heldout claim is added.
"""
function report(record,rows;response_effect,orders=(16,32,64),log_order_tolerance=1e-5,
        log_score_mcse_limit=.01,policy=P.POLICY)
    all(x->x isa Real && !(x isa Bool) && isfinite(x) && 0<x<1,
        (log_order_tolerance,log_score_mcse_limit)) || throw(ArgumentError("declare positive log-score tolerances below one nat"))
    policy=P.checked_policy(policy);t=W.restore(record)
    scored=score_design(t,rows;response_effect);source=W.report(record)
    source_ok=record.run.controls.chains>=policy.min_chains &&
        all(d->P.diagnostic_ok(d,policy),[source.raw_diagnostics;source.model_diagnostics]) &&
        all(s->s.n_divergences==0 && s.n_nonfinite_logdensity==0 && s.n_max_treedepth==0 &&
            isfinite(s.e_bfmi) && s.e_bfmi>=policy.ebfmi_min,source.sampler)
    extracted=log_probability_draws(t,record.run.draws,scored;orders)
    source_ok &= extracted.partial_saturation_draws==0
    results=map(eachindex(scored.groups)) do j
        logs=extracted.values[:,j];offset=maximum(logs);scaled=exp.(logs.-offset)
        name="response_probability[$(repr(scored.response_ids[j]))]"
        m=only(B._posterior_mcse_rows(reshape(scaled,:,1),[name],record.run.controls.chains;
            probabilities=(.5,),parameter_space=:scaled_response_probability))
        d=only(B._candidate_mcmc_diagnostic_rows(reshape(scaled,:,1),[name],record.run.controls.chains;
            parameter_space=:scaled_response_probability,split_chains=true,
            rhat_threshold=Float64(policy.rhat_max),ess_threshold=Float64(policy.ess_min)))
        log_mcse=P.positive_mcse(m.mean_mcse) ? m.mean_mcse/mean(scaled) : missing
        integration_ok=extracted.maximum_log_order_difference[j]<=log_order_tolerance
        mcse_ok=!ismissing(log_mcse) && isfinite(log_mcse) && log_mcse<=log_score_mcse_limit
        qualified=source_ok && P.diagnostic_ok(d,policy) && integration_ok && mcse_ok
        group=scored.groups[j]
        (;response_id=scored.response_ids[j],person=scored.rows[first(group)].person,
            task=scored.rows[first(group)].task,observation_ids=[scored.rows[n].observation_id for n in group],
            ratings=length(group),log_predictive_density=offset+log(mean(scaled)),
            posterior_mean_log_probability=mean(logs),log_score_mcse=log_mcse,
            mcse_status=m.mcse_status,mcse_method=:delta_method_on_scaled_mean,
            scaled_probability_offset=offset,scaled_probability_mcse=m,diagnostics=d,
            maximum_log_order_difference=extracted.maximum_log_order_difference[j],
            integration_evaluations=extracted.evaluations[j],integration_ok,mcse_ok,
            source_diagnostics_ok=source_ok,computationally_qualified=qualified)
    end
    request=(;target_identity=record.target_identity,source_sample_content_hash=record.content_hash,
        response_effect,rows=scored.rows,orders=Tuple(orders),log_order_tolerance,log_score_mcse_limit,policy)
    return (;schema="bayesianmgmfrm.joint_rating_response_score.v1",request,request_identity=B._cache_hash(request),
        backend=record.run.backend,public_api=false,scientific_acceptance=false,heldout_validation=false,
        unit=:response,conditioning=:observed_training_data_and_known_person_task_rater,
        rows=results,parameter_chain_ids=copy(record.run.chain_ids),parameter_iterations=copy(record.run.iterations),
        summary=(;responses=length(results),ratings=length(rows),
            sum_log_predictive_density=sum(r.log_predictive_density for r in results),
            computationally_qualified=count(r->r.computationally_qualified,results),
            aggregation=:sum_of_marginal_response_log_scores,dataset_joint_score=false,
            sum_mcse_status=:not_computed,data_sampling_se_status=:not_computed),
        integration=(;method=response_effect===:new ? :gauss_hermite : :not_needed,
            status=:order_agreement_is_not_an_error_bound,automatic_extension=false),
        correlation_representation=(;partial_saturation_draws=extracted.partial_saturation_draws,
            diagonal_underflow=:refused_without_dropping_draws),
        source_diagnostics=(;source.status,source.controls,source.raw_diagnostics,source.model_diagnostics,
            source.sampler,source.warmup,qualified=source_ok),
        interpretation="Scores describe the supplied outcomes. Source warnings and integration disagreement remain. Whole-response training exclusion, matched refits, comparison uncertainty and sampling-unit dependence require separate validation.")
end
end
