# Included in PairedRatingReference. These are proposal-based engineering checks.
const FOCAL_PRECISION_PROPOSAL=(;min_chains=4,rhat_max=1.01,ess_min=400.0,
    ebfmi_min=0.3,mean_sd_ratio=0.05,quantile_width_ratio=0.05,probability_mean_mcse=0.01)

function checked_precision(policy::NamedTuple)
    keys(policy)==keys(FOCAL_PRECISION_PROPOSAL) || throw(ArgumentError("all focal precision controls must be explicit"))
    checked_count(policy.min_chains,"min_chains";minimum=2)
    all(x->x isa Real && !(x isa Bool) && isfinite(x) && x>0,values(policy)[2:end]) ||
        throw(ArgumentError("precision thresholds must be finite and positive"))
    policy.rhat_max>1 || throw(ArgumentError("rhat_max must exceed one"))
    return policy
end

function focal_design(t::Target;recordings)
    count=checked_count(recordings,"recordings")
    d=t.data;known=canonical_rows(d)
    pairs=Dict(r.recording=>(r.person,r.word) for r in known)
    absent=[(p,w) for p in d.levels.person for w in d.levels.word if !((p,w) in values(pairs))]
    d.O>=count && length(absent)>=count || throw(ArgumentError("insufficient eligible recordings for the declared focal design"))
    existing=[(;person=pairs[id][1],word=pairs[id][2],rater=r,recording=id,criterion=c)
        for id in d.levels.recording[1:count] for r in d.levels.rater for c in d.levels.criterion]
    # Use IDs proven absent even when the user's labels happen to use this prefix.
    prefix="focal-new-"
    while any(startswith(id,prefix) for id in d.levels.recording);prefix="_"*prefix;end
    future=[(;person=p,word=w,rater=r,recording=prefix*string(i),criterion=c)
        for (i,(p,w)) in enumerate(absent[1:count]) for r in d.levels.rater for c in d.levels.criterion]
    return (;existing,new=future)
end

function marginal_pcm(location::Real,sd::Real,steps::AbstractVector;atol,maxevals)
    isfinite(location) && isfinite(sd) && sd>0 && length(steps)>=1 && all(isfinite,steps) ||
        throw(ArgumentError("invalid marginal PCM coordinates"))
    atol isa Real && !(atol isa Bool) && isfinite(atol) && 1e-12<=atol<1 ||
        throw(ArgumentError("quadrature atol must be in [1e-12,1)"))
    limit=checked_count(maxevals,"quadrature maxevals")
    H=length(steps);prefix=[0.;cumsum(steps)]
    all(isfinite,prefix) || throw(ArgumentError("unrepresentable cumulative steps"))
    # Splitting at all line crossings helps resolve narrow category peaks.
    knots=Float64[-9,0,9]
    for i in 0:H-1,j in i+1:H
        crossing=((prefix[j+1]-prefix[i+1])/(j-i)-location)/sd
        isfinite(crossing) && -9<crossing<9 && push!(knots,crossing)
    end
    sort!(unique!(knots));evaluations=Ref(0)
    integrand=z->begin
        evaluations[]+=1
        evaluations[]>limit && throw(ArgumentError("quadrature evaluation budget exhausted"))
        p=B._ld1_pcm_probabilities(location+sd*z,steps)
        [p;cumsum(p)[1:end-1]].*(exp(-z^2/2)/sqrt(2pi))
    end
    # Distributions already imports this installed QuadGK function; no new core dependency.
    values,error=B.Turing.Distributions.quadgk(integrand,knots...;
        atol=Float64(atol)/2,rtol=0.0,maxevals=limit,norm=v->maximum(abs,v))
    tail=2B.Turing.Distributions.ccdf(B.Turing.Distributions.Normal(),9.0)
    estimated_error=error+tail
    isfinite(estimated_error) && estimated_error<=atol && all(isfinite,values) &&
        all(v->-atol<=v<=1+atol,values) && abs(sum(values[1:H+1])-1)<=atol ||
        throw(ArgumentError("marginal probability quadrature tolerance not met"))
    return (;values,estimated_error,evaluations=evaluations[],tail_bound=tail,
        method=:adaptive_gauss_kronrod_with_normal_tail_bound)
end

function focal_draws(t::Target,raw::AbstractMatrix;existing_rows,new_rows,quadrature_atol,quadrature_maxevals)
    size(raw,1)>0 && size(raw,2)==LDP.dimension(t) && all(isfinite,raw) || throw(ArgumentError("invalid focal parameter draws"))
    old=prediction_design(t,existing_rows;recording_effect=:existing)
    new=prediction_design(t,new_rows;recording_effect=:new)
    # Validate quadrature controls even before any parameter draw is processed.
    quadrature_atol isa Real && !(quadrature_atol isa Bool) && isfinite(quadrature_atol) &&
        1e-12<=quadrature_atol<1 || throw(ArgumentError("invalid quadrature atol"))
    checked_count(quadrature_maxevals,"quadrature_maxevals")
    d=t.data;columns=NamedTuple[]
    for (kind,ids) in ((:person_contrast,d.levels.person),(:rater_contrast,d.levels.rater)),c in 1:2,
            i in 1:length(ids)-1,j in i+1:length(ids)
        push!(columns,(;name="$kind[$i,$j,$c]",kind,criterion=d.levels.criterion[c],first_id=ids[i],second_id=ids[j]))
    end
    append!(columns,[(;name="rho_person",kind=:correlation), (;name="rho_recording",kind=:correlation),
        (;name="recording_sd[1]",kind=:recording_sd), (;name="recording_sd[2]",kind=:recording_sd)])
    for (effect,design) in ((:existing,old),(:new,new)),n in eachindex(design.rows)
        for k in 0:d.K-1
            push!(columns,(;name="$effect.probability[$n,$k]",kind=:probability,recording_effect=effect,
                row=n,category=k,ids=design.rows[n]))
        end
        for k in 0:d.K-2
            push!(columns,(;name="$effect.cumulative[$n,$k]",kind=:cumulative_probability,recording_effect=effect,
                row=n,category=k,ids=design.rows[n]))
        end
    end
    draws=zeros(size(raw,1),length(columns));errors=zeros(size(raw,1),length(new.rows));evals=zeros(Int,size(errors))
    for (s,q) in enumerate(eachrow(raw))
        x=coordinates(t,q);index=0
        for (values,ids) in ((x.theta,d.levels.person),(permutedims(x.rater),d.levels.rater)),c in 1:2,
                i in 1:length(ids)-1,j in i+1:length(ids)
            draws[s,index+=1]=values[c,i]-values[c,j]
        end
        draws[s,index+1:index+4]=[x.rho;x.sd];index+=4
        for (effect,design) in ((:existing,old),(:new,new)),n in eachindex(design.rows)
            c=design.criterion[n]
            eta=x.theta[c,design.person[n]]-x.word[c,design.word[n]]-x.rater[design.rater[n],c]
            values=if effect===:existing
                p=B._ld1_pcm_probabilities(eta+x.u[c,design.trained_index[design.group[n]]],x.steps[2:end,c])
                [p;cumsum(p)[1:end-1]]
            else
                integrated=marginal_pcm(eta,x.sd[c],x.steps[2:end,c];atol=quadrature_atol,maxevals=quadrature_maxevals)
                errors[s,n]=integrated.estimated_error;evals[s,n]=integrated.evaluations
                integrated.values
            end
            draws[s,index+1:index+length(values)]=values;index+=length(values)
        end
    end
    all(isfinite,draws) || throw(ArgumentError("nonfinite focal draw; no draw removed"))
    return (;draws,columns,existing_rows=old.rows,new_rows=new.rows,
        integration=(;method=:adaptive_gauss_kronrod,atol=quadrature_atol,maxevals=quadrature_maxevals,
            error_estimates=errors,evaluations=evals,
            scope="Per-draw marginal probabilities and CDFs. Error estimates, not rigorous universal bounds; no random inner draws or joint predictive probability."))
end

function focal_diagnostic_ok(row,policy)
    !row.quality_gate_applicable && return row.flag===:structurally_fixed
    return isfinite(row.rank_normalized_rhat) && row.rank_normalized_rhat<policy.rhat_max &&
        isfinite(row.bulk_ess) && row.bulk_ess>=policy.ess_min &&
        isfinite(row.tail_ess) && row.tail_ess>=policy.ess_min
end

function focal_precision_decision(summary,mcse,kind,policy)
    if mcse.mcse_status!==:available || ismissing(mcse.mean_mcse) ||
            any(r->ismissing(r.mcse),mcse.quantiles)
        return (;status=:mcse_unavailable,mean_ratio=missing,endpoint_ratio=missing,mean_ok=false,interval_ok=false)
    end
    width=summary.upper-summary.lower
    mean_ratio=summary.sd>0 ? mcse.mean_mcse/summary.sd : Inf
    endpoint_ratio=width>0 ? maximum(r.mcse for r in mcse.quantiles if r.probability in (0.025,0.975))/width : Inf
    probability=kind in (:probability,:cumulative_probability)
    mean_ok=probability ? mcse.mean_mcse<=policy.probability_mean_mcse : mean_ratio<=policy.mean_sd_ratio
    interval_ok=endpoint_ratio<=policy.quantile_width_ratio
    return (;status=mean_ok && interval_ok ? :precision_met : :precision_insufficient,
        mean_ratio,endpoint_ratio,mean_ok,interval_ok)
end

function focal_report(record;existing_rows,new_rows,quadrature_atol,quadrature_maxevals,precision::NamedTuple)
    policy=checked_precision(precision);t=restore(record);run=record.run
    focal=focal_draws(t,run.draws;existing_rows,new_rows,quadrature_atol,quadrature_maxevals)
    names=String[c.name for c in focal.columns]
    summaries=B._posterior_summary_rows(focal.draws,names;lower=0.025,upper=0.975,
        intervals=(0.95,),reference=0.0,rope=nothing,rope_probability_threshold=0.95)
    mcse=B._posterior_mcse_rows(focal.draws,names,run.controls.chains;parameter_space=:focal)
    diagnostics=B._candidate_mcmc_diagnostic_rows(focal.draws,names,run.controls.chains;parameter_space=:focal,
        split_chains=run.split_chains_requested,rhat_threshold=Float64(policy.rhat_max),ess_threshold=Float64(policy.ess_min))
    source=report(record)
    source_ok=run.controls.chains>=policy.min_chains &&
        all(r->focal_diagnostic_ok(r,policy),[source.raw_diagnostics;source.model_diagnostics]) &&
        all(r->r.n_divergences==0 && r.n_nonfinite_logdensity==0 && isfinite(r.e_bfmi) && r.e_bfmi>=policy.ebfmi_min,source.sampler)
    decisions=map(eachindex(names)) do i
        decision=focal_precision_decision(summaries[i],mcse[i],focal.columns[i].kind,policy)
        diagnostic_ok=focal_diagnostic_ok(diagnostics[i],policy)
        (;parameter=names[i],decision...,focal_diagnostics_ok=diagnostic_ok,source_diagnostics_ok=source_ok,
            computationally_qualified=source_ok && diagnostic_ok && decision.status===:precision_met)
    end
    return (;schema="bayesianmgmfrm.paired_rating_focal_precision.v1",target_identity=record.target_identity,
        source_sample_content_hash=record.content_hash,backend=run.backend,precision_policy=policy,
        policy_status="engineering precision proposal; not an application acceptance margin",
        scientific_status=:not_established,parameter_chain_ids=run.chain_ids,parameter_iterations=run.iterations,
        focal...,posterior=summaries,mcse,diagnostics,decisions,
        source_diagnostics=(;controls=source.controls,raw=source.raw_diagnostics,model=source.model_diagnostics,
            sampler=source.sampler,warmup=source.warmup,qualified=source_ok),
        summary=(;quantities=length(names),computationally_qualified=count(r->r.computationally_qualified,decisions),
            mcse_unavailable=count(r->r.status===:mcse_unavailable,decisions),
            precision_insufficient=count(r->r.status===:precision_insufficient,decisions),
            retained_max_depth_hits=sum(r.n_max_treedepth for r in source.sampler)))
end
