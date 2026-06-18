# facet_workflow.jl -- v0.1 long-format data, validation, and minimal spec layer

using LinearAlgebra

"""
    FacetData(table; person, rater, item, score, group = nothing, task = nothing,
              form = nothing, occasion = nothing, missing_policy = :error)

Encode long-format rating data into deterministic integer indexes for the
required person, rater, item, and ordinal score columns. Optional columns are
stored as indexed metadata and are not model terms in the v0.1 design scaffold.
"""
struct FacetData
    n::Int
    person::Vector{Int}
    rater::Vector{Int}
    item::Vector{Int}
    score::Vector{Int}
    category::Vector{Int}
    person_levels::Vector{Any}
    rater_levels::Vector{Any}
    item_levels::Vector{Any}
    category_levels::Vector{Int}
    optional::Dict{Symbol,Vector{Int}}
    optional_levels::Dict{Symbol,Vector{Any}}
    columns::NamedTuple
end

"""
    ValidationIssue

Machine-readable issue produced by `validate_design`, with `code`, `severity`,
a message, and optional context.
"""
struct ValidationIssue
    code::Symbol
    severity::Symbol
    message::String
    context::Dict{Symbol,Any}
end

ValidationIssue(code::Symbol, severity::Symbol, message::AbstractString; context = Dict{Symbol,Any}()) =
    ValidationIssue(code, severity, String(message), Dict{Symbol,Any}(context))

"""
    ValidationReport

Structured result returned by `validate_design`, including pass/fail status,
category and facet counts, graph components, item/category support warnings,
requested DFF cell counts, and internal signatures used to prevent stale report
reuse.
"""
struct ValidationReport
    n::Int
    passed::Bool
    issues::Vector{ValidationIssue}
    category_counts::Dict{Int,Int}
    facet_counts::Dict{Symbol,Dict{Any,Int}}
    components::Vector{Vector{Tuple{Symbol,Any}}}
    dff_counts::Dict{Tuple{Symbol,Symbol},Dict{Tuple{Any,Any},Int}}
    data_signature::UInt64
    options_signature::UInt64
end

"""
    FacetSpec

Minimal MFRM specification produced by `mfrm_spec`. This is a design scaffold,
not a fitted Bayesian model.
"""
struct FacetSpec
    data::FacetData
    thresholds::Symbol
    validation::ValidationReport
end

"""
    FacetDesign

Inspectable design object with deterministic parameter names and block ranges.
The current scaffold uses reference constraints for rater and item blocks and
sum-to-zero threshold steps.
"""
struct FacetDesign
    spec::FacetSpec
    parameter_names::Vector{String}
    blocks::Dict{Symbol,UnitRange{Int}}
    identification::Dict{Symbol,Symbol}
end

_facet_data(data::FacetData) = data
_facet_data(spec::FacetSpec) = spec.data
_facet_data(design::FacetDesign) = design.spec.data

_validation_report(::FacetData) = nothing
_validation_report(spec::FacetSpec) = spec.validation
_validation_report(design::FacetDesign) = design.spec.validation

function _is_column_lookup_error(err)
    err isa KeyError && return true
    err isa BoundsError && return true
    if err isa ArgumentError
        msg = lowercase(sprint(showerror, err))
        return occursin("not found", msg) ||
            occursin("no column", msg) ||
            occursin("invalid column", msg) ||
            occursin("does not contain", msg)
    end
    return false
end

function _is_missing_getindex_method(err, table, args)
    err isa MethodError || return false
    err.f === getindex || return false
    length(err.args) == length(args) + 1 || return false
    err.args[1] === table || return false
    return true
end

function _try_column_getindex(table, args...)
    try
        return collect(getindex(table, args...))
    catch err
        if err isa MethodError
            _is_missing_getindex_method(err, table, args) || rethrow()
            return nothing
        end
        _is_column_lookup_error(err) || rethrow()
        return nothing
    end
end

function _column(table, name::Symbol)
    if table isa AbstractDict
        haskey(table, name) && return collect(table[name])
        haskey(table, String(name)) && return collect(table[String(name)])
    end
    if hasproperty(table, name)
        return collect(getproperty(table, name))
    end
    col = _try_column_getindex(table, !, name)
    col === nothing || return col
    col = _try_column_getindex(table, :, name)
    col === nothing || return col
    col = _try_column_getindex(table, name)
    col === nothing || return col
    throw(ArgumentError("column :$name was not found"))
end

function _check_length!(n::Int, col, name::Symbol)
    length(col) == n || throw(ArgumentError("column :$name has length $(length(col)); expected $n"))
    return nothing
end

function _check_no_missing!(col, name::Symbol)
    bad = findall(ismissing, col)
    isempty(bad) || throw(ArgumentError("column :$name contains missing values at rows $(bad)"))
    return nothing
end

function _level_key(x)
    if x isa Real && !(x isa Bool)
        return ("Real", Float64(x), string(typeof(x)), string(x))
    end
    return (string(typeof(x)), Inf, string(typeof(x)), string(x))
end

function _stable_levels(col, name::Symbol)
    seen = Dict{Any,Bool}()
    levels = Any[]
    for x in col
        try
            if !haskey(seen, x)
                seen[x] = true
                push!(levels, x)
            end
        catch err
            throw(ArgumentError("column :$name contains an unhashable facet label: $(repr(x))"))
        end
    end
    sort!(levels; by = _level_key)
    return levels
end

function _encode_levels(col, name::Symbol)
    _check_no_missing!(col, name)
    levels = _stable_levels(col, name)
    index = Dict{Any,Int}(level => i for (i, level) in pairs(levels))
    return [index[x] for x in col], levels
end

function _score_to_int(x, name::Symbol)
    ismissing(x) && throw(ArgumentError("column :$name contains missing score values"))
    if x isa Integer && !(x isa Bool)
        return Int(x)
    elseif x isa AbstractFloat && isfinite(x) && isinteger(x)
        return Int(x)
    else
        throw(ArgumentError("column :$name must contain integer ordinal scores; found $(repr(x))"))
    end
end

function _encode_scores(col, name::Symbol)
    scores = [_score_to_int(x, name) for x in col]
    levels = isempty(scores) ? Int[] : collect(minimum(scores):maximum(scores))
    index = Dict{Int,Int}(level => i for (i, level) in pairs(levels))
    return scores, [index[x] for x in scores], levels
end

function FacetData(table;
        person::Symbol,
        rater::Symbol,
        item::Symbol,
        score::Symbol,
        group::Union{Nothing,Symbol} = nothing,
        task::Union{Nothing,Symbol} = nothing,
        form::Union{Nothing,Symbol} = nothing,
        occasion::Union{Nothing,Symbol} = nothing,
        missing_policy::Symbol = :error)
    missing_policy == :error ||
        throw(ArgumentError("only missing_policy = :error is currently supported"))

    person_col = _column(table, person)
    n = length(person_col)
    rater_col = _column(table, rater)
    item_col = _column(table, item)
    score_col = _column(table, score)
    _check_length!(n, rater_col, rater)
    _check_length!(n, item_col, item)
    _check_length!(n, score_col, score)

    person_index, person_levels = _encode_levels(person_col, person)
    rater_index, rater_levels = _encode_levels(rater_col, rater)
    item_index, item_levels = _encode_levels(item_col, item)
    scores, category_index, category_levels = _encode_scores(score_col, score)

    optional = Dict{Symbol,Vector{Int}}()
    optional_levels = Dict{Symbol,Vector{Any}}()
    optional_columns = Dict{Symbol,Symbol}()
    for (role, column) in ((:group, group), (:task, task), (:form, form), (:occasion, occasion))
        column === nothing && continue
        col = _column(table, column)
        _check_length!(n, col, column)
        idx, levels = _encode_levels(col, column)
        optional[role] = idx
        optional_levels[role] = levels
        optional_columns[role] = column
    end

    columns = (;
        person,
        rater,
        item,
        score,
        optional = optional_columns,
        missing_policy,
    )
    return FacetData(
        n,
        person_index,
        rater_index,
        item_index,
        scores,
        category_index,
        person_levels,
        rater_levels,
        item_levels,
        category_levels,
        optional,
        optional_levels,
        columns,
    )
end

Base.length(data::FacetData) = data.n

function Base.show(io::IO, data::FacetData)
    print(io, "FacetData(", data.n, " ratings, ",
        length(data.person_levels), " persons, ",
        length(data.rater_levels), " raters, ",
        length(data.item_levels), " items, ",
        length(data.category_levels), " categories)")
end

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
        push!(seen, node)
        component = Tuple{Symbol,Int}[]
        while !isempty(queue)
            current = popfirst!(queue)
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

function _validate_minimal_location_rank!(issues, data::FacetData)
    data.n == 0 && return nothing
    matrix = _minimal_location_matrix(data)
    ncol = size(matrix, 2)
    ncol == 0 && return nothing
    r = rank(matrix)
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

Run pre-fit validation checks for category use, singleton facet levels,
person-rater-item connectedness, minimal location-design rank, item/category
support, and optional DFF/bias cell counts.
"""
function validate_design(data::FacetData; bias = Tuple{Symbol,Symbol}[], min_cell_count::Int = 2)
    min_cell_count >= 1 || throw(ArgumentError("min_cell_count must be positive"))
    issues = ValidationIssue[]

    category_counts = _category_counts(data)
    if data.n == 0
        push!(issues, ValidationIssue(:empty_data, :error,
            "at least one rating row is required"))
    elseif length(data.category_levels) < 2
        push!(issues, ValidationIssue(:single_observed_category, :error,
            "at least two score categories are required to fit an ordered-response model"))
    end
    if data.n > 0
        skipped = sort([category for (category, n) in category_counts if n == 0])
        if !isempty(skipped)
            push!(issues, ValidationIssue(:unused_interior_category, :warning,
                "observed score categories skip interior value(s): $(skipped)",
                context = Dict{Symbol,Any}(:categories => data.category_levels, :skipped => skipped)))
        end
    end
    _validate_item_category_support!(issues, data)

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

function _median_count(values::Vector{Int})
    isempty(values) && return 0.0
    sorted = sort(values)
    n = length(sorted)
    mid = n ÷ 2
    return isodd(n) ? Float64(sorted[mid + 1]) : (sorted[mid] + sorted[mid + 1]) / 2
end

function _coverage_roles(data::FacetData)
    roles = Any[
        (:person, data.person, data.person_levels),
        (:rater, data.rater, data.rater_levels),
        (:item, data.item, data.item_levels),
    ]
    for role in sort(collect(keys(data.optional)); by = string)
        push!(roles, (role, data.optional[role], data.optional_levels[role]))
    end
    return roles
end

function _validation_summary(report)
    report === nothing && return nothing
    n_error = count(issue -> issue.severity === :error, report.issues)
    n_warning = count(issue -> issue.severity === :warning, report.issues)
    return (passed = report.passed, n_errors = n_error, n_warnings = n_warning)
end

"""
    coverage_summary(data_or_spec)

Return fit-independent coverage summaries for long-format rating data. The
result is a `NamedTuple` containing rating counts, category counts, long-form
facet-level counts, compact facet summaries, and validation status when a
`FacetSpec` or `FacetDesign` is supplied.
"""
function coverage_summary(data_or_spec)
    data = _facet_data(data_or_spec)
    facet_counts = NamedTuple[]
    facet_summary = NamedTuple[]
    for (facet, index, levels) in _coverage_roles(data)
        counts = _counts(index, levels)
        values = [counts[level] for level in levels]
        for level in levels
            count = counts[level]
            push!(facet_counts, (;
                facet,
                level,
                count,
                proportion = data.n == 0 ? 0.0 : count / data.n,
            ))
        end
        push!(facet_summary, (;
            facet,
            n_levels = length(levels),
            min_count = isempty(values) ? 0 : minimum(values),
            median_count = _median_count(values),
            max_count = isempty(values) ? 0 : maximum(values),
            singleton_count = count(==(1), values),
            total_count = sum(values),
        ))
    end

    category_counts = NamedTuple[]
    category_count_map = _category_counts(data)
    for category in data.category_levels
        count = category_count_map[category]
        push!(category_counts, (;
            category,
            count,
            proportion = data.n == 0 ? 0.0 : count / data.n,
        ))
    end

    return (;
        n_ratings = data.n,
        n_persons = length(data.person_levels),
        n_raters = length(data.rater_levels),
        n_items = length(data.item_levels),
        n_categories = length(data.category_levels),
        facet_summary,
        facet_counts,
        category_counts,
        validation = _validation_summary(_validation_report(data_or_spec)),
    )
end

"""
    coverage_matrix(data_or_spec; rows = :rater, columns = :person)

Return a facet-by-facet rating-count matrix for heat maps and design coverage
checks. `rows` and `columns` may be required facets (`:person`, `:rater`,
`:item`) or optional metadata roles present in `FacetData`, such as `:group`,
`:task`, `:form`, or `:occasion`.
"""
function coverage_matrix(data_or_spec; rows::Symbol = :rater, columns::Symbol = :person)
    data = _facet_data(data_or_spec)
    row_facet = _facet(data, rows)
    row_facet === nothing &&
        throw(ArgumentError("rows = :$rows is not present in FacetData"))
    column_facet = _facet(data, columns)
    column_facet === nothing &&
        throw(ArgumentError("columns = :$columns is not present in FacetData"))

    row_index, row_levels = row_facet
    column_index, column_levels = column_facet
    counts = zeros(Int, length(row_levels), length(column_levels))
    for n in 1:data.n
        counts[row_index[n], column_index[n]] += 1
    end

    return (;
        row_facet = rows,
        column_facet = columns,
        row_levels = copy(row_levels),
        column_levels = copy(column_levels),
        counts,
    )
end

function _overlap_unit(data::FacetData, row::Int, unit::Symbol)
    unit === :person && return (data.person[row],)
    unit === :item && return (data.item[row],)
    unit === :person_item && return (data.person[row], data.item[row])
    if unit === :task
        haskey(data.optional, :task) ||
            throw(ArgumentError("unit = :task requires FacetData(...; task = ...)"))
        return (data.optional[:task][row],)
    end
    if unit === :person_task
        haskey(data.optional, :task) ||
            throw(ArgumentError("unit = :person_task requires FacetData(...; task = ...)"))
        return (data.person[row], data.optional[:task][row])
    end
    throw(ArgumentError("unit must be one of :person, :item, :person_item, :task, or :person_task"))
end

"""
    rater_overlap(data_or_spec; unit = :person_item)

Return pairwise rater-overlap data for coverage and linking plots. `unit`
controls what counts as a shared rated unit and may be `:person`,
`:item`, `:person_item`, `:task`, or `:person_task`. Task-based units require
`FacetData(...; task = ...)`.
"""
function rater_overlap(data_or_spec; unit::Symbol = :person_item)
    data = _facet_data(data_or_spec)
    unit_sets = [Set{Any}() for _ in data.rater_levels]
    for row in 1:data.n
        push!(unit_sets[data.rater[row]], _overlap_unit(data, row, unit))
    end

    rows = NamedTuple[]
    for a in 1:(length(data.rater_levels) - 1), b in (a + 1):length(data.rater_levels)
        shared = intersect(unit_sets[a], unit_sets[b])
        all_units = union(unit_sets[a], unit_sets[b])
        push!(rows, (;
            rater_a = data.rater_levels[a],
            rater_b = data.rater_levels[b],
            unit,
            n_units_a = length(unit_sets[a]),
            n_units_b = length(unit_sets[b]),
            shared_units = length(shared),
            union_units = length(all_units),
            jaccard = isempty(all_units) ? 0.0 : length(shared) / length(all_units),
        ))
    end
    return rows
end

"""
    mfrm_spec(data::FacetData; thresholds = :partial_credit, bias = Tuple{Symbol,Symbol}[],
              min_cell_count = 2, validation_report = nothing)

Construct a minimal MFRM specification after validation errors are resolved.
Pass `bias` or an existing `validation_report` to preserve DFF validation
evidence in the spec.
"""
function mfrm_spec(data::FacetData;
        thresholds::Symbol = :partial_credit,
        bias = Tuple{Symbol,Symbol}[],
        min_cell_count::Int = 2,
        validation_report::Union{Nothing,ValidationReport} = nothing)
    thresholds in (:rating_scale, :partial_credit) ||
        throw(ArgumentError("thresholds must be :rating_scale or :partial_credit"))
    report = validation_report === nothing ?
        validate_design(data; bias, min_cell_count) :
        validation_report
    report.n == data.n ||
        throw(ArgumentError("validation_report has n = $(report.n); expected $(data.n)"))
    report.data_signature == _data_signature(data) ||
        throw(ArgumentError("validation_report was produced for different FacetData"))
    if validation_report !== nothing && !_is_default_validation_request(bias, min_cell_count)
        report.options_signature == _validation_options_signature(bias, min_cell_count) ||
            throw(ArgumentError("validation_report was produced with different validation options"))
    end
    if !report.passed
        codes = [issue.code for issue in report.issues if issue.severity === :error]
        throw(ArgumentError("cannot construct MFRM spec until validation errors are resolved: $(codes)"))
    end
    return FacetSpec(data, thresholds, report)
end

function Base.show(io::IO, spec::FacetSpec)
    print(io, "FacetSpec(thresholds = :", spec.thresholds, ", ", spec.data, ")")
end

function _push_block!(names::Vector{String}, blocks::Dict{Symbol,UnitRange{Int}}, block::Symbol, labels, prefix::String)
    start = length(names) + 1
    for label in labels
        push!(names, prefix * "[" * string(label) * "]")
    end
    blocks[block] = start:length(names)
    return nothing
end

"""
    getdesign(spec::FacetSpec)

Return the current minimal additive RSM/PCM design scaffold. The first rater
and first item levels are fixed to zero as reference levels. Rating-scale and
partial-credit threshold steps are represented with a sum-to-zero constraint.
"""
function getdesign(spec::FacetSpec)
    data = spec.data
    names = String[]
    blocks = Dict{Symbol,UnitRange{Int}}()
    _push_block!(names, blocks, :person, data.person_levels, "person")
    _push_block!(names, blocks, :rater, data.rater_levels[2:end], "rater")
    _push_block!(names, blocks, :item, data.item_levels[2:end], "item")

    start = length(names) + 1
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
    blocks[:thresholds] = start:length(names)

    identification = Dict{Symbol,Symbol}(
        :person => :free,
        :rater => :reference_first,
        :item => :reference_first,
        :thresholds => :sum_to_zero,
    )
    return FacetDesign(spec, names, blocks, identification)
end

function Base.show(io::IO, design::FacetDesign)
    print(io, "FacetDesign(", length(design.parameter_names), " parameters, thresholds = :",
        design.spec.thresholds, ")")
end

function _logsumexp(vals::Vector{Float64})
    m = maximum(vals)
    return m + log(sum(exp(v - m) for v in vals))
end

function _reference_value(params::AbstractVector, block::UnitRange{Int}, index::Int)
    index == 1 && return 0.0
    return Float64(params[block[index - 1]])
end

function _threshold_step(design::FacetDesign, params::AbstractVector, item::Int, step::Int)
    step_range = design.blocks[:thresholds]
    kminus1 = length(design.spec.data.category_levels) - 1
    free_steps = max(kminus1 - 1, 0)
    if free_steps == 0
        return 0.0
    end
    if design.spec.thresholds === :rating_scale
        if step <= free_steps
            return Float64(params[step_range[step]])
        end
        return -sum(Float64(params[step_range[s]]) for s in 1:free_steps)
    else
        offset = (item - 1) * free_steps
        if step <= free_steps
            return Float64(params[step_range[offset + step]])
        end
        return -sum(Float64(params[step_range[offset + s]]) for s in 1:free_steps)
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
    free_steps = max(nsteps - 1, 0)
    rows = NamedTuple[]
    step_range = design.blocks[:thresholds]

    function push_step!(item_index, item_label, step)
        is_free = step <= free_steps
        parameter_index = is_free ?
            (design.spec.thresholds === :rating_scale ?
                step_range[step] :
                step_range[(item_index - 1) * free_steps + step]) :
            missing
        parameter_name = is_free ? design.parameter_names[parameter_index] : missing
        status = is_free ? :free : (nsteps == 1 ? :fixed_zero : :sum_to_zero_derived)
        value = params === nothing ? missing : _threshold_step(design, params, item_index, step)
        push!(rows, (;
            thresholds = design.spec.thresholds,
            item = item_label,
            step,
            from_category = data.category_levels[step],
            to_category = data.category_levels[step + 1],
            parameter_index,
            parameter_name,
            status,
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
    category <= 1 && return 0.0
    return sum(_threshold_step(design, params, item, step) for step in 1:(category - 1))
end

"""
    pointwise_loglikelihood(design::FacetDesign, params)

Evaluate the minimal additive RSM/PCM pointwise log likelihood for the
identified parameter vector returned by `getdesign`. This helper is for design
validation and does not apply Bayesian priors.
"""
function pointwise_loglikelihood(design::FacetDesign, params::AbstractVector)
    length(params) == length(design.parameter_names) ||
        throw(ArgumentError("parameter vector has length $(length(params)); expected $(length(design.parameter_names))"))
    data = design.spec.data
    out = Vector{Float64}(undef, data.n)
    person_block = design.blocks[:person]
    rater_block = design.blocks[:rater]
    item_block = design.blocks[:item]
    K = length(data.category_levels)
    etas = zeros(Float64, K)
    for n in 1:data.n
        person_value = Float64(params[person_block[data.person[n]]])
        rater_value = _reference_value(params, rater_block, data.rater[n])
        item_value = _reference_value(params, item_block, data.item[n])
        location = person_value - rater_value - item_value
        for category in 1:K
            etas[category] = (category - 1) * location -
                _step_sum(design, params, data.item[n], category)
        end
        out[n] = etas[data.category[n]] - _logsumexp(etas)
    end
    return out
end
