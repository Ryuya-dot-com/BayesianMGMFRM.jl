# reliability_and_facets_stats.jl -- Expected scores, reliability, Wright maps, FACETS stats, residuals, DFF, and rater diagnostics.

function _draw_indices(fit, ndraws::Union{Nothing,Int}, rng::AbstractRNG)
    total = size(fit.draws, 1)
    if ndraws === nothing
        return collect(1:total)
    end
    ndraws >= 1 || throw(ArgumentError("ndraws must be positive"))
    return rand(rng, 1:total, ndraws)
end

function _validate_draw_indices(fit, draw_indices)
    indices = collect(Int, draw_indices)
    isempty(indices) && throw(ArgumentError("draw_indices must not be empty"))
    total = size(fit.draws, 1)
    all(index -> 1 <= index <= total, indices) ||
        throw(ArgumentError("draw_indices are out of bounds"))
    return indices
end

function _posterior_draw_indices(fit, ndraws::Union{Nothing,Int}, draw_indices, rng::AbstractRNG)
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
    _linear_predictors!(probs, design, params, row)
    return _softmax_eta!(probs)
end

function _softmax_eta!(probs::AbstractVector{Float64})
    max_eta = maximum(probs)

    denom = 0.0
    for category in eachindex(probs)
        p = exp(probs[category] - max_eta)
        probs[category] = p
        denom += p
    end
    probs ./= denom
    return probs
end

function _gmfrm_direct_draws_for_prediction(
        design::FacetDesign,
        direct_draws::AbstractMatrix,
        caller::AbstractString)
    _check_gmfrm_source_fixture_design(design, caller)
    size(direct_draws, 1) >= 1 ||
        throw(ArgumentError("$caller requires at least one draw"))
    expected = length(design.parameter_names)
    size(direct_draws, 2) == expected ||
        throw(ArgumentError("direct_draws has $(size(direct_draws, 2)) column(s); expected $expected"))
    all(value -> isfinite(Float64(value)), direct_draws) ||
        throw(ArgumentError("direct_draws contain non-finite values"))
    for draw in axes(direct_draws, 1)
        _gmfrm_source_fixture_constraints(design, @view direct_draws[draw, :])
    end
    return direct_draws
end

function _mgmfrm_direct_draws_for_prediction(
        design::FacetDesign,
        direct_draws::AbstractMatrix,
        caller::AbstractString)
    _check_mgmfrm_source_fixture_design(design, caller)
    size(direct_draws, 1) >= 1 ||
        throw(ArgumentError("$caller requires at least one draw"))
    expected = length(design.parameter_names)
    size(direct_draws, 2) == expected ||
        throw(ArgumentError("direct_draws has $(size(direct_draws, 2)) column(s); expected $expected"))
    all(value -> isfinite(Float64(value)), direct_draws) ||
        throw(ArgumentError("direct_draws contain non-finite values"))
    for draw in axes(direct_draws, 1)
        _mgmfrm_source_fixture_constraints(design, @view direct_draws[draw, :])
    end
    return direct_draws
end

function _gmfrm_category_probabilities!(probs::AbstractVector{Float64},
        design::FacetDesign,
        direct_params::AbstractVector,
        row::Int)
    _gmfrm_source_linear_predictors!(probs, design, direct_params, row)
    return _softmax_eta!(probs)
end

function _mgmfrm_category_probabilities!(probs::AbstractVector{Float64},
        design::FacetDesign,
        loading_indices::AbstractMatrix{Int},
        direct_params::AbstractVector,
        row::Int)
    _mgmfrm_source_linear_predictors!(
        probs,
        design,
        direct_params,
        row,
        loading_indices,
    )
    return _softmax_eta!(probs)
end

function _gmfrm_predictive_probabilities_direct(
        design::FacetDesign,
        direct_draws::AbstractMatrix)
    checked = _gmfrm_direct_draws_for_prediction(
        design,
        direct_draws,
        "predictive_probabilities",
    )
    data = design.spec.data
    K = length(data.category_levels)
    out = Array{Float64}(undef, size(checked, 1), data.n, K)
    probs = zeros(Float64, K)

    for draw in axes(checked, 1)
        direct_params = @view checked[draw, :]
        for row in 1:data.n
            _gmfrm_category_probabilities!(probs, design, direct_params, row)
            for category in 1:K
                out[draw, row, category] = probs[category]
            end
        end
    end
    return out
end

function _mgmfrm_predictive_probabilities_direct(
        design::FacetDesign,
        direct_draws::AbstractMatrix)
    checked = _mgmfrm_direct_draws_for_prediction(
        design,
        direct_draws,
        "predictive_probabilities",
    )
    data = design.spec.data
    K = length(data.category_levels)
    out = Array{Float64}(undef, size(checked, 1), data.n, K)
    probs = zeros(Float64, K)
    loading_indices = _mgmfrm_source_loading_index_matrix(design)

    for draw in axes(checked, 1)
        direct_params = @view checked[draw, :]
        for row in 1:data.n
            _mgmfrm_category_probabilities!(
                probs,
                design,
                loading_indices,
                direct_params,
                row,
            )
            for category in 1:K
                out[draw, row, category] = probs[category]
            end
        end
    end
    return out
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
    _check_fit_supported_mfrm(design, "predictive_probabilities")
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

function predictive_probabilities(fit::GMFRMFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return _gmfrm_predictive_probabilities_direct(
        fit.design,
        fit.direct_draws[indices, :],
    )
end

function predictive_probabilities(fit::MGMFRMFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return _mgmfrm_predictive_probabilities_direct(
        fit.design,
        fit.direct_draws[indices, :],
    )
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

function expected_scores(fit::GMFRMFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    probabilities = predictive_probabilities(fit; ndraws, draw_indices, rng)
    return _expected_scores_from_probabilities(probabilities, fit.design.spec.data.category_levels)
end

function expected_scores(fit::MGMFRMFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    probabilities = predictive_probabilities(fit; ndraws, draw_indices, rng)
    return _expected_scores_from_probabilities(probabilities, fit.design.spec.data.category_levels)
end

function _fair_average_groups(data::FacetData, by::Symbol)
    by === :person && return data.person, data.person_levels
    by === :rater && return data.rater, data.rater_levels
    by === :item && return data.item, data.item_levels
    throw(ArgumentError("fair_average_summary currently supports by = :person, :rater, or :item"))
end

function _fair_average_reference_rows(data::FacetData, by::Symbol, level_index::Int)
    rows = NTuple{3,Int}[]
    if by === :person
        for rater in eachindex(data.rater_levels), item in eachindex(data.item_levels)
            push!(rows, (level_index, rater, item))
        end
    elseif by === :rater
        for person in eachindex(data.person_levels), item in eachindex(data.item_levels)
            push!(rows, (person, level_index, item))
        end
    elseif by === :item
        for person in eachindex(data.person_levels), rater in eachindex(data.rater_levels)
            push!(rows, (person, rater, level_index))
        end
    else
        throw(ArgumentError("fair_average_summary currently supports by = :person, :rater, or :item"))
    end
    return rows
end

function _hypothetical_mfrm_category_probabilities!(
        probs::AbstractVector{Float64},
        design::FacetDesign,
        params::AbstractVector,
        person::Int,
        rater::Int,
        item::Int)
    length(probs) == length(design.spec.data.category_levels) ||
        throw(ArgumentError("probability work vector has the wrong length"))
    person_value = params[design.blocks[:person][person]]
    rater_value = _stable_facet_value(design, params, :rater, rater)
    item_value = _stable_facet_value(design, params, :item, item)
    location = person_value - rater_value - item_value
    step_sum = _param_zero(params)
    for category_index in eachindex(probs)
        if category_index > 1
            step_sum += _threshold_step(design, params, item, category_index - 1)
        end
        probs[category_index] = Float64((category_index - 1) * location - step_sum)
    end
    return _softmax_eta!(probs)
end

function _hypothetical_mfrm_expected_score(
        design::FacetDesign,
        params::AbstractVector,
        person::Int,
        rater::Int,
        item::Int,
        probs::AbstractVector{Float64})
    _hypothetical_mfrm_category_probabilities!(probs, design, params, person, rater, item)
    expected = 0.0
    for category_index in eachindex(probs)
        expected += Float64(design.spec.data.category_levels[category_index]) *
            probs[category_index]
    end
    return expected
end

function _fair_average_by_draw(
        design::FacetDesign,
        draws::AbstractMatrix,
        reference_rows::AbstractVector{<:Tuple{Int,Int,Int}})
    !isempty(reference_rows) ||
        throw(ArgumentError("fair_average_summary reference grid is empty"))
    out = Vector{Float64}(undef, size(draws, 1))
    probs = zeros(Float64, length(design.spec.data.category_levels))
    for draw in axes(draws, 1)
        params = @view draws[draw, :]
        total = 0.0
        for (person, rater, item) in reference_rows
            total += _hypothetical_mfrm_expected_score(
                design,
                params,
                person,
                rater,
                item,
                probs,
            )
        end
        out[draw] = total / length(reference_rows)
    end
    return out
end

"""
    fair_average_summary(fit::MFRMFit; by = :person, interval = 0.95,
        min_n = 1, ndraws = nothing, draw_indices = nothing,
        rng = Random.default_rng())
    fair_average_summary(design::FacetDesign, draws; by = :person,
        interval = 0.95, min_n = 1)

Return posterior fair-average expected-score summaries for a focal MFRM facet.
Rows use an equal-weight balanced reference grid over the non-focal core
facets, so `by = :person` averages each person over all observed raters and
items, `by = :rater` averages each rater over all persons and items, and
`by = :item` averages each item over all persons and raters. Rows include the
observed mean score for the focal level, fair-average and expected-score
intervals, the fair-minus-observed adjustment, and a caveat that the balanced
grid is a reporting standardization rather than a population-weighted target.
"""
function fair_average_summary(design::FacetDesign,
        draws::AbstractMatrix;
        by::Symbol = :person,
        interval::Real = 0.95,
        min_n::Int = 1)
    _check_fit_supported_mfrm(design, "fair_average_summary")
    min_n >= 1 || throw(ArgumentError("min_n must be positive"))
    size(draws, 1) >= 1 ||
        throw(ArgumentError("fair_average_summary requires at least one posterior draw"))
    size(draws, 2) == length(design.parameter_names) ||
        throw(ArgumentError("draws has $(size(draws, 2)) column(s); expected $(length(design.parameter_names))"))
    all(value -> isfinite(Float64(value)), draws) ||
        throw(ArgumentError("draws contain non-finite values"))

    lower_probability, upper_probability = _interval_probabilities(interval)
    data = design.spec.data
    group_index, group_levels = _fair_average_groups(data, by)
    rows = NamedTuple[]
    for (level_index, level) in pairs(group_levels)
        observations = findall(==(level_index), group_index)
        observed_mean = _mean_at_indices(data.score, observations)
        reference_rows = _fair_average_reference_rows(data, by, level_index)
        fair_by_draw = _fair_average_by_draw(design, draws, reference_rows)
        adjustment_by_draw = fair_by_draw .- observed_mean
        fair_summary = _finite_draw_summary(
            fair_by_draw,
            lower_probability,
            upper_probability,
        )
        adjustment_summary = _finite_draw_summary(
            adjustment_by_draw,
            lower_probability,
            upper_probability,
        )
        n_observations = length(observations)
        push!(rows, (;
            facet = by,
            level,
            n_observations,
            n_reference_rows = length(reference_rows),
            n_draws = size(draws, 1),
            method = :posterior_expected_score,
            reference = :balanced_facet_grid,
            interval_probability = Float64(interval),
            lower_probability,
            upper_probability,
            observed_mean,
            fair_average_mean = fair_summary.mean,
            fair_average_median = fair_summary.median,
            fair_average_lower = fair_summary.lower,
            fair_average_upper = fair_summary.upper,
            expected_score_mean = fair_summary.mean,
            expected_score_median = fair_summary.median,
            expected_score_lower = fair_summary.lower,
            expected_score_upper = fair_summary.upper,
            adjustment_mean = adjustment_summary.mean,
            adjustment_median = adjustment_summary.median,
            adjustment_lower = adjustment_summary.lower,
            adjustment_upper = adjustment_summary.upper,
            caveat = :balanced_reference_grid_not_population_standardization,
            flag = n_observations < min_n ? :below_min_n : :ok,
        ))
    end
    return rows
end

function fair_average_summary(fit::MFRMFit;
        by::Symbol = :person,
        interval::Real = 0.95,
        min_n::Int = 1,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return fair_average_summary(fit.design, fit.draws[indices, :];
        by,
        interval,
        min_n)
end

function _separation_reliability_facets(facets::Symbol)
    facets === :all && return (:person, :rater, :item)
    return _separation_reliability_facets((facets,))
end

function _separation_reliability_facets(facets)
    out = Symbol[]
    for facet in facets
        facet isa Symbol ||
            throw(ArgumentError("facets must contain symbols"))
        facet in (:person, :rater, :item) ||
            throw(ArgumentError("separation_reliability_summary supports facets :person, :rater, and :item"))
        facet in out &&
            throw(ArgumentError("facets must not contain duplicates"))
        push!(out, facet)
    end
    isempty(out) &&
        throw(ArgumentError("facets must contain at least one facet"))
    return Tuple(out)
end

function _separation_reliability_levels(data::FacetData, facet::Symbol)
    facet === :person && return data.person_levels
    facet === :rater && return data.rater_levels
    facet === :item && return data.item_levels
    throw(ArgumentError("separation_reliability_summary supports facets :person, :rater, and :item"))
end

function _mfrm_facet_value(design::FacetDesign,
        params::AbstractVector,
        facet::Symbol,
        level_index::Int)
    if facet === :person
        return Float64(params[design.blocks[:person][level_index]])
    elseif facet === :rater
        return Float64(_stable_facet_value(design, params, :rater, level_index))
    elseif facet === :item
        return Float64(_stable_facet_value(design, params, :item, level_index))
    end
    throw(ArgumentError("separation_reliability_summary supports facets :person, :rater, and :item"))
end

function _mfrm_facet_value_matrix(design::FacetDesign,
        draws::AbstractMatrix,
        facet::Symbol)
    levels = _separation_reliability_levels(design.spec.data, facet)
    values = Matrix{Float64}(undef, size(draws, 1), length(levels))
    for draw in axes(draws, 1)
        params = @view draws[draw, :]
        for level_index in eachindex(levels)
            values[draw, level_index] =
                _mfrm_facet_value(design, params, facet, level_index)
        end
    end
    return values
end

function _sample_variance_or_nan(values::AbstractVector{<:Real})
    length(values) >= 2 || return NaN
    mean_value = _column_mean(values)
    ss = 0.0
    for value in values
        d = Float64(value) - mean_value
        ss += d * d
    end
    return ss / (length(values) - 1)
end

function _mean_level_posterior_variance(values::AbstractMatrix{Float64})
    size(values, 1) >= 2 ||
        throw(ArgumentError("separation_reliability_summary requires at least two posterior draws"))
    size(values, 2) >= 1 ||
        throw(ArgumentError("separation_reliability_summary requires at least one level"))
    total = 0.0
    for level in axes(values, 2)
        total += _sample_variance_or_nan(@view values[:, level])
    end
    return total / size(values, 2)
end

function _separation_reliability_row(
        design::FacetDesign,
        draws::AbstractMatrix,
        facet::Symbol,
        interval::Real,
        lower_probability::Float64,
        upper_probability::Float64)
    values = _mfrm_facet_value_matrix(design, draws, facet)
    n_draws, n_levels = size(values)
    observed_variance = Vector{Float64}(undef, n_draws)
    observed_sd = Vector{Float64}(undef, n_draws)
    adjusted_variance = Vector{Float64}(undef, n_draws)
    adjusted_sd = Vector{Float64}(undef, n_draws)
    separation = Vector{Float64}(undef, n_draws)
    reliability = Vector{Float64}(undef, n_draws)

    posterior_error_variance =
        n_levels < 2 ? NaN : _mean_level_posterior_variance(values)
    error_variance = fill(posterior_error_variance, n_draws)
    eps_var = eps(Float64)
    for draw in axes(values, 1)
        level_values = @view values[draw, :]
        raw_variance = _sample_variance_or_nan(level_values)
        observed_variance[draw] = raw_variance
        observed_sd[draw] = isfinite(raw_variance) ? sqrt(max(raw_variance, 0.0)) : NaN
        adjusted = isfinite(raw_variance) && isfinite(posterior_error_variance) ?
            max(raw_variance - posterior_error_variance, 0.0) : NaN
        adjusted_variance[draw] = adjusted
        adjusted_sd[draw] = isfinite(adjusted) ? sqrt(adjusted) : NaN
        if isfinite(adjusted) && posterior_error_variance > eps_var
            separation[draw] = sqrt(adjusted / posterior_error_variance)
            reliability[draw] = adjusted / (adjusted + posterior_error_variance)
        else
            separation[draw] = NaN
            reliability[draw] = NaN
        end
    end

    observed_variance_summary =
        _finite_draw_summary(observed_variance, lower_probability, upper_probability)
    observed_sd_summary =
        _finite_draw_summary(observed_sd, lower_probability, upper_probability)
    error_variance_summary =
        _finite_draw_summary(error_variance, lower_probability, upper_probability)
    adjusted_variance_summary =
        _finite_draw_summary(adjusted_variance, lower_probability, upper_probability)
    adjusted_sd_summary =
        _finite_draw_summary(adjusted_sd, lower_probability, upper_probability)
    separation_summary =
        _finite_draw_summary(separation, lower_probability, upper_probability)
    reliability_summary =
        _finite_draw_summary(reliability, lower_probability, upper_probability)

    flag = n_levels < 2 ? :single_level :
        !(posterior_error_variance > eps_var) ? :zero_posterior_error_variance :
        all(value -> isfinite(value) && value == 0.0, adjusted_variance) ?
        :no_adjusted_separation : :ok

    return (;
        facet,
        n_levels,
        n_draws,
        method = :posterior_empirical_reliability,
        scale = :logit,
        interval_probability = Float64(interval),
        lower_probability,
        upper_probability,
        observed_variance_mean = observed_variance_summary.mean,
        observed_variance_median = observed_variance_summary.median,
        observed_variance_lower = observed_variance_summary.lower,
        observed_variance_upper = observed_variance_summary.upper,
        observed_sd_mean = observed_sd_summary.mean,
        observed_sd_median = observed_sd_summary.median,
        observed_sd_lower = observed_sd_summary.lower,
        observed_sd_upper = observed_sd_summary.upper,
        error_variance_mean = error_variance_summary.mean,
        error_variance_median = error_variance_summary.median,
        error_variance_lower = error_variance_summary.lower,
        error_variance_upper = error_variance_summary.upper,
        adjusted_variance_mean = adjusted_variance_summary.mean,
        adjusted_variance_median = adjusted_variance_summary.median,
        adjusted_variance_lower = adjusted_variance_summary.lower,
        adjusted_variance_upper = adjusted_variance_summary.upper,
        adjusted_sd_mean = adjusted_sd_summary.mean,
        adjusted_sd_median = adjusted_sd_summary.median,
        adjusted_sd_lower = adjusted_sd_summary.lower,
        adjusted_sd_upper = adjusted_sd_summary.upper,
        separation_mean = separation_summary.mean,
        separation_median = separation_summary.median,
        separation_lower = separation_summary.lower,
        separation_upper = separation_summary.upper,
        reliability_mean = reliability_summary.mean,
        reliability_median = reliability_summary.median,
        reliability_lower = reliability_summary.lower,
        reliability_upper = reliability_summary.upper,
        caveat = :posterior_empirical_reliability_screening_not_generalizability_coefficient,
        flag,
    )
end

"""
    separation_reliability_summary(fit::MFRMFit; facets = (:person, :rater, :item),
        interval = 0.95, ndraws = nothing, draw_indices = nothing,
        rng = Random.default_rng())
    separation_reliability_summary(design::FacetDesign, draws;
        facets = (:person, :rater, :item), interval = 0.95)

Return posterior separation and empirical reliability summaries for MFRM
person, rater, and item measures. For each requested facet, rows summarize the
posterior distribution of level dispersion, mean posterior error variance,
error-adjusted dispersion, separation, and reliability. Reliability is computed
as adjusted variance divided by adjusted-plus-error variance; use the included
caveat flag because these rows are practical screening summaries rather than
full generalizability-study coefficients.

This historical screen is not a validated FACETS separation estimator or EAP
score-reliability estimator. It subtracts the average marginal posterior variance
from the cross-level variance within each draw, truncates at zero, then summarizes
the resulting ratios. Equal posterior means can therefore yield positive values;
shared location uncertainty can change the result even when all pairwise
contrasts stay fixed. The returned interval is a distribution of this screening
statistic, not an established credible interval for a reliability coefficient.
Do not convert these values into reportable Strata or interpret rater separation
as score agreement. Use qualified `BayesianMGMFRM.posterior_reliability` for an
explicit finite-cohort target; its definition and return schema differ. This
legacy call now warns but preserves historical numerical values.
"""
function separation_reliability_summary(design::FacetDesign,
        draws::AbstractMatrix;
        facets = (:person, :rater, :item),
        interval::Real = 0.95)
    _check_fit_supported_mfrm(design, "separation_reliability_summary")
    size(draws, 1) >= 2 ||
        throw(ArgumentError("separation_reliability_summary requires at least two posterior draws"))
    size(draws, 2) == length(design.parameter_names) ||
        throw(ArgumentError("draws has $(size(draws, 2)) column(s); expected $(length(design.parameter_names))"))
    all(value -> isfinite(Float64(value)), draws) ||
        throw(ArgumentError("draws contain non-finite values"))
    lower_probability, upper_probability = _interval_probabilities(interval)
    requested_facets = _separation_reliability_facets(facets)
    @warn "separation_reliability_summary is a legacy screen requiring methodological review; use BayesianMGMFRM.posterior_reliability with an explicit finite-cohort target. Do not derive reportable Strata from this screen." maxlog=1
    return [
        _separation_reliability_row(
            design,
            draws,
            facet,
            interval,
            lower_probability,
            upper_probability,
        )
        for facet in requested_facets
    ]
end

function separation_reliability_summary(fit::MFRMFit;
        facets = (:person, :rater, :item),
        interval::Real = 0.95,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return separation_reliability_summary(fit.design, fit.draws[indices, :];
        facets,
        interval)
end

function _wright_map_facets(facets::Symbol)
    facets === :all && return (:person, :rater, :item)
    return _wright_map_facets((facets,))
end

function _wright_map_facets(facets)
    out = Symbol[]
    for facet in facets
        facet isa Symbol ||
            throw(ArgumentError("facets must contain symbols"))
        facet in (:person, :rater, :item) ||
            throw(ArgumentError("wright_map_data supports facets :person, :rater, and :item"))
        facet in out &&
            throw(ArgumentError("facets must not contain duplicates"))
        push!(out, facet)
    end
    isempty(out) &&
        throw(ArgumentError("facets must contain at least one facet"))
    return Tuple(out)
end

function _wright_map_facet_index(data::FacetData, facet::Symbol)
    facet === :person && return data.person, data.person_levels
    facet === :rater && return data.rater, data.rater_levels
    facet === :item && return data.item, data.item_levels
    throw(ArgumentError("wright_map_data supports facets :person, :rater, and :item"))
end

function _wright_map_check_draws(design::FacetDesign, draws::AbstractMatrix)
    _check_fit_supported_mfrm(design, "wright_map_data")
    size(draws, 1) >= 1 ||
        throw(ArgumentError("wright_map_data requires at least one posterior draw"))
    size(draws, 2) == length(design.parameter_names) ||
        throw(ArgumentError("draws has $(size(draws, 2)) column(s); expected $(length(design.parameter_names))"))
    all(value -> isfinite(Float64(value)), draws) ||
        throw(ArgumentError("draws contain non-finite values"))
    return draws
end

function _wright_map_facet_parameter(design::FacetDesign,
        facet::Symbol,
        level_index::Int)
    if facet === :person
        parameter_index = design.blocks[:person][level_index]
        return (;
            parameter_index,
            parameter_name = design.parameter_names[parameter_index],
            status = :estimated,
            is_fixed = false,
            fixed_value = missing,
        )
    elseif facet === :rater
        parameter_index = _stable_facet_parameter_index(design, :rater, level_index)
        if parameter_index === missing
            fixed_value = _stable_facet_fixed_value(design, :rater, level_index)
            anchored = haskey(_stable_hard_anchor_map(design)[:rater], level_index)
            return (;
                parameter_index = missing,
                parameter_name = missing,
                status = anchored ? :hard_anchor : :reference_zero,
                is_fixed = true,
                fixed_value,
            )
        end
        return (;
            parameter_index,
            parameter_name = design.parameter_names[parameter_index],
            status = :estimated,
            is_fixed = false,
            fixed_value = missing,
        )
    elseif facet === :item
        parameter_index = _stable_facet_parameter_index(design, :item, level_index)
        if parameter_index === missing
            fixed_value = _stable_facet_fixed_value(design, :item, level_index)
            anchored = haskey(_stable_hard_anchor_map(design)[:item], level_index)
            return (;
                parameter_index = missing,
                parameter_name = missing,
                status = anchored ? :hard_anchor : :reference_zero,
                is_fixed = true,
                fixed_value,
            )
        end
        return (;
            parameter_index,
            parameter_name = design.parameter_names[parameter_index],
            status = :estimated,
            is_fixed = false,
            fixed_value = missing,
        )
    end
    throw(ArgumentError("wright_map_data supports facets :person, :rater, and :item"))
end

function _wright_map_facet_values(design::FacetDesign,
        draws::AbstractMatrix,
        facet::Symbol,
        level_index::Int)
    values = Vector{Float64}(undef, size(draws, 1))
    for draw in axes(draws, 1)
        values[draw] = _mfrm_facet_value(
            design,
            @view(draws[draw, :]),
            facet,
            level_index,
        )
    end
    return values
end

function _wright_map_threshold_values(design::FacetDesign,
        draws::AbstractMatrix,
        item_index::Int,
        step::Int)
    item_values = Vector{Float64}(undef, size(draws, 1))
    step_values = Vector{Float64}(undef, size(draws, 1))
    positions = Vector{Float64}(undef, size(draws, 1))
    for draw in axes(draws, 1)
        params = @view draws[draw, :]
        item_value = _mfrm_facet_value(design, params, :item, item_index)
        step_value = Float64(_threshold_step(design, params, item_index, step))
        item_values[draw] = item_value
        step_values[draw] = step_value
        positions[draw] = item_value + step_value
        isfinite(item_value) && isfinite(step_value) && isfinite(positions[draw]) ||
            throw(ArgumentError("Wright-map item-step positions must be finite for every draw"))
    end
    return item_values, step_values, positions
end

function _wright_map_facet_row(design::FacetDesign,
        draws::AbstractMatrix,
        facet::Symbol,
        level,
        level_index::Int,
        interval::Real,
        lower_probability::Float64,
        upper_probability::Float64)
    data = design.spec.data
    facet_index, _ = _wright_map_facet_index(data, facet)
    n_observations = count(==(level_index), facet_index)
    parameter = _wright_map_facet_parameter(design, facet, level_index)
    values = _wright_map_facet_values(design, draws, facet, level_index)
    position_summary = _finite_draw_summary(values, lower_probability, upper_probability)

    return (;
        component = :facet_measure,
        facet,
        level,
        level_index,
        item = missing,
        item_index = missing,
        step = missing,
        from_category = missing,
        to_category = missing,
        thresholds = design.spec.thresholds,
        parameter.parameter_index,
        parameter.parameter_name,
        item_parameter_index = missing,
        item_parameter_name = missing,
        threshold_parameter_index = missing,
        threshold_parameter_name = missing,
        status = parameter.status,
        is_fixed = parameter.is_fixed,
        fixed_value = parameter.fixed_value,
        n_observations,
        n_draws = size(draws, 1),
        scale = :logit,
        position_mean = position_summary.mean,
        position_median = position_summary.median,
        position_lower = position_summary.lower,
        position_upper = position_summary.upper,
        item_measure_mean = missing,
        item_measure_median = missing,
        item_measure_lower = missing,
        item_measure_upper = missing,
        threshold_step_mean = missing,
        threshold_step_median = missing,
        threshold_step_lower = missing,
        threshold_step_upper = missing,
        interval_probability = Float64(interval),
        lower_probability,
        upper_probability,
        label = string(facet, "=", level),
        caveat = :wright_map_data_not_backend_rendering,
        flag = n_observations == 0 ? :empty_level : :ok,
    )
end

function _wright_map_threshold_row(design::FacetDesign,
        draws::AbstractMatrix,
        item,
        item_index::Int,
        step::Int,
        interval::Real,
        lower_probability::Float64,
        upper_probability::Float64)
    metadata = _threshold_step_metadata(design, item_index, step)
    item_parameter = _wright_map_facet_parameter(design, :item, item_index)
    item_values, step_values, positions =
        _wright_map_threshold_values(design, draws, item_index, step)
    item_summary = _finite_draw_summary(item_values, lower_probability, upper_probability)
    step_summary = _finite_draw_summary(step_values, lower_probability, upper_probability)
    position_summary = _finite_draw_summary(positions, lower_probability, upper_probability)
    position_fixed = item_parameter.is_fixed && metadata.status === :fixed_zero

    return (;
        component = :threshold,
        facet = :threshold,
        level = missing,
        level_index = missing,
        item,
        item_index,
        step = metadata.step,
        from_category = metadata.from_category,
        to_category = metadata.to_category,
        thresholds = design.spec.thresholds,
        parameter_index = metadata.parameter_index,
        parameter_name = metadata.parameter_name,
        item_parameter_index = item_parameter.parameter_index,
        item_parameter_name = item_parameter.parameter_name,
        threshold_parameter_index = metadata.parameter_index,
        threshold_parameter_name = metadata.parameter_name,
        status = metadata.status,
        is_fixed = position_fixed,
        fixed_value = position_fixed ? item_parameter.fixed_value : missing,
        n_observations = missing,
        n_draws = size(draws, 1),
        scale = :logit,
        position_mean = position_summary.mean,
        position_median = position_summary.median,
        position_lower = position_summary.lower,
        position_upper = position_summary.upper,
        item_measure_mean = item_summary.mean,
        item_measure_median = item_summary.median,
        item_measure_lower = item_summary.lower,
        item_measure_upper = item_summary.upper,
        threshold_step_mean = step_summary.mean,
        threshold_step_median = step_summary.median,
        threshold_step_lower = step_summary.lower,
        threshold_step_upper = step_summary.upper,
        interval_probability = Float64(interval),
        lower_probability,
        upper_probability,
        label = string("item=", item, ", step=", metadata.step),
        caveat = :wright_map_data_not_backend_rendering,
        flag = :ok,
    )
end

function _wright_map_threshold_rows(design::FacetDesign,
        draws::AbstractMatrix,
        interval::Real,
        lower_probability::Float64,
        upper_probability::Float64)
    data = design.spec.data
    nsteps = max(length(data.category_levels) - 1, 0)
    rows = NamedTuple[]
    for (item_index, item) in pairs(data.item_levels), step in 1:nsteps
        push!(rows, _wright_map_threshold_row(
            design,
            draws,
            item,
            item_index,
            step,
            interval,
            lower_probability,
            upper_probability,
        ))
    end
    return rows
end

"""
    wright_map_data(fit::MFRMFit; facets = :all, include_thresholds = true,
        interval = 0.95, ndraws = nothing, draw_indices = nothing,
        rng = Random.default_rng())
    wright_map_data(design::FacetDesign, draws; facets = :all,
        include_thresholds = true, interval = 0.95)

Return plotting-backend-independent Wright-map rows for the current
fit-supported MFRM/RSM/PCM design. Facet rows summarize posterior person,
rater, and item measures on the logit scale. Threshold rows summarize item-step
positions as `item measure + threshold step`, which puts category boundaries on
the same latent scale as person measures. The returned rows are intended for
Quarto, Makie, AlgebraOfGraphics, ggplot, or CSV workflows and do not commit
the package to a specific plotting backend.

Higher person measures increase adjacent-category log odds; higher item
difficulty or rater severity decreases them. An item-step position is an
adjacent-category equal-probability boundary at zero rater severity, not an
expected-score half-point. Positions are summed draw by draw, preserving joint
item/step uncertainty. Threshold-row `status` describes the step constraint;
`is_fixed` and `fixed_value` describe the complete item-step position. A derived
sum-to-zero step remains uncertain; even a fixed binary step has an uncertain
position when its item is estimated. Nonfinite derived positions raise an error.
"""
function wright_map_data(design::FacetDesign,
        draws::AbstractMatrix;
        facets = :all,
        include_thresholds::Bool = true,
        interval::Real = 0.95)
    _wright_map_check_draws(design, draws)
    lower_probability, upper_probability = _interval_probabilities(interval)
    requested_facets = _wright_map_facets(facets)
    data = design.spec.data
    rows = NamedTuple[]
    for facet in requested_facets
        _, levels = _wright_map_facet_index(data, facet)
        for (level_index, level) in pairs(levels)
            push!(rows, _wright_map_facet_row(
                design,
                draws,
                facet,
                level,
                level_index,
                interval,
                lower_probability,
                upper_probability,
            ))
        end
    end
    if include_thresholds
        append!(rows, _wright_map_threshold_rows(
            design,
            draws,
            interval,
            lower_probability,
            upper_probability,
        ))
    end
    return rows
end

function wright_map_data(fit::MFRMFit;
        facets = :all,
        include_thresholds::Bool = true,
        interval::Real = 0.95,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return wright_map_data(fit.design, fit.draws[indices, :];
        facets,
        include_thresholds,
        interval)
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

function predictive_variances(fit::GMFRMFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    probabilities = predictive_probabilities(fit; ndraws, draw_indices, rng)
    return _predictive_variances_from_probabilities(probabilities, fit.design.spec.data.category_levels)
end

function predictive_variances(fit::MGMFRMFit;
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

function predictive_residuals(fit::GMFRMFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    expected = expected_scores(fit; ndraws, draw_indices, rng)
    data = fit.design.spec.data
    residuals = similar(expected)
    for draw in axes(expected, 1), row in axes(expected, 2)
        residuals[draw, row] = data.score[row] - expected[draw, row]
    end
    return residuals
end

function predictive_residuals(fit::MGMFRMFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    expected = expected_scores(fit; ndraws, draw_indices, rng)
    data = fit.design.spec.data
    residuals = similar(expected)
    for draw in axes(expected, 1), row in axes(expected, 2)
        residuals[draw, row] = data.score[row] - expected[draw, row]
    end
    return residuals
end

function _predictive_standardized_residuals_from_probabilities(
        data::FacetData,
        probabilities::AbstractArray{<:Real,3};
        family,
        thresholds,
        draw_indices,
        draw_source::Symbol,
        variance_tolerance::Real)
    size(probabilities, 1) >= 1 ||
        throw(ArgumentError(
            "predictive_standardized_residuals requires at least one draw"))
    size(probabilities, 2) == data.n ||
        throw(ArgumentError("probabilities observation count does not match data"))
    size(probabilities, 3) == length(data.category_levels) ||
        throw(ArgumentError("probabilities category count does not match data"))
    tolerance = Float64(variance_tolerance)
    isfinite(tolerance) && tolerance >= 0 ||
        throw(ArgumentError(
            "variance_tolerance must be finite and nonnegative"))
    all(value -> isfinite(Float64(value)), probabilities) ||
        throw(ArgumentError(
            "predictive probabilities contain non-finite values; " *
            "standardized residuals are not available"))

    expected = _expected_scores_from_probabilities(
        probabilities,
        data.category_levels,
    )
    variances = _predictive_variances_from_probabilities(
        probabilities,
        data.category_levels,
    )
    all(isfinite, expected) ||
        throw(ArgumentError(
            "predictive expected scores contain non-finite values; " *
            "standardized residuals are not available"))
    all(isfinite, variances) ||
        throw(ArgumentError(
            "predictive variances contain non-finite values; " *
            "standardized residuals are not available"))
    values = fill(NaN, size(expected))
    valid = falses(size(expected))
    for draw in axes(expected, 1), row in axes(expected, 2)
        variance = variances[draw, row]
        if variance > tolerance
            value = (Float64(data.score[row]) - expected[draw, row]) /
                sqrt(variance)
            isfinite(value) ||
                throw(ArgumentError(
                    "standardized residual is non-finite at draw $draw, " *
                    "observation $row"))
            values[draw, row] = value
            valid[draw, row] = true
        end
    end
    excluded_by_draw = Tuple(
        count(!, @view valid[draw, :]) for draw in axes(valid, 1))
    excluded_by_observation = Tuple(
        count(!, @view valid[:, row]) for row in axes(valid, 2))

    return (;
        schema = "bayesianmgmfrm.predictive_standardized_residuals.v1",
        object = :predictive_standardized_residuals,
        family,
        thresholds,
        draw_source,
        draw_indices = Tuple(Int.(draw_indices)),
        n_draws = size(values, 1),
        n_observations = size(values, 2),
        residual_definition = :draw_specific_pearson,
        conditioning = :parameter_draw,
        variance_tolerance = tolerance,
        values,
        valid,
        n_valid = count(valid),
        n_excluded = length(valid) - count(valid),
        excluded_by_draw,
        excluded_by_observation,
        nonfinite_prediction_action = :error,
        caveat = :low_predictive_variance_rows_are_excluded_not_clamped,
    )
end

"""
    predictive_standardized_residuals(
        fit::MFRMFit;
        ndraws = nothing,
        draw_indices = nothing,
        rng = Random.default_rng(),
        variance_tolerance = 1e-12)
    predictive_standardized_residuals(
        design::FacetDesign,
        draws;
        variance_tolerance = 1e-12)

Return draw-specific Pearson score residuals for MFRM, GMFRM, or MGMFRM
predictions. For observation `n` and parameter draw `d`, the reported value is
`(y[n] - E[y[n] | draw d]) / sqrt(Var[y[n] | draw d])`. The result retains the
draw-by-observation matrix in `values`, a same-shaped `valid` mask, draw indices,
and exclusion counts. Predictive variances at or below `variance_tolerance` are
excluded rather than clamped, preventing artificial extreme residuals.
Non-finite predictive probabilities, expectations, variances, or standardized
values raise `ArgumentError`; they are never counted as low-variance exclusions.

These residuals are a low-level diagnostic input. They do not by themselves
establish local independence, a testlet effect, rater halo, or a universal Q3
cutoff. Use [`local_dependence_contract`](@ref) and
[`testlet_design_check`](@ref) to inspect the planned matching and design
requirements before forming pairwise dependence statistics.
"""
function predictive_standardized_residuals(
        design::FacetDesign,
        draws::AbstractMatrix;
        variance_tolerance::Real = 1e-12)
    probabilities = predictive_probabilities(design, draws)
    return _predictive_standardized_residuals_from_probabilities(
        design.spec.data,
        probabilities;
        family = design.spec.family,
        thresholds = design.spec.thresholds,
        draw_indices = 1:size(draws, 1),
        draw_source = :supplied,
        variance_tolerance,
    )
end

function predictive_standardized_residuals(
        fit::MFRMFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng(),
        variance_tolerance::Real = 1e-12)
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    probabilities = predictive_probabilities(
        fit.design,
        @view(fit.draws[indices, :]),
    )
    return _predictive_standardized_residuals_from_probabilities(
        fit.design.spec.data,
        probabilities;
        family = fit.design.spec.family,
        thresholds = fit.design.spec.thresholds,
        draw_indices = indices,
        draw_source = :posterior,
        variance_tolerance,
    )
end

function predictive_standardized_residuals(
        fit::GMFRMFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng(),
        variance_tolerance::Real = 1e-12)
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    probabilities = _gmfrm_predictive_probabilities_direct(
        fit.design,
        @view(fit.direct_draws[indices, :]),
    )
    return _predictive_standardized_residuals_from_probabilities(
        fit.design.spec.data,
        probabilities;
        family = fit.design.spec.family,
        thresholds = fit.design.spec.thresholds,
        draw_indices = indices,
        draw_source = :posterior,
        variance_tolerance,
    )
end

function predictive_standardized_residuals(
        fit::MGMFRMFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng(),
        variance_tolerance::Real = 1e-12)
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    probabilities = _mgmfrm_predictive_probabilities_direct(
        fit.design,
        @view(fit.direct_draws[indices, :]),
    )
    return _predictive_standardized_residuals_from_probabilities(
        fit.design.spec.data,
        probabilities;
        family = fit.design.spec.family,
        thresholds = fit.design.spec.thresholds,
        draw_indices = indices,
        draw_source = :posterior,
        variance_tolerance,
    )
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

function _expected_score_calibration_target(data::FacetData,
        probabilities::AbstractArray{<:Real,3})
    return (;
        target = :expected_score,
        category = missing,
        predicted = _expected_scores_from_probabilities(
            probabilities,
            data.category_levels,
        ),
        observed = Float64.(data.score),
    )
end

function _category_probability_calibration_target(data::FacetData,
        probabilities::AbstractArray{<:Real,3},
        category)
    category_index = findfirst(==(category), data.category_levels)
    category_index === nothing &&
        throw(ArgumentError("category $category is not an observed score category"))
    level = data.category_levels[category_index]
    return (;
        target = :category_probability,
        category = level,
        predicted = @view(probabilities[:, :, category_index]),
        observed = [score == level ? 1.0 : 0.0 for score in data.score],
    )
end

function _calibration_targets_from_probabilities(data::FacetData,
        probabilities::AbstractArray{<:Real,3},
        target::Symbol,
        category)
    size(probabilities, 1) >= 1 ||
        throw(ArgumentError("calibration_table requires at least one posterior draw"))
    size(probabilities, 2) == data.n ||
        throw(ArgumentError("probabilities observation count does not match data"))
    size(probabilities, 3) == length(data.category_levels) ||
        throw(ArgumentError("probabilities category count does not match data"))

    if target === :expected_score
        category === nothing ||
            throw(ArgumentError("category is only supported with target = :category_probability"))
        return [_expected_score_calibration_target(data, probabilities)]
    elseif target === :category_probability
        if category === :all
            return [
                _category_probability_calibration_target(data, probabilities, level)
                for level in data.category_levels
            ]
        end
        chosen_category = category === nothing ? last(data.category_levels) : category
        return [_category_probability_calibration_target(data, probabilities, chosen_category)]
    elseif target === :all
        (category === nothing || category === :all) ||
            throw(ArgumentError("category is not supported with target = :all except category = :all"))
        targets = NamedTuple[_expected_score_calibration_target(data, probabilities)]
        append!(targets, [
            _category_probability_calibration_target(data, probabilities, level)
            for level in data.category_levels
        ])
        return targets
    end

    throw(ArgumentError("target must be :expected_score, :category_probability, or :all"))
end

function _calibration_targets(design::FacetDesign,
        draws::AbstractMatrix,
        target::Symbol,
        category)
    probabilities = predictive_probabilities(design, draws)
    return _calibration_targets_from_probabilities(
        design.spec.data,
        probabilities,
        target,
        category,
    )
end

function _calibration_column_means(predicted::AbstractMatrix{<:Real})
    means = Vector{Float64}(undef, size(predicted, 2))
    for row in axes(predicted, 2)
        means[row] = _column_mean(@view predicted[:, row])
    end
    all(isfinite, means) ||
        throw(ArgumentError("predicted calibration values contain non-finite entries"))
    return means
end

function _calibration_bin_assignments(predicted_mean::AbstractVector{<:Real}, bins::Int)
    bins >= 1 || throw(ArgumentError("bins must be positive"))
    n = length(predicted_mean)
    n >= 1 || throw(ArgumentError("calibration_table requires at least one observation"))
    nbins = min(bins, n)
    order = sortperm(predicted_mean; alg = MergeSort)
    assignments = Vector{Int}(undef, n)
    for (rank, row) in pairs(order)
        assignments[row] = min(nbins, fld((rank - 1) * nbins, n) + 1)
    end
    return assignments, nbins
end

function _mean_at_indices(values::AbstractVector{<:Real}, indices::AbstractVector{Int})
    isempty(indices) && return NaN
    return sum(Float64(values[index]) for index in indices) / length(indices)
end

"""
    calibration_table(fit::MFRMFit; target = :expected_score,
        category = nothing, bins = 10, interval = 0.9, ndraws = nothing,
        draw_indices = nothing, rng = Random.default_rng())
    calibration_table(design::FacetDesign, draws; target = :expected_score,
        category = nothing, bins = 10, interval = 0.9)

Return binned observed-vs-predicted calibration rows from posterior draws.
The default `target = :expected_score` compares observed scores with posterior
expected scores. With `target = :category_probability`, the table compares the
observed proportion of `category` with the posterior probability of that
category; when `category` is omitted, the highest score category is used. Use
`category = :all` to return one category-probability calibration block for each
ordinal score category. Use `target = :all` to return expected-score rows plus
all ordinal category-probability rows.

Bins group the observed rating rows by their posterior mean prediction for
each target. They are not ability bins. Each prediction retains that row's
person, item and rater conditions; observed and expected values use the same
rows with equal rating weight. `n_observations` counts ratings, not unique people,
and `n_draws` counts selected parameter draws, not effective sample size.

`predicted_lower` and `predicted_upper` form an equal-tail posterior interval
for the bin's mean expected score or category probability. They do not include
replicated-rating variation, uncertainty of the observed mean or Monte Carlo
error. `:outside_interval` describes the observed mean's position relative to
this interval; it is not a calibrated lack-of-fit test. These in-sample rows
do not establish held-out predictive calibration. Use
[`posterior_predictive_check`](@ref) for replicated-data comparisons and inspect
sampling diagnostics separately.
"""
function calibration_table(design::FacetDesign,
        draws::AbstractMatrix;
        target::Symbol = :expected_score,
        category = nothing,
        bins::Int = 10,
        interval::Real = 0.9)
    lower_probability, upper_probability = _interval_probabilities(interval)
    calibration_targets = _calibration_targets(design, draws, target, category)
    return _calibration_table_from_targets(
        calibration_targets;
        bins,
        interval,
        lower_probability,
        upper_probability,
    )
end

function _calibration_table_from_targets(
        calibration_targets;
        bins::Int,
        interval::Real,
        lower_probability::Float64,
        upper_probability::Float64)
    rows = NamedTuple[]
    for calibration_target in calibration_targets
        append!(rows, _calibration_table_from_target(
            calibration_target;
            bins,
            interval,
            lower_probability,
            upper_probability,
        ))
    end
    return rows
end

function _calibration_table_from_target(
        calibration_target;
        bins::Int,
        interval::Real,
        lower_probability::Float64,
        upper_probability::Float64)
    predicted = calibration_target.predicted
    observed = calibration_target.observed
    predicted_mean = _calibration_column_means(predicted)
    assignments, nbins = _calibration_bin_assignments(predicted_mean, bins)
    rows = NamedTuple[]

    for bin in 1:nbins
        obs = findall(==(bin), assignments)
        predicted_by_draw = Vector{Float64}(undef, size(predicted, 1))
        for draw in axes(predicted, 1)
            predicted_by_draw[draw] = _mean_at_indices(@view(predicted[draw, :]), obs)
        end
        predicted_summary = _finite_draw_summary(predicted_by_draw,
            lower_probability, upper_probability)
        observed_mean = _mean_at_indices(observed, obs)
        bin_predicted_means = predicted_mean[obs]
        outside = isfinite(observed_mean) &&
            (observed_mean < predicted_summary.lower || observed_mean > predicted_summary.upper)
        calibration_error = observed_mean - predicted_summary.mean
        push!(rows, (;
            target = calibration_target.target,
            category = calibration_target.category,
            bin,
            n_observations = length(obs),
            n_draws = size(predicted, 1),
            predicted_bin_lower = minimum(bin_predicted_means),
            predicted_bin_upper = maximum(bin_predicted_means),
            observed_mean,
            predicted_mean = predicted_summary.mean,
            predicted_median = predicted_summary.median,
            predicted_lower = predicted_summary.lower,
            predicted_upper = predicted_summary.upper,
            interval_probability = Float64(interval),
            lower_probability,
            upper_probability,
            calibration_error,
            absolute_calibration_error = abs(calibration_error),
            flag = outside ? :outside_interval : :ok,
        ))
    end

    return rows
end

function calibration_table(fit::MFRMFit;
        target::Symbol = :expected_score,
        category = nothing,
        bins::Int = 10,
        interval::Real = 0.9,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return calibration_table(fit.design, fit.draws[indices, :];
        target, category, bins, interval)
end

function calibration_table(fit::GMFRMFit;
        target::Symbol = :expected_score,
        category = nothing,
        bins::Int = 10,
        interval::Real = 0.9,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    lower_probability, upper_probability = _interval_probabilities(interval)
    probabilities = predictive_probabilities(fit; ndraws, draw_indices, rng)
    calibration_targets = _calibration_targets_from_probabilities(
        fit.design.spec.data,
        probabilities,
        target,
        category,
    )
    return _calibration_table_from_targets(
        calibration_targets;
        bins,
        interval,
        lower_probability,
        upper_probability,
    )
end

function calibration_table(fit::MGMFRMFit;
        target::Symbol = :expected_score,
        category = nothing,
        bins::Int = 10,
        interval::Real = 0.9,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    lower_probability, upper_probability = _interval_probabilities(interval)
    probabilities = predictive_probabilities(fit; ndraws, draw_indices, rng)
    calibration_targets = _calibration_targets_from_probabilities(
        fit.design.spec.data,
        probabilities,
        target,
        category,
    )
    return _calibration_table_from_targets(
        calibration_targets;
        bins,
        interval,
        lower_probability,
        upper_probability,
    )
end

function _facets_plugin_parameters(draws::AbstractMatrix)
    size(draws, 1) >= 1 ||
        throw(ArgumentError("FACETS compatibility statistics require at least one draw"))
    params = Vector{Float64}(undef, size(draws, 2))
    for column in axes(draws, 2)
        params[column] = _column_mean(@view draws[:, column])
    end
    all(isfinite, params) ||
        throw(ArgumentError("the plugin parameter estimate contains non-finite values"))
    return params
end

function _facets_score_moments(design::FacetDesign, params::AbstractVector)
    _check_fit_supported_mfrm(design, "facets_compatibility_stats")
    _check_parameter_vector(design, params)
    probabilities = predictive_probabilities(
        design,
        reshape(Float64.(params), 1, length(params)),
    )
    data = design.spec.data
    levels = Float64.(data.category_levels)
    expected = Vector{Float64}(undef, data.n)
    variance = Vector{Float64}(undef, data.n)
    fourth = Vector{Float64}(undef, data.n)

    for row in 1:data.n
        mean_score = 0.0
        for category in eachindex(levels)
            mean_score += probabilities[1, row, category] * levels[category]
        end
        second_central = 0.0
        fourth_central = 0.0
        for category in eachindex(levels)
            centered = levels[category] - mean_score
            probability = probabilities[1, row, category]
            second_central += probability * centered^2
            fourth_central += probability * centered^4
        end
        expected[row] = mean_score
        variance[row] = max(second_central, 0.0)
        fourth[row] = max(fourth_central, 0.0)
    end
    return (;
        expected,
        residual = Float64.(data.score) .- expected,
        variance,
        fourth,
    )
end

function _facets_wright_masters_df(information::Float64,
        weight_sum::Float64,
        infit_denominator::Float64,
        outfit_denominator::Float64,
        tolerance::Float64)
    infit_df = information > 0 && infit_denominator > tolerance ?
        2 * information^2 / infit_denominator : NaN
    outfit_df = weight_sum > 0 && outfit_denominator > tolerance ?
        2 * weight_sum^2 / outfit_denominator : NaN
    return infit_df, outfit_df
end

function _facets_wilson_hilferty_zstd(
        mnsq::Float64,
        df::Float64,
        cap::Float64;
        whexact::Bool = true)
    isfinite(mnsq) && mnsq >= 0.0 && isfinite(df) && df > 0.0 || return NaN
    q = sqrt(2.0 / df)
    zstd = 3.0 * (cbrt(mnsq) - 1.0) / q + (whexact ? q / 3.0 : 0.0)
    return isfinite(zstd) ? clamp(zstd, -cap, cap) : NaN
end

function _facets_compatibility_stats(design::FacetDesign,
        params::AbstractVector;
        by::Symbol,
        min_n::Int,
        weighting,
        zstd_cap::Real,
        variance_tolerance::Real,
        method::Symbol,
        parameter_estimate::Symbol,
        n_draws_aggregated::Int)
    min_n >= 1 || throw(ArgumentError("min_n must be positive"))
    weighting === :unit ||
        throw(ArgumentError(
            "facets_compatibility_stats currently supports only weighting = :unit; " *
            "frequency, sampling, and other observation weights are not implemented",
        ))
    isfinite(zstd_cap) && zstd_cap > 0 ||
        throw(ArgumentError("zstd_cap must be finite and positive"))
    isfinite(variance_tolerance) && variance_tolerance > 0 ||
        throw(ArgumentError("variance_tolerance must be finite and positive"))
    cap = Float64(zstd_cap)
    tolerance = Float64(variance_tolerance)
    moments = _facets_score_moments(design, params)
    data = design.spec.data
    group_index, group_levels = _fit_stat_groups(data, by)
    threshold_model = design.spec.thresholds === :rating_scale ? :rsm : :pcm
    rows = NamedTuple[]

    for (level_index, level) in pairs(group_levels)
        observations = findall(==(level_index), group_index)
        valid = [
            row for row in observations
            if isfinite(moments.variance[row]) &&
                moments.variance[row] > tolerance &&
                isfinite(moments.fourth[row])
        ]
        n_obs = length(observations)
        n_valid = length(valid)
        n_excluded_tiny_variance = n_obs - n_valid

        infit = NaN
        outfit = NaN
        infit_information = NaN
        outfit_weight_sum = NaN
        infit_fourth_moment_denominator = NaN
        outfit_fourth_moment_denominator = NaN
        infit_df = NaN
        outfit_df = NaN
        infit_zstd = NaN
        outfit_zstd = NaN

        if n_valid >= min_n
            residual_ss = sum(row -> moments.residual[row]^2, valid)
            infit_information = sum(row -> moments.variance[row], valid)
            outfit_weight_sum = Float64(n_valid)
            standardized_ss = sum(
                row -> moments.residual[row]^2 / moments.variance[row],
                valid,
            )
            infit = residual_ss / infit_information
            outfit = standardized_ss / outfit_weight_sum
            infit_fourth_moment_denominator = sum(
                row -> moments.fourth[row] - moments.variance[row]^2,
                valid,
            )
            outfit_fourth_moment_denominator = sum(
                row -> moments.fourth[row] / moments.variance[row]^2 - 1,
                valid,
            )
            infit_df, outfit_df = _facets_wright_masters_df(
                infit_information,
                outfit_weight_sum,
                infit_fourth_moment_denominator,
                outfit_fourth_moment_denominator,
                tolerance,
            )
            infit_zstd = _facets_wilson_hilferty_zstd(infit, infit_df, cap)
            outfit_zstd = _facets_wilson_hilferty_zstd(outfit, outfit_df, cap)
        end

        flag = n_valid < min_n ? :below_min_n :
            !(isfinite(infit_df) && isfinite(outfit_df)) ?
                :undefined_fourth_moment_df :
            !(isfinite(infit_zstd) && isfinite(outfit_zstd)) ?
                :undefined_zstd :
            n_excluded_tiny_variance > 0 ?
                :excluded_tiny_predictive_variance : :ok

        push!(rows, (;
            schema = "bayesianmgmfrm.facets_compatibility_stats.v1",
            object = :facets_compatibility_fit_row,
            model_family = :mfrm,
            threshold_regime = design.spec.thresholds,
            rasch_model = threshold_model,
            facet = by,
            level,
            n_obs,
            n_valid,
            n_excluded_tiny_variance,
            method,
            parameter_estimate,
            n_draws_aggregated,
            weighting = :unit,
            residual_formula = :observed_minus_plugin_expected_score,
            mnsq_formula = :rasch_expected_score_variance,
            df_method = :facets_wright_masters_fourth_moment,
            zstd_transform = :wilson_hilferty_cube_root,
            zstd_cap = cap,
            approximation = :facets_compatible_bayesian_plugin,
            facets_software_equivalence = :not_claimed,
            posterior_uncertainty = :not_propagated,
            generalized_model_support = :rejected,
            infit,
            outfit,
            infit_information,
            outfit_weight_sum,
            infit_fourth_moment_denominator,
            outfit_fourth_moment_denominator,
            infit_df,
            outfit_df,
            infit_zstd,
            outfit_zstd,
            variance_tolerance = tolerance,
            flag,
            caveat = :point_estimate_approximation_not_facets_jml_output,
        ))
    end
    return rows
end

"""
    facets_compatibility_stats(fit::MFRMFit; by = :rater,
        point_estimate = :posterior_mean, min_n = 1, weighting = :unit,
        zstd_cap = 9, variance_tolerance = 1e-12, ndraws = nothing,
        draw_indices = nothing, rng = Random.default_rng())
    facets_compatibility_stats(design::FacetDesign, params; by = :rater,
        min_n = 1, weighting = :unit, zstd_cap = 9,
        variance_tolerance = 1e-12)

Return an explicitly approximate FACETS-compatible fit table for the
fit-supported one-dimensional MFRM rating-scale or partial-credit model. The
fit method plugs the selected draws' parameter-wise posterior means into the
Rasch response probabilities. It then computes infit and outfit MnSq, the
Wright--Masters fourth-moment degrees of freedom, and Wilson--Hilferty ZSTD
values capped at `+/-zstd_cap`.

This function is separate from [`fit_stats`](@ref): posterior infit/outfit
summaries remain the default Bayesian residual diagnostic. Only unit-weighted
observations are supported, and rows state that posterior uncertainty is not
propagated and numerical equivalence to FACETS JML output is not claimed.
`GMFRMFit` and `MGMFRMFit` inputs are rejected because generalized
discrimination invalidates an unqualified FACETS-df interpretation.
"""
function facets_compatibility_stats(design::FacetDesign,
        params::AbstractVector;
        by::Symbol = :rater,
        min_n::Int = 1,
        weighting = :unit,
        zstd_cap::Real = 9,
        variance_tolerance::Real = 1e-12)
    return _facets_compatibility_stats(
        design,
        params;
        by,
        min_n,
        weighting,
        zstd_cap,
        variance_tolerance,
        method = :supplied_parameter_plugin,
        parameter_estimate = :supplied,
        n_draws_aggregated = 0,
    )
end

function facets_compatibility_stats(fit::MFRMFit;
        by::Symbol = :rater,
        point_estimate::Symbol = :posterior_mean,
        min_n::Int = 1,
        weighting = :unit,
        zstd_cap::Real = 9,
        variance_tolerance::Real = 1e-12,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    point_estimate === :posterior_mean ||
        throw(ArgumentError(
            "only point_estimate = :posterior_mean is currently supported",
        ))
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    params = _facets_plugin_parameters(@view fit.draws[indices, :])
    return _facets_compatibility_stats(
        fit.design,
        params;
        by,
        min_n,
        weighting,
        zstd_cap,
        variance_tolerance,
        method = :posterior_mean_plugin,
        parameter_estimate = :posterior_mean,
        n_draws_aggregated = length(indices),
    )
end

function facets_compatibility_stats(fit::Union{GMFRMFit,MGMFRMFit}; kwargs...)
    family = fit isa GMFRMFit ? :gmfrm : :mgmfrm
    throw(ArgumentError(
        "facets_compatibility_stats rejects $family fits: FACETS-style " *
        "fourth-moment df and ZSTD are currently limited to unit-discrimination " *
        "MFRM/RSM/PCM fits; generalized support requires a separately calibrated " *
        "estimand",
    ))
end

"""
    facets_report(args...; kwargs...)

Report-oriented public name for [`facets_compatibility_stats`](@ref). It
returns the same explicitly approximate, unit-weighted posterior-mean plugin
rows for MFRM/RSM/PCM fits and preserves the same rejection boundaries for
non-unit weights and generalized fits. [`fit_stats`](@ref) remains the default
posterior Bayesian diagnostic.
"""
facets_report(args...; kwargs...) = facets_compatibility_stats(args...; kwargs...)

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

function _diagnostic_map_metrics(metrics::Symbol)
    metrics === :all && return (:infit, :outfit)
    return _diagnostic_map_metrics((metrics,))
end

function _diagnostic_map_metrics(metrics)
    out = Symbol[]
    for metric in metrics
        metric isa Symbol ||
            throw(ArgumentError("diagnostic map metrics must be Symbols"))
        metric in (:infit, :outfit) ||
            throw(ArgumentError("diagnostic_map_data supports metrics :infit and :outfit"))
        metric in out &&
            throw(ArgumentError("diagnostic map metrics must not contain duplicates"))
        push!(out, metric)
    end
    return Tuple(out)
end

function _diagnostic_map_fit_value(row, metric::Symbol)
    metric === :infit && return (;
        value = row.infit_mean,
        median = row.infit_median,
        lower = row.infit_lower,
        upper = row.infit_upper,
    )
    metric === :outfit && return (;
        value = row.outfit_mean,
        median = row.outfit_median,
        lower = row.outfit_lower,
        upper = row.outfit_upper,
    )
    throw(ArgumentError("diagnostic_map_data supports metrics :infit and :outfit"))
end

function _diagnostic_map_pathway_row(design::FacetDesign,
        position_row,
        fit_row,
        metric::Symbol)
    fit_value = _diagnostic_map_fit_value(fit_row, metric)
    flag = position_row.flag !== :ok ? position_row.flag : fit_row.flag
    return (;
        schema = "bayesianmgmfrm.diagnostic_map_data.v1",
        object = :diagnostic_map_row,
        map_layer = :pathway_fit,
        component = position_row.component,
        model_family = design.spec.family,
        thresholds = design.spec.thresholds,
        facet = position_row.facet,
        level = position_row.level,
        level_index = position_row.level_index,
        item = position_row.item,
        item_index = position_row.item_index,
        step = position_row.step,
        from_category = position_row.from_category,
        to_category = position_row.to_category,
        label = position_row.label,
        fit_metric = metric,
        fit_value = fit_value.value,
        fit_median = fit_value.median,
        fit_lower = fit_value.lower,
        fit_upper = fit_value.upper,
        fit_interval_probability = fit_row.interval_probability,
        logit_position = position_row.position_mean,
        logit_median = position_row.position_median,
        logit_lower = position_row.position_lower,
        logit_upper = position_row.position_upper,
        logit_interval_probability = position_row.interval_probability,
        n_observations = fit_row.n_obs,
        n_draws = position_row.n_draws,
        scale = position_row.scale,
        parameter_index = position_row.parameter_index,
        parameter_name = position_row.parameter_name,
        status = position_row.status,
        fit_flag = fit_row.flag,
        position_flag = position_row.flag,
        flag,
        caveat = :diagnostic_map_screening_not_model_selection,
        suggested_x = fit_value.value,
        suggested_y = position_row.position_mean,
    )
end

function _diagnostic_map_threshold_row(design::FacetDesign, position_row)
    return (;
        schema = "bayesianmgmfrm.diagnostic_map_data.v1",
        object = :diagnostic_map_row,
        map_layer = :threshold_position,
        component = position_row.component,
        model_family = design.spec.family,
        thresholds = design.spec.thresholds,
        facet = position_row.facet,
        level = position_row.level,
        level_index = position_row.level_index,
        item = position_row.item,
        item_index = position_row.item_index,
        step = position_row.step,
        from_category = position_row.from_category,
        to_category = position_row.to_category,
        label = position_row.label,
        fit_metric = missing,
        fit_value = missing,
        fit_median = missing,
        fit_lower = missing,
        fit_upper = missing,
        fit_interval_probability = missing,
        logit_position = position_row.position_mean,
        logit_median = position_row.position_median,
        logit_lower = position_row.position_lower,
        logit_upper = position_row.position_upper,
        logit_interval_probability = position_row.interval_probability,
        n_observations = position_row.n_observations,
        n_draws = position_row.n_draws,
        scale = position_row.scale,
        parameter_index = position_row.parameter_index,
        parameter_name = position_row.parameter_name,
        status = position_row.status,
        fit_flag = missing,
        position_flag = position_row.flag,
        flag = position_row.flag,
        caveat = :diagnostic_map_screening_not_model_selection,
        suggested_x = missing,
        suggested_y = position_row.position_mean,
    )
end

"""
    diagnostic_map_data(fit::MFRMFit; facets = :all, include_thresholds = true,
        metrics = :all, interval = 0.95, min_n = 1, ndraws = nothing,
        draw_indices = nothing, rng = Random.default_rng())
    diagnostic_map_data(design::FacetDesign, draws; facets = :all,
        include_thresholds = true, metrics = :all, interval = 0.95,
        min_n = 1)

Return plotting-backend-independent rows that join Wright-map logit positions
to posterior infit/outfit summaries. `:pathway_fit` rows are intended for
pathway-map displays with `x = fit_value` and `y = logit_position`; threshold
rows are returned as `:threshold_position` reference rows on the same logit
scale. The rows are diagnostic screening data, not model-selection or
fairness-claim evidence.
"""
function diagnostic_map_data(design::FacetDesign,
        draws::AbstractMatrix;
        facets = :all,
        include_thresholds::Bool = true,
        metrics = :all,
        interval::Real = 0.95,
        min_n::Int = 1)
    requested_facets = _wright_map_facets(facets)
    requested_metrics = _diagnostic_map_metrics(metrics)
    wright_rows = wright_map_data(design, draws;
        facets = requested_facets,
        include_thresholds,
        interval)
    position_by_key = Dict{Tuple{Symbol,Any},Any}()
    rows = NamedTuple[]

    for row in wright_rows
        if row.component === :facet_measure
            position_by_key[(row.facet, row.level)] = row
        elseif row.component === :threshold
            push!(rows, _diagnostic_map_threshold_row(design, row))
        end
    end

    for facet in requested_facets
        fit_rows = fit_stats(design, draws; by = facet, interval, min_n)
        for fit_row in fit_rows
            position_row = position_by_key[(facet, fit_row.level)]
            for metric in requested_metrics
                push!(rows, _diagnostic_map_pathway_row(
                    design,
                    position_row,
                    fit_row,
                    metric,
                ))
            end
        end
    end

    return rows
end

function diagnostic_map_data(fit::MFRMFit;
        facets = :all,
        include_thresholds::Bool = true,
        metrics = :all,
        interval::Real = 0.95,
        min_n::Int = 1,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return diagnostic_map_data(fit.design, fit.draws[indices, :];
        facets,
        include_thresholds,
        metrics,
        interval,
        min_n)
end

function _residual_summary_groups(data::FacetData, by::Symbol)
    by === :observation && return collect(1:data.n), collect(1:data.n)
    return _fit_stat_groups(data, by)
end

function _posterior_group_mean(values::AbstractMatrix{<:Real},
        observations::AbstractVector{Int})
    out = Vector{Float64}(undef, size(values, 1))
    for draw in axes(values, 1)
        out[draw] = _mean_at_indices(@view(values[draw, :]), observations)
    end
    return out
end

function _posterior_group_absolute_mean(values::AbstractMatrix{<:Real},
        observations::AbstractVector{Int})
    out = Vector{Float64}(undef, size(values, 1))
    for draw in axes(values, 1)
        total = 0.0
        for observation in observations
            total += abs(Float64(values[draw, observation]))
        end
        out[draw] = total / length(observations)
    end
    return out
end

function _posterior_group_rmse(values::AbstractMatrix{<:Real},
        observations::AbstractVector{Int})
    out = Vector{Float64}(undef, size(values, 1))
    for draw in axes(values, 1)
        total = 0.0
        for observation in observations
            value = Float64(values[draw, observation])
            total += value * value
        end
        out[draw] = sqrt(total / length(observations))
    end
    return out
end

function _residual_summary_rows(data::FacetData,
        expected::AbstractMatrix{<:Real},
        residuals::AbstractMatrix{<:Real};
        by::Symbol,
        interval::Real,
        min_n::Int)
    min_n >= 1 || throw(ArgumentError("min_n must be positive"))
    size(expected) == size(residuals) ||
        throw(ArgumentError("expected and residual matrices must have the same shape"))
    size(expected, 1) >= 1 ||
        throw(ArgumentError("residual_summary requires at least one posterior draw"))
    size(expected, 2) == data.n ||
        throw(ArgumentError("residual_summary observation count does not match data"))
    all(value -> isfinite(Float64(value)), expected) ||
        throw(ArgumentError("expected score matrix contains non-finite values"))
    all(value -> isfinite(Float64(value)), residuals) ||
        throw(ArgumentError("residual matrix contains non-finite values"))

    lower_probability, upper_probability = _interval_probabilities(interval)
    group_index, group_levels = _residual_summary_groups(data, by)
    rows = NamedTuple[]
    for (level_index, level) in pairs(group_levels)
        observations = findall(==(level_index), group_index)
        n_observations = length(observations)
        expected_by_draw = _posterior_group_mean(expected, observations)
        residual_by_draw = _posterior_group_mean(residuals, observations)
        absolute_residual_by_draw =
            _posterior_group_absolute_mean(residuals, observations)
        rmse_by_draw = _posterior_group_rmse(residuals, observations)

        expected_summary = _finite_draw_summary(
            expected_by_draw,
            lower_probability,
            upper_probability,
        )
        residual_summary = _finite_draw_summary(
            residual_by_draw,
            lower_probability,
            upper_probability,
        )
        absolute_residual_summary = _finite_draw_summary(
            absolute_residual_by_draw,
            lower_probability,
            upper_probability,
        )
        rmse_summary = _finite_draw_summary(
            rmse_by_draw,
            lower_probability,
            upper_probability,
        )
        residual_interval_excludes_zero =
            isfinite(residual_summary.lower) &&
            isfinite(residual_summary.upper) &&
            (residual_summary.lower > 0 || residual_summary.upper < 0)
        flag = n_observations < min_n ? :below_min_n :
            residual_interval_excludes_zero ? :residual_interval_excludes_zero : :ok

        push!(rows, (;
            facet = by,
            level,
            n_observations,
            n_draws = size(expected, 1),
            method = :posterior_expected_score,
            interval_probability = Float64(interval),
            lower_probability,
            upper_probability,
            observed_mean = _mean_at_indices(data.score, observations),
            expected_mean = expected_summary.mean,
            expected_median = expected_summary.median,
            expected_lower = expected_summary.lower,
            expected_upper = expected_summary.upper,
            residual_mean = residual_summary.mean,
            residual_median = residual_summary.median,
            residual_lower = residual_summary.lower,
            residual_upper = residual_summary.upper,
            absolute_residual_mean = absolute_residual_summary.mean,
            absolute_residual_median = absolute_residual_summary.median,
            absolute_residual_lower = absolute_residual_summary.lower,
            absolute_residual_upper = absolute_residual_summary.upper,
            rmse_mean = rmse_summary.mean,
            rmse_median = rmse_summary.median,
            rmse_lower = rmse_summary.lower,
            rmse_upper = rmse_summary.upper,
            residual_interval_excludes_zero,
            caveat = :posterior_predictive_residual_screening_not_confirmatory,
            flag,
        ))
    end
    return rows
end

"""
    residual_summary(fit::MFRMFit; by = :observation, interval = 0.95,
        min_n = 1, ndraws = nothing, draw_indices = nothing,
        rng = Random.default_rng())
    residual_summary(design::FacetDesign, draws; by = :observation,
        interval = 0.95, min_n = 1)

Return posterior summaries of observed-minus-expected score residuals by
observation or facet level. Rows include observed mean score, posterior
expected-score intervals, residual intervals, mean absolute residual, RMSE, and
a screening caveat flag. Use `by = :person`, `:rater`, `:item`, `:category`, or
an optional facet name to aggregate rows; `by = :observation` returns one row
per original response. Fitted-object methods are available for MFRM and guarded
scalar GMFRM fit objects.
"""
function residual_summary(design::FacetDesign,
        draws::AbstractMatrix;
        by::Symbol = :observation,
        interval::Real = 0.95,
        min_n::Int = 1)
    expected = expected_scores(design, draws)
    residuals = predictive_residuals(design, draws)
    return _residual_summary_rows(design.spec.data, expected, residuals;
        by,
        interval,
        min_n)
end

function residual_summary(fit::MFRMFit;
        by::Symbol = :observation,
        interval::Real = 0.95,
        min_n::Int = 1,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return residual_summary(fit.design, fit.draws[indices, :];
        by,
        interval,
        min_n)
end

function residual_summary(fit::GMFRMFit;
        by::Symbol = :observation,
        interval::Real = 0.95,
        min_n::Int = 1,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    expected = expected_scores(fit; draw_indices = indices)
    residuals = predictive_residuals(fit; draw_indices = indices)
    return _residual_summary_rows(fit.design.spec.data, expected, residuals;
        by,
        interval,
        min_n)
end

function _dff_report_terms(design::FacetDesign, terms)
    data = design.spec.data
    if terms === :validation
        out = Tuple{Symbol,Symbol}[design.spec.validation_bias_terms...]
        isempty(out) &&
            throw(ArgumentError("dff_report requires declared validation DFF terms; pass terms explicitly for an ad hoc report"))
    elseif terms isa Tuple && length(terms) == 2 &&
            first(terms) isa Symbol && last(terms) isa Symbol
        out = Tuple{Symbol,Symbol}[(first(terms), last(terms))]
    elseif terms isa Symbol
        throw(ArgumentError("terms must be :validation, one two-facet tuple, or a collection of two-facet tuples"))
    else
        out = Tuple{Symbol,Symbol}[]
        for term in terms
            term isa Tuple && length(term) == 2 &&
                first(term) isa Symbol && last(term) isa Symbol ||
                throw(ArgumentError("terms must be :validation, one two-facet tuple, or a collection of two-facet tuples"))
            normalized = (first(term), last(term))
            normalized in out &&
                throw(ArgumentError("terms must not contain duplicates"))
            push!(out, normalized)
        end
        isempty(out) &&
            throw(ArgumentError("terms must contain at least one DFF term"))
    end
    for term in out
        term[1] != term[2] || throw(ArgumentError("DFF requires two distinct facets"))
        _fit_stat_groups(data, term[1])
        _fit_stat_groups(data, term[2])
    end
    return Tuple(out)
end

function _dff_observations(index::AbstractVector{Int}, level_index::Int)
    return findall(==(level_index), index)
end

function _dff_observations(index_a::AbstractVector{Int},
        level_a::Int,
        index_b::AbstractVector{Int},
        level_b::Int)
    return findall(row -> index_a[row] == level_a && index_b[row] == level_b,
        eachindex(index_a))
end

function _dff_logit_shift_draws(residuals::AbstractVector{<:Real},
        slopes::AbstractVector{<:Real})
    length(residuals) == length(slopes) ||
        throw(ArgumentError("residual and slope vectors must have the same length"))
    out = Vector{Float64}(undef, length(residuals))
    eps_slope = eps(Float64)
    for index in eachindex(residuals)
        slope = Float64(slopes[index])
        residual = Float64(residuals[index])
        out[index] = isfinite(slope) && abs(slope) > eps_slope ?
            residual / slope : NaN
    end
    return out
end

function _dff_group_draws(expected::AbstractMatrix{<:Real},
        residuals::AbstractMatrix{<:Real},
        slopes::AbstractMatrix{<:Real},
        observations::AbstractVector{Int})
    expected_by_draw = _posterior_group_mean(expected, observations)
    residual_by_draw = _posterior_group_mean(residuals, observations)
    slope_by_draw = _posterior_group_mean(slopes, observations)
    logit_shift_by_draw = _dff_logit_shift_draws(residual_by_draw, slope_by_draw)
    return (;
        expected = expected_by_draw,
        residual = residual_by_draw,
        slope = slope_by_draw,
        logit_shift = logit_shift_by_draw,
    )
end

function _dff_interval_excludes_zero(summary)
    return isfinite(summary.lower) &&
        isfinite(summary.upper) &&
        (summary.lower > 0 || summary.upper < 0)
end

function _dff_practical_threshold(value, name::AbstractString)
    value === nothing && return nothing
    value isa Real ||
        throw(ArgumentError("$name must be nothing or a finite non-negative number"))
    checked = Float64(value)
    isfinite(checked) && checked >= 0 ||
        throw(ArgumentError("$name must be nothing or a finite non-negative number"))
    return checked
end

function _dff_practical_probability_threshold(value::Real)
    checked = Float64(value)
    isfinite(checked) && 0 < checked <= 1 ||
        throw(ArgumentError("practical_probability_threshold must be finite and in (0, 1]"))
    return checked
end

function _dff_practical_magnitude_summary(values::AbstractVector{<:Real},
        threshold,
        probability_threshold::Float64)
    threshold === nothing && return (;
        practical_threshold = nothing,
        probability_practically_positive = nothing,
        probability_practically_negative = nothing,
        probability_practically_negligible = nothing,
        probability_practically_large = nothing,
        practical_magnitude = :not_requested,
    )

    finite = [Float64(value) for value in values if isfinite(value)]
    if isempty(finite)
        return (;
            practical_threshold = threshold,
            probability_practically_positive = NaN,
            probability_practically_negative = NaN,
            probability_practically_negligible = NaN,
            probability_practically_large = NaN,
            practical_magnitude = :not_estimable,
        )
    end

    n = length(finite)
    positive = count(>(threshold), finite) / n
    negative = count(<(-threshold), finite) / n
    negligible = count(value -> -threshold <= value <= threshold, finite) / n
    large = positive + negative
    practical_magnitude =
        positive >= probability_threshold ? :practically_positive :
        negative >= probability_threshold ? :practically_negative :
        negligible >= probability_threshold ? :practically_negligible :
        :mixed
    return (;
        practical_threshold = threshold,
        probability_practically_positive = positive,
        probability_practically_negative = negative,
        probability_practically_negligible = negligible,
        probability_practically_large = large,
        practical_magnitude,
    )
end

function _dff_cell_flag(n_observations::Int,
        min_n::Int,
        expected_score_dff_summary,
        logit_dff_summary)
    n_observations == 0 && return :empty_cell
    n_observations < min_n && return :below_min_n
    !isfinite(logit_dff_summary.mean) && return :logit_scale_unstable
    (_dff_interval_excludes_zero(expected_score_dff_summary) ||
        _dff_interval_excludes_zero(logit_dff_summary)) &&
        return :dff_interval_excludes_zero
    return :ok
end

# Project only observed cells; no row/column reference level or missing-cell imputation.
function _dff_assignment_projection(counts::AbstractMatrix{<:Integer})
    cells = findall(>(0), counts)
    isempty(cells) && throw(ArgumentError("DFF requires observed cells"))
    sqrt_weights = sqrt.([Float64(counts[cell]) for cell in cells])
    X = zeros(length(cells), sum(size(counts)))
    for (j, cell) in pairs(cells)
        X[j, cell[1]] = sqrt_weights[j]
        X[j, size(counts, 1) + cell[2]] = sqrt_weights[j]
    end
    factor = svd(X)
    rank_rtol = max(size(X)...) * eps(Float64)
    additive_rank = count(>(rank_rtol * first(factor.S)), factor.S)
    basis = factor.U[:, 1:additive_rank]
    residual_fraction = clamp.(1 .- vec(sum(abs2, basis; dims=2)), 0, 1)
    support_tolerance = 64 * rank_rtol
    supported = residual_fraction .> support_tolerance
    active_levels = count(j -> any(>(0), @view(counts[j, :])), axes(counts, 1)) +
        count(j -> any(>(0), @view(counts[:, j])), axes(counts, 2))
    return (; cells, sqrt_weights, basis, additive_rank, rank_rtol,
        support_tolerance, residual_fraction, supported,
        n_components = active_levels - additive_rank,
        interaction_df = length(cells) - additive_rank)
end

function _dff_project_draws(projection, values::AbstractMatrix{<:Real})
    size(values, 1) == length(projection.cells) ||
        throw(ArgumentError("DFF projection cell count mismatch"))
    out = fill(NaN, size(values))
    for draw in axes(values, 2)
        all(isfinite, @view(values[:, draw])) || continue
        weighted = projection.sqrt_weights .* @view(values[:, draw])
        remainder = weighted - projection.basis * (projection.basis' * weighted)
        # Prevent floating-point cancellation alone from creating a directional flag.
        tolerance = projection.support_tolerance * max(1.0, maximum(abs, weighted))
        for cell in eachindex(weighted)
            projection.supported[cell] || continue
            out[cell, draw] = abs(remainder[cell]) <= tolerance ? 0.0 :
                remainder[cell] / projection.sqrt_weights[cell]
        end
    end
    return out
end

function _dff_report_rows_for_term(design::FacetDesign,
        expected::AbstractMatrix{<:Real},
        residuals::AbstractMatrix{<:Real},
        slopes::AbstractMatrix{<:Real},
        term::Tuple{Symbol,Symbol};
        interval::Real,
        lower_probability::Float64,
        upper_probability::Float64,
        min_n::Int,
        expected_score_practical_threshold,
        logit_practical_threshold,
        practical_probability_threshold::Float64,
        adjustment::Symbol)
    data = design.spec.data
    focal_facet, comparison_facet = term
    focal_index, focal_levels = _fit_stat_groups(data, focal_facet)
    comparison_index, comparison_levels = _fit_stat_groups(data, comparison_facet)
    validation_counts = get(design.spec.validation.dff_counts, term, nothing)
    validation_status = term in design.spec.validation_bias_terms ?
        :declared_validation_term : :ad_hoc_term
    observations_by_cell = [_dff_observations(focal_index, a, comparison_index, b)
        for a in eachindex(focal_levels), b in eachindex(comparison_levels)]
    counts = length.(observations_by_cell)
    cells = [_dff_group_draws(expected, residuals, slopes, observations)
        for observations in observations_by_cell]
    projection = _dff_assignment_projection(counts)
    observed_position = Dict(cell => j for (j, cell) in pairs(projection.cells))
    if adjustment === :assignment
        cell_residuals = reduce(hcat, [cells[c].residual for c in projection.cells])'
        cell_logits = reduce(hcat, [cells[c].logit_shift for c in projection.cells])'
        adjusted_scores = _dff_project_draws(projection, cell_residuals)
        adjusted_logits = _dff_project_draws(projection, cell_logits)
    else
        all_observations = collect(1:data.n)
        grand = _dff_group_draws(expected, residuals, slopes, all_observations)
        focal_draws = [
            _dff_group_draws(
                expected,
                residuals,
                slopes,
                _dff_observations(focal_index, focal_level),
            )
            for focal_level in eachindex(focal_levels)
        ]
        comparison_draws = [
            _dff_group_draws(
                expected,
                residuals,
                slopes,
                _dff_observations(comparison_index, comparison_level),
            )
            for comparison_level in eachindex(comparison_levels)
        ]
    end

    rows = NamedTuple[]
    for (focal_level_index, focal_level) in pairs(focal_levels),
            (comparison_level_index, comparison_level) in pairs(comparison_levels)
        cell_index = CartesianIndex(focal_level_index, comparison_level_index)
        observations = observations_by_cell[cell_index]
        cell = cells[cell_index]
        position = get(observed_position, cell_index, 0)
        contrast_status = position == 0 ? :empty_cell :
            projection.supported[position] ? :supported : :no_independent_cell_contrast
        if adjustment === :assignment
            expected_score_dff = position == 0 ? fill(NaN, size(expected, 1)) :
                vec(adjusted_scores[position, :])
            logit_dff = position == 0 ? fill(NaN, size(expected, 1)) :
                vec(adjusted_logits[position, :])
        else
            focal = focal_draws[focal_level_index]
            comparison = comparison_draws[comparison_level_index]
            expected_score_dff = cell.residual .- focal.residual .-
                comparison.residual .+ grand.residual
            logit_dff = cell.logit_shift .- focal.logit_shift .-
                comparison.logit_shift .+ grand.logit_shift
        end
        n_expected_score_dff_draws = count(isfinite, expected_score_dff)
        n_logit_dff_draws = count(isfinite, logit_dff)

        expected_summary = _finite_draw_summary(
            cell.expected,
            lower_probability,
            upper_probability,
        )
        residual_summary = _finite_draw_summary(
            cell.residual,
            lower_probability,
            upper_probability,
        )
        logit_summary = _finite_draw_summary(
            cell.logit_shift,
            lower_probability,
            upper_probability,
        )
        expected_score_dff_summary = _finite_draw_summary(
            expected_score_dff,
            lower_probability,
            upper_probability,
        )
        logit_dff_summary = _finite_draw_summary(
            logit_dff,
            lower_probability,
            upper_probability,
        )
        expected_score_practical_summary = _dff_practical_magnitude_summary(
            expected_score_dff,
            expected_score_practical_threshold,
            practical_probability_threshold,
        )
        logit_practical_summary = _dff_practical_magnitude_summary(
            logit_dff,
            logit_practical_threshold,
            practical_probability_threshold,
        )
        n_observations = length(observations)
        expected_score_dff_interval_excludes_zero =
            _dff_interval_excludes_zero(expected_score_dff_summary)
        logit_dff_interval_excludes_zero =
            _dff_interval_excludes_zero(logit_dff_summary)
        validation_cell_count = validation_counts === nothing ? missing :
            get(validation_counts, (focal_level, comparison_level), missing)

        push!(rows, (;
            term,
            focal_facet,
            focal_level,
            focal_level_index,
            comparison_facet,
            comparison_level,
            comparison_level_index,
            n_observations,
            validation_cell_count,
            n_draws = size(expected, 1),
            method = :posterior_predictive_interaction_residual,
            adjustment,
            assignment_weighting = :observed_rating_counts,
            assignment_n_observations = sum(counts),
            assignment_n_observed_cells = length(projection.cells),
            assignment_n_components = projection.n_components,
            assignment_additive_rank = projection.additive_rank,
            assignment_interaction_df = projection.interaction_df,
            assignment_rank_rtol = projection.rank_rtol,
            assignment_support_tolerance = projection.support_tolerance,
            cell_residual_fraction = position == 0 ? NaN : projection.residual_fraction[position],
            contrast_status,
            n_expected_score_dff_draws,
            n_logit_dff_draws,
            uncertainty = :conditional_on_observed_scores_and_assignment,
            multiplicity_adjustment = :none,
            logit_method = :local_expected_score_residual_divided_by_predictive_variance,
            scale = :expected_score_and_logit,
            interval_probability = Float64(interval),
            lower_probability,
            upper_probability,
            observed_mean = _mean_at_indices(data.score, observations),
            expected_score_mean = expected_summary.mean,
            expected_score_median = expected_summary.median,
            expected_score_lower = expected_summary.lower,
            expected_score_upper = expected_summary.upper,
            expected_score_residual_mean = residual_summary.mean,
            expected_score_residual_median = residual_summary.median,
            expected_score_residual_lower = residual_summary.lower,
            expected_score_residual_upper = residual_summary.upper,
            logit_residual_mean = logit_summary.mean,
            logit_residual_median = logit_summary.median,
            logit_residual_lower = logit_summary.lower,
            logit_residual_upper = logit_summary.upper,
            expected_score_dff_mean = expected_score_dff_summary.mean,
            expected_score_dff_median = expected_score_dff_summary.median,
            expected_score_dff_lower = expected_score_dff_summary.lower,
            expected_score_dff_upper = expected_score_dff_summary.upper,
            logit_dff_mean = logit_dff_summary.mean,
            logit_dff_median = logit_dff_summary.median,
            logit_dff_lower = logit_dff_summary.lower,
            logit_dff_upper = logit_dff_summary.upper,
            expected_score_dff_interval_excludes_zero,
            logit_dff_interval_excludes_zero,
            practical_probability_threshold,
            expected_score_dff_practical_threshold =
                expected_score_practical_summary.practical_threshold,
            expected_score_dff_probability_practically_positive =
                expected_score_practical_summary.probability_practically_positive,
            expected_score_dff_probability_practically_negative =
                expected_score_practical_summary.probability_practically_negative,
            expected_score_dff_probability_practically_negligible =
                expected_score_practical_summary.probability_practically_negligible,
            expected_score_dff_probability_practically_large =
                expected_score_practical_summary.probability_practically_large,
            expected_score_dff_practical_magnitude =
                expected_score_practical_summary.practical_magnitude,
            logit_dff_practical_threshold =
                logit_practical_summary.practical_threshold,
            logit_dff_probability_practically_positive =
                logit_practical_summary.probability_practically_positive,
            logit_dff_probability_practically_negative =
                logit_practical_summary.probability_practically_negative,
            logit_dff_probability_practically_negligible =
                logit_practical_summary.probability_practically_negligible,
            logit_dff_probability_practically_large =
                logit_practical_summary.probability_practically_large,
            logit_dff_practical_magnitude =
                logit_practical_summary.practical_magnitude,
            validation_status,
            caveat = :dff_screening_not_fitted_dff_effect,
            flag = adjustment === :assignment && contrast_status === :no_independent_cell_contrast ?
                :no_independent_cell_contrast :
                adjustment === :assignment && 0 < n_logit_dff_draws < size(expected, 1) ?
                :incomplete_logit_draws : _dff_cell_flag(
                n_observations,
                min_n,
                expected_score_dff_summary,
                logit_dff_summary,
            ),
        ))
    end
    return rows
end

"""
    dff_report(fit::MFRMFit; terms = :validation, adjustment = :assignment, interval = 0.95,
        min_n = 1, expected_score_practical_threshold = nothing,
        logit_practical_threshold = nothing,
        practical_probability_threshold = 0.8, ndraws = nothing,
        draw_indices = nothing, rng = Random.default_rng())
    dff_report(design::FacetDesign, draws; terms = :validation,
        adjustment = :assignment, interval = 0.95, min_n = 1,
        expected_score_practical_threshold = nothing,
        logit_practical_threshold = nothing,
        practical_probability_threshold = 0.8)

Return screening rows for declared or ad hoc differential facet functioning
(DFF) terms. The default `terms = :validation` uses DFF/bias terms retained in
the `FacetSpec` by `mfrm_spec(...; bias = ...)` or a matching validation
report. Each row is one cell of a two-facet term and reports observed mean
score, posterior expected-score residuals, and a two-way interaction residual
on both expected-score and local logit-approximation scales.

Pass `expected_score_practical_threshold` and/or `logit_practical_threshold`
to add estimand-specific practical-magnitude probabilities and classification.
Rows classify a DFF contrast as `:practically_positive`,
`:practically_negative`, `:practically_negligible`, or `:mixed` when the
corresponding posterior probability is at least
`practical_probability_threshold`; otherwise the practical-magnitude status is
`:not_requested`.

These rows are not fitted DFF model effects. The logit scale is a local
screening approximation that divides expected-score residuals by posterior
predictive variance, so results should be used for fairness review triage and
sensitivity planning rather than confirmatory unfairness claims.

By default `adjustment=:assignment` removes the weighted least-squares additive
focal/comparison surface separately from each draw's cell score residuals and
local logit shifts. Weights are observed rating counts, not inverse variances or
model/sampling weights. No missing cell is imputed. On observed cells, with
indicator matrix `X` and count weights `W`, the residual is
`W^(-1/2) * (I-U*U') * W^(1/2) * y`, where `U` spans `W^(1/2)*X`.
Thus additive cell composition is removed even under unbalanced assignment.
The target is the remainder under this observed allocation, not a balanced
population contrast or a fitted interaction. Scores/draws remain jointly aligned.

Rows retain the complete cell roster, counts, additive rank, assignment component
count, interaction degrees of freedom and `cell_residual_fraction` (one minus
weighted projection leverage). A cell without independent interaction support
has `contrast_status=:no_independent_cell_contrast` and NaN interaction summaries,
not a zero effect. Disconnected components may support their own within-component
contrasts; they do not support between-component comparisons. `min_n` flags cells
without removing them from the projection. Floating-point rank/support tolerances
are reported; cancellation at that tolerance is set to zero before directional
summaries. This is not a practical-effect threshold.

`n_expected_score_dff_draws` and `n_logit_dff_draws` report usable draw counts. If
any observed cell has an undefined local logit shift, that whole term's logit
projection is unavailable for that draw; summaries use finite draws and an
incomplete-draw flag remains. Intervals condition on the observed scores and
assignment and propagate base-model uncertainty only. They are neither repeated-
sample error intervals nor calibrated multiplicity-adjusted tests. Practical
probabilities describe the residual statistic, not a fitted bias parameter.

For reproduction only, `adjustment=:observed_margins` retains the historical
row/column/grand-margin arithmetic and emits a warning. That arithmetic can
retain additive composition under unbalanced assignment. `fit_report` forwards
`dff_adjustment` and records it in report controls. A formal bias claim needs a
defined contrast, adequate linking, and an appropriate fitted interaction model
or separately validated conditional procedure. Neither mode establishes unfairness.

"""
function dff_report(design::FacetDesign,
        draws::AbstractMatrix;
        terms = :validation,
        adjustment::Symbol = :assignment,
        interval::Real = 0.95,
        min_n::Int = 1,
        expected_score_practical_threshold = nothing,
        logit_practical_threshold = nothing,
        practical_probability_threshold::Real = 0.8)
    _check_fit_supported_mfrm(design, "dff_report")
    adjustment in (:assignment, :observed_margins) ||
        throw(ArgumentError("adjustment must be :assignment or :observed_margins"))
    adjustment === :observed_margins && @warn "Legacy observed-margin DFF screening can retain additive composition under unbalanced assignment; use adjustment=:assignment for the count-weighted additive projection."
    min_n >= 1 || throw(ArgumentError("min_n must be positive"))
    lower_probability, upper_probability = _interval_probabilities(interval)
    checked_expected_score_threshold = _dff_practical_threshold(
        expected_score_practical_threshold,
        "expected_score_practical_threshold",
    )
    checked_logit_threshold = _dff_practical_threshold(
        logit_practical_threshold,
        "logit_practical_threshold",
    )
    checked_practical_probability_threshold =
        _dff_practical_probability_threshold(practical_probability_threshold)
    requested_terms = _dff_report_terms(design, terms)
    expected = expected_scores(design, draws)
    residuals = predictive_residuals(design, draws)
    slopes = predictive_variances(design, draws)
    rows = NamedTuple[]
    for term in requested_terms
        append!(rows, _dff_report_rows_for_term(
            design,
            expected,
            residuals,
            slopes,
            term;
            interval,
            adjustment,
            lower_probability,
            upper_probability,
            min_n,
            expected_score_practical_threshold =
                checked_expected_score_threshold,
            logit_practical_threshold = checked_logit_threshold,
            practical_probability_threshold =
                checked_practical_probability_threshold,
        ))
    end
    return rows
end

function dff_report(fit::MFRMFit;
        terms = :validation,
        adjustment::Symbol = :assignment,
        interval::Real = 0.95,
        min_n::Int = 1,
        expected_score_practical_threshold = nothing,
        logit_practical_threshold = nothing,
        practical_probability_threshold::Real = 0.8,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return dff_report(fit.design, fit.draws[indices, :];
        terms,
        adjustment,
        interval,
        min_n,
        expected_score_practical_threshold,
        logit_practical_threshold,
        practical_probability_threshold)
end

function _check_rater_diagnostic_draws(design::FacetDesign,
        draws::AbstractMatrix,
        caller::AbstractString)
    size(draws, 1) >= 1 ||
        throw(ArgumentError("$caller requires at least one posterior draw"))
    size(draws, 2) == length(design.parameter_names) ||
        throw(ArgumentError("draws has $(size(draws, 2)) column(s); expected $(length(design.parameter_names))"))
    all(value -> isfinite(Float64(value)), draws) ||
        throw(ArgumentError("draws contain non-finite values"))
    return draws
end

function _category_use_rows(data::FacetData,
        counts::AbstractVector{<:Integer},
        n_observations::Int)
    category_counts = [
        (category = data.category_levels[index], count = Int(counts[index]))
        for index in eachindex(data.category_levels)
    ]
    category_proportions = [
        (category = data.category_levels[index],
            proportion = n_observations == 0 ? NaN : counts[index] / n_observations)
        for index in eachindex(data.category_levels)
    ]
    unused_categories = [
        data.category_levels[index]
        for index in eachindex(data.category_levels)
        if counts[index] == 0
    ]
    return category_counts, category_proportions, unused_categories
end

function _central_category_summary(data::FacetData,
        counts::AbstractVector{<:Integer},
        n_observations::Int)
    score_minimum = minimum(data.category_levels)
    score_maximum = maximum(data.category_levels)
    midpoint = (Float64(score_minimum) + Float64(score_maximum)) / 2
    distances = [abs(Float64(level) - midpoint) for level in data.category_levels]
    closest = minimum(distances)
    central_indices = findall(==(closest), distances)
    central_categories = [data.category_levels[index] for index in central_indices]
    central_count = sum(counts[index] for index in central_indices)
    return (;
        scale_midpoint = midpoint,
        central_categories,
        central_category_count = Int(central_count),
        central_category_proportion =
            n_observations == 0 ? NaN : central_count / n_observations,
    )
end

function _rater_observed_diagnostic_summary(data::FacetData, rater_index::Int)
    observations = findall(==(rater_index), data.rater)
    n_observations = length(observations)
    counts = zeros(Int, length(data.category_levels))
    for observation in observations
        counts[data.category[observation]] += 1
    end
    category_counts, category_proportions, unused_categories =
        _category_use_rows(data, counts, n_observations)
    central = _central_category_summary(data, counts, n_observations)
    score_values = [Float64(data.score[observation]) for observation in observations]
    score_mean = _mean_at_indices(data.score, observations)
    score_sd = length(score_values) >= 2 ?
        sqrt(_sample_variance_or_nan(score_values)) : NaN
    score_minimum = isempty(score_values) ? missing : minimum(score_values)
    score_maximum = isempty(score_values) ? missing : maximum(score_values)
    score_range = isempty(score_values) ? missing : score_maximum - score_minimum

    return (;
        n_observations,
        n_categories = length(data.category_levels),
        n_categories_used = count(>(0), counts),
        category_counts,
        category_proportions,
        unused_categories,
        mean_score = score_mean,
        score_sd,
        min_score = score_minimum,
        max_score = score_maximum,
        score_range,
        central.scale_midpoint,
        central.central_categories,
        central.central_category_count,
        central.central_category_proportion,
    )
end

function _rater_mfrm_severity_draws(design::FacetDesign,
        draws::AbstractMatrix,
        rater_index::Int)
    values = Vector{Float64}(undef, size(draws, 1))
    for draw in axes(draws, 1)
        values[draw] = Float64(_stable_facet_value(
            design,
            @view(draws[draw, :]),
            :rater,
            rater_index,
        ))
    end
    return values
end

function _rater_direct_block_draws(design::FacetDesign,
        direct_draws::AbstractMatrix,
        block::Symbol,
        rater_index::Int)
    haskey(design.blocks, block) || return nothing
    block_range = design.blocks[block]
    1 <= rater_index <= length(block_range) || return nothing
    values = Vector{Float64}(undef, size(direct_draws, 1))
    column = block_range[rater_index]
    for draw in axes(direct_draws, 1)
        values[draw] = Float64(direct_draws[draw, column])
    end
    return values
end

function _maybe_finite_draw_summary(values,
        lower_probability::Float64,
        upper_probability::Float64)
    values === nothing &&
        return (mean = missing, median = missing, lower = missing, upper = missing)
    return _finite_draw_summary(values, lower_probability, upper_probability)
end

function _rater_diagnostics_flag(n_observations::Int,
        min_n::Int,
        residual_flag,
        fit_flag)
    n_observations < min_n && return :below_min_n
    residual_flag !== :ok && return residual_flag
    fit_flag !== missing && fit_flag !== :ok && return fit_flag
    return :ok
end

function _row_by_level(rows)
    return Dict(row.level => row for row in rows)
end

function _rater_diagnostic_row(;
        data::FacetData,
        model_family::Symbol,
        level_index::Int,
        level,
        n_draws::Int,
        interval::Real,
        lower_probability::Float64,
        upper_probability::Float64,
        severity_parameter_name,
        severity_status::Symbol,
        severity_fixed_value,
        severity_values,
        discrimination_modeled::Bool,
        discrimination_parameter,
        discrimination_parameter_name,
        discrimination_scale::Symbol,
        discrimination_values,
        residual_row,
        fit_row,
        fit_statistics_available::Bool,
        min_n::Int)
    observed = _rater_observed_diagnostic_summary(data, level_index)
    severity_summary =
        _finite_draw_summary(severity_values, lower_probability, upper_probability)
    discrimination_summary =
        _maybe_finite_draw_summary(
            discrimination_values,
            lower_probability,
            upper_probability,
        )
    fit_flag = fit_statistics_available ? fit_row.flag : missing
    flag = _rater_diagnostics_flag(
        observed.n_observations,
        min_n,
        residual_row.flag,
        fit_flag,
    )

    return (;
        facet = :rater,
        level,
        rater = level,
        rater_index = level_index,
        model_family,
        method = :posterior_rater_diagnostics,
        n_draws,
        interval_probability = Float64(interval),
        lower_probability,
        upper_probability,
        observed.n_observations,
        observed.n_categories,
        observed.n_categories_used,
        observed.category_counts,
        observed.category_proportions,
        observed.unused_categories,
        observed.mean_score,
        observed.score_sd,
        observed.min_score,
        observed.max_score,
        observed.score_range,
        observed.scale_midpoint,
        observed.central_categories,
        observed.central_category_count,
        observed.central_category_proportion,
        severity_parameter_name,
        severity_status,
        severity_is_fixed = severity_status in (:reference_zero, :hard_anchor),
        severity_fixed_value,
        severity_reference = severity_status === :reference_zero,
        severity_mean = severity_summary.mean,
        severity_median = severity_summary.median,
        severity_lower = severity_summary.lower,
        severity_upper = severity_summary.upper,
        discrimination_modeled,
        discrimination_parameter,
        discrimination_parameter_name,
        discrimination_scale,
        discrimination_mean = discrimination_summary.mean,
        discrimination_median = discrimination_summary.median,
        discrimination_lower = discrimination_summary.lower,
        discrimination_upper = discrimination_summary.upper,
        residual_mean = residual_row.residual_mean,
        residual_median = residual_row.residual_median,
        residual_lower = residual_row.residual_lower,
        residual_upper = residual_row.residual_upper,
        absolute_residual_mean = residual_row.absolute_residual_mean,
        absolute_residual_median = residual_row.absolute_residual_median,
        absolute_residual_lower = residual_row.absolute_residual_lower,
        absolute_residual_upper = residual_row.absolute_residual_upper,
        rmse_mean = residual_row.rmse_mean,
        rmse_median = residual_row.rmse_median,
        rmse_lower = residual_row.rmse_lower,
        rmse_upper = residual_row.rmse_upper,
        residual_interval_excludes_zero = residual_row.residual_interval_excludes_zero,
        residual_flag = residual_row.flag,
        fit_statistics_available,
        infit_mean = fit_statistics_available ? fit_row.infit_mean : missing,
        infit_median = fit_statistics_available ? fit_row.infit_median : missing,
        infit_lower = fit_statistics_available ? fit_row.infit_lower : missing,
        infit_upper = fit_statistics_available ? fit_row.infit_upper : missing,
        outfit_mean = fit_statistics_available ? fit_row.outfit_mean : missing,
        outfit_median = fit_statistics_available ? fit_row.outfit_median : missing,
        outfit_lower = fit_statistics_available ? fit_row.outfit_lower : missing,
        outfit_upper = fit_statistics_available ? fit_row.outfit_upper : missing,
        fit_flag,
        caveat = :rater_diagnostics_screening_not_confirmatory,
        flag,
    )
end

"""
    rater_diagnostics(fit::MFRMFit; interval = 0.95, min_n = 1,
        ndraws = nothing, draw_indices = nothing, rng = Random.default_rng())
    rater_diagnostics(fit::GMFRMFit; interval = 0.95, min_n = 1,
        ndraws = nothing, draw_indices = nothing, rng = Random.default_rng())
    rater_diagnostics(design::FacetDesign, draws; interval = 0.95, min_n = 1)

Return one posterior diagnostic row per rater. Rows combine observed category
use, score range and central-category use, posterior rater severity intervals,
posterior residual summaries, and MFRM infit/outfit summaries where available.
For the fit-supported minimal MFRM, a rater-consistency multiplier is not
modeled and the generalized consistency fields are marked missing. For the
guarded scalar GMFRM fit object, the `rater_consistency`
multiplier is summarized as the current positive source-equation parameter;
infit/outfit statistics are not yet available for that path.
"""
function rater_diagnostics(design::FacetDesign,
        draws::AbstractMatrix;
        interval::Real = 0.95,
        min_n::Int = 1)
    _check_fit_supported_mfrm(design, "rater_diagnostics")
    min_n >= 1 || throw(ArgumentError("min_n must be positive"))
    _check_rater_diagnostic_draws(design, draws, "rater_diagnostics")
    lower_probability, upper_probability = _interval_probabilities(interval)
    data = design.spec.data
    residual_by_level = _row_by_level(residual_summary(design, draws;
        by = :rater,
        interval,
        min_n))
    fit_by_level = _row_by_level(fit_stats(design, draws;
        by = :rater,
        interval,
        min_n))
    rows = NamedTuple[]

    for (level_index, level) in pairs(data.rater_levels)
        severity_values = _rater_mfrm_severity_draws(design, draws, level_index)
        severity_parameter_index =
            _stable_facet_parameter_index(design, :rater, level_index)
        severity_parameter_name = severity_parameter_index === missing ? missing :
            design.parameter_names[severity_parameter_index]
        severity_anchored = haskey(
            _stable_hard_anchor_map(design)[:rater],
            level_index,
        )
        severity_status = severity_parameter_index === missing ?
            (severity_anchored ? :hard_anchor : :reference_zero) : :estimated
        severity_fixed_value = severity_parameter_index === missing ?
            _stable_facet_fixed_value(design, :rater, level_index) : missing
        push!(rows, _rater_diagnostic_row(;
            data,
            model_family = :mfrm,
            level_index,
            level,
            n_draws = size(draws, 1),
            interval,
            lower_probability,
            upper_probability,
            severity_parameter_name,
            severity_status,
            severity_fixed_value,
            severity_values,
            discrimination_modeled = false,
            discrimination_parameter = missing,
            discrimination_parameter_name = missing,
            discrimination_scale = :not_modeled,
            discrimination_values = nothing,
            residual_row = residual_by_level[level],
            fit_row = fit_by_level[level],
            fit_statistics_available = true,
            min_n,
        ))
    end
    return rows
end

function rater_diagnostics(fit::MFRMFit;
        interval::Real = 0.95,
        min_n::Int = 1,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return rater_diagnostics(fit.design, fit.draws[indices, :];
        interval,
        min_n)
end

function rater_diagnostics(fit::GMFRMFit;
        interval::Real = 0.95,
        min_n::Int = 1,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    min_n >= 1 || throw(ArgumentError("min_n must be positive"))
    lower_probability, upper_probability = _interval_probabilities(interval)
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    direct_draws = _gmfrm_direct_draws_for_prediction(
        fit.design,
        fit.direct_draws[indices, :],
        "rater_diagnostics",
    )
    data = fit.design.spec.data
    residual_by_level = _row_by_level(residual_summary(fit;
        by = :rater,
        interval,
        min_n,
        draw_indices = indices))
    rows = NamedTuple[]

    for (level_index, level) in pairs(data.rater_levels)
        severity_values =
            _rater_direct_block_draws(fit.design, direct_draws, :rater, level_index)
        severity_values === nothing &&
            throw(ArgumentError("rater_diagnostics requires a direct rater block"))
        severity_index = fit.design.blocks[:rater][level_index]
        discrimination_values = _rater_direct_block_draws(
            fit.design,
            direct_draws,
            :rater_consistency,
            level_index,
        )
        discrimination_modeled = discrimination_values !== nothing
        discrimination_index = discrimination_modeled ?
            fit.design.blocks[:rater_consistency][level_index] : missing

        push!(rows, _rater_diagnostic_row(;
            data,
            model_family = :gmfrm,
            level_index,
            level,
            n_draws = size(direct_draws, 1),
            interval,
            lower_probability,
            upper_probability,
            severity_parameter_name = fit.design.parameter_names[severity_index],
            severity_status = :estimated,
            severity_fixed_value = missing,
            severity_values,
            discrimination_modeled,
            discrimination_parameter = discrimination_modeled ?
                :rater_consistency : missing,
            discrimination_parameter_name = discrimination_modeled ?
                fit.design.parameter_names[discrimination_index] : missing,
            discrimination_scale = discrimination_modeled ?
                :positive_consistency_multiplier : :not_modeled,
            discrimination_values,
            residual_row = residual_by_level[level],
            fit_row = missing,
            fit_statistics_available = false,
            min_n,
        ))
    end
    return rows
end
