# bayesian_fit.jl -- minimal Bayesian MFRM fitting for the v0.1 design scaffold.

using Random

const LOG2PI_BAYES = log(2 * pi)

"""
    MFRMPrior(; person_sd = 1.5, rater_sd = 1.0, item_sd = 1.0, step_sd = 1.0)

Independent zero-centered normal priors for the identified minimal MFRM
parameter vector returned by `getdesign`. The scales apply to person, rater,
item, and threshold-step blocks after the current reference and sum-to-zero
constraints have been imposed.
"""
struct MFRMPrior
    person_sd::Float64
    rater_sd::Float64
    item_sd::Float64
    step_sd::Float64

    function MFRMPrior(person_sd::Real, rater_sd::Real, item_sd::Real, step_sd::Real)
        values = (person_sd, rater_sd, item_sd, step_sd)
        all(x -> isfinite(x) && x > 0, values) ||
            throw(ArgumentError("all prior standard deviations must be finite and positive"))
        return new(Float64(person_sd), Float64(rater_sd), Float64(item_sd), Float64(step_sd))
    end
end

MFRMPrior(; person_sd::Real = 1.5,
            rater_sd::Real = 1.0,
            item_sd::Real = 1.0,
            step_sd::Real = 1.0) =
    MFRMPrior(person_sd, rater_sd, item_sd, step_sd)

"""
    MFRMFit

Posterior draws and sampler metadata returned by `fit` for the minimal MFRM
design scaffold. `draws` is a matrix with one posterior draw per row and one
identified design parameter per column, in `fit.design.parameter_names` order.
"""
struct MFRMFit
    design::FacetDesign
    prior::MFRMPrior
    draws::Matrix{Float64}
    log_posterior::Vector{Float64}
    acceptance_rate::Float64
    backend::Symbol
    sampler::Symbol
    warmup::Int
    step_size::Float64
end

function Base.show(io::IO, fit::MFRMFit)
    print(io, "MFRMFit(",
        size(fit.draws, 1), " draw(s), ",
        size(fit.draws, 2), " parameter(s), backend = :",
        fit.backend, ", sampler = :", fit.sampler, ", acceptance_rate = ",
        round(fit.acceptance_rate; digits = 3), ")")
end

@inline function _normal_logpdf(x::Float64, sd::Float64)
    z = x / sd
    return -log(sd) - 0.5 * (LOG2PI_BAYES + z * z)
end

function _in_range(range::UnitRange{Int}, index::Int)
    return first(range) <= index <= last(range)
end

function _prior_sd(design::FacetDesign, prior::MFRMPrior, index::Int)
    _in_range(design.blocks[:person], index) && return prior.person_sd
    _in_range(design.blocks[:rater], index) && return prior.rater_sd
    _in_range(design.blocks[:item], index) && return prior.item_sd
    _in_range(design.blocks[:thresholds], index) && return prior.step_sd
    throw(ArgumentError("parameter index $index is not covered by any design block"))
end

function _check_parameter_vector(design::FacetDesign, params::AbstractVector)
    expected = length(design.parameter_names)
    length(params) == expected ||
        throw(ArgumentError("parameter vector has length $(length(params)); expected $expected"))
    all(x -> isfinite(Float64(x)), params) ||
        throw(ArgumentError("parameter vector contains non-finite values"))
    return nothing
end

"""
    logposterior(design::FacetDesign, params, prior = MFRMPrior())

Evaluate the log posterior for the minimal additive MFRM/RSM/PCM design:
the sum of `pointwise_loglikelihood(design, params)` plus independent normal
priors from `prior` on the identified parameter vector.
"""
function logposterior(design::FacetDesign, params::AbstractVector, prior::MFRMPrior = MFRMPrior())
    _check_parameter_vector(design, params)
    lp = sum(pointwise_loglikelihood(design, params))
    for index in eachindex(params)
        lp += _normal_logpdf(Float64(params[index]), _prior_sd(design, prior, index))
    end
    return lp
end

logposterior(spec::FacetSpec, params::AbstractVector, prior::MFRMPrior = MFRMPrior()) =
    logposterior(getdesign(spec), params, prior)

function _fit_initial_params(design::FacetDesign, init)
    nparams = length(design.parameter_names)
    if init === nothing
        return zeros(Float64, nparams)
    end
    length(init) == nparams ||
        throw(ArgumentError("init has length $(length(init)); expected $nparams"))
    out = Float64.(collect(init))
    all(isfinite, out) || throw(ArgumentError("init contains non-finite values"))
    return out
end

"""
    fit(spec_or_design; prior = MFRMPrior(), backend = :julia, ndraws = 1000,
        warmup = 1000, step_size = 0.05, init = nothing,
        rng = Random.default_rng())

Fit the current minimal Bayesian MFRM/RSM/PCM scaffold with a random-walk
Metropolis sampler when `backend = :julia`. This first fitting path is intended
for small validation examples and API stabilization; it is not a production
HMC/NUTS sampler. Stan/Turing/AdvancedHMC backends are planned but not exposed
by this API yet.
"""
function fit(design::FacetDesign;
        prior::MFRMPrior = MFRMPrior(),
        backend::Symbol = :julia,
        ndraws::Int = 1000,
        warmup::Int = 1000,
        step_size::Real = 0.05,
        init = nothing,
        rng::AbstractRNG = Random.default_rng())
    backend === :julia ||
        throw(ArgumentError("only backend = :julia is currently supported; Stan/Turing/AdvancedHMC backends are planned"))
    ndraws >= 1 || throw(ArgumentError("ndraws must be positive"))
    warmup >= 0 || throw(ArgumentError("warmup must be non-negative"))
    isfinite(step_size) && step_size > 0 ||
        throw(ArgumentError("step_size must be finite and positive"))

    nparams = length(design.parameter_names)
    current = _fit_initial_params(design, init)
    current_lp = logposterior(design, current, prior)
    isfinite(current_lp) || throw(ArgumentError("initial parameter vector has non-finite log posterior"))

    draws = Matrix{Float64}(undef, ndraws, nparams)
    logps = Vector{Float64}(undef, ndraws)
    proposal = similar(current)
    total = warmup + ndraws
    accepted = 0
    draw_index = 0
    step = Float64(step_size)

    for iter in 1:total
        @inbounds for j in 1:nparams
            proposal[j] = current[j] + step * randn(rng)
        end
        proposal_lp = logposterior(design, proposal, prior)
        if log(rand(rng)) < proposal_lp - current_lp
            current .= proposal
            current_lp = proposal_lp
            accepted += 1
        end
        if iter > warmup
            draw_index += 1
            draws[draw_index, :] .= current
            logps[draw_index] = current_lp
        end
    end

    return MFRMFit(design, prior, draws, logps, accepted / total, backend,
        :random_walk_metropolis, warmup, step)
end

fit(spec::FacetSpec; kwargs...) = fit(getdesign(spec); kwargs...)

function _column_mean(xs::AbstractVector{<:Real})
    isempty(xs) && return NaN
    return sum(Float64, xs) / length(xs)
end

function _column_sd(xs::AbstractVector{<:Real}, mean::Float64)
    n = length(xs)
    n <= 1 && return NaN
    ss = 0.0
    for x in xs
        d = Float64(x) - mean
        ss += d * d
    end
    return sqrt(ss / (n - 1))
end

function _quantile_sorted(sorted::Vector{Float64}, p::Real)
    0 <= p <= 1 || throw(ArgumentError("quantile probabilities must be in [0, 1]"))
    n = length(sorted)
    n == 0 && return NaN
    n == 1 && return sorted[1]
    pos = 1 + (n - 1) * Float64(p)
    lo = floor(Int, pos)
    hi = ceil(Int, pos)
    lo == hi && return sorted[lo]
    w = pos - lo
    return (1 - w) * sorted[lo] + w * sorted[hi]
end

"""
    posterior_summary(fit::MFRMFit; lower = 0.025, upper = 0.975)

Summarize posterior draws for each identified design parameter. Returns a
vector of named tuples with parameter name, mean, standard deviation, median,
and lower/upper interval endpoints.
"""
function posterior_summary(fit::MFRMFit; lower::Real = 0.025, upper::Real = 0.975)
    0 <= lower < 0.5 || throw(ArgumentError("lower must be in [0, 0.5)"))
    0.5 < upper <= 1 || throw(ArgumentError("upper must be in (0.5, 1]"))
    rows = NamedTuple[]
    for j in axes(fit.draws, 2)
        vals = Float64.(fit.draws[:, j])
        sorted = sort(vals)
        m = _column_mean(vals)
        push!(rows, (;
            parameter = fit.design.parameter_names[j],
            mean = m,
            sd = _column_sd(vals, m),
            median = _quantile_sorted(sorted, 0.5),
            lower = _quantile_sorted(sorted, lower),
            upper = _quantile_sorted(sorted, upper),
            lower_probability = Float64(lower),
            upper_probability = Float64(upper),
        ))
    end
    return rows
end

"""
    pointwise_loglikelihood_matrix(fit::MFRMFit)
    pointwise_loglikelihood_matrix(design::FacetDesign, draws)

Evaluate a draws-by-observations pointwise log-likelihood matrix for posterior
summaries, posterior predictive checks, and future model-comparison helpers.
"""
function pointwise_loglikelihood_matrix(design::FacetDesign, draws::AbstractMatrix)
    size(draws, 2) == length(design.parameter_names) ||
        throw(ArgumentError("draws has $(size(draws, 2)) column(s); expected $(length(design.parameter_names))"))
    out = Matrix{Float64}(undef, size(draws, 1), design.spec.data.n)
    for i in axes(draws, 1)
        out[i, :] .= pointwise_loglikelihood(design, @view draws[i, :])
    end
    return out
end

pointwise_loglikelihood_matrix(fit::MFRMFit) =
    pointwise_loglikelihood_matrix(fit.design, fit.draws)

function _draw_indices(fit::MFRMFit, ndraws::Union{Nothing,Int}, rng::AbstractRNG)
    total = size(fit.draws, 1)
    if ndraws === nothing
        return collect(1:total)
    end
    ndraws >= 1 || throw(ArgumentError("ndraws must be positive"))
    return rand(rng, 1:total, ndraws)
end

function _validate_draw_indices(fit::MFRMFit, draw_indices)
    indices = collect(Int, draw_indices)
    isempty(indices) && throw(ArgumentError("draw_indices must not be empty"))
    total = size(fit.draws, 1)
    all(index -> 1 <= index <= total, indices) ||
        throw(ArgumentError("draw_indices are out of bounds"))
    return indices
end

function _posterior_draw_indices(fit::MFRMFit, ndraws::Union{Nothing,Int}, draw_indices, rng::AbstractRNG)
    if draw_indices !== nothing && ndraws !== nothing
        throw(ArgumentError("pass either ndraws or draw_indices, not both"))
    end
    return draw_indices === nothing ?
        _draw_indices(fit, ndraws, rng) :
        _validate_draw_indices(fit, draw_indices)
end

function _category_probabilities!(probs::AbstractVector{Float64},
        design::FacetDesign,
        params::AbstractVector,
        row::Int)
    data = design.spec.data
    person_block = design.blocks[:person]
    rater_block = design.blocks[:rater]
    item_block = design.blocks[:item]

    person_value = Float64(params[person_block[data.person[row]]])
    rater_value = _reference_value(params, rater_block, data.rater[row])
    item_value = _reference_value(params, item_block, data.item[row])
    location = person_value - rater_value - item_value

    max_eta = -Inf
    for category in eachindex(probs)
        eta = (category - 1) * location -
            _step_sum(design, params, data.item[row], category)
        probs[category] = eta
        max_eta = max(max_eta, eta)
    end

    denom = 0.0
    for category in eachindex(probs)
        p = exp(probs[category] - max_eta)
        probs[category] = p
        denom += p
    end
    probs ./= denom
    return probs
end

function _sample_category_index(rng::AbstractRNG, probs::AbstractVector{Float64})
    u = rand(rng)
    cumulative = 0.0
    for category in eachindex(probs)
        cumulative += probs[category]
        u <= cumulative && return category
    end
    return lastindex(probs)
end

"""
    posterior_predict(fit::MFRMFit; ndraws = nothing, draw_indices = nothing,
        rng = Random.default_rng())

Generate replicated score matrices from posterior draws. The returned matrix
has one replicated dataset per row and one rating observation per column, with
entries on the original integer score scale.
"""
function posterior_predict(fit::MFRMFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    data = fit.design.spec.data
    K = length(data.category_levels)
    replicated = Matrix{Int}(undef, length(indices), data.n)
    probs = zeros(Float64, K)

    for (replication, draw_index) in pairs(indices)
        params = @view fit.draws[draw_index, :]
        for row in 1:data.n
            _category_probabilities!(probs, fit.design, params, row)
            category = _sample_category_index(rng, probs)
            replicated[replication, row] = data.category_levels[category]
        end
    end
    return replicated
end

function _mean_score(scores::AbstractVector{<:Integer})
    isempty(scores) && return NaN
    return sum(Float64, scores) / length(scores)
end

function _category_proportions(scores::AbstractVector{<:Integer}, levels::AbstractVector{Int})
    counts = zeros(Float64, length(levels))
    level_index = Dict(level => index for (index, level) in pairs(levels))
    for score in scores
        counts[level_index[score]] += 1
    end
    if !isempty(scores)
        counts ./= length(scores)
    end
    return counts
end

function _facet_mean_scores(scores::AbstractVector{<:Integer},
        index::AbstractVector{Int},
        levels::AbstractVector)
    sums = zeros(Float64, length(levels))
    counts = zeros(Int, length(levels))
    for row in eachindex(scores)
        facet_index = index[row]
        sums[facet_index] += scores[row]
        counts[facet_index] += 1
    end
    return [counts[i] == 0 ? NaN : sums[i] / counts[i] for i in eachindex(levels)]
end

function _predictive_summary(data::FacetData, scores::AbstractVector{<:Integer})
    length(scores) == data.n ||
        throw(ArgumentError("scores has length $(length(scores)); expected $(data.n)"))
    return (;
        mean_score = _mean_score(scores),
        category_proportions = _category_proportions(scores, data.category_levels),
        rater_mean = _facet_mean_scores(scores, data.rater, data.rater_levels),
        item_mean = _facet_mean_scores(scores, data.item, data.item_levels),
    )
end

function _replicated_summaries(data::FacetData, replicated::AbstractMatrix{<:Integer})
    nrep = size(replicated, 1)
    ncategory = length(data.category_levels)
    nrater = length(data.rater_levels)
    nitem = length(data.item_levels)
    mean_score = Vector{Float64}(undef, nrep)
    category_proportions = Matrix{Float64}(undef, nrep, ncategory)
    rater_mean = Matrix{Float64}(undef, nrep, nrater)
    item_mean = Matrix{Float64}(undef, nrep, nitem)

    for replication in 1:nrep
        summary = _predictive_summary(data, vec(replicated[replication, :]))
        mean_score[replication] = summary.mean_score
        category_proportions[replication, :] .= summary.category_proportions
        rater_mean[replication, :] .= summary.rater_mean
        item_mean[replication, :] .= summary.item_mean
    end
    return (;
        mean_score,
        category_proportions,
        rater_mean,
        item_mean,
    )
end

"""
    posterior_predictive_check(fit::MFRMFit; ndraws = nothing,
        draw_indices = nothing, rng = Random.default_rng())

Generate posterior predictive replicated scores and compact observed-vs-
replicated summaries for the minimal MFRM design. The summary currently covers
overall mean score, category proportions, rater-level mean scores, and
item-level mean scores.
"""
function posterior_predictive_check(fit::MFRMFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    replicated = posterior_predict(fit; draw_indices = indices, rng)
    data = fit.design.spec.data
    return (;
        observed = _predictive_summary(data, data.score),
        replicated = _replicated_summaries(data, replicated),
        replicated_scores = replicated,
        draw_indices = indices,
        category_levels = copy(data.category_levels),
        rater_levels = copy(data.rater_levels),
        item_levels = copy(data.item_levels),
    )
end
