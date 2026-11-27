function _check_family(family::Symbol)
    family in (:mfrm, :gmfrm, :mgmfrm) ||
        throw(ArgumentError("family must be :mfrm, :gmfrm, or :mgmfrm"))
    return family
end

function _default_dimension_labels(dimensions::Int)
    return ["dim=$(dim)" for dim in 1:dimensions]
end

function _normalize_dimension_labels(dimensions::Int, dimension_labels)
    dimension_labels === nothing && return _default_dimension_labels(dimensions)
    labels = collect(dimension_labels)
    length(labels) == dimensions ||
        throw(ArgumentError("dimension_labels must have one label per dimension"))
    out = String[]
    for (index, label) in pairs(labels)
        ismissing(label) &&
            throw(ArgumentError("dimension label $index is missing"))
        text = string(label)
        !isempty(text) ||
            throw(ArgumentError("dimension label $index is empty"))
        push!(out, text)
    end
    length(unique(out)) == length(out) ||
        throw(ArgumentError("dimension_labels must be unique"))
    return out
end

_is_mfrm_fixed_q(family::Symbol, dimensions::Int) = family === :mfrm && dimensions >= 2
_is_mfrm_fixed_q(spec::FacetSpec) = _is_mfrm_fixed_q(spec.family, spec.dimensions)

function _check_dimensions(family::Symbol, dimensions::Int)
    dimensions >= 1 || throw(ArgumentError("dimensions must be positive"))
    family === :gmfrm && dimensions == 1 ||
        family !== :gmfrm ||
        throw(ArgumentError(
            "family = :gmfrm is one-dimensional; use family = :mgmfrm with " *
            "dimensions >= 2 and a fixed q_matrix for multidimensional models",
        ))
    return dimensions
end

function _check_discrimination(family::Symbol, discrimination::Symbol)
    allowed = (:none, :global, :rater, :item, :rater_item)
    discrimination in allowed ||
        throw(ArgumentError("discrimination must be one of $(allowed)"))
    family === :mfrm && discrimination === :none ||
        family !== :mfrm ||
        throw(ArgumentError("family = :mfrm currently requires discrimination = :none"))
    family === :gmfrm && discrimination !== :none ||
        family !== :gmfrm ||
        throw(ArgumentError("family = :gmfrm requires an explicit discrimination structure"))
    return discrimination
end

function _q_matrix_validation_row(; check::Symbol,
        status::Symbol,
        severity::Symbol = :info,
        item = missing,
        dimension = missing,
        dimension_label = missing,
        n_items = missing,
        n_dimensions = missing,
        n_active = missing,
        n_components = missing,
        note::Symbol = :none,
        details = (;))
    return (;
        schema = "bayesianmgmfrm.q_matrix_validation_row.v1",
        check,
        status,
        severity,
        item,
        dimension,
        dimension_label,
        n_items,
        n_dimensions,
        n_active,
        n_components,
        note,
        details,
    )
end

function _resolve_q_matrix_input(q_in, item_levels::AbstractVector; item_role::Symbol = :item)
    q_in === nothing && return (; matrix = nothing, dimension_labels = nothing)
    q_in isa AbstractMatrix && return (; matrix = q_in, dimension_labels = nothing)
    I = length(item_levels)
    if q_in isa NamedTuple && (:items in keys(q_in)) && (:matrix in keys(q_in))
        extra_keys = setdiff(keys(q_in), (:items, :matrix, :dimensions))
        isempty(extra_keys) || throw(ArgumentError("unrecognized keys $(extra_keys) in labeled q_matrix NamedTuple"))
        it_in = collect(q_in.items)
        mat_in = q_in.matrix
        mat_in isa AbstractMatrix || throw(ArgumentError("q_matrix.matrix must be a 2D matrix"))
        size(mat_in, 1) == length(it_in) || throw(DimensionMismatch("length(q_matrix.items) != size(q_matrix.matrix, 1)"))
        length(it_in) == I && length(unique(string.(it_in))) == I ||
            throw(ArgumentError("q_matrix.items must list each observed $item_role level once"))
        perm = Vector{Int}(undef, I)
        for (i, lvl) in enumerate(item_levels)
            hit = findfirst(x -> isequal(x, lvl) || string(x) == string(lvl), it_in)
            hit === nothing && throw(ArgumentError("missing $item_role $(repr(lvl)) in q_matrix.items"))
            perm[i] = hit
        end
        dims_out = hasproperty(q_in, :dimensions) ? q_in.dimensions : nothing
        return (; matrix = mat_in[perm, :], dimension_labels = dims_out)
    elseif q_in isa AbstractDict || q_in isa NamedTuple || (q_in isa AbstractVector && !isempty(q_in) && all(x -> x isa Pair, q_in))
        kv = q_in isa NamedTuple ? collect(pairs(q_in)) : (q_in isa AbstractDict ? collect(pairs(q_in)) : collect(q_in))
        length(kv) == I || throw(ArgumentError(
            "named q_matrix must provide exactly one indicator row for each of the $I observed $item_role levels; got $(length(kv)) entries"))
        seen_keys = Set{String}()
        for (k, _) in kv
            ks = string(k)
            ks in seen_keys && throw(ArgumentError("duplicate $item_role key $(repr(k)) in named q_matrix"))
            push!(seen_keys, ks)
        end
        first_row = collect(last(kv[1]))
        D = length(first_row)
        D >= 1 || throw(ArgumentError("named q_matrix rows must have at least 1 dimension"))
        mat_out = Matrix{Int}(undef, I, D)
        for (i, lvl) in enumerate(item_levels)
            hit = findfirst(p -> isequal(first(p), lvl) || string(first(p)) == string(lvl), kv)
            hit === nothing && throw(ArgumentError("missing $item_role level $(repr(lvl)) in named q_matrix"))
            rv = collect(last(kv[hit]))
            length(rv) == D || throw(DimensionMismatch("named q_matrix row for $(repr(lvl)) has length $(length(rv)); expected $D"))
            for d in 1:D
                val = rv[d]
                if val isa Bool
                    mat_out[i, d] = val ? 1 : 0
                elseif val isa Real && !(val isa Bool) && (val == 0 || val == 1)
                    mat_out[i, d] = Int(val)
                else
                    throw(ArgumentError("named q_matrix entry for $(repr(lvl)), dim $d must be 0/1 or Bool; got $(repr(val))"))
                end
            end
        end
        return (; matrix = Bool.(mat_out), dimension_labels = nothing)
    end
    return (; matrix = q_in, dimension_labels = nothing)
end

function _q_matrix_bool_matrix(q_matrix)
    q_matrix isa AbstractMatrix ||
        return nothing, ((row = missing, column = missing, value = repr(q_matrix)),)
    mat = Matrix{Bool}(undef, size(q_matrix))
    invalid = NamedTuple[]
    for row in axes(q_matrix, 1), col in axes(q_matrix, 2)
        value = q_matrix[row, col]
        if value isa Bool
            mat[row, col] = value
        elseif value isa Integer && !(value isa Bool) && value in (0, 1)
            mat[row, col] = Bool(value)
        else
            push!(invalid, (; row, column = col, value = repr(value)))
        end
    end
    return mat, Tuple(invalid)
end

function _q_matrix_duplicate_column_groups(mat::Matrix{Bool})
    groups = Dict{Tuple{Vararg{Bool}},Vector{Int}}()
    for dim in axes(mat, 2)
        key = Tuple(mat[:, dim])
        push!(get!(groups, key, Int[]), dim)
    end
    out = [Tuple(group) for group in values(groups) if length(group) > 1]
    sort!(out; by = group -> first(group))
    return Tuple(out)
end

function _q_matrix_structural_matching(
        mat::Matrix{Bool}, item_indices = axes(mat, 1))
    items = sort(unique(Int(item) for item in item_indices))
    all(item -> item in axes(mat, 1), items) ||
        throw(ArgumentError("Q-matrix structural matching received an invalid item index"))
    matched_item_by_dimension = zeros(Int, size(mat, 2))

    function augment(item::Int, seen_dimensions::AbstractVector{Bool})
        for dimension in axes(mat, 2)
            mat[item, dimension] || continue
            seen_dimensions[dimension] && continue
            seen_dimensions[dimension] = true
            previous_item = matched_item_by_dimension[dimension]
            if previous_item == 0 || augment(previous_item, seen_dimensions)
                matched_item_by_dimension[dimension] = item
                return true
            end
        end
        return false
    end

    structural_rank = 0
    for item in items
        structural_rank += augment(item, falses(size(mat, 2))) ? 1 : 0
    end
    unmatched_dimensions = Tuple(findall(iszero, matched_item_by_dimension))
    return (;
        structural_rank,
        full_column_rank = structural_rank == size(mat, 2),
        matched_item_by_dimension = Tuple(matched_item_by_dimension),
        matched_pairs = Tuple(
            (item = item, dimension = dimension)
            for (dimension, item) in pairs(matched_item_by_dimension)
            if item != 0
        ),
        unmatched_dimensions,
    )
end

function _q_matrix_pure_items_per_dimension(mat::Matrix{Bool})
    return Tuple(
        Tuple(item for item in axes(mat, 1)
            if mat[item, dimension] && count(@view mat[item, :]) == 1)
        for dimension in axes(mat, 2)
    )
end

function _q_matrix_person_dimension_support(
        data::FacetData,
        mat::Matrix{Bool},
        dimension_labels::Vector{String})
    rows = NamedTuple[]
    observation_counts = zeros(Int, length(data.person_levels))
    observed_item_sets = [Set{Int}() for _ in eachindex(data.person_levels)]
    for observation in 1:data.n
        person = data.person[observation]
        observation_counts[person] += 1
        push!(observed_item_sets[person], data.item[observation])
    end
    for person in eachindex(data.person_levels)
        observed_items = sort!(collect(observed_item_sets[person]))
        matching = _q_matrix_structural_matching(mat, observed_items)
        observed_dimensions = Tuple(
            dimension for dimension in axes(mat, 2)
            if any(item -> mat[item, dimension], observed_items)
        )
        unobserved_dimensions = Tuple(
            dimension for dimension in axes(mat, 2)
            if dimension ∉ observed_dimensions
        )
        push!(rows, (;
            person,
            person_label = data.person_levels[person],
            n_observations = observation_counts[person],
            n_observed_items = length(observed_items),
            observed_item_indices = Tuple(observed_items),
            observed_item_labels =
                Tuple(data.item_levels[item] for item in observed_items),
            observed_dimensions,
            unobserved_dimensions,
            unobserved_dimension_labels =
                Tuple(dimension_labels[dimension]
                    for dimension in unobserved_dimensions),
            structural_rank = matching.structural_rank,
            full_column_rank = matching.full_column_rank,
            example_unmatched_dimensions = matching.unmatched_dimensions,
            example_unmatched_dimension_labels =
                Tuple(dimension_labels[dimension]
                    for dimension in matching.unmatched_dimensions),
        ))
    end
    return Tuple(rows)
end

function _q_matrix_component_rows(data::FacetData,
        mat::Matrix{Bool},
        dimension_labels::Vector{String})
    nodes = Tuple{Symbol,Int}[]
    for item in axes(mat, 1)
        push!(nodes, (:item, item))
    end
    for dim in axes(mat, 2)
        push!(nodes, (:dimension, dim))
    end
    adj = Dict(node => Tuple{Symbol,Int}[] for node in nodes)
    for item in axes(mat, 1), dim in axes(mat, 2)
        mat[item, dim] || continue
        push!(adj[(:item, item)], (:dimension, dim))
        push!(adj[(:dimension, dim)], (:item, item))
    end

    seen = Set{Tuple{Symbol,Int}}()
    components = Vector{Vector{Tuple{Symbol,Int}}}()
    for node in nodes
        node in seen && continue
        queue = [node]
        head = 1
        push!(seen, node)
        component = Tuple{Symbol,Int}[]
        while head <= length(queue)
            current = queue[head]
            head += 1
            push!(component, current)
            for nxt in adj[current]
                nxt in seen && continue
                push!(seen, nxt)
                push!(queue, nxt)
            end
        end
        push!(components, component)
    end
    sort!(components; by = component -> (-length(component), string(first(component))))
    return Tuple(
        Tuple(
            node[1] === :item ?
                (node = :item, index = node[2], label = data.item_levels[node[2]]) :
                (node = :dimension, index = node[2],
                    label = dimension_labels[node[2]])
            for node in component
        )
        for component in components
    )
end

function _q_matrix_dimension_facet_components(data::FacetData, active_items::Set{Int})
    nodes = Tuple{Symbol,Int}[]
    for person in eachindex(data.person_levels)
        push!(nodes, (:person, person))
    end
    for rater in eachindex(data.rater_levels)
        push!(nodes, (:rater, rater))
    end
    for item in sort(collect(active_items))
        push!(nodes, (:item, item))
    end
    adj = Dict(node => Tuple{Symbol,Int}[] for node in nodes)
    observed = Set{Tuple{Symbol,Int}}()
    for row in 1:data.n
        item = data.item[row]
        item in active_items || continue
        p = (:person, data.person[row])
        r = (:rater, data.rater[row])
        i = (:item, item)
        push!(observed, p)
        push!(observed, r)
        push!(observed, i)
        _add_edge!(adj, p, r)
        _add_edge!(adj, p, i)
        _add_edge!(adj, r, i)
    end

    active_nodes = [node for node in nodes if node in observed]
    seen = Set{Tuple{Symbol,Int}}()
    components = Vector{Vector{Tuple{Symbol,Int}}}()
    for node in active_nodes
        node in seen && continue
        queue = [node]
        head = 1
        push!(seen, node)
        component = Tuple{Symbol,Int}[]
        while head <= length(queue)
            current = queue[head]
            head += 1
            push!(component, current)
            for nxt in adj[current]
                nxt in seen && continue
                push!(seen, nxt)
                push!(queue, nxt)
            end
        end
        push!(components, component)
    end
    sort!(components; by = component -> (-length(component), string(first(component))))
    return Tuple(
        Tuple(
            node[1] === :person ?
                (facet = :person, index = node[2], label = data.person_levels[node[2]]) :
            node[1] === :rater ?
                (facet = :rater, index = node[2], label = data.rater_levels[node[2]]) :
                (facet = :item, index = node[2], label = data.item_levels[node[2]])
            for node in component
        )
        for component in components
    )
end

function _q_matrix_validation_manifest(data::FacetData,
        family::Symbol,
        dimensions::Int,
        q_matrix,
        dimension_labels::Vector{String};
        cross_loading_policy::Symbol = :confirmatory_fixed,
        include_matrix::Bool = false)
    rows = NamedTuple[]
    mat = nothing

    applicable = family === :mgmfrm || _is_mfrm_fixed_q(family, dimensions)
    family_applicability_status =
        applicable ? :applicable : :not_applicable
    family_applicability_severity =
        applicable || q_matrix === nothing ? :info : :error
    push!(rows, _q_matrix_validation_row(;
        check = :family_applicability,
        status = family_applicability_status,
        severity = family_applicability_severity,
        n_items = length(data.item_levels),
        n_dimensions = dimensions,
        note = _is_mfrm_fixed_q(family, dimensions) ? :q_matrix_required_for_multidimensional_mfrm : family === :mgmfrm ?
            :q_matrix_required_for_mgmfrm :
            :q_matrix_only_applies_to_mgmfrm,
    ))
    if !applicable
        q_matrix === nothing || push!(rows, _q_matrix_validation_row(;
            check = :family_applicability,
            status = :rejected_for_family,
            severity = :error,
            n_items = length(data.item_levels),
            n_dimensions = dimensions,
            note = :q_matrix_only_accepted_for_mgmfrm,
        ))
        passed = !any(row -> row.severity === :error, rows)
        return (;
            schema = "bayesianmgmfrm.q_matrix_validation.v1",
            object = :q_matrix_validation,
            family,
            dimensions,
            dimension_labels = copy(dimension_labels),
            cross_loading_policy,
            q_matrix = nothing,
            matrix = include_matrix ? mat : nothing,
            identification = nothing,
            passed,
            rows = Tuple(rows),
            summary = (;
                passed,
                n_items = length(data.item_levels),
                n_dimensions = dimensions,
                n_error_rows = count(row -> row.severity === :error, rows),
                n_warning_rows = count(row -> row.severity === :warning, rows),
                fixed_q_confirmatory = false,
                n_cross_loading_items = 0,
                n_duplicate_dimension_groups = 0,
                n_dimension_facet_subgraphs_disconnected = 0,
            ),
        )
    end

    if q_matrix === nothing
        push!(rows, _q_matrix_validation_row(;
            check = :required_q_matrix,
            status = :missing,
            severity = :error,
            n_items = length(data.item_levels),
            n_dimensions = dimensions,
            note = :family_mgmfrm_requires_fixed_confirmatory_q_matrix,
        ))
        passed = false
        return (;
            schema = "bayesianmgmfrm.q_matrix_validation.v1",
            object = :q_matrix_validation,
            family,
            dimensions,
            dimension_labels = copy(dimension_labels),
            cross_loading_policy,
            q_matrix = nothing,
            matrix = include_matrix ? mat : nothing,
            identification = nothing,
            passed,
            rows = Tuple(rows),
            summary = (;
                passed,
                n_items = length(data.item_levels),
                n_dimensions = dimensions,
                n_error_rows = count(row -> row.severity === :error, rows),
                n_warning_rows = count(row -> row.severity === :warning, rows),
                fixed_q_confirmatory = false,
                n_cross_loading_items = 0,
                n_duplicate_dimension_groups = 0,
                n_dimension_facet_subgraphs_disconnected = 0,
            ),
        )
    end

    if !(q_matrix isa AbstractMatrix) && (q_matrix isa AbstractDict || q_matrix isa NamedTuple ||
            (q_matrix isa AbstractVector && !isempty(q_matrix) && all(x -> x isa Pair, q_matrix)))
        q_matrix = _resolve_q_matrix_input(q_matrix, data.item_levels).matrix
    end
    if !(q_matrix isa AbstractMatrix)
        push!(rows, _q_matrix_validation_row(;
            check = :matrix_schema,
            status = :not_matrix,
            severity = :error,
            n_items = length(data.item_levels),
            n_dimensions = dimensions,
            note = :q_matrix_must_be_two_dimensional_matrix,
            details = (; value = repr(q_matrix)),
        ))
        passed = false
        return (;
            schema = "bayesianmgmfrm.q_matrix_validation.v1",
            object = :q_matrix_validation,
            family,
            dimensions,
            dimension_labels = copy(dimension_labels),
            cross_loading_policy,
            q_matrix = nothing,
            matrix = include_matrix ? mat : nothing,
            identification = nothing,
            passed,
            rows = Tuple(rows),
            summary = (;
                passed,
                n_items = length(data.item_levels),
                n_dimensions = dimensions,
                n_error_rows = count(row -> row.severity === :error, rows),
                n_warning_rows = count(row -> row.severity === :warning, rows),
                fixed_q_confirmatory = false,
                n_cross_loading_items = 0,
                n_duplicate_dimension_groups = 0,
                n_dimension_facet_subgraphs_disconnected = 0,
            ),
        )
    end

    push!(rows, _q_matrix_validation_row(;
        check = :matrix_schema,
        status = :matrix,
        n_items = size(q_matrix, 1),
        n_dimensions = size(q_matrix, 2),
        note = :two_dimensional_matrix_supplied,
    ))

    mat, invalid_values = _q_matrix_bool_matrix(q_matrix)
    if isempty(invalid_values)
        push!(rows, _q_matrix_validation_row(;
            check = :binary_mask_schema,
            status = :binary_bool_or_zero_one,
            n_items = size(q_matrix, 1),
            n_dimensions = size(q_matrix, 2),
            note = :q_matrix_entries_are_binary_mask_values,
        ))
    else
        push!(rows, _q_matrix_validation_row(;
            check = :binary_mask_schema,
            status = :non_binary_entries,
            severity = :error,
            n_items = size(q_matrix, 1),
            n_dimensions = size(q_matrix, 2),
            note = :q_matrix_entries_must_be_bool_or_zero_one_integer,
            details = (; invalid_entries = invalid_values),
        ))
    end

    expected_shape = (length(data.item_levels), dimensions)
    shape_ok = size(q_matrix) == expected_shape
    push!(rows, _q_matrix_validation_row(;
        check = :shape,
        status = shape_ok ? :matches_items_by_dimensions : :shape_mismatch,
        severity = shape_ok ? :info : :error,
        n_items = size(q_matrix, 1),
        n_dimensions = size(q_matrix, 2),
        note = shape_ok ? :one_row_per_item_one_column_per_dimension :
            :q_matrix_shape_must_match_items_by_dimensions,
        details = (; expected = expected_shape, observed = size(q_matrix)),
    ))

    if mat === nothing || !isempty(invalid_values) || !shape_ok
        passed = !any(row -> row.severity === :error, rows)
        return (;
            schema = "bayesianmgmfrm.q_matrix_validation.v1",
            object = :q_matrix_validation,
            family,
            dimensions,
            dimension_labels = copy(dimension_labels),
            cross_loading_policy,
            q_matrix = nothing,
            matrix = include_matrix ? mat : nothing,
            identification = nothing,
            passed,
            rows = Tuple(rows),
            summary = (;
                passed,
                n_items = length(data.item_levels),
                n_dimensions = dimensions,
                n_error_rows = count(row -> row.severity === :error, rows),
                n_warning_rows = count(row -> row.severity === :warning, rows),
                fixed_q_confirmatory = false,
                n_cross_loading_items = 0,
                n_duplicate_dimension_groups = 0,
                n_dimension_facet_subgraphs_disconnected = 0,
            ),
        )
    end

    empty_items = [item for item in axes(mat, 1) if !any(@view mat[item, :])]
    push!(rows, _q_matrix_validation_row(;
        check = :empty_item_rows,
        status = isempty(empty_items) ? :passed : :empty_rows,
        severity = isempty(empty_items) ? :info : :error,
        n_items = size(mat, 1),
        n_dimensions = size(mat, 2),
        n_active = size(mat, 1) - length(empty_items),
        note = isempty(empty_items) ?
            :each_item_loads_on_at_least_one_dimension :
            :each_item_must_load_on_at_least_one_dimension,
        details = (;
            item_indices = Tuple(empty_items),
            item_labels = Tuple(data.item_levels[item] for item in empty_items),
        ),
    ))

    empty_dimensions = [dim for dim in axes(mat, 2) if !any(@view mat[:, dim])]
    push!(rows, _q_matrix_validation_row(;
        check = :empty_dimensions,
        status = isempty(empty_dimensions) ? :passed : :empty_dimensions,
        severity = isempty(empty_dimensions) ? :info : :error,
        n_items = size(mat, 1),
        n_dimensions = size(mat, 2),
        n_active = size(mat, 2) - length(empty_dimensions),
        note = isempty(empty_dimensions) ?
            :each_dimension_has_at_least_one_item :
            :each_dimension_must_have_at_least_one_item,
        details = (;
            dimension_indices = Tuple(empty_dimensions),
            dimension_labels = Tuple(dimension_labels[dim] for dim in empty_dimensions),
        ),
    ))

    duplicate_groups = _q_matrix_duplicate_column_groups(mat)
    push!(rows, _q_matrix_validation_row(;
        check = :duplicate_dimension_columns,
        status = isempty(duplicate_groups) ? :passed : :aliased_columns,
        severity = isempty(duplicate_groups) ? :info : :error,
        n_items = size(mat, 1),
        n_dimensions = size(mat, 2),
        n_active = size(mat, 2) -
            sum((max(length(group) - 1, 0) for group in duplicate_groups); init = 0),
        note = isempty(duplicate_groups) ?
            :dimension_columns_have_distinct_item_masks :
            :duplicate_q_columns_alias_dimensions,
        details = (;
            duplicate_dimension_groups = duplicate_groups,
            duplicate_dimension_label_groups = Tuple(
                Tuple(dimension_labels[dim] for dim in group)
                for group in duplicate_groups
            ),
        ),
    ))

    structural_matching = _q_matrix_structural_matching(mat)
    push!(rows, _q_matrix_validation_row(;
        check = :global_loading_structural_rank,
        status = structural_matching.full_column_rank ?
            :full_column_structural_rank : :structurally_rank_deficient,
        severity = structural_matching.full_column_rank ? :info : :error,
        n_items = size(mat, 1),
        n_dimensions = size(mat, 2),
        n_active = structural_matching.structural_rank,
        note = structural_matching.full_column_rank ?
            :q_zero_pattern_can_generically_support_all_loading_dimensions :
            :q_zero_pattern_cannot_support_a_full_column_rank_loading_matrix,
        details = (;
            structural_rank = structural_matching.structural_rank,
            matched_item_by_dimension =
                structural_matching.matched_item_by_dimension,
            matched_pairs = structural_matching.matched_pairs,
            unmatched_dimension_indices =
                structural_matching.unmatched_dimensions,
            unmatched_dimension_labels = Tuple(
                dimension_labels[dimension]
                for dimension in structural_matching.unmatched_dimensions
            ),
        ),
    ))

    person_dimension_support =
        _q_matrix_person_dimension_support(data, mat, dimension_labels)
    incomplete_person_support = Tuple(
        row for row in person_dimension_support if !row.full_column_rank
    )
    person_support_status = if !structural_matching.full_column_rank
        :not_separately_assessed_global_rank_deficient
    elseif isempty(incomplete_person_support)
        :every_person_has_full_dimension_structural_support
    else
        :some_person_dimensions_are_prior_anchored
    end
    push!(rows, _q_matrix_validation_row(;
        check = :person_dimension_likelihood_support,
        status = person_support_status,
        severity = structural_matching.full_column_rank &&
            !isempty(incomplete_person_support) ? :warning : :info,
        n_items = size(mat, 1),
        n_dimensions = size(mat, 2),
        n_active = length(person_dimension_support) -
            length(incomplete_person_support),
        note = !structural_matching.full_column_rank ?
            :global_loading_structure_must_be_fixed_before_person_support_review :
        isempty(incomplete_person_support) ?
            :each_person_observes_an_item_pattern_with_full_dimension_structural_rank :
            :some_person_dimension_coordinates_rely_on_the_population_prior,
        details = (;
            n_persons = length(person_dimension_support),
            n_persons_full_column_rank = length(person_dimension_support) -
                length(incomplete_person_support),
            n_persons_incomplete = length(incomplete_person_support),
            minimum_person_structural_rank =
                minimum(row.structural_rank for row in person_dimension_support),
            person_rows = person_dimension_support,
            incomplete_person_rows = incomplete_person_support,
        ),
    ))

    cross_loading_items = [item for item in axes(mat, 1) if count(@view mat[item, :]) > 1]
    cross_loading_status =
        isempty(cross_loading_items) ? :simple_structure : :fixed_confirmatory_cross_loadings
    cross_loading_severity =
        isempty(cross_loading_items) ? :info : :warning
    if cross_loading_policy === :blocked_simple_structure && !isempty(cross_loading_items)
        cross_loading_status = :blocked_cross_loading
        cross_loading_severity = :error
    elseif cross_loading_policy !== :confirmatory_fixed &&
            cross_loading_policy !== :blocked_simple_structure
        cross_loading_status = :unsupported_cross_loading_policy
        cross_loading_severity = :error
    end
    push!(rows, _q_matrix_validation_row(;
        check = :cross_loading_policy,
        status = cross_loading_status,
        severity = cross_loading_severity,
        n_items = size(mat, 1),
        n_dimensions = size(mat, 2),
        n_active = length(cross_loading_items),
        note = cross_loading_severity === :error ?
            :cross_loading_policy_not_supported_for_current_q_matrix :
        isempty(cross_loading_items) ?
            :simple_structure_q_matrix :
            :cross_loadings_are_fixed_confirmatory_not_exploratory,
        details = (;
            policy = cross_loading_policy,
            item_indices = Tuple(cross_loading_items),
            item_labels = Tuple(data.item_levels[item] for item in cross_loading_items),
        ),
    ))

    pure_items_per_dimension = _q_matrix_pure_items_per_dimension(mat)
    single_loading_missing =
        findall(isempty, pure_items_per_dimension)
    push!(rows, _q_matrix_validation_row(;
        check = :positive_loading_identification,
        status = isempty(single_loading_missing) ? :single_loading_anchor_present :
            :no_single_loading_anchor,
        severity = isempty(single_loading_missing) ? :info : :warning,
        n_items = size(mat, 1),
        n_dimensions = size(mat, 2),
        n_active = size(mat, 2) - length(single_loading_missing),
        note = isempty(single_loading_missing) ?
            :positive_loadings_have_simple_anchor_items :
            :dimension_has_only_cross_loading_items_review_interpretation,
        details = (;
            dimension_indices = Tuple(single_loading_missing),
            dimension_labels = Tuple(dimension_labels[dim] for dim in single_loading_missing),
            pure_item_indices_per_dimension = pure_items_per_dimension,
            pure_item_labels_per_dimension = Tuple(
                Tuple(data.item_levels[item] for item in items)
                for items in pure_items_per_dimension
            ),
        ),
    ))

    push!(rows, _q_matrix_validation_row(;
        check = :ability_population_identification_anchor,
        status = :standard_normal_identity_correlation_prior_anchor,
        severity = :info,
        n_items = size(mat, 1),
        n_dimensions = size(mat, 2),
        n_active = size(mat, 2),
        note = :origin_scale_and_latent_rotation_are_prior_anchored_not_likelihood_only,
        details = (;
            population_prior = :standard_normal_by_dimension,
            latent_correlation = :identity_fixed,
            ability_location = :zero_prior_mean,
            ability_scale = :unit_prior_standard_deviation,
            likelihood_only_identification_claim = false,
        ),
    ))

    q_components = _q_matrix_component_rows(data, mat, dimension_labels)
    push!(rows, _q_matrix_validation_row(;
        check = :dimension_item_graph_components,
        status = :recorded,
        n_items = size(mat, 1),
        n_dimensions = size(mat, 2),
        n_components = length(q_components),
        note = :q_item_dimension_graph_recorded_for_review,
        details = (; components = q_components),
    ))

    n_disconnected_dimension_subgraphs = 0
    for dim in axes(mat, 2)
        active_items = Set(item for item in axes(mat, 1) if mat[item, dim])
        rows_for_dimension = [row for row in 1:data.n if data.item[row] in active_items]
        persons = Set(data.person[row] for row in rows_for_dimension)
        raters = Set(data.rater[row] for row in rows_for_dimension)
        components = _q_matrix_dimension_facet_components(data, active_items)
        disconnected = length(components) > 1
        n_disconnected_dimension_subgraphs += disconnected ? 1 : 0
        severity =
            isempty(rows_for_dimension) ? :error :
            disconnected ? :warning :
            :info
        push!(rows, _q_matrix_validation_row(;
            check = :dimension_facet_subgraph_coverage,
            status = isempty(rows_for_dimension) ? :no_observed_ratings :
                disconnected ? :disconnected_dimension_subgraph :
                :connected_dimension_subgraph,
            severity,
            dimension = dim,
            dimension_label = dimension_labels[dim],
            n_items = length(active_items),
            n_dimensions = dimensions,
            n_active = length(rows_for_dimension),
            n_components = length(components),
            note = isempty(rows_for_dimension) ?
                :dimension_has_no_observed_ratings_for_active_items :
            disconnected ?
                :dimension_specific_person_rater_item_subgraph_disconnected :
                :dimension_specific_person_rater_item_subgraph_connected,
            details = (;
                n_persons = length(persons),
                n_raters = length(raters),
                item_indices = Tuple(sort(collect(active_items))),
                item_labels = Tuple(data.item_levels[item] for item in sort(collect(active_items))),
                component_sizes = Tuple(length(component) for component in components),
                components,
            ),
        ))
    end

    all_persons_full_dimension_rank =
        all(row -> row.full_column_rank, person_dimension_support)
    all_dimensions_have_pure_items =
        all(!isempty, pure_items_per_dimension)
    guarded_fit_structure_ready =
        !any(row -> row.severity === :error, rows)
    conservative_stable_structure_ready =
        guarded_fit_structure_ready &&
        structural_matching.full_column_rank &&
        all_persons_full_dimension_rank &&
        all_dimensions_have_pure_items &&
        n_disconnected_dimension_subgraphs == 0
    promotion_blockers = Symbol[]
    guarded_fit_structure_ready || push!(promotion_blockers, :q_validation_errors)
    structural_matching.full_column_rank ||
        push!(promotion_blockers, :global_loading_structural_rank)
    all_persons_full_dimension_rank ||
        push!(promotion_blockers, :person_dimension_likelihood_support)
    all_dimensions_have_pure_items ||
        push!(promotion_blockers, :pure_item_interpretation_support)
    n_disconnected_dimension_subgraphs == 0 ||
        push!(promotion_blockers, :dimension_facet_subgraph_connectivity)
    identification_status = if !guarded_fit_structure_ready
        :rejected_fixed_q_structure
    elseif conservative_stable_structure_ready
        :conservative_stable_structure_ready
    elseif !all_persons_full_dimension_rank
        :guarded_prior_anchored_person_dimensions
    elseif !all_dimensions_have_pure_items
        :guarded_generic_fixed_q_review_required
    else
        :guarded_connectivity_review_required
    end
    push!(rows, _q_matrix_validation_row(;
        check = :fixed_q_identification_gate,
        status = identification_status,
        severity = !guarded_fit_structure_ready ? :error :
            conservative_stable_structure_ready ? :info : :warning,
        n_items = size(mat, 1),
        n_dimensions = size(mat, 2),
        n_active = structural_matching.structural_rank,
        note = conservative_stable_structure_ready ?
            :fixed_q_structure_meets_the_conservative_stable_support_rule :
        guarded_fit_structure_ready ?
            :fixed_q_structure_is_guarded_only_and_requires_promotion_evidence :
            :fixed_q_structure_fails_guarded_prefit_validation,
        details = (;
            guarded_fit_structure_ready,
            conservative_stable_structure_ready,
            promotion_blockers = Tuple(unique(promotion_blockers)),
        ),
    ))

    passed = !any(row -> row.severity === :error, rows)
    identification = (;
        schema = "bayesianmgmfrm.fixed_q_identification.v1",
        object = :fixed_q_identification,
        status = identification_status,
        likelihood_support = (;
            q_structural_rank = structural_matching.structural_rank,
            q_full_column_structural_rank =
                structural_matching.full_column_rank,
            matched_item_by_dimension =
                structural_matching.matched_item_by_dimension,
            all_persons_full_dimension_rank,
            minimum_person_structural_rank =
                minimum(row.structural_rank for row in person_dimension_support),
            n_persons_incomplete = length(incomplete_person_support),
            person_rows = person_dimension_support,
        ),
        interpretation_support = (;
            pure_item_indices_per_dimension = pure_items_per_dimension,
            pure_item_counts_per_dimension =
                Tuple(length(items) for items in pure_items_per_dimension),
            all_dimensions_have_pure_items,
            fixed_dimension_labels = true,
            positive_q_masked_loadings = true,
        ),
        prior_anchor = (;
            population_prior = :standard_normal_by_dimension,
            latent_correlation = :identity_fixed,
            ability_location = :zero_prior_mean,
            ability_scale = :unit_prior_standard_deviation,
            likelihood_only_identification_claim = false,
        ),
        guarded_fit_structure_ready = passed,
        conservative_stable_structure_ready =
            passed && conservative_stable_structure_ready,
        promotion_blockers = Tuple(unique(promotion_blockers)),
    )
    return (;
        schema = "bayesianmgmfrm.q_matrix_validation.v1",
        object = :q_matrix_validation,
        family,
        dimensions,
        dimension_labels = copy(dimension_labels),
        cross_loading_policy,
        q_matrix = _q_matrix_manifest(mat),
        matrix = include_matrix ? mat : nothing,
        identification,
        passed,
        rows = Tuple(rows),
        summary = (;
            passed,
            n_items = size(mat, 1),
            n_dimensions = size(mat, 2),
            n_error_rows = count(row -> row.severity === :error, rows),
            n_warning_rows = count(row -> row.severity === :warning, rows),
            fixed_q_confirmatory = true,
            n_cross_loading_items = length(cross_loading_items),
            n_duplicate_dimension_groups = length(duplicate_groups),
            n_dimension_facet_subgraphs_disconnected =
                n_disconnected_dimension_subgraphs,
            q_structural_rank = structural_matching.structural_rank,
            q_full_column_structural_rank =
                structural_matching.full_column_rank,
            all_persons_full_dimension_rank,
            minimum_person_structural_rank =
                identification.likelihood_support.minimum_person_structural_rank,
            n_persons_incomplete_dimension_support =
                length(incomplete_person_support),
            pure_item_counts_per_dimension =
                identification.interpretation_support.
                    pure_item_counts_per_dimension,
            all_dimensions_have_pure_items,
            identification_status,
            guarded_fit_structure_ready = passed,
            conservative_stable_structure_ready =
                identification.conservative_stable_structure_ready,
            identification_promotion_blockers =
                identification.promotion_blockers,
        ),
    )
end

"""
    q_matrix_validation(data::FacetData; family = :mgmfrm, dimensions = nothing,
                        q_matrix = nothing, dimension_labels = nothing,
                        cross_loading_policy = :confirmatory_fixed)
    q_matrix_validation(spec::FacetSpec; cross_loading_policy = :confirmatory_fixed)
    q_matrix_validation(design::FacetDesign; cross_loading_policy = :confirmatory_fixed)

Validate the fixed confirmatory Q-matrix contract used by guarded MGMFRM
specifications. The returned manifest records binary mask schema checks,
item/dimension coverage, duplicate or aliased dimension columns, fixed
cross-loading policy, the generic structural rank of the Q zero pattern,
person-specific dimension support, simple loading anchors, the standard-normal
identity-correlation prior anchor, and dimension-specific person-rater-item
subgraph coverage. Error rows make `passed = false`; warning rows remain
actionable review evidence without rejecting the guarded fixed-Q spec.
`identification.conservative_stable_structure_ready` is a stricter sufficient
structural screen; it does not establish parameter recovery or reliable
inference for an observed dataset.
"""
function q_matrix_validation(data::FacetData;
        family::Symbol = :mgmfrm,
        dimensions = nothing,
        q_matrix = nothing,
        dimension_labels = nothing,
        cross_loading_policy::Symbol = :confirmatory_fixed)
    checked_family = _check_family(family)
    checked_dimensions = if dimensions === nothing
        checked_family === :mgmfrm ? 2 : 1
    elseif dimensions isa Integer && !(dimensions isa Bool)
        _check_dimensions(checked_family, Int(dimensions))
    else
        throw(ArgumentError("dimensions must be an integer"))
    end
    checked_dimension_labels =
        _normalize_dimension_labels(checked_dimensions, dimension_labels)
    return _q_matrix_validation_manifest(
        data,
        checked_family,
        checked_dimensions,
        q_matrix,
        checked_dimension_labels;
        cross_loading_policy,
    )
end

q_matrix_validation(spec::FacetSpec; cross_loading_policy::Symbol = :confirmatory_fixed) =
    _q_matrix_validation_manifest(
        spec.data,
        spec.family,
        spec.dimensions,
        spec.q_matrix,
        spec.dimension_labels;
        cross_loading_policy,
    )

q_matrix_validation(design::FacetDesign; kwargs...) =
    q_matrix_validation(design.spec; kwargs...)

const _Q_MATRIX_OBSERVATION_COVERAGE_CHECKS =
    (:dimension_facet_subgraph_coverage,)

const _Q_MATRIX_DERIVED_VALIDATION_CHECKS =
    (:fixed_q_identification_gate,)

function _q_matrix_guarded_structure_passed(validation)
    # The identification gate only summarizes the primary rows above it. Ignore
    # that derived row here so an allowed observation-coverage error is not
    # counted twice; every primary, unclassified current or future error remains
    # blocking, so mutable Q inputs still fail closed.
    return all(
        row -> row.severity !== :error ||
            row.check in _Q_MATRIX_OBSERVATION_COVERAGE_CHECKS ||
            row.check in _Q_MATRIX_DERIVED_VALIDATION_CHECKS,
        validation.rows,
    )
end

function _normalize_q_matrix(data::FacetData,
        family::Symbol,
        dimensions::Int,
        q_matrix,
        dimension_labels::Vector{String})
    if family !== :mgmfrm && !_is_mfrm_fixed_q(family, dimensions)
        q_matrix === nothing || throw(ArgumentError("q_matrix requires multidimensional family = :mfrm or :mgmfrm"))
        return nothing
    end
    validation = _q_matrix_validation_manifest(
        data,
        family,
        dimensions,
        q_matrix,
        dimension_labels;
        include_matrix = true,
    )
    if !validation.passed
        failing_checks = Tuple(
            (check = row.check, status = row.status, note = row.note)
            for row in validation.rows
            if row.severity === :error
        )
        throw(ArgumentError(
            "invalid fixed-Q $(family === :mgmfrm ? "MGMFRM" : "MFRM") q_matrix; failing_checks=$(failing_checks); " *
            "inspect q_matrix_validation(...) for actionable rows",
        ))
    end
    return validation.matrix
end
