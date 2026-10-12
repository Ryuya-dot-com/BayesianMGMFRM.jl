"""Opt-in four-facet density prototype; no sampler or public fit API.

The input FacetSpec supplies data, categories and pure Q. This new target owns
its own four-facet constraints and priors; it is not the input spec's old model.
"""
module FourFacetSharedTarget
import BayesianMGMFRM as B
import LogDensityProblems as L
export SharedTaskTarget, target_record, restore_target, pointwise_loglikelihood, category_logprobs, logprior

const SCALE_NAMES = (:person_sd, :task_kernel_sd, :rater_kernel_sd,
    :criterion_kernel_sd, :step_kernel_sd, :shared_sd_scale)

struct SharedTaskTarget{P,BT}
    input_spec::B.FacetSpec
    prior::P
    blocks::BT
    sizes::NTuple{5,Int} # persons, tasks, raters, criteria, categories
    task::Vector{Int}
    group::Vector{Int}
    criterion_groups::NTuple{2,Vector{Int}}
    dimension::Vector{Int}
end

function SharedTaskTarget(spec::B.FacetSpec; prior::NamedTuple, category_direction::Symbol)
    B._require_current_facet_spec(spec, "SharedTaskTarget")
    spec.family === :mfrm && spec.dimensions == 2 && spec.thresholds === :partial_credit ||
        throw(ArgumentError("prototype requires a 2D fixed-coefficient partial-credit input spec"))
    isempty(spec.anchors) && isempty(spec.validation_bias_terms) ||
        throw(ArgumentError("anchors and bias terms are not supported"))
    category_direction === :higher_is_more ||
        throw(ArgumentError("declare consistently oriented categories as :higher_is_more"))
    Set(keys(prior)) == Set(SCALE_NAMES) || throw(ArgumentError("declare exactly $SCALE_NAMES"))
    all(v -> v isa Real && !(v isa Bool) && isfinite(v) && v > 0, values(prior)) ||
        throw(ArgumentError("prior scales must be finite positive real numbers"))
    checked_prior = NamedTuple{SCALE_NAMES}(Tuple(Float64(prior[k]) for k in SCALE_NAMES))
    all(v -> isfinite(v) && v > 0, checked_prior) || throw(ArgumentError("scales exceed Float64 range"))
    input = deepcopy(spec)
    data = input.data
    all(k -> haskey(data.optional, k), (:task, :response_id)) ||
        throw(ArgumentError("explicit task and globally unique response_id metadata are required"))
    P, T, R, C, K = length(data.person_levels), length(data.optional_levels[:task]),
        length(data.rater_levels), length(data.item_levels), length(data.category_levels)
    P >= 2 && T >= 2 && R >= 2 && K >= 2 ||
        throw(ArgumentError("prototype requires at least two persons, tasks, raters and categories"))
    q = input.q_matrix
    q !== nothing && all(==(1), sum(q; dims=2)) || throw(ArgumentError("pure Q is required"))
    groups = Tuple(findall(q[:,d]) for d in 1:2)
    all(g -> length(g) >= 2, groups) || throw(ArgumentError("each dimension needs at least two criteria"))
    task = copy(data.optional[:task])
    cells = collect(zip(data.person, task, data.rater, data.item))
    data.n == P*T*R*C && length(unique(cells)) == data.n ||
        throw(ArgumentError("prototype requires one rating per cell in the complete person × task × rater × criterion design"))
    group = [(p-1)*T+t for (p,t) in zip(data.person,task)]
    responses = data.optional[:response_id]
    length(unique(zip(group,responses))) == P*T && length(unique(responses)) == P*T ||
        throw(ArgumentError("exactly one distinct response per person × task is required"))
    counts = (; theta=2P, task=T-1, rater=R-1, criterion=C-2,
        steps=C*(K-2), z=P*T, log_sigma=1)
    offset = 0
    ranges = map(values(counts)) do count
        r = (offset+1):(offset+count)
        offset += count
        r
    end
    blocks = NamedTuple{keys(counts)}(ranges)
    return SharedTaskTarget(input, checked_prior, blocks, (P,T,R,C,K), task, group,
        groups, Int[findfirst(q[c,:]) for c in 1:C])
end

L.dimension(target::SharedTaskTarget) = last(target.blocks.log_sigma)
L.capabilities(::Type{<:SharedTaskTarget}) = L.LogDensityOrder{0}()

function _check(target, x)
    length(x) == L.dimension(target) || throw(ArgumentError("wrong parameter-vector length"))
    all(isfinite, x) || throw(ArgumentError("parameters must be finite"))
end

# Helmert map in linear time and space; its columns are orthonormal contrasts.
function _zero_sum(v)
    out = zeros(typeof(zero(eltype(v)) + 0.0), length(v)+1)
    tail = zero(eltype(out))
    for j in length(v):-1:1
        value = v[j]/sqrt(j*(j+1))
        out[j+1] = tail-j*value
        tail += value
    end
    out[1] = tail
    return out
end

function _components(target, x)
    b = target.blocks
    P,T,R,C,K = target.sizes
    theta = reshape(view(x,b.theta),2,P)
    task, rater = _zero_sum(view(x,b.task)), _zero_sum(view(x,b.rater))
    criterion = zeros(typeof(first(x)+0.0),C)
    offset = first(b.criterion)
    for group in target.criterion_groups
        count = length(group)-1
        criterion[group] = _zero_sum(view(x,offset:(offset+count-1)))
        offset += count
    end
    steps = hcat([_zero_sum(view(x,(first(b.steps)+(c-1)*(K-2)):(first(b.steps)+c*(K-2)-1)))
                  for c in 1:C]...)
    sigma = exp(x[first(b.log_sigma)])
    shared = sigma .* view(x,b.z)
    return (; theta, task, rater, criterion, steps, sigma, shared)
end

function logprior(target::SharedTaskTarget, x::AbstractVector{<:Real})
    _check(target,x)
    b, p = target.blocks, target.prior
    value = zero(first(x)+0.0)
    for (block,sd) in ((b.theta,p.person_sd),(b.task,p.task_kernel_sd),
                      (b.rater,p.rater_kernel_sd),(b.criterion,p.criterion_kernel_sd),
                      (b.steps,p.step_kernel_sd),(b.z,1.0))
        value -= length(block)*(log(sd)+log(2pi)/2)
        for j in block
            value -= (x[j]/sd)^2/2
        end
    end
    y = x[first(b.log_sigma)]
    # HalfNormal(A) on sigma, in d log(sigma); z already has a standard normal prior.
    return value + log(2/pi)/2-log(p.shared_sd_scale)-(exp(y)/p.shared_sd_scale)^2/2+y
end

function _loglikelihood(target, x; pointwise=nothing, logprobs=nothing)
    _check(target,x)
    v = _components(target,x)
    data, K = target.input_spec.data, target.sizes[5]
    eta = zeros(typeof(first(x)+0.0),K)
    total = zero(eltype(eta))
    for n in 1:data.n
        c = data.item[n]
        location = v.theta[target.dimension[c],data.person[n]]-v.task[target.task[n]]-
            v.rater[data.rater[n]]-v.criterion[c]+v.shared[target.group[n]]
        eta[1] = zero(eltype(eta))
        for k in 2:K
            eta[k] = eta[k-1]+location-v.steps[k-1,c]
        end
        all(isfinite, eta) || throw(ArgumentError("nonfinite category logits"))
        eta .-= maximum(eta)
        z = B._logsumexp(eta)
        value = eta[data.category[n]]-z
        total += value
        pointwise === nothing || (pointwise[n] = value)
        if logprobs !== nothing
            for k in 1:K
                logprobs[n,k] = eta[k]-z
            end
        end
    end
    return total
end

function L.logdensity(target::SharedTaskTarget, x::AbstractVector{<:Real})
    prior = logprior(target,x)
    isfinite(prior) || return prior
    return prior + _loglikelihood(target,x)
end

"""Conditional observation likelihood at ONE supplied parameter vector; no prior terms."""
function pointwise_loglikelihood(target::SharedTaskTarget, x::AbstractVector{<:Real})
    out = zeros(typeof(zero(eltype(x))+0.0), target.input_spec.data.n)
    _loglikelihood(target,x; pointwise=out)
    return out
end

"""Training-row category log probabilities at one parameter vector, not a fit prediction API."""
function category_logprobs(target::SharedTaskTarget, x::AbstractVector{<:Real})
    out = zeros(typeof(zero(eltype(x))+0.0), target.input_spec.data.n, target.sizes[5])
    _loglikelihood(target,x; logprobs=out)
    return out
end

function target_record(target::SharedTaskTarget)
    canonical = SharedTaskTarget(target.input_spec; prior=target.prior, category_direction=:higher_is_more)
    all(field -> isequal(getfield(target,field),getfield(canonical,field)),
        (:blocks,:sizes,:task,:group,:criterion_groups,:dimension)) ||
        throw(ArgumentError("derived target layout changed; reconstruct the target"))
    return deepcopy((; schema="bayesianmgmfrm.four_facet_shared_task_target.prototype.v1",
        input_spec=target.input_spec,
        input_identity=B.design_identity(B.getdesign(target.input_spec;preview=true)),
        prior=target.prior, category_direction=:higher_is_more,
        family=:four_facet_fixed_q_shared_task, likelihood_scale=1.0,
        parameter_space=:orthonormal_locations_standard_normal_shared_log_sd,
        location=:task_rater_and_within_dimension_criterion_zero_sum,
        steps=:within_criterion_zero_sum, latent_correlation=:identity_fixed,
        shared_effect=:person_task, shared_prior=:normal_zero_mean,
        shared_scale_prior=:half_normal, repeated_responses=false,
        design_scope=:complete_crossed_2d_pure_q,
        new_level_prediction=:not_implemented, posterior_fitting=:not_implemented))
end

function restore_target(record::NamedTuple; expected_identity::AbstractString)
    B._cache_hash(record) == expected_identity || throw(ArgumentError("target identity mismatch"))
    target = SharedTaskTarget(record.input_spec; prior=record.prior,
        category_direction=record.category_direction)
    B._cache_hash(target_record(target)) == expected_identity || throw(ArgumentError("unsupported target contract"))
    return target
end
end
