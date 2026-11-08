"""Opt-in precision/equivalence reporting for existing training-row probabilities.

Include joint_rating_static.jl and joint_rating_workflow.jl first. No sampler,
new-level integration, public API promotion or scientific acceptance is added.
"""
module JointRatingPredictionPrecision
using Statistics
import BayesianMGMFRM as B
import ..JointRatingStatic as S
import ..JointRatingWorkflow as W

const POLICY=(;min_chains=4,rhat_max=1.01,ess_min=400.,ebfmi_min=.3,
    mean_mcse_max=.01,endpoint_mcse_max=.01)

function checked_policy(policy)
    policy isa NamedTuple && keys(policy)==keys(POLICY) ||
        throw(ArgumentError("declare the complete prediction precision policy"))
    policy.min_chains isa Int && policy.min_chains>=2 || throw(ArgumentError("min_chains must be at least two"))
    all(x->x isa Real && !(x isa Bool) && isfinite(x) && x>0,values(policy)[2:end]) &&
        policy.rhat_max>1 && policy.mean_mcse_max<1 && policy.endpoint_mcse_max<1 ||
        throw(ArgumentError("invalid precision thresholds"))
    return policy
end

function selected_rows(t,observation_ids)
    observation_ids isa Union{Tuple,AbstractVector} && !isempty(observation_ids) &&
        all(x->x isa AbstractString,observation_ids) || throw(ArgumentError("declare observation IDs"))
    ids=String.(collect(observation_ids))
    length(unique(ids))==length(ids) || throw(ArgumentError("duplicate prediction observation ID"))
    lookup=Dict(id=>i for (i,id) in enumerate(t.data.observation_ids))
    all(haskey(lookup,id) for id in ids) || throw(ArgumentError("prediction requires existing training IDs"))
    return [lookup[id] for id in ids]
end

function columns(t,rows)
    labels=Dict(c.criterion=>(c.direction==:higher_is_more ? c.levels : reverse(c.levels)) for c in t.data.criteria)
    return [(;parameter="probability[$(repr(t.data.observation_ids[n])),$k]",
        observation_id=t.data.observation_ids[n],row=n,criterion=t.data.rows[n].criterion,
        response_id=t.data.response_ids[n],rating_event_id=t.data.rating_event_ids[n],
        canonical_category=k,raw_category=labels[t.data.rows[n].criterion][k+1])
        for n in rows for k in 0:t.sizes[5]-1]
end

# This internal extractor is also exercised with explicitly artificial finite
# coordinates; only report(record) supplies validated posterior provenance.
function probability_draws(t,draws,rows)
    K=t.sizes[5];out=Matrix{Float64}(undef,size(draws,1),length(rows)*K)
    for (s,q) in enumerate(eachrow(draws))
        v=S.coordinates(t,q)
        for (i,n) in enumerate(rows)
            group=t.indices.threshold_group[t.indices.criterion[n]]
            out[s,(i-1)*K+1:i*K]=B._ld1_pcm_probabilities(S.row_location(t,v,n),v.steps[:,group])
        end
    end
    all(x->isfinite(x) && 0<=x<=1,out) || throw(ArgumentError("invalid category probabilities"))
    return out
end

function diagnostic_ok(row,policy)
    !row.quality_gate_applicable && return row.flag===:structurally_fixed
    return all(isfinite,(row.rank_normalized_rhat,row.bulk_ess,row.tail_ess)) &&
        row.rank_normalized_rhat<=policy.rhat_max && row.bulk_ess>=policy.ess_min && row.tail_ess>=policy.ess_min
end
positive_mcse(x)=x isa Real && isfinite(x) && x>0

function summarize(draws,names,chains,masses,policy)
    levels=Tuple(sort(unique([.5;[p for mass in masses for p in ((1-mass)/2,1-(1-mass)/2)]])))
    rows=B._posterior_summary_rows(draws,names;lower=.05,upper=.95,intervals=masses,
        reference=0.,rope=nothing,rope_probability_threshold=.95)
    # Probability of a category is positive by construction, not evidence for it.
    posterior=[(;r.parameter,r.mean,r.sd,r.median,r.intervals,r.n_draws) for r in rows]
    mcse=B._posterior_mcse_rows(draws,names,chains;probabilities=levels,parameter_space=:conditional_probability)
    diagnostics=B._candidate_mcmc_diagnostic_rows(draws,names,chains;
        parameter_space=:conditional_probability,split_chains=true,
        rhat_threshold=Float64(policy.rhat_max),ess_threshold=Float64(policy.ess_min))
    decisions=[begin
        mean_available=positive_mcse(m.mean_mcse)
        quantiles_available=all(q->positive_mcse(q.mcse),m.quantiles)
        mean_ok=mean_available && m.mean_mcse<=policy.mean_mcse_max
        endpoints_ok=quantiles_available && all(q->q.mcse<=policy.endpoint_mcse_max,m.quantiles)
        (;parameter=m.parameter,mean_available,quantiles_available,mean_ok,endpoints_ok,
            diagnostics_ok=diagnostic_ok(d,policy),
            precision_status=!mean_available || !quantiles_available ? :unavailable_or_zero_mcse :
                mean_ok && endpoints_ok ? :precision_met : :precision_insufficient)
    end for (m,d) in zip(mcse,diagnostics)]
    return (;posterior,mcse,diagnostics,decisions,quantile_levels=levels)
end

"""
    report(record; observation_ids, intervals=(.9,.99), policy=POLICY, block_rows=8)

Summarize conditional training-row category probabilities and their MCSE.
The explicit ID roster preserves order and raw category labels. The probability
draw buffer holds at most draws * block_rows * K values. This excludes the saved
parameter draws and diagnostic working copies; it is not a total memory bound.
POLICY is an engineering proposal, not a scientifically adopted default.
"""
function report(record;observation_ids,intervals=(.9,.99),policy=POLICY,block_rows::Int=8)
    policy=checked_policy(policy)
    block_rows>=1 || throw(ArgumentError("block_rows must be positive"))
    masses=B._posterior_interval_probabilities(intervals)
    !isempty(masses) && length(unique(masses))==length(masses) || throw(ArgumentError("declare distinct interval masses"))
    t=W.restore(record);run=record.run;rows=selected_rows(t,observation_ids)
    source=W.report(record)
    source_ok=run.controls.chains>=policy.min_chains &&
        all(d->diagnostic_ok(d,policy),[source.raw_diagnostics;source.model_diagnostics]) &&
        all(s->s.n_divergences==0 && s.n_nonfinite_logdensity==0 && s.n_max_treedepth==0 &&
            isfinite(s.e_bfmi) && s.e_bfmi>=policy.ebfmi_min,source.sampler)
    posterior=NamedTuple[];mcse=NamedTuple[];diagnostics=NamedTuple[];decisions=NamedTuple[]
    quantile_levels=()
    for start in 1:block_rows:length(rows)
        selected=rows[start:min(start+block_rows-1,length(rows))];meta=columns(t,selected)
        values=probability_draws(t,run.draws,selected)
        block=summarize(values,String[c.parameter for c in meta],run.controls.chains,masses,policy)
        append!(posterior,block.posterior);append!(mcse,block.mcse);append!(diagnostics,block.diagnostics)
        append!(decisions,[merge(d,(;source_diagnostics_ok=source_ok,
            computationally_qualified=source_ok && d.diagnostics_ok && d.precision_status===:precision_met))
            for d in block.decisions]);quantile_levels=block.quantile_levels
    end
    return (;schema="bayesianmgmfrm.joint_rating_prediction_precision.v1",
        target_identity=record.target_identity,source_sample_content_hash=record.content_hash,
        backend=run.backend,scientific_acceptance=false,public_api=false,
        conditioning=:observed_training_data_and_existing_effects,new_levels=false,
        observation_ids=t.data.observation_ids[rows],columns=columns(t,rows),
        parameter_chain_ids=copy(run.chain_ids),parameter_iterations=copy(run.iterations),
        interval_method=:equal_tailed,intervals=Tuple(masses),quantile_levels,
        policy,policy_status=:engineering_proposal,posterior,mcse,diagnostics,decisions,
        source_diagnostics=(;controls=source.controls,raw=source.raw_diagnostics,model=source.model_diagnostics,
            sampler=source.sampler,warmup=source.warmup,qualified=source_ok,
            parameter_mcse_qualification=:not_assessed_by_prediction_report),
        memory=(;block_rows,maximum_probability_buffer_elements=size(run.draws,1)*min(block_rows,length(rows))*t.sizes[5]),
        summary=(;quantities=length(posterior),computationally_qualified=count(d->d.computationally_qualified,decisions)),
        interpretation="MCSE concerns numerical error in posterior summaries of conditional probabilities, not their posterior uncertainty, future outcomes or heldout accuracy.")
end

function equivalence_row(left,right,left_mcse,right_mcse;multiplier,margin,mcse_limit)
    valid=all(x->x isa Real && isfinite(x),(left,right)) && positive_mcse(left_mcse) && positive_mcse(right_mcse)
    if !valid
        return (;difference=missing,combined_mcse=missing,bound=missing,lower_bound=missing,
            mcse_ok=false,within_margin=false,status=:mcse_unavailable)
    end
    difference=right-left;combined_mcse=hypot(left_mcse,right_mcse)
    bound=abs(difference)+multiplier*combined_mcse
    lower_bound=max(0.,abs(difference)-multiplier*combined_mcse)
    mcse_ok=max(left_mcse,right_mcse)<=mcse_limit
    within_margin=isfinite(bound) && bound<=margin
    return (;difference,combined_mcse,bound,lower_bound,mcse_ok,within_margin,
        status=!mcse_ok ? :precision_insufficient : within_margin ? :within_equivalence_margin :
            lower_bound>margin ? :outside_equivalence_margin : :unresolved)
end

"""
    compare(julia_record, stan_record; observation_ids, margin, alpha=.05,
            family_size=nothing, kwargs...)

Freshly validate/report the same target in both backends, then compare mean and
reported quantiles using |difference| + z * combined MCSE <= explicit margin.
Bonferroni normal bounds are approximate; family_size can include other planned
comparisons and must not be smaller than this roster. No model selection.
"""
function compare(julia_record,stan_record;observation_ids,margin::Real,alpha::Real=.05,
        family_size=nothing,kwargs...)
    isfinite(margin) && 0<margin<1 && isfinite(alpha) && 0<alpha<1 || throw(ArgumentError("invalid equivalence margin or alpha"))
    julia_record.run.backend==:advancedhmc && stan_record.run.backend==:cmdstan || throw(ArgumentError("expected Julia then Stan records"))
    julia_record.target_identity==stan_record.target_identity || throw(ArgumentError("comparison requires the identical target"))
    j=report(julia_record;observation_ids,kwargs...);s=report(stan_record;observation_ids,kwargs...)
    j.columns==s.columns && j.quantile_levels==s.quantile_levels || throw(ArgumentError("prediction roster mismatch"))
    count=length(j.columns)*(1+length(j.quantile_levels))
    family=family_size===nothing ? count : family_size
    family isa Int && family>=count || throw(ArgumentError("family size omits planned comparisons"))
    multiplier=B.Distributions.quantile(B.Distributions.Normal(),1-alpha/(2family))
    isfinite(multiplier) || throw(ArgumentError("unrepresentable comparison multiplier"))
    comparisons=NamedTuple[]
    for i in eachindex(j.columns)
        left=[(;statistic=:mean,probability=missing,estimate=j.posterior[i].mean,mcse=j.mcse[i].mean_mcse);
            [(;statistic=:quantile,probability=q.probability,q.estimate,q.mcse) for q in j.mcse[i].quantiles]]
        right=[(;estimate=s.posterior[i].mean,mcse=s.mcse[i].mean_mcse);
            [(;q.estimate,q.mcse) for q in s.mcse[i].quantiles]]
        for (a,b) in zip(left,right)
            limit=a.statistic===:mean ? j.policy.mean_mcse_max : j.policy.endpoint_mcse_max
            numerical=equivalence_row(a.estimate,b.estimate,a.mcse,b.mcse;multiplier,margin,mcse_limit=limit)
            qualified=j.decisions[i].computationally_qualified && s.decisions[i].computationally_qualified
            push!(comparisons,(;j.columns[i]...,a.statistic,a.probability,julia_estimate=a.estimate,stan_estimate=b.estimate,
                numerical...,computationally_qualified=qualified,
                passed=qualified && numerical.status===:within_equivalence_margin))
        end
    end
    return (;schema="bayesianmgmfrm.joint_rating_prediction_equivalence.v1",target_identity=j.target_identity,
        source_sample_content_hashes=(j.source_sample_content_hash,s.source_sample_content_hash),
        conditioning=j.conditioning,margin,alpha,family_size=family,multiplier,
        interval_approximation=:bonferroni_normal_mcse,comparisons,
        resolved=all(r->r.passed,comparisons),scientific_acceptance=false,
        parameter_agreement=:not_assessed,source_reports=(;julia=j,stan=s))
end
end
