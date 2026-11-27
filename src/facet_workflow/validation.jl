function _counts(index::Vector{Int}, levels)
    counts = Dict{Any,Int}(level => 0 for level in levels)
    for i in index
        counts[levels[i]] += 1
    end
    return counts
end

function _category_counts(data::FacetData)
    counts = Dict{Int,Int}(level => 0 for level in data.category_levels)
    for x in data.score
        counts[x] += 1
    end
    return counts
end

function _category_scale_contract(data::FacetData)
    counts = _category_counts(data)
    intended = copy(data.category_levels)
    observed = [level for level in intended if counts[level] > 0]
    unobserved = [level for level in intended if counts[level] == 0]
    interior = length(intended) <= 2 ? Int[] : intended[2:(end - 1)]
    endpoints = isempty(intended) ? Int[] : unique([first(intended), last(intended)])
    source = hasproperty(data.columns, :category_scale_source) ?
        data.columns.category_scale_source :
        :contiguous_observed_minimum_to_maximum
    return (;
        source,
        intended_levels = intended,
        observed_levels = observed,
        unobserved_levels = unobserved,
        unobserved_interior_levels = [level for level in unobserved
            if level in interior],
        unobserved_endpoint_levels = [level for level in unobserved
            if level in endpoints],
        endpoints_explicitly_declared = source === :declared,
    )
end

function _facet(data::FacetData, facet::Symbol)
    facet === :person && return data.person, data.person_levels
    facet === :rater && return data.rater, data.rater_levels
    facet === :item && return data.item, data.item_levels
    if haskey(data.optional, facet)
        return data.optional[facet], data.optional_levels[facet]
    end
    return nothing
end

function _add_edge!(adj, a, b)
    push!(get!(adj, a, Tuple{Symbol,Int}[]), b)
    push!(get!(adj, b, Tuple{Symbol,Int}[]), a)
    return nothing
end

function _connected_components(data::FacetData)
    adj = Dict{Tuple{Symbol,Int},Vector{Tuple{Symbol,Int}}}()
    for p in eachindex(data.person_levels)
        get!(adj, (:person, p), Tuple{Symbol,Int}[])
    end
    for r in eachindex(data.rater_levels)
        get!(adj, (:rater, r), Tuple{Symbol,Int}[])
    end
    for i in eachindex(data.item_levels)
        get!(adj, (:item, i), Tuple{Symbol,Int}[])
    end
    for n in 1:data.n
        p = (:person, data.person[n])
        r = (:rater, data.rater[n])
        i = (:item, data.item[n])
        _add_edge!(adj, p, r)
        _add_edge!(adj, p, i)
        _add_edge!(adj, r, i)
    end

    seen = Set{Tuple{Symbol,Int}}()
    components = Vector{Vector{Tuple{Symbol,Int}}}()
    for node in keys(adj)
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
    sort!(components; by = c -> (-length(c), string(first(c))))
    return components
end

function _label_node(data::FacetData, node::Tuple{Symbol,Int})
    facet, idx = node
    levels = facet === :person ? data.person_levels :
        facet === :rater ? data.rater_levels :
        data.item_levels
    return (facet, levels[idx])
end

function _validate_singletons!(issues, data::FacetData, facet::Symbol, index, levels)
    counts = _counts(index, levels)
    singleton = [level for (level, n) in counts if n == 1]
    isempty(singleton) && return nothing
    push!(issues, ValidationIssue(
        :singleton_facet_level,
        :warning,
        "$(length(singleton)) $(facet) level(s) have only one rating",
        context = Dict{Symbol,Any}(:facet => facet, :levels => sort(singleton; by = _level_key)),
    ))
    return nothing
end

function _validate_bias!(issues, dff_counts, data::FacetData, bias, min_cell_count::Int)
    for term in bias
        if !(term isa Tuple) || length(term) != 2
            push!(issues, ValidationIssue(:invalid_bias_term, :error,
                "bias terms must be two-facet tuples such as (:rater, :group)",
                context = Dict{Symbol,Any}(:term => term)))
            continue
        end
        a, b = term
        fa = _facet(data, a)
        fb = _facet(data, b)
        if fa === nothing || fb === nothing
            push!(issues, ValidationIssue(:unknown_bias_facet, :error,
                "bias term $term references a facet that is not present in FacetData",
                context = Dict{Symbol,Any}(:term => term)))
            continue
        end
        ai, al = fa
        bi, bl = fb
        counts = Dict{Tuple{Any,Any},Int}()
        for x in al, y in bl
            counts[(x, y)] = 0
        end
        for n in 1:data.n
            counts[(al[ai[n]], bl[bi[n]])] += 1
        end
        dff_counts[(a, b)] = counts

        empty_cells = [cell for (cell, n) in counts if n == 0]
        if !isempty(empty_cells)
            push!(issues, ValidationIssue(:empty_dff_cell, :warning,
                "bias term $term has $(length(empty_cells)) empty cell(s)",
                context = Dict{Symbol,Any}(:term => term, :cells => sort(empty_cells; by = string))))
        end

        sparse_cells = [cell for (cell, n) in counts if 0 < n < min_cell_count]
        if !isempty(sparse_cells)
            push!(issues, ValidationIssue(:sparse_dff_cell, :warning,
                "bias term $term has $(length(sparse_cells)) cell(s) below min_cell_count = $min_cell_count",
                context = Dict{Symbol,Any}(:term => term, :cells => sort(sparse_cells; by = string))))
        end

        for x in al
            observed = [y for y in bl if counts[(x, y)] > 0]
            if length(observed) == 1 && length(bl) > 1
                push!(issues, ValidationIssue(:potential_dff_confounding, :warning,
                    "$a level $(repr(x)) is observed with only one $b level",
                    context = Dict{Symbol,Any}(:term => term, :facet => a, :level => x)))
            end
        end
        for y in bl
            observed = [x for x in al if counts[(x, y)] > 0]
            if length(observed) == 1 && length(al) > 1
                push!(issues, ValidationIssue(:potential_dff_confounding, :warning,
                    "$b level $(repr(y)) is observed with only one $a level",
                    context = Dict{Symbol,Any}(:term => term, :facet => b, :level => y)))
            end
        end
    end
    return nothing
end

function _validate_item_category_support!(issues, data::FacetData)
    data.n == 0 && return nothing
    isempty(data.item_levels) && return nothing
    length(data.category_levels) <= 1 && return nothing

    counts = Dict{Tuple{Any,Int},Int}()
    for item in data.item_levels, category in data.category_levels
        counts[(item, category)] = 0
    end
    for row in 1:data.n
        item = data.item_levels[data.item[row]]
        counts[(item, data.score[row])] += 1
    end

    one_category_items = Any[]
    missing_cells = Tuple{Any,Int}[]
    for item in data.item_levels
        observed = [category for category in data.category_levels if counts[(item, category)] > 0]
        if length(observed) <= 1
            push!(one_category_items, item)
        end
        for category in data.category_levels
            counts[(item, category)] == 0 && push!(missing_cells, (item, category))
        end
    end

    if !isempty(one_category_items)
        push!(issues, ValidationIssue(
            :single_item_category,
            :warning,
            "$(length(one_category_items)) item level(s) use only one score category",
            context = Dict{Symbol,Any}(:items => sort(one_category_items; by = _level_key)),
        ))
    end
    if !isempty(missing_cells)
        push!(issues, ValidationIssue(
            :unobserved_item_category,
            :warning,
            "$(length(missing_cells)) item/category cell(s) are unobserved; partial-credit thresholds may be weakly informed",
            context = Dict{Symbol,Any}(:cells => sort(missing_cells; by = string)),
        ))
    end
    return nothing
end

function _signature_levels(levels)
    return Tuple(repr(level) for level in levels)
end

function _data_signature(data::FacetData)
    optional_keys = sort(collect(keys(data.optional)); by = string)
    optional_signature = Tuple(
        (role, Tuple(data.optional[role]), _signature_levels(data.optional_levels[role]))
        for role in optional_keys
    )
    return hash((
        data.n,
        Tuple(data.person),
        Tuple(data.rater),
        Tuple(data.item),
        Tuple(data.score),
        Tuple(data.category),
        _signature_levels(data.person_levels),
        _signature_levels(data.rater_levels),
        _signature_levels(data.item_levels),
        Tuple(data.category_levels),
        optional_signature,
        data.columns,
    ))
end

function _bias_signature(bias)
    return Tuple(
        term isa Tuple ? Tuple(term) : repr(term)
        for term in bias
    )
end

function _validation_options_signature(bias, min_cell_count::Int)
    return hash((_bias_signature(bias), min_cell_count))
end

function _is_default_validation_request(bias, min_cell_count::Int)
    return isempty(bias) && min_cell_count == 2
end

function _minimal_location_matrix(data::FacetData)
    n_person = length(data.person_levels)
    n_rater = max(length(data.rater_levels) - 1, 0)
    n_item = max(length(data.item_levels) - 1, 0)
    ncol = n_person + n_rater + n_item
    matrix = zeros(Float64, data.n, ncol)
    rater_offset = n_person
    item_offset = n_person + n_rater
    for n in 1:data.n
        matrix[n, data.person[n]] = 1.0
        if data.rater[n] > 1
            matrix[n, rater_offset + data.rater[n] - 1] = -1.0
        end
        if data.item[n] > 1
            matrix[n, item_offset + data.item[n] - 1] = -1.0
        end
    end
    return matrix
end

function _single_item_location_rank(data::FacetData)
    # Incidence rank is V-components; deleting the reference-rater column
    # removes that component's redundant column, preserving the rank.
    P, R = length(data.person_levels), length(data.rater_levels)
    parent = collect(1:(P+R))
    for n in 1:data.n
        _anchor_link_union!(parent, data.person[n], P+data.rater[n])
    end
    return P+R-count(i -> parent[i] == i, eachindex(parent))
end

function _validate_minimal_location_rank!(issues, data::FacetData)
    data.n == 0 && return nothing
    if length(data.item_levels) == 1
        ncol = length(data.person_levels)+length(data.rater_levels)-1
        r = _single_item_location_rank(data)
    else
        matrix = _minimal_location_matrix(data)
        ncol = size(matrix, 2)
        r = rank(matrix)
    end
    ncol == 0 && return nothing
    r == ncol && return nothing
    push!(issues, ValidationIssue(
        :rank_deficient_design,
        :error,
        "minimal reference-constrained location design has rank $r for $ncol location parameter(s)",
        context = Dict{Symbol,Any}(:rank => r, :parameters => ncol, :deficiency => ncol - r),
    ))
    return nothing
end

"""
    validate_design(data::FacetData; bias = Tuple{Symbol,Symbol}[], min_cell_count = 2)

Check whether the observed ratings have design problems that should be resolved
before fitting. Review category use, sparse or extreme response patterns,
links between persons, raters and items, and the ability to separate their effects.

Return a `ValidationReport`. `report.passed` is false when blocking errors
exist; warnings can remain when it is true. Each entry in `report.issues` has
a `severity`, `code` and explanatory `message`. A passing report is not evidence
of adequate sample size, correct model assumptions or MCMC convergence.

# Examples

After constructing `data` with the complete example in [`FacetData`](@ref):

```julia
report = validate_design(data)
report.passed
[(issue.severity, issue.message) for issue in report.issues]
```

Resolve errors and review warnings before calling [`mfrm_spec`](@ref).

# Extended help

Checks include category coverage, singleton and extreme response patterns,
person-rater-item connectedness, minimal location-design rank, item/category
support, and optional DFF/bias cell counts. `min_cell_count` controls sparse-cell
warnings; it is not a universal adequacy threshold or a way to repair missing links.
"""
function validate_design(data::FacetData; bias = Tuple{Symbol,Symbol}[], min_cell_count::Int = 2)
    min_cell_count >= 1 || throw(ArgumentError("min_cell_count must be positive"))
    issues = ValidationIssue[]

    category_counts = _category_counts(data)
    category_scale = _category_scale_contract(data)
    if data.n == 0
        push!(issues, ValidationIssue(:empty_data, :error,
            "at least one rating row is required"))
    elseif length(category_scale.observed_levels) < 2
        push!(issues, ValidationIssue(:single_observed_category, :error,
            "this fitting interface requires at least two observed score categories; single-category data are outside its current support"))
    end
    if data.n > 0
        skipped = category_scale.unobserved_interior_levels
        if !isempty(skipped)
            push!(issues, ValidationIssue(:unused_interior_category, :warning,
                "intended score scale contains unobserved interior value(s): $(skipped)",
                context = Dict{Symbol,Any}(:categories => data.category_levels, :skipped => skipped)))
        end
        unobserved_endpoints = category_scale.unobserved_endpoint_levels
        if !isempty(unobserved_endpoints)
            push!(issues, ValidationIssue(
                :unobserved_declared_endpoint,
                :warning,
                "declared score-scale endpoint(s) are unobserved: $(unobserved_endpoints)",
                context = Dict{Symbol,Any}(
                    :category_levels => data.category_levels,
                    :observed_categories => category_scale.observed_levels,
                    :unobserved_endpoints => unobserved_endpoints,
                ),
            ))
        end
    end
    _validate_item_category_support!(issues, data)
    _validate_ordinal_response_patterns!(issues, data)

    facet_counts = Dict{Symbol,Dict{Any,Int}}(
        :person => _counts(data.person, data.person_levels),
        :rater => _counts(data.rater, data.rater_levels),
        :item => _counts(data.item, data.item_levels),
    )
    for (role, idx) in data.optional
        facet_counts[role] = _counts(idx, data.optional_levels[role])
    end

    _validate_singletons!(issues, data, :person, data.person, data.person_levels)
    _validate_singletons!(issues, data, :rater, data.rater, data.rater_levels)
    _validate_singletons!(issues, data, :item, data.item, data.item_levels)
    for (role, idx) in data.optional
        role === :response_id && continue
        _validate_singletons!(issues, data, role, idx, data.optional_levels[role])
    end

    raw_components = _connected_components(data)
    components = [[_label_node(data, node) for node in component] for component in raw_components]
    if length(components) > 1
        push!(issues, ValidationIssue(:disconnected_design, :error,
            "person-rater-item graph has $(length(components)) connected components",
            context = Dict{Symbol,Any}(:component_sizes => length.(components))))
    end
    _validate_minimal_location_rank!(issues, data)

    dff_counts = Dict{Tuple{Symbol,Symbol},Dict{Tuple{Any,Any},Int}}()
    _validate_bias!(issues, dff_counts, data, bias, min_cell_count)

    passed = !any(issue -> issue.severity === :error, issues)
    return ValidationReport(
        data.n,
        passed,
        issues,
        category_counts,
        facet_counts,
        components,
        dff_counts,
        _data_signature(data),
        _validation_options_signature(bias, min_cell_count),
    )
end

function Base.show(io::IO, report::ValidationReport)
    n_error = count(issue -> issue.severity === :error, report.issues)
    n_warning = count(issue -> issue.severity === :warning, report.issues)
    print(io, "ValidationReport(", report.passed ? "passed" : "failed",
        ", ", n_error, " error(s), ", n_warning, " warning(s))")
end
