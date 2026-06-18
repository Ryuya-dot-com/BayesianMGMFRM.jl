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

function _logmeanexp(values::AbstractVector{<:Real})
    isempty(values) && throw(ArgumentError("values must not be empty"))
    vals = Float64.(values)
    all(isfinite, vals) || throw(ArgumentError("values contain non-finite entries"))
    max_value = maximum(vals)
    return max_value + log(sum(exp(value - max_value) for value in vals) / length(vals))
end

function _sample_variance(values::AbstractVector{<:Real})
    n = length(values)
    n >= 2 || throw(ArgumentError("at least two posterior draws are required"))
    mean_value = _column_mean(values)
    ss = 0.0
    for value in values
        d = Float64(value) - mean_value
        ss += d * d
    end
    return ss / (n - 1)
end

function _pointwise_se(values::AbstractVector{<:Real})
    n = length(values)
    n <= 1 && return NaN
    return sqrt(n * _sample_variance(values))
end

"""
    waic(fit::MFRMFit; ndraws = nothing, draw_indices = nothing,
        rng = Random.default_rng())
    waic(design::FacetDesign, draws)
    waic(loglik::AbstractMatrix)

Compute the widely applicable information criterion (WAIC) from posterior
pointwise log-likelihood draws. The log-likelihood matrix must have dimensions
draws-by-observations. The returned named tuple includes `elpd_waic`,
`p_waic`, `lppd`, `waic`, standard errors, and pointwise components.
"""
function waic(loglik::AbstractMatrix)
    n_draws, n_observations = size(loglik)
    n_draws >= 2 || throw(ArgumentError("WAIC requires at least two posterior draws"))
    n_observations >= 1 || throw(ArgumentError("WAIC requires at least one observation"))
    all(value -> isfinite(Float64(value)), loglik) ||
        throw(ArgumentError("loglik contains non-finite values"))

    point_lppd = Vector{Float64}(undef, n_observations)
    point_p_waic = Vector{Float64}(undef, n_observations)
    point_elpd = Vector{Float64}(undef, n_observations)
    point_waic = Vector{Float64}(undef, n_observations)

    for observation in 1:n_observations
        values = @view loglik[:, observation]
        point_lppd[observation] = _logmeanexp(values)
        point_p_waic[observation] = _sample_variance(values)
        point_elpd[observation] = point_lppd[observation] - point_p_waic[observation]
        point_waic[observation] = -2 * point_elpd[observation]
    end

    lppd = sum(point_lppd)
    p_waic = sum(point_p_waic)
    elpd_waic = sum(point_elpd)
    waic_value = sum(point_waic)
    high_variance_count = count(>(0.4), point_p_waic)
    return (;
        criterion = :waic,
        elpd_waic,
        p_waic,
        lppd,
        waic = waic_value,
        se_elpd_waic = _pointwise_se(point_elpd),
        se_waic = _pointwise_se(point_waic),
        pointwise = (;
            elpd_waic = point_elpd,
            p_waic = point_p_waic,
            lppd = point_lppd,
            waic = point_waic,
        ),
        n_draws,
        n_observations,
        high_variance_count,
        warning = high_variance_count == 0 ? :ok : :high_loglik_variance,
    )
end

function waic(design::FacetDesign, draws::AbstractMatrix)
    return waic(pointwise_loglikelihood_matrix(design, draws))
end

function waic(fit::MFRMFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return waic(fit.design, fit.draws[indices, :])
end

function _compare_model_names(names, n_models::Int)
    labels = names === nothing ?
        ["model_$i" for i in 1:n_models] :
        [string(name) for name in names]
    length(labels) == n_models ||
        throw(ArgumentError("names has length $(length(labels)); expected $n_models"))
    length(unique(labels)) == length(labels) ||
        throw(ArgumentError("model names must be unique"))
    return labels
end

function _compare_criterion(criterion::Symbol)
    criterion === :waic ||
        throw(ArgumentError("only criterion = :waic is currently supported"))
    return criterion
end

function _waic_comparison_rows(labels::AbstractVector{<:AbstractString}, stats)
    n_models = length(stats)
    n_models >= 2 || throw(ArgumentError("at least two models are required"))
    n_observations = stats[1].n_observations
    all(stat -> stat.n_observations == n_observations, stats) ||
        throw(ArgumentError("all models must have the same number of observations"))

    order = sortperm(1:n_models; by = i -> stats[i].elpd_waic, rev = true)
    best = stats[order[1]]
    rows = NamedTuple[]
    for (rank, index) in pairs(order)
        stat = stats[index]
        pointwise_difference = stat.pointwise.elpd_waic .- best.pointwise.elpd_waic
        push!(rows, (;
            model = labels[index],
            rank,
            criterion = :waic,
            elpd_waic = stat.elpd_waic,
            elpd_difference = stat.elpd_waic - best.elpd_waic,
            se_elpd_difference = _pointwise_se(pointwise_difference),
            se_elpd_waic = stat.se_elpd_waic,
            waic = stat.waic,
            waic_difference = stat.waic - best.waic,
            se_waic = stat.se_waic,
            p_waic = stat.p_waic,
            lppd = stat.lppd,
            n_draws = stat.n_draws,
            n_observations = stat.n_observations,
            high_variance_count = stat.high_variance_count,
            warning = stat.warning,
        ))
    end
    return rows
end

function _compare_models_waic(fits::AbstractVector{<:MFRMFit},
        labels::AbstractVector{<:AbstractString};
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    length(fits) >= 2 || throw(ArgumentError("at least two models are required"))
    length(labels) == length(fits) ||
        throw(ArgumentError("labels has length $(length(labels)); expected $(length(fits))"))
    stats = [waic(fit; ndraws, draw_indices, rng) for fit in fits]
    return _waic_comparison_rows(labels, stats)
end

"""
    compare_models(fits::MFRMFit...; names = nothing, criterion = :waic,
        ndraws = nothing, draw_indices = nothing, rng = Random.default_rng())
    compare_models(models::Pair...; criterion = :waic, ndraws = nothing,
        draw_indices = nothing, rng = Random.default_rng())

Compare fitted models with WAIC. Rows are sorted by `elpd_waic` in descending
order. `elpd_difference` is relative to the best model and is therefore zero
for the top row and non-positive for lower-ranked rows; `waic_difference` is
zero for the top row and non-negative for lower-ranked rows.
"""
function compare_models(fits::MFRMFit...;
        names = nothing,
        criterion::Symbol = :waic,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    _compare_criterion(criterion)
    labels = _compare_model_names(names, length(fits))
    return _compare_models_waic(collect(fits), labels; ndraws, draw_indices, rng)
end

function compare_models(models::Pair...;
        criterion::Symbol = :waic,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    _compare_criterion(criterion)
    fits = MFRMFit[]
    labels = String[]
    for model in models
        model.second isa MFRMFit ||
            throw(ArgumentError("model pair :$(model.first) does not contain an MFRMFit"))
        push!(labels, string(model.first))
        push!(fits, model.second)
    end
    _compare_model_names(labels, length(labels))
    return _compare_models_waic(fits, labels; ndraws, draw_indices, rng)
end

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

"""
    predictive_probabilities(fit::MFRMFit; ndraws = nothing,
        draw_indices = nothing, rng = Random.default_rng())
    predictive_probabilities(design::FacetDesign, draws)

Return observation-level category probabilities for posterior or supplied
parameter draws. The returned array has dimensions draws-by-observations-by-
categories, with categories ordered as `fit.design.spec.data.category_levels`.
"""
function predictive_probabilities(design::FacetDesign, draws::AbstractMatrix)
    size(draws, 2) == length(design.parameter_names) ||
        throw(ArgumentError("draws has $(size(draws, 2)) column(s); expected $(length(design.parameter_names))"))
    data = design.spec.data
    K = length(data.category_levels)
    out = Array{Float64}(undef, size(draws, 1), data.n, K)
    probs = zeros(Float64, K)

    for draw in axes(draws, 1)
        params = @view draws[draw, :]
        for row in 1:data.n
            _category_probabilities!(probs, design, params, row)
            for category in 1:K
                out[draw, row, category] = probs[category]
            end
        end
    end
    return out
end

function predictive_probabilities(fit::MFRMFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return predictive_probabilities(fit.design, fit.draws[indices, :])
end

function _expected_scores_from_probabilities(probabilities::AbstractArray{<:Real,3},
        levels::AbstractVector{<:Real})
    size(probabilities, 3) == length(levels) ||
        throw(ArgumentError("probabilities has $(size(probabilities, 3)) category column(s); expected $(length(levels))"))
    expected = zeros(Float64, size(probabilities, 1), size(probabilities, 2))
    for category in eachindex(levels)
        expected .+= Float64(levels[category]) .* @view probabilities[:, :, category]
    end
    return expected
end

"""
    expected_scores(fit::MFRMFit; ndraws = nothing, draw_indices = nothing,
        rng = Random.default_rng())
    expected_scores(design::FacetDesign, draws)

Return observation-level expected scores for each posterior or supplied
parameter draw. The returned matrix has dimensions draws-by-observations.
"""
function expected_scores(design::FacetDesign, draws::AbstractMatrix)
    probabilities = predictive_probabilities(design, draws)
    return _expected_scores_from_probabilities(probabilities, design.spec.data.category_levels)
end

function expected_scores(fit::MFRMFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    probabilities = predictive_probabilities(fit; ndraws, draw_indices, rng)
    return _expected_scores_from_probabilities(probabilities, fit.design.spec.data.category_levels)
end

function _predictive_variances_from_probabilities(probabilities::AbstractArray{<:Real,3},
        levels::AbstractVector{<:Real})
    expected = _expected_scores_from_probabilities(probabilities, levels)
    second = zeros(Float64, size(probabilities, 1), size(probabilities, 2))
    for category in eachindex(levels)
        score = Float64(levels[category])
        second .+= (score * score) .* @view probabilities[:, :, category]
    end
    variances = second .- expected .* expected
    return max.(variances, 0.0)
end

"""
    predictive_variances(fit::MFRMFit; ndraws = nothing,
        draw_indices = nothing, rng = Random.default_rng())
    predictive_variances(design::FacetDesign, draws)

Return observation-level conditional predictive score variances for each
posterior or supplied parameter draw. The returned matrix has dimensions
draws-by-observations.
"""
function predictive_variances(design::FacetDesign, draws::AbstractMatrix)
    probabilities = predictive_probabilities(design, draws)
    return _predictive_variances_from_probabilities(probabilities, design.spec.data.category_levels)
end

function predictive_variances(fit::MFRMFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    probabilities = predictive_probabilities(fit; ndraws, draw_indices, rng)
    return _predictive_variances_from_probabilities(probabilities, fit.design.spec.data.category_levels)
end

"""
    predictive_residuals(fit::MFRMFit; ndraws = nothing,
        draw_indices = nothing, rng = Random.default_rng())
    predictive_residuals(design::FacetDesign, draws)

Return observation-level observed-minus-expected score residuals for each
posterior or supplied parameter draw. The returned matrix has dimensions
draws-by-observations.
"""
function predictive_residuals(design::FacetDesign, draws::AbstractMatrix)
    expected = expected_scores(design, draws)
    data = design.spec.data
    residuals = similar(expected)
    for draw in axes(expected, 1), row in axes(expected, 2)
        residuals[draw, row] = data.score[row] - expected[draw, row]
    end
    return residuals
end

function predictive_residuals(fit::MFRMFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return predictive_residuals(fit.design, fit.draws[indices, :])
end

function _fit_stat_groups(data::FacetData, by::Symbol)
    by === :person && return data.person, data.person_levels
    by === :rater && return data.rater, data.rater_levels
    by === :item && return data.item, data.item_levels
    by === :category && return data.category, data.category_levels
    if haskey(data.optional, by)
        return data.optional[by], data.optional_levels[by]
    end
    throw(ArgumentError("by = :$by is not a facet in this design"))
end

function _interval_probabilities(interval::Real)
    0 < interval < 1 || throw(ArgumentError("interval must be in (0, 1)"))
    lower = (1 - Float64(interval)) / 2
    return lower, 1 - lower
end

function _finite_draw_summary(values::AbstractVector{<:Real}, lower::Float64, upper::Float64)
    finite = [Float64(value) for value in values if isfinite(value)]
    if isempty(finite)
        return (mean = NaN, median = NaN, lower = NaN, upper = NaN)
    end
    sorted = sort(finite)
    return (;
        mean = _column_mean(finite),
        median = _quantile_sorted(sorted, 0.5),
        lower = _quantile_sorted(sorted, lower),
        upper = _quantile_sorted(sorted, upper),
    )
end

"""
    fit_stats(fit::MFRMFit; by = :rater, method = :posterior,
        interval = 0.95, min_n = 1, ndraws = nothing, draw_indices = nothing,
        rng = Random.default_rng())
    fit_stats(design::FacetDesign, draws; by = :rater, interval = 0.95,
        min_n = 1)

Return posterior summaries of observation-level infit and outfit mean-square
statistics by facet level. This initial implementation uses posterior draws and
the current minimal MFRM predictive variances; `method = :posterior` is the only
supported method.
"""
function fit_stats(design::FacetDesign,
        draws::AbstractMatrix;
        by::Symbol = :rater,
        interval::Real = 0.95,
        min_n::Int = 1)
    min_n >= 1 || throw(ArgumentError("min_n must be positive"))
    lower_probability, upper_probability = _interval_probabilities(interval)
    residuals = predictive_residuals(design, draws)
    variances = predictive_variances(design, draws)
    data = design.spec.data
    group_index, group_levels = _fit_stat_groups(data, by)
    rows = NamedTuple[]
    eps_var = eps(Float64)

    for (level_index, level) in pairs(group_levels)
        obs = findall(==(level_index), group_index)
        n_obs = length(obs)
        infit = Vector{Float64}(undef, size(draws, 1))
        outfit = Vector{Float64}(undef, size(draws, 1))
        tiny_variance_count = 0

        if n_obs < min_n
            fill!(infit, NaN)
            fill!(outfit, NaN)
            flag = :below_min_n
        else
            for draw in axes(draws, 1)
                residual_ss = 0.0
                variance_sum = 0.0
                standardized_sum = 0.0
                for row in obs
                    r = residuals[draw, row]
                    v = variances[draw, row]
                    if v <= eps_var
                        tiny_variance_count += 1
                    end
                    residual_ss += r * r
                    variance_sum += v
                    standardized_sum += r * r / max(v, eps_var)
                end
                infit[draw] = residual_ss / max(variance_sum, eps_var)
                outfit[draw] = standardized_sum / n_obs
            end
            flag = tiny_variance_count == 0 ? :ok : :tiny_predictive_variance
        end

        infit_summary = _finite_draw_summary(infit, lower_probability, upper_probability)
        outfit_summary = _finite_draw_summary(outfit, lower_probability, upper_probability)
        push!(rows, (;
            facet = by,
            level,
            n_obs,
            method = :posterior,
            interval_probability = Float64(interval),
            lower_probability,
            upper_probability,
            infit_mean = infit_summary.mean,
            infit_median = infit_summary.median,
            infit_lower = infit_summary.lower,
            infit_upper = infit_summary.upper,
            outfit_mean = outfit_summary.mean,
            outfit_median = outfit_summary.median,
            outfit_lower = outfit_summary.lower,
            outfit_upper = outfit_summary.upper,
            tiny_variance_count,
            flag,
        ))
    end
    return rows
end

function fit_stats(fit::MFRMFit;
        by::Symbol = :rater,
        method::Symbol = :posterior,
        interval::Real = 0.95,
        min_n::Int = 1,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    method === :posterior ||
        throw(ArgumentError("only method = :posterior is currently supported"))
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return fit_stats(fit.design, fit.draws[indices, :]; by, interval, min_n)
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

function _replicate_scores(design::FacetDesign, draws::AbstractMatrix, rng::AbstractRNG)
    size(draws, 2) == length(design.parameter_names) ||
        throw(ArgumentError("draws has $(size(draws, 2)) column(s); expected $(length(design.parameter_names))"))
    data = design.spec.data
    K = length(data.category_levels)
    replicated = Matrix{Int}(undef, size(draws, 1), data.n)
    probs = zeros(Float64, K)

    for replication in axes(draws, 1)
        params = @view draws[replication, :]
        for row in 1:data.n
            _category_probabilities!(probs, design, params, row)
            category = _sample_category_index(rng, probs)
            replicated[replication, row] = data.category_levels[category]
        end
    end
    return replicated
end

function _prior_parameter_draws(design::FacetDesign,
        prior::MFRMPrior,
        ndraws::Int,
        rng::AbstractRNG)
    ndraws >= 1 || throw(ArgumentError("ndraws must be positive"))
    nparams = length(design.parameter_names)
    draws = Matrix{Float64}(undef, ndraws, nparams)
    for draw in 1:ndraws, param in 1:nparams
        draws[draw, param] = _prior_sd(design, prior, param) * randn(rng)
    end
    return draws
end

"""
    prior_predict(spec_or_design; prior = MFRMPrior(), ndraws = 1000,
        rng = Random.default_rng())

Generate replicated score matrices from prior draws for the minimal MFRM
design. The returned matrix has one replicated dataset per row and one rating
observation per column, with entries on the original integer score scale.
"""
function prior_predict(design::FacetDesign;
        prior::MFRMPrior = MFRMPrior(),
        ndraws::Int = 1000,
        rng::AbstractRNG = Random.default_rng())
    draws = _prior_parameter_draws(design, prior, ndraws, rng)
    return _replicate_scores(design, draws, rng)
end

prior_predict(spec::FacetSpec; kwargs...) = prior_predict(getdesign(spec); kwargs...)

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
    return _replicate_scores(fit.design, fit.draws[indices, :], rng)
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

function _tail_probabilities(values::AbstractVector{<:Real}, observed::Real)
    obs = Float64(observed)
    vals = [Float64(value) for value in values if isfinite(value)]
    isempty(vals) && return (lower = NaN, upper = NaN, two_sided = NaN)
    if !isfinite(obs)
        return (lower = NaN, upper = NaN, two_sided = NaN)
    end
    lower = count(<=(obs), vals) / length(vals)
    upper = count(>=(obs), vals) / length(vals)
    return (;
        lower,
        upper,
        two_sided = min(1.0, 2 * min(lower, upper)),
    )
end

function _predictive_check_row(statistic::Symbol,
        level,
        observed::Real,
        replicated::AbstractVector{<:Real},
        interval::Real,
        lower_probability::Float64,
        upper_probability::Float64)
    summary = _finite_draw_summary(replicated, lower_probability, upper_probability)
    tails = _tail_probabilities(replicated, observed)
    obs = Float64(observed)
    outside = isfinite(obs) &&
        (obs < summary.lower || obs > summary.upper)
    return (;
        statistic,
        level,
        observed = obs,
        replicated_mean = summary.mean,
        replicated_median = summary.median,
        replicated_lower = summary.lower,
        replicated_upper = summary.upper,
        interval_probability = Float64(interval),
        lower_probability,
        upper_probability,
        lower_tail_probability = tails.lower,
        upper_tail_probability = tails.upper,
        two_sided_tail_probability = tails.two_sided,
        n_replicates = count(value -> isfinite(Float64(value)), replicated),
        flag = outside ? :outside_interval : :ok,
    )
end

function _require_predictive_check_fields(check)
    for field in (:observed, :replicated, :category_levels, :rater_levels, :item_levels)
        hasproperty(check, field) ||
            throw(ArgumentError("predictive check object is missing .$field"))
    end
    return nothing
end

"""
    predictive_check_summary(check; interval = 0.9)

Summarize a `prior_predictive_check` or `posterior_predictive_check` result as
rows with observed values, replicated means, replicated intervals, and tail
probabilities. The current summary covers overall mean score, category
proportions, rater-level mean scores, and item-level mean scores.
"""
function predictive_check_summary(check; interval::Real = 0.9)
    _require_predictive_check_fields(check)
    lower_probability, upper_probability = _interval_probabilities(interval)
    observed = check.observed
    replicated = check.replicated
    rows = NamedTuple[]

    push!(rows, _predictive_check_row(:mean_score, missing,
        observed.mean_score,
        replicated.mean_score,
        interval,
        lower_probability,
        upper_probability))

    for (index, level) in pairs(check.category_levels)
        push!(rows, _predictive_check_row(:category_proportion, level,
            observed.category_proportions[index],
            @view(replicated.category_proportions[:, index]),
            interval,
            lower_probability,
            upper_probability))
    end

    for (index, level) in pairs(check.rater_levels)
        push!(rows, _predictive_check_row(:rater_mean, level,
            observed.rater_mean[index],
            @view(replicated.rater_mean[:, index]),
            interval,
            lower_probability,
            upper_probability))
    end

    for (index, level) in pairs(check.item_levels)
        push!(rows, _predictive_check_row(:item_mean, level,
            observed.item_mean[index],
            @view(replicated.item_mean[:, index]),
            interval,
            lower_probability,
            upper_probability))
    end

    return rows
end

"""
    prior_predictive_check(spec_or_design; prior = MFRMPrior(), ndraws = 1000,
        rng = Random.default_rng())

Generate prior predictive replicated scores and compact observed-vs-replicated
summaries for the minimal MFRM design. The returned object includes the prior
parameter draws used to generate `replicated_scores`.
"""
function prior_predictive_check(design::FacetDesign;
        prior::MFRMPrior = MFRMPrior(),
        ndraws::Int = 1000,
        rng::AbstractRNG = Random.default_rng())
    draws = _prior_parameter_draws(design, prior, ndraws, rng)
    replicated = _replicate_scores(design, draws, rng)
    data = design.spec.data
    return (;
        observed = _predictive_summary(data, data.score),
        replicated = _replicated_summaries(data, replicated),
        replicated_scores = replicated,
        parameter_draws = draws,
        category_levels = copy(data.category_levels),
        rater_levels = copy(data.rater_levels),
        item_levels = copy(data.item_levels),
    )
end

prior_predictive_check(spec::FacetSpec; kwargs...) =
    prior_predictive_check(getdesign(spec); kwargs...)

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
