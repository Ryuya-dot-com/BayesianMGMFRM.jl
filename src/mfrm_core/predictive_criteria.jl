# predictive_criteria.jl -- Pointwise log-likelihood, WAIC, PSIS-LOO, K-fold/LOO refits, and model comparison.

function _mfrm_pointwise_loglikelihood_matrix_unchecked(
        design::FacetDesign,
        draws::AbstractMatrix)
    size(draws, 2) == length(design.parameter_names) ||
        throw(ArgumentError(
            "draws has $(size(draws, 2)) column(s); " *
            "expected $(length(design.parameter_names))",
        ))
    out = Matrix{Float64}(undef, size(draws, 1), design.spec.data.n)
    _parallel_ranges(size(draws,1), design.spec.data.n) do indices
        for draw in indices
            out[draw, :] .= _pointwise_loglikelihood_unchecked(
                design,
                @view(draws[draw, :]),
            )
        end
    end
    return out
end

"""
    pointwise_loglikelihood_matrix(fit::Union{MFRMFit,GMFRMFit,MGMFRMFit})
    pointwise_loglikelihood_matrix(design::FacetDesign, draws;
        parameter_space = :direct)

Evaluate a draws-by-observations pointwise log-likelihood matrix for posterior
summaries, posterior predictive checks, and future model-comparison helpers.
For specified-only GMFRM/MGMFRM preview designs, pass `parameter_space = :raw`
when `draws` are raw unconstrained candidate coordinates.
"""
function pointwise_loglikelihood_matrix(design::FacetDesign,
        draws::AbstractMatrix;
        parameter_space::Symbol = :direct)
    _require_canonical_design(design, "pointwise_loglikelihood_matrix")
    parameter_space in (:direct, :raw) ||
        throw(ArgumentError("parameter_space must be :direct or :raw"))
    if design.spec.family === :mfrm &&
            design.spec.estimation_status === :fit_supported
        parameter_space === :direct ||
            throw(ArgumentError("fit-supported MFRM/RSM/PCM pointwise loglikelihood only accepts parameter_space = :direct"))
        return _mfrm_pointwise_loglikelihood_matrix_unchecked(design, draws)
    end
    out = Matrix{Float64}(undef, size(draws, 1), design.spec.data.n)
    if design.spec.family === :gmfrm &&
            design.spec.estimation_status === :specified_only
        expected = parameter_space === :raw ?
            _gmfrm_source_unconstrained_blueprint(design).n_parameters :
            length(design.parameter_names)
        size(draws, 2) == expected ||
            throw(ArgumentError("draws has $(size(draws, 2)) column(s); expected $expected"))
        _parallel_ranges(size(draws,1), design.spec.data.n) do indices
            for draw in indices
                out[draw, :] .= parameter_space === :raw ?
                    _gmfrm_source_pointwise_loglikelihood_from_unconstrained(
                        design,
                        (@view draws[draw, :]),
                    ) :
                    _gmfrm_source_pointwise_loglikelihood(
                        design,
                        (@view draws[draw, :]),
                    )
            end
        end
        return out
    elseif design.spec.family === :mgmfrm &&
            design.spec.estimation_status === :specified_only
        expected = parameter_space === :raw ?
            _mgmfrm_source_unconstrained_blueprint(design).n_parameters :
            length(design.parameter_names)
        size(draws, 2) == expected ||
            throw(ArgumentError("draws has $(size(draws, 2)) column(s); expected $expected"))
        _parallel_ranges(size(draws,1), design.spec.data.n) do indices
            for draw in indices
                out[draw, :] .= parameter_space === :raw ?
                    _mgmfrm_source_pointwise_loglikelihood_from_unconstrained(
                        design,
                        (@view draws[draw, :]),
                    ) :
                    _mgmfrm_source_pointwise_loglikelihood(
                        design,
                        (@view draws[draw, :]),
                    )
            end
        end
        return out
    end
    throw(ArgumentError(
        "pointwise_loglikelihood_matrix currently supports fit-supported " *
        "MFRM/RSM/PCM designs and specified-only GMFRM/MGMFRM preview designs",
    ))
end

pointwise_loglikelihood_matrix(fit::MFRMFit) =
    pointwise_loglikelihood_matrix(fit.design, fit.draws)

pointwise_loglikelihood_matrix(fit::GMFRMFit) =
    copy(fit.direct_pointwise_loglikelihood)

pointwise_loglikelihood_matrix(fit::MGMFRMFit) =
    copy(fit.direct_pointwise_loglikelihood)

function loglikelihood(fit::MFRMFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    values = Vector{Float64}(undef, length(indices))
    for (out, draw) in enumerate(indices)
        values[out] = loglikelihood(fit.design, @view(fit.draws[draw, :]))
    end
    return values
end

function loglikelihood(fit::Union{GMFRMFit,MGMFRMFit};
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return copy(fit.direct_loglikelihood[indices])
end

function logprior(fit::MFRMFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    values = Vector{Float64}(undef, length(indices))
    for (out, draw) in enumerate(indices)
        values[out] = logprior(fit.design, @view(fit.draws[draw, :]), fit.prior)
    end
    return values
end

function logprior(fit::Union{GMFRMFit,MGMFRMFit};
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return copy(fit.log_posterior[indices] .- fit.direct_loglikelihood[indices])
end

function logposterior(fit::_ModelComparisonFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return copy(fit.log_posterior[indices])
end

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

function waic(design::FacetDesign,
        draws::AbstractMatrix;
        parameter_space::Symbol = :direct)
    return waic(pointwise_loglikelihood_matrix(design, draws; parameter_space))
end

function waic(fit::MFRMFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return waic(fit.design, fit.draws[indices, :])
end

function waic(fit::GMFRMFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return waic(fit.direct_pointwise_loglikelihood[indices, :])
end

function waic(fit::MGMFRMFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return waic(fit.direct_pointwise_loglikelihood[indices, :])
end

function _check_loo_controls(;
        pareto_k_threshold::Real,
        tail_fraction::Real,
        min_tail_draws::Int)
    isfinite(pareto_k_threshold) && pareto_k_threshold >= 0 ||
        throw(ArgumentError("pareto_k_threshold must be finite and non-negative"))
    isfinite(tail_fraction) && 0 < tail_fraction < 1 ||
        throw(ArgumentError("tail_fraction must be finite and in (0, 1)"))
    min_tail_draws >= 1 ||
        throw(ArgumentError("min_tail_draws must be positive"))
    return (;
        pareto_k_threshold = Float64(pareto_k_threshold),
        tail_fraction = Float64(tail_fraction),
        min_tail_draws,
    )
end

function _loo_tail_draws(n_draws::Int, tail_fraction::Float64, min_tail_draws::Int)
    n_draws >= 3 || throw(ArgumentError("LOO requires at least three posterior draws"))
    fraction_tail = ceil(Int, tail_fraction * n_draws)
    return min(max(fraction_tail, min_tail_draws), n_draws - 1)
end

function _hill_log_tail_pareto_k(log_ratios::AbstractVector{Float64},
        tail_draws::Int)
    sorted = sort(log_ratios)
    n = length(sorted)
    threshold = sorted[n - tail_draws]
    total_excess = 0.0
    for index in (n - tail_draws + 1):n
        total_excess += max(sorted[index] - threshold, 0.0)
    end
    return max(total_excess / tail_draws, 0.0)
end

function _raw_importance_effective_sample_size(log_ratios::AbstractVector{Float64})
    log_total = _logsumexp(log_ratios)
    sum_squared = sum(exp(2 * (value - log_total)) for value in log_ratios)
    return 1 / sum_squared
end

function _self_normalized_importance_log_score(
        loglik_values::AbstractVector,
        log_ratios::AbstractVector{Float64})
    length(loglik_values) == length(log_ratios) ||
        throw(ArgumentError("loglik_values and log_ratios must have the same length"))
    log_weight_total = _logsumexp(log_ratios)
    weighted_terms = Vector{Float64}(undef, length(log_ratios))
    for draw in eachindex(log_ratios)
        weighted_terms[draw] =
            Float64(loglik_values[draw]) + log_ratios[draw] - log_weight_total
    end
    return _logsumexp(weighted_terms)
end

function _truncate_importance_log_ratios!(log_ratios::Vector{Float64})
    n = length(log_ratios)
    cap = 0.75 * log(n) + _logmeanexp(log_ratios)
    for draw in eachindex(log_ratios)
        log_ratios[draw] = min(log_ratios[draw], cap)
    end
    return log_ratios
end

function _pareto_smoothed_log_ratios(log_ratios::AbstractVector{Float64},
        tail_draws::Int)
    n = length(log_ratios)
    1 <= tail_draws < n ||
        throw(ArgumentError("tail_draws must be between 1 and length(log_ratios) - 1"))
    order = sortperm(log_ratios)
    sorted = Vector{Float64}(undef, n)
    for rank in 1:n
        sorted[rank] = log_ratios[order[rank]]
    end

    threshold_index = n - tail_draws
    threshold = sorted[threshold_index]
    pareto_k = _hill_log_tail_pareto_k(log_ratios, tail_draws)
    smoothed_sorted = copy(sorted)
    for tail_rank in 1:tail_draws
        probability = (tail_rank - 0.5) / tail_draws
        smoothed_sorted[threshold_index + tail_rank] =
            pareto_k == 0 ? threshold : threshold - pareto_k * log1p(-probability)
    end
    for rank in (threshold_index + 1):n
        smoothed_sorted[rank] = max(smoothed_sorted[rank], smoothed_sorted[rank - 1])
    end

    smoothed = Vector{Float64}(undef, n)
    for rank in 1:n
        smoothed[order[rank]] = smoothed_sorted[rank]
    end
    return _truncate_importance_log_ratios!(smoothed), pareto_k
end

function _loo_diagnostic_flag(pareto_k::Float64, threshold::Float64)
    return pareto_k > threshold ? :high_pareto_k : :ok
end

"""
    loo(fit::MFRMFit; ndraws = nothing, draw_indices = nothing,
        rng = Random.default_rng(), pareto_k_threshold = 0.7,
        tail_fraction = 0.2, min_tail_draws = 5)
    loo(design::FacetDesign, draws; kwargs...)
    loo(loglik::AbstractMatrix; kwargs...)

Compute a raw importance-sampling leave-one-out (LOO) estimate from posterior
pointwise log-likelihood draws. The log-likelihood matrix must have dimensions
draws-by-observations. The returned named tuple includes `elpd_loo`, `p_loo`,
`lppd`, `looic`, standard errors, raw-importance effective sample sizes, and a
Hill-estimated Pareto-k diagnostic for each observation.

This helper does not perform PSIS smoothing. Treat rows with `pareto_k` above
`pareto_k_threshold` as unstable and prefer exact LOO, K-fold cross-validation,
or model-specific follow-up before making strong model-comparison claims.
"""
function loo(loglik::AbstractMatrix;
        pareto_k_threshold::Real = 0.7,
        tail_fraction::Real = 0.2,
        min_tail_draws::Int = 5)
    controls = _check_loo_controls(;
        pareto_k_threshold,
        tail_fraction,
        min_tail_draws)
    n_draws, n_observations = size(loglik)
    n_draws >= 3 || throw(ArgumentError("LOO requires at least three posterior draws"))
    n_observations >= 1 || throw(ArgumentError("LOO requires at least one observation"))
    all(value -> isfinite(Float64(value)), loglik) ||
        throw(ArgumentError("loglik contains non-finite values"))
    tail_draws = _loo_tail_draws(
        n_draws,
        controls.tail_fraction,
        controls.min_tail_draws,
    )

    point_lppd = Vector{Float64}(undef, n_observations)
    point_elpd = Vector{Float64}(undef, n_observations)
    point_p_loo = Vector{Float64}(undef, n_observations)
    point_looic = Vector{Float64}(undef, n_observations)
    point_pareto_k = Vector{Float64}(undef, n_observations)
    point_ess = Vector{Float64}(undef, n_observations)
    point_tail_draws = fill(tail_draws, n_observations)

    log_ratios = Vector{Float64}(undef, n_draws)
    for observation in 1:n_observations
        values = @view loglik[:, observation]
        point_lppd[observation] = _logmeanexp(values)
        for draw in 1:n_draws
            log_ratios[draw] = -Float64(loglik[draw, observation])
        end
        point_elpd[observation] = -_logmeanexp(log_ratios)
        point_p_loo[observation] =
            point_lppd[observation] - point_elpd[observation]
        point_looic[observation] = -2 * point_elpd[observation]
        point_pareto_k[observation] =
            _hill_log_tail_pareto_k(log_ratios, tail_draws)
        point_ess[observation] =
            _raw_importance_effective_sample_size(log_ratios)
    end

    elpd_loo = sum(point_elpd)
    p_loo = sum(point_p_loo)
    lppd = sum(point_lppd)
    looic_value = sum(point_looic)
    bad_pareto_k_count = count(>(controls.pareto_k_threshold), point_pareto_k)
    min_effective_sample_size = minimum(point_ess)
    return (;
        criterion = :loo,
        method = :raw_importance_sampling,
        psis_smoothing = false,
        pareto_k_estimator = :hill_log_tail,
        elpd_loo,
        p_loo,
        lppd,
        looic = looic_value,
        se_elpd_loo = _pointwise_se(point_elpd),
        se_looic = _pointwise_se(point_looic),
        pointwise = (;
            elpd_loo = point_elpd,
            p_loo = point_p_loo,
            lppd = point_lppd,
            looic = point_looic,
            pareto_k = point_pareto_k,
            effective_sample_size = point_ess,
            tail_draws = point_tail_draws,
        ),
        n_draws,
        n_observations,
        pareto_k_threshold = controls.pareto_k_threshold,
        tail_fraction = controls.tail_fraction,
        min_tail_draws = controls.min_tail_draws,
        bad_pareto_k_count,
        max_pareto_k = maximum(point_pareto_k),
        min_effective_sample_size,
        warning = bad_pareto_k_count == 0 ? :ok : :high_pareto_k,
    )
end

function loo(design::FacetDesign,
        draws::AbstractMatrix;
        parameter_space::Symbol = :direct,
        kwargs...)
    return loo(pointwise_loglikelihood_matrix(design, draws; parameter_space); kwargs...)
end

function loo(fit::MFRMFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng(),
        kwargs...)
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return loo(fit.design, fit.draws[indices, :]; kwargs...)
end

function loo(fit::GMFRMFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng(),
        kwargs...)
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return loo(fit.direct_pointwise_loglikelihood[indices, :]; kwargs...)
end

function loo(fit::MGMFRMFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng(),
        kwargs...)
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return loo(fit.direct_pointwise_loglikelihood[indices, :]; kwargs...)
end

function _hill_smoothed_loo(loglik::AbstractMatrix;
        pareto_k_threshold::Real = 0.7,
        tail_fraction::Real = 0.2,
        min_tail_draws::Int = 5)
    controls = _check_loo_controls(;
        pareto_k_threshold,
        tail_fraction,
        min_tail_draws)
    n_draws, n_observations = size(loglik)
    n_draws >= 3 || throw(ArgumentError("LOO requires at least three posterior draws"))
    n_observations >= 1 || throw(ArgumentError("LOO requires at least one observation"))
    all(value -> isfinite(Float64(value)), loglik) ||
        throw(ArgumentError("loglik contains non-finite values"))
    tail_draws = _loo_tail_draws(
        n_draws,
        controls.tail_fraction,
        controls.min_tail_draws,
    )

    point_lppd = Vector{Float64}(undef, n_observations)
    point_elpd = Vector{Float64}(undef, n_observations)
    point_p_loo = Vector{Float64}(undef, n_observations)
    point_looic = Vector{Float64}(undef, n_observations)
    point_pareto_k = Vector{Float64}(undef, n_observations)
    point_ess = Vector{Float64}(undef, n_observations)
    point_tail_draws = fill(tail_draws, n_observations)

    log_ratios = Vector{Float64}(undef, n_draws)
    for observation in 1:n_observations
        values = @view loglik[:, observation]
        point_lppd[observation] = _logmeanexp(values)
        for draw in 1:n_draws
            log_ratios[draw] = -Float64(loglik[draw, observation])
        end
        smoothed_log_ratios, pareto_k =
            _pareto_smoothed_log_ratios(log_ratios, tail_draws)
        point_elpd[observation] =
            _self_normalized_importance_log_score(values, smoothed_log_ratios)
        point_p_loo[observation] =
            point_lppd[observation] - point_elpd[observation]
        point_looic[observation] = -2 * point_elpd[observation]
        point_pareto_k[observation] = pareto_k
        point_ess[observation] =
            _raw_importance_effective_sample_size(smoothed_log_ratios)
    end

    elpd_loo = sum(point_elpd)
    p_loo = sum(point_p_loo)
    lppd = sum(point_lppd)
    looic_value = sum(point_looic)
    bad_pareto_k_count = count(>(controls.pareto_k_threshold), point_pareto_k)
    min_effective_sample_size = minimum(point_ess)
    return (;
        criterion = :loo,
        method = :pareto_smoothed_importance_sampling,
        psis_smoothing = true,
        pareto_k_estimator = :hill_log_tail,
        elpd_loo,
        p_loo,
        lppd,
        looic = looic_value,
        se_elpd_loo = _pointwise_se(point_elpd),
        se_looic = _pointwise_se(point_looic),
        pointwise = (;
            elpd_loo = point_elpd,
            p_loo = point_p_loo,
            lppd = point_lppd,
            looic = point_looic,
            pareto_k = point_pareto_k,
            effective_sample_size = point_ess,
            tail_draws = point_tail_draws,
        ),
        n_draws,
        n_observations,
        pareto_k_threshold = controls.pareto_k_threshold,
        tail_fraction = controls.tail_fraction,
        min_tail_draws = controls.min_tail_draws,
        bad_pareto_k_count,
        max_pareto_k = maximum(point_pareto_k),
        min_effective_sample_size,
        warning = bad_pareto_k_count == 0 ? :ok : :high_pareto_k,
    )
end

function psis_loo(design::FacetDesign,
        draws::AbstractMatrix;
        parameter_space::Symbol = :direct,
        kwargs...)
    return psis_loo(pointwise_loglikelihood_matrix(design, draws; parameter_space); kwargs...)
end

for Fit in (MFRMFit, GMFRMFit, MGMFRMFit)
    @eval psis_loo(fit::$Fit; kwargs...) = _common_fit_psis(fit; kwargs...)
end

function _check_kfold_loglik(loglik::AbstractMatrix, fold_index::Int)
    n_draws, n_heldout = size(loglik)
    n_draws >= 1 ||
        throw(ArgumentError("K-fold fold $fold_index requires at least one posterior draw"))
    n_heldout >= 1 ||
        throw(ArgumentError("K-fold fold $fold_index requires at least one heldout observation"))
    all(value -> isfinite(Float64(value)), loglik) ||
        throw(ArgumentError("K-fold fold $fold_index contains non-finite log-likelihood values"))
    return n_draws, n_heldout
end

function _kfold_fold_ids(n_folds::Int, fold_ids)
    if fold_ids === nothing
        return collect(1:n_folds)
    end
    collected = collect(fold_ids)
    length(collected) == n_folds ||
        throw(ArgumentError("fold_ids has length $(length(collected)); expected $n_folds"))
    length(unique(collected)) == length(collected) ||
        throw(ArgumentError("fold_ids must be unique"))
    return Any[collected...]
end

function _kfold_observation_indices(
        n_heldout_by_fold::AbstractVector{Int},
        observation_indices)
    total_heldout = sum(n_heldout_by_fold)
    if observation_indices === nothing
        return collect(1:total_heldout)
    end

    collected = collect(observation_indices)
    if length(collected) == length(n_heldout_by_fold) &&
            all(index_set -> index_set isa AbstractVector, collected)
        out = Any[]
        for (fold_index, index_set) in pairs(collected)
            fold_indices = collect(index_set)
            expected = n_heldout_by_fold[fold_index]
            length(fold_indices) == expected ||
                throw(ArgumentError(
                    "observation_indices for fold $fold_index has length " *
                    "$(length(fold_indices)); expected $expected"))
            append!(out, fold_indices)
        end
        length(unique(out)) == length(out) ||
            throw(ArgumentError("observation_indices must be unique across folds"))
        return out
    end

    length(collected) == total_heldout ||
        throw(ArgumentError(
            "observation_indices has length $(length(collected)); expected $total_heldout"))
    length(unique(collected)) == length(collected) ||
        throw(ArgumentError("observation_indices must be unique across folds"))
    return Any[collected...]
end

function _kfold_plan_group_indices(data::FacetData, group_by::Union{Nothing,Symbol})
    group_by === nothing && return :observation, collect(1:data.n), collect(1:data.n)
    group_by === :observation && return :observation, collect(1:data.n), collect(1:data.n)
    group_by === :person && return :person, data.person, data.person_levels
    group_by === :rater && return :rater, data.rater, data.rater_levels
    group_by === :item && return :item, data.item, data.item_levels
    group_by === :category && return :category, data.category, data.category_levels
    if haskey(data.optional, group_by)
        return group_by, data.optional[group_by], data.optional_levels[group_by]
    end
    throw(ArgumentError(
        "group_by = :$group_by is not :observation, a required facet, or an optional facet"))
end

function _kfold_plan_units(data::FacetData, group_by::Union{Nothing,Symbol})
    role, unit_indices, levels = _kfold_plan_group_indices(data, group_by)
    unit_rows = [Int[] for _ in eachindex(levels)]
    for (observation, unit_index) in pairs(unit_indices)
        1 <= unit_index <= length(unit_rows) ||
            throw(ArgumentError(
                "group_by = :$role produced invalid unit index $unit_index at observation $observation"))
        push!(unit_rows[unit_index], observation)
    end

    nonempty = findall(!isempty, unit_rows)
    isempty(nonempty) &&
        throw(ArgumentError("K-fold planning requires at least one observation"))
    return (;
        group_by = role,
        rows = [unit_rows[index] for index in nonempty],
        levels = Any[levels[index] for index in nonempty],
    )
end

function _least_loaded_fold_index(fold_observation_counts::AbstractVector{Int})
    best_index = firstindex(fold_observation_counts)
    best_count = fold_observation_counts[best_index]
    for index in Iterators.drop(eachindex(fold_observation_counts), 1)
        count = fold_observation_counts[index]
        if count < best_count
            best_index = index
            best_count = count
        end
    end
    return best_index
end

"""
    kfold_plan(data::FacetData; k, group_by = nothing, shuffle = false,
        rng = Random.default_rng(), fold_ids = nothing)
    kfold_plan(spec::FacetSpec; kwargs...)
    kfold_plan(design::FacetDesign; kwargs...)

Construct deterministic heldout-fold assignments for later K-fold refits. By
default observations are assigned directly to balanced folds. With
`group_by = :person`, `:rater`, `:item`, `:category`, or an optional facet such
as `:group`, all observations for each level are kept in the same heldout fold.

The returned named tuple includes `fold_rows`, `folds`, and
`heldout_observation_indices`; pass the latter two to [`kfold`](@ref) after
fitting each training fold and collecting fold-specific heldout log-likelihood
matrices. This helper builds the fold plan only. It does not refit models.
"""
function kfold_plan(data::FacetData;
        k::Integer,
        group_by::Union{Nothing,Symbol} = nothing,
        shuffle::Bool = false,
        rng::AbstractRNG = Random.default_rng(),
        fold_ids = nothing)
    data.n >= 1 || throw(ArgumentError("K-fold planning requires at least one observation"))
    k_int = Int(k)
    k_int >= 2 || throw(ArgumentError("K-fold planning requires k >= 2"))

    units = _kfold_plan_units(data, group_by)
    n_units = length(units.rows)
    k_int <= n_units ||
        throw(ArgumentError(
            "K-fold planning with group_by = :$(units.group_by) has $n_units heldout units; " *
            "expected at least k = $k_int"))

    checked_fold_ids = _kfold_fold_ids(k_int, fold_ids)
    unit_order = collect(1:n_units)
    shuffle && Random.shuffle!(rng, unit_order)

    fold_observation_counts = zeros(Int, k_int)
    heldout_by_fold = [Int[] for _ in 1:k_int]
    units_by_fold = [Any[] for _ in 1:k_int]
    for unit_index in unit_order
        fold_index = _least_loaded_fold_index(fold_observation_counts)
        rows = units.rows[unit_index]
        append!(heldout_by_fold[fold_index], rows)
        push!(units_by_fold[fold_index], units.levels[unit_index])
        fold_observation_counts[fold_index] += length(rows)
    end

    observation_fold = Vector{Any}(undef, data.n)
    fold_rows = NamedTuple[]
    all_observations = collect(1:data.n)
    for fold_index in 1:k_int
        heldout_observations = sort(heldout_by_fold[fold_index])
        heldout_set = Set(heldout_observations)
        training_observations =
            [observation for observation in all_observations if !(observation in heldout_set)]
        fold_id = checked_fold_ids[fold_index]
        for observation in heldout_observations
            observation_fold[observation] = fold_id
        end
        heldout_units = copy(units_by_fold[fold_index])
        push!(fold_rows, (;
            fold = fold_id,
            n_heldout_observations = length(heldout_observations),
            n_training_observations = length(training_observations),
            heldout_observations,
            training_observations,
            heldout_units,
            n_heldout_units = length(heldout_units),
        ))
    end

    return (;
        schema = "bayesianmgmfrm.kfold_plan.v1",
        object = :kfold_plan,
        method = shuffle ? :randomized_balanced_fold_plan : :deterministic_balanced_fold_plan,
        comparison_contract = :same_heldout_observation_folds,
        group_by = units.group_by,
        k = k_int,
        n_observations = data.n,
        n_units,
        n_folds = k_int,
        folds = copy(checked_fold_ids),
        observation_fold,
        heldout_observation_indices =
            [copy(row.heldout_observations) for row in fold_rows],
        n_heldout_by_fold = copy(fold_observation_counts),
        fold_rows,
        refits_per_model_required = k_int,
        warning = :ok,
    )
end

kfold_plan(spec::FacetSpec; kwargs...) = kfold_plan(spec.data; kwargs...)
kfold_plan(design::FacetDesign; kwargs...) = kfold_plan(design.spec.data; kwargs...)

function _loo_refit_plan_from_observations(
        data::FacetData,
        heldout_observations::Vector{Int},
        fold_ids,
        warning::Symbol)
    n_refits = length(heldout_observations)
    checked_fold_ids = fold_ids === nothing ?
        Any[heldout_observations...] :
        _kfold_fold_ids(n_refits, fold_ids)

    all_observations = collect(1:data.n)
    observation_fold = Vector{Any}(undef, data.n)
    fill!(observation_fold, missing)
    fold_rows = NamedTuple[]
    for (index, observation) in pairs(heldout_observations)
        fold_id = checked_fold_ids[index]
        training_observations = [row for row in all_observations if row != observation]
        observation_fold[observation] = fold_id
        push!(fold_rows, (;
            fold = fold_id,
            n_heldout_observations = 1,
            n_training_observations = length(training_observations),
            heldout_observations = [observation],
            training_observations,
            heldout_units = [observation],
            n_heldout_units = 1,
        ))
    end

    return (;
        schema = "bayesianmgmfrm.loo_refit_plan.v1",
        object = :loo_refit_plan,
        method = :deterministic_leave_one_observation_out_plan,
        comparison_contract = :same_heldout_observation_folds,
        group_by = :observation,
        n_observations = data.n,
        n_refits,
        n_folds = n_refits,
        folds = copy(checked_fold_ids),
        observation_fold,
        heldout_observation_indices =
            [copy(row.heldout_observations) for row in fold_rows],
        n_heldout_by_fold = fill(1, n_refits),
        fold_rows,
        refits_per_model_required = n_refits,
        warning,
    )
end

"""
    loo_refit_plan(data::FacetData; observations = nothing, fold_ids = nothing)
    loo_refit_plan(data::FacetData, stat; threshold = nothing,
        only_flagged = true, fold_ids = nothing)
    loo_refit_plan(spec::FacetSpec; kwargs...)
    loo_refit_plan(design::FacetDesign; kwargs...)

Construct a deterministic leave-one-observation-out refit plan. Each returned
fold row holds out exactly one observation and lists the complementary training
observations. Pass `observations` to plan exact-refit follow-up for a subset,
such as flagged raw-importance LOO rows. When a raw LOO summary is supplied,
`only_flagged = true` selects observations whose Pareto-k exceeds `threshold`;
by default the threshold is read from the summary. This helper builds the refit
plan only. It does not refit models.
"""
function loo_refit_plan(data::FacetData;
        observations = nothing,
        fold_ids = nothing)
    heldout_observations =
        _check_observation_indices(data, observations, "loo_refit_plan")
    isempty(heldout_observations) &&
        throw(ArgumentError("loo_refit_plan requires at least one heldout observation"))
    return _loo_refit_plan_from_observations(
        data,
        heldout_observations,
        fold_ids,
        observations === nothing ? :ok : :subset,
    )
end

loo_refit_plan(spec::FacetSpec; kwargs...) = loo_refit_plan(spec.data; kwargs...)
loo_refit_plan(design::FacetDesign; kwargs...) =
    loo_refit_plan(design.spec.data; kwargs...)

function _loo_refit_plan_stat_observations(data::FacetData, stat;
        threshold,
        only_flagged::Bool)
    hasproperty(stat, :criterion) && stat.criterion === :loo ||
        throw(ArgumentError("loo_refit_plan requires a raw LOO summary"))
    hasproperty(stat, :n_observations) && stat.n_observations isa Integer ||
        throw(ArgumentError("LOO summary must contain integer n_observations"))
    n_observations = Int(stat.n_observations)
    n_observations == data.n ||
        throw(ArgumentError("LOO summary n_observations does not match the supplied data"))
    hasproperty(stat, :pointwise) && hasproperty(stat.pointwise, :pareto_k) ||
        throw(ArgumentError("LOO summary must contain pointwise Pareto-k diagnostics"))
    length(stat.pointwise.pareto_k) == n_observations ||
        throw(ArgumentError("LOO summary pointwise Pareto-k length does not match n_observations"))
    checked_threshold = threshold === nothing ?
        _check_loo_threshold(
            hasproperty(stat, :pareto_k_threshold) ? stat.pareto_k_threshold : 0.7) :
        _check_loo_threshold(threshold)

    observations = Int[]
    for observation in 1:n_observations
        pareto_k = Float64(stat.pointwise.pareto_k[observation])
        (isfinite(pareto_k) || pareto_k == Inf) ||
            throw(ArgumentError("LOO summary Pareto-k must be finite or a flagged positive infinity"))
        flag = _loo_diagnostic_flag(pareto_k, checked_threshold)
        (!only_flagged || flag !== :ok) && push!(observations, observation)
    end
    return observations
end

function loo_refit_plan(data::FacetData, stat;
        threshold = nothing,
        only_flagged::Bool = true,
        fold_ids = nothing)
    observations = _loo_refit_plan_stat_observations(
        data,
        stat;
        threshold,
        only_flagged,
    )
    warning = only_flagged ?
        (isempty(observations) ? :no_refits_required : :subset) :
        :ok
    return _loo_refit_plan_from_observations(data, observations, fold_ids, warning)
end

loo_refit_plan(spec::FacetSpec, stat; kwargs...) =
    loo_refit_plan(spec.data, stat; kwargs...)
loo_refit_plan(design::FacetDesign, stat; kwargs...) =
    loo_refit_plan(design.spec.data, stat; kwargs...)

function _check_loo_refit_plan_for_execution(data::FacetData, plan)
    hasproperty(plan, :object) && plan.object === :loo_refit_plan ||
        throw(ArgumentError("loo_refit requires a loo_refit_plan result"))
    hasproperty(plan, :fold_rows) ||
        throw(ArgumentError("loo_refit plan must contain fold_rows"))
    _check_refit_plan_partition(data, plan; loo = true)
    # Current supported refit likelihoods do not fit optional metadata levels.
    diagnostics = kfold_plan_diagnostics(data, plan;
        facets = (:person, :rater, :item, :category))
    diagnostics.passed ||
        throw(ArgumentError(
            "loo_refit plan has heldout-only facet levels; inspect kfold_plan_diagnostics"))
    return diagnostics
end

function _facet_data_optional_kwargs(data::FacetData)
    return (;
        group = haskey(data.optional, :group) ? :group : nothing,
        task = haskey(data.optional, :task) ? :task : nothing,
        form = haskey(data.optional, :form) ? :form : nothing,
        occasion = haskey(data.optional, :occasion) ? :occasion : nothing,
        response_id = haskey(data.optional, :response_id) ? :response_id : nothing,
        testlet_id = haskey(data.optional, :testlet_id) ? :testlet_id : nothing,
    )
end

function _loo_refit_training_data(data::FacetData, observations::AbstractVector{Int})
    table = facet_response_table(data; observations)
    optional_kwargs = _facet_data_optional_kwargs(data)
    training = FacetData(
        table;
        person = :person,
        rater = data.columns.rater === nothing ? nothing : :rater,
        item = :item,
        score = :score,
        category_levels = data.category_levels,
        optional_kwargs...,
    )
    # Explicitly encoded source data may differ from FacetData(table)'s sorted order.
    # Keep reference labels fixed for raw-coordinate priors across folds.
    maps = map((:person, :rater, :item)) do facet
        levels = getproperty(training, Symbol(facet, :_levels))
        source_levels = getproperty(data, Symbol(facet, :_levels))
        order = sortperm([_loo_refit_level_index(source_levels, level, facet) for level in levels])
        (; indices=invperm(order)[getproperty(training, facet)], levels=levels[order])
    end
    return FacetData(training.n, maps[1].indices, maps[2].indices, maps[3].indices,
        training.score, training.category, maps[1].levels, maps[2].levels, maps[3].levels,
        training.category_levels, training.optional, training.optional_levels, training.columns)
end

_refit_default_prior(spec::FacetSpec) =
    spec.family === :mfrm ? MFRMPrior() : nothing

_refit_training_experimental(spec::FacetSpec, requested::Bool) =
    spec.family === :mfrm ? false : requested

_refit_fit_experimental_default(fit::_ModelComparisonFit) = !(fit isa MFRMFit)

function _refit_q_matrix_for_training(spec::FacetSpec, training_data::FacetData)
    spec.q_matrix === nothing && return nothing
    q_matrix = Matrix{Bool}(undef, length(training_data.item_levels), size(spec.q_matrix, 2))
    for (row, item_label) in pairs(training_data.item_levels)
        source_index = findfirst(
            level -> isequal(level, item_label),
            spec.data.item_levels,
        )
        source_index === nothing &&
            throw(ArgumentError(
                "refit training fold item level $(repr(item_label)) is absent " *
                "from the source q_matrix item map"))
        q_matrix[row, :] .= spec.q_matrix[source_index, :]
    end
    return q_matrix
end

function _refit_training_spec(spec::FacetSpec, training_data::FacetData)
    return mfrm_spec(
        training_data;
        thresholds = spec.thresholds,
        family = spec.family,
        dimensions = spec.dimensions,
        dimension_labels = spec.dimension_labels,
        discrimination = spec.discrimination,
        q_matrix = _refit_q_matrix_for_training(spec, training_data),
        bias = spec.validation_bias_terms,
        anchors = spec.anchors,
    )
end

function _loo_refit_level_index(levels::AbstractVector, label, facet::Symbol)
    index = findfirst(level -> isequal(level, label), levels)
    index === nothing &&
        throw(ArgumentError(
            "loo_refit cannot score heldout :$facet level $(repr(label)) " *
            "because it is absent from the training fold"))
    return Int(index)
end

function _loo_refit_score_data(source::FacetData,
        training::FacetData,
        observations::AbstractVector{Int})
    rows = _check_observation_indices(source, observations, "loo_refit heldout_observations")
    person = Int[]
    rater = Int[]
    item = Int[]
    score = Int[]
    category = Int[]
    for row in rows
        push!(person, _loo_refit_level_index(
            training.person_levels,
            source.person_levels[source.person[row]],
            :person,
        ))
        push!(rater, _loo_refit_level_index(
            training.rater_levels,
            source.rater_levels[source.rater[row]],
            :rater,
        ))
        push!(item, _loo_refit_level_index(
            training.item_levels,
            source.item_levels[source.item[row]],
            :item,
        ))
        score_value = source.score[row]
        push!(score, score_value)
        push!(category, _loo_refit_level_index(training.category_levels, score_value, :category))
    end

    optional = Dict{Symbol,Vector{Int}}()
    optional_levels = Dict{Symbol,Vector{Any}}()
    for facet in sort(collect(keys(source.optional)); by = string)
        haskey(training.optional, facet) ||
            throw(ArgumentError(
                "loo_refit cannot score heldout optional facet :$facet " *
                "because it is absent from the training fold"))
        optional_index = Int[]
        levels = copy(training.optional_levels[facet])
        for row in rows
            label = source.optional_levels[facet][source.optional[facet][row]]
            # Preserve training indexes and append heldout metadata labels.
            # These are grouping/reporting IDs, not new fitted coefficients.
            index = findfirst(level -> isequal(level, label), levels)
            if index === nothing
                push!(levels, label)
                index = length(levels)
            end
            push!(optional_index, index)
        end
        optional[facet] = optional_index
        optional_levels[facet] = levels
    end

    return FacetData(
        length(rows),
        person,
        rater,
        item,
        score,
        category,
        copy(training.person_levels),
        copy(training.rater_levels),
        copy(training.item_levels),
        copy(training.category_levels),
        optional,
        optional_levels,
        training.columns,
    )
end

function _replace_spec_data(spec::FacetSpec, data::FacetData)
    return FacetSpec(
        data,
        spec.thresholds,
        spec.validation,
        spec.family,
        spec.dimensions,
        spec.dimension_labels,
        spec.discrimination,
        spec.q_matrix,
        spec.validation_bias_terms,
        spec.anchors,
        spec.constraints,
        spec.prior_blocks,
        spec.estimation_status,
    )
end

function _loo_refit_score_design(source::FacetData,
        training_design::FacetDesign,
        observations::AbstractVector{Int})
    score_data = _loo_refit_score_data(source, training_design.spec.data, observations)
    score_spec = _replace_spec_data(training_design.spec, score_data)
    return FacetDesign(
        score_spec,
        copy(training_design.parameter_names),
        Dict(key => value for (key, value) in training_design.blocks),
        Dict(key => value for (key, value) in training_design.identification),
    )
end

function _refit_score_loglikelihood(score_design::FacetDesign, training_fit::MFRMFit)
    return _mfrm_pointwise_loglikelihood_matrix_unchecked(
        score_design,
        training_fit.draws,
    )
end

function _refit_score_loglikelihood(score_design::FacetDesign, training_fit::GMFRMFit)
    draws = training_fit.draws
    out = Matrix{Float64}(undef, size(draws, 1), score_design.spec.data.n)
    for draw in axes(draws, 1)
        out[draw, :] .=
            _gmfrm_source_pointwise_loglikelihood_from_unconstrained(
                score_design,
                (@view draws[draw, :]),
            )
    end
    return out
end

function _refit_score_loglikelihood(score_design::FacetDesign, training_fit::MGMFRMFit)
    draws = training_fit.draws
    out = Matrix{Float64}(undef, size(draws, 1), score_design.spec.data.n)
    for draw in axes(draws, 1)
        params = _mgmfrm_source_constrained_params_from_unconstrained(
            training_fit.design,
            (@view draws[draw, :]),
        )
        out[draw, :] .=
            _mgmfrm_source_pointwise_loglikelihood(
                score_design,
                params;
                require_q_observation_coverage = false,
            )
    end
    return out
end

function _refit_fit_row(fold_row, heldout_observations, training_observations,
        training_fit::_ModelComparisonFit, experimental::Bool)
    fit_summary = diagnostics(training_fit).summary
    spec = training_fit.design.spec
    return (;
        fold = fold_row.fold,
        heldout_observations = copy(heldout_observations),
        n_training_observations = length(training_observations),
        n_heldout_observations = length(heldout_observations),
        family = spec.family,
        dimensions = spec.dimensions,
        discrimination = spec.discrimination,
        estimation_status = spec.estimation_status,
        experimental,
        backend = training_fit.backend,
        sampler = training_fit.sampler,
        n_draws = size(training_fit.draws, 1),
        diagnostic_flag = fit_summary.flag,
    )
end

function _loo_refit_empty_result(data::FacetData, plan, plan_diagnostics)
    return (;
        schema = "bayesianmgmfrm.loo_refit.v1",
        object = :loo_refit,
        criterion = :loo_refit,
        method = :no_refits_required,
        prediction_target = :heldout_observation_log_score,
        plan_schema = hasproperty(plan, :schema) ? plan.schema : missing,
        n_refits = 0,
        n_folds = 0,
        n_observations = 0,
        n_total_observations = data.n,
        folds = Any[],
        observation_indices = Any[],
        n_draws_by_fold = Int[],
        n_heldout_by_fold = Int[],
        fold_rows = NamedTuple[],
        fit_rows = NamedTuple[],
        fold_logliks = Matrix{Float64}[],
        fold_fits = nothing,
        kfold_summary = nothing,
        plan_diagnostics,
        warning = :no_refits_required,
    )
end

function _check_refit_supported_spec(spec::FacetSpec, caller::AbstractString;
        experimental::Bool = false)
    if spec.family === :mfrm
        spec.estimation_status === :fit_supported ||
            throw(ArgumentError("$caller requires a fit-supported spec"))
        return spec
    end
    spec.family in (:gmfrm, :mgmfrm) ||
        throw(ArgumentError(
            "$caller currently supports fit-supported MFRM specs and guarded " *
            "GMFRM/MGMFRM specs"))
    experimental ||
        throw(ArgumentError(
            "$caller requires experimental = true for guarded generalized refits"))
    _check_guarded_generalized_spec(
        spec,
        "$caller guarded generalized refit",
    )
    return spec
end

_check_loo_refit_spec(spec::FacetSpec; experimental::Bool = false) =
    _check_refit_supported_spec(spec, "loo_refit"; experimental)

"""
    loo_refit(data::FacetData, plan = loo_refit_plan(data);
        thresholds = :partial_credit, prior = MFRMPrior(), kwargs...)
    loo_refit(spec::FacetSpec, plan = loo_refit_plan(spec);
        prior = model default, experimental = false, return_fits = false, kwargs...)
    loo_refit(design::FacetDesign, plan = loo_refit_plan(design); kwargs...)
    loo_refit(fit::Union{MFRMFit,GMFRMFit,MGMFRMFit},
        plan = loo_refit_plan(fit.design); kwargs...)

Execute exact leave-one-observation-out refits for a [`loo_refit_plan`](@ref)
under the current fit-supported MFRM/RSM/PCM likelihood, or under the guarded
GMFRM/MGMFRM likelihood when `experimental = true` is supplied.
Each plan row is refit on the complementary training observations, scored on
its single heldout observation, and summarized with the same heldout log-score
contract as [`kfold`](@ref).

Before fitting, all plan rows must have disjoint heldout/training sets with
training equal to the full heldout complement. Each heldout row occurs at most
once; fold IDs, counts and scored-row labels must agree with the plan rows.
Subset LOO follow-up and an empty no-flag plan remain supported. Training specs
retain the declared dimension labels and item-specific Q rows.
Plans are also checked with [`kfold_plan_diagnostics`](@ref); rows
with heldout-only person, rater, item, or score-category levels
are rejected because the heldout observation cannot be scored against the
training-fold parameter map. Optional facets are metadata in these supported
likelihoods; their heldout-only labels are preserved without adding fitted
effects. The general `kfold_plan_diagnostics` default still audits all facets.
"""
function loo_refit(spec::FacetSpec, plan = loo_refit_plan(spec);
        prior = _refit_default_prior(spec),
        experimental::Bool = false,
        return_fits::Bool = false,
        kwargs...)
    checked_spec = _check_refit_supported_spec(spec, "loo_refit"; experimental)
    data = checked_spec.data
    plan_diagnostics = _check_loo_refit_plan_for_execution(data, plan)
    isempty(plan.fold_rows) &&
        return _loo_refit_empty_result(data, plan, plan_diagnostics)

    fold_logliks = Matrix{Float64}[]
    fold_fits = _ModelComparisonFit[]
    fit_rows = NamedTuple[]
    training_experimental = _refit_training_experimental(checked_spec, experimental)
    for fold_row in plan.fold_rows
        heldout_observations = _kfold_plan_checked_observations(
            data,
            fold_row.heldout_observations,
            "loo_refit heldout_observations",
        )
        length(heldout_observations) == 1 ||
            throw(ArgumentError(
                "loo_refit expects each fold row to hold out exactly one observation"))
        training_observations = _kfold_plan_checked_observations(
            data,
            fold_row.training_observations,
            "loo_refit training_observations",
        )
        training_data = _loo_refit_training_data(data, training_observations)
        training_spec = _refit_training_spec(checked_spec, training_data)
        training_fit = fit(training_spec; prior, experimental = training_experimental, kwargs...)
        score_design =
            _loo_refit_score_design(data, training_fit.design, heldout_observations)
        push!(fold_logliks, _refit_score_loglikelihood(score_design, training_fit))
        return_fits && push!(fold_fits, training_fit)
        push!(fit_rows,
            _refit_fit_row(
                fold_row,
                heldout_observations,
                training_observations,
                training_fit,
                training_experimental,
            ))
    end

    kfold_summary = kfold(
        fold_logliks;
        fold_ids = plan.folds,
        observation_indices = plan.heldout_observation_indices,
    )
    return (;
        kfold_summary...,
        schema = "bayesianmgmfrm.loo_refit.v1",
        object = :loo_refit,
        refit_method = :exact_leave_one_observation_out_refit,
        plan_schema = hasproperty(plan, :schema) ? plan.schema : missing,
        n_refits = length(plan.fold_rows),
        n_total_observations = data.n,
        fold_rows = copy(plan.fold_rows),
        fit_rows,
        fold_logliks,
        fold_fits = return_fits ? fold_fits : nothing,
        kfold_summary,
        plan_diagnostics,
    )
end

function loo_refit(data::FacetData, plan = loo_refit_plan(data);
        thresholds::Symbol = :partial_credit,
        kwargs...)
    return loo_refit(mfrm_spec(data; thresholds), plan; kwargs...)
end

loo_refit(design::FacetDesign, plan = loo_refit_plan(design); kwargs...) =
    loo_refit(design.spec, plan; kwargs...)

function loo_refit(fit::_ModelComparisonFit, plan = loo_refit_plan(fit.design);
        prior = fit.prior,
        experimental::Bool = _refit_fit_experimental_default(fit),
        kwargs...)
    return loo_refit(fit.design.spec, plan; prior, experimental, kwargs...)
end

function _check_refit_plan_count(value, expected::Int, name::AbstractString)
    value isa Integer && !(value isa Bool) && value == expected ||
        throw(ArgumentError("invalid refit plan: $name must equal $expected"))
    return nothing
end

function _check_refit_plan_partition(data::FacetData, plan; loo::Bool)
    for field in (:n_observations, :n_folds, :folds, :heldout_observation_indices)
        hasproperty(plan, field) || throw(ArgumentError("invalid refit plan: missing $field"))
    end
    n = length(plan.fold_rows)
    _check_refit_plan_count(plan.n_observations, data.n, "n_observations")
    _check_refit_plan_count(plan.n_folds, n, "n_folds")
    loo || n >= 2 || throw(ArgumentError("invalid refit plan: K-fold requires at least two folds"))
    plan.folds === nothing && throw(ArgumentError("invalid refit plan: explicit fold IDs required"))
    folds = _kfold_fold_ids(n, plan.folds)
    group_by = hasproperty(plan, :group_by) ? plan.group_by : :observation
    group_by isa Union{Nothing,Symbol} || throw(ArgumentError("invalid refit plan: invalid group_by"))
    loo && !(group_by in (nothing, :observation)) &&
        throw(ArgumentError("invalid refit plan: LOO must hold out individual observations"))
    units = _kfold_plan_units(data, group_by)
    heldout_by_fold = Vector{Int}[]
    counts = Int[]
    seen = falses(data.n)
    observation_fold = Any[missing for _ in 1:data.n]
    # Validate every fold before the caller starts its first fit.
    for (index, row) in enumerate(plan.fold_rows)
        all(field -> hasproperty(row, field),
            (:fold, :heldout_observations, :training_observations)) ||
            throw(ArgumentError("invalid refit plan: incomplete fold row $index"))
        if row.heldout_observations === nothing || row.training_observations === nothing
            throw(ArgumentError("invalid refit plan: explicit training and heldout rows required"))
        end
        heldout = _check_observation_indices(data, row.heldout_observations, "invalid refit plan heldout")
        training = _check_observation_indices(data, row.training_observations, "invalid refit plan training")
        !isempty(heldout) && !isempty(training) ||
            throw(ArgumentError("invalid refit plan: training and heldout sets must be nonempty"))
        loo && length(heldout) != 1 &&
            throw(ArgumentError("invalid refit plan: LOO requires one heldout row per fold"))
        isempty(intersect(training, heldout)) ||
            throw(ArgumentError("invalid refit plan: training and heldout observations overlap"))
        sort(vcat(training, heldout)) == collect(1:data.n) ||
            throw(ArgumentError("invalid refit plan: training must be the full heldout complement"))
        any(seen[heldout]) && throw(ArgumentError("invalid refit plan: heldout observations repeat across folds"))
        isequal(row.fold, folds[index]) ||
            throw(ArgumentError("invalid refit plan: fold IDs disagree with fold rows"))
        seen[heldout] .= true
        observation_fold[heldout] .= Ref(row.fold)
        push!(heldout_by_fold, heldout); push!(counts, length(heldout))
        for (field, expected) in ((:n_heldout_observations, length(heldout)),
                (:n_training_observations, length(training)))
            hasproperty(row, field) && _check_refit_plan_count(getproperty(row, field), expected, string(field))
        end
        selected = Set(heldout)
        unit_indices = findall(rows -> any(in(selected), rows), units.rows)
        all(i -> all(in(selected), units.rows[i]), unit_indices) ||
            throw(ArgumentError("invalid refit plan: a declared grouping unit spans training and heldout"))
        if hasproperty(row, :heldout_units)
            labels = row.heldout_units
            length(labels) == length(unit_indices) && Set(labels) == Set(units.levels[unit_indices]) ||
                throw(ArgumentError("invalid refit plan: heldout unit labels disagree with rows"))
        end
        hasproperty(row, :n_heldout_units) &&
            _check_refit_plan_count(row.n_heldout_units, length(unit_indices), "n_heldout_units")
    end
    loo || all(seen) || throw(ArgumentError("invalid refit plan: K-fold must hold out every observation once"))
    plan.heldout_observation_indices === nothing &&
        throw(ArgumentError("invalid refit plan: explicit scored observation IDs required"))
    expected_indices = isempty(heldout_by_fold) ? Int[] : vcat(heldout_by_fold...)
    isequal(_kfold_observation_indices(counts, plan.heldout_observation_indices), expected_indices) ||
        throw(ArgumentError("invalid refit plan: scored observation IDs disagree with heldout row order"))
    for (field, expected) in ((:n_heldout_by_fold, counts), (:observation_fold, observation_fold))
        hasproperty(plan, field) && !isequal(getproperty(plan, field), expected) &&
            throw(ArgumentError("invalid refit plan: $field disagrees with fold rows"))
    end
    for (field, expected) in ((:k, n), (:n_refits, n), (:refits_per_model_required, n), (:n_units, length(units.rows)))
        hasproperty(plan, field) && _check_refit_plan_count(getproperty(plan, field), expected, string(field))
    end
    return nothing
end

function _check_kfold_refit_plan_for_execution(data::FacetData, plan)
    hasproperty(plan, :object) && plan.object === :kfold_plan ||
        throw(ArgumentError("kfold_refit requires a kfold_plan result"))
    hasproperty(plan, :fold_rows) ||
        throw(ArgumentError("kfold_refit plan must contain fold_rows"))
    isempty(plan.fold_rows) &&
        throw(ArgumentError("kfold_refit requires at least one fold row"))
    _check_refit_plan_partition(data, plan; loo = false)
    # Current supported refit likelihoods do not fit optional metadata levels.
    diagnostics = kfold_plan_diagnostics(data, plan;
        facets = (:person, :rater, :item, :category))
    diagnostics.passed ||
        throw(ArgumentError(
            "kfold_refit plan has heldout-only facet levels; inspect kfold_plan_diagnostics"))
    return diagnostics
end

"""
    kfold_refit(data::FacetData, plan; thresholds = :partial_credit,
        prior = MFRMPrior(), return_fits = false, kwargs...)
    kfold_refit(data::FacetData; k, group_by = nothing, shuffle = false,
        rng = Random.default_rng(), fold_ids = nothing, thresholds = :partial_credit,
        kwargs...)
    kfold_refit(spec::FacetSpec, plan; prior = model default,
        experimental = false, return_fits = false, kwargs...)
    kfold_refit(spec::FacetSpec; k, group_by = nothing, shuffle = false,
        rng = Random.default_rng(), fold_ids = nothing, kwargs...)
    kfold_refit(design::FacetDesign, plan; kwargs...)
    kfold_refit(fit::Union{MFRMFit,GMFRMFit,MGMFRMFit}, plan; kwargs...)

Execute heldout K-fold refits for a [`kfold_plan`](@ref) under the current
fit-supported MFRM/RSM/PCM likelihood, or under the documented
GMFRM/MGMFRM likelihood when `experimental = true` is supplied. Each fold is
refit on its training observations, scored on all heldout observations in that
fold, and summarized with the same heldout log-score contract as [`kfold`](@ref).

All folds are validated before the first fit. Each training set must be the full
heldout complement; K-fold holds out every observation exactly once, with at
least two nonempty folds. Declared grouping units cannot span training and
heldout. Fold IDs, counts, observation-to-fold maps and scored-row labels must
agree with the fold rows, including their heldout order. Training specs retain
dimension labels and remap Q by item label.
Plans are also checked with [`kfold_plan_diagnostics`](@ref); rows
with heldout-only person, rater, item, or score-category levels
are rejected because the heldout observations cannot be scored against the
training-fold parameter map. Optional facets are metadata in these supported
likelihoods, so `group_by = :response_id` or `:occasion` can keep whole rating
events together without rejecting their heldout-only labels. Those labels are
preserved for reporting and add no fitted effects. The general
`kfold_plan_diagnostics` default still audits all facets. Scores remain
pointwise marginal log scores; grouping the split does not turn their sum into
a joint predictive score for a whole event.
"""
function kfold_refit(spec::FacetSpec, plan;
        prior = _refit_default_prior(spec),
        experimental::Bool = false,
        return_fits::Bool = false,
        kwargs...)
    checked_spec = _check_loo_refit_spec(spec; experimental)
    data = checked_spec.data
    plan_diagnostics = _check_kfold_refit_plan_for_execution(data, plan)

    fold_logliks = Matrix{Float64}[]
    fold_fits = _ModelComparisonFit[]
    fit_rows = NamedTuple[]
    training_experimental = _refit_training_experimental(checked_spec, experimental)
    for fold_row in plan.fold_rows
        heldout_observations = _kfold_plan_checked_observations(
            data,
            fold_row.heldout_observations,
            "kfold_refit heldout_observations",
        )
        isempty(heldout_observations) &&
            throw(ArgumentError("kfold_refit fold rows must hold out at least one observation"))
        training_observations = _kfold_plan_checked_observations(
            data,
            fold_row.training_observations,
            "kfold_refit training_observations",
        )
        training_data = _loo_refit_training_data(data, training_observations)
        training_spec = _refit_training_spec(checked_spec, training_data)
        training_fit = fit(training_spec; prior, experimental = training_experimental, kwargs...)
        score_design =
            _loo_refit_score_design(data, training_fit.design, heldout_observations)
        push!(fold_logliks, _refit_score_loglikelihood(score_design, training_fit))
        return_fits && push!(fold_fits, training_fit)
        push!(fit_rows,
            _refit_fit_row(
                fold_row,
                heldout_observations,
                training_observations,
                training_fit,
                training_experimental,
            ))
    end

    kfold_summary = kfold(
        fold_logliks;
        fold_ids = plan.folds,
        observation_indices = plan.heldout_observation_indices,
    )
    return (;
        kfold_summary...,
        schema = "bayesianmgmfrm.kfold_refit.v1",
        object = :kfold_refit,
        refit_method = :automatic_kfold_refit,
        plan_schema = hasproperty(plan, :schema) ? plan.schema : missing,
        group_by = hasproperty(plan, :group_by) ? plan.group_by : missing,
        n_refits = length(plan.fold_rows),
        n_total_observations = data.n,
        fold_rows = copy(plan.fold_rows),
        fit_rows,
        fold_logliks,
        fold_fits = return_fits ? fold_fits : nothing,
        kfold_summary,
        plan_diagnostics,
    )
end

function kfold_refit(spec::FacetSpec;
        k::Integer,
        group_by::Union{Nothing,Symbol} = nothing,
        shuffle::Bool = false,
        rng::AbstractRNG = Random.default_rng(),
        fold_ids = nothing,
        kwargs...)
    plan = kfold_plan(spec; k, group_by, shuffle, rng, fold_ids)
    return kfold_refit(spec, plan; kwargs...)
end

function kfold_refit(data::FacetData, plan;
        thresholds::Symbol = :partial_credit,
        kwargs...)
    return kfold_refit(mfrm_spec(data; thresholds), plan; kwargs...)
end

function kfold_refit(data::FacetData;
        k::Integer,
        group_by::Union{Nothing,Symbol} = nothing,
        shuffle::Bool = false,
        rng::AbstractRNG = Random.default_rng(),
        fold_ids = nothing,
        thresholds::Symbol = :partial_credit,
        kwargs...)
    spec = mfrm_spec(data; thresholds)
    plan = kfold_plan(data; k, group_by, shuffle, rng, fold_ids)
    return kfold_refit(spec, plan; kwargs...)
end

kfold_refit(design::FacetDesign, plan; kwargs...) =
    kfold_refit(design.spec, plan; kwargs...)

function kfold_refit(design::FacetDesign;
        k::Integer,
        group_by::Union{Nothing,Symbol} = nothing,
        shuffle::Bool = false,
        rng::AbstractRNG = Random.default_rng(),
        fold_ids = nothing,
        kwargs...)
    plan = kfold_plan(design; k, group_by, shuffle, rng, fold_ids)
    return kfold_refit(design.spec, plan; kwargs...)
end

function kfold_refit(fit::_ModelComparisonFit, plan;
        prior = fit.prior,
        experimental::Bool = _refit_fit_experimental_default(fit),
        kwargs...)
    return kfold_refit(fit.design.spec, plan; prior, experimental, kwargs...)
end

function kfold_refit(fit::_ModelComparisonFit;
        k::Integer,
        group_by::Union{Nothing,Symbol} = nothing,
        shuffle::Bool = false,
        rng::AbstractRNG = Random.default_rng(),
        fold_ids = nothing,
        prior = fit.prior,
        experimental::Bool = _refit_fit_experimental_default(fit),
        kwargs...)
    plan = kfold_plan(fit.design; k, group_by, shuffle, rng, fold_ids)
    return kfold_refit(fit.design.spec, plan; prior, experimental, kwargs...)
end

function _kfold_plan_diagnostic_facet_groups(data::FacetData, facet::Symbol)
    facet === :person && return data.person, data.person_levels
    facet === :rater && return data.rater, data.rater_levels
    facet === :item && return data.item, data.item_levels
    facet === :category && return data.category, data.category_levels
    if haskey(data.optional, facet)
        return data.optional[facet], data.optional_levels[facet]
    end
    throw(ArgumentError(
        "facets contains :$facet, which is not a required or optional facet"))
end

function _kfold_plan_diagnostic_facets(data::FacetData, facets)
    requested = if facets === :all
        Symbol[:person, :rater, :item, :category,
            sort(collect(keys(data.optional)); by = string)...]
    elseif facets isa Symbol
        Symbol[facets]
    else
        Symbol[facet for facet in facets]
    end
    isempty(requested) &&
        throw(ArgumentError("facets must contain at least one facet"))
    length(unique(requested)) == length(requested) ||
        throw(ArgumentError("facets must not contain duplicates"))
    for facet in requested
        _kfold_plan_diagnostic_facet_groups(data, facet)
    end
    return Tuple(requested)
end

function _kfold_plan_checked_observations(data::FacetData, observations, context)
    return _check_observation_indices(data, observations, context)
end

function _kfold_plan_present_levels(index::AbstractVector{Int},
        levels::AbstractVector,
        observations::AbstractVector{Int})
    present = falses(length(levels))
    for observation in observations
        present[index[observation]] = true
    end
    return Tuple(levels[level_index] for level_index in eachindex(levels)
        if present[level_index])
end

function _check_kfold_plan_for_diagnostics(data::FacetData, plan)
    hasproperty(plan, :fold_rows) ||
        throw(ArgumentError("kfold_plan_diagnostics requires a kfold_plan result with fold_rows"))
    hasproperty(plan, :n_observations) &&
        Int(plan.n_observations) == data.n ||
        throw(ArgumentError("kfold_plan n_observations does not match the supplied data"))
    return plan
end

"""
    kfold_plan_diagnostics(data::FacetData, plan; facets = :all)
    kfold_plan_diagnostics(spec::FacetSpec, plan; kwargs...)
    kfold_plan_diagnostics(design::FacetDesign, plan; kwargs...)

Check whether each training fold in a [`kfold_plan`](@ref) retains the levels
needed to score its heldout observations. Rows are reported by fold and facet
for person, rater, item, score category, and optional facets by default. A row
with `refit_blocker = true` has heldout-only levels for that facet, so an
external refit using only that training fold would need a fixed level map,
pooled treatment, or a different fold assignment before heldout scoring.
This is a level-availability audit, not a partition-integrity or source-data
identity certificate. Automatic `kfold_refit` and `loo_refit` additionally check
the complete partition and scoring metadata before starting any fits. Plan row
indices remain positional and must refer to the supplied source data/order.
"""
function kfold_plan_diagnostics(data::FacetData, plan; facets = :all)
    checked_plan = _check_kfold_plan_for_diagnostics(data, plan)
    checked_facets = _kfold_plan_diagnostic_facets(data, facets)
    rows = NamedTuple[]
    for fold_row in checked_plan.fold_rows
        hasproperty(fold_row, :fold) ||
            throw(ArgumentError("kfold_plan fold_rows must contain :fold"))
        training_observations = _kfold_plan_checked_observations(
            data,
            fold_row.training_observations,
            "kfold_plan_diagnostics training_observations",
        )
        heldout_observations = _kfold_plan_checked_observations(
            data,
            fold_row.heldout_observations,
            "kfold_plan_diagnostics heldout_observations",
        )
        for facet in checked_facets
            index, levels = _kfold_plan_diagnostic_facet_groups(data, facet)
            training_levels = _kfold_plan_present_levels(
                index,
                levels,
                training_observations,
            )
            heldout_levels = _kfold_plan_present_levels(
                index,
                levels,
                heldout_observations,
            )
            training_set = Set(training_levels)
            heldout_only_levels =
                Tuple(level for level in heldout_levels if !(level in training_set))
            status = isempty(heldout_only_levels) ? :ok : :heldout_only_levels
            push!(rows, (;
                fold = fold_row.fold,
                facet,
                n_levels = length(levels),
                n_training_observations = length(training_observations),
                n_heldout_observations = length(heldout_observations),
                n_training_levels = length(training_levels),
                n_heldout_levels = length(heldout_levels),
                n_heldout_only_levels = length(heldout_only_levels),
                heldout_only_levels,
                training_levels,
                heldout_levels,
                refit_blocker = !isempty(heldout_only_levels),
                status,
            ))
        end
    end
    n_blocking_rows = count(row -> row.refit_blocker, rows)
    return (;
        schema = "bayesianmgmfrm.kfold_plan_diagnostics.v1",
        object = :kfold_plan_diagnostics,
        plan_schema = hasproperty(checked_plan, :schema) ? checked_plan.schema : missing,
        group_by = hasproperty(checked_plan, :group_by) ? checked_plan.group_by : missing,
        n_folds = length(checked_plan.fold_rows),
        n_observations = data.n,
        facets = checked_facets,
        rows,
        n_rows = length(rows),
        n_blocking_rows,
        passed = n_blocking_rows == 0,
        warning = n_blocking_rows == 0 ? :ok : :heldout_only_levels,
    )
end

kfold_plan_diagnostics(spec::FacetSpec, plan; kwargs...) =
    kfold_plan_diagnostics(spec.data, plan; kwargs...)
kfold_plan_diagnostics(design::FacetDesign, plan; kwargs...) =
    kfold_plan_diagnostics(design.spec.data, plan; kwargs...)

"""
    kfold(fold_logliks; fold_ids = nothing, observation_indices = nothing)
    kfold(loglik::AbstractMatrix; fold_ids = nothing, observation_indices = nothing)

Summarize heldout K-fold log predictive density from fold-specific refits. Each
fold log-likelihood matrix must be draws-by-heldout-observations and contain
posterior pointwise log-likelihood draws for observations that were not used to
fit that fold. The returned named tuple includes `elpd_kfold`, `kfoldic`,
standard errors, fold sizes, observation identifiers, and pointwise heldout
components.

This helper does not refit models. Use [`kfold_plan`](@ref) to construct
observation or grouped heldout folds, then use `kfold` to record exact
heldout-refit or K-fold follow-up evidence after fitting each training fold.
"""
function kfold(fold_logliks::Union{Tuple,AbstractVector};
        fold_ids = nothing,
        observation_indices = nothing)
    matrices = collect(fold_logliks)
    n_folds = length(matrices)
    n_folds >= 1 || throw(ArgumentError("K-fold requires at least one fold"))
    all(matrix -> matrix isa AbstractMatrix, matrices) ||
        throw(ArgumentError("K-fold inputs must be log-likelihood matrices"))

    n_draws_by_fold = Int[]
    n_heldout_by_fold = Int[]
    for (fold_index, matrix) in pairs(matrices)
        n_draws, n_heldout = _check_kfold_loglik(matrix, fold_index)
        push!(n_draws_by_fold, n_draws)
        push!(n_heldout_by_fold, n_heldout)
    end

    checked_fold_ids = _kfold_fold_ids(n_folds, fold_ids)
    checked_observation_indices =
        _kfold_observation_indices(n_heldout_by_fold, observation_indices)

    point_elpd = Float64[]
    point_kfoldic = Float64[]
    point_fold = Any[]
    point_observation = Any[]
    observation_offset = 0
    for (fold_index, matrix) in pairs(matrices)
        fold_id = checked_fold_ids[fold_index]
        n_heldout = n_heldout_by_fold[fold_index]
        for heldout_index in 1:n_heldout
            observation_offset += 1
            heldout_elpd = _logmeanexp(@view matrix[:, heldout_index])
            push!(point_elpd, heldout_elpd)
            push!(point_kfoldic, -2 * heldout_elpd)
            push!(point_fold, fold_id)
            push!(point_observation, checked_observation_indices[observation_offset])
        end
    end

    elpd_kfold = sum(point_elpd)
    kfoldic_value = sum(point_kfoldic)
    return (;
        criterion = :kfold,
        method = :heldout_refit_log_score,
        prediction_target = :heldout_observation_log_score,
        elpd_kfold,
        kfoldic = kfoldic_value,
        se_elpd_kfold = _pointwise_se(point_elpd),
        se_kfoldic = _pointwise_se(point_kfoldic),
        pointwise = (;
            elpd_heldout = point_elpd,
            kfoldic = point_kfoldic,
            fold = point_fold,
            observation = point_observation,
        ),
        n_folds,
        n_observations = length(point_elpd),
        n_draws_by_fold,
        n_heldout_by_fold,
        folds = copy(checked_fold_ids),
        observation_indices = copy(point_observation),
        warning = :ok,
    )
end

function kfold(loglik::AbstractMatrix;
        fold_ids = nothing,
        observation_indices = nothing)
    return kfold([loglik]; fold_ids, observation_indices)
end

function _check_waic_threshold(threshold::Real)
    isfinite(threshold) && threshold >= 0 ||
        throw(ArgumentError("threshold must be finite and non-negative"))
    return Float64(threshold)
end

_check_loo_threshold(threshold::Real) = _check_waic_threshold(threshold)

function _optional_observation_labels(data::FacetData, observation::Int)
    facets = Tuple(sort(collect(keys(data.optional)); by = string))
    values = Tuple(data.optional_levels[facet][data.optional[facet][observation]]
        for facet in facets)
    return NamedTuple{facets}(values)
end

function _waic_diagnostic_flag(p_waic::Float64, threshold::Float64)
    return p_waic > threshold ? :high_loglik_variance : :ok
end

function _waic_diagnostics_rows(stat;
        threshold::Float64,
        only_flagged::Bool)
    rows = NamedTuple[]
    for observation in 1:stat.n_observations
        p_waic = stat.pointwise.p_waic[observation]
        flag = _waic_diagnostic_flag(p_waic, threshold)
        only_flagged && flag === :ok && continue
        push!(rows, (;
            observation,
            criterion = :waic,
            lppd = stat.pointwise.lppd[observation],
            p_waic,
            elpd_waic = stat.pointwise.elpd_waic[observation],
            waic = stat.pointwise.waic[observation],
            threshold,
            flag,
        ))
    end
    return rows
end

function _waic_diagnostics_rows(design::FacetDesign, stat;
        threshold::Float64,
        only_flagged::Bool)
    data = design.spec.data
    rows = NamedTuple[]
    for observation in 1:stat.n_observations
        p_waic = stat.pointwise.p_waic[observation]
        flag = _waic_diagnostic_flag(p_waic, threshold)
        only_flagged && flag === :ok && continue
        push!(rows, (;
            observation,
            person = data.person_levels[data.person[observation]],
            rater = data.rater_levels[data.rater[observation]],
            item = data.item_levels[data.item[observation]],
            score = data.score[observation],
            category = data.category_levels[data.category[observation]],
            optional = _optional_observation_labels(data, observation),
            criterion = :waic,
            lppd = stat.pointwise.lppd[observation],
            p_waic,
            elpd_waic = stat.pointwise.elpd_waic[observation],
            waic = stat.pointwise.waic[observation],
            threshold,
            flag,
        ))
    end
    return rows
end

function _loo_diagnostics_rows(stat;
        threshold::Float64,
        only_flagged::Bool)
    rows = NamedTuple[]
    for observation in 1:stat.n_observations
        pareto_k = stat.pointwise.pareto_k[observation]
        flag = _loo_diagnostic_flag(pareto_k, threshold)
        only_flagged && flag === :ok && continue
        push!(rows, (;
            observation,
            criterion = :loo,
            method = stat.method,
            psis_smoothing = stat.psis_smoothing,
            lppd = stat.pointwise.lppd[observation],
            p_loo = stat.pointwise.p_loo[observation],
            elpd_loo = stat.pointwise.elpd_loo[observation],
            looic = stat.pointwise.looic[observation],
            pareto_k,
            effective_sample_size =
                stat.pointwise.effective_sample_size[observation],
            tail_draws = stat.pointwise.tail_draws[observation],
            threshold,
            flag,
        ))
    end
    return rows
end

function _loo_diagnostics_rows(design::FacetDesign, stat;
        threshold::Float64,
        only_flagged::Bool)
    data = design.spec.data
    rows = NamedTuple[]
    for observation in 1:stat.n_observations
        pareto_k = stat.pointwise.pareto_k[observation]
        flag = _loo_diagnostic_flag(pareto_k, threshold)
        only_flagged && flag === :ok && continue
        push!(rows, (;
            observation,
            person = data.person_levels[data.person[observation]],
            rater = data.rater_levels[data.rater[observation]],
            item = data.item_levels[data.item[observation]],
            score = data.score[observation],
            category = data.category_levels[data.category[observation]],
            optional = _optional_observation_labels(data, observation),
            criterion = :loo,
            method = stat.method,
            psis_smoothing = stat.psis_smoothing,
            lppd = stat.pointwise.lppd[observation],
            p_loo = stat.pointwise.p_loo[observation],
            elpd_loo = stat.pointwise.elpd_loo[observation],
            looic = stat.pointwise.looic[observation],
            pareto_k,
            effective_sample_size =
                stat.pointwise.effective_sample_size[observation],
            tail_draws = stat.pointwise.tail_draws[observation],
            threshold,
            flag,
        ))
    end
    return rows
end

function _check_kfold_diagnostic_stat(stat)
    checked = _check_kfold_stat(stat)
    if hasproperty(checked.pointwise, :observation)
        length(checked.pointwise.observation) == checked.n_observations ||
            throw(ArgumentError(
                "K-fold pointwise observation length does not match n_observations"))
    end
    if hasproperty(checked.pointwise, :kfoldic)
        length(checked.pointwise.kfoldic) == checked.n_observations ||
            throw(ArgumentError(
                "K-fold pointwise K-fold IC length does not match n_observations"))
        all(value -> isfinite(Float64(value)), checked.pointwise.kfoldic) ||
            throw(ArgumentError("K-fold pointwise K-fold IC values must be finite"))
    end
    return checked
end

function _kfold_diagnostic_observation(stat, index::Int)
    return hasproperty(stat.pointwise, :observation) ?
        stat.pointwise.observation[index] :
        stat.observation_indices[index]
end

function _kfold_diagnostic_kfoldic(stat, index::Int)
    return hasproperty(stat.pointwise, :kfoldic) ?
        Float64(stat.pointwise.kfoldic[index]) :
        -2 * Float64(stat.pointwise.elpd_heldout[index])
end

function _kfold_diagnostics_rows(stat)
    checked = _check_kfold_diagnostic_stat(stat)
    rows = NamedTuple[]
    for index in 1:checked.n_observations
        push!(rows, (;
            heldout_index = index,
            observation = _kfold_diagnostic_observation(checked, index),
            fold = checked.pointwise.fold[index],
            criterion = :kfold,
            method = checked.method,
            prediction_target = checked.prediction_target,
            elpd_heldout = Float64(checked.pointwise.elpd_heldout[index]),
            kfoldic = _kfold_diagnostic_kfoldic(checked, index),
            flag = checked.warning,
        ))
    end
    return rows
end

function _kfold_diagnostics_rows(data::FacetData, stat)
    checked = _check_kfold_diagnostic_stat(stat)
    observations = _check_observation_indices(
        data,
        checked.observation_indices,
        "kfold_diagnostics observation_indices",
    )
    rows = NamedTuple[]
    for index in 1:checked.n_observations
        observation = observations[index]
        push!(rows, (;
            heldout_index = index,
            observation,
            person = data.person_levels[data.person[observation]],
            rater = data.rater_levels[data.rater[observation]],
            item = data.item_levels[data.item[observation]],
            score = data.score[observation],
            category = data.category_levels[data.category[observation]],
            optional = _optional_observation_labels(data, observation),
            fold = checked.pointwise.fold[index],
            criterion = :kfold,
            method = checked.method,
            prediction_target = checked.prediction_target,
            elpd_heldout = Float64(checked.pointwise.elpd_heldout[index]),
            kfoldic = _kfold_diagnostic_kfoldic(checked, index),
            flag = checked.warning,
        ))
    end
    return rows
end

"""
    waic_diagnostics(fit::MFRMFit; threshold = 0.4, only_flagged = false,
        ndraws = nothing, draw_indices = nothing, rng = Random.default_rng())
    waic_diagnostics(design::FacetDesign, draws; threshold = 0.4,
        only_flagged = false, parameter_space = :direct)
    waic_diagnostics(loglik::AbstractMatrix; threshold = 0.4,
        only_flagged = false)

Return observation-level WAIC diagnostics. Rows include pointwise `lppd`,
`p_waic`, `elpd_waic`, WAIC contribution, and a flag for observations whose
`p_waic` exceeds `threshold`. When a `FacetDesign` or fit object is supplied,
rows also include person, rater, item, score, category, and optional facet
labels. Use `parameter_space = :raw` for raw GMFRM/MGMFRM preview-design
draws. Use this helper to locate observations behind a WAIC
`:high_loglik_variance` warning before interpreting model-comparison rows.
"""
function waic_diagnostics(loglik::AbstractMatrix;
        threshold::Real = 0.4,
        only_flagged::Bool = false)
    checked_threshold = _check_waic_threshold(threshold)
    return _waic_diagnostics_rows(waic(loglik);
        threshold = checked_threshold,
        only_flagged)
end

function waic_diagnostics(design::FacetDesign,
        draws::AbstractMatrix;
        threshold::Real = 0.4,
        only_flagged::Bool = false,
        parameter_space::Symbol = :direct)
    checked_threshold = _check_waic_threshold(threshold)
    return _waic_diagnostics_rows(design, waic(design, draws; parameter_space);
        threshold = checked_threshold,
        only_flagged)
end

function waic_diagnostics(fit::MFRMFit;
        threshold::Real = 0.4,
        only_flagged::Bool = false,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    checked_threshold = _check_waic_threshold(threshold)
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return _waic_diagnostics_rows(fit.design, waic(fit.design, fit.draws[indices, :]);
        threshold = checked_threshold,
        only_flagged)
end

function waic_diagnostics(fit::GMFRMFit;
        threshold::Real = 0.4,
        only_flagged::Bool = false,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    checked_threshold = _check_waic_threshold(threshold)
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return _waic_diagnostics_rows(
        fit.design,
        waic(fit.direct_pointwise_loglikelihood[indices, :]);
        threshold = checked_threshold,
        only_flagged)
end

function waic_diagnostics(fit::MGMFRMFit;
        threshold::Real = 0.4,
        only_flagged::Bool = false,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    checked_threshold = _check_waic_threshold(threshold)
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return _waic_diagnostics_rows(
        fit.design,
        waic(fit.direct_pointwise_loglikelihood[indices, :]);
        threshold = checked_threshold,
        only_flagged)
end

"""
    loo_diagnostics(fit::MFRMFit; threshold = 0.7, only_flagged = false,
        ndraws = nothing, draw_indices = nothing, rng = Random.default_rng(),
        tail_fraction = 0.2, min_tail_draws = 5, psis_smoothing = false)
    loo_diagnostics(design::FacetDesign, draws; threshold = 0.7,
        only_flagged = false, tail_fraction = 0.2, min_tail_draws = 5,
        psis_smoothing = false, parameter_space = :direct)
    loo_diagnostics(loglik::AbstractMatrix; threshold = 0.7,
        only_flagged = false, tail_fraction = 0.2, min_tail_draws = 5,
        psis_smoothing = false)

Return observation-level LOO diagnostics. Rows include
pointwise `lppd`, `p_loo`, `elpd_loo`, LOOIC contribution,
importance-sampling effective sample size, `pareto_k`, and a
flag for observations whose `pareto_k` exceeds `threshold`. The raw-IS route
uses a Hill tail estimate; `psis_smoothing=true` uses standard PSIS and its
fitted-tail estimate, with chain efficiency when supplied. When a
`FacetDesign` or fit object is supplied, rows also include person, rater, item,
score, category, and optional facet labels. Use `parameter_space = :raw` for
raw GMFRM/MGMFRM preview-design draws. Set `psis_smoothing = true` to report
diagnostics from [`psis_loo`](@ref) instead of raw importance-sampling [`loo`](@ref).
"""
function loo_diagnostics(loglik::AbstractMatrix;
        threshold::Real = 0.7,
        only_flagged::Bool = false,
        tail_fraction::Real = 0.2,
        min_tail_draws::Int = 5,
        psis_smoothing::Bool = false,
        chain_ids=nothing, r_eff=nothing)
    checked_threshold = _check_loo_threshold(threshold)
    stat = psis_smoothing ?
        psis_loo(loglik; chain_ids, r_eff,
            pareto_k_threshold = checked_threshold,
            tail_fraction,
            min_tail_draws) :
        loo(loglik;
            pareto_k_threshold = checked_threshold,
            tail_fraction,
            min_tail_draws)
    return _loo_diagnostics_rows(
        stat;
        threshold = checked_threshold,
        only_flagged)
end

function loo_diagnostics(design::FacetDesign,
        draws::AbstractMatrix;
        threshold::Real = 0.7,
        only_flagged::Bool = false,
        tail_fraction::Real = 0.2,
        min_tail_draws::Int = 5,
        psis_smoothing::Bool = false,
        parameter_space::Symbol = :direct, chain_ids=nothing, r_eff=nothing)
    checked_threshold = _check_loo_threshold(threshold)
    stat = psis_smoothing ?
        psis_loo(design, draws; chain_ids, r_eff,
            pareto_k_threshold = checked_threshold,
            tail_fraction,
            min_tail_draws,
            parameter_space) :
        loo(design, draws;
            pareto_k_threshold = checked_threshold,
            tail_fraction,
            min_tail_draws,
            parameter_space)
    return _loo_diagnostics_rows(
        design,
        stat;
        threshold = checked_threshold,
        only_flagged)
end

function loo_diagnostics(fit::MFRMFit;
        threshold::Real = 0.7,
        only_flagged::Bool = false,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng(),
        tail_fraction::Real = 0.2,
        min_tail_draws::Int = 5,
        psis_smoothing::Bool = false)
    checked_threshold = _check_loo_threshold(threshold)
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    stat = psis_smoothing ?
        psis_loo(fit; ndraws, draw_indices, rng,
            pareto_k_threshold = checked_threshold,
            tail_fraction,
            min_tail_draws) :
        loo(fit.design, fit.draws[indices, :];
            pareto_k_threshold = checked_threshold,
            tail_fraction,
            min_tail_draws)
    return _loo_diagnostics_rows(
        fit.design,
        stat;
        threshold = checked_threshold,
        only_flagged)
end

function loo_diagnostics(fit::GMFRMFit;
        threshold::Real = 0.7,
        only_flagged::Bool = false,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng(),
        tail_fraction::Real = 0.2,
        min_tail_draws::Int = 5,
        psis_smoothing::Bool = false)
    checked_threshold = _check_loo_threshold(threshold)
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    stat = psis_smoothing ?
        psis_loo(fit; ndraws, draw_indices, rng,
            pareto_k_threshold = checked_threshold,
            tail_fraction,
            min_tail_draws) :
        loo(fit.direct_pointwise_loglikelihood[indices, :];
            pareto_k_threshold = checked_threshold,
            tail_fraction,
            min_tail_draws)
    return _loo_diagnostics_rows(
        fit.design,
        stat;
        threshold = checked_threshold,
        only_flagged)
end

function loo_diagnostics(fit::MGMFRMFit;
        threshold::Real = 0.7,
        only_flagged::Bool = false,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng(),
        tail_fraction::Real = 0.2,
        min_tail_draws::Int = 5,
        psis_smoothing::Bool = false)
    checked_threshold = _check_loo_threshold(threshold)
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    stat = psis_smoothing ?
        psis_loo(fit; ndraws, draw_indices, rng,
            pareto_k_threshold = checked_threshold,
            tail_fraction,
            min_tail_draws) :
        loo(fit.direct_pointwise_loglikelihood[indices, :];
            pareto_k_threshold = checked_threshold,
            tail_fraction,
            min_tail_draws)
    return _loo_diagnostics_rows(
        fit.design,
        stat;
        threshold = checked_threshold,
        only_flagged)
end

"""
    kfold_diagnostics(stat)
    kfold_diagnostics(data::FacetData, stat)
    kfold_diagnostics(spec::FacetSpec, stat)
    kfold_diagnostics(design::FacetDesign, stat)

Return observation-level heldout K-fold rows from a [`kfold`](@ref) result.
Rows include heldout index, observation identifier, fold, heldout ELPD, K-fold
information-criterion contribution, method, prediction target, and flag. When
`FacetData`, `FacetSpec`, or `FacetDesign` is supplied, observation identifiers
must be valid data row indices and rows also include person, rater, item, score,
category, and optional facet labels.
"""
function kfold_diagnostics(stat)
    return _kfold_diagnostics_rows(stat)
end

function kfold_diagnostics(data::FacetData, stat)
    return _kfold_diagnostics_rows(data, stat)
end

kfold_diagnostics(spec::FacetSpec, stat) =
    kfold_diagnostics(spec.data, stat)
kfold_diagnostics(design::FacetDesign, stat) =
    kfold_diagnostics(design.spec.data, stat)

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

function _check_kfold_stat(stat)
    required_fields = (
        :criterion,
        :method,
        :prediction_target,
        :elpd_kfold,
        :kfoldic,
        :se_elpd_kfold,
        :se_kfoldic,
        :pointwise,
        :n_folds,
        :n_observations,
        :n_draws_by_fold,
        :n_heldout_by_fold,
        :folds,
        :observation_indices,
        :warning,
    )
    for field in required_fields
        hasproperty(stat, field) ||
            throw(ArgumentError("K-fold statistic is missing field :$field"))
    end
    stat.criterion === :kfold ||
        throw(ArgumentError("K-fold statistic must have criterion = :kfold"))
    hasproperty(stat.pointwise, :elpd_heldout) ||
        throw(ArgumentError("K-fold statistic pointwise data is missing :elpd_heldout"))
    hasproperty(stat.pointwise, :fold) ||
        throw(ArgumentError("K-fold statistic pointwise data is missing :fold"))
    length(stat.pointwise.elpd_heldout) == stat.n_observations ||
        throw(ArgumentError("K-fold pointwise length does not match n_observations"))
    length(stat.pointwise.fold) == stat.n_observations ||
        throw(ArgumentError("K-fold fold length does not match n_observations"))
    length(stat.observation_indices) == stat.n_observations ||
        throw(ArgumentError("K-fold observation_indices length does not match n_observations"))
    isfinite(Float64(stat.elpd_kfold)) && isfinite(Float64(stat.kfoldic)) ||
        throw(ArgumentError("K-fold aggregate values must be finite"))
    all(value -> isfinite(Float64(value)), stat.pointwise.elpd_heldout) ||
        throw(ArgumentError("K-fold pointwise ELPD values must be finite"))
    return stat
end

function _require_kfold_comparison_compatibility(stats::AbstractVector)
    isempty(stats) && return nothing
    first_stat = stats[1]
    first_n_observations = first_stat.n_observations
    first_observation_indices = first_stat.observation_indices
    first_folds = first_stat.pointwise.fold
    first_prediction_target = first_stat.prediction_target
    all(stat -> stat.n_observations == first_n_observations, stats) ||
        throw(ArgumentError("all K-fold statistics must have the same number of heldout observations"))
    all(stat -> isequal(stat.observation_indices, first_observation_indices), stats) ||
        throw(ArgumentError("all K-fold statistics must use the same heldout observation order"))
    all(stat -> isequal(stat.pointwise.fold, first_folds), stats) ||
        throw(ArgumentError("all K-fold statistics must use the same fold assignment order"))
    all(stat -> stat.prediction_target === first_prediction_target, stats) ||
        throw(ArgumentError("all K-fold statistics must use the same prediction target"))
    return nothing
end

function _kfold_comparison_rows(labels::AbstractVector{<:AbstractString},
        stats::AbstractVector)
    n_models = length(stats)
    n_models >= 2 || throw(ArgumentError("at least two models are required"))
    length(labels) == n_models ||
        throw(ArgumentError("labels has length $(length(labels)); expected $n_models"))
    checked_stats = [_check_kfold_stat(stat) for stat in stats]
    _require_kfold_comparison_compatibility(checked_stats)

    order = sortperm(1:n_models; by = i -> checked_stats[i].elpd_kfold, rev = true)
    best = checked_stats[order[1]]
    unnormalized_weights =
        [exp(stat.elpd_kfold - best.elpd_kfold) for stat in checked_stats]
    weight_total = sum(unnormalized_weights)
    rows = NamedTuple[]
    for (rank, index) in pairs(order)
        stat = checked_stats[index]
        pointwise_difference =
            stat.pointwise.elpd_heldout .- best.pointwise.elpd_heldout
        push!(rows, (;
            model = labels[index],
            rank,
            criterion = :kfold,
            comparison_contract = _KFOLD_COMPARISON_CONTRACT,
            method = stat.method,
            prediction_target = stat.prediction_target,
            elpd_kfold = stat.elpd_kfold,
            elpd_difference = stat.elpd_kfold - best.elpd_kfold,
            se_elpd_difference = _pointwise_se(pointwise_difference),
            se_elpd_kfold = stat.se_elpd_kfold,
            kfoldic = stat.kfoldic,
            kfoldic_difference = stat.kfoldic - best.kfoldic,
            se_kfoldic = stat.se_kfoldic,
            relative_weight = unnormalized_weights[index] / weight_total,
            n_folds = stat.n_folds,
            n_observations = stat.n_observations,
            n_draws_by_fold = copy(stat.n_draws_by_fold),
            n_heldout_by_fold = copy(stat.n_heldout_by_fold),
            folds = copy(stat.folds),
            observation_indices = copy(stat.observation_indices),
            warning = stat.warning,
        ))
    end
    return rows
end

"""
    compare_kfold(stats...; names = nothing)
    compare_kfold(models::Pair...)

Compare heldout K-fold summaries returned by [`kfold`](@ref). Rows are sorted
by `elpd_kfold` in descending order and include differences relative to the
best model, K-fold information-criterion differences, normalized
expected-log-predictive-density weights, and a comparison contract requiring
the same heldout observation order and fold assignment order across models.

This helper compares already computed K-fold summaries. It does not construct
folds or refit models.
"""
function compare_kfold(; names = nothing)
    labels = _compare_model_names(names, 0)
    return _kfold_comparison_rows(labels, Any[])
end

function compare_kfold(stats::NamedTuple...; names = nothing)
    labels = _compare_model_names(names, length(stats))
    return _kfold_comparison_rows(labels, Any[stats...])
end

function compare_kfold(models::Pair...)
    stats = Any[]
    labels = String[]
    for model in models
        push!(labels, string(model.first))
        push!(stats, model.second)
    end
    _compare_model_names(labels, length(labels))
    return _kfold_comparison_rows(labels, stats)
end

function _compare_criterion(criterion::Symbol)
    criterion in (:waic, :loo, :psis_loo) ||
        throw(ArgumentError("criterion must be :waic, :loo, or :psis_loo"))
    return criterion
end

function _model_comparison_contract(fit::_ModelComparisonFit)
    spec = fit.design.spec
    data = spec.data
    return (;
        comparison_contract = _MODEL_COMPARISON_CONTRACT,
        model_family = spec.family,
        thresholds = spec.thresholds,
        dimensions = spec.dimensions,
        discrimination = spec.discrimination,
        q_matrix = _q_matrix_manifest(spec.q_matrix),
        estimation_status = spec.estimation_status,
        data_signature = spec.validation.data_signature,
        n_observations = data.n,
        n_categories = length(data.category_levels),
        category_levels = copy(data.category_levels),
        n_persons = length(data.person_levels),
        n_raters = length(data.rater_levels),
        n_items = length(data.item_levels),
        optional_facets = sort(collect(keys(data.optional)); by = string),
    )
end

function _require_same_contract_field(
        contracts::AbstractVector,
        field::Symbol,
        message::AbstractString)
    isempty(contracts) && return nothing
    first_value = getproperty(contracts[1], field)
    all(contract -> isequal(getproperty(contract, field), first_value), contracts) ||
        throw(ArgumentError(message))
    return nothing
end

function _require_model_comparison_compatibility(contracts::AbstractVector)
    isempty(contracts) && return nothing
    _require_same_contract_field(contracts, :data_signature,
        "all models must be fit to the same observation data and row order; call waic on each model separately for different data")
    _require_same_contract_field(contracts, :n_observations,
        "all models must have the same number of observations")
    _require_same_contract_field(contracts, :category_levels,
        "all models must use the same ordinal category levels")
    _require_same_contract_field(contracts, :optional_facets,
        "all models must use the same optional facet roles")
    _require_same_contract_field(contracts, :dimensions,
        "all models must use the same latent dimensionality; use a predeclared sensitivity workflow for dimensionality comparisons")
    _require_same_contract_field(contracts, :q_matrix,
        "all multidimensional models must use the same fixed Q-matrix for direct compare_models output")
    return nothing
end

function _require_sensitivity_comparison_compatibility(contracts::AbstractVector,
        axis::Symbol)
    isempty(contracts) && return nothing
    _require_same_contract_field(contracts, :data_signature,
        "all sensitivity candidates must be fit to the same observation data and row order")
    _require_same_contract_field(contracts, :n_observations,
        "all sensitivity candidates must have the same number of observations")
    _require_same_contract_field(contracts, :category_levels,
        "all sensitivity candidates must use the same ordinal category levels")
    _require_same_contract_field(contracts, :optional_facets,
        "all sensitivity candidates must use the same optional facet roles")
    if axis !== :dimensions
        _require_same_contract_field(contracts, :dimensions,
            "all sensitivity candidates must use the same latent dimensionality unless axis = :dimensions")
    end
    if !(axis in (:dimensions, :q_matrix))
        _require_same_contract_field(contracts, :q_matrix,
            "all sensitivity candidates must use the same fixed Q-matrix unless axis = :q_matrix or :dimensions")
    end
    return nothing
end

function _comparison_contract_fields(contract::NamedTuple)
    return (;
        comparison_contract = contract.comparison_contract,
        model_family = contract.model_family,
        thresholds = contract.thresholds,
        dimensions = contract.dimensions,
        discrimination = contract.discrimination,
        q_matrix = contract.q_matrix,
        estimation_status = contract.estimation_status,
        data_signature = contract.data_signature,
        n_categories = contract.n_categories,
        category_levels = copy(contract.category_levels),
        n_persons = contract.n_persons,
        n_raters = contract.n_raters,
        n_items = contract.n_items,
        optional_facets = copy(contract.optional_facets),
    )
end

function _waic_comparison_rows(labels::AbstractVector{<:AbstractString}, stats,
        contracts::AbstractVector)
    n_models = length(stats)
    n_models >= 2 || throw(ArgumentError("at least two models are required"))
    length(contracts) == n_models ||
        throw(ArgumentError("contracts has length $(length(contracts)); expected $n_models"))
    n_observations = stats[1].n_observations
    all(stat -> stat.n_observations == n_observations, stats) ||
        throw(ArgumentError("all models must have the same number of observations"))

    order = sortperm(1:n_models; by = i -> stats[i].elpd_waic, rev = true)
    best = stats[order[1]]
    unnormalized_weights = [exp(stat.elpd_waic - best.elpd_waic) for stat in stats]
    weight_total = sum(unnormalized_weights)
    rows = NamedTuple[]
    for (rank, index) in pairs(order)
        stat = stats[index]
        pointwise_difference = stat.pointwise.elpd_waic .- best.pointwise.elpd_waic
        push!(rows, merge((;
                model = labels[index],
                rank,
                criterion = :waic,
            ),
            _comparison_contract_fields(contracts[index]),
            (;
                elpd_waic = stat.elpd_waic,
                elpd_difference = stat.elpd_waic - best.elpd_waic,
                se_elpd_difference = _pointwise_se(pointwise_difference),
                se_elpd_waic = stat.se_elpd_waic,
                waic = stat.waic,
                waic_difference = stat.waic - best.waic,
                se_waic = stat.se_waic,
                relative_weight = unnormalized_weights[index] / weight_total,
                p_waic = stat.p_waic,
                lppd = stat.lppd,
                n_draws = stat.n_draws,
                n_observations = stat.n_observations,
                high_variance_count = stat.high_variance_count,
                warning = stat.warning,
            )))
    end
    return rows
end

function _loo_comparison_rows(labels::AbstractVector{<:AbstractString}, stats,
        contracts::AbstractVector)
    n_models = length(stats)
    n_models >= 2 || throw(ArgumentError("at least two models are required"))
    length(contracts) == n_models ||
        throw(ArgumentError("contracts has length $(length(contracts)); expected $n_models"))
    n_observations = stats[1].n_observations
    all(stat -> stat.n_observations == n_observations, stats) ||
        throw(ArgumentError("all models must have the same number of observations"))

    order = sortperm(1:n_models; by = i -> stats[i].elpd_loo, rev = true)
    best = stats[order[1]]
    unnormalized_weights = [exp(stat.elpd_loo - best.elpd_loo) for stat in stats]
    weight_total = sum(unnormalized_weights)
    rows = NamedTuple[]
    for (rank, index) in pairs(order)
        stat = stats[index]
        pointwise_difference = stat.pointwise.elpd_loo .- best.pointwise.elpd_loo
        push!(rows, merge((;
                model = labels[index],
                rank,
                criterion = :loo,
            ),
            _comparison_contract_fields(contracts[index]),
            (;
                method = stat.method,
                psis_smoothing = stat.psis_smoothing,
                pareto_k_estimator = stat.pareto_k_estimator,
                relative_efficiency = get(stat,:relative_efficiency,:not_used),
                elpd_loo = stat.elpd_loo,
                elpd_difference = stat.elpd_loo - best.elpd_loo,
                se_elpd_difference = _pointwise_se(pointwise_difference),
                se_elpd_loo = stat.se_elpd_loo,
                looic = stat.looic,
                looic_difference = stat.looic - best.looic,
                se_looic = stat.se_looic,
                relative_weight = unnormalized_weights[index] / weight_total,
                p_loo = stat.p_loo,
                lppd = stat.lppd,
                n_draws = stat.n_draws,
                n_observations = stat.n_observations,
                max_pareto_k = stat.max_pareto_k,
                bad_pareto_k_count = stat.bad_pareto_k_count,
                min_effective_sample_size = stat.min_effective_sample_size,
                warning = stat.warning,
            )))
    end
    return rows
end

function _compare_models_waic(fits::AbstractVector{<:_ModelComparisonFit},
        labels::AbstractVector{<:AbstractString};
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    length(fits) >= 2 || throw(ArgumentError("at least two models are required"))
    length(labels) == length(fits) ||
        throw(ArgumentError("labels has length $(length(labels)); expected $(length(fits))"))
    contracts = [_model_comparison_contract(fit) for fit in fits]
    _require_model_comparison_compatibility(contracts)
    stats = [waic(fit; ndraws, draw_indices, rng) for fit in fits]
    return _waic_comparison_rows(labels, stats, contracts)
end

function _compare_models_loo(fits::AbstractVector{<:_ModelComparisonFit},
        labels::AbstractVector{<:AbstractString};
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng(),
        psis_smoothing::Bool = false)
    length(fits) >= 2 || throw(ArgumentError("at least two models are required"))
    length(labels) == length(fits) ||
        throw(ArgumentError("labels has length $(length(labels)); expected $(length(fits))"))
    contracts = [_model_comparison_contract(fit) for fit in fits]
    _require_model_comparison_compatibility(contracts)
    stats = psis_smoothing ?
        [psis_loo(fit; ndraws, draw_indices, rng) for fit in fits] :
        [loo(fit; ndraws, draw_indices, rng) for fit in fits]
    return _loo_comparison_rows(labels, stats, contracts)
end

function _sensitivity_compare_models_waic(fits::AbstractVector{<:_ModelComparisonFit},
        labels::AbstractVector{<:AbstractString},
        axis::Symbol;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    length(fits) >= 2 || throw(ArgumentError("at least two models are required"))
    length(labels) == length(fits) ||
        throw(ArgumentError("labels has length $(length(labels)); expected $(length(fits))"))
    contracts = [_model_comparison_contract(fit) for fit in fits]
    _require_sensitivity_comparison_compatibility(contracts, axis)
    stats = [waic(fit; ndraws, draw_indices, rng) for fit in fits]
    return _waic_comparison_rows(labels, stats, contracts)
end

function _sensitivity_compare_models_loo(fits::AbstractVector{<:_ModelComparisonFit},
        labels::AbstractVector{<:AbstractString},
        axis::Symbol;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng(),
        psis_smoothing::Bool = false)
    length(fits) >= 2 || throw(ArgumentError("at least two models are required"))
    length(labels) == length(fits) ||
        throw(ArgumentError("labels has length $(length(labels)); expected $(length(fits))"))
    contracts = [_model_comparison_contract(fit) for fit in fits]
    _require_sensitivity_comparison_compatibility(contracts, axis)
    stats = psis_smoothing ?
        [psis_loo(fit; ndraws, draw_indices, rng) for fit in fits] :
        [loo(fit; ndraws, draw_indices, rng) for fit in fits]
    return _loo_comparison_rows(labels, stats, contracts)
end

"""
    compare_models(fits...; names = nothing, criterion = :waic,
        ndraws = nothing, draw_indices = nothing, rng = Random.default_rng())
    compare_models(models::Pair...; criterion = :waic, ndraws = nothing,
        draw_indices = nothing, rng = Random.default_rng())

For an observation-bound comparison across the eight common fit types, use
named pairs with `comparison_axis=:model`, `:dimensions` or `:q_matrix`, plus
`dataset_id` and `observation_ids`. This delegates to `compare_predictions`:
all retained draws, explicit baseline (first input by default), optional
`se_unit`, original input order and warnings. Its criteria are `:waic`,
`:raw_loo`, `:psis_loo` and `:hill_smoothed_loo`. Prediction bundles already carry IDs.
No RNG is used in this route. `rng`, `ndraws` and `draw_indices` are refused.

For two Star results, named pairs or `names` preserve primary/baseline labels.
Event IDs align automatically, observed outcomes/supports must match, and the
returned differences are primary minus baseline. The Star report retains its
own event-level estimator and SE contract; see its `compare_models` help.

For two explanatory held-performance reports from `criteria(fit; unit=:performance,
integrate=...)`, pass named pairs and `criterion=:psis_loo`. Input order defines
primary minus baseline, without ranking or model weights. Declare
`independent_model_rng=true` only for independent original/refit sampling streams
to report combined computational MCSE. Otherwise difference MCSE is unavailable.
Observation/support/conditioning bindings and shared predictor values must match.
Crossed-design population SE remains unavailable. Save the comparison and use
`plot(report; kind=:comparison)` without refitting.

Without `comparison_axis`, the legacy common-fit route compares WAIC
(`criterion=:waic`), raw importance-sampling LOO (`:loo`) or the native
standard PSIS (`:psis_loo`) using retained chain efficiency.
MFRM, scalar GMFRM, and MGMFRM fit
objects can be compared when they share the same observation data, row order,
ordinal category levels, latent dimensionality, and fixed Q-matrix contract.
LOO comparison rows retain the explicit estimator and relative-efficiency metadata.
PSIS requires all original draws; raw LOO and WAIC retain their existing controls.
Rows are sorted by expected log predictive density in descending order.
`elpd_difference` is relative to the best model and is therefore zero for the
top row and non-positive for lower-ranked rows. `relative_weight` is a
normalized Akaike-style weight computed from the selected expected log
predictive density values. Each row carries the model family, thresholds,
discrimination mode, dimensionality, Q-matrix, and data signature used by the
compatibility check.
"""
function compare_models(fits::_ModelComparisonFit...;
        names = nothing,
        criterion::Symbol = :waic,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    checked_criterion = _compare_criterion(criterion)
    labels = _compare_model_names(names, length(fits))
    collected_fits = _ModelComparisonFit[fits...]
    return checked_criterion === :waic ?
        _compare_models_waic(collected_fits, labels; ndraws, draw_indices, rng) :
        _compare_models_loo(collected_fits, labels;
            ndraws,
            draw_indices,
            rng,
            psis_smoothing = checked_criterion === :psis_loo)
end

function compare_models(models::Pair...;
        comparison_axis::Union{Nothing,Symbol} = nothing,
        criterion::Union{Nothing,Symbol} = nothing,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::Union{Nothing,AbstractRNG} = nothing, kwargs...)
    if !isempty(models) && any(p -> last(p) isa FrequentistMFRM.Fit, models)
        ndraws === nothing && draw_indices === nothing && rng === nothing && comparison_axis === nothing ||
            throw(ArgumentError("frequentist MMLE model comparison accepts no MCMC draw selection, RNG, or comparison_axis"))
        crit_f = criterion === nothing ? :aic : criterion
        return FrequentistMFRM.compare_mmle_models(collect(models); criterion = crit_f, kwargs...)
    end
    if !isempty(models) && any(p -> last(p) isa ScaleIdentifiedMGMFRM.Fit, models)
        ndraws === nothing && draw_indices === nothing && rng === nothing && comparison_axis === nothing ||
            throw(ArgumentError("ScaleIdentifiedMGMFRM model comparison uses all retained draws and accepts no MCMC draw selection, RNG, or comparison_axis"))
        crit_s = criterion === nothing ? :psis_loo : criterion
        return _compare_aligned_rating_fits(collect(models); criterion = crit_s, kwargs...)
    end
    if !isempty(models) && any(p -> last(p) isa AdditiveFacets.Fit, models)
        ndraws === nothing && draw_indices === nothing && rng === nothing && comparison_axis === nothing ||
            throw(ArgumentError("AdditiveFacets model comparison uses all retained draws and accepts no MCMC draw selection, RNG, or comparison_axis"))
        crit_a = criterion === nothing ? :psis_loo : criterion
        return _compare_additive_rating_models(collect(models); criterion = crit_a, kwargs...)
    end
    criterion = criterion === nothing ? :waic : criterion
    if !isempty(models) && any(p->_explanatory_score_report(last(p)),models)
        ndraws===nothing && draw_indices===nothing && rng===nothing ||
            throw(ArgumentError("saved explanatory comparison accepts no draw selection or RNG"))
        return _compare_explanatory_profiles(models;criterion,comparison_axis,kwargs...)
    end
    if !isempty(models) && any(p->last(p) isa NamedTuple && string(get(last(p),:kind,""))=="criterion_collapse_heldout_criteria",models)
        ndraws===nothing && draw_indices===nothing && rng===nothing && comparison_axis===nothing ||
            throw(ArgumentError("CriterionCollapse profile comparison accepts no draw selection, RNG, or comparison_axis"))
        return _CC_MOD.compare_heldout_criteria(collect(models);criterion,kwargs...)
    end
    if comparison_axis !== nothing
        ndraws===nothing && draw_indices===nothing || throw(ArgumentError(
            "observation-bound comparison requires all retained draws"))
        rng===nothing || throw(ArgumentError("observation-bound comparison is deterministic; omit rng"))
        return compare_predictions(models...;comparison_axis,criterion,kwargs...)
    end
    isempty(kwargs) || throw(ArgumentError(
        "observation IDs, baseline and SE controls require an explicit comparison_axis"))
    rng = rng === nothing ? Random.default_rng() : rng
    checked_criterion = _compare_criterion(criterion)
    fits = _ModelComparisonFit[]
    labels = String[]
    for model in models
        model.second isa _ModelComparisonFit ||
            throw(ArgumentError("model pair :$(model.first) does not contain a comparable fitted model"))
        push!(labels, string(model.first))
        push!(fits, model.second)
    end
    _compare_model_names(labels, length(labels))
    return checked_criterion === :waic ?
        _compare_models_waic(fits, labels; ndraws, draw_indices, rng) :
        _compare_models_loo(fits, labels;
            ndraws,
            draw_indices,
            rng,
            psis_smoothing = checked_criterion === :psis_loo)
end
