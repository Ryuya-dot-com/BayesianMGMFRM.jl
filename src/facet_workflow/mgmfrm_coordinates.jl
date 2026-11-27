function _check_mgmfrm_source_fixture_design(
        design::FacetDesign,
        caller::AbstractString;
        require_q_observation_coverage::Bool = true)
    design.spec.family === :mgmfrm &&
        design.spec.estimation_status === :specified_only ||
        throw(ArgumentError("$caller is only for specified-only MGMFRM preview designs"))
    capability = _check_guarded_generalized_spec(
        design.spec,
        caller;
        require_q_observation_coverage,
    )
    Set(keys(design.blocks)) == Set(capability.expected_blocks) ||
        throw(_guarded_generalized_unsupported_error(
            caller,
            :mgmfrm,
            :compiled_blocks,
            Tuple(sort!(collect(keys(design.blocks)); by = string)),
            "the compiled design blocks do not match the guarded MGMFRM kernel contract",
        ))
    for block in capability.expected_blocks
        haskey(design.blocks, block) ||
            throw(ArgumentError("$caller requires an MGMFRM preview block :$block"))
    end
    design.spec.q_matrix === nothing &&
        throw(ArgumentError("$caller requires a fixed Q-matrix"))
    return nothing
end

function _mgmfrm_unconstrained_blueprint(design::FacetDesign;
        caller::AbstractString,
        scope::Symbol,
        status::Symbol,
        fit_ready::Bool,
        fixture_only::Bool,
        compiler_stage::Symbol)
    _check_mgmfrm_source_fixture_design(design, caller)
    data = design.spec.data
    names = String[]
    blocks = Dict{Symbol,UnitRange{Int}}()
    _push_named_block!(names, blocks, :person, copy(design.parameter_names[design.blocks[:person]]))
    _push_named_block!(names, blocks, :rater_free,
        _free_except_last_names(data.rater_levels, "raw_rater"))
    _push_named_block!(names, blocks, :item, copy(design.parameter_names[design.blocks[:item]]))
    _push_named_block!(names, blocks, :log_item_dimension_discrimination,
        ["raw_log_" * name for name in design.parameter_names[design.blocks[:item_dimension_discrimination]]])
    _push_named_block!(names, blocks, :log_rater_consistency_free,
        _free_except_last_names(data.rater_levels, "raw_log_rater_consistency"))
    _push_named_block!(names, blocks, :item_steps, copy(design.parameter_names[design.blocks[:item_steps]]))
    return (;
        family = :mgmfrm,
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

function _mgmfrm_source_unconstrained_blueprint(design::FacetDesign)
    return _mgmfrm_unconstrained_blueprint(design;
        caller = "_mgmfrm_source_unconstrained_blueprint",
        scope = :mgmfrm_source_aligned,
        status = :internal_source_fixture,
        fit_ready = false,
        fixture_only = true,
        compiler_stage = :source_fixture,
    )
end

function _mgmfrm_fit_ready_candidate_blueprint(design::FacetDesign)
    return _mgmfrm_unconstrained_blueprint(design;
        caller = "_mgmfrm_fit_ready_candidate_blueprint",
        scope = :minimal_confirmatory_mgmfrm_candidate,
        status = :internal_fit_ready_candidate,
        fit_ready = false,
        fixture_only = false,
        compiler_stage = :fit_ready_candidate,
    )
end

function _mgmfrm_source_constrained_params_from_unconstrained(
        design::FacetDesign,
        raw_params::AbstractVector,
        blueprint::NamedTuple = _mgmfrm_source_unconstrained_blueprint(design))
    # Numerical targets own a validated design snapshot and its blueprint.
    # Standalone two-argument calls still validate and compile the design.
    length(raw_params) == blueprint.n_parameters ||
        throw(ArgumentError("MGMFRM source transform expected $(blueprint.n_parameters) raw parameter(s); got $(length(raw_params))"))
    T = typeof(_param_zero(raw_params) + 0.0)
    params = Vector{T}(undef, length(design.parameter_names))
    data = design.spec.data
    raw_blocks = blueprint.blocks
    _put_block_values!(params, design.blocks[:person], raw_params[raw_blocks[:person]])
    _put_block_values!(params, design.blocks[:rater],
        _sum_to_zero_from_raw(raw_params[raw_blocks[:rater_free]], length(data.rater_levels)))
    _put_block_values!(params, design.blocks[:item], raw_params[raw_blocks[:item]])
    _put_block_values!(params, design.blocks[:item_dimension_discrimination],
        _positive_from_log_raw(raw_params[raw_blocks[:log_item_dimension_discrimination]]))
    _put_block_values!(params, design.blocks[:rater_consistency],
        _geometric_mean_one_from_log_raw(
            raw_params[raw_blocks[:log_rater_consistency_free]],
            length(data.rater_levels),
        ))
    _put_block_values!(params, design.blocks[:item_steps], raw_params[raw_blocks[:item_steps]])
    _mgmfrm_source_fixture_constraints(design, params)
    return params
end

function _mgmfrm_source_fixture_constraints(design::FacetDesign, params::AbstractVector)
    data = design.spec.data
    rater_values = params[design.blocks[:rater]]
    item_values = params[design.blocks[:item]]
    item_dimension_discriminations = params[design.blocks[:item_dimension_discrimination]]
    rater_consistencies = params[design.blocks[:rater_consistency]]
    _check_approx_constraint("sum(rater severity)", sum(rater_values), _param_zero(params))
    _check_positive_constraint("item-dimension discrimination", item_dimension_discriminations)
    _check_positive_constraint("rater consistency", rater_consistencies)
    _check_approx_constraint("prod(rater consistency)", _positive_product(rater_consistencies), 1.0)
    length(rater_values) == length(data.rater_levels) ||
        throw(ArgumentError("MGMFRM source fixture expected one rater severity per rater level"))
    length(item_values) == length(data.item_levels) ||
        throw(ArgumentError("MGMFRM source fixture expected one item difficulty per item level"))
    length(rater_consistencies) == length(data.rater_levels) ||
        throw(ArgumentError("MGMFRM source fixture expected one rater consistency per rater level"))
    return nothing
end

function _mgmfrm_source_row_terms(design::FacetDesign,
        index_by_name,
        params::AbstractVector,
        row::Int)
    data = design.spec.data
    dims = design.spec.dimensions
    person_block = design.blocks[:person]
    person_offset = (data.person[row] - 1) * dims
    person_values = [params[person_block[person_offset + dim]] for dim in 1:dims]
    active_dimensions = _loading_dimensions(design.spec, data.item[row])
    discrimination_indices = _loading_parameter_indices(design, index_by_name, data.item[row])
    item_dimension_discrimination_values = [params[index] for index in discrimination_indices]
    ability_score = _param_zero(params)
    for (dim, value) in zip(active_dimensions, item_dimension_discrimination_values)
        ability_score += value * person_values[dim]
    end
    rater_value = params[design.blocks[:rater][data.rater[row]]]
    item_value = params[design.blocks[:item][data.item[row]]]
    rater_consistency_value = params[design.blocks[:rater_consistency][data.rater[row]]]
    source_scale = 1.7
    scale_value = source_scale * rater_consistency_value
    location_value = ability_score - item_value - rater_value
    return (;
        person_values,
        active_dimension_values = [person_values[dim] for dim in active_dimensions],
        item_dimension_discrimination_values,
        ability_score,
        rater_value,
        item_value,
        rater_consistency_value,
        source_scale,
        scale_value,
        location_value,
    )
end

function _mgmfrm_source_linear_predictors!(etas::AbstractVector,
        design::FacetDesign,
        _index_by_name,
        params::AbstractVector,
        row::Int)
    return _mgmfrm_source_linear_predictors!(
        etas,
        design,
        params,
        row,
        _mgmfrm_source_loading_index_matrix(design),
    )
end

function _mgmfrm_source_linear_predictors!(etas::AbstractVector,
        design::FacetDesign,
        params::AbstractVector,
        row::Int,
        loading_indices::AbstractMatrix{Int},
        step_values::Union{Nothing,AbstractMatrix} = nothing)
    data = design.spec.data
    dims = design.spec.dimensions
    K = length(data.category_levels)
    length(etas) == K || throw(ArgumentError(
        "eta vector has length $(length(etas)); expected $K"))
    size(loading_indices) ==
        (length(data.item_levels), dims) || throw(ArgumentError(
        "MGMFRM loading-index matrix has the wrong size"))

    person_offset = (data.person[row] - 1) * dims
    person_block = design.blocks[:person]
    item_index = data.item[row]
    ability_score = _param_zero(params)
    for dim in 1:dims
        loading_index = loading_indices[item_index, dim]
        iszero(loading_index) && continue
        ability_score += params[loading_index] *
            params[person_block[person_offset + dim]]
    end
    rater_index = data.rater[row]
    rater_value = params[design.blocks[:rater][rater_index]]
    item_value = params[design.blocks[:item][item_index]]
    rater_consistency =
        params[design.blocks[:rater_consistency][rater_index]]
    scale_value = 1.7 * rater_consistency
    location_value = ability_score - item_value - rater_value

    etas[1] = zero(scale_value * location_value)
    cumulative = zero(etas[1])
    for category_index in 2:K
        step_value = step_values === nothing ? _source_step_value(
            design,
            params,
            :item_steps,
            item_index,
            category_index,
        ) : step_values[category_index, item_index]
        cumulative += scale_value * (location_value - step_value)
        etas[category_index] = cumulative
    end
    return etas
end

function _mgmfrm_source_pointwise_loglikelihood(
        design::FacetDesign,
        params::AbstractVector;
        require_q_observation_coverage::Bool = true)
    _check_mgmfrm_source_fixture_design(
        design,
        "_mgmfrm_source_pointwise_loglikelihood";
        require_q_observation_coverage,
    )
    return _mgmfrm_source_pointwise_loglikelihood(
        design, params, _mgmfrm_source_loading_index_matrix(design))
end

# Batch consumers validate the design once and reuse its loading indices.
# Parameter length and constraints remain checked for every draw.
function _mgmfrm_source_pointwise_loglikelihood(
        design::FacetDesign, params::AbstractVector,
        loading_indices::AbstractMatrix{Int})
    _check_parameter_vector_length(design, params)
    _mgmfrm_source_fixture_constraints(design, params)
    data = design.spec.data
    K = length(data.category_levels)
    T = typeof(_param_zero(params) + 0.0)
    etas = Vector{T}(undef, K)
    out = Vector{T}(undef, data.n)
    # Reuse the same per-draw thresholds as the total-likelihood kernel.
    step_values = T[_source_step_value(design, params, :item_steps, item, category)
        for category in 1:K, item in eachindex(data.item_levels)]
    for row in 1:data.n
        _mgmfrm_source_linear_predictors!(
            etas,
            design,
            params,
            row,
            loading_indices,
            step_values,
        )
        out[row] = etas[data.category[row]] - _logsumexp(etas)
    end
    return out
end

function _mgmfrm_source_pointwise_loglikelihood_from_unconstrained(
        design::FacetDesign,
        raw_params::AbstractVector)
    params = _mgmfrm_source_constrained_params_from_unconstrained(design, raw_params)
    return _mgmfrm_source_pointwise_loglikelihood(design, params)
end

function _mgmfrm_source_loglikelihood_from_unconstrained(
        design::FacetDesign,
        raw_params::AbstractVector,
        blueprint::NamedTuple = _mgmfrm_source_unconstrained_blueprint(design))
    params = _mgmfrm_source_constrained_params_from_unconstrained(
        design,
        raw_params,
        blueprint,
    )
    return _mgmfrm_source_loglikelihood(design, params)
end

# Specialize the response loop on the transformed element type. Otherwise the
# Float64/AD transform union can cause dispatch and boxing for every response.
function _mgmfrm_source_loglikelihood(design::FacetDesign,
        params::AbstractVector{T}) where {T}
    data = design.spec.data
    K = length(data.category_levels)
    etas = Vector{T}(undef, K)
    loading_indices = _mgmfrm_source_loading_index_matrix(design)
    total = zero(T)
    # Item thresholds do not depend on the person or rater. Rebuild them once
    # per evaluation (including each AD chunk), never across parameter vectors.
    step_values = T[_source_step_value(design, params, :item_steps, item, category)
        for category in 1:K, item in eachindex(data.item_levels)]
    for row in 1:data.n
        _mgmfrm_source_linear_predictors!(
            etas,
            design,
            params,
            row,
            loading_indices,
            step_values,
        )
        total += etas[data.category[row]] - _logsumexp(etas)
    end
    return total
end

function _mgmfrm_source_fixture_values(design::FacetDesign, params::AbstractVector)
    _check_mgmfrm_source_fixture_design(design, "_mgmfrm_source_fixture_values")
    _check_parameter_vector_length(design, params)
    _mgmfrm_source_fixture_constraints(design, params)
    data = design.spec.data
    K = length(data.category_levels)
    T = typeof(_param_zero(params) + 0.0)
    etas = Vector{T}(undef, K)
    index_by_name = _parameter_index_map(design)
    loading_indices = _mgmfrm_source_loading_index_matrix(design)
    rows = NamedTuple[]
    for row in 1:data.n
        _mgmfrm_source_linear_predictors!(
            etas,
            design,
            params,
            row,
            loading_indices,
        )
        log_denominator = _logsumexp(etas)
        terms = _mgmfrm_source_row_terms(design, index_by_name, params, row)
        for category_index in eachindex(data.category_levels)
            components = _predictor_components(design, index_by_name, row, category_index)
            step_values = _source_step_values(
                design,
                params,
                :item_steps,
                data.item[row],
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
