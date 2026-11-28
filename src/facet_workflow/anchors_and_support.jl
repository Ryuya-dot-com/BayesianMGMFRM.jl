function _normalize_bias_terms(bias, report::ValidationReport)
    if isempty(bias) && !isempty(report.dff_counts)
        return sort(collect(keys(report.dff_counts)); by = string)
    end
    out = Tuple{Symbol,Symbol}[]
    for term in bias
        if term isa Tuple && length(term) == 2 && first(term) isa Symbol && last(term) isa Symbol
            push!(out, (first(term), last(term)))
        end
    end
    return out
end

function _anchor_symbol(anchor, keys::Tuple{Vararg{Symbol}})
    for key in keys
        haskey(anchor, key) && return anchor[key]
    end
    return nothing
end

function _normalize_anchor_type(anchor)
    declared = _anchor_symbol(anchor, (:anchor_type, :kind, :type))
    if declared === nothing
        return any(key -> haskey(anchor, key), (:scale, :sd, :prior_scale)) ?
            :soft_anchor : :hard_anchor
    end
    declared isa Symbol ||
        throw(ArgumentError("anchor type must be a Symbol when supplied"))
    declared in (:hard, :fixed, :hard_anchor) && return :hard_anchor
    declared in (:soft, :soft_anchor) && return :soft_anchor
    throw(ArgumentError("anchor type must be :hard or :soft"))
end

function _anchor_scale(anchor)
    scale = _anchor_symbol(anchor, (:scale, :sd, :prior_scale))
    scale === nothing && return missing
    scale isa Real && isfinite(scale) && scale > 0 ||
        throw(ArgumentError("soft anchors require a positive finite scale, sd, or prior_scale"))
    return Float64(scale)
end

function _normalize_anchors(anchors)
    out = NamedTuple[]
    for anchor in anchors
        anchor isa NamedTuple ||
            throw(ArgumentError("anchors must be named tuples"))
        haskey(anchor, :block) ||
            throw(ArgumentError("each anchor must include a :block field"))
        anchor.block isa Symbol ||
            throw(ArgumentError("anchor block must be a Symbol"))
        haskey(anchor, :value) ||
            throw(ArgumentError("each anchor must include a :value field"))
        anchor_type = _normalize_anchor_type(anchor)
        anchor_scale = _anchor_scale(anchor)
        if anchor_type === :soft_anchor && ismissing(anchor_scale)
            throw(ArgumentError("soft anchors require a positive scale, sd, or prior_scale"))
        end
        push!(out, merge(anchor, (;
            anchor_type,
            anchor_scale,
        )))
    end
    return out
end

function _stable_anchor_block(block::Symbol)
    block in (:rater, :rater_severity, :raters) && return :rater
    block in (:item, :item_difficulty, :items) && return :item
    return :unsupported
end

function _stable_hard_anchor_map(data::FacetData, anchors)
    fixed = Dict{Symbol,Dict{Int,Float64}}(
        :rater => Dict{Int,Float64}(),
        :item => Dict{Int,Float64}(),
    )
    for anchor in anchors
        anchor.anchor_type === :hard_anchor || return nothing
        ismissing(anchor.anchor_scale) || return nothing
        block = _stable_anchor_block(anchor.block)
        block in (:rater, :item) || return nothing
        target = _anchor_target(anchor)
        ismissing(target) && return nothing
        levels = block === :rater ? data.rater_levels : data.item_levels
        matches = findall(level -> isequal(level, target), levels)
        length(matches) == 1 || return nothing
        anchor.value isa Bool && return nothing
        anchor.value isa Real || return nothing
        value = try
            Float64(anchor.value)
        catch
            return nothing
        end
        isfinite(value) || return nothing
        underflowed = try
            iszero(value) && !iszero(anchor.value)
        catch
            true
        end
        underflowed && return nothing
        level_index = only(matches)
        haskey(fixed[block], level_index) && return nothing
        fixed[block][level_index] = value
    end
    return fixed
end

function _stable_hard_anchor_map(spec::FacetSpec)
    fixed = _stable_hard_anchor_map(spec.data, spec.anchors)
    fixed === nothing && throw(ArgumentError(
        "the stable MFRM hard-anchor map is invalid; inspect anchor_refit_plan(spec; require_provenance = false)",
    ))
    return fixed
end

function _stable_hard_anchor_map(design::FacetDesign)
    return _stable_hard_anchor_map(design.spec)
end

function _stable_anchor_level_indices(spec::FacetSpec, block::Symbol)
    fixed = _stable_hard_anchor_map(spec)
    return sort!(collect(keys(fixed[block])))
end

function _stable_free_facet_level_indices(spec::FacetSpec, block::Symbol)
    data = spec.data
    levels = block === :rater ? data.rater_levels :
        block === :item ? data.item_levels :
        throw(ArgumentError("stable facet block must be :rater or :item"))
    fixed = _stable_anchor_level_indices(spec, block)
    if isempty(fixed)
        return collect(2:length(levels))
    end
    fixed_set = Set(fixed)
    return [index for index in eachindex(levels) if index ∉ fixed_set]
end

function _stable_facet_parameter_index(
        design::FacetDesign,
        block::Symbol,
        level_index::Int)
    spec = design.spec
    isempty(spec.anchors) &&
        return _reference_parameter_index(design.blocks[block], level_index)
    levels = block === :rater ? spec.data.rater_levels : spec.data.item_levels
    target_level = levels[level_index]
    block_anchored = false
    free_position = level_index
    for anchor in spec.anchors
        _stable_anchor_block(anchor.block) === block || continue
        block_anchored = true
        target = _anchor_target(anchor)
        isequal(target, target_level) && return missing
        target_index = findfirst(level -> isequal(level, target), levels)
        target_index !== nothing && target_index < level_index &&
            (free_position -= 1)
    end
    block_anchored ||
        return _reference_parameter_index(design.blocks[block], level_index)
    return design.blocks[block][free_position]
end

function _stable_facet_fixed_value(
        design::FacetDesign,
        block::Symbol,
        level_index::Int)
    spec = design.spec
    isempty(spec.anchors) && return level_index == 1 ? 0.0 : missing
    levels = block === :rater ? spec.data.rater_levels : spec.data.item_levels
    target_level = levels[level_index]
    block_anchored = false
    for anchor in spec.anchors
        _stable_anchor_block(anchor.block) === block || continue
        block_anchored = true
        isequal(_anchor_target(anchor), target_level) &&
            return Float64(anchor.value)
    end
    !block_anchored && level_index == 1 && return 0.0
    return missing
end

function _stable_facet_value(
        design::FacetDesign,
        params::AbstractVector,
        block::Symbol,
        level_index::Int)
    isempty(design.spec.anchors) &&
        return _reference_value(params, design.blocks[block], level_index)
    parameter_index = _stable_facet_parameter_index(design, block, level_index)
    parameter_index === missing || return params[parameter_index]
    fixed_value = _stable_facet_fixed_value(design, block, level_index)
    ismissing(fixed_value) && throw(ArgumentError(
        "facet level $level_index in block :$block is neither free nor fixed",
    ))
    return _param_zero(params) + fixed_value
end

function _estimation_status(family::Symbol,
        dimensions::Int,
        discrimination::Symbol,
        q_matrix,
        anchors,
        data::FacetData)
    family === :mfrm &&
        dimensions == 1 &&
        discrimination === :none &&
        q_matrix === nothing &&
        _stable_hard_anchor_map(data, anchors) !== nothing &&
        return :fit_supported
    return :specified_only
end

function _guarded_generalized_next_gate(
        family::Symbol,
        option::Symbol,
        value)
    option === :thresholds && return :guarded_generalized_threshold_contract
    option === :anchors && return :generalized_anchor_likelihood_implementation
    option === :q_matrix && return :mgmfrm_fixed_q_validation
    option === :dff_effects && return family === :gmfrm ?
        :gmfrm_dff_estimand_validation_grid : :mgmfrm_dff_estimand_validation_grid
    option === :dimensions && return family === :gmfrm ?
        :mgmfrm_guarded_fit_validation_grid : :mgmfrm_guarded_fit_entrypoint
    option === :discrimination && return family === :gmfrm && value === :item ?
        :item_discrimination_promotion_decision :
        (family === :gmfrm ?
            :guarded_scalar_gmfrm_fit_entrypoint :
            :mgmfrm_generic_discrimination_validation)
    option === :estimation_status && return family === :gmfrm ?
        :guarded_scalar_gmfrm_manifest_review : :mgmfrm_guarded_manifest_review
    option === :family && return :guarded_generalized_fit_entrypoint
    return :guarded_generalized_capability_review
end

function _guarded_generalized_supported_surface(capability)
    dimensions = capability.maximum_dimensions === nothing ?
        ">=$(capability.minimum_dimensions)" :
        capability.minimum_dimensions == capability.maximum_dimensions ?
            string(capability.minimum_dimensions) :
            "$(capability.minimum_dimensions):$(capability.maximum_dimensions)"
    return (;
        family = capability.family,
        dimensions,
        thresholds = capability.threshold_regimes,
        discrimination = capability.spec_discrimination,
        q_matrix = capability.requires_fixed_q ? :fixed_confirmatory : :not_used,
        validation_bias_terms = (),
        anchors = (),
    )
end

function _guarded_generalized_unsupported_error(
        caller::AbstractString,
        family::Symbol,
        option::Symbol,
        value,
        reason::AbstractString;
        next_gate::Symbol = _guarded_generalized_next_gate(family, option, value))
    capability = _guarded_generalized_fit_capability(family)
    return ArgumentError(
        "$caller does not support $(option) = $(repr(value)). " *
        "Supported configuration: " *
        "$(repr(_guarded_generalized_supported_surface(capability))). " *
        reason,
    )
end

struct _GuardedGeneralizedSupportIssue{T}
    option::Symbol
    value::T
    reason::String
    next_gate::Symbol
end

function _guarded_generalized_support_issue(
        family::Symbol,
        option::Symbol,
        value,
        reason::AbstractString)
    return _GuardedGeneralizedSupportIssue(
        option,
        value,
        String(reason),
        _guarded_generalized_next_gate(family, option, value),
    )
end

function _guarded_generalized_spec_status(
        spec::FacetSpec;
        require_q_observation_coverage::Bool = true)
    capability = _guarded_generalized_fit_capability(spec.family)
    issue(option, value, reason) = (;
        supported = false,
        capability,
        issue = _guarded_generalized_support_issue(
            spec.family,
            option,
            value,
            reason,
        ),
    )

    if spec.dimensions < capability.minimum_dimensions ||
            (capability.maximum_dimensions !== nothing &&
                spec.dimensions > capability.maximum_dimensions)
        return issue(
            :dimensions,
            spec.dimensions,
            "the guarded surface has a family-specific dimensionality contract",
        )
    end
    if !(spec.thresholds in capability.threshold_regimes)
        return issue(
            :thresholds,
            spec.thresholds,
            "the compiled generalized kernel uses $(capability.kernel_threshold_block); " *
            "unsupported threshold labels are not silently reinterpreted",
        )
    end
    if !(spec.discrimination in capability.spec_discrimination)
        return issue(
            :discrimination,
            spec.discrimination,
            "the guarded surface requires its family-specific generic discrimination selector",
        )
    end
    if capability.requires_fixed_q
        spec.q_matrix === nothing && return issue(
            :q_matrix,
            nothing,
            "the guarded MGMFRM surface requires a fixed confirmatory q_matrix",
        )
        q_validation = q_matrix_validation(spec)
        q_validation_passed = require_q_observation_coverage ?
            q_validation.passed :
            _q_matrix_guarded_structure_passed(q_validation)
        if !q_validation_passed
            return issue(
                :q_matrix,
                spec.q_matrix,
                "the fixed q_matrix no longer passes confirmatory " *
                (require_q_observation_coverage ? "validation; " :
                    "structural validation; ") *
                "mutable specification inputs are revalidated before numerical execution",
            )
        end
    end
    if !capability.allows_validation_bias_terms &&
            !isempty(spec.validation_bias_terms)
        return issue(
            :dff_effects,
            spec.validation_bias_terms,
            "DFF/bias terms are validation and reporting rows only; they are not fitted model effects",
        )
    end
    if !capability.allows_anchors && !isempty(spec.anchors)
        return issue(
            :anchors,
            spec.anchors,
            "declared anchors are not yet applied by the generalized likelihood or raw-coordinate transform",
        )
    end
    if spec.estimation_status !== :specified_only
        return issue(
            :estimation_status,
            spec.estimation_status,
            "guarded generalized fitting expects the specified-only manifest path",
        )
    end
    return (; supported = true, capability, issue = nothing)
end

function _check_guarded_generalized_spec(
        spec::FacetSpec,
        caller::AbstractString;
        require_q_observation_coverage::Bool = true)
    status = _guarded_generalized_spec_status(
        spec;
        require_q_observation_coverage,
    )
    if !status.supported
        issue = status.issue
        throw(_guarded_generalized_unsupported_error(
            caller,
            spec.family,
            issue.option,
            issue.value,
            issue.reason;
            next_gate = issue.next_gate,
        ))
    end
    return status.capability
end

function _experimental_generalized_fit_supported(spec::FacetSpec)
    spec.family in (:gmfrm, :mgmfrm) || return false
    return _guarded_generalized_spec_status(spec).supported
end

function _spec_scope(family::Symbol, status::Symbol)
    family === :mfrm && status === :fit_supported && return :minimal_mfrm_rsm_pcm
    family === :mfrm && return :planned_mfrm_variant
    family === :gmfrm && return :planned_generalized_mfrm
    family === :mgmfrm && return :planned_multidimensional_gmfrm
    return :unknown
end

_spec_scope(spec::FacetSpec) = _is_mfrm_fixed_q(spec) ? :fixed_coefficient_multidimensional_mfrm :
    _spec_scope(spec.family, spec.estimation_status)
