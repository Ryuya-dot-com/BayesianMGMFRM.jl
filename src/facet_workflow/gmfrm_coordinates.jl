function _check_gmfrm_source_fixture_design(design::FacetDesign, caller::AbstractString)
    design.spec.family === :gmfrm &&
        design.spec.estimation_status === :specified_only ||
        throw(ArgumentError("$caller is only for specified-only GMFRM preview designs"))
    capability = _check_guarded_generalized_spec(design.spec, caller)
    Set(keys(design.blocks)) == Set(capability.expected_blocks) ||
        throw(_guarded_generalized_unsupported_error(
            caller,
            :gmfrm,
            :compiled_blocks,
            Tuple(sort!(collect(keys(design.blocks)); by = string)),
            "the compiled design blocks do not match the guarded GMFRM kernel contract",
        ))
    for block in capability.expected_blocks
        haskey(design.blocks, block) ||
            throw(ArgumentError("$caller requires a GMFRM preview block :$block"))
    end
    return nothing
end

function _check_approx_constraint(name::AbstractString, value, target; atol = 1e-8)
    abs(value - target) <= atol ||
        throw(ArgumentError("$name must be approximately $target for the source fixture; got $value"))
    return nothing
end

function _check_positive_constraint(name::AbstractString, values)
    all(value -> isfinite(value) && value > 0, values) ||
        throw(ArgumentError("$name must be finite and strictly positive for the source fixture"))
    return nothing
end

# Avoid overflow/underflow of intermediate products when finite factors balance.
# Invalid factors remain reportable as a failed constraint, without log-domain errors.
_positive_product(values) = all(value -> isfinite(value) && value > 0, values) ?
    exp(sum(log, values)) : NaN

function _gmfrm_source_fixture_constraints(design::FacetDesign, params::AbstractVector)
    data = design.spec.data
    item_values = params[design.blocks[:item]]
    item_discriminations = params[design.blocks[:item_discrimination]]
    rater_consistencies = params[design.blocks[:rater_consistency]]
    _check_approx_constraint("sum(item difficulty)", sum(item_values), _param_zero(params))
    _check_positive_constraint("item discrimination", item_discriminations)
    _check_approx_constraint("prod(item discrimination)", _positive_product(item_discriminations), 1.0)
    _check_positive_constraint("rater consistency", rater_consistencies)
    length(item_values) == length(data.item_levels) ||
        throw(ArgumentError("GMFRM source fixture expected one item difficulty per item level"))
    length(rater_consistencies) == length(data.rater_levels) ||
        throw(ArgumentError("GMFRM source fixture expected one rater consistency per rater level"))
    return nothing
end

function _source_step_value(design::FacetDesign,
        params::AbstractVector,
        block::Symbol,
        level_index::Int,
        source_step::Int)
    data = design.spec.data
    K = length(data.category_levels)
    source_step == 1 && return _param_zero(params)
    2 <= source_step <= K ||
        throw(ArgumentError("source-model step m = $source_step is outside 2:$K"))
    free_steps = max(K - 2, 0)
    free_steps == 0 && return _param_zero(params)
    block_range = design.blocks[block]
    offset = (level_index - 1) * free_steps
    if source_step <= K - 1
        return params[block_range[offset + source_step - 1]]
    end
    total = _param_zero(params)
    for m in 2:(K - 1)
        total += params[block_range[offset + m - 1]]
    end
    return -total
end

function _source_step_values(design::FacetDesign,
        params::AbstractVector,
        block::Symbol,
        level_index::Int,
        category_index::Int)
    category_index <= 1 && return typeof(_param_zero(params) + 0.0)[]
    return [
        _source_step_value(design, params, block, level_index, source_step)
        for source_step in 2:category_index
    ]
end

function _put_block_values!(out::AbstractVector, block::UnitRange{Int}, values)
    length(block) == length(values) ||
        throw(ArgumentError("cannot assign $(length(values)) value(s) to block of length $(length(block))"))
    for (index, value) in zip(block, values)
        out[index] = value
    end
    return out
end

function _sum_to_zero_from_raw(raw_values, n::Int)
    n >= 1 || return typeof(_param_zero(raw_values) + 0.0)[]
    expected = n - 1
    length(raw_values) == expected ||
        throw(ArgumentError("sum-to-zero transform expected $expected raw value(s); got $(length(raw_values))"))
    T = typeof(_param_zero(raw_values) + 0.0)
    values = Vector{T}(undef, n)
    total = _param_zero(raw_values)
    for index in 1:expected
        values[index] = raw_values[index]
        total += raw_values[index]
    end
    values[n] = -total
    return values
end

function _geometric_mean_one_from_log_raw(log_raw_values, n::Int)
    n >= 1 || return typeof(exp(_param_zero(log_raw_values)))[]
    expected = n - 1
    length(log_raw_values) == expected ||
        throw(ArgumentError("geometric-mean-one transform expected $expected raw log value(s); got $(length(log_raw_values))"))
    T = typeof(exp(_param_zero(log_raw_values)))
    values = Vector{T}(undef, n)
    total = _param_zero(log_raw_values)
    for index in 1:expected
        values[index] = exp(log_raw_values[index])
        total += log_raw_values[index]
    end
    values[n] = exp(-total)
    return values
end

function _positive_from_log_raw(log_raw_values)
    return [exp(value) for value in log_raw_values]
end

function _free_except_last_names(levels, prefix::AbstractString)
    return [prefix * "[" * string(level) * "]" for level in levels[1:max(end - 1, 0)]]
end

function _gmfrm_unconstrained_blueprint(design::FacetDesign;
        caller::AbstractString,
        scope::Symbol,
        status::Symbol,
        fit_ready::Bool,
        fixture_only::Bool,
        compiler_stage::Symbol)
    _check_gmfrm_source_fixture_design(design, caller)
    data = design.spec.data
    names = String[]
    blocks = Dict{Symbol,UnitRange{Int}}()
    _push_named_block!(names, blocks, :person, copy(design.parameter_names[design.blocks[:person]]))
    _push_named_block!(names, blocks, :rater, copy(design.parameter_names[design.blocks[:rater]]))
    _push_named_block!(names, blocks, :item_free,
        _free_except_last_names(data.item_levels, "raw_item"))
    _push_named_block!(names, blocks, :log_item_discrimination_free,
        _free_except_last_names(data.item_levels, "raw_log_item_discrimination"))
    _push_named_block!(names, blocks, :log_rater_consistency,
        ["raw_log_rater_consistency[rater=$(rater)]" for rater in data.rater_levels])
    _push_named_block!(names, blocks, :rater_steps, copy(design.parameter_names[design.blocks[:rater_steps]]))
    return (;
        family = :gmfrm,
        scope,
        status,
        compiler_stage,
        parameter_names = names,
        blocks,
        n_parameters = length(names),
        constrained_parameter_names = copy(design.parameter_names),
        constrained_blocks = copy(design.blocks),
        fit_ready,
        fixture_only,
    )
end

function _gmfrm_source_unconstrained_blueprint(design::FacetDesign)
    return _gmfrm_unconstrained_blueprint(design;
        caller = "_gmfrm_source_unconstrained_blueprint",
        scope = :scalar_gmfrm_source_aligned,
        status = :internal_source_fixture,
        fit_ready = false,
        fixture_only = true,
        compiler_stage = :source_fixture,
    )
end

function _gmfrm_fit_ready_candidate_blueprint(design::FacetDesign)
    return _gmfrm_unconstrained_blueprint(design;
        caller = "_gmfrm_fit_ready_candidate_blueprint",
        scope = :scalar_gmfrm_fit_ready_candidate,
        status = :internal_fit_ready_candidate,
        fit_ready = false,
        fixture_only = false,
        compiler_stage = :fit_ready_candidate,
    )
end

function _gmfrm_source_constrained_params_from_unconstrained(
        design::FacetDesign,
        raw_params::AbstractVector)
    blueprint = _gmfrm_source_unconstrained_blueprint(design)
    length(raw_params) == blueprint.n_parameters ||
        throw(ArgumentError("GMFRM source transform expected $(blueprint.n_parameters) raw parameter(s); got $(length(raw_params))"))
    T = typeof(_param_zero(raw_params) + 0.0)
    params = Vector{T}(undef, length(design.parameter_names))
    data = design.spec.data
    raw_blocks = blueprint.blocks
    _put_block_values!(params, design.blocks[:person], raw_params[raw_blocks[:person]])
    _put_block_values!(params, design.blocks[:rater], raw_params[raw_blocks[:rater]])
    _put_block_values!(params, design.blocks[:item],
        _sum_to_zero_from_raw(raw_params[raw_blocks[:item_free]], length(data.item_levels)))
    _put_block_values!(params, design.blocks[:item_discrimination],
        _geometric_mean_one_from_log_raw(
            raw_params[raw_blocks[:log_item_discrimination_free]],
            length(data.item_levels),
        ))
    _put_block_values!(params, design.blocks[:rater_consistency],
        _positive_from_log_raw(raw_params[raw_blocks[:log_rater_consistency]]))
    _put_block_values!(params, design.blocks[:rater_steps], raw_params[raw_blocks[:rater_steps]])
    _gmfrm_source_fixture_constraints(design, params)
    return params
end

function _gmfrm_source_row_terms(design::FacetDesign, params::AbstractVector, row::Int)
    data = design.spec.data
    person_value = params[design.blocks[:person][data.person[row]]]
    rater_value = params[design.blocks[:rater][data.rater[row]]]
    item_value = params[design.blocks[:item][data.item[row]]]
    item_discrimination_value = params[design.blocks[:item_discrimination][data.item[row]]]
    rater_consistency_value = params[design.blocks[:rater_consistency][data.rater[row]]]
    location_value = person_value - item_value - rater_value
    scale_value = item_discrimination_value * rater_consistency_value
    return (;
        person_value,
        rater_value,
        item_value,
        item_discrimination_value,
        rater_consistency_value,
        location_value,
        scale_value,
    )
end

function _gmfrm_source_linear_predictors!(etas::AbstractVector,
        design::FacetDesign,
        params::AbstractVector,
        row::Int)
    data = design.spec.data
    K = length(data.category_levels)
    length(etas) == K ||
        throw(ArgumentError("eta vector has length $(length(etas)); expected $K"))
    terms = _gmfrm_source_row_terms(design, params, row)
    etas[1] = zero(terms.scale_value * terms.location_value)
    cumulative = zero(etas[1])
    rater_index = data.rater[row]
    for category_index in 2:K
        step_value = _source_step_value(design, params, :rater_steps, rater_index, category_index)
        cumulative += terms.scale_value * (terms.location_value - step_value)
        etas[category_index] = cumulative
    end
    return etas
end

function _gmfrm_source_pointwise_loglikelihood(design::FacetDesign, params::AbstractVector)
    _check_gmfrm_source_fixture_design(design, "_gmfrm_source_pointwise_loglikelihood")
    _check_parameter_vector_length(design, params)
    _gmfrm_source_fixture_constraints(design, params)
    data = design.spec.data
    K = length(data.category_levels)
    T = typeof(_param_zero(params) + 0.0)
    etas = Vector{T}(undef, K)
    out = Vector{T}(undef, data.n)
    for row in 1:data.n
        _gmfrm_source_linear_predictors!(etas, design, params, row)
        out[row] = etas[data.category[row]] - _logsumexp(etas)
    end
    return out
end

function _gmfrm_source_pointwise_loglikelihood_from_unconstrained(
        design::FacetDesign,
        raw_params::AbstractVector)
    params = _gmfrm_source_constrained_params_from_unconstrained(design, raw_params)
    return _gmfrm_source_pointwise_loglikelihood(design, params)
end

function _gmfrm_source_loglikelihood_from_unconstrained(
        design::FacetDesign,
        raw_params::AbstractVector)
    pointwise = _gmfrm_source_pointwise_loglikelihood_from_unconstrained(design, raw_params)
    return sum(pointwise; init = _param_zero(pointwise))
end

function _gmfrm_source_fixture_values(design::FacetDesign, params::AbstractVector)
    _check_gmfrm_source_fixture_design(design, "_gmfrm_source_fixture_values")
    _check_parameter_vector_length(design, params)
    _gmfrm_source_fixture_constraints(design, params)
    data = design.spec.data
    K = length(data.category_levels)
    T = typeof(_param_zero(params) + 0.0)
    etas = Vector{T}(undef, K)
    index_by_name = _parameter_index_map(design)
    rows = NamedTuple[]
    for row in 1:data.n
        _gmfrm_source_linear_predictors!(etas, design, params, row)
        log_denominator = _logsumexp(etas)
        terms = _gmfrm_source_row_terms(design, params, row)
        for category_index in eachindex(data.category_levels)
            components = _predictor_components(design, index_by_name, row, category_index)
            step_values = _source_step_values(
                design,
                params,
                :rater_steps,
                data.rater[row],
                category_index,
            )
            step_sum = sum(step_values; init = _param_zero(params))
            eta = etas[category_index]
            push!(rows, merge(components, terms, (;
                step_values,
                step_sum,
                scaled_step_sum = terms.scale_value * step_sum,
                eta,
                log_denominator,
                log_probability = eta - log_denominator,
                fixture_only = true,
                fit_ready = false,
            )))
        end
    end
    return rows
end
