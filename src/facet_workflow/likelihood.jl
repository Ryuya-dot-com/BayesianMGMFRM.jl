function _logsumexp(vals::AbstractVector)
    m = maximum(vals)
    return m + log(sum(exp(v - m) for v in vals))
end

function _param_zero(params::AbstractVector)
    isempty(params) && return 0.0
    return zero(first(params))
end

function _reference_value(params::AbstractVector, block::UnitRange{Int}, index::Int)
    index == 1 && return _param_zero(params)
    return params[block[index - 1]]
end

function _threshold_step(design::FacetDesign, params::AbstractVector, item::Int, step::Int)
    step_range = design.blocks[:thresholds]
    kminus1 = length(design.spec.data.category_levels) - 1
    free_steps = max(kminus1 - 1, 0)
    if free_steps == 0
        return _param_zero(params)
    end
    if design.spec.thresholds === :rating_scale
        if step <= free_steps
            return params[step_range[step]]
        end
        total = _param_zero(params)
        for s in 1:free_steps
            total += params[step_range[s]]
        end
        return -total
    else
        offset = (item - 1) * free_steps
        if step <= free_steps
            return params[step_range[offset + step]]
        end
        total = _param_zero(params)
        for s in 1:free_steps
            total += params[step_range[offset + s]]
        end
        return -total
    end
end

"""
    threshold_map_data(spec_or_design; params = nothing)

Return long-form threshold-step metadata for rating-scale or partial-credit
threshold maps. When `params` is supplied, the returned rows include the
identified threshold-step value, including the sum-to-zero derived step.
Without `params`, `value` is `missing`.
"""
function threshold_map_data(spec::FacetSpec; params = nothing)
    return threshold_map_data(getdesign(spec); params)
end

function threshold_map_data(design::FacetDesign; params = nothing)
    if params !== nothing
        length(params) == length(design.parameter_names) ||
            throw(ArgumentError("parameter vector has length $(length(params)); expected $(length(design.parameter_names))"))
    end
    data = design.spec.data
    K = length(data.category_levels)
    nsteps = max(K - 1, 0)
    rows = NamedTuple[]

    function push_step!(item_index, item_label, step)
        metadata = _threshold_step_metadata(design, item_index, step)
        value = params === nothing ? missing : _threshold_step(design, params, item_index, step)
        push!(rows, (;
            thresholds = design.spec.thresholds,
            item = item_label,
            step = metadata.step,
            from_category = metadata.from_category,
            to_category = metadata.to_category,
            parameter_index = metadata.parameter_index,
            parameter_name = metadata.parameter_name,
            status = metadata.status,
            value,
        ))
    end

    if design.spec.thresholds === :rating_scale
        for step in 1:nsteps
            push_step!(1, missing, step)
        end
    else
        for (item_index, item_label) in pairs(data.item_levels), step in 1:nsteps
            push_step!(item_index, item_label, step)
        end
    end
    return rows
end

function _step_sum(design::FacetDesign, params::AbstractVector, item::Int, category::Int)
    total = _param_zero(params)
    category <= 1 && return total
    for step in 1:(category - 1)
        total += _threshold_step(design, params, item, step)
    end
    return total
end

function _pointwise_loglikelihood_unchecked(
        design::FacetDesign,
        params::AbstractVector)
    data = design.spec.data
    T = typeof(_param_zero(params) + 0.0)
    out = Vector{T}(undef, data.n)
    K = length(data.category_levels)
    etas = Vector{T}(undef, K)
    for n in 1:data.n
        _linear_predictors!(etas, design, params, n)
        out[n] = etas[data.category[n]] - _logsumexp(etas)
    end
    return out
end

"""
    pointwise_loglikelihood(design::FacetDesign, params)

Evaluate the minimal additive RSM/PCM pointwise log likelihood for the
identified parameter vector returned by `getdesign`. This helper is for design
validation and does not apply Bayesian priors.
"""
function pointwise_loglikelihood(design::FacetDesign, params::AbstractVector)
    _check_fit_supported_mfrm(design, "pointwise_loglikelihood")
    _check_parameter_vector_length(design, params)
    return _pointwise_loglikelihood_unchecked(design, params)
end
