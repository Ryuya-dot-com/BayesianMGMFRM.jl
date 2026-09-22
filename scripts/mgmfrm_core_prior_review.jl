module MGMFRMCorePriorReview

include("mgmfrm_core_evaluation.jl")
const E=MGMFRMCoreEvaluation
const P=E.P
const B=E.B
using Statistics, Random, Serialization

const REGIMES=(:implementation_reference,:source_aligned,:strong_regularizing)
const METRICS=(:category_1,:category_2,:category_3,:category_4,:endpoint_mass,
    :dominant_095,:normalized_entropy,:expected_score,:replicated_endpoint_fraction,
    :any_missing_category,:missing_interior_category,:single_category)

function groups(data)
    E.candidate_cells(data)
    rows=NamedTuple[]
    function add(scope,id,indices;weights=fill(1/length(indices),length(indices)))
        push!(rows,(;scope,id,indices,weights,n_observations=length(indices)))
    end
    add(:overall,"equal_person_dimension",collect(1:data.n);weights=E.predictive_weights(data))
    for d in 1:2
        add(:dimension,"D$d",findall(n -> P.Q[data.item[n],d],1:data.n))
    end
    for r in 1:5,d in 1:2
        add(:rater_dimension,"$(data.rater_levels[r])/D$d",
            findall(n -> data.rater[n]==r && P.Q[data.item[n],d],1:data.n))
    end
    for i in 1:5
        add(:item,data.item_levels[i],findall(==(i),data.item))
    end
    for p in 1:50,d in 1:2
        add(:person_dimension,"$(data.person_levels[p])/D$d",
            findall(n -> data.person[n]==p && P.Q[data.item[n],d],1:data.n))
    end
    return rows
end

function summarize(values;binary=false)
    length(values)>=2 && all(isfinite,values) || throw(ArgumentError("Finite complete iid replicates required"))
    n=length(values)
    bounds=nothing
    if binary
        all(v -> v in (0,1),values) || throw(ArgumentError("Binary events required"))
        c=Int(sum(values))
        # Exact binomial interval; zero observed events never implies impossibility.
        bounds=(c==0 ? 0. : quantile(B.Turing.Beta(c,n-c+1),.025),
            c==n ? 1. : quantile(B.Turing.Beta(c+1,n-c),.975))
    end
    return (;mean=mean(values),q05=quantile(values,.05),q95=quantile(values,.95),
        iid_mean_mcse=std(values)/sqrt(n),n,binomial_interval95=bounds)
end

"""Conditional probability summaries and replicated-data events, keeping groups
and joint-prior draw IDs separate. The dense overall mean weights dimensions equally.
"""
function fill_metrics!(out,selected,logs,replicated,group_rows)
    size(logs,3)==4 && size(logs,1)==length(selected) &&
        size(logs,2)==size(replicated,2) && size(out,2)==length(group_rows) && size(out,3)==12 ||
        throw(ArgumentError("Prior prediction/score/group shape mismatch"))
    B._mgmfrm_mean_predicted_probabilities(logs,1e-8;log_probabilities=true)
    all(k -> k in 1:4,replicated[selected,:]) || throw(ArgumentError("Invalid replicated scores"))
    prob=exp.(logs)
    features=AbstractMatrix{Float64}[@view(prob[:,:,k]) for k in 1:4]
    append!(features,[prob[:,:,1]+prob[:,:,4],
        Float64.(dropdims(maximum(prob;dims=3);dims=3).>=.95),
        -dropdims(sum(ifelse.(isfinite.(logs),prob.*logs,0.);dims=3);dims=3)./log(4),
        sum(k.*prob[:,:,k] for k in 1:4)])
    for (g,group) in pairs(group_rows), (local_s,s) in enumerate(selected)
        ns,ws=group.indices,group.weights
        for m in 1:8
            out[s,g,m]=sum(ws[j]*features[m][local_s,n] for (j,n) in pairs(ns))
        end
        scores=@view replicated[s,ns]
        counts=[count(==(k),scores) for k in 1:4]
        out[s,g,9]=sum(ws[j]*(scores[j] in (1,4)) for j in eachindex(ns))
        out[s,g,10]=any(iszero,counts)
        out[s,g,11]=counts[2]==0 || counts[3]==0
        out[s,g,12]=count(>(0),counts)==1
    end
    return out
end

function parameter_summary(bundle)
    raw=bundle.raw_draws
    rater=hcat(raw[:,101:104],-sum(raw[:,101:104];dims=2))
    ell=hcat(raw[:,115:118],-sum(raw[:,115:118];dims=2))
    rows=NamedTuple[]
    for r in 1:5
        for (metric,values) in ((:severity,rater[:,r]),(:log_consistency,ell[:,r]),(:consistency,exp.(ell[:,r])))
            push!(rows,(;id="R$r",metric,summarize(values)...))
        end
    end
    for i in 1:5
        push!(rows,(;id="I$i",metric=:loading,summarize(exp.(raw[:,109+i]))...))
    end
    return rows
end

function review(spec,regime;ndraws,prior_seed,response_seed,batch_size=128)
    regime in REGIMES && ndraws isa Integer && !(ndraws isa Bool) && ndraws>=2 &&
        all(s -> s isa Integer && !(s isa Bool) && s>=0,(prior_seed,response_seed)) &&
        prior_seed!=response_seed || throw(ArgumentError("Declared regime, draws and distinct seeds required"))
    E.candidate_cells(spec.data)
    spec.q_matrix==P.Q || throw(ArgumentError("Wrong candidate Q matrix"))
    prior=B._mgmfrm_stress_prior(regime)
    # Reuse exactly the typed prior-prediction draw law and coordinate transforms.
    bundle=B._guarded_generalized_prior_draw_bundle(spec,"core prior review";
        prior,ndraws,rng=MersenneTwister(prior_seed))
    group_rows=groups(spec.data)
    replicated=B._guarded_generalized_replicate_scores(bundle,MersenneTwister(response_seed),"core prior review")
    values=fill(NaN,ndraws,length(group_rows),length(METRICS))
    E.foreach_log_batch(bundle.design,bundle.direct_draws;batch_size) do selected,logs
        fill_metrics!(values,selected,logs,replicated,group_rows)
    end
    all(isfinite,values) || throw(ArgumentError("Incomplete prior metrics; no draw omission or replacement allowed"))
    rows=[(;scope=g.scope,id=g.id,n_observations=g.n_observations,metric,
        summarize(values[:,j,m];binary=m>=10)...) for (j,g) in pairs(group_rows) for (m,metric) in pairs(METRICS)]
    scales=B._source_fixture_prior_values(bundle.prior)
    summary=(;regime,ndraws,prior_seed,response_seed,scales,rows,parameters=parameter_summary(bundle),
        weighting=:equal_person_dimension_overall_equal_rows_within_other_groups,
        interpretation=:joint_prior_implications_not_posterior_or_empirical_acceptance,
        observed_scores_used=false,redraws=0,new_sampler_runs=0,prior_selected=false,scientific_acceptance=false)
    return (;summary,values,groups=group_rows,raw_draws=bundle.raw_draws,
        raw_parameter_names=bundle.raw_parameter_names,replicated_scores=UInt8.(replicated))
end

function paired_summary(a,b)
    a.summary.prior_seed==b.summary.prior_seed && a.summary.response_seed==b.summary.response_seed &&
        a.summary.ndraws==b.summary.ndraws && a.groups==b.groups &&
        a.raw_parameter_names==b.raw_parameter_names || throw(ArgumentError("Prior comparison pairing mismatch"))
    differences=b.values-a.values
    return [(;scope=g.scope,id=g.id,metric,reference=a.summary.regime,alternative=b.summary.regime,
        summarize(differences[:,j,m])...) for (j,g) in pairs(a.groups) for (m,metric) in pairs(METRICS)]
end

end
