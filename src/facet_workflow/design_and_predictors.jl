function _push_block!(names::Vector{String}, blocks::Dict{Symbol,UnitRange{Int}}, block::Symbol, labels, prefix::String)
    start = length(names) + 1
    for label in labels
        push!(names, prefix * "[" * string(label) * "]")
    end
    blocks[block] = start:length(names)
    return nothing
end

function _push_named_block!(names::Vector{String},
        blocks::Dict{Symbol,UnitRange{Int}},
        block::Symbol,
        parameter_names)
    start = length(names) + 1
    append!(names, parameter_names)
    blocks[block] = start:length(names)
    return nothing
end

function _ensure_minimal_design_supported(spec::FacetSpec)
    _is_mfrm_fixed_q(spec) && throw(ArgumentError("multidimensional MFRM design inspection requires getdesign(spec; preview = true); estimate with BayesianMGMFRM.Experimental.fit(spec)"))
    spec.estimation_status === :fit_supported ||
        throw(ArgumentError(
            "getdesign currently supports only the minimal fit-supported MFRM/RSM/PCM specification; " *
            "this spec has family = :$(spec.family), dimensions = $(spec.dimensions), " *
            "discrimination = :$(spec.discrimination), estimation_status = :$(spec.estimation_status). " *
            "Use model_manifest or constraint_table to inspect specified-only GMFRM/MGMFRM configurations.",
        ))
    return nothing
end

function _threshold_parameter_names(spec::FacetSpec)
    data = spec.data
    names = String[]
    free_steps = max(length(data.category_levels) - 2, 0)
    if spec.thresholds === :rating_scale
        for step in 1:free_steps
            push!(names, "step[$step]")
        end
    else
        for item in data.item_levels, step in 1:free_steps
            push!(names, "step[item=$(item),$step]")
        end
    end
    return names
end

function _minimal_design(spec::FacetSpec)
    _ensure_minimal_design_supported(spec)
    data = spec.data
    names = String[]
    blocks = Dict{Symbol,UnitRange{Int}}()
    _push_block!(names, blocks, :person, data.person_levels, "person")
    rater_free = _stable_free_facet_level_indices(spec, :rater)
    item_free = _stable_free_facet_level_indices(spec, :item)
    _push_block!(names, blocks, :rater, data.rater_levels[rater_free], "rater")
    _push_block!(names, blocks, :item, data.item_levels[item_free], "item")
    _push_named_block!(names, blocks, :thresholds, _threshold_parameter_names(spec))

    identification = Dict{Symbol,Symbol}(
        :person => :free,
        :rater => isempty(_stable_anchor_level_indices(spec, :rater)) ?
            :reference_first : :hard_anchor,
        :item => isempty(_stable_anchor_level_indices(spec, :item)) ?
            :reference_first : :hard_anchor,
        :thresholds => :sum_to_zero,
    )
    return FacetDesign(spec, names, blocks, identification)
end

function _person_parameter_names(spec::FacetSpec)
    spec.dimensions == 1 &&
        return ["person[$(person)]" for person in spec.data.person_levels]
    return [
        "person[$(person),$(spec.dimension_labels[dim])]"
        for person in spec.data.person_levels
        for dim in 1:spec.dimensions
    ]
end

function _item_discrimination_parameter_names(spec::FacetSpec)
    spec.family === :gmfrm || return String[]
    return ["item_discrimination[item=$(item)]" for item in spec.data.item_levels]
end

function _rater_consistency_parameter_names(spec::FacetSpec)
    spec.family in (:gmfrm, :mgmfrm) || return String[]
    return ["rater_consistency[rater=$(rater)]" for rater in spec.data.rater_levels]
end

function _item_dimension_discrimination_parameter_names(spec::FacetSpec)
    spec.family === :mgmfrm || return String[]
    q = spec.q_matrix
    q === nothing && return String[]
    names = String[]
    for item_index in axes(q, 1), dim in axes(q, 2)
        q[item_index, dim] || continue
        item = spec.data.item_levels[item_index]
        push!(names,
            "item_dimension_discrimination[item=$(item),$(spec.dimension_labels[dim])]")
    end
    return names
end

function _source_step_free_count(spec::FacetSpec)
    return max(length(spec.data.category_levels) - 2, 0)
end

function _rater_step_parameter_names(spec::FacetSpec)
    spec.family === :gmfrm || return String[]
    names = String[]
    free_steps = _source_step_free_count(spec)
    for rater in spec.data.rater_levels, offset in 1:free_steps
        m = offset + 1
        push!(names, "rater_step[rater=$(rater),m=$(m)]")
    end
    return names
end

function _item_step_parameter_names(spec::FacetSpec)
    spec.family === :mgmfrm || return String[]
    names = String[]
    free_steps = _source_step_free_count(spec)
    for item in spec.data.item_levels, offset in 1:free_steps
        m = offset + 1
        push!(names, "item_step[item=$(item),m=$(m)]")
    end
    return names
end

function _discrimination_parameter_names(spec::FacetSpec)
    spec.discrimination === :none && return String[]
    spec.discrimination === :global && return ["discrimination[global]"]
    spec.discrimination === :rater &&
        return ["discrimination[rater=$(rater)]" for rater in spec.data.rater_levels]
    spec.discrimination === :item &&
        return ["discrimination[item=$(item)]" for item in spec.data.item_levels]
    if spec.discrimination === :rater_item
        return [
            "discrimination[rater=$(rater),item=$(item)]"
            for rater in spec.data.rater_levels
            for item in spec.data.item_levels
        ]
    end
    throw(ArgumentError("unsupported discrimination structure :$(spec.discrimination)"))
end

function _preview_design(spec::FacetSpec)
    spec.estimation_status === :specified_only ||
        throw(ArgumentError("preview design is only needed for specified-only configurations"))
    _is_mfrm_fixed_q(spec) && return _mfrm_fixed_q_design(spec)
    data = spec.data
    names = String[]
    blocks = Dict{Symbol,UnitRange{Int}}()
    _push_named_block!(names, blocks, :person, _person_parameter_names(spec))
    if spec.family === :gmfrm
        _push_block!(names, blocks, :rater, data.rater_levels, "rater")
        _push_block!(names, blocks, :item, data.item_levels, "item")
        _push_named_block!(names, blocks, :item_discrimination, _item_discrimination_parameter_names(spec))
        _push_named_block!(names, blocks, :rater_consistency, _rater_consistency_parameter_names(spec))
        _push_named_block!(names, blocks, :rater_steps, _rater_step_parameter_names(spec))
    elseif spec.family === :mgmfrm
        _push_block!(names, blocks, :rater, data.rater_levels, "rater")
        _push_block!(names, blocks, :item, data.item_levels, "item")
        _push_named_block!(names, blocks, :item_dimension_discrimination, _item_dimension_discrimination_parameter_names(spec))
        _push_named_block!(names, blocks, :rater_consistency, _rater_consistency_parameter_names(spec))
        _push_named_block!(names, blocks, :item_steps, _item_step_parameter_names(spec))
    else
        _push_block!(names, blocks, :rater, data.rater_levels[2:end], "rater")
        _push_block!(names, blocks, :item, data.item_levels[2:end], "item")
        _push_named_block!(names, blocks, :thresholds, _threshold_parameter_names(spec))
        if spec.discrimination !== :none
            _push_named_block!(names, blocks, :discrimination, _discrimination_parameter_names(spec))
        end
    end
    identification = Dict{Symbol,Symbol}(
        :person => spec.dimensions == 1 ? :free : :multidimensional_location_gauge,
        :rater => spec.family === :mgmfrm ? :sum_to_zero :
            (spec.family === :gmfrm ? :free_given_item_sum_to_zero : :reference_first),
        :item => spec.family === :gmfrm ? :sum_to_zero :
            (spec.family === :mgmfrm ? :free_given_rater_sum_to_zero : :reference_first),
    )
    if spec.family === :gmfrm
        identification[:item_discrimination] = :geometric_mean_one
        identification[:rater_consistency] = :positive
        identification[:rater_steps] = :first_step_zero_sum_to_zero
    elseif spec.family === :mgmfrm
        identification[:item_dimension_discrimination] = :confirmatory_q_mask
        identification[:rater_consistency] = :geometric_mean_one
        identification[:item_steps] = :first_step_zero_sum_to_zero
    else
        identification[:thresholds] = :sum_to_zero
        spec.discrimination !== :none && (identification[:discrimination] = :positive_with_scale_constraint)
    end
    return FacetDesign(spec, names, blocks, identification)
end

"""
    getdesign(spec::FacetSpec; preview = false)

Compile the identified additive MFRM/RSM/PCM parameter names, block ranges,
and constraints. This inspection step is optional: `fit(spec)` compiles the
stable specification internally. Without anchors,
the first rater and first item levels are fixed to zero. An exact individual
hard anchor replaces that default gauge for its block: anchored coordinates are
fixed at their declared values and omitted from the sampled parameter vector.
Rating-scale and partial-credit threshold steps use a sum-to-zero constraint.

Specified-only GMFRM/MGMFRM configurations are rejected by this stable compiler
route so fitting code cannot silently use an unsupported likelihood. Set
`preview = true` to compile an inspectable parameter blueprint. The documented
partial-credit scalar GMFRM and fixed-Q, identity-correlation MGMFRM subsets are
fit-ready only through [`BayesianMGMFRM.Experimental.fit`](@ref); other preview
configurations remain inspection-only.
"""
function getdesign(spec::FacetSpec; preview::Bool = false)
    _require_current_facet_spec(spec, "getdesign")
    if preview
        spec.estimation_status === :fit_supported && return _minimal_design(spec)
        return _preview_design(spec)
    end
    return _minimal_design(spec)
end

function Base.show(io::IO, design::FacetDesign)
    print(io, "FacetDesign(", length(design.parameter_names), " parameters, thresholds = :",
        design.spec.thresholds, ")")
end

"""
    constraint_table(spec_or_design)

Return machine-readable identification and transform declarations for a
`FacetSpec` or `FacetDesign`. For specified-only GMFRM/MGMFRM configurations,
rows explain the declared constraint/gauge. The documented partial-credit
scalar GMFRM and fixed-Q, identity-correlation MGMFRM subsets are executable
only through [`BayesianMGMFRM.Experimental.fit`](@ref); all other generalized
configurations remain inspection-only. For a compiled `FacetDesign`,
implemented rows also include parameter ranges and names.
"""
function constraint_table(spec::FacetSpec)
    return copy(spec.constraints)
end

function constraint_table(design::FacetDesign)
    base_rows = constraint_table(design.spec)
    rows = NamedTuple[]
    for row in base_rows
        if haskey(row, :anchor_target)
            push!(rows, merge(row, (;
                first_parameter = missing,
                last_parameter = missing,
                n_parameters = 0,
                parameter_names = String[],
                is_fixed = row.status === :implemented,
            )))
        elseif haskey(design.blocks, row.block)
            range = design.blocks[row.block]
            indices = collect(range)
            push!(rows, merge(row, (;
                first_parameter = isempty(indices) ? missing : first(indices),
                last_parameter = isempty(indices) ? missing : last(indices),
                n_parameters = length(indices),
                parameter_names = isempty(indices) ? String[] : copy(design.parameter_names[indices]),
            )))
        else
            push!(rows, merge(row, (;
                first_parameter = missing,
                last_parameter = missing,
                n_parameters = 0,
                parameter_names = String[],
            )))
        end
    end
    return rows
end

function _identification_components(row)
    constraint = row.constraint
    components = Symbol[]
    constraint === :reference_first && push!(components, :reference)
    constraint === :sum_to_zero && push!(components, :sum_to_zero)
    constraint === :geometric_mean_one && push!(components, :geometric_mean_one)
    constraint === :fixed_mask && append!(components, (:fixed, :multidimensional_gauge))
    constraint === :hard_anchor && append!(components, (:hard_anchor, :fixed))
    constraint === :soft_anchor && push!(components, :soft_anchor)
    constraint === :free_with_hard_anchors &&
        append!(components, (:free, :hard_anchor))
    if constraint === :first_step_zero_sum_to_zero
        append!(components, (:fixed, :sum_to_zero))
    end
    if constraint in (:standard_normal_by_dimension, :confirmatory_q_mask,
            :multidimensional_location_gauge)
        push!(components, :multidimensional_gauge)
    end
    constraint === :ability_distribution_location_scale &&
        push!(components, :distribution_location_scale)
    constraint === :positive && push!(components, :positive)
    constraint === :free && push!(components, :free)
    isempty(components) && push!(components, constraint)
    return Tuple(unique(components))
end

function _identification_rule(row)
    components = _identification_components(row)
    return first(components)
end

function _identification_declaration_row(spec::FacetSpec, row)
    base = (;
        block = row.block,
        rule = _identification_rule(row),
        components = _identification_components(row),
        constraint = row.constraint,
        transform = row.transform,
        status = row.status,
        family = spec.family,
        dimensions = spec.dimensions,
        estimation_status = spec.estimation_status,
        note = row.note,
    )
    if haskey(row, :anchor_value)
        return merge(base, (;
            anchor_type = row.constraint,
            anchor_target = row.anchor_target,
            anchor_value = row.anchor_value,
            anchor_scale = row.anchor_scale,
            is_fixed = row.status === :implemented,
        ))
    end
    return base
end

function _attach_design_parameter_metadata(row, design::FacetDesign)
    if haskey(row, :anchor_target)
        return merge(row, (;
            first_parameter = missing,
            last_parameter = missing,
            n_parameters = 0,
            parameter_names = String[],
        ))
    elseif haskey(design.blocks, row.block)
        range = design.blocks[row.block]
        indices = collect(range)
        return merge(row, (;
            first_parameter = isempty(indices) ? missing : first(indices),
            last_parameter = isempty(indices) ? missing : last(indices),
            n_parameters = length(indices),
            parameter_names = isempty(indices) ? String[] : copy(design.parameter_names[indices]),
        ))
    end
    return merge(row, (;
        first_parameter = missing,
        last_parameter = missing,
        n_parameters = 0,
        parameter_names = String[],
    ))
end

"""
    identification_declarations(spec_or_design)

Return machine-readable identification declarations for a `FacetSpec` or
`FacetDesign`. Rows normalize constraint-table entries into reviewable
components such as `:sum_to_zero`, `:reference`, `:fixed`,
`:geometric_mean_one`, `:hard_anchor`, `:soft_anchor`, and
`:multidimensional_gauge`.

For a compiled `FacetDesign`, rows also include parameter ranges and names when
the declaration maps to an explicit parameter block.
"""
function identification_declarations(spec::FacetSpec)
    rows = NamedTuple[_identification_declaration_row(spec, row) for row in constraint_table(spec)]
    if spec.family === :mfrm && spec.dimensions == 1 && isempty(spec.anchors)
        push!(rows, (;
            block = :global_location_origin,
            rule = :over_anchored_reference_prior_risk,
            components = (:over_anchored_reference_prior_risk,),
            constraint = :over_anchored_reference_prior_risk,
            transform = :identity,
            status = :warning,
            family = spec.family,
            dimensions = spec.dimensions,
            estimation_status = spec.estimation_status,
            note = "Unanchored FacetSpec fixes first-level facet references to zero (rater[1]=0, item[1]=0) while MFRMPrior centers person abilities on zero with fixed SD; under strong ceiling or floor targeting this over-anchoring can distort or invert unanchored facet contrasts. Prefer mfrm_spec(...; prior = :default) for label-permutation-invariant isometric centering with estimated population mean and SD.",
        ))
    end
    return rows
end

function identification_declarations(design::FacetDesign)
    rows = identification_declarations(design.spec)
    return [_attach_design_parameter_metadata(row, design) for row in rows]
end

function _parameter_index_map(design::FacetDesign)
    return Dict(name => index for (index, name) in pairs(design.parameter_names))
end

function _parameter_names(design::FacetDesign, indices::AbstractVector{Int})
    return [design.parameter_names[index] for index in indices]
end

function _reference_parameter_index(block::UnitRange{Int}, level_index::Int)
    level_index == 1 && return missing
    return block[level_index - 1]
end

function _facet_parameter_index(block::UnitRange{Int}, level_index::Int, nlevels::Int)
    length(block) == nlevels && return block[level_index]
    return _reference_parameter_index(block, level_index)
end

function _reference_parameter_name(design::FacetDesign, index)
    index === missing && return missing
    return design.parameter_names[index]
end

function _person_parameter_indices(design::FacetDesign, person_index::Int)
    block = design.blocks[:person]
    dimensions = design.spec.dimensions
    dimensions == 1 && return [block[person_index]]
    offset = (person_index - 1) * dimensions
    return [block[offset + dim] for dim in 1:dimensions]
end

function _threshold_step_metadata(design::FacetDesign, item_index::Int, step::Int)
    data = design.spec.data
    K = length(data.category_levels)
    nsteps = max(K - 1, 0)
    1 <= step <= nsteps ||
        throw(ArgumentError("threshold step $step is outside 1:$nsteps"))
    free_steps = max(nsteps - 1, 0)
    step_range = design.blocks[:thresholds]
    is_free = step <= free_steps
    parameter_index = if is_free
        design.spec.thresholds === :rating_scale ?
            step_range[step] :
            step_range[(item_index - 1) * free_steps + step]
    else
        missing
    end
    parameter_name = is_free ? design.parameter_names[parameter_index] : missing
    status = is_free ? :free : (nsteps == 1 ? :fixed_zero : :sum_to_zero_derived)
    return (;
        step,
        from_category = data.category_levels[step],
        to_category = data.category_levels[step + 1],
        parameter_index,
        parameter_name,
        status,
        block = :thresholds,
    )
end

function _threshold_path_metadata(design::FacetDesign, item_index::Int, category_index::Int)
    category_index <= 1 && return NamedTuple[]
    return [_threshold_step_metadata(design, item_index, step) for step in 1:(category_index - 1)]
end

function _source_step_metadata(design::FacetDesign, block::Symbol, level_index::Int, m::Int)
    data = design.spec.data
    K = length(data.category_levels)
    2 <= m <= K ||
        throw(ArgumentError("source-model step m = $m is outside 2:$K"))
    free_steps = max(K - 2, 0)
    is_free = m <= K - 1
    block_range = design.blocks[block]
    parameter_index = if is_free && free_steps > 0
        block_range[(level_index - 1) * free_steps + (m - 1)]
    else
        missing
    end
    parameter_name = is_free && free_steps > 0 ? design.parameter_names[parameter_index] : missing
    status = is_free && free_steps > 0 ? :free : (K == 2 ? :fixed_zero : :sum_to_zero_derived)
    return (;
        step = m - 1,
        source_step = m,
        from_category = data.category_levels[m - 1],
        to_category = data.category_levels[m],
        parameter_index,
        parameter_name,
        status,
        block,
    )
end

function _source_step_path_metadata(design::FacetDesign,
        item_index::Int,
        rater_index::Int,
        category_index::Int)
    category_index <= 1 && return NamedTuple[]
    if haskey(design.blocks, :rater_steps)
        return [_source_step_metadata(design, :rater_steps, rater_index, m) for m in 2:category_index]
    elseif haskey(design.blocks, :item_steps)
        return [_source_step_metadata(design, :item_steps, item_index, m) for m in 2:category_index]
    end
    return _threshold_path_metadata(design, item_index, category_index)
end

function _loading_dimensions(spec::FacetSpec, item_index::Int)
    spec.family === :mgmfrm || return Int[]
    q = spec.q_matrix
    q === nothing && return Int[]
    return [dim for dim in 1:spec.dimensions if q[item_index, dim]]
end

function _loading_parameter_indices(design::FacetDesign, index_by_name, item_index::Int)
    haskey(design.blocks, :item_dimension_discrimination) || return Int[]
    spec = design.spec
    indices = Int[]
    item = spec.data.item_levels[item_index]
    for dim in _loading_dimensions(spec, item_index)
        name = "item_dimension_discrimination[item=$(item),$(spec.dimension_labels[dim])]"
        push!(indices, index_by_name[name])
    end
    return indices
end

function _mgmfrm_source_loading_index_matrix(design::FacetDesign)
    spec = design.spec
    spec.family === :mgmfrm || throw(ArgumentError(
        "MGMFRM loading indices require an MGMFRM design"))
    q = spec.q_matrix
    q === nothing && throw(ArgumentError(
        "MGMFRM loading indices require a fixed Q-matrix"))
    indices = zeros(Int, size(q))
    loading_block = design.blocks[:item_dimension_discrimination]
    loading_offset = 0
    for item_index in axes(q, 1), dim in axes(q, 2)
        q[item_index, dim] || continue
        loading_offset += 1
        indices[item_index, dim] = loading_block[loading_offset]
    end
    loading_offset == length(loading_block) || throw(ArgumentError(
        "MGMFRM Q-mask and loading block have inconsistent sizes"))
    return indices
end

function _item_discrimination_parameter_index(design::FacetDesign, item_index::Int)
    haskey(design.blocks, :item_discrimination) || return missing
    return design.blocks[:item_discrimination][item_index]
end

function _rater_consistency_parameter_index(design::FacetDesign, rater_index::Int)
    haskey(design.blocks, :rater_consistency) || return missing
    return design.blocks[:rater_consistency][rater_index]
end

function _discrimination_parameter_indices(design::FacetDesign, index_by_name, rater_index::Int, item_index::Int)
    haskey(design.blocks, :discrimination) || return Int[]
    spec = design.spec
    spec.discrimination === :global &&
        return [index_by_name["discrimination[global]"]]
    if spec.discrimination === :rater
        rater = spec.data.rater_levels[rater_index]
        return [index_by_name["discrimination[rater=$(rater)]"]]
    elseif spec.discrimination === :item
        item = spec.data.item_levels[item_index]
        return [index_by_name["discrimination[item=$(item)]"]]
    elseif spec.discrimination === :rater_item
        rater = spec.data.rater_levels[rater_index]
        item = spec.data.item_levels[item_index]
        return [index_by_name["discrimination[rater=$(rater),item=$(item)]"]]
    end
    return Int[]
end

function _predictor_kernel(design::FacetDesign)
    design.spec.family === :gmfrm && return :gmfrm_source_aligned
    design.spec.family === :mgmfrm && return :mgmfrm_source_aligned
    return :mfrm_additive
end

function _predictor_components(design::FacetDesign,
        index_by_name,
        row::Int,
        category_index::Int)
    _is_mfrm_fixed_q(design.spec) && throw(ArgumentError(
        "row-level predictor inspection is not yet connected to multidimensional MFRM; use model_manifest and constraint_table"))
    data = design.spec.data
    person_indices = _person_parameter_indices(design, data.person[row])
    stable_mfrm = design.spec.family === :mfrm &&
        design.spec.estimation_status === :fit_supported
    rater_parameter_index = stable_mfrm ?
        _stable_facet_parameter_index(design, :rater, data.rater[row]) :
        _facet_parameter_index(design.blocks[:rater], data.rater[row], length(data.rater_levels))
    item_parameter_index = stable_mfrm ?
        _stable_facet_parameter_index(design, :item, data.item[row]) :
        _facet_parameter_index(design.blocks[:item], data.item[row], length(data.item_levels))
    threshold_path = _source_step_path_metadata(design, data.item[row], data.rater[row], category_index)
    item_discrimination_index = _item_discrimination_parameter_index(design, data.item[row])
    rater_consistency_index = _rater_consistency_parameter_index(design, data.rater[row])
    item_dimension_indices = _loading_parameter_indices(design, index_by_name, data.item[row])
    discrimination_indices = _discrimination_parameter_indices(
        design,
        index_by_name,
        data.rater[row],
        data.item[row],
    )
    return (;
        row,
        category_index,
        category = data.category_levels[category_index],
        observed = category_index == data.category[row],
        score = data.score[row],
        kernel = _predictor_kernel(design),
        location_multiplier = category_index - 1,
        person_index = data.person[row],
        person = data.person_levels[data.person[row]],
        person_parameter_indices = person_indices,
        person_parameter_names = _parameter_names(design, person_indices),
        rater_index = data.rater[row],
        rater = data.rater_levels[data.rater[row]],
        rater_parameter_index,
        rater_parameter_name = _reference_parameter_name(design, rater_parameter_index),
        rater_parameter_status = stable_mfrm &&
            rater_parameter_index === missing ?
            (ismissing(_stable_facet_fixed_value(design, :rater, data.rater[row])) ?
                :unmapped :
                (haskey(_stable_hard_anchor_map(design)[:rater], data.rater[row]) ?
                    :hard_anchor : :reference_zero)) : :estimated,
        rater_fixed_value = stable_mfrm &&
            rater_parameter_index === missing ?
            _stable_facet_fixed_value(design, :rater, data.rater[row]) : missing,
        item_index = data.item[row],
        item = data.item_levels[data.item[row]],
        item_parameter_index,
        item_parameter_name = _reference_parameter_name(design, item_parameter_index),
        item_parameter_status = stable_mfrm &&
            item_parameter_index === missing ?
            (ismissing(_stable_facet_fixed_value(design, :item, data.item[row])) ?
                :unmapped :
                (haskey(_stable_hard_anchor_map(design)[:item], data.item[row]) ?
                    :hard_anchor : :reference_zero)) : :estimated,
        item_fixed_value = stable_mfrm &&
            item_parameter_index === missing ?
            _stable_facet_fixed_value(design, :item, data.item[row]) : missing,
        item_discrimination_parameter_index = item_discrimination_index,
        item_discrimination_parameter_name = _reference_parameter_name(design, item_discrimination_index),
        rater_consistency_parameter_index = rater_consistency_index,
        rater_consistency_parameter_name = _reference_parameter_name(design, rater_consistency_index),
        item_dimension_discrimination_parameter_indices = item_dimension_indices,
        item_dimension_discrimination_parameter_names = _parameter_names(design, item_dimension_indices),
        active_dimensions = _loading_dimensions(design.spec, data.item[row]),
        step_path = threshold_path,
        step_parameter_indices = [step.parameter_index for step in threshold_path],
        step_parameter_names = [step.parameter_name for step in threshold_path],
        step_statuses = [step.status for step in threshold_path],
        step_blocks = [step.block for step in threshold_path],
        discrimination_parameter_indices = discrimination_indices,
        discrimination_parameter_names = _parameter_names(design, discrimination_indices),
    )
end

function _check_fit_supported_mfrm(design::FacetDesign, caller::AbstractString)
    _require_canonical_design(design, caller)
    design.spec.family === :mfrm && design.spec.estimation_status === :fit_supported ||
        throw(ArgumentError("$caller is currently implemented only for the fit-supported minimal MFRM/RSM/PCM design"))
    return nothing
end

function _check_parameter_vector_length(design::FacetDesign, params::AbstractVector)
    expected = length(design.parameter_names)
    length(params) == expected ||
        throw(ArgumentError("parameter vector has length $(length(params)); expected $expected"))
    return nothing
end

function _row_location(design::FacetDesign, params::AbstractVector, row::Int)
    data = design.spec.data
    person_block = design.blocks[:person]
    person_value = params[person_block[data.person[row]]]
    rater_value = _stable_facet_value(design, params, :rater, data.rater[row])
    item_value = _stable_facet_value(design, params, :item, data.item[row])
    return (;
        person_value,
        rater_value,
        item_value,
        location_value = person_value - rater_value - item_value,
    )
end

function _step_values(design::FacetDesign, params::AbstractVector, item::Int, category_index::Int)
    category_index <= 1 && return typeof(_param_zero(params) + 0.0)[]
    return [_threshold_step(design, params, item, step) for step in 1:(category_index - 1)]
end

function _linear_predictor_value(design::FacetDesign,
        params::AbstractVector,
        row::Int,
        category_index::Int)
    data = design.spec.data
    location = _row_location(design, params, row).location_value
    step_sum = _param_zero(params)
    for step in 1:(category_index - 1)
        step_sum += _threshold_step(design, params, data.item[row], step)
    end
    return (category_index - 1) * location - step_sum
end

function _linear_predictors!(etas::AbstractVector,
        design::FacetDesign,
        params::AbstractVector,
        row::Int)
    length(etas) == length(design.spec.data.category_levels) ||
        throw(ArgumentError("eta vector has length $(length(etas)); expected $(length(design.spec.data.category_levels))"))
    data = design.spec.data
    location = _row_location(design, params, row).location_value
    step_sum = _param_zero(params)
    for category_index in eachindex(etas)
        if category_index > 1
            step_sum += _threshold_step(design, params, data.item[row], category_index - 1)
        end
        etas[category_index] = (category_index - 1) * location - step_sum
    end
    return etas
end

"""
    linear_predictor_table(spec_or_design; preview = false)

Return one row per observed rating and response category describing the
source-level linear-predictor components used by the current design compiler.
Rows include the category-specific location multiplier, facet parameter
indexes, source-step path, and generalized item/rater blocks when a
specified-only GMFRM/MGMFRM design is compiled with `preview = true`.

The table is a compiler-inspection artifact for checking denominator terms and
source-equation alignment. It does not make specified-only GMFRM/MGMFRM
likelihoods fit-ready.
"""
function linear_predictor_table(spec::FacetSpec; preview::Bool = false)
    return linear_predictor_table(getdesign(spec; preview))
end

function linear_predictor_table(design::FacetDesign; preview::Bool = false)
    preview &&
        throw(ArgumentError("preview is only a FacetSpec compilation option; pass linear_predictor_table(spec; preview = true) for specified-only specs"))
    data = design.spec.data
    index_by_name = _parameter_index_map(design)
    rows = NamedTuple[]
    for row in 1:data.n, category_index in eachindex(data.category_levels)
        push!(rows, _predictor_components(design, index_by_name, row, category_index))
    end
    return rows
end

"""
    linear_predictor_values(spec_or_design, params; preview = false)

Return one row per observed rating and response category with numeric
linear-predictor values for the fit-supported minimal MFRM/RSM/PCM design.
Rows include the same compiler metadata as [`linear_predictor_table`](@ref),
plus identified person/rater/item values, the additive location value,
threshold-step values, their sum, the category score `eta`, the row log
denominator, and the category log probability.

Numeric values are deliberately not implemented for specified-only
GMFRM/MGMFRM previews. The limited
`BayesianMGMFRM.Experimental.fit(spec)` entrypoint performs its own guarded
generalized evaluation, but it does not extend this stable compiler-inspection
helper to generalized parameter vectors.
"""
function linear_predictor_values(spec::FacetSpec, params::AbstractVector; preview::Bool = false)
    return linear_predictor_values(getdesign(spec; preview), params)
end

function linear_predictor_values(design::FacetDesign,
        params::AbstractVector;
        preview::Bool = false)
    preview &&
        throw(ArgumentError("preview is only a FacetSpec compilation option; pass linear_predictor_values(spec, params; preview = true) for specified-only specs"))
    _check_fit_supported_mfrm(design, "linear_predictor_values")
    _check_parameter_vector_length(design, params)
    data = design.spec.data
    K = length(data.category_levels)
    T = typeof(_param_zero(params) + 0.0)
    etas = Vector{T}(undef, K)
    index_by_name = _parameter_index_map(design)
    rows = NamedTuple[]
    for row in 1:data.n
        _linear_predictors!(etas, design, params, row)
        log_denominator = _logsumexp(etas)
        location = _row_location(design, params, row)
        for category_index in eachindex(data.category_levels)
            components = _predictor_components(design, index_by_name, row, category_index)
            step_values = _step_values(design, params, data.item[row], category_index)
            step_sum = sum(step_values; init = _param_zero(params))
            eta = etas[category_index]
            push!(rows, merge(components, (;
                person_value = location.person_value,
                rater_value = location.rater_value,
                item_value = location.item_value,
                location_value = location.location_value,
                step_values,
                step_sum,
                eta,
                log_denominator,
                log_probability = eta - log_denominator,
            )))
        end
    end
    return rows
end
