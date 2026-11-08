"""Isolated two-criterion static density; no public fitting API."""
module JointRatingStatic

import BayesianMGMFRM as B
import LogDensityProblems as L
using LinearAlgebra
include("joint_rating_design.jl")
import ..Numerics
include("mgmfrm_lkj_cholesky_candidate.jl")
const J = JointRatingDesign
const H = Numerics
const C = MGMFRMLKJCholeskyCandidate
const SCHEMA = "bayesianmgmfrm.joint_rating_static_target.v1"
const PRIOR_KEYS = (:task_sd,:rater_sd,:step_sd,:response_log_sd_mean,
    :response_log_sd_sd,:beta_sd,:person_lkj_eta,:response_lkj_eta)

struct Target{D,P,BT,IX,LV}
    data::D
    prior::P
    blocks::BT
    indices::IX
    levels::LV
    X::Matrix{Float64}
    predictor_names::Vector{Symbol}
    sizes::NTuple{7,Int} # P,T,R,O,K,G,F
    mean::Vector{Float64}
    sd::Vector{Float64}
    log_normalizer::Vector{Float64}
end

finite_number(x) = x isa Real && !(x isa Bool) && isfinite(x) && isfinite(Float64(x))
function checked_prior(prior, G, F)
    prior isa NamedTuple && Set(keys(prior)) == Set(PRIOR_KEYS) ||
        throw(ArgumentError("declare exactly $PRIOR_KEYS"))
    for k in (:task_sd,:person_lkj_eta,:response_lkj_eta)
        finite_number(prior[k]) && Float64(prior[k]) > 0 ||
            throw(ArgumentError("$k must be finite and positive"))
    end
    for (k,n) in ((:rater_sd,2),(:step_sd,G),(:response_log_sd_mean,2),
                  (:response_log_sd_sd,2),(:beta_sd,F))
        v=prior[k]
        v isa Union{Tuple,AbstractVector} && length(v)==n &&
            all(x->finite_number(x) && (k==:response_log_sd_mean || Float64(x)>0),v) ||
            throw(ArgumentError("$k needs $n finite values; scales must be positive"))
    end
    return (;task_sd=Float64(prior.task_sd),rater_sd=Tuple(Float64.(prior.rater_sd)),
        step_sd=Tuple(Float64.(prior.step_sd)),response_log_sd_mean=Tuple(Float64.(prior.response_log_sd_mean)),
        response_log_sd_sd=Tuple(Float64.(prior.response_log_sd_sd)),beta_sd=Tuple(Float64.(prior.beta_sd)),
        person_lkj_eta=Float64(prior.person_lkj_eta),response_lkj_eta=Float64(prior.response_lkj_eta))
end

"""
    Target(rows; criteria, prior, predictor_columns=())

Two criteria, common category count, unit coefficients, criterion-specific
task/finite-panel rater effects and a correlated produced-response effect.
Predictors are explicit numeric columns on the input rows. See the internal
static-target specification for complete priors and identification limits.
This creates a density at supplied coordinates, not a posterior fit.
"""
function Target(rows; criteria, prior, predictor_columns=())
    data=J.prepare_ratings(rows;criteria)
    length(data.criteria)==2 && length(unique(data.category_counts))==1 ||
        throw(ArgumentError("static target requires exactly two criteria with a common category count"))
    fields=(:person,:task,:rater,:response_id,:criterion)
    levels=NamedTuple{fields}(Tuple(sort(unique(getproperty.(data.rows,f))) for f in fields))
    P,T,R,O=length.((levels.person,levels.task,levels.rater,levels.response_id))
    min(P,T,R)>=2 || throw(ArgumentError("first target requires at least two people, tasks and raters"))
    indices=NamedTuple{fields}(Tuple(begin
        lookup=Dict(x=>i for (i,x) in enumerate(levels[f]))
        [lookup[getproperty(r,f)] for r in data.rows]
    end for f in fields))
    all(p -> length(unique(indices.criterion[indices.person.==p]))==2,1:P) ||
        throw(ArgumentError("both criteria must be observed for each person in this target"))
    groups=sort(unique(c.threshold_group for c in data.criteria))
    group=[findfirst(==(c.threshold_group),groups) for c in data.criteria]
    levels=merge(levels,(;threshold_group=groups))
    indices=merge(indices,(;threshold_group=Int.(group)))
    predictor_columns isa Union{Tuple,AbstractVector} || throw(ArgumentError("declare predictor columns"))
    X=isempty(predictor_columns) ? zeros(length(data.rows),0) :
        J.checked_predictors(data,rows;columns=predictor_columns).values
    K,G,F=first(data.category_counts),length(groups),size(X,2)
    pr=checked_prior(prior,G,F)
    counts=(;person_white=2P,task=2T,rater_white=2(R-1),step_white=G*(K-2),
        response_white=2O,beta=F,log_response_sd=2,correlation=2)
    offset=0
    blocks=NamedTuple{keys(counts)}(Tuple(begin
        result=(offset+1):(offset+count);offset+=count;result
    end for count in values(counts)))
    mu=zeros(offset-2);sd=ones(offset-2)
    sd[blocks.task].=pr.task_sd
    sd[blocks.beta].=pr.beta_sd
    mu[blocks.log_response_sd].=pr.response_log_sd_mean
    sd[blocks.log_response_sd].=pr.response_log_sd_sd
    logc=[-B.SpecialFunctions.logbeta(.5,eta) for eta in
        (pr.person_lkj_eta,pr.response_lkj_eta)]
    return Target(data,pr,blocks,indices,levels,X,Symbol[predictor_columns...],
        (P,T,R,O,K,G,F),mu,sd,logc)
end

L.dimension(t::Target)=last(t.blocks.correlation)
L.capabilities(::Type{<:Target})=L.LogDensityOrder{1}()
function check_vector(t,q)
    length(q)==L.dimension(t) && all(isfinite,q) || throw(ArgumentError("invalid parameter vector"))
end
function initial(t::Target)
    q=zeros(L.dimension(t));q[t.blocks.log_response_sd].=t.prior.response_log_sd_mean
    return q
end
function coordinates(t::Target,q::AbstractVector{<:Real})
    check_vector(t,q)
    b,p=t.blocks,t.prior;P,T,R,O,K,G,F=t.sizes
    cp=C.correlation_state(view(q,b.correlation[1]:b.correlation[1]),2;eta=p.person_lkj_eta)
    cr=C.correlation_state(view(q,b.correlation[2]:b.correlation[2]),2;eta=p.response_lkj_eta)
    response_sd=exp.(q[b.log_response_sd])
    return (;theta=cp.L*reshape(q[b.person_white],2,P),task=reshape(q[b.task],2,T),
        rater=hcat([p.rater_sd[c]*H._zero_sum(q[(first(b.rater_white)+(c-1)*(R-1)):(first(b.rater_white)+c*(R-1)-1)]) for c in 1:2]...),
        steps=hcat([p.step_sd[g]*H._zero_sum(q[(first(b.step_white)+(g-1)*(K-2)):(first(b.step_white)+g*(K-2)-1)]) for g in 1:G]...),
        response=Diagonal(response_sd)*cr.L*reshape(q[b.response_white],2,O),
        beta=q[b.beta],response_sd,person_correlation=cp.R[1,2],response_correlation=cr.R[1,2],
        correlation_status=(;person=(;cp.partial_saturation,cp.diagonal_underflow),
            response=(;cr.partial_saturation,cr.diagonal_underflow)),
        correlation_logprior=cp.logdensity_kernel+cr.logdensity_kernel+sum(t.log_normalizer))
end
function logprior(t::Target,q::AbstractVector{<:Real},v=coordinates(t,q))
    return sum(B._normal_logpdf(q[i]-t.mean[i],t.sd[i]) for i in eachindex(t.mean))+
        v.correlation_logprior
end
function row_location(t,v,n)
    ix=t.indices;c=ix.criterion[n]
    return v.theta[c,ix.person[n]]-v.task[c,ix.task[n]]-v.rater[ix.rater[n],c]+
        v.response[c,ix.response_id[n]]+dot(view(t.X,n,:),v.beta)
end
function likelihood(t,q; pointwise=nothing,logprobs=nothing,v=coordinates(t,q),reject_nonfinite=false)
    K=t.sizes[5]
    a=zeros(eltype(v.theta),K);total=zero(eltype(a))
    for n in eachindex(t.data.score)
        location=row_location(t,v,n);g=t.indices.threshold_group[t.indices.criterion[n]]
        a[1]=0
        for k in 2:K; a[k]=a[k-1]+location-v.steps[k-1,g];end
        if !all(isfinite,a)
            reject_nonfinite && return oftype(total,-Inf)
            throw(ArgumentError("nonfinite category logits"))
        end
        a.-=maximum(a);a.-=B._logsumexp(a)
        value=a[t.data.score[n]+1];total+=value
        pointwise===nothing || (pointwise[n]=value)
        logprobs===nothing || (logprobs[n,:]=a)
    end
    return total
end
function L.logdensity(t::Target,q::AbstractVector{<:Real})
    length(q)==L.dimension(t) || throw(ArgumentError("invalid parameter dimension"))
    rejected=oftype(zero(eltype(q)),-Inf)
    all(isfinite,q) || return rejected
    v=coordinates(t,q)
    prior=logprior(t,q,v)
    isfinite(prior) || return rejected
    value=prior+likelihood(t,q;v,reject_nonfinite=true)
    return isfinite(value) ? value : rejected
end
include("joint_rating_gradient.jl")

function category_logprobs(t::Target,q::AbstractVector{<:Real})
    out=zeros(promote_type(Float64,eltype(q)),length(t.data.rows),t.sizes[5])
    likelihood(t,q;logprobs=out);return out
end
function pointwise_loglikelihood(t::Target,q::AbstractVector{<:Real})
    out=zeros(promote_type(Float64,eltype(q)),length(t.data.rows))
    likelihood(t,q;pointwise=out);return out
end

function record_body(t::Target)
    return deepcopy((;schema=SCHEMA,rows=t.data.rows,criteria=t.data.criteria,
        predictor_names=t.predictor_names,predictor_values=t.X,prior=t.prior,
        likelihood_scale=1.0,dimensions=2,person_marginal_sd=:fixed_one,
        coordinates=:white_rater_steps_person_response_and_log_response_sd_fisher_z,
        rater_population_covariance=:not_estimated,assessment_event_effect=:none,
        predictor_identification=:unassessed_beyond_X_rank,posterior_fitting=:not_implemented))
end
function from_record(record)
    rows=[merge(row,NamedTuple{Tuple(record.predictor_names)}(Tuple(record.predictor_values[n,:])))
        for (n,row) in enumerate(record.rows)]
    return Target(rows;criteria=record.criteria,prior=record.prior,predictor_columns=record.predictor_names)
end
function target_record(t::Target)
    record=record_body(t);canonical=from_record(record)
    all(f -> isequal(getfield(t,f),getfield(canonical,f)),fieldnames(typeof(t))) ||
        throw(ArgumentError("target input or derived layout changed; reconstruct the target"))
    return record
end
function restore_target(record; expected_identity)
    B._cache_hash(record)==expected_identity && record.schema==SCHEMA ||
        throw(ArgumentError("target record identity or schema mismatch"))
    t=from_record(record)
    B._cache_hash(record_body(t))==expected_identity || throw(ArgumentError("unsupported target record"))
    return t
end

function stan_data(t::Target)
    target_record(t)
    P,T,R,O,K,G,F=t.sizes;ix=t.indices;p=t.prior
    return deepcopy((;P,T,R,O,K,G,F,N=length(t.data.rows),person=ix.person,task=ix.task,
        rater=ix.rater,response=ix.response_id,criterion=ix.criterion,y=t.data.score.+1,
        threshold_group=ix.threshold_group,X=[collect(r) for r in eachrow(t.X)],
        task_sd=p.task_sd,rater_sd=collect(p.rater_sd),
        step_sd=collect(p.step_sd),response_log_sd_mean=collect(p.response_log_sd_mean),
        response_log_sd_sd=collect(p.response_log_sd_sd),beta_sd=collect(p.beta_sd),
        lkj_eta=[p.person_lkj_eta,p.response_lkj_eta]))
end
end
