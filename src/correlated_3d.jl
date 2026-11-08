"""Experimental fixed-Q three-dimensional correlated MGMFRM workflow."""
module Correlated3D
using BayesianMGMFRM, LinearAlgebra
import LogDensityProblems as L
include("correlated_3d_lkj.jl")
const B = BayesianMGMFRM
const C = MGMFRMLKJCholeskyCandidate

struct Target{T}
    independent::T
    eta::Float64
    correlation_log_normalizer::Float64
end

"""
    Target(spec; scales, lkj_eta)

Compose the normalized exchangeable MGMFRM prior with a three-dimensional
person correlation. Require pure fixed Q, two items per dimension, every person
observed in all dimensions, at least two raters and at least three categories.
All six scales are explicit; person_sd must be 1 (fixed population scale).
The last three raw coordinates are row-wise Cholesky partial correlations on
the Fisher-z scale, not three independently chosen pairwise correlations.
Construction validates the model only; call generate, fit and report explicitly.
"""
function Target(spec; scales::NamedTuple, lkj_eta::Real)
    spec.dimensions == 3 || throw(ArgumentError("this target requires exactly three dimensions"))
    !(lkj_eta isa Bool) && isfinite(lkj_eta) && lkj_eta > 0 ||
        throw(ArgumentError("lkj_eta must be a fixed finite positive real"))
    base = B._MGMFRMNormalizedPriorLogDensity(spec; prior_model=:exchangeable, scales)
    scales.person_sd == 1 || throw(ArgumentError("person marginal SD is fixed at one"))
    Q = base.base.design.spec.q_matrix
    all(sum(Q;dims=2).==1) || throw(ArgumentError("one active dimension per item is required"))
    all(sum(Q;dims=1).>=2) || throw(ArgumentError("at least two pure items per dimension are required"))
    data = base.base.design.spec.data
    length(data.rater_levels)>=2 && length(data.category_levels)>=3 ||
        throw(ArgumentError("this first domain requires at least two raters and three categories"))
    observed = falses(length(data.person_levels),3)
    for n in 1:data.n
        observed[data.person[n],:] .|= Q[data.item[n],:]
    end
    all(observed) || throw(ArgumentError("every person must be observed in all three dimensions"))
    eta = Float64(lkj_eta)
    isfinite(eta) && eta > 0 || throw(ArgumentError("lkj_eta is not representable as positive Float64"))
    logc = -sum(B.SpecialFunctions.logbeta(.5,eta+(3-j-1)/2)
        for i in 2:3 for j in 1:(i-1))
    isfinite(logc) || throw(ArgumentError("nonfinite LKJ normalizer"))
    Target(base,eta,logc)
end

L.dimension(t::Target) = L.dimension(t.independent)+3
L.capabilities(::Type{<:Target}) = L.LogDensityOrder{0}()
initial(t::Target) = [B.initial_params(t.independent);zeros(3)]

function coordinates(t::Target, q::AbstractVector{<:Real})
    length(q)==L.dimension(t) && all(isfinite,q) || throw(ArgumentError("invalid parameter vector"))
    n=L.dimension(t.independent)
    state=C.correlation_state(view(q,n+1:n+3),3;eta=t.eta)
    (;raw=view(q,1:n),state)
end

function logprior(t::Target, q::AbstractVector{<:Real})
    raw,state = coordinates(t,q)
    people=t.independent.base.blueprint.blocks[:person]
    theta=reshape(view(raw,people),3,:)
    white=LowerTriangular(state.L)\theta
    # Replace only independent unit-normal person density; other normalized
    # zero-sum priors retain their original free-coordinate measure.
    correction=(sum(abs2,theta)-sum(abs2,white))/2-size(theta,2)*sum(log,diag(state.L))
    B.logprior(t.independent,raw)+correction+state.logdensity_kernel+t.correlation_log_normalizer
end

function L.logdensity(t::Target,q::AbstractVector{<:Real})
    raw,_=coordinates(t,q)
    B._source_fixture_loglikelihood(t.independent.base,raw)+logprior(t,q)
end

"""Full category log probabilities at fixed coordinates; no predictive draws."""
function category_logprobs(t::Target,q::AbstractVector{<:Real})
    raw,_=coordinates(t,q)
    design=t.independent.base.design
    direct=B._guarded_generalized_direct_params(t.independent.base,raw)
    loading_indices=B._mgmfrm_source_loading_index_matrix(design)
    result=zeros(eltype(direct),design.spec.data.n,length(design.spec.data.category_levels))
    for n in axes(result,1)
        row=view(result,n,:)
        B._mgmfrm_source_linear_predictors!(row,design,direct,n,loading_indices)
        row .-= B._logsumexp(row)
    end
    result
end

"""Named population correlations; not sample correlations of fitted abilities."""
function correlations(t::Target,q::AbstractVector{<:Real})
    _,state=coordinates(t,q)
    labels=t.independent.base.design.spec.dimension_labels
    [(;dimension_1=labels[j],dimension_2=labels[i],correlation=state.R[i,j])
        for i in 2:3 for j in 1:(i-1)]
end

stan_data(t::Target)=merge(B._cmdstan_mgmfrm_data(t.independent),(;lkj_eta=t.eta))

"""Semantic identity of the centered target, including its explicit normalized prior."""
function contract(t::Target)
    spec=t.independent.base.design.spec
    record=(;schema="bayesianmgmfrm.correlated_3d_target_contract.v1",
        independent_target_identity=B._mgmfrm_normalized_prior_identity(t.independent),
        prior=B._mgmfrm_normalized_prior_record(t.independent),lkj_eta=t.eta,
        dimension_labels=copy(spec.dimension_labels),q_matrix=copy(spec.q_matrix),
        person_marginal_sd=1.,threshold_owner=:item,likelihood_multiplier=1.7,
        coordinates=:base_raw_then_rowwise_cholesky_partial_fisher_z,
        fit_ready=true,public_api=true,scientific_acceptance=false)
    merge(record,(;target_identity=B._cache_hash(record)))
end
include("correlated_3d_workflow.jl")
end
